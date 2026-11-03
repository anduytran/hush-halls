--!strict
-- Robux purchases, on the server. Game code says what each purchase gives:
--   Monetization.onPass("VIP", function(player) ... end)            -- runs when an owner joins, and right after buying
--   Monetization.onProduct("Coins100", function(player) ... return true end)  -- return true once it's given
-- A product's receipt is reserved in a DataStore before its handler runs and marked done after,
-- so a purchase Roblox retries is never given twice.
-- Sprint-8 fix: each attempt writes a "pending" marker with its own token, and only that attempt ever replaces
-- it (with "done" or "released"). There is no stale-marker takeover any more, so two grants can never overlap.
-- The handler runs in its own task. While it runs, the receipt answers NotProcessedYet. When it finishes, even
-- late, its result is written over its own marker, retrying with backoff until the write succeeds:
--   true          -> "done": Roblox's retry gets PurchaseGranted and nothing more is given
--   false / error -> "released": Roblox's retry can try the grant again
-- Handlers SHOULD NOT YIELD (no task.wait, no Async calls, no WaitForChild): give the product and return.
-- Why: a yielding handler is never cancelled (that could leave a half-done grant), so the player waits for
-- it, and if the server shuts down while it's yielding, its marker is never replaced. With no takeover, that
-- purchase then answers NotProcessedYet on every retry and is never given.
-- The DataStore is opened on first use, so an unpublished Studio place can still require this module.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)

local Monetization = {}

-- Sprint-8 fix: PENDING_TIMEOUT and the stale-marker takeover are gone. Writing a result over our own marker
-- retries after this many seconds, doubling each time up to RETRY_MAX.
local RETRY_FIRST = 0.5
local RETRY_MAX = 30

type PassHandler = (player: Player) -> ()
type ProductHandler = (player: Player) -> boolean
type Receipt = { PlayerId: number, PurchaseId: string, ProductId: number }

local passHandlers: { [string]: PassHandler } = {}
local productHandlers: { [string]: ProductHandler } = {}
local owned: { [Player]: { [string]: boolean } } = {}
local history: DataStore? = nil
-- Receipts being handled right now, so a duplicate ProcessReceipt call can't grant twice.
local processing: { [string]: boolean } = {}

local function getHistory(): DataStore?
	if history then
		return history
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("PurchaseHistory")
	end)
	if not ok then
		warn(`[Monetization] purchase history unavailable: {store}`)
		return nil
	end
	history = store
	return store
end

local function keyFor(list: { [string]: Products.Item }, id: number): string?
	if id == 0 then
		return nil
	end
	for key, item in list do
		if item.id == id then
			return key
		end
	end
	return nil
end

function Monetization.ownsPass(player: Player, key: string): boolean
	local cache = owned[player]
	if cache and cache[key] ~= nil then
		return cache[key]
	end
	local pass = Products.Passes[key]
	if not pass or pass.id == 0 then
		return false
	end
	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
	end)
	if not ok then
		return false
	end
	local entry = owned[player] or {}
	owned[player] = entry
	entry[key] = has == true
	return has == true
end

function Monetization.onPass(key: string, handler: PassHandler)
	passHandlers[key] = handler
	for _, player in Players:GetPlayers() do
		if Monetization.ownsPass(player, key) then
			task.spawn(handler, player)
		end
	end
end

function Monetization.onProduct(key: string, handler: ProductHandler)
	productHandlers[key] = handler
end

Players.PlayerAdded:Connect(function(player)
	for key, handler in passHandlers do
		if Monetization.ownsPass(player, key) then
			task.spawn(handler, player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	owned[player] = nil
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	local key = keyFor(Products.Passes, passId)
	if not key then
		return
	end
	local entry = owned[player] or {}
	owned[player] = entry
	entry[key] = true
	local handler = passHandlers[key]
	if handler then
		task.spawn(handler, player)
	end
end)

local function isDone(value: any): boolean
	-- `true` is how receipts were recorded before sprint 4.
	return value == true or (type(value) == "table" and value.status == "done")
end

-- Sprint-8 fix: any pending marker means another attempt owns the receipt, however old it is. Only that
-- attempt replaces it, so there's no age check and no takeover.
local function isPending(value: any): boolean
	return type(value) == "table" and value.status == "pending"
end

local function isOurs(value: any, token: string): boolean
	return type(value) == "table" and value.token == token
end

-- Sprint-8 fix: one UpdateAsync that writes `final` only over the marker holding our token.
-- Returns (ok, wasOurs or error).
local function writeOverOurs(store: DataStore, receiptKey: string, token: string, final: any): (boolean, any)
	local wasOurs = false
	local ok, err = pcall(function()
		store:UpdateAsync(receiptKey, function(value)
			wasOurs = isOurs(value, token)
			if not wasOurs then
				return nil -- not our marker: leave it alone
			end
			return final
		end)
	end)
	return ok, if ok then wasOurs else err
end

-- Sprint-8 fix: writes `final` over our own marker, retrying with task.wait backoff until the write succeeds.
-- Yields, so it runs from the handler's task or a task of its own, never on ProcessReceipt's own path.
local function keepWriting(store: DataStore, receiptKey: string, token: string, final: any, purchaseId: string)
	local delay = RETRY_FIRST
	while true do
		local ok, wasOurs = writeOverOurs(store, receiptKey, token, final)
		if ok then
			if not wasOurs then
				warn(`[Monetization] purchase {purchaseId} doesn't hold our marker; wrote nothing`)
			end
			return
		end
		warn(`[Monetization] couldn't record purchase {purchaseId} as {final.status}, retrying in {delay} s: {wasOurs}`)
		task.wait(delay)
		delay = math.min(delay * 2, RETRY_MAX)
	end
end

-- Sprint-8 fix: runs the grant in its own task (task.spawn) and never cancels it. Returns (true, ok, given) if
-- it finished before task.spawn returned, or (false) if it's still running. A grant that's still running
-- calls `onLate(ok, given)` from its own task when it finishes.
local function runGrant(
	grant: ProductHandler,
	buyer: Player,
	onLate: (ok: boolean, given: any) -> ()
): (boolean, boolean, any)
	local waiting = true
	local finished = false
	local resultOk, resultGiven = false, nil
	task.spawn(function()
		local ok, given = pcall(grant, buyer)
		finished = true
		if waiting then
			resultOk, resultGiven = ok, given
		else
			onLate(ok, given)
		end
	end)
	waiting = false
	if finished then
		return true, resultOk, resultGiven
	end
	return false, false, nil
end

-- Sprint-4 fix: UpdateAsync only reserves the receipt key with a "pending" marker. The grant runs after it
-- returns (so a retried UpdateAsync callback can never grant twice), then a second UpdateAsync records it.
-- Sprint-5 fix: each attempt writes its marker with its own unique token, and only grants if the stored value
-- after the reserve is that marker.
-- Sprint-8 fix: a pending marker is only ever replaced by the attempt that owns its token: with "done" after a
-- grant, or "released" after a refused or failed one (a released receipt can be reserved again).
local function processReceipt(receipt: Receipt, store: DataStore, grant: ProductHandler, buyer: Player)
	local receiptKey = `{receipt.PlayerId}_{receipt.PurchaseId}`
	local purchaseId = receipt.PurchaseId
	local token = HttpService:GenerateGUID(false)
	local function marker(status: string)
		return { status = status, at = os.time(), token = token }
	end
	local status: "done" | "busy" | "reserved" = "busy"
	local reserveOk, reserveResult = pcall(function()
		return store:UpdateAsync(receiptKey, function(value)
			-- May run more than once: it only sets `status` and returns the marker, nothing else.
			if isDone(value) then
				status = "done"
				return nil
			end
			if isPending(value) then
				status = "busy" -- another attempt owns it (its grant may still be running)
				return nil
			end
			status = "reserved"
			return marker("pending")
		end)
	end)
	if not reserveOk then
		warn(`[Monetization] couldn't reserve purchase {purchaseId}: {reserveResult}`)
		-- Sprint-8 fix: the write may have landed before the error. Nothing was granted, so release our marker
		-- if it's there: with no takeover, it would otherwise block the purchase for good.
		task.spawn(keepWriting, store, receiptKey, token, marker("released"), purchaseId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "done" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Sprint-5 fix: grant only once the store holds our token, not just because our callback said "reserved".
	if status == "busy" or not isOurs(reserveResult, token) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Sprint-8 fix: a grant still running when task.spawn returns answers NotProcessedYet now. Its result is
	-- written over our own marker when it finishes, retrying until the write succeeds.
	local finished, grantOk, given = runGrant(grant, buyer, function(lateOk, lateGiven)
		if lateOk and lateGiven == true then
			keepWriting(store, receiptKey, token, marker("done"), purchaseId)
			return
		end
		if not lateOk then
			warn(`[Monetization] yielding handler failed late for purchase {purchaseId}: {lateGiven}`)
		end
		keepWriting(store, receiptKey, token, marker("released"), purchaseId)
	end)
	if not finished then
		warn(
			`[Monetization] handler for purchase {purchaseId} yielded; product handlers should not yield.`
				.. " Answering NotProcessedYet until it finishes."
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not grantOk or given ~= true then
		if not grantOk then
			warn(`[Monetization] handler failed for purchase {purchaseId}: {given}`)
		end
		-- Sprint-8 fix: release our own marker with UpdateAsync (not RemoveAsync). If that fails, keep retrying
		-- in the background; until it lands the receipt stays busy, so nothing is granted meanwhile.
		local released = marker("released")
		local releaseOk, releaseErr = writeOverOurs(store, receiptKey, token, released)
		if not releaseOk then
			warn(`[Monetization] couldn't release purchase {purchaseId}, retrying: {releaseErr}`)
			task.spawn(keepWriting, store, receiptKey, token, released, purchaseId)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local done = marker("done")
	local doneOk, wasOurs = writeOverOurs(store, receiptKey, token, done)
	if not doneOk then
		-- It was given, so tell Roblox it's done rather than risk giving it again, and keep trying to record it.
		warn(`[Monetization] granted purchase {purchaseId} but couldn't record it yet, retrying: {wasOurs}`)
		task.spawn(keepWriting, store, receiptKey, token, done, purchaseId)
	elseif not wasOurs then
		-- Sprint-8 fix: nothing else replaces our marker, so the store was changed by hand. It was given anyway.
		warn(`[Monetization] purchase {purchaseId} was granted but no longer holds our marker`)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- TEST-ONLY: lets specs run a receipt against a stand-in DataStore (UpdateAsync) and handler, and read the
-- first retry delay.
Monetization._processReceipt = processReceipt
Monetization._RETRY_FIRST = RETRY_FIRST

MarketplaceService.ProcessReceipt = function(receipt)
	local key = keyFor(Products.Products, receipt.ProductId)
	local handler = if key then productHandlers[key] else nil
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local store = getHistory()
	local processingKey = `{receipt.PlayerId}_{receipt.PurchaseId}`
	if not handler or not player or not store or processing[processingKey] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	processing[processingKey] = true
	local ok, decision = pcall(processReceipt, receipt, store, handler, player)
	processing[processingKey] = nil
	if not ok then
		warn(`[Monetization] couldn't process purchase {receipt.PurchaseId}: {decision}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
end

return Monetization

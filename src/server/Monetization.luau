--!strict
-- Robux purchases, on the server. Game code says what each purchase gives:
--   Monetization.onPass("VIP", function(player) ... end)            -- runs when an owner joins, and right after buying
--   Monetization.onProduct("Coins100", function(player) ... return true end)  -- return true once it's given
-- A product's receipt is reserved in a DataStore before its handler runs and marked done after,
-- so a purchase Roblox retries is never given twice. The handler runs outside UpdateAsync and MUST NOT YIELD
-- (no task.wait, no Async calls, no WaitForChild): it has to give the product and return straight away.
-- Sprint-7 fix: a handler that yields anyway is not stopped (stopping it could leave a half-done grant). It's
-- logged, the receipt answers NotProcessedYet and keeps its pending marker, and if the handler finishes later
-- the receipt is marked done then, so Roblox's retry grants nothing more.
-- The DataStore is opened on first use, so an unpublished Studio place can still require this module.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)

local Monetization = {}

-- A "pending" receipt marker older than this (seconds) is from an attempt that died mid-grant
-- (its server shut down, taking the unsaved grant with it), so a retry may take it over.
-- Sprint-6 fix: raised from 120 s. The grant doesn't yield, so a live attempt only holds the marker for
-- two DataStore calls.
-- Sprint-7 fix: lowered to 180 s, still far past two DataStore calls, so a purchase whose server died
-- mid-grant is retried after 3 minutes instead of 10.
local PENDING_TIMEOUT = 180

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

local function isFreshPending(value: any, now: number): boolean
	return type(value) == "table"
		and value.status == "pending"
		and type(value.at) == "number"
		and now - value.at < PENDING_TIMEOUT
end

local function isOurs(value: any, token: string): boolean
	return type(value) == "table" and value.token == token
end

-- Sprint-7 fix: runs the grant synchronously in its own coroutine and never cancels it. Returns
-- (true, ok, given) if it finished without yielding, or (false) if it yielded. A yielded grant keeps running
-- when the engine resumes it, and `onLate(ok, given)` is called once it finishes.
local function runGrant(
	grant: ProductHandler,
	buyer: Player,
	onLate: (ok: boolean, given: any) -> ()
): (boolean, boolean, any)
	local yielded = false
	local resultOk, resultGiven = false, nil
	local thread = coroutine.create(function()
		local ok, given = pcall(grant, buyer)
		if yielded then
			onLate(ok, given)
		else
			resultOk, resultGiven = ok, given
		end
	end)
	coroutine.resume(thread)
	if coroutine.status(thread) ~= "dead" then
		yielded = true
		return false, false, nil
	end
	return true, resultOk, resultGiven
end

-- Sprint-4 fix: UpdateAsync only reserves the receipt key with a "pending" marker. The grant runs after it
-- returns (so a retried UpdateAsync callback can never grant twice), then a second UpdateAsync marks it done.
-- A failed grant removes the marker so Roblox's retry can try again.
-- Sprint-5 fix: each attempt writes its marker with its own unique token, and only grants if the stored value
-- after the reserve is that marker. Marking done only replaces our own marker: if another attempt took the
-- receipt over meanwhile (ours went stale), its marker is left alone and we return NotProcessedYet.
-- Sprint-6 fix: the grant runs synchronously, straight after the reserve's fresh token check, with no yield in
-- between. Our marker could only go stale (180 s, sprint-7 fix) while a DataStore call itself stalls,
-- so a takeover can't overlap a grant that's still running (unless a handler breaks the no-yield rule).
local function processReceipt(receipt: Receipt, store: DataStore, grant: ProductHandler, buyer: Player)
	local receiptKey = `{receipt.PlayerId}_{receipt.PurchaseId}`
	local now = os.time()
	local token = HttpService:GenerateGUID(false)
	local status: "done" | "busy" | "reserved" = "busy"
	local reserveOk, reserveResult = pcall(function()
		return store:UpdateAsync(receiptKey, function(value)
			-- May run more than once: it only sets `status` and returns the marker, nothing else.
			if isDone(value) then
				status = "done"
				return nil
			end
			if isFreshPending(value, now) then
				status = "busy" -- another attempt is granting it right now
				return nil
			end
			status = "reserved"
			return { status = "pending", at = now, token = token }
		end)
	end)
	if not reserveOk then
		warn(`[Monetization] couldn't reserve purchase {receipt.PurchaseId}: {reserveResult}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "done" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Sprint-5 fix: grant only once the store holds our token, not just because our callback said "reserved".
	-- Sprint-6 fix: the token is lost (another attempt's marker came back) → NotProcessedYet, nothing granted.
	if status == "busy" or not isOurs(reserveResult, token) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Sprint-5 fix: only our own marker is replaced with "done". Returns (ok, marked or error).
	local function markDone(): (boolean, any)
		local marked = false
		local ok, err = pcall(function()
			store:UpdateAsync(receiptKey, function(value)
				marked = isOurs(value, token)
				if not marked then
					return nil -- another attempt took it over: leave its marker for it to finish
				end
				return { status = "done", at = now, token = token }
			end)
		end)
		return ok, if ok then marked else err
	end

	-- Sprint-6 fix: nothing yields between the token check above and this grant.
	-- Sprint-7 fix: a grant that yields isn't cancelled. Our marker stays (a retry within PENDING_TIMEOUT sees it
	-- busy) and is marked done when the grant finishes; if the grant fails late, the marker is left to go stale.
	local finished, grantOk, given = runGrant(grant, buyer, function(lateOk, lateGiven)
		if not lateOk or lateGiven ~= true then
			warn(`[Monetization] yielding handler failed late for purchase {receipt.PurchaseId}: {lateGiven}`)
			return
		end
		local lateDoneOk, lateMarked = markDone()
		if not lateDoneOk or not lateMarked then
			warn(`[Monetization] yielding handler granted purchase {receipt.PurchaseId} late; couldn't record it`)
		end
	end)
	if not finished then
		warn(
			`[Monetization] handler for purchase {receipt.PurchaseId} yielded; product handlers must not yield.`
				.. " Answering NotProcessedYet until it finishes."
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grantOk or given ~= true then
		if not grantOk then
			warn(`[Monetization] handler failed for purchase {receipt.PurchaseId}: {given}`)
		end
		-- If this fails too, the marker goes stale after PENDING_TIMEOUT and a later retry can take it over.
		local clearOk, clearErr = pcall(function()
			store:RemoveAsync(receiptKey)
		end)
		if not clearOk then
			warn(`[Monetization] couldn't clear pending purchase {receipt.PurchaseId}: {clearErr}`)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local doneOk, marked = markDone()
	if not doneOk then
		-- It was given, so tell Roblox it's done rather than risk giving it again on retry.
		warn(`[Monetization] granted purchase {receipt.PurchaseId} but couldn't record it: {marked}`)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not marked then
		-- The attempt that took over records the receipt; Roblox's retry then sees it done and grants nothing more.
		warn(`[Monetization] purchase {receipt.PurchaseId} was taken over by another attempt while granting`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- TEST-ONLY: lets specs run a receipt against a stand-in DataStore (UpdateAsync/RemoveAsync) and handler,
-- and read the stale-takeover window.
Monetization._processReceipt = processReceipt
Monetization._PENDING_TIMEOUT = PENDING_TIMEOUT

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

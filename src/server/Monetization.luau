--!strict
-- Robux purchases, on the server. Game code says what each purchase gives:
--   Monetization.onPass("VIP", function(player) ... end)            -- runs when an owner joins, and right after buying
--   Monetization.onProduct("Coins100", function(player) ... return true end)  -- return true once it's given
-- A product's receipt is reserved in a DataStore before its handler runs and marked done after,
-- so a purchase Roblox retries is never given twice. The handler runs outside UpdateAsync and may yield.
-- The DataStore is opened on first use, so an unpublished Studio place can still require this module.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)

local Monetization = {}

-- A "pending" receipt marker older than this (seconds) is from an attempt that died mid-grant
-- (its server shut down, taking the unsaved grant with it), so a retry may take it over.
local PENDING_TIMEOUT = 120

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

-- Sprint-4 fix: UpdateAsync only reserves the receipt key with a "pending" marker. The grant runs after it
-- returns (so a retried UpdateAsync callback can never grant twice), then a second UpdateAsync marks it done.
-- A failed grant removes the marker so Roblox's retry can try again.
local function processReceipt(receipt: Receipt, store: DataStore, grant: ProductHandler, buyer: Player)
	local receiptKey = `{receipt.PlayerId}_{receipt.PurchaseId}`
	local now = os.time()
	local status: "done" | "busy" | "reserved" = "busy"
	local reserveOk, reserveErr = pcall(function()
		store:UpdateAsync(receiptKey, function(value)
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
			return { status = "pending", at = now }
		end)
	end)
	if not reserveOk then
		warn(`[Monetization] couldn't reserve purchase {receipt.PurchaseId}: {reserveErr}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "done" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if status == "busy" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local grantOk, given = pcall(grant, buyer)
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

	local doneOk, doneErr = pcall(function()
		store:UpdateAsync(receiptKey, function()
			return { status = "done", at = now }
		end)
	end)
	if not doneOk then
		-- It was given, so tell Roblox it's done rather than risk giving it again on retry.
		warn(`[Monetization] granted purchase {receipt.PurchaseId} but couldn't record it: {doneErr}`)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- TEST-ONLY: lets specs run a receipt against a stand-in DataStore (UpdateAsync/RemoveAsync) and handler.
Monetization._processReceipt = processReceipt

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

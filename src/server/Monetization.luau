--!strict
-- Robux purchases, on the server. Game code says what each purchase gives:
--   Monetization.onPass("VIP", function(player) ... end)            -- runs when an owner joins, and right after buying
--   Monetization.onProduct("Coins100", function(player) ... return true end)  -- return true once it's given
-- A product handler runs inside a DataStore UpdateAsync callback, so it must not yield.
-- A product's receipt is recorded, so a purchase Roblox retries is never given twice.
-- The DataStore is opened on first use, so an unpublished Studio place can still require this module.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)

local Monetization = {}

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

-- Sprint-3 fix: the check, the grant and the record happen in one UpdateAsync on the receipt key,
-- so nothing can record or grant the receipt between our check and our write.
local function processReceipt(receipt: Receipt, store: DataStore, grant: ProductHandler, buyer: Player)
	local receiptKey = `{receipt.PlayerId}_{receipt.PurchaseId}`
	local alreadyDone = false
	-- UpdateAsync may run the callback again if the key changes under it; this keeps the grant to once.
	local granted = false
	local updateOk, err = pcall(function()
		store:UpdateAsync(receiptKey, function(done)
			alreadyDone = done == true
			if alreadyDone then
				return nil -- recorded already: leave it, don't grant
			end
			if not granted then
				local grantOk, given = pcall(grant, buyer)
				if not grantOk then
					warn(`[Monetization] handler failed for purchase {receipt.PurchaseId}: {given}`)
					return nil
				end
				if given ~= true then
					return nil
				end
				granted = true
			end
			return true
		end)
	end)
	if alreadyDone or granted then
		if granted and not updateOk then
			-- It was given, so tell Roblox it's done rather than risk giving it again on retry.
			warn(`[Monetization] granted purchase {receipt.PurchaseId} but couldn't record it: {err}`)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not updateOk then
		warn(`[Monetization] couldn't read purchase {receipt.PurchaseId}: {err}`)
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

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

--!strict
-- Robux purchases, on the server. Game code says what each purchase gives:
--   Monetization.onPass("VIP", function(player) ... end)            -- runs when an owner joins, and right after buying
--   Monetization.onProduct("Coins100", function(player) ... return true end)  -- return true once it's given
-- A product's receipt is recorded, so a purchase Roblox retries is never given twice.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)

local Monetization = {}

type PassHandler = (player: Player) -> ()
type ProductHandler = (player: Player) -> boolean

local passHandlers: { [string]: PassHandler } = {}
local productHandlers: { [string]: ProductHandler } = {}
local owned: { [Player]: { [string]: boolean } } = {}
local history = DataStoreService:GetDataStore("PurchaseHistory")

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

MarketplaceService.ProcessReceipt = function(receipt)
	local key = keyFor(Products.Products, receipt.ProductId)
	local handler = if key then productHandlers[key] else nil
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not handler or not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local grant: ProductHandler = handler
	local buyer: Player = player
	local granted = false
	local ok, err = pcall(function()
		history:UpdateAsync(`{receipt.PlayerId}_{receipt.PurchaseId}`, function(done)
			if done then
				granted = true
				return nil
			end
			if grant(buyer) then
				granted = true
				return true
			end
			return nil
		end)
	end)
	if not ok then
		warn(`[Monetization] couldn't record purchase {receipt.PurchaseId}: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

return Monetization

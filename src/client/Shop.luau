--!strict
-- Opens Roblox's purchase prompt for something listed in Shared.Products. Granting happens on the server
-- (src/server/Monetization.luau), never here.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)

local Shop = {}

function Shop.buyPass(key: string)
	local pass = Products.Passes[key]
	if not pass or pass.id == 0 then
		warn(`[Shop] the pass "{key}" has no ID yet: create it in the Creator Hub, then paste it into Products`)
		return
	end
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, pass.id)
end

function Shop.buyProduct(key: string)
	local product = Products.Products[key]
	if not product or product.id == 0 then
		warn(`[Shop] the product "{key}" has no ID yet: create it in the Creator Hub, then paste it into Products`)
		return
	end
	MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.id)
end

return Shop

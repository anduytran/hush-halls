--!strict
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Hud = require(script.Parent.UI.Hud)
local ShopMenu = require(script.Parent.UI.ShopMenu)

Hud.mount()
ShopMenu.mount()

print(`[client] Welcome to {Config.GAME_NAME}`)

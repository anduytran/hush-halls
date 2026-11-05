--!strict
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Audio = require(script.Parent.Audio)
local Dread = require(script.Parent.Dread)
local Hud = require(script.Parent.UI.Hud)
local MonsterAnimator = require(script.Parent.MonsterAnimator)
local ShopMenu = require(script.Parent.UI.ShopMenu)

Hud.mount()
ShopMenu.mount()
Audio.start()
Dread.start()
MonsterAnimator.start()

print(`[client] Welcome to {Config.GAME_NAME}`)

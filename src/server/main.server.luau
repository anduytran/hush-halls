--!strict
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local NoiseService = require(script.Parent.NoiseService)

NoiseService.start()

-- Robux purchases: say what each one gives with Monetization.onPass / Monetization.onProduct.
local _Monetization = require(script.Parent.Monetization)

print(`[server] {Config.GAME_NAME} started`)

-- Engine tests for RoundService.luau. Run in a real Roblox server on the test place.
-- main.server.luau has already called RoundService.start(), so these tests call it again on purpose.
-- Only player-less behaviour is checked here: Running, InRound and spectator moves need real Players,
-- which a test server does not provide; those are covered by the Studio playtest.
local RoundService = require("./RoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local state = ReplicatedStorage:WaitForChild("State", 10)
assert(state and state:IsA("Folder"), "ReplicatedStorage.State missing")

return {
	["start() can be called twice without error"] = function()
		RoundService.start()
		RoundService.start()
		local roundState = state:GetAttribute("RoundState")
		assert(
			roundState == "Lobby" or roundState == "Running" or roundState == "Ended",
			"unexpected RoundState " .. tostring(roundState)
		)
	end,

	["with no players the Lobby timer stays at 15 and does not advance"] = function()
		if #Players:GetPlayers() > 0 then
			return -- only meaningful on an empty server
		end
		task.wait(1.5)
		assert(state:GetAttribute("RoundState") == "Lobby", "expected Lobby with no players")
		assert(
			state:GetAttribute("TimeLeft") == 15,
			"expected TimeLeft 15 in Lobby, got " .. tostring(state:GetAttribute("TimeLeft"))
		)
	end,
}

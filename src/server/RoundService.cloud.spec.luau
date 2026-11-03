-- Engine tests for RoundService.luau. Run in a real Roblox server on the test place.
-- Sprint-3 fix: every test starts from fresh state. beforeEach stops the loop main.server started
-- (or the previous test's), clears the round, and starts a new one, so no live state is shared.
-- Only player-less behaviour is checked here: Running, InRound and spectator moves need real Players,
-- which a test server does not provide; those are covered by the Studio playtest.
local RoundService = require("./RoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local state = ReplicatedStorage:WaitForChild("State", 10)
assert(state and state:IsA("Folder"), "ReplicatedStorage.State missing")

local function beforeEach()
	RoundService.stop()
	state:SetAttribute("RoundState", nil)
	state:SetAttribute("TimeLeft", nil)
	RoundService.start()
end

local tests = {
	["start() can be called twice without error"] = function()
		RoundService.start()
		local roundState = state:GetAttribute("RoundState")
		assert(roundState == "Lobby", "expected a fresh loop to be in Lobby, got " .. tostring(roundState))
	end,

	["a fresh start begins in Lobby with TimeLeft 15"] = function()
		assert(state:GetAttribute("RoundState") == "Lobby", "expected Lobby")
		assert(
			state:GetAttribute("TimeLeft") == 15,
			"expected TimeLeft 15, got " .. tostring(state:GetAttribute("TimeLeft"))
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

	["stop() twice is safe, and start() after it begins a fresh Lobby"] = function()
		RoundService.stop()
		RoundService.stop()
		state:SetAttribute("RoundState", nil)
		state:SetAttribute("TimeLeft", nil)
		RoundService.start()
		task.wait(0.5)
		assert(
			state:GetAttribute("RoundState") == "Lobby",
			"expected Lobby after restart, got " .. tostring(state:GetAttribute("RoundState"))
		)
	end,

	["stop() ends the loop: state is no longer updated"] = function()
		RoundService.stop()
		state:SetAttribute("TimeLeft", -1)
		task.wait(1.5)
		assert(state:GetAttribute("TimeLeft") == -1, "expected the stopped loop to leave TimeLeft alone")
	end,
}

-- The runner has no beforeEach hook, so each test is wrapped to call it first.
local wrapped = {}
for name, test in tests do
	wrapped[name] = function()
		beforeEach()
		test()
	end
end
return wrapped

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

-- A stand-in character, and a stand-in player who isn't in the round (RoundService only reads .Character
-- from a non-participant). Returns both plus a cleanup function.
local function fakeJoiner()
	local character = Instance.new("Model")
	character.Name = "SpecJoiner"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Position = Vector3.new(0, 500, 0)
	root.Parent = character
	character.PrimaryPart = root
	character.Parent = workspace
	local player = { Character = character }
	return player, character, function()
		character:Destroy()
	end
end

local tests = {
	["a player joining while the round is spawning lands on the platform"] = function()
		task.wait(0.5) -- start() waits for Hall.Start/Exit before the platform exists
		local platform = RoundService._test.platform()
		assert(platform, "start() should have made Hall.LobbyPlatform")
		local player, character, cleanup = fakeJoiner()
		RoundService._test.setSpawning(true)
		local ok, err = pcall(RoundService._test.placeSpectator, player, character)
		RoundService._test.setSpawning(false)
		local position = character:GetPivot().Position
		cleanup()
		assert(ok, "placeSpectator errored: " .. tostring(err))
		local flat = Vector3.new(position.X - platform.Position.X, 0, position.Z - platform.Position.Z)
		assert(flat.Magnitude <= 18, "expected the joiner over the platform, was " .. flat.Magnitude .. " studs off")
		assert(
			math.abs(position.Y - (platform.Position.Y + 4)) < 0.5,
			"expected the joiner 4 studs above the platform, got Y " .. position.Y
		)
	end,

	["a player joining in Lobby (not spawning) stays where they spawned"] = function()
		task.wait(0.5)
		local player, character, cleanup = fakeJoiner()
		RoundService._test.placeSpectator(player, character)
		local position = character:GetPivot().Position
		cleanup()
		assert((position - Vector3.new(0, 500, 0)).Magnitude < 0.01, "a Lobby joiner must not be moved")
	end,

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

	["stop() when not started is a safe no-op"] = function()
		RoundService.stop()
		state:SetAttribute("TimeLeft", -1)
		RoundService.stop() -- not started now: must not touch anything
		assert(state:GetAttribute("TimeLeft") == -1, "stop() when not started changed state")
	end,

	-- Sprint-5 fix: this used to set State.TimeLeft to -1 and check nothing wrote it. That failed because the
	-- spec's RoundService can be a separate module instance from main.server's, whose loop keeps writing the
	-- shared State folder. So it checks this instance's own loop thread instead.
	["stop() ends the loop: its thread is cancelled and cleared"] = function()
		local thread = RoundService._test.loop()
		assert(thread, "start() should have started the loop")
		RoundService.stop()
		assert(RoundService._test.loop() == nil, "stop() should clear the loop")
		task.wait(1.5)
		assert(
			coroutine.status(thread) == "dead",
			"expected the stopped loop to be dead, was " .. coroutine.status(thread)
		)
	end,

	["stop() clears the platform and start() finds it again"] = function()
		task.wait(0.5)
		local before = RoundService._test.platform()
		assert(before, "start() should have made Hall.LobbyPlatform")
		RoundService.stop()
		assert(RoundService._test.platform() == nil, "stop() should reset platform to nil")
		RoundService.start()
		task.wait(0.5)
		assert(RoundService._test.platform() == before, "start() should reuse the existing Hall.LobbyPlatform")
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

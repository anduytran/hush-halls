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

-- Sprint-7 fix: the original Hall.LobbyPlatform is remembered here, before any test runs. It is never destroyed:
-- resetState detaches it (Parent = nil) and afterEach puts it back in Hall. Only platforms this spec makes are
-- destroyed.
local hall = workspace:FindFirstChild("Hall")
local originalPlatform: BasePart? = hall and hall:FindFirstChild("LobbyPlatform") :: BasePart?

-- Sprint-7 fix: skip the whole suite if a live round is running, or a player is standing on the original platform
-- (so a test can't move someone or tear down a platform that is in use).
local function platformInUse(platform: BasePart): boolean
	local half = platform.Size / 2
	local topY = platform.Position.Y + half.Y
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local offset = root.Position - platform.Position
			local height = root.Position.Y - topY
			if math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z and height >= 0 and height <= 20 then
				return true
			end
		end
	end
	return false
end

if state:GetAttribute("RoundState") == "Running" then
	warn("[RoundService.cloud.spec] skipped: a round is Running on this server")
	return {}
end
if originalPlatform and platformInUse(originalPlatform) then
	warn("[RoundService.cloud.spec] skipped: a player is standing on Hall.LobbyPlatform")
	return {}
end

-- Sprint-6 fix: no test depends on what an earlier test left behind. Before each test the service is stopped,
-- any forced failure is cleared, State is wiped and Hall.LobbyPlatform is replaced, so start() makes a new one;
-- after each test (even a failed one) the service is stopped again.
-- Sprint-7 fix: the original platform is detached (Parent = nil) rather than destroyed. Any other platform
-- in Hall is one this spec made, and it is destroyed.
local function resetState()
	RoundService._test.failStep(nil)
	RoundService.stop()
	state:SetAttribute("RoundState", nil)
	state:SetAttribute("TimeLeft", nil)
	local currentHall = workspace:FindFirstChild("Hall")
	if currentHall then
		for _, child in currentHall:GetChildren() do
			if child.Name == "LobbyPlatform" then
				if child == originalPlatform then
					child.Parent = nil
				else
					child:Destroy()
				end
			end
		end
	end
end

local function beforeEach()
	resetState()
	RoundService.start()
end

-- Sprint-7 fix: puts the original platform back in Hall. resetState has already destroyed any spec-made platform.
local function afterEach()
	resetState()
	local currentHall = workspace:FindFirstChild("Hall")
	if originalPlatform and currentHall then
		originalPlatform.Parent = currentHall
	end
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
		assert(before.Parent and before.Parent.Name == "Hall", "the platform should be in Hall")
		RoundService.stop()
		assert(RoundService._test.platform() == nil, "stop() should reset platform to nil")
		RoundService.start()
		task.wait(0.5)
		assert(RoundService._test.platform() == before, "start() should reuse the existing Hall.LobbyPlatform")
	end,

	["each test starts with a newly made platform"] = function()
		-- beforeEach detached the original platform and removed any spec-made one, so this one was made by
		-- this test's start().
		local currentHall = workspace:FindFirstChild("Hall")
		assert(currentHall, "start() should have found or built the Hall")
		local platforms = 0
		for _, child in currentHall:GetChildren() do
			if child.Name == "LobbyPlatform" then
				platforms += 1
			end
		end
		assert(platforms == 1, `expected exactly one Hall.LobbyPlatform, found {platforms}`)
	end,

	-- Sprint-6 fix: start()'s setup runs as small steps, each in its own pcall. Whichever step fails, start()
	-- errors naming it, and everything set up before it is undone (same rollback as the old single pcall).
	["a failing setup step rolls back and names the step; a later start() works"] = function()
		for _, stepName in { "the lobby platform", "player setup", "the exit", "the round loop" } do
			resetState()
			RoundService._test.failStep(stepName)
			local ok, err = pcall(RoundService.start)
			RoundService._test.failStep(nil)
			assert(not ok, `start() should error when "{stepName}" fails`)
			assert(string.find(tostring(err), stepName, 1, true), `the error should name "{stepName}", got {err}`)
			assert(not RoundService._test.started(), `"{stepName}" failing should clear started`)
			assert(RoundService._test.connectionCount() == 0, `"{stepName}" failing left connections behind`)
			assert(RoundService._test.loop() == nil, `"{stepName}" failing left the loop running`)
			assert(RoundService._test.platform() == nil, `"{stepName}" failing left the platform set`)
		end
		-- A retry after a failed start registers each connection once: PlayerAdded, PlayerRemoving, Exit.Touched,
		-- plus one CharacterAdded per player already in the server.
		RoundService.start()
		local expected = 3 + #Players:GetPlayers()
		local count = RoundService._test.connectionCount()
		assert(count == expected, `expected {expected} connections after a retry, got {count}`)
		assert(RoundService._test.loop(), "a retry should start the loop")
	end,

	-- Sprint-7 fix: beforeStep is the hook start() calls before each setup step. It must be a function, both
	-- at the default and after failStep(nil) has cleared a forced failure.
	["the beforeStep hook is a function, and failStep(nil) restores it"] = function()
		assert(type(RoundService._test.beforeStep) == "function", "_test.beforeStep should be a function")
		RoundService._test.failStep("the exit")
		RoundService._test.failStep(nil)
		assert(
			type(RoundService._test.beforeStep) == "function",
			"_test.beforeStep should still be a function after failStep(nil)"
		)
	end,

	-- Sprint-7 fix: after a forced failure is cleared with failStep(nil), start() succeeds and starts the loop.
	["after failStep(nil) clears a forced failure, start() succeeds"] = function()
		RoundService.stop()
		RoundService._test.failStep("the exit")
		local ok = pcall(RoundService.start)
		assert(not ok, 'start() should error while "the exit" is forced to fail')
		RoundService._test.failStep(nil)
		local startOk, startErr = pcall(RoundService.start)
		assert(startOk, `start() should succeed after failStep(nil), got {tostring(startErr)}`)
		assert(RoundService._test.started(), "start() should mark the service started")
		assert(RoundService._test.loop(), "start() should start the loop")
	end,

	-- Sprint-14: the escape reward is 10 Coins, times the player's CoinMultiplier attribute when that is a number >= 1.
	-- The fake player has just the two members addCoins reads: FindFirstChild and GetAttribute.
	["escape coins use CoinMultiplier: none = 10, 2 = 20, bad values = 10"] = function()
		local function coinsAfterReward(multiplier: any): number
			local leaderstats = Instance.new("Folder")
			leaderstats.Name = "leaderstats"
			local coins = Instance.new("IntValue")
			coins.Name = "Coins"
			coins.Parent = leaderstats
			local player = {
				FindFirstChild = function(_self: any, name: string)
					return if name == "leaderstats" then leaderstats else nil
				end,
				GetAttribute = function(_self: any, name: string)
					return if name == "CoinMultiplier" then multiplier else nil
				end,
			}
			RoundService._test.addCoins(player :: any, 10)
			local value = coins.Value
			leaderstats:Destroy()
			return value
		end
		assert(coinsAfterReward(nil) == 10, "no attribute should give +10")
		assert(coinsAfterReward(2) == 20, "CoinMultiplier 2 should give +20")
		assert(coinsAfterReward(1.5) == 15, "CoinMultiplier 1.5 should give +15")
		for _, bad in { 0, 0.5, -3, "2", true, 0 / 0, math.huge } do
			assert(coinsAfterReward(bad) == 10, `CoinMultiplier {tostring(bad)} should count as 1`)
		end
	end,
}

-- The runner has no beforeEach/afterEach hooks, so each test is wrapped: fresh state before, cleanup after.
local wrapped = {}
for name, test in tests do
	wrapped[name] = function()
		beforeEach()
		local ok, err = pcall(test)
		afterEach()
		if not ok then
			error(err, 0)
		end
	end
end
return wrapped

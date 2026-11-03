-- Engine tests for RoundService.luau. Run in a real Roblox server on the test place.
-- Sprint-3 fix: every test starts from fresh state. beforeEach stops the loop main.server started
-- (or the previous test's), clears the round, and starts a new one, so no live state is shared.
-- Most tests check player-less behaviour. Sprint 20: the end-to-end round test needs a real Player (a Studio
-- play-test) and Studio's _test.setDurations; it skips itself without them.
local RoundService = require("./RoundService")
local RoundTestPlayers = require("./RoundTestPlayers")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")

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
	RoundService._test.resetDurations()
	RoundService.stop()
	RoundTestPlayers._test.pretendLiveServer(false)
	RoundTestPlayers.detach()
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

-- Sprint 20: stops this instance's loop, then watches State for 1.25s without writing it. True if another
-- RoundService instance (e.g. main.server's, when the spec got its own copy) changes RoundState or TimeLeft, or
-- has a round under way (a player is InRound while this instance is stopped).
local function anotherLoopRunning(): boolean
	RoundService.stop()
	local changed = false
	local connection = state.AttributeChanged:Connect(function(name)
		if name == "RoundState" or name == "TimeLeft" then
			changed = true
		end
	end)
	task.wait(1.25)
	connection:Disconnect()
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("InRound") == true then
			return true
		end
	end
	return changed
end

-- Sprint 21: the fake-player round tests need Studio (setDurations, RoundTestPlayers) and no other loop writing
-- State. Sprint 22: when they can run, this also wires RoundTestPlayers into the (now stopped) RoundService.
local function fakeRoundSkipped(what: string): boolean
	if not RunService:IsStudio() then
		warn(`[RoundService.cloud.spec] {what} skipped: RoundTestPlayers is Studio only`)
		return true
	end
	if anotherLoopRunning() then
		warn(`[RoundService.cloud.spec] {what} skipped: another RoundService loop is writing State`)
		return true
	end
	RoundTestPlayers.attach(RoundService)
	return false
end

-- Sprint 22: the module scripts whose errors fail a test, found by instance (this spec is their sibling).
local watchedScripts: { Instance } = {}
for _, name in { "RoundService", "RoundTestPlayers" } do
	local module = script.Parent and script.Parent:FindFirstChild(name)
	if module then
		table.insert(watchedScripts, module)
	end
end

-- True if the error came from a watched script: it is the erroring script, or a line of the stack trace is in
-- it ("<full name>:<line>" or "<full name>, line <n>", so "RoundService.cloud.spec" doesn't count).
local function fromWatchedScript(errorScript: Instance?, trace: string): boolean
	for _, module in watchedScripts do
		local fullName = module:GetFullName()
		if
			errorScript == module
			or string.find(trace, fullName .. ":", 1, true)
			or string.find(trace, fullName .. ", line", 1, true)
		then
			return true
		end
	end
	return false
end

-- Sprint 21: collects RoundService's warnings and errors until the returned function is called; that returns them.
-- Sprint 22: matched by source, not message text: warnings arrive through this instance's _test.onWarn hook (every
-- RoundService warn goes through it), errors through ScriptContext.Error when the erroring script or its stack
-- trace is RoundService or RoundTestPlayers. Errors caught by a pcall (as failStep's are) aren't reported.
local function watchRoundServiceLogs(): () -> { string }
	local messages: { string } = {}
	local previousOnWarn = RoundService._test.onWarn
	RoundService._test.onWarn = function(message: string)
		table.insert(messages, message)
	end
	local connection = ScriptContext.Error:Connect(function(message, trace, errorScript)
		if fromWatchedScript(errorScript, trace) then
			table.insert(messages, message)
		end
	end)
	return function()
		task.wait() -- errors raised this frame can arrive a frame late
		connection:Disconnect()
		RoundService._test.onWarn = previousOnWarn
		return messages
	end
end

-- Runs the test body while watching RoundService's output; fails if the body did, or if RoundService warned or erred.
local function withoutRoundServiceLogs(body: () -> ())
	local stopWatching = watchRoundServiceLogs()
	local ok, err = pcall(body)
	local messages = stopWatching()
	if not ok then
		error(err, 0)
	end
	assert(#messages == 0, `RoundService printed {#messages} warning(s)/error(s): {table.concat(messages, " | ")}`)
end

-- Sprint 23: for tests that expect RoundService to warn. Collects this instance's warnings while body runs and
-- returns them, instead of letting them fail the test; a warning after body returns still fails it, and so do errors.
local function collectWarnings(body: () -> ()): { string }
	local warnings: { string } = {}
	local previousOnWarn = RoundService._test.onWarn
	RoundService._test.onWarn = function(message: string)
		table.insert(warnings, message)
	end
	local ok, err = pcall(body)
	RoundService._test.onWarn = previousOnWarn
	if not ok then
		error(err, 0)
	end
	return warnings
end

-- Waits (sampling each frame) until RoundState is the given state, or errors after timeout seconds.
local function waitForState(roundState: string, timeout: number, onFrame: (() -> ())?)
	local deadline = os.clock() + timeout
	while state:GetAttribute("RoundState") ~= roundState do
		assert(os.clock() < deadline, `timed out waiting for RoundState {roundState}`)
		if onFrame then
			onFrame()
		end
		RunService.Heartbeat:Wait()
	end
end

-- Sprint 22: waits (checking each frame) until done() is true, or errors after timeout seconds. Timeouts are
-- generous: the tests wait for state changes, not for a set time.
local function waitUntil(what: string, timeout: number, done: () -> boolean)
	local deadline = os.clock() + timeout
	while not done() do
		assert(os.clock() < deadline, `timed out after {timeout}s waiting for {what}`)
		RunService.Heartbeat:Wait()
	end
end

local function coinsOf(player: RoundTestPlayers.FakePlayer): any
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	return if coins and coins:IsA("IntValue") then coins.Value else nil
end

-- The character stands on the platform: sendToPlatform puts it 4 studs up, within 12 studs on X and Z.
local function onPlatform(player: RoundTestPlayers.FakePlayer, platform: BasePart): (boolean, string)
	local character = player.Character
	if not character then
		return false, `{player.Name} has no character`
	end
	local position = character:GetPivot().Position
	local flat = Vector3.new(position.X - platform.Position.X, 0, position.Z - platform.Position.Z)
	if flat.Magnitude > 18 then
		return false, `expected {player.Name} over the platform, was {flat.Magnitude} studs off`
	end
	if math.abs(position.Y - (platform.Position.Y + 4)) >= 0.5 then
		return false, `expected {player.Name} 4 studs above the platform, got Y {position.Y}`
	end
	return true, ""
end

local function assertOnPlatform(player: RoundTestPlayers.FakePlayer, platform: BasePart)
	local ok, why = onPlatform(player, platform)
	assert(ok, why)
end

local tests = {
	["a player joining while the round is spawning lands on the platform"] = function()
		waitUntil("start() to make Hall.LobbyPlatform", 10, function()
			return RoundService._test.platform() ~= nil
		end)
		local platform = RoundService._test.platform() :: BasePart
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
		waitUntil("RoundState Lobby", 10, function()
			return state:GetAttribute("RoundState") == "Lobby"
		end)
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
		waitUntil("Lobby after the restart", 10, function()
			return state:GetAttribute("RoundState") == "Lobby"
		end)
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
		waitUntil(`the stopped loop to be dead (was {coroutine.status(thread)})`, 5, function()
			return coroutine.status(thread) == "dead"
		end)
	end,

	["stop() clears the platform and start() finds it again"] = function()
		waitUntil("start() to make Hall.LobbyPlatform", 10, function()
			return RoundService._test.platform() ~= nil
		end)
		local before = RoundService._test.platform() :: BasePart
		assert(before.Parent and before.Parent.Name == "Hall", "the platform should be in Hall")
		RoundService.stop()
		assert(RoundService._test.platform() == nil, "stop() should reset platform to nil")
		RoundService.start()
		waitUntil("start() to find the platform again", 10, function()
			return RoundService._test.platform() ~= nil
		end)
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

	-- Sprint 20: the duration hook is Studio only, takes seconds >= 0.5, and resetDurations() restores 15/120/5.
	["setDurations checks its seconds and resetDurations restores the defaults"] = function()
		local setDurations = RoundService._test.setDurations
		if not RunService:IsStudio() then
			assert(not pcall(setDurations, 1, 2, 1), "setDurations should error outside Studio")
			return
		end
		assert(not pcall(setDurations, nil, 2, 1), "a missing lobby length should be rejected")
		for _, bad in { 0.4, 0, -1, 0 / 0, math.huge, "1", true } do
			assert(not pcall(setDurations, bad, 2, 1), `lobby {tostring(bad)} should be rejected`)
			assert(not pcall(setDurations, 1, bad, 1), `running {tostring(bad)} should be rejected`)
			assert(not pcall(setDurations, 1, 2, bad), `ended {tostring(bad)} should be rejected`)
		end
		local lobby, running, ended = RoundService._test.durations()
		assert(lobby == 15 and running == 120 and ended == 5, "a rejected call should leave the defaults")
		setDurations(0.5, 2, 1)
		lobby, running, ended = RoundService._test.durations()
		assert(lobby == 0.5 and running == 2 and ended == 1, `expected 0.5/2/1, got {lobby}/{running}/{ended}`)
		RoundService._test.resetDurations()
		lobby, running, ended = RoundService._test.durations()
		assert(lobby == 15 and running == 120 and ended == 5, `expected 15/120/5, got {lobby}/{running}/{ended}`)
	end,

	-- Sprint 20: with the hook unused, the Lobby still counts down in whole seconds from 15.
	["with players and default durations the Lobby counts 15, 14 a second apart"] = function()
		if #Players:GetPlayers() == 0 then
			return -- the Lobby only counts down with a player present
		end
		if anotherLoopRunning() then
			warn("[RoundService.cloud.spec] default Lobby check skipped: another RoundService loop is writing State")
			return
		end
		local lobby, running, ended = RoundService._test.durations()
		assert(lobby == 15 and running == 120 and ended == 5, `expected 15/120/5, got {lobby}/{running}/{ended}`)
		RoundService.start()
		assert(state:GetAttribute("TimeLeft") == 15, `expected TimeLeft 15, got {state:GetAttribute("TimeLeft")}`)
		-- Sprint 22: waits for the first change instead of sampling at set times. The next value must be 14,
		-- still in Lobby, and it can't come early (task.wait never returns early, so 0.5s is a safe floor).
		local started = os.clock()
		waitUntil("TimeLeft to leave 15", 10, function()
			return state:GetAttribute("TimeLeft") ~= 15
		end)
		local elapsed = os.clock() - started
		assert(
			state:GetAttribute("TimeLeft") == 14,
			`expected TimeLeft 14 after 15, got {state:GetAttribute("TimeLeft")}`
		)
		assert(state:GetAttribute("RoundState") == "Lobby", "expected Lobby")
		assert(elapsed >= 0.5, `TimeLeft went 15 -> 14 after only {elapsed}s; a Lobby second should last 1s`)
	end,

	-- Sprint 20: end-to-end smoke of one round with durations 1/2/1. Samples State and every present player each
	-- frame from the first Lobby to the next one. Mid-Running it marks everyone Escaped (as Exit.Touched would),
	-- which also ends Running early, so the next round's spawn has an Escaped flag to clear. RoundService clears
	-- Escaped when that Lobby's countdown ends, while RoundState is still Lobby.
	["one full round with durations 1/2/1: states, timer, water, InRound and Escaped"] = function()
		local players = Players:GetPlayers()
		if #players == 0 then
			warn("[RoundService.cloud.spec] round smoke skipped: it needs a player (Studio play-test)")
			return
		end
		if not RunService:IsStudio() then
			warn("[RoundService.cloud.spec] round smoke skipped: _test.setDurations is Studio only")
			return
		end
		if anotherLoopRunning() then
			warn("[RoundService.cloud.spec] round smoke skipped: another RoundService loop is writing State")
			return
		end
		-- NoiseService (started by main.server) makes Workspace.Water and resets WaterLevel on Lobby and Running.
		local noiseRunning = workspace:FindFirstChild("Water") ~= nil
		if not noiseRunning then
			warn("[RoundService.cloud.spec] round smoke: NoiseService isn't running, so the water reset isn't checked")
		end

		RoundService._test.setDurations(1, 2, 1)
		RoundService.start()

		type Sample = {
			roundState: any,
			timeLeft: any,
			water: number,
			afterEscape: boolean,
			inRound: { [Player]: any },
			escaped: { [Player]: any },
		}
		local samples: { Sample } = {}
		local phases: { any } = {}
		local escapeMarked = false
		local deadline = os.clock() + 30
		while os.clock() < deadline do
			local sample: Sample = {
				roundState = state:GetAttribute("RoundState"),
				timeLeft = state:GetAttribute("TimeLeft"),
				water = state:GetAttribute("WaterLevel") :: number? or 0,
				afterEscape = escapeMarked,
				inRound = {},
				escaped = {},
			}
			local escapedCleared = true
			for _, player in players do
				if player.Parent == Players then
					sample.inRound[player] = player:GetAttribute("InRound")
					sample.escaped[player] = player:GetAttribute("Escaped")
					if sample.escaped[player] ~= false then
						escapedCleared = false
					end
				end
			end
			table.insert(samples, sample)
			if phases[#phases] ~= sample.roundState then
				table.insert(phases, sample.roundState)
			end
			if #phases > 4 or (#phases == 4 and escapeMarked and escapedCleared) then
				break
			end
			if sample.roundState == "Running" and sample.timeLeft == 1 and not escapeMarked then
				-- Same attributes as Exit.Touched sets. With NoiseService running, the water is also raised as
				-- noise would, so the next Lobby has a level to reset.
				escapeMarked = true
				for _, player in players do
					if player.Parent == Players then
						player:SetAttribute("Escaped", true)
						player:SetAttribute("InRound", false)
					end
				end
				if noiseRunning and sample.water == 0 then
					state:SetAttribute("WaterLevel", 1)
				end
			end
			RunService.Heartbeat:Wait()
		end

		-- RoundState: Lobby -> Running -> Ended -> Lobby, and nothing else.
		local names = {}
		for _, phase in phases do
			table.insert(names, tostring(phase))
		end
		local order = table.concat(names, " -> ")
		assert(
			order == "Lobby -> Running -> Ended -> Lobby",
			`expected Lobby -> Running -> Ended -> Lobby, got {order}`
		)
		assert(escapeMarked, "Running never showed TimeLeft 1, so the escape was never marked")

		-- Split the samples into the four phases.
		local segments: { { Sample } } = {}
		for _, sample in samples do
			local last = segments[#segments]
			if not last or last[1].roundState ~= sample.roundState then
				table.insert(segments, { sample })
			else
				table.insert(last, sample)
			end
		end
		local lobby1, running, ended, lobby2 = segments[1], segments[2], segments[3], segments[4]

		-- TimeLeft counts down inside each phase and starts at that phase's length.
		local function timesOf(segment: { Sample }): string
			local seen = {}
			for _, sample in segment do
				if seen[#seen] ~= tostring(sample.timeLeft) then
					table.insert(seen, tostring(sample.timeLeft))
				end
			end
			return table.concat(seen, ",")
		end
		for index, segment in segments do
			for i = 2, #segment do
				local before, now = segment[i - 1].timeLeft, segment[i].timeLeft
				assert(
					type(before) == "number" and type(now) == "number" and now <= before,
					`TimeLeft went up in phase {index} ({segment[1].roundState}): {timesOf(segment)}`
				)
			end
		end
		assert(timesOf(lobby1) == "1,0", `first Lobby TimeLeft should go 1,0, got {timesOf(lobby1)}`)
		local runTimes = timesOf(running)
		assert(string.sub(runTimes, 1, 3) == "2,1", `Running TimeLeft should start 2,1, got {runTimes}`)
		assert(timesOf(ended) == "1", `Ended TimeLeft should be 1, got {timesOf(ended)}`)
		assert(lobby2[1].timeLeft == 1, `the next Lobby should start at TimeLeft 1, got {tostring(lobby2[1].timeLeft)}`)

		-- WaterLevel never rises outside Running, and is 0 by the end of each Lobby.
		for i = 2, #samples do
			local before, now = samples[i - 1], samples[i]
			if before.roundState ~= "Running" and now.roundState ~= "Running" then
				assert(
					now.water <= before.water + 1e-6,
					`WaterLevel rose from {before.water} to {now.water} during {tostring(now.roundState)}`
				)
			end
		end
		assert(lobby1[#lobby1].water == 0, `WaterLevel should be 0 in Lobby, got {lobby1[#lobby1].water}`)
		local final = samples[#samples]
		if noiseRunning then
			assert(ended[#ended].water > 0, "the water raised while Running should still be up in Ended")
		end
		assert(final.water == 0, `WaterLevel should reset by the next Lobby, got {final.water}`)

		-- InRound: true for every present player all through Running until they escape; false in Ended and the
		-- next Lobby's countdown (the next round's spawn sets it again once that countdown ends).
		for _, sample in running do
			if not sample.afterEscape then
				for player, inRound in sample.inRound do
					assert(inRound == true, `{player.Name} should be InRound while Running, was {tostring(inRound)}`)
				end
			end
		end
		for _, segment in { ended, lobby2 } do
			for _, sample in segment do
				if sample.timeLeft ~= 0 then
					for player, inRound in sample.inRound do
						assert(
							inRound == false,
							`{player.Name} should not be InRound during {tostring(sample.roundState)}, was {tostring(
								inRound
							)}`
						)
					end
				end
			end
		end

		-- Escaped: still true through Ended, then cleared before the next round leaves Lobby.
		for _, sample in ended do
			for player, escaped in sample.escaped do
				assert(escaped == true, `{player.Name} should still be Escaped during Ended, was {tostring(escaped)}`)
			end
		end
		assert(
			final.roundState == "Lobby",
			`Escaped should be cleared while still in Lobby, got {tostring(final.roundState)}`
		)
		for player, escaped in final.escaped do
			assert(
				escaped == false,
				`{player.Name} should have Escaped cleared at the next Lobby, was {tostring(escaped)}`
			)
		end
	end,

	-- Sprint 21: two fake participants, durations 1/3/1. The runner touches the exit twice at the start of Running
	-- and is paid 10 Coins once; the stayer stays InRound until Ended (Running runs its full 3s); then both clear.
	-- RoundService must not warn or error during the run. A real player in the play-test just plays along.
	["two players: one escapes for exactly 10 coins once, the other stays InRound until Ended"] = function()
		if fakeRoundSkipped("two-player round") then
			return
		end
		RoundService._test.setDurations(1, 3, 1)
		local runner = RoundTestPlayers.add("SpecRunner")
		local stayer = RoundTestPlayers.add("SpecStayer")
		RoundService.start()
		assert(coinsOf(runner) == 0 and coinsOf(stayer) == 0, "fake players should start with 0 Coins")

		waitForState("Running", 15)
		for _, player in { runner, stayer } do
			assert(player:GetAttribute("InRound") == true, `{player.Name} should be InRound when Running begins`)
		end

		local root = (runner.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
		assert(RoundTestPlayers.touchExit(root), "touchExit should reach start()'s exit handler")
		assert(runner:GetAttribute("Escaped") == true, "touching the exit should mark the runner Escaped")
		assert(runner:GetAttribute("InRound") == false, "an escaped runner should leave InRound")
		assert(coinsOf(runner) == 10, `the first touch should pay 10 Coins, got {tostring(coinsOf(runner))}`)
		RunService.Heartbeat:Wait()
		assert(RoundTestPlayers.touchExit(root), "the second touchExit should reach the handler too")
		assert(coinsOf(runner) == 10, `a second touch must not pay again, got {tostring(coinsOf(runner))}`)
		local platform = RoundService._test.platform()
		assert(platform, "start() should have made Hall.LobbyPlatform")
		assertOnPlatform(runner, platform)

		-- Sprint 22: Running must run out its clock while the stayer is in, rather than end early. Checked by state,
		-- not time: Running is seen in its last second (TimeLeft 1). The loop writes 0 and switches to Ended in one
		-- step, so 0 itself is never seen while Running.
		local lowestRunningTime = math.huge
		waitForState("Ended", 15, function()
			assert(stayer:GetAttribute("InRound") == true, "the stayer should stay InRound all through Running")
			assert(runner:GetAttribute("InRound") == false, "the escaped runner must not be InRound again")
			local timeLeft = state:GetAttribute("TimeLeft")
			if state:GetAttribute("RoundState") == "Running" and type(timeLeft) == "number" then
				lowestRunningTime = math.min(lowestRunningTime, timeLeft)
			end
		end)
		assert(
			lowestRunningTime <= 1,
			`Running should count down to its last second while the stayer is in, lowest TimeLeft {lowestRunningTime}`
		)

		waitForState("Lobby", 15, function()
			for _, player in { runner, stayer } do
				assert(player:GetAttribute("InRound") == false, `{player.Name} should not be InRound in Ended`)
			end
		end)
		assert(coinsOf(runner) == 10, `the runner should end with 10 Coins, got {tostring(coinsOf(runner))}`)
		assert(coinsOf(stayer) == 0, `the stayer didn't escape and should have 0 Coins, got {coinsOf(stayer)}`)
	end,

	-- Sprint 21: a fake who joins while Running (durations 1/2/1) watches from the platform, is never InRound in
	-- that round, and is spawned into the next one. RoundService must not warn or error during the run.
	["a player who joins while Running spectates on the platform and plays the next round"] = function()
		if fakeRoundSkipped("mid-round joiner") then
			return
		end
		RoundService._test.setDurations(1, 2, 1)
		local player = RoundTestPlayers.add("SpecPlayer")
		RoundService.start()

		waitForState("Running", 15)
		assert(player:GetAttribute("InRound") == true, "the round's player should be InRound")
		local joiner = RoundTestPlayers.add("SpecLateJoiner")
		assert(joiner:GetAttribute("InRound") ~= true, "a player who joined mid-round must not be InRound")
		-- Every change to the joiner's InRound is checked as it happens. The only time it may turn true is the next
		-- round's spawn, at the end of the next Lobby's countdown (Lobby, TimeLeft 0).
		local badSets: { string } = {}
		local connection = joiner:GetAttributeChangedSignal("InRound"):Connect(function()
			local roundState, timeLeft = state:GetAttribute("RoundState"), state:GetAttribute("TimeLeft")
			if joiner:GetAttribute("InRound") == true and not (roundState == "Lobby" and timeLeft == 0) then
				table.insert(badSets, `{tostring(roundState)} {tostring(timeLeft)}`)
			end
		end)
		local ok, err = pcall(function()
			-- placeSpectator runs on CharacterAdded, which may be deferred: wait for the joiner to arrive.
			local platform = RoundService._test.platform()
			assert(platform, "start() should have made Hall.LobbyPlatform")
			waitUntil("the joiner to reach the platform", 5, function()
				return (onPlatform(joiner, platform))
			end)
			assert(
				state:GetAttribute("RoundState") == "Running",
				"Running ended before the joiner reached the platform"
			)

			waitForState("Ended", 15)
			waitForState("Lobby", 15)
			waitForState("Running", 15)
		end)
		connection:Disconnect()
		if not ok then
			error(err, 0)
		end
		assert(#badSets == 0, `the mid-round joiner was set InRound too early, during: {table.concat(badSets, ", ")}`)
		assert(joiner:GetAttribute("InRound") == true, "the joiner should be InRound in the next round")
		assert(player:GetAttribute("InRound") == true, "the first player should be InRound in the next round too")
		local start = (workspace:FindFirstChild("Hall") :: Instance):FindFirstChild("Start") :: BasePart
		local offset = (joiner.Character :: Model):GetPivot().Position - start.Position
		assert(
			Vector3.new(offset.X, 0, offset.Z).Magnitude <= 3 and math.abs(offset.Y - 4) < 0.5,
			`the joiner should be spawned at Start for the next round, was {offset} off`
		)
	end,

	-- Sprint 23: one fake's LoadCharacter errors once at the round spawn. RoundService reports exactly one warning
	-- (through _test.onWarn) and no error, the round still starts for the others, and its retry spawns the fake.
	["LoadCharacter failing for one player warns once and the round still starts"] = function()
		if fakeRoundSkipped("LoadCharacter failure") then
			return
		end
		RoundService._test.setDurations(1, 2, 1)
		local failing = RoundTestPlayers.add("SpecLoadFails")
		local other = RoundTestPlayers.add("SpecOther")
		RoundTestPlayers.failLoadCharacter(failing, 1)
		RoundService.start()

		local warnings = collectWarnings(function()
			waitForState("Running", 15)
		end)
		assert(#warnings == 1, `expected exactly 1 warning, got {#warnings}: {table.concat(warnings, " | ")}`)
		assert(
			string.find(warnings[1], failing.Name, 1, true),
			`the warning should name {failing.Name}, got: {warnings[1]}`
		)
		assert(other:GetAttribute("InRound") == true, "the other player should be InRound when Running begins")
		assert(failing:GetAttribute("InRound") == true, "the retried LoadCharacter should have spawned the player")
		waitForState("Ended", 15)
	end,

	-- Sprint 24: LoadCharacter errors on all 3 tries. The fake has no character to fall back on, so it is dropped
	-- from the round: one warning per try (3), never InRound, and it watches from the platform while the other
	-- fake plays.
	["LoadCharacter failing on every try drops the player, who spectates"] = function()
		if fakeRoundSkipped("LoadCharacter failing on all tries") then
			return
		end
		RoundService._test.setDurations(1, 2, 1)
		local failing = RoundTestPlayers.add("SpecLoadFailsAll")
		local other = RoundTestPlayers.add("SpecOther")
		-- Drop the character add() gave it: a failed spawn keeps an existing body, and this test wants none.
		if failing.Character then
			failing.Character:Destroy()
			failing.Character = nil
		end
		RoundTestPlayers.failLoadCharacter(failing, 3)
		RoundService.start()

		local warnings = collectWarnings(function()
			waitForState("Running", 15)
		end)
		assert(#warnings == 3, `expected 3 warnings, got {#warnings}: {table.concat(warnings, " | ")}`)
		for _, warning in warnings do
			assert(
				string.find(warning, failing.Name, 1, true),
				`every warning should name {failing.Name}, got: {warning}`
			)
		end
		assert(other:GetAttribute("InRound") == true, "the other player should be InRound when Running begins")
		assert(failing:GetAttribute("InRound") ~= true, "the player whose spawns all failed must not be InRound")
		assert(failing.Character == nil, "the player should still have no character")
		waitForState("Ended", 15)
	end,

	-- Sprint 23: one fake's spawn outlasts the 10s spawn wait. Running begins anyway, the stuck fake is dropped from
	-- the round and watches from the platform; when its spawn finally finishes it stays a spectator (never InRound,
	-- never at Start) while the other fake plays the round out. Exactly one warning (the timeout) is reported.
	["a player whose spawn times out spectates and the round continues"] = function()
		if fakeRoundSkipped("spawn timeout") then
			return
		end
		RoundService._test.setDurations(1, 5, 1)
		local stuck = RoundTestPlayers.add("SpecStuck")
		local stayer = RoundTestPlayers.add("SpecStayer")
		RoundTestPlayers.holdLoadCharacter(stuck, true)
		local oldCharacter = stuck.Character
		RoundService.start()

		local badSets: { string } = {}
		local connection = stuck:GetAttributeChangedSignal("InRound"):Connect(function()
			if stuck:GetAttribute("InRound") == true then
				table.insert(
					badSets,
					`{tostring(state:GetAttribute("RoundState"))} {tostring(state:GetAttribute("TimeLeft"))}`
				)
			end
		end)
		local ok, err = pcall(function()
			local warnings = collectWarnings(function()
				waitForState("Running", 20)
			end)
			assert(#warnings == 1, `expected exactly 1 warning, got {#warnings}: {table.concat(warnings, " | ")}`)
			assert(
				string.find(warnings[1], stuck.Name, 1, true),
				`the warning should name {stuck.Name}, got: {warnings[1]}`
			)
			assert(stayer:GetAttribute("InRound") == true, "the other player should be InRound when Running begins")
			assert(stuck:GetAttribute("InRound") ~= true, "the timed-out player must not be InRound")
			local platform = RoundService._test.platform()
			assert(platform, "start() should have made Hall.LobbyPlatform")
			assertOnPlatform(stuck, platform)

			-- The slow spawn finishes mid-round: the new character must go to the platform, not Start.
			RoundTestPlayers.holdLoadCharacter(stuck, false)
			waitUntil("the late character to reach the platform", 5, function()
				return stuck.Character ~= nil and stuck.Character ~= oldCharacter and (onPlatform(stuck, platform))
			end)
			assert(state:GetAttribute("RoundState") == "Running", "Running ended before the late spawn finished")
			-- A frame later the finished spawn must still not have moved them or set InRound.
			RunService.Heartbeat:Wait()
			assertOnPlatform(stuck, platform)

			waitForState("Ended", 15, function()
				assert(stayer:GetAttribute("InRound") == true, "the stayer should stay InRound all through Running")
			end)
			waitForState("Lobby", 15)
		end)
		connection:Disconnect()
		if not ok then
			error(err, 0)
		end
		assert(#badSets == 0, `the timed-out player was set InRound during: {table.concat(badSets, ", ")}`)
	end,

	-- Sprint 23: a fake dies mid-round (Health = 0). Its InRound clears and stays clear, the other fake stays InRound,
	-- and the round ends normally: Running counts down to its last second, then Ended and the next Lobby.
	["a player who dies mid-round leaves InRound and the round ends normally"] = function()
		if fakeRoundSkipped("mid-round death") then
			return
		end
		RoundService._test.setDurations(1, 3, 1)
		local victim = RoundTestPlayers.add("SpecVictim")
		local stayer = RoundTestPlayers.add("SpecStayer")
		RoundService.start()

		waitForState("Running", 15)
		assert(victim:GetAttribute("InRound") == true, "the victim should be InRound when Running begins")
		assert(RoundTestPlayers.kill(victim), "the victim should have a character to kill")
		waitUntil("the dead player's InRound to clear", 5, function()
			return victim:GetAttribute("InRound") == false
		end)
		assert(state:GetAttribute("RoundState") == "Running", "Running ended before the death was handled")

		local lowestRunningTime = math.huge
		waitForState("Ended", 15, function()
			assert(victim:GetAttribute("InRound") == false, "the dead player must not be InRound again this round")
			assert(stayer:GetAttribute("InRound") == true, "the stayer should stay InRound all through Running")
			local timeLeft = state:GetAttribute("TimeLeft")
			if state:GetAttribute("RoundState") == "Running" and type(timeLeft) == "number" then
				lowestRunningTime = math.min(lowestRunningTime, timeLeft)
			end
		end)
		assert(lowestRunningTime <= 1, `Running should run out its clock, lowest TimeLeft {lowestRunningTime}`)
		waitForState("Lobby", 15, function()
			for _, player in { victim, stayer } do
				assert(player:GetAttribute("InRound") == false, `{player.Name} should not be InRound in Ended`)
			end
		end)
		assert(victim:GetAttribute("Escaped") ~= true, "dying must not count as escaping")
	end,

	-- Sprint 23: RoundTestPlayers.attach refuses when RunService:IsStudio() is false. In Studio this uses
	-- _test.pretendLiveServer, which can only make the check stricter. A refused attach leaves RoundService on the
	-- Players service, and add() still refuses.
	["RoundTestPlayers refuses to attach outside Studio"] = function()
		RoundService.stop()
		RoundTestPlayers.detach()
		local inStudio = RunService:IsStudio()
		if inStudio then
			RoundTestPlayers._test.pretendLiveServer(true)
		end
		local ok = pcall(RoundTestPlayers.attach, RoundService)
		local addOk = pcall(RoundTestPlayers.add, "SpecIntruder")
		RoundTestPlayers._test.pretendLiveServer(false)
		assert(not ok, "attach() should error when the server isn't Studio")
		assert(not addOk, "add() should refuse after a refused attach()")
		assert(RoundService._test.usingDefaultSource(), "a refused attach() must not swap RoundService's player source")
		if inStudio then
			-- The pretend flag is off again, so a Studio attach works, and detach puts the Players service back.
			RoundTestPlayers.attach(RoundService)
			assert(not RoundService._test.usingDefaultSource(), "attach() in Studio should swap the player source")
			RoundTestPlayers.detach()
			assert(RoundService._test.usingDefaultSource(), "detach() should restore the Players service")
		end
	end,
}

-- The runner has no beforeEach/afterEach hooks, so each test is wrapped: fresh state before, cleanup after.
-- Sprint 21: the whole of each wrapped test, setup and cleanup included, fails if RoundService warns or errors.
local wrapped = {}
for name, test in tests do
	wrapped[name] = function()
		withoutRoundServiceLogs(function()
			beforeEach()
			local ok, err = pcall(test)
			afterEach()
			if not ok then
				error(err, 0)
			end
		end)
	end
end
return wrapped

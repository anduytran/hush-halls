--!strict
-- Round loop: Lobby (15s) -> Running (up to 120s) -> Ended (5s) -> Lobby. Studio specs can shorten these
-- with RoundService._test.setDurations.
-- Players who touch Hall.Exit while Running escape: +10 Coins and a teleport to the lobby platform above Start.
-- Player attribute InRound is true while a participant is alive and hasn't escaped; Monster and NoiseService
-- only hear, kill and drown InRound players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)

local LOBBY_TIME = 15
local RUN_TIME = 120
local ENDED_TIME = 5
local ESCAPE_REWARD = 10
local PLATFORM_HEIGHT = 30
local TICK = 0.25
local LOAD_ATTEMPTS = 3
local LOAD_RETRY_DELAY = 1
local SPAWN_TIMEOUT = 10
local HALL_TIMEOUT = 10 -- how long start() waits for Hall.Start and Hall.Exit
local MIN_TEST_DURATION = 0.5

local RoundService = {}

local State = GameState.State
local started = false

-- Counts rounds, so a Died handler from an earlier round can't mark anyone dead in this one.
local round = 0
-- Players taking part in the current round, and how their round went.
local participants: { [Player]: boolean } = {}
local dead: { [Player]: boolean } = {}
-- True while the round's players are being spawned at Start (RoundState is still Lobby then).
local spawning = false
-- What start() set up, so stop() can undo it.
local connections: { RBXScriptConnection } = {}
local loop: thread? = nil
-- Bumped by stop(), so a start() still waiting for the hall gives up instead of starting after it.
local generation = 0
-- Where spectators and escaped players wait; set by start().
local platform: BasePart? = nil
-- Phase lengths in seconds. Always the constants above, unless a Studio spec calls _test.setDurations.
-- Each phase reads its length when it begins.
local lobbyTime: number = LOBBY_TIME
local runTime: number = RUN_TIME
local endedTime: number = ENDED_TIME

local function setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats
	leaderstats.Parent = player
end

local function addCoins(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		-- VIP pass sets CoinMultiplier = 2; anything that isn't a number >= 1 counts as 1.
		local multiplier = player:GetAttribute("CoinMultiplier")
		if type(multiplier) ~= "number" or multiplier ~= multiplier or multiplier < 1 or multiplier == math.huge then
			multiplier = 1
		end
		coins.Value += math.round(amount * multiplier)
	end
end

local function makePlatform(hall: Instance, start: BasePart): BasePart
	local existing = hall:FindFirstChild("LobbyPlatform")
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "LobbyPlatform"
	part.Anchored = true
	part.Size = Vector3.new(40, 1, 40)
	part.CFrame = CFrame.new(start.Position + Vector3.new(0, PLATFORM_HEIGHT, 0))
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(90, 90, 110)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Parent = hall
	return part
end

-- Alive, still in the hall, and hasn't escaped.
local function isActive(player: Player): boolean
	return participants[player] == true and not dead[player] and not player:GetAttribute("Escaped")
end

local function roundOver(): boolean
	for player in participants do
		if player.Parent == Players and isActive(player) then
			return false
		end
	end
	return true
end

local function sendToPlatform(player: Player)
	local character = player.Character
	if character and platform then
		local offset = Vector3.new(math.random(-12, 12), 4, math.random(-12, 12))
		character:PivotTo(CFrame.new(platform.Position + offset))
	end
end

-- Late joiners and respawned dead players watch from the platform, out of the monster's way.
-- Sprint-3 fix: this also covers players who join while the round is spawning (still Lobby).
local function placeSpectator(player: Player, character: Model)
	if (State:GetAttribute("RoundState") ~= "Running" and not spawning) or isActive(player) then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	if character.Parent and player.Character == character and not isActive(player) then
		sendToPlatform(player)
	end
end

-- LoadCharacter can fail (e.g. the player is leaving); retry a few times before giving up.
local function loadCharacter(player: Player): Model?
	for attempt = 1, LOAD_ATTEMPTS do
		if player.Parent ~= Players then
			return nil
		end
		local ok, err = pcall(player.LoadCharacter, player)
		if ok and player.Character then
			return player.Character
		end
		warn(`[RoundService] LoadCharacter failed for {player.Name} (attempt {attempt}): {err}`)
		task.wait(LOAD_RETRY_DELAY)
	end
	return player.Character
end

-- Undoes start(). Used by stop() and by a start() whose setup failed.
local function teardown()
	generation += 1
	if loop then
		task.cancel(loop)
		loop = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	round += 1 -- spawns still running from the old loop see a newer round and give up
	table.clear(participants)
	table.clear(dead)
	spawning = false
	platform = nil -- Sprint-5 fix: a stopped service holds no platform; start() finds or makes it again
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InRound", false)
	end
	started = false
end

function RoundService.start()
	if started then
		return
	end
	started = true
	local myGeneration = generation

	-- HallBuilder is only required when there's no hall, so a broken builder can't stop this module loading.
	-- If setup fails, started is cleared so a later start() can try again.
	local hallOk, hall = pcall(function()
		return workspace:FindFirstChild("Hall") or require(script.Parent.Map.HallBuilder).build()
	end)
	local foundStart = if hallOk and hall then hall:WaitForChild("Start", HALL_TIMEOUT) else nil
	local foundExit = if hallOk and hall then hall:WaitForChild("Exit", HALL_TIMEOUT) else nil
	if generation ~= myGeneration then
		return -- stop() was called while this was waiting
	end
	if not (foundStart and foundStart:IsA("BasePart") and foundExit and foundExit:IsA("BasePart")) then
		started = false
		error(if hallOk then "Hall has no Start and Exit parts" else `couldn't build the hall: {hall}`)
	end
	local start = foundStart :: BasePart
	local exit = foundExit :: BasePart

	-- Sprint-5 fix: if anything below errors, what it already set up is undone and started is cleared,
	-- so main.server's retry starts clean instead of registering the connections a second time.
	-- Sprint-6 fix: each setup step runs in its own small pcall instead of one big one. A failing step does
	-- the same rollback (teardown) and the error names the step that failed.
	-- Sprint-7 fix: no test-only branch here. Each step first calls RoundService._test.beforeStep, a no-op unless a
	-- spec swaps it (via _test.failStep) to make a step fail.
	local function step(name: string, fn: () -> ())
		local ok, err = pcall(function()
			RoundService._test.beforeStep(name)
			fn()
		end)
		if not ok then
			teardown()
			error(`start() failed at {name}: {err}`, 0)
		end
	end

	step("the lobby platform", function()
		platform = makePlatform(hall, start)
	end)

	-- Sprint-7 fix: onPlayerAdded is defined inside its step, so it's covered by the step's pcall and rollback.
	step("player setup", function()
		local function onPlayerAdded(player: Player)
			setupLeaderstats(player)
			player:SetAttribute("InRound", false)
			table.insert(
				connections,
				player.CharacterAdded:Connect(function(character)
					placeSpectator(player, character)
				end)
			)
		end

		for _, player in Players:GetPlayers() do
			onPlayerAdded(player)
		end
		table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
		table.insert(
			connections,
			Players.PlayerRemoving:Connect(function(player)
				participants[player] = nil
				dead[player] = nil
			end)
		)
	end)

	step("the exit", function()
		table.insert(
			connections,
			exit.Touched:Connect(function(hit)
				if State:GetAttribute("RoundState") ~= "Running" then
					return
				end
				local character = hit:FindFirstAncestorOfClass("Model")
				if not character then
					return
				end
				local player = Players:GetPlayerFromCharacter(character)
				if not player or not isActive(player) then
					return
				end
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid or humanoid.Health <= 0 then
					return
				end
				player:SetAttribute("Escaped", true)
				player:SetAttribute("InRound", false)
				addCoins(player, ESCAPE_REWARD)
				sendToPlatform(player)
			end)
		)
	end)

	-- Sprint-7 fix: spawnAtStart is defined inside the round loop's step, so it's covered by its pcall and rollback.
	step("the round loop", function()
		local function spawnAtStart(player: Player, thisRound: number)
			local character = loadCharacter(player)
			if round ~= thisRound or player.Parent ~= Players then
				return
			end
			if not character then
				-- Couldn't give them a body: drop them from the round so it isn't held open waiting for them.
				participants[player] = nil
				return
			end
			character:PivotTo(start.CFrame + Vector3.new(math.random(-2, 2), 4, math.random(-2, 2)))
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					if round == thisRound and participants[player] and not player:GetAttribute("Escaped") then
						dead[player] = true
						player:SetAttribute("InRound", false)
					end
				end)
			end
			player:SetAttribute("InRound", true)
		end

		loop = task.spawn(function()
			while true do
				-- Lobby: wait for at least one player, then count down.
				State:SetAttribute("RoundState", "Lobby")
				local lobbyLength = lobbyTime
				local left = lobbyLength
				while left > 0 do
					State:SetAttribute("TimeLeft", math.ceil(left))
					local pause = math.min(1, left)
					task.wait(pause)
					left = if #Players:GetPlayers() > 0 then left - pause else lobbyLength
				end
				State:SetAttribute("TimeLeft", 0)

				-- Spawn everyone at Start, then start the clock once they're in place.
				round += 1
				local thisRound = round
				table.clear(participants)
				table.clear(dead)
				for _, player in Players:GetPlayers() do
					participants[player] = true
					player:SetAttribute("Escaped", false)
				end
				spawning = true
				local pending = 0
				for player in participants do
					pending += 1
					task.spawn(function()
						local ok, err = pcall(spawnAtStart, player, thisRound)
						if not ok then
							warn(`[RoundService] couldn't spawn {player.Name}: {err}`)
							participants[player] = nil
						end
						pending -= 1
					end)
				end
				local spawnDeadline = os.clock() + SPAWN_TIMEOUT
				while pending > 0 and os.clock() < spawnDeadline do
					task.wait(0.1)
				end
				spawning = false
				-- Anyone who joined during the spawn wait and already has a body goes to the platform too.
				for _, player in Players:GetPlayers() do
					if not participants[player] then
						sendToPlatform(player)
					end
				end

				-- Running
				State:SetAttribute("RoundState", "Running")
				local runLength = runTime
				local endTime = os.clock() + runLength
				State:SetAttribute("TimeLeft", math.ceil(runLength))
				while os.clock() < endTime do
					task.wait(TICK)
					State:SetAttribute("TimeLeft", math.max(0, math.ceil(endTime - os.clock())))
					if roundOver() then
						break
					end
				end

				-- Ended
				State:SetAttribute("RoundState", "Ended")
				for _, player in Players:GetPlayers() do
					player:SetAttribute("InRound", false)
				end
				local endLeft = endedTime
				while endLeft > 0 do
					State:SetAttribute("TimeLeft", math.ceil(endLeft))
					local pause = math.min(1, endLeft)
					task.wait(pause)
					endLeft -= pause
				end
				table.clear(participants)
				table.clear(dead)
			end
		end)
	end)
end

-- TEST-ONLY: game code never calls this. Undoes start(): ends the loop, drops its connections and clears
-- the round, so each spec starts from fresh state. Sprint-4 fix: does nothing unless start() has run.
function RoundService.stop()
	if not started then
		return
	end
	teardown()
end

-- TEST-ONLY hooks, all in one table. Sprint-5 fix: grouped under RoundService._test so they can't be mistaken
-- for the module's API. A test server has no real Players, so the spec drives the spawn-wait join path
-- directly, and reads the loop thread to check that stop() really ended it.
RoundService._test = {
	setSpawning = function(on: boolean)
		spawning = on
	end,
	placeSpectator = function(player: Player, character: Model)
		placeSpectator(player, character)
	end,
	platform = function(): BasePart?
		return platform
	end,
	loop = function(): thread?
		return loop
	end,
	-- Sprint-7 fix: start() calls this before each setup step. It does nothing unless failStep swaps it.
	beforeStep = function(_name: string) end,
	-- Sprint-6 fix: makes the named start() setup step fail ("the lobby platform", "player setup", "the exit",
	-- "the round loop"); nil turns it off. Sprint-7 fix: it swaps beforeStep, so start() has no test branch.
	failStep = function(name: string?)
		RoundService._test.beforeStep = function(stepName: string)
			if name ~= nil and stepName == name then
				error("forced failure (test)")
			end
		end
	end,
	connectionCount = function(): number
		return #connections
	end,
	started = function(): boolean
		return started
	end,
	addCoins = function(player: Player, amount: number)
		addCoins(player, amount)
	end,
	-- Sprint 20: Studio only. Sets the Lobby, Running and Ended lengths (seconds, each >= 0.5) the loop uses from
	-- the next phase that begins; a phase already under way keeps its length. resetDurations() undoes it.
	setDurations = function(lobby: number, running: number, ended: number)
		if not RunService:IsStudio() then
			error("RoundService._test.setDurations only works in Studio", 2)
		end
		-- Each argument is checked on its own: a nil in a table constructor would be skipped.
		local function check(name: string, seconds: unknown)
			if
				type(seconds) ~= "number"
				or seconds ~= seconds
				or seconds < MIN_TEST_DURATION
				or seconds == math.huge
			then
				error(`RoundService._test.setDurations: {name} {tostring(seconds)} isn't a number of seconds >= 0.5`, 3)
			end
		end
		check("lobby", lobby)
		check("running", running)
		check("ended", ended)
		lobbyTime, runTime, endedTime = lobby, running, ended
	end,
	resetDurations = function()
		lobbyTime, runTime, endedTime = LOBBY_TIME, RUN_TIME, ENDED_TIME
	end,
	durations = function(): (number, number, number)
		return lobbyTime, runTime, endedTime
	end,
}

return RoundService

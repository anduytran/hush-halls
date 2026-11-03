--!strict
-- Round loop: Lobby (15s) -> Running (up to 120s) -> Ended (5s) -> Lobby.
-- Players who touch Hall.Exit while Running escape: +10 Coins and a teleport to the lobby platform above Start.
-- Player attribute InRound is true while a participant is alive and hasn't escaped; Monster and NoiseService
-- only hear, kill and drown InRound players.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
		coins.Value += amount
	end
end

local function makePlatform(hall: Instance, start: BasePart): BasePart
	local existing = hall:FindFirstChild("LobbyPlatform")
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local platform = Instance.new("Part")
	platform.Name = "LobbyPlatform"
	platform.Anchored = true
	platform.Size = Vector3.new(40, 1, 40)
	platform.CFrame = CFrame.new(start.Position + Vector3.new(0, PLATFORM_HEIGHT, 0))
	platform.Material = Enum.Material.SmoothPlastic
	platform.Color = Color3.fromRGB(90, 90, 110)
	platform.TopSurface = Enum.SurfaceType.Smooth
	platform.Parent = hall
	return platform
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
	local platform = makePlatform(hall, start)

	local function sendToPlatform(player: Player)
		local character = player.Character
		if character then
			local offset = Vector3.new(math.random(-12, 12), 4, math.random(-12, 12))
			character:PivotTo(CFrame.new(platform.Position + offset))
		end
	end

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

	local function onPlayerAdded(player: Player)
		setupLeaderstats(player)
		player:SetAttribute("InRound", false)
		-- Late joiners and respawned dead players watch from the platform, out of the monster's way.
		-- Sprint-3 fix: this also covers players who join while the round is spawning (still Lobby).
		table.insert(
			connections,
			player.CharacterAdded:Connect(function(character)
				if (State:GetAttribute("RoundState") ~= "Running" and not spawning) or isActive(player) then
					return
				end
				character:WaitForChild("HumanoidRootPart", 10)
				if character.Parent and player.Character == character and not isActive(player) then
					sendToPlatform(player)
				end
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

	loop = task.spawn(function()
		while true do
			-- Lobby: wait for at least one player, then count down.
			State:SetAttribute("RoundState", "Lobby")
			local left = LOBBY_TIME
			while left > 0 do
				State:SetAttribute("TimeLeft", left)
				task.wait(1)
				left = if #Players:GetPlayers() > 0 then left - 1 else LOBBY_TIME
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
			local endTime = os.clock() + RUN_TIME
			State:SetAttribute("TimeLeft", RUN_TIME)
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
			for endLeft = ENDED_TIME, 1, -1 do
				State:SetAttribute("TimeLeft", endLeft)
				task.wait(1)
			end
			table.clear(participants)
			table.clear(dead)
		end
	end)
end

-- Undoes start(): ends the loop, drops its connections and clears the round. Used by the specs
-- (sprint-3 fix: each test starts from fresh state) and safe to call when not started.
function RoundService.stop()
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
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InRound", false)
	end
	started = false
end

return RoundService

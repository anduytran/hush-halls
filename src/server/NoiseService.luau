--!strict
-- Sprint, noise and rising water.
-- Players walk (sneak) at 10 by default and sprint at 24 while the Sprint remote says so.
-- Every step the loudest InRound player's horizontal speed (measured on the server from position
-- changes) becomes State.Noise (0-1); while the round is Running, the water rises by
-- Noise * RISE_PER_SECOND. An InRound player whose HumanoidRootPart stays under the water, inside
-- its XZ footprint, for DROWN_TIME dies. The water drains when a round starts and in the lobby.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameState = require(ReplicatedStorage.Shared.GameState)

local WALK_SPEED = 10
local SPRINT_SPEED = 24
local TICK = 0.2
local RISE_PER_SECOND = 0.6
local DROWN_TIME = 2
local IDLE_SPEED = 0.5 -- below this horizontal speed counts as silent
local SNEAK_NOISE = 0.1 -- noise at full walk speed
local SPRINT_RATE_LIMIT = 10 -- Sprint events per second per player
local DEFAULT_FLOOR_SIZE = Vector3.new(200, 1, 200)
local MAX_PLAUSIBLE_SPEED = 60 -- faster than this between steps is a teleport, not footsteps

local NoiseService = {}

local State = GameState.State
local started = false

local sprinting: { [Player]: boolean } = {}
local sprintBudget: { [Player]: { tokens: number, last: number } } = {}
local underwaterSince: { [Player]: number } = {}
local lastPosition: { [Player]: { root: BasePart, position: Vector3 } } = {}

local function allowSprintEvent(player: Player): boolean
	local now = os.clock()
	local budget = sprintBudget[player]
	if not budget then
		budget = { tokens = SPRINT_RATE_LIMIT, last = now }
		sprintBudget[player] = budget
	end
	budget.tokens = math.min(SPRINT_RATE_LIMIT, budget.tokens + (now - budget.last) * SPRINT_RATE_LIMIT)
	budget.last = now
	if budget.tokens < 1 then
		return false
	end
	budget.tokens -= 1
	return true
end

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	if player:GetAttribute("InRound") ~= true then
		return nil, nil
	end
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function applySpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.WalkSpeed = if sprinting[player] then SPRINT_SPEED else WALK_SPEED
	end
end

-- Maps horizontal speed to noise: idle 0, walk (10) ~0.1, sprint (24) ~1.
local function noiseFromSpeed(speed: number): number
	if speed < IDLE_SPEED then
		return 0
	elseif speed <= WALK_SPEED then
		return SNEAK_NOISE * speed / WALK_SPEED
	end
	local t = (speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED)
	return math.clamp(SNEAK_NOISE + (1 - SNEAK_NOISE) * t, 0, 1)
end

local function getFloor(): BasePart?
	local hall = workspace:FindFirstChild("Hall")
	local floor = hall and hall:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return floor
	end
	return nil
end

local function createWater(): Part
	local water = Instance.new("Part")
	water.Name = "Water"
	water.Anchored = true
	water.CanCollide = false
	water.CanTouch = false
	water.CanQuery = false
	water.CastShadow = false
	water.Material = Enum.Material.SmoothPlastic
	water.Color = Color3.fromRGB(40, 110, 200)
	water.Transparency = 0.5
	water.Size = Vector3.new(1, 0, 1)
	water.Parent = workspace
	return water
end

-- Water level is measured in studs above the top of Hall.Floor.
local function waterTop(): number
	local floor = getFloor()
	local base = if floor then floor.Position.Y + floor.Size.Y / 2 else 0
	return base + (State:GetAttribute("WaterLevel") :: number? or 0)
end

-- True when the position is over the water, which covers Hall.Floor (or the default footprint).
local function insideFootprint(position: Vector3): boolean
	local floor = getFloor()
	local size = if floor then floor.Size else DEFAULT_FLOOR_SIZE
	local center = if floor then floor.Position else Vector3.zero
	return math.abs(position.X - center.X) <= size.X / 2 and math.abs(position.Z - center.Z) <= size.Z / 2
end

-- Horizontal speed since the last step, from where the server sees the character.
local function measureSpeed(player: Player, root: BasePart, dt: number): number
	local position = root.Position
	local previous = lastPosition[player]
	lastPosition[player] = { root = root, position = position }
	if not previous or previous.root ~= root or dt <= 0 then
		return 0
	end
	local delta = position - previous.position
	local speed = Vector2.new(delta.X, delta.Z).Magnitude / dt
	return if speed > MAX_PLAUSIBLE_SPEED then 0 else speed
end

local function updateWater(water: Part)
	local floor = getFloor()
	local level = State:GetAttribute("WaterLevel") :: number? or 0
	local footprint = if floor then floor.Size else DEFAULT_FLOOR_SIZE
	local base = if floor then floor.Position.Y + floor.Size.Y / 2 else 0
	local center = if floor then floor.Position else Vector3.zero
	if level <= 0.01 then
		water.Transparency = 1
		water.Size = Vector3.new(footprint.X, 0.05, footprint.Z)
		water.CFrame = CFrame.new(center.X, base - 0.025, center.Z)
		return
	end
	water.Transparency = 0.5
	water.Size = Vector3.new(footprint.X, level, footprint.Z)
	water.CFrame = CFrame.new(center.X, base + level / 2, center.Z)
end

local function step(water: Part, dt: number)
	local now = os.clock()
	local loudest = 0
	for _, player in Players:GetPlayers() do
		local humanoid, root = getHumanoid(player)
		if humanoid and root and humanoid.Health > 0 then
			loudest = math.max(loudest, noiseFromSpeed(measureSpeed(player, root, dt)))
		else
			lastPosition[player] = nil
		end
	end
	State:SetAttribute("Noise", loudest)

	if State:GetAttribute("RoundState") == "Running" then
		local level = State:GetAttribute("WaterLevel") :: number? or 0
		State:SetAttribute("WaterLevel", level + loudest * RISE_PER_SECOND * dt)
	end
	updateWater(water)

	local top = waterTop()
	local level = State:GetAttribute("WaterLevel") :: number? or 0
	for _, player in Players:GetPlayers() do
		local humanoid, root = getHumanoid(player)
		local submerged = root ~= nil and root.Position.Y < top and insideFootprint(root.Position)
		if humanoid and humanoid.Health > 0 and level > 0 and submerged then
			local since = underwaterSince[player]
			if not since then
				underwaterSince[player] = now
			elseif now - since >= DROWN_TIME then
				humanoid.Health = 0
				underwaterSince[player] = nil
			end
		else
			underwaterSince[player] = nil
		end
	end
end

function NoiseService.start()
	if started then
		return
	end
	started = true

	local sprintRemote = GameState.Remotes:WaitForChild("Sprint") :: RemoteEvent
	sprintRemote.OnServerEvent:Connect(function(player: Player, held: unknown)
		if typeof(held) ~= "boolean" then
			return
		end
		-- Releasing sprint is always honoured so a throttled client can't get stuck fast.
		if held and not allowSprintEvent(player) then
			return
		end
		sprinting[player] = held
		applySpeed(player)
	end)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			sprinting[player] = false
			underwaterSince[player] = nil
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.WalkSpeed = WALK_SPEED
			end
		end)
		if player.Character then
			applySpeed(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		sprinting[player] = nil
		sprintBudget[player] = nil
		underwaterSince[player] = nil
		lastPosition[player] = nil
	end)

	State:GetAttributeChangedSignal("RoundState"):Connect(function()
		local roundState = State:GetAttribute("RoundState")
		if roundState == "Running" or roundState == "Lobby" then
			State:SetAttribute("WaterLevel", 0)
			table.clear(underwaterSince)
		end
	end)

	local water = createWater()
	updateWater(water)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			step(water, now - last)
			last = now
		end
	end)
end

return NoiseService

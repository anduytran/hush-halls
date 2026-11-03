--!strict
-- Sprint, noise and rising water.
-- Players walk (sneak) at 10 by default and sprint at 24 while the Sprint remote says so.
-- Every tick the loudest player's horizontal speed becomes State.Noise (0-1); while the
-- round is Running, the water rises by Noise * RISE_PER_SECOND. Anyone whose
-- HumanoidRootPart stays under the water for DROWN_TIME dies.
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

local NoiseService = {}

local State = GameState.State
local started = false

local sprinting: { [Player]: boolean } = {}
local sprintBudget: { [Player]: { tokens: number, last: number } } = {}
local underwaterSince: { [Player]: number } = {}

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
	local humanoid = getHumanoid(player)
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

local function tick(water: Part, dt: number)
	local now = os.clock()
	local loudest = 0
	for _, player in Players:GetPlayers() do
		local humanoid, root = getHumanoid(player)
		if humanoid and root and humanoid.Health > 0 then
			local velocity = root.AssemblyLinearVelocity
			local speed = Vector2.new(velocity.X, velocity.Z).Magnitude
			loudest = math.max(loudest, noiseFromSpeed(speed))
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
		if humanoid and root and humanoid.Health > 0 and level > 0 and root.Position.Y < top then
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
	end)

	State:GetAttributeChangedSignal("RoundState"):Connect(function()
		if State:GetAttribute("RoundState") == "Running" then
			State:SetAttribute("WaterLevel", 0)
		end
	end)

	local water = createWater()
	updateWater(water)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			tick(water, now - last)
			last = now
		end
	end)
end

return NoiseService

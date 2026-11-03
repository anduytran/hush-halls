--!strict
-- The blind monster: hunts the loudest player by sound while a round is running.
-- Reads ReplicatedStorage.State attributes: Noise (0-1) and RoundState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monster = {}

local SIZE = 6
local HEARING_RANGE = 150
local SPRINT_SPEED = 14 -- horizontal speed above this counts as sprinting (heard first)
local HEARD_SPEED = 8 -- slower than this is sneaking: the monster can't hear it
local QUIET_NOISE = 0.05 -- below this the monster drifts to the last heard spot
local BASE_SPEED = 4
local NOISE_SPEED = 14
local DRIFT_SPEED = 2
local FLOOR_Y = 0
local PARK_DISTANCE = 200
local ARRIVE_DISTANCE = 1
local ENTRY_FALLBACK_Z = 120

local started = false

local function buildMonster(hall: Instance): Part
	local body = Instance.new("Part")
	body.Name = "Monster"
	body.Size = Vector3.new(SIZE, SIZE, SIZE)
	body.Color = Color3.fromRGB(70, 8, 8)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = true
	body.CastShadow = true

	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(1, 1, 0.2)
		eye.Color = Color3.fromRGB(255, 40, 20)
		eye.Material = Enum.Material.Neon
		eye.Anchored = false
		eye.CanCollide = false
		eye.CanTouch = false
		eye.Massless = true
		eye.CFrame = body.CFrame * CFrame.new(side * 1.5, 1.2, -SIZE / 2 - 0.1)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye
		eye.Parent = body
	end

	body.Parent = hall
	return body
end

local function anchorPosition(inst: Instance?): Vector3?
	if inst == nil then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

local function parkPosition(hall: Instance): Vector3
	local exitPos = anchorPosition(hall:FindFirstChild("Exit"))
	if exitPos then
		local startPos = anchorPosition(hall:FindFirstChild("Start"))
		local dir = Vector3.new(0, 0, 1)
		if startPos then
			local flat = Vector3.new(exitPos.X - startPos.X, 0, exitPos.Z - startPos.Z)
			if flat.Magnitude > 0.01 then
				dir = flat.Unit
			end
		end
		return exitPos + dir * PARK_DISTANCE
	end
	local startPos = anchorPosition(hall:FindFirstChild("Start")) or Vector3.zero
	return startPos + Vector3.new(0, 0, 250)
end

-- Where the monster enters the hall when a round starts (the parked spot is out of earshot).
local function entryPosition(hall: Instance): Vector3
	local exitPos = anchorPosition(hall:FindFirstChild("Exit"))
	if exitPos then
		return exitPos
	end
	local startPos = anchorPosition(hall:FindFirstChild("Start")) or Vector3.zero
	return startPos + Vector3.new(0, 0, ENTRY_FALLBACK_Z)
end

local function clampY(pos: Vector3): Vector3
	return Vector3.new(pos.X, math.max(pos.Y, FLOOR_Y + SIZE / 2), pos.Z)
end

-- Loudest alive player within range: sprinters beat walkers, then fastest wins.
-- Sneakers (below HEARD_SPEED) are silent.
local function findLoudest(from: Vector3): Vector3?
	local bestPos: Vector3? = nil
	local bestScore = -math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and root:IsA("BasePart") and humanoid.Health > 0 then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local distance = (root.Position - from).Magnitude
			if speed >= HEARD_SPEED and distance <= HEARING_RANGE then
				local score = speed + (if speed > SPRINT_SPEED then 1000 else 0)
				if score > bestScore then
					bestScore = score
					bestPos = root.Position
				end
			end
		end
	end
	return bestPos
end

local function moveToward(body: Part, target: Vector3, speed: number, dt: number): boolean
	local current = body.Position
	local goal = clampY(target)
	local offset = goal - current
	local distance = offset.Magnitude
	if distance <= ARRIVE_DISTANCE then
		return true
	end
	local step = math.min(speed * dt, distance)
	local nextPos = clampY(current + offset.Unit * step)
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > 0.01 then
		body.CFrame = CFrame.lookAt(nextPos, nextPos + flat.Unit)
	else
		body.CFrame = CFrame.new(nextPos) * body.CFrame.Rotation
	end
	return step >= distance
end

function Monster.start()
	if started then
		return
	end
	started = true

	local state = ReplicatedStorage:WaitForChild("State")
	local hall = workspace:WaitForChild("Hall")
	local body = buildMonster(hall)
	body.CFrame = CFrame.new(clampY(parkPosition(hall)))

	local lastHeard: Vector3? = nil
	local wasRunning = false

	body.Touched:Connect(function(hit)
		if state:GetAttribute("RoundState") ~= "Running" then
			return
		end
		local character = hit.Parent
		if character == nil then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and Players:GetPlayerFromCharacter(character) then
			humanoid.Health = 0
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local running = state:GetAttribute("RoundState") == "Running"
		if not running then
			if wasRunning or lastHeard ~= nil then
				body.CFrame = CFrame.new(clampY(parkPosition(hall)))
				lastHeard = nil
			end
			wasRunning = false
			return
		end
		if not wasRunning then
			body.CFrame = CFrame.new(clampY(entryPosition(hall)))
		end
		wasRunning = true

		local noise = state:GetAttribute("Noise")
		local level = math.clamp(if typeof(noise) == "number" then noise else 0, 0, 1)

		if level < QUIET_NOISE then
			-- Silence: drift to where it last heard someone, then wait there.
			if lastHeard and moveToward(body, lastHeard, DRIFT_SPEED, dt) then
				lastHeard = nil
			end
			return
		end

		local target = findLoudest(body.Position)
		if target then
			lastHeard = target
			moveToward(body, target, BASE_SPEED + level * NOISE_SPEED, dt)
		elseif lastHeard and moveToward(body, lastHeard, DRIFT_SPEED, dt) then
			lastHeard = nil
		end
	end)
end

return Monster

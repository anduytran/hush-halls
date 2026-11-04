--!strict
-- The blind monster: hunts the loudest player by sound while a round is running.
-- Reads ReplicatedStorage.State attributes: Noise (0-1) and RoundState, and the InRound player attribute.
-- It only touches (and kills) while Running; its round connections are dropped when the round ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local SpeedSampler = require(script.Parent.SpeedSampler)

local Monster = {}

local SIZE = 6
local HEARING_RANGE = 150
-- Above this speed you are sprinting and are chased before anyone walking. The gap up from HEARD_SPEED
-- (12-14) is on purpose: heard, but only a walker-level target, so the monster drifts toward you.
local SPRINT_SPEED = 14
-- At or above this speed the monster hears you. Walk speed is 10, so walkers stay silent; 12-14 = heard
-- but not sprinting; above 14 = sprint, chased first.
local HEARD_SPEED = 12
-- Sprint 29 fix: a player only counts as heard once they've stayed at or above HEARD_SPEED this long.
-- In a live soak one brief ~12 studs/s reading from a walker (wall corner or network jitter) made the monster
-- drift down the hall to that spot and kill the walker. A real sprinter (24) is over the line the whole time.
local HEAR_CONFIRM = 0.5
local QUIET_NOISE = 0.05 -- below this the monster drifts to the last heard spot
local BASE_SPEED = 4
local NOISE_SPEED = 14
local DRIFT_SPEED = 2
local FLOOR_Y = 0
local PARK_DISTANCE = 200
local ARRIVE_DISTANCE = 1
local ENTRY_FALLBACK_Z = 120
local HALL_WARN_INTERVAL = 30 -- seconds between "still waiting for the hall" warnings

type Sample = { root: BasePart, position: Vector3, speed: number }

local started = false
-- Latest position and server-measured horizontal speed of each InRound player.
local samples: { [Player]: Sample } = {}
-- When each player's speed last went up to HEARD_SPEED without dropping below it since.
local heardSince: { [any]: number } = {}
-- Sprint-3 fix: speed is averaged over ~0.5 s by the helper NoiseService also uses (samples under
-- 0.1 s apart are skipped), so a walker's uneven network updates no longer read as sprinting.
local sampler = SpeedSampler.new()

local function buildMonster(hall: Instance): Part
	local body = Instance.new("Part")
	body.Name = "Monster"
	body.Size = Vector3.new(SIZE, SIZE, SIZE)
	body.Color = Color3.fromRGB(70, 8, 8)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false -- turned on only while a round is Running
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

local function aliveRoot(player: Player): BasePart?
	if player:GetAttribute("InRound") ~= true then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Measures speed from where the server sees each character, not from the velocity the client reports.
local function sampleSpeeds()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = aliveRoot(player)
		if not root then
			samples[player] = nil
			heardSince[player] = nil
			sampler.forget(player)
			continue
		end
		local position = root.Position
		local speed = sampler.update(player, root, position, now)
		samples[player] = { root = root, position = position, speed = speed }
	end
	for player in samples do
		if player.Parent ~= Players then
			samples[player] = nil
			heardSince[player] = nil
			sampler.forget(player)
		end
	end
end

-- Loudest alive player within range: sprinters beat walkers, then fastest wins.
-- Anyone at or below walk speed (under HEARD_SPEED) is silent.
local function isHeard(speed: number): boolean
	return speed >= HEARD_SPEED
end

-- Records this reading and says whether the player has been heard for HEAR_CONFIRM seconds in a row.
local function confirmHeard(player: any, speed: number, now: number): boolean
	if not isHeard(speed) then
		heardSince[player] = nil
		return false
	end
	local since = heardSince[player]
	if not since then
		heardSince[player] = now
		return false
	end
	return now - since >= HEAR_CONFIRM
end

local function findLoudest(from: Vector3): Vector3?
	local bestPos: Vector3? = nil
	local bestScore = -math.huge
	local now = os.clock()
	for player, sample in samples do
		if player.Parent ~= Players or aliveRoot(player) ~= sample.root then
			heardSince[player] = nil
			continue
		end
		local speed = sample.speed
		local distance = (sample.position - from).Magnitude
		if confirmHeard(player, speed, now) and distance <= HEARING_RANGE then
			local score = speed + (if speed > SPRINT_SPEED then 1000 else 0)
			if score > bestScore then
				bestScore = score
				bestPos = sample.position
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

-- Builds the monster in the hall and follows RoundState from then on.
local function run(hall: Instance)
	local state = GameState.State
	local body = buildMonster(hall)
	body.CFrame = CFrame.new(clampY(parkPosition(hall)))

	local lastHeard: Vector3? = nil
	local connections: { RBXScriptConnection } = {}

	local function onTouched(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not character or not player or player:GetAttribute("InRound") ~= true then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end

	local function onHeartbeat(dt: number)
		sampleSpeeds()

		local noise = state:GetAttribute("Noise")
		local level = math.clamp(if typeof(noise) == "number" then noise else 0, 0, 1)

		if level < QUIET_NOISE then
			-- Silence: drift to where it last heard someone, then wait there.
			table.clear(heardSince)
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
	end

	local function endRound()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		table.clear(samples)
		table.clear(heardSince)
		sampler.clear()
		lastHeard = nil
		body.CanTouch = false
		body.CFrame = CFrame.new(clampY(parkPosition(hall)))
	end

	local function beginRound()
		endRound()
		body.CFrame = CFrame.new(clampY(entryPosition(hall)))
		body.CanTouch = true
		table.insert(connections, body.Touched:Connect(onTouched))
		table.insert(connections, RunService.Heartbeat:Connect(onHeartbeat))
	end

	local function onRoundState()
		if state:GetAttribute("RoundState") == "Running" then
			if #connections == 0 then
				beginRound()
			end
		elseif #connections > 0 then
			endRound()
		end
	end

	state:GetAttributeChangedSignal("RoundState"):Connect(onRoundState)
	onRoundState()
end

-- TEST-ONLY hooks, like RoundService._test: the table exists only in Studio, so it is not part of the API.
if RunService:IsStudio() then
	Monster._test = {
		isHeard = isHeard,
		-- Sprint 29: pass your own key (any table) as the player; clear with resetHeard.
		confirmHeard = confirmHeard,
		resetHeard = function()
			table.clear(heardSince)
		end,
		HEARD_SPEED = HEARD_SPEED,
		HEAR_CONFIRM = HEAR_CONFIRM,
		SPRINT_SPEED = SPRINT_SPEED,
	}
end

function Monster.start()
	if started then
		return
	end
	started = true

	-- Sprint-3 fix: wait for the hall in a task, so start() returns straight away even if the build failed.
	task.spawn(function()
		-- Keeps waiting after each warning: RoundService may still build the hall.
		-- Sprint-4 fix: warns every HALL_WARN_INTERVAL seconds, so a hall that never comes stays visible in the log.
		local hall = workspace:WaitForChild("Hall", HALL_WARN_INTERVAL)
		local waited = HALL_WARN_INTERVAL
		while not hall do
			warn(`[Monster] still waiting for Workspace.Hall ({waited}s)`)
			hall = workspace:WaitForChild("Hall", HALL_WARN_INTERVAL)
			waited += HALL_WARN_INTERVAL
		end
		local ok, err = pcall(run, hall)
		if not ok then
			warn(`[Monster] failed to start: {err}`)
		end
	end)
end

return Monster

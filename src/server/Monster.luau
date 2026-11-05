--!strict
-- The blind monster: hunts the loudest player by sound while a round is running.
-- Reads ReplicatedStorage.State attributes: Noise (0-1) and RoundState, and the InRound player attribute.
-- It only touches (and kills) while Running; its round connections are dropped when the round ends.
-- Sprint 36: it walks paths (PathfindingService) instead of through walls, stops to listen when it loses you,
-- and lunges when it is close to a heard player. Its look comes from Map.MonsterModel; the root part is invisible.
-- Sprint 37: with nobody heard it patrols random points (PATROL_AREAS) at DRIFT_SPEED instead of standing still,
-- it enters on the floor instead of at the Exit trigger's mid-height, and there is only ever one Monster/Body.
-- Sprint 37 (animation): the root carries `State` (Idle, Patrol, Chase, Lunge, Listen, Kill) and `Speed`
-- (measured flat studs/s) attributes. They are only for looks: src/client/MonsterAnimator.luau reads them.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local NoiseService = require(script.Parent.NoiseService)
local SpeedSampler = require(script.Parent.SpeedSampler)

local Monster = {}

-- Monster audio. Both are free ProSoundEffects Creator Store assets, checked to load in Studio.
local SOUNDS = {
	Growl = "rbxassetid://9113980507", -- "Creature Mix Giant Crab Monster Roar Growl 1", ~8.4 s, looped
	Scream = "rbxassetid://9113985848", -- "Creature Scream Piercing Pain Female 3", ~1.3 s, one-shot on a catch
}
local GROWL_ROLLOFF_MAX = 60
local GROWL_ROLLOFF_MIN = 8
local GROWL_VOLUME_DRIFT = 0.25 -- drifting, or waiting in silence
local GROWL_VOLUME_CHASE = 0.8 -- chasing a heard player
local SCREAM_VOLUME = 1
local SCREAM_ROLLOFF_MAX = 120

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

-- Sprint 36 (Routes, Exits and Dread): paths, listening and the lunge.
local AGENT_RADIUS = 3
local AGENT_HEIGHT = 9
local REPATH_INTERVAL = 0.5 -- never computes a path more often than this
local REPATH_DISTANCE = 8 -- the goal moving this far from where the path was aimed asks for a new one
local PATH_END_SLACK = 4 -- path used up and the goal is behind a wall but this close: counts as arrived
local LISTEN_TIME = 2 -- seconds it stands at the last heard spot before drifting
local LISTEN_TURN_RATE = math.rad(45) -- radians per second it turns while listening
local LUNGE_RANGE = 15 -- within this flat distance of a heard player it lunges
local LUNGE_BONUS = 8 -- extra studs/s while lunging

-- Sprint 37 fix: with nobody heard it used to stand still (QA: 20 s at the main exit). Now it patrols at
-- DRIFT_SPEED, pathfinding to random points in these floor areas. Interiors come from Map/HallBuilder.luau
-- (main hall segments A/B/C, back corridor, gym), shrunk ~4 studs from each wall so AGENT_RADIUS fits.
-- The gym stops short of the bleachers along its north wall.
-- Sprint 39: the school is ~1.7x longer, with five cross halls and four link rooms between the back corridor
-- and the main hall. Each cross hall and link room gets a small area down its middle (link rooms: the door
-- lane, clear of the desks), so it patrols every part of the map.
type Area = { name: string, x0: number, x1: number, z0: number, z1: number }
local PATROL_AREAS: { Area } = {
	{ name = "HallA", x0 = -8, x1 = 8, z0 = 4, z1 = 166 },
	{ name = "HallB", x0 = 4, x1 = 20, z0 = 174, z1 = 336 },
	{ name = "HallC", x0 = -8, x1 = 8, z0 = 344, z1 = 490 },
	{ name = "BackCorridor", x0 = -36, x1 = -32, z0 = 4, z1 = 486 },
	{ name = "Gym", x0 = -66, x1 = -46, z0 = 394, z1 = 454 },
	{ name = "CrossHall1", x0 = -22, x1 = -18, z0 = 24, z1 = 28 },
	{ name = "CrossHall2", x0 = -22, x1 = -18, z0 = 114, z1 = 118 },
	{ name = "CrossHall3", x0 = -22, x1 = -6, z0 = 254, z1 = 258 },
	{ name = "CrossHall4", x0 = -22, x1 = -18, z0 = 376, z1 = 380 },
	{ name = "CrossHall5", x0 = -22, x1 = -18, z0 = 478, z1 = 482 },
	{ name = "LinkRoom1", x0 = -22, x1 = -18, z0 = 66, z1 = 74 },
	{ name = "LinkRoom2", x0 = -22, x1 = -18, z0 = 144, z1 = 152 },
	{ name = "LinkRoom3", x0 = -22, x1 = -18, z0 = 404, z1 = 412 },
	{ name = "WindowRoom", x0 = -21, x1 = -19, z0 = 444, z1 = 460 },
}
local PATROL_MIN_LEG = 20 -- a new patrol point is at least this far away (flat), so it walks somewhere
local PATROL_PICK_TRIES = 8
local STUCK_CHECK = 5 -- seconds; patrolling and moved under STUCK_MOVE in that time picks a new point
local STUCK_MOVE = 2
local ENTRY_INSET = 6 -- enters this far in from the Exit toward Start, clear of the end wall

-- Animation attributes (Sprint 37).
local KILL_ANIM_TIME = 1.2 -- State stays Kill this long after a catch
local SPEED_SMOOTH_RATE = 8 -- per second; measured speed is smoothed so path corners don't flicker it
local SPEED_STEP = 0.5 -- Speed is written rounded to this, and only when it changes
type AnimState = "Idle" | "Patrol" | "Chase" | "Lunge" | "Listen" | "Kill"

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
	body.Transparency = 1 -- Map.MonsterModel is the visible creature
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false -- turned on only while a round is Running
	body.CastShadow = false
	body.Parent = hall
	return body
end

-- Fallback look if Map.MonsterModel is missing or fails: the old red cube with glowing eyes.
local function addFallbackLook(body: Part)
	body.Transparency = 0
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
end

-- Exactly one Body: attach already replaces its own Body, and anything else named Body is removed too.
-- (QA's "75 parts" was 75 descendants: 37 parts, 37 WeldConstraints and the Model.)
local function attachModel(body: Part)
	local ok, err = pcall(function()
		local MonsterModel = require(script.Parent.Map.MonsterModel) :: any
		local model = MonsterModel.attach(body)
		for _, child in body:GetChildren() do
			if child.Name == "Body" and child ~= model then
				child:Destroy()
			end
		end
	end)
	if not ok then
		warn(`[Monster] MonsterModel.attach failed, using the fallback cube: {err}`)
		addFallbackLook(body)
	end
end

-- 3D sound on the monster's body. Returns nil (with a warning) if it can't be made; a SoundId that fails to
-- load does not error, it just stays silent.
local function makeSound(body: Part, name: string, soundId: string, looped: boolean, maxDistance: number): Sound?
	local ok, result = pcall(function()
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = soundId
		sound.Looped = looped
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = GROWL_ROLLOFF_MIN
		sound.RollOffMaxDistance = maxDistance
		sound.Parent = body
		return sound
	end)
	if not ok then
		warn(`[Monster] could not create {name} sound: {result}`)
		return nil
	end
	return result
end

-- Play/Stop never decide game state, so any failure here is only warned about.
local function safeSound(sound: Sound?, action: (Sound) -> ())
	if not sound then
		return
	end
	local ok, err = pcall(action, sound)
	if not ok then
		warn(`[Monster] {sound.Name} sound failed: {err}`)
	end
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

-- Standing height: the root's centre when its bottom is on the floor.
local function onFloor(pos: Vector3): Vector3
	return Vector3.new(pos.X, FLOOR_Y + SIZE / 2, pos.Z)
end

-- Where the monster enters the hall when a round starts (the parked spot is out of earshot).
-- Sprint 37 fix: it used the Exit trigger's centre, which is Y 10 (the trigger spans Y 0..20) and 2 studs off
-- the end wall, so it hung in the air at (0, 10, 298). Now it stands on the floor, ENTRY_INSET in toward Start.
local function entryPosition(hall: Instance): Vector3
	local exitPos = anchorPosition(hall:FindFirstChild("Exit"))
	if exitPos then
		local startPos = anchorPosition(hall:FindFirstChild("Start"))
		local inward = Vector3.zero
		if startPos then
			local flat = Vector3.new(startPos.X - exitPos.X, 0, startPos.Z - exitPos.Z)
			if flat.Magnitude > ENTRY_INSET then
				inward = flat.Unit * ENTRY_INSET
			end
		end
		return onFloor(exitPos + inward)
	end
	local startPos = anchorPosition(hall:FindFirstChild("Start")) or Vector3.zero
	return onFloor(startPos + Vector3.new(0, 0, ENTRY_FALLBACK_Z))
end

local function clampY(pos: Vector3): Vector3
	return Vector3.new(pos.X, math.max(pos.Y, FLOOR_Y + SIZE / 2), pos.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A random standing spot in a random PATROL_AREAS entry, at least PATROL_MIN_LEG from `from` when it can.
local function patrolPoint(from: Vector3, rng: Random): Vector3
	local point = from
	for _ = 1, PATROL_PICK_TRIES do
		local area = PATROL_AREAS[rng:NextInteger(1, #PATROL_AREAS)]
		point = onFloor(Vector3.new(rng:NextNumber(area.x0, area.x1), 0, rng:NextNumber(area.z0, area.z1)))
		if flatDistance(point, from) >= PATROL_MIN_LEG then
			break
		end
	end
	return point
end

-- Chase speed: faster the louder the hall is, plus the lunge bonus when within LUNGE_RANGE.
local function chaseSpeed(level: number, distance: number): number
	return BASE_SPEED + level * NOISE_SPEED + (if distance <= LUNGE_RANGE then LUNGE_BONUS else 0)
end

-- Whether a new path should be computed now. Throttled to REPATH_INTERVAL; then it is needed when there is no
-- path aim yet, the last one failed, or the goal moved REPATH_DISTANCE or more from where the path was aimed.
local function shouldRepath(now: number, lastCompute: number, aim: Vector3?, goal: Vector3, failed: boolean): boolean
	if now - lastCompute < REPATH_INTERVAL then
		return false
	end
	if aim == nil or failed then
		return true
	end
	return flatDistance(aim, goal) >= REPATH_DISTANCE
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
		-- Sprint 34: a hazard (puddle splash, plank creak) makes a player heard at once while its noise lasts,
		-- scored like moving at that fraction of sprint speed (so a sprinter is still chased first).
		local hazard = NoiseService.noiseFloor(player)
		local heard = confirmHeard(player, speed, now)
		if (heard or hazard > 0) and distance <= HEARING_RANGE then
			local score = math.max(if heard then speed else 0, hazard * SPRINT_SPEED)
				+ (if speed > SPRINT_SPEED then 1000 else 0)
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
	-- Only one monster: drop any left in the hall (e.g. saved into the place from an old playtest).
	for _, child in hall:GetChildren() do
		if child.Name == "Monster" then
			child:Destroy()
		end
	end
	local body = buildMonster(hall)
	body.CFrame = CFrame.new(onFloor(parkPosition(hall)))
	attachModel(body)

	local lastHeard: Vector3? = nil
	local listenUntil: number? = nil
	local connections: { RBXScriptConnection } = {}

	-- Path state. One Path object; only one ComputeAsync runs at a time (computing).
	local path = PathfindingService:CreatePath({
		AgentRadius = AGENT_RADIUS,
		AgentHeight = AGENT_HEIGHT,
		AgentCanJump = false,
		AgentCanClimb = false,
	})
	local generation = 0 -- bumped at round end so a late path result from the old round is dropped
	local computing = false
	local lastCompute = -math.huge
	local pathAim: Vector3? = nil -- the goal the current (or pending) path was computed for
	local waypoints: { Vector3 }? = nil
	local waypointIndex = 1
	local pathFailed = false
	local pathWarned = false

	-- Patrol state (Sprint 37).
	local rng = Random.new()
	local mode: "chase" | "drift" | "patrol" | "listen" | nil = nil
	local patrolGoal: Vector3? = nil
	local stuckFrom = Vector3.zero
	local stuckAt = 0

	-- Animation attributes (Sprint 37).
	local killUntil = 0
	local smoothSpeed = 0

	local function setAnim(animState: AnimState, speed: number)
		if body:GetAttribute("State") ~= animState then
			body:SetAttribute("State", animState)
		end
		local rounded = math.floor(speed / SPEED_STEP + 0.5) * SPEED_STEP
		if body:GetAttribute("Speed") ~= rounded then
			body:SetAttribute("Speed", rounded)
		end
	end
	setAnim("Idle", 0)

	-- Drops the current path. Bumping generation also drops a path still being computed for the old goal,
	-- so it can't land as the waypoints for a new one.
	local function clearPath()
		generation += 1
		pathAim = nil
		waypoints = nil
		waypointIndex = 1
		pathFailed = false
		lastCompute = -math.huge
	end

	local function setMode(newMode: "chase" | "drift" | "patrol" | "listen" | nil, now: number)
		if newMode == mode then
			return
		end
		mode = newMode
		clearPath()
		patrolGoal = nil
		stuckFrom = body.Position
		stuckAt = now
	end

	local function requestPath(goal: Vector3, now: number)
		if computing then
			return
		end
		computing = true
		lastCompute = now
		pathAim = goal
		local requestGeneration = generation
		local from = body.Position
		task.spawn(function()
			local ok, err = pcall(function()
				path:ComputeAsync(from, goal)
			end)
			computing = false
			if requestGeneration ~= generation then
				return
			end
			if ok and path.Status == Enum.PathStatus.Success then
				local points = {}
				for _, waypoint in path:GetWaypoints() do
					table.insert(points, waypoint.Position)
				end
				waypoints = points
				-- The first waypoint is where it already stands.
				waypointIndex = if #points >= 2 then 2 else 1
				pathFailed = false
			else
				if not ok and not pathWarned then
					pathWarned = true
					warn(`[Monster] path compute failed, moving directly: {err}`)
				end
				waypoints = nil
				pathFailed = true
			end
		end)
	end

	-- True when nothing solid stands between the monster and the goal (players and the monster are ignored).
	local function hasClearLine(from: Vector3, goal: Vector3): boolean
		local ignore: { Instance } = { body }
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignore
		params.RespectCanCollide = true
		local direction = Vector3.new(goal.X, from.Y, goal.Z) - from
		return workspace:Raycast(from, direction, params) == nil
	end

	-- Moves one step toward goal along the path. Returns true once it has arrived.
	-- Moves straight at the goal only when the path failed (and allowDirect), or when the path is used up and
	-- the line is clear. Patrol passes allowDirect = false and picks another point instead.
	local function navigate(goal: Vector3, speed: number, dt: number, now: number, allowDirect: boolean): boolean
		local position = body.Position
		if flatDistance(position, goal) <= ARRIVE_DISTANCE then
			return true
		end
		if shouldRepath(now, lastCompute, pathAim, goal, pathFailed) then
			requestPath(goal, now)
		end
		if pathFailed then
			if allowDirect then
				return moveToward(body, goal, speed, dt)
			end
			return false
		end
		local points = waypoints
		if not points then
			return false -- the first path is still being computed: hold still rather than cut through walls
		end
		while waypointIndex <= #points do
			local point = points[waypointIndex] + Vector3.new(0, SIZE / 2, 0)
			if flatDistance(position, point) <= ARRIVE_DISTANCE then
				waypointIndex += 1
			else
				moveToward(body, point, speed, dt)
				return false
			end
		end
		-- Path used up but the goal is not reached (it moved, or the path ended just short).
		if hasClearLine(position, goal) then
			return moveToward(body, goal, speed, dt)
		end
		if flatDistance(position, goal) <= PATH_END_SLACK then
			return true
		end
		pathAim = nil -- ask for a fresh path at the next allowed time
		return false
	end

	local growl = makeSound(body, "Growl", SOUNDS.Growl, true, GROWL_ROLLOFF_MAX)
	local scream = makeSound(body, "Scream", SOUNDS.Scream, false, SCREAM_ROLLOFF_MAX)
	safeSound(growl, function(sound)
		sound.Volume = GROWL_VOLUME_DRIFT
	end)
	safeSound(scream, function(sound)
		sound.Volume = SCREAM_VOLUME
	end)
	local growlChasing = false

	-- Louder while chasing a heard player than while drifting. Only writes Volume when the mode changes.
	local function setGrowlChasing(chasing: boolean)
		if chasing == growlChasing then
			return
		end
		growlChasing = chasing
		safeSound(growl, function(sound)
			sound.Volume = if chasing then GROWL_VOLUME_CHASE else GROWL_VOLUME_DRIFT
		end)
	end

	local function onTouched(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not character or not player or player:GetAttribute("InRound") ~= true then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
			killUntil = os.clock() + KILL_ANIM_TIME
			setAnim("Kill", smoothSpeed)
			safeSound(scream, function(sound)
				sound:Play()
			end)
		end
	end

	-- One frame of movement. Returns the animation state for what it did.
	local function step(dt: number, now: number): AnimState
		sampleSpeeds()

		local noise = state:GetAttribute("Noise")
		local level = math.clamp(if typeof(noise) == "number" then noise else 0, 0, 1)

		local target: Vector3? = nil
		if level < QUIET_NOISE then
			table.clear(heardSince) -- silence: nobody is heard
		else
			target = findLoudest(body.Position)
		end
		setGrowlChasing(target ~= nil)

		if target then
			listenUntil = nil -- hearing someone ends a listen pause at once
			lastHeard = target
			setMode("chase", now)
			local distance = flatDistance(body.Position, target)
			navigate(target, chaseSpeed(level, distance), dt, now, true)
			return if distance <= LUNGE_RANGE then "Lunge" else "Chase"
		end

		local until_ = listenUntil
		if until_ then
			-- Lost them: stand at the last heard spot and slowly turn, listening.
			if now < until_ then
				setMode("listen", now)
				body.CFrame = body.CFrame * CFrame.Angles(0, LISTEN_TURN_RATE * dt, 0)
				return "Listen"
			end
			listenUntil = nil
		end

		-- Drift to where it last heard someone, then listen there for LISTEN_TIME.
		local heardSpot = lastHeard
		if heardSpot then
			setMode("drift", now)
			if navigate(heardSpot, DRIFT_SPEED, dt, now, true) then
				lastHeard = nil
				listenUntil = now + LISTEN_TIME
				setMode("listen", now)
				return "Listen"
			end
			return "Patrol"
		end

		-- Nothing heard: patrol to random points across the hall, corridor and gym.
		setMode("patrol", now)
		local position = body.Position
		if now - stuckAt >= STUCK_CHECK then
			if patrolGoal and flatDistance(position, stuckFrom) < STUCK_MOVE then
				patrolGoal = nil -- stalled (unreachable point or a bad path): pick another
				clearPath()
			end
			stuckFrom = position
			stuckAt = now
		end
		local goal = patrolGoal
		if goal == nil or pathFailed then
			if pathFailed then
				clearPath()
			end
			goal = patrolPoint(position, rng)
			patrolGoal = goal
		end
		if navigate(goal, DRIFT_SPEED, dt, now, false) then
			patrolGoal = nil
			clearPath()
		end
		return "Patrol"
	end

	local function onHeartbeat(dt: number)
		local now = os.clock()
		local before = body.Position
		local animState = step(dt, now)
		local speed = if dt > 0 then flatDistance(body.Position, before) / dt else 0
		smoothSpeed += (speed - smoothSpeed) * (1 - math.exp(-SPEED_SMOOTH_RATE * dt))
		setAnim(if now < killUntil then "Kill" else animState, smoothSpeed)
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
		listenUntil = nil
		mode = nil
		patrolGoal = nil
		clearPath() -- also bumps generation, so a late path result from this round is dropped
		body.CanTouch = false
		body.CFrame = CFrame.new(onFloor(parkPosition(hall)))
		setGrowlChasing(false)
		safeSound(growl, function(sound)
			sound:Stop()
		end)
		killUntil = 0
		smoothSpeed = 0
		setAnim("Idle", 0)
	end

	local function beginRound()
		endRound()
		body.CFrame = CFrame.new(entryPosition(hall))
		body.CanTouch = true
		table.insert(connections, body.Touched:Connect(onTouched))
		table.insert(connections, RunService.Heartbeat:Connect(onHeartbeat))
		safeSound(growl, function(sound)
			sound:Play()
		end)
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
		SOUNDS = SOUNDS,
		GROWL_VOLUME_DRIFT = GROWL_VOLUME_DRIFT,
		GROWL_VOLUME_CHASE = GROWL_VOLUME_CHASE,
		-- Sprint 36
		chaseSpeed = chaseSpeed,
		shouldRepath = shouldRepath,
		BASE_SPEED = BASE_SPEED,
		NOISE_SPEED = NOISE_SPEED,
		LISTEN_TIME = LISTEN_TIME,
		LUNGE_RANGE = LUNGE_RANGE,
		LUNGE_BONUS = LUNGE_BONUS,
		REPATH_INTERVAL = REPATH_INTERVAL,
		REPATH_DISTANCE = REPATH_DISTANCE,
		-- Sprint 37
		patrolPoint = patrolPoint,
		entryPosition = entryPosition,
		PATROL_AREAS = PATROL_AREAS,
		PATROL_MIN_LEG = PATROL_MIN_LEG,
		DRIFT_SPEED = DRIFT_SPEED,
		STANDING_Y = FLOOR_Y + SIZE / 2,
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

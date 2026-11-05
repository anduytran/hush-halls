--!strict
-- Sprint 39 movement tech (design-vault/Mechanics/Movement Tech.md): dash, dash jump, slide, slide hop,
-- double jump and wall jump, all done by setting HumanoidRootPart velocity before each physics step.
-- Stamina is 3 pips that regenerate 1 pip per 2.5 s once nothing has been spent for 0.5 s; it is shown
-- through the LocalPlayer attribute Stamina (0-3, fractional), which the HUD reads.
-- Every loud move fires Remotes.Move with its action name; the server (MovementNoise.luau) turns it into noise.
-- Keys: Q dash, C / Left Ctrl slide, Space jump. Movement.dash() and Movement.slide() are for touch buttons.
-- Movement.onAction(fn) tells local listeners (MovementAnimator) about each move as it happens: Dash, DashJump,
-- Slide, SlideHop, DoubleJump, WallJump and SlideEnd, with a world direction where it matters.
-- Sprint 41 momentum: this module owns the root's horizontal velocity every frame (Quake/Source style). Ground
-- friction slows you instead of an instant stop, the air has no drag (up to MOMENTUM_CAP) and air strafing bends
-- the path, and a jump within HOP_WINDOW of landing skips friction (bunny hop / slide hop). The server's WalkSpeed
-- (walk 10, sprint 24) is the speed the keys accelerate toward. Each frame the humanoid is told to move at exactly
-- that velocity (Humanoid:Move plus WalkSpeed), so its own controller doesn't brake or fight it. The player's input
-- is MoveDirection as the ControlModule leaves it each RenderStep (keyboard, gamepad, touch thumbstick), read in
-- PreSimulation before this module overwrites it.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local GameState = require(ReplicatedStorage.Shared.GameState)

local MAX_STAMINA = 3
local REGEN_DELAY = 0.5 -- seconds without spending before stamina comes back
local REGEN_TIME = 2.5 -- seconds per pip

local DASH_DISTANCE = 18
local DASH_TIME = 0.25
local DASH_SPEED = DASH_DISTANCE / DASH_TIME -- 72 studs/s
local DASH_COST = 1
-- Ground friction slows a set velocity, so each step aims at the distance still to cover, within these bounds.
local DASH_SPEED_MIN = DASH_SPEED * 0.5
local DASH_SPEED_MAX = DASH_SPEED * 1.4
local DASH_EXIT_SPEED = 24 -- horizontal speed left when a dash ends (sprint speed, so a slide can follow)

local DASH_JUMP_WINDOW = 0.15 -- the last part of a dash where Space turns it into a dash jump
local DASH_JUMP_COST = 1 -- on top of the dash's own pip
local DASH_JUMP_SPEED = 50 -- horizontal; the height is a normal jump

local SLIDE_MIN_SPEED = 18
local SLIDE_TIME = 1
local SLIDE_START_MIN = 28
local SLIDE_START_MAX = 40
local SLIDE_END_SPEED = 12
local SLIDE_STEER = 2 -- how fast the slide turns toward the move direction
local SLIDE_CAMERA_OFFSET = Vector3.new(0, -1.6, 0)
-- Floor contact can drag a slide below plan, so the slide pushes harder while it is behind its planned distance
-- (per second of lag, capped at SLIDE_PUSH_MAX times the planned speed).
local SLIDE_CATCHUP = 10
local SLIDE_PUSH_MAX = 1.8

local DOUBLE_JUMP_COST = 1

local WALL_RANGE = 2.6 -- studs from the root's centre
local WALL_JUMP_OUT = 30
local WALL_JUMP_UP = 46
local WALL_JUMP_COST = 0.5 -- the first wall jump in an airtime is free
local WALL_JUMP_COOLDOWN = 0.2

-- Momentum (sprint 41). Ground friction: speed falls at max(speed, STOP_SPEED) * GROUND_FRICTION per second. In
-- playtests the Humanoid's own controller halves the net rate, so 7 measures about 0.5 s to stop from sprint (24)
-- and about 0.27 s from walk (10); 4 measured 0.9 s.
local GROUND_FRICTION = 7
local STOP_SPEED = 10
-- Sprint 42: 12 measured 0 to sprint (98%) in 0.22 s with 50% at 0.08 s; 16 is snappier at the start and
-- still lands near 0.2 s. Friction is untouched, so letting go still glides to a stop.
local GROUND_ACCEL = 16
-- Air strafing: the air may add speed sideways to the current velocity. Sprint 42 raised it from 4 so holding
-- A or D in the air bends the path noticeably (still capped at max(speed, MOMENTUM_CAP)).
local AIR_ACCEL = 10
local MOMENTUM_CAP = 32 -- hops and air strafing never go above this
local HOP_WINDOW = 0.15 -- a jump this soon after landing skips ground friction
local CARRY_DRAG = 12 -- studs/s lost per second in the air while above MOMENTUM_CAP (a dash jump)
-- Humanoid states where the humanoid's own movement is left alone.
local HANDS_OFF_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Dead] = true,
}
local LAUNCH_GRACE = 0.15 -- after a launch, touching the ground doesn't count as landing yet
local TOUCH_JUMP_GAP = 0.15 -- JumpRequest repeats while held; a gap this long starts a new press

-- Feel (sprint 42). Coyote time: a jump press this soon after walking off a ledge is still a ground jump. Jump
-- buffer: a press while falling that would land within this time waits and jumps on landing (reliable bunny hops)
-- instead of spending the double jump.
local COYOTE_TIME = 0.12
local JUMP_BUFFER = 0.12
-- A soft click when a move is refused for lack of stamina (a built-in sound, so no asset upload).
local DENIED_SOUND_ID = "rbxasset://sounds/clickfast.wav"
local DENIED_VOLUME = 0.3
local DENIED_GAP = 0.25 -- at most one click this often

local WALL_DIRECTIONS: { Vector3 } = {}
for i = 0, 7 do
	local angle = i * math.pi / 4
	table.insert(WALL_DIRECTIONS, Vector3.new(math.cos(angle), 0, math.sin(angle)))
end

type Rig = { character: Model, humanoid: Humanoid, root: BasePart }
-- direction: the dash / slide / dash jump direction, or the wall's outward normal for a wall jump.
export type ActionListener = (action: string, direction: Vector3?) -> ()

local Movement = {}

local player = Players.LocalPlayer
local started = false
local moveRemote: RemoteEvent? = nil
local rig: Rig? = nil
local listeners: { ActionListener } = {}

local stamina = MAX_STAMINA
local lastSpend = -math.huge

local dashing = false
local dashInAir = false
local dashStart = 0
local dashDir = Vector3.zero
local dashOrigin = Vector3.zero
local airDashUsed = false

local sliding = false
local slideStart = 0
local slideDir = Vector3.zero
local slideStartSpeed = 0
local slideTravelled = 0
local slideLastPos = Vector3.zero

local lastLaunch = -math.huge
local wasOnGround = false
local landedAt = -math.huge -- when the root last touched down (starts the hop window)
-- The player's input, read in a RenderStep binding right after the ControlModule's Humanoid:Move. Physics can step
-- several times per rendered frame, and MoveDirection holds our own write between renders, so steps, dash and
-- slide all use this copy.
local frameWish = Vector3.zero
local doubleJumpUsed = false
local wallJumps = 0
local lastWallJump = -math.huge
local lastTouchJump = -math.huge
local lastGroundedAt = -math.huge -- the last step that was on the ground (coyote time counts from here)
local coyoteReady = false -- left the ground without jumping or being launched
local bufferedJumpAt = -math.huge -- when a jump press was held over for the landing
local deniedSound: Sound? = nil
local lastDenied = -math.huge

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- FloorMaterial keeps the floor's material for a few frames after takeoff, so it alone would treat the start of
-- every jump as ground (an early wall jump or double jump press did nothing). The state has to agree too.
local AIRBORNE_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Flying] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.Physics] = true,
}

local function isGrounded(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial ~= Enum.Material.Air and not AIRBORNE_STATES[humanoid:GetState()]
end

local function aliveRig(): Rig?
	local current = rig
	if current and current.humanoid.Health > 0 and current.root.Parent ~= nil then
		return current
	end
	return nil
end

local function publishStamina()
	player:SetAttribute("Stamina", stamina)
end

-- The soft "denied" click, local to this player only (a Sound in SoundService plays without a position).
local function denied()
	local now = os.clock()
	if now - lastDenied < DENIED_GAP then
		return
	end
	lastDenied = now
	local sound = deniedSound
	if not sound or sound.Parent == nil then
		local created = Instance.new("Sound")
		created.Name = "MovementDenied"
		created.SoundId = DENIED_SOUND_ID
		created.Volume = DENIED_VOLUME
		created.PlaybackSpeed = 0.8 -- a little lower and softer than the stock click
		created.Parent = SoundService
		deniedSound = created
		sound = created
	end
	if sound then
		sound:Play()
	end
end

-- Spends stamina; when there isn't enough, plays the denied click (unless quiet) and returns false.
local function spend(cost: number, quiet: boolean?): boolean
	if stamina < cost - 1e-6 then
		if not quiet then
			denied()
		end
		return false
	end
	stamina = math.max(0, stamina - cost)
	lastSpend = os.clock()
	publishStamina()
	return true
end

local function report(action: string)
	if moveRemote then
		moveRemote:FireServer(action)
	end
end

local function emit(action: string, direction: Vector3?)
	for _, listener in listeners do
		task.spawn(listener, action, direction)
	end
end

local function jumpSpeed(humanoid: Humanoid): number
	if humanoid.UseJumpPower then
		return humanoid.JumpPower
	end
	return math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
end

-- The player's move input in world space, length 0-1 (a thumbstick can be part way).
local function readWish(current: Rig): Vector3
	local move = flat(current.humanoid.MoveDirection)
	if move.Magnitude > 1 then
		move = move.Unit
	end
	return move
end

-- The way the player is steering, or the camera's forward when they aren't.
local function wishDirection(current: Rig): Vector3
	local move = frameWish
	if move.Magnitude > 0.05 then
		return move.Unit
	end
	local camera = workspace.CurrentCamera
	local look = if camera then flat(camera.CFrame.LookVector) else Vector3.zero
	if look.Magnitude < 0.05 then
		look = flat(current.root.CFrame.LookVector)
	end
	return if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, -1)
end

local function setHorizontal(root: BasePart, horizontal: Vector3)
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, root.AssemblyLinearVelocity.Y, horizontal.Z)
end

-- The humanoid's controller pushes horizontal velocity toward MoveDirection * WalkSpeed (hard on the ground, softer
-- in the air). drive() points that target at the velocity this module wants by writing WalkSpeed locally every
-- frame. baseWalkSpeed is the server's value (walk or sprint) and caps how fast input alone accelerates; a value
-- we didn't write is the server's, which the WalkSpeed signal in bindCharacter picks up.
local writtenWalkSpeed: number? = nil
local baseWalkSpeed = 16

local function writeWalkSpeed(humanoid: Humanoid, speed: number)
	if math.abs(humanoid.WalkSpeed - speed) > 1e-3 then
		writtenWalkSpeed = speed
		humanoid.WalkSpeed = speed
	end
end

-- The controller treats Move as a direction (a short vector still runs at full WalkSpeed), so the speed goes in
-- WalkSpeed and Move gets the unit direction. Its target is then exactly `horizontal`.
-- The last direction drive() gave; the RenderStep binding puts it back after the ControlModule's own Move.
local drivenMove: Vector3? = nil

local function drive(humanoid: Humanoid, horizontal: Vector3)
	local speed = horizontal.Magnitude
	if speed < 0.05 then
		writeWalkSpeed(humanoid, baseWalkSpeed)
		drivenMove = Vector3.zero
		humanoid:Move(Vector3.zero, false)
		return
	end
	writeWalkSpeed(humanoid, speed)
	drivenMove = horizontal / speed
	humanoid:Move(horizontal / speed, false)
end

local function launch(root: BasePart, horizontal: Vector3, up: number)
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, up, horizontal.Z)
	lastLaunch = os.clock()
	coyoteReady = false
end

-- True when the root is falling and will reach the floor below within JUMP_BUFFER (gravity included).
local function landingSoon(current: Rig): boolean
	local vy = current.root.AssemblyLinearVelocity.Y
	if vy > 0 then
		return false
	end
	local reach = current.root.Size.Y / 2 + current.humanoid.HipHeight -- root centre to the feet
	local fall = -vy * JUMP_BUFFER + 0.5 * workspace.Gravity * JUMP_BUFFER * JUMP_BUFFER
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { current.character }
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local hit = workspace:Raycast(current.root.Position, Vector3.new(0, -(reach + fall + 0.5), 0), params)
	return hit ~= nil and hit.Normal.Y > 0.5 and hit.Distance - reach <= fall + 0.25
end

-- A jump from the ground while already airborne (coyote time, or a buffered press that just landed).
local function groundJump(current: Rig, now: number)
	local humanoid, root = current.humanoid, current.root
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, jumpSpeed(humanoid), velocity.Z)
	lastLaunch = now
	coyoteReady = false
end

-- Quake-style acceleration: add speed along wishDir until the velocity's part along it reaches wishSpeed.
local function accelerate(velocity: Vector3, wishDir: Vector3, wishSpeed: number, accel: number, dt: number): Vector3
	if wishSpeed <= 0 then
		return velocity
	end
	local add = wishSpeed - velocity:Dot(wishDir)
	if add <= 0 then
		return velocity
	end
	return velocity + wishDir * math.min(accel * wishSpeed * dt, add)
end

local function applyFriction(velocity: Vector3, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < 0.05 then
		return Vector3.zero
	end
	local newSpeed = math.max(0, speed - math.max(speed, STOP_SPEED) * GROUND_FRICTION * dt)
	return velocity * (newSpeed / speed)
end

local function capSpeed(velocity: Vector3, cap: number): Vector3
	local speed = velocity.Magnitude
	if speed > cap then
		return velocity * (cap / speed)
	end
	return velocity
end

local function endSlide(current: Rig?)
	if sliding then
		emit("SlideEnd")
	end
	sliding = false
	if current then
		current.humanoid.CameraOffset = Vector3.zero
	end
end

local function resetMoves()
	dashing = false
	airDashUsed = false
	sliding = false
	wasOnGround = false
	landedAt = -math.huge
	doubleJumpUsed = false
	wallJumps = 0
	lastGroundedAt = -math.huge
	coyoteReady = false
	bufferedJumpAt = -math.huge
end

-- The outward normal of the nearest wall beside the root, if there is one.
local function findWall(current: Rig): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { current.character }
	params.RespectCanCollide = true
	local best: RaycastResult? = nil
	for _, direction in WALL_DIRECTIONS do
		local hit = workspace:Raycast(current.root.Position, direction * WALL_RANGE, params)
		if hit and math.abs(hit.Normal.Y) < 0.5 and (best == nil or hit.Distance < best.Distance) then
			best = hit
		end
	end
	if best then
		local normal = flat(best.Normal)
		if normal.Magnitude > 0.05 then
			return normal.Unit
		end
	end
	return nil
end

function Movement.dash()
	local current = aliveRig()
	if not current or dashing then
		return
	end
	local grounded = isGrounded(current.humanoid)
	if not grounded and airDashUsed then
		return
	end
	if not spend(DASH_COST) then
		return
	end
	if not grounded then
		airDashUsed = true
	end
	if sliding then
		endSlide(current)
	end
	dashing = true
	dashInAir = not grounded
	dashStart = os.clock()
	dashDir = wishDirection(current)
	dashOrigin = current.root.Position
	report("Dash")
	emit("Dash", dashDir)
end

function Movement.slide()
	local current = aliveRig()
	if not current or sliding or not isGrounded(current.humanoid) then
		return
	end
	local velocity = flat(current.root.AssemblyLinearVelocity)
	if dashing then
		velocity = dashDir * DASH_SPEED
	end
	local speed = velocity.Magnitude
	if speed < SLIDE_MIN_SPEED then
		return
	end
	dashing = false
	sliding = true
	slideStart = os.clock()
	slideDir = velocity.Unit
	slideStartSpeed = math.clamp(speed, SLIDE_START_MIN, SLIDE_START_MAX)
	slideTravelled = 0
	slideLastPos = current.root.Position
	current.humanoid.CameraOffset = SLIDE_CAMERA_OFFSET
	report("Slide")
	emit("Slide", slideDir)
end

local function slideSpeed(now: number): number
	local t = math.clamp((now - slideStart) / SLIDE_TIME, 0, 1)
	return slideStartSpeed + (SLIDE_END_SPEED - slideStartSpeed) * t
end

-- How far the slide should have gone by now (the integral of slideSpeed).
local function slidePlanned(now: number): number
	local elapsed = math.clamp(now - slideStart, 0, SLIDE_TIME)
	return slideStartSpeed * elapsed + (SLIDE_END_SPEED - slideStartSpeed) * elapsed * elapsed / (2 * SLIDE_TIME)
end

local function onJumpPress()
	local current = aliveRig()
	if not current then
		return
	end
	local humanoid, root = current.humanoid, current.root
	local now = os.clock()

	if dashing then
		dashing = false
		if now - dashStart >= DASH_TIME - DASH_JUMP_WINDOW and spend(DASH_JUMP_COST) then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			launch(root, dashDir * DASH_JUMP_SPEED, jumpSpeed(humanoid))
			report("DashJump")
			emit("DashJump", dashDir)
			return
		end
		-- An early press just ends the dash; a grounded humanoid then jumps normally.
	end

	if isGrounded(humanoid) then
		if sliding then
			-- Slide hop: the humanoid does the jump, the slide's speed (up to MOMENTUM_CAP) is kept in the air.
			setHorizontal(root, slideDir * math.min(slideSpeed(now), MOMENTUM_CAP))
			lastLaunch = now
			endSlide(current)
			emit("SlideHop", slideDir)
		end
		return
	end

	-- Coyote time: just walked (or slid) off a ledge without jumping, so this is still a ground jump.
	if
		coyoteReady
		and now - lastGroundedAt <= COYOTE_TIME
		and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
	then
		groundJump(current, now)
		return
	end

	-- Jump buffer: about to land, so hold the press for the landing (a free hop that keeps the speed) rather
	-- than spending the double jump a moment before touching down.
	if landingSoon(current) then
		bufferedJumpAt = now
		return
	end

	if now - lastWallJump >= WALL_JUMP_COOLDOWN then
		local normal = findWall(current)
		if normal and (wallJumps == 0 or spend(WALL_JUMP_COST)) then
			wallJumps += 1
			lastWallJump = now
			launch(root, normal * WALL_JUMP_OUT, WALL_JUMP_UP)
			report("WallJump")
			emit("WallJump", normal)
			return
		end
	end

	if not doubleJumpUsed and spend(DOUBLE_JUMP_COST) then
		doubleJumpUsed = true
		lastLaunch = now -- a press just above the floor must not be refunded by the landing check
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, jumpSpeed(humanoid), velocity.Z)
		report("DoubleJump")
		emit("DoubleJump")
	end
end

-- Walking, running, hopping and falling: friction on the ground, none in the air, keys accelerate toward the
-- server's WalkSpeed. It starts from the root's real velocity, so walls and props still stop you.
local function momentum(humanoid: Humanoid, root: BasePart, onGround: boolean, now: number, dt: number)
	local velocity = flat(root.AssemblyLinearVelocity)
	local wish = frameWish
	local amount = wish.Magnitude
	local wishDir = if amount > 1e-3 then wish / amount else Vector3.zero
	local wishSpeed = baseWalkSpeed * amount
	if onGround then
		if now - landedAt < HOP_WINDOW then
			-- Just landed: no friction yet, so a jump now keeps the speed (bunny hop), up to the cap.
			velocity = capSpeed(velocity, MOMENTUM_CAP)
		else
			velocity = applyFriction(velocity, dt)
		end
		velocity = accelerate(velocity, wishDir, wishSpeed, GROUND_ACCEL, dt)
	else
		local before = velocity.Magnitude
		if before > MOMENTUM_CAP then
			velocity *= math.max(MOMENTUM_CAP, before - CARRY_DRAG * dt) / before
			before = velocity.Magnitude
		end
		-- Air strafing: the keys can turn the velocity and add a little, never past max(speed before, cap).
		velocity = capSpeed(accelerate(velocity, wishDir, wishSpeed, AIR_ACCEL, dt), math.max(before, MOMENTUM_CAP))
	end
	setHorizontal(root, velocity)
	drive(humanoid, velocity)
end

local function step(dt: number)
	local now = os.clock()
	if stamina < MAX_STAMINA and now - lastSpend >= REGEN_DELAY then
		stamina = math.min(MAX_STAMINA, stamina + dt / REGEN_TIME)
		publishStamina()
	end

	local current = aliveRig()
	if not current then
		return
	end
	local humanoid, root = current.humanoid, current.root
	local grounded = isGrounded(humanoid)

	local onGround = grounded and now - lastLaunch > LAUNCH_GRACE
	if onGround then
		airDashUsed = false
		doubleJumpUsed = false
		wallJumps = 0
		if not wasOnGround then
			landedAt = now
		end
		lastGroundedAt = now
		coyoteReady = true
	end
	wasOnGround = onGround

	if grounded and now - bufferedJumpAt <= JUMP_BUFFER and not HANDS_OFF_STATES[humanoid:GetState()] then
		-- The buffered press lands: jump now, inside the hop window, so the speed carries (bunny hop).
		bufferedJumpAt = -math.huge
		if sliding then
			endSlide(current)
		end
		groundJump(current, now)
	end

	if HANDS_OFF_STATES[humanoid:GetState()] then
		-- Ladders, seats, ragdolls: the humanoid moves itself at the server's WalkSpeed.
		dashing = false
		endSlide(current)
		writeWalkSpeed(humanoid, baseWalkSpeed)
		drivenMove = nil
		return
	end

	if dashing then
		if now - dashStart >= DASH_TIME then
			dashing = false
			setHorizontal(root, dashDir * DASH_EXIT_SPEED)
			drive(humanoid, dashDir * DASH_EXIT_SPEED)
			if not grounded then
				lastLaunch = now
			end
		else
			local travelled = flat(root.Position - dashOrigin):Dot(dashDir)
			local timeLeft = math.max(DASH_TIME - (now - dashStart), 1 / 60)
			local speed = math.clamp((DASH_DISTANCE - travelled) / timeLeft, DASH_SPEED_MIN, DASH_SPEED_MAX)
			local y = if dashInAir then 0 else root.AssemblyLinearVelocity.Y
			root.AssemblyLinearVelocity = dashDir * speed + Vector3.new(0, y, 0)
			drive(humanoid, dashDir * speed)
		end
	elseif sliding then
		local speed = slideSpeed(now)
		-- Progress comes from positions, like the dash: the velocity read back can lag what floor contact left,
		-- which once hid the slide's lag and ended it as "blocked" a few frames after it started.
		local moved = flat(root.Position - slideLastPos).Magnitude
		slideLastPos = root.Position
		local actual = if dt > 0 then moved / dt else speed
		slideTravelled += moved
		local finished = now - slideStart >= SLIDE_TIME
		local blocked = now - slideStart > 0.1 and actual < speed * 0.4 -- ran into something
		if grounded and (finished or blocked) then
			endSlide(current)
			momentum(humanoid, root, onGround, now, dt)
		elseif not grounded then
			-- Sliding off a ledge keeps the speed in the air; jumping out of it (Space is handled in onJumpPress,
			-- this catches the touch button and Humanoid.Jump) is a slide hop, capped like every hop.
			local hop = humanoid:GetState() == Enum.HumanoidStateType.Jumping
			local kept = slideDir * (if hop then math.min(speed, MOMENTUM_CAP) else speed)
			lastLaunch = now
			endSlide(current)
			if hop then
				emit("SlideHop", slideDir)
			end
			setHorizontal(root, kept)
			drive(humanoid, kept)
		else
			local wish = frameWish
			if wish.Magnitude > 0.05 then
				local turned = slideDir:Lerp(wish.Unit, math.min(1, SLIDE_STEER * dt))
				if turned.Magnitude > 0.05 then
					slideDir = turned.Unit
				end
			end
			local lag = slidePlanned(now) - slideTravelled
			local push = math.clamp(speed + lag * SLIDE_CATCHUP, speed, speed * SLIDE_PUSH_MAX)
			setHorizontal(root, slideDir * push)
			drive(humanoid, slideDir * push)
		end
	else
		momentum(humanoid, root, onGround, now, dt)
	end
end

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end
	if player.Character ~= character then
		return
	end
	resetMoves()
	writtenWalkSpeed = nil
	drivenMove = nil
	frameWish = Vector3.zero
	baseWalkSpeed = humanoid.WalkSpeed
	stamina = MAX_STAMINA
	lastSpend = -math.huge
	publishStamina()
	rig = { character = character, humanoid = humanoid, root = root }
	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		-- A value we didn't write is the server's (sprint on or off): the speed the keys aim for.
		-- Signals can be deferred, so this compares against what we wrote rather than using a flag.
		local written = writtenWalkSpeed
		if written == nil or math.abs(humanoid.WalkSpeed - written) > 1e-3 then
			baseWalkSpeed = humanoid.WalkSpeed
		end
	end)
	humanoid.StateChanged:Connect(function(_, newState)
		-- The humanoid's own jump (Space, Humanoid.Jump, auto-jump) uses up the coyote jump.
		if newState == Enum.HumanoidStateType.Jumping then
			coyoteReady = false
		end
	end)
	humanoid.Died:Connect(function()
		local current = rig
		if current and current.character == character then
			rig = nil
			resetMoves()
		end
	end)
end

-- Calls fn(action, direction?) for each local move. Returns a function that removes the listener.
function Movement.onAction(fn: ActionListener): () -> ()
	table.insert(listeners, fn)
	return function()
		local index = table.find(listeners, fn)
		if index then
			table.remove(listeners, index)
		end
	end
end

function Movement.start()
	if started then
		return
	end
	started = true

	moveRemote = GameState.Remotes:FindFirstChild("Move") :: RemoteEvent?
	publishStamina()

	ContextActionService:BindAction("HushDash", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Movement.dash()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q)
	ContextActionService:BindAction("HushSlide", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			Movement.slide()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl)

	-- Keyboard and gamepad jumps are read as key presses; the touch jump button only raises JumpRequest.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			onJumpPress()
		end
	end)
	UserInputService.JumpRequest:Connect(function()
		if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			return
		end
		local now = os.clock()
		local isNewPress = now - lastTouchJump > TOUCH_JUMP_GAP
		lastTouchJump = now
		if isNewPress then
			onJumpPress()
		end
	end)

	-- Bound after the ControlModule (Input priority) so this reads the Humanoid:Move it just made.
	RunService:BindToRenderStep("MovementWish", Enum.RenderPriority.Input.Value + 1, function()
		local current = aliveRig()
		frameWish = if current then readWish(current) else Vector3.zero
		-- The ControlModule's Move would otherwise reach physics on rendered frames and brake the momentum.
		if current and drivenMove then
			current.humanoid:Move(drivenMove, false)
		end
	end)
	-- PreSimulation runs after the ControlModule's RenderStep Humanoid:Move, so drive() has the last word.
	RunService.PreSimulation:Connect(step)

	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
end

return Movement

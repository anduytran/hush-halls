--!strict
-- Sprint 39 movement tech (design-vault/Mechanics/Movement Tech.md): dash, dash jump, slide, slide hop,
-- double jump and wall jump, all done by setting HumanoidRootPart velocity before each physics step.
-- Stamina is 3 pips that regenerate 1 pip per 2.5 s once nothing has been spent for 0.5 s; it is shown
-- through the LocalPlayer attribute Stamina (0-3, fractional), which the HUD reads.
-- Every loud move fires Remotes.Move with its action name; the server (MovementNoise.luau) turns it into noise.
-- Keys: Q dash, C / Left Ctrl slide, Space jump. Movement.dash() and Movement.slide() are for touch buttons.
-- Movement.onAction(fn) tells local listeners (MovementAnimator) about each move as it happens: Dash, DashJump,
-- Slide, SlideHop, DoubleJump, WallJump and SlideEnd, with a world direction where it matters.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
-- The ground controller drags a slide back to WalkSpeed, so the slide pushes harder while it is behind its
-- planned distance (per second of lag, capped at SLIDE_PUSH_MAX times the planned speed).
local SLIDE_CATCHUP = 10
local SLIDE_PUSH_MAX = 1.8

local DOUBLE_JUMP_COST = 1

local WALL_RANGE = 2.6 -- studs from the root's centre
local WALL_JUMP_OUT = 30
local WALL_JUMP_UP = 46
local WALL_JUMP_COST = 0.5 -- the first wall jump in an airtime is free
local WALL_JUMP_COOLDOWN = 0.2

local CARRY_DRAG = 12 -- studs/s lost per second while carrying momentum in the air
local AIR_STEER = 3
local LAUNCH_GRACE = 0.15 -- after a launch, touching the ground doesn't count as landing yet
local TOUCH_JUMP_GAP = 0.15 -- JumpRequest repeats while held; a gap this long starts a new press

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

local carry: Vector3? = nil -- horizontal velocity kept while airborne (dash jump, slide hop, wall jump)
local lastLaunch = -math.huge
local doubleJumpUsed = false
local wallJumps = 0
local lastWallJump = -math.huge
local lastTouchJump = -math.huge

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

local function spend(cost: number): boolean
	if stamina < cost - 1e-6 then
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

-- The way the player is steering, or the camera's forward when they aren't.
local function wishDirection(current: Rig): Vector3
	local move = flat(current.humanoid.MoveDirection)
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

-- With a move key held, the ground controller snaps horizontal speed to MoveDirection * WalkSpeed every frame,
-- so a ground dash or slide raises WalkSpeed locally to its own speed and then gives back the server's value.
-- A WalkSpeed the server replicates mid-move (sprint toggled) becomes the value that is given back.
local walkOverride: number? = nil
local baseWalkSpeed = 16

local function setWalkOverride(humanoid: Humanoid, speed: number?)
	if speed then
		if walkOverride == nil then
			baseWalkSpeed = humanoid.WalkSpeed
		end
		walkOverride = speed
		humanoid.WalkSpeed = speed
	elseif walkOverride ~= nil then
		walkOverride = nil
		humanoid.WalkSpeed = baseWalkSpeed
	end
end

local function launch(root: BasePart, horizontal: Vector3, up: number)
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, up, horizontal.Z)
	carry = horizontal
	lastLaunch = os.clock()
end

local function endSlide(current: Rig?)
	if sliding then
		emit("SlideEnd")
	end
	sliding = false
	if current then
		current.humanoid.CameraOffset = Vector3.zero
		setWalkOverride(current.humanoid, nil)
	end
end

local function resetMoves()
	dashing = false
	airDashUsed = false
	sliding = false
	carry = nil
	doubleJumpUsed = false
	wallJumps = 0
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
	carry = nil
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
	carry = nil
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
			-- Slide hop: the humanoid does the jump, the slide's speed is carried through the air.
			carry = slideDir * slideSpeed(now)
			lastLaunch = now
			endSlide(current)
			emit("SlideHop", slideDir)
		end
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

	if grounded and now - lastLaunch > LAUNCH_GRACE then
		airDashUsed = false
		doubleJumpUsed = false
		wallJumps = 0
		carry = nil
	end

	local override: number? = nil -- WalkSpeed to hold this frame (ground dash and slide)
	if dashing then
		if now - dashStart >= DASH_TIME then
			dashing = false
			setHorizontal(root, dashDir * DASH_EXIT_SPEED)
			if not grounded then
				carry = dashDir * DASH_EXIT_SPEED
				lastLaunch = now
			end
		else
			local travelled = flat(root.Position - dashOrigin):Dot(dashDir)
			local timeLeft = math.max(DASH_TIME - (now - dashStart), 1 / 60)
			local speed = math.clamp((DASH_DISTANCE - travelled) / timeLeft, DASH_SPEED_MIN, DASH_SPEED_MAX)
			local y = if dashInAir then 0 else root.AssemblyLinearVelocity.Y
			root.AssemblyLinearVelocity = dashDir * speed + Vector3.new(0, y, 0)
			if grounded then
				override = speed
			end
		end
	elseif sliding then
		local speed = slideSpeed(now)
		-- Progress comes from positions, like the dash: the velocity read back here is not what the ground
		-- controller left after braking (with no move key held it brakes hard), so it hid the slide's lag and
		-- the slide ended as "blocked" a few frames after it started.
		local moved = flat(root.Position - slideLastPos).Magnitude
		slideLastPos = root.Position
		local actual = if dt > 0 then moved / dt else speed
		slideTravelled += moved
		local finished = now - slideStart >= SLIDE_TIME
		local blocked = now - slideStart > 0.1 and actual < speed * 0.4 -- ran into something
		if grounded and (finished or blocked) then
			endSlide(current)
		elseif not grounded then
			-- Sliding off a ledge keeps the speed in the air.
			carry = slideDir * speed
			lastLaunch = now
			endSlide(current)
		else
			local wish = flat(humanoid.MoveDirection)
			if wish.Magnitude > 0.05 then
				local turned = slideDir:Lerp(wish.Unit, math.min(1, SLIDE_STEER * dt))
				if turned.Magnitude > 0.05 then
					slideDir = turned.Unit
				end
			end
			local lag = slidePlanned(now) - slideTravelled
			local push = math.clamp(speed + lag * SLIDE_CATCHUP, speed, speed * SLIDE_PUSH_MAX)
			setHorizontal(root, slideDir * push)
			override = push
		end
	else
		setWalkOverride(humanoid, nil) -- the carry check below compares against the real WalkSpeed
		local kept = carry
		if kept then
			local actual = flat(root.AssemblyLinearVelocity).Magnitude
			local speed = kept.Magnitude - CARRY_DRAG * dt
			if speed <= humanoid.WalkSpeed or (now - lastLaunch > 0.1 and actual < kept.Magnitude * 0.5) then
				carry = nil -- slowed to walking pace, or hit something
			else
				local direction = kept.Unit
				local wish = flat(humanoid.MoveDirection)
				if wish.Magnitude > 0.05 then
					local turned = direction:Lerp(wish.Unit, math.min(1, AIR_STEER * dt))
					if turned.Magnitude > 0.05 then
						direction = turned.Unit
					end
				end
				carry = direction * speed
				setHorizontal(root, direction * speed)
			end
		end
	end
	setWalkOverride(humanoid, override)
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
	walkOverride = nil
	stamina = MAX_STAMINA
	lastSpend = -math.huge
	publishStamina()
	rig = { character = character, humanoid = humanoid, root = root }
	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		-- A value we didn't write is the server's (sprint on or off); give that one back after the move.
		-- Signals can be deferred, so this compares against what we wrote rather than using a flag.
		local written = walkOverride
		if written ~= nil and math.abs(humanoid.WalkSpeed - written) > 1e-3 then
			baseWalkSpeed = humanoid.WalkSpeed
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

	RunService.PreSimulation:Connect(step)

	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
end

return Movement

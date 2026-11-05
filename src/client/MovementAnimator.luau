--!strict
-- Sprint 40 movement animations (design-vault/Mechanics/Movement Tech.md, "Animations (sprint 40)").
-- Procedural poses with no uploaded assets: every PreSimulation (after the Animator has written this frame's
-- joint Transform) each joint is blended from the Animator's pose toward a move pose, with a per-joint weight
-- that eases in and out, so the default Roblox animations take back over without a snap.
-- Joints are Motor6Ds, or AnimationConstraints on rigs using the newer avatar joints; both have Transform.
-- Works on R15 (all joints) and R6 (root, neck, shoulders and hips; R6 has no knees or elbows).
-- The HumanoidRootPart is never moved, so the camera and the root's collision are untouched.
-- Local player: Movement.onAction. Other players: the MoveAction / MoveActionAt attributes the server sets
-- on their character (MovementNoise.luau); characters more than 200 studs from the camera are skipped.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Movement = require(script.Parent.Movement)

local MAX_DISTANCE = 200
local STALE_AFTER = 1 -- seconds; older remote MoveActionAt values are ignored (e.g. on join)
local BLEND_OUT = 9 -- per-second rate the weight falls back to the Animator's pose
local SLIDE_REMOTE_TIME = 1 -- remote slides have no end event; the local slide lasts 1 s
local TAU = 2 * math.pi

-- R6 joint names mapped onto the R15 names the poses use.
local R6_NAMES: { [string]: string } = {
	RootJoint = "Root",
	Neck = "Neck",
	["Right Shoulder"] = "RightShoulder",
	["Left Shoulder"] = "LeftShoulder",
	["Right Hip"] = "RightHip",
	["Left Hip"] = "LeftHip",
}
local R15_NAMES: { [string]: boolean } = {
	Root = true,
	Waist = true,
	Neck = true,
	RightShoulder = true,
	LeftShoulder = true,
	RightElbow = true,
	LeftElbow = true,
	RightHip = true,
	LeftHip = true,
	RightKnee = true,
	LeftKnee = true,
}

type Joint = {
	motor: any, -- Motor6D or AnimationConstraint; both expose Transform
	-- A pose rotation R is given in the parent part's frame; the Transform is C0rot^-1 * R * C0rot
	-- (C0 for a Motor6D, Attachment0.CFrame for an AnimationConstraint).
	c0Rot: CFrame,
	c0RotInv: CFrame,
	pose: CFrame, -- smoothed target, in joint space
	weight: number,
	written: CFrame?, -- what we wrote last frame
	base: CFrame, -- the Animator's value under what we wrote
}

type Action = {
	name: string,
	start: number,
	duration: number,
	dir: Vector3, -- character-space direction (dash / slide / wall), Y = 0
	blendIn: number,
}

type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	isLocal: boolean,
	r6: boolean,
	joints: { [string]: Joint },
	action: Action?,
	spinStart: number?,
	connections: { RBXScriptConnection },
}

type Pose = { [string]: CFrame }

local MovementAnimator = {}

local started = false
local rigs: { [Model]: Rig } = {}

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(x, y, z)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function mix(a: Pose, b: Pose, t: number): Pose
	local out: Pose = {}
	for key, value in a do
		out[key] = value:Lerp(b[key] or CFrame.identity, t)
	end
	for key, value in b do
		if out[key] == nil then
			out[key] = CFrame.new():Lerp(value, t)
		end
	end
	return out
end

-- Pose functions. Signs (R15 joint frames): +X pitch swings a limb forward and leans the torso back, +Z roll
-- swings a limb toward the character's right and leans the torso to its left. Knees bend with -X.
-- `t` is 0-1 through the action, `dir` is the move direction in character space (forward is -Z).

local function dashPose(_t: number, dir: Vector3): Pose
	local lean = 0.75
	return {
		Root = angles(dir.Z * lean, 0, -dir.X * lean),
		Waist = angles(dir.Z * 0.35, 0, -dir.X * 0.3),
		Neck = angles(0.45, 0, 0),
		RightShoulder = angles(-1.3, 0, 0.35),
		LeftShoulder = angles(-1.3, 0, -0.35),
		RightElbow = angles(0.3, 0, 0),
		LeftElbow = angles(0.3, 0, 0),
		RightHip = angles(0.75, 0, 0),
		LeftHip = angles(-0.55, 0, 0),
		RightKnee = angles(-0.9, 0, 0),
		LeftKnee = angles(-0.5, 0, 0),
	}
end

local TUCK: Pose = {
	Root = angles(-0.25, 0, 0),
	Waist = angles(-0.2, 0, 0),
	Neck = angles(-0.2, 0, 0),
	RightShoulder = angles(0.9, 0, 0.2),
	LeftShoulder = angles(0.9, 0, -0.2),
	RightElbow = angles(1.1, 0, 0),
	LeftElbow = angles(1.1, 0, 0),
	RightHip = angles(1.7, 0, 0.1),
	LeftHip = angles(1.7, 0, -0.1),
	RightKnee = angles(-2.1, 0, 0),
	LeftKnee = angles(-2.1, 0, 0),
}

local OPEN: Pose = {
	Root = angles(0.1, 0, 0),
	Neck = angles(0.15, 0, 0),
	RightShoulder = angles(0.4, 0, 1.25),
	LeftShoulder = angles(0.4, 0, -1.25),
	RightElbow = angles(0.25, 0, 0),
	LeftElbow = angles(0.25, 0, 0),
	RightHip = angles(0.45, 0, 0.15),
	LeftHip = angles(-0.3, 0, -0.15),
	RightKnee = angles(-0.5, 0, 0),
	LeftKnee = angles(-0.3, 0, 0),
}

local function dashJumpPose(t: number, _dir: Vector3): Pose
	return mix(TUCK, OPEN, smooth((t - 0.3) / 0.35))
end

local function slidePose(rig: Rig): Pose
	local drop = if rig.r6 then 1.3 else math.max(rig.humanoid.HipHeight, 1) * 0.8
	return {
		Root = CFrame.new(0, -drop, 0) * angles(0.55, 0, 0),
		Waist = angles(0.15, 0, 0),
		Neck = angles(-0.55, 0, 0),
		RightHip = angles(1.05, 0, 0.05),
		RightKnee = angles(-0.15, 0, 0),
		LeftHip = angles(0.15, 0, -0.1),
		LeftKnee = angles(-2.2, 0, 0),
		-- The left hand trails behind on the floor, the right arm is up for balance.
		LeftShoulder = angles(-0.7, 0, -0.55),
		LeftElbow = angles(0.15, 0, 0),
		RightShoulder = angles(0.8, 0, 0.35),
		RightElbow = angles(0.6, 0, 0),
	}
end

local function slideHopPose(_t: number, _dir: Vector3): Pose
	return TUCK
end

local function doubleJumpPose(_t: number, _dir: Vector3): Pose
	return TUCK
end

-- dir is the wall's outward normal; the wall is on the opposite side.
local function wallJumpPose(t: number, dir: Vector3): Pose
	local wx, wz = -dir.X, -dir.Z -- toward the wall
	local kick = 1 - smooth((t - 0.5) / 0.5) * 0.4
	return {
		Root = angles(-wz * 0.4, 0, wx * 0.35),
		Waist = angles(-wz * 0.2, 0, wx * 0.2),
		RightShoulder = angles(-wz * 1.5 + 0.2, 0, wx * 1.4 + 0.35),
		LeftShoulder = angles(-wz * 1.5 + 0.2, 0, wx * 1.4 - 0.35),
		RightElbow = angles(0.3, 0, 0),
		LeftElbow = angles(0.3, 0, 0),
		RightHip = angles((wz * 0.9 + 0.2) * kick, 0, -wx * 0.8 * kick),
		LeftHip = angles((wz * 0.9 - 0.3) * kick, 0, -wx * 0.6 * kick),
		RightKnee = angles(-0.4, 0, 0),
		LeftKnee = angles(-1.1, 0, 0),
	}
end

type ActionSpec = { duration: number, blendIn: number, pose: (t: number, dir: Vector3) -> Pose }

local ACTIONS: { [string]: ActionSpec } = {
	Dash = { duration = 0.25, blendIn = 30, pose = dashPose },
	DashJump = { duration = 0.65, blendIn = 25, pose = dashJumpPose },
	Slide = {
		duration = math.huge,
		blendIn = 20,
		pose = function()
			return {}
		end,
	}, -- built per rig, see slidePose
	SlideHop = { duration = 0.22, blendIn = 30, pose = slideHopPose },
	DoubleJump = { duration = 0.35, blendIn = 30, pose = doubleJumpPose },
	WallJump = { duration = 0.4, blendIn = 30, pose = wallJumpPose },
}
local SPIN_TIME = 0.35

local function collectJoints(character: Model, r6: boolean): { [string]: Joint }
	local joints: { [string]: Joint } = {}
	for _, descendant in character:GetDescendants() do
		local c0: CFrame? = nil
		if descendant:IsA("Motor6D") then
			c0 = descendant.C0
		elseif descendant:IsA("AnimationConstraint") then
			local attachment = (descendant :: any).Attachment0
			if typeof(attachment) == "Instance" and attachment:IsA("Attachment") then
				c0 = attachment.CFrame
			end
		end
		if c0 then
			local key: string? = nil
			if r6 then
				key = R6_NAMES[descendant.Name]
			elseif R15_NAMES[descendant.Name] then
				key = descendant.Name
			end
			if key and joints[key] == nil then
				local c0Rot = c0.Rotation
				joints[key] = {
					motor = descendant,
					c0Rot = c0Rot,
					c0RotInv = c0Rot:Inverse(),
					pose = CFrame.identity,
					weight = 0,
					written = nil,
					base = CFrame.identity,
				}
			end
		end
	end
	return joints
end

local function play(rig: Rig, name: string, worldDir: Vector3?)
	local spec = ACTIONS[name]
	if not spec then
		return
	end
	local dir = Vector3.new(0, 0, -1)
	if worldDir then
		local localDir = rig.root.CFrame:VectorToObjectSpace(worldDir)
		local flat = Vector3.new(localDir.X, 0, localDir.Z)
		if flat.Magnitude > 0.05 then
			dir = flat.Unit
		end
	end
	local duration = spec.duration
	if name == "Slide" and not rig.isLocal then
		duration = SLIDE_REMOTE_TIME
	end
	rig.action = { name = name, start = os.clock(), duration = duration, dir = dir, blendIn = spec.blendIn }
	if name == "DoubleJump" then
		rig.spinStart = os.clock()
	end
end

local function stopAction(rig: Rig, name: string)
	local action = rig.action
	if action and action.name == name then
		rig.action = nil
	end
end

local function untrack(character: Model)
	local rig = rigs[character]
	if not rig then
		return
	end
	rigs[character] = nil
	for _, connection in rig.connections do
		connection:Disconnect()
	end
end

local function track(character: Model, isLocal: boolean): Rig?
	if rigs[character] then
		return rigs[character]
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return nil
	end
	if character.Parent == nil or rigs[character] then
		return rigs[character]
	end
	local r6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local rig: Rig = {
		character = character,
		humanoid = humanoid,
		root = root,
		isLocal = isLocal,
		r6 = r6,
		joints = collectJoints(character, r6),
		action = nil,
		spinStart = nil,
		connections = {},
	}
	rigs[character] = rig
	table.insert(
		rig.connections,
		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				untrack(character)
			end
		end)
	)
	table.insert(
		rig.connections,
		humanoid.Died:Connect(function()
			untrack(character)
		end)
	)
	if not isLocal then
		table.insert(
			rig.connections,
			character:GetAttributeChangedSignal("MoveActionAt"):Connect(function()
				local at = character:GetAttribute("MoveActionAt")
				local name = character:GetAttribute("MoveAction")
				if typeof(at) ~= "number" or typeof(name) ~= "string" then
					return
				end
				if workspace:GetServerTimeNow() - at > STALE_AFTER then
					return
				end
				local camera = workspace.CurrentCamera
				if camera and (camera.CFrame.Position - root.Position).Magnitude > MAX_DISTANCE then
					return
				end
				-- Remote moves carry no direction; the replicated velocity points along the dash / slide
				-- and away from the wall on a wall jump.
				local velocity = root.AssemblyLinearVelocity
				local flat = Vector3.new(velocity.X, 0, velocity.Z)
				play(rig, name, if flat.Magnitude > 2 then flat else nil)
			end)
		)
	end
	return rig
end

local function blendRate(rig: Rig, target: Pose?): number
	local action = rig.action
	if target and action then
		return action.blendIn
	end
	return BLEND_OUT
end

local function stepRig(rig: Rig, dt: number, now: number, cameraPos: Vector3?)
	-- Remote slides: a jump out of the slide is a slide hop; leaving the ground ends it.
	local action = rig.action
	if action and action.name == "Slide" and not rig.isLocal then
		local state = rig.humanoid:GetState()
		if state == Enum.HumanoidStateType.Jumping then
			play(rig, "SlideHop", nil)
		elseif state == Enum.HumanoidStateType.Freefall then
			stopAction(rig, "Slide")
		end
	end
	action = rig.action
	if action and now - action.start >= action.duration then
		rig.action = nil
		action = nil
	end

	local target: Pose? = nil
	if action then
		if action.name == "Slide" then
			target = slidePose(rig)
		else
			local spec = ACTIONS[action.name]
			target = spec.pose(math.clamp((now - action.start) / action.duration, 0, 1), action.dir)
		end
	end

	local spin = CFrame.identity
	local spinStart = rig.spinStart
	if spinStart then
		local t = (now - spinStart) / SPIN_TIME
		if t >= 1 then
			rig.spinStart = nil
		else
			-- A forward flip: the top of the body goes forward (-X pitch at the root).
			spin = angles(-TAU * smooth(t), 0, 0)
		end
	end

	local far = cameraPos ~= nil and (cameraPos - rig.root.Position).Magnitude > MAX_DISTANCE
	local alpha = 1 - math.exp(-blendRate(rig, target) * dt)
	for key, joint in rig.joints do
		local motor = joint.motor
		-- The Animator rewrites Transform each frame for joints it is playing; for a joint it left alone the
		-- value is still ours, so the base under it is the one we kept.
		local current = motor.Transform
		local written = joint.written
		local base = if written and current == written then joint.base else current
		joint.base = base

		local want = target and target[key]
		if want then
			local jointPose = joint.c0RotInv * want * joint.c0Rot
			joint.pose = joint.pose:Lerp(jointPose, alpha)
			joint.weight += (1 - joint.weight) * alpha
		else
			joint.weight += (0 - joint.weight) * alpha
		end
		if far then
			joint.weight = 0
		end

		local isSpinning = key == "Root" and spin ~= CFrame.identity
		if joint.weight < 1e-3 and not isSpinning then
			joint.weight = 0
			if written then
				-- Hand the joint back: write the base once so nothing of ours is left on it.
				motor.Transform = base
				joint.written = nil
			end
		else
			local out = base:Lerp(joint.pose, joint.weight)
			if isSpinning then
				out = (joint.c0RotInv * spin * joint.c0Rot) * out
			end
			motor.Transform = out
			joint.written = out
		end
	end
end

local function onPreSimulation(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else nil
	for character, rig in rigs do
		if rig.humanoid.Health <= 0 or rig.root.Parent == nil then
			untrack(character)
		else
			stepRig(rig, dt, now, cameraPos)
		end
	end
end

local function watchPlayer(other: Player)
	local isLocal = other == Players.LocalPlayer
	other.CharacterAdded:Connect(function(character)
		track(character, isLocal)
	end)
	other.CharacterRemoving:Connect(untrack)
	if other.Character then
		task.spawn(track, other.Character, isLocal)
	end
end

function MovementAnimator.start()
	if started then
		return
	end
	started = true

	Movement.onAction(function(name: string, direction: Vector3?)
		local character = Players.LocalPlayer.Character
		local rig = character and (rigs[character] or track(character, true))
		if not rig then
			return
		end
		if name == "SlideEnd" then
			stopAction(rig, "Slide")
		else
			play(rig, name, direction)
		end
	end)

	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	RunService.PreSimulation:Connect(onPreSimulation)
end

-- Studio-only hooks for specs and playtests.
MovementAnimator._test = {
	play = function(character: Model, name: string, direction: Vector3?)
		local rig = rigs[character]
		if rig then
			play(rig, name, direction)
		end
	end,
	isTracked = function(character: Model): boolean
		return rigs[character] ~= nil
	end,
}

return MovementAnimator

--!strict
-- Client-side procedural animation for the monster (Sprint 37).
-- Reads the `State` (Idle, Patrol, Chase, Lunge, Listen, Kill) and `Speed` attributes on Workspace.Hall.Monster
-- (set by src/server/Monster.luau) and, every RenderStepped, writes Motor6D.Transform on the joints built by
-- src/server/Map/MonsterModel.luau. Transform does not replicate, so this is looks only.
-- Joint frames use the root's axes: +X pitch swings a hanging limb forward (-Z), lifts a forward-pointing head,
-- and tips the spine backward; +Z roll moves a hanging limb toward +X.
-- The monster can appear late (joining mid-round, streaming) or be rebuilt: the rig is re-found whenever it goes
-- missing or a joint is gone, checked every SEARCH_INTERVAL seconds.
-- See design-vault/Mechanics/Routes, Exits and Dread.md, "Animation (sprint 37)".
local RunService = game:GetService("RunService")

local MonsterAnimator = {}

local JOINTS = {
	"Root",
	"Spine",
	"Neck",
	"Jaw",
	"LeftShoulder",
	"RightShoulder",
	"LeftElbow",
	"RightElbow",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
}
local SEARCH_INTERVAL = 0.5
local MAX_ANIM_DISTANCE = 250 -- farther from the camera than this it is not animated (it parks 200 past the exit)

-- How fast state blend weights follow the current state (per second, exponential).
local BLEND_RATE = 5
local KILL_BLEND_RATE = 14
local SPEED_RATE = 6

-- Per-state pose targets (radians). lean: spine pitch forward; reach: arms raised ahead; tilt: listen head tilt.
type Pose = { lean: number, reach: number, listen: number, kill: number, lurch: number }
local POSES: { [string]: Pose } = {
	Idle = { lean = 0.05, reach = 0, listen = 0, kill = 0, lurch = 0 },
	Patrol = { lean = 0.12, reach = 0, listen = 0, kill = 0, lurch = 1 },
	Chase = { lean = 0.38, reach = 1.15, listen = 0, kill = 0, lurch = 0 },
	Lunge = { lean = 0.6, reach = 1.45, listen = 0, kill = 0, lurch = 0 },
	Listen = { lean = -0.06, reach = 0.15, listen = 1, kill = 0, lurch = 0 },
	Kill = { lean = 0.35, reach = 1.3, listen = 0, kill = 1, lurch = 0 },
}

-- Gait: stride frequency (Hz) and swing amplitude (radians) grow with speed.
local STRIDE_HZ_BASE = 0.3
local STRIDE_HZ_PER_SPEED = 0.09
local STRIDE_HZ_MAX = 2.6
local STRIDE_BASE = math.rad(16)
local STRIDE_PER_SPEED = math.rad(1.1)
local STRIDE_MAX = math.rad(46)
local MOVING_SPEED = 0.4 -- below this (studs/s) the legs settle

-- Jaw: hangs open slowly, then snaps shut.
local JAW_HANG_MIN = 2.2
local JAW_HANG_MAX = 4
local JAW_HANG_OPEN = math.rad(24)
local JAW_SNAP_HOLD = 0.25
local JAW_KILL_OPEN = math.rad(62)
local JAW_KILL_SNAP_PERIOD = 0.4
local JAW_KILL_SNAP_TIME = 0.1
local JAW_RATE = 30

-- Head twitch: random jerks, big while listening, small always.
local TWITCH_LISTEN = 0.4
local TWITCH_BASE = 0.07
local TWITCH_HOLD = 0.09
local TWITCH_RATE = 35

type Rig = { root: BasePart, motors: { [string]: Motor6D } }

local started = false
local rng = Random.new()

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function findRig(): Rig?
	local hall = workspace:FindFirstChild("Hall")
	local root = hall and hall:FindFirstChild("Monster")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local motors: { [string]: Motor6D } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	return { root = root, motors = motors }
end

-- Valid while the root is in the world and every joint it had is still attached to it.
local function rigComplete(rig: Rig): boolean
	if not rig.root:IsDescendantOf(workspace) then
		return false
	end
	for _, name in JOINTS do
		local m = rig.motors[name]
		if not m or not m:IsDescendantOf(rig.root) then
			return false
		end
	end
	return true
end

function MonsterAnimator.start()
	if started then
		return
	end
	started = true

	local rig: Rig? = nil
	local nextSearch = 0

	-- Blend weights per state, and smoothed values.
	local weights: { [string]: number } = { Idle = 1 }
	local speed = 0
	local phase = 0
	local t = 0

	local jawOpen = 0
	local jawCycle = 0
	local jawHang = JAW_HANG_MIN
	local twitch = Vector3.zero
	local twitchTarget = Vector3.zero
	local nextTwitch = 0
	local twitchRelease = 0

	local function setTransform(name: string, cf: CFrame)
		local current = rig
		local m = current and current.motors[name]
		if m then
			m.Transform = cf
		end
	end

	RunService.RenderStepped:Connect(function(dt: number)
		t += dt
		local current = rig
		if not current or not rigComplete(current) then
			if t < nextSearch then
				return
			end
			nextSearch = t + SEARCH_INTERVAL
			current = findRig()
			rig = current
			if not current or next(current.motors) == nil then
				return -- not here yet, or the fallback cube (no joints)
			end
		end

		local root = current.root
		local camera = workspace.CurrentCamera
		if camera and (camera.CFrame.Position - root.Position).Magnitude > MAX_ANIM_DISTANCE then
			return
		end

		-- Inputs from the server.
		local stateAttr = root:GetAttribute("State")
		local state = if typeof(stateAttr) == "string" and POSES[stateAttr] then stateAttr else "Idle"
		local speedAttr = root:GetAttribute("Speed")
		speed = approach(speed, if typeof(speedAttr) == "number" then math.max(speedAttr, 0) else 0, SPEED_RATE, dt)

		-- Blend toward the current state's pose.
		local pose = { lean = 0, reach = 0, listen = 0, kill = 0, lurch = 0 }
		local total = 0
		for name, target in POSES do
			local rate = if name == "Kill" or state == "Kill" then KILL_BLEND_RATE else BLEND_RATE
			local w = approach(weights[name] or 0, if name == state then 1 else 0, rate, dt)
			weights[name] = w
			total += w
			pose.lean += target.lean * w
			pose.reach += target.reach * w
			pose.listen += target.listen * w
			pose.kill += target.kill * w
			pose.lurch += target.lurch * w
		end
		if total > 0 then
			pose.lean /= total
			pose.reach /= total
			pose.listen /= total
			pose.kill /= total
			pose.lurch /= total
		end

		-- Gait.
		local moving = math.clamp(speed / MOVING_SPEED, 0, 1) * (1 - pose.listen)
		local hz = math.min(STRIDE_HZ_BASE + speed * STRIDE_HZ_PER_SPEED, STRIDE_HZ_MAX)
		phase = (phase + dt * hz * 2 * math.pi) % (2 * math.pi)
		local stride = math.min(STRIDE_BASE + speed * STRIDE_PER_SPEED, STRIDE_MAX) * moving
		local s = math.sin(phase)
		local c = math.cos(phase)
		-- Patrol lurch: the right leg drags and the body drops hard onto it.
		local lurch = pose.lurch * moving
		local hitch = math.max(0, -s) ^ 3 * lurch

		local bob = -math.abs(s) * 0.22 * moving - hitch * 0.35
		local sway = s * math.rad(5) * moving + hitch * math.rad(7)
		setTransform("Root", CFrame.new(0, bob, 0) * CFrame.Angles(0, -s * math.rad(4) * moving, sway))

		-- Spine: lean forward (negative pitch), counter-twist with the stride, a slow breath.
		local breath = math.sin(t * 1.4) * math.rad(1.5)
		local lean = pose.lean + hitch * 0.12 + math.abs(c) * 0.05 * moving
		setTransform("Spine", CFrame.Angles(-lean + breath, s * math.rad(6) * moving, 0))

		-- Head twitch.
		if t >= nextTwitch then
			local amp = TWITCH_BASE + (TWITCH_LISTEN - TWITCH_BASE) * pose.listen
			twitchTarget = Vector3.new(rng:NextNumber(-1, 1) * 0.5, rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * amp
			twitchRelease = t + TWITCH_HOLD
			local gap = if pose.listen > 0.5 then rng:NextNumber(0.25, 0.9) else rng:NextNumber(0.8, 2.5)
			nextTwitch = t + gap
		elseif t >= twitchRelease then
			twitchTarget = Vector3.zero
		end
		twitch = Vector3.new(
			approach(twitch.X, twitchTarget.X, TWITCH_RATE, dt),
			approach(twitch.Y, twitchTarget.Y, TWITCH_RATE, dt),
			approach(twitch.Z, twitchTarget.Z, TWITCH_RATE, dt)
		)

		-- Neck: hold the head up against the lean, tilt side to side while listening.
		local tilt = math.sin(t * 1.6) * math.rad(28) * pose.listen
		local listenYaw = math.sin(t * 0.7 + 1) * math.rad(18) * pose.listen
		local neckPitch = pose.lean * 0.7 + math.rad(8) * pose.listen + c * math.rad(3) * moving
		setTransform(
			"Neck",
			CFrame.Angles(neckPitch + twitch.X, listenYaw + twitch.Y, tilt + twitch.Z + hitch * math.rad(-10))
		)

		-- Jaw: slow hang then snap; wide snapping on a kill.
		jawCycle += dt * (1 + pose.reach * 0.6)
		local jawTarget
		if jawCycle < jawHang then
			local k = jawCycle / jawHang
			jawTarget = math.rad(3) + JAW_HANG_OPEN * k * k * (3 - 2 * k)
		else
			jawTarget = 0
			if jawCycle >= jawHang + JAW_SNAP_HOLD then
				jawCycle = 0
				jawHang = rng:NextNumber(JAW_HANG_MIN, JAW_HANG_MAX)
			end
		end
		local killJaw = if (t % JAW_KILL_SNAP_PERIOD) < JAW_KILL_SNAP_TIME then math.rad(4) else JAW_KILL_OPEN
		jawTarget = jawTarget + (killJaw - jawTarget) * pose.kill
		jawOpen = approach(jawOpen, jawTarget, JAW_RATE, dt)
		setTransform("Jaw", CFrame.Angles(-jawOpen, 0, 0))

		-- Arms and legs, per side. Left leg leads with sin(phase); the arms swing opposite their leg.
		for _, side in { -1, 1 } do
			local full = if side < 0 then "Left" else "Right"
			local legPhase = if side < 0 then phase else phase + math.pi
			local ls = math.sin(legPhase)
			local lc = math.cos(legPhase)
			local drag = if side > 0 then lurch else 0 -- the dragging leg barely lifts

			local swing = ls * stride * (1 - 0.35 * drag)
			setTransform(full .. "Hip", CFrame.Angles(swing, 0, side * math.rad(2) * drag))
			local lift = math.max(0, lc) * (stride * 1.6) * (1 - 0.7 * drag)
			setTransform(full .. "Knee", CFrame.Angles(-lift - math.rad(4) * moving, 0, 0))

			-- Arms: loose swing on patrol, reaching ahead (and clawing) on chase, lunge and kill.
			local reach = pose.reach
			local armSwing = -ls * stride * 0.8 * (1 - 0.7 * math.min(reach, 1))
			local claw = math.sin(t * 9 + side) * math.rad(6) * reach * moving
			local grab = math.sin(t * 14 + side * 1.3) * math.rad(10) * pose.kill
			local spread = side * (math.rad(6) * reach + math.rad(10) * pose.listen)
			local listenTwitch = twitch.Z * 0.5 * pose.listen * side
			setTransform(full .. "Shoulder", CFrame.Angles(reach + armSwing + claw + grab, 0, spread + listenTwitch))
			local elbow = math.rad(8) + math.max(0, -armSwing) * 0.5 + math.rad(20) * pose.kill - math.rad(6) * reach
			setTransform(full .. "Elbow", CFrame.Angles(elbow + grab * 0.8, 0, 0))
		end
	end)
end

return MonsterAnimator

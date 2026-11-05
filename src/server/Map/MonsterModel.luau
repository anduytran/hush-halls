--!strict
-- Visual body for the monster: a tall, gaunt, eyeless creature built from parts.
-- MonsterModel.attach(root) builds a jointed rig and returns a Model named "Body" parented under root.
-- All parts are Massless and do not collide, query or touch, so the root keeps driving movement and hit detection.
-- Local space: root centre is the origin, floor is Y = -3, the creature faces -Z.
-- Sprint 37: limbs hang on named Motor6Ds (MonsterModel.JOINTS) that src/client/MonsterAnimator.luau drives through
-- Motor6D.Transform. Every joint's C0/C1 is a frame at the pivot with the root's axes, so a Transform rotates in the
-- root's space: +X pitch swings a hanging limb forward (-Z). Smaller pieces ride their segment on WeldConstraints.
-- Tree: Root (root->Pelvis), Spine (Pelvis->Abdomen), Neck (Chest->Neck), Jaw (Head->Jaw),
-- Left/RightShoulder (Chest->UpperArm), Left/RightElbow (UpperArm->Forearm), Left/RightHip (Pelvis->Thigh),
-- Left/RightKnee (Thigh->Shin).

local MonsterModel = {}

local SKIN = Color3.fromRGB(28, 28, 31)
local SKIN_DARK = Color3.fromRGB(18, 18, 20)
local TEETH = Color3.fromRGB(148, 138, 116)
local MOUTH = Color3.fromRGB(70, 6, 8)

-- Motor6D names; the client animator looks these up by name.
MonsterModel.JOINTS = {
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

-- offsets: each part's rest CFrame in root space, used to place joints.
type Ctx = { root: BasePart, model: Model, offsets: { [BasePart]: CFrame } }

local function finish(ctx: Ctx, p: BasePart, name: string, color: Color3, material: Enum.Material, offset: CFrame)
	p.Name = name
	p.Color = color
	p.Material = material
	p.Reflectance = if material == Enum.Material.SmoothPlastic then 0.03 else 0
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = ctx.root.CFrame * offset
	p.Parent = ctx.model
	ctx.offsets[p] = offset
end

-- Rigid: `part` keeps its rest pose relative to `to` (both already placed).
local function rigid(part: BasePart, to: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
end

-- A Motor6D from part0 to part1 pivoting at `pivot` (root space). part0 may be the root itself.
local function motor(ctx: Ctx, name: string, part0: BasePart, part1: BasePart, pivot: Vector3)
	local at = CFrame.new(pivot)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = (ctx.offsets[part0] or CFrame.identity):Inverse() * at
	m.C1 = ctx.offsets[part1]:Inverse() * at
	m.Parent = part1
end

local function block(
	ctx: Ctx,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3?,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Size = size
	finish(ctx, p, name, color or SKIN, material or Enum.Material.SmoothPlastic, offset)
	return p
end

local function ball(ctx: Ctx, name: string, diameter: number, pos: Vector3, color: Color3?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	finish(ctx, p, name, color or SKIN, Enum.Material.SmoothPlastic, CFrame.new(pos))
	return p
end

-- A limb segment from a to b (local space), w wide and d deep.
local function limb(ctx: Ctx, name: string, a: Vector3, b: Vector3, w: number, d: number, color: Color3?): Part
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b, Vector3.new(0, 0, -1))
	if math.abs((b - a).Unit:Dot(Vector3.new(0, 0, -1))) > 0.95 then
		cf = CFrame.lookAt(mid, b)
	end
	-- Long axis on Z; w/d across it.
	return block(ctx, name, Vector3.new(w, d, len), cf, color)
end

function MonsterModel.attach(root: BasePart): Model
	local existing = root:FindFirstChild("Body")
	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "Body"
	local ctx: Ctx = { root = root, model = model, offsets = {} }

	-- Pelvis, abdomen and a hunched chest leaning forward.
	local pelvis = block(ctx, "Pelvis", Vector3.new(2, 0.7, 1), CFrame.new(0, 1.9, 0.2), SKIN_DARK)
	motor(ctx, "Root", root, pelvis, Vector3.new(0, 1.9, 0.2))
	local abdomen = limb(ctx, "Abdomen", Vector3.new(0, 2.1, 0.2), Vector3.new(0, 3.7, -0.3), 1.2, 0.8)
	motor(ctx, "Spine", pelvis, abdomen, Vector3.new(0, 2.1, 0.2))
	local chest = limb(ctx, "Chest", Vector3.new(0, 3.4, -0.2), Vector3.new(0, 5.0, -1.3), 2.4, 1.3, SKIN_DARK)
	chest.Material = Enum.Material.Slate
	chest.Reflectance = 0
	rigid(chest, abdomen)

	-- Legs: gaunt, knees bent forward, feet flat on the floor (Y = -3).
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local full = if side < 0 then "Left" else "Right"
		local hip = Vector3.new(0.8 * side, 1.8, 0.2)
		local knee = Vector3.new(0.9 * side, -0.2, -0.45)
		local ankle = Vector3.new(0.9 * side, -2.6, 0.1)
		local thigh = limb(ctx, "Thigh" .. tag, hip, knee, 0.6, 0.6)
		local shin = limb(ctx, "Shin" .. tag, knee, ankle, 0.45, 0.45)
		local foot =
			block(ctx, "Foot" .. tag, Vector3.new(0.7, 0.3, 1.4), CFrame.new(0.9 * side, -2.85, -0.3), SKIN_DARK)
		motor(ctx, full .. "Hip", pelvis, thigh, hip)
		motor(ctx, full .. "Knee", thigh, shin, knee)
		rigid(foot, shin)
	end

	-- Vertebrae poking through the hunched back.
	rigid(ball(ctx, "Vertebra1", 0.5, Vector3.new(0, 3.9, 0.3)), abdomen)
	rigid(ball(ctx, "Vertebra2", 0.55, Vector3.new(0, 4.6, -0.15)), chest)
	rigid(ball(ctx, "Vertebra3", 0.5, Vector3.new(0, 5.25, -0.75)), chest)

	-- Long thin arms hanging nearly to the floor, with long fingers.
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local full = if side < 0 then "Left" else "Right"
		local shoulder = Vector3.new(1.35 * side, 4.75, -1.0)
		local elbow = Vector3.new(1.65 * side, 2.0, -1.35)
		local wrist = Vector3.new(1.55 * side, -1.0, -1.65)
		local palm = Vector3.new(1.55 * side, -1.75, -1.75)
		rigid(ball(ctx, "Shoulder" .. tag, 0.8, shoulder, SKIN_DARK), chest)
		local upper = limb(ctx, "UpperArm" .. tag, shoulder, elbow, 0.45, 0.45)
		motor(ctx, full .. "Shoulder", chest, upper, shoulder)
		rigid(ball(ctx, "Elbow" .. tag, 0.5, elbow), upper)
		local forearm = limb(ctx, "Forearm" .. tag, elbow, wrist, 0.38, 0.38)
		motor(ctx, full .. "Elbow", upper, forearm, elbow)
		rigid(limb(ctx, "Hand" .. tag, wrist, palm, 0.6, 0.25, SKIN_DARK), forearm)
		for i, dx in { -0.22, 0, 0.22 } do
			local base = palm + Vector3.new(dx, 0.1, 0)
			local tip = Vector3.new(palm.X + dx * 1.6, -2.75, palm.Z - 0.25 + math.abs(dx))
			rigid(limb(ctx, "Finger" .. tag .. i, base, tip, 0.14, 0.14, SKIN_DARK), forearm)
		end
	end

	-- Neck thrust forward, wide eyeless head, gaping jaw.
	local neck = limb(ctx, "Neck", Vector3.new(0, 4.9, -1.2), Vector3.new(0, 5.35, -2.0), 0.6, 0.6)
	motor(ctx, "Neck", chest, neck, Vector3.new(0, 4.9, -1.2))
	local head = block(
		ctx,
		"Head",
		Vector3.new(2.7, 0.8, 1.9),
		CFrame.new(0, 5.5, -2.45) * CFrame.Angles(math.rad(-14), 0, 0),
		SKIN_DARK,
		Enum.Material.Slate
	)
	head.Reflectance = 0
	rigid(head, neck)
	rigid(ball(ctx, "Cranium", 1.3, Vector3.new(0, 5.6, -1.9)), head)

	local hinge = CFrame.new(0, 5.0, -1.75)
	local jaw = block(
		ctx,
		"Jaw",
		Vector3.new(2.1, 0.35, 1.6),
		hinge * CFrame.Angles(math.rad(-38), 0, 0) * CFrame.new(0, 0, -0.8),
		SKIN
	)
	motor(ctx, "Jaw", head, jaw, hinge.Position)

	local mouth = block(
		ctx,
		"Mouth",
		Vector3.new(1.8, 0.25, 1.2),
		CFrame.new(0, 4.85, -2.3) * CFrame.Angles(math.rad(-18), 0, 0),
		MOUTH
	)
	mouth.Reflectance = 0
	rigid(mouth, head)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 40, 30)
	glow.Brightness = 1.2
	glow.Range = 7
	glow.Shadows = false
	glow.Parent = mouth

	-- Upper teeth, on the head; the jaw drops away below them.
	for i, x in { -0.75, -0.25, 0.25, 0.75 } do
		local tooth = block(
			ctx,
			"Tooth" .. i,
			Vector3.new(0.14, 0.45, 0.14),
			CFrame.new(x, 4.85, -3.1) * CFrame.Angles(0, 0, math.rad(x * 6)),
			TEETH,
			Enum.Material.SmoothPlastic
		)
		rigid(tooth, head)
	end

	model.PrimaryPart = pelvis
	model.Parent = root
	return model
end

return MonsterModel

--!strict
-- Builds the greybox hall: a 24-stud-wide, 300-stud-long corridor running along +Z.
-- It has three straight segments joined by two side-step turns (the corridor jogs 12 studs
-- sideways at z=100 and back at z=200), plus pillar and crate obstacles.
-- Named children: Start (SpawnLocation at z=0), Floor (top at Y=0), Exit (neon trigger at the far end),
-- Walls, Obstacles and Hazards.
-- Sprint 34: three obstacle layouts. HallBuilder.buildLayout(index) rebuilds Hall.Obstacles and Hall.Hazards
-- (puddles tagged "Puddle", planks tagged "Plank"; Hazards.luau gives them their noise). Start, Exit, Floor
-- and Walls are never touched. Hall's "Layout" attribute is the layout in use.
-- Sprint 35 (Map Overhaul): dressed as a flooded school. The footprint, turn openings and contracts above are
-- unchanged. Extra children: Ceiling (at WALL_HEIGHT) and Dressing (floor tiles, wainscot, lockers, classroom
-- doorways, lamps, notice boards, the exit door; all built with Map/Props). Pillars are now piles of toppled
-- lockers and crates are desk piles, each no wider in X than the old obstacle, so with the 2.2-deep locker rows
-- every layout still keeps a 12-stud walking gap. The classrooms sit behind walls inside Hall.Floor's footprint,
-- so the water (and drowning) reaches them too.
-- Sprint 36 (Routes, Exits and Dread): a parallel back corridor (x -40..-28, z 34..282) west of the main hall,
-- joined to it by two cross halls (z 40..52 and 212..224) and by two classrooms with a doorway on each side
-- (z 80..100 and 240..264), so there are 3+ paths from Start. A gym opens off the back corridor. Extra exits are
-- invisible trigger BaseParts in Hall.Exits: FireExit (gym west wall) and BrokenWindow (north wall of the second
-- classroom), each with a green EXIT sign. Hall.Exit stays the main exit. Shortest walks from Start are about
-- 270 (fire exit), 275 (window) and 305 (main). Hall.Floor still covers the whole footprint (the water uses it).
-- To stay under 2,000 parts: one floor overlay per section instead of checker tiles, and the wall lockers are
-- cheap banks (one body, a door, vent and handle per locker) instead of 14-part Props lockers.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Props = require(script.Parent.Props)

local HallBuilder = {}

local WIDTH = 24
local LENGTH = 300
local WALL_HEIGHT = 20
local WALL_THICKNESS = 2
local STEP = 12 -- how far the middle segment is shifted along +X

local FLOOR_CREAM = Color3.fromRGB(196, 190, 172)
local FLOOR_GREY = Color3.fromRGB(104, 108, 106)
local FLOOR_SECTION = FLOOR_CREAM:Lerp(FLOOR_GREY, 0.45) -- worn linoleum, one overlay per section
local FLOOR_ROOM = Color3.fromRGB(58, 58, 54)
local FLOOR_GYM = Color3.fromRGB(150, 112, 70)
local TILE_THICKNESS = 0.02 -- floor overlays are thin, non-colliding parts on the cream Floor
local LOCKER_GREEN = Color3.fromRGB(84, 104, 88)
local LOCKER_DOOR = Color3.fromRGB(94, 114, 96)
local LOCKER_DARK = Color3.fromRGB(38, 46, 40)
local STEEL = Color3.fromRGB(170, 172, 168)
local CHALK_GREEN = Color3.fromRGB(34, 52, 42)
local EXIT_GREEN = Color3.fromRGB(40, 255, 110)
local NIGHT = Color3.fromRGB(14, 20, 34)
local PLASTER = Color3.fromRGB(214, 202, 172)
local CEILING_COLOR = Color3.fromRGB(150, 146, 132)
local WOOD_DARK = Color3.fromRGB(66, 44, 30)
local WAINSCOT_HEIGHT = 3.5
local DOOR_HALF = 7 -- classroomDoorway is 14 wide; the wall is cut over that span
local DOOR_TOP = 11 -- ...and up to this height (the doorway's own front wall and lintel fill it)
local ROOM_LIFT = 0.03 -- room floors sit just above Hall.Floor so the two floor tops don't z-fight
local LOCKER_REACH = 1 -- a locker's centre sits this far off the wall (its handles reach about 2.2)
local LAMP_SPACING = 25
local FLICKER_TAG = "FlickerLamp"
local PUDDLE_COLOR = Color3.fromRGB(45, 110, 190)
local PUDDLE_TRANSPARENCY = 0.35
local PUDDLE_SIZE = Vector3.new(6, 0.1, 5) -- flat, sitting on the floor; walk-through
local PLANK_COLOR = Color3.fromRGB(110, 74, 42)
local PLANK_SIZE = Vector3.new(3, 0.3, 8) -- slightly raised; low enough to step onto

-- Sprint 36 routes (see the header). Interiors are given; walls are WALL_THICKNESS outside them.
local BACK_X0, BACK_X1 = -40, -28 -- back corridor
local BACK_Z0, BACK_Z1 = 34, 282
local LINK_X0, LINK_X1 = -26, -14 -- cross halls and link classrooms, between the two corridors
local GYM_X0, GYM_X1 = -70, -42
local GYM_Z0, GYM_Z1 = 216, 262
local GYM_DOOR = { 222, 234 } -- opening in the back corridor's west wall
local FIRE_EXIT_Z = 250 -- centre of the fire exit on the gym's west wall
local CROSS_TOP = 15 -- cross hall and gym openings are cut up to this height
local LINK_DOOR_HALF = 4 -- link classroom doorways are 8 wide, up to DOOR_TOP
local CROSS_HALLS = { { 40, 52 }, { 212, 224 } }
type LinkRoom = { z0: number, z1: number, door: number, window: boolean? }
local LINK_ROOMS: { LinkRoom } = {
	{ z0 = 80, z1 = 100, door = 88 },
	{ z0 = 240, z1 = 264, door = 246, window = true }, -- broken window in the north wall
}
local WINDOW_X0, WINDOW_X1 = -23, -17 -- broken window in LINK_ROOMS[2]'s north wall
local WINDOW_SILL, WINDOW_TOP = 3, 9

export type Obstacle = { kind: "Pillar" | "Crate", x: number, z: number, size: number? }
export type Layout = {
	obstacles: { Obstacle },
	puddles: { Vector3 }, -- centres on the floor (Y ignored)
	planks: { Vector3 },
}

-- Each layout keeps at least a 12-stud gap beside every obstacle, keeps clear of the turn openings
-- (x 0..12 at z=100 and z=200), Start (z=0) and Exit (z 296..300), and has 4-6 puddles and 4-6 planks.
-- Hazards are walk-through, so they never block the route. Layout 1 is the original greybox placement.
-- Sprint 36: the main hall's left wall now has openings at z 40..52, 84..92, 212..224 and 242..250. Obstacles at
-- x -6 are 2 wide either side, so a 4-stud gap stays along that wall and every opening can still be reached.
local LAYOUTS: { Layout } = {
	{
		obstacles = {
			{ kind = "Pillar", x = -6, z = 30 },
			{ kind = "Crate", x = 6, z = 58, size = 6 },
			{ kind = "Crate", x = -5, z = 80, size = 5 },
			{ kind = "Pillar", x = 18, z = 130 },
			{ kind = "Crate", x = 6, z = 165, size = 6 },
			{ kind = "Pillar", x = -6, z = 235 },
			{ kind = "Crate", x = 6, z = 265, size = 5 },
		},
		puddles = {
			Vector3.new(6, 0, 30),
			Vector3.new(-6, 0, 62),
			Vector3.new(8, 0, 145),
			Vector3.new(16, 0, 180),
			Vector3.new(5, 0, 245),
		},
		planks = {
			Vector3.new(-6, 0, 45),
			Vector3.new(6, 0, 92),
			Vector3.new(12, 0, 115),
			Vector3.new(-5, 0, 215),
			Vector3.new(-4, 0, 280),
		},
	},
	{
		obstacles = {
			{ kind = "Pillar", x = 6, z = 40 },
			{ kind = "Crate", x = -6, z = 65, size = 6 },
			{ kind = "Crate", x = 6, z = 75, size = 5 },
			{ kind = "Pillar", x = 6, z = 140 },
			{ kind = "Crate", x = 18, z = 175, size = 6 },
			{ kind = "Pillar", x = 6, z = 225 },
			{ kind = "Crate", x = -6, z = 255, size = 6 },
			{ kind = "Pillar", x = 6, z = 280 },
		},
		puddles = {
			Vector3.new(-6, 0, 30),
			Vector3.new(6, 0, 58),
			Vector3.new(16, 0, 125),
			Vector3.new(6, 0, 185),
			Vector3.new(-6, 0, 240),
			Vector3.new(4, 0, 268),
		},
		planks = {
			Vector3.new(6, 0, 20),
			Vector3.new(-6, 0, 90),
			Vector3.new(20, 0, 150),
			Vector3.new(-6, 0, 210),
			Vector3.new(6, 0, 250),
		},
	},
	{
		obstacles = {
			{ kind = "Crate", x = -6, z = 25, size = 6 },
			{ kind = "Pillar", x = 6, z = 50 },
			{ kind = "Pillar", x = -6, z = 75 },
			{ kind = "Crate", x = 18, z = 120, size = 6 },
			{ kind = "Pillar", x = 6, z = 155 },
			{ kind = "Crate", x = 18, z = 185, size = 5 },
			{ kind = "Pillar", x = 6, z = 240 },
			{ kind = "Crate", x = -6, z = 270, size = 5 },
		},
		puddles = {
			Vector3.new(6, 0, 25),
			Vector3.new(-6, 0, 50),
			Vector3.new(6, 0, 75),
			Vector3.new(6, 0, 135),
			Vector3.new(-6, 0, 225),
			Vector3.new(0, 0, 285),
		},
		planks = {
			Vector3.new(-6, 0, 40),
			Vector3.new(16, 0, 105),
			Vector3.new(8, 0, 170),
			Vector3.new(-6, 0, 250),
		},
	},
}

HallBuilder.LAYOUT_COUNT = #LAYOUTS

-- Creates an anchored part from its min/max corners.
local function box(
	parent: Instance,
	name: string,
	minCorner: Vector3,
	maxCorner: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = maxCorner - minCorner
	part.Position = (minCorner + maxCorner) / 2
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function wall(parent: Instance, name: string, x0: number, x1: number, z0: number, z1: number)
	if x1 - x0 <= 0.01 or z1 - z0 <= 0.01 then
		return
	end
	box(parent, name, Vector3.new(x0, 0, z0), Vector3.new(x1, WALL_HEIGHT, z1), PLASTER, Enum.Material.Plaster)
end

-- An opening in a wall along Z: { zFrom, zTo, top }. The wall above `top` stays as a "<name>Lintel".
type Opening = { number }

-- A wall running along Z (x0..x1, z0..z1) with openings cut through it.
local function wallZ(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	openings: { Opening }
)
	local spans = table.clone(openings)
	table.sort(spans, function(p, q)
		return p[1] < q[1]
	end)
	local z = z0
	for _, o in spans do
		wall(parent, name, x0, x1, z, o[1])
		box(
			parent,
			name .. "Lintel",
			Vector3.new(x0, o[3], o[1]),
			Vector3.new(x1, WALL_HEIGHT, o[2]),
			PLASTER,
			Enum.Material.Plaster
		)
		z = o[2]
	end
	wall(parent, name, x0, x1, z, z1)
end

-- A wall running along Z with classroom openings (centre z values). Each opening is cut DOOR_HALF either side
-- and up to DOOR_TOP; the wall above it stays as a "<name>Lintel".
local function wallWithDoors(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	doors: { number }
)
	local openings: { Opening } = {}
	for _, door in doors do
		table.insert(openings, { door - DOOR_HALF, door + DOOR_HALF, DOOR_TOP })
	end
	wallZ(parent, name, x0, x1, z0, z1, openings)
end

-- A dressing part: anchored, no collision, queries or touches.
local function trim(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- `count` wall lockers side by side along cf.RightVector, centred on cf, front along cf.LookVector, base at cf.Y.
-- Same size and colours as Props.lockerRow, but one shared body: 3 + 3 * count parts instead of 14 * count.
local function lockerBank(parent: Instance, cf: CFrame, count: number): Model
	local model = Instance.new("Model")
	model.Name = "LockerRow"
	local width = count * 2
	local metal = Enum.Material.Metal
	local base = trim(model, "Base", Vector3.new(width, 0.3, 1.9), cf * CFrame.new(0, 0.15, 0.05), LOCKER_DARK, metal)
	trim(model, "Body", Vector3.new(width, 6.6, 2), cf * CFrame.new(0, 3.6, 0), LOCKER_GREEN, metal)
	trim(model, "Cap", Vector3.new(width, 0.1, 2.1), cf * CFrame.new(0, 6.95, -0.05), LOCKER_DARK, metal)
	for i = 1, count do
		local x = (i - 1 - (count - 1) / 2) * 2
		local shade = 1 + ((i * 37) % 7 - 3) * 0.025
		local door = Color3.new(
			math.clamp(LOCKER_DOOR.R * shade, 0, 1),
			math.clamp(LOCKER_DOOR.G * shade, 0, 1),
			math.clamp(LOCKER_DOOR.B * shade, 0, 1)
		)
		trim(model, "Door", Vector3.new(1.76, 6.3, 0.08), cf * CFrame.new(x, 3.6, -1.04), door, metal)
		trim(model, "Vents", Vector3.new(1.1, 0.6, 0.05), cf * CFrame.new(x, 6.0, -1.09), LOCKER_DARK, metal)
		trim(model, "Handle", Vector3.new(0.12, 0.6, 0.14), cf * CFrame.new(x + 0.6, 3.7, -1.15), STEEL, metal)
	end
	-- the lockers stand against the wall, so they block like the Props ones did
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "Body" or d.Name == "Base") then
			d.CanCollide = true
			d.CanQuery = true
		end
	end
	model.PrimaryPart = base
	model.Parent = parent
	return model
end

-- A green EXIT sign (box, neon face with text, light). Front along cf.LookVector, centred on cf.
local function exitSign(parent: Instance, cf: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "ExitSign"
	local signBox = trim(
		model,
		"SignBox",
		Vector3.new(4.4, 1.5, 0.5),
		cf * CFrame.new(0, 0, 0.1),
		Color3.fromRGB(30, 34, 32),
		Enum.Material.Metal
	)
	local face = trim(
		model,
		"SignFace",
		Vector3.new(4, 1.15, 0.06),
		cf * CFrame.new(0, 0, -0.18),
		EXIT_GREEN,
		Enum.Material.Neon
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = face
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "EXIT"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 255, 240)
	label.Parent = gui
	local light = Instance.new("PointLight")
	light.Color = EXIT_GREEN
	light.Brightness = 2
	light.Range = 16
	light.Parent = face
	model.PrimaryPart = signBox
	model.Parent = parent
	return model
end

-- An invisible, walk-through escape trigger from its min/max corners (RoundService connects its Touched).
local function exitTrigger(parent: Instance, name: string, minCorner: Vector3, maxCorner: Vector3): Part
	local part = box(parent, name, minCorner, maxCorner, Color3.fromRGB(0, 255, 90), Enum.Material.Neon)
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	return part
end

-- A corridor-facing wall face: from `a` to `b` on the floor (Y=0), `normal` points into the corridor.
-- `skip` lists spans (distance along the face from `a`) that get no wainscot, e.g. doorways.
type Face = { a: Vector3, b: Vector3, normal: Vector3, skip: { { number } }? }

-- CFrame on a wall face at height y, `along` studs from face.a, looking into the corridor.
local function faceFrame(face: Face, along: number, y: number, out: number): CFrame
	local dir = (face.b - face.a).Unit
	local pos = face.a + dir * along + face.normal * out + Vector3.new(0, y, 0)
	return CFrame.lookAt(pos, pos + face.normal)
end

local function wainscotSpan(parent: Instance, face: Face, s0: number, s1: number)
	local length = s1 - s0
	if length <= 0.05 then
		return
	end
	local mid = (s0 + s1) / 2
	local panel = Instance.new("Part")
	panel.Name = "Wainscot"
	panel.Size = Vector3.new(length, WAINSCOT_HEIGHT, 0.15)
	panel.CFrame = faceFrame(face, mid, WAINSCOT_HEIGHT / 2, 0.075)
	local rail = Instance.new("Part")
	rail.Name = "ChairRail"
	rail.Size = Vector3.new(length, 0.3, 0.3)
	rail.CFrame = faceFrame(face, mid, WAINSCOT_HEIGHT + 0.15, 0.15)
	for _, p in { panel, rail } do
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = WOOD_DARK
		p.Material = Enum.Material.Wood
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
	end
end

-- Dark wood panelling along a face, leaving its skip spans bare.
local function wainscot(parent: Instance, face: Face)
	local length = (face.b - face.a).Magnitude
	local s = 0
	local spans = table.clone(face.skip or {})
	table.sort(spans, function(p, q)
		return p[1] < q[1]
	end)
	for _, span in spans do
		wainscotSpan(parent, face, s, span[1])
		s = math.max(s, span[2])
	end
	wainscotSpan(parent, face, s, length)
end

-- Locker rows (and a notice board in every other gap) along a face, between `from` and `to` (distance from
-- face.a), keeping out of `blocked` spans. Rows are 5 lockers (10 studs) with 7-stud gaps. `sparse` (the back
-- corridor) uses 12-stud gaps and no notice boards, to stay inside the part budget.
local function dressFace(
	parent: Instance,
	face: Face,
	from: number,
	to: number,
	blocked: { { number } },
	sparse: boolean?
)
	local free: { { number } } = {}
	local s = from
	local spans = table.clone(blocked)
	table.sort(spans, function(p, q)
		return p[1] < q[1]
	end)
	for _, span in spans do
		if span[1] > s then
			table.insert(free, { s, math.min(span[1], to) })
		end
		s = math.max(s, span[2])
	end
	if to > s then
		table.insert(free, { s, to })
	end

	local board = false
	for _, interval in free do
		local a, b = interval[1], interval[2]
		while true do
			local count = math.min(5, math.floor((b - a) / 2))
			if count < 2 then
				break
			end
			lockerBank(parent, faceFrame(face, a + count, 0, LOCKER_REACH), count)
			a += count * 2
			local gap = if sparse then 12 else 7
			if a + gap > b then
				break
			end
			board = not board
			if board and not sparse then
				Props.noticeBoard(parent, faceFrame(face, a + gap / 2, 4, 0))
			end
			a += gap
		end
	end
end

-- One thin floor overlay per section rectangle { xMin, xMax, zMin, zMax, color?, material? } over the cream Floor.
-- (Sprint 36: replaces the per-tile checker, which alone was 231 parts.)
type FloorRect = { any }
local function floorSections(parent: Instance, rects: { FloorRect })
	local folder = Instance.new("Folder")
	folder.Name = "FloorSections"
	folder.Parent = parent
	for _, r in rects do
		local section = box(
			folder,
			"FloorSection",
			Vector3.new(r[1], 0, r[3]),
			Vector3.new(r[2], TILE_THICKNESS, r[4]),
			r[5] or FLOOR_SECTION,
			r[6] or Enum.Material.SmoothPlastic
		)
		section.CanCollide = false
		section.CanQuery = false
		section.CanTouch = false
		section.CastShadow = false
	end
end

-- Lockers lying on their backs (doors up), long axis along Z: two side by side and one askew on top.
-- 4 wide in X, like the old 4x4 pillar.
local function toppledLockers(parent: Instance, x: number, z: number)
	local pile = Instance.new("Model")
	pile.Name = "ToppledLockers"
	-- local up -> world +Z, local back (+Z) -> world -Y, so the door faces up and the locker is 2.2 tall
	local lying = CFrame.fromMatrix(Vector3.zero, Vector3.xAxis, Vector3.zAxis, -Vector3.yAxis)
	local centre = CFrame.new(x, 0, z)
	Props.locker(pile, centre * CFrame.new(-1, 1, -3.5) * lying)
	Props.locker(pile, centre * CFrame.new(1, 1, -3.5) * lying)
	Props.locker(pile, centre * CFrame.Angles(0, 0.15, 0) * CFrame.new(0, 3.22, -3.5) * lying)
	pile.Parent = parent
end

-- Two desks pushed together side by side (facing +X) with a third upside down on top. About 4 wide in X,
-- so never wider than the old 5- or 6-stud crate.
local function deskPile(parent: Instance, x: number, z: number)
	local pile = Instance.new("Model")
	pile.Name = "DeskPile"
	-- facing +X a desk spans x -2.9..1.1 around its origin; shift it so the pile is centred on x
	local base = CFrame.new(x + 0.9, 0, z) * CFrame.Angles(0, -math.pi / 2, 0)
	Props.desk(pile, base * CFrame.new(-1.75, 0, 0))
	Props.desk(pile, base * CFrame.new(1.75, 0, 0) * CFrame.Angles(0, 0.06, 0))
	Props.desk(pile, base * CFrame.new(-1.2, 5.4, -0.3) * CFrame.Angles(0, 0.2, math.pi))
	pile.Parent = parent
end

local function puddle(parent: Instance, center: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Puddle"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = PUDDLE_SIZE
	part.Position = Vector3.new(center.X, PUDDLE_SIZE.Y / 2, center.Z)
	part.Color = PUDDLE_COLOR
	part.Transparency = PUDDLE_TRANSPARENCY
	part.Material = Enum.Material.Glass
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	CollectionService:AddTag(part, "Puddle")
	return part
end

local function plank(parent: Instance, center: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Plank"
	part.Anchored = true
	part.Size = PLANK_SIZE
	part.Position = Vector3.new(center.X, PLANK_SIZE.Y / 2, center.Z)
	part.Color = PLANK_COLOR
	part.Material = Enum.Material.WoodPlanks
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	CollectionService:AddTag(part, "Plank")
	return part
end

local function replaceFolder(hall: Instance, name: string): Folder
	local existing = hall:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = hall
	return folder
end

-- Rebuilds Hall.Obstacles and Hall.Hazards for layout `index` (1..LAYOUT_COUNT) in the hall given, or
-- Workspace.Hall. Everything else in the hall is left alone. Errors if there is no hall or the index is bad.
function HallBuilder.buildLayout(index: number, target: Instance?): Instance
	local layout = LAYOUTS[index]
	if not layout then
		error(`HallBuilder.buildLayout: no layout {tostring(index)} (1..{#LAYOUTS})`, 2)
	end
	local hall = target or Workspace:FindFirstChild("Hall")
	if not hall then
		error("HallBuilder.buildLayout: there is no Workspace.Hall", 2)
	end

	local obstacles = replaceFolder(hall, "Obstacles")
	for _, obstacle in layout.obstacles do
		if obstacle.kind == "Pillar" then
			toppledLockers(obstacles, obstacle.x, obstacle.z)
		else
			deskPile(obstacles, obstacle.x, obstacle.z)
		end
	end

	local hazards = replaceFolder(hall, "Hazards")
	for _, center in layout.puddles do
		puddle(hazards, center)
	end
	for _, center in layout.planks do
		plank(hazards, center)
	end

	hall:SetAttribute("Layout", index)
	return hall
end

-- Wood jambs and a header round an opening `s0..s1` (distance along the face), `top` high.
local function doorFrame(parent: Instance, face: Face, s0: number, s1: number, top: number)
	for _, s in { s0 - 0.2, s1 + 0.2 } do
		trim(
			parent,
			"DoorJamb",
			Vector3.new(0.4, top, 0.3),
			faceFrame(face, s, top / 2, 0.15),
			WOOD_DARK,
			Enum.Material.Wood
		)
	end
	trim(
		parent,
		"DoorHeader",
		Vector3.new(s1 - s0 + 0.8, 0.4, 0.3),
		faceFrame(face, (s0 + s1) / 2, top + 0.2, 0.15),
		WOOD_DARK,
		Enum.Material.Wood
	)
end

-- A chalkboard with a wood frame on a face, centred `along` studs from face.a.
local function chalkboard(parent: Instance, face: Face, along: number)
	trim(
		parent,
		"BoardFrame",
		Vector3.new(8.6, 4.1, 0.1),
		faceFrame(face, along, 5.5, 0.05),
		WOOD_DARK,
		Enum.Material.Wood
	)
	trim(
		parent,
		"Chalkboard",
		Vector3.new(8, 3.5, 0.1),
		faceFrame(face, along, 5.5, 0.12),
		CHALK_GREEN,
		Enum.Material.Slate
	)
end

function HallBuilder.build(): Model
	local existing = Workspace:FindFirstChild("Hall")
	if existing then
		existing:Destroy()
	end

	local hall = Instance.new("Model")
	hall.Name = "Hall"

	local half = WIDTH / 2 -- 12
	local t = WALL_THICKNESS
	local backZ = -10 -- a little room behind the spawn
	local turn1 = LENGTH / 3 -- 100
	local turn2 = LENGTH * 2 / 3 -- 200
	local minX = GYM_X0 - t -- the gym is the west edge of the footprint

	-- Floor covers every segment, the back corridor, the link rooms and the gym; its top sits at Y=0.
	-- NoiseService sizes the water from this one part, so it must stay a single box over the whole footprint.
	local floor = box(
		hall,
		"Floor",
		Vector3.new(minX, -2, backZ - t),
		Vector3.new(half + STEP + t, 0, LENGTH + t),
		FLOOR_CREAM,
		Enum.Material.SmoothPlastic
	)
	hall.PrimaryPart = floor

	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = hall

	-- Classroom doorways (centre z) on the walls that have room behind them inside the Floor footprint.
	local doorsA = { 30, 70 } -- RightWallA, rooms x 12..24
	local doorsB = { 130, 170 } -- LeftWallB, rooms x -12..0
	local doorsC = { 230, 265 } -- RightWallC, rooms x 12..24

	-- Openings between the main hall's left wall and the back corridor: 2 cross halls and 2 link-room doors.
	local links: { Opening } = {}
	for _, c in CROSS_HALLS do
		table.insert(links, { c[1], c[2], CROSS_TOP })
	end
	for _, room in LINK_ROOMS do
		table.insert(links, { room.door - LINK_DOOR_HALF, room.door + LINK_DOOR_HALF, DOOR_TOP })
	end
	local function linksIn(z0: number, z1: number): { Opening }
		local list: { Opening } = {}
		for _, o in links do
			if o[1] >= z0 and o[2] <= z1 then
				table.insert(list, o)
			end
		end
		return list
	end

	-- Segment A: x -12..12, z backZ..100
	wall(walls, "BackWall", -half - t, half + t, backZ - t, backZ)
	wallZ(walls, "LeftWallA", -half - t, -half, backZ, turn1 + t, linksIn(backZ, turn1))
	wallWithDoors(walls, "RightWallA", half, half + t, backZ, turn1, doorsA)
	-- Turn 1: corridor steps +12 in X. The 12-stud overlap x 0..12 is the opening.
	wall(walls, "Turn1Right", half, half + STEP + t, turn1 - t, turn1)
	wall(walls, "Turn1Left", -half - t, -half + STEP, turn1, turn1 + t)
	-- Segment B: x 0..24, z 100..200
	wallWithDoors(walls, "LeftWallB", -half + STEP - t, -half + STEP, turn1, turn2, doorsB)
	wall(walls, "RightWallB", half + STEP, half + STEP + t, turn1 - t, turn2 + t)
	-- Turn 2: corridor steps back to x -12..12.
	wall(walls, "Turn2Left", -half - t, -half + STEP, turn2 - t, turn2)
	wall(walls, "Turn2Right", half, half + STEP + t, turn2, turn2 + t)
	-- Segment C: x -12..12, z 200..300
	wallZ(walls, "LeftWallC", -half - t, -half, turn2 - t, LENGTH, linksIn(turn2, LENGTH))
	wallWithDoors(walls, "RightWallC", half, half + t, turn2, LENGTH, doorsC)
	wall(walls, "EndWall", -half - t, half + t, LENGTH, LENGTH + t)

	-- Back corridor: x -40..-28, z 34..282, parallel to the main hall. Its east wall has the same 4 openings;
	-- its west wall opens into the gym.
	wallZ(walls, "BackHallEast", BACK_X1, LINK_X0, BACK_Z0 - t, BACK_Z1 + t, links)
	wallZ(
		walls,
		"BackHallWest",
		BACK_X0 - t,
		BACK_X0,
		BACK_Z0 - t,
		BACK_Z1 + t,
		{ { GYM_DOOR[1], GYM_DOOR[2], CROSS_TOP } }
	)
	wall(walls, "BackHallSouth", BACK_X0 - t, LINK_X0, BACK_Z0 - t, BACK_Z0)
	wall(walls, "BackHallNorth", BACK_X0 - t, LINK_X0, BACK_Z1, BACK_Z1 + t)

	-- Cross halls and link rooms between the two corridors (x -26..-14).
	for i, c in CROSS_HALLS do
		wall(walls, `CrossHall{i}South`, LINK_X0, LINK_X1, c[1] - t, c[1])
		wall(walls, `CrossHall{i}North`, LINK_X0, LINK_X1, c[2], c[2] + t)
	end
	for i, room in LINK_ROOMS do
		wall(walls, `LinkRoom{i}South`, LINK_X0, LINK_X1, room.z0 - t, room.z0)
		if room.window then
			-- the window wall: full-height pieces either side, a sill below and a header above the hole
			local z0, z1 = room.z1, room.z1 + t
			wall(walls, `LinkRoom{i}North`, LINK_X0, WINDOW_X0, z0, z1)
			wall(walls, `LinkRoom{i}North`, WINDOW_X1, LINK_X1, z0, z1)
			box(
				walls,
				`LinkRoom{i}Sill`,
				Vector3.new(WINDOW_X0, 0, z0),
				Vector3.new(WINDOW_X1, WINDOW_SILL, z1),
				PLASTER,
				Enum.Material.Plaster
			)
			box(
				walls,
				`LinkRoom{i}Header`,
				Vector3.new(WINDOW_X0, WINDOW_TOP, z0),
				Vector3.new(WINDOW_X1, WALL_HEIGHT, z1),
				PLASTER,
				Enum.Material.Plaster
			)
		else
			wall(walls, `LinkRoom{i}North`, LINK_X0, LINK_X1, room.z1, room.z1 + t)
		end
	end

	-- Gym: x -70..-42, z 216..262, west of the back corridor. Its east wall is BackHallWest.
	wall(walls, "GymSouth", GYM_X0 - t, GYM_X1, GYM_Z0 - t, GYM_Z0)
	wall(walls, "GymNorth", GYM_X0 - t, GYM_X1, GYM_Z1, GYM_Z1 + t)
	wall(walls, "GymWest", GYM_X0 - t, GYM_X0, GYM_Z0 - t, GYM_Z1 + t)

	-- The ceiling closes the whole footprint at WALL_HEIGHT.
	box(
		hall,
		"Ceiling",
		Vector3.new(minX, WALL_HEIGHT, backZ - t),
		Vector3.new(half + STEP + t, WALL_HEIGHT + 1, LENGTH + t),
		CEILING_COLOR,
		Enum.Material.Plaster
	)

	local dressing = Instance.new("Folder")
	dressing.Name = "Dressing"
	dressing.Parent = hall

	local sections: { FloorRect } = {
		{ -half, half, backZ, turn1 },
		{ -half + STEP, half + STEP, turn1, turn2 },
		{ -half, half, turn2, LENGTH },
		{ BACK_X0, BACK_X1, BACK_Z0, BACK_Z1 },
		{ GYM_X0, GYM_X1, GYM_Z0, GYM_Z1, FLOOR_GYM, Enum.Material.WoodPlanks },
	}
	for _, c in CROSS_HALLS do
		table.insert(sections, { LINK_X0, LINK_X1, c[1], c[2] })
	end
	for _, room in LINK_ROOMS do
		table.insert(sections, { LINK_X0, LINK_X1, room.z0, room.z1, FLOOR_ROOM, Enum.Material.Slate })
	end
	floorSections(dressing, sections)

	local function doorSkips(doors: { number }, z0: number, margin: number): { { number } }
		local spans = {}
		for _, z in doors do
			table.insert(spans, { z - z0 - DOOR_HALF - margin, z - z0 + DOOR_HALF + margin })
		end
		return spans
	end
	-- Openings as spans along a face that starts at z0.
	local function openingSkips(openings: { Opening }, z0: number, margin: number): { { number } }
		local spans = {}
		for _, o in openings do
			table.insert(spans, { o[1] - z0 - margin, o[2] - z0 + margin })
		end
		return spans
	end

	local px, nx, pz, nz = Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis
	local function v(x: number, z: number): Vector3
		return Vector3.new(x, 0, z)
	end
	local linksA, linksC = linksIn(backZ, turn1), linksIn(turn2, LENGTH)
	local gymOpening: { Opening } = { { GYM_DOOR[1], GYM_DOOR[2], CROSS_TOP } }
	-- Side walls (along Z): wainscot, then locker rows and notice boards between `from` and `to` (along the face).
	-- `openings` get wood frames and are kept clear of lockers.
	type Side = { face: Face, doors: { number }, openings: { Opening }?, from: number, to: number, sparse: boolean? }
	local sideFaces: { Side } = {
		{
			face = { a = v(-half, backZ), b = v(-half, turn1), normal = px, skip = openingSkips(linksA, backZ, 0) },
			doors = {},
			openings = linksA,
			from = 16,
			to = 100,
		},
		{
			face = { a = v(half, backZ), b = v(half, turn1), normal = nx, skip = doorSkips(doorsA, backZ, 0) },
			doors = doorsA,
			from = 16,
			to = 100,
		},
		{
			face = {
				a = v(-half + STEP, turn1),
				b = v(-half + STEP, turn2),
				normal = px,
				skip = doorSkips(doorsB, turn1, 0),
			},
			doors = doorsB,
			from = 10,
			to = 90,
		},
		{
			face = { a = v(half + STEP, turn1), b = v(half + STEP, turn2), normal = nx },
			doors = {},
			from = 10,
			to = 90,
		},
		{
			face = { a = v(-half, turn2), b = v(-half, LENGTH), normal = px, skip = openingSkips(linksC, turn2, 0) },
			doors = {},
			openings = linksC,
			from = 10,
			to = 88,
		},
		{
			face = { a = v(half, turn2), b = v(half, LENGTH), normal = nx, skip = doorSkips(doorsC, turn2, 0) },
			doors = doorsC,
			from = 10,
			to = 88,
		},
		-- back corridor: lockers down the west side, bare panelling on the east side between the openings
		{
			face = {
				a = v(BACK_X0, BACK_Z0),
				b = v(BACK_X0, BACK_Z1),
				normal = px,
				skip = openingSkips(gymOpening, BACK_Z0, 0),
			},
			doors = {},
			openings = gymOpening,
			from = 6,
			to = BACK_Z1 - BACK_Z0 - 6,
			sparse = true,
		},
		{
			face = {
				a = v(BACK_X1, BACK_Z0),
				b = v(BACK_X1, BACK_Z1),
				normal = nx,
				skip = openingSkips(links, BACK_Z0, 0),
			},
			doors = {},
			openings = links,
			from = 0,
			to = 0,
		},
	}
	for _, side in sideFaces do
		wainscot(dressing, side.face)
		local blocked = doorSkips(side.doors, side.face.a.Z, 1)
		for _, span in openingSkips(side.openings or {}, side.face.a.Z, 1) do
			table.insert(blocked, span)
		end
		dressFace(dressing, side.face, side.from, side.to, blocked, side.sparse)
		for _, z in side.doors do
			Props.classroomDoorway(dressing, faceFrame(side.face, z - side.face.a.Z, ROOM_LIFT, 0))
		end
		for _, o in side.openings or {} do
			doorFrame(dressing, side.face, o[1] - side.face.a.Z, o[2] - side.face.a.Z, o[3])
		end
	end

	-- Wainscot only: end walls, turn walls, the back corridor's ends, cross halls, link rooms and the gym.
	-- The end wall is left bare behind the exit door, and the gym's west wall behind the fire exit door.
	local backFace: Face = { a = v(-half, backZ), b = v(half, backZ), normal = pz }
	local crossFaces: { Face } = {
		backFace,
		{ a = v(-half, turn1), b = v(-half + STEP, turn1), normal = nz },
		{ a = v(half, turn1), b = v(half + STEP, turn1), normal = pz },
		{ a = v(-half, turn2), b = v(-half + STEP, turn2), normal = pz },
		{ a = v(half, turn2), b = v(half + STEP, turn2), normal = nz },
		{ a = v(-half, LENGTH), b = v(half, LENGTH), normal = nz, skip = { { half - 7, half + 7 } } },
		{ a = v(BACK_X0, BACK_Z0), b = v(BACK_X1, BACK_Z0), normal = pz },
		{ a = v(BACK_X0, BACK_Z1), b = v(BACK_X1, BACK_Z1), normal = nz },
		{ a = v(GYM_X0, GYM_Z0), b = v(GYM_X1, GYM_Z0), normal = pz },
		{ a = v(GYM_X0, GYM_Z1), b = v(GYM_X1, GYM_Z1), normal = nz },
		{
			a = v(GYM_X0, GYM_Z0),
			b = v(GYM_X0, GYM_Z1),
			normal = px,
			skip = { { FIRE_EXIT_Z - GYM_Z0 - 7, FIRE_EXIT_Z - GYM_Z0 + 7 } },
		},
		{
			a = v(GYM_X1, GYM_Z0),
			b = v(GYM_X1, GYM_Z1),
			normal = nx,
			skip = openingSkips(gymOpening, GYM_Z0, 0),
		},
	}
	for _, c in CROSS_HALLS do
		table.insert(crossFaces, { a = v(LINK_X0, c[1]), b = v(LINK_X1, c[1]), normal = pz })
		table.insert(crossFaces, { a = v(LINK_X0, c[2]), b = v(LINK_X1, c[2]), normal = nz })
	end
	local roomFaces: { [number]: { south: Face, north: Face } } = {}
	for i, room in LINK_ROOMS do
		local doorSpan = { { room.door - LINK_DOOR_HALF - room.z0, room.door + LINK_DOOR_HALF - room.z0 } }
		local south: Face = { a = v(LINK_X0, room.z0), b = v(LINK_X1, room.z0), normal = pz }
		local north: Face = {
			a = v(LINK_X0, room.z1),
			b = v(LINK_X1, room.z1),
			normal = nz,
			skip = if room.window then { { WINDOW_X0 - LINK_X0, WINDOW_X1 - LINK_X0 } } else nil,
		}
		roomFaces[i] = { south = south, north = north }
		table.insert(crossFaces, south)
		table.insert(crossFaces, north)
		table.insert(crossFaces, { a = v(LINK_X0, room.z0), b = v(LINK_X0, room.z1), normal = px, skip = doorSpan })
		table.insert(crossFaces, { a = v(LINK_X1, room.z0), b = v(LINK_X1, room.z1), normal = nx, skip = doorSpan })
	end
	for _, face in crossFaces do
		wainscot(dressing, face)
	end
	Props.noticeBoard(dressing, faceFrame(backFace, half, 4, 0))

	-- Link rooms: a chalkboard and two desks each. Room 1's desks face its north board, behind the door lane;
	-- room 2's face its south board, leaving a gap down the middle to the window.
	local midX = (LINK_X0 + LINK_X1) / 2
	local room1, room2 = LINK_ROOMS[1], LINK_ROOMS[2]
	chalkboard(dressing, roomFaces[1].north, midX - LINK_X0)
	for _, x in { -23, -17 } do
		Props.desk(dressing, CFrame.new(x, 0, room1.z1 - 4) * CFrame.Angles(0, math.pi, 0))
	end
	chalkboard(dressing, roomFaces[2].south, midX - LINK_X0)
	for _, x in { -24, -16 } do
		Props.desk(dressing, CFrame.new(x, 0, room2.z1 - 10))
	end

	-- The broken window: a dark night sky in the hole (solid, so nobody climbs out), a sill, glass shards
	-- and an EXIT sign above it.
	local windowZ = room2.z1
	local windowMid = (WINDOW_X0 + WINDOW_X1) / 2
	local sky = box(
		dressing,
		"NightSky",
		Vector3.new(WINDOW_X0, WINDOW_SILL, windowZ + t - 0.4),
		Vector3.new(WINDOW_X1, WINDOW_TOP, windowZ + t),
		NIGHT,
		Enum.Material.SmoothPlastic
	)
	sky.CastShadow = false
	local moon = Instance.new("PointLight")
	moon.Color = Color3.fromRGB(110, 140, 220)
	moon.Brightness = 0.6
	moon.Range = 12
	moon.Parent = sky
	trim(
		dressing,
		"WindowSill",
		Vector3.new(WINDOW_X1 - WINDOW_X0 + 0.6, 0.25, 0.7),
		CFrame.new(windowMid, WINDOW_SILL + 0.12, windowZ - 0.2),
		WOOD_DARK,
		Enum.Material.Wood
	)
	local shards = {
		{
			CFrame.new(WINDOW_X0 + 0.9, WINDOW_TOP - 1.2, windowZ + 1) * CFrame.Angles(0, 0, 0.5),
			Vector3.new(1.6, 2.4, 0.08),
		},
		{
			CFrame.new(WINDOW_X1 - 0.8, WINDOW_SILL + 1, windowZ + 1) * CFrame.Angles(0, 0, -0.4),
			Vector3.new(1.4, 1.9, 0.08),
		},
		{
			CFrame.new(windowMid + 1, WINDOW_TOP - 0.6, windowZ + 1) * CFrame.Angles(0, 0, 2.6),
			Vector3.new(1.1, 1.3, 0.08),
		},
	}
	for _, s in shards do
		local shard = trim(dressing, "GlassShard", s[2], s[1], Color3.fromRGB(170, 200, 210), Enum.Material.Glass)
		shard.Transparency = 0.45
	end
	exitSign(
		dressing,
		CFrame.lookAt(Vector3.new(windowMid, 10.5, windowZ - 0.3), Vector3.new(windowMid, 10.5, windowZ - 10))
	)

	-- Gym: low bleachers along the north wall and a hoop on the south wall.
	for step = 1, 3 do
		box(
			dressing,
			"Bleacher",
			Vector3.new(-60, 0, GYM_Z1 - 6 + (step - 1) * 2),
			Vector3.new(-44, step, GYM_Z1),
			WOOD_DARK,
			Enum.Material.WoodPlanks
		)
	end
	local hoopX = (GYM_X0 + GYM_X1) / 2
	trim(
		dressing,
		"Backboard",
		Vector3.new(6, 3.5, 0.2),
		CFrame.new(hoopX, 11.5, GYM_Z0 + 1.5),
		Color3.fromRGB(200, 200, 196),
		Enum.Material.SmoothPlastic
	)
	trim(
		dressing,
		"HoopArm",
		Vector3.new(0.3, 0.3, 1.4),
		CFrame.new(hoopX, 11.5, GYM_Z0 + 0.7),
		STEEL,
		Enum.Material.Metal
	)
	trim(
		dressing,
		"Rim",
		Vector3.new(1.8, 0.15, 1.8),
		CFrame.new(hoopX, 10, GYM_Z0 + 2.6),
		Color3.fromRGB(200, 80, 40),
		Enum.Material.Metal
	)

	-- Ceiling lamps down the middle of each segment, LAMP_SPACING apart, plus the back corridor, the cross halls,
	-- the link rooms and the gym; every 4th one (sorted by z) flickers.
	-- Props tags the lamp Model, but Atmosphere flickers tagged BaseParts, so the tubes are tagged as well.
	local lampSpots: { Vector3 } = {}
	for i = 0, 3 do
		table.insert(lampSpots, Vector3.new(0, WALL_HEIGHT, 8 + i * LAMP_SPACING))
		table.insert(lampSpots, Vector3.new(STEP, WALL_HEIGHT, turn1 + 8 + i * LAMP_SPACING))
		table.insert(lampSpots, Vector3.new(0, WALL_HEIGHT, turn2 + 8 + i * LAMP_SPACING))
	end
	local backMid = (BACK_X0 + BACK_X1) / 2
	for i = 0, 9 do
		table.insert(lampSpots, Vector3.new(backMid, WALL_HEIGHT, BACK_Z0 + 6 + i * LAMP_SPACING))
	end
	for _, c in CROSS_HALLS do
		table.insert(lampSpots, Vector3.new(midX, WALL_HEIGHT, (c[1] + c[2]) / 2))
	end
	for _, room in LINK_ROOMS do
		table.insert(lampSpots, Vector3.new(midX, WALL_HEIGHT, room.door + 4))
	end
	table.insert(lampSpots, Vector3.new(hoopX, WALL_HEIGHT, 228))
	table.insert(lampSpots, Vector3.new(hoopX, WALL_HEIGHT, 250))
	table.sort(lampSpots, function(p, q)
		return p.Z < q.Z
	end)
	for i, spot in lampSpots do
		local flicker = i % 4 == 3
		local lamp = Props.ceilingLamp(dressing, CFrame.new(spot), flicker)
		if flicker then
			for _, d in lamp:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Tube" then
					CollectionService:AddTag(d, FLICKER_TAG)
				end
			end
		end
	end

	-- The exit door stands against the end wall, inside the Exit trigger (z 296..300).
	Props.exitDoor(dressing, CFrame.lookAt(Vector3.new(0, 0, LENGTH - 0.6), Vector3.new(0, 0, 0)))
	-- The gym fire exit door stands against the gym's west wall, inside the FireExit trigger.
	Props.exitDoor(
		dressing,
		CFrame.lookAt(Vector3.new(GYM_X0 + 0.6, 0, FIRE_EXIT_Z), Vector3.new(GYM_X0 + 10, 0, FIRE_EXIT_Z))
	)

	-- Obstacles and hazards: layout 1 until RoundService picks one for a round.
	HallBuilder.buildLayout(1, hall)

	local start = Instance.new("SpawnLocation")
	start.Name = "Start"
	start.Anchored = true
	start.Neutral = true
	start.Duration = 0
	start.Size = Vector3.new(6, 1, 6)
	start.Position = Vector3.new(0, 0.5, 0)
	start.Color = Color3.fromRGB(90, 90, 96)
	start.Material = Enum.Material.Concrete
	start.TopSurface = Enum.SurfaceType.Smooth
	start.Parent = hall

	-- Exit is the main exit: a walk-through trigger spanning the full corridor width at the far end.
	-- Monster and the specs use it as the hall's far anchor.
	local exit = box(
		hall,
		"Exit",
		Vector3.new(-half, 0, LENGTH - 4),
		Vector3.new(half, WALL_HEIGHT, LENGTH),
		Color3.fromRGB(0, 255, 90),
		Enum.Material.Neon
	)
	exit.CanCollide = false
	exit.Transparency = 1 -- the exit door and its EXIT sign show where it is

	-- The extra exits. RoundService connects every BasePart in here to the same escape handler as Exit.
	local exits = Instance.new("Folder")
	exits.Name = "Exits"
	exits.Parent = hall
	exitTrigger(
		exits,
		"FireExit",
		Vector3.new(GYM_X0, 0, FIRE_EXIT_Z - 6),
		Vector3.new(GYM_X0 + 4, 12, FIRE_EXIT_Z + 6)
	)
	exitTrigger(exits, "BrokenWindow", Vector3.new(WINDOW_X0, 0, windowZ - 4), Vector3.new(WINDOW_X1, 10, windowZ))

	hall.Parent = Workspace
	return hall
end

return HallBuilder

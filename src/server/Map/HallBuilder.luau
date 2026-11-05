--!strict
-- Builds the greybox hall: a 24-stud-wide, 500-stud-long corridor running along +Z.
-- It has three straight segments joined by two side-step turns (the corridor jogs 12 studs
-- sideways at z=170 and back at z=340), plus pillar and crate obstacles.
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
-- Sprint 38 (spawn points): Hall.Starts holds 4 invisible, non-colliding 4x1x4 BaseParts: Start1 (on Hall.Start),
-- Start2 (south end of the back corridor), Start3 (the side classroom at z 30) and Start4 (cross hall 1). They are
-- outside Hall.Obstacles, so the same in every layout. Hall.Start is kept (the lobby platform and Monster use it).
-- Sprint 39 (bigger school): everything is ~1.7x longer. The main hall is 500 long (turns at z 170 and 340), the
-- back corridor runs z 0..490, and five cross halls (z 20, 110, 250, 372, 474; the z-250 one crosses from the
-- middle segment, through the classroom row) and four link classrooms join the two corridors. Three classrooms
-- per segment. The gym (z 390..466) and both extra exits moved north, so the shortest walk from every Hall.Starts
-- spawn to every exit is 420..520 studs, and every spawn is far from the monster's entry at the main Exit.
-- Sprint 41 (courtyard and second floor): the main hall's segment A and the back corridor both run 120 studs
-- further south (to z -130), and all four spawns moved to that south end, so the shortest walk from every spawn
-- to every exit is 550..700. West of the back corridor is an open-air courtyard (x -100..-42, z -130..170) with
-- grass, stone paths, a dead tree in a planter, benches and low walls, lit by a moonlight SurfaceLight. Three
-- 12x15 doorways in the back corridor's west wall join it to the halls. Above the back corridor is a dry second
-- floor (the ceiling slab, top at UPPER_Y) whose west side is a balcony with a broken railing over the courtyard,
-- so you can drop down. Two ramps (12 wide, 21 up over 60, about 19 degrees) climb from the courtyard to it.
-- Start4 is upstairs. The courtyard walls are 40 tall with an invisible cap on top, so nobody climbs out.
-- The ceiling is now two parts (school and gym) so the courtyard is open to the sky. Exits are unchanged.
-- The comments above give the Sprint 36 numbers; the constants below are the current ones.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Props = require(script.Parent.Props)

local HallBuilder = {}

local WIDTH = 24
local LENGTH = 500
local TURN1, TURN2 = 170, 340 -- where the corridor jogs +STEP and back
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
local LAMP_SPACING = 38 -- Sprint 39: was 25, widened for the part budget
local LOCKER_GAP = 20 -- studs between locker rows (was 7)
local SPARSE_LOCKER_GAP = 36 -- back corridor (was 12)
local BOARD_EVERY = 4 -- a notice board in every fourth gap (was every other)
local FLICKER_TAG = "FlickerLamp"
local PUDDLE_COLOR = Color3.fromRGB(45, 110, 190)
local PUDDLE_TRANSPARENCY = 0.35
local PUDDLE_SIZE = Vector3.new(6, 0.1, 5) -- flat, sitting on the floor; walk-through
local PLANK_COLOR = Color3.fromRGB(110, 74, 42)
local PLANK_SIZE = Vector3.new(3, 0.3, 8) -- slightly raised; low enough to step onto

-- Sprint 36 routes (see the header). Interiors are given; walls are WALL_THICKNESS outside them.
local BACK_X0, BACK_X1 = -40, -28 -- back corridor
local SOUTH_Z = -130 -- Sprint 41: south end of the main hall and the back corridor (was -10 and 0)
local BACK_Z0, BACK_Z1 = SOUTH_Z, 490
local LINK_X0, LINK_X1 = -26, -14 -- cross halls and link classrooms, between the two corridors
local GYM_X0, GYM_X1 = -70, -42
local GYM_Z0, GYM_Z1 = 390, 466
local GYM_DOOR = { 426, 438 } -- opening in the back corridor's west wall
local FIRE_EXIT_Z = 452 -- centre of the fire exit on the gym's west wall
local CROSS_TOP = 15 -- cross hall and gym openings are cut up to this height
local LINK_DOOR_HALF = 4 -- link classroom doorways are 8 wide, up to DOOR_TOP
-- { z0, z1, x1? }: x1 is the cross hall's east end (default LINK_X1, the main hall's left wall in segments A and C).
-- The z-250 one starts at the middle segment's left wall (x -2), so it runs past the classroom row.
local CROSS_HALLS: { { number } } = { { 20, 32 }, { 110, 122 }, { 250, 262, -2 }, { 372, 384 }, { 474, 486 } }
type LinkRoom = { z0: number, z1: number, door: number, window: boolean? }
local LINK_ROOMS: { LinkRoom } = {
	{ z0 = 62, z1 = 82, door = 70 },
	{ z0 = 140, z1 = 160, door = 148 },
	{ z0 = 400, z1 = 420, door = 408 },
	{ z0 = 440, z1 = 464, door = 446, window = true }, -- broken window in the north wall
}
local WINDOW_X0, WINDOW_X1 = -23, -17 -- broken window in the window room's north wall
local WINDOW_SILL, WINDOW_TOP = 3, 9

-- Sprint 41: courtyard and second floor (see the header). Interiors are given; walls are outside them.
local COURT_X0, COURT_X1 = -100, -42 -- the east side is BackHallWest (x -42..-40)
local COURT_Z0, COURT_Z1 = SOUTH_Z, 170
local COURT_WALL_HEIGHT = 40 -- the invisible SkyCap sits right on top, so nobody stands on a wall top
local COURT_DOORS = { -15, 30, 70 } -- doorway centres (z) in BackHallWest
local COURT_DOOR_HALF = 6 -- 12 wide, up to CROSS_TOP
local UPPER_Y = WALL_HEIGHT + 1 -- second-floor walking height: the top of the ceiling slab
local UPPER_TOP = COURT_WALL_HEIGHT -- the second floor's roof underside
local UPPER_X0, UPPER_X1 = -42, -28 -- second-floor corridor; open balcony edge at x0, wall at x1..x1 + 2
local UPPER_Z0, UPPER_Z1 = SOUTH_Z, COURT_Z1
local STAIR_X0, STAIR_X1 = -54, -42 -- ramps and landings run along the courtyard's east wall
-- Each staircase: a solid landing (top at UPPER_Y, touching the balcony) and a wedge ramp down to the courtyard.
type Stair = { landing0: number, landing1: number, ramp0: number, ramp1: number, highNorth: boolean }
local STAIRS: { Stair } = {
	{ landing0 = -104, landing1 = -90, ramp0 = -90, ramp1 = -30, highNorth = false },
	{ landing0 = 150, landing1 = 164, ramp0 = 90, ramp1 = 150, highNorth = true },
}
-- The railing gap at each landing also runs this far along the top of the ramp: a 14-wide gap alone was too
-- narrow for PathfindingService (agent radius 3) to join the landing to the balcony.
local LANDING_GAP_OVER_RAMP = 10
local RAIL_GAPS = { { -4, 8 }, { 40, 52 }, { 110, 118 } } -- broken railing spans (the landings are gaps too)
local GRASS = Color3.fromRGB(58, 66, 42)
local STONE = Color3.fromRGB(96, 96, 92)
local BRICK = Color3.fromRGB(92, 58, 48)
local BARK = Color3.fromRGB(52, 42, 36)
local MOON = Color3.fromRGB(150, 175, 230)

export type Obstacle = { kind: "Pillar" | "Crate", x: number, z: number, size: number? }
export type Layout = {
	obstacles: { Obstacle },
	puddles: { Vector3 }, -- centres on the floor (Y ignored)
	planks: { Vector3 },
}

-- Each layout keeps at least a 12-stud gap beside every obstacle, keeps clear of the turn openings
-- (x 0..12 at z=TURN1 and z=TURN2), Start (z=0) and Exit (z LENGTH-4..LENGTH), and has 4-6 puddles and 4-6 planks.
-- Hazards are walk-through, so they never block the route. Layout 1 is the original greybox placement.
-- Sprint 36: the main hall's left wall has openings (cross halls and link-room doors). Obstacles at x -6 are 2
-- wide either side, so a 4-stud gap stays along that wall, and none stands in front of an opening.
-- Sprint 39: the Sprint 36 placements stretched ~1.7x along the longer hall (nudged off the new openings),
-- plus one or two extra obstacles each.
local LAYOUTS: { Layout } = {
	{
		obstacles = {
			{ kind = "Pillar", x = -6, z = 51 },
			{ kind = "Crate", x = 6, z = 99, size = 6 },
			{ kind = "Crate", x = -5, z = 136, size = 5 },
			{ kind = "Pillar", x = 18, z = 221 },
			{ kind = "Crate", x = 6, z = 281, size = 6 },
			{ kind = "Crate", x = 18, z = 318, size = 5 },
			{ kind = "Pillar", x = -6, z = 396 },
			{ kind = "Crate", x = 6, z = 436, size = 5 },
			{ kind = "Pillar", x = 6, z = 470 },
		},
		puddles = {
			Vector3.new(6, 0, 51),
			Vector3.new(-6, 0, 105),
			Vector3.new(8, 0, 246),
			Vector3.new(16, 0, 306),
			Vector3.new(5, 0, 412),
		},
		planks = {
			Vector3.new(-6, 0, 90),
			Vector3.new(6, 0, 156),
			Vector3.new(12, 0, 196),
			Vector3.new(-5, 0, 364),
			Vector3.new(-4, 0, 462),
		},
	},
	{
		obstacles = {
			{ kind = "Pillar", x = 6, z = 68 },
			{ kind = "Crate", x = -6, z = 98, size = 6 },
			{ kind = "Crate", x = 6, z = 118, size = 5 },
			{ kind = "Pillar", x = 6, z = 238 },
			{ kind = "Crate", x = 18, z = 298, size = 6 },
			{ kind = "Pillar", x = 6, z = 390 },
			{ kind = "Crate", x = -6, z = 428, size = 6 },
			{ kind = "Pillar", x = 6, z = 468 },
		},
		puddles = {
			Vector3.new(-6, 0, 51),
			Vector3.new(6, 0, 99),
			Vector3.new(16, 0, 212),
			Vector3.new(6, 0, 315),
			Vector3.new(-6, 0, 408),
			Vector3.new(4, 0, 449),
		},
		planks = {
			Vector3.new(6, 0, 40),
			Vector3.new(-6, 0, 132),
			Vector3.new(20, 0, 255),
			Vector3.new(-6, 0, 356),
			Vector3.new(6, 0, 420),
		},
	},
	{
		obstacles = {
			{ kind = "Crate", x = -6, z = 43, size = 6 },
			{ kind = "Pillar", x = 6, z = 85 },
			{ kind = "Pillar", x = -6, z = 132 },
			{ kind = "Crate", x = 18, z = 204, size = 6 },
			{ kind = "Pillar", x = 6, z = 275 },
			{ kind = "Crate", x = 18, z = 315, size = 5 },
			{ kind = "Pillar", x = 6, z = 404 },
			{ kind = "Crate", x = -6, z = 462, size = 5 },
		},
		puddles = {
			Vector3.new(6, 0, 43),
			Vector3.new(-6, 0, 90),
			Vector3.new(6, 0, 128),
			Vector3.new(6, 0, 230),
			Vector3.new(-6, 0, 392),
			Vector3.new(0, 0, 478),
		},
		planks = {
			Vector3.new(-6, 0, 58),
			Vector3.new(16, 0, 186),
			Vector3.new(8, 0, 323),
			Vector3.new(-6, 0, 425),
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
-- face.a), keeping out of `blocked` spans. Rows are 5 lockers (10 studs) with LOCKER_GAP gaps and a notice board
-- in every BOARD_EVERY-th gap. `sparse` (the back corridor) uses SPARSE_LOCKER_GAP and no notice boards.
-- Sprint 39: the gaps widened so the ~1.7x longer school stays inside the 2,500-part budget.
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

	local gaps = 0
	for _, interval in free do
		local a, b = interval[1], interval[2]
		while true do
			local count = math.min(5, math.floor((b - a) / 2))
			if count < 2 then
				break
			end
			lockerBank(parent, faceFrame(face, a + count, 0, LOCKER_REACH), count)
			a += count * 2
			local gap = if sparse then SPARSE_LOCKER_GAP else LOCKER_GAP
			if a + gap > b then
				break
			end
			gaps += 1
			if gaps % BOARD_EVERY == 1 and not sparse then
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
	local backZ = SOUTH_Z -- Sprint 41: segment A runs 120 studs further south, past the spawns
	local turn1 = TURN1
	local turn2 = TURN2
	local minX = COURT_X0 - t -- the courtyard is the west edge of the footprint

	-- Floor covers every segment, the back corridor, the link rooms, the gym and the courtyard; its top sits at Y=0.
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
	local doorsA = { 30, 80, 130 } -- RightWallA, rooms x 12..24
	local doorsB = { 200, 228, 305 } -- LeftWallB, rooms x -12..0 (the z-250 cross hall runs between them)
	local doorsC = { 370, 420, 465 } -- RightWallC, rooms x 12..24

	-- Openings between the main hall's left wall and the back corridor: the cross halls and link-room doors.
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
	local linksB = linksIn(turn1, turn2)
	local openingsB: { Opening } = table.clone(linksB)
	for _, door in doorsB do
		table.insert(openingsB, { door - DOOR_HALF, door + DOOR_HALF, DOOR_TOP })
	end

	-- Segment A: x -12..12, z backZ..TURN1
	wall(walls, "BackWall", -half - t, half + t, backZ - t, backZ)
	wallZ(walls, "LeftWallA", -half - t, -half, backZ, turn1 + t, linksIn(backZ, turn1))
	wallWithDoors(walls, "RightWallA", half, half + t, backZ, turn1, doorsA)
	-- Turn 1: corridor steps +12 in X. The 12-stud overlap x 0..12 is the opening.
	wall(walls, "Turn1Right", half, half + STEP + t, turn1 - t, turn1)
	wall(walls, "Turn1Left", -half - t, -half + STEP, turn1, turn1 + t)
	-- Segment B: x 0..24, z TURN1..TURN2. Its left wall has the classroom doors and the middle cross hall.
	wallZ(walls, "LeftWallB", -half + STEP - t, -half + STEP, turn1, turn2, openingsB)
	wall(walls, "RightWallB", half + STEP, half + STEP + t, turn1 - t, turn2 + t)
	-- Turn 2: corridor steps back to x -12..12.
	wall(walls, "Turn2Left", -half - t, -half + STEP, turn2 - t, turn2)
	wall(walls, "Turn2Right", half, half + STEP + t, turn2, turn2 + t)
	-- Segment C: x -12..12, z TURN2..LENGTH
	wallZ(walls, "LeftWallC", -half - t, -half, turn2 - t, LENGTH, linksIn(turn2, LENGTH))
	wallWithDoors(walls, "RightWallC", half, half + t, turn2, LENGTH, doorsC)
	wall(walls, "EndWall", -half - t, half + t, LENGTH, LENGTH + t)

	-- Back corridor: x -40..-28, z BACK_Z0..BACK_Z1, parallel to the main hall. Its east wall has the same openings;
	-- its west wall opens into the gym.
	wallZ(walls, "BackHallEast", BACK_X1, LINK_X0, BACK_Z0 - t, BACK_Z1 + t, links)
	wallZ(
		walls,
		"BackHallWest",
		BACK_X0 - t,
		BACK_X0,
		BACK_Z0 - t,
		BACK_Z1 + t,
		(function()
			local openings: { Opening } = { { GYM_DOOR[1], GYM_DOOR[2], CROSS_TOP } }
			for _, z in COURT_DOORS do
				table.insert(openings, { z - COURT_DOOR_HALF, z + COURT_DOOR_HALF, CROSS_TOP })
			end
			return openings
		end)()
	)
	wall(walls, "BackHallSouth", BACK_X0 - t, LINK_X0, BACK_Z0 - t, BACK_Z0)
	wall(walls, "BackHallNorth", BACK_X0 - t, LINK_X0, BACK_Z1, BACK_Z1 + t)

	-- Cross halls and link rooms between the two corridors (x -26..-14; the middle cross hall to x -2).
	local function crossEnd(c: { number }): number
		return c[3] or LINK_X1
	end
	for i, c in CROSS_HALLS do
		wall(walls, `CrossHall{i}South`, LINK_X0, crossEnd(c), c[1] - t, c[1])
		wall(walls, `CrossHall{i}North`, LINK_X0, crossEnd(c), c[2], c[2] + t)
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

	-- Gym: x -70..-42, z GYM_Z0..GYM_Z1, west of the back corridor. Its east wall is BackHallWest.
	wall(walls, "GymSouth", GYM_X0 - t, GYM_X1, GYM_Z0 - t, GYM_Z0)
	wall(walls, "GymNorth", GYM_X0 - t, GYM_X1, GYM_Z1, GYM_Z1 + t)
	wall(walls, "GymWest", GYM_X0 - t, GYM_X0, GYM_Z0 - t, GYM_Z1 + t)

	-- The ceiling closes the school at WALL_HEIGHT (its top is the second floor's floor over the back corridor);
	-- the gym has its own slab, and the courtyard is open to the sky.
	box(
		hall,
		"Ceiling",
		Vector3.new(BACK_X0 - t, WALL_HEIGHT, backZ - t),
		Vector3.new(half + STEP + t, UPPER_Y, LENGTH + t),
		CEILING_COLOR,
		Enum.Material.Plaster
	)
	box(
		hall,
		"GymCeiling",
		Vector3.new(GYM_X0 - t, WALL_HEIGHT, GYM_Z0 - t),
		Vector3.new(BACK_X0 - t, UPPER_Y, GYM_Z1 + t),
		CEILING_COLOR,
		Enum.Material.Plaster
	)

	-- Sprint 41: the courtyard's outer walls (tall, so wall jumps can't reach the top) and an invisible cap.
	local function tallBox(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number)
		return box(walls, name, Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1), BRICK, Enum.Material.Brick)
	end
	tallBox("CourtWest", COURT_X0 - t, COURT_X0, 0, COURT_WALL_HEIGHT, COURT_Z0 - t, COURT_Z1 + t)
	tallBox("CourtSouth", COURT_X0 - t, BACK_X0 - t, 0, COURT_WALL_HEIGHT, COURT_Z0 - t, COURT_Z0)
	tallBox("CourtNorth", COURT_X0 - t, BACK_X0 - t, 0, COURT_WALL_HEIGHT, COURT_Z1, COURT_Z1 + t)
	local skyCap = box(
		walls,
		"SkyCap",
		Vector3.new(COURT_X0 - t, COURT_WALL_HEIGHT, COURT_Z0 - t),
		Vector3.new(UPPER_X0, COURT_WALL_HEIGHT + 1, COURT_Z1 + t),
		CEILING_COLOR,
		Enum.Material.SmoothPlastic
	)
	skyCap.Transparency = 1
	skyCap.CastShadow = false
	box(
		hall,
		"UpperCeiling",
		Vector3.new(UPPER_X0, UPPER_TOP, UPPER_Z0 - t),
		Vector3.new(UPPER_X1 + t, UPPER_TOP + 1, UPPER_Z1 + t),
		CEILING_COLOR,
		Enum.Material.Plaster
	)

	-- The second floor over the back corridor (x -42..-28, z UPPER_Z0..UPPER_Z1, floor at UPPER_Y). Its east and
	-- end walls stand on the ceiling; the west side is the open balcony over the courtyard. The SkyCap is its roof.
	tallBox("UpperEast", UPPER_X1, UPPER_X1 + t, UPPER_Y, UPPER_TOP, UPPER_Z0 - t, UPPER_Z1 + t)
	tallBox("UpperSouth", UPPER_X0, UPPER_X1, UPPER_Y, UPPER_TOP, UPPER_Z0 - t, UPPER_Z0)
	tallBox("UpperNorth", UPPER_X0, UPPER_X1, UPPER_Y, UPPER_TOP, UPPER_Z1, UPPER_Z1 + t)

	-- Two staircases: a solid landing level with the balcony and a 12-wide wedge ramp (about 19 degrees) down.
	for i, s in STAIRS do
		box(
			walls,
			`StairLanding{i}`,
			Vector3.new(STAIR_X0, 0, s.landing0),
			Vector3.new(STAIR_X1, UPPER_Y, s.landing1),
			STONE,
			Enum.Material.Concrete
		)
		local ramp = Instance.new("WedgePart")
		ramp.Name = `StairRamp{i}`
		ramp.Anchored = true
		ramp.Size = Vector3.new(STAIR_X1 - STAIR_X0, UPPER_Y, s.ramp1 - s.ramp0)
		-- a WedgePart is tallest at its local +Z (back) end
		local centre = Vector3.new((STAIR_X0 + STAIR_X1) / 2, UPPER_Y / 2, (s.ramp0 + s.ramp1) / 2)
		ramp.CFrame = CFrame.new(centre) * (if s.highNorth then CFrame.identity else CFrame.Angles(0, math.pi, 0))
		ramp.Color = STONE
		ramp.Material = Enum.Material.Concrete
		ramp.TopSurface = Enum.SurfaceType.Smooth
		ramp.BottomSurface = Enum.SurfaceType.Smooth
		ramp.Parent = walls
	end

	-- The broken balcony railing along x UPPER_X0: posts and rail runs with gaps where it has fallen away and at
	-- both landings, so a player can drop (or be chased) down into the courtyard.
	local railGaps: { { number } } = table.clone(RAIL_GAPS)
	for _, s in STAIRS do
		if s.highNorth then
			table.insert(railGaps, { s.landing0 - LANDING_GAP_OVER_RAMP, s.landing1 })
		else
			table.insert(railGaps, { s.landing0, s.landing1 + LANDING_GAP_OVER_RAMP })
		end
	end
	table.sort(railGaps, function(p, q)
		return p[1] < q[1]
	end)
	local railZ = UPPER_Z0
	local function railRun(z0: number, z1: number)
		if z1 - z0 < 1 then
			return
		end
		box(
			walls,
			"BalconyRail",
			Vector3.new(UPPER_X0, UPPER_Y, z0),
			Vector3.new(UPPER_X0 + 0.5, UPPER_Y + 3.5, z1),
			WOOD_DARK,
			Enum.Material.Wood
		)
	end
	for _, g in railGaps do
		railRun(railZ, g[1])
		railZ = math.max(railZ, g[2])
	end
	railRun(railZ, UPPER_Z1)

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
		table.insert(sections, { LINK_X0, crossEnd(c), c[1], c[2] })
	end
	for _, room in LINK_ROOMS do
		table.insert(sections, { LINK_X0, LINK_X1, room.z0, room.z1, FLOOR_ROOM, Enum.Material.Slate })
	end
	table.insert(sections, { COURT_X0, COURT_X1, COURT_Z0, COURT_Z1, GRASS, Enum.Material.Grass })
	floorSections(dressing, sections)

	-- Sprint 41: the courtyard. Stone paths, a dead tree in a brick planter, benches, low walls and moonlight.
	local court = Instance.new("Folder")
	court.Name = "Courtyard"
	court.Parent = dressing
	local function overlay(
		name: string,
		x0: number,
		x1: number,
		z0: number,
		z1: number,
		color: Color3,
		m: Enum.Material
	)
		local p = trim(
			court,
			name,
			Vector3.new(x1 - x0, TILE_THICKNESS * 2, z1 - z0),
			CFrame.new((x0 + x1) / 2, TILE_THICKNESS, (z0 + z1) / 2),
			color,
			m
		)
		p.CastShadow = false
	end
	-- a long path down the middle and one cross path to each doorway
	overlay("Path", -72, -64, COURT_Z0, COURT_Z1, STONE, Enum.Material.Cobblestone)
	for _, z in COURT_DOORS do
		overlay("Path", -64, COURT_X1, z - 4, z + 4, STONE, Enum.Material.Cobblestone)
	end
	local treeX, treeZ = -88, 20
	-- the planter's low brick walls (solid, 2.5 tall: you can hop them) around dead earth
	local function lowWall(name: string, x0: number, x1: number, z0: number, z1: number, h: number)
		box(court, name, Vector3.new(x0, 0, z0), Vector3.new(x1, h, z1), BRICK, Enum.Material.Brick)
	end
	lowWall("Planter", treeX - 6, treeX + 6, treeZ - 6, treeZ - 5, 2.5)
	lowWall("Planter", treeX - 6, treeX + 6, treeZ + 5, treeZ + 6, 2.5)
	lowWall("Planter", treeX - 6, treeX - 5, treeZ - 5, treeZ + 5, 2.5)
	lowWall("Planter", treeX + 5, treeX + 6, treeZ - 5, treeZ + 5, 2.5)
	overlay("Earth", treeX - 5, treeX + 5, treeZ - 5, treeZ + 5, BARK, Enum.Material.Ground)
	-- the dead tree: a solid trunk and bare, crooked branches
	box(
		court,
		"TreeTrunk",
		Vector3.new(treeX - 1, 0, treeZ - 1),
		Vector3.new(treeX + 1, 16, treeZ + 1),
		BARK,
		Enum.Material.Wood
	)
	local branches = {
		{ Vector3.new(0.8, 9, 0.8), CFrame.new(treeX + 2.5, 18, treeZ) * CFrame.Angles(0, 0, -0.6) },
		{ Vector3.new(0.7, 8, 0.7), CFrame.new(treeX - 2.5, 17, treeZ + 1) * CFrame.Angles(0.2, 0, 0.7) },
		{ Vector3.new(0.6, 7, 0.6), CFrame.new(treeX, 19, treeZ - 2.5) * CFrame.Angles(-0.6, 0, 0.1) },
		{ Vector3.new(0.5, 6, 0.5), CFrame.new(treeX + 0.5, 21, treeZ + 2.5) * CFrame.Angles(0.5, 0, -0.2) },
		{ Vector3.new(0.4, 5, 0.4), CFrame.new(treeX + 5, 22, treeZ) * CFrame.Angles(0, 0, -1.1) },
	}
	for _, b in branches do
		trim(court, "TreeBranch", b[1], b[2], BARK, Enum.Material.Wood)
	end
	-- low walls breaking up the west half (hop-over cover from the balcony's view)
	lowWall("LowWall", COURT_X0, -80, -60, -58.5, 3)
	lowWall("LowWall", COURT_X0, -80, 100, 101.5, 3)
	lowWall("LowWall", -86, -84.5, -110, -80, 3)
	-- benches along the west wall, facing east: a solid seat and back on two legs
	for _, z in { -100, -30, 60, 140 } do
		box(court, "BenchSeat", Vector3.new(-97, 1.6, z - 3), Vector3.new(-95, 2, z + 3), WOOD_DARK, Enum.Material.Wood)
		box(court, "BenchBack", Vector3.new(-97.6, 2, z - 3), Vector3.new(-97, 4, z + 3), WOOD_DARK, Enum.Material.Wood)
		trim(court, "BenchLegs", Vector3.new(1.6, 1.6, 5), CFrame.new(-96, 0.8, z), STEEL, Enum.Material.Metal)
	end
	-- moonlight: wide, cold SurfaceLights shining down from just under the cap
	for _, z in { -80, 20, 120 } do
		local moonPart = trim(
			court,
			"Moonlight",
			Vector3.new(2, 0.2, 2),
			CFrame.new((COURT_X0 + COURT_X1) / 2, COURT_WALL_HEIGHT - 1, z),
			MOON,
			Enum.Material.SmoothPlastic
		)
		moonPart.Transparency = 1
		moonPart.CastShadow = false
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Color = MOON
		light.Brightness = 2.5
		light.Range = 60
		light.Angle = 150
		light.Shadows = true
		light.Parent = moonPart
	end
	-- the second floor's wooden floor overlay on the ceiling slab
	local upperFloor = trim(
		dressing,
		"UpperFloor",
		Vector3.new(UPPER_X1 - UPPER_X0, TILE_THICKNESS * 2, UPPER_Z1 - UPPER_Z0),
		CFrame.new((UPPER_X0 + UPPER_X1) / 2, UPPER_Y + TILE_THICKNESS, (UPPER_Z0 + UPPER_Z1) / 2),
		FLOOR_GYM,
		Enum.Material.WoodPlanks
	)
	upperFloor.CastShadow = false
	-- upstairs lockers on the east wall, facing the balcony
	for z = UPPER_Z0 + 20, UPPER_Z1 - 20, 40 do
		lockerBank(
			dressing,
			CFrame.lookAt(Vector3.new(UPPER_X1 - 1, UPPER_Y, z), Vector3.new(UPPER_X1 - 10, UPPER_Y, z)),
			4
		)
	end

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
	-- Lockers stop 10 short of each turn (and 12 short of the end wall); segment A's start 16 in, clear of Start.
	local lenA, lenB, lenC = turn1 - backZ, turn2 - turn1, LENGTH - turn2
	local skipsB = doorSkips(doorsB, turn1, 0)
	for _, span in openingSkips(linksB, turn1, 0) do
		table.insert(skipsB, span)
	end
	local sideFaces: { Side } = {
		{
			face = { a = v(-half, backZ), b = v(-half, turn1), normal = px, skip = openingSkips(linksA, backZ, 0) },
			doors = {},
			openings = linksA,
			from = 16,
			to = lenA - 10,
		},
		{
			face = { a = v(half, backZ), b = v(half, turn1), normal = nx, skip = doorSkips(doorsA, backZ, 0) },
			doors = doorsA,
			from = 16,
			to = lenA - 10,
		},
		{
			face = {
				a = v(-half + STEP, turn1),
				b = v(-half + STEP, turn2),
				normal = px,
				skip = skipsB,
			},
			doors = doorsB,
			openings = linksB,
			from = 10,
			to = lenB - 10,
		},
		{
			face = { a = v(half + STEP, turn1), b = v(half + STEP, turn2), normal = nx },
			doors = {},
			from = 10,
			to = lenB - 10,
		},
		{
			face = { a = v(-half, turn2), b = v(-half, LENGTH), normal = px, skip = openingSkips(linksC, turn2, 0) },
			doors = {},
			openings = linksC,
			from = 10,
			to = lenC - 12,
		},
		{
			face = { a = v(half, turn2), b = v(half, LENGTH), normal = nx, skip = doorSkips(doorsC, turn2, 0) },
			doors = doorsC,
			from = 10,
			to = lenC - 12,
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
		table.insert(crossFaces, { a = v(LINK_X0, c[1]), b = v(crossEnd(c), c[1]), normal = pz })
		table.insert(crossFaces, { a = v(LINK_X0, c[2]), b = v(crossEnd(c), c[2]), normal = nz })
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

	-- Link rooms: a chalkboard and two desks each. A plain room's desks face its north board, behind the door lane;
	-- the window room's face its south board, leaving a gap down the middle to the window.
	local midX = (LINK_X0 + LINK_X1) / 2
	local windowZ = 0
	for i, room in LINK_ROOMS do
		if room.window then
			windowZ = room.z1
			chalkboard(dressing, roomFaces[i].south, midX - LINK_X0)
			for _, x in { -24, -16 } do
				Props.desk(dressing, CFrame.new(x, 0, room.z1 - 10))
			end
		else
			chalkboard(dressing, roomFaces[i].north, midX - LINK_X0)
			for _, x in { -23, -17 } do
				Props.desk(dressing, CFrame.new(x, 0, room.z1 - 4) * CFrame.Angles(0, math.pi, 0))
			end
		end
	end

	-- The broken window: a dark night sky in the hole (solid, so nobody climbs out), a sill, glass shards
	-- and an EXIT sign above it.
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
	-- one row of lamps from z0 + 8 up to (not past) z1 - 4
	local function lampRow(x: number, z0: number, z1: number, spacing: number)
		local z = z0 + 8
		while z <= z1 - 4 do
			table.insert(lampSpots, Vector3.new(x, WALL_HEIGHT, z))
			z += spacing
		end
	end
	lampRow(0, backZ, turn1, LAMP_SPACING)
	lampRow(STEP, turn1, turn2, LAMP_SPACING)
	lampRow(0, turn2, LENGTH, LAMP_SPACING)
	local backMid = (BACK_X0 + BACK_X1) / 2
	lampRow(backMid, BACK_Z0 - 2, BACK_Z1, LAMP_SPACING)
	for _, c in CROSS_HALLS do
		table.insert(lampSpots, Vector3.new((LINK_X0 + crossEnd(c)) / 2, WALL_HEIGHT, (c[1] + c[2]) / 2))
	end
	for _, room in LINK_ROOMS do
		table.insert(lampSpots, Vector3.new(midX, WALL_HEIGHT, room.door + 4))
	end
	lampRow(hoopX, GYM_Z0 + 4, GYM_Z1, 26)
	-- the second floor: one row under its own ceiling, set a little in from the balcony edge
	local upperLampZ = UPPER_Z0 + 8
	while upperLampZ <= UPPER_Z1 - 4 do
		table.insert(lampSpots, Vector3.new(-33, UPPER_TOP, upperLampZ))
		upperLampZ += LAMP_SPACING * 1.5
	end
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

	-- The exit door stands against the end wall, inside the Exit trigger (z LENGTH-4..LENGTH).
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

	-- Sprint 38: the round spawn points. RoundService puts each player on one of these (spread out before any
	-- is reused), falling back to Hall.Start. All sit on open floor, clear of lockers, desks and obstacles, and far
	-- from the monster's entry by the main Exit. Sprint 41: all at the far south end, 550..700 studs' walk from
	-- every exit; Start4 is upstairs (its base at UPPER_Y).
	local starts = Instance.new("Folder")
	starts.Name = "Starts"
	starts.Parent = hall
	local startSpots: { { any } } = {
		{ "Start1", Vector3.new(0, 0, backZ + 8) }, -- the south end of the main hall
		{ "Start2", Vector3.new(backMid, 0, BACK_Z0 + 5) }, -- the south end of the back corridor
		{ "Start3", Vector3.new(-71, 0, COURT_Z0 + 10) }, -- the south end of the courtyard
		{ "Start4", Vector3.new(-35, UPPER_Y, UPPER_Z0 + 8) }, -- the south end of the second floor
	}
	for _, spot in startSpots do
		local point = box(
			starts,
			spot[1],
			spot[2] - Vector3.new(2, 0, 2),
			spot[2] + Vector3.new(2, 1, 2),
			Color3.fromRGB(90, 90, 96),
			Enum.Material.Concrete
		)
		point.CanCollide = false
		point.CanQuery = false
		point.CanTouch = false
		point.CastShadow = false
		point.Transparency = 1
	end

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

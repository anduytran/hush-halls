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
local TILE = 4 -- checker tile size
local TILE_THICKNESS = 0.02 -- the grey tiles are thin, non-colliding overlays on the cream Floor
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

export type Obstacle = { kind: "Pillar" | "Crate", x: number, z: number, size: number? }
export type Layout = {
	obstacles: { Obstacle },
	puddles: { Vector3 }, -- centres on the floor (Y ignored)
	planks: { Vector3 },
}

-- Each layout keeps at least a 12-stud gap beside every obstacle, keeps clear of the turn openings
-- (x 0..12 at z=100 and z=200), Start (z=0) and Exit (z 296..300), and has 4-6 puddles and 4-6 planks.
-- Hazards are walk-through, so they never block the route. Layout 1 is the original greybox placement.
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
	box(parent, name, Vector3.new(x0, 0, z0), Vector3.new(x1, WALL_HEIGHT, z1), PLASTER, Enum.Material.Plaster)
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
	local z = z0
	for _, door in doors do
		wall(parent, name, x0, x1, z, door - DOOR_HALF)
		box(
			parent,
			name .. "Lintel",
			Vector3.new(x0, DOOR_TOP, door - DOOR_HALF),
			Vector3.new(x1, WALL_HEIGHT, door + DOOR_HALF),
			PLASTER,
			Enum.Material.Plaster
		)
		z = door + DOOR_HALF
	end
	wall(parent, name, x0, x1, z, z1)
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
-- face.a), keeping out of `blocked` spans. Rows are 5 lockers (10 studs) with 7-stud gaps.
local function dressFace(parent: Instance, face: Face, from: number, to: number, blocked: { { number } })
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
			Props.lockerRow(parent, faceFrame(face, a + count, 0, LOCKER_REACH), count)
			a += count * 2
			local gap = 7
			if a + gap > b then
				break
			end
			board = not board
			if board then
				Props.noticeBoard(parent, faceFrame(face, a + gap / 2, 4, 0))
			end
			a += gap
		end
	end
end

-- Grey checker tiles over the cream Floor, inside the corridor rectangles { xMin, xMax, zMin, zMax }.
local function floorTiles(parent: Instance, rects: { { number } })
	local tiles = Instance.new("Folder")
	tiles.Name = "FloorTiles"
	tiles.Parent = parent
	for x = -WIDTH / 2, WIDTH / 2 + STEP - TILE, TILE do
		for z = -12, LENGTH - TILE, TILE do
			local cx, cz = x + TILE / 2, z + TILE / 2
			local inside = false
			for _, r in rects do
				if cx > r[1] and cx < r[2] and cz > r[3] and cz < r[4] then
					inside = true
					break
				end
			end
			if inside and (x // TILE + z // TILE) % 2 == 0 then
				local tile = box(
					tiles,
					"Tile",
					Vector3.new(x, 0, z),
					Vector3.new(x + TILE, TILE_THICKNESS, z + TILE),
					FLOOR_GREY,
					Enum.Material.SmoothPlastic
				)
				tile.CanCollide = false
				tile.CanQuery = false
				tile.CanTouch = false
				tile.CastShadow = false
			end
		end
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

	-- Floor covers every segment; its top sits at Y=0.
	local floor = box(
		hall,
		"Floor",
		Vector3.new(-half - t, -2, backZ - t),
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

	-- Segment A: x -12..12, z backZ..100
	wall(walls, "BackWall", -half - t, half + t, backZ - t, backZ)
	wall(walls, "LeftWallA", -half - t, -half, backZ, turn1 + t)
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
	wall(walls, "LeftWallC", -half - t, -half, turn2 - t, LENGTH)
	wallWithDoors(walls, "RightWallC", half, half + t, turn2, LENGTH, doorsC)
	wall(walls, "EndWall", -half - t, half + t, LENGTH, LENGTH + t)

	-- The ceiling closes the whole footprint at WALL_HEIGHT.
	box(
		hall,
		"Ceiling",
		Vector3.new(-half - t, WALL_HEIGHT, backZ - t),
		Vector3.new(half + STEP + t, WALL_HEIGHT + 1, LENGTH + t),
		CEILING_COLOR,
		Enum.Material.Plaster
	)

	local dressing = Instance.new("Folder")
	dressing.Name = "Dressing"
	dressing.Parent = hall

	floorTiles(dressing, {
		{ -half, half, backZ, turn1 },
		{ -half + STEP, half + STEP, turn1, turn2 },
		{ -half, half, turn2, LENGTH },
	})

	local function doorSkips(doors: { number }, z0: number, margin: number): { { number } }
		local spans = {}
		for _, z in doors do
			table.insert(spans, { z - z0 - DOOR_HALF - margin, z - z0 + DOOR_HALF + margin })
		end
		return spans
	end

	local px, nx, pz, nz = Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis
	local function v(x: number, z: number): Vector3
		return Vector3.new(x, 0, z)
	end
	-- Side walls (along Z): wainscot, then locker rows and notice boards between `from` and `to` (along the face).
	local sideFaces: { { face: Face, doors: { number }, from: number, to: number } } = {
		{ face = { a = v(-half, backZ), b = v(-half, turn1), normal = px }, doors = {}, from = 16, to = 100 },
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
		{ face = { a = v(-half, turn2), b = v(-half, LENGTH), normal = px }, doors = {}, from = 10, to = 88 },
		{
			face = { a = v(half, turn2), b = v(half, LENGTH), normal = nx, skip = doorSkips(doorsC, turn2, 0) },
			doors = doorsC,
			from = 10,
			to = 88,
		},
	}
	for _, side in sideFaces do
		wainscot(dressing, side.face)
		dressFace(dressing, side.face, side.from, side.to, doorSkips(side.doors, side.face.a.Z, 1))
		for _, z in side.doors do
			Props.classroomDoorway(dressing, faceFrame(side.face, z - side.face.a.Z, ROOM_LIFT, 0))
		end
	end

	-- End walls and turn walls (along X): wainscot only. The end wall is left bare behind the exit door.
	local backFace: Face = { a = v(-half, backZ), b = v(half, backZ), normal = pz }
	local crossFaces: { Face } = {
		backFace,
		{ a = v(-half, turn1), b = v(-half + STEP, turn1), normal = nz },
		{ a = v(half, turn1), b = v(half + STEP, turn1), normal = pz },
		{ a = v(-half, turn2), b = v(-half + STEP, turn2), normal = pz },
		{ a = v(half, turn2), b = v(half + STEP, turn2), normal = nz },
		{ a = v(-half, LENGTH), b = v(half, LENGTH), normal = nz, skip = { { half - 7, half + 7 } } },
	}
	for _, face in crossFaces do
		wainscot(dressing, face)
	end
	Props.noticeBoard(dressing, faceFrame(backFace, half, 4, 0))

	-- Ceiling lamps down the middle of each segment, LAMP_SPACING apart; every 4th one flickers.
	-- Props tags the lamp Model, but Atmosphere flickers tagged BaseParts, so the tubes are tagged as well.
	local lampSpots: { Vector3 } = {}
	for i = 0, 3 do
		table.insert(lampSpots, Vector3.new(0, WALL_HEIGHT, 8 + i * LAMP_SPACING))
		table.insert(lampSpots, Vector3.new(STEP, WALL_HEIGHT, turn1 + 8 + i * LAMP_SPACING))
		table.insert(lampSpots, Vector3.new(0, WALL_HEIGHT, turn2 + 8 + i * LAMP_SPACING))
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

	-- The exit door stands against the end wall, inside the Exit trigger (z 296..300).
	Props.exitDoor(dressing, CFrame.lookAt(Vector3.new(0, 0, LENGTH - 0.6), Vector3.new(0, 0, 0)))

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

	-- Exit is a walk-through trigger spanning the full corridor width at the far end.
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

	hall.Parent = Workspace
	return hall
end

return HallBuilder

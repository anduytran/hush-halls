--!strict
-- Builds the greybox hall: a 24-stud-wide, 300-stud-long corridor running along +Z.
-- It has three straight segments joined by two side-step turns (the corridor jogs 12 studs
-- sideways at z=100 and back at z=200), plus pillar and crate obstacles.
-- Named children: Start (SpawnLocation at z=0), Floor (top at Y=0), Exit (neon trigger at the far end),
-- Walls, Obstacles and Hazards.
-- Sprint 34: three obstacle layouts. HallBuilder.buildLayout(index) rebuilds Hall.Obstacles and Hall.Hazards
-- (puddles tagged "Puddle", planks tagged "Plank"; Hazards.luau gives them their noise). Start, Exit, Floor
-- and Walls are never touched. Hall's "Layout" attribute is the layout in use.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local HallBuilder = {}

local WIDTH = 24
local LENGTH = 300
local WALL_HEIGHT = 20
local WALL_THICKNESS = 2
local STEP = 12 -- how far the middle segment is shifted along +X

local CONCRETE = Color3.fromRGB(58, 58, 62)
local WALL_CONCRETE = Color3.fromRGB(72, 72, 76)
local PILLAR_CONCRETE = Color3.fromRGB(46, 46, 50)
local CRATE_COLOR = Color3.fromRGB(84, 78, 70)
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
	box(parent, name, Vector3.new(x0, 0, z0), Vector3.new(x1, WALL_HEIGHT, z1), WALL_CONCRETE, Enum.Material.Concrete)
end

local function pillar(parent: Instance, x: number, z: number)
	box(
		parent,
		"Pillar",
		Vector3.new(x - 2, 0, z - 2),
		Vector3.new(x + 2, WALL_HEIGHT, z + 2),
		PILLAR_CONCRETE,
		Enum.Material.Concrete
	)
end

local function crate(parent: Instance, x: number, z: number, size: number)
	local half = size / 2
	box(
		parent,
		"Crate",
		Vector3.new(x - half, 0, z - half),
		Vector3.new(x + half, size, z + half),
		CRATE_COLOR,
		Enum.Material.WoodPlanks
	)
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
			pillar(obstacles, obstacle.x, obstacle.z)
		else
			crate(obstacles, obstacle.x, obstacle.z, obstacle.size or 5)
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
		CONCRETE,
		Enum.Material.Concrete
	)
	hall.PrimaryPart = floor

	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	walls.Parent = hall

	-- Segment A: x -12..12, z backZ..100
	wall(walls, "BackWall", -half - t, half + t, backZ - t, backZ)
	wall(walls, "LeftWallA", -half - t, -half, backZ, turn1 + t)
	wall(walls, "RightWallA", half, half + t, backZ, turn1)
	-- Turn 1: corridor steps +12 in X. The 12-stud overlap x 0..12 is the opening.
	wall(walls, "Turn1Right", half, half + STEP + t, turn1 - t, turn1)
	wall(walls, "Turn1Left", -half - t, -half + STEP, turn1, turn1 + t)
	-- Segment B: x 0..24, z 100..200
	wall(walls, "LeftWallB", -half + STEP - t, -half + STEP, turn1, turn2)
	wall(walls, "RightWallB", half + STEP, half + STEP + t, turn1 - t, turn2 + t)
	-- Turn 2: corridor steps back to x -12..12.
	wall(walls, "Turn2Left", -half - t, -half + STEP, turn2 - t, turn2)
	wall(walls, "Turn2Right", half, half + STEP + t, turn2, turn2 + t)
	-- Segment C: x -12..12, z 200..300
	wall(walls, "LeftWallC", -half - t, -half, turn2 - t, LENGTH)
	wall(walls, "RightWallC", half, half + t, turn2, LENGTH)
	wall(walls, "EndWall", -half - t, half + t, LENGTH, LENGTH + t)

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
	exit.Transparency = 0.4

	hall.Parent = Workspace
	return hall
end

return HallBuilder

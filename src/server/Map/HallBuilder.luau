--!strict
-- Builds the greybox hall: a 24-stud-wide, 300-stud-long corridor running along +Z.
-- It has three straight segments joined by two side-step turns (the corridor jogs 12 studs
-- sideways at z=100 and back at z=200), plus pillar and crate obstacles.
-- Named children: Start (SpawnLocation at z=0), Floor (top at Y=0), Exit (neon trigger at the far end).

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

	-- Obstacles: each leaves at least a 12-stud gap, and none sit near the turn openings.
	local obstacles = Instance.new("Folder")
	obstacles.Name = "Obstacles"
	obstacles.Parent = hall
	pillar(obstacles, -6, 30)
	crate(obstacles, 6, 58, 6)
	crate(obstacles, -5, 80, 5)
	pillar(obstacles, 18, 130)
	crate(obstacles, 6, 165, 6)
	pillar(obstacles, -6, 235)
	crate(obstacles, 6, 265, 5)

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

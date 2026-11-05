--!strict
-- Props: part-built set dressing for the flooded school (see design-vault/Mechanics/Map Overhaul.md).
--
-- Every builder has the shape (parent, cf, ...) -> Model and returns an anchored Model with a PrimaryPart.
-- Conventions, in the prop's local space:
--   * the front faces cf.LookVector (local -Z), +X is cf.RightVector;
--   * the base sits at cf.Y (for floor props the bottom of the prop; for classroomDoorway the room's floor top);
--   * exceptions: ceilingLamp hangs DOWN from cf (its mounting top is at cf.Y), and noticeBoard is wall-mounted
--     with its bottom edge at cf.Y and its back on cf's plane.

local CollectionService = game:GetService("CollectionService")

local Props = {}

-- School palette
local LOCKER_GREEN = Color3.fromRGB(84, 104, 88)
local LOCKER_DOOR = Color3.fromRGB(94, 114, 96)
local LOCKER_DARK = Color3.fromRGB(38, 46, 40)
local STEEL = Color3.fromRGB(170, 172, 168)
local PLASTER = Color3.fromRGB(214, 202, 172)
local PLASTER_DIM = Color3.fromRGB(96, 90, 76)
local WOOD_DARK = Color3.fromRGB(66, 44, 30)
local WOOD_MID = Color3.fromRGB(96, 66, 44)
local FLOOR_DARK = Color3.fromRGB(58, 58, 54)
local CHALK_GREEN = Color3.fromRGB(34, 52, 42)
local CORK = Color3.fromRGB(160, 116, 72)
local DOOR_PAINT = Color3.fromRGB(70, 84, 78)
local EXIT_GREEN = Color3.fromRGB(40, 255, 110)
local TUBE_WHITE = Color3.fromRGB(215, 235, 255)
local LAMP_LIGHT = Color3.fromRGB(190, 220, 255)

local function newModel(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	return model
end

local function part(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function finish(model: Model, primary: BasePart, parent: Instance): Model
	model.PrimaryPart = primary
	model.Parent = parent
	return model
end

local function setCollide(model: Model, collide: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = collide
		end
	end
end

-- Builds a locker model without parenting it, tinted by `variant` so rows don't look copy-pasted.
local function buildLocker(cf: CFrame, variant: number): Model
	local model = newModel("Locker")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local shade = 1 + ((variant * 37) % 7 - 3) * 0.025
	local door = Color3.new(
		math.clamp(LOCKER_DOOR.R * shade, 0, 1),
		math.clamp(LOCKER_DOOR.G * shade, 0, 1),
		math.clamp(LOCKER_DOOR.B * shade, 0, 1)
	)

	local base = part(model, "Base", Vector3.new(2, 0.3, 1.9), at(0, 0.15, 0.05), LOCKER_DARK, Enum.Material.Metal)
	part(model, "Body", Vector3.new(2, 6.6, 2), at(0, 3.6, 0), LOCKER_GREEN, Enum.Material.Metal)
	part(model, "Cap", Vector3.new(2, 0.1, 2.1), at(0, 6.95, -0.05), LOCKER_DARK, Enum.Material.Metal)
	part(model, "Door", Vector3.new(1.76, 6.3, 0.08), at(0, 3.6, -1.04), door, Enum.Material.Metal)
	for i = 0, 3 do
		local y = 6.25 - i * 0.18
		part(model, "VentTop", Vector3.new(1.1, 0.07, 0.05), at(0, y, -1.09), LOCKER_DARK, Enum.Material.Metal)
	end
	for i = 0, 2 do
		local y = 1.15 - i * 0.18
		part(model, "VentLow", Vector3.new(1.1, 0.07, 0.05), at(0, y, -1.09), LOCKER_DARK, Enum.Material.Metal)
	end
	part(model, "Handle", Vector3.new(0.12, 0.6, 0.14), at(0.6, 3.7, -1.15), STEEL, Enum.Material.Metal)
	part(model, "Lock", Vector3.new(0.22, 0.22, 0.06), at(0.6, 4.2, -1.1), STEEL, Enum.Material.Metal)
	part(model, "NumberPlate", Vector3.new(0.5, 0.18, 0.04), at(0, 5.6, -1.1), STEEL, Enum.Material.Metal)
	model.PrimaryPart = base
	return model
end

-- A single school locker, about 2 wide x 7 tall x 2 deep.
function Props.locker(parent: Instance, cf: CFrame): Model
	local model = buildLocker(cf, 0)
	model.Parent = parent
	return model
end

-- `count` lockers side by side along cf.RightVector, centred on cf.
function Props.lockerRow(parent: Instance, cf: CFrame, count: number): Model
	local row = newModel("LockerRow")
	local n = math.max(1, math.floor(count))
	local middle: BasePart? = nil
	for i = 1, n do
		local x = (i - 1 - (n - 1) / 2) * 2
		local locker = buildLocker(cf * CFrame.new(x, 0, 0), i)
		locker.Parent = row
		if i == math.ceil(n / 2) then
			middle = locker.PrimaryPart
		end
	end
	row.PrimaryPart = middle
	row.Parent = parent
	return row
end

-- A student desk with its chair behind it; a seated student would look along cf.LookVector.
local function buildDesk(cf: CFrame): Model
	local model = newModel("Desk")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local metal = Enum.Material.Metal
	part(model, "Top", Vector3.new(3.4, 0.2, 2.2), at(0, 2.6, 0), WOOD_MID, Enum.Material.Wood)
	part(model, "Shelf", Vector3.new(3, 0.1, 1.8), at(0, 1.9, 0), STEEL, metal)
	for _, x in { -1.5, 1.5 } do
		for _, z in { -0.9, 0.9 } do
			part(model, "Leg", Vector3.new(0.18, 2.5, 0.18), at(x, 1.25, z), STEEL, metal)
		end
	end
	-- chair
	part(model, "Seat", Vector3.new(1.7, 0.2, 1.6), at(0, 1.6, 2.1), WOOD_MID, Enum.Material.Wood)
	part(model, "Back", Vector3.new(1.7, 1.2, 0.15), at(0, 2.7, 2.85), WOOD_MID, Enum.Material.Wood)
	for _, x in { -0.75, 0.75 } do
		part(model, "ChairLeg", Vector3.new(0.14, 1.5, 0.14), at(x, 0.75, 1.45), STEEL, metal)
		part(model, "ChairLeg", Vector3.new(0.14, 3.2, 0.14), at(x, 1.6, 2.85), STEEL, metal)
	end
	-- a forgotten book
	part(
		model,
		"Book",
		Vector3.new(0.9, 0.12, 1.2),
		at(-0.6, 2.76, -0.1) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(120, 40, 36),
		Enum.Material.SmoothPlastic
	)
	-- the base: a flat invisible pad at floor level
	local pad = part(model, "Base", Vector3.new(3.4, 0.05, 4), at(0, 0.025, 1), FLOOR_DARK, Enum.Material.SmoothPlastic)
	pad.Transparency = 1
	pad.CanCollide = false
	model.PrimaryPart = pad
	return model
end

function Props.desk(parent: Instance, cf: CFrame): Model
	local model = buildDesk(cf)
	model.Parent = parent
	return model
end

-- A wood-framed 6 x 9 doorway with a small closed classroom 10 deep behind it (local +Z).
-- The doorway's outer face is on cf's plane; the room's floor top is at cf.Y.
function Props.classroomDoorway(parent: Instance, cf: CFrame): Model
	local model = newModel("ClassroomDoorway")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local plaster = Enum.Material.Plaster
	local wood = Enum.Material.Wood

	-- interior is x -6..6, z 1..11, y 0..10
	local floor = part(model, "Floor", Vector3.new(14, 1, 12), at(0, -0.5, 6), FLOOR_DARK, Enum.Material.Slate)
	part(model, "Ceiling", Vector3.new(14, 1, 12), at(0, 10.5, 6), PLASTER_DIM, plaster)
	part(model, "BackWall", Vector3.new(14, 10, 1), at(0, 5, 11.5), PLASTER_DIM, plaster)
	part(model, "SideWall", Vector3.new(1, 10, 10), at(-6.5, 5, 6), PLASTER_DIM, plaster)
	part(model, "SideWall", Vector3.new(1, 10, 10), at(6.5, 5, 6), PLASTER_DIM, plaster)

	-- front wall around the 6 x 9 opening
	part(model, "FrontWall", Vector3.new(4, 11, 1), at(-5, 5.5, 0.5), PLASTER, plaster)
	part(model, "FrontWall", Vector3.new(4, 11, 1), at(5, 5.5, 0.5), PLASTER, plaster)
	part(model, "Lintel", Vector3.new(6, 2, 1), at(0, 10, 0.5), PLASTER, plaster)
	-- wainscot panelling on the corridor side
	part(model, "Wainscot", Vector3.new(3.5, 3.5, 0.15), at(-5.25, 1.75, -0.07), WOOD_DARK, wood)
	part(model, "Wainscot", Vector3.new(3.5, 3.5, 0.15), at(5.25, 1.75, -0.07), WOOD_DARK, wood)

	-- wood frame (casing) around the opening
	part(model, "Jamb", Vector3.new(0.5, 9.5, 1.4), at(-3.25, 4.75, 0.4), WOOD_DARK, wood)
	part(model, "Jamb", Vector3.new(0.5, 9.5, 1.4), at(3.25, 4.75, 0.4), WOOD_DARK, wood)
	part(model, "Header", Vector3.new(7, 0.5, 1.4), at(0, 9.25, 0.4), WOOD_DARK, wood)
	part(model, "Threshold", Vector3.new(6, 0.08, 1), at(0, 0.04, 0.5), WOOD_DARK, wood)
	-- room number plate beside the door
	part(
		model,
		"RoomPlate",
		Vector3.new(1, 0.6, 0.06),
		at(-4.4, 6, -0.03),
		Color3.fromRGB(190, 180, 150),
		Enum.Material.Metal
	)

	-- chalkboard on the back wall, facing the doorway
	local boardZ = 10.9
	part(model, "BoardFrame", Vector3.new(8.4, 4.2, 0.2), at(0, 5.6, boardZ), WOOD_DARK, wood)
	part(model, "Chalkboard", Vector3.new(7.8, 3.6, 0.1), at(0, 5.6, boardZ - 0.12), CHALK_GREEN, Enum.Material.Slate)
	part(model, "ChalkTray", Vector3.new(7.8, 0.12, 0.4), at(0, 3.55, boardZ - 0.25), WOOD_DARK, wood)
	part(
		model,
		"Scrawl",
		Vector3.new(3.2, 0.08, 0.02),
		at(-1.6, 6.6, boardZ - 0.18) * CFrame.Angles(0, 0, 0.05),
		Color3.fromRGB(200, 205, 200),
		Enum.Material.SmoothPlastic
	)
	part(
		model,
		"Scrawl",
		Vector3.new(2.4, 0.08, 0.02),
		at(-2, 6.1, boardZ - 0.18) * CFrame.Angles(0, 0, -0.03),
		Color3.fromRGB(200, 205, 200),
		Enum.Material.SmoothPlastic
	)

	-- two desks facing the chalkboard (one knocked askew)
	local face = CFrame.Angles(0, math.pi, 0)
	buildDesk(cf * CFrame.new(-2.6, 0, 6.5) * face).Parent = model
	buildDesk(cf * CFrame.new(2.8, 0, 5.2) * face * CFrame.Angles(0, 0.35, 0)).Parent = model

	return finish(model, floor, parent)
end

-- A fluorescent ceiling fixture hanging down from cf (mount top at cf.Y), tubes along cf.RightVector.
-- flicker=true tags the model "FlickerLamp" for Atmosphere.
function Props.ceilingLamp(parent: Instance, cf: CFrame, flicker: boolean?): Model
	local model = newModel("CeilingLamp")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local metal = Enum.Material.Metal
	part(model, "Rod", Vector3.new(0.08, 0.8, 0.08), at(-1.8, -0.4, 0), STEEL, metal)
	part(model, "Rod", Vector3.new(0.08, 0.8, 0.08), at(1.8, -0.4, 0), STEEL, metal)
	local housing =
		part(model, "Housing", Vector3.new(5, 0.35, 1.3), at(0, -0.97, 0), Color3.fromRGB(200, 200, 192), metal)
	part(model, "Lip", Vector3.new(5, 0.12, 0.08), at(0, -1.2, -0.62), Color3.fromRGB(150, 150, 144), metal)
	part(model, "Lip", Vector3.new(5, 0.12, 0.08), at(0, -1.2, 0.62), Color3.fromRGB(150, 150, 144), metal)
	local tubes: { Part } = {}
	for _, z in { -0.3, 0.3 } do
		local tube = part(
			model,
			"Tube",
			Vector3.new(4.6, 0.22, 0.22),
			at(0, -1.25, z),
			TUBE_WHITE,
			Enum.Material.Neon,
			Enum.PartType.Cylinder
		)
		tube.CastShadow = false
		table.insert(tubes, tube)
	end
	local light = Instance.new("PointLight")
	light.Color = LAMP_LIGHT
	light.Brightness = 1.2
	light.Range = 20
	light.Shadows = true
	light.Parent = tubes[1]
	setCollide(model, false)
	if flicker then
		CollectionService:AddTag(model, "FlickerLamp")
	end
	return finish(model, housing, parent)
end

-- A 12-wide decorative double exit door with a green neon EXIT sign and a light. CanCollide false throughout.
function Props.exitDoor(parent: Instance, cf: CFrame): Model
	local model = newModel("ExitDoor")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local metal = Enum.Material.Metal
	local wood = Enum.Material.Wood

	local sill = part(model, "Sill", Vector3.new(13.6, 0.1, 1.2), at(0, 0.05, 0), WOOD_DARK, wood)
	part(model, "Jamb", Vector3.new(0.8, 11, 1.2), at(-6.4, 5.5, 0), WOOD_DARK, wood)
	part(model, "Jamb", Vector3.new(0.8, 11, 1.2), at(6.4, 5.5, 0), WOOD_DARK, wood)
	part(model, "Header", Vector3.new(13.6, 0.8, 1.2), at(0, 10.4, 0), WOOD_DARK, wood)
	for _, side in { -1, 1 } do
		local x = side * 3
		part(model, "Leaf", Vector3.new(5.95, 9.9, 0.4), at(x, 5.05, 0.1), DOOR_PAINT, metal)
		local glass = part(
			model,
			"Window",
			Vector3.new(1.6, 2.8, 0.06),
			at(x, 7, -0.13),
			Color3.fromRGB(20, 40, 38),
			Enum.Material.Glass
		)
		glass.Transparency = 0.2
		part(model, "WindowFrame", Vector3.new(1.9, 3.1, 0.04), at(x, 7, -0.11), STEEL, metal)
		part(model, "PushBar", Vector3.new(4.4, 0.3, 0.3), at(x, 3.8, -0.3), STEEL, metal)
		part(model, "KickPlate", Vector3.new(5.4, 1.1, 0.05), at(x, 0.75, -0.13), STEEL, Enum.Material.DiamondPlate)
	end
	part(model, "Seam", Vector3.new(0.1, 9.9, 0.42), at(0, 5.05, 0.1), Color3.fromRGB(15, 15, 15), metal)

	-- EXIT sign above the frame
	part(model, "SignBox", Vector3.new(4.4, 1.5, 0.5), at(0, 11.75, 0.1), Color3.fromRGB(30, 34, 32), metal)
	local face =
		part(model, "SignFace", Vector3.new(4, 1.15, 0.06), at(0, 11.75, -0.18), EXIT_GREEN, Enum.Material.Neon)
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
	local signLight = Instance.new("PointLight")
	signLight.Color = EXIT_GREEN
	signLight.Brightness = 2
	signLight.Range = 16
	signLight.Parent = face

	setCollide(model, false)
	return finish(model, sill, parent)
end

-- A wall-mounted cork notice board; bottom edge at cf.Y, back on cf's plane, front along cf.LookVector.
function Props.noticeBoard(parent: Instance, cf: CFrame): Model
	local model = newModel("NoticeBoard")
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local wood = Enum.Material.Wood
	local w, h = 5, 3.5
	local cork = part(model, "Cork", Vector3.new(w, h, 0.15), at(0, h / 2, -0.075), CORK, Enum.Material.Fabric)
	part(model, "Frame", Vector3.new(w + 0.4, 0.2, 0.25), at(0, h + 0.1, -0.125), WOOD_DARK, wood)
	part(model, "Frame", Vector3.new(w + 0.4, 0.2, 0.25), at(0, -0.1, -0.125), WOOD_DARK, wood)
	part(model, "Frame", Vector3.new(0.2, h, 0.25), at(-w / 2 - 0.1, h / 2, -0.125), WOOD_DARK, wood)
	part(model, "Frame", Vector3.new(0.2, h, 0.25), at(w / 2 + 0.1, h / 2, -0.125), WOOD_DARK, wood)
	local papers = {
		{ -1.6, 2.5, 1.0, 1.3, 0.08, Color3.fromRGB(206, 198, 172) },
		{ -0.3, 2.2, 1.1, 1.5, -0.05, Color3.fromRGB(190, 176, 120) },
		{ 1.3, 2.4, 1.3, 1.0, 0.12, Color3.fromRGB(206, 198, 172) },
		{ -1.2, 0.9, 1.3, 0.9, -0.1, Color3.fromRGB(150, 166, 170) },
		{ 0.9, 1.0, 1.0, 1.2, 0.04, Color3.fromRGB(176, 140, 128) },
	}
	for _, p in papers do
		local x, y, pw, ph, rot, color =
			p[1] :: number, p[2] :: number, p[3] :: number, p[4] :: number, p[5] :: number, p[6] :: Color3
		part(
			model,
			"Paper",
			Vector3.new(pw, ph, 0.02),
			at(x, y, -0.16) * CFrame.Angles(0, 0, rot),
			color,
			Enum.Material.SmoothPlastic
		)
		part(
			model,
			"Pin",
			Vector3.new(0.12, 0.12, 0.12),
			at(x, y + ph / 2 - 0.12, -0.2),
			Color3.fromRGB(170, 30, 30),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
	end
	return finish(model, cork, parent)
end

return Props

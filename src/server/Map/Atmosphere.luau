--!strict
-- Atmosphere: the night look of the flooded school (Map Overhaul, sprint 35).
-- Atmosphere.start() sets up Lighting (dark night, cold ambient, teal fog, a slight teal grade, a little
-- bloom) and makes every CollectionService "FlickerLamp" part flicker now and again. Lamps tagged later
-- (the hall is rebuilt every round) are picked up too. Purely visual: nothing here touches gameplay.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local Atmosphere = {}

local FLICKER_TAG = "FlickerLamp"

-- Tuned with a Studio screenshot (ambient only, no lamps) so the route still reads on a phone at default brightness: dark, but never black.
local LIGHTING = {
	ClockTime = 0.5,
	Brightness = 1.5,
	Ambient = Color3.fromRGB(92, 108, 116),
	OutdoorAmbient = Color3.fromRGB(100, 122, 128),
	EnvironmentDiffuseScale = 0.3,
	EnvironmentSpecularScale = 0.4,
	ExposureCompensation = 0.5,
	GlobalShadows = true,
}

-- Seconds between flicker bursts on one lamp, the toggles in a burst and how long each off/on step lasts.
local FLICKER_GAP_MIN, FLICKER_GAP_MAX = 3, 11
local FLICKER_TOGGLES_MIN, FLICKER_TOGGLES_MAX = 2, 6
local FLICKER_STEP_MIN, FLICKER_STEP_MAX = 0.04, 0.16

local started = false
local rng = Random.new()
-- Each watched lamp has a token; removing the lamp (or untagging it) clears it and ends its flicker loop.
local watching: { [BasePart]: {} } = {}

-- Finds a Lighting child by name and class, or makes it.
local function ensure<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return (existing :: any) :: T
	end
	local instance = Instance.new(className :: any)
	instance.Name = name
	instance.Parent = Lighting
	return (instance :: any) :: T
end

local function setUpLighting()
	for property, value in LIGHTING do
		(Lighting :: any)[property] = value
	end

	local atmosphere = ensure("Atmosphere", "NightFog") :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(90, 140, 138)
	atmosphere.Decay = Color3.fromRGB(40, 78, 80)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.2

	local grade = ensure("ColorCorrectionEffect", "NightGrade") :: ColorCorrectionEffect
	grade.TintColor = Color3.fromRGB(222, 245, 242)
	grade.Contrast = 0.12
	grade.Saturation = -0.1
	grade.Brightness = 0.04

	local bloom = ensure("BloomEffect", "NightBloom") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 20
	bloom.Threshold = 1.6
end

type LampState = {
	lights: { Light },
	enabled: { [Light]: boolean },
	material: Enum.Material,
}

local function captureLamp(part: BasePart): LampState
	local lights: { Light } = {}
	local enabled: { [Light]: boolean } = {}
	for _, child in part:GetDescendants() do
		if child:IsA("Light") then
			table.insert(lights, child)
			enabled[child] = child.Enabled
		end
	end
	return { lights = lights, enabled = enabled, material = part.Material }
end

-- Off dims the bulb (a Neon bulb turns plain) and switches its lights off; on puts them back as they were.
local function setLampOn(part: BasePart, state: LampState, on: boolean)
	for _, light in state.lights do
		if light.Parent then
			light.Enabled = if on then state.enabled[light] else false
		end
	end
	if state.material == Enum.Material.Neon then
		part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function watchLamp(instance: Instance)
	if not instance:IsA("BasePart") or watching[instance] then
		return
	end
	local part = instance
	local token = {}
	watching[part] = token
	task.spawn(function()
		-- Stagger the first burst so lamps built together don't flicker in step.
		task.wait(rng:NextNumber(0, FLICKER_GAP_MAX))
		while watching[part] == token do
			local state = captureLamp(part)
			for _ = 1, rng:NextInteger(FLICKER_TOGGLES_MIN, FLICKER_TOGGLES_MAX) do
				if watching[part] ~= token then
					break
				end
				setLampOn(part, state, false)
				task.wait(rng:NextNumber(FLICKER_STEP_MIN, FLICKER_STEP_MAX))
				setLampOn(part, state, true)
				task.wait(rng:NextNumber(FLICKER_STEP_MIN, FLICKER_STEP_MAX))
			end
			setLampOn(part, state, true)
			task.wait(rng:NextNumber(FLICKER_GAP_MIN, FLICKER_GAP_MAX))
		end
	end)
end

local function unwatchLamp(instance: Instance)
	if instance:IsA("BasePart") then
		watching[instance] = nil
	end
end

function Atmosphere.start()
	if started then
		return
	end
	started = true
	setUpLighting()
	CollectionService:GetInstanceAddedSignal(FLICKER_TAG):Connect(watchLamp)
	CollectionService:GetInstanceRemovedSignal(FLICKER_TAG):Connect(unwatchLamp)
	for _, instance in CollectionService:GetTagged(FLICKER_TAG) do
		watchLamp(instance)
	end
end

return Atmosphere

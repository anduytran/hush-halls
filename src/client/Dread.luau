--!strict
-- Client dread: the closer the monster, the darker the red vignette, the stronger the camera tremble
-- and the tighter the FOV. Dying with the monster close shows a 0.7 s jumpscare (dark frame, flash,
-- jaws snapping shut). Everything resets on CharacterAdded.
-- See design-vault/Mechanics/Routes, Exits and Dread.md and ui-vault/Screens/Dread.md.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Distances in studs: no dread beyond FAR, full dread at NEAR and closer
local FAR = 50
local NEAR = 5
-- How fast the shown intensity follows the target (per second, exponential)
local SMOOTH_RATE = 3
local SHAKE_MAX = 0.15
local SHAKE_SPEED = 9
local FOV_DROP = 8
-- Vignette edge opacity at full intensity
local VIGNETTE_MAX = 0.85
-- Jumpscare
local CATCH_RANGE = 12
local SCARE_TIME = 0.7
-- How often to look for the monster again while it is missing
local SEARCH_INTERVAL = 0.5

local COLOR_VIGNETTE = Color3.fromHex("#3A0004")
local COLOR_SCARE_BG = Color3.fromHex("#070102")
local COLOR_THROAT = Color3.fromHex("#5C0A0E")
local COLOR_JAW = Color3.fromHex("#000000")
local COLOR_TOOTH = Color3.fromHex("#D9CFBD")
local COLOR_FLASH = Color3.fromHex("#FFF2F2")

local RENDER_UNDO = "HushDreadUndo"
local RENDER_APPLY = "HushDreadApply"

local Dread = {}

local started = false

-- 0 beyond FAR, 1 at NEAR or closer, linear in between
local function intensityFor(distance: number): number
	return math.clamp((FAR - distance) / (FAR - NEAR), 0, 1)
end

-- The monster's collision part is Hall.Monster; fall back to any BasePart named Monster in workspace
local function findMonster(): BasePart?
	local hall = workspace:FindFirstChild("Hall")
	local direct = if hall then hall:FindFirstChild("Monster") else nil
	if direct and direct:IsA("BasePart") then
		return direct
	end
	local top = workspace:FindFirstChild("Monster")
	if top and top:IsA("BasePart") then
		return top
	end
	for _, d in workspace:GetDescendants() do
		if d.Name == "Monster" and d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function frame(parent: Instance, name: string, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- One vignette edge: a strip along a screen edge whose gradient fades from opaque at the edge to clear
-- toward the middle. rotation is the UIGradient rotation that points the opaque end at the edge.
local function edge(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2, rotation: number)
	local f = frame(parent, name, COLOR_VIGNETTE)
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor
	f.BackgroundTransparency = 1
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.45, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f
end

local function buildVignette(gui: ScreenGui): { Frame }
	local root = frame(gui, "Vignette", COLOR_VIGNETTE)
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 1
	-- Gradient offset 0 is the left (rotation 0) or top (rotation 90) end; 180/270 flip it
	return {
		edge(root, "Left", UDim2.fromScale(0.35, 1), UDim2.fromScale(0, 0), Vector2.new(0, 0), 0),
		edge(root, "Right", UDim2.fromScale(0.35, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180),
		edge(root, "Top", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0), Vector2.new(0, 0), 90),
		edge(root, "Bottom", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 1), Vector2.new(0, 1), 270),
	}
end

-- A row of diamond teeth straddling a jaw's inner edge (y = 1 for the upper jaw, 0 for the lower)
local function teeth(jaw: Frame, edgeY: number, count: number)
	local row = Instance.new("Frame")
	row.Name = "Teeth"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, edgeY)
	row.Size = UDim2.fromScale(0.62, 0.25)
	row.ZIndex = jaw.ZIndex + 1
	row.Parent = jaw
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0.012, 0)
	list.Parent = row
	for i = 1, count do
		local tooth = frame(row, `Tooth{i}`, COLOR_TOOTH)
		tooth.LayoutOrder = i
		tooth.Rotation = 45
		-- Outer teeth smaller so the bite curves like a mouth
		local fromMiddle = math.abs(i - (count + 1) / 2) / (count / 2)
		local s = 0.75 - 0.35 * fromMiddle
		-- Width cap keeps all teeth on a narrow phone; height sets their size on wider screens
		tooth.Size = UDim2.fromScale(0.09, s)
		tooth.ZIndex = row.ZIndex
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.DominantAxis = Enum.DominantAxis.Height
		aspect.Parent = tooth
	end
end

type Scare = {
	root: Frame,
	flash: Frame,
	upper: Frame,
	lower: Frame,
	scale: UIScale,
}

local UPPER_OPEN = UDim2.fromScale(0.5, 0.2)
-- Shut leaves a gap the size of the tooth tips, so the teeth interlock instead of hiding behind
-- the other jaw (both jaws share a ZIndex)
local UPPER_SHUT = UDim2.fromScale(0.5, 0.45)
local LOWER_OPEN = UDim2.fromScale(0.5, 0.8)
local LOWER_SHUT = UDim2.fromScale(0.5, 0.55)

local function buildScare(gui: ScreenGui): Scare
	local root = frame(gui, "Jumpscare", COLOR_SCARE_BG)
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 10
	root.Visible = false
	-- Everything inside it is non-Active, but the dark frame itself swallows clicks while shown
	root.Active = true

	local mouth = Instance.new("Frame")
	mouth.Name = "Mouth"
	mouth.BackgroundTransparency = 1
	mouth.AnchorPoint = Vector2.new(0.5, 0.5)
	mouth.Position = UDim2.fromScale(0.5, 0.5)
	mouth.Size = UDim2.fromScale(1, 1)
	mouth.ZIndex = 11
	mouth.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = mouth

	-- Dim red throat glow behind the jaws
	local throat = frame(mouth, "Throat", COLOR_THROAT)
	throat.AnchorPoint = Vector2.new(0.5, 0.5)
	throat.Position = UDim2.fromScale(0.5, 0.5)
	throat.Size = UDim2.fromScale(0.75, 0.5)
	throat.ZIndex = 11
	local throatCorner = Instance.new("UICorner")
	throatCorner.CornerRadius = UDim.new(0.5, 0)
	throatCorner.Parent = throat
	local throatFade = Instance.new("UIGradient")
	throatFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	throatFade.Parent = throat

	-- Wide pill-shaped jaws that run off both sides of the screen, so only the curved bite edge shows
	local function jaw(name: string, anchorY: number, position: UDim2, teethEdge: number, count: number): Frame
		local j = frame(mouth, name, COLOR_JAW)
		j.AnchorPoint = Vector2.new(0.5, anchorY)
		j.Position = position
		j.Size = UDim2.fromScale(1.5, 0.75)
		j.ZIndex = 12
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = j
		teeth(j, teethEdge, count)
		return j
	end
	local upper = jaw("UpperJaw", 1, UPPER_OPEN, 1, 9)
	local lower = jaw("LowerJaw", 0, LOWER_OPEN, 0, 8)

	local flash = frame(root, "Flash", COLOR_FLASH)
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 20
	flash.BackgroundTransparency = 1

	return { root = root, flash = flash, upper = upper, lower = lower, scale = scale }
end

function Dread.start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "Dread"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Vignette and jumpscare sit over the HUD
	gui.DisplayOrder = 50
	local edges = buildVignette(gui)
	local scare = buildScare(gui)
	gui.Parent = player:WaitForChild("PlayerGui")

	local monster: BasePart? = nil
	local nextSearch = 0
	local intensity = 0
	local humanoid: Humanoid? = nil
	local root: BasePart? = nil
	local scareToken = 0
	local scareTweens: { Tween } = {}

	-- Camera bookkeeping: the shake offset and FOV drop we applied, so they can be undone exactly
	local shakeCamera: Camera? = nil
	local appliedOffset = CFrame.identity
	local fovCamera: Camera? = nil
	local appliedFovDrop = 0

	local function getMonster(): BasePart?
		local m = monster
		if m and m.Parent then
			return m
		end
		monster = nil
		local now = os.clock()
		if now >= nextSearch then
			nextSearch = now + SEARCH_INTERVAL
			monster = findMonster()
		end
		return monster
	end

	local function setVignette(alpha: number)
		local t = 1 - alpha * VIGNETTE_MAX
		for _, f in edges do
			f.BackgroundTransparency = t
		end
	end

	local function undoShake()
		local cam = shakeCamera
		if cam then
			cam.CFrame = cam.CFrame * appliedOffset:Inverse()
		end
		shakeCamera = nil
		appliedOffset = CFrame.identity
	end

	local function restoreFov()
		local cam = fovCamera
		if cam then
			cam.FieldOfView += appliedFovDrop
		end
		fovCamera = nil
		appliedFovDrop = 0
	end

	-- Adds this frame's FOV drop on top of whatever FOV other code has set since last frame
	local function setFovDrop(cam: Camera, drop: number)
		if fovCamera ~= cam then
			restoreFov()
			fovCamera = cam
		end
		cam.FieldOfView = cam.FieldOfView + appliedFovDrop - drop
		appliedFovDrop = drop
	end

	local function hideScare()
		scareToken += 1
		for _, tween in scareTweens do
			tween:Cancel()
		end
		table.clear(scareTweens)
		scare.root.Visible = false
	end

	local function playScare()
		hideScare()
		local token = scareToken
		scare.flash.BackgroundTransparency = 0
		scare.upper.Position = UPPER_OPEN
		scare.lower.Position = LOWER_OPEN
		scare.scale.Scale = 0.85
		scare.root.Visible = true
		local function tween(target: Instance, seconds: number, style: Enum.EasingStyle, goal: any, delay: number?)
			local info = TweenInfo.new(seconds, style, Enum.EasingDirection.In, 0, false, delay or 0)
			local t = TweenService:Create(target, info, goal)
			table.insert(scareTweens, t)
			t:Play()
		end
		-- Flash burns off fast, the jaws snap shut, and the whole mouth lurches toward the camera
		tween(scare.flash, 0.15, Enum.EasingStyle.Quad, { BackgroundTransparency = 1 })
		tween(scare.upper, 0.28, Enum.EasingStyle.Quint, { Position = UPPER_SHUT }, 0.12)
		tween(scare.lower, 0.28, Enum.EasingStyle.Quint, { Position = LOWER_SHUT }, 0.12)
		tween(scare.scale, SCARE_TIME, Enum.EasingStyle.Quad, { Scale = 1.3 })
		task.delay(SCARE_TIME, function()
			if scareToken == token then
				hideScare()
			end
		end)
	end

	local function resetAll()
		hideScare()
		intensity = 0
		setVignette(0)
		undoShake()
		restoreFov()
	end

	local diedConnection: RBXScriptConnection? = nil
	local function onCharacter(character: Model)
		resetAll()
		if diedConnection then
			diedConnection:Disconnect()
			diedConnection = nil
		end
		humanoid = nil
		root = nil
		local hum = character:WaitForChild("Humanoid", 10)
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		-- A newer character may have arrived while waiting
		if player.Character ~= character then
			return
		end
		if not (hum and hum:IsA("Humanoid")) then
			return
		end
		humanoid = hum
		root = if hrp and hrp:IsA("BasePart") then hrp else nil
		local caught = false
		diedConnection = hum.Died:Connect(function()
			if caught then
				return
			end
			caught = true
			local m = getMonster()
			local r = root
			if m and r and (m.Position - r.Position).Magnitude <= CATCH_RANGE then
				playScare()
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- Before the camera scripts run: take last frame's shake off so they start from a clean CFrame
	RunService:BindToRenderStep(RENDER_UNDO, Enum.RenderPriority.Camera.Value - 1, undoShake)

	-- After the camera scripts: work out intensity and apply vignette, shake and FOV
	RunService:BindToRenderStep(RENDER_APPLY, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local target = 0
		local hum = humanoid
		local r = root
		local m = getMonster()
		if hum and r and m and r.Parent and hum.Health > 0 then
			target = intensityFor((m.Position - r.Position).Magnitude)
		end
		intensity += (target - intensity) * (1 - math.exp(-SMOOTH_RATE * dt))
		if intensity < 0.001 and target == 0 then
			intensity = 0
		end
		setVignette(intensity)

		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		setFovDrop(cam, FOV_DROP * intensity)
		if intensity > 0 then
			local t = os.clock() * SHAKE_SPEED
			local offset = Vector3.new(math.noise(t, 0.3), math.noise(t, 7.1), math.noise(t, 13.7)) * 2
			-- math.noise can stray above 1; keep the offset inside the cap
			if offset.Magnitude > 1 then
				offset = offset.Unit
			end
			appliedOffset = CFrame.new(offset * SHAKE_MAX * intensity)
			shakeCamera = cam
			cam.CFrame = cam.CFrame * appliedOffset
		end
	end)

	-- Studio-only hooks for specs
	if RunService:IsStudio() then
		(Dread :: any)._test = {
			gui = gui,
			intensity = function(): number
				return intensity
			end,
			playScare = playScare,
			reset = resetAll,
		}
	end
end

-- Pure distance curve, exposed for specs
Dread.intensityFor = intensityFor

return Dread

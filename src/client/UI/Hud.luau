--!strict
-- In-round HUD: round state + timer, water bar, noise meter, stamina pips, coins, the hold-to-sprint button
-- and the touch DASH/SLIDE buttons.
-- Reads attributes on ReplicatedStorage.State (see knowledge/planner/mvp-contracts.md) and fires
-- ReplicatedStorage.Remotes.Sprint with true on press, false on release. See ui-vault/Screens/HUD.md.
-- Stamina pips read the LocalPlayer attributes Stamina (0-3, fractional) and InRound. DASH/SLIDE call
-- dash()/slide() on src/client/Movement.luau, required lazily inside pcall on tap
-- (design-vault/Mechanics/Movement Tech.md).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local WATER_MAX = 20

local TITLE_TAGLINE = "Every sound floods the halls."
local TITLE_HINT = "Walk to stay quiet. Sprint and it hears you."
-- Fade in, hold, fade out: about 4 s on screen in total
local TITLE_FADE_IN = 0.25
local TITLE_HOLD = 3
local TITLE_FADE_OUT = 0.75
local NOISE_DANGER = 0.6
local STAMINA_PIPS = 3
-- A pip that drops by more than this in one update counts as spent and flashes
local STAMINA_SPENT_STEP = 0.05
local PIP_FLASH_TIME = 0.35
-- Gap between the movement buttons and between them and the SprintButton
local BUTTON_GAP = 8

local RUNNING_TEXT = "Find an exit. Sprinting is loud."
local RUNNING_TEXT_KEYBOARD = "Find an exit. Q dash, C slide."

local COLOR_BG = Color3.fromHex("#0F1115")
local COLOR_ACCENT = Color3.fromHex("#F5A524")
local COLOR_TEXT = Color3.fromHex("#E8EAF1")
local COLOR_DANGER = Color3.fromHex("#FF6B6B")
local COLOR_WATER = Color3.fromHex("#3A8DFF")
local COLOR_NOISE = Color3.fromHex("#8FD694")

local FONT_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local FONT_MEDIUM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)
local FONT_ITALIC =
	Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium, Enum.FontStyle.Italic)

local Hud = {}

-- The title card shows once per session, on the first HUD mounted (the join), never on later mounts
local titleShown = false

-- True while some mounted HUD holds the global HushSprint binding
local sprintOwned = false
-- Live HUDs that could take over the binding when its owner is destroyed
local sprintCandidates: { { bind: () -> () } } = {}

-- Studio-only spec hooks per mounted gui (weak keys, so destroyed HUDs are collected)
local testHooks: { [ScreenGui]: any } = setmetatable({}, { __mode = "k" }) :: any
if RunService:IsStudio() then
	Hud._test = {
		hooks = function(gui: ScreenGui): any
			return testHooks[gui]
		end,
	}
end

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 8)
	c.Parent = parent
end

local function label(parent: Instance, name: string, font: Font, maxSize: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = font
	t.TextColor3 = COLOR_TEXT
	t.TextScaled = true
	t.Text = ""
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 14
	limit.MaxTextSize = maxSize
	limit.Parent = t
	t.Parent = parent
	return t
end

local function panel(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = COLOR_BG
	f.BackgroundTransparency = 0.2
	f.BorderSizePixel = 0
	corner(f)
	f.Parent = parent
	return f
end

-- Round touch button in the SprintButton style: amber circle, dark bold text, 0.15 transparency at rest.
-- scale is the scale size; minPx/maxPx clamp it (square).
local function roundButton(parent: Instance, name: string, text: string, scale: number, minPx: number, maxPx: number)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(1, 1)
	b.Size = UDim2.fromScale(scale, scale)
	b.BackgroundColor3 = COLOR_ACCENT
	b.BackgroundTransparency = 0.15
	b.AutoButtonColor = false
	b.FontFace = FONT_BOLD
	b.Text = text
	b.TextColor3 = COLOR_BG
	b.TextScaled = true
	corner(b, UDim.new(1, 0))
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = b
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(minPx, minPx)
	limit.MaxSize = Vector2.new(maxPx, maxPx)
	limit.Parent = b
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize = 14
	textLimit.MaxTextSize = 22
	textLimit.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	b.Parent = parent
	return b
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Waits without the "Infinite yield possible" warning, since State/Remotes come from another module.
local function waitFor(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	while not child do
		child = parent:WaitForChild(name, 30)
	end
	return child
end

-- Join title card: game name, tagline and a one-line hint in a dark panel in the middle of the screen.
-- It fades in, holds, fades out and destroys itself (about 4 s). Size 0.8 x 0.3 scale, clamped to
-- 260x150 - 560x240 px and centred, so on a 375x667 phone it is 300 px wide (clear of the WaterBar on the
-- left) and ends ~145 px above the SprintButton; on a 667x375 landscape phone it ends ~25 px above it.
-- Input passes through (nothing in it is Active).
local function titleCard(parent: Instance): Frame
	local card = panel(parent, "TitleCard")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(0.8, 0.3)
	card.ZIndex = 10
	card.BackgroundTransparency = 1
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MinSize = Vector2.new(260, 150)
	cardLimit.MaxSize = Vector2.new(560, 240)
	cardLimit.Parent = card
	-- Faint water-blue edge so the card reads as part of the flooded halls
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = COLOR_WATER
	edge.Thickness = 1
	edge.Transparency = 1
	edge.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = card
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = card

	local function line(name: string, order: number, font: Font, height: number, maxSize: number): TextLabel
		local t = label(card, name, font, maxSize)
		t.LayoutOrder = order
		t.Size = UDim2.fromScale(1, height)
		t.ZIndex = 11
		t.TextWrapped = true
		t.TextTransparency = 1
		return t
	end
	local title = line("Title", 1, FONT_BOLD, 0.46, 64)
	title.Text = string.upper(Config.GAME_NAME)
	local glow = Instance.new("UIStroke")
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	glow.Color = COLOR_WATER
	glow.Thickness = 1
	glow.Transparency = 1
	glow.Parent = title
	local tagline = line("Tagline", 2, FONT_ITALIC, 0.2, 24)
	tagline.Text = TITLE_TAGLINE
	tagline.TextColor3 = COLOR_WATER
	local hint = line("Hint", 3, FONT_MEDIUM, 0.2, 20)
	hint.Text = TITLE_HINT

	-- Each faded property and the value it fades in to
	local fades: { { target: Instance, shown: { [string]: number } } } = {
		{ target = card, shown = { BackgroundTransparency = 0.1 } },
		{ target = edge, shown = { Transparency = 0.6 } },
		{ target = title, shown = { TextTransparency = 0 } },
		{ target = glow, shown = { Transparency = 0.6 } },
		{ target = tagline, shown = { TextTransparency = 0 } },
		{ target = hint, shown = { TextTransparency = 0.15 } },
	}
	local function fade(seconds: number, visible: boolean)
		for _, f in fades do
			local goal: { [string]: number } = {}
			for prop, value in f.shown do
				goal[prop] = if visible then value else 1
			end
			local direction = if visible then Enum.EasingDirection.Out else Enum.EasingDirection.In
			TweenService:Create(f.target, TweenInfo.new(seconds, Enum.EasingStyle.Quad, direction), goal :: any):Play()
		end
	end
	fade(TITLE_FADE_IN, true)
	-- Timed destroy rather than Tween.Completed, so it still cleans up if the HUD goes away mid-fade
	task.delay(TITLE_FADE_IN + TITLE_HOLD, function()
		if card.Parent then
			fade(TITLE_FADE_OUT, false)
		end
	end)
	task.delay(TITLE_FADE_IN + TITLE_HOLD + TITLE_FADE_OUT, function()
		card:Destroy()
	end)
	return card
end

function Hud.mount()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Top centre: round state + time left
	local top = panel(gui, "RoundInfo")
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 8)
	top.Size = UDim2.fromScale(0.28, 0.08)
	local topLimit = Instance.new("UISizeConstraint")
	topLimit.MinSize = Vector2.new(160, 40)
	topLimit.MaxSize = Vector2.new(360, 64)
	topLimit.Parent = top
	local topPad = Instance.new("UIPadding")
	topPad.PaddingLeft = UDim.new(0, 12)
	topPad.PaddingRight = UDim.new(0, 12)
	topPad.PaddingTop = UDim.new(0, 4)
	topPad.PaddingBottom = UDim.new(0, 4)
	topPad.Parent = top
	local roundText = label(top, "RoundText", FONT_BOLD, 28)

	-- Goal line: its own panel, 4 px under RoundInfo. It keeps RoundInfo's width (0.28 scale, 160-360 px)
	-- so on a 375 px phone it sits in the centre column and clears Coins and the Shop button on the right.
	-- Height 0.08 scale (44-64 px) leaves room for two wrapped lines at 14 px. Its top follows RoundInfo's
	-- real height, because RoundInfo's 40-64 px clamp means a plain scale offset would drift or overlap.
	local goalPanel = panel(gui, "GoalPanel")
	goalPanel.AnchorPoint = Vector2.new(0.5, 0)
	goalPanel.Size = UDim2.fromScale(0.28, 0.08)
	local goalLimit = Instance.new("UISizeConstraint")
	goalLimit.MinSize = Vector2.new(160, 44)
	goalLimit.MaxSize = Vector2.new(360, 64)
	goalLimit.Parent = goalPanel
	local goalPad = Instance.new("UIPadding")
	goalPad.PaddingLeft = UDim.new(0, 8)
	goalPad.PaddingRight = UDim.new(0, 8)
	goalPad.PaddingTop = UDim.new(0, 4)
	goalPad.PaddingBottom = UDim.new(0, 4)
	goalPad.Parent = goalPanel
	local goalText = label(goalPanel, "GoalText", FONT_MEDIUM, 20)
	goalText.TextWrapped = true
	local function placeGoal()
		goalPanel.Position = UDim2.new(0.5, 0, 0, 8 + top.AbsoluteSize.Y + 4)
	end
	placeGoal()

	-- Signal connections, dropped when the HUD is destroyed
	local connections: { RBXScriptConnection } = {}
	local alive = true
	-- Only the HUD that bound the global HushSprint action may unbind it
	local boundSprint = false
	local candidate = { bind = function() end }
	-- Set once sprint is built below: lets go of anything still held so the server isn't left sprinting
	local releaseHeld = function() end
	connections[1] = top:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeGoal)
	local function disconnectAll()
		alive = false
		releaseHeld()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		local index = table.find(sprintCandidates, candidate)
		if index then
			table.remove(sprintCandidates, index)
		end
		if boundSprint then
			boundSprint = false
			sprintOwned = false
			ContextActionService:UnbindAction("HushSprint")
			-- Hand the binding to another live HUD so Shift keeps working
			local successor = sprintCandidates[1]
			if successor then
				successor.bind()
			end
		end
	end
	table.insert(connections, gui.Destroying:Connect(disconnectAll))

	-- keyboard defaults to KeyboardEnabled: keyboard players get the Q/C dash and slide keys in the goal line
	local function setGoal(roundState: any, escaped: boolean, keyboard: boolean?)
		local hasKeyboard = if keyboard == nil then UserInputService.KeyboardEnabled else keyboard
		if roundState == "Running" and escaped then
			goalText.Text = "You escaped! Wait for the next round."
			goalText.TextColor3 = COLOR_NOISE
		elseif roundState == "Running" then
			goalText.Text = if hasKeyboard then RUNNING_TEXT_KEYBOARD else RUNNING_TEXT
			goalText.TextColor3 = COLOR_TEXT
		elseif roundState == "Ended" then
			goalText.Text = "Round over."
			goalText.TextColor3 = COLOR_TEXT
		else
			goalText.Text = "Next round soon. Find an exit."
			goalText.TextColor3 = COLOR_TEXT
		end
	end
	-- Studio-only hook for the spec: drive the goal line without writing replicated State,
	-- and count live connections. Kept per gui: Hud._test.hooks(gui).
	if RunService:IsStudio() then
		testHooks[gui] = {
			setGoal = setGoal,
			connectionCount = function(): number
				return #connections
			end,
		}
	end

	-- Top right: coins
	local coins = panel(gui, "Coins")
	coins.AnchorPoint = Vector2.new(1, 0)
	coins.Position = UDim2.new(1, -8, 0, 8)
	coins.Size = UDim2.fromScale(0.14, 0.07)
	local coinsLimit = Instance.new("UISizeConstraint")
	coinsLimit.MinSize = Vector2.new(96, 36)
	coinsLimit.MaxSize = Vector2.new(200, 56)
	coinsLimit.Parent = coins
	local coinsText = label(coins, "CoinsText", FONT_BOLD, 26)
	coinsText.TextColor3 = COLOR_ACCENT
	coinsText.Text = "Coins: 0"

	-- Left: vertical water bar
	local water = panel(gui, "WaterBar")
	water.AnchorPoint = Vector2.new(0, 0.5)
	water.Position = UDim2.new(0, 8, 0.5, 0)
	water.Size = UDim2.fromScale(0.035, 0.4)
	local waterLimit = Instance.new("UISizeConstraint")
	waterLimit.MinSize = Vector2.new(24, 120)
	waterLimit.MaxSize = Vector2.new(40, 400)
	waterLimit.Parent = water
	local waterFill = Instance.new("Frame")
	waterFill.Name = "Fill"
	waterFill.AnchorPoint = Vector2.new(0, 1)
	waterFill.Position = UDim2.fromScale(0, 1)
	waterFill.Size = UDim2.fromScale(1, 0)
	waterFill.BackgroundColor3 = COLOR_WATER
	waterFill.BorderSizePixel = 0
	corner(waterFill)
	waterFill.Parent = water
	local waterCaption = label(water, "Caption", FONT_MEDIUM, 16)
	waterCaption.AnchorPoint = Vector2.new(0, 0)
	waterCaption.Position = UDim2.new(0, 0, 1, 4)
	waterCaption.Size = UDim2.new(2, 0, 0, 18)
	waterCaption.TextXAlignment = Enum.TextXAlignment.Left
	waterCaption.Text = "Water"

	-- Bottom centre: noise meter
	local noise = panel(gui, "NoiseMeter")
	noise.AnchorPoint = Vector2.new(0.5, 1)
	noise.Position = UDim2.new(0.5, 0, 1, -12)
	noise.Size = UDim2.fromScale(0.35, 0.035)
	local noiseLimit = Instance.new("UISizeConstraint")
	noiseLimit.MinSize = Vector2.new(160, 18)
	noiseLimit.MaxSize = Vector2.new(420, 28)
	noiseLimit.Parent = noise
	local noiseFill = Instance.new("Frame")
	noiseFill.Name = "Fill"
	noiseFill.Size = UDim2.fromScale(0, 1)
	noiseFill.BackgroundColor3 = COLOR_NOISE
	noiseFill.BorderSizePixel = 0
	corner(noiseFill)
	noiseFill.Parent = noise
	local noiseCaption = label(noise, "Caption", FONT_MEDIUM, 16)
	noiseCaption.AnchorPoint = Vector2.new(0.5, 1)
	noiseCaption.Position = UDim2.new(0.5, 0, 0, -4)
	noiseCaption.Size = UDim2.new(1, 0, 0, 18)
	noiseCaption.Text = "Noise"

	-- Bottom centre, just above the Noise caption: 3 stamina pips (only while InRound). Each pip fills
	-- left to right as it regenerates (dimmer until full) and flashes white when spent. Its bottom follows
	-- NoiseMeter's real height (18-28 px clamp) plus the 18 px caption and a 6 px gap.
	local stamina = Instance.new("Frame")
	stamina.Name = "StaminaBar"
	stamina.AnchorPoint = Vector2.new(0.5, 1)
	stamina.Size = UDim2.fromScale(0.18, 0.03)
	stamina.BackgroundTransparency = 1
	stamina.Visible = false
	local staminaLimit = Instance.new("UISizeConstraint")
	staminaLimit.MinSize = Vector2.new(120, 14)
	staminaLimit.MaxSize = Vector2.new(210, 20)
	staminaLimit.Parent = stamina
	local pipList = Instance.new("UIListLayout")
	pipList.FillDirection = Enum.FillDirection.Horizontal
	pipList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipList.SortOrder = Enum.SortOrder.LayoutOrder
	pipList.Padding = UDim.new(0, 6)
	pipList.Parent = stamina
	local pips: { { frame: Frame, fill: Frame, flash: Frame, last: number } } = {}
	for i = 1, STAMINA_PIPS do
		local pip = panel(stamina, "Pip" .. i)
		pip.LayoutOrder = i
		-- Thirds minus the two 6 px gaps
		pip.Size = UDim2.new(1 / STAMINA_PIPS, -4, 1, 0)
		local pipCorner = pip:FindFirstChildOfClass("UICorner") :: UICorner
		pipCorner.CornerRadius = UDim.new(0, 4)
		local pipStroke = Instance.new("UIStroke")
		pipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		pipStroke.Color = COLOR_ACCENT
		pipStroke.Thickness = 1
		pipStroke.Transparency = 0.6
		pipStroke.Parent = pip
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = COLOR_ACCENT
		fill.BorderSizePixel = 0
		corner(fill, UDim.new(0, 4))
		fill.Parent = pip
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = COLOR_TEXT
		flash.BackgroundTransparency = 1
		flash.BorderSizePixel = 0
		flash.ZIndex = 2
		corner(flash, UDim.new(0, 4))
		flash.Parent = pip
		pips[i] = { frame = pip, fill = fill, flash = flash, last = 1 }
	end
	stamina.Parent = gui
	local function placeStamina()
		stamina.Position = UDim2.new(0.5, 0, 1, -(12 + noise.AbsoluteSize.Y + 4 + 18 + 6))
	end
	placeStamina()
	table.insert(connections, noise:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeStamina))

	-- value is 0-3 stamina; nil (Movement hasn't set it yet) reads as full
	local function renderStamina(value: number?)
		local v = math.clamp(if typeof(value) == "number" then value else STAMINA_PIPS, 0, STAMINA_PIPS)
		for i, pip in pips do
			local f = math.clamp(v - (i - 1), 0, 1)
			pip.fill.Size = UDim2.fromScale(f, 1)
			pip.fill.Visible = f > 0
			-- Regenerating pips are dimmer so a full pip reads as ready
			pip.fill.BackgroundTransparency = if f >= 1 then 0 else 0.45
			if f < pip.last - STAMINA_SPENT_STEP then
				pip.flash.BackgroundTransparency = 0.1
				TweenService:Create(
					pip.flash,
					TweenInfo.new(PIP_FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 1 }
				):Play()
			end
			pip.last = f
		end
	end
	renderStamina(nil)

	-- Bottom right: hold-to-sprint (touch only; PC uses LeftShift)
	local sprintButton = roundButton(gui, "SprintButton", "SPRINT", 0.16, 72, 120)
	sprintButton.Position = UDim2.new(1, -16, 1, -16)
	sprintButton.Visible = UserInputService.TouchEnabled

	-- Touch DASH and SLIDE (PC uses Q and C), smaller, in a row above the SprintButton: DASH centred over
	-- it, SLIDE to DASH's left. Kept above it so they stay clear of the NoiseMeter and StaminaBar on a
	-- 375 px portrait phone. Shown only on touch and while InRound.
	local dashButton = roundButton(gui, "DashButton", "DASH", 0.12, 56, 96)
	local slideButton = roundButton(gui, "SlideButton", "SLIDE", 0.12, 56, 96)
	dashButton.Visible = false
	slideButton.Visible = false
	local function placeMoveButtons()
		local sprintSize = sprintButton.AbsoluteSize
		local size = dashButton.AbsoluteSize
		local right = 16 + (sprintSize.X - size.X) / 2
		local bottom = 16 + sprintSize.Y + BUTTON_GAP
		dashButton.Position = UDim2.new(1, -right, 1, -bottom)
		slideButton.Position = UDim2.new(1, -(right + size.X + BUTTON_GAP), 1, -bottom)
	end
	placeMoveButtons()
	table.insert(connections, sprintButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeMoveButtons))
	table.insert(connections, dashButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeMoveButtons))

	-- Spec overrides (Studio hooks only): nil means use the real TouchEnabled / InRound
	local touchOverride: boolean? = nil
	local inRoundOverride: boolean? = nil
	local function refreshInRound()
		local inRound = if inRoundOverride ~= nil then inRoundOverride else player:GetAttribute("InRound") == true
		local touch = if touchOverride ~= nil then touchOverride else UserInputService.TouchEnabled
		stamina.Visible = inRound
		dashButton.Visible = touch and inRound
		slideButton.Visible = touch and inRound
	end
	refreshInRound()
	table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(refreshInRound))
	table.insert(
		connections,
		player:GetAttributeChangedSignal("Stamina"):Connect(function()
			renderStamina(player:GetAttribute("Stamina"))
		end)
	)
	renderStamina(player:GetAttribute("Stamina"))

	-- Movement is built by another module; require it only on tap so a missing or broken module never
	-- breaks the HUD. Warns once per HUD. Specs can swap in a stand-in with hooks.setMovement.
	local movementOverride: any = nil
	local movementWarned = false
	local function callMovement(action: string): boolean
		local ok, err = pcall(function()
			local movement = movementOverride or require((script.Parent :: any).Parent.Movement) :: any
			movement[action]()
		end)
		if not ok and not movementWarned then
			movementWarned = true
			warn(`[Hud] Movement.{action}() failed: {err}`)
		end
		return ok
	end
	local function tapButton(button: TextButton, action: string): boolean
		button.BackgroundTransparency = 0
		task.delay(0.12, function()
			button.BackgroundTransparency = 0.15
		end)
		return callMovement(action)
	end
	for button, action in { [dashButton] = "dash", [slideButton] = "slide" } do
		table.insert(
			connections,
			button.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.Touch
					or input.UserInputType == Enum.UserInputType.MouseButton1
				then
					tapButton(button, action)
				end
			end)
		)
	end

	-- Centre: join title card, first HUD of the session only
	if not titleShown then
		titleShown = true
		titleCard(gui)
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	-- Live values from ReplicatedStorage.State
	task.spawn(function()
		local state = waitFor(ReplicatedStorage, "State")
		local function refreshRound()
			local roundState = state:GetAttribute("RoundState")
			local timeLeft = state:GetAttribute("TimeLeft")
			local text = if typeof(roundState) == "string" then roundState else "Waiting"
			if typeof(timeLeft) == "number" then
				text ..= "  " .. formatTime(timeLeft)
			end
			roundText.Text = text
		end
		local function refreshWater()
			local level = state:GetAttribute("WaterLevel")
			local ratio = if typeof(level) == "number" then math.clamp(level / WATER_MAX, 0, 1) else 0
			waterFill.Size = UDim2.fromScale(1, ratio)
		end
		local function refreshNoise()
			local value = state:GetAttribute("Noise")
			local ratio = if typeof(value) == "number" then math.clamp(value, 0, 1) else 0
			noiseFill.Size = UDim2.fromScale(ratio, 1)
			local loud = ratio > NOISE_DANGER
			noiseFill.BackgroundColor3 = if loud then COLOR_DANGER else COLOR_NOISE
			noiseCaption.Text = if loud then "Noise: LOUD" else "Noise"
		end
		local function refreshGoal()
			setGoal(state:GetAttribute("RoundState"), player:GetAttribute("Escaped") == true)
		end
		-- The HUD may have been destroyed (or the player left) while State was still loading
		if not alive then
			return
		end
		table.insert(connections, state:GetAttributeChangedSignal("RoundState"):Connect(refreshGoal))
		table.insert(connections, player:GetAttributeChangedSignal("Escaped"):Connect(refreshGoal))
		refreshGoal()
		table.insert(connections, state:GetAttributeChangedSignal("RoundState"):Connect(refreshRound))
		table.insert(connections, state:GetAttributeChangedSignal("TimeLeft"):Connect(refreshRound))
		table.insert(connections, state:GetAttributeChangedSignal("WaterLevel"):Connect(refreshWater))
		table.insert(connections, state:GetAttributeChangedSignal("Noise"):Connect(refreshNoise))
		refreshRound()
		refreshWater()
		refreshNoise()
	end)

	-- Coins from leaderstats
	task.spawn(function()
		local leaderstats = waitFor(player, "leaderstats")
		local coinValue = waitFor(leaderstats, "Coins") :: any
		local function refresh()
			coinsText.Text = `Coins: {coinValue.Value}`
		end
		if not alive then
			return
		end
		table.insert(connections, coinValue.Changed:Connect(refresh))
		refresh()
	end)

	-- Sprint: only send on change, so holding Shift and the button together doesn't double-fire
	local sprintRemote: RemoteEvent? = nil
	task.spawn(function()
		local remotes = waitFor(ReplicatedStorage, "Remotes")
		sprintRemote = waitFor(remotes, "Sprint") :: RemoteEvent
	end)
	-- Shift and the button are tracked apart; sprint is on while either is held
	local sprinting = false
	local held: { [string]: boolean } = {}
	local function setSprint(source: string, down: boolean)
		held[source] = down or nil
		local isHeld = next(held) ~= nil
		if isHeld == sprinting then
			return
		end
		sprinting = isHeld
		sprintButton.BackgroundTransparency = if isHeld then 0 else 0.15
		if sprintRemote then
			sprintRemote:FireServer(isHeld)
		end
	end
	releaseHeld = function()
		table.clear(held)
		setSprint("Button", false)
	end

	-- Track the press globally so sliding a finger off the button still counts as a release
	local pressInput: InputObject? = nil
	local function buttonDown(input: InputObject?)
		pressInput = input
		setSprint("Button", true)
	end
	local function buttonUp()
		pressInput = nil
		setSprint("Button", false)
	end
	table.insert(
		connections,
		sprintButton.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				buttonDown(input)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if pressInput and (input == pressInput or input.UserInputType == pressInput.UserInputType) then
				if input.UserInputType == Enum.UserInputType.Touch and input ~= pressInput then
					return
				end
				buttonUp()
			end
		end)
	)
	-- Studio-only sprint hooks: forceTouch shows/hides the button whatever TouchEnabled says, and
	-- pressSprint/releaseSprint run the same press/release as a real touch (including the remote fire)
	local hooks = testHooks[gui]
	if hooks then
		-- Also lets DASH/SLIDE show (they still need InRound, see forceInRound)
		hooks.forceTouch = function(on: boolean)
			sprintButton.Visible = on
			touchOverride = on
			refreshInRound()
		end
		-- true/false pins the InRound visibility of the stamina pips and DASH/SLIDE; nil goes back to the attribute
		hooks.forceInRound = function(on: boolean?)
			inRoundOverride = on
			refreshInRound()
		end
		-- Renders a stamina value (0-3) as if the Stamina attribute had changed; never writes the attribute
		hooks.setStamina = renderStamina
		-- Each pip's fill (0-1), left to right
		hooks.pipFills = function(): { number }
			local fills = {}
			for i, pip in pips do
				fills[i] = pip.last
			end
			return fills
		end
		-- Stand-in for the Movement module (a table with dash/slide); nil goes back to the real one
		hooks.setMovement = function(module: any)
			movementOverride = module
		end
		-- Same as tapping the button; returns whether the Movement call succeeded
		hooks.tapDash = function(): boolean
			return tapButton(dashButton, "dash")
		end
		hooks.tapSlide = function(): boolean
			return tapButton(slideButton, "slide")
		end
		hooks.pressSprint = function()
			buttonDown(nil)
		end
		hooks.releaseSprint = buttonUp
		hooks.isSprinting = function(): boolean
			return sprinting
		end
		-- Builds a fresh title card (whatever titleShown says) under parent, or this HUD's gui
		hooks.showTitle = function(parent: Instance?): Frame
			return titleCard(parent or gui)
		end
	end

	-- The action name is global: a second HUD (such as a spec's) must not replace or remove the live binding
	candidate.bind = function()
		if sprintOwned or not alive then
			return
		end
		sprintOwned = true
		boundSprint = true
		ContextActionService:BindAction("HushSprint", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				setSprint("Shift", true)
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				setSprint("Shift", false)
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.LeftShift)
	end
	table.insert(sprintCandidates, candidate)
	candidate.bind()

	return gui
end

return Hud

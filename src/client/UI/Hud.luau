--!strict
-- In-round HUD: round state + timer, water bar, noise meter, coins and the hold-to-sprint button.
-- Reads attributes on ReplicatedStorage.State (see knowledge/planner/mvp-contracts.md) and fires
-- ReplicatedStorage.Remotes.Sprint with true on press, false on release. See ui-vault/Screens/HUD.md.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local WATER_MAX = 20
local NOISE_DANGER = 0.6

local COLOR_BG = Color3.fromHex("#0F1115")
local COLOR_ACCENT = Color3.fromHex("#F5A524")
local COLOR_TEXT = Color3.fromHex("#E8EAF1")
local COLOR_DANGER = Color3.fromHex("#FF6B6B")
local COLOR_WATER = Color3.fromHex("#3A8DFF")
local COLOR_NOISE = Color3.fromHex("#8FD694")

local FONT_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local FONT_MEDIUM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

local Hud = {}

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

	-- Goal line under the timer; a child of RoundInfo so nothing else in the HUD moves
	local goalText = label(top, "GoalText", FONT_MEDIUM, 20)
	goalText.AnchorPoint = Vector2.new(0.5, 0)
	goalText.Position = UDim2.new(0.5, 0, 1, 10)
	goalText.Size = UDim2.new(2.4, 0, 0, 40)
	goalText.TextWrapped = true
	goalText.TextStrokeTransparency = 0.5

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

	-- Bottom right: hold-to-sprint (touch only; PC uses LeftShift)
	local sprintButton = Instance.new("TextButton")
	sprintButton.Name = "SprintButton"
	sprintButton.AnchorPoint = Vector2.new(1, 1)
	sprintButton.Position = UDim2.new(1, -16, 1, -16)
	sprintButton.Size = UDim2.fromScale(0.16, 0.16)
	sprintButton.BackgroundColor3 = COLOR_ACCENT
	sprintButton.BackgroundTransparency = 0.15
	sprintButton.AutoButtonColor = false
	sprintButton.FontFace = FONT_BOLD
	sprintButton.Text = "SPRINT"
	sprintButton.TextColor3 = COLOR_BG
	sprintButton.TextScaled = true
	sprintButton.Visible = UserInputService.TouchEnabled
	corner(sprintButton, UDim.new(1, 0))
	local sprintAspect = Instance.new("UIAspectRatioConstraint")
	sprintAspect.AspectRatio = 1
	sprintAspect.Parent = sprintButton
	local sprintLimit = Instance.new("UISizeConstraint")
	sprintLimit.MinSize = Vector2.new(72, 72)
	sprintLimit.MaxSize = Vector2.new(120, 120)
	sprintLimit.Parent = sprintButton
	local sprintText = Instance.new("UITextSizeConstraint")
	sprintText.MinTextSize = 14
	sprintText.MaxTextSize = 22
	sprintText.Parent = sprintButton
	local sprintPad = Instance.new("UIPadding")
	sprintPad.PaddingLeft = UDim.new(0, 8)
	sprintPad.PaddingRight = UDim.new(0, 8)
	sprintPad.Parent = sprintButton
	sprintButton.Parent = gui

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
			local roundState = state:GetAttribute("RoundState")
			local escaped = player:GetAttribute("Escaped") == true
			if roundState == "Running" and escaped then
				goalText.Text = "You escaped! Wait for the next round."
				goalText.TextColor3 = COLOR_NOISE
			elseif roundState == "Running" then
				goalText.Text = "Reach the EXIT. Sprinting is loud."
				goalText.TextColor3 = COLOR_TEXT
			elseif roundState == "Ended" then
				goalText.Text = "Round over."
				goalText.TextColor3 = COLOR_TEXT
			else
				goalText.Text = "Next round soon. Reach the EXIT before the water rises."
				goalText.TextColor3 = COLOR_TEXT
			end
		end
		state:GetAttributeChangedSignal("RoundState"):Connect(refreshGoal)
		player:GetAttributeChangedSignal("Escaped"):Connect(refreshGoal)
		refreshGoal()
		state:GetAttributeChangedSignal("RoundState"):Connect(refreshRound)
		state:GetAttributeChangedSignal("TimeLeft"):Connect(refreshRound)
		state:GetAttributeChangedSignal("WaterLevel"):Connect(refreshWater)
		state:GetAttributeChangedSignal("Noise"):Connect(refreshNoise)
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
		coinValue.Changed:Connect(refresh)
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

	-- Track the press globally so sliding a finger off the button still counts as a release
	local pressInput: InputObject? = nil
	sprintButton.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			pressInput = input
			setSprint("Button", true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if pressInput and (input == pressInput or input.UserInputType == pressInput.UserInputType) then
			if input.UserInputType == Enum.UserInputType.Touch and input ~= pressInput then
				return
			end
			pressInput = nil
			setSprint("Button", false)
		end
	end)

	ContextActionService:BindAction("HushSprint", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setSprint("Shift", true)
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			setSprint("Shift", false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift)

	return gui
end

return Hud

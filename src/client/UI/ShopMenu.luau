--!strict
-- Shop button + panel listing every pass and product in Shared.Products. Buy opens the Roblox prompt
-- through src/client/Shop.luau; granting happens on the server. See ui-vault/Screens/Shop.md.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Products = require(ReplicatedStorage.Shared.Products)
local Shop = require(script.Parent.Parent.Shop)

local COLOR_BG = Color3.fromHex("#0F1115")
local COLOR_CARD = Color3.fromHex("#1A1D24")
local COLOR_ACCENT = Color3.fromHex("#F5A524")
local COLOR_TEXT = Color3.fromHex("#E8EAF1")
local COLOR_MUTED = Color3.fromHex("#A3A8B5")

local FONT_BOLD = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)
local FONT_MEDIUM = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium)

local OPEN_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ShopMenu = {}

type Entry = { key: string, kind: "Pass" | "Product", item: Products.Item }

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = parent
end

local function textLimit(parent: Instance, maxSize: number)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 14
	limit.MaxTextSize = maxSize
	limit.Parent = parent
end

local function entries(): { Entry }
	local list: { Entry } = {}
	for key, item in Products.Passes do
		table.insert(list, { key = key, kind = "Pass", item = item })
	end
	for key, item in Products.Products do
		table.insert(list, { key = key, kind = "Product", item = item })
	end
	table.sort(list, function(a, b)
		return a.item.price < b.item.price
	end)
	return list
end

local function makeCard(parent: Instance, entry: Entry, order: number)
	local card = Instance.new("Frame")
	card.Name = entry.key
	card.LayoutOrder = order
	card.Size = UDim2.new(1, 0, 0, 72)
	card.BackgroundColor3 = COLOR_CARD
	card.BorderSizePixel = 0
	corner(card)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = card

	local name = Instance.new("TextLabel")
	name.Name = "ItemName"
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(0.68, 0.5)
	name.FontFace = FONT_BOLD
	name.TextColor3 = COLOR_TEXT
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = entry.item.name
	textLimit(name, 22)
	name.Parent = card

	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.fromScale(0, 0.5)
	desc.Size = UDim2.fromScale(0.68, 0.5)
	desc.FontFace = FONT_MEDIUM
	desc.TextColor3 = COLOR_MUTED
	desc.TextScaled = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Text = entry.item.description
	textLimit(desc, 16)
	desc.Parent = card

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.fromScale(1, 0.5)
	buy.Size = UDim2.fromScale(0.3, 1)
	buy.BackgroundColor3 = COLOR_ACCENT
	buy.FontFace = FONT_BOLD
	buy.TextColor3 = COLOR_BG
	buy.TextScaled = true
	buy.Text = `R$ {entry.item.price}`
	textLimit(buy, 20)
	corner(buy)
	buy.Parent = card
	buy.Activated:Connect(function()
		if entry.kind == "Pass" then
			Shop.buyPass(entry.key)
		else
			Shop.buyProduct(entry.key)
		end
	end)

	card.Parent = parent
end

function ShopMenu.mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopMenu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Under the coins counter on the top right
	local open = Instance.new("TextButton")
	open.Name = "ShopButton"
	open.AnchorPoint = Vector2.new(1, 0)
	open.Position = UDim2.new(1, -8, 0, 72)
	open.Size = UDim2.fromScale(0.14, 0.07)
	open.BackgroundColor3 = COLOR_ACCENT
	open.FontFace = FONT_BOLD
	open.TextColor3 = COLOR_BG
	open.TextScaled = true
	open.Text = "Shop"
	textLimit(open, 24)
	corner(open)
	local openLimit = Instance.new("UISizeConstraint")
	openLimit.MinSize = Vector2.new(96, 44)
	openLimit.MaxSize = Vector2.new(200, 56)
	openLimit.Parent = open
	open.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.5, 0.7)
	panel.BackgroundColor3 = COLOR_BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	corner(panel)
	local panelLimit = Instance.new("UISizeConstraint")
	panelLimit.MinSize = Vector2.new(300, 240)
	panelLimit.MaxSize = Vector2.new(520, 560)
	panelLimit.Parent = panel
	local panelPad = Instance.new("UIPadding")
	panelPad.PaddingLeft = UDim.new(0, 16)
	panelPad.PaddingRight = UDim.new(0, 16)
	panelPad.PaddingTop = UDim.new(0, 12)
	panelPad.PaddingBottom = UDim.new(0, 16)
	panelPad.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	panel.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -52, 0, 44)
	title.FontFace = FONT_BOLD
	title.TextColor3 = COLOR_TEXT
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Shop"
	textLimit(title, 30)
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = COLOR_CARD
	close.FontFace = FONT_BOLD
	close.TextColor3 = COLOR_TEXT
	close.TextSize = 22
	close.Text = "X"
	corner(close)
	close.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 56)
	list.Size = UDim2.new(1, 0, 1, -56)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local items = entries()
	for i, entry in items do
		makeCard(list, entry, i)
	end
	if #items == 0 then
		local empty = Instance.new("TextLabel")
		empty.Name = "Empty"
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 40)
		empty.FontFace = FONT_MEDIUM
		empty.TextColor3 = COLOR_MUTED
		empty.TextSize = 18
		empty.Text = "Nothing for sale yet."
		empty.Parent = list
	end

	local function setOpen(isOpen: boolean)
		if isOpen then
			panel.Visible = true
			scale.Scale = 0.9
			TweenService:Create(scale, OPEN_TWEEN, { Scale = 1 }):Play()
		else
			panel.Visible = false
		end
	end
	open.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

return ShopMenu

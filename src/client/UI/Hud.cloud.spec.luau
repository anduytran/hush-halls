-- Engine tests for the GoalPanel.GoalText line built in Hud.mount().
-- Hud.mount() needs Players.LocalPlayer and PlayerGui, so these only run on a client (Studio play-test).
-- On a server runner the module has no LocalPlayer and the single test below passes without checking anything.
-- The goal text is driven through Hud._test.hooks(gui).setGoal (Studio only); replicated State is never written.
local Hud = require("./Hud")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if not player then
	return {
		["goal line tests skipped: no LocalPlayer on this runner"] = function() end,
	}
end

local LOBBY_TEXT = "Next round soon. Reach the EXIT."
local RUNNING_TEXT = "Reach the EXIT. Sprinting is loud."
local ENDED_TEXT = "Round over."
local ESCAPED_TEXT = "You escaped! Wait for the next round."

local CASES = {
	{ round = "Lobby", escaped = false, text = LOBBY_TEXT, green = false },
	{ round = nil, escaped = false, text = LOBBY_TEXT, green = false },
	{ round = "Lobby", escaped = true, text = LOBBY_TEXT, green = false },
	{ round = "Running", escaped = false, text = RUNNING_TEXT, green = false },
	{ round = "Running", escaped = true, text = ESCAPED_TEXT, green = true },
	{ round = "Ended", escaped = false, text = ENDED_TEXT, green = false },
	{ round = "Ended", escaped = true, text = ENDED_TEXT, green = false },
}

local gui = Hud.mount()
local hudTest = (Hud :: any)._test
assert(hudTest, "Hud._test missing (it should exist in Studio)")
local test = hudTest.hooks(gui)
assert(test, "Hud._test.hooks(gui) returned nothing for the mounted HUD")
local roundInfo = gui:FindFirstChild("RoundInfo") :: Frame
assert(roundInfo, "RoundInfo missing from Hud gui")
local goalPanel = gui:FindFirstChild("GoalPanel") :: Frame
assert(goalPanel, "GoalPanel missing from Hud gui")
local goal = goalPanel:FindFirstChild("GoalText") :: TextLabel
assert(goal and goal:IsA("TextLabel"), "GoalPanel.GoalText missing")

local function isGreen(color: Color3): boolean
	return color.G > color.R and color.G > color.B
end

-- Waits a few frames so layout, AbsoluteSize, deferred signals and TextFits reflect the latest state.
-- Hud's goal Position follows RoundInfo's AbsoluteSize through a signal, which lands about two frames
-- after a move, so two frames is not enough right after reparenting.
local function settle(frames: number?)
	for _ = 1, frames or 2 do
		RunService.Heartbeat:Wait()
	end
end

-- Copy of the replicated State attributes, used to prove the goal line never writes them
local function stateSnapshot(): { [string]: any }
	local state = ReplicatedStorage:FindFirstChild("State")
	assert(state, "ReplicatedStorage.State missing, cannot check that State is untouched")
	return state:GetAttributes()
end

-- Builds a throwaway HUD and a stand-in Shop button (same geometry as ShopMenu's ShopButton) inside a
-- 375x667 frame, so they lay out as on a portrait phone. The live HUD and Shop button are never touched.
-- Returns the frame, the throwaway HUD's panels by name, its test hooks and a cleanup function.
local function phoneViewport(): (Frame, { [string]: GuiObject }, any, () -> ())
	local holder = Instance.new("ScreenGui")
	holder.Name = "HudPhoneTest"
	holder.IgnoreGuiInset = true
	local viewport = Instance.new("Frame")
	viewport.Size = UDim2.fromOffset(375, 667)
	viewport.BackgroundTransparency = 1
	viewport.Parent = holder
	holder.Parent = player:WaitForChild("PlayerGui")

	local throwaway = Hud.mount()
	local throwawayHooks = hudTest.hooks(throwaway)
	local panels: { [string]: GuiObject } = {}
	for _, child in throwaway:GetChildren() do
		if child:IsA("GuiObject") then
			child.Parent = viewport
			panels[child.Name] = child
		end
	end
	local shop = Instance.new("Frame")
	shop.Name = "ShopButton"
	shop.AnchorPoint = Vector2.new(1, 0)
	shop.Position = UDim2.new(1, -8, 0, 72)
	shop.Size = UDim2.fromScale(0.14, 0.07)
	local shopLimit = Instance.new("UISizeConstraint")
	shopLimit.MinSize = Vector2.new(96, 44)
	shopLimit.MaxSize = Vector2.new(200, 56)
	shopLimit.Parent = shop
	shop.Parent = viewport
	panels.ShopButton = shop
	settle(5)

	local function cleanup()
		throwaway:Destroy()
		holder:Destroy()
	end
	return viewport, panels, throwawayHooks, cleanup
end

local function rect(g: GuiObject, origin: Vector2): (Vector2, Vector2)
	local min = g.AbsolutePosition - origin
	return min, min + g.AbsoluteSize
end

local function overlaps(a: GuiObject, b: GuiObject): boolean
	local aMin, aMax = rect(a, Vector2.zero)
	local bMin, bMax = rect(b, Vector2.zero)
	return aMin.X < bMax.X and bMin.X < aMax.X and aMin.Y < bMax.Y and bMin.Y < aMax.Y
end

-- The phone checks, run inside pcall by the test so the panels are always restored afterwards
local function checkPhoneLayout(viewport: Frame, panels: { [string]: GuiObject }, phoneHooks: any)
	local phoneGoalPanel = panels.GoalPanel
	local phoneGoal = phoneGoalPanel:FindFirstChild("GoalText") :: TextLabel
	local origin = viewport.AbsolutePosition
	local min, max = rect(phoneGoalPanel, origin)
	assert(min.X >= 0 and max.X <= 375 and min.Y >= 0 and max.Y <= 667, `GoalPanel off screen: {min} - {max}`)
	assert(phoneGoalPanel.AbsoluteSize.X <= 360, "GoalPanel wider than 360 px")
	for name, other in panels do
		if name ~= "GoalPanel" and other.Visible then
			assert(not overlaps(phoneGoalPanel, other), "GoalPanel overlaps " .. name)
		end
	end
	-- Coins and the Shop button share the right-hand column; the goal line must stay clear of its left edge
	assert(max.X < panels.Coins.AbsolutePosition.X - origin.X, "GoalPanel reaches into the Coins/Shop column")
	for _, case in CASES do
		phoneHooks.setGoal(case.round, case.escaped)
		settle()
		assert(phoneGoal.TextFits, `"{phoneGoal.Text}" does not fit the GoalPanel on a 375x667 phone`)
	end
end

return {
	["goal text and colour match every round state"] = function()
		for _, case in CASES do
			test.setGoal(case.round, case.escaped)
			local context = `{case.round or "nil"} escaped={case.escaped}`
			assert(goal.Text == case.text, `{context}: expected "{case.text}", got "{goal.Text}"`)
			assert(isGreen(goal.TextColor3) == case.green, `{context}: wrong colour {goal.TextColor3}`)
		end
	end,

	["lobby text does not mention water"] = function()
		test.setGoal("Lobby", false)
		assert(not string.find(string.lower(goal.Text), "water"), "Lobby text mentions water: " .. goal.Text)
	end,

	["setGoal never writes replicated State"] = function()
		local before = stateSnapshot()
		for _, case in CASES do
			test.setGoal(case.round, case.escaped)
		end
		local after = stateSnapshot()
		local beforeCount, afterCount = 0, 0
		for key, value in before do
			beforeCount += 1
			assert(after[key] == value, `State.{key} changed from {value} to {after[key]}`)
		end
		for _ in after do
			afterCount += 1
		end
		assert(beforeCount == afterCount, `State attribute count changed: {beforeCount} -> {afterCount}`)
	end,

	["goal panel is its own panel with the size and text limits"] = function()
		assert(goalPanel.Parent == gui and goalPanel ~= roundInfo, "GoalPanel should be a sibling of RoundInfo")
		assert(goalPanel.BackgroundTransparency == roundInfo.BackgroundTransparency, "GoalPanel should use panel()")
		assert(goalPanel.BackgroundColor3 == roundInfo.BackgroundColor3, "GoalPanel should use panel()")
		assert(goalPanel:FindFirstChildOfClass("UICorner"), "GoalPanel should have panel()'s UICorner")
		assert(goalPanel.Size.X.Scale <= 1, "GoalPanel scale width must not exceed the screen")
		local sizeLimit = goalPanel:FindFirstChildOfClass("UISizeConstraint")
		assert(sizeLimit, "GoalPanel needs a UISizeConstraint")
		assert(sizeLimit.MaxSize.X <= 360, "GoalPanel max width above 360: " .. sizeLimit.MaxSize.X)
		assert(goal.Size == UDim2.fromScale(1, 1), "GoalText should fill its panel, got " .. tostring(goal.Size))
		assert(goal.TextScaled and goal.TextWrapped, "GoalText should be TextScaled and TextWrapped")
		local textLimit = goal:FindFirstChildOfClass("UITextSizeConstraint")
		assert(textLimit, "GoalText needs a UITextSizeConstraint")
		assert(textLimit.MinTextSize == 14 and textLimit.MaxTextSize == 20, "GoalText text size should be 14-20")
	end,

	["goal panel size is scale-only with no odd offsets"] = function()
		local size = goalPanel.Size
		assert(size.X.Offset == 0 and size.Y.Offset == 0, "GoalPanel Size should be scale-only, got " .. tostring(size))
		assert(
			size.X.Scale > 0 and size.X.Scale <= 1 and size.Y.Scale > 0 and size.Y.Scale <= 1,
			"GoalPanel Size scale out of range: " .. tostring(size)
		)
	end,

	["goal panel sits directly under RoundInfo"] = function()
		-- Five frames: after another test has moved or restored the panels, the goal Position catches up late
		settle(5)
		local gap = goalPanel.AbsolutePosition.Y - (roundInfo.AbsolutePosition.Y + roundInfo.AbsoluteSize.Y)
		assert(gap >= 0 and gap <= 8, "GoalPanel should be 0-8 px under RoundInfo, gap is " .. gap)
		assert(
			math.abs(
				goalPanel.AbsolutePosition.X
					+ goalPanel.AbsoluteSize.X / 2
					- (roundInfo.AbsolutePosition.X + roundInfo.AbsoluteSize.X / 2)
			) < 1,
			"GoalPanel should be centred under RoundInfo"
		)
	end,

	["on a 375x667 phone the goal panel fits and overlaps nothing"] = function()
		local liveParent = gui.Parent
		local viewport, panels, phoneHooks, cleanup = phoneViewport()
		local ok, err = pcall(checkPhoneLayout, viewport, panels, phoneHooks)
		cleanup()
		assert(gui.Parent == liveParent and goalPanel.Parent == gui, "phone test must not move the live HUD")
		if not ok then
			error(err, 0)
		end
	end,

	["destroying the HUD drops its connections"] = function()
		-- A second HUD with its own hooks, so the shared one above keeps working
		local extra = Hud.mount()
		local extraTest = hudTest.hooks(extra)
		assert(extraTest ~= test, "each mounted HUD should get its own test hooks")
		task.wait(0.5)
		assert(extraTest.connectionCount() > 0, "HUD should hold its State/player connections")
		extra:Destroy()
		-- Destroying is handled a frame later, so give it one frame before counting
		settle(1)
		assert(extraTest.connectionCount() == 0, "connections left after Destroy: " .. extraTest.connectionCount())
	end,

	["destroying a second HUD leaves the live sprint binding intact"] = function()
		local function sprintBound(): boolean
			return ContextActionService:GetAllBoundActionInfo()["HushSprint"] ~= nil
		end
		assert(sprintBound(), "HushSprint should be bound by the first mounted HUD")
		local extra = Hud.mount()
		extra:Destroy()
		settle(2)
		assert(sprintBound(), "destroying a second HUD unbound the live HushSprint action")
	end,

	["destroying several extra HUDs in a row keeps the sprint binding"] = function()
		-- The owner hand-over itself (owner destroyed while another HUD lives) is checked by hand in
		-- Studio: the shared HUD above must stay alive for the other tests, so it can't be the one destroyed.
		local a = Hud.mount()
		local b = Hud.mount()
		a:Destroy()
		b:Destroy()
		settle(2)
		assert(ContextActionService:GetAllBoundActionInfo()["HushSprint"] ~= nil, "HushSprint lost")
	end,
}

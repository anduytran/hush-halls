-- Engine tests for the RoundInfo.GoalText line built in Hud.mount().
-- Hud.mount() needs Players.LocalPlayer and PlayerGui, so these only run on a client (Studio play-test).
-- On a server runner the module has no LocalPlayer and the single test below passes without checking anything.
local Hud = require("./Hud")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player then
	return {
		["goal line tests skipped: no LocalPlayer on this runner"] = function() end,
	}
end

local LOBBY_TEXT = "Next round soon. Reach the EXIT before the water rises."
local RUNNING_TEXT = "Reach the EXIT. Sprinting is loud."
local ENDED_TEXT = "Round over."
local ESCAPED_TEXT = "You escaped! Wait for the next round."

local state = ReplicatedStorage:WaitForChild("State", 30) :: Folder
assert(state, "ReplicatedStorage.State missing")
state:SetAttribute("RoundState", "Lobby")
player:SetAttribute("Escaped", nil)

local gui = Hud.mount()
local roundInfo = gui:FindFirstChild("RoundInfo") :: Frame
assert(roundInfo, "RoundInfo missing from Hud gui")
local goal = roundInfo:FindFirstChild("GoalText") :: TextLabel
assert(goal and goal:IsA("TextLabel"), "RoundInfo.GoalText missing")

local function settle()
	task.wait(0.1)
end

local function setRound(roundState: string)
	state:SetAttribute("RoundState", roundState)
	settle()
end

local function setEscaped(value: boolean?)
	player:SetAttribute("Escaped", value)
	settle()
end

local function expectText(expected: string, context: string)
	assert(goal.Text == expected, `{context}: expected "{expected}", got "{goal.Text}"`)
end

local function isGreen(color: Color3): boolean
	return color.G > color.R and color.G > color.B
end

return {
	["Lobby shows the next-round goal"] = function()
		setEscaped(nil)
		setRound("Lobby")
		expectText(LOBBY_TEXT, "Lobby")
	end,

	["Running shows the reach-EXIT goal"] = function()
		setEscaped(nil)
		setRound("Running")
		expectText(RUNNING_TEXT, "Running")
	end,

	["Ended shows Round over"] = function()
		setEscaped(nil)
		setRound("Ended")
		expectText(ENDED_TEXT, "Ended")
		setRound("Lobby")
	end,

	["Escaped during Running shows the escape message in green"] = function()
		setRound("Running")
		setEscaped(true)
		expectText(ESCAPED_TEXT, "Running + Escaped")
		assert(isGreen(goal.TextColor3), "escape message should be green, got " .. tostring(goal.TextColor3))
		setEscaped(nil)
		setRound("Lobby")
	end,

	["Escaped flag toggling during Running updates the label without a RoundState change"] = function()
		setRound("Running")
		setEscaped(false)
		expectText(RUNNING_TEXT, "Running, not escaped")
		setEscaped(true)
		expectText(ESCAPED_TEXT, "Running, escaped")
		setEscaped(false)
		expectText(RUNNING_TEXT, "Running, escape cleared")
		setRound("Lobby")
	end,

	["Escaped does not change the label outside Running"] = function()
		setEscaped(true)
		setRound("Lobby")
		expectText(LOBBY_TEXT, "Lobby + Escaped")
		setRound("Ended")
		expectText(ENDED_TEXT, "Ended + Escaped")
		setEscaped(nil)
		setRound("Lobby")
	end,

	["non-escape text is not green"] = function()
		setEscaped(nil)
		setRound("Running")
		assert(not isGreen(goal.TextColor3), "Running goal line should not be green")
		setRound("Lobby")
		assert(not isGreen(goal.TextColor3), "Lobby goal line should not be green")
		setRound("Ended")
		assert(not isGreen(goal.TextColor3), "Ended goal line should not be green")
		setRound("Lobby")
	end,

	["label follows each RoundState change in order"] = function()
		setEscaped(nil)
		local sequence = {
			{ "Lobby", LOBBY_TEXT },
			{ "Running", RUNNING_TEXT },
			{ "Ended", ENDED_TEXT },
			{ "Lobby", LOBBY_TEXT },
		}
		for _, step in sequence do
			setRound(step[1])
			expectText(step[2], step[1])
		end
	end,

	["goal label is scaled and wraps for phone-sized screens"] = function()
		assert(goal.TextScaled == true, "GoalText should use TextScaled")
		assert(goal.TextWrapped == true, "GoalText should wrap long lines")
		local limit = goal:FindFirstChildOfClass("UITextSizeConstraint")
		assert(limit ~= nil, "GoalText needs a UITextSizeConstraint")
		assert(limit.MinTextSize >= 14, "GoalText min size should be at least 14, got " .. tostring(limit.MinTextSize))
		assert(limit.MaxTextSize >= limit.MinTextSize, "GoalText max size below min size")
	end,

	["RoundText and the other HUD panels are where Hud.luau places them"] = function()
		setEscaped(nil)
		setRound("Running")
		local roundText = roundInfo:FindFirstChild("RoundText") :: TextLabel
		assert(roundText and roundText:IsA("TextLabel"), "RoundInfo.RoundText missing")
		assert(
			string.sub(roundText.Text, 1, 7) == "Running",
			"RoundText should still show the round state, got " .. roundText.Text
		)
		assert(roundInfo.Size == UDim2.fromScale(0.28, 0.08), "RoundInfo size changed")
		assert(roundInfo.Position == UDim2.new(0.5, 0, 0, 8), "RoundInfo position changed")
		assert(goal.Parent == roundInfo, "GoalText should be a child of RoundInfo")

		local coins = gui:FindFirstChild("Coins") :: Frame
		assert(coins and coins.Position == UDim2.new(1, -8, 0, 8), "Coins panel moved")
		local water = gui:FindFirstChild("WaterBar") :: Frame
		assert(water and water.Position == UDim2.new(0, 8, 0.5, 0), "WaterBar moved")
		local noise = gui:FindFirstChild("NoiseMeter") :: Frame
		assert(noise and noise.Position == UDim2.new(0.5, 0, 1, -12), "NoiseMeter moved")
		local sprint = gui:FindFirstChild("SprintButton", true) :: TextButton
		assert(sprint and sprint.Position == UDim2.new(1, -16, 1, -16), "SprintButton moved")
		setRound("Lobby")
	end,
}

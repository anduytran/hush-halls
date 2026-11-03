-- Engine tests for Monster.luau. Run in a real Roblox server on the test place.
-- Monster.start() only runs once per module instance, so one shared world is built and reused.
-- Sprint/sneak/touch-kill criteria need real Players (the module ignores non-Player characters),
-- so they are not covered here; see the report.
local Monster = require("./Monster")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local state = ReplicatedStorage:FindFirstChild("State")
if not state then
	state = Instance.new("Folder")
	state.Name = "State"
	state.Parent = ReplicatedStorage
end
state:SetAttribute("Noise", 0)
state:SetAttribute("RoundState", "Lobby")

local hall = workspace:FindFirstChild("Hall")
if not hall then
	hall = Instance.new("Folder")
	hall.Name = "Hall"
	hall.Parent = workspace
end
local startPart = hall:FindFirstChild("Start")
if not startPart then
	startPart = Instance.new("Part")
	startPart.Name = "Start"
	startPart.Anchored = true
	startPart.Position = Vector3.new(0, 5, 0)
	startPart.Parent = hall
end
local exitPart = hall:FindFirstChild("Exit")
if not exitPart then
	exitPart = Instance.new("Part")
	exitPart.Name = "Exit"
	exitPart.Anchored = true
	exitPart.Position = Vector3.new(0, 5, 100)
	exitPart.Parent = hall
end

Monster.start()

local function monsterBody(): BasePart
	local body = hall:FindFirstChild("Monster")
	assert(body and body:IsA("BasePart"), "Monster part missing under Hall")
	return body :: BasePart
end

local function flatDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

return {
	["parks about 200 studs beyond Exit when round is not Running"] = function()
		state:SetAttribute("RoundState", "Lobby")
		task.wait(0.2)
		local exit = exitPart :: BasePart
		local body = monsterBody()
		local d = flatDistance(body.Position, exit.Position)
		assert(d >= 199 and d <= 201, "expected parked ~200 studs from Exit, got " .. tostring(d))
	end,

	["re-enters at Exit when round starts"] = function()
		state:SetAttribute("RoundState", "Running")
		task.wait(0.2)
		local exit = exitPart :: BasePart
		local body = monsterBody()
		local d = flatDistance(body.Position, exit.Position)
		assert(d < 10, "expected monster near Exit on round start, got " .. tostring(d))
		state:SetAttribute("RoundState", "Lobby")
	end,

	["CanTouch is off outside Running and on while Running"] = function()
		state:SetAttribute("RoundState", "Lobby")
		task.wait(0.2)
		assert(monsterBody().CanTouch == false, "expected CanTouch false in Lobby")
		state:SetAttribute("RoundState", "Running")
		task.wait(0.2)
		assert(monsterBody().CanTouch == true, "expected CanTouch true in Running")
		state:SetAttribute("RoundState", "Ended")
		task.wait(0.2)
		assert(monsterBody().CanTouch == false, "expected CanTouch false in Ended")
		state:SetAttribute("RoundState", "Lobby")
	end,

	["monster Y is never below the floor"] = function()
		state:SetAttribute("RoundState", "Running")
		task.wait(0.2)
		local body = monsterBody()
		assert(body.Position.Y >= 3, "expected Y clamped to >= FLOOR_Y + SIZE/2 (3), got " .. tostring(body.Position.Y))
		state:SetAttribute("RoundState", "Lobby")
	end,

	["walk speed (10) is ignored and sprint-ish speed (16) is heard"] = function()
		if not RunService:IsStudio() then
			return -- Monster._test only exists in Studio
		end
		local test = Monster._test
		assert(test.isHeard(10) == false, "a target moving at 10 studs/s should be ignored")
		assert(test.isHeard(16) == true, "a target moving at 16 studs/s should be heard")
	end,

	["13 studs/s is heard but is not sprinting"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		assert(test.isHeard(13) == true, "13 studs/s should be heard")
		assert(13 <= test.SPRINT_SPEED, "13 studs/s should not count as sprinting")
		assert(test.HEARD_SPEED < test.SPRINT_SPEED, "the heard threshold should sit below the sprint threshold")
		assert(16 > test.SPRINT_SPEED, "16 studs/s should count as sprinting")
	end,
}

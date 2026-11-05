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

	["first reading at or above HEARD_SPEED is not yet confirmed"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		test.resetHeard()
		local key = {}
		assert(test.confirmHeard(key, 12, 0) == false, "the first reading at 12 studs/s should not confirm")
	end,

	["readings at or above HEARD_SPEED confirm once HEAR_CONFIRM seconds have passed"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		test.resetHeard()
		local key = {}
		-- 0.5 is exact in binary floating point, so 0.5 - 0 >= HEAR_CONFIRM holds without float noise.
		assert(test.confirmHeard(key, 13, 0) == false, "at 0 s the player should not be confirmed yet")
		assert(test.confirmHeard(key, 13, 0.2) == false, "at 0.2 s the player should not be confirmed yet")
		assert(test.confirmHeard(key, 13, 0.4) == false, "at 0.4 s the player should not be confirmed yet")
		assert(test.confirmHeard(key, 13, 0.5) == true, "at 0.5 s the player should be confirmed")
		assert(test.confirmHeard(key, 13, 0.6) == true, "at 0.6 s the player should stay confirmed")
	end,

	["a reading below HEARD_SPEED restarts the hold timer"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		test.resetHeard()
		local key = {}
		assert(test.confirmHeard(key, 13, 0) == false, "at 0 s should not be confirmed yet")
		assert(test.confirmHeard(key, 10, 0.3) == false, "a 10 studs/s reading should not confirm")
		assert(test.confirmHeard(key, 13, 0.4) == false, "at 0.4 s should restart the timer, not confirm")
		assert(test.confirmHeard(key, 13, 0.8) == false, "at 0.8 s only 0.4 s has passed since the restart")
		assert(test.confirmHeard(key, 13, 0.91) == true, "at 0.91 s 0.51 s has passed since the restart")
	end,

	["walk speed (10) never confirms however long it lasts"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		test.resetHeard()
		local key = {}
		for step = 0, 120 do
			local now = step * 0.5
			assert(test.confirmHeard(key, 10, now) == false, "10 studs/s confirmed at " .. tostring(now) .. " s")
		end
	end,

	["two different keys are tracked independently"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		test.resetHeard()
		local a = {}
		local b = {}
		assert(test.confirmHeard(a, 13, 0) == false, "a at 0 s should not be confirmed yet")
		assert(test.confirmHeard(b, 13, 0.3) == false, "b at 0.3 s should not be confirmed yet")
		assert(test.confirmHeard(a, 13, 0.5) == true, "a at 0.5 s should be confirmed")
		assert(test.confirmHeard(b, 13, 0.5) == false, "b at 0.5 s has only held 0.2 s")
		assert(test.confirmHeard(b, 13, 0.8) == true, "b at 0.8 s has held 0.5 s and should be confirmed")
		assert(test.confirmHeard(a, 10, 0.9) == false, "a dropping to 10 studs/s should not confirm")
		assert(test.confirmHeard(b, 13, 0.9) == true, "b should stay confirmed when a resets")
		assert(test.confirmHeard(a, 13, 1.0) == false, "a should need a fresh 0.5 s hold after its reset")
	end,

	["resetHeard clears a confirmed key"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		test.resetHeard()
		local key = {}
		assert(test.confirmHeard(key, 13, 0) == false, "at 0 s should not be confirmed yet")
		assert(test.confirmHeard(key, 13, 0.5) == true, "at 0.5 s should be confirmed before the reset")
		test.resetHeard()
		assert(test.confirmHeard(key, 13, 0.6) == false, "after resetHeard the next reading should not confirm")
		assert(test.confirmHeard(key, 13, 1.0) == false, "at 1.0 s only 0.4 s has passed since the reset")
		assert(test.confirmHeard(key, 13, 1.2) == true, "at 1.2 s 0.6 s has passed since the reset")
	end,

	["HEAR_CONFIRM is 0.5 and HEARD_SPEED stays below SPRINT_SPEED"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		assert(test.HEAR_CONFIRM == 0.5, "expected HEAR_CONFIRM 0.5, got " .. tostring(test.HEAR_CONFIRM))
		assert(test.HEARD_SPEED == 12, "expected HEARD_SPEED 12, got " .. tostring(test.HEARD_SPEED))
		assert(test.HEARD_SPEED < test.SPRINT_SPEED, "the heard threshold should sit below the sprint threshold")
	end,

	["has a looping 3D growl and a one-shot scream on the body"] = function()
		local body = monsterBody()
		local growl = body:FindFirstChild("Growl")
		local scream = body:FindFirstChild("Scream")
		assert(growl and growl:IsA("Sound"), "expected a Growl Sound under the Monster part")
		assert(scream and scream:IsA("Sound"), "expected a Scream Sound under the Monster part")
		assert(growl.Looped == true, "growl should loop")
		assert(scream.Looped == false, "scream should be one-shot")
		assert(
			growl.RollOffMaxDistance >= 50 and growl.RollOffMaxDistance <= 70,
			"growl RollOffMaxDistance should be ~60, got " .. tostring(growl.RollOffMaxDistance)
		)
	end,

	["growl plays only while Running, at drift volume with nobody heard"] = function()
		local body = monsterBody()
		local growl = body:FindFirstChild("Growl") :: Sound
		state:SetAttribute("RoundState", "Running")
		task.wait(0.2)
		assert(growl.Playing == true, "growl should play while Running")
		if RunService:IsStudio() then
			local test = Monster._test
			assert(test.GROWL_VOLUME_CHASE > test.GROWL_VOLUME_DRIFT, "chasing should be louder than drifting")
			assert(growl.Volume == test.GROWL_VOLUME_DRIFT, "with no heard player the growl should be at drift volume")
		end
		state:SetAttribute("RoundState", "Lobby")
		task.wait(0.2)
		assert(growl.Playing == false, "growl should stop outside Running")
	end,
}

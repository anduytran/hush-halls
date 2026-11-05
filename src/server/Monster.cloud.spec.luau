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

-- Sprint 37: patrol pathfinds, so the test world needs something to walk on. Covers every PATROL_AREAS rect.
if not hall:FindFirstChild("Floor") then
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(100, 2, 320)
	floor.Position = Vector3.new(-23, -1, 145) -- top at Y 0, x -73..27, z -15..305
	floor.Parent = hall
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

	["root part stays named Monster and is invisible"] = function()
		local body = monsterBody()
		assert(body.Name == "Monster", "root should be named Monster")
		-- If MonsterModel failed the fallback cube is visible; only check when a model was attached.
		if body:FindFirstChildOfClass("Model") then
			assert(body.Transparency == 1, "root should be invisible when the model is attached")
		end
	end,

	["lunge adds LUNGE_BONUS within LUNGE_RANGE only"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		assert(test.LUNGE_RANGE == 15, "expected LUNGE_RANGE 15")
		assert(test.LUNGE_BONUS == 8, "expected LUNGE_BONUS 8")
		local far = test.chaseSpeed(0.5, 40)
		assert(far == test.BASE_SPEED + 0.5 * test.NOISE_SPEED, "no lunge at 40 studs")
		assert(test.chaseSpeed(0.5, 15) == far + 8, "lunge at exactly 15 studs")
		assert(test.chaseSpeed(0.5, 5) == far + 8, "lunge at 5 studs")
		assert(test.chaseSpeed(0.5, 15.5) == far, "no lunge just past 15 studs")
	end,

	["LISTEN_TIME is 2 seconds"] = function()
		if not RunService:IsStudio() then
			return
		end
		assert(Monster._test.LISTEN_TIME == 2, "expected LISTEN_TIME 2")
	end,

	["repaths at most every 0.5 s and when the goal moves 8+ studs"] = function()
		if not RunService:IsStudio() then
			return
		end
		local repath = Monster._test.shouldRepath
		local aim = Vector3.new(0, 3, 0)
		assert(repath(10, -math.huge, nil, aim, false) == true, "no path yet should repath")
		assert(repath(10, 9.8, nil, aim, false) == false, "throttled under 0.5 s")
		assert(repath(10, 9.5, aim, Vector3.new(7, 3, 0), false) == false, "goal moved 7: keep the path")
		assert(repath(10, 9.5, aim, Vector3.new(8, 3, 0), false) == true, "goal moved 8: repath")
		assert(repath(10, 9.9, aim, Vector3.new(30, 3, 0), false) == false, "big move still throttled")
		assert(repath(10, 9.5, aim, aim, true) == true, "a failed path retries after the throttle")
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

	-- Sprint 37: QA saw it hang at the Exit trigger's centre (0, 10, 298) and never move.
	["enters standing on the floor, not at the Exit trigger's mid-height"] = function()
		state:SetAttribute("RoundState", "Running")
		task.wait(0.2)
		local body = monsterBody()
		assert(math.abs(body.Position.Y - 3) < 0.01, "expected the root at standing height 3, got " .. body.Position.Y)
		state:SetAttribute("RoundState", "Lobby")
	end,

	["patrols when nobody is heard"] = function()
		state:SetAttribute("Noise", 0)
		state:SetAttribute("RoundState", "Running")
		task.wait(0.3)
		local body = monsterBody()
		local from = body.Position
		task.wait(6)
		local moved = flatDistance(body.Position, from)
		state:SetAttribute("RoundState", "Lobby")
		assert(moved >= 3, "expected the monster to patrol with nobody heard, it moved " .. tostring(moved))
	end,

	["patrol points are on the floor inside the hall, corridor and gym areas"] = function()
		if not RunService:IsStudio() then
			return
		end
		local test = Monster._test
		local rng = Random.new(37)
		local seen = {}
		local origin = Vector3.new(0, 3, 50)
		for _ = 1, 300 do
			local p = test.patrolPoint(origin, rng)
			assert(p.Y == test.STANDING_Y, "patrol point should be at standing height, got " .. p.Y)
			local inside = false
			for _, a in test.PATROL_AREAS do
				if p.X >= a.x0 and p.X <= a.x1 and p.Z >= a.z0 and p.Z <= a.z1 then
					inside = true
					seen[a.name] = true
				end
			end
			assert(inside, "patrol point outside every area: " .. tostring(p))
			assert(flatDistance(p, origin) >= test.PATROL_MIN_LEG, "patrol leg too short: " .. tostring(p))
		end
		for _, a in test.PATROL_AREAS do
			assert(seen[a.name], "no patrol point landed in " .. a.name)
		end
	end,

	["exactly one Monster under Hall with exactly one Body"] = function()
		local count = 0
		for _, child in hall:GetChildren() do
			if child.Name == "Monster" then
				count += 1
			end
		end
		assert(count == 1, "expected one Monster under Hall, got " .. count)
		local bodies = 0
		for _, child in monsterBody():GetChildren() do
			if child.Name == "Body" then
				bodies += 1
			end
		end
		-- 0 only when MonsterModel failed and the fallback cube is in use.
		assert(bodies <= 1, "expected at most one Body model, got " .. bodies)
	end,
}

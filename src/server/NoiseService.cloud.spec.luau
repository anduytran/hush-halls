-- Engine tests for NoiseService.luau (rising water). Run in a real Roblox server on the test place.
-- In Studio, NoiseService._test.setNoiseOverride(1) forces Noise to 1, so the rate test checks that the
-- water rises RISE_PER_SECOND (0.3) x window, ±10%. Outside Studio there is no override; the rate is then
-- checked against whatever Noise the server reports (rise = 0.3 x integral of Noise over the window).
-- Every test skips if the round is already Running (a live round on this server would be corrupted), and
-- puts RoundState and WaterLevel back as they were afterwards, even when it fails.
local NoiseService = require("./NoiseService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

NoiseService.start()
local state = ReplicatedStorage:WaitForChild("State")

local RATE = 0.3
local WINDOW = 5 -- seconds sampled per check; longer windows shrink the tick-alignment error
local SAMPLE = 0.05

local function waterLevel(): number
	return (state:GetAttribute("WaterLevel") :: number?) or 0
end

local function setRound(roundState: string)
	state:SetAttribute("RoundState", roundState)
	task.wait(0.5) -- lets the attribute change apply and at least two TICK (0.2 s) steps run
end

local function setOverride(n: number?)
	local test = NoiseService._test
	if test then
		test.setNoiseOverride(n)
	end
end

-- Runs body unless a round is live, then restores RoundState, WaterLevel and the noise override.
local function guarded(name: string, body: () -> ()): () -> ()
	return function()
		local roundState = state:GetAttribute("RoundState")
		if roundState == "Running" then
			print(`[NoiseService.spec] skipped "{name}": a round is Running on this server`)
			return
		end
		local level = waterLevel()
		local ok, err = pcall(body)
		setOverride(nil)
		state:SetAttribute("RoundState", roundState)
		task.wait(0.1) -- the RoundState handler zeroes WaterLevel; let it run before restoring
		state:SetAttribute("WaterLevel", level)
		if not ok then
			error(err, 0)
		end
	end
end

-- Samples for WINDOW seconds. Returns the water rise, the time measured and the integral of Noise over it.
local function measure(): (number, number, number)
	local startLevel = waterLevel()
	local weighted = 0
	local last = os.clock()
	local deadline = last + WINDOW
	while os.clock() < deadline do
		task.wait(SAMPLE)
		local now = os.clock()
		local noise = (state:GetAttribute("Noise") :: number?) or 0
		weighted += noise * (now - last)
		last = now
	end
	return waterLevel() - startLevel, os.clock() - (deadline - WINDOW), weighted
end

local function assertNoRise(roundState: string)
	setOverride(1) -- in Studio, also proves full noise doesn't raise the water outside Running
	setRound(roundState)
	local before = waterLevel()
	task.wait(1.5)
	local rise = waterLevel() - before
	assert(math.abs(rise) <= 0.001, `WaterLevel rose by {rise} in {roundState}, expected no rise`)
end

return {
	["walking is quiet (0.05) and sprinting is full noise (1)"] = function()
		local test = NoiseService._test
		if not test then
			warn("[NoiseService.spec] walk/sprint noise not checked: NoiseService._test only exists in Studio")
			return
		end
		local walk = test.noiseFromSpeed(test.WALK_SPEED)
		local sprint = test.noiseFromSpeed(test.SPRINT_SPEED)
		assert(math.abs(walk - 0.05) <= 1e-6, `noise at WALK_SPEED is {walk}, expected 0.05`)
		assert(math.abs(sprint - 1) <= 1e-6, `noise at SPRINT_SPEED is {sprint}, expected 1`)
		-- A full 120 s round of walking stays under the 3.43 root height.
		assert(walk * test.RISE_PER_SECOND * 120 < 3.43, "walking a full round would drown the player")
	end,

	["water does not rise in Lobby"] = guarded("Lobby", function()
		assertNoRise("Lobby")
	end),

	["water does not rise in Ended"] = guarded("Ended", function()
		assertNoRise("Ended")
	end),

	["water rises at RISE_PER_SECOND x Noise while Running"] = guarded("rate", function()
		local test = NoiseService._test
		if test then
			assert(test.RISE_PER_SECOND == RATE, `RISE_PER_SECOND is {test.RISE_PER_SECOND}, expected {RATE}`)
			test.setNoiseOverride(1)
			setRound("Running")
			local rise, elapsed = measure()
			local expected = RATE * elapsed
			assert(
				math.abs(rise - expected) <= 0.1 * expected,
				`expected rise {expected} (0.3 x {elapsed} s at Noise 1) while Running, got {rise}`
			)
			return
		end
		-- Not Studio: no override, so compare against the Noise the server actually reported.
		setRound("Running")
		local rise, _, weighted = measure()
		local expected = RATE * weighted
		-- The absolute part covers near-zero windows (nobody loud), where the expected rise is about 0.
		local tolerance = 0.1 * expected + 0.02
		assert(
			math.abs(rise - expected) <= tolerance,
			`expected rise {expected} (0.3 x integral Noise {weighted}) while Running, got {rise}`
		)
	end),

	["water stops rising once the round is no longer Running"] = guarded("stop", function()
		setOverride(1)
		setRound("Running")
		task.wait(0.5)
		if NoiseService._test then
			assert(waterLevel() > 0, "WaterLevel did not rise while Running at Noise 1")
		end
		setRound("Ended")
		local before = waterLevel()
		task.wait(1.5)
		local rise = waterLevel() - before
		assert(math.abs(rise) <= 0.001, `WaterLevel rose by {rise} after leaving Running, expected no rise`)
	end),
}

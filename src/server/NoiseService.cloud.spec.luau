-- Engine tests for NoiseService.luau (rising water). Run in a real Roblox server on the test place.
-- NoiseService recomputes State.Noise every tick from real InRound players (fakes are not seen), so
-- Noise can't be forced to 1 from a spec. Instead the rate is checked against whatever Noise the server
-- reports: over a window, WaterLevel rise must equal RISE_PER_SECOND (0.3) times the summed Noise * dt.
-- With no loud player that is simply "no rise". At Noise 1 (a real player sprinting from Start) it is
-- ~0.3 studs/s. The spec assumes no other loop is writing RoundState while it runs.
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

-- Samples for WINDOW seconds. Returns the water rise and the integral of Noise over time.
local function measure(): (number, number)
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
	return waterLevel() - startLevel, weighted
end

return {
	["water does not rise in Lobby"] = function()
		setRound("Lobby")
		local before = waterLevel()
		task.wait(1.5)
		local rise = waterLevel() - before
		assert(math.abs(rise) <= 0.001, `WaterLevel rose by {rise} in Lobby, expected no rise`)
	end,

	["water does not rise in Ended"] = function()
		setRound("Ended")
		local before = waterLevel()
		task.wait(1.5)
		local rise = waterLevel() - before
		assert(math.abs(rise) <= 0.001, `WaterLevel rose by {rise} in Ended, expected no rise`)
		setRound("Lobby")
	end,

	["water rises at RISE_PER_SECOND x Noise while Running"] = function()
		setRound("Running")
		local rise, weighted = measure()
		local expected = RATE * weighted
		-- Relative tolerance covers tick alignment at the window edges; the absolute part covers
		-- near-zero windows (nobody loud), where the expected rise is about 0.
		local tolerance = 0.1 * expected + 0.02
		assert(
			math.abs(rise - expected) <= tolerance,
			`expected rise {expected} (0.3 x integral Noise {weighted}) while Running, got {rise}`
		)
		setRound("Lobby")
	end,

	["water does not rise in Running once the round is no longer Running"] = function()
		setRound("Running")
		task.wait(0.5)
		setRound("Ended")
		local before = waterLevel()
		task.wait(1.5)
		local rise = waterLevel() - before
		assert(math.abs(rise) <= 0.001, `WaterLevel rose by {rise} after leaving Running, expected no rise`)
		setRound("Lobby")
	end,
}

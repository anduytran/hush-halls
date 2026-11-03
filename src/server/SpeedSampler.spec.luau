-- Plain-logic specs for SpeedSampler.luau (run with Lune, no engine).
-- Positions are plain { X, Z } tables and players/roots are plain tables: the sampler reads nothing else.
-- Covers sprint-3 criteria 2 (averaging, jitter, min sample, window, new root, forget/clear) and 3 (teleport filter).
local SpeedSampler = require("./SpeedSampler")

-- Speeds are compared with this tolerance (studs/s).
local TOLERANCE = 0.01

local function assertNear(actual: number, expected: number, label: string, tolerance: number?)
	local limit = tolerance or TOLERANCE
	assert(math.abs(actual - expected) <= limit, `{label}: expected about {expected}, got {actual}`)
end

-- Feeds { time, x, z? } steps for one player and returns the speed reported after each step.
local function feed(sampler, player, root, track)
	local speeds = {}
	for i, step in track do
		speeds[i] = sampler.update(player, root, { X = step.x, Z = step.z or 0 }, step.time)
	end
	return speeds
end

-- Times 0, interval, 2*interval, ... count*interval.
local function every(interval: number, count: number): { number }
	local times = {}
	for i = 0, count do
		times[i + 1] = i * interval
	end
	return times
end

-- A player moving straight along +X at `speed` studs/s, reported at each of `times`.
local function straight(speed: number, times: { number }): { { time: number, x: number } }
	local track = {}
	for i, t in times do
		track[i] = { time = t, x = speed * t }
	end
	return track
end

-- Sample times that alternate 0.1 s and 0.3 s apart (uneven network updates).
local function jittered(count: number): { number }
	local times = { 0 }
	local t = 0
	for i = 1, count do
		local step = if i % 2 == 1 then 0.1 else 0.3
		t += step
		times[#times + 1] = t
	end
	return times
end

local tests = {
	["tuning constants match the sprint-3 spec"] = function()
		assert(SpeedSampler.WINDOW == 0.5, `WINDOW should be 0.5, got {SpeedSampler.WINDOW}`)
		assert(SpeedSampler.MIN_SAMPLE == 0.1, `MIN_SAMPLE should be 0.1, got {SpeedSampler.MIN_SAMPLE}`)
		assert(SpeedSampler.MAX_STEP == 40, `MAX_STEP should be 40, got {SpeedSampler.MAX_STEP}`)
	end,

	["new() returns update, speed, forget and clear"] = function()
		local sampler = SpeedSampler.new()
		for _, name in { "update", "speed", "forget", "clear" } do
			assert(type(sampler[name]) == "function", `sampler.{name} should be a function`)
		end
	end,

	["a player's first sample reports 0"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		assert(sampler.update(player, root, { X = 0, Z = 0 }, 0) == 0, "first sample should read 0")
		assertNear(sampler.speed(player), 0, "speed() after first sample")
	end,

	["speed() of an unknown player is 0"] = function()
		local sampler = SpeedSampler.new()
		assertNear(sampler.speed({}), 0, "speed() of an unknown player")
	end,

	["a steady walker at 10 studs/s reads 10"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		local speeds = feed(sampler, player, root, straight(10, every(0.1, 20)))
		for i = 3, #speeds do
			assertNear(speeds[i], 10, `steady walker, sample {i}`)
		end
	end,

	["a walker at 10 studs/s with 0.1/0.3 s jitter averages near 10 and never above 14"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		local speeds = feed(sampler, player, root, straight(10, jittered(30)))
		for i = 2, #speeds do
			assert(speeds[i] <= 14, `jittered walker must never read as a sprint, sample {i} read {speeds[i]}`)
			assertNear(speeds[i], 10, `jittered walker, sample {i}`, 0.05)
		end
	end,

	["a burst of samples closer than MIN_SAMPLE never spikes the reading"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		local times = { 0, 0.03, 0.06, 0.09, 0.12, 0.2, 0.22, 0.25, 0.3, 0.4 }
		local speeds = feed(sampler, player, root, straight(10, times))
		for i, speed in speeds do
			assert(speed <= 10.05, `burst sample {i} read {speed}, above the walking speed`)
		end
		assertNear(speeds[#speeds], 10, "after the burst")
	end,

	["samples less than MIN_SAMPLE after the last one are ignored"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		assert(sampler.update(player, root, { X = 0, Z = 0 }, 0) == 0, "first sample should read 0")
		-- 0.05 s later: too soon, so it's skipped. Counting it would read 100 studs/s.
		local early = sampler.update(player, root, { X = 5, Z = 0 }, 0.05)
		assert(early == 0, `a sample 0.05 s after the last must be skipped, read {early}`)
		-- 0.2 s after the start: 2 studs in 0.2 s is 10. A moved baseline at 0.05 s would read 20.
		local later = sampler.update(player, root, { X = 2, Z = 0 }, 0.2)
		assertNear(later, 10, "speed after a skipped sample")
	end,

	["a same-instant sample is ignored"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		sampler.update(player, root, { X = 0, Z = 0 }, 1)
		local same = sampler.update(player, root, { X = 9, Z = 0 }, 1)
		assert(same == 0, `a sample at the same time must not count, read {same}`)
	end,

	["speed is averaged over the window: it falls after a walker stops"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		-- Walk along +X at 10 studs/s from 0 to 1.0 s, then stand still at X = 10.
		local track = straight(10, every(0.1, 10))
		table.insert(track, { time = 1.1, x = 10 })
		table.insert(track, { time = 1.2, x = 10 })
		table.insert(track, { time = 1.35, x = 10 })
		local speeds = feed(sampler, player, root, track)
		-- Track indexes: 1..11 are t = 0..1.0, 12 is 1.1, 13 is 1.2, 14 is 1.35.
		assertNear(speeds[11], 10, "reading at the end of the walk")
		-- At 1.35 s the window keeps deltas ending at 0.9, 1.0, 1.1, 1.2, 1.35: 2 studs over 0.55 s, about 3.64.
		-- (0.8 and earlier fall outside; 0.9 is 0.05 s inside the edge, so this doesn't depend on float rounding.)
		assert(speeds[14] > 3.5 and speeds[14] < 3.8, `expected about 3.64 at 1.35 s, got {speeds[14]}`)
		-- 1.6 s: every delta still in the window is stationary.
		assertNear(sampler.update(player, root, { X = 10, Z = 0 }, 1.6), 0, "reading 0.6 s after the walker stopped")
	end,

	["a sprinter at 24 studs/s stays near 24"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		local speeds = feed(sampler, player, root, straight(24, every(0.1, 20)))
		for i = 3, #speeds do
			assertNear(speeds[i], 24, `steady sprinter, sample {i}`)
			assert(speeds[i] >= 14, `sprinter must stay above the sprint threshold, sample {i} read {speeds[i]}`)
		end
	end,

	["a sprinter with 0.5 s update gaps still reads near 24"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		local speeds = feed(sampler, player, root, straight(24, every(0.5, 10)))
		for i = 2, #speeds do
			assertNear(speeds[i], 24, `sprinter with 0.5 s gaps, sample {i}`)
		end
	end,

	["a single teleport is dropped and the sprinter stays near 24"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		-- Sprint 0 to 1.0 s, teleport 100 studs at 1.1 s, then keep sprinting from the new spot.
		local track = straight(24, every(0.1, 10))
		table.insert(track, { time = 1.1, x = 24 * 1.1 + 100 })
		for i = 1, 10 do
			table.insert(track, { time = 1.1 + i * 0.1, x = 24 * 1.1 + 100 + 24 * i * 0.1 })
		end
		local speeds = feed(sampler, player, root, track)
		-- The teleport sample is index 12; without the filter it would read far above 24, or be zeroed by an old cutoff.
		for i = 2, #speeds do
			assertNear(speeds[i], 24, `sprinter across a teleport, sample {i}`)
		end
	end,

	["a step of exactly MAX_STEP counts"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		sampler.update(player, root, { X = 0, Z = 0 }, 0)
		-- 40 studs in 0.1 s is 400 studs/s: the step is kept, so the reading is 400.
		local kept = sampler.update(player, root, { X = 40, Z = 0 }, 0.1)
		assertNear(kept, 400, "a 40-stud step", 0.5)
	end,

	["a step just over MAX_STEP is dropped"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		sampler.update(player, root, { X = 0, Z = 0 }, 0)
		local dropped = sampler.update(player, root, { X = 40.5, Z = 0 }, 0.1)
		assert(dropped == 0, `a 40.5-stud step must be dropped, read {dropped}`)
		assertNear(sampler.speed(player), 0, "speed() after a dropped step")
	end,

	["a diagonal step is measured horizontally"] = function()
		local sampler = SpeedSampler.new()
		local player, root = {}, {}
		sampler.update(player, root, { X = 0, Z = 0 }, 0)
		-- 3-4-5 triangle: 5 studs horizontal in 0.5 s is 10 studs/s.
		local speed = sampler.update(player, root, { X = 3, Z = 4 }, 0.5)
		assertNear(speed, 10, "diagonal walker")
	end,

	["a new root restarts at 0 and forgets the old root's deltas"] = function()
		local sampler = SpeedSampler.new()
		local player, oldRoot, newRoot = {}, {}, {}
		feed(sampler, player, oldRoot, straight(10, every(0.1, 10)))
		assertNear(sampler.speed(player), 10, "before respawn")
		local first = sampler.update(player, newRoot, { X = 10, Z = 0 }, 1.1)
		assert(first == 0, `a new root must restart at 0, read {first}`)
		assertNear(sampler.speed(player), 0, "speed() right after respawn")
		-- 2 studs in 0.2 s after the restart: 10 studs/s. (1.3 - 1.1 avoids a float edge at exactly 0.1.)
		local after = sampler.update(player, newRoot, { X = 12, Z = 0 }, 1.3)
		assertNear(after, 10, "speed after respawn")
	end,

	["players are measured independently"] = function()
		local sampler = SpeedSampler.new()
		local walker, sprinter = {}, {}
		local rootW, rootS = {}, {}
		feed(sampler, walker, rootW, straight(10, every(0.1, 10)))
		feed(sampler, sprinter, rootS, straight(24, every(0.1, 10)))
		assertNear(sampler.speed(walker), 10, "walker")
		assertNear(sampler.speed(sprinter), 24, "sprinter")
	end,

	["forget() drops one player and their next sample starts over"] = function()
		local sampler = SpeedSampler.new()
		local player, other = {}, {}
		local root, otherRoot = {}, {}
		feed(sampler, player, root, straight(10, every(0.1, 10)))
		feed(sampler, other, otherRoot, straight(10, every(0.1, 10)))
		sampler.forget(player)
		assertNear(sampler.speed(player), 0, "speed() after forget")
		local restart = sampler.update(player, root, { X = 11, Z = 0 }, 1.1)
		assert(restart == 0, `after forget the next sample must start over, read {restart}`)
		assertNear(sampler.speed(other), 10, "other player after forget")
	end,

	["clear() forgets every player"] = function()
		local sampler = SpeedSampler.new()
		local a, b = {}, {}
		local rootA, rootB = {}, {}
		feed(sampler, a, rootA, straight(10, every(0.1, 10)))
		feed(sampler, b, rootB, straight(24, every(0.1, 10)))
		sampler.clear()
		assertNear(sampler.speed(a), 0, "speed(a) after clear")
		assertNear(sampler.speed(b), 0, "speed(b) after clear")
		local again = sampler.update(a, rootA, { X = 11, Z = 0 }, 1.1)
		assert(again == 0, `after clear the next sample must start over, read {again}`)
	end,
}

return tests

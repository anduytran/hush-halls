--!strict
-- Server-measured horizontal speed of players, shared by Monster and NoiseService.
-- Speed is the average of position deltas over the last WINDOW seconds, so one uneven network
-- update can't make a walker look like a sprinter. Samples closer together than MIN_SAMPLE are
-- skipped. Sprint-4 fix: a single step longer than MAX_STEP studs (a teleport or a lag spike) is no
-- longer ignored; that step counts as at most SPRINT_SPEED, so it adds noise but can't read faster than a sprint.
-- Only .X and .Z of positions are read and no engine API is used, so it can be tested without Roblox.

local SpeedSampler = {}

SpeedSampler.WINDOW = 0.5
SpeedSampler.MIN_SAMPLE = 0.1
SpeedSampler.MAX_STEP = 40
SpeedSampler.SPRINT_SPEED = 24 -- matches NoiseService's sprint WalkSpeed

type Delta = { time: number, distance: number, dt: number }
type Entry = { root: any, x: number, z: number, time: number, deltas: { Delta } }

export type Sampler = {
	update: (player: any, root: any, position: Vector3, now: number) -> number,
	speed: (player: any) -> number,
	forget: (player: any) -> (),
	clear: () -> (),
}

local function average(deltas: { Delta }): number
	local distance, span = 0, 0
	for _, delta in deltas do
		distance += delta.distance
		span += delta.dt
	end
	return if span > 0 then distance / span else 0
end

function SpeedSampler.new(): Sampler
	local entries: { [any]: Entry } = {}

	-- Records where `root` is at `now` and returns the player's averaged speed.
	-- A new root (respawn) starts again at 0.
	local function update(player: any, root: any, position: Vector3, now: number): number
		local entry = entries[player]
		if not entry or entry.root ~= root then
			entries[player] = { root = root, x = position.X, z = position.Z, time = now, deltas = {} }
			return 0
		end
		local dt = now - entry.time
		if dt >= SpeedSampler.MIN_SAMPLE then
			local dx, dz = position.X - entry.x, position.Z - entry.z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance > SpeedSampler.MAX_STEP then
				-- min: a long step over a long gap (a walker after a stall) keeps its real, slower speed.
				distance = math.min(distance, SpeedSampler.SPRINT_SPEED * dt)
			end
			table.insert(entry.deltas, { time = now, distance = distance, dt = dt })
			entry.x, entry.z, entry.time = position.X, position.Z, now
		end
		-- Keep the deltas that end inside the window.
		while entry.deltas[1] and now - entry.deltas[1].time > SpeedSampler.WINDOW do
			table.remove(entry.deltas, 1)
		end
		return average(entry.deltas)
	end

	local function speed(player: any): number
		local entry = entries[player]
		return if entry then average(entry.deltas) else 0
	end

	local function forget(player: any)
		entries[player] = nil
	end

	local function clear()
		table.clear(entries)
	end

	return { update = update, speed = speed, forget = forget, clear = clear }
end

return SpeedSampler

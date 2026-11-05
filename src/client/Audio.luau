--!strict
-- Client-only sounds: local footsteps, monster heartbeat and rising-water ambience.
-- Every sound is played locally (parented to SoundService), so nothing here replicates.
-- A sound that fails to load just stays silent; nothing in here errors on it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local GameState = require(ReplicatedStorage.Shared.GameState)

local SOUND_IDS = {
	-- Built-in Roblox footstep loop (ships with the client).
	Footsteps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	-- Creator Store "Heartbeat (loop)" by Screaming_Monkeys, free.
	Heartbeat = "rbxassetid://6202853067",
	-- Creator Store "River Water 1 (SFX)" by ProSoundEffects, free.
	Water = "rbxassetid://9118187543",
}

local WALK_SPEED = 10
local SPRINT_SPEED = 24
local MOVING_SPEED = 1 -- below this horizontal speed (studs/s) footsteps are silent
local STEP_VOLUME_WALK = 0.2
local STEP_VOLUME_SPRINT = 0.9
local STEP_RATE_WALK = 0.8
local STEP_RATE_SPRINT = 1.5

local HEARTBEAT_RANGE = 40
local HEARTBEAT_MAX_VOLUME = 1
local HEARTBEAT_RATE_FAR = 0.8
local HEARTBEAT_RATE_NEAR = 1.7
local MONSTER_NAME = "Monster" -- the Part Monster.luau builds under Workspace.Hall
local MONSTER_SEARCH_INTERVAL = 1

local WATER_MIN_VOLUME = 0.1
local WATER_MAX_VOLUME = 0.7
local WATER_FULL_LEVEL = 15 -- studs of WaterLevel at which the ambience is loudest

local FADE_RATE = 4 -- how fast volumes chase their targets (per second)

local Audio = {}

local started = false

local function makeSound(name: string, id: string): Sound?
	local ok, result = pcall(function()
		local sound = Instance.new("Sound")
		sound.Name = `HushAudio_{name}`
		sound.SoundId = id
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		return sound
	end)
	if not ok then
		warn(`[Audio] could not create {name} sound: {result}`)
		return nil
	end
	return result
end

local function setPlaying(sound: Sound?, playing: boolean)
	if sound == nil then
		return
	end
	if playing and not sound.IsPlaying then
		pcall(function()
			sound:Play()
		end)
	elseif not playing and sound.IsPlaying then
		pcall(function()
			sound:Stop()
		end)
	end
end

local function approach(current: number, target: number, dt: number): number
	return current + (target - current) * math.min(1, dt * FADE_RATE)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function partPosition(inst: Instance?): Vector3?
	if inst == nil or not inst:IsDescendantOf(workspace) then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

-- The default character script also plays a "Running" sound; mute it locally so steps aren't doubled.
local function muteDefaultRunning(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil then
		return
	end
	local running = root:WaitForChild("Running", 10)
	if running and running:IsA("Sound") then
		running.Volume = 0
		running:GetPropertyChangedSignal("Volume"):Connect(function()
			if running.Volume ~= 0 then
				running.Volume = 0
			end
		end)
	end
end

function Audio.start()
	if started then
		return
	end
	started = true

	local player = Players.LocalPlayer
	local state = GameState.State

	local footsteps = makeSound("Footsteps", SOUND_IDS.Footsteps)
	local heartbeat = makeSound("Heartbeat", SOUND_IDS.Heartbeat)
	local water = makeSound("Water", SOUND_IDS.Water)

	if player.Character then
		task.spawn(muteDefaultRunning, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(muteDefaultRunning, character)
	end)

	local monster: Instance? = nil
	local lastSearch = -math.huge

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local alive = humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart")
		local rootPos: Vector3? = if alive and root and root:IsA("BasePart") then root.Position else nil

		-- Footsteps: louder and faster with horizontal speed, silent when standing or airborne.
		if footsteps then
			local targetVolume = 0
			if alive and humanoid and root and root:IsA("BasePart") then
				local v = root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
				if grounded and speed >= MOVING_SPEED then
					local t = math.clamp((speed - WALK_SPEED) / (SPRINT_SPEED - WALK_SPEED), 0, 1)
					local slow = math.clamp(speed / WALK_SPEED, 0, 1)
					targetVolume = if speed < WALK_SPEED
						then STEP_VOLUME_WALK * slow
						else lerp(STEP_VOLUME_WALK, STEP_VOLUME_SPRINT, t)
					footsteps.PlaybackSpeed = lerp(STEP_RATE_WALK, STEP_RATE_SPRINT, t)
				end
			end
			footsteps.Volume = targetVolume
			setPlaying(footsteps, targetVolume > 0)
		end

		-- Heartbeat: fades in inside HEARTBEAT_RANGE of the monster and speeds up as it closes in.
		if heartbeat then
			local now = os.clock()
			if partPosition(monster) == nil and now - lastSearch >= MONSTER_SEARCH_INTERVAL then
				lastSearch = now
				monster = workspace:FindFirstChild(MONSTER_NAME, true)
			end
			local monsterPos = partPosition(monster)
			local closeness = 0
			if rootPos and monsterPos then
				closeness = math.clamp(1 - (monsterPos - rootPos).Magnitude / HEARTBEAT_RANGE, 0, 1)
			end
			heartbeat.Volume = approach(heartbeat.Volume, closeness * HEARTBEAT_MAX_VOLUME, dt)
			heartbeat.PlaybackSpeed = lerp(HEARTBEAT_RATE_FAR, HEARTBEAT_RATE_NEAR, closeness)
			setPlaying(heartbeat, heartbeat.Volume > 0.01 or closeness > 0)
		end

		-- Water ambience: only during a round, louder as the water rises.
		if water then
			local target = 0
			if state:GetAttribute("RoundState") == "Running" then
				local level = state:GetAttribute("WaterLevel")
				local amount = if typeof(level) == "number" then math.clamp(level / WATER_FULL_LEVEL, 0, 1) else 0
				target = lerp(WATER_MIN_VOLUME, WATER_MAX_VOLUME, amount)
			end
			water.Volume = approach(water.Volume, target, dt)
			setPlaying(water, water.Volume > 0.01 or target > 0)
		end
	end)
end

return Audio

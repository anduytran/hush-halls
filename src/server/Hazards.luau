--!strict
-- Sprint 34: floor hazards. HallBuilder tags puddles "Puddle" and loose planks "Plank" (under Hall.Hazards).
-- Touching one makes a noise spike through NoiseService.addNoise and plays a sound at the hazard, for
-- InRound, alive players only. Each hazard cools down per player, so standing in one doesn't spam it.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local NoiseService = require(script.Parent.NoiseService)

local COOLDOWN = 1 -- seconds before the same hazard can go off again for the same player

type Kind = {
	tag: string,
	noise: number, -- 0-1 floor on the player's noise
	duration: number, -- seconds the floor lasts
	soundName: string,
	soundId: string,
	volume: number,
	pitch: number,
}

-- Built-in engine sounds, so nothing depends on a Creator Store asset.
local KINDS: { Kind } = {
	{
		tag = "Puddle",
		noise = 0.8,
		duration = 0.6,
		soundName = "Splash",
		soundId = "rbxasset://sounds/impact_water.mp3",
		volume = 0.8,
		pitch = 1,
	},
	{
		tag = "Plank",
		noise = 0.4,
		duration = 0.4,
		soundName = "Creak",
		soundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		volume = 0.7,
		pitch = 0.55,
	},
}
local SOUND_ROLLOFF_MAX = 80

local Hazards = {}

local started = false
-- When each player last set off each hazard. Inner tables have weak keys, so destroyed hazards drop out.
local lastHit: { [Player]: { [BasePart]: number } } = {}
local partConnections: { [Instance]: RBXScriptConnection } = {}

local function playerFromHit(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player or player:GetAttribute("InRound") ~= true then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return player
end

local function getSound(part: BasePart, kind: Kind): Sound
	local existing = part:FindFirstChild(kind.soundName)
	if existing and existing:IsA("Sound") then
		return existing
	end
	local sound = Instance.new("Sound")
	sound.Name = kind.soundName
	sound.SoundId = kind.soundId
	sound.Volume = kind.volume
	sound.PlaybackSpeed = kind.pitch
	sound.RollOffMaxDistance = SOUND_ROLLOFF_MAX
	sound.Parent = part
	return sound
end

local function onTouched(part: BasePart, kind: Kind, hit: BasePart)
	local player = playerFromHit(hit)
	if not player then
		return
	end
	local now = os.clock()
	local hits = lastHit[player]
	if not hits then
		hits = setmetatable({}, { __mode = "k" }) :: any
		lastHit[player] = hits
	end
	local last = hits[part]
	if last and now - last < COOLDOWN then
		return
	end
	hits[part] = now
	NoiseService.addNoise(player, kind.noise, kind.duration)
	local sound = getSound(part, kind)
	sound.TimePosition = 0
	sound:Play()
end

local function watch(instance: Instance, kind: Kind)
	if not instance:IsA("BasePart") or partConnections[instance] then
		return
	end
	local part = instance
	getSound(part, kind)
	partConnections[part] = part.Touched:Connect(function(hit)
		onTouched(part, kind, hit)
	end)
end

local function unwatch(instance: Instance)
	local connection = partConnections[instance]
	if connection then
		connection:Disconnect()
		partConnections[instance] = nil
	end
end

function Hazards.start()
	if started then
		return
	end
	started = true

	for _, kind in KINDS do
		CollectionService:GetInstanceAddedSignal(kind.tag):Connect(function(instance)
			watch(instance, kind)
		end)
		CollectionService:GetInstanceRemovedSignal(kind.tag):Connect(unwatch)
		for _, instance in CollectionService:GetTagged(kind.tag) do
			watch(instance, kind)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
	end)
end

return Hazards

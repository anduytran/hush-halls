--!strict

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local HallBuilder = require(script.Parent.Map.HallBuilder)
local Monetization = require(script.Parent.Monetization)
local Monster = require(script.Parent.Monster)
local NoiseService = require(script.Parent.NoiseService)
local RoundService = require(script.Parent.RoundService)

-- The hall is built first: Monster lives in it and RoundService plays rounds in it.
local built, buildErr = pcall(HallBuilder.build)
if not built then
	warn(`[server] couldn't build the hall: {buildErr}`)
end

-- Each start() returns straight away. One failing must not stop the rest.
local systems: { { name: string, start: () -> () } } = {
	{ name = "NoiseService", start = NoiseService.start },
	{ name = "Monster", start = Monster.start },
	{ name = "RoundService", start = RoundService.start },
}
for _, system in systems do
	local ok, err = pcall(system.start)
	if not ok then
		warn(`[server] {system.name} failed to start: {err}`)
	end
end

-- Cosmetic and coin grants only: nothing sold here touches noise, speed or the monster.
local function attachTrail(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or root:FindFirstChild("NeonTrail") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "NeonTrailTop"
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "NeonTrailBottom"
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "NeonTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(0, 255, 255))
	trail.LightEmission = 1
	trail.Lifetime = 0.6
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = root
end

local function addNameTag(character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") or head:FindFirstChild("VipTag") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "VipTag"
	tag.Size = UDim2.fromOffset(80, 24)
	tag.StudsOffset = Vector3.new(0, 2.5, 0)
	tag.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "VIP"
	label.TextColor3 = Color3.fromRGB(255, 205, 40)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = tag
	tag.Parent = head
end

-- Runs for the current character and every respawn.
local function onEachCharacter(player: Player, fn: (Model) -> ())
	if player.Character then
		task.spawn(fn, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		fn(character)
	end)
end

Monetization.onPass("NeonTrail", function(player)
	onEachCharacter(player, attachTrail)
end)

Monetization.onPass("VIP", function(player)
	player:SetAttribute("CoinMultiplier", 2)
	onEachCharacter(player, addNameTag)
end)

Monetization.onProduct("Coins100", function(player)
	-- Look up without waiting: if leaderstats isn't there yet, returning false makes Roblox retry later.
	local stats = player:FindFirstChild("leaderstats")
	local coins = if stats then stats:FindFirstChild("Coins") else nil
	if not coins or not (coins:IsA("IntValue") or coins:IsA("NumberValue")) then
		return false
	end
	coins.Value += 100
	return true
end)

print(`[server] {Config.GAME_NAME} started`)

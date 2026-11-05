--!strict

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Hazards = require(script.Parent.Hazards)
local Monetization = require(script.Parent.Monetization)
local Monster = require(script.Parent.Monster)
local NoiseService = require(script.Parent.NoiseService)
local RoundService = require(script.Parent.RoundService)

-- The hall is built first: Monster lives in it and RoundService plays rounds in it.
-- Sprint-3 fix: requiring and building are both in the pcall, so a broken HallBuilder only warns;
-- the systems below and the Monetization handlers are still set up.
local built, buildErr = pcall(function()
	require(script.Parent.Map.HallBuilder).build()
end)
if not built then
	warn(`[server] couldn't build the hall: {buildErr}`)
end

-- Each start() runs in its own thread: one that fails or waits (e.g. for a missing hall) can't hold up the rest.
-- Sprint-4 fix: a start() that errors is tried again every START_RETRY_DELAY seconds, up to START_RETRIES times.
local START_RETRY_DELAY = 5
local START_RETRIES = 5
local systems: { { name: string, start: () -> () } } = {
	{ name = "NoiseService", start = NoiseService.start },
	{ name = "Monster", start = Monster.start },
	{ name = "RoundService", start = RoundService.start },
	{ name = "Hazards", start = Hazards.start },
}
-- Sprint-5 fix: a system that has started once is never started again, and each start() also returns early
-- if it's already running (a failed RoundService.start() undoes its connections before erroring).
local startedSystems: { [string]: boolean } = {}
local function tryStart(system: { name: string, start: () -> () }, attempt: number)
	if startedSystems[system.name] then
		return
	end
	local ok, err = pcall(system.start)
	if ok then
		startedSystems[system.name] = true
		return
	end
	if attempt > START_RETRIES then
		warn(`[server] {system.name} failed to start, giving up: {err}`)
		return
	end
	warn(`[server] {system.name} failed to start (retry {attempt}/{START_RETRIES} in {START_RETRY_DELAY}s): {err}`)
	task.delay(START_RETRY_DELAY, tryStart, system, attempt + 1)
end
for _, system in systems do
	task.spawn(tryStart, system, 1)
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

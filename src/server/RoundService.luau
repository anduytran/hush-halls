--!strict
-- Round loop: Lobby (15s) -> Running (up to 120s) -> Ended (5s) -> Lobby.
-- Players who touch Hall.Exit while Running escape: +10 Coins and a teleport to the lobby platform above Start.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HallBuilder = require(script.Parent.Map.HallBuilder)

local LOBBY_TIME = 15
local RUN_TIME = 120
local ENDED_TIME = 5
local ESCAPE_REWARD = 10
local PLATFORM_HEIGHT = 30
local TICK = 0.25

local RoundService = {}

-- Players taking part in the current round, and how their round went.
local participants: { [Player]: boolean } = {}
local dead: { [Player]: boolean } = {}

local function setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = 0
	coins.Parent = leaderstats
	leaderstats.Parent = player
end

local function addCoins(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins and coins:IsA("IntValue") then
		coins.Value += amount
	end
end

local function makePlatform(hall: Instance, start: BasePart): BasePart
	local platform = Instance.new("Part")
	platform.Name = "LobbyPlatform"
	platform.Anchored = true
	platform.Size = Vector3.new(40, 1, 40)
	platform.CFrame = CFrame.new(start.Position + Vector3.new(0, PLATFORM_HEIGHT, 0))
	platform.Material = Enum.Material.SmoothPlastic
	platform.Color = Color3.fromRGB(90, 90, 110)
	platform.TopSurface = Enum.SurfaceType.Smooth
	platform.Parent = hall
	return platform
end

local function roundOver(): boolean
	for player in participants do
		if player.Parent ~= Players then
			continue
		end
		if not player:GetAttribute("Escaped") and not dead[player] then
			return false
		end
	end
	return true
end

function RoundService.start()
	local State = ReplicatedStorage:WaitForChild("State")

	HallBuilder.build()
	local hall = workspace:WaitForChild("Hall")
	local start = hall:WaitForChild("Start") :: BasePart
	local exit = hall:WaitForChild("Exit") :: BasePart
	local platform = makePlatform(hall, start)

	local function sendToPlatform(player: Player)
		local character = player.Character
		if character then
			local offset = Vector3.new(math.random(-12, 12), 4, math.random(-12, 12))
			character:PivotTo(CFrame.new(platform.Position + offset))
		end
	end

	local function spawnAtStart(player: Player)
		player:LoadCharacter()
		local character = player.Character
		if not character or player.Parent ~= Players then
			return
		end
		character:PivotTo(start.CFrame + Vector3.new(math.random(-3, 3), 4, math.random(-3, 3)))
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				if participants[player] and State:GetAttribute("RoundState") == "Running" then
					dead[player] = true
				end
			end)
		end
	end

	for _, player in Players:GetPlayers() do
		setupLeaderstats(player)
	end
	Players.PlayerAdded:Connect(setupLeaderstats)
	Players.PlayerRemoving:Connect(function(player)
		participants[player] = nil
		dead[player] = nil
	end)

	exit.Touched:Connect(function(hit)
		if State:GetAttribute("RoundState") ~= "Running" then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character then
			return
		end
		local player = Players:GetPlayerFromCharacter(character)
		if not player or not participants[player] or dead[player] or player:GetAttribute("Escaped") then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		player:SetAttribute("Escaped", true)
		addCoins(player, ESCAPE_REWARD)
		sendToPlatform(player)
	end)

	task.spawn(function()
		while true do
			-- Lobby: wait for at least one player, then count down.
			State:SetAttribute("RoundState", "Lobby")
			local left = LOBBY_TIME
			while left > 0 do
				State:SetAttribute("TimeLeft", left)
				task.wait(1)
				left = if #Players:GetPlayers() > 0 then left - 1 else LOBBY_TIME
			end
			State:SetAttribute("TimeLeft", 0)

			-- Running
			table.clear(participants)
			table.clear(dead)
			for _, player in Players:GetPlayers() do
				participants[player] = true
				player:SetAttribute("Escaped", false)
			end
			for player in participants do
				task.spawn(spawnAtStart, player)
			end
			State:SetAttribute("RoundState", "Running")

			local endTime = os.clock() + RUN_TIME
			State:SetAttribute("TimeLeft", RUN_TIME)
			while os.clock() < endTime do
				task.wait(TICK)
				State:SetAttribute("TimeLeft", math.max(0, math.ceil(endTime - os.clock())))
				if roundOver() then
					break
				end
			end

			-- Ended
			State:SetAttribute("RoundState", "Ended")
			for left2 = ENDED_TIME, 1, -1 do
				State:SetAttribute("TimeLeft", left2)
				task.wait(1)
			end
			table.clear(participants)
			table.clear(dead)
		end
	end)
end

return RoundService

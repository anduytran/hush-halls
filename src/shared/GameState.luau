--!strict
-- Shared round state (attributes on ReplicatedStorage.State) and remotes.
-- The server creates everything on first require; clients wait for it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFAULTS: { [string]: any } = {
	WaterLevel = 0,
	Noise = 0,
	RoundState = "Lobby",
	TimeLeft = 0,
}

local REMOTE_EVENTS = { "Sprint", "Move" }

local State: Folder
local Remotes: Folder

if RunService:IsServer() then
	local existingState = ReplicatedStorage:FindFirstChild("State")
	if existingState and existingState:IsA("Folder") then
		State = existingState
	else
		State = Instance.new("Folder")
		State.Name = "State"
		for name, value in DEFAULTS do
			State:SetAttribute(name, value)
		end
		State.Parent = ReplicatedStorage
	end

	local existingRemotes = ReplicatedStorage:FindFirstChild("Remotes")
	if existingRemotes and existingRemotes:IsA("Folder") then
		Remotes = existingRemotes
	else
		Remotes = Instance.new("Folder")
		Remotes.Name = "Remotes"
		Remotes.Parent = ReplicatedStorage
	end

	for _, name in REMOTE_EVENTS do
		if not Remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = Remotes
		end
	end
else
	State = ReplicatedStorage:WaitForChild("State") :: Folder
	Remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	for _, name in REMOTE_EVENTS do
		Remotes:WaitForChild(name)
	end
end

return {
	State = State,
	Remotes = Remotes,
}

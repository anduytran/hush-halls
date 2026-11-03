--!strict
-- Studio only, for specs: stand-in players a RoundService round treats like real ones (a Studio play-test has
-- just one real player). Game code never requires this module. attach() errors outside Studio, and nothing
-- else here does anything until it has run, so no stand-in can reach a live game.
-- attach(roundService) swaps RoundService's player source (RoundService._test.setPlayerSource) for one that
-- lists the real players plus the stand-ins; detach() removes the stand-ins and puts the Players service back.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- The members RoundService (and the specs) read from a player. A stand-in has exactly these.
export type FakePlayer = {
	Name: string,
	Parent: Instance?,
	Character: Model?,
	CharacterAdded: RBXScriptSignal,
	SetAttribute: (self: FakePlayer, attribute: string, value: any) -> (),
	GetAttribute: (self: FakePlayer, attribute: string) -> any,
	GetAttributeChangedSignal: (self: FakePlayer, attribute: string) -> RBXScriptSignal,
	FindFirstChild: (self: FakePlayer, name: string) -> Instance?,
	LoadCharacter: (self: FakePlayer) -> (),
}

-- Matches RoundService.PlayerSource (not required here, so a spec's own RoundService instance is the one used).
type PlayerSource = {
	getPlayers: () -> { Player },
	playerFromCharacter: (character: Model) -> Player?,
	connectPlayers: (onAdded: (Player) -> (), onRemoving: (Player) -> ()) -> { RBXScriptConnection },
	connectExit: (exit: BasePart, onTouched: (BasePart) -> ()) -> RBXScriptConnection,
}
type RoundServiceTest = { _test: { setPlayerSource: (PlayerSource?) -> () } }

local RoundTestPlayers = {}

-- The RoundService attach() wired up, or nil.
local attached: RoundServiceTest? = nil
-- Each stand-in, with the Folder that holds its attributes, leaderstats and CharacterAdded event.
local fakes: { [FakePlayer]: Folder } = {}
-- What RoundService's start() handed the source, with the connection that says whether it is still live
-- (stop() disconnects it). Only called while that connection is connected.
local joined: { connection: RBXScriptConnection, onAdded: (Player) -> (), onRemoving: (Player) -> () }? = nil
local exitHandler: { connection: RBXScriptConnection, onTouched: (BasePart) -> () }? = nil
-- Sprint 23: how many more LoadCharacter calls error for each stand-in, and which stand-ins' LoadCharacter is held
-- (it yields until released or the stand-in is removed).
local failsLeft: { [FakePlayer]: number } = {}
local held: { [FakePlayer]: boolean } = {}
-- Sprint 23: set by _test.pretendLiveServer, so a Studio spec can check that attach() refuses outside Studio. It can
-- only make the check stricter: a server that isn't Studio is refused whatever this is.
local pretendLive = false

local function inStudio(): boolean
	return RunService:IsStudio() and not pretendLive
end

-- RoundService is typed on Player. A stand-in only gets read through the FakePlayer members above, so it is
-- handed over as a Player here, in this one place.
local function asPlayer(fake: FakePlayer): Player
	return (fake :: any) :: Player
end

local source: PlayerSource = {
	getPlayers = function()
		local list = Players:GetPlayers()
		for fake in fakes do
			table.insert(list, asPlayer(fake))
		end
		return list
	end,
	playerFromCharacter = function(character)
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			return player
		end
		for fake in fakes do
			if fake.Character == character then
				return asPlayer(fake)
			end
		end
		return nil
	end,
	connectPlayers = function(onAdded, onRemoving)
		local added = Players.PlayerAdded:Connect(onAdded)
		joined = { connection = added, onAdded = onAdded, onRemoving = onRemoving }
		return { added, Players.PlayerRemoving:Connect(onRemoving) }
	end,
	connectExit = function(exit, onTouched)
		local connection = exit.Touched:Connect(onTouched)
		exitHandler = { connection = connection, onTouched = onTouched }
		return connection
	end,
}

-- Studio only (errors elsewhere). Wires the stand-ins into this RoundService. Call it while the service is
-- stopped: start() connects through the source it finds. Calling it again just re-wires.
function RoundTestPlayers.attach(roundService: RoundServiceTest)
	if not inStudio() then
		error("RoundTestPlayers only works in Studio", 2)
	end
	attached = roundService
	roundService._test.setPlayerSource(source)
end

-- Removes every stand-in and gives the attached RoundService back the Players service. Safe to call any time.
function RoundTestPlayers.detach()
	RoundTestPlayers.removeAll()
	if attached then
		attached._test.setPlayerSource(nil)
		attached = nil
	end
	joined, exitHandler = nil, nil
end

-- Adds a stand-in that joins as PlayerAdded would (if start() has run) and gets a character at once, as Roblox's
-- auto-spawn would. It starts with leaderstats.Coins = 0. Its character is an anchored HumanoidRootPart and a
-- Humanoid; LoadCharacter replaces it (see failLoadCharacter and holdLoadCharacter). Errors unless attach() has run.
function RoundTestPlayers.add(name: string): FakePlayer
	if not attached then
		error("RoundTestPlayers.add: call attach() first", 2)
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	local characterAdded = Instance.new("BindableEvent")
	characterAdded.Parent = folder
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	leaderstats.Parent = folder

	local fake: FakePlayer = {
		Name = name,
		Parent = Players,
		Character = nil,
		CharacterAdded = characterAdded.Event,
		SetAttribute = function(_self, attribute, value)
			folder:SetAttribute(attribute, value)
		end,
		GetAttribute = function(_self, attribute)
			return folder:GetAttribute(attribute)
		end,
		GetAttributeChangedSignal = function(_self, attribute)
			return folder:GetAttributeChangedSignal(attribute)
		end,
		FindFirstChild = function(_self, childName)
			return folder:FindFirstChild(childName)
		end,
		LoadCharacter = function(self)
			local fails = failsLeft[self]
			if fails then
				failsLeft[self] = if fails > 1 then fails - 1 else nil
				error(`LoadCharacter failed for {name} (test)`)
			end
			-- A held load keeps the old character until it is released; a stand-in removed meanwhile gets none.
			while held[self] and fakes[self] do
				RunService.Heartbeat:Wait()
			end
			if not fakes[self] then
				return
			end
			if self.Character then
				self.Character:Destroy()
			end
			local character = Instance.new("Model")
			character.Name = name
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Anchored = true
			root.CanCollide = false
			root.Size = Vector3.new(2, 2, 1)
			root.Parent = character
			character.PrimaryPart = root
			local humanoid = Instance.new("Humanoid")
			humanoid.RequiresNeck = false
			humanoid.Parent = character
			character.Parent = workspace
			self.Character = character
			characterAdded:Fire(character)
		end,
	}
	fakes[fake] = folder
	if joined and joined.connection.Connected then
		joined.onAdded(asPlayer(fake))
	end
	fake:LoadCharacter()
	return fake
end

-- Takes every stand-in out, as PlayerRemoving would, and destroys its character.
function RoundTestPlayers.removeAll()
	for fake, folder in fakes do
		fakes[fake] = nil
		failsLeft[fake] = nil
		held[fake] = nil
		if joined and joined.connection.Connected then
			joined.onRemoving(asPlayer(fake))
		end
		if fake.Character then
			fake.Character:Destroy()
			fake.Character = nil
		end
		fake.Parent = nil
		folder:Destroy()
	end
end

-- Runs the attached RoundService's Exit.Touched handler for this part, as if it touched Hall.Exit, without
-- physics. Returns false (and does nothing) if start() hasn't connected the exit, or stop() has dropped it.
function RoundTestPlayers.touchExit(hit: BasePart): boolean
	if not (exitHandler and exitHandler.connection.Connected) then
		return false
	end
	exitHandler.onTouched(hit)
	return true
end

-- Sprint 23: the stand-in's next `times` LoadCharacter calls error (as a real one can, e.g. while the player leaves),
-- leaving its character as it was. 0 turns it off.
function RoundTestPlayers.failLoadCharacter(fake: FakePlayer, times: number)
	failsLeft[fake] = if times > 0 then times else nil
end

-- Sprint 23: while held, the stand-in's LoadCharacter yields (keeping its old character), as a slow spawn would.
-- Releasing it lets any waiting load finish and make the new character.
function RoundTestPlayers.holdLoadCharacter(fake: FakePlayer, hold: boolean)
	held[fake] = if hold then true else nil
end

-- Sprint 23: kills the stand-in's character (Humanoid.Health = 0), as the monster would. False if it has none.
function RoundTestPlayers.kill(fake: FakePlayer): boolean
	local character = fake.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	humanoid.Health = 0
	return true
end

RoundTestPlayers._test = {
	-- Sprint 23: while on, attach() acts as on a live server and refuses. It can't make a live server pass.
	pretendLiveServer = function(on: boolean)
		pretendLive = on
	end,
}

return RoundTestPlayers

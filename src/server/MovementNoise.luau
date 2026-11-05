--!strict
-- Sprint 39: movement tech is loud. The client fires Remotes.Move with an action name each time it dashes,
-- dash jumps, slides, double jumps or wall jumps (see src/client/Movement.luau). The server checks that the
-- action is known, only listens to InRound players who are alive, allows at most RATE_LIMIT events per second
-- per player (a token bucket holding RATE_LIMIT), and then raises their noise through NoiseService.addNoise.
-- The movement itself is client physics on a client-owned character; skipping the remote only skips the extra
-- noise floor, the server's own speed sampling (NoiseService) still hears fast movement.
-- Each accepted event also sets MoveAction (the action) and MoveActionAt (workspace:GetServerTimeNow()) on the
-- player's character, so other clients can animate the move. Ignored events leave both alone.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameState = require(ReplicatedStorage.Shared.GameState)
local NoiseService = require(script.Parent.NoiseService)

local RATE_LIMIT = 5 -- Move events per second per player

-- Noise amount (0-1) and duration (s) for each action, from design-vault/Mechanics/Movement Tech.md.
local NOISE: { [string]: { amount: number, duration: number } } = {
	Dash = { amount = 1.0, duration = 0.5 },
	DashJump = { amount = 1.0, duration = 0.5 },
	Slide = { amount = 0.6, duration = 0.4 },
	DoubleJump = { amount = 0.6, duration = 0.4 },
	WallJump = { amount = 0.6, duration = 0.4 },
}

local MovementNoise = {}

local started = false
local budgets: { [Player]: { tokens: number, last: number } } = {}
-- Studio-only test hooks replace these (see MovementNoise._test).
local clock: () -> number = os.clock
local noiseSink: ((player: Player, amount: number, duration: number) -> ())? = nil

local function allowEvent(player: Player): boolean
	local now = clock()
	local budget = budgets[player]
	if not budget then
		budget = { tokens = RATE_LIMIT, last = now }
		budgets[player] = budget
	end
	budget.tokens = math.min(RATE_LIMIT, budget.tokens + (now - budget.last) * RATE_LIMIT)
	budget.last = now
	if budget.tokens < 1 then
		return false
	end
	budget.tokens -= 1
	return true
end

local function isAliveInRound(player: Player): boolean
	if player:GetAttribute("InRound") ~= true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- The Move remote handler. Unknown actions and events from players who aren't InRound and alive are dropped
-- before the rate limit, so they don't use up the player's budget.
local function onMove(player: Player, action: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local noise = NOISE[action]
	if not noise then
		return
	end
	if not isAliveInRound(player) then
		return
	end
	if not allowEvent(player) then
		return
	end
	-- Accepted: tell other clients which move this was and when, so they can animate it.
	-- isAliveInRound has just checked that the character exists.
	local character = player.Character :: Model
	character:SetAttribute("MoveAction", action)
	character:SetAttribute("MoveActionAt", workspace:GetServerTimeNow())
	local sink = noiseSink
	if sink then
		sink(player, noise.amount, noise.duration)
	else
		NoiseService.addNoise(player, noise.amount, noise.duration)
	end
end

function MovementNoise.start()
	if started then
		return
	end
	started = true

	local moveRemote = GameState.Remotes:WaitForChild("Move") :: RemoteEvent
	moveRemote.OnServerEvent:Connect(onMove)

	Players.PlayerRemoving:Connect(function(player)
		budgets[player] = nil
	end)
end

-- TEST-ONLY hooks, like NoiseService._test: the table exists only in Studio, so it is not part of the API.
if RunService:IsStudio() then
	MovementNoise._test = {
		-- Runs the same handler the Move remote is connected to.
		handleMove = onMove,
		-- Replaces NoiseService.addNoise while set (nil puts it back); the remote handler uses it too.
		setNoiseSink = function(sink: ((player: Player, amount: number, duration: number) -> ())?)
			noiseSink = sink
		end,
		-- Replaces os.clock for the rate limit (nil puts it back).
		setClock = function(fn: (() -> number)?)
			clock = fn or os.clock
		end,
		resetBudgets = function()
			table.clear(budgets)
		end,
		RATE_LIMIT = RATE_LIMIT,
		NOISE = NOISE,
	}
end

return MovementNoise

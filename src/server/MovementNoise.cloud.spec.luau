-- Engine tests for MovementNoise.luau (the Move remote: known action, at most 5/s, InRound and alive).
-- They drive the real handler through MovementNoise._test.handleMove with fake players, a frozen clock and a
-- noise sink that records calls instead of touching NoiseService. The hooks only exist in Studio; outside
-- Studio every test warns and skips. Each test puts the sink, clock and budgets back, even when it fails.
local MovementNoise = require("./MovementNoise")

type Call = { player: any, amount: number, duration: number }

-- A stand-in Player: attributes plus a Character with a Humanoid at the given health.
local function fakePlayer(inRound: boolean, health: number): any
	local attributes: { [string]: any } = { InRound = inRound }
	local character = Instance.new("Model")
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	humanoid.Health = health
	local player = {
		Character = character,
		GetAttribute = function(_self, name: string)
			return attributes[name]
		end,
		SetAttribute = function(_self, name: string, value: any)
			attributes[name] = value
		end,
	}
	return player
end

-- Runs body(test, calls, setTime) with a recording sink and a manual clock, then restores everything.
local function withHooks(name: string, body: (test: any, calls: { Call }, setTime: (number) -> ()) -> ()): () -> ()
	return function()
		local test = (MovementNoise :: any)._test
		if not test then
			warn(`[MovementNoise.spec] skipped "{name}": MovementNoise._test only exists in Studio`)
			return
		end
		local calls: { Call } = {}
		local now = 1000
		test.resetBudgets()
		test.setClock(function()
			return now
		end)
		test.setNoiseSink(function(player, amount, duration)
			table.insert(calls, { player = player, amount = amount, duration = duration })
		end)
		local ok, err = pcall(body, test, calls, function(t: number)
			now = t
		end)
		test.setNoiseSink(nil)
		test.setClock(nil)
		test.resetBudgets()
		if not ok then
			error(err, 0)
		end
	end
end

return {
	["12 dashes in one frame give 5 noise calls, and 5 more a second later"] = withHooks(
		"rate limit",
		function(test, calls, setTime)
			assert(test.RATE_LIMIT == 5, `RATE_LIMIT is {test.RATE_LIMIT}, expected 5`)
			local player = fakePlayer(true, 100)
			for _ = 1, 12 do
				test.handleMove(player, "Dash")
			end
			assert(#calls == 5, `12 Dash events in one frame gave {#calls} noise calls, expected 5`)
			setTime(1001)
			for _ = 1, 12 do
				test.handleMove(player, "Dash")
			end
			assert(#calls == 10, `after 1 s, 12 more Dash events gave {#calls - 5} calls, expected 5`)
		end
	),

	["each player has their own budget"] = withHooks("per player", function(test, calls)
		local a = fakePlayer(true, 100)
		local b = fakePlayer(true, 100)
		for _ = 1, 8 do
			test.handleMove(a, "Slide")
			test.handleMove(b, "Slide")
		end
		assert(#calls == 10, `two players x 8 events gave {#calls} calls, expected 10 (5 each)`)
	end),

	["players who aren't InRound are ignored and keep their budget"] = withHooks("not InRound", function(test, calls)
		local player = fakePlayer(false, 100)
		for _ = 1, 12 do
			test.handleMove(player, "Dash")
		end
		assert(#calls == 0, `a player not InRound got {#calls} noise calls, expected 0`)
		player:SetAttribute("InRound", true)
		for _ = 1, 12 do
			test.handleMove(player, "Dash")
		end
		assert(#calls == 5, `after joining the round, got {#calls} calls, expected the full 5`)
	end),

	["dead players and players without a character are ignored"] = withHooks("dead", function(test, calls)
		local dead = fakePlayer(true, 0)
		test.handleMove(dead, "Dash")
		local noCharacter = fakePlayer(true, 100)
		noCharacter.Character = nil
		test.handleMove(noCharacter, "Dash")
		assert(#calls == 0, `dead or character-less players got {#calls} noise calls, expected 0`)
	end),

	["unknown and non-string actions are ignored"] = withHooks("bad action", function(test, calls)
		local player = fakePlayer(true, 100)
		for _, action in { "Teleport", "", "dash", 1, true, {} :: any } do
			test.handleMove(player, action)
		end
		test.handleMove(player, nil)
		assert(#calls == 0, `bad actions gave {#calls} noise calls, expected 0`)
		-- Ignored events don't use up the budget.
		for _ = 1, 5 do
			test.handleMove(player, "WallJump")
		end
		assert(#calls == 5, `after bad actions, 5 good ones gave {#calls} calls, expected 5`)
	end),

	["accepted events set MoveAction and MoveActionAt on the character"] = withHooks(
		"move attributes",
		function(test, _calls, setTime)
			local player = fakePlayer(true, 100)
			local character = player.Character
			local before = workspace:GetServerTimeNow()
			test.handleMove(player, "Slide")
			local after = workspace:GetServerTimeNow()
			assert(
				character:GetAttribute("MoveAction") == "Slide",
				`MoveAction is {character:GetAttribute("MoveAction")}, expected Slide`
			)
			local at = character:GetAttribute("MoveActionAt")
			assert(typeof(at) == "number", `MoveActionAt is {typeof(at)}, expected a number`)
			assert(at >= before and at <= after, `MoveActionAt {at} is outside [{before}, {after}]`)
			setTime(1001)
			test.handleMove(player, "WallJump")
			assert(
				character:GetAttribute("MoveAction") == "WallJump",
				`a second accepted event left MoveAction at {character:GetAttribute("MoveAction")}`
			)
			assert(character:GetAttribute("MoveActionAt") >= at, "MoveActionAt went backwards on a later event")
		end
	),

	["ignored events don't set MoveAction or MoveActionAt"] = withHooks("ignored attributes", function(test)
		local function unset(player: any, why: string)
			local character = player.Character
			assert(
				character:GetAttribute("MoveAction") == nil,
				`{why}: MoveAction was set to {character:GetAttribute("MoveAction")}`
			)
			assert(character:GetAttribute("MoveActionAt") == nil, `{why}: MoveActionAt was set`)
		end

		local bad = fakePlayer(true, 100)
		for _, action in { "Teleport", "", "dash", 1, true, {} :: any } do
			test.handleMove(bad, action)
		end
		test.handleMove(bad, nil)
		unset(bad, "unknown action")

		local outside = fakePlayer(false, 100)
		test.handleMove(outside, "Dash")
		unset(outside, "not InRound")

		local dead = fakePlayer(true, 0)
		test.handleMove(dead, "Dash")
		unset(dead, "dead")

		-- Over the budget: the 6th event in one frame is dropped and must not overwrite the 5th.
		local spammer = fakePlayer(true, 100)
		for _ = 1, 5 do
			test.handleMove(spammer, "Dash")
		end
		local character = spammer.Character
		local at = character:GetAttribute("MoveActionAt")
		character:SetAttribute("MoveActionAt", -1) -- a marker the dropped event would overwrite
		test.handleMove(spammer, "Slide")
		assert(
			character:GetAttribute("MoveAction") == "Dash",
			`a rate-limited Slide set MoveAction to {character:GetAttribute("MoveAction")}`
		)
		assert(character:GetAttribute("MoveActionAt") == -1, "a rate-limited event set MoveActionAt")
		assert(typeof(at) == "number", "the 5th accepted Dash did not set MoveActionAt")
	end),

	["noise amounts and durations match the design"] = withHooks("amounts", function(test, calls, setTime)
		local expected = {
			Dash = { 1.0, 0.5 },
			DashJump = { 1.0, 0.5 },
			Slide = { 0.6, 0.4 },
			DoubleJump = { 0.6, 0.4 },
			WallJump = { 0.6, 0.4 },
		}
		local player = fakePlayer(true, 100)
		local t = 1000
		for action, want in expected do
			t += 1 -- a fresh second each, so the rate limit never hides an action
			setTime(t)
			local before = #calls
			test.handleMove(player, action)
			assert(#calls == before + 1, `{action} gave no noise call`)
			local call = calls[#calls]
			assert(call.player == player, `{action} raised noise for the wrong player`)
			assert(
				math.abs(call.amount - want[1]) < 1e-6 and math.abs(call.duration - want[2]) < 1e-6,
				`{action} added {call.amount} for {call.duration} s, expected {want[1]} for {want[2]} s`
			)
		end
	end),
}

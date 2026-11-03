-- Engine tests for Monetization.luau's receipt handling (sprint-4 fix). Run in a real Roblox server on the
-- test place. Requiring Monetization hooks MarketplaceService.ProcessReceipt, which is fine here.
-- Every test uses its own fake DataStore and counting grant, so no state is shared between tests.
-- The fake store runs the UpdateAsync callback the way Roblox does: it can run it several times (a conflicting
-- write re-runs it and only the last result is written), and a test can change storage between runs.
local Monetization = require("./Monetization")
local processReceipt = Monetization._processReceipt
local Decision = Enum.ProductPurchaseDecision

local buyer = { Name = "Tester", UserId = 1 }

local function receipt(purchaseId: string)
	return { PlayerId = 1, PurchaseId = purchaseId, ProductId = 0 }
end

local function keyOf(r)
	return `{r.PlayerId}_{r.PurchaseId}`
end

-- A stand-in DataStore. Fields:
--   data            stored values by key
--   calls           how many UpdateAsync calls were made (call 1 is the reserve, call 2 the mark-done)
--   runs            how many times an UpdateAsync callback ran in total
--   conflicts       extra callback runs before the final result is written (simulated conflicting writes)
--   beforeRun(n)    optional hook, run before callback run n, to change storage like another server would
--   failCalls[n]    makes UpdateAsync call n throw
--   failRemove      makes RemoveAsync throw
--   removes         how many RemoveAsync calls were made
--   inUpdate        true while an UpdateAsync callback is running
--   grantsDuringUpdate  grants that ran inside an UpdateAsync callback (must stay 0)
local function newStore()
	local store = {
		data = {},
		calls = 0,
		runs = 0,
		conflicts = 0,
		beforeRun = nil,
		failCalls = {},
		failRemove = false,
		removes = 0,
		inUpdate = false,
		grantsDuringUpdate = 0,
	}
	function store:UpdateAsync(key, transform)
		self.calls += 1
		if self.failCalls[self.calls] then
			error("simulated UpdateAsync failure")
		end
		local result = nil
		self.inUpdate = true
		for attempt = 1, self.conflicts + 1 do
			self.runs += 1
			if self.beforeRun then
				self.beforeRun(attempt, self)
			end
			result = transform(self.data[key])
		end
		self.inUpdate = false
		if result ~= nil then
			self.data[key] = result
		end
		return self.data[key]
	end
	function store:RemoveAsync(key)
		self.removes += 1
		if self.failRemove then
			error("simulated RemoveAsync failure")
		end
		self.data[key] = nil
	end
	return store
end

-- A grant that counts its calls. `behavior` is "true" (default), "false", or "error".
-- Records what the store held for the key while the grant ran (it should be the pending marker).
local function countingGrant(store, key, behavior)
	local counter = { calls = 0, statusDuringGrant = nil }
	local fn = function(_player)
		counter.calls += 1
		if store.inUpdate then
			store.grantsDuringUpdate += 1
		end
		local held = store.data[key]
		counter.statusDuringGrant = if type(held) == "table" then held.status else held
		if behavior == "false" then
			return false
		elseif behavior == "error" then
			error("handler exploded")
		end
		return true
	end
	return counter, fn
end

local function assertDecision(actual, expected, label)
	assert(actual == expected, `{label}: expected {tostring(expected)}, got {tostring(actual)}`)
end

local tests = {
	["a re-run UpdateAsync callback never grants twice"] = function()
		local store = newStore()
		local r = receipt("rerun")
		local key = keyOf(r)
		store.conflicts = 2 -- the callback runs three times before its result is written
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.PurchaseGranted, "re-run receipt")
		assert(store.runs >= 3, `expected the callback to re-run, ran {store.runs} times`)
		assert(counter.calls == 1, `expected exactly 1 grant, got {counter.calls}`)
		assert(store.grantsDuringUpdate == 0, "a grant ran inside an UpdateAsync callback")
		assert(store.data[key].status == "done", "receipt should end up done")
	end,

	["a re-run that sees another server's fresh pending marker does not grant"] = function()
		local store = newStore()
		local r = receipt("otherserver")
		local key = keyOf(r)
		store.conflicts = 1
		store.beforeRun = function(attempt, s)
			if attempt == 2 then
				s.data[key] = { status = "pending", at = os.time() }
			end
		end
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "another server is granting")
		assert(counter.calls == 0, `expected no grant, got {counter.calls}`)
	end,

	["a receipt already marked done is granted with no second grant"] = function()
		local store = newStore()
		local r = receipt("done")
		local key = keyOf(r)
		store.data[key] = { status = "done", at = os.time() }
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.PurchaseGranted, "already done")
		assert(counter.calls == 0, `a done receipt must not be granted again, granted {counter.calls} times`)
	end,

	["a legacy true record counts as done"] = function()
		local store = newStore()
		local r = receipt("legacy")
		local key = keyOf(r)
		store.data[key] = true
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.PurchaseGranted, "legacy true")
		assert(counter.calls == 0, `a legacy receipt must not be granted again, granted {counter.calls} times`)
	end,

	["a fresh pending marker means busy: NotProcessedYet and no grant"] = function()
		local store = newStore()
		local r = receipt("busy")
		local key = keyOf(r)
		store.data[key] = { status = "pending", at = os.time() }
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "fresh pending")
		assert(counter.calls == 0, `a busy receipt must not be granted, granted {counter.calls} times`)
	end,

	["a stale pending marker is taken over and granted"] = function()
		local store = newStore()
		local r = receipt("stale")
		local key = keyOf(r)
		-- 700 s old, past PENDING_TIMEOUT (600 s, sprint-6 fix), so the attempt that wrote it died mid-grant.
		store.data[key] = { status = "pending", at = os.time() - 700 }
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.PurchaseGranted, "stale pending")
		assert(counter.calls == 1, `a stale marker must grant once, granted {counter.calls} times`)
		assert(store.data[key].status == "done", "receipt should be marked done after the takeover")
	end,

	-- Sprint-6 fix: the stale-takeover window is 600 s, so a marker a few minutes old is still busy.
	["the stale-takeover window is 600 s"] = function()
		assert(
			Monetization._PENDING_TIMEOUT == 600,
			`PENDING_TIMEOUT should be 600, got {tostring(Monetization._PENDING_TIMEOUT)}`
		)
	end,

	["a 200 s old pending marker is still busy: NotProcessedYet and no grant"] = function()
		local store = newStore()
		local r = receipt("busy200")
		local key = keyOf(r)
		store.data[key] = { status = "pending", at = os.time() - 200, token = "other" }
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "200 s old pending")
		assert(counter.calls == 0, `a 200 s old marker must not be taken over, granted {counter.calls} times`)
		assert(store.data[key].token == "other", "the other attempt's marker must be left untouched")
	end,

	["a marker just inside the window is busy, one just past it is taken over"] = function()
		local inside, past = newStore(), newStore()
		local r = receipt("edge")
		local key = keyOf(r)
		-- 10 s either side of 600, so a clock tick during the test can't flip the result.
		inside.data[key] = { status = "pending", at = os.time() - 590, token = "other" }
		past.data[key] = { status = "pending", at = os.time() - 610, token = "dead" }
		local insideCounter, insideGrant = countingGrant(inside, key)
		local pastCounter, pastGrant = countingGrant(past, key)
		assertDecision(processReceipt(r, inside, insideGrant, buyer), Decision.NotProcessedYet, "590 s old")
		assertDecision(processReceipt(r, past, pastGrant, buyer), Decision.PurchaseGranted, "610 s old")
		assert(insideCounter.calls == 0, `590 s old marker granted {insideCounter.calls} times`)
		assert(pastCounter.calls == 1, `610 s old marker should grant once, granted {pastCounter.calls} times`)
	end,

	-- Sprint-6 fix: the grant runs synchronously. A handler that yields is stopped there and counts as failed.
	["the grant runs synchronously, right after the reserve, with no yield in between"] = function()
		local store = newStore()
		local r = receipt("sync")
		local callsAtGrant = nil
		local function grant(_player)
			callsAtGrant = store.calls
			return true
		end
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "sync grant")
		assert(callsAtGrant == 1, `the grant must run right after the reserve, saw {tostring(callsAtGrant)} calls`)
	end,

	["a handler that yields is stopped, never resumes, and returns NotProcessedYet"] = function()
		local store = newStore()
		local r = receipt("yielder")
		local key = keyOf(r)
		local reachedAfterYield = false
		local function grant(_player)
			coroutine.yield()
			reachedAfterYield = true
			return true
		end
		local ok, decision = pcall(processReceipt, r, store, grant, buyer)
		assert(ok, `processReceipt must not throw when the handler yields: {tostring(decision)}`)
		assertDecision(decision, Decision.NotProcessedYet, "yielding handler")
		task.wait(0.1)
		assert(not reachedAfterYield, "a yielding handler must not run past its yield")
		assert(store.data[key] == nil, "the marker should be cleared so Roblox's retry can grant")
	end,

	["the token is lost to another attempt during the reserve: NotProcessedYet and no grant"] = function()
		local store = newStore()
		local r = receipt("lost")
		local key = keyOf(r)
		-- The reserve's write is overwritten by another attempt before UpdateAsync returns its stored value.
		local realUpdate = store.UpdateAsync
		function store:UpdateAsync(k, transform)
			local result = realUpdate(self, k, transform)
			if self.calls == 1 then
				self.data[k] = { status = "pending", at = os.time(), token = "other" }
				return self.data[k]
			end
			return result
		end
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "token lost")
		assert(counter.calls == 0, `nothing may be granted once the token is lost, granted {counter.calls} times`)
		assert(store.data[key].token == "other", "the other attempt's marker must be left untouched")
	end,

	["a stale takeover during our grant returns NotProcessedYet, grants once, and leaves the other marker alone"] = function()
		local store = newStore()
		local r = receipt("takeover")
		local key = keyOf(r)
		-- Our attempt reserves over this stale marker. While our grant runs, another attempt takes the receipt over.
		store.data[key] = { status = "pending", at = os.time() - 700, token = "dead" }
		local calls = 0
		local function grant(_player)
			calls += 1
			if calls == 1 then
				store.data[key] = { status = "pending", at = os.time(), token = "other" }
			end
			return true
		end
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "taken over during our grant")
		assert(calls == 1, `expected exactly 1 grant, got {calls}`)
		assert(store.data[key].token == "other", "the other attempt's marker must be left untouched")
		assert(store.data[key].status == "pending", "the other attempt's marker must still be pending")
	end,

	["a redelivery after a takeover is granted with no extra grant once the other attempt marks done"] = function()
		local store = newStore()
		local r = receipt("takeover-redeliver")
		local key = keyOf(r)
		store.data[key] = { status = "pending", at = os.time() - 700, token = "dead" }
		local calls = 0
		local function grant(_player)
			calls += 1
			if calls == 1 then
				store.data[key] = { status = "pending", at = os.time(), token = "other" }
			end
			return true
		end
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "first attempt")
		-- Simulates the other attempt finishing: it writes its own done marker. Its grant is not modelled here.
		store.data[key] = { status = "done", at = os.time(), token = "other" }
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "redelivery")
		assert(calls == 1, `expected 1 grant across both deliveries, got {calls}`)
	end,

	["the stored marker during our grant carries a non-empty token string"] = function()
		local store = newStore()
		local r = receipt("tokencheck")
		local key = keyOf(r)
		local seen = nil
		local function grant(_player)
			local held = store.data[key]
			seen = if type(held) == "table" then held.token else nil
			return true
		end
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "token check")
		assert(type(seen) == "string", `expected a string token during the grant, got {tostring(seen)}`)
		assert(#seen > 0, "the token must not be empty")
	end,

	["the receipt is reserved as pending before the handler runs"] = function()
		local store = newStore()
		local r = receipt("reserved")
		local key = keyOf(r)
		local counter, grant = countingGrant(store, key)
		processReceipt(r, store, grant, buyer)
		assert(
			counter.statusDuringGrant == "pending",
			`expected the marker to be pending during the grant, saw {tostring(counter.statusDuringGrant)}`
		)
	end,

	["a grant that returns false clears the marker and returns NotProcessedYet"] = function()
		local store = newStore()
		local r = receipt("refused")
		local key = keyOf(r)
		local counter, grant = countingGrant(store, key, "false")
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "grant returned false")
		assert(counter.calls == 1, `expected 1 grant attempt, got {counter.calls}`)
		assert(store.removes == 1, `expected the marker removed once, RemoveAsync ran {store.removes} times`)
		assert(store.data[key] == nil, "the marker should be gone so Roblox's retry can grant")
	end,

	["a grant that errors clears the marker and returns NotProcessedYet"] = function()
		local store = newStore()
		local r = receipt("errored")
		local key = keyOf(r)
		local counter, grant = countingGrant(store, key, "error")
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "grant errored")
		assert(counter.calls == 1, `expected 1 grant attempt, got {counter.calls}`)
		assert(store.removes == 1, `expected the marker removed once, RemoveAsync ran {store.removes} times`)
		assert(store.data[key] == nil, "the marker should be gone so Roblox's retry can grant")
	end,

	["a failed RemoveAsync after a refused grant still returns NotProcessedYet"] = function()
		local store = newStore()
		local r = receipt("removefail")
		local key = keyOf(r)
		store.failRemove = true
		local _, grant = countingGrant(store, key, "false")
		local ok, decision = pcall(processReceipt, r, store, grant, buyer)
		assert(ok, `processReceipt must not throw when RemoveAsync fails: {tostring(decision)}`)
		assertDecision(decision, Decision.NotProcessedYet, "remove failed")
	end,

	["a failed mark-done still returns PurchaseGranted and grants once"] = function()
		local store = newStore()
		local r = receipt("markfail")
		local key = keyOf(r)
		store.failCalls[2] = true -- the second UpdateAsync (mark-done) throws
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.PurchaseGranted, "mark-done failed after a grant")
		assert(counter.calls == 1, `expected exactly 1 grant, got {counter.calls}`)
		assert(store.removes == 0, "a granted purchase must not have its marker removed")
	end,

	["a redelivered receipt after a successful grant is not granted again"] = function()
		local store = newStore()
		local r = receipt("redeliver")
		local key = keyOf(r)
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "first delivery")
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "second delivery")
		assert(counter.calls == 1, `expected 1 grant across two deliveries, got {counter.calls}`)
	end,

	["a reserve UpdateAsync failure returns NotProcessedYet and grants nothing"] = function()
		local store = newStore()
		local r = receipt("reservefail")
		local key = keyOf(r)
		store.failCalls[1] = true -- the first UpdateAsync (reserve) throws
		local counter, grant = countingGrant(store, key)
		local ok, decision = pcall(processReceipt, r, store, grant, buyer)
		assert(ok, `processReceipt must not throw when the reserve fails: {tostring(decision)}`)
		assertDecision(decision, Decision.NotProcessedYet, "reserve failed")
		assert(counter.calls == 0, `nothing may be granted when the reserve fails, granted {counter.calls} times`)
	end,
}

return tests

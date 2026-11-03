-- Engine tests for Monetization.luau's receipt handling (sprint-4 fix). Run in a real Roblox server on the
-- test place. Requiring Monetization hooks MarketplaceService.ProcessReceipt, which is fine here.
-- Every test uses its own fake DataStore and counting grant, so no state is shared between tests.
-- The fake store runs the UpdateAsync callback the way Roblox does: it can run it several times (a conflicting
-- write re-runs it and only the last result is written), and a test can change storage between runs.
-- Sprint-8 fix: a pending marker is only replaced by the attempt that owns its token: "done" after a grant,
-- "released" after a refusal or error (a released receipt can be reserved again). A handler that yields runs in
-- its own task; its late result is written with retries.
-- Sprint-9 fix: no test really waits. Every test runs on a fake clock (Monetization._test.clock): `now` is a
-- number the test moves, and `wait` records the delay, moves the clock and returns at once, so background
-- retries finish before the call that started them returns. Yielding grants yield with coroutine.yield and the
-- test resumes them with `finish()`, so their timing is exact too.
local Monetization = require("./Monetization")
local processReceipt = Monetization._processReceipt
local hooks = Monetization._test
local Decision = Enum.ProductPurchaseDecision

local buyer = { Name = "Tester", UserId = 1 }

-- Sprint-9 fix: the fake clock. `fake.t` is "now"; `fake.waits` lists every delay waited, in order.
local realNow, realWait = hooks.clock.now, hooks.clock.wait
local fake = { t = 0, waits = {} :: { number } }

local function installFakeClock()
	fake.t = os.time()
	fake.waits = {}
	hooks.clock.now = function()
		return fake.t
	end
	hooks.clock.wait = function(seconds)
		table.insert(fake.waits, seconds)
		fake.t += seconds
	end
end

local function restoreClock()
	hooks.clock.now = realNow
	hooks.clock.wait = realWait
end

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
--   gets            how many GetAsync calls were made (Sprint-9 fix)
--   failGet         makes GetAsync throw (Sprint-9 fix)
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
		gets = 0,
		failGet = false,
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
	function store:GetAsync(key)
		self.gets += 1
		if self.failGet then
			error("simulated GetAsync failure")
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

-- Sprint-7 fix: a grant that yields before it returns `result`. Sprint-8 fix: "error" makes it throw instead.
-- Sprint-9 fix: it yields with coroutine.yield (not task.wait) and stays suspended until the test calls
-- `counter.finish()`, which resumes it right there.
local function lateGrant(result: boolean | string)
	local counter = { calls = 0, thread = nil :: thread? }
	local fn = function(_player)
		counter.calls += 1
		counter.thread = coroutine.running()
		coroutine.yield()
		if result == "error" then
			error("late handler exploded")
		end
		return result
	end
	function counter.finish()
		local thread = counter.thread
		assert(thread and coroutine.status(thread) == "suspended", "the late grant should be waiting to finish")
		task.spawn(thread)
	end
	return counter, fn
end

local function statusOf(store, key)
	local held = store.data[key]
	return if type(held) == "table" then held.status else held
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
				s.data[key] = { status = "pending", at = fake.t }
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
		store.data[key] = { status = "done", at = fake.t }
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
		store.data[key] = { status = "pending", at = fake.t }
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "fresh pending")
		assert(counter.calls == 0, `a busy receipt must not be granted, granted {counter.calls} times`)
	end,

	-- Sprint-9 fix: a pending marker up to exactly STALE_PENDING old is still busy and left untouched.
	["a pending marker up to STALE_PENDING old is busy: NotProcessedYet, no grant, marker untouched"] = function()
		for _, age in { 600, hooks.STALE_PENDING - 1, hooks.STALE_PENDING } do
			local store = newStore()
			local r = receipt(`old-pending-{age}`)
			local key = keyOf(r)
			local old = { status = "pending", at = fake.t - age, token = "other" }
			store.data[key] = old
			local counter, grant = countingGrant(store, key)
			assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, `pending {age} s old`)
			assert(counter.calls == 0, `a {age} s old marker must not be taken over, granted {counter.calls} times`)
			assert(store.data[key] == old, "the other attempt's marker must be left untouched")
		end
	end,

	-- Sprint-9 fix: a pending marker older than STALE_PENDING (or with no time) counts as released.
	["a stale pending marker is taken over: reserved again, granted once, done with our token"] = function()
		for label, stale in
			{
				older = { status = "pending", at = fake.t - hooks.STALE_PENDING - 1, token = "other" },
				epoch = { status = "pending", at = 0 },
				untimed = { status = "pending", token = "other" },
				-- a non-numeric `at` is not a time, so the marker counts as released
				textat = { status = "pending", at = "yesterday", token = "other" },
			}
		do
			local store = newStore()
			local r = receipt(`stale-{label}`)
			local key = keyOf(r)
			store.data[key] = stale
			local counter, grant = countingGrant(store, key)
			assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, `stale {label}`)
			assert(counter.calls == 1, `stale {label}: expected 1 grant, got {counter.calls}`)
			assert(
				counter.statusDuringGrant == "pending",
				`stale {label}: our marker should be pending during the grant`
			)
			assert(statusOf(store, key) == "done", `stale {label}: expected done, got {tostring(statusOf(store, key))}`)
			assert(store.data[key].token ~= "other", `stale {label}: the done marker must carry our token`)
		end
	end,

	-- Sprint-9 fix: the attempt whose marker went stale can still finish late. Its write only lands over its own
	-- token, so it leaves the new attempt's done marker alone.
	["a stale attempt's late result never overwrites the attempt that took it over"] = function()
		local store = newStore()
		local r = receipt("stale-late")
		local key = keyOf(r)
		local first, firstGrant = lateGrant(false)
		assertDecision(processReceipt(r, store, firstGrant, buyer), Decision.NotProcessedYet, "first attempt yields")
		fake.t += hooks.STALE_PENDING + 1
		local second, secondGrant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, secondGrant, buyer), Decision.PurchaseGranted, "takeover")
		local done = store.data[key]
		first.finish()
		assert(first.calls == 1 and second.calls == 1, "each attempt should have run its grant once")
		assert(store.data[key] == done, "the late release must leave the new attempt's done marker alone")
		assert(statusOf(store, key) == "done", `expected done, got {tostring(statusOf(store, key))}`)
	end,

	["the stale-takeover window is a day"] = function()
		assert(Monetization._PENDING_TIMEOUT == nil, "PENDING_TIMEOUT should no longer exist")
		assert(hooks.STALE_PENDING == 24 * 3600, `expected STALE_PENDING of a day, got {hooks.STALE_PENDING}`)
	end,

	-- Sprint-8 fix: a released marker (a refused or failed attempt) can be reserved again.
	["a released marker is reserved again and granted once"] = function()
		local store = newStore()
		local r = receipt("released")
		local key = keyOf(r)
		store.data[key] = { status = "released", at = fake.t, token = "old" }
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "released receipt")
		assert(counter.calls == 1, `expected 1 grant, got {counter.calls}`)
		assert(statusOf(store, key) == "done", "receipt should end up done")
	end,

	-- Sprint-6 fix: the grant runs synchronously, right after the reserve.
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

	-- Sprint-7 fix: a handler that yields is not stopped. The first call answers NotProcessedYet and keeps the
	-- pending marker (no RemoveAsync). When it finishes, the receipt is marked done. A redelivery grants nothing.
	["a handler that yields then returns true: NotProcessedYet, marked done late, no extra grant"] = function()
		local store = newStore()
		local r = receipt("yielder-true")
		local key = keyOf(r)
		local counter, grant = lateGrant(true)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "yielding handler")
		assert(store.removes == 0, `a yielded grant must not remove its marker, removes was {store.removes}`)
		assert(store.data[key].status == "pending", "the marker must stay pending while the grant runs")
		counter.finish()
		assert(counter.calls == 1, `expected 1 grant, got {counter.calls}`)
		assert(
			store.data[key].status == "done",
			`expected the late grant to mark done, status {tostring(store.data[key].status)}`
		)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "redelivery after late done")
		assert(counter.calls == 1, `a redelivery must not grant again, granted {counter.calls} times`)
	end,

	-- Sprint-8 fix: a late refusal or error releases our marker (UpdateAsync, no RemoveAsync) so a retry grants.
	["a handler that yields then returns false or errors: marker released late, retry grants once"] = function()
		for _, result in { false, "error" } do
			local store = newStore()
			local r = receipt(`yielder-{tostring(result)}`)
			local key = keyOf(r)
			local counter, grant = lateGrant(result)
			assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "yielding handler")
			assert(statusOf(store, key) == "pending", "the marker must stay pending while the grant runs")
			counter.finish()
			assert(counter.calls == 1, `expected 1 grant attempt, got {counter.calls}`)
			assert(store.removes == 0, `the marker must be released, not removed; removes was {store.removes}`)
			assert(statusOf(store, key) == "released", `expected released, got {tostring(statusOf(store, key))}`)
			local retry, retryGrant = countingGrant(store, key)
			assertDecision(processReceipt(r, store, retryGrant, buyer), Decision.PurchaseGranted, "retry after release")
			assert(retry.calls == 1, `the retry should grant once, granted {retry.calls} times`)
		end
	end,

	-- Sprint-8 fix: the late done write is retried with backoff. Sprint-9 fix: the delays are checked exactly.
	["a late success whose done write fails twice is still recorded, after RETRY_FIRST then double"] = function()
		local store = newStore()
		local r = receipt("yielder-retrywrite")
		local key = keyOf(r)
		store.failCalls[2] = true
		store.failCalls[3] = true
		local counter, grant = lateGrant(true)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "yielding handler")
		counter.finish()
		assert(store.calls == 4, `expected 1 reserve and 3 done writes, saw {store.calls} UpdateAsync calls`)
		local first = Monetization._RETRY_FIRST
		assert(
			#fake.waits == 2 and fake.waits[1] == first and fake.waits[2] == first * 2,
			`expected waits of {first} and {first * 2} s, got {table.concat(fake.waits, ", ")}`
		)
		assert(statusOf(store, key) == "done", `expected done, got {tostring(statusOf(store, key))}`)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "redelivery")
		assert(counter.calls == 1, `a redelivery must not grant again, granted {counter.calls} times`)
	end,

	-- Sprint-8 fix: a late failure whose release write fails is retried too, and then a retry can grant.
	["a late failure whose release write fails once is still released"] = function()
		local store = newStore()
		local r = receipt("yielder-retryrelease")
		local key = keyOf(r)
		store.failCalls[2] = true
		local counter, grant = lateGrant(false)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "yielding handler")
		counter.finish()
		assert(statusOf(store, key) == "released", `expected released, got {tostring(statusOf(store, key))}`)
	end,

	-- Sprint-9 fix: keepWriting stops after MAX_RETRIES attempts instead of looping forever.
	["a late write that always fails gives up after MAX_RETRIES attempts"] = function()
		local store = newStore()
		local r = receipt("yielder-giveup")
		local key = keyOf(r)
		for call = 2, hooks.MAX_RETRIES + 5 do
			store.failCalls[call] = true
		end
		local counter, grant = lateGrant(true)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "yielding handler")
		local inFlightBefore = hooks.inFlight()
		counter.finish()
		assert(
			store.calls == 1 + hooks.MAX_RETRIES,
			`expected 1 reserve and {hooks.MAX_RETRIES} attempts, saw {store.calls} UpdateAsync calls`
		)
		assert(#fake.waits == hooks.MAX_RETRIES - 1, `expected {hooks.MAX_RETRIES - 1} waits, got {#fake.waits}`)
		for i, delay in fake.waits do
			assert(delay <= 30, `wait {i} was {delay} s, over RETRY_MAX`)
		end
		-- Doubling from RETRY_FIRST (0.5 s), capped at RETRY_MAX (30 s): 0.5, 1, 2, 4, 8, 16, then 30.
		local expectedWaits = { 0.5, 1, 2, 4, 8, 16, 30, 30, 30 }
		assert(#fake.waits == #expectedWaits, `expected {#expectedWaits} waits, got {#fake.waits}`)
		for i, delay in expectedWaits do
			assert(fake.waits[i] == delay, `wait {i}: expected {delay} s, got {fake.waits[i]}`)
		end
		assert(statusOf(store, key) == "pending", "nothing could be written, so our marker is still pending")
		assert(hooks.inFlight() == inFlightBefore - 1, "the given-up grant must no longer count as in flight")
	end,

	-- Sprint-9 fix: the same cap applies to the background mark-done after a synchronous grant.
	["a synchronous mark-done that always fails gives up after MAX_RETRIES background attempts"] = function()
		local store = newStore()
		local r = receipt("markfail-giveup")
		local key = keyOf(r)
		for call = 2, hooks.MAX_RETRIES + 5 do
			store.failCalls[call] = true
		end
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "mark-done failing")
		assert(counter.calls == 1, `expected 1 grant, got {counter.calls}`)
		-- 1 reserve, 1 synchronous mark-done, then MAX_RETRIES background attempts.
		assert(
			store.calls == 2 + hooks.MAX_RETRIES,
			`expected {2 + hooks.MAX_RETRIES} UpdateAsync calls, saw {store.calls}`
		)
	end,

	-- Sprint-8 fix: retries keep answering NotProcessedYet while a yielding grant runs, however many there are.
	["many retries while a yielding grant runs: one grant in total"] = function()
		local store = newStore()
		local r = receipt("yielder-many")
		local key = keyOf(r)
		local first, firstGrant = lateGrant(true)
		local others, otherGrant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, firstGrant, buyer), Decision.NotProcessedYet, "first attempt")
		for i = 1, 5 do
			assertDecision(processReceipt(r, store, otherGrant, buyer), Decision.NotProcessedYet, `retry {i}`)
		end
		first.finish()
		assertDecision(processReceipt(r, store, otherGrant, buyer), Decision.PurchaseGranted, "retry after done")
		assert(first.calls == 1 and others.calls == 0, `expected 1 grant, got {first.calls + others.calls}`)
	end,

	-- Sprint-7 fix: a retry while the yielded grant is still running sees the fresh marker and grants nothing.
	["a retry while the yielded grant is still running: NotProcessedYet and no second grant"] = function()
		local store = newStore()
		local r = receipt("yielder-retry")
		local key = keyOf(r)
		local first, firstGrant = lateGrant(true)
		local second, secondGrant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, firstGrant, buyer), Decision.NotProcessedYet, "first attempt")
		assertDecision(processReceipt(r, store, secondGrant, buyer), Decision.NotProcessedYet, "retry while running")
		assert(second.calls == 0, `the retry must not grant, granted {second.calls} times`)
		first.finish()
		assert(first.calls == 1, `expected the first grant to finish once, got {first.calls}`)
		assert(store.data[key].status == "done", "the first grant should mark the receipt done")
		assert(second.calls == 0, `the retry must still not grant after the first finishes, granted {second.calls}`)
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
				self.data[k] = { status = "pending", at = fake.t, token = "other" }
				return self.data[k]
			end
			return result
		end
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "token lost")
		assert(counter.calls == 0, `nothing may be granted once the token is lost, granted {counter.calls} times`)
		assert(store.data[key].token == "other", "the other attempt's marker must be left untouched")
	end,

	-- Sprint-8 fix: if our marker is replaced by hand while the grant runs, the other value is left alone; the
	-- product was given, so it answers PurchaseGranted rather than let Roblox retry it.
	["a marker replaced during our grant is left alone and the grant is not repeated"] = function()
		local store = newStore()
		local r = receipt("replaced")
		local key = keyOf(r)
		local calls = 0
		local function grant(_player)
			calls += 1
			store.data[key] = { status = "pending", at = fake.t, token = "other" }
			return true
		end
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "replaced during grant")
		assert(calls == 1, `expected exactly 1 grant, got {calls}`)
		assert(store.data[key].token == "other", "the other marker must be left untouched")
	end,

	["the stored marker during our grant carries a non-empty token string and the clock's time"] = function()
		local store = newStore()
		local r = receipt("tokencheck")
		local key = keyOf(r)
		local seen, seenAt = nil, nil
		local function grant(_player)
			local held = store.data[key]
			seen = if type(held) == "table" then held.token else nil
			seenAt = if type(held) == "table" then held.at else nil
			return true
		end
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "token check")
		assert(type(seen) == "string", `expected a string token during the grant, got {tostring(seen)}`)
		assert(#seen > 0, "the token must not be empty")
		assert(seenAt == fake.t, `the marker's time should come from the clock hook, got {tostring(seenAt)}`)
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

	-- Sprint-8 fix: a refused or failed grant releases its own marker (UpdateAsync, no RemoveAsync).
	["a grant that returns false releases the marker and returns NotProcessedYet"] = function()
		local store = newStore()
		local r = receipt("refused")
		local key = keyOf(r)
		local counter, grant = countingGrant(store, key, "false")
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "grant returned false")
		assert(counter.calls == 1, `expected 1 grant attempt, got {counter.calls}`)
		assert(store.removes == 0, `the marker must be released, not removed; removes was {store.removes}`)
		assert(statusOf(store, key) == "released", "the marker should be released so Roblox's retry can grant")
	end,

	["a grant that errors releases the marker and returns NotProcessedYet"] = function()
		local store = newStore()
		local r = receipt("errored")
		local key = keyOf(r)
		local counter, grant = countingGrant(store, key, "error")
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.NotProcessedYet, "grant errored")
		assert(counter.calls == 1, `expected 1 grant attempt, got {counter.calls}`)
		assert(statusOf(store, key) == "released", "the marker should be released so Roblox's retry can grant")
	end,

	["a failed release after a refused grant returns NotProcessedYet and is retried"] = function()
		local store = newStore()
		local r = receipt("releasefail")
		local key = keyOf(r)
		store.failCalls[2] = true -- the release UpdateAsync throws once
		local _, grant = countingGrant(store, key, "false")
		local ok, decision = pcall(processReceipt, r, store, grant, buyer)
		assert(ok, `processReceipt must not throw when the release fails: {tostring(decision)}`)
		assertDecision(decision, Decision.NotProcessedYet, "release failed")
		assert(statusOf(store, key) == "released", `expected released, got {tostring(statusOf(store, key))}`)
	end,

	["a failed mark-done still returns PurchaseGranted, grants once, and is recorded by a retry"] = function()
		local store = newStore()
		local r = receipt("markfail")
		local key = keyOf(r)
		store.failCalls[2] = true -- the second UpdateAsync (mark-done) throws
		local counter, grant = countingGrant(store, key)
		local decision = processReceipt(r, store, grant, buyer)
		assertDecision(decision, Decision.PurchaseGranted, "mark-done failed after a grant")
		assert(counter.calls == 1, `expected exactly 1 grant, got {counter.calls}`)
		assert(statusOf(store, key) == "done", `expected done, got {tostring(statusOf(store, key))}`)
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

	-- Sprint-9 fix: a reserve that throws before writing leaves nothing of ours. After RETRY_FIRST the receipt is
	-- read back, and since it doesn't hold our token, no release is written.
	["a reserve that throws before writing: read back after RETRY_FIRST, no release written"] = function()
		local store = newStore()
		local r = receipt("reservefail")
		local key = keyOf(r)
		store.failCalls[1] = true -- the first UpdateAsync (reserve) throws
		local counter, grant = countingGrant(store, key)
		local ok, decision = pcall(processReceipt, r, store, grant, buyer)
		assert(ok, `processReceipt must not throw when the reserve fails: {tostring(decision)}`)
		assertDecision(decision, Decision.NotProcessedYet, "reserve failed")
		assert(counter.calls == 0, `nothing may be granted when the reserve fails, granted {counter.calls} times`)
		assert(
			fake.waits[1] == Monetization._RETRY_FIRST,
			`expected a {Monetization._RETRY_FIRST} s wait first, got {tostring(fake.waits[1])}`
		)
		assert(store.gets == 1, `expected the receipt to be read back once, got {store.gets} reads`)
		assert(store.calls == 1, `no release should be written, saw {store.calls} UpdateAsync calls`)
		assert(store.data[key] == nil, "nothing should be stored")
	end,

	-- Sprint-9 fix: same, but another attempt's marker is there: it's read back and left untouched.
	["a failed reserve with another attempt's marker stored: no release, marker untouched"] = function()
		local store = newStore()
		local r = receipt("reservefail-other")
		local key = keyOf(r)
		local other = { status = "released", at = fake.t, token = "other" }
		store.data[key] = other
		store.failCalls[1] = true
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "reserve failed")
		assert(counter.calls == 0, `nothing may be granted, granted {counter.calls} times`)
		assert(store.gets == 1, `expected the receipt to be read back once, got {store.gets} reads`)
		assert(store.calls == 1, `no release should be written, saw {store.calls} UpdateAsync calls`)
		assert(store.data[key] == other, "the other attempt's marker must be left untouched")
	end,

	-- Sprint-8 fix: a reserve that writes its marker and then throws leaves it behind. Sprint-9 fix: after
	-- RETRY_FIRST it's read back; it holds our token, so it's released and a retry can grant.
	["a reserve that writes then throws: our marker is read back and released; a retry grants once"] = function()
		local store = newStore()
		local r = receipt("reserve-landed")
		local key = keyOf(r)
		local realUpdate = store.UpdateAsync
		function store:UpdateAsync(k, transform)
			local isReserve = self.calls == 0
			local result = realUpdate(self, k, transform)
			if isReserve then
				error("simulated reserve failure after the write landed")
			end
			return result
		end
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "reserve threw")
		assert(counter.calls == 0, `nothing may be granted when the reserve throws, granted {counter.calls} times`)
		assert(fake.waits[1] == Monetization._RETRY_FIRST, `expected a {Monetization._RETRY_FIRST} s wait first`)
		assert(store.gets == 1, `expected the receipt to be read back once, got {store.gets} reads`)
		assert(statusOf(store, key) == "released", `expected released, got {tostring(statusOf(store, key))}`)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "retry")
		assert(counter.calls == 1, `expected 1 grant, got {counter.calls}`)
	end,

	-- Sprint-9 fix: if the read-back fails too, it releases anyway; the write still only lands over our token.
	["a reserve that writes then throws, and the read-back fails: still released"] = function()
		local store = newStore()
		local r = receipt("reserve-landed-noread")
		local key = keyOf(r)
		store.failGet = true
		local realUpdate = store.UpdateAsync
		function store:UpdateAsync(k, transform)
			local isReserve = self.calls == 0
			local result = realUpdate(self, k, transform)
			if isReserve then
				error("simulated reserve failure after the write landed")
			end
			return result
		end
		local _, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "reserve threw")
		assert(statusOf(store, key) == "released", `expected released, got {tostring(statusOf(store, key))}`)
	end,

	-- Sprint-8 fix: a mark-done that writes and then throws is written again over the same token. Nothing is
	-- granted twice.
	["a mark-done that writes then throws is written again, and a redelivery grants nothing"] = function()
		local store = newStore()
		local r = receipt("done-landed")
		local key = keyOf(r)
		local realUpdate = store.UpdateAsync
		function store:UpdateAsync(k, transform)
			local result = realUpdate(self, k, transform)
			if self.calls == 2 then
				error("simulated mark-done failure after the write landed")
			end
			return result
		end
		local counter, grant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "mark-done threw")
		assert(counter.calls == 1, `expected exactly 1 grant, got {counter.calls}`)
		assert(statusOf(store, key) == "done", `expected done, got {tostring(statusOf(store, key))}`)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.PurchaseGranted, "redelivery")
		assert(counter.calls == 1, `a redelivery must not grant again, granted {counter.calls} times`)
	end,

	-- A handler that returns nothing has not said it gave the product, so it counts as a refusal.
	["a handler that returns nothing is treated as refused and released"] = function()
		local store = newStore()
		local r = receipt("nothing")
		local key = keyOf(r)
		local calls = 0
		local function grant(_player)
			calls += 1
		end
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "no return value")
		assert(calls == 1, `expected 1 grant attempt, got {calls}`)
		assert(statusOf(store, key) == "released", `expected released, got {tostring(statusOf(store, key))}`)
		local retry, retryGrant = countingGrant(store, key)
		assertDecision(processReceipt(r, store, retryGrant, buyer), Decision.PurchaseGranted, "retry")
		assert(retry.calls == 1, `the retry should grant once, granted {retry.calls} times`)
	end,

	-- Sprint-8 fix: a late result is written only over our own marker. If another attempt's marker has replaced
	-- ours, the late result leaves it alone.
	["a late result never overwrites another attempt's marker"] = function()
		local store = newStore()
		local r = receipt("late-clobber")
		local key = keyOf(r)
		local counter, grant = lateGrant(true)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "yielding handler")
		store.data[key] = { status = "pending", at = fake.t, token = "other" }
		counter.finish()
		assert(counter.calls == 1, `expected 1 grant, got {counter.calls}`)
		assert(store.data[key].token == "other", "the other attempt's marker must be left untouched")
		assert(store.data[key].status == "pending", "the other attempt's marker must not be changed")
	end,

	-- Sprint-9 fix: a yielding grant and its write count as in flight; the shutdown drain waits for them, and
	-- gives up after SHUTDOWN_WAIT seconds if they never finish.
	["in-flight writes are tracked; the shutdown drain waits for them, up to SHUTDOWN_WAIT"] = function()
		local base = hooks.inFlight()
		local store = newStore()
		local r = receipt("drain")
		local key = keyOf(r)
		-- The late done write stalls inside UpdateAsync until the test resumes it.
		local stalled: thread? = nil
		local realUpdate = store.UpdateAsync
		function store:UpdateAsync(k, transform)
			if self.calls == 1 and not stalled then
				stalled = coroutine.running()
				coroutine.yield()
			end
			return realUpdate(self, k, transform)
		end
		local counter, grant = lateGrant(true)
		assertDecision(processReceipt(r, store, grant, buyer), Decision.NotProcessedYet, "yielding handler")
		assert(hooks.inFlight() == base + 1, `a running late grant should be in flight, got {hooks.inFlight() - base}`)
		counter.finish()
		assert(stalled ~= nil, "the late done write should have started")
		assert(hooks.inFlight() > base, "the stalled write should be in flight")
		local t0 = fake.t
		local drained = hooks.drain(hooks.SHUTDOWN_WAIT)
		assert(not drained, "the drain should give up while a write is stalled")
		local waited = fake.t - t0
		assert(
			waited >= hooks.SHUTDOWN_WAIT - 0.01 and waited <= hooks.SHUTDOWN_WAIT + 0.2,
			`the drain should wait about {hooks.SHUTDOWN_WAIT} s, waited {waited}`
		)
		task.spawn(stalled :: thread)
		assert(statusOf(store, key) == "done", `expected done, got {tostring(statusOf(store, key))}`)
		assert(hooks.inFlight() == base, `nothing should be in flight now, got {hooks.inFlight() - base}`)
		fake.waits = {}
		assert(hooks.drain(hooks.SHUTDOWN_WAIT), "the drain should finish once nothing is in flight")
		assert(#fake.waits == 0, "the drain should not wait when nothing is in flight")
	end,
}

-- Sprint-9 fix: every test runs on a fresh fake clock, which is put back afterwards, and must not leave any
-- write or grant in flight.
for name, test in tests do
	tests[name] = function()
		installFakeClock()
		local inFlightBefore = hooks.inFlight()
		local ok, err = pcall(test)
		local inFlightAfter = hooks.inFlight()
		restoreClock()
		if not ok then
			error(err, 0)
		end
		assert(
			inFlightAfter == inFlightBefore,
			`the test left {inFlightAfter - inFlightBefore} write(s) or grant(s) in flight`
		)
	end
end

return tests

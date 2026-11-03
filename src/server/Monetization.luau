--!strict
-- Robux purchases, on the server. Game code says what each purchase gives:
--   Monetization.onPass("VIP", function(player) ... end)            -- runs when an owner joins, and right after buying
--   Monetization.onProduct("Coins100", function(player) ... return true end)  -- return true once it's given
-- A product's receipt is reserved in a DataStore before its handler runs and marked done after,
-- so a purchase Roblox retries is never given twice.
-- Sprint-8 fix: each attempt writes a "pending" marker with its own token, and only that attempt ever replaces
-- it (with "done" or "released"). Sprint-9 fix: the one exception is a marker over a day old (see below).
-- The handler runs in its own task. While it runs, the receipt answers NotProcessedYet. When it finishes, even
-- late, its result is written over its own marker, retrying with backoff until the write succeeds:
--   true          -> "done": Roblox's retry gets PurchaseGranted and nothing more is given
--   false / error -> "released": Roblox's retry can try the grant again
-- Handlers SHOULD NOT YIELD (no task.wait, no Async calls, no WaitForChild): give the product and return.
-- Why: a yielding handler is never cancelled (that could leave a half-done grant), so the player waits for
-- it, and if the server shuts down while it's yielding, its marker is never replaced. Then that
-- purchase then answers NotProcessedYet on every retry until the marker goes stale (Sprint-9 fix).
-- Sprint-9 fix: a pending marker older than STALE_PENDING (a day) counts as released, so a purchase left
-- pending by a server that died is retried the next day instead of being stuck for good. Late writes give up
-- after MAX_RETRIES attempts, and on shutdown the server waits (up to SHUTDOWN_WAIT) for writes still running.
-- Sprint-10 fix: while our grant runs or its result is still being written, a heartbeat refreshes our pending
-- marker's `at` every HEARTBEAT seconds, so only markers left by dead servers ever go stale. A pending marker with
-- no numeric `at` counts as busy and is restamped with the current time, so it goes stale a day later.
-- Sprint-11 fix: a heartbeat stops after MAX_HEARTBEAT_AGE (with one warn), so a handler that never returns lets its
-- marker go stale like a dead server's. The restamp happens once per marker (`restamped = true`). A receipt whose
-- result write was given up on is never granted again by this server (`gaveUp`).
-- Sprint-12 fix: only a given-up "done" blocks (a given-up "released" gave nothing). The heartbeat cap counts from
-- the attempt's reserve, one MAX_HEARTBEAT_AGE window shared by the grant and its result write; if the cap is hit
-- while the grant runs or its done write is pending, the receipt is blocked too. Blocks expire after GAVE_UP_TTL.
-- The DataStore is opened on first use, so an unpublished Studio place can still require this module.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Products = require(game:GetService("ReplicatedStorage").Shared.Products)

local Monetization = {}

-- Sprint-8 fix: PENDING_TIMEOUT and the stale-marker takeover are gone. Writing a result over our own marker
-- retries after this many seconds, doubling each time up to RETRY_MAX.
local RETRY_FIRST = 0.5
local RETRY_MAX = 30
-- Sprint-9 fix: a pending marker this old (seconds) is treated like "released" and can be reserved again.
local STALE_PENDING = 24 * 3600
-- Sprint-9 fix: keepWriting gives up (with a warn) after this many UpdateAsync attempts.
local MAX_RETRIES = 10
-- Sprint-9 fix: on shutdown, wait at most this many seconds for in-flight writes and late grants.
-- Sprint-10 fix: 20 s (was 25), well inside the 30 s Roblox gives BindToClose.
local SHUTDOWN_WAIT = 20
-- Sprint-10 fix: how often (seconds) a live attempt refreshes its pending marker's `at`.
local HEARTBEAT = 60
-- Sprint-11 fix: a heartbeat refreshes for at most this many seconds in total, then stops (with one warn).
local MAX_HEARTBEAT_AGE = 1800
-- Sprint-12 fix: a gaveUp entry blocks its receipt for this many seconds after it was recorded, then expires.
local GAVE_UP_TTL = STALE_PENDING + MAX_HEARTBEAT_AGE

type Clock = {
	now: () -> number,
	wait: (seconds: number) -> (),
	delay: (seconds: number, callback: () -> ()) -> (),
}

-- Sprint-9 fix: the clock and wait used for markers and retries. Specs swap these for a fake clock.
local realClock: Clock = {
	now = function(): number
		return os.time()
	end,
	wait = function(seconds: number)
		task.wait(seconds)
	end,
	-- Sprint-10 fix: runs `callback` after `seconds`, without yielding. Used by the heartbeat.
	delay = function(seconds: number, callback: () -> ())
		task.delay(seconds, callback)
	end,
}
local clock: Clock = table.clone(realClock)

-- Sprint-10 fix: every warning goes through here, so specs can read them.
local function realWarn(message: string)
	warn(message)
end
local log = { warn = realWarn }

type PassHandler = (player: Player) -> ()
type ProductHandler = (player: Player) -> boolean
type Receipt = { PlayerId: number, PurchaseId: string, ProductId: number }
-- Sprint-12 fix: one try at a receipt, from its reserve to its final write. The heartbeat window starts at
-- `reservedAt`; `capped` is set once the heartbeat cap is hit, so it warns only once per attempt.
type Attempt = {
	store: DataStore,
	key: string,
	token: string,
	purchaseId: string,
	reservedAt: number,
	capped: boolean,
}
-- Sprint-12 fix: a receipt this server must not grant again, the attempt that blocked it, and since when.
type GaveUp = { status: "done", token: string, at: number }

local passHandlers: { [string]: PassHandler } = {}
local productHandlers: { [string]: ProductHandler } = {}
local owned: { [Player]: { [string]: boolean } } = {}
local history: DataStore? = nil
-- Receipts being handled right now, so a duplicate ProcessReceipt call can't grant twice.
local processing: { [string]: boolean } = {}
-- Sprint-9 fix: background writes and late grants still running, so BindToClose can wait for them.
local inFlight = 0
-- Sprint-11 fix: receipt keys whose result keepWriting gave up on, with the token of the attempt that gave up.
-- This server never grants them again (it may already have), whatever the store says later.
-- Sprint-12 fix: only for a "done" result (or a grant still running at the heartbeat cap), and for GAVE_UP_TTL.
local gaveUp: { [string]: GaveUp } = {}

-- Sprint-12 fix: blocks this attempt's receipt on this server. Keeps the first time recorded, so it can't be extended.
local function recordGaveUp(attempt: Attempt)
	local entry = gaveUp[attempt.key]
	if entry and entry.token == attempt.token then
		return
	end
	gaveUp[attempt.key] = { status = "done", token = attempt.token, at = clock.now() }
end

-- Sprint-12 fix: lifts this attempt's block once the store holds its result, or once its grant is known to have
-- given nothing.
local function clearGaveUp(attempt: Attempt)
	local entry = gaveUp[attempt.key]
	if entry and entry.token == attempt.token then
		gaveUp[attempt.key] = nil
	end
end

local function getHistory(): DataStore?
	if history then
		return history
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore("PurchaseHistory")
	end)
	if not ok then
		log.warn(`[Monetization] purchase history unavailable: {store}`)
		return nil
	end
	history = store
	return store
end

local function keyFor(list: { [string]: Products.Item }, id: number): string?
	if id == 0 then
		return nil
	end
	for key, item in list do
		if item.id == id then
			return key
		end
	end
	return nil
end

function Monetization.ownsPass(player: Player, key: string): boolean
	local cache = owned[player]
	if cache and cache[key] ~= nil then
		return cache[key]
	end
	local pass = Products.Passes[key]
	if not pass or pass.id == 0 then
		return false
	end
	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
	end)
	if not ok then
		return false
	end
	local entry = owned[player] or {}
	owned[player] = entry
	entry[key] = has == true
	return has == true
end

function Monetization.onPass(key: string, handler: PassHandler)
	passHandlers[key] = handler
	for _, player in Players:GetPlayers() do
		if Monetization.ownsPass(player, key) then
			task.spawn(handler, player)
		end
	end
end

function Monetization.onProduct(key: string, handler: ProductHandler)
	productHandlers[key] = handler
end

Players.PlayerAdded:Connect(function(player)
	for key, handler in passHandlers do
		if Monetization.ownsPass(player, key) then
			task.spawn(handler, player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	owned[player] = nil
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	local key = keyFor(Products.Passes, passId)
	if not key then
		return
	end
	local entry = owned[player] or {}
	owned[player] = entry
	entry[key] = true
	local handler = passHandlers[key]
	if handler then
		task.spawn(handler, player)
	end
end)

local function isDone(value: any): boolean
	-- `true` is how receipts were recorded before sprint 4.
	return value == true or (type(value) == "table" and value.status == "done")
end

-- Sprint-8 fix: a pending marker means another attempt owns the receipt. Only that attempt replaces it.
-- Sprint-9 fix: unless it's older than STALE_PENDING: then it counts as released.
-- The old attempt's late write only lands over its own token, so it can't clobber the new attempt's marker.
local function isPending(value: any): boolean
	if type(value) ~= "table" or value.status ~= "pending" then
		return false
	end
	if type(value.at) ~= "number" then
		return true -- Sprint-10 fix: no time means busy (the reserve restamps it), not released
	end
	return clock.now() - value.at <= STALE_PENDING
end

local function isOurs(value: any, token: string): boolean
	return type(value) == "table" and value.token == token
end

-- Sprint-8 fix: one UpdateAsync that writes `final` only over the marker holding our token.
-- Returns (ok, wasOurs or error).
-- Sprint-10 fix: with `onlyPending`, it also needs our marker to still be pending (the heartbeat uses this, so a
-- late refresh can never turn our "done" or "released" back into "pending").
local function writeOverOurs(
	store: DataStore,
	receiptKey: string,
	token: string,
	final: any,
	onlyPending: boolean?
): (boolean, any)
	local wasOurs = false
	local ok, err = pcall(function()
		store:UpdateAsync(receiptKey, function(value)
			wasOurs = isOurs(value, token) and (not onlyPending or value.status == "pending")
			if not wasOurs then
				return nil -- not our marker: leave it alone
			end
			return final
		end)
	end)
	return ok, if ok then wasOurs else err
end

-- Sprint-10 fix: refreshes our pending marker's `at` every HEARTBEAT seconds until the returned stop function is
-- called, or the marker is no longer our pending one. Never yields; each beat runs in a task of its own.
-- Sprint-11 fix: it also stops (warning once) once a next beat would come more than MAX_HEARTBEAT_AGE seconds after
-- it started. The marker then goes stale STALE_PENDING after its last refresh, like a dead server's.
-- Sprint-12 fix: the window counts from the attempt's reserve, so the grant's heartbeat and keepWriting's share one
-- MAX_HEARTBEAT_AGE window per attempt. When the cap is hit (or already was), it calls `onCap`.
local function startHeartbeat(attempt: Attempt, onCap: () -> ()): () -> ()
	local beating = true
	local function overCap(): boolean
		if clock.now() + HEARTBEAT - attempt.reservedAt <= MAX_HEARTBEAT_AGE then
			return false
		end
		beating = false
		if not attempt.capped then
			attempt.capped = true
			log.warn(
				`[Monetization] stopped refreshing pending marker {attempt.key} after {MAX_HEARTBEAT_AGE} s;`
					.. ` it goes stale {STALE_PENDING} s after its last refresh.`
			)
		end
		onCap()
		return true
	end
	local function beat()
		if not beating then
			return
		end
		local fresh = { status = "pending", at = clock.now(), token = attempt.token }
		local ok, wasOurs = writeOverOurs(attempt.store, attempt.key, attempt.token, fresh, true)
		if ok and not wasOurs then
			beating = false -- our marker is gone or final: nothing left to keep alive
		elseif not ok then
			log.warn(`[Monetization] couldn't refresh pending marker {attempt.key}, trying again later: {wasOurs}`)
		end
		if beating and not overCap() then
			clock.delay(HEARTBEAT, beat)
		end
	end
	if not overCap() then
		clock.delay(HEARTBEAT, beat)
	end
	return function()
		beating = false
	end
end

-- Sprint-8 fix: writes `final` over our own marker, retrying with backoff until the write succeeds.
-- Yields, so it runs from the handler's task or a task of its own, never on ProcessReceipt's own path.
-- Sprint-9 fix: gives up with a warn after MAX_RETRIES attempts, and counts as in flight while it runs.
-- Sprint-10 fix: keeps our pending marker alive with a heartbeat while it retries.
-- Sprint-12 fix: a "released" result gave nothing, so it lifts this attempt's block and its give-up blocks nothing.
-- A "done" result blocks the receipt if it's given up on or the heartbeat cap is hit, until it lands over our marker.
local function keepWriting(attempt: Attempt, final: any)
	inFlight += 1
	local writingDone = final.status == "done"
	if not writingDone then
		clearGaveUp(attempt)
	end
	local stopHeartbeat = startHeartbeat(attempt, function()
		if writingDone then
			recordGaveUp(attempt)
		end
	end)
	local delay = RETRY_FIRST
	for try = 1, MAX_RETRIES do
		local ok, wasOurs = writeOverOurs(attempt.store, attempt.key, attempt.token, final)
		if ok then
			if wasOurs then
				clearGaveUp(attempt) -- Sprint-12 fix: the store holds our result now
			else
				log.warn(`[Monetization] purchase {attempt.purchaseId} doesn't hold our marker; wrote nothing`)
			end
			break
		end
		if try == MAX_RETRIES then
			-- Sprint-11 fix: this server never grants this receipt again. Sprint-12 fix: only if it was given.
			if writingDone then
				recordGaveUp(attempt)
			end
			-- Sprint-10 fix: name the receipt key, and say what happens to it now.
			log.warn(
				`[Monetization] gave up recording purchase {attempt.purchaseId} (receipt {attempt.key}) as {final.status}`
					.. ` after {MAX_RETRIES} attempts: {wasOurs}. It stays pending (NotProcessedYet) until it goes`
					.. ` stale, {STALE_PENDING} s after its last heartbeat; `
					.. (if writingDone then "this server won't grant it again." else "then it can be granted again.")
			)
			break
		end
		log.warn(
			`[Monetization] couldn't record purchase {attempt.purchaseId} as {final.status}, retrying in {delay} s: {wasOurs}`
		)
		clock.wait(delay)
		delay = math.min(delay * 2, RETRY_MAX)
	end
	stopHeartbeat()
	inFlight -= 1
end

-- Sprint-9 fix: after a failed reserve, wait RETRY_FIRST, read the receipt back, and release it only if it holds
-- our token (the reserve's write landed before the error). If the read fails too, release anyway: keepWriting
-- only ever writes over our own token, so that can't touch another attempt's marker.
local function releaseIfOurs(attempt: Attempt, final: any)
	inFlight += 1
	clock.wait(RETRY_FIRST)
	local ok, value = pcall(function()
		return attempt.store:GetAsync(attempt.key)
	end)
	if not ok then
		log.warn(`[Monetization] couldn't read purchase {attempt.purchaseId} after a failed reserve: {value}`)
	end
	if not ok or isOurs(value, attempt.token) then
		keepWriting(attempt, final)
	end
	inFlight -= 1
end

-- Sprint-8 fix: runs the grant in its own task (task.spawn) and never cancels it. Returns (true, ok, given) if
-- it finished before task.spawn returned, or (false) if it's still running. A grant that's still running
-- calls `onLate(ok, given)` from its own task when it finishes.
local function runGrant(
	grant: ProductHandler,
	buyer: Player,
	onLate: (ok: boolean, given: any) -> ()
): (boolean, boolean, any)
	local waiting = true
	local finished = false
	local resultOk, resultGiven = false, nil
	task.spawn(function()
		inFlight += 1 -- Sprint-9 fix: a yielding grant counts as in flight until its result is written
		local ok, given = pcall(grant, buyer)
		finished = true
		if waiting then
			resultOk, resultGiven = ok, given
		else
			local lateOk, lateErr = pcall(onLate, ok, given)
			if not lateOk then
				log.warn(`[Monetization] couldn't record a late grant: {lateErr}`)
			end
		end
		inFlight -= 1
	end)
	waiting = false
	if finished then
		return true, resultOk, resultGiven
	end
	return false, false, nil
end

-- Sprint-4 fix: UpdateAsync only reserves the receipt key with a "pending" marker. The grant runs after it
-- returns (so a retried UpdateAsync callback can never grant twice), then a second UpdateAsync records it.
-- Sprint-5 fix: each attempt writes its marker with its own unique token, and only grants if the stored value
-- after the reserve is that marker.
-- Sprint-8 fix: a pending marker is only ever replaced by the attempt that owns its token: with "done" after a
-- grant, or "released" after a refused or failed one (a released receipt can be reserved again).
local function processReceipt(receipt: Receipt, store: DataStore, grant: ProductHandler, buyer: Player)
	local receiptKey = `{receipt.PlayerId}_{receipt.PurchaseId}`
	local purchaseId = receipt.PurchaseId
	-- Sprint-11 fix: we gave up writing this receipt's result, so it may already be given: never grant it again here.
	-- Sprint-12 fix: only a "done" give-up blocks, and only until GAVE_UP_TTL after it was recorded.
	local blocked = gaveUp[receiptKey]
	if blocked and clock.now() - blocked.at > GAVE_UP_TTL then
		gaveUp[receiptKey] = nil
	elseif blocked and blocked.status == "done" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local token = HttpService:GenerateGUID(false)
	local attempt: Attempt = {
		store = store,
		key = receiptKey,
		token = token,
		purchaseId = purchaseId,
		reservedAt = clock.now(),
		capped = false,
	}
	local function marker(status: string)
		return { status = status, at = clock.now(), token = token }
	end
	local status: "done" | "busy" | "reserved" = "busy"
	local reserveOk, reserveResult = pcall(function()
		return store:UpdateAsync(receiptKey, function(value)
			-- May run more than once: it only sets `status` and returns the marker, nothing else.
			if isDone(value) then
				status = "done"
				return nil
			end
			if isPending(value) then
				status = "busy" -- another attempt owns it (its grant may still be running); stale ones fall through
				if type(value.at) ~= "number" and value.restamped ~= true then
					-- Sprint-10 fix: no time: keep the same marker (same token) but stamp it now, so it goes stale
					-- a day from now instead of staying busy for good.
					-- Sprint-11 fix: only once. A marker already restamped is just busy, so it can't be extended.
					local restamped = table.clone(value)
					restamped.at = clock.now()
					restamped.restamped = true
					return restamped
				end
				return nil
			end
			status = "reserved"
			return marker("pending")
		end)
	end)
	if not reserveOk then
		log.warn(`[Monetization] couldn't reserve purchase {purchaseId}: {reserveResult}`)
		-- Sprint-8 fix: the write may have landed before the error. Nothing was granted, so release our marker
		-- if it's there: it would otherwise block the purchase until it goes stale.
		-- Sprint-9 fix: not blindly: wait, read it back, and release only if it holds our token.
		task.spawn(releaseIfOurs, attempt, marker("released"))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "done" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- Sprint-5 fix: grant only once the store holds our token, not just because our callback said "reserved".
	if status == "busy" or not isOurs(reserveResult, token) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Sprint-8 fix: a grant still running when task.spawn returns answers NotProcessedYet now. Its result is
	-- written over our own marker when it finishes, retrying until the write succeeds.
	-- Sprint-10 fix: while it runs, a heartbeat keeps our marker fresh; keepWriting takes over when it finishes.
	local stopHeartbeat: () -> () = function() end
	local finished, grantOk, given = runGrant(grant, buyer, function(lateOk, lateGiven)
		stopHeartbeat()
		if lateOk and lateGiven == true then
			keepWriting(attempt, marker("done"))
			return
		end
		if not lateOk then
			log.warn(`[Monetization] yielding handler failed late for purchase {purchaseId}: {lateGiven}`)
		end
		keepWriting(attempt, marker("released"))
	end)
	if not finished then
		-- Sprint-10 fix. Sprint-12 fix: if the cap is hit while the grant still runs, it may yet give the product,
		-- so this server blocks the receipt (as done) from then on.
		stopHeartbeat = startHeartbeat(attempt, function()
			recordGaveUp(attempt)
		end)
		log.warn(
			`[Monetization] handler for purchase {purchaseId} yielded; product handlers should not yield.`
				.. " Answering NotProcessedYet until it finishes."
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not grantOk or given ~= true then
		if not grantOk then
			log.warn(`[Monetization] handler failed for purchase {purchaseId}: {given}`)
		end
		-- Sprint-8 fix: release our own marker with UpdateAsync (not RemoveAsync). If that fails, keep retrying
		-- in the background; until it lands the receipt stays busy, so nothing is granted meanwhile.
		local released = marker("released")
		local releaseOk, releaseErr = writeOverOurs(store, receiptKey, token, released)
		if not releaseOk then
			log.warn(`[Monetization] couldn't release purchase {purchaseId}, retrying: {releaseErr}`)
			task.spawn(keepWriting, attempt, released)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local done = marker("done")
	local doneOk, wasOurs = writeOverOurs(store, receiptKey, token, done)
	if not doneOk then
		-- It was given, so tell Roblox it's done rather than risk giving it again, and keep trying to record it.
		log.warn(`[Monetization] granted purchase {purchaseId} but couldn't record it yet, retrying: {wasOurs}`)
		task.spawn(keepWriting, attempt, done)
	elseif not wasOurs then
		-- Sprint-8 fix: nothing else replaces our marker, so the store was changed by hand. It was given anyway.
		log.warn(`[Monetization] purchase {purchaseId} was granted but no longer holds our marker`)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Sprint-9 fix: waits until no writes or late grants are in flight, or `timeout` seconds have passed.
-- Returns true if everything finished.
local function drain(timeout: number): boolean
	local waited = 0
	while inFlight > 0 and waited < timeout do
		clock.wait(0.1)
		waited += 0.1
	end
	return inFlight == 0
end

-- Sprint-9 fix: on shutdown, give background writes up to SHUTDOWN_WAIT seconds to land.
game:BindToClose(function()
	if not drain(SHUTDOWN_WAIT) then
		log.warn(`[Monetization] shutting down with {inFlight} purchase write(s) still running`)
	end
end)

-- TEST-ONLY: lets specs run a receipt against a stand-in DataStore (UpdateAsync, GetAsync) and handler on a fake
-- clock, and read the limits and in-flight count. `_test` is frozen.
-- Sprint-12 fix: `_test` exists everywhere (the Studio-only `_processReceipt` / `_RETRY_FIRST` are gone), so the
-- spec runs on any test runner. Its functions only work once wired: in Studio, or after `_test.enable()`; unwired
-- they error, so a live server never runs them by accident. The limits can always be read.
local testWired = RunService:IsStudio()
local function wired(name: string, fn: any): any
	return function(...)
		if not testWired then
			error(`[Monetization] _test.{name} is off outside Studio; call Monetization._test.enable() first`, 2)
		end
		return fn(...)
	end
end
Monetization._test = table.freeze({
	enable = function()
		testWired = true
	end,
	enabled = function(): boolean
		return testWired
	end,
	RETRY_FIRST = RETRY_FIRST,
	STALE_PENDING = STALE_PENDING,
	MAX_RETRIES = MAX_RETRIES,
	SHUTDOWN_WAIT = SHUTDOWN_WAIT,
	HEARTBEAT = HEARTBEAT,
	MAX_HEARTBEAT_AGE = MAX_HEARTBEAT_AGE,
	GAVE_UP_TTL = GAVE_UP_TTL,
	processReceipt = wired("processReceipt", processReceipt),
	passHandlers = wired("passHandlers", function()
		return passHandlers
	end),
	productHandlers = wired("productHandlers", function()
		return productHandlers
	end),
	drain = wired("drain", drain),
	inFlight = wired("inFlight", function(): number
		return inFlight
	end),
	-- Replaces the clock's now/wait/delay with the given ones (missing ones are the real ones); `nil` puts the real
	-- clock back.
	setClock = wired(
		"setClock",
		function(fake: { now: (() -> number)?, wait: ((number) -> ())?, delay: ((number, () -> ()) -> ())? }?)
			clock.now = (fake and fake.now) or realClock.now
			clock.wait = (fake and fake.wait) or realClock.wait
			clock.delay = (fake and fake.delay) or realClock.delay
		end
	),
	-- Replaces where warnings go; `nil` puts the real warn back.
	setWarn = wired("setWarn", function(fakeWarn: ((string) -> ())?)
		log.warn = fakeWarn or realWarn
	end),
	-- A copy of the block on `receiptKey` ({status, token, at}), if any, and a reset for specs.
	gaveUp = wired("gaveUp", function(receiptKey: string): GaveUp?
		local entry = gaveUp[receiptKey]
		return if entry then table.clone(entry) else nil
	end),
	clearGaveUp = wired("clearGaveUp", function()
		table.clear(gaveUp)
	end),
})

MarketplaceService.ProcessReceipt = function(receipt)
	local key = keyFor(Products.Products, receipt.ProductId)
	local handler = if key then productHandlers[key] else nil
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local store = getHistory()
	local processingKey = `{receipt.PlayerId}_{receipt.PurchaseId}`
	if not handler or not player or not store or processing[processingKey] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	processing[processingKey] = true
	local ok, decision = pcall(processReceipt, receipt, store, handler, player)
	processing[processingKey] = nil
	if not ok then
		log.warn(`[Monetization] couldn't process purchase {receipt.PurchaseId}: {decision}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return decision
end

return Monetization

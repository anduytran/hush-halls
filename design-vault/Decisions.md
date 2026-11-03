# Decisions

Newest first. One entry per decision: what, why, alternatives considered.

## 2026-11-03 — Sprint 23: spawn timeout drops the player
- **A player whose spawn outlasts SPAWN_TIMEOUT (10 s) is removed from that round and spectates**, so one stuck load can't hold the round or drop someone at Start mid-round. Alternative considered: let the late spawn join the running round; rejected as it gives a head start into an already-moving round and a spec showed it could hang the start.

## 2026-11-03 — Sprint 22: test players out of RoundService
- **Fake players live in a separate Studio-only `RoundTestPlayers` module**, plugged into RoundService through a swappable `PlayerSource`; supersedes sprint 21's `_test.addFakePlayer` inside RoundService. Keeps test code out of the production module. Specs detect warnings through a `report()` hook instead of matching log text. Alternative considered: keeping fakes in `_test`; rejected as it bloats the live module.

## 2026-11-03 — Sprint 21: fake players for multi-player specs
- **Multi-player round specs use Studio-only fake players inside RoundService** (`_test.addFakePlayer`), since a Studio play-test has one real player. RoundService reads players through one `getPlayers()` helper so fakes go through the real loop. Alternative considered: Studio's multi-client test server; rejected as it can't run unattended. Known gap: Monster and NoiseService don't see fakes, so a real multi-player playtest is still needed.

## 2026-11-03 — Sprint 20: round smoke test timing
- **Phase lengths can be shortened only from Studio specs** (`RoundService._test.setDurations`, min 0.5 s, errors outside Studio), so a full round can be tested in seconds without touching live numbers. Alternative considered: a shorter-round config flag; rejected because it could leak into a live server.

## 2026-11-03 — Sprint 19: HUD sprint-key ownership
- **Only one mounted HUD owns the global `HushSprint` Shift binding; when it is destroyed, the next live HUD takes it over.** This stops a spec's (or a second) HUD from stealing or removing the player's sprint key. Alternative considered: unique action names per HUD; rejected because two bindings on Shift would both fire.

## 2026-11-03 — Sprint 18: goal line review fixes
- **The goal line gets its own panel under RoundInfo, capped to RoundInfo's width (160–360 px)** so it stays in the top-centre column clear of Coins/Shop on a 375 px phone. Screens under ~370 px aren't a target today. Alternative considered: keeping it as a child line inside RoundInfo; rejected because wrapped text overflowed and crowded the right column.

## 2026-11-03 — Sprint 17: HUD goal line
- **The goal is shown as a line under the round timer** (child of RoundInfo) so new players know to reach the EXIT and that sprinting is loud, without moving other HUD elements. Alternative considered: a one-time tutorial popup; rejected as it's easy to miss and adds a screen.

## 2026-11-03 — Sprint 16: hearing follow-ups
- **Monster test hooks are Studio-only** (`Monster._test`), like RoundService, replacing sprint 15's public `Monster.isHeard`.
- **Kept the 12–14 studs/s band on purpose**: heard, but ranked like a walker so the monster drifts toward you instead of chasing first.

## 2026-11-03 — Sprint 15: walking is silent
- **Raised the monster's hearing limit to 12 studs/s** (walk is 10, sprint 24), so walking is silent and only sprinting draws the monster. Fits the "sprinting is loud, walking is quiet" rule. Alternative considered: lower walk speed below 8 so walkers stay faintly audible; rejected as it slows every round.

## 2026-11-03 — Sprint 14: VIP 2x coins
- **Built the advertised VIP 2x coins** rather than changing the pass description. The VIP grant sets a `CoinMultiplier = 2` attribute; RoundService's `addCoins` multiplies by it. Only the escape reward exists today, so VIP escape pays 20.
- **Bad multiplier values count as 1**, so a broken attribute can never lower or blow up a payout.

## 2026-11-03 — Sprint 13: receipt follow-ups
- **Test hooks exist only in Studio** and start off there; live servers never have `_test`. Replaces sprint 12's always-present locked hooks.
- **Expired regrant blocks are pruned** on every receipt and new block, so the table can't grow forever.
- **Accepted known limit:** past the 30 min heartbeat cap, a receipt can be granted twice once its marker goes stale or its block expires. Closing it needs a never-stale "maybe given" status; deferred.

## 2026-11-03 — Sprint 12: receipt follow-ups
- **Only a given-up "done" write blocks regrants**, and the block expires 24 h + 30 min later. A released give-up can be bought again. Replaces sprint 11's block on any give-up for the server's lifetime.
- **One 30 min heartbeat window per attempt**, shared by the grant and result-write retries.
- **Test hooks always exist but are locked** unless Studio or `_test.enable()`. Replaces sprint 11's Studio-only hooks, which left non-Studio runs untested.

## 2026-11-03 — Sprint 11: receipt follow-ups
- **Heartbeats stop after 30 min** (MAX_HEARTBEAT_AGE), replacing sprint 10's "busy forever" cost. Accepted cost: a handler yielding over 30 min + 24 h may be granted twice.
- **No-time markers are restamped once only**, so a marker can't be extended forever.
- **A server that gave up writing a receipt's result never grants it again** (answers NotProcessedYet).
- **Test hooks exist only in Studio**, so live servers never expose them.

## 2026-11-03 — Sprint 10: receipt follow-ups
- **Live attempts heartbeat their pending marker every 60 s**, so the 24 h stale rule only frees markers left by dead servers. Accepted cost: a grant handler that never returns keeps its receipt busy for good.
- **A pending marker with no time is busy**, not released; the reserve restamps it so it can go stale a day later.
- **BindToClose drain lowered to 20 s** (from 25), well inside Roblox's 30 s limit.

## 2026-11-03 — Sprint 9: receipt follow-ups
- **Pending markers go stale after 24 h** and count as released. Eases sprint 8's stuck-forever cost; a day is far beyond any live attempt. Accepted cost: a yielding grant whose done write never lands may be granted twice a day later.
- **Background writes capped at 10 tries**, and BindToClose drains in-flight work for up to 25 s.
- **A failed reserve releases only after reading back our own token**, not blindly.

## 2026-11-03 — Sprint 8: receipts without takeover
- **Stale pending markers are never taken over.** Only the attempt holding the marker's token can replace it, which closes the double-grant gap for good. Replaces sprint 7's 180 s window. Cost accepted: a server that dies mid-purchase leaves that purchase stuck pending until fixed by hand in the DataStore.
- **Refused or failed grants write a `released` marker** instead of deleting the key, so a stale attempt can't race a delete.
- **Late results are always recorded**: a background loop retries the done/released write with backoff (0.5 s doubling to 30 s) until it succeeds.

## 2026-11-03 — Sprint 7: reviewer follow-ups
- **A yielding grant handler is not cancelled.** Cancelling could double-grant or leave half-done effects. The receipt answers NotProcessedYet and keeps its marker; a late success is marked done. Handlers still must not yield. Replaces sprint 6's cancel.
- **Stale-takeover window lowered to 180 s** (from 600 s), so a purchase whose server died is retried sooner.
- **Teleport-sized steps are dropped and hold the previous reading.** Reviewer rule: a long step must read neither as a sprint nor as 0. Replaces sprint 6's clamp.
- **No test-only branch in `RoundService.start()`**; tests force failures through the `_test.beforeStep` hook.

## 2026-11-03 — Sprint 6: reviewer follow-ups
- **Grant handlers must not yield.** The grant runs synchronously right after the token check; a handler that yields is stopped and counts as failed. This closes sprint 5's accepted double-grant gap.
- **Stale-takeover window raised to 600 s** (from 120 s). A live attempt now only holds the marker across two DataStore calls, so a wide margin costs little.
- **Teleport-sized steps are clamped to sprint speed again**, entry kept. Sprint 5's reset to 0 let a sprinter go silent by teleporting.
- **`RoundService.start()` runs each setup step in its own pcall** so the error names the step that failed.

## 2026-11-03 — Sprint 5: reviewer follow-ups
- **Receipt markers carry a per-attempt token.** Grant only when the store holds our token; mark done only over our own marker. Accepted limit: a handler yielding past 120 s while another server takes over can still double-grant, since grant and done-write can't be atomic.
- **Teleport-sized steps reset the speed reading to 0** (like a respawn), replacing sprint 4's cap at sprint speed. Reviewer's call.
- **A started system is never restarted** by main.server's retry loop; a failed `RoundService.start()` tears down what it set up.
- **RoundService test hooks grouped under `_test`** so they can't be mistaken for the public API.

## 2026-11-03 — Sprint 4: reviewer follow-ups
- **Receipt grants run outside `UpdateAsync`.** UpdateAsync can re-run its callback, which could grant twice, and grant handlers may yield. Now: reserve (pending) → grant → mark done. This replaces sprint 3's single-UpdateAsync flow.
- **Stale pending markers (over 120 s) are taken over.** This is safe only while Coins aren't saved; revisit if purchases ever persist.
- **Failed system starts are retried** (5 s apart, 5 tries) instead of being given up after one warning.
- **Teleport-sized steps are capped at sprint speed, not dropped.** Dropping them left a silent gap.

## 2026-11-03 — Sprint 3: reviewer follow-ups
- **One shared `SpeedSampler` for Monster and NoiseService.** It averages speed over about 0.5 s and skips samples under 0.1 s apart. The alternative was each system keeping its own deltas, which could disagree and read walkers as sprinting.
- **Teleport filter is per step (over 40 studs), not per speed (over 60 studs/s).** The old rule zeroed real sprinters.
- **Receipts are checked, granted and recorded in one `UpdateAsync`.** This replaces sprint 2's grant-then-record, which had a gap between the check and the write.
- **A broken HallBuilder only warns.** The systems and purchase handlers still start.

## 2026-11-03 — Sprint 2: round wiring
- **`InRound` player attribute is the single "who's playing" flag.** RoundService sets it; Monster and NoiseService ignore anyone without it. The alternative was each system tracking participants itself.
- **Movement speed for hearing and noise comes from server position deltas**, sampled every 0.2 s, not `AssemblyLinearVelocity` (client-owned, so spoofable). Deltas over 60 studs/s count as teleports and are ignored.
- **main.server builds the hall once, then starts the systems in order.** This replaces the sprint 1 parallel-thread start, since nothing waits on anything else now.
- **Receipts: grant first, then record.** If recording fails after a grant it still returns PurchaseGranted, so nothing is granted twice.

## 2026-11-03 — Sprint 1 build choices
- **Shared state is attributes on `ReplicatedStorage.State`** (WaterLevel, Noise, RoundState, TimeLeft), set up by `GameState.luau`. The server writes them and clients only read. This let the six pieces be built in parallel against one contract. The alternative was one RemoteEvent per value.
- **Each server system starts in its own protected thread, before Monetization loads.** Monster waits for the hall that RoundService builds, so starting them one after another would hang. Monetization errors in an unpublished place, so it loads last and can't stop the game systems.
- **Only players present when a round starts take part.** Anyone who joins mid-round waits for the next one. Simpler and fairer than letting late joiners drop in.
- **Sprint "release" is never rate-limited.** That way a player can't get stuck sprinting.
- **Purchases are cosmetic or coins only** (Neon Trail, VIP tag + 2x coins, 100 Coins). Nothing sold changes noise, speed or the monster, per CLAUDE.md.

## 2026-11-03 — Vault created
Started a design vault so agents and people share one source of truth for the game.

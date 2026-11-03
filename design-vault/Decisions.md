# Decisions

Newest first. One entry per decision: what, why, alternatives considered.

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

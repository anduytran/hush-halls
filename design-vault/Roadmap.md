# Roadmap

## Now: Milestone 1 — Ship v1 (see [[Ship Checklist]])
Sprint 1 (2026-11-03): all six pieces merged. Only the hall map has run in Studio so far.
- [x] Greybox hall map (Start, Exit, Floor): `src/server/Map/HallBuilder.luau`. Built and QA-checked in Studio.
- [x] [[Mechanics/Sprint Noise and Water]]: `src/server/NoiseService.luau`, `src/shared/GameState.luau`
- [x] [[Mechanics/Blind Monster]]: `src/server/Monster.luau`
- [x] [[Mechanics/Round Loop]]: `src/server/RoundService.luau`
- [x] [[Mechanics/Products and Grants]]: `src/shared/Products.luau`, `src/server/main.server.luau`
- [x] HUD + Shop menu: `src/client/UI/Hud.luau`, `src/client/UI/ShopMenu.luau` (spec in ui-vault)

Sprint 2 (2026-11-03): round loop wired end to end and reviewer blockers fixed (merged; checks pass, not run in Studio).
- [x] Startup order: `main.server.luau` builds the hall, then starts NoiseService, Monster, RoundService.
- [x] `InRound` player attribute: only round participants make noise, drown, or can be heard and killed. Spectators wait on the lobby platform.
- [x] Monster and noise use server-side position deltas (not client velocity); teleports ignored. Monster is idle and parked outside Running.
- [x] Round spawn retries LoadCharacter; stale Died handlers from earlier rounds ignored.
- [x] Monetization: lazy DataStore, grant-then-record receipts with no double grants.
- [x] Cloud specs added: `Monster.cloud.spec.luau`, `RoundService.cloud.spec.luau` (not run yet).

Sprint 3 (2026-11-03): six reviewer follow-ups on the round loop fixed (merged; checks pass, not run in Studio).
- [x] Receipts: check, grant and record happen in one `UpdateAsync` on the receipt key (`Monetization.luau`).
- [x] New `src/server/SpeedSampler.luau` (+ spec): speed averaged over about 0.5 s, shared by Monster and NoiseService, so a walker's uneven network updates don't read as sprinting.
- [x] Teleport filter only skips a single step over 40 studs (`SpeedSampler.MAX_STEP`), so sprinters stay audible.
- [x] Monster waits for the hall in its own task; `start()` returns straight away.
- [x] Players who join while a round is spawning are handled as spectators (`RoundService.luau`).
- [x] `main.server.luau`: requiring and building the hall are both in the pcall, so a broken HallBuilder only warns.
- [x] `RoundService.cloud.spec.luau`: each test starts from fresh round state.

Sprint 4 (2026-11-03): reviewer follow-ups (merged; checks pass, not run in a live round).
- [x] Receipts: `UpdateAsync` only reserves a pending marker; the grant runs outside it, then a second `UpdateAsync` marks it done. Failed grant drops the marker (NotProcessedYet). Stale pending markers (over 120 s) are taken over. New `Monetization.cloud.spec.luau` with a fake store.
- [x] `main.server.luau`: a system whose `start()` errors is retried every 5 s, up to 5 times.
- [x] Monster warns every 30 s while it waits for the hall, instead of once.
- [x] `RoundService.stop()` does nothing unless started (test-only).
- [x] SpeedSampler: a single step over 40 studs is kept but capped at sprint speed, so there's no silent gap. (Replaced in sprint 5.)

Sprint 5 (2026-11-03): five sprint-4 reviewer follow-ups (merged; checks pass, not run in a live round).
- [x] Receipts: each attempt's pending marker carries its own token; it grants only if the store holds that token, and marks done only over its own marker. Known limit: a handler that yields past 120 s while another server takes over can still double-grant.
- [x] `main.server.luau`: a system that started once is never started again by the retry loop.
- [x] `RoundService`: a failed `start()` undoes what it set up; `stop()` also clears the platform. Test hooks moved into `RoundService._test`.
- [x] SpeedSampler: a single step over 40 studs now resets the player's entry (reading 0, like a respawn) instead of being capped. (Replaced in sprint 6.)
- [x] Specs updated: `Monetization.cloud.spec.luau`, `RoundService.cloud.spec.luau`, `SpeedSampler.spec.luau`.

Sprint 6 (2026-11-03): five sprint-5 reviewer follow-ups (merged; scripter reports checks pass, not run in a live round).
- [x] Receipts: the grant handler runs synchronously right after the token check; a handler that yields is stopped and counts as failed. Stale-takeover window raised from 120 s to 600 s. This closes sprint 5's known double-grant gap.
- [x] SpeedSampler: a step over 40 studs is clamped to sprint speed and the entry kept, so a sprinter can't go silent by teleporting (reverses sprint 5's reset to 0).
- [x] `RoundService.start()`: each setup step runs in its own pcall; the error names the failing step, with the same rollback.
- [x] `RoundService.cloud.spec.luau`: every test starts from fresh state and cleans up after itself.
- [x] Specs updated for all three files.

Sprint 7 (2026-11-03): six sprint-6 reviewer follow-ups (merged; scripter reports checks pass, not run in a live round).
- [x] Receipts: a grant handler that yields is no longer stopped (replaces sprint 6's cancel). The receipt answers NotProcessedYet and keeps its pending marker; if the handler later returns true it is marked done. Stale-takeover window lowered from 600 s to 180 s.
- [x] SpeedSampler: a step over 40 studs is dropped. The sample keeps the previous average and the baseline moves to the new spot (replaces sprint 6's clamp to sprint speed).
- [x] `RoundService.start()`: no test-only branch; the `_test.beforeStep` hook does the forced failures. `onPlayerAdded` and `spawnAtStart` now sit inside their steps' pcall and rollback.
- [x] `RoundService.cloud.spec.luau`: skips itself during a live round, and detaches/restores the real lobby platform instead of destroying it.
- [x] Specs updated for all three files.

Sprint 8 (2026-11-03): receipts, no takeover (merged; scripter reports checks pass, not run in a live round).
- [x] Receipts: stale-pending takeover removed; any pending marker is busy until its owner (same token) replaces it. Refused/failed grants write a `released` marker that can be reserved again (no more RemoveAsync). Late handler results and failed done-writes are retried in the background until recorded. Known cost: a server dying mid-purchase leaves it stuck pending (manual DataStore fix).
- [x] `Monetization.cloud.spec.luau` updated.

Sprint 9 (2026-11-03): five sprint-8 reviewer follow-ups on receipts (merged; scripter reports checks pass, not run in a live round).
- [x] A pending marker over 24 h old (or with no time) counts as released, so a purchase whose server died recovers after a day instead of needing a manual fix.
- [x] Background writes give up after 10 tries; a failed reserve releases only if the stored marker holds our token; BindToClose waits up to 25 s for in-flight writes and late grants.
- [x] `Monetization.cloud.spec.luau` runs on a fake clock. Known cost: a yielding grant whose done write never lands can be granted again after 24 h.

Sprint 10 (2026-11-03): sprint-9 reviewer follow-ups on receipts (merged; scripter reports checks pass, not run in a live round).
- [x] A live attempt heartbeats its pending marker's time every 60 s (while a yielding grant runs and while results are retried), so only markers from dead servers go stale. Heartbeat can't undo done/released.
- [x] A pending marker with no time now counts as busy and is restamped by the reserve.
- [x] BindToClose waits 20 s (was 25). Warnings name the receipt key and go through a hookable logger.
- [x] `Monetization.cloud.spec.luau` gained a fake timer (`advance`) and warn capture. Known cost: a handler that never returns keeps its receipt busy forever.

Sprint 11 (2026-11-03): sprint-10 reviewer follow-ups on receipts (merged; scripter reports checks pass, not run in a live round).
- [x] A heartbeat stops (one warning) after 30 min, so a handler that never returns lets its marker go stale like a dead server's. Known cost: a handler yielding over 30 min + 24 h can be granted twice.
- [x] A marker with no time is restamped only once; after that it is just busy.
- [x] A receipt whose result write was given up on is never granted again by that server.
- [x] Test hooks (`_processReceipt`, `_test`) exist only in Studio. Outside Studio the spec only checks the hooks are absent.

Sprint 12 (2026-11-03): sprint-11 reviewer follow-ups on receipts (merged; scripter reports all 54 spec tests pass in Studio, not run in a live round).
- [x] Each try is one `Attempt`; the 30 min heartbeat window is shared by the grant and the result-write retries, with one stop warning per attempt.
- [x] Only a given-up "done" blocks regrants; a released give-up clears the block. Blocks expire after 24 h + 30 min.
- [x] `Monetization._test` always exists but is frozen and errors unless enabled (Studio, or `_test.enable()`), so the spec really tests receipts outside Studio too. Old `_processReceipt`/`_RETRY_FIRST` hooks removed.

Sprint 13 (2026-11-03): sprint-12 reviewer follow-ups on receipts (merged; scripter reports all 59 spec tests pass in a Studio playtest, not run in a live round).
- [x] `Monetization._test` exists only in Studio and starts off; `enable()`/`disable()` toggle it, and the spec restores the state per test.
- [x] Expired regrant blocks are pruned on every receipt and every new block.
- [x] Spec write failures now fail inside the real UpdateAsync (nothing written, then throws).
- Known limit (documented in code): after the 30 min heartbeat cap, a receipt can still be granted twice once its marker goes stale or the block expires.

Sprint 14 (2026-11-03): VIP 2x coins on escape (merged; new spec in `RoundService.cloud.spec.luau`, not run in a live round).
- [x] Escape pays 10 × the player's `CoinMultiplier` attribute (VIP pass sets 2 → 20 coins); a missing or bad value (non-number, NaN, < 1, infinite) counts as 1.

## Needs a playtest
- VIP escape pays 20 coins, non-VIP 10 (sprint 14; needs a VIP pass ID to test the real grant).
None of these have run in a live round yet. Studio wasn't reachable in sprints 1–11; sprints 12–13 receipt specs ran in Studio (54, then 59 pass) but not in a live round.
- Buy a product in a published place and check sprint 13: hooks absent on a live server, expired blocks pruned.
- Buy a product in a published place and check the receipt flow (sprint 12: shared heartbeat window, done-only regrant block).
- Run `Monetization.cloud.spec.luau` in Studio (sprint 11: 30 min heartbeat cap, one-time restamp, no regrant after give-up, hooks absent outside Studio).
- Run `Monetization.cloud.spec.luau` (sprint 10: heartbeat, no-time restamp, 20 s drain, warn text).
- Run `Monetization.cloud.spec.luau` (sprint 9: 24 h stale rule, retry cap, token-checked release, shutdown drain).
- Run `SpeedSampler.spec.luau` (sprint 7: teleports hold the previous reading).
- Run `RoundService.cloud.spec.luau`: forced failure in each start step rolls back cleanly.
- Check a failed RoundService start retries cleanly and a started system isn't restarted.
- Run `SpeedSampler.spec.luau`; check that walkers stay quiet and sprinters are heard.
- Full round end to end: spectators on the platform, InRound cleared on death/escape/Ended, monster parks between rounds.
- Run the two `.cloud.spec.luau` files.
- Sprint/noise/water: water rises only while Running, players drown, Sprint remote works from Shift and the touch button.
- Blind monster: hears sprinters, ignores sneakers, kills only during Running.
- Round loop: Lobby 15 s → Running 120 s → Ended 5 s; escaping pays +10 coins once.
- HUD and shop: bars, timer and coins update; shop opens the purchase prompts.
- Pass grants: Neon Trail and VIP tag on spawn, Coins100 adds coins.

## Blocked
- Purchases: every ID in `src/shared/Products.luau` is 0. The passes and the product must be created in the Creator Hub and their IDs pasted in before they can be sold.
- Monetization now opens its DataStore lazily, so it no longer breaks startup, but receipts still can't be tested in an unpublished Studio place. A full test needs the place published with API access turned on.

## Next
- Fix the walk/hearing mismatch (see [[Mechanics/Blind Monster]], open questions).
- Write the sprint 1 numbers into [[Balance]].
- Milestone 2 — Feel: footstep sounds, monster audio, water VFX, camera shake, proper hall art.

## Later
- Milestone 3 — Depth: multiple halls, hazards (puddles, loose planks), daily rewards, leaderboards.
- Milestone 4 — Social: team rounds, spectating, trails shop expansion.

---
status: in-progress   # wired end to end in sprint 2; reviewer fixes in sprints 3–7 (start retries, stop() guard, failed-start teardown, no restarts, per-step start errors, all setup inside the step pcalls); sprint 20 full-round smoke spec passes in a Studio play-test, not played in a live round
tags: [design, mechanic]
---
# Round loop

## What it does
Players wait in a lobby above Start, then run the hall. Reaching the Exit escapes and pays coins.

## Rules and numbers
Lobby 15 s (it waits while the server is empty), Running up to 120 s, Ended 5 s. Escaping pays +10 Coins (`leaderstats.Coins`).

## Acceptance criteria
- [ ] RoundState and TimeLeft step through Lobby → Running → Ended.
- [ ] Touching the Exit during Running pays +10 coins once and returns the player to the lobby platform.
- [ ] Players who join mid-round sit out until the next round.

## Implementation
- Files: `src/server/RoundService.luau`, `src/server/Map/HallBuilder.luau`
- Sprint 20: Studio-only `RoundService._test.setDurations(lobby, running, ended)` (each >= 0.5 s), `resetDurations()`, `durations()` let specs run a short full round. `RoundService.cloud.spec.luau` has an end-to-end smoke test; all 17 RoundService tests passed in a one-player Studio play-test (main.server disabled during the run). Live defaults unchanged (15/120/5).

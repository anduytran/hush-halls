---
status: in-progress   # wired end to end in sprint 2; reviewer fixes in sprints 3–5 (start retries, stop() guard, failed-start teardown, no restarts), not playtested
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

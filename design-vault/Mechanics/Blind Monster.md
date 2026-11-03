---
status: in-progress   # round-scoped + server-side hearing in sprint 2; averaged SpeedSampler in sprint 3; repeating hall-wait warning in sprint 4, not playtested; walking silent (hearing limit 12) in sprint 15; Studio-only test hooks and 12–14 band documented in sprint 16 (spec 6/6 in Studio), not playtested
tags: [design, mechanic]
---
# Blind monster

## What it does
The monster can't see. It hunts the loudest player it can hear, and it touches to kill.

## Rules and numbers
Hearing range 150 studs. Below 12 studs/s a player is silent (so walking at 10 is silent); above 14 counts as sprinting and wins over walkers. Chase speed = 4 + Noise × 14. When it hears nothing it drifts at 2 studs/s to the last spot it heard. Between rounds it waits out of range and re-enters at Hall.Exit.

## Acceptance criteria
- [ ] It chases a sprinting player and ignores one who is sneaking.
- [ ] It kills only player characters, and only while RoundState is Running.
- [ ] It re-enters from the exit end when a round starts.

## Implementation
- Files: `src/server/Monster.luau`, `src/server/Monster.cloud.spec.luau`

## Open questions
- ~~Walk vs hearing mismatch~~: decided in sprint 15, walking is silent (limit raised to 12). See [[Decisions]].

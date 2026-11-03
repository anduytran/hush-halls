---
status: in-progress   # round-scoped + server-side hearing in sprint 2, not playtested
tags: [design, mechanic]
---
# Blind monster

## What it does
The monster can't see. It hunts the loudest player it can hear, and it touches to kill.

## Rules and numbers
Hearing range 150 studs. Below 8 studs/s a player is silent; above 14 counts as sprinting and wins over walkers. Chase speed = 4 + Noise × 14. When it hears nothing it drifts at 2 studs/s to the last spot it heard. Between rounds it waits out of range and re-enters at Hall.Exit.

## Acceptance criteria
- [ ] It chases a sprinting player and ignores one who is sneaking.
- [ ] It kills only player characters, and only while RoundState is Running.
- [ ] It re-enters from the exit end when a round starts.

## Implementation
- Files: `src/server/Monster.luau`, `src/server/Monster.cloud.spec.luau`

## Open questions
- Walk speed is 10, which is above the monster's "silent" limit of 8, so walking players can be heard. Should walking be silent (raise the limit) or quiet but audible (lower the walk speed)? To decide at the first playtest.

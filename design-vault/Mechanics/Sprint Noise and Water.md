---
status: in-progress   # InRound-only noise/drowning in sprint 2, not playtested
tags: [design, mechanic]
---
# Sprint, noise and water

## What it does
Hold Shift (or the touch button) to sprint. Sprinting is loud and walking is quiet. The water rises during the run, and a player left underwater drowns.

## Rules and numbers
Walk 10, sprint 24 studs/s. Water rises 0.6 studs/s while Running and resets when a round starts. Drowning takes 2 s underwater. Sprint events are limited to 10/s per player. Not yet copied into [[Balance]].

## Acceptance criteria
- [ ] Holding Shift or the touch button sprints; letting go goes back to walking.
- [ ] State.Noise is about 0 standing still, about 0.1 walking, about 1 sprinting.
- [ ] The water rises only while RoundState is Running and is back at 0 when a new round starts.
- [ ] A player underwater for 2 s dies.

## Implementation
- Files: `src/server/NoiseService.luau`, `src/shared/GameState.luau`, client input in `src/client/UI/Hud.luau`
- Remotes: `Remotes.Sprint` (bool, rate-limited on `true` only)

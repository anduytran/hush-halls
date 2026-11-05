---
status: in-progress   # sprint 34
tags: [design, mechanic]
---
# Hazards and hall layouts

## What it does
Each round picks one of three hall layouts (different obstacle placement). Halls contain **puddles** (stepping in one splashes: a short noise spike) and **loose planks** (creak when stepped on: a smaller spike). Players have to watch their feet, not just their speed.

## Why
Depth and replay value: rounds stop feeling identical, and sneaking becomes a route-reading skill, not just "hold walk".

## Rules and numbers
See [[Balance]]: puddle splash 0.8 noise for 0.6 s, plank creak 0.4 noise for 0.4 s, each hazard cools down 1 s per player.

## Acceptance criteria
- [ ] A new round picks a layout (1–3) and rebuilds the obstacles and hazards; Start and Exit stay put.
- [ ] Each layout has 4–6 puddles and 4–6 planks, and a walkable route from Start to Exit.
- [ ] Stepping in a puddle raises that player's noise to 0.8 for 0.6 s and plays a splash; the monster can hear it.
- [ ] Stepping on a plank raises noise to 0.4 for 0.4 s and plays a creak.
- [ ] Hazards only make noise for players who are InRound and alive.
- [ ] No errors in Output over several rounds.

## Implementation
- Files: `src/server/Map/HallBuilder.luau` (layouts, tagged parts), `src/server/Hazards.luau` (behaviour), `src/server/NoiseService.luau` (`addNoise`), `src/server/RoundService.luau` (rebuild per round)

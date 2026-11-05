---
status: in-progress   # sprint 35
tags: [design, mechanic, map]
---
# Map overhaul: the flooded school

## What it does
The grey concrete corridor becomes a **flooded, abandoned school at night**: tiled floor, peeling plaster walls with wood panelling, a ceiling, rows of lockers, classroom doorways with small dark rooms behind them, flickering ceiling lamps, and a green-lit EXIT double door at the far end. Teal fog and a murky water surface.

## Why
Pillar: atmosphere sells a sound-horror game. It also sets us apart from DONT SPLASH, whose look is pool rooms (see [[Decisions]], sprint 34). The layout, the 300-stud route and the balance stay the same, so the tuning in [[Balance]] still holds.

## Rules
- Keep the contracts: `Hall` model with `Floor` (top at Y=0), `Start`, `Exit`, `Walls`, `Obstacles`, `Hazards`; `buildLayout(1..3)`; the same footprint and turn openings, so the monster and round code don't change.
- Lockers and props stay out of the 12-stud walking gap; classroom alcoves are side areas, not shortcuts.
- Lights: dim, cold; about 1 in 4 lamps flickers.

## Acceptance criteria
- [ ] The hall reads as a school: tiled floor, panelled walls, ceiling, lockers, at least 4 classroom doorways, lamps every ~25 studs.
- [ ] The exit is a double door with a glowing green EXIT sign; the Exit trigger still ends the run.
- [ ] Lighting is dark with teal fog, but the route is visible on a phone at default brightness.
- [ ] The water looks murky teal, not a plain blue block.
- [ ] All three layouts still build, rounds start and end, the monster still catches, and the puddles and planks still work.
- [ ] No errors in Output; checks pass.

## Implementation
- Files: `src/server/Map/Props.luau` (prop builders), `src/server/Map/Atmosphere.luau` (lighting, flicker), `src/server/Map/HallBuilder.luau` (shell + dressing), the water look in `src/server/NoiseService.luau` `createWater`

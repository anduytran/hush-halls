---
status: in-progress   # sprint 36
tags: [design, mechanic]
---
# Routes, exits and dread

## What it does
- **Routes:** the school branches. A main corridor and a parallel back corridor are joined by two cross halls and by classrooms with doors on both sides, so there are at least 3 distinct paths from Start.
- **Exits:** three ways out: the **main EXIT** double doors (far end), a **gym fire exit** off one side and a **broken window** in a classroom. Each one escapes you (+10 coins, as before). Shortest paths to each are 250–330 studs, so the water and monster balance holds.
- **Scarier monster:** a tall, gaunt, eyeless creature (not a cube). It follows corridors (no going through walls), stops to **listen** (2 s, head tilted) when it loses you, and **lunges** (speed burst) when within 15 studs of a heard player.
- **Dread (client):** as the monster gets closer, the screen vignettes, the camera trembles and the FOV tightens slightly. Getting caught shows a short jumpscare (its face and the scream, about 0.7 s). The goal line says "Find an exit".

## Why
Choosing a route against a monster you can hear is the core decision; dread sells the horror. Research (sprint 34): Roblox horror hits win on atmosphere.

## Rules and numbers
In [[Balance]]: listen pause 2 s, lunge range 15 studs, lunge speed +8, dread starts at 50 studs.

## Acceptance criteria
- [ ] At least 3 different paths from Start, and 3 exits; touching any exit while Running escapes once (+10 coins).
- [ ] The monster never passes through walls; it reaches players by paths through doorways and halls.
- [ ] When the monster loses its target it stops about 2 s at the last heard spot before drifting.
- [ ] Within 15 studs of a heard player it speeds up visibly.
- [ ] Vignette/shake rise smoothly from 50 studs; a catch shows the jumpscare once; no effects linger after respawn.
- [ ] All 3 layouts, hazards and round flow still work; no Output errors; part count under 2,000.

## Status (sprint 36)
Built. Checks pass.
- Seen in a server playtest: patrol, chase through a cross-hall doorway, lunge (speed about 26), the 2 s pause, all 3 exits paying once (fire exit tested), and part counts of 1,857–1,900.
- Not yet checked by hand: the dread vignette, shake and jumpscare on a real client, a real catch (the test player was anchored), and a scream with the jumpscare (not built).
- Added beyond the brief: when it hears nothing, the monster patrols at drift speed through the main hall, back corridor and gym instead of standing still.

## Implementation
- Files: `src/server/Map/HallBuilder.luau`, `src/server/RoundService.luau` (exits), `src/server/Monster.luau` (PathfindingService, listen, lunge), `src/server/Map/MonsterModel.luau` (visual), `src/client/Dread.luau` + `src/client/UI/Hud.luau`
- Contract: `Hall.Exit` stays as the main exit; extra exits are BaseParts in the `Hall.Exits` folder. The monster's collision part is still `Hall.Monster`.

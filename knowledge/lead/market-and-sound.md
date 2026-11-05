# Market position and sound

- Competitor: DONT SPLASH (Bacon Theory, live 2026-10-17, ~99K concurrent players in Nov 2026). It's a 9-stage obby with a blind monster hunting splashes. We stand apart through the rising water and short, repeatable rounds.
- Sound lives in `src/client/Audio.luau` (footsteps, heartbeat, water ambience) and `src/server/Monster.luau` (growl, scream). Hazard sounds are in `src/server/Hazards.luau`.
- The monster targets by speed, not by `State.Noise`. Hazard noise reaches it through `NoiseService.noiseFloor` in `findLoudest`.
- Layouts: `HallBuilder.buildLayout(i)` is picked at random in RoundService each round. Hazard parts are tagged "Puddle"/"Plank".
- `rbxassetid://203785492` warnings in Output aren't from `src/`.

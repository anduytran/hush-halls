# Market position and sound

- Competitor: DONT SPLASH (Bacon Theory, live 2026-10-17, ~99K concurrent players in Nov 2026). It's a 9-stage obby with a blind monster hunting splashes. We stand apart through the rising water and short, repeatable rounds.
- Sound lives in `src/client/Audio.luau` (footsteps, heartbeat, water ambience) and `src/server/Monster.luau` (growl, scream). Hazard sounds are in `src/server/Hazards.luau`.
- The monster targets by speed, not by `State.Noise`. Hazard noise reaches it through `NoiseService.noiseFloor` in `findLoudest`.
- Layouts: `HallBuilder.buildLayout(i)` is picked at random in RoundService each round. Hazard parts are tagged "Puddle"/"Plank".
- Sprint 36 map: back corridor x -40..-28, gym x -70..-42 z 216..262. Extra exits are BaseParts in `Hall.Exits`; `Hall.Exit` is still the main one, used for the monster's park and entry. The monster visual is `MonsterModel.attach(root)` (37 parts); its pathfinding agent has radius 3 and height 9, and the narrowest doorway is 8×11. Client dread effects are in `src/client/Dread.luau`.
- The open Studio place has stale duplicate copies of MonsterModel, Props, Atmosphere and Hazards.
- `rbxassetid://203785492` warnings in Output aren't from `src/`.

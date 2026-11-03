# Noise, sprint and water

- `src/shared/GameState.luau` creates `ReplicatedStorage.State` (attributes WaterLevel, Noise, RoundState, TimeLeft) and `ReplicatedStorage.Remotes` on the server; clients just wait for them. Add new remotes to its `REMOTE_EVENTS` list.
- `src/server/NoiseService.luau` owns WalkSpeed (10 walk, 24 sprint), State.Noise (loudest player's speed mapped to 0 / ~0.1 / ~1) and WaterLevel (only rises while RoundState == "Running"; reset to 0 when RoundState changes to "Running").
- WaterLevel is measured in studs above the top of `Workspace.Hall.Floor` (Y=0 with a 200x200 footprint if there is no floor). The water part is `Workspace.Water`, non-colliding.
- The Sprint rate limit only applies to `true`; `false` is always accepted so a player can't get stuck sprinting.
- `main.server.luau` starts NoiseService, Monster and RoundService before requiring Monetization, because Monetization errors on DataStore access in an unpublished Studio place and would stop everything after it.
- Each `start()` runs in its own `task.spawn` + `pcall`: Monster.start() waits for `Workspace.Hall`, which only RoundService.start() builds, so calling them in sequence would deadlock.
- No client sprint input yet: something on the client must fire `Remotes.Sprint` with true/false.

# Noise, sprint and water

- `src/shared/GameState.luau` creates `ReplicatedStorage.State` (attributes WaterLevel, Noise, RoundState, TimeLeft) and `ReplicatedStorage.Remotes` on the server; clients just wait for them. Add new remotes to its `REMOTE_EVENTS` list.
- `src/server/NoiseService.luau` owns WalkSpeed (10 walk, 24 sprint) for everyone. State.Noise is the loudest InRound player's speed (from `SpeedSampler`, see speed-sampler.md), mapped to 0 / ~0.1 / ~1. WaterLevel only rises while Running and resets to 0 on Lobby and on Running.
- Drowning: only InRound players, only while their root is below the water top AND inside Hall.Floor's XZ footprint, for 2s.
- WaterLevel is measured in studs above the top of `Workspace.Hall.Floor` (Y=0 with a 200x200 footprint if there is no floor). The water part is `Workspace.Water`, non-colliding.
- The Sprint rate limit only applies to `true`; `false` is always accepted so a player can't get stuck sprinting.
- The loop function is `step` (not `tick`, which shadows the Roblox global).

# Server startup (main.server.luau)
- HallBuilder is required *inside* the pcall that builds the hall, so a HallBuilder that errors on require only warns and Monetization handlers still get set up.
- NoiseService.start, Monster.start and RoundService.start each run in their own thread (`task.spawn(tryStart, ...)` + pcall), so one that errors or yields (Monster waits for `Workspace.Hall`) can't block the others or the purchase handlers below. A start() that errors is retried every 5 s, up to 5 times; one that succeeded is recorded in `startedSystems` and never started again.
- Monetization opens its DataStore lazily, so requiring it in an unpublished Studio place is safe. Receipt handling is in monetization-receipts.md.

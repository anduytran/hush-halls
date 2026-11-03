# Noise, sprint and water

- `src/shared/GameState.luau` creates `ReplicatedStorage.State` (attributes WaterLevel, Noise, RoundState, TimeLeft) and `ReplicatedStorage.Remotes` on the server; clients just wait for them. Add new remotes to its `REMOTE_EVENTS` list.
- `src/server/NoiseService.luau` owns WalkSpeed (10 walk, 24 sprint) for everyone. State.Noise is the loudest InRound player's speed (from server position deltas per 0.2s step, deltas over 60 studs/s ignored), mapped to 0 / ~0.1 / ~1. WaterLevel only rises while Running and resets to 0 on Lobby and on Running.
- Drowning: only InRound players, only while their root is below the water top AND inside Hall.Floor's XZ footprint, for 2s.
- WaterLevel is measured in studs above the top of `Workspace.Hall.Floor` (Y=0 with a 200x200 footprint if there is no floor). The water part is `Workspace.Water`, non-colliding.
- The Sprint rate limit only applies to `true`; `false` is always accepted so a player can't get stuck sprinting.
- The loop function is `step` (not `tick`, which shadows the Roblox global).

# Server startup (main.server.luau)
- Requires everything up front, builds the hall (`HallBuilder.build()` in a pcall), then calls NoiseService.start, Monster.start and RoundService.start in order, each in a pcall. Every start() returns straight away.
- Monetization opens its DataStore lazily, so requiring it in an unpublished Studio place is safe. ProcessReceipt reads the record with GetAsync, grants outside any DataStore callback (handlers may yield), then records it with UpdateAsync. If recording fails after a grant, it still returns PurchaseGranted so nothing is given twice.

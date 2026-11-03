# Monster (src/server/Monster.luau)

- `Monster.start()` is idempotent; it waits for `ReplicatedStorage.State` and `Workspace.Hall`.
- Hearing: players below 8 studs/s horizontal are silent (sneaking); above 14 counts as sprinting and always beats walkers. Range 150 studs.
- Chase speed 4 + Noise*14; Noise < 0.05 means it drifts at 2 studs/s to the last heard spot.
- Between rounds it parks 200 studs past Hall.Exit (along Start→Exit), which is out of hearing range, so on round start it re-enters at Hall.Exit (fallback: Start + 120 Z).
- Kills only Player characters, only while RoundState == "Running".
- Speed thresholds 8 and 14 are my assumptions; nothing in the design vault defines walk/sneak speeds yet.

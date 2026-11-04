# Monster (src/server/Monster.luau)

- `Monster.start()` is idempotent and returns at once; it waits for `Workspace.Hall` in a task and runs the rest in a pcall.
- Round-scoped: outside Running, CanTouch is false and it has no Touched/Heartbeat connections, and it parks 200 studs past Hall.Exit. On Running it re-enters at Hall.Exit and connects; on any other state it disconnects everything and parks.
- Hearing uses server-side position deltas via `SpeedSampler` (see speed-sampler.md), not `AssemblyLinearVelocity`, which the client controls. A new character (new root) starts at speed 0.
- Only hears and kills players whose `InRound` attribute is true (set by RoundService).
- Thresholds: below 8 studs/s is silent (sneaking); above 14 counts as sprinting and beats walkers. Range 150. Chase speed 4 + Noise*14; when Noise < 0.05 it drifts at 2 to the last heard spot. The speed thresholds are my assumptions, not from the design vault.
- Sprint 29: a player only counts as heard after staying ≥ HEARD_SPEED for `HEAR_CONFIRM` (0.5 s) in a row (`confirmHeard`, `heardSince`). It's cleared when Noise goes quiet, on sample drop and at round end. Why: one brief overspeed from a walker made the monster commit to a drift that killed them (see live-smoke.md). It doesn't help against overspeed that lasts 0.5 s, since SpeedSampler already averages over 0.5 s.

# Monster (src/server/Monster.luau)

- `Monster.start()` is idempotent; it uses `GameState.State` and waits for `Workspace.Hall` (main.server builds the hall before starting anything).
- Round-scoped: outside Running, CanTouch is false and it has no Touched/Heartbeat connections, and it parks 200 studs past Hall.Exit. On Running it re-enters at Hall.Exit and connects; on any other state it disconnects everything and parks.
- Hearing uses server-side position deltas (sampled every 0.2s), not `AssemblyLinearVelocity`, which the client controls. A delta over 60 studs/s counts as a teleport and is ignored. A new character (new root) starts at speed 0.
- Only hears and kills players whose `InRound` attribute is true (set by RoundService).
- Thresholds: below 8 studs/s is silent (sneaking); above 14 counts as sprinting and beats walkers. Range 150. Chase speed 4 + Noise*14; when Noise < 0.05 it drifts at 2 to the last heard spot. The speed thresholds are my assumptions, not from the design vault.

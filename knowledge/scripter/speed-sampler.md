# SpeedSampler (src/server/SpeedSampler.luau)

- Shared by Monster and NoiseService; each makes its own `SpeedSampler.new()` (they sample at different cadences).
- Speed = sum of horizontal deltas / sum of their time over the last 0.5 s. Samples under 0.1 s after the last recorded one are skipped (the baseline doesn't move). One step over 40 studs (teleport/lag spike) resets the entry at the new position: deltas cleared, reading 0, like a respawn (sprint 5, reviewer's call; sprint 4 had capped it at sprint speed instead). That includes a walker's long step after a multi-second stall.
- Why: single 0.2 s deltas were jittery from uneven network updates and made walkers read above 14 (sprint), and the old 60 studs/s filter could zero a sprinter on a short step.
- Float gotcha for specs: with MIN_SAMPLE 0.1, differences like 1.2 - 1.1 come out just under 0.1 and get skipped. Use gaps that are clearly over 0.1.
- Pure logic (only .X/.Z read, no engine API), so `SpeedSampler.spec.luau` runs under Lune.

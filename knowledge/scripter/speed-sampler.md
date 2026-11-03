# SpeedSampler (src/server/SpeedSampler.luau)

- Shared by Monster and NoiseService; each makes its own `SpeedSampler.new()` (they sample at different cadences).
- Speed = sum of horizontal deltas / sum of their time over the last 0.5 s. Samples under 0.1 s after the last recorded one are skipped (the baseline doesn't move). One step over 40 studs is a teleport: that delta is dropped, the rest still count.
- Why: single 0.2 s deltas were jittery from uneven network updates and made walkers read above 14 (sprint), and the old 60 studs/s filter could zero a sprinter on a short step.
- Pure logic (only .X/.Z read, no engine API), so `SpeedSampler.spec.luau` runs under Lune.

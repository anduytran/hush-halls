# SpeedSampler (src/server/SpeedSampler.luau)

- Shared by Monster and NoiseService; each makes its own `SpeedSampler.new()` (they sample at different cadences).
- Speed = sum of horizontal deltas / sum of their time over the last 0.5 s. Samples under 0.1 s after the last recorded one are skipped (the baseline doesn't move). One step over 40 studs (teleport/lag spike) is dropped (sprint 7): no delta is added, there's no pruning on that sample, the baseline moves to the new spot, and the sample returns the previous average. The history went: sprint 4 capped it, sprint 5 reset it to 0, sprint 6 clamped it to SPRINT_SPEED (it read as a sprint), and sprint 7 holds it. Reviewer rule: a long step must read neither as a sprint nor as 0. A slow long step after a stall (over 40 studs) is held too. SPRINT_SPEED is now unused by the code but kept (the spec checks it).
- Why: single 0.2 s deltas were jittery from uneven network updates and made walkers read above 14 (sprint), and the old 60 studs/s filter could zero a sprinter on a short step.
- Float gotcha for specs: with MIN_SAMPLE 0.1, differences like 1.2 - 1.1 come out just under 0.1 and get skipped. Use gaps that are clearly over 0.1.
- Pure logic (only .X/.Z read, no engine API), so `SpeedSampler.spec.luau` runs under Lune.

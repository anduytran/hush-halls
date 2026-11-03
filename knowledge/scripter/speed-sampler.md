# SpeedSampler (src/server/SpeedSampler.luau)

- Shared by Monster and NoiseService; each makes its own `SpeedSampler.new()` (they sample at different cadences).
- Speed = sum of horizontal deltas / sum of their time over the last 0.5 s. Samples under 0.1 s after the last recorded one are skipped (the baseline doesn't move). One step over 40 studs (teleport/lag spike) is kept but capped at SPRINT_SPEED (24) × dt (sprint 4: the reviewer didn't want it ignored, since dropping it gave a silent gap). The cap is a `min`, so a walker's long step after a multi-second stall keeps its real speed.
- Why: single 0.2 s deltas were jittery from uneven network updates and made walkers read above 14 (sprint), and the old 60 studs/s filter could zero a sprinter on a short step.
- Known gap: a standing player who teleports averages only ~4.8 over the window, which is below Monster's HEARD_SPEED 8. Fine for now because server teleports (spawn, platform) reset the root or clear InRound.
- Pure logic (only .X/.Z read, no engine API), so `SpeedSampler.spec.luau` runs under Lune.

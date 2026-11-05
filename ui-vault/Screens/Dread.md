---
status: in-progress   # sprint 36, not playtested yet
tags: [ui, screen, overlay]
---
# Dread overlay

## Purpose
Sells the horror as the monster closes in, and punishes a catch with a short jumpscare. Design: [[../design-vault/Mechanics/Routes, Exits and Dread|Routes, Exits and Dread]].

## Layout
- Full-screen ScreenGui `Dread` (IgnoreGuiInset, DisplayOrder 50, over the HUD)
- Vignette: four edge strips (left/right 0.35 wide, top/bottom 0.4 tall), dark red #3A0004, UIGradient from opaque at the edge to clear inward
- Jumpscare (hidden by default, ZIndex 10+): dark frame #070102, red throat glow, two black pill-shaped jaws with bone (#D9CFBD) diamond teeth (9 upper, 8 lower, smaller at the sides), white flash on top

## Elements
- Intensity: distance from the local HumanoidRootPart to the monster part. 0 beyond 50 studs, 1 at 5 studs, linear between, smoothed (exponential, rate 3/s). 0 while dead or with no monster.
- Vignette: edge BackgroundTransparency = 1 - 0.85 x intensity
- Camera shake: position offset from math.noise, at most 0.15 studs x intensity. Undone before the camera scripts run (RenderPriority Camera - 1) and reapplied after (Camera + 1), so it never accumulates.
- FOV: down by 8 x intensity, applied as a delta on top of whatever FOV other code set
- Jumpscare: on local Humanoid.Died with the monster within 12 studs; once per life. 0.7 s: flash fades in 0.15 s, jaws snap shut (Quint In, 0.28 s after 0.12 s), mouth scales 0.85 to 1.3, then hard cut
- Monster lookup: `workspace.Hall.Monster`, then `workspace.Monster`, then any BasePart named Monster; re-searched every 0.5 s while missing

## States
- No monster in workspace: no effects
- CharacterAdded: everything reset (jumpscare hidden and tweens cancelled, vignette clear, shake removed, FOV restored)
- Mobile vs desktop: all scale-based; teeth are capped to 0.09 of the row width so they fit on a portrait phone

## Implementation
- Files: `src/client/Dread.luau` (`Dread.start()`), started from `src/client/main.client.luau`
- Remotes used: none (reads the replicated monster part)
- Studio hooks: `Dread._test` with `gui`, `intensity()`, `playScare()`, `reset()`; `Dread.intensityFor(distance)` is public

## Open questions
- No scream sound yet (the design asks for one); Audio module would need a jumpscare cue.
- No spec yet for Dread.

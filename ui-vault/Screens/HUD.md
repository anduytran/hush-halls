---
status: done
tags: [ui, screen]
---
# HUD

## Purpose
Always-on round info while sneaking through the hall: how long is left, how high the water is, how loud you are, your coins, and a sprint control.

## Layout
- Top centre: round state + time left (e.g. `Running  1:45`)
- Top right: Coins counter, with the [[Screens/Shop|Shop]] button under it
- Left edge, vertically centred: water bar (fills bottom-up, blue)
- Bottom centre: noise meter (fills left-to-right)
- Bottom right: round SPRINT button (touch devices only)

## Elements
- RoundInfo: `State.RoundState` + `State.TimeLeft` as m:ss; shows "Waiting" until State exists
- GoalText: objective line under the timer (child of RoundInfo, so nothing else moves; wraps, 14–20 px scaled text with a light stroke). Follows `State.RoundState` and `LocalPlayer.Escaped`:
  - Lobby / unset: "Next round soon. Reach the EXIT before the water rises."
  - Running: "Reach the EXIT. Sprinting is loud."
  - Running + Escaped: "You escaped! Wait for the next round." in green
  - Ended: "Round over."
- WaterBar: fill = `State.WaterLevel / 20`, clamped 0–1
- NoiseMeter: fill = `State.Noise` (0–1); green, turns Danger red and caption reads "Noise: LOUD" above 0.6 (text change so it isn't colour-only)
- Coins: `leaderstats.Coins`, Accent colour
- SprintButton: hold to sprint. Fires `Remotes.Sprint(true)` on press and `(false)` on release (also when the finger slides off). LeftShift does the same on PC. Shift and the button are tracked apart, so releasing one while holding the other keeps sprinting.

## States
- Before State/Remotes/leaderstats exist: placeholders, waits silently (no infinite-yield warning)
- Mobile: SprintButton visible (`UserInputService.TouchEnabled`), 72–120 px round target
- Desktop: SprintButton hidden; LeftShift via ContextActionService (passes input through so shift-lock still works)

## Implementation
- Files: `src/client/UI/Hud.luau` (`Hud.mount()`), mounted from `src/client/main.client.luau`
- Remotes used: `ReplicatedStorage.Remotes.Sprint` (client → server, bool)
- Sizing: Scale sizes + UISizeConstraint/UITextSizeConstraint (min text 14), ScreenInsets = CoreUISafeInsets

## Open questions
- No icons yet (text only). Water bar max (20) is hard-coded to match the contract.

---
status: done
tags: [ui, screen]
---
# HUD

## Purpose
Always-on round info while sneaking through the hall: how long is left, how high the water is, how loud you are, your coins, and a sprint control.

## Layout
- Top centre: round state + time left (e.g. `Running  1:45`), with the goal line in its own panel just under it
- Top right: Coins counter, with the [[Screens/Shop|Shop]] button under it
- Left edge, vertically centred: water bar (fills bottom-up, blue)
- Bottom centre: noise meter (fills left-to-right)
- Bottom right: round SPRINT button (touch devices only)
- Centre (on join only, ~4 s): TitleCard overlay

## Elements
- RoundInfo: `State.RoundState` + `State.TimeLeft` as m:ss; shows "Waiting" until State exists
- GoalPanel / GoalText: objective line in its own panel (same style as RoundInfo), 4 px under RoundInfo and following its real height. Same width as RoundInfo (0.28 scale, 160–360 px) so on a 375 px phone it stays in the centre column clear of Coins and the Shop button; height 0.08 scale (44–64 px) fits two wrapped lines. TextScaled + wrapped, 14–20 px. Follows `State.RoundState` and `LocalPlayer.Escaped`:
  - Lobby / unset: "Next round soon. Reach the EXIT."
  - Running: "Reach the EXIT. Sprinting is loud."
  - Running + Escaped: "You escaped! Wait for the next round." in green
  - Ended: "Round over."
- WaterBar: fill = `State.WaterLevel / 20`, clamped 0–1
- NoiseMeter: fill = `State.Noise` (0–1); green, turns Danger red and caption reads "Noise: LOUD" above 0.6 (text change so it isn't colour-only)
- Coins: `leaderstats.Coins`, Accent colour
- SprintButton: hold to sprint. Fires `Remotes.Sprint(true)` on press and `(false)` on release (also when the finger slides off). LeftShift does the same on PC. Shift and the button are tracked apart, so releasing one while holding the other keeps sprinting. If the HUD is destroyed while sprint is held, it sends `Sprint(false)` once so the server isn't left sprinting.
- TitleCard: shown once per session on the first `Hud.mount()` (the join), never on later mounts. Dark panel (Background, 0.1 transparent) with a faint water-blue UIStroke edge, centred, ZIndex 10, input passes through. Contents, stacked with UIListLayout:
  - Title: `string.upper(Config.GAME_NAME)` → "HUSH HALLS", BuilderSans Bold, Text colour with a water-blue glow stroke, 14–64 px
  - Tagline: "Every sound floods the halls.", BuilderSans Medium Italic, water blue (#3A8DFF), 14–24 px
  - Hint: "Walk to stay quiet. Sprint and it hears you.", BuilderSans Medium, Text colour, 14–20 px, wraps
  - Size 0.8 × 0.3 scale, clamped 260×150 – 560×240 px. On 375×667 portrait it is 300 px wide, clear of the WaterBar, and ends ~145 px above the SprintButton; on 667×375 landscape it ends ~25 px above it
  - Motion: fade in 0.25 s (Quad Out), hold 3 s, fade out 0.75 s (Quad In), then destroyed (see [[Decisions]])

## States
- Before State/Remotes/leaderstats exist: placeholders, waits silently (no infinite-yield warning)
- Mobile: SprintButton visible (`UserInputService.TouchEnabled`), 72–120 px round target
- Desktop: SprintButton hidden; LeftShift via ContextActionService (passes input through so shift-lock still works)

## Implementation
- Files: `src/client/UI/Hud.luau` (`Hud.mount()`), mounted from `src/client/main.client.luau`
- Remotes used: `ReplicatedStorage.Remotes.Sprint` (client → server, bool)
- Sizing: Scale sizes + UISizeConstraint/UITextSizeConstraint (min text 14), ScreenInsets = CoreUISafeInsets
- Cleanup: every State/player/input connection sits in one table and is disconnected (and `HushSprint` unbound) when the Hud gui is destroyed or the local player leaves
- Tests: `src/client/UI/Hud.cloud.spec.luau` (client play-test). It drives the goal line through the Studio-only `Hud._test.hooks(gui).setGoal(roundState, escaped)` and never writes replicated State; it also checks the layout in a simulated 375x667 viewport
- Sprint test hooks (same table, Studio only): `forceTouch(on)` shows or hides SprintButton whatever `TouchEnabled` says; `pressSprint()` / `releaseSprint()` run the same press/release code as a real touch (and fire the remote); `isSprinting()` reads the state. Specs cover: button visible and on screen at 375x667, press sets sprint on and release sets it off, release after Destroy doesn't error, button hidden when not touch
- Title card hook (Studio only): `showTitle(parent?)` builds a fresh TitleCard whatever the once-per-session flag says. Specs cover: later mounts show no card, texts (title from Config), min text 14, scale-only size, gone by 4.5 s, and on 375×667 and 667×375 the card is on screen, text fits, and it clears SprintButton, NoiseMeter and WaterBar
- Config: reads `ReplicatedStorage.Shared.Config.GAME_NAME`

## Open questions
- On screens narrower than ~370 px (safe area), RoundInfo/GoalPanel (160 px min) would touch the Coins column; 375 px clears it by ~3 px. Not a target size today.
- No icons yet (text only). Water bar max (20) is hard-coded to match the contract.

# RoundService

- `src/server/RoundService.luau`: `start()` is idempotent; `stop()` cancels the loop, drops connections and clears state (specs call stop+start in a beforeEach wrapper, since the runner has no hook). A `generation` counter makes a start that's still waiting give up after stop(); a failed start resets `started`. HallBuilder is required lazily. It uses the existing `Workspace.Hall` (it only builds one if missing), makes or reuses `Hall.LobbyPlatform` 30 studs above Start, and runs the loop in a task.
- Loop: Lobby 15s → spawn everyone at Start (waits up to 10s) → Running ≤120s → Ended 5s. The Lobby timer stays at 15 while the server has no players.
- LoadCharacter runs in a pcall with 3 tries. A player who still has no character is dropped from the round, so it isn't held open.
- Player attribute `InRound`: true from the round spawn until death, escape or Ended. Monster and NoiseService ignore players without it. Spectators (late joiners, dead players who respawned) are moved to the platform during Running, and during the spawn wait (`spawning` flag; RoundState is still Lobby then), plus a sweep of non-participants when Running begins.
- A `round` counter guards Died handlers, so a character from an earlier round can't mark someone dead.
- Escape: Exit.Touched sets Escaped=true before coins are added, so the reward can't be paid twice.
- `stop()` is test-only and does nothing unless started. It and a failed start() share a local `teardown()`, which also sets `platform` to nil. Test hooks are all in `RoundService._test`: `setSpawning`, `placeSpectator(player, character)`, `platform()`, `loop()`. The spec passes a plain `{ Character = model }` table as the player (a non-participant only has `.Character` read).
- main.server retries any system's `start()` that errors: every 5 s, up to 5 retries. A system that started is put in `startedSystems` and is never started again.
- Gotcha: a spec can get its own module instance (separate require cache), so its `stop()` can't stop main.server's loop, and main's loop keeps writing the shared `State` attributes. Specs should check this instance's own state (e.g. `_test.loop()` being dead), not whether State stopped changing.
- Owns `leaderstats.Coins` (created on PlayerAdded). Other systems should add to it, not recreate it.

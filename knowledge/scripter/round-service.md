# RoundService

- `src/server/RoundService.luau`: `start()` is idempotent. It uses the existing `Workspace.Hall` (it only builds one if missing), makes or reuses `Hall.LobbyPlatform` 30 studs above Start, and runs the loop in a task.
- Loop: Lobby 15s → spawn everyone at Start (waits up to 10s) → Running ≤120s → Ended 5s. The Lobby timer stays at 15 while the server has no players.
- LoadCharacter runs in a pcall with 3 tries. A player who still has no character is dropped from the round, so it isn't held open.
- Player attribute `InRound`: true from the round spawn until death, escape or Ended. Monster and NoiseService ignore players without it. Spectators (late joiners, dead players who respawned) are moved to the platform during Running.
- A `round` counter guards Died handlers, so a character from an earlier round can't mark someone dead.
- Escape: Exit.Touched sets Escaped=true before coins are added, so the reward can't be paid twice.
- Owns `leaderstats.Coins` (created on PlayerAdded). Other systems should add to it, not recreate it.

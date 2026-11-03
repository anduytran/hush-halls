# RoundService

- `src/server/RoundService.luau`, `start()` builds the hall (HallBuilder.build(), then waits for `Workspace.Hall`), makes `Hall.LobbyPlatform` 30 studs above Start, and runs the loop in a task.
- Loop: Lobby 15s → Running ≤120s → Ended 5s. The Lobby timer stays at 15 while the server has no players.
- Only players present when Running begins are participants. Players who join mid-round sit out until the next round.
- Dead = Humanoid.Died during Running (on the character from the round respawn). Auto-respawned players still count as dead for that round.
- Escape: Exit.Touched → Escaped=true is set before coins are added, so the reward can't be paid twice.
- Owns `leaderstats.Coins` (created on PlayerAdded). Other systems should add to it, not recreate it.

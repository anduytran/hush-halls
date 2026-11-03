# MVP contracts (sprint 1)

Shared state lives in `ReplicatedStorage.State` (Folder created by `src/shared/GameState.luau`), with attributes:
- `WaterLevel` (number, studs above hall floor), `Noise` (0–1), `RoundState` ("Lobby"|"Running"|"Ended"), `TimeLeft` (seconds).
- Remotes in `ReplicatedStorage.Remotes`: `Sprint` (RemoteEvent, client→server, bool held).

Map: `src/server/Map/HallBuilder.luau` returns `build()` and creates `Workspace.Hall` with `Start` (SpawnLocation), `Exit` (Part), `Floor`. Hall runs along +Z from Start.

Server modules each expose `start()`; `main.server.luau` requires them: NoiseService, Monster, RoundService.
Players: `leaderstats.Coins`. Attribute `Escaped` on the Player when they reach Exit.

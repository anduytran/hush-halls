# Live round smoke in Studio (sprint 25)

- Playing the real game (no module injection) works when Studio's scripts match the worktree: compare each script's `#Source` with the file's byte size first. Studio had some duplicated modules (SpeedSampler, RoundTestPlayers, specs) left from earlier injections; harmless while identical.
- Layout seen: Start at (0, 0.5, 0), Exit 24x20x4 at (0, 10, 298), Floor 40x2x314. Monster parks at (0, 10, 498) and enters at the Exit. LobbyPlatform at y 30.5.
- Walking (10) to the Exit is silent: the monster stays put and the escape pays 10 coins, round ends early (one player). Sprinting toward the Exit gets you caught.
- Output on a clean run: the two startup prints plus 6x "ContentId: rbxassetid://203785492 failed due to: Asset type does not match requested type" at startup only. Not in src/ or any instance property; doesn't repeat on respawn. Treat it as engine/avatar noise.
- `os.clock()` advances with wall time across yields in Studio (checked: 3.014 s vs 3.014 s), so RoundService's timers are fine.
- Tooling: `character_navigation` to the Exit can time out on a long walk; `Humanoid:MoveTo` from the Server datamodel works. A `PivotTo` teleport reads as speed 0 (the monster won't hear it).

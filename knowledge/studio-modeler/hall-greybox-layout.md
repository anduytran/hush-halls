# Hall greybox layout (sprint 1)

Built by `src/server/Map/HallBuilder.luau` → `Workspace.Hall` (Model, PrimaryPart = Floor).

- Floor top at Y=0. Corridor interior 24 wide, walls 20 high, runs +Z from a back wall at z=-10 to an end wall at z=300.
- Three segments: A at x -12..12 (z up to 100), B shifted +12 to x 0..24 (z 100..200), C back at x -12..12 (z 200..300). The jog openings are the 12-stud overlap at x 0..12.
- Start = SpawnLocation at (0, 0.5, 0). Exit = neon trigger x -12..12, z 296..300, CanCollide false.
- Children: Floor, Walls (folder), Obstacles (folder: 3 pillars + 4 crates), Start, Exit. 22 parts.
- Obstacles are kept away from z≈95..105 and z≈195..205 so the jogs stay open.

Gotchas
- `build()` destroys any existing `Workspace.Hall` first, so it's safe to call again.
- character_navigation in a straight line from spawn can catch on the jog corner at (0, z=100). Navigate in two legs via (6, z=120) instead. It is not a real block.
- To test in Studio without Rojo, paste the module body into execute_luau and call build() inline.

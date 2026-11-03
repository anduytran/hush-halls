# Hush Halls

A Roblox game built with Rojo. Code in `src/` syncs into Roblox Studio with `rojo serve`.

## Layout
- `src/server` → ServerScriptService.Server (Scripts end in `.server.luau`)
- `src/client` → StarterPlayer.StarterPlayerScripts.Client (LocalScripts end in `.client.luau`)
- `src/shared` → ReplicatedStorage.Shared (ModuleScripts)

## Conventions
- Luau. Use `--!strict` where practical. ModuleScripts return a table; PascalCase module names, camelCase functions.
- The server is the authority: validate every RemoteEvent/RemoteFunction argument, rate and ownership on the server.
- Create remotes in code (in `src/shared`), not by hand in Studio.
- Build UI in code under `src/client/UI` so it can be reviewed.
- Keep changes small: one feature or fix per task.
- Don't install packages or tools. If you need one, say so in your final message.

## Design
- The game design lives in `design-vault/`: start with `Brief.md` (the product owner's idea), then `Game Overview.md`, `Roadmap.md` and the mechanic notes.
- The UI spec lives in `ui-vault/`.
- Approved web research lives in `research/`.
- Milestone 1 is shipping: `design-vault/Ship Checklist.md` lists what the first public version needs.

## Purchases
- Everything sold for Robux is listed in `src/shared/Products.luau` (IDs come from the Creator Hub; 0 = not created yet).
- Grant purchases only on the server, through `src/server/Monetization.luau` (`Monetization.onPass`, `Monetization.onProduct`).
- Open purchase prompts from the client with `src/client/Shop.luau`. Never sell power in a fair fight.

## Checks
These must pass before work is merged: `stylua --check src`, `selene src`, `rojo build -o hangar-check.rbxl`.

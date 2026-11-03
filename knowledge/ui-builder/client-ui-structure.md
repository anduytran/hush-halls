# Client UI structure

- Each UI module in `src/client/UI/` exposes `mount()` and builds its own ScreenGui; `main.client.luau` calls them.
- `src/client` is a plain Folder in Rojo, so from `UI/X.luau`, `script.Parent.Parent.Shop` is the Shop module.
- State/Remotes/leaderstats come from server modules: wait with `WaitForChild(name, timeout)` in a loop to avoid "Infinite yield possible" warnings (see Hud.luau `waitFor`).
- Sprint is tracked per source (Shift vs touch button) so one release doesn't cancel the other.
- In an unpublished Studio place, Monetization errors on DataStore at load: not a UI bug.
- Notes: ui-vault/Screens/HUD.md, ui-vault/Screens/Shop.md.
- Hud spec hooks: `Hud._test.hooks(gui)` (Studio only, per mounted gui). Specs mount their own HUD; never write replicated State from a client spec.
- Phone layout check without a device: move a gui's children into a 375x667 offset Frame and read AbsolutePosition/AbsoluteSize/TextFits (see Hud.cloud.spec.luau).
- Top-centre column budget at 375 px: centre panels must stay ≤160 px wide to clear Coins/Shop (right column starts at W-104).

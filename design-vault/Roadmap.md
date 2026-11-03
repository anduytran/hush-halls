# Roadmap

## Now: Milestone 1 — Ship v1 (see [[Ship Checklist]])
Sprint 1 (2026-11-03): all six pieces merged. Only the hall map has run in Studio so far.
- [x] Greybox hall map (Start, Exit, Floor): `src/server/Map/HallBuilder.luau`. Built and QA-checked in Studio.
- [x] [[Mechanics/Sprint Noise and Water]]: `src/server/NoiseService.luau`, `src/shared/GameState.luau`
- [x] [[Mechanics/Blind Monster]]: `src/server/Monster.luau`
- [x] [[Mechanics/Round Loop]]: `src/server/RoundService.luau`
- [x] [[Mechanics/Products and Grants]]: `src/shared/Products.luau`, `src/server/main.server.luau`
- [x] HUD + Shop menu: `src/client/UI/Hud.luau`, `src/client/UI/ShopMenu.luau` (spec in ui-vault)

## Needs a playtest
None of these have run in a live round yet. Studio wasn't reachable when they were built.
- Sprint/noise/water: water rises only while Running, players drown, Sprint remote works from Shift and the touch button.
- Blind monster: hears sprinters, ignores sneakers, kills only during Running.
- Round loop: Lobby 15 s → Running 120 s → Ended 5 s; escaping pays +10 coins once.
- HUD and shop: bars, timer and coins update; shop opens the purchase prompts.
- Pass grants: Neon Trail and VIP tag on spawn, Coins100 adds coins.

## Blocked
- Purchases: every ID in `src/shared/Products.luau` is 0. The passes and the product must be created in the Creator Hub and their IDs pasted in before they can be sold.
- Monetization errors on DataStore access in an unpublished Studio place. A full test needs the place published with API access turned on.

## Next
- VIP "2x coins" is advertised but not built (see [[Mechanics/Products and Grants]]).
- Fix the walk/hearing mismatch (see [[Mechanics/Blind Monster]], open questions).
- Write the sprint 1 numbers into [[Balance]].
- Milestone 2 — Feel: footstep sounds, monster audio, water VFX, camera shake, proper hall art.

## Later
- Milestone 3 — Depth: multiple halls, hazards (puddles, loose planks), daily rewards, leaderboards.
- Milestone 4 — Social: team rounds, spectating, trails shop expansion.

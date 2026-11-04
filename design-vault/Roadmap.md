# Roadmap

## Now: Milestone 1 — Ship v1 (see [[Ship Checklist]])
As of sprint 33 (2026-11-04): the hall, [[Mechanics/Sprint Noise and Water]], [[Mechanics/Blind Monster]], [[Mechanics/Round Loop]], HUD (goal line, touch sprint button) and Shop menu are built and merged. A 10-minute solo Studio soak (six rounds, 670 s) ran with clean Output: timeouts, walk escapes (+10 coins), a sprinter caught by the monster. Water rise is 0.3 studs/s at full noise and walking makes 0.05 noise, so the monster punishes sprinting and a full-round walker no longer drowns (~1.8 studs at 120 s). Receipt handling ([[Mechanics/Products and Grants]]) is hardened and spec-tested, but sales are blocked on product IDs. What's left for v1 is mostly product-owner work: real two-player and phone checks, product IDs, store page, publish.

Done (history in git log):
- [x] Sprints 1–13: hall, core systems, round loop wiring, receipt hardening (59 Monetization specs pass in Studio).
- [x] Sprints 14–19: VIP 2x escape coins, walking silent (HEARD_SPEED 12), HUD goal line.
- [x] Sprints 20–27: round smoke/two-player specs with fake players, live Studio rounds, Escaped clears at round end, touch sprint specs.
- [x] Sprint 29: 0.5 s hearing confirm (`HEAR_CONFIRM`). Sprints 30–31: water 0.3/s, catch-before-drown confirmed.
- [x] Sprint 32: 10-minute Studio soak, clean Output (no code changed).
- [x] Sprint 33: walk noise 0.1 → 0.05 (`SNEAK_NOISE`), spec-tested.

## Needs a playtest
- Two real clients at once (Test → Clients and Servers, by hand): second player caught/drowned, join mid-round, several escapes, slow loader spectates, leave mid-spawn; earlier stuck-at-Start spawn overlap.
- Touch sprint button and HUD layout on a real phone/tablet (hold sprints, release walks, respawn mid-hold).
- Purchases in a published place: VIP 20 coins, Neon Trail/VIP tag, Coins100, receipt flow; `_test` hooks absent on a live server.
- Feel: does the monster still feel threatening when everyone walks?
- Full-round walk at 0.05 noise in a live Studio round (spec only so far).

## Blocked
- Purchases: every ID in `src/shared/Products.luau` is 0. Create the passes and product in the Creator Hub and paste the IDs in.
- Receipts can't be tested in an unpublished place; needs the place published with API access on.

## Next
- Copy the sprint 1 numbers the 0.3/s water rate and 0.05 walk noise into [[Balance]].
- Milestone 2 — Feel: footstep sounds, monster audio, water VFX, camera shake, proper hall art.

## Later
- Milestone 3 — Depth: multiple halls, hazards (puddles, loose planks), daily rewards, leaderboards.
- Milestone 4 — Social: team rounds, spectating, trails shop expansion.

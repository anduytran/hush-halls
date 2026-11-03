---
status: in-progress   # receipts hardened in sprint 2, sprint 4 reserve → grant → mark done (grant outside UpdateAsync), sprint 5 per-attempt tokens, sprint 8 no stale takeover (owner-only markers, released state, late results retried until recorded), sprint 9 24 h stale rule + retry cap + shutdown drain, sprint 10 60 s heartbeat on live markers + 20 s drain, sprint 11 heartbeat capped at 30 min + one-time restamp + no regrant after give-up, sprint 12 per-attempt heartbeat window + done-only expiring regrant block + locked test hooks, sprint 13 Studio-only test hooks + gave-up block pruning (59 spec tests pass in Studio), blocked on Creator Hub IDs
tags: [design, mechanic]
---
# Products and grants

## What it does
Neon Trail pass (99 R$): a cyan trail. VIP pass (199 R$): a gold name tag and 2x coins. 100 Coins product (49 R$). Cosmetic and coins only.

## Acceptance criteria
- [ ] Buying each item from the Shop menu grants it on the server.
- [ ] The trail and the VIP tag come back after respawning.
- [ ] Nothing sold changes speed, noise or the monster.

## Implementation
- Files: `src/shared/Products.luau`, `src/server/main.server.luau`, `src/server/Monetization.luau`, `src/client/UI/ShopMenu.luau`

## Open questions
- Blocked: all IDs are 0 until the items are created in the Creator Hub.
- Gap: VIP's "2x coins" isn't built. Only the name tag is granted, and RoundService always pays +10. Either build it or change the pass description.

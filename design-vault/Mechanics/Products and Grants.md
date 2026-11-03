---
status: in-progress   # receipts hardened in sprint 2, sprint 4 reserve → grant → mark done (grant outside UpdateAsync), sprint 5 per-attempt tokens, blocked on Creator Hub IDs
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

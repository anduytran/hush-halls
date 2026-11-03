---
status: done
tags: [ui, screen]
---
# Shop

## Purpose
Lets players buy the passes and products listed in `src/shared/Products.luau`.

## Layout
- Shop button: top right, under the Coins counter on the [[Screens/HUD|HUD]]
- Panel: centred, title "Shop" + close X, scrolling list of item cards

## Elements
- Item card: name, description, Buy button showing `R$ price`. One card per entry in `Products.Passes` and `Products.Products`, sorted by price.
- Buy: calls `Shop.buyPass(key)` / `Shop.buyProduct(key)` (`src/client/Shop.luau`); granting is server-side in `Monetization`.

## States
- Empty catalogue: "Nothing for sale yet."
- Item with id 0: Buy warns in Output (from Shop.luau) and no prompt opens
- Open: UIScale tween 0.9 → 1 (0.2 s Quad Out). Shop button toggles; X closes.
- Mobile: panel 300–520 px wide, 44 px close target

## Implementation
- Files: `src/client/UI/ShopMenu.luau` (`ShopMenu.mount()`), mounted from `src/client/main.client.luau`
- Remotes used: none (MarketplaceService prompts via Shop.luau)

## Open questions
- Cards are built once at mount; Products is static so that's fine.

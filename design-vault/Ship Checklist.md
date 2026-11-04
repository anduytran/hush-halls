---
tags: [design, ship]
---
# Ship checklist

The smallest version worth publishing: fun for ten minutes, with a goal and two or three things to buy. This is milestone 1 ("Ship v1"); depth comes after launch. The Lead ticks items as they're done. Items marked (you) need the product owner. Hangar shows the progress on the game's Overview.

## Game
- [x] The core loop works from start to finish: what a new player does in their first five minutes
- [x] A goal players can see: a way to win a round, finish, or progress
- [ ] (you) Controls work on phone and tablet (touch) as well as PC
- [ ] (you) Two players at once in Studio (Test → Clients and Servers, 2 players) with no errors
- [x] A 10-minute play with no errors in the Output window

## Purchases
- [ ] Two or three things to buy, listed in `src/shared/Products.luau`: cosmetics, convenience or a VIP perk. Nothing that makes paying players stronger in a fair fight
- [ ] Each one is granted in code (`Monetization.onPass` / `Monetization.onProduct` in `src/server/Monetization.luau`), and a Shop button opens it (`src/client/Shop.luau`)
- [ ] (you) Each one created in the Creator Hub (your game → Monetization → Passes / Developer Products) and its ID pasted into `Products.luau`
- [ ] (you) Each one bought in a Studio test and granted correctly (Studio test purchases are free; turn on Game Settings → Security → "Enable Studio Access to API Services" first)

## Store page (you)
- [ ] Name, description and genre set in the Creator Hub
- [ ] An icon (512×512) and at least one thumbnail
- [ ] The maturity questionnaire answered
- [ ] The experience set to public

## Launch
- [ ] (you) Published to the live game from Hangar (the game's Overview → Publish to live game)

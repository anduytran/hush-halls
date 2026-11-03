# Decisions

Newest first. One entry per decision: what, why, alternatives considered.

## 2026-11-03 — Sprint 1 build choices
- **Shared state is attributes on `ReplicatedStorage.State`** (WaterLevel, Noise, RoundState, TimeLeft), set up by `GameState.luau`. The server writes them and clients only read. This let the six pieces be built in parallel against one contract. The alternative was one RemoteEvent per value.
- **Each server system starts in its own protected thread, before Monetization loads.** Monster waits for the hall that RoundService builds, so starting them one after another would hang. Monetization errors in an unpublished place, so it loads last and can't stop the game systems.
- **Only players present when a round starts take part.** Anyone who joins mid-round waits for the next one. Simpler and fairer than letting late joiners drop in.
- **Sprint "release" is never rate-limited.** That way a player can't get stuck sprinting.
- **Purchases are cosmetic or coins only** (Neon Trail, VIP tag + 2x coins, 100 Coins). Nothing sold changes noise, speed or the monster, per CLAUDE.md.

## 2026-11-03 — Vault created
Started a design vault so agents and people share one source of truth for the game.

# Decisions

Newest first. One entry per decision: what, why, alternatives considered.

## 2026-11-05 — Join title card lives in the HUD, with a slower fade
What: the "HUSH HALLS" title card is built by `Hud.mount()` (first mount of the session only), not a separate ScreenGui. It fades in 0.25 s, holds 3 s, fades out 0.75 s (about 4 s total).
Why: one file owns the on-join screen and its cleanup; the slow fade-out is an atmospheric exception to the 0.15–0.25 s motion rule, which stays the rule for interactive UI.
Alternatives: own ScreenGui/module (more wiring for a 4 s element); CanvasGroup fade (blurs scaled text on phones).

## 2026-11-03 — Vault created
Started a UI vault so agents and people share one source of truth for the interface.

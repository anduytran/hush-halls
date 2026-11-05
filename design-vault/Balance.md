# Balance

The numbers. Change values here first, then in code (the Lead keeps them in sync).

| Thing | Value | Unit | Why |
| --- | --- | --- | --- |
| Walk speed | 10 | studs/s | Quiet sneak pace |
| Monster listen pause (`LISTEN_TIME`) | 2 | s | Gives a hiding player a tense beat (sprint 36) |
| Monster lunge range / bonus (`LUNGE_RANGE`, `LUNGE_BONUS`) | 15 / +8 | studs / studs/s | A close sprint is punished hard (sprint 36) |
| Dread effects start | 50 | studs | Vignette, shake and FOV ramp up to full at 5 studs (sprint 36) |
| Exits | 3 | — | Main door, gym fire exit, classroom window; each 250–330 studs away (sprint 36) |
| Sprint speed | 24 | studs/s | Fast but loud |
| Walk noise (`SNEAK_NOISE`) | 0.05 | 0–1 | A full-round walker doesn't drown (sprint 33) |
| Water rise at full noise (`RISE_PER_SECOND`) | 0.3 | studs/s | The monster catches sprinters before they drown (sprint 30) |
| Drown time (`DROWN_TIME`) | 2 | s | |
| Monster hearing range (`HEARING_RANGE`) | 150 | studs | |
| Hearing confirm (`HEAR_CONFIRM`) | 0.5 | s | Ignores one-frame blips (sprint 29) |
| Puddle splash | 0.8 for 0.6 | noise / s | Punishes careless routes (sprint 34) |
| Plank creak | 0.4 for 0.4 | noise / s | Smaller warning than a puddle (sprint 34) |
| Hazard cooldown | 1 | s per player | No spam from standing on one |
| Hall layouts | 3 | | Picked at random each round (sprint 34) |
| Exits (sprint 39) | 3 | — | Walks from each spawn to each exit are 446–519 studs on the bigger map |
| Round length | 180 | s | Longer for the bigger map; a full-round walker reaches about 2.7 of 3.43 studs of water (sprint 39) |
| Stamina pips | 3, +1 per 2.5 s after 0.5 s | pips | Movement tech (sprint 39) |
| Dash / dash jump | 1 / 2 pips, ~18 studs in 0.25 s | | One air dash per jump; noise 1.0 for 0.5 s |
| Slide | free, needs ≥18 studs/s, ~1 s | | A slide hop keeps the speed; noise 0.6 for 0.4 s |
| Double jump / wall jump | 1 pip / first free, then 0.5 | | Noise 0.6 for 0.4 s |
| Move remote limit | 5 | per s per player | Server-checked in `MovementNoise.luau` |

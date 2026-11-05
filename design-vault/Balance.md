# Balance

The numbers. Change values here first, then in code (the Lead keeps them in sync).

| Thing | Value | Unit | Why |
| --- | --- | --- | --- |
| Walk speed | 10 | studs/s | Quiet sneak pace |
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

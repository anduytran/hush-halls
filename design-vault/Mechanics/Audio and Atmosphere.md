---
status: in-progress   # sprint 34
tags: [design, mechanic]
---
# Audio and atmosphere

## What it does
The halls sound alive: your own footsteps (soft walking, loud sprinting), the monster growling louder as it gets near, a heartbeat when it is close, and the water sloshing as it rises. The monster screams when it catches someone.

## Why
Sound is the theme ("every sound floods the halls"). Research (Nov 2026) shows horror hits on Roblox are praised for sound design first; this was our biggest gap.

## Acceptance criteria
- [ ] Walking plays quiet footsteps, sprinting plays louder, faster ones; standing still is silent.
- [ ] The monster has a looping 3D growl, audible from about 60 studs and louder up close.
- [ ] A heartbeat fades in within about 40 studs of the monster and speeds up closer.
- [ ] A water ambience plays during a round and gets louder as the water rises.
- [ ] Catching a player plays a scream at the monster.
- [ ] No errors in Output if a sound fails to load.

## Implementation
- Files: `src/client/Audio.luau` (footsteps, heartbeat, water), `src/server/Monster.luau` (growl, scream)

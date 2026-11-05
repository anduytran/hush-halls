---
status: in-progress   # sprint 39
tags: [design, mechanic]
---
# Movement tech (Deadlock-inspired) and a bigger school

## What it does
Movement inspired by Valve's Deadlock: stamina pips power the bursts, and skilled chaining saves stamina. Every burst is **loud**, so it's an escape tool with a price, which fits the pillar that speed is noise.
- **Stamina:** 3 pips, regenerating 1 pip per 2.5 s after 0.5 s of not using any.
- **Dash (Q / touch button):** a quick burst in the move direction, about 18 studs in 0.25 s. Costs 1 pip. One air dash per jump.
- **Dash jump:** press Space during the last 0.15 s of a dash for a long, fast leap. Costs +1 pip (2 total).
- **Slide (C or Left Ctrl / touch button):** only when moving at least 18 studs/s, e.g. out of a dash or sprint. A low, fast glide that loses speed over about 1 s. Free. Jumping out of a slide keeps the speed (a slide hop).
- **Double jump:** 1 pip in the air.
- **Wall jump:** jump while airborne next to a wall to kick off it. The first one is free, each later one in the same airtime costs 0.5 pip.
- **Noise:** dash and dash jump add 1.0 noise for 0.5 s (the monster hears it); slide, double jump and wall jump add 0.6 for 0.4 s.

The school also grows: corridors are about 1.7× longer, so the shortest walk to any exit is 420–520 studs. The round runs 180 s.

## Why
User request (sprint 39). Deadlock's movement rewards skill and timing without giving power. Research: [Deadlock wiki: Movement](https://deadlock.wiki/Movement), [Deadlock handbook](https://deadlockhandbook.com/mechanics/movement/).

## Acceptance criteria
- [x] Dash, dash jump, slide, slide hop, double jump and wall jump all work on keyboard; dash and slide have touch buttons. (wall jump, dash-to-slide and slide hop playtested after fixes; touch buttons not tried on a phone)
- [x] Stamina costs and regen match the numbers above; a stamina bar with 3 pips shows on the HUD. (costs playtested; the pips draining on a spend not seen by eye)
- [ ] Each move adds its noise on the server; the monster turns toward a dash. (a real Slide set the noise to 0.6 for 0.4 s, and the 5/s limit passes its spec; the monster turning toward a dash is untested)
- [x] The shortest walk from every spawn to every exit is 420–520 studs; spawns are at least 100 studs from the monster entry; the part count stays under 2,500. (446–519, ≥465, 2,411–2,453)
- [x] Monster patrol points cover the new areas; the round lasts 180 s; walking a full round doesn't drown you. (about 2.7 of 3.43 studs)
- [x] No Output errors; checks pass. (only the known 203785492 warning)

## Animations (sprint 40) — acceptance criteria
Procedural (Motor6D `Transform` on R15 and R6), with no uploaded animation assets. They play on every client: the local player animates at once, and other players animate from a `MoveAction` attribute on their character, set by the server.
- [x] Dash: the body leans hard into the dash direction and the arms sweep back, for about 0.25 s.
- [x] Dash jump: a tucked leap (knees up), then it opens out on the way down.
- [x] Slide: crouched low, one leg forward and the other tucked, leaning back, with one hand trailing; it eases out as the slide ends.
- [x] Slide hop: a quick tuck, then back to a normal jump. (other players guess it from the humanoid state, because the server isn't told about a SlideHop)
- [x] Double jump: a front-flip-style tuck spin (about 360° in 0.35 s) or a strong knee tuck. (full flip)
- [x] Wall jump: a push-off pose (arms out toward the wall side, legs kicking away).
- [x] It blends back to the default Roblox animations without snapping; it doesn't break the camera or the HitBox; no Output errors; checks pass. (seen by one player in Studio; two clients untested; R6 untested)

Implementation: `src/client/MovementAnimator.luau` handles both Motor6Ds and AnimationConstraints (this place's avatars use AnimationConstraints). `Movement.onAction(fn)` reports the local player's moves, and the server sets `MoveAction`/`MoveActionAt` on the character for other players.

## Momentum (sprint 41) — acceptance criteria
Speed is kept, CS/Deadlock style: letting go of W no longer stops you dead.
- [x] Ground: releasing all move keys decelerates with friction (from 24 to about 0 in roughly 0.5 s at sprint speed; from walk speed in 0.25 s), not instantly. Changing direction carries speed over. (measured 0.52 s and 0.28 s)
- [x] Air: no deceleration in the air; holding A/D while turning the camera air-strafes (it bends the path and can add a little speed, capped at 32 studs/s). (air speed held; the strafe gain wasn't measured)
- [x] Bunny hop and slide hop: jumping within 0.15 s of landing keeps the horizontal speed (no ground friction that frame). Chained hops cap at 32 studs/s. (3 hops held 24.0; slide hop 24.3)
- [x] Reward: a dash, slide or hop chain keeps you faster than sprinting without spending more stamina. Momentum speed above 18 is loud: the noise rule stays. (the dash carries into sprint; the slide starts at 29.9)
- [ ] The default walk and sprint still feel normal on the ground; touch controls (thumbstick) work; no Output errors; checks pass. (checks and Output OK; feel and thumbstick need a hand test)

Implementation: `Movement.luau` sets the horizontal velocity in PreSimulation (GROUND_FRICTION 7, a 32 cap, 0.15 s without friction after landing). A `MovementWish` render-step binding reads the input after the default control script.

## Bigger school: courtyard and second floor (sprint 41) — acceptance criteria
- [x] An open-air courtyard in the middle (grass, paths, a dead tree, benches and low walls), joined to the halls by at least 3 doorways. It's lit by moonlight, so it's brighter but exposed. (x -100..-42, west of the back hall; three 12×15 doorways)
- [x] A second floor over part of the school: at least 2 staircases and a broken railing or balcony where you can drop down to the courtyard. The water stays on the ground floor, so the second floor is dry but a longer way round. (a balcony at Y 21, two 60-stud ramps, 3 railing gaps)
- [x] The exits stay on the ground floor. The shortest walk from every spawn to every exit is 550–700 studs; at least one spawn is upstairs. (592–659; Start4 is upstairs, Start3 in the courtyard)
- [ ] The monster can path up the stairs and through the courtyard; its patrol points cover both. (paths up and down succeed and the patrol has Courtyard/Upstairs areas; the real monster wasn't seen climbing)
- [x] Part count under 3,200 (use big parts); no Output errors; checks pass. (2,900–2,901)

## Status (sprint 39)
Built; checks pass. Fixes after QA: the wall jump treated the first airborne frames as grounded, and the slide cancelled itself at once. Both now work. `MovementNoise.cloud.spec.luau` passes 6/6.

## Implementation
- `src/client/Movement.luau` (input, stamina, physics; it sets the LocalPlayer attribute `Stamina` 0–3, and fires the remote `Move` with an action name)
- The server checks the `Move` remote (a known action, at most 5/s, InRound and alive) and adds noise through `NoiseService.addNoise` (in `src/server/MovementNoise.luau`).
- HUD stamina pips and touch buttons are in `src/client/UI/Hud.luau`.
- The map is in `HallBuilder.luau`; patrol areas are in `Monster.luau`; round length is in `RoundService.luau`.

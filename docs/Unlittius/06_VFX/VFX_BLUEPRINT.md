# VFX BLUEPRINT

## Style rule

VFX should support the low-poly cave aesthetic.

Prefer:
- chunky stone fragments;
- dust;
- simple geometric particles;
- restrained purple glow;
- floor markers that look carved / mineral rather than sci-fi circles.

Avoid:
- huge anime particle cones;
- dense bloom;
- rainbow magic;
- screen-filling particles;
- transparent VFX that make first-person visibility unusable.

---

# Constant VFX

## Eyes
- two small violet emitters / neon shapes;
- subtle pulse;
- no giant bloom.

## Chest rune
- primary supernatural focal point;
- slight pulse;
- optional PointLight with small range;
- power scales by candles.

## Orbit stones
- 5–7 small stones;
- slow orbit;
- minor vertical offsets;
- rise during Dripstone / Gnawer summon;
- never become the Boulder Burst projectiles.

## Cape
No particle trail.
Use rigid-panel procedural sway only.

---

# Dripstone

During telegraph:
- dust drifts from ceiling;
- chosen dripstone shakes;
- floor marker appears.

Floor marker:
- irregular cracked stone decal / flat mesh;
- warm-purple mix depending chamber lighting;
- readable from first-person.

At snap:
- small shock pulse around chest / hands.

At impact:
- angular debris;
- dust puff;
- small ground chip fragments.

---

# Boulder Burst

Conjure:
- boulder begins at 10–15% scale;
- small stone fragments pull inward;
- faint violet core flash;
- grow to full size over ~0.6s.

Launch:
- short directional violet pressure streak from hand direction;
- no orbit;
- no beam tether unless extremely subtle.

Flight:
- minimal dust / grit;
- optional faint rock particles.

Impact:
- heavy debris;
- dust cone;
- brief ground decal/chip.

---

# Summon Gnawers

During arm rise:
- orbit stones rise;
- chest rune stretches/pulses;
- dust starts lifting around valid spawn points.

Spawn:
- stone crack line;
- dirt/dust burst;
- Gnawer emerges / appears using existing system.

Keep spawn VFX low enough not to hide the enemy.

---

# Melee

Windup:
- minimal violet edge on talons.

Swipe:
- one thin low-poly arc trail per claw pass;
- fast fade;
- do not make giant sword slashes.

World hit:
- small stone spark / grit burst.

Player hit:
- rely on existing damage feedback plus a tiny contact flash.

---

# Candle recoil

Required:
- chest rune flares white-violet for 1–2 frames;
- eyes flicker;
- orbit stones jump outward;
- violet hairline cracks briefly illuminate;
- then permanent dim step.

Suggested `BossPower`:
```text
power = 1 - candlesLit / 8
```

Apply to:
- eye brightness;
- rune brightness;
- rune light intensity;
- supernatural particles;
- rune hum volume.

Do not make the physical body fade every candle.

---

# Banishment

Phase 1:
- orbit stones vibrate and rise.

Phase 2:
- violet cracks expand across torso.

Phase 3:
- boss rises;
- dust falls FROM ceiling as he approaches;
- cape/back enters rock first.

Phase 4:
- optional geometry swap to ceiling relief;
- large dust burst;
- stone crack seam around relief.

Phase 5:
- violet light retracts into cracks and turns off;
- chamber warm lighting remains.

The end frame should be calm.

# ANIMATION BLUEPRINT

## General rules

- Use the current HTML viewer timing as the baseline.
- Animation should feel weighty, not floaty.
- Use animation markers in the published Roblox animations for VFX/audio synchronization.
- Server-side gameplay events should still be driven by authoritative attack timing, not trusted solely from a client marker.
- Keep the boss position rooted except the small melee lunge and the banish rise.

## Required animation library

| Animation | Duration | Loop | Main purpose |
|---|---:|---:|---|
| `Idle` | 6.00s | yes | heavy hovering / scanning |
| `Dripstone` | 2.60s | no | ceiling attack |
| `BoulderBurst` | 2.45s | no | two magically directed projectiles |
| `SummonGnawers` | 3.05s | no | ritual summon |
| `MeleeDoubleRake` | 1.55s | no | close-range punish |
| `CandleRecoil` | 1.70s | no | progress feedback |
| `Banish` | 3.40s | no | ceiling relief transition |

---

# Idle — 6.0 seconds looping

Motion:
- tiny vertical hover;
- chest and shoulder plate drift;
- head slowly scans;
- claws slightly flex / rotate;
- orbit stones counter-rotate;
- cape panels lag by only a few degrees.

Do not:
- bob like a balloon;
- wave arms;
- make symmetrical robotic movements.

Suggested poses:
- 0.0s: head ~10° left, torso ~2° forward
- 3.0s: head ~12° right, torso slight counter-turn
- 6.0s: return

---

# Dripstone — 2.60 seconds

### Timing

**0.00–0.90**
- both arms begin rising;
- torso leans back;
- head follows late;
- ceiling rumble begins.

**0.90–1.45**
- full raised position;
- chest rune brightens;
- selected ceiling pieces tremble;
- impact indicators should already be visible.

**1.45–1.62**
- micro-hold followed by violent downward snap.

**1.62**
- gameplay event: `DripstoneSnap`
- detach / begin falling selected stones.

**1.62–2.47**
- fall / impact period.

**2.47–2.60**
- return toward neutral.

### Markers

- `TelegraphStart` @ 0.10
- `CeilingShake` @ 0.90
- `DripstoneSnap` @ 1.62
- `Recover` @ 2.45

---

# Boulder Burst — 2.45 seconds

The boulders are spell objects. Hands never touch them.

### Timing

**0.00–0.55**
- arms open and rise to conduct;
- two boulder spawn anchors light up.

**0.18**
- left/right boulder begins materializing.

**0.55–0.92**
- boulders reach full size;
- arms move into forward conducting pose.

**0.92**
- `BoulderFire1`

**1.16 ± 0.04**
- `BoulderFire2`

**1.16–1.65**
- follow-through.

**1.65–2.45**
- settle.

### Visual placement

Boulder origins:
- outside shoulder silhouette;
- roughly 3–4 studs left/right from root;
- slightly above chest level;
- slightly forward or beside the boss;
- never behind the torso if that makes the flight path clip through him.

### Projectile behavior

- target is selected on server;
- direction is sampled independently for each shot;
- optional small velocity prediction;
- after release, do not hard-home;
- second shot may use updated target position;
- spherecast along motion path to avoid tunneling.

### Markers

- `BoulderConjure` @ 0.18
- `BoulderReady` @ 0.72
- `BoulderFire1` @ 0.92
- `BoulderFire2` @ 1.16
- `Recover` @ 1.70

---

# Summon Gnawers — 3.05 seconds

This must look like summoning.

### Timing

**0.00–0.70**
- arms rise;
- elbows widen;
- palms/talons rotate upward.

**0.70–1.30**
- head tilts back;
- shoulders open;
- orbit stones rise.

**1.30**
- full ritual pose.

**1.35–1.55**
- `GnawerSpawn`

**1.30–2.15**
- hold the pose;
- ground dust / cracks / enemy arrival.

**2.15–3.05**
- slow recovery.

### Markers

- `SummonCharge` @ 0.25
- `SummonOpen` @ 0.80
- `GnawerSpawn` @ 1.42
- `Recover` @ 2.20

---

# Melee Double Rake — 1.55 seconds

Trigger only when a valid player is too close.

### Timing

**0.00–0.28**
- pull both hands back;
- torso compresses slightly;
- claws visibly open.

**0.28–0.56**
- first side attacks.

**0.56**
- `MeleeHit1`

**0.56–0.82**
- opposite side crosses through.

**0.82**
- `MeleeHit2`

**0.82–1.55**
- recover.

Root:
- small forward lunge only;
- about 1–1.5 studs maximum;
- no arena movement.

### Markers

- `MeleeWindup` @ 0.08
- `MeleeHit1` @ 0.56
- `MeleeHit2` @ 0.82
- `MeleeRecover` @ 0.96

---

# Candle Recoil — 1.70 seconds

Purpose:
Make every candle feel like direct progress.

**0.00–0.13**
- instant shock;
- chest flare/flicker.

**0.13**
- recoil peak.

**0.13–0.90**
- defensive shield posture.

**0.90–1.70**
- unstable return.

Markers:
- `RecoilImpact` @ 0.10
- `RuneDimStep` @ 0.22
- `Recover` @ 1.50

If a candle is lit during an attack:
- cancel current action if safe;
- recoil should take priority over normal attacks;
- gameplay damage event that already fired should not be retroactively canceled.

---

# Banish — 3.40 seconds

Goal:
Become a ceiling sculpture.

**0.00–0.45**
- rune destabilizes;
- body recoils upward;
- arms spread.

**0.45–1.25**
- strong upward pull begins.

**0.55–2.40**
- rotate toward -90° local pitch so front faces downward once embedded.

**1.25–2.30**
- arms settle into relief pose.

**2.30–3.20**
- enter ceiling plane;
- cape and back disappear first;
- torso/hood/claws remain as shallow relief.

**3.20**
- `ReliefSwap`

**3.40**
- encounter complete.

Recommended production implementation:
- animate the live rig up to ~3.1s;
- fade / hide live rig;
- reveal prebuilt `CeilingRelief` at exact matching pose;
- stop Animator;
- leave relief anchored.

Markers:
- `BanishStart` @ 0.00
- `CeilingPull` @ 0.55
- `ReliefAlign` @ 2.30
- `ReliefSwap` @ 3.20
- `BanishComplete` @ 3.40

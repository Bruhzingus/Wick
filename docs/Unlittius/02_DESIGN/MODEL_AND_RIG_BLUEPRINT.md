# MODEL + RIG BLUEPRINT

## Recommended production representation

Use a non-Humanoid rig:
- `Model`
- `AnimationController`
- `Animator`
- `Motor6D` joints for animated hard-surface parts

The boss does not need normal humanoid locomotion.

If the existing project already has a custom enemy rig standard, use that instead of creating a second animation architecture.

## Suggested hierarchy

```text
Unlittius
├── BossRoot                    # invisible root / PrimaryPart
├── AnimationController
│   └── Animator
├── Rig
│   ├── Core
│   ├── PelvisStone
│   ├── FloatStone_A
│   ├── FloatStone_B
│   ├── FloatStone_C
│   ├── Torso
│   ├── ChestRune
│   ├── Neck
│   ├── Head
│   ├── Hood
│   ├── Shoulder_L
│   ├── UpperArm_L
│   ├── Forearm_L
│   ├── Hand_L
│   ├── Claw_L_1
│   ├── Claw_L_2
│   ├── Claw_L_3
│   ├── ThumbClaw_L
│   ├── Shoulder_R
│   ├── UpperArm_R
│   ├── Forearm_R
│   ├── Hand_R
│   ├── Claw_R_1
│   ├── Claw_R_2
│   ├── Claw_R_3
│   ├── ThumbClaw_R
│   ├── CapeRoot
│   ├── CapePanel_1
│   ├── CapePanel_2
│   ├── CapePanel_3
│   ├── CapePanel_4
│   └── CapePanel_5
├── OrbitStones
│   ├── Stone_01
│   ├── Stone_02
│   ├── ...
├── Attachments
│   ├── ChestFX
│   ├── HeadFX
│   ├── BoulderSpawn_L
│   ├── BoulderSpawn_R
│   ├── MeleeTrace_L
│   ├── MeleeTrace_R
│   ├── AudioEmitter
│   └── CeilingAnchor
└── CeilingRelief               # optional hidden final statue/relief model
```

## Joint list

Minimum animation joints:
- Root → Core
- Core → PelvisStone
- Core → Torso
- Torso → Neck
- Neck → Head
- Head → Hood/Crown
- Torso → Shoulder_L
- Shoulder_L → UpperArm_L
- UpperArm_L → Forearm_L
- Forearm_L → Hand_L
- same for right side
- Torso → CapeRoot

Cape:
- simplest option: cape panels attached under one `CapeRoot`;
- better option: 3 animation joints across top of cape so outer panels lag during big arm motions;
- do not use full cloth simulation unless the existing project already depends on it.

## Collision

Boss visual parts:
- `CanCollide = false`
- `CanTouch = false` unless specifically used
- `CanQuery = false` for decorative pieces where possible

Use dedicated invisible query / hitbox parts or pure spatial queries for attacks.

## Materials

Recommended:
- main stone: `Slate`, `Rock`, or custom cave MaterialVariant depending existing art direction;
- dark cavities: near-black matte material;
- purple rune: Neon or emissive-looking mesh/part with restrained brightness;
- cape: dark stone-cloth appearance, still rough and low-poly.

## Proportions

Target:
- shoulder width: 4.4–4.8 studs
- torso width: 3.5–4.0 studs
- torso height: 2.7–3.2 studs
- hood visible height: 3.0–3.6 studs
- upper arm: 1.8–2.0 studs
- forearm: 1.7–1.9 studs
- claw extension past wrist: 1.6–1.9 studs
- compact lower floating cluster: 2.0–2.8 studs total
- cape length from shoulders: 3.8–4.8 studs

These are starting dimensions, not hard constraints. Preserve silhouette before exact numbers.

## Arm revision

The package HTML viewer already applies the shorter arm revision.

Do not shorten the talons to match. The entire reason for shortening the limb is to make the hand threat feel larger and the upper body more powerful.

## Cape construction

Prefer:
- 4–5 broad low-poly panels;
- overlap between panels;
- irregular hem;
- asymmetry in panel length;
- one large center panel;
- two outer panels that flare slightly.

Avoid:
- 8+ narrow vertical strips;
- perfect rectangle;
- smooth superhero cape;
- cloth that flaps violently.

## Ceiling relief

Recommended separate final asset:
- flattened version of torso/head/hood/arms;
- claws spread outward;
- cape omitted or mostly buried;
- same stone material as ceiling;
- no collision;
- subtle cracks around perimeter;
- optional tiny residual purple seam for 1–2 seconds, then off.

# ENCOUNTER + ATTACK LOGIC

## 1. Server-authoritative encounter state

Recommended states:

```text
Dormant
Intro
Active
Recoil
Banishing
Complete
Resetting
```

Authoritative server values:
- encounter active;
- candle lit set / count;
- current boss action;
- current target(s);
- action start server timestamp;
- active Gnawer count;
- active projectile records;
- complete / banished flag.

Clients should receive state and timestamps for visuals, not decide whether attacks hit.

---

# 2. Candle progression

Exactly 8 encounter candles.

Each candle should have a stable ID:
- Candle01
- Candle02
- ...
- Candle08

When a candle successfully changes from unlit → lit:
1. validate server-side;
2. mark candle immutable for this encounter;
3. increment `CandlesLit`;
4. cancel normal attack scheduling briefly;
5. play `CandleRecoil`;
6. broadcast progress event;
7. reduce boss rune/eye power;
8. update chamber lighting;
9. if count == 8, begin banish.

Do not allow:
- one candle to count twice;
- client to set total candle count;
- multiple recoil sequences stacking on top of each other.

If two candles legitimately become lit nearly simultaneously:
- queue or compress recoil feedback;
- do not run two separate conflicting full-body animations at once.

---

# 3. Attack scheduler

Do not choose attacks by pure random spam.

Recommended decision order:

1. If banishing / recoiling → no selection.
2. If a player is inside melee trigger radius → strongly prefer Melee.
3. If Gnawer cap is not met and summon cooldown is ready → Summon Gnawers becomes eligible.
4. If players are at range → Boulder Burst gets increased weight.
5. Dripstone remains the reliable arena-control option.
6. Avoid repeating the exact same major attack more than twice in a row.

Suggested base weights:
- Dripstone: 34
- Boulder Burst: 32
- Summon Gnawers: 22
- Melee: conditional, not normal weighted roll

Suggested idle delay between attacks:
- 0–2 candles: 2.2–3.0s
- 3–5 candles: 1.9–2.6s
- 6–7 candles: 1.6–2.3s

Do not shorten attack telegraphs as the fight progresses. Reduce downtime instead.

---

# 4. Recommended starting damage / tuning

These are **starting playtest numbers**, not sacred balance.

## Dripstone
- number of strike zones:
  - solo: 4
  - duo: 5
  - 3+ players: 6
- telegraph before drop: ~1.4–1.6s
- impact radius: 2.5–3.25 studs
- damage: 32–42
- optional small stagger / camera shake
- avoid unavoidable overlapping markers

## Boulder Burst
- exactly 2 boulders
- shot delay: 0.22–0.28s
- radius: 1.7–2.2 studs
- speed: ~38–46 studs/sec
- max travel: chamber-dependent, typically 35–55 studs
- damage: 30–38
- modest knockback
- do not home after launch

## Summon Gnawers
Use existing enemy tuning.

Recommended boss-specific spawn count:
- solo: 1
- duo: 1–2
- 3–4 players: 2
- active boss-summoned Gnawer cap: 3–4

Avoid summoning when active cap is already reached.

## Melee
- trigger radius: roughly 5.5–6.5 studs from boss center
- two hit windows
- damage per swipe: 18–24
- one player may be hit by both if they remain in the area
- short knockback on second hit
- total maximum should hurt badly but not necessarily one-shot a healthy player

---

# 5. Boulder implementation

Preferred production behavior:

### Spawn
- server chooses target;
- create logical projectile at `BoulderSpawn_L` / `BoulderSpawn_R`;
- clients render large low-poly boulder VFX objects.

### Aim
For each shot:
```text
targetPoint =
    currentCharacterPosition
    + horizontalVelocity * smallLeadTime
```

Recommended lead time:
- 0.10–0.22 seconds

Clamp extreme velocity prediction so the shot does not wildly miss.

### Flight
Use deterministic movement.

Good option:
- server advances projectile position;
- each step performs `Workspace:Spherecast()` from previous position to next position;
- server decides hit;
- clients interpolate / animate matching visuals.

This avoids relying on unstable client physics and reduces tunneling.

### On hit
- player hit → damage + knockback + impact event;
- cave geometry hit → impact VFX;
- lifetime exceeded → despawn.

Do not allow one boulder to damage the same player repeatedly.

---

# 6. Melee hit detection

Do not use the visual claw MeshParts themselves as the only hitbox.

At each hit time:
- build an oriented box / sweep volume in front of the active claw;
- query with `GetPartBoundsInBox` + `OverlapParams`, OR use existing combat hitbox code;
- map returned character parts to a unique player/character;
- one damage event per player per swipe.

Suggested two volumes:
- left rake at 0.56s;
- right rake at 0.82s.

The box should follow the hand attachment / wrist orientation.

---

# 7. Dripstone

Server chooses ceiling pieces / landing locations.

Recommended:
- avoid selecting locations directly under invalid geometry;
- ensure at least one safe route remains;
- distribute markers around player positions without fully surrounding them;
- use floor telegraph decal / flat part / particle marker;
- actual visual stone may be animated client-side, but damage timing remains server-side.

---

# 8. Gnawer summon integration

Do not fork Gnawer AI.

Claude should find:
- existing enemy factory;
- existing Stone Gnawer module/prefab;
- existing spawn registration;
- active enemy limits.

The boss only requests:
```text
SpawnEnemy("StoneGnawer", spawnPoint, bossSummoned=true)
```
or the local project equivalent.

If current Stone Gnawers still use sound-oriented hunting, keep that behavior.

---

# 9. Target selection

Priority:
- valid, alive, encounter participants only;
- nearest player for melee;
- ranged attacks may rotate target to reduce frustration.

Boulder target selection:
- with 1 player: both shots at that player;
- with 2+ players: optionally choose separate targets if both are valid and visible.

Avoid:
- targeting players outside encounter;
- firing through walls if line-of-sight matters in the chamber;
- repeatedly selecting dead/downed players.

---

# 10. Reset / cleanup

On reset / wipe / encounter teardown:
- stop all boss AnimationTracks;
- destroy active boulders;
- destroy boss-specific telegraph VFX;
- stop / fade boss audio loops;
- despawn boss-summoned Gnawers if that matches floor reset rules;
- reset candles through the existing candle/floor system;
- return boss rig to idle transform;
- hide ceiling relief;
- restore rune strength.

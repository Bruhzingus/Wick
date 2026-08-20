# ROBLOX / ROJO ARCHITECTURE

This is a recommended architecture, not a demand to replace the project's existing systems.

Claude must inspect the repository first.

## Core rule

**Integrate with existing WICK services instead of building a parallel framework.**

Before writing code, Claude should identify:
- enemy/boss controller patterns;
- damage service;
- room/floor lifecycle;
- candle interaction logic;
- enemy spawn service;
- Stone Gnawer implementation;
- audio service / SoundGroups;
- VFX remotes;
- player state / death rules;
- Rojo project layout.

---

# Recommended conceptual modules

```text
Unlittius/
├── UnlittiusConfig
├── UnlittiusController
├── UnlittiusAttackDirector
├── Attacks/
│   ├── Dripstone
│   ├── BoulderBurst
│   ├── SummonGnawers
│   └── Melee
├── UnlittiusAnimation
├── UnlittiusAudio
├── UnlittiusVFX
└── UnlittiusRigMap
```

Client:
```text
UnlittiusClient
├── receives replicated attack start events
├── plays local cosmetic VFX
├── interpolates boulder visuals
├── camera shake
└── non-authoritative sound polish
```

---

# Rig / animation

For a non-Humanoid animated rig:
- use `AnimationController`;
- parent an `Animator`;
- connect rigid pieces with `Motor6D`;
- publish animations and load them through `Animator`.

If the project already has a custom animation driver, use it.

Important:
- do not use a Humanoid just to get animation if it complicates collision/pathfinding;
- boss is not walking.

---

# Server/client synchronization

Recommended event payload:

```lua
{
    encounterId = "...",
    action = "BoulderBurst",
    startTime = workspace:GetServerTimeNow(),
    seed = 12345,
    targetUserIds = {...},
    candleCount = 3,
}
```

Clients compare against `workspace:GetServerTimeNow()` and seek / start cosmetic timelines at the correct offset.

Use a reliable `RemoteEvent` for:
- attack start;
- candle recoil;
- banish;
- major one-shot state changes.

Do not let clients send "attack hit" decisions to the server.

---

# Damage / spatial queries

Melee:
- `GetPartBoundsInBox` + `OverlapParams`, or existing combat hitbox utility.

Boulder:
- deterministic server projectile;
- advance position at fixed/heartbeat step;
- `Workspace:Spherecast()` from previous to next position.

Dripstone:
- server owns chosen impact position + impact time;
- clients visualize the falling rock.

---

# Collection / registration

If existing project uses tags:
- tag encounter candles;
- tag boss spawn points;
- tag Gnawer spawn points.

If it uses explicit room registries, use those instead.

Do not introduce CollectionService just because this document mentions it if the repo already has a better registration system.

---

# Network ownership / physics

The boss itself should generally not depend on client-owned physics.

For animated visual pieces:
- keep rig anchored through root / non-physical animation pattern as compatible with existing rig system.

For boulders:
- visual part may be client cosmetic;
- logical collision remains server-authoritative.

---

# Performance

Keep:
- boss part count reasonable;
- particle count low;
- only 2 boulders per burst;
- orbit stones 5–7;
- cape panels ~4–5;
- no per-frame server scans of every character unless necessary.

Use attack windows rather than permanent overlap loops.

---

# Animation markers

Use marker names matching `03_ANIMATION/ANIMATION_MARKERS.csv`.

Markers are especially useful for:
- sound;
- VFX;
- editor alignment.

Authoritative damage should be tied to the server action timeline so it cannot be spoofed by a client.

---

# Ceiling relief

Recommended:
- `CeilingRelief` stored with boss asset;
- hidden during fight;
- matched to ceiling anchor CFrame;
- reveal at `ReliefSwap`;
- hide live rig;
- anchor relief;
- leave it in room.

This is more robust than leaving a live animation rig rotated inside the ceiling forever.

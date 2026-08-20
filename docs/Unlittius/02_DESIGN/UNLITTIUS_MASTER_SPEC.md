# UNLITTIUS — MASTER DESIGN SPEC

## 1. Boss fantasy

Unlittius should feel like an ancient cave shrine guardian that was never meant to walk.

He is:
- part carved stone deity;
- part cave sorcerer;
- part cursed shrine sculpture;
- suspended above a ritual dais;
- animated by dim violet energy;
- physically heavy despite floating;
- silent in personality, but extremely communicative through pose, stone movement, and sound.

He should **not** read as:
- a standard humanoid NPC;
- a knight;
- a robot;
- a wizard wearing normal cloth;
- a golem that walks around;
- a fast acrobatic monster;
- a bright fantasy spellcaster.

His identity is built around contradiction:
- massive stone mass, but levitating;
- long threatening claws, but ritualistic movements;
- violent attacks, but no frantic locomotion;
- visually alive during the encounter, then literally returns to architecture when banished.

---

# 2. Encounter premise

The encounter revolves around **8 candles positioned around the chamber**.

The boss itself is not the objective to damage. The player is trying to restore light to the room while Unlittius prevents them from safely doing so.

Every candle lit:
1. advances encounter progress;
2. triggers a highly visible recoil from Unlittius;
3. permanently weakens the intensity of his purple eyes / chest rune;
4. slightly reduces the supernatural dominance of his audio and VFX;
5. makes the chamber itself feel more reclaimed by warm light.

At 8/8 candles:
- stop all attack scheduling;
- cancel / suppress future enemy summons;
- enter the banishment sequence;
- pull Unlittius into the ceiling;
- end with him embedded as an engraved / sculpted stone relief;
- leave the chamber lit after the sequence.

There should be no corpse and no conventional death collapse.

---

# 3. Final silhouette

## Overall proportions

Target visual height while active:
- approximately **11–12.5 studs** from the lowest major floating base stone to hood tip;
- do not count orbiting pebbles in height;
- shoulder width approximately **4.4–4.8 studs**;
- chest should be visibly broader than the waist / floating base;
- arms should be intimidating but no longer extremely gangly.

### Final arm direction

The final package deliberately shortens the arm geometry from the previous viewer.

Suggested model proportions:
- shoulder joint → elbow: ~1.8–2.0 studs;
- elbow → wrist: ~1.7–1.9 studs;
- wrist/palm → longest claw tip: ~1.6–1.9 studs;
- claws remain large relative to the shortened arm.

The arm itself should now read as a powerful hanging limb with oversized talons, rather than a very long limb ending in fingers.

## Resting pose

- shoulders low and heavy;
- upper arms fall down and slightly forward;
- elbows have a modest natural bend;
- forearms angle down;
- wrists subtly rotate inward;
- talons point down and inward, but do not touch;
- hands should sit clearly outside the centerline of the torso;
- avoid any idle pose where the hands form a neat symmetrical "prayer" shape.

The idle should feel like gravity is pulling on a body that magic barely keeps suspended.

---

# 4. Body construction

## Head / hood

The hood is one of the strongest identifiers.

Required:
- tall, pointed, roughly pentagonal/faceted hood;
- black recessed face void;
- two small violet eyes;
- visible faceted brim / band;
- slightly broken or crooked top detail;
- side stone fins / cheek armor;
- asymmetry should be subtle, not cartoonish.

The hood should look carved, layered, and old rather than a single smooth cone.

## Face

No mouth.

No visible skull.

No normal facial expression.

Use:
- a deep black face cavity;
- violet eye lights;
- optional tiny stone hanging pieces under the face to create a ragged, beard-like silhouette.

The face is scary because it is unreadable.

## Torso

The torso must be intimidating.

Required:
- broad upper chest;
- layered faceted rib-like stone plates;
- dark cavity around the chest rune;
- strong narrowing into the lower torso;
- large shoulder masses;
- no smooth cylindrical body.

The chest rune / "unlit heart":
- violet;
- compact;
- clearly brighter than all other purple accents;
- pulses subtly;
- dims permanently per candle.

## Shoulders

- large enough to frame the hood;
- multiple jagged stone layers;
- 2–3 short spikes / dripstone-like protrusions per shoulder;
- shoulders should visually connect the body to the cave itself.

## Arms

- shorter than the previous revision;
- faceted stone upper arm;
- darker joint/cuff region;
- faceted stone forearm;
- large wrist block;
- no flesh;
- no visible humanoid fingers.

## Claws

This is a critical feature.

Each hand should be constructed around:
- a compact palm;
- **three primary scythe-like talons**;
- one opposing thumb talon;
- thick stone roots;
- narrow dark middle section;
- sharp stone blade tip.

They should look capable of opening a person, not typing on a keyboard.

Rules:
- claws curve down and slightly inward;
- tips should be visibly separated;
- avoid four parallel finger sticks;
- avoid human knuckles;
- avoid tiny nail tips;
- the silhouette should remain readable in near-black lighting.

## Cape

The cape replaces the earlier back lantern concept.

It should be:
- broad;
- continuous;
- layered;
- torn;
- uneven;
- heavy-looking;
- low-poly;
- slightly rigid, not a fabric simulation noodle curtain.

Recommended:
- shoulder mantle under/behind the shoulder armor;
- 4–5 large overlapping cape panels;
- irregular triangular bites / tears at bottom;
- a few harder fold wedges;
- optional 3–4 small talisman tags attached directly to the cape.

Do **not** build the cape from many narrow vertical strips.

The cape can have very subtle procedural movement, but it should mostly feel stone-heavy and old.

---

# 5. Lower body

Unlittius has **no legs**.

Do not add a walk cycle.

Do not add feet.

The lower body ends in:
- 3 compact major floating stones directly under the torso;
- 4–6 much smaller fragments loosely orbiting nearby;
- a broad upper stone that visually replaces a pelvis;
- a very short taper.

The final shape should be stubby, not a long tornado or vertical spine.

The boss should look like a statue whose lower pedestal shattered and is being held in place by magic.

---

# 6. Material / color direction

Base:
- charcoal;
- dirty dark gray;
- muted brown-black;
- dry basalt / cave stone;
- very high roughness.

Accent:
- violet energy in eyes / chest rune / limited cracks.

Environment contrast:
- boss = cold/dark;
- candles = warm amber;
- as candles are lit, the chamber wins the color battle.

Avoid:
- shiny metal;
- bright saturated purple armor;
- glossy obsidian everywhere;
- neon outlines around the whole boss.

---

# 7. Motion language

Unlittius should never feel lightweight.

All movement should obey these principles:
1. anticipation is slow enough to read;
2. actual attack release can be fast;
3. body mass lags behind hand movement slightly;
4. the floating base moves less than the upper body;
5. the head often moves last;
6. the claws should overshoot slightly during violent actions;
7. no unnecessary spins;
8. no running, stepping, jumping, or strafing.

He is rooted to the dais in positional gameplay even though he physically hovers.

---

# 8. Gameplay attack roster

Core states:
- Idle
- Dripstone
- Boulder Burst
- Summon Gnawers
- Melee
- Candle Recoil
- Banished

There is explicitly **no candle-snuff attack** in the final design.

## Dripstone

Fantasy:
Unlittius pulls the cave ceiling down.

Visual:
- arms rise;
- chest rune intensifies;
- ceiling pieces begin to tremble;
- marked impact zones appear on the floor;
- he performs a hard downward conducting snap;
- selected dripstone falls.

Counterplay:
- read the floor markers;
- move out before impact.

Do not make markers appear only at the instant of impact.

## Boulder Burst

Fantasy:
He conjures two massive stones and hurls them with sorcery.

Rules:
- he does NOT physically grab the boulders;
- boulders materialize outside the left and right shoulder region;
- boulders must never pass through his torso during their conjure path;
- he raises and opens his arms as if controlling them;
- shot #1 fires;
- shot #2 follows ~0.22–0.28 seconds later;
- both travel in a tight forward burst toward the intended player.

Do not:
- spray boulders radially;
- orbit the projectiles around him first;
- spawn tiny rocks and call them boulders;
- continuously home after launch.

Recommended fairness:
- snapshot target position or a modest predicted position at each release;
- after release, travel mostly straight;
- large enough to be scary but readable to dodge.

## Summon Gnawers

Fantasy:
A ritual summoning, not an attack swing.

Motion:
- shoulders open;
- both arms lift;
- palms / claws open upward;
- head tilts back;
- stones around him rise slightly;
- hold the pose;
- spawn Gnawers during the hold;
- slowly settle.

Reuse the existing Gnawer enemy system rather than creating a boss-specific duplicate AI.

## Melee

Purpose:
Prevent players from safely hugging the dais / camping underneath him.

Motion:
- short pullback;
- fast left rake;
- fast right rake;
- small upper-body lunge;
- recover.

Do not move the boss across the arena.

## Candle Recoil

Every successful candle light should hit him like a direct wound even though he has no health.

Required:
- sharp recoil;
- shoulders rise defensively;
- head jerks away;
- rune flicker;
- nearby orbit stones kick outward;
- loud stone / magical suppression sound.

This is the main progress feedback.

## Banishment

The boss is not killed.

Sequence:
1. attacks stop;
2. rune becomes unstable;
3. arms spread;
4. body rises toward the ceiling;
5. body rolls to lie flat against the ceiling plane;
6. cape / back side is swallowed into rock;
7. torso, hood and arms settle into a shallow stone relief;
8. violet glow disappears or becomes nearly invisible;
9. final stone seam seals;
10. the room remains lit.

The final result should look like he has always been carved into the ceiling.

For the production version, it is acceptable — and probably cleaner — to swap the animated boss rig at the final frame for a purpose-built anchored `CeilingRelief` model.

---

# 9. Phase / candle progression

Do not scale raw damage upward every candle.

The player should feel that lighting candles is working.

Recommended progression:

### 0–2 candles
- strongest rune / eyes;
- slowest overall attack cadence;
- simplest patterns;
- sparse Gnawer count.

### 3–5 candles
- boss visually dimmer;
- slightly shorter downtime between actions;
- occasional attack sequencing pressure;
- no raw damage increase required.

### 6–7 candles
- very dim rune;
- more desperate animation;
- slightly faster attack selection;
- boulder burst and melee can be chosen more readily;
- never remove fair telegraphs.

### 8 candles
- no more attacks;
- banish.

---

# 10. Multiplayer principles

- Target selection should rotate when possible.
- Do not focus one player repeatedly unless they stay nearest for melee.
- Boulder shots can target the same player or two separate players depending party size.
- Gnawer cap should scale with party size.
- Candle state must be server authoritative.
- One candle lighting event should only count once.
- Encounter should not double-trigger recoil / progress if two players interact on the same frame.

---

# 11. What absolutely must survive implementation

If Claude needs to simplify during integration, preserve these first:

1. Eight-candle objective instead of boss HP.
2. Floating / legless body.
3. Short floating stone base.
4. Pointed hood + purple eyes.
5. Broad intimidating ribbed torso.
6. Large real talons.
7. Broad torn cape.
8. Dripstone attack.
9. Two-shot magically-directed boulder burst.
10. Proper arms-raised Gnawer summoning.
11. Close-range double claw melee.
12. Candle recoil.
13. Ceiling-relief banishment.

Everything else is secondary.

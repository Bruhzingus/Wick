# CLAUDE HANDOFF PROMPT — IMPLEMENT UNLITTIUS INTO WICK

I am giving you a zip package called `unlittius_boss_implementation_package`.

Your job is to **fully integrate Unlittius into the existing WICK Roblox project**, using the repository's existing systems wherever possible.

Do not treat the reference Luau files as a drop-in architecture. They are design / implementation examples.

## FIRST: inspect the repository

Before editing anything, identify:

1. Rojo project structure and all `*.project.json` files.
2. Existing enemy architecture.
3. Existing boss architecture, if any.
4. Existing model-building / rig-building patterns.
5. Existing AnimationController / Animator utilities.
6. Existing damage and hitbox utilities.
7. Existing projectile utilities.
8. Existing VFX remotes / client FX controller.
9. Existing sound system and SoundGroups.
10. Existing room/floor lifecycle.
11. Existing candle / interaction systems.
12. Existing Stone Gnawer enemy implementation and spawn pathway.
13. Existing player-death / wipe / encounter reset logic.
14. Existing configuration / tuning conventions.

Then tell me what architecture you found and where Unlittius should slot in.

Do not create redundant services if equivalents already exist.

---

# SOURCE OF TRUTH

Use package files in this order:

1. `02_DESIGN/UNLITTIUS_MASTER_SPEC.md`
2. `03_ANIMATION/ANIMATION_BLUEPRINT.md`
3. `01_REFERENCE/Unlittius_REFERENCE_VIEWER_shorter_arms.html`
4. `01_REFERENCE/Unlittius_4_angle_visual_reference.png`
5. supporting technical docs

The HTML file is a **reference viewer only**. Do not embed Three.js or HTML into Roblox.

The current visual revision intentionally has arms slightly shorter than the prior viewer, while preserving the oversized claws.

---

# CORE BOSS REQUIREMENTS

Unlittius:
- is a floating, legless stone cave deity;
- stays centered/rooted over the boss dais;
- has a compact floating stone base, not a vertical tornado;
- has several smaller orbiting stones;
- has a broad intimidating ribbed torso;
- has a tall faceted pointed hood;
- has a black face void and two violet eyes;
- has a violet chest rune / heart;
- has shortened stone arms;
- has huge hooked talons that read as claws, not fingers;
- has a broad torn low-poly cape;
- is not a standard Humanoid walker.

Do not add a walk cycle.

---

# FIGHT OBJECTIVE

The boss should not use a normal health bar.

There are 8 encounter candles.

Lighting a candle:
- is server-authoritative;
- counts exactly once;
- triggers boss recoil;
- permanently dims his rune/eyes by one step;
- increases warm chamber lighting;
- updates progress.

At 8/8:
- no more attacks;
- start banishment;
- turn him into a ceiling relief/sculpture;
- chamber stays lit.

There is NO candle-snuff attack.

---

# ATTACKS TO IMPLEMENT

## 1. Dripstone
Animation timing from package.
- raise arms;
- telegraph floor impact zones during rise;
- downward snap;
- ceiling stones fall at snap time;
- damage on impact server-side.

## 2. Boulder Burst
Exactly TWO large boulders.

He DOES NOT grab them.

They:
- conjure outside/above his shoulders;
- become full size;
- fire toward player(s) ~0.24s apart;
- travel mostly straight after launch;
- must not originate inside the boss or pass through his torso.

Use server-authoritative collision, ideally a deterministic projectile + Spherecast if compatible with existing code.

## 3. Summon Gnawers
Must look like ritual summoning:
- both arms rise;
- palms/talons open upward;
- head tilts back;
- hold;
- spawn existing Stone Gnawers through existing enemy spawn architecture.

Do not duplicate Gnawer AI.

## 4. Melee Double Rake
If player gets too close:
- short windup;
- left/right crossing claw rakes;
- two authoritative hit windows;
- tiny forward upper-body/root lunge only;
- no chase.

## 5. Candle Recoil
High-priority feedback animation whenever a candle is successfully lit.

## 6. Banish
- stop combat;
- pull him upward;
- rotate him flat against ceiling;
- embed as an architectural relief;
- preferably swap to a dedicated anchored `CeilingRelief` asset at the final frame.

---

# ANIMATIONS

Use `03_ANIMATION/ANIMATION_BLUEPRINT.md`.

If the project's animation pipeline requires Studio animation assets:
1. build/rig the model first;
2. create/publish animations using the exact joint hierarchy;
3. add the animation asset IDs to the project's config;
4. use the marker names in `ANIMATION_MARKERS.csv`.

If you cannot publish animation assets automatically, build everything else and leave explicit ID placeholders plus a precise list of animations I must upload manually.

Do not fake animation IDs.

---

# MODEL BUILD

Because I work primarily through Rojo/VS Code, prefer a workflow that minimizes manual Studio-only reconstruction.

If the project already has a procedural low-poly model builder:
- build Unlittius through that system.

Otherwise:
- create a dedicated rig builder ModuleScript or one-time build utility that constructs the model using Parts/Wedges/MeshParts and Motor6Ds;
- keep geometry definitions centralized;
- make it easy to tune proportions in code;
- do not scatter 100 magic numbers across attack scripts.

Once generated, it must have:
- stable named joints;
- stable named attachments;
- AnimationController + Animator;
- non-colliding decorative geometry;
- melee trace attachments;
- boulder spawn attachments;
- chest/head FX attachments;
- ceiling anchor / relief support.

---

# SERVER AUTHORITY

The server owns:
- candle count;
- boss state;
- action selection;
- target selection;
- damage;
- melee hit checks;
- boulder trajectory/collision;
- dripstone impacts;
- Gnawer spawn requests;
- banish completion.

Clients own:
- cosmetic particles;
- camera shake;
- local boulder interpolation if desired;
- sound polish;
- visual telegraphs after receiving authoritative timestamps.

Use current project networking conventions.

For synchronized visual start times, use server timestamps such as `workspace:GetServerTimeNow()` if appropriate to the existing framework.

---

# SOUND DESIGN

Use `05_AUDIO/SOUND_DESIGN.md` and `AUDIO_CUE_MANIFEST.csv`.

I do not expect you to fabricate real audio asset IDs.

Implement:
- Sound object structure;
- cue names;
- SoundGroup routing;
- volume/rolloff defaults;
- playback hooks;
- variation-selection code;
- candle-based rune hum volume scaling.

Then produce one final list of audio IDs that I still need to source/upload.

---

# VFX

Implement the package VFX direction with the game's existing VFX style.

Most important:
- rune / eyes weaken per candle;
- Dripstone telegraphs;
- two boulders visibly conjure;
- Gnawer summon dust/cracks;
- restrained claw swipe trail;
- big candle recoil;
- ceiling dust / cracks during banish.

Do not turn him into a particle-heavy anime boss.

---

# BALANCE

Start with the values in `UnlittiusConfig.lua`.

All values must be centralized and easily tuneable:
- cooldowns;
- weights;
- damage;
- projectile speed;
- melee radius;
- Gnawer count/cap;
- telegraph durations.

Do not bury tuning values in attack implementation.

---

# TESTING REQUIREMENTS

Use `09_IMPLEMENTATION/TEST_PLAN.md`.

At minimum verify:
- solo;
- multiplayer;
- candle race conditions;
- party wipe/reset;
- two-shot boulder direction;
- boulder never clips through body;
- melee does not multihit from body-part duplication;
- no snuff action exists;
- boss does not walk;
- recoil interrupts safely;
- 8th candle always reaches banish;
- ceiling relief aligns correctly.

---

# WHEN DONE

Give me:

1. A summary of the architecture you found.
2. Every file created/changed.
3. What was reused versus newly created.
4. The exact model hierarchy.
5. Any Studio-only steps I still have to perform.
6. Every missing AnimationId.
7. Every missing SoundId.
8. A tuning table of final current values.
9. Known limitations / TODOs.
10. A test checklist with pass/fail status.

Do not refactor unrelated game systems.

Do not redesign the boss without asking.

Do not remove existing gameplay features unrelated to the boss.

# UNLITTIUS — COMPLETE ROBLOX IMPLEMENTATION PACKAGE

This package is the handoff kit for implementing **Unlittius** into WICK through Claude / Claude Code.

## What is included

- A revised interactive HTML reference viewer with the arms shortened slightly.
- The four-angle visual reference image.
- A master boss design specification.
- Exact animation timing and marker plans.
- Gameplay logic, attack rules, candle progression, damage / hitbox recommendations, and multiplayer rules.
- Sound design and a cue manifest.
- VFX direction and event mapping.
- Roblox architecture recommendations for a Rojo codebase.
- A recommended rig hierarchy and part breakdown.
- Luau reference configuration / scaffold files for Claude to adapt into the real project.
- A full test plan.
- A long-form Claude handoff prompt that tells Claude how to inspect the existing project and integrate the boss without blindly replacing systems.

## Source-of-truth order

If two files disagree, use this order:

1. `02_DESIGN/UNLITTIUS_MASTER_SPEC.md`
2. `03_ANIMATION/ANIMATION_BLUEPRINT.md`
3. `01_REFERENCE/Unlittius_REFERENCE_VIEWER_shorter_arms.html`
4. `01_REFERENCE/Unlittius_4_angle_visual_reference.png`
5. Remaining technical/scaffold documents

The HTML viewer is a **visual and timing prototype**, not code that should be embedded into Roblox.

## Final visual revision made for this package

Relative to the previous viewer:
- upper arms are about 12–14% shorter;
- forearms are about 12–14% shorter;
- claw size is intentionally preserved;
- shoulder width and torso mass are preserved;
- animation rotations are preserved, so the same spell language remains readable;
- shorter arms make the boss less gangly while keeping the claws disproportionately threatening.

## Important design rule

**Unlittius is not a normal damage sponge boss.**

The player wins by lighting all eight encounter candles. The boss is weakened visually and behaviorally by that progression and is ultimately banished into the ceiling as a permanent-looking stone relief for the remainder of the encounter/run.

Do not add a conventional health bar unless the existing game absolutely requires one.

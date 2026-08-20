# UNLITTIUS — TEST PLAN

## A. Model

- [ ] Boss has no legs.
- [ ] Short floating base is compact.
- [ ] 5–7 small stones orbit separately.
- [ ] Arms visibly shorter than previous revision.
- [ ] Claws still look oversized.
- [ ] Hands read as 3 talons + thumb claw, not fingers.
- [ ] Cape is broad and continuous, not noodle strips.
- [ ] Hood is faceted / layered.
- [ ] Boss silhouette readable with only candle lighting.
- [ ] Decorative boss parts do not block players.

## B. Idle

- [ ] Boss remains rooted over dais.
- [ ] No walking/pathfinding.
- [ ] Hover is subtle.
- [ ] Head scan works.
- [ ] Cape motion is restrained.
- [ ] Orbit stones do not collide with players.

## C. Candles

- [ ] Exactly 8 valid candles.
- [ ] Each candle counts once.
- [ ] Two players cannot double-count one candle.
- [ ] Recoil triggers on successful light.
- [ ] Rune/eyes permanently dim each step.
- [ ] 8th candle disables attack scheduler.
- [ ] 8th candle always starts banish.

## D. Dripstone

- [ ] Telegraph visible before fall.
- [ ] Selected ceiling pieces shake.
- [ ] Damage occurs only at impact timing.
- [ ] Safe movement route exists.
- [ ] Fallen stones do not permanently soft-lock arena.
- [ ] Attack cleans up on reset.

## E. Boulder Burst

- [ ] Exactly 2 boulders.
- [ ] Boss never grabs them.
- [ ] Boulders conjure outside body.
- [ ] Neither initial path clips through torso/head.
- [ ] Shot spacing ~0.24s.
- [ ] Projectiles travel toward chosen target.
- [ ] No radial spray.
- [ ] No aggressive post-launch homing.
- [ ] Spherecast / equivalent prevents tunneling.
- [ ] One boulder cannot damage same player repeatedly.
- [ ] Impact cleans up visual/projectile.

## F. Summon Gnawers

- [ ] Arms clearly raise.
- [ ] Hands open upward.
- [ ] Head tilts back.
- [ ] Spawn occurs during held ritual pose.
- [ ] Existing Gnawer system reused.
- [ ] Active cap respected.
- [ ] Reset cleans boss-summoned enemies appropriately.

## G. Melee

- [ ] Triggers only at close range.
- [ ] Short readable windup.
- [ ] Two distinct claw hits.
- [ ] Hitbox follows claw direction.
- [ ] No duplicated damage from multiple character parts.
- [ ] Boss does not travel across arena.
- [ ] Second hit has appropriate knockback.

## H. Recoil

- [ ] Can safely interrupt idle.
- [ ] Can safely interrupt pre-release attack state.
- [ ] Does not undo already-fired projectile.
- [ ] Cannot soft-lock scheduler.
- [ ] Audio/VFX are unmistakable progress feedback.

## I. Banish

- [ ] No attacks after banish starts.
- [ ] Boss rises to ceiling.
- [ ] Correct orientation: face visible downward as relief.
- [ ] Final body looks nearly flat against ceiling.
- [ ] Cape/back can disappear into ceiling.
- [ ] Relief swap has no obvious pop from normal gameplay camera.
- [ ] Purple glow resolves off.
- [ ] Chamber remains lit.
- [ ] Encounter Complete fires exactly once.

## J. Multiplayer

- [ ] 2 players.
- [ ] 3 players.
- [ ] 4 players.
- [ ] Target selection rotates reasonably.
- [ ] Melee chooses nearest valid player.
- [ ] Two boulders can choose valid separate targets when intended.
- [ ] Player leaving encounter during attack does not error.
- [ ] Player dying during telegraph does not error.
- [ ] Party wipe resets cleanly.

## K. Network / latency

Test at simulated:
- [ ] 50 ms
- [ ] 100 ms
- [ ] 200 ms

Verify:
- telegraphs remain aligned;
- projectile visuals match server collision closely;
- animation/VFX action starts stay synchronized;
- no client can fake candle count or hit result.

## L. Performance

- [ ] No per-frame full-workspace scans.
- [ ] VFX particles bounded.
- [ ] No leaked connections after reset.
- [ ] No duplicate RenderStepped/Heartbeat loops per retry.
- [ ] Active projectiles destroyed on teardown.
- [ ] Audio loops stop on teardown.

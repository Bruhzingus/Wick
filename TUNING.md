# TUNING — the feel surface

Every tunable value in the game, grouped by **the question you're answering when you reach for
it** — not by file. All gameplay tuning lives in `src/shared/Config/`. "Harder →" is the
direction that makes the game more punishing. Wax values are candle units; divide by
`Wax.maxWax` for a displayed fraction.
Change a value, let Rojo sync, play — no logic edits, ever.

---

## How long do I survive? — the burn economy

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `startingWax` | Wax | 1.3 | Wax a fresh candle begins with (30% above the original capacity) | lower |
| `maxWax` | Wax | 1.3 | Absolute wax ceiling; visuals normalize against this | lower |
| `idleDrainPerSecond` | Wax | 0.00025 (was 0.0005 before Phase 2) | Cost of merely being lit | higher |
| `burnDrainPerSecond` | Wax | 0.0018 (was 0.0045 before Phase 2) | Brightness-drain coefficient at burnRate 1; the ordinary dial now caps at 0.78 | higher |
| `burnDrainExponent` | Wax | 1.5 | How disproportionately bright burning costs | higher |
| `movementCostMultiplier` | Wax | 0.25 (was 0.6 before Phase 2) | Global scalar on ALL movement costs | higher |
| `initialBurnRate` | Wax | 0.35 | Dial position at spawn (starting point only) | — |
| `startingWaxTypeId` | Wax | Standard | Starting burn profile | — |

**Phase 2 (wax pacing correction) — why these three dropped.** Measured against the real
`FloorPlanner`/`RoomNavigation` room graph (see "the wax pacing budget model" below and
`Tests/WaxPacingTests.luau`), the old values cost roughly 1.95 wax — 150% of the whole 1.3-wax
candle — just to WALK the shortest path to depth 12 at a modest dial, before any threat, hazard,
tool use, or mistake. Passive burn and movement drain, not threats or player choices, were the
deterministic reason nearly every run ended at the same depth. All three values were cut so the
same unavoidable walk now costs roughly 65% of the candle at depth 12 (idle and burn-coefficient
cut ~40-46% across the whole 0.18-0.78 dial so the dial's relative shape is unchanged; movement cut
to keep its ~31-33% share of the total). Sustained maximum brightness (0.78) the whole way to depth
12 still exceeds the candle on drain alone — brightness remains a real, meaningful cost.

### The wax pacing budget model (Phase 2 target)

The question this answers: **why does a run end where it ends?** Before Phase 2 the honest answer
was almost always "passive burn and movement drain," regardless of skill, threats, or luck. The
target is that the answer becomes "an accumulation of exploration, brightness choices, threats,
hazards, and mistakes" — with raw drain as a background cost, not the wall.

Every number below is expressed as a fraction of one 1.3-wax candle, measured as the worst case
across several seeds of the REAL room graph a direct player would walk (`Tests/WaxPacingTests.luau`
walks `Logic/RoomNavigation`'s reciprocal-doorway graph over a `Logic/FloorPlanner`-generated floor —
never a hand-picked distance).

| Budget category | What it is | Approximate size (depth 1→12, modest 0.30 dial unless noted) |
|---|---|---|
| **Unavoidable direct-route cost** | Idle + brightness burn, plus walking, for the shortest legal path from entry to the Basin on every floor — nothing spent on threats, hazards, tools, or backtracking | ≈65% of the candle (was ≈150%, i.e. impossible alone, before Phase 2) |
| **Reasonable exploration cost** | The same per-stud/per-second rates, just over more distance and time: checking a side room for loot, missing the Basin on the first pass, circling back for a teammate | Scales linearly with the extra distance/time — no separate multiplier, so a 30-50% longer route costs roughly 30-50% more of the direct-route number above, not a punitive tax |
| **Optional greed cost** | Burning above the modest 0.30 dial for better visibility/threat reads, or pushing past depth 12 | Sustained maximum ordinary brightness (0.78) for the same depth 1→12 walk alone EXCEEDS the full candle (see the test asserting this) — greed is a real, felt spend, not a rounding error |
| **Expected mistake cost** | One ordinary dark-hunter contact tick (0.025-0.10 wax/s of contact) or a Needle dripstone hit (20% max wax) | 0.02-0.26 wax — a small bite out of the ~35% margin a clean run keeps at depth 12, comfortably survivable |
| **Severe mistake cost** | A Fork/Hammer dripstone hit (35-50% max wax) or an Ashamed Lurker grab (20% max wax), especially stacked with an earlier expected mistake | 0.35-0.65 wax — large relative to the margin, not automatically fatal past the early floors, and exactly what Basin recovery exists for |
| **Recovery provided by the Basin** | Flat `Basin.pool[].waxGranted`, clamped to 0.20-0.35 after the optional next-price penalty | The payment stays useful at every depth; the cost scales through accumulated permanent sacrifices rather than a decaying grant |

**What this makes possible, concretely:**
- A nearly flawless direct run reaches depth 10-12 on unavoidable drain alone, with roughly 35%
  of the candle unspent at depth 12 and no Basin use — declining every offer is genuinely viable.
- That same ~35% margin at depth 12 (larger at shallower depths — depth 8 leaves >60%) is what
  absorbs exploration, one bad brightness call, and typically one serious mistake.
- Two serious mistakes, or one severe mistake stacked on real exploration and a bright dial, is
  where an ordinary run should actually end — expected to land around depth 5-9, from threats and
  hazards (whose budgets already ramp sharply there: `threatBudgetPerFloor` 1.0→3.7,
  `unstableDripstone` target count 1→15, vines from floor 5, the Ashamed Lurker and Stone Warden
  from floor 4), not from the drain formula.
- The Basin stays a recovery tool a bad floor makes worth its permanent price, rather than a
  subscription a clean run must buy to keep descending.

**Basin grant model.** A flawless run may still decline every offer, but accepting one now pays the
same amount at Floor 2 or Floor 20. The long-run price is already cumulative: each visit permanently
removes or worsens another part of the candle. The grant band is therefore fixed at 0.20-0.35, and
the doubled-next-price sacrifice clamps its reduced payment to the same 0.20 minimum.

## How much light do I get for it? — the dial

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `minBurnRate` / `maxBurnRate` | Light | 0.18 / 0.78 | Ordinary dial floor/ceiling; CUP and FLARE own the extremes | narrower |
| `minRange` / `maxRange` | Light | 10 / 30 | PointLight range at each dial end (studs) | lower |
| `minBrightness` / `maxBrightness` | Light | 0.9 / 2.6 | PointLight brightness at each end | lower |
| `minIntensity` / `maxIntensity` | Light | 0.18 / 0.42 | Threat-field strength across the dial; influences reads but cannot force retreat | lower |
| `falloffExponent` | Light | 1.0 | Curve shape; >1 = dim until pushed high | higher |
| `dial.scrollStep` | Light | 0.05 | Burn rate per scroll notch | — |
| `dial.snapPoints` | Light | .3/.5/.7 | Where the slider gently sticks | — |
| `dial.snapRadius` | Light | 0.02 | How sticky the snap points are | — |
| `rendering.transitionSeconds` | Light | 0.2 | Fade/easing response for ignition, snuffing, and dial changes | higher = softer/slower |
| `rendering.disableBrightnessThreshold` | Light | 0.01 | Brightness at which a faded light switches fully off | — |
| `rendering.localShadowBrightnessFraction` | Light | 0.35 | Share assigned to the one full-range spherical shadow accent; the derived stable fill receives 0.55 | higher = darker shadows and more visible engine shadow-LOD changes |
| `rendering.positionResponseSeconds` / `positionSnapDistance` | Light | 0.055 / 8 | Stabilizes moving torch shadows while snapping across teleports | higher response = smoother/slower |
| `rendering.positionSettleDistance` | Light | 0.01 | Snaps the last sub-pixel carrier offset so an idle shadow map stops updating | higher = steadier but less precise |
| `rendering.localBounceBrightnessFraction` / `localBounceRangeFraction` | Light | 0.10 / 0.58 | Short amber near-field layer approximating cave-surface bounce | higher = warmer/brighter |
| `rendering.flicker.enabled` | Light | true | One switch for regular client-rendered combustion; disabling returns an exact 1×/neutral-colour sample | cosmetic |
| `rendering.flicker.loopSeconds` / `noiseScale` / `ownerSeedModulo` / `ownerSeedScale` | Light | 1024 / 2 / 104729 / .0047 | Keeps coherent-noise coordinates bounded on a seamless long loop and gives each owner a stable, cross-client phase | structural/cosmetic |
| `rendering.flicker.layers` | Light | (.48 Hz, .024, 11.7) / (3.15 Hz, .046, 37.1) / (9.2 Hz, .018, 83.6) | Owner-seeded slow fuel drift, flame-body flutter, and fine turbulence (`frequency`, `amplitude`, `phase`) | cosmetic |
| `rendering.flicker.minimumBrightnessMultiplier` / `maximumBrightnessMultiplier` | Light | 0.76 / 1.10 | Hard bounds for all regular/contextual cosmetic output; idle normally remains much closer to 1 | lower floor = deeper gutter |
| `rendering.flicker.gutter.*` | Light | .105 Hz / phase 149.3 / threshold .78 / depth .14 / warmth .22 | Rare, soft and warmer output dip rather than a repeating pulse | lower threshold / higher depth = less stable |
| `rendering.flicker.contextResponseSeconds` / `impactReleaseSeconds` | Light | 0.16 / 0.12 | Smooth threat/sprint crossfade and recovery from a violent impact flicker | higher = softer/slower |
| `rendering.flicker.sprint` / `threat` | Light | (10.7 Hz, .035, 307.2) / (4.4 Hz, .014, 401.8) | Fixed-phase local instability bands (`frequency`, `amplitude`, `phase`) added by `FeelController` context or accepted sprint | higher amplitude = less stable |
| `rendering.flicker.warmthPerBrightnessLoss` / `maximumWarmthBlend` | Light | 1.65 / 0.42 | Bounded ember-orange shift as output weakens | higher = warmer dips |
| `rendering.flicker.warmColor` / `bounceWarmColor` | Light | RGB 255,145,68 / RGB 255,96,38 | Dim-flame target palettes for the primary and bounce layers | cosmetic |
| `rendering.bloom.*` / `colorGrade.*` | Light | subtle warm defaults | Light-responsive highlight bloom and warm contrast without lifting black levels | — |
| `dialInput.sendIntervalSeconds` | Feel | 0.15 | Minimum spacing while dragging; release always sends | higher = less traffic, coarser response |
| `dialInput.serverReconcileDelaySeconds` | Feel | 0.35 | Protects a recent local dial value from an older StateSync | lower = faster authority correction |

## How much does moving cost? — run / hop

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `walkSpeed` / `runSpeed` | Movement | 8 / 16 | Travel speeds (studs/s) | lower |
| `hopPower` | Movement | 30 | Low expedition hop for clearing small cracks and terrain seams | lower |
| `walkWaxPerSecond` / `runWaxPerSecond` | Movement | 0.001 / 0.004 | Wax per second moving | higher |
| `drainThresholds.*` | Movement | 0.75 / 0.25 | Measured-speed cutoffs for run/walk drain | lower |

## How do the tools trade off? — FLARE / DECOY / CUP

Opposition stays in the shared light field: categories read ordinary intensity through
`lightResponse`, while Flare additionally marks its source as panic light so dark-hunters retreat.
DECOY is proposed by the client but grounded by the server against cave geometry. A blocked,
too-close, too-steep, or missing-floor target spends no wax and starts no cooldown. No tool
extinguishes the player's own flame — CUP covers the light instead, so going dark is priced as
per-second upkeep rather than a toggle with a relight commitment.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `Flare.waxCost` | Tools | 0.13 | Price of the panic button; 10% of the default 1.3-wax candle | higher |
| `Flare.cooldown` / `duration` | Tools | 0 / 1.5 | No cooldown; wax cost limits repeated burst use / active length | — / lower |
| `Flare.burstIntensity` / `burstBrightness` / `burstRange` | Tools | 3 / 6 / 60 | Threat-field strength, rendered flash, and reach | lower |
| `Decoy.waxCost` | Tools | 0.04 | Wax permanently thrown away | higher |
| `Decoy.cooldown` / `duration` | Tools | 3 / 6 | Decoy spacing and burn time | higher / lower |
| `Decoy.throwRange` | Tools | 25 | Max throw distance (server-clamped) | lower |
| `Decoy.decoyIntensity` / `decoyRange` | Tools | 2.2 / 45 | Drawn-only distraction strength and reach. Reach is attraction only (not rendered light): wide enough that a decoy at full `throwRange` still out-pulls the brightest flame from a moth already on it | lower |
| `Decoy.throwPlacement.throwStartHeight` / `throwArcHeight` / `throwProbeSegments` | Tools | 1.5 / 5 studs / 16 | Server-validated parabolic throw that clears ordinary rolling floor while walls/roof still block | lower / lower / fewer |
| `Decoy.throwPlacement.obstructionInset` | Tools | 1 stud | Clearance before the first blocking wall/formation | lower |
| `Decoy.throwPlacement.groundProbeHeight` / `groundProbeDepth` / `groundProbeMaxHits` / `groundProbeAdvance` | Tools | 8 / 24 studs / 3 / 0.1 studs | Bounded Terrain-only ground search, including skipped roof undersides | shallower/fewer |
| `Decoy.throwPlacement.maximumGroundRise` / `minimumDistance` | Tools | 20 / 2.5 studs | Rejects implausibly high or near-self placements | lower / higher |
| `Decoy.throwPlacement.maxGroundSlopeDegrees` / `surfaceOffset` | Tools | 38° / 0.05 studs | Steepest legal candle surface and anti-embedding lift | lower / — |
| `Decoy.decoyVisual.*` | Tools | 1.15-high × 0.35-radius body, 0.34 flame, 3.4 brightness / 22 range | Miniature distraction-candle proportions, palette, and rendered light (separate from `decoyRange` attraction) | — |
| `Cup.waxCost` | Tools | 0.005 | Upkeep per SECOND held | higher |
| `Cup.cooldown` | Tools | 0 | Cup may be raised/lowered freely; upkeep and slow movement are its costs | — |
| `Cup.lightMultiplier` | Tools | 0.035 | Near-dark personal ember — the game's only go-dark control. The flame stays lit, so this is covered light, never an extinguish; nearby uncovered teammate light still illuminates the player | higher |
| `Cup.speedMultiplier` | Tools | 0.5 | Your speed while cupping | lower |

## How punishing are threats? — the two categories

`lightResponse` sign: DarkHunter < 0 (repelled), Drawn > 0 (attracted). Magnitude = sensitivity.

| Row: `speed` / `detectionRadius` / `lightResponse` / `waxDamagePerSecond` (Threats.definitions) | | |
|---|---|---|
| Lurker (DarkHunter) | 8 / 18 / −1.0 / 0.05 | contactRadius 3, bodySize 3 |
| Stalker (DarkHunter) | 11 / 24 / −0.6 / 0.08 | contactRadius 3, bodySize 4 |
| Moth (Drawn) | 9 / 30 / +1.0 / 0.04 | contactRadius 3, bodySize 3 |
| Swarm (Drawn) | 6.5 / 22 / +0.7 / 0.10 | contactRadius 4, bodySize 5 |
| Hollow (DarkHunter) | 5.5 / 30 / −0.8 / 0.06 | contactRadius 3.5, bodySize 5 |
| Ash Moth (Drawn) | 8.5 / 38 / +1.2 / 0.025 | contactRadius 2.5, bodySize 2 |
| Snuffer (Drawn) | 5 / 26 / +0.75 / 0 | contactRadius 3, bodySize 4, **Snuff contact** |
| VoidFly (DarkHunter) | 7 / 16 / −1.0 / staged | 9-stud activation, 15-stud territory, four 0.012-wax strikes to snuff |

Harder → higher speed/radius/damage; hunter `lightResponse` nearer 0 (harder to repel).

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `behavior.huntLightThreshold` | Threats | 0.2 | Effective light below which hunters commit regardless of where the player looks; includes the baseline candle's 0.18 minimum | higher |
| `behavior.darkHunterSneakLightThreshold` | Threats | 0.32 | Upper effective-light edge of the middle band where an unwatched crawler closes to contact at stalk speed | higher |
| `behavior.darkHunterObservedDotThreshold` | Threats | 0.35 | Player-facing dot required to count a crawler as watched (about a 69Â° half-angle) | higher = narrower awareness |
| `behavior.repelLightThreshold` | Threats | 0.45 | Local Flare contribution needed to drive a hunter back; ordinary light cannot trigger it | higher |
| `behavior.repathIntervalSeconds` | Threats | 0.65 | Threat reaction time | lower |
| `behavior.wanderSpeedFraction` | Threats | 0.3 | Idle drift speed | higher |
| `behavior.stalkSpeedFraction` | Threats | 0.48 | Crawler speed while maintaining watched spacing or sneaking through the unwatched middle-light band | higher |
| `behavior.wanderRadius` | Threats | 25 | Idle roam range from spawn | higher |
| `behavior.darkHunterKeepDistance` | Threats | 11 | Gap a crawler holds from a medium-light candle | lower |
| `behavior.darkHunterBlindSeconds` | Threats | 2 s | Extra blindness after estimated straight-line Flare retreat travel | lower |
| `VoidFly.ambush.patrolRadius/activationRadius/territoryRadius` | Threats | 5 / 9 / 15 studs | Fixed-area ceiling patrol, wake-up footprint, and hard chase boundary | larger |
| `VoidFly.ambush.retreatDistance/retreatSeconds` | Threats | 13 studs / 5 s | Space and blind safety window bought by Flare or a teammate | shorter |
| `VoidFly.ambush.maximumCeilingHeight/ceilingClearance` | Threats | 30 / 1.5 studs | Keeps the roof tell in light/buzz range and the animated body below the exact underside | higher cap / lower clearance |
| `VoidFly.ambush.roofDecorationClearance` | Threats | 4.5 studs beyond territory | Extra margin on the full patrol/dive/retreat disc reserved from harmless formations and boulders | lower |
| `VoidFly.ambush.diveSpeed/returnSpeed/contactHeightTolerance` | Threats | 14 / 10 studs/s / 0.45 studs | Smooth vertical attack/return and the height gate before a strike can count | faster / wider tolerance |
| `VoidFly.contactAttack.*` | Threats | 0.8s, 4 hits, 0.012 wax/hit | Discrete attacks required before snuff | fewer hits / more wax |
| `VoidFly.spawnWeightByDepth` | Threats | 0 / 3.2 / 4.8 / 6.4 / 8 / 8 / 8 / 6.4 / 6.4 / 4.8 | Relative VoidFly selection weight by depth; 60% above the previous weights | higher |
| `Moth.perch.*` / `AshMoth.perch.*` | Threats | 14 / 16-stud search, 8 probes, 2.5-7 / 3.5-9 studs high, 6-16 / 4-11 s dwell | Idle moths cling to cave walls instead of drifting across the floor, then roam to a new wall. A perched moth cannot drain you; any light it can sense pulls it straight off the stone | longer dwell = calmer caves |
| `*.perch.minimumWallSlopeDegrees` | Threats | 55° | How far from horizontal a face must tilt to count as a wall rather than floor or roof | higher = fewer legal perches |
| `definitions.*.spawnWeightByDepth` | Threats | row-specific | Relative floor-by-floor likelihood; 0 disables a row at that depth | higher late weights = tougher deep mix |
| `visuals.darkHunter.*` | Threats | near-black body, angled deep-crimson Neon slits, 2.5-stud glow | Emergency grey-box fallback hunter silhouette/eye warning (`visuals.procedural.enabled = false` only) | — |
| `visuals.drawn.*` | Threats | charcoal-taupe body, neutral grey translucent wings | Emergency grey-box fallback moth body/wing palette (`visuals.procedural.enabled = false` only) | — |

The detailed procedural bodies used by default (`visuals.procedural.enabled = true`) do **not**
read these two rows — `DarkCrawler.luau` and `CaveMoth.luau` each own their own hardcoded palette
and eye-glow constants directly in `src/shared/NewModelsAndObjects/`. A dark-hunter's eyes are
crimson (idle/locked red); a moth's eyes are faint warm yellow that brightens with attraction —
tune those in the creature files, not here.
| `visuals.procedural.enabled` | Threats | true | Detailed client-built bodies; false restores emergency grey-box server visuals | — |
| `visuals.procedural.cullDistance` | Threats | 120 | Distance beyond which a client removes a detailed body from Workspace | lower = faster |
| `visuals.procedural.cullHysteresis` | Threats | 12 | Extra retention range preventing rebuild churn at the cull boundary | higher = more retained bodies |
| `visuals.procedural.groundOffsets` | Threats | crawler 3.72, moth 1.8, fly 0.5 | Aligns each procedural root with the server ground position | — |
| `visuals.procedural.illuminationStep` | Threats | 0.05 | Cosmetic light-state quantization sent by the server proxy | lower = smoother, more traffic |
| `visuals.procedural.attackPulseIntervalSeconds` | Threats | 1.05 | Seconds between the cosmetic attack beats a threat in contact replicates; the `DarkCrawler` swings once per beat | lower = busier swings, never more damage |
| `visuals.procedural.attackAudio.*` | Threats | crawler/drawn/fly spatial cues + `ThreatHit`, 0.92â€“1.08Ã— pitch | Cue routing and per-hit pitch variation for server-confirmed attack pulses | wider/faster = harsher |
| `visuals.procedural.ceilingFlyBuzz.*` | Threats | 9–20 s / 32 studs / 0.35-stud endpoint inset | Random buzz timing, retry cadence, audible proximity, and roof-safe LOS endpoint | shorter/farther = more warning |

## How dangerous is the environment? — water and unstable dripstone

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `waterPool.minSize/maxSize/maxCenterOffset` | Hazards | 26 / 42 / 9 | Localized recessed pool DIAMETER and placement. The floor is Terrain at 4-stud voxels, so a pool much below the minimum smooths back into the rock and becomes invisible and un-wadeable | larger |
| `waterPool.aspectJitter` / `placementAttempts` | Hazards | 0.12 / 24 | Per-axis stretch on that diameter, and re-rolls before falling back to a minimum pool on the room's centre pad | — |
| `waterPool.shoreMossPatches/shoreMossRingPadding` | Hazards | 14 / 5 | Moss ring following the waterline (art only; see `Floors.caveMoss`) | — |
| `unstableDripstone.wardenStunSeconds` | Hazards | 15 | How long a Stone Warden caught under a falling crown is rooted and unable to kill | higher = easier |
| `waterPool.surfaceOffset` | Hazards | 0.5 | How far below the room's flat floor the water plane sits, so the Terrain bowl reads as a natural dip | lower = flusher, less readable |
| `waterPool.poolBedDepthPad` | Hazards | 0.8 | Extra depth added under the planned wading depth when carving/testing the pool bed and dripstone fall clearance | lower |
| `animation.*` | Hazards | water bob 0.06, wind 18 particles/s | Client-only water sheen/bob and wind motion | — |
| `Water.degradePerSecond` | Hazards | 0.2 | Wax/s while wading | higher |
| `Water.lethalAtHeightFraction` | Hazards | 1.0 | Surface height (fraction of CURRENT body) that kills | lower |
| `heightAtFullWax` | Character | 4 | Body height at full wax — water headroom early | lower |
| `heightAtZeroWax` | Character | 0.8 | Body height near burnout — late-run water death | lower |
| `waterDepth` (Shallows / Flooded / Sump) | Floors | 0.45 / 1.2 / 2.0 | Optional water depth variants; required entry-to-Basin route is always dry | higher |

The shrink interaction remains: height = 0.8 + 3.2 × wax. Shallows remain wadeable, Flooded
becomes lethal only near the end of a candle, and the rare Sump becomes lethal much earlier.
FloorPlanner converts water modules on one entry-to-Basin path into dry modules. Other flooded
modules contain a local pool with dry perimeter rock and submerged steps, so deep water remains a
positioning risk rather than a room-wide softlock. Tune `waterDepth` against the Character heights.
(`bodyRadius` 1.4, `rimHeight`/`wickHeight`/`cameraLift` in Config/Character are body/eye
structure — visual proportions, no difficulty axis.)

Unstable dripstone is a one-shot environmental system, not an enemy row. Its fixed proximity
footprint does not inspect burn rate or movement mode: brightness only changes how early the
physical warning can be seen, while sprinting naturally spends more of the available reaction
distance. Warning and fall state are shared by the server, including when one player triggers a
formation ahead of the rest of the party.

For depth `d`, the uncapped target is `round(1 + 0.5 × (d − 1))` for F1–3,
`round(4 × 1.3^(d − 4))` for F4–6, and `round(7 × 1.2^(d − 6))` for F7+. The planner accepts a
lower result whenever one of the room, harmless-majority, doorway, hazard, visibility, or spacing
safety caps prevents a valid placement.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `unstableDripstone.maxEligibleCeilingHeight` | Hazards | 34 studs | Highest nominal room roof allowed to contain a dangerous formation | higher |
| target curve | Hazards / DripstoneRules | F1–10: 1, 2, 2, 4, 5, 7, 8, 10, 12, 15 | Desired formations before placement/safety caps; linear F1–3, exponential F4–6 and F7+ | higher bases/growth |
| `maxHazardousRoomFraction` | Hazards | 0.5 | At least half of ordinary rooms remain free of dangerous dripstone | higher |
| `maxPerRoomEarly/Mid/Deep` | Hazards | 1 / 2 / 3 | Per-room cap on F1–3 / F4–6 / F7+ | higher |
| `maxUnstableToHarmlessRatio` | Hazards | 0.4 | Global harmless-majority cap relative to normal ceiling formations | higher |
| `placementAttempts/minCenterOffset/maxCenterOffset` | Hazards | 64 / 11 / 25 studs | Safe deterministic placement away from the room-center route | more attempts / wider usable band can increase placements |
| `doorwaySafetyPadding/minFormationSpacing` | Hazards | 8 / 12 studs | Keeps trigger zones clear of door approaches, other hazards, and one another | lower |
| `visualLengthRadiusFactor/minimumFallDistance/impactEmbedDepth` | Hazards | 2.4 / 4.5 / 0.2 studs | Conservative procedural-tip clearance, guaranteed readable drop, and model-bounds landing embed | lower clearance/drop = less warning space |
| `decorationEgressPadding` | Hazards | 4 studs | Keeps boulders, columns, and harmless roof dressing outside each trigger/escape lane | lower |
| Needle | Hazards variants | 1.65 s / 5 trigger / 3.25 impact / 20% max wax | Narrow one-prong warning, footprint, and impact | shorter / larger / more loss |
| Fork | Hazards variants | 1.8 s / 5.25 trigger / 3.6 impact / 35% max wax | Split two-prong warning, footprint, and impact | shorter / larger / more loss |
| Hammer | Hazards variants | 2 s / 5.5 trigger / 4 impact / 50% max wax | Heavy three-prong warning, footprint, and impact | shorter / larger / more loss |
| `snuffBelowWaxFraction` | Hazards | 0.3 | Wax fraction below which any dripstone hit snuffs instead of damaging | higher |
| `fallAcceleration/minFallSeconds/maxFallSeconds` | Hazards | 180 / 0.28 / 0.62 s | Analytic anchored vertical fall; no physics ownership or Touched damage | faster |
| `lightSuppressionMultiplier/lightSuppressionSeconds` | Hazards | 0.42 / 2 s | Surviving candle output and threat-visible light after impact | lower / longer |
| `presentationCullDistance/impactPresentationRadius` | Hazards | 90 / 36 studs | Client warning animation cull and nearby impact-feedback reach | cosmetic |
| `impactShake*/impactDim*/flameFlicker*` | Hazards | 0.1 stud, 1.25°, 0.42 s / −0.12, 0.62 s / 0.95 s | Dust/debris, camera, grade, and violent flame response; never gameplay authority | cosmetic |
| `warningDust*`, `dormantDust*`, `warningWobble*`, `impactDebris*` | Hazards | row-specific | Subtle learnable warning and local impact presentation cadence | cosmetic |
| `model*` | Hazards | row-specific | Shared fractured-collar colors, prong spacing, crown/crack counts, and dry dust palette | cosmetic |

## When does the stone wake? — Stone Warden

All encounter-selection and runtime pacing values live in `Config/StoneWarden`.

| Value | Default | Feel question |
|---|---:|---|
| `minGlobalDepth` | 4 | How deep before the encounter can exist? |
| `spawnChancePerEligibleFloor` | 0.45 | How rare is its optional weathered chamber? |
| `roomCeilingHeight` | 28 | How tall is the inspectable encounter chamber? |
| `pileOffset` / `relicOffset` | `(8,0,4)` / `(-10,0,-6)` | Where do the dormant body and wake-up choice sit? |
| `counterDripstoneOffset` / `counterDripstoneVariantId` | `(8,0,-8)` / `Hammer` | Where is the guaranteed physical counter? |
| `encounterClearance` | 9 | How much cave dressing is kept away from each encounter pad? |
| `walkSpeed` / `pathRefreshSeconds` | 8 / 0.3 s | How quickly and responsively does it pursue? |
| `emergenceSeconds` / `stationaryPauseSeconds` | 4 / 3 s | How much warning and stop-listening pause does it give? |

The `WardenDen` room-module row has zero assembly weight. Only `FloorPlanner` may add it, and
`FloorPlan.warden` is the authority for its fixtures. The room is excluded from ordinary threats,
loot, pools, deposits, vines, and Ashamed Lurkers.

## What is waiting in the archway? — the Ashamed Lurker

A deep-floor creature clinging to one springer of an ordinary arch, with a long arm across ONE half
of the opening. It is not fought and never dies. Run through the half it occupies and it lunges for
your wax; stand in the open half and hold its gaze for 1.5 s and it covers its face and leaves that
arch. Everything below lives in `Config/AshamedLurker`; the rules that read them are pure in
`Logic/AshamedLurkerRules`, so placement safety is testable rather than conventional.

**Resting arm and attack reach are different numbers.** `placement.restArmReach` is only the
silhouette; `trigger.reach` is what can actually catch you, and the creature lunges the difference.
This is deliberate — a trip volume the size of the drooping arm only ever caught players who walked
into the body.

Three properties are structural, not tuning. `trigger.reach` is a fixed stud distance, so a wider
arch is proportionally LESS covered (41% of the narrowest allowed door, 25% of the widest) rather
than equally covered. The trip lane can never cross the doorway's centre line (reach is capped by the
trap half's own width). And an occupied arch always keeps at least `minSafeLaneWidth` studs of clear
floor, measured against the lunge rather than the resting arm. All three are asserted for every
allowed width in `Tests/AshamedLurkerRulesTests`. Note the three placement numbers are coupled:
`minDoorWidth` must be at least `edgeInset + trigger.reach + minSafeLaneWidth`, or no arch qualifies.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `minDepth` | AshamedLurker | 4 | First global depth an arch can host one | lower |
| `maxPerFloorByDepth` | AshamedLurker | F1–10: 0,0,0,1,1,1,2,2,2,2 | Per-floor ceiling before eligibility and the roll cut it down | higher |
| `chancePerEligibleDoorway` | AshamedLurker | 0.7 | Chance a qualifying arch is taken. In practice ≈ half of deep floors carry one and two is rare, because qualifying arches are already scarce | higher |
| `sitesPerLurker` | AshamedLurker | 3 | Arches one creature reserves: where it starts plus where it reappears. A floor with only one qualifying arch means it returns to the same one | higher = more relocation variety |
| `placement.minDoorWidth/maxDoorWidth` | AshamedLurker | 17 / 28 studs | Medium-to-large doors only. Nominal width is measured before Terrain rolls into the opening, so a door plays tighter than it measures; 17 is the narrowest that still walks as a real room mouth AND can hold reach + inset + the full safe-lane guarantee | wider window = more encounters |
| `placement.minDoorHeight/maxDoorHeight` | AshamedLurker | 9.5 / 13 studs | Height window; short arches would hide the head | — |
| `trigger.reach` | AshamedLurker | 7 studs | THE attack range: fixed studs in from the trapped springer, never a fraction of the arch. Drives the trip lane, the grab volume, and the safe-lane guarantee | longer |
| `placement.restArmReach` | AshamedLurker | 3.5 studs | VISUAL ONLY — how far the arm droops while dormant. The lunge animation throws the body the difference between this and `trigger.reach` | — |
| `placement.minSafeLaneWidth` | AshamedLurker | 8.4 studs | Clear floor the open half must keep: three candles abreast (3 × 2 × `Character.bodyRadius`), measured against the lunge. THE guarantee that an occupied arch is still a route | lower |
| `placement.edgeInset` | AshamedLurker | 0.7 studs | How far the body sits in from the springer | — |
| `face.*` | AshamedLurker | 0.52 height / 1.35 inset / 0 forward | Where the face sits, and so what a player must actually look at. Kept in the plane of the opening so it reads from both approaches | — |
| `trigger.minSpeedFraction/minAbsoluteSpeed` | AshamedLurker | 0.7 of run speed / 10 studs/s | Measured speed that counts as running through — 11.2 studs/s, clearly above walkSpeed (8) so walking is unambiguously safe and below runSpeed so any sprint trips it | lower |
| `trigger.laneDepth/laneCenterY/laneHeight` | AshamedLurker | 4.5 / 2.5 / 10 studs | Trip volume through and above the opening; generous vertically because Terrain rolls up into the arch and a candle's tracked position is its base | larger |
| `trigger.grabLateralPadding/grabDepthPadding` | AshamedLurker | 0.8 / 2.5 studs | How much larger the impact-frame volume is than the trip lane. Depth is padded hard: a sprinter covers ~2 studs during the wind-up, so escaping is meant to be LATERAL, not simply being fast | larger |
| `trigger.sampleHz` | AshamedLurker | 20 | Trip-detection rate. Too low and a sprinter is sampled past the lane before it fires | higher |
| `trigger.grabCheckDelaySeconds` | AshamedLurker | 0.12 s | The entire reaction window: leave the volume before this and the grab misses | shorter |
| `trigger.waxLossFraction` | AshamedLurker | 0.2 of max wax | Wax a connecting grab takes; level with a Needle dripstone | higher |
| `trigger.recoverySeconds/rearmSeconds` | AshamedLurker | 0.9 / 0.5 s | Time extended after a lunge, and the minimum gap between lunges so one pass cannot be hit twice | shorter |
| `gaze.holdSeconds` | AshamedLurker | 0.5 s | Continuous stare needed to shame it off. It is caught, not out-stared | longer |
| `gaze.dotThreshold` | AshamedLurker | 0.86 (≈31°) | How directly the face must be in view | higher |
| `gaze.maxDistance` | AshamedLurker | 12 studs | How close you must be for it to tell it is being looked at | lower |
| `gaze.requiredDialFraction` | AshamedLurker | 0.5 | How far up the ORDINARY dial (`Light.minBurnRate`..`maxBurnRate` → 0.48) the flame must be. Below it you can creep past in the dark, but you cannot shame it. CUP never qualifies; FLARE always does | higher |
| `gaze.losEndpointInset` | AshamedLurker | 1.5 studs | The line-of-sight ray stops this far short of the face, so the arch the head is embedded in is not treated as blocking its own creature. Set to 0 and no stare ever lands | lower = stricter |
| `gaze.decayPerSecond` | AshamedLurker | 2.4 | Progress lost per second of looking away, so a flicked glance is not banked | higher |
| `gaze.sampleHz/sampleTimeoutSeconds/maxCameraOffsetStuds` | AshamedLurker | 12 Hz / 0.35 s / 8 studs | Client report cadence and the server's staleness/plausibility gates (see `Security.remoteRateLimits.LurkerGaze`) | — |
| `ashamedSeconds` | AshamedLurker | 1.3 s | Cover-face-and-retreat animation before it is gone | — |
| `hiddenSeconds` | AshamedLurker | 50 s | How long a shamed creature stays away before settling into another arch. Clearing one buys a route, never permanent safety | lower |
| `presentation.*` | AshamedLurker | cull 110 studs, shake 0.65 s / 0.9 stud / 3.2°, dim 1.1 s | Local body culling, breathing cue cadence, and the grab scare. Never gameplay authority | cosmetic |

## How exposed does moving make me? — the drip trail

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `emitIntervalStuds` | DripTrail | 8 | Distance between drips | lower |
| `pointLifetimeSeconds` | DripTrail | 35 | How long your route stays readable/followable | higher |
| `maxPointsPerPlayer` | DripTrail | 24 | How far back you can be tracked | higher |
| `dripPartSize` / `dripFlattening` | DripTrail | 0.18 / 0.16 | Tiny floor-hugging cylinder geometry, never floating balls | — |
| `dripSizeJitter` / `dripAspectJitter` / `dripPositionJitter` | DripTrail | 0.22 / 0.18 / 0.14 | Natural variation between dull drops | — |
| `dripColor` | DripTrail | dark brown wax (112/88/62) | Non-emissive SmoothPlastic color | — |

Wax drops never use Neon, never own a PointLight, and never enter `LightSources`; only
dark-hunters consume their geometric `TrailPoint` breadcrumbs.

## What does the cave hear? — the sound field

The second perception field, alongside light. Only **dark-hunters** listen (`hearing` on their
`Config/Threats` rows); every Drawn row is deaf, so a noisy action never pulls both families at once
and the light/dark read is untouched. Loudness falls off linearly with distance, decays linearly
with time, and **events sum** — which is why one strike is usually ignored and three are not.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `emitters.MineStrikeClean` | Sound | 0.55 / 46 / 3.2 s | Loudness, radius, decay of a clean pick strike | higher |
| `emitters.MineStrikeFumble` | Sound | 0.95 / 62 / 4 s | A missed swing — deliberately the loud one | higher |
| `emitters.MineBreak` | Sound | 1.25 / 74 / 4.5 s | The seam giving way | higher |
| `emitters.Sprint` | Sound | 0.3 / 30 / 1.6 s | One footfall burst; must stay under every threshold alone | higher |
| `emitters.DripstoneImpact` | Sound | 1.4 / 85 / 5 s | A crown hitting the floor; the cave's own loudest event | higher |
| `emitters.VineBurn` | Sound | 0.85 / 55 / 4 s | A curtain catching | higher |
| `sprintEmitIntervalSeconds` | Sound | 1.1 | How often sustained running re-announces itself | lower |
| `maxLiveEvents` | Sound | 96 | Live-event cap; overflow drops the oldest | — |
| `hearing.curiosityThreshold` | Threats | 0.8 / 0.7 / 0.6 | Summed loudness before Lurker / Stalker / Hollow investigate | lower |
| `hearing.sensitivity` | Threats | 1.0 / 1.2 / 1.4 | Multiplies perceived loudness (the `\|lightResponse\|` of ears) | higher |
| `hearing.hearingRadius` | Threats | 55 / 68 / 80 | Earshot gate, independent of `detectionRadius` | higher |
| `hearing.investigateSeconds` | Threats | 9 / 8 / 12 | How long it commits to a remembered noise | higher |
| `hearing.investigateSpeedFraction` | Threats | 0.5 / 0.6 / 0.45 | Walk speed toward a noise; below a hunt on purpose | higher |
| `behavior.investigateArrivalToleranceStuds` | Threats | 5 | How close counts as "looked" | — |

Investigating ranks **below every real prey read and above the drip trail**. It targets a position,
never a player: being heard costs you a location, not your life.

## What does mining cost? — Raw Wax deposits

Click a seam to **engage** it: you plant, the pick comes up, and a marker sweeps one continuous
fracture rail. Every further click is a **strike**, and the target aperture moves between them. Any
movement key leaves. The server owns validation, sweep, progress, reward, and world impact. A shared
click timestamp is accepted only inside a narrow rewind bound, so ordinary transport latency does
not move a visible hit and hostile/stale values score at arrival. The price is time standing still —
genuinely still — with an uncovered flame, making noise. Value lives in `Config/Extraction`.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `rows[*].cleanStrikes / units / maxPaidMiners / minBurnFraction` | Mining | Standard 3/2/1/0; Twin 6/2/2/0; Deep 9/6/1/0; Bright 3/4/1/.9 | Row duration, yield, co-op payout ceiling, and Bright burn gate | row-specific |
| `deposit.interactionRange` | Mining | 6.5 | Reach; tighter than loot pickup on purpose | lower |
| `deposit.promptViewDot` / `requiresLineOfSight` | Mining | 0.56 / true | Prompt aim cone plus client/server obstruction checks | higher / true |
| `deposit.strikeCooldownSeconds` | Mining | 0.55 | Recovery between strikes; also the beat the next sweep starts on | higher |
| `deposit.swingWindupSeconds` | Mining | 0.14 | Dead time at the top of each sweep before the marker moves | — |
| `deposit.swingTimeoutSeconds` | Mining | 6 | Idle time before a stance releases itself | lower |
| `deposit.movementSpeedMultiplier` | Mining | 0 | The stance lock. 0 = planted; the exit is a movement key, handled client-side | — |
| `deposit.requiresLit` / `requiresUncoveredFlame` | Mining | true / true | You cannot mine dark or cupped | — |
| `timing.sweepSeconds` | Mining | 1.15 | One pass of the timing marker | lower |
| `timing.perfectCenter` | Mining | 0.62 | Where the band sits before it wanders | — |
| `timing.bandWander` | Mining | 0.28 | How far the band moves per strike. 0 turns the loop into a metronome | higher |
| `timing.perfectHalfWidth` / `goodHalfWidth` | Mining | 0.045 / 0.13 | Band widths as a fraction of a sweep | lower |
| `timing.goodFractionOfPerfect` / `missFractionOfPerfect` | Mining | 0.66 / 0.30 | Lesser grades as fractions of this row's clean strike | lower |
| `timing.maxInputRewindSeconds` / `inputFutureToleranceSeconds` | Mining | 0.22 / 0.04 | Bounds for converting the shared click sample to the server scoring clock | lower |
| `placement.minDepth` | Mining | 1 | First eligible floor | higher |
| `placement.depositCounts` | Mining | E = 0.65 / 1.10 / 1.40 / 1.85 / 2.45 by depth band | **How many seams a floor carries**, weighted by global depth (0–1 on floors 1–3, rising to 2–3 past floor 10). Replaced a flat 65%-of-one, which made the mining layer contribute nothing to the depth push | steeper = pushes deeper |
| `placement.maxPerFloor` | Mining | 3 | Absolute clamp on the weights above, not a balance lever. At most one deposit per room, so several seams read as several detours rather than a route | — |
| `placement.footprint` / `standingClearance` | Mining | 6 / 7 | Seam plus the dry ground needed to work it | — |
| `placement.minHazardSeparation` | Mining | 9 | Clearance from pools and unstable formations | higher |
| `placement.minThreatSeparation` | Mining | 14 | Clearance from a threat's spawn point | higher |
| `visual.surfaceEmbed` | Mining | 0.35 | How far the boulder sinks into the resolved ground | — |
| `visual.glow.range` / `.nearDistance` | Mining | 26 / 8 | Where the seam's amber ember starts, and where it is full | lower |
| `visual.glow.color` | Mining | `255,190,110` | Warm gold, deliberately kept away from red (Neon is self-lit — the raw hue is what shows) | — |
| `visual.glow.minTransparency` | Mining | 0.82 | Strongest the ember gets — high on purpose, it is a warmth not a beacon | higher |
| `visual.glow.thickness` | Mining | -0.05 | Negative insets the ember shell inside the seam so it never pokes past the wax's own silhouette | — |
| `pickaxe.anticipationSeconds` / `.swingSeconds` / `.impactSeconds` / `.reboundSeconds` / `.recoverSeconds` | Mining | 0.075 / 0.105 / 0.052 / 0.088 / 0.225 | Preload, accelerating fall, contact hold, outcome recoil, and asymmetric settle; sum stays ≤ cooldown | — |
| `pickaxe.aimScreenOffsetStuds` / `.aimYawDegrees` / `.aimPitchDegrees` | Mining | (0.34, 0.22) / 8° / 5° | Biases the camera-space tool toward the real seam, strongest at contact | lower |
| `qte.widthPixels` / `.trackThicknessPixels` / Good/Perfect heights | Mining | 238 / 2 / 7 / 13 | One continuous strike rail with nested apertures and no segmented timing error | — |
| `qte.enterSeconds` / `.exitSeconds` / `.requestTimeoutSeconds` | Mining | 0.16 / 0.13 / 1.25 | HUD settle/fade and local input-latch recovery | — |
| `feedback.impactDebris*` | Mining | 7 chips / 0.55 s / 5.5 outward / 3.8 up | Local collision-neutral seam chips on confirmed contact | lower |
| `feedback.comboPitchStep` / `.comboPitchMax` | Mining | 0.012 / 1.04 | Subtle Perfect lift without changing the material identity | — |
| `feedback.impactPresentationRange` | Mining | 74 studs | Covers the loudest server-authorized mining event (break) for teammate presentation | lower |
| `Audio.cues.MineSwing` / `MineRecover` | Audio | volume 0.20 / 0.065 | Close-mixed head movement on input and quiet haul-back foley | lower |
| `Audio.cues.MineStrikeImpact` | Audio | volume 0.72 | The spatial crunch layer — timed to visible contact and played under every confirmed strike | lower |
| `geometry.placementProbe.upStuds` / `.downStuds` | Floors | 10 / 24 | How far `server/SurfaceProbe` hunts for the real floor around a planned spot. Too tall and a deposit can rest on an overhang | — |

Placement invariants (enforced in `Logic/FloorPlanner`, tested in `FloorPlannerTests`): never the
entry, Basin, or Brazier room; never on the guaranteed entry → Brazier → Basin route; never behind a
vine curtain; never blocking a doorway lane; always a dry interaction footprint. **A floor that
cannot satisfy all of that carries no deposit — the count drops rather than the safety rules.**

## What is a run worth? — the extraction economy (Phase 8)

**Raw Wax is the only income in the game.** Leftover candle wax pays nothing; what you get paid for is
what you dug out of the rock and walked back up. Every number here is an **integer** — per-unit values
are whole currency and the two scalars are permille — so no payout is ever computed in floating point.

A unit is priced by the **floor it was mined out of**, never by where it was cashed in. That single
decision is what makes "farm the safe floors, then sprint to the bottom" worth exactly what sprinting
to the bottom alone is worth.

| Value | File | Default | Controls | Harder / deeper → |
|---|---|---|---|---|
| `valuePerUnitByDepth` | Extraction | 10,11,14,18,23,28,35,43,54,68,87,112,146,192,254 | Whole currency per unit by origin depth | steeper = pushes deeper |
| `extensionGrowthPermille` | Extraction | 1330 | Compounding past the authored table (1.33×/floor) | higher |
| `maxValuePerUnit` | Extraction | 5000 | Ceiling, reached ~floor 26 | — |
| `unitsPerDeposit` | Extraction | 2 | Units one depleted seam grants. Cut from 3 when floors gained multiple seams; without it deep income roughly triples | lower |
| `maxCargoUnits` | Extraction | 999 | Overflow guard, not a balance lever — hitting it is a bug signal | — |
| `partyBonusPermille` | Extraction | 1500 | "Everyone came back" bonus, paid retroactively once the last member is out | lower |
| `partyBonusMinimumMembers` | Extraction | 2 | Solo runs never earn it | — |
| `deathDropPermille` | Extraction | 500 | Share of a dead player's bag that lands on their remains; the rest shatters | lower |
| `disconnectGraceSeconds` | Extraction | 120 | How long a dropped bag stays locked to its owner before the party may take it | lower |
| `maxSinglePayout` | Extraction | 1000000 | Absolute payout ceiling; nothing legitimate approaches it | — |

### Caves charge admission

Permanent unlocks were replaced by a per-descent fee taken from **every** party member. The Shallows
is free forever. Owning a cave outright makes its fee zero and is priced at fifteen descents.

| Cave | `entryFee` | `payoutPermille` | `permanentUnlockPrice` | Break-even |
|---|---|---|---|---|
| The Shallows | 0 | 1000 | — (never for sale) | always free |
| The Descent | 350 | 2500 | 5250 | ~floor 5; real profit past floor 8 |
| The Deep | 1000 | 4500 | 15000 | ~floor 7; an average run **loses money** |

Measured, from the real config: an average 5-floor free run pays **~149**, so one Descent admission
is **~2.3 free runs**. A floor-8 Descent run nets **+941**; a floor-5 Deep run nets **−328**.

Those figures were re-derived when floors gained multiple seams (`Mining.placement.depositCounts`,
`unitsPerDeposit` 3 → 2). **Both previously documented anchors survive** — the free 5-floor run was
~152 and the Deep 5-floor run −316 — so the change is neutral for a typical shallow run and only the
deep end gets richer, which is the point of putting the seam count on a depth curve. Cumulative base
value by depth: **13 / 27 / 46 / 85 / 149 / 228 / 357 / 517 / 716 / 1,050**. Full derivation and the
contract break-even table are in `LAMP-NETWORK.md` §6.

### Rules that are decisions rather than numbers

Written out in `Config/Extraction`, enforced in `server/ExtractionService` and `Logic/CargoRules`:
cargo is **individual**; a **snuff never drops it** and a **revived player keeps all of it**; a
**terminal death drops half and shatters half** onto the candle remains; a **disconnect drops the
whole bag owner-locked** for the grace window and then unlocks it for the party. There is **no
transfer verb** — the only path between two players' bags is a pile in the world with a single claim,
which is what makes duplication structurally impossible rather than merely checked for.

### The mining shard

A **Perfect** strike shatters wax onto the miner (`Mining.deposit.waxPerPerfectStrike`, 0.012). Only
Perfect — a fumble sprays nothing, so this rewards reading the rail rather than grinding a rock.

**This is the economy's most sensitive lever.** Raising it much past 0.03 per strike makes mining a
net wax fountain and deletes the survival pressure the whole game is built on.

It was **cut from 0.025 to 0.012 when floors gained multiple seams.** The old value was tuned against
exactly one seam per floor: 3 strikes × 0.025 = 0.075 returned against the ~0.070 a floor's traversal
costs. Once a deep floor averages 2.45 seams, that same value returns **0.18 per floor** — precisely
the fountain above. At 0.012 the return by depth band is **0.023 / 0.040 / 0.050 / 0.067 / 0.088**
against the same ~0.070 cost, so shallow floors are a net wax loss and deep floors roughly break
even. The margin survives, and the wax reward now tracks depth alongside the currency reward instead
of sitting flat against it.

## How brutal is the Basin? — the sacrifice ritual

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `minimumGrant` / `maximumGrant` | Basin | 0.20 / 0.35 | Final payment band at every depth, including the next-price penalty | lower |
| `offersPerVisit` | Basin | 3 | Choices shown per visit | lower |
| `pool[].waxGranted` | Basin | 0.20–0.35 | Depth-independent payment per sacrifice before the optional penalty clamp | lower |
| `pool[].weight` | Basin | 1 | Offer frequency (shifts which losses hurt) | — |
| `effects.maxBurnRateCapMultiplier` | Basin | 0.6 | How hard the brightness cap bites | lower |
| `effects.peripheralDarknessOpacity` | Basin | 0.22 | Permanent darkness at the screen edges | higher |
| `effects.sightBrightness` / `sightSaturation` | Basin | -0.055 / -0.24 | Mild permanent local vision grading | lower |
| `basinVision.edgeColor` / `edgeWidthScale` | Feel | (2,2,4) / 0.24 | Shape and color of the peripheral-darkness sacrifice | wider/darker |

## Is it worth going deeper? — the brazier

Phase 8 removed the Living Wax payout. The brazier no longer computes a reward from your candle: it
is the place cargo becomes currency, and the arithmetic lives in `Logic/ExtractionValue` (see the
extraction-economy section above). `depthMultipliers`, `groupBonusPerPlayer` and `rewardPerWaxUnit`
are **gone** — the depth curve is now `Extraction.valuePerUnitByDepth`, and the group bonus became an
"everyone came back" bonus settled once the whole party is out rather than a proximity check here.

| Value | File | Default | Controls | Harder / deeper → |
|---|---|---|---|---|
| `promptRange` | Brazier | 10 | Where the preview/commit appears (studs) | — |
| `positionToleranceStuds` | Brazier | 2 | Server-side slack when re-validating the commit | lower |
| `commitHoldSeconds` | Brazier | 1 | Hold time to end your run | — |
| `previewUpdateSeconds` | Brazier | 0.25 | Preview refresh cadence | — |

The preview at the brazier is **the only place a bag's currency value is shown**. In the cave the HUD
carries a unit count and nothing else, so the decision to turn back is made at the exit with the real
number in front of you rather than continuously recalculated in the dark.

## What does swapping wax do? — burn profiles

| Row: `drainMultiplier` / `brightnessMultiplier` / `attractsDrawn` (WaxTypes) | |
|---|---|
| Standard | 1.0 / 1.0 / true (neutral start) |
| Beeswax | 0.8 / 0.85 / true (slow, dim, efficient) |
| Tallow | 1.3 / 1.3 / true (fast, bright, hungry) |
| ColdWax | 1.0 / 0.9 / **false** (invisible to the drawn — all your light, incl. decoys) |

Profiles are selected by the planned pickup rows below and remain active for the rest of that run.

## What loot decisions appear? — wax profiles and prepared tools

| Value | File | Default | Controls | Harder / richer → |
|---|---|---|---|---|
| `spawnsPerFloor` | Loot | {2,2,2,3,3,3,4,4,4,4} | Planned pickups per floor | lower = fewer options |
| `definitions.*.spawnWeightByDepth` | Loot | row-specific | Depth availability and relative frequency | — |
| `definitions.*.freeCharges` / `.matchCharges` | Loot | 1 | Wax-free uses granted to Flare/Decoy, or solo self-relights stored by Match | lower |
| `wallInsetMin` / `wallInsetMax` / `wallLateralRange` | Loot | 6 / 13 / 24 | Peripheral wall/shelf band used for pickup placement | lower inset / higher lateral range = more searching |
| `placementAttempts` / `placementFootprint` | Loot | 18 / 3.4 | Door-safe wall-pocket search and reserved pickup width | lower / higher = fewer valid pockets |
| `pickupRange` / `pickupHoldSeconds` | Loot | 8 / 0.25 | Server collection reach and prompt commitment | lower / higher |
| `visualSize` / `surfaceClearance` / `promptHeight` | Loot | 1.15 / 0.1 / 1.45 | Diegetic pickup scale, visible-model ground clearance, and prompt height | cosmetic |

## How big and long is a run? — floors, party, pacing

| Value | File | Default | Controls | Harder / longer → |
|---|---|---|---|---|
| `planningBatchSize` | Floors | 10 | Default finite batch for deterministic tests/tools only; live runs generate floors on demand | — |
| `roomsPerFloor` | Floors | {6,7,8,8,9,10,10,11,12,12} | Rooms per **global depth**; `DepthRules.getRoomCountTarget` extends the last row past this table | higher |
| `threatBudgetPerFloor` | Floors | {1,1.3,1.6,1.9,2.2,2.5,2.8,3.1,3.4,3.7} | Threats per **global depth**; a smooth ramp (each depth slightly busier than the last), scaled again by `Depth.threatBudget` past the table and by the tier's `threatBudgetMultiplier` | higher |
| `hazardChancePerRoom` | Floors | 0.4 | Hazard roll per eligible room | higher |
| `floodedFloorChance` | Floors | 0.4 | **How often you meet water at all.** Chance a whole floor is wet; a dry floor never considers a flooded module | higher |
| `floodedRoomsPerFloor` | Floors | 1 | Pools on a wet floor. Extra flooded modules are converted back to dry, and a wet floor that lost its pools to the dry-route guarantee gets one re-flooded off-route room | higher |
| `linearContinuationChance` / `loopSeekingChance` | Floors | 0.82 / 0.9 | Bias toward a readable main chain, then toward placements that can close a loop | higher |
| `loopConnectionChance` / `minimumLoopConnections` | Floors | 0.72 / 1 | Chance adjacent rooms connect and minimum available loop edges opened | higher = more alternate routes |
| `roomModules[].weight` | Floors | 0.45–3 | Dry/water/grotto room mix. Water weights are RELATIVE ONLY — they pick which kind of pool a wet floor gets, not how often water appears | — |
| `caveMoss.*` | Floors | 5 patches/wall dry, 13 damp | Collision-neutral wall moss; rooms holding water get the denser damp palette | — |
| `geometry.*` | Floors | cell 64, walls 24/1, cave mouths 8–45 wide × 8–13 high, gap 96 | Physical scale and deterministic per-edge connection sizes; footprint is 20% below the prior 80-stud rooms | bigger cells = longer treks |
| `caveDressing.*` | Floors | relief 5×1.8, CaveKit boulders 1, columns 1, roof formations 2 + straw cluster 1 | Multi-facet procedural dressing; terrain remains the primary variance | more collidable structures = more cover |
| `caveDressing.ceilingFormationGroundGap/ceilingFormationExtentRadiusFactor/ceilingStrawLengthMultiplier` | Floors | 1.5 / 2.4 / 1.85 | Clamps harmless hanging formations to the exact roof-to-ground clearance | lower gap / extent estimate = longer formations |
| `caveDressing.ceilingFacetClustersPerRoom/PiecesPerCluster` | Floors | 9 / 2 | Adds broad, collision-neutral fractured planes without changing the authoritative roof field | higher = denser visual roof detail |
| `caveDressing.ceilingFacetMinSize/MaxSize/MinThickness/MaxThickness/Spread/Embed` | Floors | 3.5 / 8 / 0.35 / 0.9 / 1.8 studs / 0.72 | Shapes shallow overlapping roof chips; most of every chip remains buried in Terrain | larger/thicker/lower embed = bolder breakup |
| `caveDressing.ceilingFacetPlacementAttempts/EdgeInset/SlopeSample` | Floors | 36 / 5 / 2 studs | Bounds deterministic placement, keeps wall seams clean, and aligns chips to local roof slope | more attempts/lower inset = broader coverage |
| `terrain.groundHump*` | Floors | 7 attempts per room, 12–22 wide, 0.65–3.2 high, −3 separation | Dense, partially overlapping ramped floor shelves in every room | more/larger = rougher routes |
| `terrain.groundPatchFallbackOffset` | Floors | 17 | Corner fallback offset (studs) for a ground patch when the radial roll fails to find a valid spot | — |
| `terrain.specialRoomCenterClearance` | Floors | 7 | Keeps spawn and Basin interaction centers level and clear | lower = rougher special rooms |
| `terrain.doorClearance*` | Floors | depth 10, width 24 | Keeps ground rises out of the largest cave-mouth approaches | lower = more obstruction |
| `terrain.wallClearance/hazardClearance` | Floors | 2 / 2 | Keeps planned rises inside rock walls and away from pools | lower = more overlap |
| `terrain.aiGroundProbe*` / `aiObstacleSidestep` | Floors | 7 / 16 / 4 | Threat ground following and local rock detours | — |
| `groundField.*` | Floors | row-specific | Shared floor-wave amplitude, frequencies, doorway-lane blend, enclosure berm, and depth growth | higher amplitude/berm = rougher routes |
| `roof.rockThickness` | Floors | 12 | Solid Terrain above the visible inverted roof underside | lower = thinner shell |
| `roof.minRelief/maxRelief` + `*Frequency*` | Floors | 0.45 / 4.8 studs; 0.035–0.058 / 0.14–0.22 | Ceiling structure and wavelength ranges; tall rooms receive more potential relief | higher relief/frequency = rougher roof |
| `roof.longWaveAmplitude/rippleAmplitude` | Floors | 0.62 / 0.2 | Broad floor-like roof rolls versus smaller stone breakup | higher |
| `roof.edgeBlend` | Floors | 9 studs | Smoothly returns roof relief to zero at walls and shared door arches | lower = sharper seams |
| `caveMouthArchFacetMinLength` / `MaxLength` / `Thickness` / `Depth` / `Embed` | Floors | 2.2 / 4.2 / 0.7 / 1.6 studs / 0.78 | Keeps doorway-edge chips shallow, curve-aligned, and mostly buried in the structural arch | longer/thicker/lower embed = rougher, more prominent arch edge |
| `roof.minimumClearance` | Floors | 8.5 studs | Clamps the sampled underside above the shared local ground field; unstable placement applies its own larger clearance requirement | lower = tighter passages |
| `targetRunLengthSeconds` | RunSettings | 1200 | Pacing target (reference, not enforced) | higher |
| `partyCap` | RunSettings | 4 | Max players per run | — |
| `entrySpawnRadius` | RunSettings | 5 | Radius of separated multiplayer entry slots | studs |
| `entrySpawnClearance` | RunSettings | 0.5 | Empty gap between entry-spawn candle colliders | studs |
| `soloAllowed` | RunSettings | true | Solo runs permitted | — |
| `startCountdownSeconds` | RunSettings | 5 | Delay before descent starts | — |
| `restartDelaySeconds` | RunSettings | 60 | Results choice window before automatic replay | — |
| `tickRate` / `stateReplicationHz` | RunSettings | 10 / 10 | Sim and sync cadence (mechanical) | — |

## How deep does the cave go? — the canonical depth model

`globalDepth = startDepth + localFloor - 1` is the single difficulty number (`Logic/DepthRules`).
Inside the authored range (depths 1–`authoredDepth`) every curve below is neutral, so these values
change nothing about the game as it ships today — they describe what happens *past* the
hand-authored per-floor tables. Valid positive whole depths are uncapped; each content curve caps
its own density or magnitude, and `RunOrchestrator` constructs successors on demand.

| Value | File | Default | Controls | Harder / longer → |
|---|---|---|---|---|
| `minDepth` | Depth | 1 | Shallowest legal depth. Anything below is rejected, never clamped | — |
| `authoredDepth` | Depth | 10 | The deepest global depth the hand-authored per-floor tables cover. Raise only when those tables are extended by hand | — |
| `bands` | Depth | 1–3 / 4–6 / 7–10 / 11–15 / 16+ | Internal difficulty bands (Introduction → Extreme). The final band extends indefinitely | — |
| `threatBudget.perDepth` / `.maximum` | Depth | 0.06 / 1.6 | Extra threat budget per depth past `authoredDepth`, and its hard cap | higher |
| `hazardBudget.perDepth` / `.maximum` | Depth | 0.05 / 1.5 | Extra falling-dripstone density past `authoredDepth`, and its hard cap. Planner per-room and hazardous-room-fraction caps still bind above it | higher |
| `roomCountStepPerDepth` / `maxRoomsPerFloor` | Depth | 0.5 / 16 | Rooms added per depth past the authored `roomsPerFloor` table, and the absolute room ceiling | higher = longer floors |
| `rewardGrowthPerDepth` / `maxRewardDepthMultiplier` | Depth | 1.25 / 60 | Geometric growth of the brazier depth multiplier past the authored table, and its cap | higher = richer deep runs |

## How do cave tiers and the lobby scale a run?

| Value | File | Default | Controls |
|---|---|---|---|
| `requiredCurrency` | CaveTiers | 0 / 1500 / 6000 | Persistent access threshold |
| `startDepth` | CaveTiers | 1 / 1 / 1 | Absolute global depth this tier's expedition begins at. Every tier starts at the surface today |
| `threatBudgetMultiplier` | CaveTiers | 0.6 / 1.1 / 1.35 | Per-floor threat budget multiplier, stacked on top of `threatBudgetPerFloor`'s own per-floor ramp |
| `rewardMultiplier` | CaveTiers | 1.0 / 1.15 / 1.5 | Brazier payout multiplier |
| `dripstoneMultiplier` | CaveTiers | 1.0 / 1.2 / 1.45 | Scales `DripstoneRules.targetCount`'s expected falling-dripstone count per floor (higher = harder) |
| `waxDrainMultiplier` | CaveTiers | 1.0 / 1.0 / 1.0 (was 1.0 / 1.08 / 1.18 before Phase 2) | Uniformly scales the whole `WaxDrain.perSecond` result (`WaxService.setCaveTier`). Phase 2 flattened this to 1 for every tier: a flat per-tier drain tax duplicated the readable difficulty Descent/Deep already get from `threatBudgetMultiplier` and `dripstoneMultiplier`. Tier difficulty now comes from those two plus `rewardMultiplier` |
| `atmosphereColor` / `atmosphereDecay` | CaveTiers | (0.62,0.66,0.74)/(0.22,0.24,0.3) → progressively toward (0.37,0.4,0.44)/(0.13,0.14,0.18) | Retints the global Atmosphere (`EnvironmentSetup.applyCaveTier`) so deeper tiers read as a visibly darker shade of cave |
| `minimumPlayers` | Lobby | 1 | Ready players needed to start |
| `teleportRetries` | Lobby | 2 | Reserved-server attempts after a failure |
| `arrivalWaitSeconds` | Lobby | 8 | How long a reserved expedition waits for expected teleported members before countdown |

Studio always takes the local-start branch; only a published live server exercises
`TeleportService`. ProfileStore also uses its isolated Mock in Studio, so persistence tuning and
unlock verification require a live published test.

## How is the physical lobby laid out?

The lobby ("The Landing") is one fixed mineshaft hub built once at server boot by
`server/LobbyRoomBuilder.luau` — not seeded or rebuilt per run, unlike `Config/Floors`. Its entire
tier-select/ready/start interaction is the three elevators (`server/ElevatorService.luau`):
standing in one is readiness for that tier; the leader's chosen elevator sets the party's tier; a
leader-only lever starts the expedition through the same validated path the old UI used
(`PartyLobbyService.tryStart`/`canStart`).

The open hub shows the player's **real Roblox avatar** (`CharacterService.spawnLobby`). Pulling the
lever immediately replaces committed riders with full, lit candles and enters first person.
Those elevator candles remain lobby-tracked presentation bodies, so they spend no wax and never
enter hazards, threat perception, or movement correction before floor 1 exists.

| Value | File | Default | Controls |
|---|---|---|---|
| `origin` | LobbyRoom | (0, 500, 0) | World position of the hub. Must clear both the tallest cave roof (Y≈58) and `rideShaftDepth` below itself, so the hub and its shafts can never overlap cave Terrain |
| `roomWidth` / `roomDepth` / `wallHeight` | LobbyRoom | 140 / 104 / 26 studs | Hub footprint and ceiling height |
| `beamSpacing` / `railSpacing` | LobbyRoom | 16 / 6 studs | Density of the timber ceiling supports and the mine-cart sleepers |
| `lighting.ceilingLampRange` / `Brightness` | LobbyRoom | 42 studs / 0.8 | Broad but subdued pools from the six overhead lamps |
| `lighting.lanternRange` / `Brightness` | LobbyRoom | 20 studs / 0.45 | Local fill around freestanding lantern posts |
| `lighting.elevatorLampRange` / `Brightness` | LobbyRoom | 18 studs / 0.55 | Restrained light inside each elevator car |
| `spawnOffset` / `spawnSpread` | LobbyRoom | (0,0,-40) / 7 studs | Where arrivals appear, and the radius they are fanned around so a party never stacks up |
| `fallRecoveryDrop` | LobbyRoom | 40 studs | How far below the floor counts as "fell down an open shaft" and is teleported back to spawn |
| `walkSpeed` / `sprintSpeed` / `jumpPower` | LobbyRoom | 16 / 30 / 48 | Lobby-only movement. Costs no wax (there is no `PlayerState`), and is client-driven on purpose — nothing here is authoritative |
| `shopOffset` / `shopPromptText` / `shopMessage` | LobbyRoom | — | Placeholder shop stall; no purchase economy yet — see IMPLEMENTATION-ROADMAP.md |
| `elevators` | LobbyRoom | one row per cave tier (1/2/3) | tierId + position; adding a `Config.CaveTiers` row needs a matching row here or that tier is unreachable |
| `elevatorCarWidth` / `Depth` / `Height` | LobbyRoom | 14 / 14 / 14 studs | Elevator car dimensions. The floor is built with a matching gap so the car has a shaft to descend through |
| `elevatorZoneRadius` | LobbyRoom | 10 studs | Horizontal distance counting as "standing in this elevator". Keep ≥ the car's half-diagonal or its corners fall outside the zone |
| `elevatorLeverPromptText` / `elevatorLeverObjectText` | LobbyRoom | "Descend" / "Control Lever" | The leader-only descend prompt |
| `elevatorBoardWidth` / `Height` | LobbyRoom | 11 / 7 studs | The alcove header board carrying each car's tier name, lock state, and live party roster |
| `rideDistance` / `rideShaftDepth` | LobbyRoom | 220 / 260 studs | How far the car travels, and how deep the shaft it travels into is. Shaft must exceed travel |
| `rideShaftRibSpacing` | LobbyRoom | 10 studs | Spacing of the four-segment perimeter wall ribs — the parallax that makes the ride read as motion without placing solid plates across the car's path |
| `rideShaftRibThickness` / `rideShaftRibOutset` | LobbyRoom | 0.8 / 1.5 studs | Perimeter-beam thickness and clearance outside the car shell |
| `rideShakeStuds` / `rideShakeHz` | LobbyRoom | 0.1 studs / 5.5 Hz | Subtle horizontal mechanical camera tremor during the ride; descent never bobs the camera vertically |
| `welcomeSignText` / `howToPlayRules` | LobbyRoom | — | Board copy. Keybinds are NOT written here: the controls panel is generated from `Feel.controls` so it can't drift from real bindings |
| `boardWidth` / `boardHeight` | LobbyRoom | 22 / 13 studs | Size of the welcome, how-to-play, and standings boards |
| `leaderboardRows` / `leaderboardRefreshSeconds` | LobbyRoom | 10 / 60 | How many standings rows the board shows and how often it re-reads them |

The refresh interval is only the background cross-server poll. A death or successful Brazier
extract overlays its score in the current server immediately and requests an immediate repaint, so
returning players never wait a minute to see the result. Studio uses that same session-local
overlay without writing to the production OrderedDataStore.

The ride is the loading transition, not decoration over it: on a successful `tryStart`,
`ElevatorService` closes the gate, captures and anchors riders, swaps them to cosmetic candles, and
broadcasts one server timestamp plus the authoritative rest transform/duration/distance. Every
client evaluates the same smoothstep curve before its camera update, eliminating replicated-CFrame
judder; the server applies only the final car/rider transform. The duration remains
`RunSettings.startCountdownSeconds`, and a live reserved-server teleport begins after it completes.

Cars are returned to the top of their shafts whenever the hub reopens — on a normal lobby return,
and also after a descent that never became a run (a failed teleport, an emptied party).

## What protects the public prototype?

| Value | File | Default | Controls |
|---|---|---|---|
| `remoteRateLimits.*` | Security | per-remote | Per-player token-bucket burst/refill |
| `movement.sampleSeconds` | Security | 0.2 | Server displacement sampling cadence |
| `movement.trustWindowSeconds` | Security | 1 | How long displacement accumulates from one trusted anchor |
| `movement.slackMultiplier` | Security | 1.5 | Multiplier on sustained run-speed allowance |
| `movement.teleportAllowance` | Security | 2.5 | Fixed replication-jitter margin; authorized teleports reset the anchor |
| `telemetryEnabled` | Security | true | Structured prototype server-log events |

## How forgiving is death? — snuff, relight, the ghost candle

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `relightWaxCost` | Death | 0.15 | What the reviver personally pays | higher |
| `snuffStateDuration` | Death | 20 | Rescue window before a snuff turns terminal | lower |
| `relightRange` / `relightHoldSeconds` | Death | 8 / 1 | Reach and deliberation of the rescue | lower / higher |
| `soloSnuffIsTerminal` | Death | true | Immediately resolves an involuntary solo snuff unless the candle carries a Match; a Match presents a self-relight prompt and is consumed | false = wait for the normal rescue timeout |
| `remainsWaxFraction` | Death | 0.5 | Remaining wax deposited by a terminal death | lower |
| `minimumWax` / `maxStoredPerFloor` | Remains | 0.005 / 12 | Smallest deposit and session storage bound | higher / lower |
| `ownerMayCollect` | Remains | false | Whether the candle that left a pool may reclaim it | false |
| `pickupRange` / `pickupHoldSeconds` | Remains | 9 / 0.5 | Recovery reach and commitment | lower / higher |
| `lightIntensity` / `lightRange` | Remains | 0.45 / 12 | Visibility and Drawn attraction of a pool | higher |

### What a dead player becomes — the ghost candle (Config/Spectator)

A terminally dead player keeps a body for the rest of the expedition: a translucent candle that walks,
follows a living teammate, sheds almost nothing, and sees only where its teammates have walked. None of
it is visible to the cave — a ghost is never in the light field or the sound field — so every value
below is a spectating value, not a difficulty one. The exception is `light.*`, which is the one small
favour a dead friend still does the party, and `light.fadeAfterSeconds`, which takes it back.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `body.height` / `body.transparency` | Spectator | 2.6 / 0.62 | How present a ghost looks. Above ~0.4 transparency it starts reading as a live candle in a dark corridor | — |
| `body.walkSpeed` | Spectator | 14 | Ghost travel speed; faster than a living walk (8), slower than a sprint (16) | lower |
| `body.hopPower` | Spectator | 30 | Terrain recovery only, same as the living hop | — |
| `light.range` / `light.brightness` | Spectator | 6 / 0.35 | The faint glow a dead friend still sheds. Must stay under `Light.minRange` (10) — a pure-rule test asserts it | lower |
| `light.fadeAfterSeconds` | Spectator | 120 | Seconds before that glow is gone for good. The body keeps walking; only the light expires | lower |
| `follow.autoFollowOnDeath` | Spectator | true | Whether a fresh ghost is attached to a teammate immediately | false = they must press the key |
| `follow.graceSeconds` | Spectator | 4 | Seconds a ghost is left over its own remains before an automatic pull can move it | lower |
| `follow.reanchorDistance` | Spectator | 90 | Studs of drift before the server pulls a following ghost back to its teammate | lower = a tighter leash |
| `follow.reanchorCooldownSeconds` | Spectator | 2 | Minimum seconds between two pulls | higher |
| `follow.anchorLift` | Spectator | 0.5 | Studs a pulled ghost is lifted. Never make this a sideways offset — a teammate's feet are the only floor the server knows is standable | — |
| `trail.sampleIntervalStuds` | Spectator | 4 | Studs a runner travels per recorded footfall. Lower = a denser path and more marks | higher = harder to follow |
| `trail.maxSamplesPerRunner` | Spectator | 48 | Cap per runner, oldest dropped first. Bounds the whole system at party size × this many local parts | lower |
| `trail.lifetimeSeconds` | Spectator | 45 | How long a footfall stays visible — the memory of the system | lower |
| `trail.sendHz` | Spectator | 4 | Trail replication rate to each ghost (only new samples are sent) | — |
| `trail.markerWidth` / `markerThickness` / `markerLift` | Spectator | 0.9 / 0.08 / 0.06 | One footfall mark, laid flat on the floor | — |
| `trail.markerTransparency` / `markerFadeFloor` | Spectator | 0.25 / 0.08 | Clarity of the freshest mark, and the floor of the fade curve | higher / higher |
| `trail.freshMarkerSeconds` / `freshMarkerWidthMultiplier` | Spectator | 2.5 / 1.8 | How long and how much the newest mark reads as "they are THERE" | lower |
| `trail.ownerColors` | Spectator | 4 cold hues | One colour per runner, chosen by userId so two paths never merge | — |
| `hud.*` | Spectator | — | The ghost readout's placement, copy, and follow-key hint. `touchSize` is larger than `size` because touch has no key and carries the follow button in the panel | — |
| `controls.spectatorFollowKey` | Feel | F | The ghost's only control: follow the next candle, or past the last one, roam free | — |

## How clearly does danger read? — local feel and controls

These values are cosmetic and client-only. They never change wax, threat decisions, or hazard rules.
Cooldown bars cover FLARE, DECOY, and CUP; Sprint has no cooldown. Immediate
`ActionFeedback` is reconciled by `StateSync.actionCooldowns`, with both using
`Workspace:GetServerTimeNow()` timestamps, so the bar never claims an unavailable action is ready.
On touch devices the same title, timer, and shrinking fill are mirrored onto Roblox's native
ContextActionService buttons without changing their binding or placement.

| Value | File | Default | Controls |
|---|---|---|---|
| `lowWax.threshold` / `urgentThreshold` | Feel | 0.25 / 0.10 | When the wax bar begins pulsing and changes to its urgent colour |
| `lowWax.pulseFrequencyHz` / colour blend | Feel | 1.6 Hz / 0.25–0.85 | Warning pulse speed and strength |
| `sprintFeedback.normalFov` / `sprintFov` | Feel | 74 / 85 | Restrained view expansion while an accepted sprint is moving |
| `sprintFeedback.transitionSeconds` | Feel | 0.4 s | Time to enter or leave the sprint strain |
| `sprintFeedback.vignette*` / `heat*` | Feel | 0.16 max / 2 px | Peripheral tunnel vision and barely visible heat shimmer |
| `sprintFeedback.camera*` | Feel | 0.018–0.022 studs / 0.22° | Unstable flame-driven camera motion, not athletic head-bob |
| `sprintFeedback.streak*` | Feel | 4 per side / 0.055 max opacity | Sparse, soft peripheral movement traces |
| `sprintFlame*` | Character | 1.28× tall / 0.88× narrow / 10° lean | Teammate-visible flame strain from measured Run movement |
| `sprintIntervalMultiplier` | DripTrail | 0.65 | Running distance between wax drops; lower creates a denser, riskier trail |
| `waterWarning.*` | Feel | cool grading | Local environmental warning tint; authoritative exposure still comes from the server |
| `dialSnap.*` | Feel | 0.12 s flash | Visual/audio acknowledgement when the brightness dial reaches a snap point |
| `threatWarning.radius` / `scanIntervalSeconds` | Feel | 30 / 0.25 s | Range and cadence for requesting the nearby-threat cue |
| `ambientCave.initialDelay*` / `refractory*` / `meanSilenceSeconds` / `maxSilenceSeconds` | Feel | 34–72 / 26–38 / 62 / 190 s | One global, exponential ambient clock with long valleys rather than independent periodic timers |
| `ambientCave.silentWeight` / `recentFamilyCount` / `focusQuietSeconds` | Feel | 18 / 2 / 11 s | Authored non-events, anti-repeat memory, and protected silence after gameplay-critical Focus cues |
| `ambientCave.soundEvents` | Feel | Strata/Fissure/Calcite/Water/Gravel | Weights, real surface kind, range, burst gaps, restrained pitch, and occupied duration for five harmless families |
| `ambientRockfall.*` | Feel | 0.6–1.1 studs / 3.2–5.8-stud fall | Director-invoked loose-stone surface query, fall, roll, and cleanup; no private timer or gameplay effect |
| `ambientWaterDrip.*` | Feel | 6 attempts / 8–26 studs / 34-stud ceiling search | Director-invoked randomized roof source query and emitter cleanup; no listener-centred fallback or private timer |
| `tutorialHints.*` | Feel | floors 1–3 / 5 s / 0.35 s fade / 12 s repeat | Bottom-screen teaching hints for authoritative threat contacts, first nearby dripstone falls, and replicated water entry |
| `debug.showThreatLabels` | Feel | false | Restores grey-box threat names for tuning; keep false for horror playtests |
| `controls.*` | Feel | 1–4, Shift | Single source for real keyboard bindings, touch button positions, and hotbar labels |
| `hotbar.*` | Feel | responsive two-row legend | Desktop/mobile placement, sizing, colours, and text bounds |
| `hotbar.cooldownBarHeightScale` / `cooldownMinimumDisplaySeconds` | Feel | 0.2 / 0 s | Bar thickness and exact-deadline cutoff; keep the cutoff at zero so readiness is never shown early |
| `hotbar.cooldownLabel*` / `touchCooldownTrack*` / `touchCooldownLabel*` | Feel | key-column pill / inset native-button bar and pill | Readable numeric overlay placement on the legend and touch controls |
| `hotbar.cooldownDisplayStepSeconds` / `cooldownSecondsFormat` | Feel | 0.1 s / `%.1fs` | Numeric timer cadence; positive remainders round upward to the next display step |
| `hotbar.pulseSeconds` / `pulseScale` / `deniedFlashSeconds` | Feel | 0.15 s / 1.09 / 0.2 s | Accepted bounce and rejected-request flash |
| `hotbar.acceptedColor` / `deniedColor` | Feel | warm amber / muted red | Immediate server-accepted versus server-rejected chip acknowledgement |
| `hotbar.denialTextSeconds` / `denialMessages` | Feel | 1.1 s / friendly reason map | Temporary explanation for authoritative rejection; `InvalidTarget` reads `AIM AT OPEN GROUND` |
| `hotbar.active*` / active display names | Feel | warm highlight + `●` / `FLARING` / `UNCUP` | Marks live Flare/Cup state |

## Where do sound assets go? — audio cues

`Audio.cues` is the event registry consumed by `client/AudioCues` and `client/MusicController`.
The menu uses `122061612190896`. The shuffled cave pool contains `71682768476112`,
`136582960170775`, `104375150403939`, and `113564986043204`, each at volume `0.352` (20% below
the original mix). The bag plays
every configured cave track once before reshuffling and prevents the last track of one bag from
immediately repeating as the first track of the next.

| Value | File | Default | Controls |
|---|---|---|---|
| `maxActiveVoices` / `buses[*].voiceLimit` | Audio | 48 global / 4–18 per bus | Oldest-voice stealing bounds mix density instead of allowing unbounded one-shots |
| `buses.Music/Ambience/World/Focus/UI` | Audio | nested beneath `WickMaster` | Category headroom; cave EQ/reverb; Focus sidechains gently duck Music/Ambience for critical reads |
| `cues[*].cooldownSeconds` | Audio | cue-specific | Spatial cooldowns apply per emitter; non-spatial/UI cooldowns remain global, so independent world contacts do not mute one another |
| `occlusion.*` | Audio | 0.68 direct volume / -1,-5,-17 dB EQ | One-shot ray obstruction keeps the reverb tail while filtering direct sound through rock |
| `music.initialDelayMinSeconds/MaxSeconds` | Audio | 18 / 42 s | Random silence before the first cave track |
| `music.betweenTrackDelayMinSeconds/MaxSeconds` | Audio | 10 / 24 s | Random silence between cave tracks |
| `music.fadeInSeconds/fadeOutSeconds` | Audio | 4 / 5 s | Smooth music entrances, natural endings, and lobby/run switches |
| `music.endCheckIntervalSeconds` | Audio | 0.2 s | How often the client checks whether end fading should begin |
| `cues.FlyBuzz` | Audio | 9114506042 / 0.12 / 4–32 studs | Quiet spatial VoidFly warning; cave walls suppress playback |
| `cues.DarkCrawlerAttack` | Audio | 9125929705 / 0.88 / 0.58Ã— / 7â€“64 studs | Low, dry joint-fracture attack layer emitted from a crawler that lands contact |
| `cues.DrawnAttack` | Audio | 9114506042 / 0.78 / 0.68Ã— / 6â€“52 studs | Low hostile insect burst emitted from a Drawn threat that lands contact |
| `cues.VoidFlyAttack` | Audio | 9114506042 / 0.86 / 1.38Ã— / 5â€“40 studs | Sharp close dive burst emitted on a confirmed VoidFly strike |
| `cues.ThreatHit` | Audio | 9118609396 / 0.94 / 0.7Ã— | Heavy non-spatial impact sting heard only by the confirmed victim |
| `cues.DripstoneFracture` | Audio | 9125929705 / 0.32 / 5–48 studs | Restrained spatial shale crack during the committed warning |
| `cues.DripstoneImpact` | Audio | 9118609396 / 0.68 / 7–68 studs | Strong nearby stone impact and debris cue |
| `cues.DripstoneImpale` | Audio | 9125929705 / 0.95 / 1.25× speed | Close, non-spatial jumpscare sting heard only by a player confirmed inside the impact footprint |
| `cues.AmbientRockfall` | Audio | 9118609396 / 0.24 / 3–52 studs | Quieter, slightly brighter spatial stone cue for a harmless loose rock rolling from a side wall |
| `cues.AmbientWaterDrip` | Audio | built-in water impact / 0.08 / 2–26 studs | Quiet, pitched spatial cave-water drip; no visual component |
| `cues.CaveStrataStrain` | Audio | 9125880974 / 0.10 / 8–90 studs | Low wall-borne rock shift with a capped, faded tail |
| `cues.CaveFissureBreath` | Audio | 9120698168 / 0.075 / 10–96 studs | Broad pressure-wind movement through a real wall/fissure source |
| `cues.CaveCalciteTick` | Audio | 9118628948 / 0.07 / 3–55 studs | One-to-three irregular mineral ticks from sampled ceiling geometry |
| `cues.CaveHiddenWater` | Audio | 9125499039 / 0.075 / 5–76 studs | Low-point underground water pulse |
| `cues.CaveGravelCreep` | Audio | 9113218672 / 0.09 / 4–68 studs | Short granular floor/wall settling movement |

Empty one-shot IDs remain safe no-ops, and invalid, inaccessible, or unpermitted configured audio
produces a `[WICK AUDIO]` warning in client Output.

The two dripstone cues are free Creator Store assets by Pro Sound Effects. As with every Roblox
asset, verify that IDs `9125929705` (fracture) and `9118609396` (impact) remain usable by the
publishing experience before release.

Each row controls bus, gain/pitch variation, polyphony, optional duration/fade, spatial rolloff,
looping, and cooldown. Unique assets preload once at startup. `AudioCues.playAt` samples obstruction
for short world one-shots. Registered events cover
dial snap, low wax, water, nearby threats, every tool, movement, Basin, Brazier, snuff/death,
relighting, and floor entry. `Audio.enabled` is the global switch; `cleanupSeconds` is the
failed/unfinished one-shot cleanup fallback. All buses route through `WickMaster`, so the local
settings volume changes fades and effects uniformly without rewriting individual Sound volumes.

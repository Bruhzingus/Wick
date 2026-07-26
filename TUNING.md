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
| `idleDrainPerSecond` | Wax | 0.0005 | Cost of merely being lit | higher |
| `burnDrainPerSecond` | Wax | 0.0045 | Brightness-drain coefficient at burnRate 1; the ordinary dial now caps at 0.78 | higher |
| `burnDrainExponent` | Wax | 1.5 | How disproportionately bright burning costs | higher |
| `movementCostMultiplier` | Wax | 0.6 | Global scalar on ALL movement costs | higher |
| `initialBurnRate` | Wax | 0.35 | Dial position at spawn (starting point only) | — |
| `startingWaxTypeId` | Wax | Standard | Starting burn profile | — |

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

## How do the tools trade off? — SNUFF / FLARE / DECOY / CUP

Opposition stays in the shared light field: categories read ordinary intensity through
`lightResponse`, while Flare additionally marks its source as panic light so dark-hunters retreat.
DECOY is proposed by the client but grounded by the server against cave geometry. A blocked,
too-close, too-steep, or missing-floor target spends no wax and starts no cooldown.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `Snuff.cooldown` | Tools | 0.5 | How fast you can flicker in/out | higher |
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
| `Cup.lightMultiplier` | Tools | 0.035 | Near-dark personal ember; nearby uncovered teammate light still illuminates the player | higher |
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
| `behavior.huntLightThreshold` | Threats | 0.15 | How dark you must be before hunters take you | higher |
| `behavior.repelLightThreshold` | Threats | 0.45 | Local Flare contribution needed to drive a hunter back; ordinary light cannot trigger it | higher |
| `behavior.repathIntervalSeconds` | Threats | 0.65 | Threat reaction time | lower |
| `behavior.wanderSpeedFraction` | Threats | 0.3 | Idle drift speed | higher |
| `behavior.stalkSpeedFraction` | Threats | 0.48 | Crawler speed while maintaining medium-light spacing | higher |
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

## How brutal is the Basin? — the sacrifice ritual

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `depthPenaltyPerFloor` | Basin | 0.85 | Exchange-rate decay: grant × this^(depth−1) | lower |
| `offersPerVisit` | Basin | 3 | Choices shown per visit | lower |
| `pool[].waxGranted` | Basin | 0.15–0.35 | Payment per specific sacrifice (every row sets its own; there is no separate base) | lower |
| `pool[].weight` | Basin | 1 | Offer frequency (shifts which losses hurt) | — |
| `effects.maxBurnRateCapMultiplier` | Basin | 0.6 | How hard the brightness cap bites | lower |

## Is it worth going deeper? — the brazier

Reward = wax × depthMultiplier × (1 + 0.25 × additional players) × caveTierMultiplier × rewardPerWaxUnit.

| Value | File | Default | Controls | Harder / deeper → |
|---|---|---|---|---|
| `depthMultipliers` | Brazier | {1,1.5,2.2,3,4,5,6.5,8,10,12.5} | Payout per floor | steeper = pushes deeper |
| `groupBonusPerPlayer` | Brazier | 0.25 | Bonus per extra player present | higher = more group pull |
| `rewardPerWaxUnit` | Brazier | 1000 | Wax → currency scalar | lower |
| `promptRange` | Brazier | 10 | Where the preview/commit appears (studs) | — |
| `groupRadius` | Brazier | 12 | Who counts as "with you" at commit (studs) | lower |
| `commitHoldSeconds` | Brazier | 1 | Hold time to end your run | — |
| `previewUpdateSeconds` | Brazier | 0.25 | Preview refresh cadence | — |

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
| `floorsPerRun` | Floors | 10 | Default expedition length when a tier does not set its own; NOT a cap (see `Depth.prototypeCeiling`) | higher |
| `roomsPerFloor` | Floors | {6,7,8,8,9,10,10,11,12,12} | Rooms per **global depth**; `DepthRules.getRoomCountTarget` extends the last row past this table | higher |
| `threatBudgetPerFloor` | Floors | {1,1.3,1.6,1.9,2.2,2.5,2.8,3.1,3.4,3.7} | Threats per **global depth**; a smooth ramp (each depth slightly busier than the last), scaled again by `Depth.threatBudget` past the table and by the tier's `threatBudgetMultiplier` | higher |
| `hazardChancePerRoom` | Floors | 0.4 | Hazard roll per eligible room | higher |
| `floodedFloorChance` | Floors | 0.4 | **How often you meet water at all.** Chance a whole floor is wet; a dry floor never considers a flooded module | higher |
| `floodedRoomsPerFloor` | Floors | 1 | Pools on a wet floor. Extra flooded modules are converted back to dry, and a wet floor that lost its pools to the dry-route guarantee gets one re-flooded off-route room | higher |
| `loopConnectionChance` | Floors | 0.35 | Chance adjacent assembled rooms gain an alternate connection | higher = less linear |
| `roomModules[].weight` | Floors | 0.45–3 | Dry/water/grotto room mix. Water weights are RELATIVE ONLY — they pick which kind of pool a wet floor gets, not how often water appears | — |
| `caveMoss.*` | Floors | 5 patches/wall dry, 13 damp | Collision-neutral wall moss; rooms holding water get the denser damp palette | — |
| `geometry.*` | Floors | cell 80, walls 24/1, cave mouths 8–56 wide × 8–13 high, gap 96 | Physical scale and deterministic per-edge connection sizes | bigger cells = longer treks |
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
hand-authored per-floor tables, plus the technical limit that keeps the prototype honest.

| Value | File | Default | Controls | Harder / longer → |
|---|---|---|---|---|
| `minDepth` | Depth | 1 | Shallowest legal depth. Anything below is rejected, never clamped | — |
| `prototypeCeiling` | Depth | 20 | **Technical** ceiling on generation. Requesting a deeper floor is an error; a run that would pass it is shortened | higher |
| `authoredDepth` | Depth | 10 | The deepest global depth the hand-authored per-floor tables cover. Raise only when those tables are extended by hand | — |
| `bands` | Depth | 1–3 / 4–6 / 7–10 / 11–15 / 16–20 | Internal difficulty bands (Introduction → Extreme). Never shown to players; systems request values, not band branches | — |
| `threatBudget.perDepth` / `.maximum` | Depth | 0.06 / 1.6 | Extra threat budget per depth past `authoredDepth`, and its hard cap | higher |
| `hazardBudget.perDepth` / `.maximum` | Depth | 0.05 / 1.5 | Extra falling-dripstone density past `authoredDepth`, and its hard cap. Planner per-room and hazardous-room-fraction caps still bind above it | higher |
| `roomCountStepPerDepth` / `maxRoomsPerFloor` | Depth | 0.5 / 16 | Rooms added per depth past the authored `roomsPerFloor` table, and the absolute room ceiling | higher = longer floors |
| `rewardGrowthPerDepth` / `maxRewardDepthMultiplier` | Depth | 1.25 / 60 | Geometric growth of the brazier depth multiplier past the authored table, and its cap | higher = richer deep runs |
| `development.enabled` / `.floorsPerRun` | Depth | false / 20 | **Development only.** Ignores the tier's length and descends to the prototype ceiling. Never ship enabled | — |

## How do cave tiers and the lobby scale a run?

| Value | File | Default | Controls |
|---|---|---|---|
| `requiredCurrency` | CaveTiers | 0 / 1500 / 6000 | Persistent access threshold |
| `startDepth` | CaveTiers | 1 / 1 / 1 | Absolute global depth this tier's expedition begins at. Every tier starts at the surface today |
| `maxFloors` | CaveTiers | 6 / 8 / 10 | Floors built for that tier (reduced if it would run past `Depth.prototypeCeiling`) |
| `threatBudgetMultiplier` | CaveTiers | 0.6 / 1.1 / 1.35 | Per-floor threat budget multiplier, stacked on top of `threatBudgetPerFloor`'s own per-floor ramp |
| `rewardMultiplier` | CaveTiers | 1.0 / 1.15 / 1.5 | Brazier payout multiplier |
| `dripstoneMultiplier` | CaveTiers | 1.0 / 1.2 / 1.45 | Scales `DripstoneRules.targetCount`'s expected falling-dripstone count per floor (higher = harder) |
| `waxDrainMultiplier` | CaveTiers | 1.0 / 1.08 / 1.18 | Uniformly scales the whole `WaxDrain.perSecond` result (`WaxService.setCaveTier`) — every candle effectively burns faster (higher = harder) |
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

## How forgiving is death? — snuff, relight, wisp

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `relightWaxCost` | Death | 0.15 | What the reviver personally pays | higher |
| `snuffStateDuration` | Death | 20 | Rescue window before a snuff turns terminal | lower |
| `relightRange` / `relightHoldSeconds` | Death | 8 / 1 | Reach and deliberation of the rescue | lower / higher |
| `selfRelightDelaySeconds` | Death | 1.5 | Commitment cost of a voluntary SNUFF | higher |
| `soloSnuffIsTerminal` | Death | true | Immediately resolves an involuntary solo snuff unless the candle carries a Match; a Match presents a self-relight prompt and is consumed | false = wait for the normal rescue timeout |
| `remainsWaxFraction` | Death | 0.5 | Remaining wax deposited by a terminal death | lower |
| `minimumWax` / `maxStoredPerFloor` | Remains | 0.005 / 12 | Smallest deposit and session storage bound | higher / lower |
| `ownerMayCollect` | Remains | false | Whether the candle that left a pool may reclaim it | false |
| `pickupRange` / `pickupHoldSeconds` | Remains | 9 / 0.5 | Recovery reach and commitment | lower / higher |
| `lightIntensity` / `lightRange` | Remains | 0.45 / 12 | Visibility and Drawn attraction of a pool | higher |
| `wisp.lifetimeSeconds` | RunSettings | 120 | How long a burned-out player stays mobile | lower |
| `wisp.moveSpeed` | RunSettings | 14 | Wisp travel speed | lower |
| `wisp.lightRange` / `lightBrightness` | RunSettings | 6 / 0.4 | How much a dead friend still helps | lower |
| `wisp.bodySize` | RunSettings | 1.2 | Wisp sphere size (visual) | — |

## How clearly does danger read? — local feel and controls

These values are cosmetic and client-only. They never change wax, threat decisions, or hazard rules.
Cooldown bars cover SNUFF, FLARE, DECOY, and CUP; Sprint has no cooldown. Immediate
`ActionFeedback` is reconciled by `StateSync.actionCooldowns`, with both using
`Workspace:GetServerTimeNow()` timestamps. SNUFF displays the later of its normal cooldown and the
1.5-second voluntary relight commitment, so the bar never claims an unavailable action is ready.
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
| `ambientRockfall.*` | Feel | 80–145 s / 0.6–1.1 studs / 3.2–5.8-stud fall | Rare client-only loose stone: wall/ground query bounds, small faceted-rock scale, fall, roll, and cleanup; never affects gameplay |
| `ambientWaterDrip.*` | Feel | 70–210 s / 34-stud ceiling search | Rare sound-only cave drip: timing, roof source search, and invisible emitter cleanup; never affects gameplay |
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
| `hotbar.active*` / active display names | Feel | warm highlight + `●` / `FLARING` / `UNCUP` | Marks live Flare/Cup state while keeping voluntary Snuff's `RELIGHT` action legible |

## Where do sound assets go? — audio cues

`Audio.cues` is the event registry consumed by `client/AudioCues` and `client/MusicController`.
The menu uses `122061612190896`. The shuffled cave pool contains `71682768476112`,
`136582960170775`, `104375150403939`, and `113564986043204`, each at volume `0.352` (20% below
the original mix). The bag plays
every configured cave track once before reshuffling and prevents the last track of one bag from
immediately repeating as the first track of the next.

| Value | File | Default | Controls |
|---|---|---|---|
| `music.initialDelayMinSeconds/MaxSeconds` | Audio | 18 / 42 s | Random silence before the first cave track |
| `music.betweenTrackDelayMinSeconds/MaxSeconds` | Audio | 10 / 24 s | Random silence between cave tracks |
| `music.fadeInSeconds/fadeOutSeconds` | Audio | 4 / 5 s | Smooth music entrances, natural endings, and lobby/run switches |
| `music.endCheckIntervalSeconds` | Audio | 0.2 s | How often the client checks whether end fading should begin |
| `cues.FlyBuzz` | Audio | 9114506042 / 0.12 / 4–32 studs | Quiet spatial VoidFly warning; cave walls suppress playback |
| `cues.DripstoneFracture` | Audio | 9125929705 / 0.32 / 5–48 studs | Restrained spatial shale crack during the committed warning |
| `cues.DripstoneImpact` | Audio | 9118609396 / 0.68 / 7–68 studs | Strong nearby stone impact and debris cue |
| `cues.AmbientRockfall` | Audio | 9118609396 / 0.24 / 3–52 studs | Quieter, slightly brighter spatial stone cue for a harmless loose rock rolling from a side wall |
| `cues.AmbientWaterDrip` | Audio | built-in water impact / 0.08 / 2–26 studs | Quiet, pitched spatial cave-water drip; no visual component |

Empty one-shot IDs remain safe no-ops, and invalid, inaccessible, or unpermitted configured audio
produces a `[WICK AUDIO]` warning in client Output.

The two dripstone cues are free Creator Store assets by Pro Sound Effects. As with every Roblox
asset, verify that IDs `9125929705` (fracture) and `9118609396` (impact) remain usable by the
publishing experience before release.

Each row controls `volume`, `playbackSpeed`, `looped`, and `cooldownSeconds`; optional rolloff values
make a cue spatial when `AudioCues.playAt` attaches it to a world object. Registered events cover
dial snap, low wax, water, nearby threats, every tool, movement, Basin, Brazier, snuff/death,
relighting, and floor entry. `Audio.enabled` is the global switch; `cleanupSeconds` is the
failed/unfinished one-shot cleanup fallback. All cues and music route through `WickMaster`, so the
local settings volume changes fades and effects uniformly without rewriting individual Sound volumes.

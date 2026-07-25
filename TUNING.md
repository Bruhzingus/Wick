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
| `burnDrainPerSecond` | Wax | 0.0045 | Cost of full brightness | higher |
| `burnDrainExponent` | Wax | 1.5 | How disproportionately bright burning costs | higher |
| `movementCostMultiplier` | Wax | 0.6 | Global scalar on ALL movement costs | higher |
| `initialBurnRate` | Wax | 0.35 | Dial position at spawn (starting point only) | — |
| `startingWaxTypeId` | Wax | Standard | Starting burn profile | — |

## How much light do I get for it? — the dial

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `minBurnRate` / `maxBurnRate` | Light | 0.05 / 1.0 | The dial's floor and ceiling | narrower |
| `minRange` / `maxRange` | Light | 6 / 40 | PointLight range at each dial end (studs) | lower |
| `minBrightness` / `maxBrightness` | Light | 0.5 / 4 | PointLight brightness at each end | lower |
| `falloffExponent` | Light | 1.0 | Curve shape; >1 = dim until pushed high | higher |
| `dial.scrollStep` | Light | 0.05 | Burn rate per scroll notch | — |
| `dial.snapPoints` | Light | .25/.5/.75 | Where the slider gently sticks | — |
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
| `rendering.flicker.contextResponseSeconds` / `impactReleaseSeconds` | Light | 0.16 / 0.12 | Smooth draft/threat/sprint crossfade and recovery from a violent impact flicker | higher = softer/slower |
| `rendering.flicker.draft` / `sprint` / `threat` | Light | (7.4 Hz, .065, 211.9) / (10.7 Hz, .035, 307.2) / (4.4 Hz, .014, 401.8) | Fixed-phase local instability bands (`frequency`, `amplitude`, `phase`) added by `FeelController` context or accepted sprint | higher amplitude = less stable |
| `rendering.flicker.warmthPerBrightnessLoss` / `maximumWarmthBlend` | Light | 1.65 / 0.42 | Bounded ember-orange shift as output weakens | higher = warmer dips |
| `rendering.flicker.warmColor` / `bounceWarmColor` | Light | RGB 255,145,68 / RGB 255,96,38 | Dim-flame target palettes for the primary and bounce layers | cosmetic |
| `rendering.bloom.*` / `colorGrade.*` | Light | subtle warm defaults | Light-responsive highlight bloom and warm contrast without lifting black levels | — |
| `dialInput.sendIntervalSeconds` | Feel | 0.15 | Minimum spacing while dragging; release always sends | higher = less traffic, coarser response |
| `dialInput.serverReconcileDelaySeconds` | Feel | 0.35 | Protects a recent local dial value from an older StateSync | lower = faster authority correction |

## How much does moving cost? — run / dodge / slide

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `walkSpeed` / `runSpeed` | Movement | 8 / 16 | Travel speeds (studs/s) | lower |
| `dodgeDistance` / `dodgeSpeed` | Movement | 12 / 40 | Dash length and velocity | lower / lower |
| `dodgeCooldown` | Movement | 1.5 | Seconds between dodges | higher |
| `slideDuration` / `slideSpeed` | Movement | 0.6 / 22 | Slide length and velocity | lower |
| `slideCooldown` | Movement | 2.5 | Seconds between slides | higher |
| `walkWaxPerSecond` / `runWaxPerSecond` | Movement | 0.001 / 0.004 | Wax per second moving | higher |
| `dodgeWaxCost` / `slideWaxCost` | Movement | 0.01 / 0.008 | Wax per action | higher |
| `drainThresholds.*` | Movement | 0.75 / 0.25 | Measured-speed cutoffs for run/walk drain | lower |

## How do the tools trade off? — SNUFF / FLARE / CAST / CUP

Opposition is emergent: tools change the light field; categories react via `lightResponse` sign.
CAST is proposed by the client but grounded by the server against cave geometry. A blocked,
too-close, too-steep, or missing-floor target spends no wax and starts no cooldown.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `Snuff.cooldown` | Tools | 0.5 | How fast you can flicker in/out | higher |
| `Flare.waxCost` | Tools | 0.13 | Price of the panic button; 10% of the default 1.3-wax candle | higher |
| `Flare.cooldown` / `duration` | Tools | 4 / 1.5 | Burst spacing and length | higher / lower |
| `Flare.burstIntensity` / `burstBrightness` / `burstRange` | Tools | 3 / 6 / 60 | Threat-field strength, rendered flash, and reach | lower |
| `Cast.waxCost` | Tools | 0.04 | Wax permanently thrown away | higher |
| `Cast.cooldown` / `duration` | Tools | 3 / 6 | Decoy spacing and burn time | higher / lower |
| `Cast.castRange` | Tools | 25 | Max throw distance (server-clamped) | lower |
| `Cast.decoyIntensity` / `decoyRange` | Tools | 1.6 / 15 | Drawn-only distraction strength and reach; intensity exceeds the brightest ordinary player source before falloff | lower |
| `Cast.castPlacement.throwStartHeight` / `throwArcHeight` / `throwProbeSegments` | Tools | 1.5 / 5 studs / 16 | Server-validated parabolic throw that clears ordinary rolling floor while walls/roof still block | lower / lower / fewer |
| `Cast.castPlacement.obstructionInset` | Tools | 1 stud | Clearance before the first blocking wall/formation | lower |
| `Cast.castPlacement.groundProbeHeight` / `groundProbeDepth` / `groundProbeMaxHits` / `groundProbeAdvance` | Tools | 8 / 24 studs / 3 / 0.1 studs | Bounded Terrain-only ground search, including skipped roof undersides | shallower/fewer |
| `Cast.castPlacement.maximumGroundRise` / `minimumDistance` | Tools | 20 / 2.5 studs | Rejects implausibly high or near-self placements | lower / higher |
| `Cast.castPlacement.maxGroundSlopeDegrees` / `surfaceOffset` | Tools | 38° / 0.05 studs | Steepest legal candle surface and anti-embedding lift | lower / — |
| `Cast.decoyVisual.*` | Tools | 1.15-high × 0.35-radius body, 0.28 flame, 2.2 light brightness | Miniature distraction-candle proportions, palette, and rendered light | — |
| `Cup.waxCost` | Tools | 0.005 | Upkeep per SECOND held | higher |
| `Cup.lightMultiplier` | Tools | 0.16 | Small visible ember pocket while cupping; still hides most light | higher |
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
| `behavior.repelLightThreshold` | Threats | 0.45 | Light needed to drive a hunter back | higher |
| `behavior.repathIntervalSeconds` | Threats | 0.65 | Threat reaction time | lower |
| `behavior.wanderSpeedFraction` | Threats | 0.3 | Idle drift speed | higher |
| `behavior.stalkSpeedFraction` | Threats | 0.48 | Crawler speed while maintaining medium-light spacing | higher |
| `behavior.wanderRadius` | Threats | 25 | Idle roam range from spawn | higher |
| `behavior.darkHunterKeepDistance` | Threats | 11 | Gap a crawler holds from a medium-light candle | lower |
| `behavior.darkHunterRetreatSeconds` | Threats | 6 s | Safety window after bright light drives a crawler away | lower |
| `VoidFly.ambush.patrolRadius/activationRadius/territoryRadius` | Threats | 5 / 9 / 15 studs | Fixed-area ceiling patrol, wake-up footprint, and hard chase boundary | larger |
| `VoidFly.ambush.retreatDistance/retreatSeconds` | Threats | 13 studs / 5 s | Space and safety window bought by max exposed light, a Flare, or a teammate | shorter |
| `VoidFly.ambush.maximumCeilingHeight/ceilingClearance` | Threats | 30 / 1.5 studs | Keeps the roof tell in light/buzz range and the animated body below the exact underside | higher cap / lower clearance |
| `VoidFly.ambush.roofDecorationClearance` | Threats | 4.5 studs beyond territory | Extra margin on the full patrol/dive/retreat disc reserved from harmless formations and boulders | lower |
| `VoidFly.ambush.diveSpeed/returnSpeed/contactHeightTolerance` | Threats | 14 / 10 studs/s / 0.45 studs | Smooth vertical attack/return and the height gate before a strike can count | faster / wider tolerance |
| `VoidFly.contactAttack.*` | Threats | 0.8s, 4 hits, 0.012 wax/hit | Discrete attacks required before snuff | fewer hits / more wax |
| `VoidFly.spawnWeightByDepth` | Threats | 0 / 3.2 / 4.8 / 6.4 / 8 / 8 / 8 / 6.4 / 6.4 / 4.8 | Relative VoidFly selection weight by depth; 60% above the previous weights | higher |
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

## How dangerous is the environment? — draft, water, and unstable dripstone

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `Draft.guttering` | Hazards | 0.03 | Extra wax/s in a draft (CUP immune) | higher |
| `Draft.snuffAfterSeconds` | Hazards | 4 | Uncupped exposure that snuffs you outright | lower |
| `draftZone.*` | Hazards | 22×8×9, offset up to 9 | Avoidable room-interior wind-pocket geometry | larger |
| `draftVisual.*` | Hazards | cold haze, edge strips, 12-stud glow | Wind-pocket readability only; does not change exposure or drain | — |
| `waterPool.minSize/maxSize/maxCenterOffset` | Hazards | 10 / 18 / 9 | Localized recessed pool footprint and placement | larger |
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
| Needle | Hazards variants | 1.65 s / 5 trigger / 3.25 impact / 12% max wax | Narrow one-prong warning, footprint, and impact | shorter / larger / more loss |
| Fork | Hazards variants | 1.8 s / 5.25 trigger / 3.6 impact / 15% max wax | Split two-prong warning, footprint, and impact | shorter / larger / more loss |
| Hammer | Hazards variants | 2 s / 5.5 trigger / 4 impact / 18% max wax | Heavy three-prong warning, footprint, and impact | shorter / larger / more loss |
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
| `effects.dodgeShortenMultiplier` | Basin | 0.5 | How much dodge the Basin takes | lower |

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
| `spawnsPerFloor` | Loot | {1,1,2,2,2,2,3,3,3,3} | Planned pickups per floor | lower = fewer options |
| `definitions.*.spawnWeightByDepth` | Loot | row-specific | Depth availability and relative frequency | — |
| `definitions.*.freeCharges` | Loot | 1 | Wax-free uses granted to Flare/Cast | lower |
| `wallInsetMin` / `wallInsetMax` / `wallLateralRange` | Loot | 6 / 13 / 24 | Peripheral wall/shelf band used for pickup placement | lower inset / higher lateral range = more searching |
| `placementAttempts` / `placementFootprint` | Loot | 18 / 3.4 | Door-safe wall-pocket search and reserved pickup width | lower / higher = fewer valid pockets |
| `pickupRange` / `pickupHoldSeconds` | Loot | 8 / 0.25 | Server collection reach and prompt commitment | lower / higher |
| `visualSize` / `surfaceClearance` / `promptHeight` | Loot | 1.15 / 0.12 / 1.45 | Diegetic pickup scale, exact-ground lift, and prompt height | cosmetic |

## How big and long is a run? — floors, party, pacing

| Value | File | Default | Controls | Harder / longer → |
|---|---|---|---|---|
| `maxFloors` | Floors | 10 | Planner ceiling; selected cave tier chooses the live run limit | higher |
| `roomsPerFloor` | Floors | {6,7,8,8,9,10,10,11,12,12} | Rooms per floor | higher |
| `threatBudgetPerFloor` | Floors | {1,1,1,2,2,2,2,3,3,3} | Threats per floor | higher |
| `hazardChancePerRoom` | Floors | 0.4 | Hazard roll per eligible room | higher |
| `loopConnectionChance` | Floors | 0.35 | Chance adjacent assembled rooms gain an alternate connection | higher = less linear |
| `roomModules[].weight` | Floors | 0.45–3 | Dry/water/grotto room mix; optional water rooms are slightly favored | — |
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
| `soloAllowed` | RunSettings | true | Solo runs permitted | — |
| `startCountdownSeconds` | RunSettings | 5 | Delay before descent starts | — |
| `restartDelaySeconds` | RunSettings | 60 | Results choice window before automatic replay | — |
| `tickRate` / `stateReplicationHz` | RunSettings | 10 / 10 | Sim and sync cadence (mechanical) | — |

## How do cave tiers and the lobby scale a run?

| Value | File | Default | Controls |
|---|---|---|---|
| `requiredCurrency` | CaveTiers | 0 / 1500 / 6000 | Persistent access threshold |
| `maxFloors` | CaveTiers | 6 / 8 / 10 | Floors built for that tier |
| `threatBudgetMultiplier` | CaveTiers | 0.6 / 1.0 / 1.2 | Per-floor threat budget |
| `rewardMultiplier` | CaveTiers | 1.0 / 1.15 / 1.5 | Brazier payout multiplier |
| `minimumPlayers` | Lobby | 1 | Ready players needed to start |
| `teleportRetries` | Lobby | 2 | Reserved-server attempts after a failure |
| `arrivalWaitSeconds` | Lobby | 8 | How long a reserved expedition waits for expected teleported members before countdown |

Studio always takes the local-start branch; only a published live server exercises
`TeleportService`. ProfileStore also uses its isolated Mock in Studio, so persistence tuning and
unlock verification require a live published test.

## What protects the public prototype?

| Value | File | Default | Controls |
|---|---|---|---|
| `remoteRateLimits.*` | Security | per-remote | Per-player token-bucket burst/refill |
| `movement.sampleSeconds` | Security | 0.2 | Server displacement sampling cadence |
| `movement.trustWindowSeconds` | Security | 1 | How long displacement accumulates from one trusted anchor |
| `movement.slackMultiplier` | Security | 1.5 | Multiplier on sustained run-speed allowance |
| `movement.teleportAllowance` | Security | 2.5 | Fixed replication-jitter margin; authorized teleports reset the anchor |
| `telemetryEnabled` | Security | true | Structured prototype server-log events |

An approved dodge or slide adds its config-derived distance once within the current trusted
window. It does not increase the sustained speed allowance on every 0.2-second sample.

## How forgiving is death? — snuff, relight, wisp

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `relightWaxCost` | Death | 0.15 | What the reviver personally pays | higher |
| `snuffStateDuration` | Death | 20 | Rescue window before a snuff turns terminal | lower |
| `relightRange` / `relightHoldSeconds` | Death | 8 / 1 | Reach and deliberation of the rescue | lower / higher |
| `selfRelightDelaySeconds` | Death | 1.5 | Commitment cost of a voluntary SNUFF | higher |
| `soloSnuffIsTerminal` | Death | true | Immediately resolves an involuntary solo snuff; there is no teammate to relight the candle | false = wait for the normal rescue timeout |
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
Cooldown bars cover SNUFF, FLARE, CAST, CUP, Dodge, and Slide; Sprint has no cooldown. Immediate
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
| `draftWarning.*` / `waterWarning.*` | Feel | strong cool grading + CUP reminder | Local environmental warning tint/text; authoritative exposure still comes from the server |
| `dialSnap.*` | Feel | 0.12 s flash | Visual/audio acknowledgement when the brightness dial reaches a snap point |
| `threatWarning.radius` / `scanIntervalSeconds` | Feel | 30 / 0.25 s | Range and cadence for requesting the nearby-threat cue |
| `tutorialHints.*` | Feel | floors 1–3 / 5 s / 0.35 s fade / 12 s repeat | Bottom-screen teaching hints for authoritative threat hits and replicated water/draft entry |
| `debug.showThreatLabels` | Feel | false | Restores grey-box threat names for tuning; keep false for horror playtests |
| `controls.*` | Feel | 1–4, Q, C, Shift | Single source for real keyboard bindings, touch button positions, and hotbar labels |
| `hotbar.*` | Feel | responsive two-row legend | Desktop/mobile placement, sizing, colours, and text bounds |
| `hotbar.cooldownBarHeightScale` / `cooldownMinimumDisplaySeconds` | Feel | 0.2 / 0 s | Bar thickness and exact-deadline cutoff; keep the cutoff at zero so readiness is never shown early |
| `hotbar.cooldownLabel*` / `touchCooldownTrack*` / `touchCooldownLabel*` | Feel | key-column pill / inset native-button bar and pill | Readable numeric overlay placement on the legend and touch controls |
| `hotbar.cooldownDisplayStepSeconds` / `cooldownSecondsFormat` | Feel | 0.1 s / `%.1fs` | Numeric timer cadence; positive remainders round upward to the next display step |
| `hotbar.pulseSeconds` / `pulseScale` / `deniedFlashSeconds` | Feel | 0.15 s / 1.09 / 0.2 s | Accepted bounce and rejected-request flash |
| `hotbar.acceptedColor` / `deniedColor` | Feel | warm amber / muted red | Immediate server-accepted versus server-rejected chip acknowledgement |
| `hotbar.denialTextSeconds` / `denialMessages` | Feel | 1.1 s / friendly reason map | Temporary explanation for authoritative rejection; `InvalidTarget` reads `AIM AT OPEN GROUND` |
| `hotbar.active*` / `relightDisplayName` / `uncupDisplayName` | Feel | warm highlight / `RELIGHT` / `UNCUP` | Makes voluntary Snuff and Cup states distinct without changing gameplay |

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
| `cues.DripstoneFracture` | Audio | 9125929705 / 0.24 / 5–48 studs | Restrained spatial shale crack during the committed warning |
| `cues.DripstoneImpact` | Audio | 9118609396 / 0.68 / 7–68 studs | Strong nearby stone impact and debris cue |

Empty one-shot IDs remain safe no-ops, and invalid, inaccessible, or unpermitted configured audio
produces a `[WICK AUDIO]` warning in client Output.

The two dripstone cues are free Creator Store assets by Pro Sound Effects. As with every Roblox
asset, verify that IDs `9125929705` (fracture) and `9118609396` (impact) remain usable by the
publishing experience before release.

Each row controls `volume`, `playbackSpeed`, `looped`, and `cooldownSeconds`; optional rolloff values
make a cue spatial when `AudioCues.playAt` attaches it to a world object. Registered events cover
dial snap, low wax, draft, water, nearby threats, every tool, movement, Basin, Brazier, snuff/death,
relighting, and floor entry. `Audio.enabled` is the global switch; `cleanupSeconds` is the
failed/unfinished one-shot cleanup fallback. All cues and music route through `WickMaster`, so the
local settings volume changes fades and effects uniformly without rewriting individual Sound volumes.

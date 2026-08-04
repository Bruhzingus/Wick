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

Every candle starts NEUTRAL — there is no starting burn profile to configure. What a candle becomes
is what the run adds to it; see "What does found wax do? — candle modifiers" below.

**Phase 2 (wax pacing correction) — why these three dropped.** Measured against the real
`FloorPlanner`/`RoomNavigation` room graph (see "the wax pacing budget model" below and
`Tests/WaxPacingTests.luau`), the old values cost roughly 1.95 wax — 150% of the whole 1.3-wax
candle — just to take the default run along the shortest path to depth 12 at a modest dial, before any threat, hazard,
tool use, or mistake. Passive burn and movement drain, not threats or player choices, were the
deterministic reason nearly every run ended at the same depth. All three values were cut so the
same unavoidable default run now costs roughly 65% of the candle at depth 12 (idle and burn-coefficient
cut ~40-46% across the whole 0.18-0.78 dial so the dial's relative shape is unchanged; movement cut
to keep its ~31-33% share of the total). Sustained maximum brightness (0.78) the whole way to depth
12 still exceeds the candle on drain alone — brightness remains a real, meaningful cost.

### The wax pacing budget model (Phase 2 target)

The question this answers: **why does a run end where it ends?** Before Phase 2 the honest answer
was almost always "passive burn and movement drain," regardless of skill, threats, or luck. The
target is that the answer becomes "an accumulation of exploration, brightness choices, threats,
hazards, and mistakes" — with raw drain as a background cost, not the wall.

Every number below is expressed as a fraction of one 1.3-wax candle, measured as the worst case
across several seeds of the REAL room graph a direct player would run (`Tests/WaxPacingTests.luau`
walks `Logic/RoomNavigation`'s reciprocal-doorway graph over a `Logic/FloorPlanner`-generated floor —
never a hand-picked distance).

| Budget category | What it is | Approximate size (depth 1→12, modest 0.30 dial unless noted) |
|---|---|---|
| **Unavoidable direct-route cost** | Idle + brightness burn, plus default running, for the shortest legal path from entry to the Basin on every floor — nothing spent on threats, hazards, tools, or backtracking | ≈65% of the candle (was ≈150%, i.e. impossible alone, before Phase 2) |
| **Reasonable exploration cost** | The same per-stud/per-second rates, just over more distance and time: checking a side room for loot, missing the Basin on the first pass, circling back for a teammate | Scales linearly with the extra distance/time — no separate multiplier, so a 30-50% longer route costs roughly 30-50% more of the direct-route number above, not a punitive tax |
| **Optional greed cost** | Burning above the modest 0.30 dial for better visibility/threat reads, or pushing past depth 12 | Sustained maximum ordinary brightness (0.78) for the same depth 1→12 direct route EXCEEDS the full candle (see the test asserting this) — greed is a real, felt spend, not a rounding error |
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
  hazards (whose budgets already ramp sharply there: `threatBudgetPerFloor` 1.2→4.4,
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
| `rendering.flicker.contextResponseSeconds` / `impactReleaseSeconds` | Light | 0.16 / 0.12 | Smooth threat/default-run crossfade and recovery from a violent impact flicker | higher = softer/slower |
| `rendering.flicker.sprint` / `threat` | Light | (10.7 Hz, .035, 307.2) / (4.4 Hz, .014, 401.8) | Fixed-phase local instability bands (`frequency`, `amplitude`, `phase`) added by `FeelController` context or measured default run | higher amplitude = less stable |
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

Three rows, three bodies. Values below are the **floor 1** profile: the flat fields on the row itself.
The arrows show where `depthScaling` carries them by floor 10 (see the next section).

| Row: `speed` / `detectionRadius` / `lightResponse` / `waxDamagePerSecond` (Threats.definitions) | | |
|---|---|---|
| DarkCrawler (DarkHunter) | 8→8.2 / 23.4→34.5 / −1.0→−0.71 / 0.05→0.069 | contactRadius 3.2, bodySize 4 |
| Moth (Drawn) | 9→7.05 / 38 flat / +0.95 flat / 0.04→0.047 | contactRadius 3.2, bodySize 3.5, perches, **sustained-contact snuff from floor 4** |
| VoidFly (DarkHunter) | 7 / 20.8 / −1.0 / staged | 11.7-stud activation, 15-stud territory, four 0.012-wax strikes to snuff. A territorial row never reads `detectionRadius`; its activation footprint is the sense that carries the pass below |

Harder → higher speed/radius/damage; hunter `lightResponse` nearer 0 (harder to repel).

### The depth ramp — `definitions.*.depthScaling`

**What this replaced.** Difficulty used to ramp by COMPOSITION. Eight rows rendered as these three
bodies, and the extra five existed only to shift the mix: a deep floor drew the fast one and the
broad-sensing one more often because their spawn tables started later. That worked only while the
rows were invisible to the player, and nothing ever labelled them — the audio cues, the tutorial text
and the client models all already said "DarkCrawler" and "cave moth". Collapsing them to the
creatures they always were meant the ramp had to become something a single row can carry.

`depthScaling` is one authored value per floor, exactly the shape of `spawnWeightByDepth`, clamped at
both ends and never interpolated. `Logic/ThreatRules.atDepth` resolves it **once per spawned body**
in `ThreatService.spawnFloor`; everything downstream — the brain, contact, the visual proxy, the
client — reads a plain `ThreatDef` and knows nothing about depth. Every shipped curve is the old
composition evaluated: at each floor, the merged rows' stats averaged under their own spawn weights
at that floor. Floor 1 is exactly what floor 1 always met.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `DarkCrawler.depthScaling.detectionRadius` | Threats | 23.4 → 34.5 over 10 floors | The main ramp: a deep crawler senses half again as far, so light discipline has to be decided further ahead | steeper |
| `DarkCrawler.depthScaling.lightResponse` | Threats | −1.0 → −0.71 | The same flare buys less retreat deeper down (flee distance derives from `detectionRadius`, so the two compound) | nearer 0 |
| `DarkCrawler.depthScaling.speed` | Threats | 8 → 8.2, peaking ~8.6 mid-run | Deliberately almost flat. Outrunning a crawler is counterplay that must keep working at every floor; depth makes one harder to *avoid* and harder to *shake*, never harder to outrun | higher, but see the note |
| `DarkCrawler.depthScaling.hearing.*` | Threats | sensitivity 1.0→1.29, threshold 0.8→0.66, radius 55→73 | Ears open with depth. By the deep floors a single clean strike at close range can rouse one, which is the deep-floor mining pressure the broad-sensing row used to supply by turning up in the roll | keener |
| `Moth.depthScaling.sustainedContactSecondsToSnuff` | Threats | 0/0/0/12/11/10/9/8/7/6 | **The moth's whole ramp.** Zero through floor 3 — the teaching floors, and where the tutorial hints stop (`Feel.maxDepth` 3) — so nothing puts a player out before the game has explained itself. From floor 4 the window is real and closes | shorter |
| `Moth.depthScaling.speed` | Threats | 9 → 7.05 | Falls, because the deep composition leaned on the slow heavy-draining rows. It also means that on every floor the snuff is live the moth is already slower than a WALK (8), so a player who never sprints is never trapped by one | higher, but this is load-bearing |

### Contact that extinguishes — `Moth.sustainedContact`

This used to be a separate rare row: same body, same palette, same eye glow as an ordinary moth, no
wax damage, and contact put you out instantly. The only tell was dying to it. It is now what an
ordinary moth does to somebody who cannot get off it — the drain runs while it feeds, and if you
never break away it takes the flame. Same snuffed state, same 20-second revive, but with a window a
player can see coming and act inside of.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `Moth.sustainedContact.secondsToSnuff` | Threats | 0 (overwritten per floor by the curve above) | Seconds of unbroken contact before the candle goes out. **0 means it cannot happen at this depth**, matching `spawnWeightByDepth`'s "0 = unavailable" convention | shorter |
| `Moth.sustainedContact.graceSeconds` | Threats | 0.75 s | How long contact may lapse and still count as unbroken. Contact is a radius test against a flying body whose wings carry it across that radius constantly, so without this the mechanic could never fire against a player standing still. A real break — walking, dimming, a decoy — is longer than a wingbeat and restarts the count from nothing | longer |

Every radius above is **30% above its original value**. That is a deliberate difficulty and pacing
change, not a rebalance of any one row: sensing now reaches past the room a candle can see into, so
the brightness you are burning has to be chosen *before* you arrive somewhere rather than when
something already stands at the edge of your light. Note that the client's own `Feel.threatWarning`
"something is near" radius (30 studs) is unchanged, and is now *inside* several rows' reach — the
answer to a threat you have not sensed yet is your light discipline, not your reaction time. Flee
distance and the post-Flare blind window are both derived from `detectionRadius`, so panic light
still drives a hunter clear out of its now-wider reach.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `behavior.huntLightThreshold` | Threats | 0.2 | Effective light below which hunters commit regardless of where the player looks; includes the baseline candle's 0.18 minimum | higher |
| `behavior.darkHunterSneakLightThreshold` | Threats | 0.32 | Upper effective-light edge of the middle band where an unwatched crawler closes to contact at stalk speed | higher |
| `behavior.darkHunterObservedDotThreshold` | Threats | 0.35 | Player-facing dot required to count a crawler as watched (about a 69Â° half-angle) | higher = narrower awareness |
| `behavior.repelLightThreshold` | Threats | 0.45 | Local Flare contribution needed to drive a hunter back; ordinary light cannot trigger it | higher |
| `behavior.repathIntervalSeconds` | Threats | 0.65 | Threat reaction time | lower |
| `behavior.wanderSpeedFraction` | Threats | 0.3 | Idle drift speed | higher |
| `behavior.stalkSpeedFraction` | Threats | 0.48 | Crawler speed while maintaining watched spacing or sneaking through the unwatched middle-light band | higher |
| `behavior.wanderRadius` | Threats | 25 | Idle drift range from a threat's current home. Under the 32-stud room half-cell, so a drift stays inside one room | higher |
| `behavior.roam.minimumDwellSeconds/maximumDwellSeconds` | Threats | 30–75 s | How long a threat drifts in one room before re-homing to a room next door and drifting on, so a floor's threats redistribute themselves over a run instead of each guarding the tile it spawned on. Rolled per threat (no synchronised migration), reset by *any* sensed prey/noise/panic light, and skipped entirely by territorial rows and perched moths. The destination comes from the room graph (`RoomNavigation.roamDestination`), which prefers not to double back and can never choose the Basin | shorter = threats redistribute faster |
| `behavior.darkHunterKeepDistance` | Threats | 11 | Gap a crawler holds from a medium-light candle | lower |
| `behavior.darkHunterBlindSeconds` | Threats | 2 s | Extra blindness after estimated straight-line Flare retreat travel | lower |
| `VoidFly.ambush.patrolRadius/activationRadius/territoryRadius` | Threats | 5 / 11.7 / 15 studs | Fixed-area ceiling patrol, wake-up footprint, and hard chase boundary. The activation footprint carries this row's share of the 30% sensing pass; the territory radius deliberately did not move, because `FloorBuilder` reserves roof dressing from it | larger |
| `VoidFly.ambush.retreatDistance/retreatSeconds` | Threats | 13 studs / 5 s | Space and blind safety window bought by Flare or a teammate | shorter |
| `VoidFly.ambush.maximumCeilingHeight/ceilingClearance` | Threats | 30 / 1.5 studs | Keeps the roof tell in light/buzz range and the animated body below the *probed* underside. The clearance covers the flying body's own reach above its root plus margin for a ceiling sloping away from the single probe point. Both shrank with the body — the fly is now barely a stud wide instead of 2.6 — and the roof probe no longer reports a ceiling *above* the real one, which is what made the old 2.4 load-bearing; at 2.4 the smaller bug hangs in open air well below the rock it should be clinging to | higher cap / lower clearance |
| `VoidFly.ambush.roofDecorationClearance` | Threats | 4.5 studs beyond territory | Extra margin on the full patrol/dive/retreat disc reserved from harmless formations and boulders | lower |
| `VoidFly.ambush.diveSpeed/returnSpeed/contactHeightTolerance` | Threats | 14 / 10 studs/s / 0.45 studs | Smooth vertical attack/return and the height gate before a strike can count | faster / wider tolerance |
| `VoidFly.contactAttack.*` | Threats | 0.8s, 4 hits, 0.012 wax/hit | Discrete attacks required before snuff | fewer hits / more wax |
| `VoidFly.spawnWeightByDepth` | Threats | 0 / 3.2 / 4.8 / 6.4 / 8 / 8 / 8 / 6.4 / 6.4 / 4.8 | Relative VoidFly selection weight by depth; 60% above the previous weights | higher |
| `Moth.perch.*` | Threats | 14-stud search, 8 probes, 2.5-7 studs high, 6-16 s dwell | Idle moths cling to cave walls instead of drifting across the floor, then roam to a new wall. A perched moth cannot drain you; any light it can sense pulls it straight off the stone. **The whole row perches now** — two of the four merged drawn rows did and two did not, and since all four drew one body the difference read as moths randomly failing to land | longer dwell = calmer caves |
| `*.perch.surfaceOffset` | Threats | 2.2 studs | Gap between the wall face and a resting moth's root. Measured against the **shared `CaveMoth` body** both Drawn rows render, never the row's nominal `bodySize`: resting belly-to-stone beats the wings toward the face and the forewing carries its tip ~1.8 studs off the body, so anything under that plants the moth in the wall | lower = flusher, until it embeds |
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
| `visuals.procedural.groundOffsets` | Threats | crawler 3.72, moth 3.1, fly 0.5 | Aligns each procedural root with the server ground position. Nothing here collides, so each offset is the only thing keeping a body out of the floor and has to clear the lowest point that body's animation reaches: the moth's 2.05-stud forewing sweeps 63° through every beat, carrying its tip ~1.8 studs under the thorax, which at the old 1.8 planted moths in any sloped ground | — |
| `visuals.procedural.illuminationStep` | Threats | 0.05 | Cosmetic light-state quantization sent by the server proxy | lower = smoother, more traffic |
| `visuals.procedural.attackPulseIntervalSeconds` | Threats | 1.05 | Seconds between the cosmetic attack beats a threat in contact replicates; the `DarkCrawler` swings once per beat | lower = busier swings, never more damage |
| `visuals.procedural.attackAudio.*` | Threats | crawler/drawn/fly lunge + arrival cues, `ThreatHit`, 0.92â€“1.08Ã— pitch | Cue routing and per-hit pitch variation for server-confirmed attack pulses. The lunge row fires when the swing starts and the arrival row fires on the animation's own strike frame, so an attack is a warning followed by a blow rather than one noise | wider/faster = harsher |
| `visuals.procedural.locomotionAudio.minimumStepWeight` | Threats | 0.24 | Gait weight below which a foot plant is silent. The crawler's legs keep ticking over while it stands still; this is what stops a stationary body sounding like an approaching one | lower = a creeping threat is audible sooner |
| `visuals.procedural.locomotionAudio.quietStepVolume/loudStepVolume` | Threats | 0.35 / 1 | The band the animation's step weight is remapped into, so one cue covers a stalk and a charge | narrower = less speed information |
| `visuals.procedural.locomotionAudio.mothWing*IntervalSeconds` | Threats | 2.4–6.5 s | Moth flutter cadence, interpolated by how hard the body is being drawn toward a flame (a Seek moth beats at the low end) | shorter = more warning |
| `visuals.procedural.locomotionAudio.audibleDistance` | Threats | 48 studs | Past this no locomotion voice is spent at all; it is already beyond both cues' rolloff | — |
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
physical warning can be seen, while default running naturally spends more of the available reaction
distance. Warning and fall state are shared by the server, including when one player triggers a
formation ahead of the rest of the party.

For depth `d`, the uncapped target is `round(1 + 0.5 × (d − 1))` for F1–3,
`round(4 × 1.35^(d − 4))` for F4–6, and `round(8 × 1.28^(d − 6))` for F7+. The planner accepts a
lower result whenever one of the room, harmless-majority, doorway, hazard, readability, or spacing
safety caps prevents a valid placement.

**The shallow end is deliberately flat and the deep end deliberately steep.** Floors 1–3 are where a
player learns to read the dust, the tremor and the warning, and they cannot learn that in a room
raining rock. Everything past floor 4 is what "deeper is more dangerous" is actually made of.

**READABILITY IS MEASURED AT THE TIP, not at the roof** (`maxEligibleTipHeight`). The rule has always
been "a full-brightness candle must be able to inspect every dangerous ceiling", but the old test
asked where the roof was — which is not where the danger is. A long spire hanging from a forty-stud
roof puts its tip at twenty-two, exactly as readable as a short needle on a twenty-five-stud roof.
The old roof cap silently excluded most Ice rooms, and Ice ended up with FEWER falling hazards than
Stone despite carrying nearly twice the hazard budget.

**HOW MANY FIT IN ONE ROOM IS SETTLED BY GEOMETRY**, at roughly three or four. The lever a cave
family has on falling hazards is therefore how many ROOMS are dangerous, which is why
`CaveFamilyRules.hazardousRoomFraction` scales the authored per-band fraction by the family's own
hazard multiplier. Past roughly floor twelve a floor physically saturates and the families converge —
that is the floor being full, not the scaling failing.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `unstableDripstone.maxEligibleTipHeight` | Hazards | 26 studs | How high a dangerous formation's TIP may hang above the room floor. Replaced a roof-height cap; see above | higher |
| target curve | Hazards / DripstoneRules | F1–10: 1, 2, 2, 4, 5, 7, 10, 13, 17, 21 | Desired formations before placement/safety caps; linear F1–3, exponential F4–6 and F7+ | higher bases/growth |
| `hazardousRoomFractionEarly/Mid/Deep` | Hazards | 0.5 / 0.55 / 0.68 | Share of ordinary rooms that may hold a falling hazard, by band, before the family scalar. Half of every shallow floor stays completely safe; the planner always leaves at least one safe ordinary room however deep | higher |
| family spread scalar | CaveFamilyRules | √(family hazard multiplier), capped at 0.85 | Scales the fraction above by how hazardous the cave is here. Square-rooted so families stay separated instead of all pinning to the cap | — |
| `maxPerRoomEarly/Mid/Deep` | Hazards | 1 / 2 / 4 | Per-room cap on F1–3 / F4–6 / F7+. Geometry independently limits this to about three or four | higher |
| `maxUnstableToHarmlessRatio` | Hazards | 0.6 | Global harmless-majority cap relative to normal ceiling formations. Most of what hangs overhead must still be scenery, or inspecting ceilings stops being a skill and becomes a tax | higher |
| `placementAttempts/minCenterOffset/maxCenterOffset` | Hazards | 64 / 11 / 25 studs | Safe deterministic placement away from the room-center route | more attempts / wider usable band can increase placements |
| `doorwaySafetyPadding/minFormationSpacing` | Hazards | 8 / 12 studs | Keeps trigger zones clear of door approaches, other hazards, and one another | lower |
| `visualLengthRadiusFactor/minimumFallDistance/impactEmbedDepth` | Hazards | 2.4 / 4.5 / 0.2 studs | Conservative procedural-tip clearance, guaranteed readable drop, and model-bounds landing embed | lower clearance/drop = less warning space |
| `decorationEgressPadding` | Hazards | 4 studs | Keeps boulders, columns, and harmless roof dressing outside each trigger/escape lane | lower |
| Needle | Hazards variants | 1.65 s / 5 trigger / 3.25 impact / 20% max wax | Narrow one-prong warning, footprint, and impact | shorter / larger / more loss |
| Fork | Hazards variants | 1.8 s / 5.25 trigger / 3.6 impact / 35% max wax | Split two-prong warning, footprint, and impact | shorter / larger / more loss |
| Hammer | Hazards variants | 2 s / 5.5 trigger / 4 impact / 50% max wax | Heavy three-prong warning, footprint, and impact | shorter / larger / more loss |
| Spire | Hazards variants | 2.2 s / 5.75 trigger / 3.9 impact / 55% max wax | The long one (15.5 studs), and the only variant that can bring a readable tip down from a tall vault. Rarest by weight, slowest to warn, costliest on impact — a formation this size is visible from across a room long before it moves | shorter / larger / more loss |
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
| `layout.wallSetback` | 5 studs | How far in from the cell boundary the dormant body sits. The encounter is laid out against one **doorless wall** of the den, chosen by the planner once the room's doorways are final: the Warden sleeps in that wall as an outcrop, not as a heap in the middle of the floor. Raising this pulls the body off the wall and back into the room, which is exactly the read this replaced |
| `layout.relicStandoff` | 9 studs | How far the relic stands out from the room centre **toward** that wall — the open floor in front of the Warden, where the thing being guarded and the thing guarding it are in one view. Larger = closer to the Warden, smaller = out on the navigation hub |
| `layout.counterLateral` / `layout.counterStandoff` | 14 / 6 studs | Where the guaranteed Heavy Crown hangs: off to one side of the walk between the relic and the wall, so taking the relic and running gives you a hazard to lead it under |
| `counterDripstoneVariantId` | `Hammer` | Which unstable-dripstone variant that counter uses |
| `relicWakeRadius` | 7 studs | How close a living player on that floor has to get before the Warden wakes. **Proximity, not contact**: the relic is a small ball on a solid plinth that stops a player short of ever touching it, so a touch-only trigger meant the first thing that actually woke the encounter was bumping into the Warden. `relic.Touched` still wakes it immediately for anything that does reach it | lower = easier to read the room before committing |
| `emergence.wallDepth` / `emergence.rise` | 4.5 / 2.5 studs | How far back inside the stone the body starts and how far it stands up over `emergenceSeconds`. It steps **forward out of its wall** rather than rising out of the floor, and stays anchored until it is clear of the rock |
| `encounterClearance` | 9 | How much cave dressing is kept away from each encounter pad? |
| `fixtureFootprint` / `bowlSize` | 4 / `(4,1,4)` | How much built floor the relic fixture requires and the physical bowl it rests in. |
| `relicSize` / `relicSurfaceClearance` | `(1.6,1.6,1.6)` / 0.12 | Trigger readability and the gap that keeps it cleanly above the bowl. |
| `relicLightRange` / `relicLightBrightness` | 18 / 2.4 | Cosmetic local read of the guaranteed trigger; never enters threat light logic. |
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
| `trigger.minSpeedFraction/minAbsoluteSpeed` | AshamedLurker | 0.7 of run speed / 10 studs/s | Measured speed that counts as running through — 11.2 studs/s, clearly above Cup-slowed movement (8) and below the 16-stud default run, so the trapped half trips during ordinary movement | lower |
| `trigger.laneDepth/laneCenterY/laneHeight` | AshamedLurker | 4.5 / 2.5 / 10 studs | Trip volume through and above the opening; generous vertically because Terrain rolls up into the arch and a candle's tracked position is its base | larger |
| `trigger.grabLateralPadding/grabDepthPadding` | AshamedLurker | 0.8 / 2.5 studs | How much larger the impact-frame volume is than the trip lane. Depth is padded hard: a default runner covers ~2 studs during the wind-up, so escaping is meant to be LATERAL, not simply being fast | larger |
| `trigger.sampleHz` | AshamedLurker | 20 | Trip-detection rate. Too low and a default runner is sampled past the lane before it fires | higher |
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
| `emitters.Sprint` | Sound | 0.3 / 30 / 1.6 s | One default-run footfall burst; must stay under every threshold alone | higher |
| `emitters.DripstoneImpact` | Sound | 1.4 / 85 / 5 s | A crown hitting the floor; the cave's own loudest event | higher |
| `emitters.VineBurn` | Sound | 0.85 / 55 / 4 s | A curtain catching | higher |
| `sprintEmitIntervalSeconds` | Sound | 1.1 | How often sustained default running re-announces itself | lower |
| `maxLiveEvents` | Sound | 96 | Live-event cap; overflow drops the oldest | — |
| `hearing.curiosityThreshold` | Threats | 0.8 on floor 1, falling to 0.66 by floor 10 | Summed loudness before a DarkCrawler comes to investigate. The only row with ears; the Drawn are deaf by design so noise never blurs the light/dark read | lower |
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
| `placement.depositCounts` | Mining | E = 0.65 / 1.10 / 1.40 / 2.35 / 3.15 by depth band | **How many seams a floor carries**, weighted by global depth (0–1 on floors 1–3, rising to 2–3 on floors 7–9 and 3–4 past floor 10). Floors 1–6 are unchanged; the two deep bands gain 27% and 29% | steeper = pushes deeper |
| `placement.maxPerFloor` | Mining | 4 | Absolute clamp on the weights above, not a balance lever. At most one deposit per room, so several seams read as several detours rather than a route | — |
| `placement.footprint` / `standingClearance` | Mining | 6 / 7 | Seam plus the dry ground needed to work it | — |
| `placement.minHazardSeparation` | Mining | 9 | Clearance from pools and unstable formations | higher |
| `placement.minThreatSeparation` | Mining | 14 | Clearance from a threat's spawn point | higher |
| `visual.surfaceEmbed` / `.surfaceEmbedJitter` | Mining | 0.3 / 0.25 | How far the boulder's skirt sinks into the resolved ground, plus a per-deposit amount on top. Only the skirt goes under — the seams ride above it | — |
| `visual.shape.pedestalMin` / `.pedestalMax` | Mining | 0.7 / 1.5 | How far the seam-bearing mass is raised above the floor. Raise if deposits still read as sunk into sloped ground; lower if they read as perched | higher = more wax showing |
| `visual.shape.sizeJitterMin` / `.sizeJitterMax` | Mining | 0.82 / 1.24 | Per-axis scale of `rockSize` per deposit, so no two seams share proportions | — |
| `visual.shape.shoulderCountMin` / `.shoulderCountMax` / `.spurChance` | Mining | 2 / 4 / 0.6 | How many rock masses break the silhouette, and the odds of a crown chunk on top | — |
| `visual.seamCountMin` / `.seamCountMax` | Mining | 3 / 6 | Wax pieces per deposit. Cosmetic only — yield is `MiningRules`, not seam count | — |
| `visual.shape.seamClusterSpread` / `.sideSeamChance` | Mining | 0.34 / 0.35 | How far the seams string out along their fracture line, and the odds one strays around a side face | — |
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
| `geometry.placementProbe.upStuds` / `.downStuds` / `.horizontalMarginStuds` | Floors | 10 / 24 / 4 | Terrain-only vertical search plus the voxel-sized open-air margin that pulls loot, seams, and the Warden relic clear of shaped side walls | larger horizontal margin = safer, more central placements and fewer peripheral pockets |
| `geometry.placementProbe.maxPeripheralDeltaStuds` | Floors | 3.5 | Highest nearby floor change accepted as the same footprint; taller hits are walls/shelves and ignored | higher = more risk of seating on a wall lip |
| `geometry.placementProbe.fallbackFractions` / `.fallbackRingRadiusStuds` / `.fallbackRingSamples` | Floors | .75/.5/.25 / 4 / 8 | Deterministic inward walk and separated navigation-hub slots when the preferred centre has no built floor | smaller ring = more central repairs |
| `geometry.placementProbe.emergencyLiftStuds` | Floors | 6 | Above-centre lift used only if the guaranteed hub itself has no Terrain; always exposed in `floor_spawn_audit` | — |

Placement invariants (enforced in `Logic/FloorPlanner`, tested in `FloorPlannerTests`): never the
entry, Basin, or Brazier room; never on the guaranteed entry → Brazier → Basin route; never behind a
vine curtain; never blocking a doorway lane; always a dry interaction footprint. A failed wall
pocket retries the same off-route room's guaranteed navigation hub through every identical safety
check. **Only a floor that cannot satisfy any safe wall or hub position drops the count.**

## What is a run worth? — the extraction economy (Phase 8)

**Raw Wax is the only income in the game.** Leftover candle wax pays nothing; what you get paid for is
what you dug out of the rock and walked back up. Every number here is an **integer** — per-unit values
are whole currency and the two scalars are permille — so no payout is ever computed in floating point.

A unit is priced by the **floor it was mined out of**, never by where it was cashed in. That single
decision is what makes "farm the safe floors, then run to the bottom" worth exactly what running
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
is **~2.3 free runs**. A floor-8 Descent run nets **+1,136**; a floor-5 Deep run nets **−328**.

Those figures were re-derived when floors gained multiple seams (`Mining.placement.depositCounts`,
`unitsPerDeposit` 3 → 2). **Both previously documented anchors survive** — the free 5-floor run was
~152 and the Deep 5-floor run −316 — so the change is neutral for a typical shallow run and only the
deep end gets richer, which is the point of putting the seam count on a depth curve. Cumulative base
value by depth: **13 / 27 / 46 / 85 / 149 / 228 / 392 / 594 / 848 / 1,276**. Full derivation and the
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
costs. Once a deep floor averages 3.15 seams, that same value returns **0.236 per floor** — precisely
the fountain above. At 0.012 the return by depth band is **0.023 / 0.040 / 0.050 / 0.085 / 0.113**
against the same ~0.070 cost. Shallow floors remain a net wax loss; optional deep detours now offer
the intended wax surplus alongside their higher Raw Wax payout.

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

## What does found wax do? — candle modifiers

There is no such thing as a burn profile you swap into any more. A candle starts neutral (all
multipliers 1) and a run ADDS to it. `Logic/CandleModifiers.profile` derives the live profile every
tick from what the run has collected; nothing else may compute one.

| Value | File | Default | Controls | Stronger → |
|---|---|---|---|---|
| `lifeWax.perStack` | CandleModifiers | 0.03 | Burn-drain cut per Life Wax pickup | higher (5% is the design ceiling) |
| `lifeWax.diminishingAbove` / `.diminishedFactor` / `.maximum` | CandleModifiers | 0.50 / 0.35 / 0.65 | Soft knee and hard cap on stacked Life Wax | higher knee = longer linear run |
| `brightWax.perStack` | CandleModifiers | 0.05 | Brightness added per Bright Wax pickup | higher (5% is the design ceiling) |
| `brightWax.diminishingAbove` / `.diminishedFactor` / `.maximum` | CandleModifiers | 0.30 / 0.30 / 0.45 | Soft knee and hard cap on stacked Bright Wax | higher |
| `frozenWax.reservePerPickup` | CandleModifiers | 0.05 | Fraction of MAX wax one block banks. **Uncapped** — blocks stack, because the reserve is temporary and the melt rate below is the real limiter | higher |
| `frozenWax.meltSeconds` / `.meltFraction` | CandleModifiers | 10 / 0.0025 | Seconds at maximum brightness per melt, and the size of a melt | lower / higher |
| `frozenWax.maxBurnRateFraction` | CandleModifiers | 0.98 | Fraction of the player's OWN dial ceiling that counts as "at max" | lower = easier to trigger |
| `extraWicks.brightnessBonus` | CandleModifiers | 0.25 | Light added by a live wick bundle, for no extra wax | higher |
| `extraWicks.secondsByWickCount` | CandleModifiers | {195, 245, 290} | Nominal bundle life by rolled wick count | higher |
| `extraWicks.stretchAtMinBurn` / `.stretchAtMaxBurn` | CandleModifiers | 1.03 / 0.93 | How a dim/bright flame stretches or eats a bundle; the pair lands the real life in the 3–5 minute band | wider spread |
| `sleeve.damageReduction` | CandleModifiers | 0.40 | Fraction of a protected hit the Candle Sleeve eats | higher |
| `sleeve.charges` / `.referenceHitSeconds` | CandleModifiers | 5 / 1.2 | Reference-cadence hits a fresh sleeve survives, and the cadence a whole charge is defined against | higher / lower |
| `sleeve.minimumChargeCost` | CandleModifiers | 0.2 | Floor on one discrete swing, however fast the attacker | lower = fast attackers spend less |
| `sleeve.protects` | CandleModifiers | Threat / Dripstone / EnvironmentalFire | Which damage sources the sleeve applies to at all | — |

The Cup interaction is a **rule, not a number**: while cupping, the Extra Wicks bonus is dropped
entirely, so a cupped candle reads at exactly the darkness it always did. Bright Wax is not dropped —
that is the candle's own wax burning brighter.

The sleeve charges a **fast attacker a fraction of a charge per swing** (`cooldown / referenceHitSeconds`,
floored and capped at 1) and a **continuous drain by the second** (`dt / referenceHitSeconds`). Five
charges is therefore about six seconds of protection whatever is doing the hitting, rather than five
swings that a swarm could spend in a second.

## What loot decisions appear? — candle modifiers and prepared tools

| Value | File | Default | Controls | Harder / richer → |
|---|---|---|---|---|
| `spawnsPerFloor` | Loot | bands by depth: {0,2} to depth 4, {1,2} to 7, {1,3} to 11, {2,4} past that | Inclusive band of pickups rolled per floor. Roughly HALF the old flat {2,2,2,3,3,3,4,4,4,4}: a shallow floor averages one and can have none, a deep one reliably has a few | raise the band |
| `definitions.*.spawnWeightByDepth` | Loot | row-specific | Depth availability and relative frequency | — |
| `definitions.*.minDepthByFamily` | Loot | Candle Sleeve only: STONE 15 / MOSS 10 / ICE 5 | Hard per-cave depth gate, checked BEFORE any weight. A family missing from a present table never gets the row at all | raise = rarer |
| `definitions.*.freeCharges` / `.matchCharges` | Loot | 1 | Wax-free uses granted to Flare/Decoy, or solo self-relights stored by Match | lower |
| `wallInsetMin` / `wallInsetMax` / `wallLateralRange` | Loot | 8 / 15 / 24 | Peripheral wall/shelf band used for pickup placement | lower inset / higher lateral range = more searching |
| `minimumCenterDistance` | Loot | 14 | Closest to a room's centre a pickup may ever be PLANNED. Reserves the middle of every room — the walking line and the fighting space | higher = pushed harder against the geology |
| `fallbackRings` / `fallbackRingSamples` | Loot | 4 / 12 | Deterministic ring sweep run when every wall pocket is refused: 48 candidate shelves in two passes before any ground is given up toward the centre | higher = fewer hub fallbacks |
| `placementAttempts` / `placementFootprint` | Loot | 18 / 3.4 | Door-safe wall-pocket search and reserved pickup width | lower / higher = fewer valid pockets |
| `pickupRange` / `pickupHoldSeconds` | Loot | 8 / 0.25 | Server collection reach and prompt commitment | lower / higher |
| `visualSize` / `surfaceClearance` / `promptHeight` | Loot | 1.15 / 0.35 / 1.45 | Diegetic pickup scale, smooth-Terrain clearance beneath visible geometry, and prompt height | cosmetic |

**Where a pickup ends up, and why it is two rules and not one.** The planner keeps items off the
room's centre line (`minimumCenterDistance`) and the server keeps them out of solid rock
(`SurfaceProbe.resolvePeripheralPosition`). Both used to give up toward the same point — the room
origin — so the harder a room was to place in, the more certainly its item landed in the exact
middle. Both now sweep every other bearing at the same distance from the centre first. The room's
navigation hub survives as the final fallback in both, because it is open air in every footprint by
construction: that is what makes it impossible for a pickup to end up under the map, and
`Tests/FloorPlannerTests` holds the hub-fallback rate under 5% of all planned pickups.

## How big and long is a run? — floors, party, pacing

| Value | File | Default | Controls | Harder / longer → |
|---|---|---|---|---|
| `planningBatchSize` | Floors | 10 | Default finite batch for deterministic tests/tools only; live runs generate floors on demand | — |
| `roomsPerFloor` | Floors | {6,7,8,8,9,10,10,11,12,12} | Rooms per **global depth**; `DepthRules.getRoomCountTarget` extends the last row past this table | higher |
| `threatBudgetPerFloor` | Floors | {1.2,1.55,1.9,2.3,2.65,3.0,3.35,3.7,4.05,4.4} | Threats per **global depth**; a smooth ramp (each depth slightly busier than the last), scaled again by `Depth.threatBudget` past the table and by the tier's `threatBudgetMultiplier`. Raised ~20% from {1.0..3.7} when each family gained a signature creature: adding a threat ROW does not add bodies (the spawn roll normalises), so this is the only number that does. Because each family scales it by its own multipliers, Ice gains most and Stone least | higher |
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
| `terrain.aiGroundProbe*` / `aiObstacleSidestep` | Floors | 7 / 16 / 4 | Threat ground following and local rock detours. The probe window reconciles the analytic ground field with the voxels actually written from it; too narrow and threats sink into slopes, too wide and one finds a shelf | — |
| `terrain.aiRoofProbeFloorInset` | Floors | 2 studs | Height above the floor `server/ThreatService` casts up from to find the real, built ceiling before hanging a ceiling ambusher. Anchored to the floor because that is the one height guaranteed to be open air: the previous fixed window under the *analytic* underside began inside stone wherever the built roof hung lower than the field predicted, reported nothing, and left the fly hung from a ceiling already above it — spawned inside the rock. Must stay below the fly's own attack height so a dive is never mistaken for a ceiling | — |
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
| `startCountdownSeconds` | RunSettings | 5 | Delay before descent starts. Charged ONCE per descent: a live party spends it on the elevator ride in the lobby server, so the destination server starts immediately rather than running a second, invisible copy of it behind the loading screen. Studio has no ride and so spends it in the run server | — |
| `restartDelaySeconds` | RunSettings | 60 | Results choice window before automatic replay | — |
| `floorLookahead` | RunSettings | 3 | Floors kept carved ahead, counting the one a runner stands on. Only the FIRST is ever built synchronously — the descent blocks on floor one and nothing else; the rest fill in one floor per frame after bodies exist, which is why raising this costs memory and replication rather than loading-screen time | higher = more memory and parts resident, same wait to enter |
| `tickRate` / `stateReplicationHz` | RunSettings | 10 / 10 | Sim and sync cadence (mechanical) | — |
| `floorRecoveryDrop` | RunSettings | 32 studs | How far under its own floor a candle must be before the run puts it back at the entry. Between the deepest pool bed (2) and the next floor down (96), so only a body that has genuinely left the world qualifies | lower = twitchier recovery |

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

## How do cave families and the lobby scale a run?

Wick ships three cave families — Stone, Moss and Ice — and `Config/CaveFamilies` is the ONLY place a
cave is described. `Config/CaveTiers` is a derived projection of those rows onto the numeric tier id
the lobby, shop, party and elevator layers already speak; it carries no tuning of its own, so every
value below is edited in `CaveFamilies`. `Logic/CaveFamilyRules` is the only place they are read.

**All three begin at global depth 1.** A family is a different cave, not a deeper starting point.

**Passive wax drain is identical in all three, and `CaveFamilyRules.validate` refuses a config where
it is not.** A family may be harder through threats, hazards, topology, visibility and environment —
never through an unavoidable timer that runs faster, which is not difficulty, only a shorter run.

### Difficulty

```
resolvedThreatBudget = baseThreatBudgetForFloor x caveBaseThreatMultiplier x caveThreatBandMultiplier
resolvedHazardBudget = baseHazardBudgetForFloor x caveBaseHazardMultiplier x caveHazardBandMultiplier
```

| Value | Default (Stone / Moss / Ice) | Controls |
|---|---|---|
| `baseThreatMultiplier` | 0.60 / 1.10 / 1.35 | The family's flat threat factor, applied on top of `threatBudgetPerFloor`'s own per-floor ramp |
| `baseHazardMultiplier` | 1.00 / 1.20 / 1.45 | The same, for unstable formations (dripstone in Stone and Moss, icicles in Ice) |
| `threatBandMultipliers` | all 1.00 / 1.00–1.52 / 1.00–1.82 | Per depth band (Introduction → Extreme). Stone is flat at every band, which is what makes it the regression baseline; Moss and Ice pull away from it the deeper a run goes |
| `hazardBandMultipliers` | all 1.00 / 1.00–1.62 / 1.00–1.92 | The same, for hazards |
| `waxDrainMultiplier` | 1.00 / 1.00 / 1.00 | Uniformly scales `WaxDrain.perSecond` (`WaxService.setCaveTier`). **Must stay equal across families** — validation enforces it |
| `threatEcology.weightMultipliers` | Listener 1/0/0 · Knotwalker 0/1/0 · Calver 0/0/1 | Each family's signature creature, and a hard zero everywhere else. Zero means ABSENT, not rare: the planner reads it that way in both its eligibility check and its spawn roll. The shared trio (DarkCrawler/Moth/VoidFly) must stay above zero in every family |
| `hazardEcology.variantWeightMultipliers` | Needle 1/0.8/1.6 · Fork 1/1.3/0.8 · Hammer 1/1.5/0.5 · Spire 1/0.35/1.9 · Lance 0/0/3.0 · Mass 0/2.6/0 | Which of the shared formation pool a family's ceilings hang. Stone is the authored baseline. Hammer stays above zero everywhere because `StoneWarden.counterDripstoneVariantId` hard-names it as the encounter's counter |
| `ambience.candidateWeights` | see `Config/CaveFamilies` | How often each ambient candidate is rolled in this family. **Rate only** — a family may never change a cue's gain, its bus, or the mixer, which is what stops a quieter cave from becoming one that hides an approach |
| `ambience.silenceWeight` | 1.00 / 0.85 / 1.15 | How much of a roll is spent on authored silence. Moss is the busiest cave and Ice the quietest; validated above zero, because a cave that stopped speaking would be using absence as a difficulty lever |
| `presentation.creatures.growthCoverage` | 0 / 0.55 / 0.40 | Fraction of a body's offered anchors that carry family growth. Ice is lower because pale-on-black is the highest-contrast dressing available and already reads at longer range than Stone's bare body |
| `payoutPermille` | 1000 / 2500 / 4500 | Brazier payout scalar, as a permille integer. **Diverges from the cave-family brief**, which asked for 1.00 / 1.25 / 1.50; every fee, price and break-even in this document is derived from the shipped values, so restating them at the brief's numbers is an economy rebalance rather than a cave change. Recorded, not applied |
| `entryFee` / `unlockCost` | 0/0 · 350/5250 · 1000/15000 | Per-descent admission and the one-off price of never paying it again — fifteen descents' worth. **The brief asked for 1500 / 6000 unlocks**; that would make owning Moss cheaper than four descents. Recorded, not applied |

### Topology and geometry

| Value | Default (Stone / Moss / Ice) | Controls |
|---|---|---|
| `topology.loopBias` | 1.00 / 1.25 / 0.90 | Scales `Floors.loopConnectionChance` and the guaranteed loop minimum. Higher = more cycles = more rooms with a second way out |
| `topology.optionalBranchBias` | 1.00 / 1.20 / 1.10 | Higher continues the newest chain LESS often, leaving older rooms spare sides for side branches |
| `topology.connectorLengthBias` | 1.00 / 0.90 / 1.20 | Higher folds back beside existing rooms LESS often, spreading the floor into longer runs |
| `topology.verticalVariation` | 1.00 / 0.95 / 1.15 | Widens or narrows the ceiling spread around the family's preferred band |
| `geometry.roomSizeScale{Min,Max}` | 1.00–1.00 / 0.85–1.05 / 0.95–1.18 | Scales the fraction of the cell a footprint fills. Containment is enforced separately, so a scale above 1 asks for a bigger room and never a room bigger than its cell |
| `geometry.ceilingPreferred{Min,Max}` | 15–46 / 15–36 / 22–46 | The ceiling band this family is pulled toward |
| `geometry.ceilingPreferenceStrength` | 0.00 / 0.60 / 0.60 | How hard that pull is. Deliberately well below 1 so no family loses its tall rooms or its tight ones |
| `geometry.internalFormationDensity` | 1.00 / 1.35 / 0.80 | Scales collidable boulders and rock columns. Moss packs its rooms; Ice leaves fewer things to hide behind |
| `geometry.doorwayWidthBias` | 1.00 / 0.92 / 1.12 | Scales the rolled doorway width. Clamped against `doorwayMinWidth`, so a family can make openings tighter on average and never impassable |
| `geometry.dripstoneFactor` | 1.00 / 0.90 / 1.45 | A third multiplier on unstable formations, on top of base and band. Ice sits above the brief's nominal 1.35 to pay for something the brief could not have known: its tall ceilings leave it roughly a tenth fewer eligible rooms than Stone or Moss, because even the longest spire cannot reach a readable tip from a forty-five-stud roof |
| `roomShapeWeights` | 50/20/15/15 · 50/10/10/30 · 50/20/25/5 | Rectangle / Ellipse / Capsule / TwinLobe. Every family keeps half its ordinary rooms rectangular. Entry, Basin, completion and Warden rooms are always the full rectangle |

### Environment and ecology

| Value | Default (Stone / Moss / Ice) | Controls |
|---|---|---|
| `environment.wetFloorProbability` | 0.40 / 0.55 / 0.30 | Chance an assembled floor is wet at all (replaces the old global `Floors.floodedFloorChance`) |
| `environment.vinesEnabled` | true / true / false | Whether ambient burnable curtains generate. A Locked Store is still sealed by one in every family: that curtain is purchased content, not scenery |
| `environment.vineIntroductionShift` | 0 / 2 / 0 | Floors EARLIER curtains start appearing |
| `environment.vineCountFactor` | 1.00 / 1.35 / 0 | Scales `VineRules.targetCount` |
| `environment.flammableVegetation` | false / true / false | Whether this family grows the dry clusters a flame can light (`Config/MossFire`) |
| `threatEcology.weightMultipliers` | — / DarkCrawler 1.05, Moth 1.15, VoidFly 1.00 / DarkCrawler 1.20, Moth 0.95, VoidFly 1.20 | Scales a threat's rolled spawn weight. Moss is damp, overgrown moth country; Ice is open, bare hunting ground. Each figure is that family's old per-row values averaged under those rows' own spawn weights, so the mix a floor draws is the one it always drew. Changes WHICH of the existing roster a floor draws; **no stat, state or AI rule in `Config/Threats` is touched by a family** |
| `threatEcology.introductionShift` | — / Moth +1 / DarkCrawler +1 | Floors earlier a row's authored weight table is sampled at. Never samples below floor 1 |

### Ore

| Value | File | Default | Controls |
|---|---|---|---|
| `ore.nativeTier` | CaveFamilies | 1 / 2 / 3 | The tier a family's rock is made of, and the whole reason a harder cave is worth entering |
| `ore.availability` | CaveFamilies | Stone: T1 → 20+ 85/15 → 40+ 65/25/10; Moss: T2 → 20+ 85/15; Ice: T3 always | Deepest-first weighted bands. Adding a fourth tier is a row in `Config/Ore.tiers` plus a band here — no cave logic changes |
| `depositTargets` | Ore | 1 / 1–2 / 2 / 2–3 / 3–4 by depth band | The cave-family brief's intended seam-count envelope, identical in every family. **Not yet the live curve** — the count a floor rolls is still `MiningRules.targetCount` against `Config/Mining.placement.depositCounts`, which is what every income figure here was measured on. Adopting it is a mining/economy task |

### Presentation

| Value | Default (Stone / Moss / Ice) | Controls |
|---|---|---|
| `presentation.atmosphereColor` / `atmosphereDecay` | grey-blue / green-grey / blue-grey | Retints the one global Atmosphere per expedition (`EnvironmentSetup.applyCaveFamily`). Takes the family's hue and never its own brightness |
| `presentation.wallColor` / `rockColor` / `terrainColor` | cool blue-charcoal / dark wet green-grey / dark blue-grey | The rock palette `FloorBuilder` resolves once per floor. Every value is held below an explicit luminance bound by `Tests/CaveFamilyRulesTests`, so a retune cannot brighten a cave by accident |
| `presentation.terrainMaterial` / `wallMaterial` / `rockMaterial` | Slate·Slate·Slate / Rock·Rock·Basalt / Glacier·Glacier·Ice | THE SURFACE GRAIN, and the reason these are three caves rather than one under three gels: colour alone would leave the texture the candle actually catches identical in all of them. Flat layered slate, coarse wet rock, dense packed glacier. The test suite requires the combination to be distinct per family |
| `presentation.coverPalette` / `coverMaterial` / `coverDensityFactor` | moss 1.0 / moss 2.2 / ice 1.4 | Collision-neutral wall cover, scaling the authored `Floors.caveMoss` patch counts |
| `presentation.formationPalette` / `formationMaterials` | slate / damp green-grey / pale glacier | What every stalactite, stalagmite, boulder and unstable formation is built from. This is all an Ice "icicle" is: the same hazard with the same warning, fall timing and impact rules, cut from ice |
| `presentation.threatVariantId` / `threatVariantTintStrength` | Stone 0 / Moss 0.22 / Ice 0.18 | How strongly a threat body is tinted toward its cave. **Presentation only.** Crimson dark-hunter eyes, yellow Drawn eyes and moth wings are never tinted, and the strength is capped low so a threat is never camouflaged against the rock it stands on |

### Moss flammable vegetation (`Config/MossFire`)

| Value | Default | Controls |
|---|---|---|
| `chanceByDepth` | 0.10 / 0.13 / 0.16 / 0.20 by band | Chance an ELIGIBLE ordinary Moss room carries a cluster. Uncommon on purpose: at depth 16, four rooms in five still have nothing to burn |
| `placement.maxClustersPerRoom` | 1 | Hard cap, and the reason the feature stays legible |
| `placement.maxActiveClustersPerFloor` | 4 | Hard cap on clusters alight at once. A cluster at full ignition progress WAITS for a slot rather than losing its progress |
| `placement.obstructionChance` | 0.45 | Chance a cluster also forms a collidable mass burning clears. Safe by construction: a cluster is never on a route, in a lane, or on the hub |
| `ignition.low/medium/highExposureSeconds` | 2.5 / 1.5 / 0.75 | Seconds of continuous exposure to ignite, interpolated continuously from the flame's burn rate |
| `ignition.lowBurnFraction` | 0.33 | Below this fraction of maximum burn a flame contributes NOTHING. A cupped flame contributes zero at any dial |
| `ignition.decayPerSecond` | 0.25 | Progress lost once every source leaves range, so a half-lit cluster is not a trap left armed |
| `ignition.flareIgnitesImmediately` | true | A Flare is instant |
| `spread.normal/quickIntervalSeconds` | 0.75 / 0.25 | How often fire tries to move along ordinary growth and along a quick-burning strand |
| `kinds[].burnSeconds{Min,Max}` | 6–10 ordinary / 3–5 quick | How long a node burns |
| `light.intensity` / `range` | 1.15 / 26 | Ordinary environmental light. Attracts the Drawn; **never forces the dark-hunter retreat only a real Flare causes** |
| `heat.near/farWaxPerSecond` | 0.020 within 4 studs / 0.008 within 8 | Living Wax per second. No second meter |
| `heat.clusterCapPerSecond` | 0.025 | The most one cluster can cost per second however many nodes are alight |

### Lobby

| Value | File | Default | Controls |
|---|---|---|---|
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
| `runSpeed` / `jumpPower` | LobbyRoom | 30 / 48 | Lobby-only default movement. Costs no wax (there is no `PlayerState`), and has no manual sprint binding |
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
| `body.walkSpeed` | Spectator | 14 | Ghost travel speed; faster than Cup-slowed movement (8), slower than the living default run (16) | lower |
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
Cooldown bars cover FLARE, DECOY, and CUP. Immediate
`ActionFeedback` is reconciled by `StateSync.actionCooldowns`, with both using
`Workspace:GetServerTimeNow()` timestamps, so the bar never claims an unavailable action is ready.
On touch devices the same title, timer, and shrinking fill are mirrored onto Roblox's native
ContextActionService buttons without changing their binding or placement.

| Value | File | Default | Controls |
|---|---|---|---|
| `lowWax.threshold` / `urgentThreshold` | Feel | 0.25 / 0.10 | When the wax bar begins pulsing and changes to its urgent colour |
| `lowWax.pulseFrequencyHz` / colour blend | Feel | 1.6 Hz / 0.25–0.85 | Warning pulse speed and strength |
| `sprintFeedback.normalFov` / `sprintFov` | Feel | 74 / 85 | Restrained view expansion while the default run is moving |
| `sprintFeedback.transitionSeconds` | Feel | 0.4 s | Time to enter or leave the default-run strain |
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
| `itemHints.enabled` / `.messages` | Feel | on / one line per `Config/Loot` id | What a pickup says the FIRST time that player ever collects it. Shares the tutorial-hint panel but is exempt from `tutorialHints.maxDepth` and its throttles — a one-shot hint has no second showing to fall back on, and the Candle Sleeve cannot even appear before floor 5. Recorded per profile (`Persistence.seenHints`), so a returning player is never re-taught |
| `debug.showThreatLabels` | Feel | false | Restores grey-box threat names for tuning; keep false for horror playtests |
| `controls.*` | Feel | 1–3 tools plus utility bindings | Single source for real keyboard bindings, touch button positions, and hotbar labels; movement has no manual sprint binding |
| `hotbar.*` | Feel | responsive tool legend | Desktop/mobile placement, sizing, colours, and text bounds |
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
| `buses.Music/Ambience/World/Focus/UI` | Audio | nested beneath `WickMaster`; Ambience 0.75 | Category headroom; every cave-only ambience cue is 25% below authored gain; cave EQ/reverb; Focus sidechains gently duck Music/Ambience for critical reads |
| `cues[*].cooldownSeconds` | Audio | cue-specific | Spatial cooldowns apply per emitter; non-spatial/UI cooldowns remain global, so independent world contacts do not mute one another |
| `occlusion.*` | Audio | 0.68 direct volume / -1,-5,-17 dB EQ | One-shot ray obstruction keeps the reverb tail while filtering direct sound through rock |
| `music.initialDelayMinSeconds/MaxSeconds` | Audio | 18 / 42 s | Random silence before the first cave track |
| `music.betweenTrackDelayMinSeconds/MaxSeconds` | Audio | 10 / 24 s | Random silence between cave tracks |
| `music.fadeInSeconds/fadeOutSeconds` | Audio | 4 / 5 s | Smooth music entrances, natural endings, and lobby/run switches |
| `music.endCheckIntervalSeconds` | Audio | 0.2 s | How often the client checks whether end fading should begin |
| Landing `MENU MUSIC` slider | Settings/MusicController | 100% | Per-client multiplier for the menu loop only; hidden during expeditions, and it never changes the cave playlist or LOCAL AUDIO master |
| `cues.FlyBuzz` | Audio | 9114506042 / 0.12 / 4–32 studs | Quiet spatial VoidFly warning; cave walls suppress playback |
| `cues.DarkCrawlerAttack` | Audio | 9125929705 / 0.88 / 0.58Ã— / 7â€“64 studs | Low, dry joint-fracture attack layer emitted from a crawler that lands contact |
| `cues.DrawnAttack` | Audio | 9114506042 / 0.78 / 0.68Ã— / 6â€“52 studs | Low hostile insect burst emitted from a Drawn threat that lands contact |
| `cues.VoidFlyAttack` | Audio | 9114506042 / 0.86 / 1.38Ã— / 5â€“40 studs | Sharp close dive burst emitted on a confirmed VoidFly strike |
| `cues.ThreatHit` | Audio | 9118609396 / 0.94 / 0.7Ã— | Heavy non-spatial impact sting heard only by the confirmed victim |
| `cues.DarkCrawlerLunge` | Audio | 9125929705 / 0.44 / 0.5× / 6–58 studs | The crawler's wind-up: the same fracture source taken low enough to read as a joint unfolding. Fires when the swing starts, so it is the warning before the blow |
| `cues.DrawnLunge` | Audio | 9114506042 / 0.4 / 0.46× / 5–44 studs | A low wet chitter as a moth's fangs gape, one beat before the bite |
| `cues.VoidFlyLunge` | Audio | 9114506042 / 0.42 / 1.85× / 4–38 studs | A thin shriek directly overhead as the fly commits to its dive |
| `cues.ThreatStep` | Audio | 9113218672 / 0.19 / 0.72× / 4–46 studs | Grit under a long bony foot. Played once per animated foot plant and scaled by the gait's own weight, so a stalk is nearly silent and a charge is not. Wide pitch variance keeps a run from becoming a metronome | louder/farther = more warning |
| `cues.MothWing` | Audio | 9120698168 / 0.085 / 1.5× / 3–28 studs | Dry paper wings — a moth's equivalent of a footstep, on an interval rather than per beat | louder/farther = more warning |
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

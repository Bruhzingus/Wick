# TUNING — the feel surface

Every tunable value in the game, grouped by **the question you're answering when you reach for
it** — not by file. All gameplay tuning lives in `src/shared/Config/`. "Harder →" is the
direction that makes the game more punishing. **Two different things are called wax and they never
mix.** *Living Wax* is the candle — health, light, fuel and timer at once — and is measured in candle
units; divide by `Wax.maxWax` for a displayed fraction. *Raw Wax* is the cargo you mine and the
currency it becomes, and is measured in whole **grams**.
Change a value, let Rojo sync, play — no logic edits, ever.

---

## How long do I survive? — the burn economy

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `startingWax` | Wax | 1.3 | Wax a fresh candle begins with (30% above the original capacity) | lower |
| `maxWax` | Wax | 1.3 | Absolute wax ceiling; visuals normalize against this | lower |
| `idleDrainPerSecond` | Wax | 0.0002875 (0.00025 Phase 2, +15% burn-rate pass; was 0.0005 pre-Phase 2) | Cost of merely being lit | higher |
| `burnDrainPerSecond` | Wax | 0.00207 (0.0018 Phase 2, +15% burn-rate pass; was 0.0045 pre-Phase 2) | Brightness-drain coefficient at burnRate 1; the ordinary dial now caps at 0.78 | higher |
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

**Burn-rate pass.** `idleDrainPerSecond` and `burnDrainPerSecond` were each raised 15% above their
Phase 2 values (candle burns down faster; movement drain untouched). Since burn is only part of the
unavoidable direct-route cost, the depth-12 direct-route figure above rises by a few points, not 15% —
re-run `Tests/WaxPacingTests.luau` after any further burn-rate change to get the exact new number.

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

The shared three plus one signature body per cave. Values below are the **floor 1** profile: the flat fields on the row itself.
The arrows show where `depthScaling` carries them by floor 10 (see the next section).

| Row: `speed` / `detectionRadius` / `lightResponse` / `waxDamagePerSecond` (Threats.definitions) | | |
|---|---|---|
| DarkCrawler (DarkHunter) | 10.4→10.71 / 23.4→34.5 / −1.0→−0.71 / 0.05→0.069 | Entire speed curve is 30% faster; contactRadius 3.2, bodySize 4 |
| Moth (Drawn) | 11.7→9.165 / 38 flat / +0.95 flat / 0.04→0.047 | Entire speed curve is 30% faster; perches, **sustained-contact snuff from floor 4** |
| VoidFly (DarkHunter) | 9.8 / 20.8 / −1.0 / staged | 40% faster, including its 19.6/14-stud dive/return; four 0.012-wax strikes to snuff |
| Listener / Knotwalker / Calver | 9.75 / 9.1 / 7.8 | Each is 30% faster; Calver roof return is 9.1 |

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
| `DarkCrawler.depthScaling.speed` | Threats | 10.4 → 10.712, peaking 11.232 mid-run | The original near-flat curve, uniformly raised 30%; escape now requires a real run and its wax cost | higher |
| `DarkCrawler.depthScaling.hearing.*` | Threats | sensitivity 1.0→1.29, threshold 0.8→0.66, radius 55→73 | Ears open with depth. By the deep floors a single clean strike at close range can rouse one, which is the deep-floor mining pressure the broad-sensing row used to supply by turning up in the roll | keener |
| `Moth.depthScaling.sustainedContactSecondsToSnuff` | Threats | 0/0/0/12/11/10/9/8/7/6 | **The moth's whole ramp.** Zero through floor 3 — the teaching floors, and where the tutorial hints stop (`Feel.maxDepth` 3) — so nothing puts a player out before the game has explained itself. From floor 4 the window is real and closes | shorter |
| `Moth.depthScaling.speed` | Threats | 11.7 → 9.165 | The original falling curve, uniformly raised 30%. It stays below a run but above a walk, so escaping sustained contact spends movement wax | higher |

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
| `VoidFly.ambush.patrolAngularSpeed/patrolRadiusBreath` | Threats | 0.55 rad/s / 0.45 | The circuit it actually flies around its anchor, and how much the orbit tightens and opens. 0.55 rad/s over a 5-stud orbit is ~2.8 studs/s of travel, which is almost exactly what `wanderSpeedFraction` (0.3) of the row's 9.8 speed sustains — raise one without the other and the body permanently trails its own target. **Zero here is a fly bolted to one stone**, which is the bug the whole patrol exists to remove | faster = harder to predict |
| `VoidFly.ambush.patrolDriftFraction/patrolDriftSpeed` | Threats | 0.6 / 0.06 rad/s | How much of the room between the orbit and the territory (15 − 5 = 10 studs) the circuit's *centre* may wander through, and how fast. Bounded by construction so the whole path stays inside the ceiling disc `FloorBuilder` kept clear of dressing | higher = the patch you walked under moves more |
| `VoidFly.ambush.pursuitSeconds/pursuitRadius/pursuitSpeedMultiplier` | Threats | 10 s / 26 studs / 1.4× | The harassment. Once committed it follows its victim past the territory for a fixed window at 1.4 × 9.8 = 13.7 studs/s — **above `Movement.walkSpeed` (8) and below `runSpeed` (16)**, which is the whole counterplay: walking away no longer works, running still does. The radius stays inside one 64-stud room, so this is never a chase across the cave. Changing the multiplier past a run changes the creature's category, not its difficulty | longer / wider / faster |
| `VoidFly.ambush.pursuitRecoverySeconds` | Threats | 7 s | After the window ends it goes home and ignores everybody for this long — what surviving a harassment actually buys | shorter |
| `VoidFly.ambush.rousedLoudness/rousedActivationMultiplier` | Threats | 0.45 / 1.55× | Summed loudness that counts as roused, and how far the disc it will dive for widens while it lasts (11.7 → 18.1 studs). One landing (0.5) clears it on its own: this is what "do not jump around under a low ceiling" costs. Needs no state — the widening lasts exactly as long as the noise does | lower threshold / wider |
| `VoidFly.hearing.*` | Threats | 1.15 / 0.42 / 34 studs / 5 s / 0.85 | The roster's lowest curiosity threshold, on its smallest ears. Being heard repositions it on its patch and widens its dive disc; `Logic/ThreatBrain` clamps a fly's investigation to its own territory, so a noise can never lead one out of its room or become a target | lower threshold |
| `VoidFly.ambush.retreatDistance/retreatSeconds` | Threats | 13 studs / 5 s | Space and blind safety window bought by Flare or a teammate | shorter |
| `Calver.ceilingStrike.patrolAngularSpeed/*` | Threats | 0.11 rad/s, 0.3 breath, 0.3 drift, 0.02 rad/s | The same circuit, authored at roughly a fifth of the fly's rate: a heavy body hauling itself around its vault, so the thing that hammers your ceiling is never quite where you left it. Both roof-bound rows read these through `Logic/ThreatRules.roofProfile` | faster |
| `VoidFly.ambush.maximumCeilingHeight/ceilingClearance` | Threats | 30 / 1.5 studs | Keeps the roof tell in light/buzz range and the animated body below the *probed* underside. The clearance covers the flying body's own reach above its root plus margin for a ceiling sloping away from the single probe point. Both shrank with the body — the fly is now barely a stud wide instead of 2.6 — and the roof probe no longer reports a ceiling *above* the real one, which is what made the old 2.4 load-bearing; at 2.4 the smaller bug hangs in open air well below the rock it should be clinging to | higher cap / lower clearance |
| `VoidFly.ambush.roofDecorationClearance` | Threats | 4.5 studs beyond territory | Extra margin on the full patrol/dive/retreat disc reserved from harmless formations and boulders | lower |
| `VoidFly.ambush.diveSpeed/returnSpeed/contactHeightTolerance` | Threats | 19.6 / 14 studs/s / 0.45 studs | The fly's 40% speed pass applies to both vertical legs; the height gate is unchanged | faster / wider tolerance |
| `VoidFly.contactAttack.*` | Threats | 0.8s, 4 hits, 0.012 wax/hit | Discrete attacks required before snuff | fewer hits / more wax |
| `VoidFly.spawnWeightByDepth` | Threats | 0 / 3.2 / 4.8 / 6.4 / 8 / 8 / 8 / 6.4 / 6.4 / 4.8 | Relative VoidFly selection weight by depth; 60% above the previous weights | higher |
| `Moth.perch.*` | Threats | 14-stud search, 8 probes, 2.5-7 studs high, 6-16 s dwell | Idle moths cling to cave walls instead of drifting across the floor, then roam to a new wall. A perched moth cannot drain you; any light it can sense pulls it straight off the stone. **The whole row perches now** — two of the four merged drawn rows did and two did not, and since all four drew one body the difference read as moths randomly failing to land | longer dwell = calmer caves |
| `*.perch.surfaceOffset` | Threats | 2.2 studs | Gap between the wall face and a resting moth's root. Measured against the **shared `CaveMoth` body** both Drawn rows render, never the row's nominal `bodySize`: resting belly-to-stone beats the wings toward the face and the forewing carries its tip ~1.8 studs off the body, so anything under that plants the moth in the wall | lower = flusher, until it embeds |
| `*.perch.minimumWallSlopeDegrees` | Threats | 55° | How far from horizontal a face must tilt to count as a wall rather than floor or roof | higher = fewer legal perches |
| `definitions.*.spawnWeightByDepth` | Threats | row-specific | Relative floor-by-floor likelihood; 0 disables a row at that depth | higher late weights = tougher deep mix |
| `visuals.darkHunter.*` | Threats | near-black body, angled deep-crimson Neon slits, 2.5-stud glow | Emergency grey-box fallback hunter silhouette/eye warning (`visuals.procedural.enabled = false` only) | — |
| `visuals.drawn.*` | Threats | charcoal-taupe body, neutral grey translucent wings | Emergency grey-box fallback moth body/wing palette (`visuals.procedural.enabled = false` only) | — |

The detailed procedural bodies used by default (`visuals.procedural.enabled = true`) do **not**
read these two fallback rows. Each of the six builders in `src/shared/NewModelsAndObjects/` owns its
palette and eye-glow constants. Dark-hunter eyes remain crimson (idle/locked red); moth eyes remain
faint warm yellow that brightens with attraction. Tune colour in the creature file, and tune attack
timing/magnitude in the shared `attackMotion` table below.
| `visuals.procedural.enabled` | Threats | true | Detailed client-built bodies; false restores emergency grey-box server visuals | — |
| `visuals.procedural.cullDistance` | Threats | 120 | Distance beyond which a client removes a detailed body from Workspace | lower = faster |
| `visuals.procedural.cullHysteresis` | Threats | 12 | Extra retention range preventing rebuild churn at the cull boundary | higher = more retained bodies |
| `visuals.procedural.groundOffsets` | Threats | crawler 3.72, moth 3.1, fly 0.5, Listener 2.65, Knotwalker 3.95, Calver 0.6 | Aligns each procedural root with its server surface position. Nothing here collides, so each offset is the only thing keeping a body out of floor/roof rock and must clear that body's lowest animated extremity | — |
| `visuals.procedural.illuminationStep` | Threats | 0.05 | Cosmetic light-state quantization sent by the server proxy | lower = smoother, more traffic |
| `visuals.procedural.attackPulseIntervalSeconds` | Threats | 1.05 | Default spacing between confirmed-contact cosmetic beats. A staged contact row uses its own hit cooldown instead (`VoidFly.contactAttack.cooldownSeconds` = 0.8), so presentation cannot suppress a real server-resolved bite | lower = busier swings, never more damage |
| `visuals.procedural.attackMotion.*.(anticipationSeconds/strikeSeconds/recoverySeconds)` | Threats | Crawler .22/.13/.56; Moth .16/.08/.34; CeilingFly .07/.055/.28; Listener .23/.15/.46; Knotwalker .25/.16/.52; Calver .82/.28/.70 | Three explicit phases for every body. Ordinary actions must settle before their next presentation beat. Calver is different: its timestamped intent starts before the effect, and .82 + .28 = the authoritative 1.10-second ceiling wind-up | longer anticipation/recovery = more readable |
| `visuals.procedural.attackMotion.*.impactFraction` | Threats | .72 / .78 / .75 / .72 / .76 / 1.0 | Arrival point inside the strike phase; drives `consumeImpact` and therefore the spatial impact cue. Calver's 1.0 pins hammer contact to the moment the server begins the independent dripstone warning | earlier = snappier |
| `visuals.procedural.attackMotion.*` silhouette fields | Threats | per kind | Full-body local offsets/angles: crawler hip/spine/jaw/swipe, moth jab/wing/abdomen, fly tuck/pivot/bite, Listener skull/ears/brace, Knotwalker reach/hand lead/reset, Calver brace/hammers/hold. Presentation only; none is read by AI, contact, wax, or death | cosmetic |
| `visuals.procedural.attackAudio.*CueNames` | Threats | explicit lunge + arrival cue for all six body kinds, `ThreatHit`, 0.92–1.08× pitch | No body inherits another creature's voice. The lunge fires at commitment and arrival fires on the model's strike frame | wider/faster = harsher |
| `visuals.procedural.locomotionAudio.minimumStepWeight` | Threats | 0.24 | Gait weight below which a foot plant is silent. The crawler's legs keep ticking over while it stands still; this is what stops a stationary body sounding like an approaching one | lower = a creeping threat is audible sooner |
| `visuals.procedural.locomotionAudio.quietStepVolume/loudStepVolume` | Threats | 0.35 / 1 | The band the animation's step weight is remapped into, so one cue covers a stalk and a charge | narrower = less speed information |
| `visuals.procedural.locomotionAudio.mothWing*IntervalSeconds` | Threats | 2.4–6.5 s | Moth flutter cadence, interpolated by how hard the body is being drawn toward a flame (a Seek moth beats at the low end) | shorter = more warning |
| `visuals.procedural.locomotionAudio.audibleDistance` | Threats | 48 studs | Past this no locomotion voice is spent at all; it is already beyond both cues' rolloff | — |
| `visuals.procedural.ceilingFlyBuzz.*` | Threats | 9–20 s / 32 studs / 0.35-stud endpoint inset | Random buzz timing, retry cadence, audible proximity, and roof-safe LOS endpoint | shorter/farther = more warning |

## How dangerous is the wick-pack? — Wax Grub / Stone Gnawer / Longarm

A second creature layer, budgeted per species against depth (`Logic/EnemySpawnRules`) rather than
drawn from the shared per-room threat roll. All damage below is expressed as a fraction of
`Config.Wax.maxWax` (1.3) and routes through `WaxService.drainExternal`, the same channel every other
threat's contact uses — never a separate health pool.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `BROOD_CHANCE` by depth (F1–10) | EnemySpawnRules | 0, .35, .45, .5, .55, .6, .6, .65, .65, .7 | Chance a floor rolls one Wax Grub brood. Floor 1 is always clear, same as the dynamite schedule | higher |
| `SECOND_BROOD_CHANCE` by depth | EnemySpawnRules | 0, 0, .12, .16, .2, .24, .26, .28, .3, .32 | Rolled only if the first brood landed, so two is genuinely uncommon | higher |
| `GNAWER_CHANCE` / `LONGARM_CHANCE` by depth (F5–10) | EnemySpawnRules | .18–.42 / .16–.4 | Per-floor odds of one Stone Gnawer / one Longarm | higher |
| `TIER_THREE_MIN_DEPTH` | EnemySpawnRules | 5 | Hard floor under both curves — no retune can put a Gnawer or Longarm on an early floor | lower |
| `allowsGnawerWithLongarm` room width | EnemySpawnRules | 40 studs | Below this, the two never share a floor | lower |
| `minimumGnawerRoomWidth` | EnemySpawnRules | 20 studs | Clear width a Gnawer's room needs perpendicular to its charge line, or there is nowhere to dodge | lower |
| `WaxGrub.health` / `speed` / `fleeSpeed` | WaxGrub | 12 / 6 / 11 | Body stats. Not player-facing — a grub is never fought, only stomped or flared off | — |
| `WaxGrub.drainPerSecond` | WaxGrub | 0.05 | Latched drain. A half-wax candle survives ≈13s latched; down from an earlier 0.2 that killed the same candle in ≈3.25s | higher |
| `WaxGrub.broodMin` / `broodMax` | WaxGrub | 2 / 5 | Smaller than the pack's stock 4–8 — an owner call so a room of grubs still reads as individuals, not a carpet | higher |
| `WaxGrub.stompRadius` | WaxGrub | 4.5 | How close a landing foot must be to scare a wandering grub | lower |
| `WaxGrub.shakeStompsMin` / `Max` | WaxGrub | 1 / 3 | Stomps needed to shake off a LATCHED grub, rolled per latch | higher |
| `WaxGrub.stompFleeSeconds` | WaxGrub | 4.5 | How long a scared grub stays away | lower |
| `WaxGrub.trailFollowSpeed` / `eatSeconds` | WaxGrub | 4 / 1 | Speed drifting toward the nearest live drip-trail drop, and how long it parks there feeding before retargeting | higher / lower |
| `WaxGrub.flareThreshold` | WaxGrub | 0.72 | Fed a FLARE-SPIKE value (1.0 while a flare burns, 0 otherwise), never continuous ambient brightness — a fifth light-fleeing creature reading ambient light would read as more of the DarkCrawler/VoidFly/Knotwalker/Calver pile | lower |
| `WaxGrub.blast` | WaxGrub | 1 hit point | One point-blank stick removes it, same as an ordinary threat row |
| `StoneGnawer.health` / `walkSpeed` / `chargeSpeed` | StoneGnawer | 140 / 6 / 26 | Eyeless. Hunts entirely by sound; the brightness dial does nothing to it |
| `StoneGnawer.chargeDamage` | StoneGnawer | 0.75 (≈58% of max) | The single worst avoidable wax loss on the roster, deliberately above every `Hazards.luau` ceiling (0.55) | higher |
| `StoneGnawer.chargeLockSeconds` / `staggerSeconds` | StoneGnawer | 1.6 / 2.0 | Cannot steer once committed; colliding with rock staggers it | shorter lock / shorter stagger |
| `StoneGnawer.warnSeconds` | StoneGnawer | 1.1 | MUST NOT SHRINK — already accounts for ~150–300ms of Bluetooth audio latency; under ~450ms the tell arrives after the hit | shorter |
| `StoneGnawer.hearSprint` / `hearWalk` | StoneGnawer | 42 / 16 | Charge-commit hearing, deliberately worse than the Cave Listener's 34/95 reach — what it gives up in range it buys back in charge speed and distance | higher |
| `StoneGnawer.hearDripstone` | StoneGnawer | 72 | Falling stone is the one sound it cannot ignore — it answers a collapse from across the room |
| `StoneGnawer.huntRadius` / `huntSeconds` | StoneGnawer | 150 studs / 22 s | Second channel: WALKS toward big structural noise (dripstone, seam breaks, detonations) too far away to charge at. Player noise is deliberately absent from this channel | higher / longer |
| `StoneGnawer.grazeRadius` | StoneGnawer | 14 studs | Orbits its spawn point and never truly leaves the room it was placed in |
| `StoneGnawer.blast` | StoneGnawer | 2 hit points, non-lethal blast staggers it | The heaviest body on the roster besides the Warden to survive one stick |
| `Longarm.health` / `speed` / `fleeSpeed` | Longarm | 80 / 4.5 / 9 | Slow, silent, gives no idle sound — the only creature offering nothing to hear before it commits |
| `Longarm.reachMax` / `reachGrab` | Longarm | 9.0 / 6.0 studs | Measured off the BUILT rig, not chosen. `reachMax` is the outer slash band; inside `reachGrab` it thrusts and grabs |
| `Longarm.grazeDamage` / `grabDamage` | Longarm | 0.22 (≈17%) / 0.55 (≈42%) | Grab is survivable from anything above half a candle, which is what makes the ignore window below meaningful |
| `Longarm.ignoreSeconds` | Longarm | 6.0 | NOT OPTIONAL — in a game with no player attack, a grab that can immediately re-grab is unrecoverable |
| `Longarm.flareThreshold` | Longarm | 0.78 | The only thing that scares it. Above anything ambient candle brightness reaches, so only an actual Flare crosses it |
| `Longarm.decoyInterest` | Longarm | 26 | A thrown Decoy candle pulls it away in preference to any player |
| `Longarm.blast` | Longarm | 1 hit point | One point-blank stick removes it |
| `GrubQueen.health` / `dynamiteDamage` | GrubQueen | 6 / 1 per detonation | FLAT COUNT, not distance-scaled — every stick landed within blast radius counts as exactly one charge |
| `GrubQueen.broodInterval` / `broodCount` / `maxLiveGrubs` | GrubQueen | 7.5 s / 2 / 14 | Continuous attrition pressure during the fight |
| `GrubQueen.guardCount` | GrubQueen | 2 | Longarms chained to her chamber, not spawned by her the way grubs are |
| `GrubQueen.callInterval` | GrubQueen | 26 s | Alerts the whole room; the pressure valve if a party is doing well |
| `GrubQueen.crawlSpeed` | GrubQueen | 1.8 | A quarter of a walk, an eighth of a run — she can never catch anybody. What she takes is the corner of the room |
| `GrubQueen.turnDegreesPerSecond` | GrubQueen | 24 | Slow, generous — the counter to the bite is staying behind her |
| `GrubQueen.leashRadius` | GrubQueen | 46 studs | Sized to her chamber; the encounter is meant to be survivable by leaving the room |
| `GrubQueen.biteDamage` | GrubQueen | 0.8 (≈62%, the biggest single hit in the game) | Telegraphed by a half-second rear-back and only lands in the arc in front of her |
| `GrubQueen.biteRange` / `biteArcDot` / `biteInterval` | GrubQueen | 9.0 studs / 0.35 (≈70°) / 4.5 s | Arc, reach, and cooldown |
| `GrubQueen.minIntervalFloors` / `maxIntervalFloors` | GrubQueen | 10 / 15 | Cadence between boss floors, walked deterministically from the run seed |
| `GrubQueen.requiresKillToDescend` | GrubQueen | true | The one hazard in the game a party cannot simply route around — DESIGN §9a |
| `BossFloorPlan.DYNAMITE_RESPAWN_SECONDS` / `WAX_RESPAWN_SECONDS` | BossFloorPlan | 60 / 38 | Dynamite (the resource that ENDS the fight) returns slower than wax (which only buys time) |
| `EnemyVariantRules` moss stats | EnemyVariantRules | health ×1.35, speed ×0.8, fireDamage ×0.75 | Moss dressing: tankier, slower, more fire-resistant |
| `EnemyVariantRules` ice stats | EnemyVariantRules | health ×0.7, speed ×1.25, fireDamage ×1.6 | Ice dressing: fragile, faster, burns much easier |
| `EnemyVariantRules` elder stats | EnemyVariantRules | health ×2.2, speed ×0.9, scale ×1.18 | ~1-in-12 roll; a silhouette change meant to be clocked across a room |

## What does a Moss tripwire cost you? — the Knotwalker's trap

The whole encounter is about TIME, not damage — every number below reflects that. All values live in
`Config/Tripwire`; the body that lays them (the Knotwalker) only decides how many and where
(`Config/Threats.Knotwalker.trapline`).

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `geometry.heightStuds` | Tripwire | 0.21 | Strand height — "a couple of inches," deliberately under a tenth of a stud so it reads as something you could have stepped over | higher = easier to miss |
| `trip.minStunSeconds` / `maxStunSeconds` | Tripwire | 1 / 3 | Stun band by speed at impact — a walker loses a moment, a full sprint loses the whole window | higher |
| `trip.fullStunSpeed` | Tripwire | 16 (= `Movement.runSpeed`) | Speed that earns the maximum stun | lower |
| `trip.minimumTripSpeed` | Tripwire | 4 (half of `Movement.walkSpeed`) | Below this the wire is stepped over, not tripped on — edging through a suspect doorway is never punished | higher |
| `trip.hopClearanceStuds` | Tripwire | 1.1 | A hop clears the wire entirely | lower |
| `trip.waxDamage` | Tripwire | 0.02 | Almost nothing — the cost is the seconds spent down, not the wax | higher |
| `trip.getUpGraceSeconds` | Tripwire | 1.5 | Immunity right after getting up, covering standing inside a doorway you were just tripped in | shorter |
| `burn.seconds` / `radiusStuds` | Tripwire | 1.5 / 7 | Qualifying light (max brightness or Flare) held this long clears it — the same key as a vine curtain, far cheaper | longer / smaller |
| `armedSeconds` | Tripwire | 150 | An untouched wire expires so an abandoned floor doesn't stay strung forever | shorter |
| `Knotwalker.trapline.maximumArmed` | Threats | 2 | Never more than two wires live on a floor at once |
| `Knotwalker.trapline.layingSeconds` / `layingCooldownSeconds` | Threats | 2.4 s / 14 s | How long it stands exposed laying a wire (the one free tell), and how often it may lay another |
| `Knotwalker.trapline.playerClearanceStuds` | Threats | 34 | Will not string a wire in a doorway somebody is actively approaching |
| `Knotwalker.trapline.responseRadiusStuds` | Threats | 90 | It answers its OWN wire from anywhere on its floor once caught |
| `Knotwalker.trapline.waxDamagePerHit` / `attackIntervalSeconds` | Threats | 0.05 / 0.8 | Four blows across the full 3-second stun band if it reaches a downed player — under half a Longarm graze in total |

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

## Whose candle was this? — the dead candle

Every value lives in `Config/DeadCandle`. The encounter owns no stat of its own: its danger is the
ordinary `VoidFly` row and its reward is ordinary `Config/Loot` rolls, arranged so the reward sits
inside three overlapping territories.

| Value | Default | Feel question |
|---|---:|---|
| `minGlobalDepth` | 10 | How deep before somebody else's failed run starts turning up? |
| `chancePerEligibleFloor` | 0.3 | How rare is it once it can appear? The roll is consumed whether or not a room takes it, so whether a floor *has* one never shifts the rest of that floor's seeded generation |
| `lootCount` / `flyCount` | 3 / 3 | How big is the haul, and how many answers does taking it cost? Both are additional to the floor's own budgets — a rare encounter must not pay for itself with a difficulty refund elsewhere |
| `layout.lootRingRadius` / `flyRingRadius` | 4.2 / 7 studs | How spread the pickups are, and how far out the creatures anchor. The fly ring is always the wider one, so every approach crosses a territory |
| `layout.flyRingOffsetDegrees` | 60° | Rotation between the two rings, so no pickup starts directly beneath a fly |
| `layout.corpseClearance` | 6 studs | Ground kept clear of dressing around the body, and the flat pad it lies on so the spilled wax reads as a pool |
| `body.*` | 2.2 × 0.85 studs, 72° lean, cold grey-white wax | The prop itself. It **emits no light of any kind** — the silhouette of a candle with the light taken out is the whole image |

## When does the stone wake? — Stone Warden

All encounter-selection and runtime pacing values live in `Config/StoneWarden`.

| Value | Default | Feel question |
|---|---:|---|
| `minGlobalDepth` | 4 | How deep before the encounter can exist? |
| `spawnChancePerEligibleFloor` | 0.45 | How rare is its optional weathered chamber? |
| `roomCeilingHeight` | 28 | How tall is the inspectable encounter chamber? |
| `layout.wallSetback` | 5 studs | How far in from the cell boundary the dormant body sits. The encounter is laid out against one **doorless wall** of the den, chosen by the planner once the room's doorways are final: the Warden sleeps in that wall as an outcrop, not as a heap in the middle of the floor. Raising this pulls the body off the wall and back into the room, which is exactly the read this replaced |
| `layout.waxStandoff` | 9 studs | How far the three-piece wax tray stands out from room centre toward the Warden's wall, visibly in front of the dormant body |
| `layout.counterLateral` / `layout.counterStandoff` | 14 / 6 studs | Where the guaranteed Heavy Crown hangs so the awakened Warden can still be led under it |
| `layout.collapseDripstones` | 3 placements: Needle / Fork / Needle | Extra inspectable formations committed by the third pickup. The Heavy Crown counter is deliberately separate and remains dormant |
| `counterDripstoneVariantId` | `Hammer` | Which unstable-dripstone variant that counter uses |
| `waxPieceOffsets` / `waxPieceSize` | 3 offsets / `(0.9,0.62,0.72)` | Three distinct non-glowing pieces on the tray, each with its own prompt |
| `pickupRange` / `pickupHoldSeconds` | 7 studs / 0.2 s | Server-validated reach and commitment per piece. The third collection wakes the Warden |
| `collapseTriggerRadius` / `collapsePresentationRadius` | 1.5 / 48 studs | Exact matching reach for the three planned formations and the distance at which clients feel the wake tremor |
| `collapseShakeSeconds/Frequency/Studs/Degrees` | 0.9 / 13 / 0.13 / 1.4° | Immediate chamber shake on the third pickup; cosmetic only |
| `emergence.wallDepth` / `emergence.rise` | 4.5 / 2.5 studs | How far back inside the stone the body starts and how far it stands up over `emergenceSeconds`. It steps **forward out of its wall** rather than rising out of the floor, and stays anchored until it is clear of the rock |
| `encounterClearance` | 9 | How much cave dressing is kept away from each encounter pad? |
| `fixtureFootprint` / `traySize` | 5 / `(4.8,0.5,3.8)` | Built floor required by the guarded wax and the low family-material tray beneath it |
| `walkSpeed` / `pathRefreshSeconds` | 9.2 / 0.3 s | Pursuit speed is 15% above the prior 8; responsiveness is unchanged |
| `emergenceSeconds` / `stationaryPauseSeconds` | 4 / 3 s | How much warning does the wake give, and how long the golem holds still when the player it is chasing stops. The stop-listening pause is ONE-SHOT per stop: it is spent after `stationaryPauseSeconds` and the pursuit resumes whether or not the player is still standing there, re-arming only when they move again. Standing still is a beat you buy, never a way to switch the Warden off |
| `motion.gaitCycleSeconds/gaitReferenceSpeed` | 1.18 s / 9.2 studs/s | Server-rendered Motor6D stomp cadence calibrated to the authoritative root speed; stopping blends the limbs back to their rest pose instead of leaving a foot suspended |
| `motion.bodyBobStuds/hipRollDegrees/legSwingDegrees/kneeLiftDegrees/armSwingDegrees` | .22 / 4.5° / 11° / 8° / 15° | Weight transfer across pelvis, legs, delayed arms, and head while the invisible gameplay root continues to own movement |
| `motion.emergenceUnsealFraction/emergenceCrouchStuds/emergenceShoulderDegrees` | .72 / 1.05 / 34° | Shoulders peel out of the wall before the existing four-second authoritative emergence finishes |
| `motion.stunSettleSeconds/stunSagStuds/stunPitchDegrees/resumeGatherSeconds` | .42 s / 1.1 / 13° / .8 s | Rubble sag and the brief gather drawn inside the existing dripstone stun window; these values never lengthen or shorten the stun |
| `motion.nearBrace*` | 9 studs / .2 s / 8° / .24 studs / 18° | Proximity-weighted planted brace. It changes silhouette only and never delays movement or contact |
| `motion.contactFollowThroughSeconds/contactPeakFraction/contact*` | .7 s / .3 / .82 gait suppression / .5 studs / 15° / 30° | Post-contact mass continuing through a server-confirmed kill. There is no pre-contact Warden attack clock: touch death remains the first server side effect |

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
| `placement.restArmReach` | AshamedLurker | 3.5 studs | VISUAL ONLY — how far the arm droops while dormant. The lunge approaches the gameplay reach but is clamped by `motion.triggered.safeLaneMarginStuds` before it can imply the open half is unsafe | — |
| `placement.minSafeLaneWidth` | AshamedLurker | 8.4 studs | Clear floor the open half must keep: three candles abreast (3 × 2 × `Character.bodyRadius`), measured against the lunge. THE guarantee that an occupied arch is still a route | lower |
| `placement.edgeInset` | AshamedLurker | 0.7 studs | How far the body sits in from the springer | — |
| `face.*` | AshamedLurker | 0.52 height / 1.35 inset / 0 forward | Where the face sits, and so what a player must actually look at. Kept in the plane of the opening so it reads from both approaches | — |
| `trigger.minSpeedFraction/minAbsoluteSpeed` | AshamedLurker | 0.7 of run speed / 10 studs/s | Measured speed that counts as running through — 11.2 studs/s, clearly above Cup-slowed movement (8) and below the 16-stud default run, so the trapped half trips during ordinary movement | lower |
| `trigger.laneDepth/laneCenterY/laneHeight` | AshamedLurker | 4.5 / 2.5 / 10 studs | Trip volume through and above the opening; generous vertically because Terrain rolls up into the arch and a candle's tracked position is its base | larger |
| `trigger.grabLateralPadding/grabDepthPadding` | AshamedLurker | 0.8 / 2.5 studs | How much larger the impact-frame volume is than the trip lane. Depth is padded hard: a default runner covers ~2 studs during the wind-up, so escaping is meant to be LATERAL, not simply being fast | larger |
| `trigger.sampleHz` | AshamedLurker | 20 | Trip-detection rate. Too low and a default runner is sampled past the lane before it fires | higher |
| `trigger.grabCheckDelaySeconds` | AshamedLurker | 0.12 s | The entire reaction window: leave the volume before this and the grab misses | shorter |
| `trigger.waxLossFraction` | AshamedLurker | 0.2 of max wax | Wax a connecting grab takes; level with a Needle dripstone | higher |
| `trigger.recoverySeconds/rearmSeconds` | AshamedLurker | 0.9 / 0.5 s | Full visual recovery after the unchanged 0.12-second grab check, and the minimum gap between lunges so one pass cannot be hit twice. Server `Triggered` lasts grab delay + recovery | shorter |
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
| `motion.dormant.*` | AshamedLurker | layered breath, head twitch, shoulder drift, finger curl | Full-strength idle channels retained at both ends of every state transition, so a lunge or shame pose never snaps to a dead neutral rig | cosmetic |
| `motion.triggered.*LeadFraction/*RecoveryStartFraction` | AshamedLurker | body 0 → arm .22 → head .5; recovery body .04 → head .12 → arm .2 | Ordered body/arm/head commitment to the authoritative grab instant, followed by a held-hand, staggered settle rather than a reversed wind-up | cosmetic |
| `motion.triggered.safeLaneMarginStuds` | AshamedLurker | 1 stud | Visible margin retained inside the trapped half after all local lunge translation; pure rules test every allowed doorway width | larger = visually safer |
| `motion.ashamed.*` | AshamedLurker | fissure dart → two-hand face cover → head turn → retreat/fade | Articulation and normalized phase windows for the non-combat clear reaction. The socket stays behind while the body withdraws | cosmetic |

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
| `emitters.SeamExplosion` | Sound | 2.6 / 150 / 9 s | An Explosive Seam going up. The loudest row in the file, and the only one whose reach is a whole floor. **Not how the blast actually summons anything** — that is an explicit alarm, because this field can only ever move something with ears. What this row adds is the aftermath: the blast site stays noisy long after the alarm lapses | higher |
| `emitters.Sprint` | Sound | 0.3 / 30 / 1.6 s | One default-run footfall burst; must stay under every threshold alone | higher |
| `emitters.Landing` | Sound | 0.5 / 30 / 1.5 s | A candle's weight hitting the rock, emitted once per touchdown by `server/DripTrailService`. The only movement noise loud enough to matter alone, and it matters to exactly one creature: it clears the VoidFly's 0.42 and stays under the Cave Listener's threshold at every depth. **Walking still emits nothing** — raising this past a fumbled swing (0.95) would make jumping the loudest thing a player does | higher |
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

**Every landed swing pays.** Grams go into the bag at the moment the strike is scored, not when the
seam breaks. A **Good** strike pays `goodFractionOfPerfect` of the row's rate (floored); a **Miss**
pays **nothing** while still chipping the rock and still being the loudest thing mining does.

**What accuracy is actually worth.** The same fraction scales the grams *and* the progress, so Good
and Perfect pay identically per unit of rock removed — a seam worked entirely in Good strikes is worth
the same 150 g, it just takes longer. Only a Miss removes rock without releasing wax:

| Miner | Seam yield | Swings taken |
|---|---|---|
| all Perfect | 150 g (100%) | 3.00 |
| 60P / 30G / 10M | 145 g (96%) | 3.62 |
| 40P / 40G / 20M | 138 g (92%) | 4.14 |
| 20P / 40G / 40M | 119 g (79%) | 5.14 |
| all Miss | **0 g** | 10.0 |

So accuracy is mostly **time and noise**, and money only at the margin — deliberately, so a new player
is priced out of mining *quietly*, not out of the economy. The Explosive Seam is the one exception:
its fuse counts strikes rather than progress, so a fumble there buys nothing and spends the rock
anyway.

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `rows[*].cleanStrikes / gramsPerStrike / maxPaidMiners / minBurnFraction` | Mining | Standard 3/50/1/0; Twin 6/**25**/2/0; Deep 9/50/1/0; Dim 4/56/1/0 (max .35); Bright 3/100/1/.9; Explosive ∞/**40**/1/0 | Row duration, **per-swing** yield in grams, co-op payout ceiling, and burn gate. A co-op row must satisfy `gramsPerStrike × maxPaidMiners ≤ 50` or a pair out-earns a solo miner per swing of real work | row-specific |
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
| `explosive.primeChanceBase` / `.primeChanceRampStrikes` / `.primeChancePerStrike` | Mining | 0.03 / 3 / 0.21 | The Explosive Seam's odds of going off on swing *N*: flat for three swings, then climbing to certainty. See below | higher = shorter fuse on the whole row |
| `explosive.fuseSeconds` | Mining | 3 | Crackle → blast. Long enough to sprint clear from a standing start, short enough to buy nothing else | lower |
| `explosive.blastRadius` / `.blastWaxCost` | Mining | 22 / 0.32 | Who the blast touches, and what a direct hit costs a candle (≈¼ of a full one, falling linearly to nothing at the edge). Absorbed by a Candle Sleeve like any other environmental impact | higher |
| `explosive.alertRadius` / `.alertSeconds` | Mining | 260 / 14 | **How far the blast summons threats, and for how long.** Every family answers, deaf rows included — the one event in the game that ignores the light/sound split | higher |
| `placement.minDepth` | Mining | 1 | First eligible floor | higher |
| `placement.depositCounts` | Mining | E = 0.65 / 1.10 / 1.40 / 2.35 / 3.15 by depth band | **How many seams a floor carries**, weighted by global depth (0–1 on floors 1–3, rising to 2–3 on floors 7–9 and 3–4 past floor 10). Floors 1–6 are unchanged; the two deep bands gain 27% and 29% | steeper = pushes deeper |
| `placement.maxPerFloor` | Mining | 4 | Absolute clamp on the weights above, not a balance lever. At most one deposit per room, so several seams read as several detours rather than a route | — |
| `placement.footprint` / `standingClearance` | Mining | 6 / 7 | Seam plus the dry ground needed to work it | — |
| `placement.minHazardSeparation` | Mining | 9 | Clearance from pools and unstable formations | higher |
| `placement.minThreatSeparation` | Mining | 14 | Clearance from a threat's spawn point | higher |
| `visual.surfaceEmbed` / `.surfaceEmbedJitter` | Mining | 0.65 / 0.10 | Extra burial after the foundation reach and pedestal are sunk; shoulders the broad core into the Terrain instead of leaving it perched | — |
| `visual.surfaceProbeRadius` | Mining | 5.5 | Radius used to validate that the deposit footprint remains on one continuous Terrain patch; the centre sample remains the seat height | higher = more conservative placement |
| `visual.shape.pedestalMin` / `.pedestalMax` | Mining | 0.7 / 1.5 | Depth of supporting foundation buried beneath the seam-bearing mass. It varies the ground-contact geology without raising the core | — |
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
| `Audio.cues.MineStrikeImpact` | Audio | volume 0.72 | The spatial crunch layer — timed to visible contact and played under every confirmed strike | lower |
| `geometry.placementProbe.upStuds` / `.downStuds` / `.horizontalMarginStuds` | Floors | 10 / 24 / 4 | Terrain-only vertical search plus the voxel-sized open-air margin that pulls loot, seams, and the Warden wax fixture clear of shaped side walls | larger horizontal margin = safer, more central placements and fewer peripheral pockets |
| `geometry.placementProbe.maxPeripheralDeltaStuds` | Floors | 3.5 | Highest nearby floor change accepted as the same footprint; taller hits are walls/shelves and ignored | higher = more risk of seating on a wall lip |
| `geometry.placementProbe.fallbackFractions` / `.fallbackRingRadiusStuds` / `.fallbackRingSamples` | Floors | .75/.5/.25 / 4 / 8 | Deterministic inward walk and separated navigation-hub slots when the preferred centre has no built floor | smaller ring = more central repairs |
| `geometry.placementProbe.emergencyLiftStuds` | Floors | 6 | Above-centre lift used only if the guaranteed hub itself has no Terrain; always exposed in `floor_spawn_audit` | — |

Placement invariants (enforced in `Logic/FloorPlanner`, tested in `FloorPlannerTests`): never the
entry, Basin, or Brazier room; never on the guaranteed entry → Brazier → Basin route; never behind a
vine curtain; never blocking a doorway lane; always a dry interaction footprint. A failed wall
pocket retries the same off-route room's guaranteed navigation hub through every identical safety
check. **Only a floor that cannot satisfy any safe wall or hub position drops the count.**

## What is a run worth? — the extraction economy (Phase 8, gram pass)

**Raw Wax is the only income in the game.** Leftover candle wax pays nothing; what you get paid for is
what you dug out of the rock and walked back up.

Raw Wax is a **mass in whole grams**. Mining pays **per landed swing**, not per broken seam, and a
swing is a fraction of a seam — which in the old "units" vocabulary would have been *0.67 units*, i.e.
exactly the fractional currency this economy forbids. The unit got smaller instead (one old unit =
100 g) and every amount stayed an integer. Per-gram values are authored in **permille of one
currency**; `Logic/ExtractionValue` sums the exact integer products `grams × permille` across a whole
bag and divides **once**, so per-gram pricing bought no extra rounding step.

A gram is priced by the **floor it was mined out of**, never by where it was cashed in. That single
decision is what makes "farm the safe floors, then run to the bottom" worth exactly what running
to the bottom alone is worth.

| Value | File | Default | Controls | Harder / deeper → |
|---|---|---|---|---|
| `valuePerGramPermilleByDepth` | Extraction | 90,99,126,158,198,239,297,360,446,554,693,873,1107,1404,1800 | Thousandths of one currency per gram, by origin depth | steeper = pushes deeper |
| `extensionGrowthPermille` | Extraction | 1280 | Compounding past the authored table (1.28×/floor) | higher |
| `maxValuePerGramPermille` | Extraction | 45000 | Ceiling, reached ~floor 29 | — |
| `maxCargoGrams` | Extraction | 100000 | Overflow guard, not a balance lever — hitting it is a bug signal | — |
| `gramsPerKilogram` | Extraction | 1000 | Where a readout switches from grams to kg. Presentation only | — |
| `partyBonusPermille` | Extraction | 1500 | "Everyone came back" bonus, paid retroactively once the last member is out | lower |
| `partyBonusMinimumMembers` | Extraction | 2 | Solo runs never earn it | — |
| `deathDropPermille` | Extraction | 500 | Share of a dead player's bag that lands on their remains; the rest shatters | lower |
| `disconnectGraceSeconds` | Extraction | 120 | How long a dropped bag stays locked to its owner before the party may take it | lower |
| `maxSinglePayout` | Extraction | 1000000 | Absolute payout ceiling; nothing legitimate approaches it | — |

### The two reductions in the gram pass, stated separately

They are separate decisions and either can be reverted without the other.

1. **The general rate is down 10%.** Neutral conversion of the old per-unit table would have been
   `oldValue × 10`. Every entry is 0.9 of that.
2. **Depth compounds more slowly.** Old multipliers 1.0 / 1.1 / 1.4 / 1.8 / 2.3 / 2.8 / 3.5 / 4.3 /
   5.4 / 6.8 / 8.7 / 11.2 / 14.6 / 19.2 / **25.4**; now 1.0 / 1.1 / 1.4 / 1.75 / 2.2 / 2.65 / 3.3 /
   4.0 / 4.95 / 6.15 / 7.7 / 9.7 / 12.3 / 15.6 / **20.0**. Untouched through floor 3, a couple of
   percent off in the middle, 21% off at floor 15.

A **third** reduction rides alongside them and lives in `Config/Mining`: a Standard seam worked
perfectly now yields **150 g** against the old lump sum's 200 g-equivalent, and **a fumble pays
nothing at all**. Combined, an average five-floor Shallows run pays **~96** where it used to pay
**~149** (−36%), and a floor-15 gram is worth 45% less than it was.

### Does it actually scale? — the progression audit

Modelled from the shipped configs against a competent miner (60P/30G/10M) with no seam rows bought.
Run length is `~75 s` traversal per floor + `~1.14 s` per swing + `~14 s` detour per seam.

| Depth | Shallows | Descent (−350) | Deep (−1000) | Run length |
|---|---|---|---|---|
| 3 | +29 (7/min) | −278 | −870 | 4.3 min |
| 5 | +96 (13/min) | −110 | −568 | 7.6 min |
| 6 | +145 (16/min) | +12 (1/min) | −348 | 9.3 min |
| 8 | +373 (28/min) | +582 (44/min) | +678 (51/min) | 13.2 min |
| 10 | +785 (45/min) | +1,612 (93/min) | +2,532 (146/min) | 17.4 min |
| 12 | +1,512 (69/min) | +3,430 (157/min) | +5,804 (266/min) | 21.8 min |

Time to afford, from that table:

| Goal | Shallows f5 | Descent f8 | Deep f10 |
|---|---|---|---|
| The Pay Table (250) | 2.6 runs · 0.3 h | 0.4 runs | — |
| The Contract Board (800) | 8.3 runs · 1.1 h | 1.4 runs · 0.3 h | — |
| Descent admission (350) | 3.6 runs · 0.5 h | — | — |
| The Hard Contracts (5,000) | 52 runs · 6.6 h | 8.6 runs · 1.9 h | 2.0 runs · 0.6 h |
| **Whole tree (29,750)** | 310 runs · 39 h | 51 runs · **11.2 h** | 11.7 runs · **3.4 h** |
| The Deep, permanent (15,000) | 156 runs · 20 h | 26 runs · 5.7 h | 5.9 runs · 1.7 h |

**Verdict: it scales.** First purchase inside ~20 minutes, Descent access inside the first hour, and
the full track is a 10–20 hour goal that shortens sharply as the player gets deeper — which is the
descent pressure doing its job rather than a flat grind. Nothing runs away: `maxSinglePayout` binds
around floor 35, and a flawless 30-floor run with every row unlocked produces 17.6 kg against the
100 kg carry guard, so that cap stays a bug signal and never a balance lever.

### Caves charge admission

Permanent unlocks were replaced by a per-descent fee taken from **every** party member. The Shallows
is free forever. Owning a cave outright makes its fee zero and is priced at fifteen descents.

| Cave | `entryFee` | `payoutPermille` | `permanentUnlockPrice` | Break-even |
|---|---|---|---|---|
| The Shallows | 0 | 1000 | — (never for sale) | always free |
| The Descent | 350 | 2500 | 5250 | ~floor 6; real profit past floor 8 |
| The Deep | 1000 | 4500 | 15000 | ~floor 7; an average 5-floor run **loses money** |

Measured, from the real config: an average 5-floor free run pays **~96**, so one Descent admission is
**~3.6 free runs** (it was ~2.3). Cumulative base value by depth is now
**8 / 17 / 29 / 58 / 96 / 145 / 265 / 373 / 565 / 785** for a competent miner.

**THE FEES ARE DELIBERATELY UNTOUCHED.** The brief was to reduce what wax is worth, not to re-price
the caves, so the pacing change is left visible rather than absorbed: admission costs more runs and
the Descent's break-even moved from floor 5 to floor 6. `ExtractionValueTests` asserts the new
relationship directly, so if the grind reads as too long in playtests, `entryFee` in
`Config/CaveFamilies` is the one dial to move and that test is where the change will announce itself.
Full derivation and the contract break-even table are in `LAMP-NETWORK.md` §6.

### Rules that are decisions rather than numbers

Written out in `Config/Extraction`, enforced in `server/ExtractionService` and `Logic/CargoRules`:
cargo is **individual**; a **snuff never drops it** and a **revived player keeps all of it**; a
**terminal death drops half and shatters half** onto the candle remains; a **disconnect drops the
whole bag owner-locked** for the grace window and then unlocks it for the party. There is **no
transfer verb** — the only path between two players' bags is a pile in the world with a single claim,
which is what makes duplication structurally impossible rather than merely checked for.

### The Explosive Seam

A seam of wax under gas pressure. **It has no end**: every other row is a fixed amount of wax you
either take or do not, and this one is an open tap that pays 55 g a swing for as long as your nerve
lasts. `neverDepletes` makes that literal — progress fills and keeps filling, and no number of strikes
will ever break it.

What ends it is the rock deciding to. Every strike rolls against an escalating chance to **prime**;
once primed it crackles for three seconds and detonates, and the detonation **summons every threat on
the floor** to the spot (`ThreatService.alertAll` → `ThreatBrain.thinkAlarm`). The blast itself is a
bill rather than a death: ~¼ of a full candle at point-blank, falling to nothing at 22 studs. What
kills a greedy player is what arrives afterwards.

`p(N) = clamp(base + perStrike × max(0, N − ramp), 0, 1)` → 3%, 3%, 3%, 24%, 45%, 66%, 87%, certain.
Multiplying the survivals out gives the distribution the row is authored against — the chance the seam
primes on exactly swing *N*:

| swings 1–3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|
| 8.7% combined | 21.9% | 31.2% | 25.2% | 11.3% | 1.7% |

**91% between the fourth and eighth swing, mean 5.05.** The three flat opening swings are the design:
they make starting a seam reasonable and the fourth swing a real decision. The sickly green-gold seam
identifies the row before the first strike; landed strikes add no special hiss. The base is never zero, so
no amount of counting buys a safe extra strike. `MiningRulesTests` asserts this table directly.

**40 g/swing is under the Standard rate, and that is what makes it a gamble rather than a freebie.**
Cumulative haul against cumulative blast risk:

| stop after | 1 | 2 | 3 | 4 | 5 | 6 | 8 |
|---|---|---|---|---|---|---|---|
| grams | 40 | 79 | 116 | **153** | 181 | 196 | 202 |
| blast risk so far | 3.0% | 5.9% | 8.7% | 30.6% | 61.9% | 87.0% | 100% |

Four swings — 153 g — is where the seam finally out-earns an ordinary 150 g one, and swing 4 is
*exactly* where the odds jump from 3% to 24%. Every gram of profit sits on the far side of the ramp,
so "chip it three times and walk" is strictly worse than mining a normal seam. Expected haul if you
ride it out: **202 g (1.35× a Standard seam)**; hard ceiling at eight swings 320 g (2.13×), which
stays under the Bright Seam's rate so a free row never devalues a bought one.

An earlier draft paid 55 g and was cut: at that rate three safe swings returned 160 g and beat a
Standard seam outright at 8.7% risk, which is a free lunch wearing a fuse.

**It is not sold by the Lamp Network.** Every other row is a purchase that puts more wax in the
ground; this one is a decision the cave puts in front of you, and a player who has bought nothing
should still have to make it. Held off floors 1–2 so meeting one is never a new player's introduction
to mining. Its sickly green-gold seam colour identifies it before it is touched, and the primed crackle
still gives the full escape window before it can hurt anybody.

### The mining shard

A **Perfect** strike shatters wax onto the miner (`Mining.deposit.waxPerPerfectStrike`, **0.007**).
Only Perfect — a fumble sprays nothing.

**This is the economy's most sensitive lever, and it is the one number that can make the game
unwinnable-proof.** If a floor returns more Living Wax than it costs, depth becomes free; depth being
free matters more than it sounds, because the currency curve compounds to a 45× ceiling and the payout
cap does not bind until floor ~35. A self-sustaining candle is not just a blunted survival mechanic,
it is an unbounded amount of money.

It was cut **0.025 → 0.012** when floors gained multiple seams, and **0.012 → 0.007** in the gram
pass. The reason 0.012 leaked is that the shard is paid per **swing** while a floor is paid for per
**second**, so long rows quietly out-earn short ones. A deepest-band floor with every seam row
unlocked offers ~14.8 Perfect strikes; at 0.012 that returned **0.177** wax against 0.038 spent
standing at the rocks and 0.070 crossing the floor — **+0.069 per floor**, i.e. an expert was
wax-positive from floor 8 down.

Break-even for that worst case is **0.00733**. Net wax per floor at the deepest band, at 0.007:

| | perfect | good | average |
|---|---|---|---|
| every seam row unlocked | −0.005 | −0.037 | −0.056 |
| no seam rows bought | −0.031 | −0.055 | −0.069 |

Which is the authored margin exactly: a perfectly mined floor very nearly pays for itself, every other
floor is a real cost. **Raising this past 0.0073 re-opens the loop**, and anything that adds swings to
a floor — a new row, a longer row, a denser deposit curve — lowers that ceiling and must be re-derived.

## What does an explosion cost me? — dynamite (`Config/Dynamite`)

The one thing in the game that can kill, and the one place DESIGN's no-combat pillar is deliberately
relaxed (DESIGN §6a, owner decision). **Four of the values below are design surface rather than
tuning**, because they are what bounds that exception: raise any of them far enough and dynamite stops
being a rare emergency and starts being a combat system.

| Value | Config | Current | What it decides |
|---|---|---|---|
| `supply.stickMinGap` / `stickMaxGap` | Dynamite | **1 / 3** | **Design surface.** How often the cave hands over a stick, as a real schedule walked from the run seed rather than a per-floor roll. A player must be able to expect one soon without knowing which floor |
| `supply.stickFirstDepth` | Dynamite | **2** | The schedule STARTS here rather than rolling for it, so every run meets its first stick at the same early, survivable place. Floor 1 stays clean — it is where the dial is taught |
| `supply.crateMinGap` / `crateMaxGap` | Dynamite | **10 / 20** | A crate is a run event, not a resupply. Most expeditions never see one |
| `supply.crateCharges` | Dynamite | **3** | Sticks per crate |
| `supply.maxCarried` | Dynamite | **4** | **Design surface.** The cap that stops a long run becoming an armoury. Low enough that finding a crate while nearly full genuinely wastes sticks, which is the pressure that makes a player spend the one they are holding |
| `fuse.thrownSeconds` | Dynamite | **3** | Matched to the Explosive Seam's fuse on purpose: long enough to get out of your own blast, far too short to get out of the room |
| `fuse.socketedSeconds` | Dynamite | **4.5** | Longer, because placing at a door also lights it and begins the walk away immediately |
| `throw.range` | Dynamite | **30** | The distance a throw covers at the IDEAL 45-degree launch, and a ceiling rather than a fixed distance. `DynamiteRules.launchSpeed` derives the release speed as `sqrt(range × gravity)`, so every other angle resolves shorter: a flat throw carries roughly two-thirds, and one aimed at your feet lands there. Raising this lengthens every angle, not only the ideal one |
| `throw.gravity` | Dynamite | **196.2** | Roblox's own default, authored here rather than read from `Workspace.Gravity` so the arc is a pure function of config — the same simulation runs in a cold test as on a live server |
| `throw.launchHeight` | Dynamite | **1.5** | Where the stick leaves the body, above the candle's base. Roughly hand height, so a flat throw clears the ground it was launched from |
| `throw.simulationSteps` / `maxFlightSeconds` | Dynamite | **48 / 2.4** | How finely the server walks the arc hunting for what the stick hits. The seconds are a safety ceiling, not an expected flight: an ideal 45-degree throw is airborne for well under one |
| `throw.animationSeconds` | Dynamite | **0.38** | The visible tumble, which replays the SAME parabola the solver walked rather than a decorative lob over the top of it. Scaled by how far the stick actually travelled |
| `door.socketCatchRadius` | Dynamite | **4.5** | How close a throw's flight path must pass to a charge pocket to seat in it and arm — the "stick a bomb on the door" catch. Tested along the ARC, not at the landing point, because a stick thrown at a vertical face never comes to rest on it. Deliberately tighter than `thrownBreakRadius` so the marker keeps meaning "hit HERE" while a near miss still breaks the door |
| `blast.radius` | Dynamite | **26** | Smaller than a seam going up |
| `blast.playerWaxCost` | Dynamite | **0.62** | **Design surface.** At point blank, falling off linearly to nothing at the edge. The largest single discrete hit in the game — and deliberately survivable from full (max wax is 1.30), because what should end a greedy run is what arrives afterwards, not the explosion |
| `blast.shakeRadius` / `floorShakeStrength` | Dynamite | **70 / 0.18** | Camera concussion falls off from full strength inside 70 studs, but never below 18% for anyone on the same floor. Other depths receive neither the floor-wide boom nor its shake |
| `blast.alertRadius` / `alertSeconds` | Dynamite | **150 / 12** | **Design surface.** The floor-wide summons, same mechanism as a detonating seam. This is the bill for the loud answer, and it is why dynamite never becomes the default one |
| `threat.default.hitPoints` | Dynamite | **1** | Blast damage is 1.0 at the centre falling to 0 at the edge, so every `hitPoints` in the game reads as **"sticks at point blank"**. A row with no `blast` block takes this — killable rather than accidentally immune |
| `threat.default.staggerSeconds` | Dynamite | **6** | What a SURVIVOR gets: driven off exactly as a Flare drives one off, so a near miss is still a defensive result rather than a wasted stick |
| `threat.wardenHitPoints` | Dynamite | **3** | More than `maxCarried`, which is what keeps DESIGN §9's promise that the Warden has exactly one real counter. A stick buys a stun and a limp, never a kill in practice |
| `threat.wardenStunSeconds` / `wardenSlowMultiplier` / `wardenSlowSeconds` | Dynamite | **2.4 / 0.55 / 8** | Routed through the ordinary crown stun, so the rubble cue and disarmed kill contact behave identically. A blast is a smaller crown, not a new state |
| `door.thrownBreakRadius` | Dynamite | **9** | A thrown stick landing this close to a blast door breaks it too. Generous on purpose: the socket is the clean way, and a player who improvised should be rewarded for the idea rather than punished for their aim |

**Per-creature lethality** lives on the threat rows themselves (`Config/Threats.definitions.*.blast`):
Cave Moth **0.6**, VoidFly **0.45**, Dark Crawler **1.0** (the reference body the scale is written
against), Knotwalker **1.3**, Calver **1.5**, Cave Listener **1.7**. Damage accumulates on a body and
never heals, so two half-strength blasts finish what one could not.

### Blast vaults

| Value | Config | Current | What it decides |
|---|---|---|---|
| `vault.minDepth` | Dynamite | **3** | Held off the tutorial band, like the Explosive Seam |
| `vault.chancePerFloor` | Dynamite | **0.40** | Whether an eligible floor carries one at all |
| `vault.secondVaultChance` | Dynamite | **0.28** | Rolled only if the first landed, so two is genuinely uncommon rather than half of all vault floors |
| `vault.depositsMin` / `depositsMax` | Dynamite | **1 / 3** | Guaranteed ore, rolled per vault and placed OUTSIDE the floor's own seam target — a vault is extra content, never a seam moved out of a room a player could reach for free |
| `vault.loot` | Dynamite | **1** | One ordinary pickup, so opening one reads as finding a cache |
| `vault.ceilingHeight` | Dynamite | **19** | Low and close. A vault reads as a pocket somebody sealed, not as another cavern |
| `visual.doorArchRiseFraction` | Dynamite | **0.6** | Matched to the vine curtain's. `buildWall` cuts an ARCH, so a door built to the doorway's own height would leave a crescent gap along the top |

## How brutal is the Basin? — the sacrifice ritual

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `minimumGrant` / `maximumGrant` | Basin | 0.20 / 0.35 | Final payment band at every depth, including the next-price penalty | lower |
| `offersPerVisit` | Basin | 4 | Fully explained choices shown per visit | lower |
| `pool[].waxGranted` | Basin | 0.20–0.35 | Depth-independent payment per sacrifice before the optional penalty clamp | lower |
| `pool[].weight` | Basin | 1 progressive / 0.35 next-price | Offer frequency; Basin rows never remove an ability or tool | — |
| `effects.maxBurnRateCapMultiplier` | Basin | 0.86 per stage | Progressive maximum-brightness reduction | lower |
| `effects.moveSpeedMultiplier` / `maxWaxMultiplier` / `waxDrainMultiplier` | Basin | 0.90 / 0.90 / 1.10 per stage | Progressive body and consumption degradation | lower / lower / higher |
| `effects.flareDurationMultiplier` / `decoyDurationMultiplier` | Basin | 0.82 / 0.82 per stage | Tool-specific duration degradation without removing the tool | lower |
| `effects.relightCostMultiplier` | Basin | 1.30 per stage | Wax cost of relighting a teammate | higher |
| `effects.peripheralDarknessOpacity` | Basin | +0.08 per stage | Permanent darkness added at the screen edges | higher |
| `effects.sightBrightness` / `sightSaturation` | Basin | -0.025 / -0.10 per stage | Progressive permanent local vision grading | lower |
| `basinVision.edgeColor` / `edgeWidthScale` | Feel | (2,2,4) / 0.24 | Shape and color of the peripheral-darkness sacrifice | wider/darker |

## Is it worth going deeper? — the brazier

Phase 8 removed the Living Wax payout. The brazier no longer computes a reward from your candle: it
is the place cargo becomes currency, and the arithmetic lives in `Logic/ExtractionValue` (see the
extraction-economy section above). `depthMultipliers`, `groupBonusPerPlayer` and `rewardPerWaxUnit`
are **gone** — the depth curve is now `Extraction.valuePerGramPermilleByDepth`, and the group bonus became an
"everyone came back" bonus settled once the whole party is out rather than a proximity check here.

| Value | File | Default | Controls | Harder / deeper → |
|---|---|---|---|---|
| `promptRange` | Brazier | 10 | Where the preview/commit appears (studs) | — |
| `positionToleranceStuds` | Brazier | 2 | Server-side slack when re-validating the commit | lower |
| `commitHoldSeconds` | Brazier | 1 | Hold time to end your run | — |
| `previewUpdateSeconds` | Brazier | 0.25 | Preview refresh cadence | — |

The preview at the lantern is **the only place a bag's currency value is shown**. In the cave the HUD
carries a unit count and nothing else, so the decision to turn back is made at the exit with the real
number in front of you rather than continuously recalculated in the dark.

## What do the three floor fixtures look like? — the Cauldron, the Brazier, the Ladder, and the Wall Lamps

Presentation for the per-floor objectives, kept in files deliberately separate from the ones that own
their RULES (`Basin`'s pool, `Brazier`'s payout, the orchestrator's descent). Those are design surface;
these are art direction, and they are retuned by different people for different reasons. What each
fixture is BUILT FROM is per cave family (`CaveFamilies.presentation.fixtureStyle`), not here.

**The extraction fixture reverted from a "Gas Lantern" to a Brazier, and lighting the cave split off
into its own system (`Config/WallLamp`).** Every row below that used to live on `Config/Lantern` —
the floor-wide lamp network, the ignition cascade, the five-second free-look — is retired along with
that fixture. `Config/Lantern` now owns exactly one decorative object: the small work lamp on the
Descent Ladder's headframe.

| Value | File | Default | Controls | Notes |
|---|---|---|---|---|
| `bellyRadius` / `bellyHeight` / `plinthRadius` | Cauldron | 2.2 / 1.9 / 2.9 | The vessel's proportions | Authored against a four-stud candle: the rim sits just under eye height so you look DOWN into it |
| `waxColor` / `waxTransparency` / `waxInset` | Cauldron | amber / 0.06 / 0.55 | The molten surface | The amber is carried over unchanged from the flat disc this replaced; the room is recognised by it |
| `rippleBobStuds` / `rippleBobSpeed` / `rippleTransparencyPulse` | Cauldron | 0.055 / 0.9 / 0.05 | Surface motion, rendered locally | Small on purpose — wax runs like syrup, and faster reads as boiling water |
| `runnelCount` | Cauldron | 5 | Set wax run down the outside | Uses `DripTrail.dripColor`; cooled wax is the same colour in every cave |
| `cairnRadius` | Brazier | 1.5 | The low cairn the bowl sits on | — |
| `coalColor` / `coalLitColor` / `emberColor` | Brazier | 44,41,39 (dead grey) / 96,44,22 / 255,122,44 | Cold coals, lit coals, ember accent | Dead until commit, like every other lightable fixture in the game |
| `flameCoreColor` / `flameTipColor` / `lightColor` | Brazier | 255,218,148 / 255,138,48 / 255,148,66 | The Brazier's own flame and thrown light | Ordinary candle-family warm palette — this fixture no longer claims a separate "gas flame" hue |
| `promptRange` / `positionToleranceStuds` / `commitHoldSeconds` | Brazier | 10 / 2 / 1 | Where the preview/commit appears, server slack, and hold time | See the brazier economy section above |
| `geometry.pillarRadius` / `pillarHeight` | WallLamp | 0.3 / 1.6 | The candle itself | Deliberately FAT — a squat pillar at this proportion reads as a candle from across a room; a taper reads as a stick, same logic as the player's own body |
| `geometry.plateWidth` / `armLength` / `panRadius` | WallLamp | 0.86 / 0.74 / 0.46 | Bracket plate, standoff arm, drip pan | Arm is long enough to read as a bracket from the side, short enough a player cannot walk between candle and wall |
| `geometry.rimRadiusMultiplier` / `dripCount` | WallLamp | 1.12 / 3 | Melted lip and cooled wax runs | Three uneven runs, not a symmetric ring — wax runs where the draught took it |
| `waxColor` / `waxLitColor` | WallLamp | 214,201,172 / 232,214,176 | Cold and lit wax | Family-neutral on purpose: this is the same wax the player is made of |
| `deadWickColor` / `litWickColor` | WallLamp | 38,34,31 / 96,62,38 | Burnt charcoal, then lit brown | Charcoal, not black — a wick that has been lit before |
| `flameCoreColor` / `flameTipColor` / `lightColor` | WallLamp | 255,226,160 / 255,152,62 / 255,164,84 | The lamp's flame | Same candle-orange family as everywhere else — deliberately not a second kind of fire |
| `roomOutput.pointRange` / `pointBrightness` | WallLamp | 12 / 0.34 | A lit room lamp's own small glow | Below a full-dial candle on purpose — it lights its corner, not the room |
| `roomOutput.spotRange` / `spotBrightness` / `spotAngle` | WallLamp | 26 / 0.85 / 130° | The useful directional throw into the room | Split from the point light so the fixture doesn't become a small sun |
| `roomOutput.perception.intensity` / `.range` | WallLamp | 0.2 / 22 | What a lit room lamp adds to threat perception | Close to what it visibly throws — a lamp that pushed hunters further than it lit would be an unreadable safety |
| `main.scale` / `crownPoints` / `crownSpread` | WallLamp | 1.5 / 7 / 34° | The completion room's crowned lamp | Half again bigger in every dimension, plus a fanned iron crown — the one piece of pure ornament in the set |
| `main.auraRadius` / `auraTransparency` / `auraColor` | WallLamp | 1.15 / 0.72 / 255,198,138 | The crowned lamp's faint halo | Two nearly-transparent self-lit discs; the one deliberate departure from "every flame is just a candle" |
| `mainOutput.pointRange` / `spotRange` / `perception.intensity` | WallLamp | 17 / 46 / 0.4 | The crowned lamp's output | Brightest fixture in the cave; still not a floodlight — perception range 40 stays well under a full-dial candle's practical reach |
| `interaction.roomHoldSeconds` / `mainHoldSeconds` | WallLamp | 2 / 3 | The price of lighting one | Rooted the whole time; any movement cancels the hold |
| `interaction.leanDegrees` / `leanRiseSeconds` | WallLamp | 26° / 0.35 s | The candle visibly bowing to touch flame to wick | The only outward sign, to everyone on the floor, of what a player is doing |
| `cascade.leadSeconds` / `stepSeconds` / `maximumSeconds` | WallLamp | 0.5 / 0.5 / 8 | The crowned lamp's floor-wide answer | Nearest-to-farthest, whole cascade capped at 8s regardless of floor size; players keep full control throughout — never a cutscene |
| `flareSeconds` / `flareBrightnessMultiplier` | WallLamp | 0.5 / 1.7 | The catch | A hard spike that decays, never a fade-in — reads as something catching, not a dial turning |
| `installation.roomMountHeight` / `mainMountHeight` | WallLamp | 2.2 / 2.35 | Mount height | The height a person would actually reach to light one, level with the flame they're carrying |
| `rideSeconds` / `Floors.geometry.floorGap` | DescentLadder / Floors | 4 s / 96 studs | **The most important ride pair.** Duration and complete physical distance between aligned floors | Long enough to feel like travel; the successor is guaranteed built before motion, and distance is structural floor geometry rather than an independently tunable visual |
| `arrival.exitGraceSeconds` / `pushSeconds` / `pushSpeed` | DescentLadder | 2.5 s / 1 s / 5 studs/s | Walk-out window, then the gentle outward push before closure | Longer grace is kinder but delays every following rider; higher push is less gentle |
| `arrival.forcedExitStuds` / `deckVerticalTolerance` / `openingHeight` | DescentLadder | 5 / 2.5 / 9 studs | Collision-safe final exit, lower-deck occupancy test, and open landing height | The final placement is a safety net after the visible push, never the primary exit motion |
| `arrival.threatGraceSeconds` | DescentLadder | 2.5 s | Enemy-targeting grace after the cage starts returning | Narrow anti-cheap-shot protection; wax drain and environmental hazards continue |
| `cageReturnSeconds` | DescentLadder | 3 s | Visible empty-cage return after the lower gate closes | Riders cannot enter or travel upward with it |
| `shaftRibSpacing` | DescentLadder | 5.5 studs | The full-height lined shaft's parallax cadence | Without regular ribs a dark tube reads as standing still |
| `hoistSideOutset` / `riderHeadClearRadius` | DescentLadder | 0.5 / 1.6 studs | Rear-right cable position outside the cage and asserted clear radius around every rider's first-person position | Larger outset moves the cable toward the shaft wall; raising clearance can deliberately reject a cramped cage retune |
| `promptRange` / `promptHoldSeconds` | DescentLadder | 12 / 0.45 | Boarding | Held, not tapped — nobody rides down by brushing a key while a teammate is two rooms back |
| `shakeStuds` / `shakeHz` | DescentLadder | 0.08 / 6.4 | Rider camera shudder | Sharper and faster than the lobby car's: a rigged cage on a chain, not a company elevator |
| `workLamp.lightRange` / `lightBrightness` | DescentLadder | 20 / 0.85 | The one lit thing on the fixture — an enclosed-glass work lamp hung off the headframe, the last surviving piece of the retired Gas Lantern fixture set | Deliberately well inside the 64-stud room so the far wall stays black. **Decorative only:** `server/LightSources` builds the threat-perception field from server-owned flames/flares/decoys/remains/lit wall lamps and never scans for `PointLight`s, so raising this makes the fixture easier to find and never makes its rider easier to hunt |

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
| `visualSize` / `surfaceClearance` / `promptHeight` | Loot | 1.15 / 0.05 / 1.45 | Diegetic pickup scale, minimal anti-z-fighting clearance above centre-sampled Terrain, and prompt height | cosmetic |

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
| `placement.floorChance` / `roomChance` / `maxPerFloor` | MineRelics | 0.62 / 0.30 / 2 | HOW OFTEN YOU MEET THE OLD WORKINGS. Two gates: the floor rolls whether it has any equipment at all, then each ordinary room rolls to host one. Measured over 3,000 simulated 12-floor descents this produces ~44% of floors carrying anything, 0.66 pieces per floor, ~1 floor between sightings | higher = more often, and past roughly 1.5/floor they stop being a find |
| `placement.placementBearings` / `placementRadiiPerBearing` | MineRelics | 16 / 3 | The sweep that looks for a legal spot. NOT a micro-optimisation: doorway lanes eat most of a well-connected room, and at 14×1 the ore cart and rail run seated in under a fifth of the rooms that tried | more = higher hit rate, more build-time work |
| `placement.openRing*Factor` / `wallRing*Factor` | MineRelics | 0.18–0.40 / 0.28–0.38 of the cell | Ring band each anchoring class samples. Open pieces sweep wider because the free ground in a room with three or four doors is out near the walls | wider = more candidate ground |
| `placement.routeClearance` / `poolClearance` | MineRelics | 1.6 / 3 studs | Kept clear of every doorway lane, the navigation hub, and any pool edge, ON TOP of the piece's own footprint. THE ROUTING GUARANTEE: a relic is collidable mass, so this is what stops one narrowing a walk between two doors | lower = relics creep toward routes |
| `placement.wallProbeStep/Steps` / `catalog[].wallOffset` | MineRelics | 1.25 × 14 / 0.7–3.4 studs | How a wall piece finds the real rock face in a shaped room, and how far its own geometry reaches back into it | a wallOffset under the model's true +Z reach buries it in stone |
| `catalog[].footprintRadius` / `minCeilingHeight` / `minDepth` | MineRelics | 1.7–6.0 / 15–19 / 1–4 | Per-piece space, headroom and depth gate. The radius must cover what the silhouette actually reaches — everything routing-related is measured from it | — |
| `palette.*` | MineRelics | dead iron, rotted timber, damp tint 26,26,30 at 0.42 blend | Materials and colours for every piece, plus how far up from the floor the damp mix fades. Deliberately desaturated: rust that read as orange would be the only warm thing in a cave reserving warm for firelight | — |
| `terrain.groundHump*` | Floors | 7 attempts per room, 12–22 wide, 0.65–3.2 high, −3 separation | Dense, partially overlapping ramped floor shelves in every room | more/larger = rougher routes |
| `terrain.groundPatchFallbackOffset` | Floors | 17 | Corner fallback offset (studs) for a ground patch when the radial roll fails to find a valid spot | — |
| `terrain.specialRoomCenterClearance` | Floors | 7 | Keeps spawn and Basin interaction centers level and clear | lower = rougher special rooms |
| `terrain.doorClearance*` | Floors | depth 10, width 24 | Keeps ground rises out of the largest cave-mouth approaches | lower = more obstruction |
| `terrain.wallClearance/hazardClearance` | Floors | 2 / 2 | Keeps planned rises inside rock walls and away from pools | lower = more overlap |
| `terrain.aiGroundProbe*` / `aiObstacleSidestep` | Floors | 7 / 16 / 4 | Threat ground following and local rock detours. The probe window reconciles the analytic ground field with the voxels actually written from it; too narrow and threats sink into slopes, too wide and one finds a shelf | — |
| `terrain.aiRoofProbeFloorInset` | Floors | 2 studs | Height above the floor `server/ThreatService` casts up from to find the real, built ceiling before hanging a ceiling ambusher. Anchored to the floor because that is the one height guaranteed to be open air: the previous fixed window under the *analytic* underside began inside stone wherever the built roof hung lower than the field predicted, reported nothing, and left the fly hung from a ceiling already above it — spawned inside the rock. Must stay below the fly's own attack height so a dive is never mistaken for a ceiling | — |
| `groundField.*` | Floors | row-specific | Shared floor-wave amplitude, frequencies, doorway-lane blend, enclosure berm, and depth growth | higher amplitude/berm = rougher routes |
| `roof.rockThickness` | Floors | 12 | Solid Terrain above the visible inverted roof underside | lower = thinner shell |
| `roof.minRelief/maxRelief` + `*Frequency*` | Floors | 0.45 / 4.8 studs; 0.035–0.058 / 0.14–0.22 | The **height-independent** part of ceiling structure, plus wavelength ranges | higher relief/frequency = rougher roof |
| `roof.reliefPerCeilingStud` | Floors | 0.3 | **Extra relief per stud of ceiling above the minimum.** Relief has to survive perspective: the same 4.8 studs is obvious structure on a 15-stud roof and invisible on a 46-stud one, since it subtends a third of the angle and sits three times further from the only light in the world. Capping relief absolutely is what made tall chambers read as flat painted lids — the complaint surfaced as "ice caves always have flat roofs", because Ice is the only family that biases its ceilings tall (22–46), but the defect was general. At 0.3 a minimum-height room is **exactly unchanged** and a maximum-height vault gets ~14 studs instead of 4.8. Pinned by "a roof's relief keeps up with how far away it is" in `Tests/FloorPlannerTests` | higher = bolder tall-room roofs |
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
| `presentation.atmosphereDensity` | 0.42 / 0.55 / 0.30 | How quickly the dark closes around the flame — the property a player most directly feels, because it decides how far light reaches and therefore how big the cave seems. **Clamped above `CaveFamilyRules.minimumAtmosphereDensity` (0.22)**: a family may change how far your flame carries, never whether you need one |
| `presentation.atmosphereHaze` | 1.20 / 0.85 / 1.75 | How much distant geometry washes toward the atmosphere colour instead of ending at a hard edge into black. Ice's long halls need a readable far end; Moss's should end in a wall of dark |
| `presentation.atmosphereGlare` | 0 / 0.12 / 0.18 | Bloom immediately around a light — moisture in Moss, ice crystals in Ice. The only one of the three that touches the flame rather than the space |
| `presentation.reverbDecayScale` | 1.00 / 0.60 / 1.65 | Multiplies every bus's authored reverb decay. Reverb is the strongest "different place" signal in audio because it colours every sound at once. Ordered by what each family physically is: fewest formations, longest connectors and hardest surfaces ring longest |
| `presentation.reverbWetOffset` | 0 / −4 / +3 dB | Added to every bus's wet level: how much of the room you hear against the dry source, which reads as how reflective the surfaces are. Offset rather than replaced, so a bus authored nearly dry stays nearly dry in every cave |
| `presentation.footstepCue` | FootstepStone / FootstepMoss / FootstepIce | What this cave sounds like underfoot — the most frequent sound in the game. Standing water overrides it everywhere (`FootstepWater`). Self-audible only; walking is not in `Config/Sound.emitters` and must not become so (`emitters.Landing` is a touchdown, not a step, and is the one deliberate exception to movement being silent to the cave) |
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
| `environment.vinesEnabled` | true / true / true | Whether an optional doorway obstruction generates; the data-stamped style decides vines versus ice bars |
| `environment.doorwayBarrierStyle` | Vines / Vines / Icicles | Stone and Moss burn; Ice melts and never displays vine geometry |
| `environment.vineIntroductionShift` | 0 / 2 / 0 | Floors EARLIER curtains start appearing |
| `environment.vineCountFactor` | 1.00 / 1.75 / 1.00 | Scales the shared optional-doorway target; Moss now produces materially more curtains |
| `environment.flammableVegetation` | false / true / false | Whether this family grows the dry clusters a flame can light (`Config/MossFire`) |
| `threatEcology.weightMultipliers` | — / DarkCrawler 1.05, Moth 1.15, VoidFly 1.00 / DarkCrawler 1.20, Moth 0.95, VoidFly 1.20 | Scales a threat's rolled spawn weight. Moss is damp, overgrown moth country; Ice is open, bare hunting ground. Each figure is that family's old per-row values averaged under those rows' own spawn weights, so the mix a floor draws is the one it always drew. Changes WHICH of the existing roster a floor draws; **no stat, state or AI rule in `Config/Threats` is touched by a family** |
| `threatEcology.introductionShift` | — / Moth +1 / DarkCrawler +1 | Floors earlier a row's authored weight table is sampled at. Never samples below floor 1 |

`Config/Icicles` owns Ice's frozen-doorway response: `maxBrightnessMeltSeconds = 6`,
`flareMeltSeconds = 1.2`, `meltRadius = 9`, and `puddleLifetimeSeconds = 10`. The puddle is cosmetic
and non-colliding; it never enters the water-hazard system.

Its `visual` block owns the barricade's ART, and none of it touches the melt rules above. The
silhouette is four layers — `crust*` (the frozen mass welded into the arch and both jambs), `fang*`
(tapered icicles hanging from the arch), `spike*` (shorter ice rising off the floor on its own slot
count so the two rows interlock), and `bloom*` (frost shards over the crust). The number that does
the most work is the `fangMinLengthFraction`/`fangMaxLengthFraction` spread: narrowing it turns the
jagged bottom edge into a hem, and a hem reads as a manufactured comb rather than as ice. `fangCount`
and `spikeCount` are fixed counts rather than spacings on purpose — doorways range from roughly 8 to
56 studs wide, so a fixed spacing would put three icicles in a crevice and forty in a hall. The whole
barricade is ~130 parts, against ~216 for a Moss vine curtain.

### Ice surface dressing (`floorGlaze` / `icicleFringe` / `coverFinish` / `formationFinish`)

| Value | Default (Stone / Moss / Ice) | Controls |
|---|---|---|
| `floorGlaze.sheetsPerRoom` | 0 / 0 / 6 | Broad flat panes of clear ice seated on the real sampled ground, breaking up a floor that otherwise reads as one poured surface. Collision-neutral: no friction, no physical properties, nothing slides |
| `icicleFringe.clustersPerRoom` | 0 / 0 / 7 | Icicle clusters across the open ceiling |
| `icicleFringe.clustersPerDoorway` | 0 / 0 / 3 | **The half that sells the family.** Clusters hung on the actual arch curve of every opening, because a player looks at a doorway before walking through it. Capped at a third of the opening's height so it frames rather than obstructs |
| `coverFinish` | neutral / neutral / 4 materials · T 0.04–0.46 · R 0.08–0.36 · tilt 24° | **The single most important block for whether Ice looks like ice.** Per-facet material, transparency, reflectance and tilt on wall and ground cover |
| `formationFinish` | neutral / neutral / 4 materials · T 0–0.20 · R 0.06–0.30 | The same question asked of every stalactite, icicle, boulder and column, applied through `CaveKit.configure` |
| `coverDensityFactor` / `coverFinish.sizeScale` | 1 / 2.2 / **2.5 · 0.7** | One decision, not two: many small facets read as crystalline, few large ones as panels. Changing either alone leaves the wall sparse or cluttered |

**A surface is defined by how it hands the candle back, not by its colour.** Ice's frost was authored
as a well-chosen blue and rendered as blue cardboard, because every facet was opaque, matte, one
material and flush against the wall. The eye identifies a material by specular behaviour — whether a
highlight sits still, slides, or never appears — long before it reads hue, and under one moving flame
that is nearly all the information available. **The ranges are the point.** Adjacent facets must
answer the same flame *differently*; a uniform reflectance is only slightly less flat than none,
because the whole wall then flashes at once. If Ice ever looks like plastic again, widen
`reflectanceMin`–`reflectanceMax` and add a material before touching a single colour.

`formationFinish.transparencyMax` is deliberately far below `coverFinish`'s, and the test suite pins
that ordering: this finish also dresses the **unstable formations**, and a falling hazard has to stay
unmistakably solid because its fracture lines are a warning the player reads at range (ART-BIBLE §8).

**Nothing in any cave emits.** A self-lit "cold light" channel — faint cyan wall seams plus one lit
crystal landmark per chamber, with the only PointLight in any cave — was built and cut. It read as
glowing sticks floating in the dark rather than as ice, and it gave away visibility the game is
designed to withhold. Reflectance reaches the same instinct honestly: it makes a surface catch the
light the player brought, so it changes how good the ice looks without changing how much anyone can
see. Do not reintroduce emission; widen a finish instead.

Every count above is zero (or neutral) in Stone and Moss, and each builder pass consumes **zero random
rolls** in that case. That is load-bearing rather than tidy: a single stray `rng` call would shift
every boulder, column and relic placed after it, and Stone is the regression baseline the other two
families are measured against. `CaveFamilyRules.surfaceFinishVaries` is the predicate the builders
gate on, and it is derived from the data rather than carried as a flag so it cannot disagree with the
numbers beside it.

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
| `presentation.terrainMaterial` / `wallMaterial` / `rockMaterial` | Slate·Slate·Slate / Rock·Rock·Basalt / **Ice·Ice·Ice** | THE SURFACE GRAIN, and the reason these are three caves rather than one under three gels. The test suite requires the combination to be distinct per family, and **deliberately does not require terrain and wall materials to match** — see the rule below |
| **Ice's `terrainMaterial`: four candidates, one survivor** | — | Roblox terrain renders **top faces from a different texture than sides**, so a material with a distinct top gives a cave a floor made of visibly different stuff from its walls out of one material and one colour. **Glacier** — great cracked side texture, but a smooth snow-ice top that washes warm (ceiling read blue-green while the floor read tan, in the same room). **Slate** — uniform, but a smooth streaky layered texture with no crack detail. **Basalt** — uniform and dark, but rust and green flecks that go orange under warm light. **`Ice`** — uniform across faces *and* genuinely ice, and its default is already blue so `SetMaterialColor`'s clamp-toward-default finally lets the authored tint land cold instead of pale |
| **The same material enum does not look the same on terrain and on a part** | — | Different rendering paths, different texture sets, different UV projection. Glacier is cracked rock as *terrain* and a rippled water-like sheet on a *part* — putting it on Ice's wall slabs is what made the doorways read as the wrong material. Never assume matching the enum names unifies the look; judge the two surfaces separately |
| `presentation.terrainColor` | — | **Only partly honoured by the engine.** `SetMaterialColor` clamps a terrain material's colour toward that material's own default, so the base tone bounds what any tint can reach — a pale default cannot be made dark. Glacier's pale default is why the Ice floor stayed warm regardless of this value; Slate's dark cool default is the first one in this family whose tint can actually land near `ICE_ROCK` |
| `presentation.colorGrade` | identity / faint green / **tint (0.75, 0.93, 1.00) · sat +0.12** | **THE ONLY LEVER THAT CAN CHANGE A CAVE'S COLOUR TEMPERATURE, and the fix for four rounds of "the ice cave looks like a muddy orange tunnel".** `EnvironmentSetup.apply` pins `Ambient`, `OutdoorAmbient` and `Brightness` to black and zero, so every lit pixel in the game is lit by one warm flame the player carries. A rendered colour is `surface × light` — with a warm light and no ambient term, **a blue surface cannot come out blue.** Dim it goes muddy brown-green; lit hard by a flare it clips toward the light's own hue and comes out orange. Ice's rock is authored at ~5:1 blue-to-red and still rendered warm. **No material palette can fix this.** A ColorCorrectionEffect multiplies the final image instead, so it recolours what the flame lands on and adds nothing to the scene |
| `presentation.coverPalette` / `coverMaterial` / `coverDensityFactor` | moss 1.0 / moss 2.2 / ice 1.6 | Collision-neutral wall cover, scaling the authored `Floors.caveMoss` patch counts |
| `presentation.coverShape` / `groundCoverPatchesPerRoom` | Patch·0 / Patch·0 / Shard·8 | Organic wall growth stays flat; Ice uses angled crystalline wall facets and scatters non-colliding frost crust over the sampled ground without changing friction or placement |
| `presentation.wallColor` / `rockColor` / `terrainColor` | cool blue-charcoal / wet green-grey / **saturated cold blue** | Ice's rock is authored for BLUE-TO-RED RATIO, not for brightness. The candle grade (~255, 242, 220) multiplies red by 1.0 and blue by ~0.86, so rock whose blue merely exceeds its red arrives at the eye neutral grey-brown — which is why Ice used to read as a muddy tunnel while being nominally blue. Blue now leads red roughly 5:1. This costs no brightness (blue carries 7% of perceived luminance against green's 72%), so all three Ice values are *darker* than the ones they replaced while reading far colder. Pinned by "Ice's rock is COLD, not merely dark" in `Tests/CaveFamilyRulesTests` |
| `presentation.atmosphereColor` | neutral grey-blue / green-grey / **cold teal** | The single strongest lever on whether a cave reads cold, and the one that was doing least work before. Every distant surface washes toward this, and with Ice's very high haze (1.75) it tints more of the screen than any material does. Colour only — `atmosphereDensity` is untouched, so how far a flame carries is unchanged |
| `presentation.formationPalette` / `formationMaterials` | slate / damp green-grey / pale glacier | What every stalactite, stalagmite, boulder and unstable formation is built from. This is all an Ice "icicle" is: the same hazard with the same warning, fall timing and impact rules, cut from ice |
| `presentation.threatVariantId` / `threatVariantTintStrength` | Stone 0 / Moss 0.22 / Ice 0.32 | How strongly a threat body is tinted toward its cave. **Presentation only.** Ice also uses broad, high-coverage rime and a glacier skin grain; crimson dark-hunter eyes, yellow Drawn eyes, moth wings and every head remain untouched |

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
| `voteSeconds` / `launchCountdownSeconds` | Lobby | 20 / 3 seconds | Maximum ballot time after everyone is ready, then the short committed gate-closing beat |
| `kickRejoinBlockSeconds` | Lobby | 20 seconds | How long a leader-removed rider is refused by that same car; other cars and the rest of the hub stay available |

Studio always takes the local-start branch; only a published live server exercises
`TeleportService`. ProfileStore also uses its isolated Mock in Studio, so persistence tuning and
unlock verification require a live published test.

## How is the physical lobby laid out?

The lobby ("The Landing") is one fixed mineshaft hub built once at server boot by
`server/LobbyRoomBuilder.luau` — not seeded or rebuilt per run, unlike `Config/Floors`. Its four
elevators are independent party queues (`server/ElevatorService.luau`): entering a car joins it,
the first rider becomes leader, and an interactive panel releases the shift-locked cursor. Riders
ready individually, then vote on a cave while the same panel shows personal entry/ownership costs
and the cave's Raw Wax/native-ore benefit. Walking out or pressing LEAVE exits before launch. A
leader may remove another rider, blocking that rider from the same car for the configured window.

The open hub shows the player's **real Roblox avatar** (`CharacterService.spawnLobby`). The moment
the vote resolves and the descent commits, the car's lever throws itself down — it is a read-out, not
a control, and takes no input — and committed riders are replaced with full, lit candles in first
person.
Those elevator candles remain lobby-tracked presentation bodies, so they spend no wax and never
enter hazards, threat perception, or movement correction before floor 1 exists.

| Value | File | Default | Controls |
|---|---|---|---|
| `origin` | LobbyRoom | (0, 500, 0) | World position of the hub. Must clear both the tallest cave roof (Y≈58) and `rideShaftDepth` below itself, so the hub and its shafts can never overlap cave Terrain |
| `roomWidth` / `roomDepth` / `wallHeight` | LobbyRoom | 200 / 150 / 30 studs | Hub footprint and ceiling height. The entry wall's inner face and rail mouth sit at z=-74 |
| `beamSpacing` / `railSpacing` | LobbyRoom | 16 / 6 studs | Density of the timber ceiling supports and the mine-cart sleepers |
| `lighting.ceilingLampRange` / `Brightness` | LobbyRoom | 42 studs / 0.8 | Broad but subdued pools from the six overhead lamps |
| `lighting.candleRange` / `Brightness` | LobbyRoom | 16 studs / 0.32 | Warm local fill from wall candles; the six ceiling lamps remain the hub's main light |
| `wallCandles.height` / `spacing` / `fixtureClearance` | LobbyRoom | 9 / 14 / 2 studs | Head-height candle cadence and the padding added to config-derived board, shop, tunnel, leaderboard, update-board, and elevator exclusion spans |
| `tunnel.width` / `height` / `depth` / `barrierSetback` | LobbyRoom | 14 / 14 / 22 / 5 studs | Arrival-mouth opening, visible recessed darkness, and the invisible collidable seal inside it |
| `rails.startZ` / `endZ` / `gauge` | LobbyRoom | -74 / -22 / 3.2 studs | Arrival track from the tunnel mouth to the forward buffer block; sleepers use `railSpacing` |
| `mineCarts.mainOffset` / `waxCartOffsets` | LobbyRoom | (0,1.4,-28) / two side rows | Parked arrival cart beyond the spawn ring and matte Raw Wax carts in side pockets outside primary walking lines |
| `lighting.elevatorLampRange` / `Brightness` | LobbyRoom | 18 studs / 0.55 | Restrained light inside each elevator car |
| `spawnOffset` / `spawnSpread` | LobbyRoom | (0,0,-44) / 10 studs | Where arrivals appear, and the first-ring radius used to keep hub arrivals separated |
| `fallRecoveryDrop` | LobbyRoom | 40 studs | How far below the floor counts as "fell down an open shaft" and is teleported back to spawn |
| `runSpeed` / `jumpPower` | LobbyRoom | 30 / 48 | Lobby-only default movement. Costs no wax (there is no `PlayerState`), and has no manual sprint binding |
| `shopOffset` / `shopFacingYaw` | LobbyRoom | (-96,0,-8) / 90 degrees | West-wall storefront anchor and rotation; every `shopDisplay` offset is shop-local |
| `elevators` | LobbyRoom | four rows (party 1–4) | Party id + car position. Cave selection happens later by vote, so cars are not tied to cave families |
| `elevatorCarWidth` / `Depth` / `Height` | LobbyRoom | 14 / 14 / 14 studs | Elevator car dimensions. The floor is built with a matching gap so the car has a shaft to descend through |
| `elevatorZoneRadius` | LobbyRoom | 10 studs | Horizontal distance counting as "standing in this elevator". Keep ≥ the car's half-diagonal or its corners fall outside the zone |
| `elevatorExitOffset` | LobbyRoom | (0,0,-13) studs | Safe point beyond the open gate used by panel LEAVE, leader kick, and refused car entry; must remain outside `elevatorZoneRadius` |
| `elevatorBoardWidth` / `Height` | LobbyRoom | 11 / 7 studs | The alcove header board carrying the party number, phase, readiness, leader, and live roster |
| `rideDistance` / `rideShaftDepth` | LobbyRoom | 220 / 260 studs | How far the car travels, and how deep the shaft it travels into is. Shaft must exceed travel |
| `rideShaftRibSpacing` | LobbyRoom | 10 studs | Spacing of the four-segment perimeter wall ribs — the parallax that makes the ride read as motion without placing solid plates across the car's path |
| `rideShaftRibThickness` / `rideShaftRibOutset` | LobbyRoom | 0.8 / 1.5 studs | Perimeter-beam thickness and clearance outside the car shell |
| `rideShakeStuds` / `rideShakeHz` | LobbyRoom | 0.1 studs / 5.5 Hz | Subtle horizontal mechanical camera tremor during the ride; descent never bobs the camera vertically |
| `welcomeSignText` / `howToPlayRules` | LobbyRoom | — | Board copy. Keybinds are NOT written here: the controls panel is generated from `Feel.controls` so it can't drift from real bindings |
| `boardWidth` / `boardHeight` | LobbyRoom | 38 / 17 studs | Size of the welcome and how-to-play boards |
| `leaderboardWidth` / `leaderboardHeight` | LobbyRoom | 34 / 20 studs | Dedicated physical size of the standings board; kept independent so it can comfortably carry aligned rows without enlarging the other lobby signs |
| `leaderboardRows` / `leaderboardRefreshSeconds` / `leaderboardManualRefreshSeconds` | LobbyRoom | 10 / 60 / 10 seconds | How many standings rows the board shows, its automatic refresh cadence, and the shared cooldown on a player's manual board refresh |
| `updateBoardWidth` / `updateBoardHeight` / `updateLog` | LobbyRoom | 30 / 20 studs / newest-first rows | Physical recent-updates board and the server-authored entries filtered against `lastSeenUpdateVersion` for the join-time panel |

The refresh interval is only the background cross-server poll. A death or successful Brazier
extract overlays its score in the current server immediately and requests an immediate repaint, so
returning players never wait a minute to see the result. Studio uses that same session-local
overlay without writing to the production OrderedDataStore.

The ride is the loading transition, not decoration over it: on a successful `tryLaunch`,
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
On touch devices the legend itself is not drawn — every chip names a key, and a phone has none. The
same title, timer, shrinking fill and active state are sent to `client/TouchControls` instead, which
draws them on the action buttons in its own cluster.

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
| `footsteps.quietVolume` / `loudVolume` | Feel | 0.238 / 0.595 | Local walk/run playback band, uniformly 30% below the prior 0.34 / 0.85 values. Surface character remains in the individual `Footstep*` cue rows |
| `ambientCave.initialDelay*` / `refractory*` / `meanSilenceSeconds` / `maxSilenceSeconds` | Feel | 28–56 / 22–32 / 48 / 150 s | One global, exponential ambient clock: more opportunities for low-gain cave detail, still with quiet valleys rather than independent periodic timers |
| `ambientCave.silentWeight` / `recentFamilyCount` / `focusQuietSeconds` | Feel | 18 / 2 / 11 s | Authored non-events, anti-repeat memory, and protected silence after gameplay-critical Focus cues |
| `ambientCave.soundEvents` | Feel | Strata/Fissure/Calcite/Water/Gravel/Settle/Draft/Drip cluster + Moss Seep/Ice Groan | Weights, real surface kind, range, burst gaps, restrained pitch, and occupied duration for ten harmless sound families |
| `ambientRockfall.*` | Feel | 0.6–1.1 studs / 3.2–5.8-stud fall | Director-invoked loose-stone surface query, fall, roll, and cleanup; no private timer or gameplay effect |
| `ambientWaterDrip.*` | Feel | 6 attempts / 8–26 studs / 34-stud ceiling search | Director-invoked randomized roof source query and emitter cleanup; no listener-centred fallback or private timer |
| `ambientCave.relicWeight` / `ambientRelic.*` | Feel | 5 / 6–42 studs / 1–2 bursts / 4.2 s | The abandoned workings settling. THE ONLY AMBIENT EVENT ANCHORED TO A REAL OBJECT: it hangs off a tagged `Config/MineRelics` model near the player instead of a raycast surface, and refuses outright when there is nothing in range — which is most floors. The lowest weight in the pool on purpose, and its effective rate is lower again because of that refusal | higher = the cave sounds like it still has machinery in it |
| `tutorialHints.*` | Feel | floors 1–3 / 5 s / 0.35 s fade / 12 s repeat | Bottom-screen teaching hints for authoritative threat contacts, first nearby dripstone falls, and replicated water entry |
| `itemHints.enabled` / `.messages` | Feel | on / one line per `Config/Loot` id | What a pickup says the FIRST time that player ever collects it. Shares the tutorial-hint panel but is exempt from `tutorialHints.maxDepth` and its throttles — a one-shot hint has no second showing to fall back on, and the Candle Sleeve cannot even appear before floor 5. Recorded per profile (`Persistence.seenHints`), so a returning player is never re-taught |
| `debug.showThreatLabels` | Feel | false | Restores grey-box threat names for tuning; keep false for horror playtests |
| `controls.*` | Feel | 1–3 tools plus utility bindings | Single source for real keyboard bindings, touch-cluster ordering (`touchOrder`, not a position — `client/TouchControls` owns placement), and hotbar labels; movement has no manual sprint binding |
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
The menu uses `122061612190896` at volume `0.1755`. The shuffled cave pool contains `71682768476112`,
`136582960170775`, `104375150403939`, and `113564986043204`, each at volume `0.352` (20% below
the original mix). The bag plays
every configured cave track once before reshuffling and prevents the last track of one bag from
immediately repeating as the first track of the next.

| Value | File | Default | Controls |
|---|---|---|---|
| `maxActiveVoices` / `buses[*].voiceLimit` | Audio | 48 global / 4–18 per bus | Oldest-voice stealing bounds mix density instead of allowing unbounded one-shots |
| `buses.Music/Ambience/World/Focus/UI` | Audio | nested beneath `WickMaster`; Ambience 0.45 | Category headroom; cave ambience is another 20% below the prior 0.5625 mix (55% below authored gain); cave EQ/reverb; Focus sidechains gently duck Music/Ambience for critical reads |
| `cues[*].cooldownSeconds` | Audio | cue-specific | Spatial cooldowns apply per emitter; non-spatial/UI cooldowns remain global, so independent world contacts do not mute one another |
| `occlusion.*` | Audio | 0.68 direct volume / -1,-5,-17 dB EQ | One-shot ray obstruction keeps the reverb tail while filtering direct sound through rock |
| `music.initialDelayMinSeconds/MaxSeconds` | Audio | 18 / 42 s | Random silence before the first cave track |
| `music.betweenTrackDelayMinSeconds/MaxSeconds` | Audio | 10 / 24 s | Random silence between cave tracks |
| `music.fadeInSeconds/fadeOutSeconds` | Audio | 4 / 5 s | Smooth music entrances, natural endings, and lobby/run switches |
| `music.endCheckIntervalSeconds` | Audio | 0.2 s | How often the client checks whether end fading should begin |
| `settings.musicMinMultiplier` / `ambienceMinMultiplier` | Audio | 0% / 10% | Per-client Music and Ambience sliders in Settings. Music can mute; Ambience bottoms out at 10% of its configured mix, preserving a minimal cave bed |
| `cues.MenuMusic` | Audio | 122061612190896 / 0.1755 | Main-lobby loop, reduced another 25% from its prior 0.234 gain |
| `cues.FlyBuzz` | Audio | 9114506042 / 0.12 / 4–32 studs | Quiet spatial VoidFly warning, and that creature's idle voice — it is deliberately absent from `idleAudio` because this row already covers it with a bespoke roof-occlusion path |
| `cues.DarkCrawlerAttack` | Audio | 9125619840 / 0.82 / 0.9× / 7–64 studs | Short wet blade-like slice on crawler contact; shares no source with mining or dripstone |
| `cues.MothBite` | Audio | 9119055965 / 0.78 / 1.15× / 6–52 studs | Small-teeth snap on the moth's strike frame, distinct from its wing and idle layers |
| `cues.VoidFlyAttack` | Audio | 9113978334 / 0.86 / 1.12× / 5–40 studs | A big flying insect slamming a pane — the fly's armoured body hitting the flame it is trying to snuff. Was `FlyBuzz`'s own file at 1.38×, so patrol, dive and strike were one sample at three speeds |
| `cues.ListenerAttack` | Audio | 9118167124 / 0.82 / 0.78× / 7–62 studs | Heavy wet ribcage impact; no longer shares the moth's small-teeth snap |
| `cues.KnotwalkerAttack` | Audio | 9119560180 / 0.76 / 1.05× / 6–58 studs | Wet ligament and cartilage as a long forelimb folds around you |
| `cues.CalverAttack` | Audio | 9125869159 / 0.8 / 0.92× / 7–64 studs | Rock struck against rock. The only correctly geological creature cue in the game: the Calver hits the CEILING, never the player |
| `cues.ThreatHit` | Audio | 9113513536 / 0.94 / 0.8× | Dull wet gut impact, non-spatial, heard only by the confirmed victim. Was `Rock Impact 1` at 0.7× — the same recording `MineStrikeImpact` plays at 0.78×, so being bitten and swinging a pick were one sound |
| `cues.DarkCrawlerLunge` | Audio | 9116311525 / 0.36 / 0.62× / 6–58 studs | Throaty snarl as the body gathers |
| `cues.MothLunge` | Audio | 9113979818 / 0.4 / 0.82× / 5–44 studs | A vocalised wing-flap as the moth commits to the flame; source is tagged for exactly this beat |
| `cues.VoidFlyLunge` | Audio | 9120627691 / 0.42 / 1.45× / 4–38 studs | Wet whipping swish as the fly lets go of the roof — the only warning that the dark patch overhead was occupied |
| `cues.ListenerLunge` | Audio | 9113971433 / 0.34 / 0.66× / 6–56 studs | Deep breathy growl. A VOICE, not the rock scrape it used to play, which was indistinguishable from the cave settling |
| `cues.KnotwalkerLunge` | Audio | 9113546532 / 0.32 / 0.88× / 5–48 studs | One long dry crack as a folded limb straightens |
| `cues.CalverLunge` | Audio | 9125881620 / 0.32 / 1.1× / 6–56 studs | Stone dragging on stone as it hauls back against the vault |
| `locomotionAudio.stepCueNames` | Threats | per rendered kind | ONE STEP CUE PER WALKING BODY, replacing a single shared `ThreatStep`. Only the crawler, Listener and Knotwalker have a gait to source foot plants from |
| `cues.CrawlerStep` | Audio | 9125467664 / 0.19 / 0.86× / 4–46 studs | A single clacky claw tap: chitin on stone, sub-second, one plant is one event |
| `cues.ListenerStep` | Audio | 9113469691 / 0.21 / 0.72× / 5–46 studs | Crunching body weight onto dirt. Loudest and furthest-carrying of the three — this is the creature you are meant to hear and stop mining for |
| `cues.KnotwalkerStep` | Audio | 9125467704 / 0.16 / 0.68× / 4–40 studs | A different claw from the crawler's, pitched down and stretched: same chitin, longer limb. Quietest of the three |
| `cues.MothWing` | Audio | 9114876115 / 0.085 / 1.15× / 3–28 studs | Actual insect wings — a moth's equivalent of a footstep, on an interval rather than per beat. Was `Whoosh By Howling Wind`, i.e. weather rather than an animal | louder/farther = more warning |
| `idleAudio.calm/alertIntervalSeconds` | Threats | 11 s / 4.5 s | THE PASSIVE LAYER, which did not exist. Interval interpolates on the body's own activity, so a creature that has noticed you speaks up more often |
| `idleAudio.quiet/loudVolume` | Threats | 0.45 / 1 | Level band, likewise remapped from activity. Every idle cue sits under that same body's movement cue, which sits under its attack cue |
| `idleAudio.audibleDistance` | Threats | 46 studs | Shorter than locomotion's 48: what something IS should reach you from closer than the fact that it is MOVING |
| `cues.CrawlerIdle` | Audio | 9113982931 / 0.115 / 0.8× / 4–34 studs | Low spider hiss from the dark it is holding |
| `cues.MothIdle` | Audio | 9119531802 / 0.075 / 0.72× / 3–26 studs | Ratchety insect clicking from a moth resting on stone; thin and high against the crawler's hiss |
| `cues.ListenerIdle` | Audio | 9113973119 / 0.155 / 0.55× / 5–44 studs | Deep quiet breathy gurgle — the blind thing listening. Loudest and furthest-carrying idle voice, because until now the creature built entirely around sound made none |
| `cues.KnotwalkerIdle` | Audio | 9113542386 / 0.1 / 0.7× / 4–32 studs | Dry joint ticking; the idle most often heard from a room you have not entered |
| `cues.CalverIdle` | Audio | 9125876215 / 0.095 / 0.8× / 5–38 studs | The scrape `Config/Threats` always said it makes between strikes, which previously had no cue behind it |
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
| `cues.CaveDistantSettle` | Audio | 9118609396 / 0.055 / 14–88 studs | Muffled, harmless wall settling beyond the visible loose-rock layer |
| `cues.CaveColdDraft` | Audio | 9120698168 / 0.05 / 8–82 studs | Short, close wall current, distinct from the broad fissure-pressure movement |
| `cues.CaveDripCluster` | Audio | built-in water impact / 0.052 / 2–40 studs | Two to four quiet roof drops from one sampled ceiling source |

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

## Developer diagnostics

`Config/Diagnostics` owns the per-player developer overlay. In the Landing, type `0610` directly
while walking; no cursor, modal, or F8 is required. The server requires a real lobby body before it authorizes the player.
Authorization is carried into reserved caves and back to the Landing. The overlay and red
AlwaysOnTop ore/enemy markers are client-only and never change gameplay state. The static teleport
handoff and live ReplicatedFirst loading screen retain a red telemetry panel until the in-game
overlay takes over. After authorization the side panel and markers remain visible and cannot be
toggled off during that session.

| Value | File | Default | Controls |
|---|---|---|---|
| `unlockCode` | Diagnostics | `0610` | Landing-only convenience code; server validation remains authoritative |
| `statsHz` | Diagnostics | 1 Hz | Server aggregate-stat update rate |
| `highlightColor` / transparency | Diagnostics | red / 0.45 fill | Through-wall ore and enemy marker appearance |
| `markerMaxDistance` | Diagnostics | 10,000 studs | Billboard visibility distance for diagnostics only |
| `wardenTag` / `enemyVisualTag` / `itemTag` / `descentTag` | Diagnostics | `WickDevWarden` / `WickDevEnemyVisual` / `WickDevItem` / `WickDevDescent` | Discovery tags for server Wardens, client-built procedural enemy bodies, active loot pickups, and next-floor beams |

## Developer enemy test room

`Config/DevTestRoom` owns the fixed, PIN-gated physical laboratory beside the Landing. Enter `0610`
at its terminal to become a real candle at virtual depth 610. The candle remains visible to the real
enemy systems, but `DevTestSessionRegistry` blocks wax loss, snuff and death; Flare and Decoy receive
large session-only charge pools. Spawn mutations are not accepted over the network: every enemy and
utility action comes from a server-owned ProximityPrompt on the room console.

| Value | File | Default | Controls |
|---|---|---|---|
| `session.depth` / `globalDepth` | DevTestRoom | 610 / 10 | Isolated runtime floor key and threat difficulty used to enable every mature behavior |
| `session.maxOrdinaryThreats` | DevTestRoom | 12 | Cap on simultaneous Crawler/Moth/VoidFly/Listener/Knotwalker/Calver instances |
| `session.freeToolCharges` | DevTestRoom | 999 | Session-only Flare and Decoy uses restored with RESET CANDLE |
| `session.controlValidationDistance` | DevTestRoom | 24 studs | Server-side console validation; the compact body-height buttons expose prompts only within 14 studs |
| `session.controlCooldownSeconds` / `rebuildControlCooldownSeconds` / `sharedRebuildCooldownSeconds` | DevTestRoom | 0.35 s / 1 s / 0.5 s | Per-tester control throttle plus a shared guard around Lurker, Warden, Crown and mass-removal rebuilds |
| `session.containmentCheckSeconds` / `containmentMargin` | DevTestRoom | 0.5 s / 3 studs | Revalidates body, depth, authorization, party isolation and chamber bounds before infinite-health protection can persist |
| `session.wardenStunSeconds` / `crownTriggerRadius` | DevTestRoom | 4 s / 28 studs | Direct Warden-stun utility and the real Heavy Crown trigger lookup |
| `access.*` | DevTestRoom | Landing offset `(30,0,-44)`, 10-stud prompt | Physical code terminal placement and prompt presentation |
| `room.offsetFromLobby` / `interiorSize` | DevTestRoom | `(440,0,0)` / `128×30×128` | Isolated four-bay chamber; four 64-stud logical cells form the minimum cycle for Knotwalker cut-ahead routing |
| `room.routeOpeningWidth` / `routeOpeningHeight` | DevTestRoom | 58 / 15 studs | Four broad physical divider arches covering every Stone/Moss/Ice doorway waypoint used by test threats |
| `controls.boards` | DevTestRoom | two boards, at most 3 button rows each | A two-row entity picker grouped into All Caves/Stone/Moss/Ice, plus a separate compact Room/Crown/Warden/Signal utility console; all 18 server-owned actions are unchanged |
| `guide.boards` | DevTestRoom | two static 56×22-stud boards | Readable behavior and counterplay cards for all ten spawnable entities, split between the shared roster and the three cave-family signature columns |
| `lurker.sites` | DevTestRoom | two opposed arches | Real trip-lane, gaze-to-shame and relocation test fixtures |
| `hazard.variantId` | DevTestRoom | `Hammer` | Registered Heavy Crown used by Calver strikes and Warden stun tests |

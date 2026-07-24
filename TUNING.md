# TUNING — the feel surface

Every tunable value in the game, grouped by **the question you're answering when you reach for
it** — not by file. All values live in `src/shared/Config/`. "Harder →" is the direction that
makes the game more punishing. Wax values are fractions of a full candle (0..1). Change a value,
let Rojo sync, play — no logic edits, ever.

---

## How long do I survive? — the burn economy

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `startingWax` | Wax | 1.0 | Wax a fresh candle begins with | lower |
| `maxWax` | Wax | 1.0 | Absolute wax ceiling | lower |
| `idleDrainPerSecond` | Wax | 0.002 | Cost of merely being lit | higher |
| `burnDrainPerSecond` | Wax | 0.02 | Cost of full brightness | higher |
| `burnDrainExponent` | Wax | 1.5 | How disproportionately bright burning costs | higher |
| `movementCostMultiplier` | Wax | 1.0 | Global scalar on ALL movement costs | higher |
| `initialBurnRate` | Wax | 0.4 | Dial position at spawn (starting point only) | — |
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

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `Snuff.cooldown` | Tools | 0.5 | How fast you can flicker in/out | higher |
| `Flare.waxCost` | Tools | 0.06 | Price of the panic button | higher |
| `Flare.cooldown` / `duration` | Tools | 4 / 1.5 | Burst spacing and length | higher / lower |
| `Flare.burstIntensity` / `burstRange` | Tools | 3 / 60 | Repel strength AND lure strength | lower |
| `Cast.waxCost` | Tools | 0.04 | Wax permanently thrown away | higher |
| `Cast.cooldown` / `duration` | Tools | 3 / 6 | Decoy spacing and burn time | higher / lower |
| `Cast.castRange` | Tools | 25 | Max throw distance (server-clamped) | lower |
| `Cast.decoyIntensity` / `decoyRange` | Tools | 0.8 / 15 | Must out-shine a dimmed player to divert | lower |
| `Cast.decoySize` | Tools | 0.8 | Blob diameter (visual) | — |
| `Cup.waxCost` | Tools | 0.005 | Upkeep per SECOND held | higher |
| `Cup.lightMultiplier` | Tools | 0.08 | Your light while cupping (hidden-ness AND blindness) | higher |
| `Cup.speedMultiplier` | Tools | 0.5 | Your speed while cupping | lower |

## How punishing are threats? — the two categories

`lightResponse` sign: DarkHunter < 0 (repelled), Drawn > 0 (attracted). Magnitude = sensitivity.

| Row: `speed` / `detectionRadius` / `lightResponse` / `waxDamagePerSecond` (Threats.definitions) | | |
|---|---|---|
| Lurker (DarkHunter) | 10 / 18 / −1.0 / 0.05 | contactRadius 3, bodySize 3 |
| Stalker (DarkHunter) | 14 / 24 / −0.6 / 0.08 | contactRadius 3, bodySize 4 |
| Moth (Drawn) | 12 / 30 / +1.0 / 0.04 | contactRadius 3, bodySize 3 |
| Swarm (Drawn) | 8 / 22 / +0.7 / 0.10 | contactRadius 4, bodySize 5 |

Harder → higher speed/radius/damage; hunter `lightResponse` nearer 0 (harder to repel).

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `behavior.huntLightThreshold` | Threats | 0.15 | How dark you must be before hunters take you | higher |
| `behavior.repelLightThreshold` | Threats | 0.45 | Light needed to drive a hunter back | higher |
| `behavior.repathIntervalSeconds` | Threats | 0.5 | Threat reaction time | lower |
| `behavior.wanderSpeedFraction` | Threats | 0.35 | Idle drift speed | higher |
| `behavior.wanderRadius` | Threats | 25 | Idle roam range from spawn | higher |

## How dangerous is the environment? — draft and water

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `Draft.guttering` | Hazards | 0.03 | Extra wax/s in a draft (CUP immune) | higher |
| `Draft.snuffAfterSeconds` | Hazards | 4 | Uncupped exposure that snuffs you outright | lower |
| `Water.degradePerSecond` | Hazards | 0.2 | Wax/s while wading | higher |
| `Water.lethalAtHeightFraction` | Hazards | 1.0 | Surface height (fraction of CURRENT body) that kills | lower |
| `heightAtFullWax` | Character | 4 | Body height at full wax — water headroom early | lower |
| `heightAtZeroWax` | Character | 0.8 | Body height near burnout — late-run water death | lower |
| `waterDepth` (Flooded row) | Floors | 2.2 | How deep flooded halls run | higher |

The shrink interaction: height = 0.8 + 3.2 × wax, so water at depth 2.2 is wadeable above ~44%
wax and lethal below it. Tune `waterDepth` against the Character heights to move that death line.
(`bodyRadius` 1.4, `rimHeight`/`wickHeight`/`cameraLift` in Config/Character are body/eye
structure — visual proportions, no difficulty axis.)

## How exposed does moving make me? — the drip trail

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `emitIntervalStuds` | DripTrail | 6 | Distance between drips | lower |
| `pointLifetimeSeconds` | DripTrail | 45 | How long your route stays readable/followable | higher |
| `maxPointsPerPlayer` | DripTrail | 40 | How far back you can be tracked | higher |
| `pointIntensity` / `pointRange` | DripTrail | 0.05 / 4 | Drip glow (drawn lure if raised) | higher |
| `dripPartSize` | DripTrail | 0.4 | Blob size (visual) | — |

## How brutal is the Basin? — the sacrifice ritual

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `baseWaxGranted` | Basin | 0.25 | Reference grant (pool rows override) | lower |
| `depthPenaltyPerFloor` | Basin | 0.85 | Exchange-rate decay: grant × this^(depth−1) | lower |
| `offersPerVisit` | Basin | 3 | Choices shown per visit | lower |
| `pool[].waxGranted` | Basin | 0.15–0.35 | Payment per specific sacrifice | lower |
| `pool[].weight` | Basin | 1 | Offer frequency (shifts which losses hurt) | — |
| `effects.maxBurnRateCapMultiplier` | Basin | 0.6 | How hard the brightness cap bites | lower |
| `effects.dodgeShortenMultiplier` | Basin | 0.5 | How much dodge the Basin takes | lower |

## Is it worth going deeper? — the brazier

Reward = wax × depthMultiplier × (1 + 0.25 × additional players) × rewardPerWaxUnit.

| Value | File | Default | Controls | Harder / deeper → |
|---|---|---|---|---|
| `depthMultipliers` | Brazier | {1,1.5,2.2,3,4,5,6.5,8} | Payout per floor | steeper = pushes deeper |
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

*(Profiles are live in the math; in-run pickups are not yet placed — see IMPLEMENTATION-NOTES.)*

## How big and long is a run? — floors, party, pacing

| Value | File | Default | Controls | Harder / longer → |
|---|---|---|---|---|
| `maxFloors` | Floors | 8 | Deepest floor reachable | higher |
| `roomsPerFloor` | Floors | {4,5,5,6,6,7,7,8} | Rooms per floor | higher |
| `threatBudgetPerFloor` | Floors | {1,2,2,3,3,4,4,5} | Threats per floor | higher |
| `hazardChancePerRoom` | Floors | 0.5 | Hazard roll per eligible room | higher |
| `roomModules[].weight` | Floors | 1–3 | Room mix (more Flooded = more water) | — |
| `geometry.*` | Floors | cell 44, walls 14/1, door 10×10, gap 80 | Physical scale of everything | bigger cells = longer treks |
| `caveDressing.*` | Floors | jitter 3, strips 3×0.9, boulders 2 (2–5) | Cosmetic cave irregularity + rock obstacles | more boulders = more cover |
| `targetRunLengthSeconds` | RunSettings | 900 | Pacing target (reference, not enforced) | higher |
| `partyCap` | RunSettings | 4 | Max players per run | — |
| `soloAllowed` | RunSettings | true | Solo runs permitted | — |
| `startCountdownSeconds` | RunSettings | 5 | Delay before descent starts | — |
| `restartDelaySeconds` | RunSettings | 15 | Downtime between runs | — |
| `tickRate` / `stateReplicationHz` | RunSettings | 10 / 10 | Sim and sync cadence (mechanical) | — |

## How forgiving is death? — snuff, relight, wisp

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `relightWaxCost` | Death | 0.15 | What the reviver personally pays | higher |
| `snuffStateDuration` | Death | 20 | Rescue window before a snuff turns terminal | lower |
| `relightRange` / `relightHoldSeconds` | Death | 8 / 1 | Reach and deliberation of the rescue | lower / higher |
| `selfRelightDelaySeconds` | Death | 1.5 | Commitment cost of a voluntary SNUFF | higher |
| `remainsWaxFraction` | Death | 0.5 | Wax pooled as remains on burnout (stub consumes) | lower |
| `wisp.lifetimeSeconds` | RunSettings | 120 | How long a burned-out player stays mobile | lower |
| `wisp.moveSpeed` | RunSettings | 14 | Wisp travel speed | lower |
| `wisp.lightRange` / `lightBrightness` | RunSettings | 6 / 0.4 | How much a dead friend still helps | lower |
| `wisp.bodySize` | RunSettings | 1.2 | Wisp sphere size (visual) | — |

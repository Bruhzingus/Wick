# TUNING — the feel surface

Every tunable value in the game, grouped by **the question you're answering when you reach for
it** — not by file. All gameplay tuning lives in `src/shared/Config/`. "Harder →" is the
direction that makes the game more punishing. Wax values are fractions of a full candle (0..1).
Change a value, let Rojo sync, play — no logic edits, ever.

---

## How long do I survive? — the burn economy

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `startingWax` | Wax | 1.0 | Wax a fresh candle begins with | lower |
| `maxWax` | Wax | 1.0 | Absolute wax ceiling | lower |
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
| Lurker (DarkHunter) | 8 / 18 / −1.0 / 0.05 | contactRadius 3, bodySize 3 |
| Stalker (DarkHunter) | 11 / 24 / −0.6 / 0.08 | contactRadius 3, bodySize 4 |
| Moth (Drawn) | 9 / 30 / +1.0 / 0.04 | contactRadius 3, bodySize 3 |
| Swarm (Drawn) | 6.5 / 22 / +0.7 / 0.10 | contactRadius 4, bodySize 5 |
| Hollow (DarkHunter) | 5.5 / 30 / −0.8 / 0.06 | contactRadius 3.5, bodySize 5 |
| Ash Moth (Drawn) | 8.5 / 38 / +1.2 / 0.025 | contactRadius 2.5, bodySize 2 |
| Snuffer (Drawn) | 5 / 26 / +0.75 / 0 | contactRadius 3, bodySize 4, **Snuff contact** |

Harder → higher speed/radius/damage; hunter `lightResponse` nearer 0 (harder to repel).

| Value | File | Default | Controls | Harder → |
|---|---|---|---|---|
| `behavior.huntLightThreshold` | Threats | 0.15 | How dark you must be before hunters take you | higher |
| `behavior.repelLightThreshold` | Threats | 0.45 | Light needed to drive a hunter back | higher |
| `behavior.repathIntervalSeconds` | Threats | 0.65 | Threat reaction time | lower |
| `behavior.wanderSpeedFraction` | Threats | 0.3 | Idle drift speed | higher |
| `behavior.wanderRadius` | Threats | 25 | Idle roam range from spawn | higher |
| `definitions.*.spawnWeightByDepth` | Threats | row-specific | Relative floor-by-floor likelihood; 0 disables a row at that depth | higher late weights = tougher deep mix |

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
| `spawnOffsetRadius` | Loot | 10 | Pickup scatter around room centres | higher = more searching |
| `pickupRange` / `pickupHoldSeconds` | Loot | 8 / 0.25 | Server collection reach and prompt commitment | lower / higher |

## How big and long is a run? — floors, party, pacing

| Value | File | Default | Controls | Harder / longer → |
|---|---|---|---|---|
| `maxFloors` | Floors | 10 | Planner ceiling; selected cave tier chooses the live run limit | higher |
| `roomsPerFloor` | Floors | {6,7,8,8,9,10,10,11,12,12} | Rooms per floor | higher |
| `threatBudgetPerFloor` | Floors | {1,1,1,2,2,2,2,3,3,3} | Threats per floor | higher |
| `hazardChancePerRoom` | Floors | 0.4 | Hazard roll per eligible room | higher |
| `roomModules[].weight` | Floors | 1–3 | Room mix (more Flooded = more water) | — |
| `geometry.*` | Floors | cell 52, walls 14/1, door 10×10, gap 80 | Physical scale of everything | bigger cells = longer treks |
| `caveDressing.*` | Floors | jitter 3, strips 3×0.9, boulders 2 (2–5) | Cosmetic cave irregularity + rock obstacles | more boulders = more cover |
| `targetRunLengthSeconds` | RunSettings | 1200 | Pacing target (reference, not enforced) | higher |
| `partyCap` | RunSettings | 4 | Max players per run | — |
| `soloAllowed` | RunSettings | true | Solo runs permitted | — |
| `startCountdownSeconds` | RunSettings | 5 | Delay before descent starts | — |
| `restartDelaySeconds` | RunSettings | 15 | Downtime between runs | — |
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

| Value | File | Default | Controls |
|---|---|---|---|
| `lowWax.threshold` / `urgentThreshold` | Feel | 0.25 / 0.10 | When the wax bar begins pulsing and changes to its urgent colour |
| `lowWax.pulseFrequencyHz` / colour blend | Feel | 1.6 Hz / 0.25–0.85 | Warning pulse speed and strength |
| `flameFlicker.*` | Feel | small local light | Cosmetic flame motion; draft and nearby-threat multipliers strengthen it |
| `draftWarning.*` / `waterWarning.*` | Feel | subtle cool grading | Local environmental warning tint; authoritative exposure still comes from the server |
| `dialSnap.*` | Feel | 0.12 s flash | Visual/audio acknowledgement when the brightness dial reaches a snap point |
| `threatWarning.radius` / `scanIntervalSeconds` | Feel | 30 / 0.25 s | Range and cadence for requesting the nearby-threat cue |
| `debug.showThreatLabels` | Feel | false | Restores grey-box threat names for tuning; keep false for horror playtests |
| `controls.*` | Feel | 1–4, Q, C, Shift | Single source for real keyboard bindings, touch button positions, and hotbar labels |
| `hotbar.*` | Feel | responsive two-row legend | Desktop/mobile placement, sizing, colours, and text bounds |

## Where do sound assets go? — audio cues

`Audio.cues` is the event registry consumed by `client/AudioCues`. Every `assetId` intentionally
defaults to an empty string, which is a safe no-op. Paste an approved numeric Roblox sound ID (or
`rbxassetid://...`) into a row to enable it; no controller edit is required.

Each row controls `volume`, `playbackSpeed`, `looped`, and `cooldownSeconds`. Registered events cover
dial snap, low wax, draft, water, nearby threats, every tool, movement, Basin, Brazier, snuff/death,
relighting, and floor entry. `Audio.enabled` is the global switch; `cleanupSeconds` is the
failed/unfinished one-shot cleanup fallback.

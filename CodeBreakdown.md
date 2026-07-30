# Code Breakdown — WICK

Use this document **before editing code**. It is a routing index: find the smallest set of files that owns the requested behaviour, read those files and their direct dependencies, then make the change. Do not scan the entire repository unless the change crosses systems.

`DESIGN.md` is the product source of truth. `ARCHITECTURE.md` contains non-negotiable engineering rules. `TUNING.md` is the human-facing value index. This document says where implementation ownership lives.

## Required workflow for LLMs and contributors

1. Read `DESIGN.md`, `ARCHITECTURE.md`, and this file before changing game behaviour.
2. Use **Change routing** to identify the owning files. Read the listed owner, its config/type/logic counterpart, and relevant direct dependencies.
3. Preserve boundaries: config is tunable data; `shared/Logic` is pure; server services are authoritative adapters; client controllers only render or request actions.
4. Update this document in the same change whenever responsibilities, routes, remotes, data shapes, services, controllers, configs, or extension paths materially change.
5. If a request conflicts with `DESIGN.md` or `ARCHITECTURE.md`, stop and flag it rather than implementing it.

## Runtime map

```
Client input/UI ──requests──> Net/Remotes ──> server services / PlayerState
                                             │
                                             ├─> shared/Logic (pure decisions)
                                             ├─> shared/Config (all tuning)
                                             └─> Character/Floor Instances

Server Heartbeat:
Elevators → RunOrchestrator → MovementSanity → DripTrail → Tools → Wax → Dripstone → Threats → Death → Spectators → Movement → Brazier
```

- `src/server/init.server.luau` owns boot and tick ordering. Change it only to wire a service or deliberately reorder simulation.
- `src/server/StudioTestRunner.server.luau` independently runs `shared/Tests` only in Studio; it never executes in published servers.
- `src/server/PartyLobbyService.luau` owns the public-lobby/reserved-server boundary; `RunOrchestrator` owns only an expedition after that handoff.
- `src/client/init.client.luau` starts all client controllers.
- `src/shared/Net/Remotes.luau` owns all remote names/payload shapes and is the only remote creator.
- `src/server/PlayerState.luau` is the only live per-player run-state store. `state.depth` is this
  expedition's floor ordinal; `PlayerState.globalDepth(state)` is the canonical difficulty depth and
  is what any scaling, payout, or progression read must use.
- `src/server/ActionFeedbackService.luau` publishes immediate accepted/rejected action feedback;
  `WaxService` republishes the same server-owned cooldown projection through `StateSync`.

## Change routing

| Change | Start here | Also inspect |
| --- | --- | --- |
| Game rules, scope, or player experience | `DESIGN.md` | `ARCHITECTURE.md` |
| Pure-rule test coverage or Studio test execution | `shared/Tests/` | `server/StudioTestRunner.server.luau`, target `Logic`/`Config` module |
| Tunable value or content row | matching `shared/Config/*.luau` | `TUNING.md`, consumer |
| Profile schema, loading, saving, or session locking | `shared/Interfaces/Persistence.luau` | `server/init.server.luau`, `wally.toml`, profile consumers |
| Cave tier definition, unlock threshold, difficulty, or payout | `shared/Config/CaveTiers.luau` | `Interfaces/CaveTiers`, `Interfaces/Persistence`, `server/PartyLobbyService`, `server/RunOrchestrator`, `server/BrazierService` |
| Lamp Network node list, costs, prerequisites, contract rows, wager curve, or rollback flags | `shared/Config/LampNetwork.luau` | `Logic/LampRules` (all interpretation), `Interfaces/LampNetwork` (currency + profile), `server/ShopService.purchaseLamp`, `server/LampHubService`, `server/LobbyRoomBuilder.buildLampLine`, `LAMP-NETWORK.md` |
| Lamp Network prerequisite/contract/wager RULES (pure, testable cold) | `shared/Logic/LampRules.luau` | `Interfaces/LampNetwork`, `server/LampHubService`, `Tests/LampRulesTests` |
| Buying a lamp node, or the atomic charge-and-grant | `shared/Interfaces/LampNetwork.luau` | `Interfaces/Persistence.applyTransaction`/`grantLampNode`, `server/ShopService`. The charge and the grant must stay in one yield-free block; a duplicate transaction must still grant |
| What a signed contract DOES to a run (tools, wax, Basin, paying depth, tether, void conditions) | `shared/Logic/ContractRules.luau` | `Config/LampNetwork` (the `effect` block on each row is the authority), `server/PlayerState.freshState`, `server/BasinService`, `server/ContractWatchService`, `server/ExtractionService`, `Logic/ExtractionValue`. Every rule must be enforced by the system that already owns what it takes away — never by a contract-shaped branch bolted alongside it |
| Enforcing a rule that can only be judged mid-run (currently only the tether) | `server/ContractWatchService.luau` | `Logic/ContractRules`, `server/ExtractionService.voidContract`, `server/PlayerState`. Decides nothing about money |
| Ringing the Signal Bell: who may, what it costs, the cooldown, the noise, who hears it | `server/SignalBellService.luau` | `Config/LampNetwork.bell`, `Config/Sound.emitters.SignalBell` (the radius the cave hears), `Logic/WaxAccounting` (`SignalBellCost`), `server/NoiseService`, `client/SignalBellController`. The bell is NOT a tool: no `Config/Tools` row, no hotbar slot, no threat interaction |
| The bell key, its spatial cue and its occluded ripple | `client/SignalBellController.luau` | `Config/Feel.controls.signalBellKey`, `Config/Audio.cues.SignalBell`, `RunEvent("bellRing")`. THE SOUND carries through rock; the ripple never does and emits no light |
| Deposit row definitions (Twin / Deep / Bright seam kinds) | `shared/Config/Mining.rows` | `Logic/MiningRules` (selection, per-row progress, burn gate), `Logic/FloorPlanner` (stamps `rowId` per placement), `server/MiningService` (honours strikes, yield, paid miners), `server/ExtractionService.grantForDeposit` |
| The Locked Store: which room is sealed, its curtain, its guaranteed stock | `Logic/FloorPlanner` (selection, curtain, stock) + `Logic/VineRules.roomMayBeSealed` (the dead-end proof) | `Config/LampNetwork.generation.lockedStore`, `VineRules.allRoomsReachable` (`exemptIndices`), `Tests/FloorPlannerTests`. The store is the ONLY room a curtain may fully seal and the ONLY vined room allowed a deposit; both exceptions rest on it being a dead end, so that requirement may never be relaxed |
| What a LIT lamp fixture does when its prompt is held | `server/LampHubService.luau` | `Interfaces/LampNetwork`, `server/PartyLobbyService` (routes the prompt, owns the toast), `server/init.server.luau` (injects notifier + party size). Never moves currency — that is ShopService's |
| Which lamps a given player sees burning | `client/LampNetworkController.luau` | `shared/LobbyVisualProtocol.lampHousingTag`, `LobbyState.ownedLampNodes`. Per-viewer by necessity: ownership is per-player and the hub is shared |
| Lobby party, ready/leader state, tier selection, or start flow | `server/ElevatorService.luau` | `server/PartyLobbyService.tryStart`/`canStart`, `Interfaces/Party`, `Config/LobbyRoom`, `client/ElevatorController`, `client/LobbyController` |
| Reserved-server teleport, teleport-data handoff, destination arrival body, or leader-start validation | `server/PartyLobbyService.luau` | `server/init.server.luau`, `server/RunOrchestrator`, `Config/Lobby`, `server/ElevatorService` (calls `tryStart`/`canStart`), `replicatedfirst/WickLoadingScreen.client.luau` (covers the transfer until a destination body exists) |
| Physical lobby geometry, shaft wall/perimeter-rib construction, local lighting, spawn point, shop placeholder, lamp-line fixtures, elevator alcoves, or signage | `server/LobbyRoomBuilder.luau` | `Config/LobbyRoom`, `Interfaces/CaveTiers`, `Interfaces/LampNetwork`, `shared/LobbyVisualProtocol`, `Config/Feel.controls` (controls-sign text) |
| The in-lobby build counter sign | `Config/Version.luau` | `server/LobbyRoomBuilder.buildVersionSign`, `Config/LobbyRoom.versionSignOffset/Width/Height`. Bump `Version.number` by one in the same change as every other edit |
| Elevator descent authority (rider capture, gate, ride-candle swap, timestamp, final car/rider transform) | `server/ElevatorService.luau` | `Config/LobbyRoom` (`rideDistance`/`rideShaftDepth`), `Config/RunSettings.startCountdownSeconds`, `server/CharacterService.spawnRideCandle`, `server/LobbyRoomBuilder` (tagged car models), `server/PartyLobbyService` (delays teleport until the ride completes) |
| Smooth elevator ride rendering (analytic car/rider interpolation, shudder, in-car readout) | `client/ElevatorController.luau` | `shared/LobbyVisualProtocol`, `Net/Remotes.RunEvent("elevatorRide")`, `client/CameraController.setElevatorOffset`, `Config/LobbyRoom` (distance/shake values) |
| Lobby avatar, non-draining elevator candle, or authoritative run candle | `server/CharacterService.luau` (`spawnLobby` / `spawnRideCandle` / `spawn`) | `shared/LobbyVisualProtocol.attributes.runBody`/`rideBody`, `server/ElevatorService`, `server/PartyLobbyService`, `server/RunOrchestrator.spawnRunner` |
| First-person vs. third-person camera and elevator camera offset | `client/CameraController.luau` | `shared/LobbyVisualProtocol.attributes.runBody`, `client/ElevatorController` — the ride-candle swap enters first person at elevator commitment |
| Lobby-only sprint | `client/LobbyMovementController.luau` | `Config/LobbyRoom` (speeds), `Config/Feel.controls.movement.Sprint` (binding), `client/MovementController` (owns the same key during a run) |
| Cross-server deepest-floor standings, same-server score overlay, or immediate board refresh | `shared/Interfaces/Leaderboard.luau` (store) / `server/LeaderboardService.luau` (board) | `server/BrazierService` + `server/DeathService` (submit and request refresh), `server/LobbyRoomBuilder.leaderboardLabel`, `Config/LobbyRoom` (rows/refresh) |
| Uncapped depth scaling, depth bands, per-floor seed derivation, or "how deep is this" | `Logic/DepthRules.luau` | `Config/Depth`, `Config/CaveTiers.startDepth`, `Logic/FloorPlanner`, `Logic/ExtractionValue`, `server/RunOrchestrator`, `server/PlayerState.globalDepth` |
| An object spawning inside, under, or on top of the cave floor (loot, deposits) | `server/SurfaceProbe.luau` | `Config/Floors.geometry.placementProbe`, `server/LootService`, `server/MiningService`, `Logic/GroundGeometry` (the planned surface the probe corrects) |
| Mining: deposit progress/wear, LOS and burn validation, bounded click-clock scoring, strike sequence, shared impact event, depletion, or run count | `server/MiningService.luau` | `Logic/MiningRules` (every rule, including `resolveInputClock`), `Config/Mining`, `shared/MiningVisualProtocol`, `NewModelsAndObjects/WaxDeposit`, `client/MiningController`, `Net/Remotes.MineStrike` / `RunEvent("mineImpact")`, `Config/Security.remoteRateLimits.MineStrike` |
| Mining target selection, pending-input latches, stance/remote coordination, movement release, or teammate impact routing | `client/MiningController.luau` | `Logic/MiningRules.sweepPhase`/`bandCenter`, `client/MiningHUD`, `client/MiningViewmodelController`, `client/MiningWorldPresentation`, `Net/Remotes.MineState` + `RunEvent("mineImpact")` + `StateEntry.rawWax` |
| Mining fracture rail, row-aware prompt, rejection/result copy, touch-button styling, or carried-Raw-Wax readout | `client/MiningHUD.luau` | `Config/Mining.qte`/`timing`/`feedback`, `client/UITheme`, `client/MiningController` |
| Seam-directed pickaxe model, draw/stow, outcome-specific swing/rebound, aim bias, or trail | `client/MiningViewmodelController.luau` | `Config/Mining.pickaxe`, `client/MiningController`; cosmetic only, with no remote or outcome authority |
| Mining proximity ember, wear-coupled seam glow, spatial grade/break layers, contact chips, or shared/private break deduplication | `client/MiningWorldPresentation.luau` | `Config/Mining.visual.glow`/`feedback`, `Config/Audio.cues.Mine*`, `shared/MiningVisualProtocol`, `client/AudioCues`, `client/MiningController` |
| Raw Wax cargo: per-depth grant, cap, loss/forfeit, party ledger, extraction, or persistence payout | `server/ExtractionService.luau` | `Config/Extraction`, `Logic/CargoRules`, `Logic/ExtractionValue`, `server/MiningService` (calls `grantForDeposit`), `server/BrazierService`, `server/DeathService`, `server/RunOrchestrator`, `Types/Mining.RawWaxCargo`/`RawWaxRun`, `Tests/CargoRulesTests` |
| Where deposits may appear | `Logic/FloorPlanner.planDeposits` | `Config/Mining.placement`, `Logic/MiningRules.targetCount`, `Tests/FloorPlannerTests` (the protected-route invariants) |
| What the cave can hear, or making an action noisy | `Config/Sound.luau` (row) + one `server/NoiseService.emit` call | `Logic/SoundField`, `Config/Threats` `hearing` rows, `Logic/ThreatBrain` (Investigate), `server/ThreatService` (protected-room filtering) |
| A threat reacting to sound | `Config/Threats.definitions[id].hearing` | `Logic/ThreatBrain.thinkInvestigate`, `Logic/SoundField.audibleFor`. Never add an `if mining` branch to a threat |
| Wax drain, burnout, shrink, state sync | `server/WaxService.luau` | `Logic/WaxDrain`, `Logic/WaxAccounting`, `Logic/CandleGeometry`, `Config/Wax`, `Config/Character`, `PlayerState`, `DeathService` |
| Any change to a player's wax, or why a run ran out of it | `Logic/WaxAccounting.luau` | `server/WaxService` (the only path that can also trigger burnout), `Types/Wax.WaxSource`, `server/RunSummaryService`, `PlayerState.waxLedger` |
| Development run summary ("why did this run end?") | `server/RunSummaryService.luau` | `Logic/WaxAccounting`, `server/Telemetry`, `DeathService`, `BrazierService`, `RunOrchestrator` |
| Dial, drag request cadence, reconciliation, or visible/threat-output curve | `server/DialService.luau` / `client/DialController.luau` | `Logic/BrightnessMap`, `Config/Light`, `Config/Feel.dialInput`, `WaxService`, `LightSources` |
| Candle light fades, deterministic combustion flicker/warmth, spherical shadow accent, emitter stabilization, bounce/bloom/grading, shadow softness/range, or multiplayer stability | `client/CandleLightController.luau` / `Logic/FlameFlicker.luau` | `server/CharacterService`, `server/FloorBuilder`, `shared/NewModelsAndObjects/CaveKit`, `shared/LightVisualProtocol`, `Config/Light.rendering`, `client/FeelController`, `default.project.json`. An emitter may declare `LightVisualProtocol.attributes.color` to opt out of the configured flame colour and the warm flicker; only the ghost candle does, and `Config/Light.rendering` stays the answer for every burning wick |
| Candle rig, body, camera, visual movement, or restart camera ownership | `server/CharacterService.luau` / `client/CameraController.luau` | `Config/Character`, `Logic/CandleGeometry`, `server/RunOrchestrator`, `RunEvent` floor handoff |
| What a body collides with (living candle vs ghost) | `server/CharacterService.init` (collision groups) | `Config/Spectator`. `WickSpectator` is non-collidable with `WickRunner` and with itself, and collidable with everything else, so a ghost is stopped by rock and can never block a doorway the party needs |
| Hop height, sprint, or movement input | `server/MovementService.luau` / `server/CharacterService.luau` | `client/MovementController`, `Config/Movement`, `Logic/WaxDrain` |
| Sprint FOV, peripheral strain, heat shimmer, camera instability, or sprint flame feedback | `client/SprintFeedbackController.luau` | `client/MovementController`, `client/FeelController`, `Config/Feel`, `server/CharacterService`, `Config/Character` |
| Tool stats, grounded-Decoy placement/visuals, or effect | `Config/Tools.luau` | `server/ToolService`, `Logic/ToolRules`, `Types/Tool`, `client/ToolController`, `LightSources` |
| Tool validation, grounded Decoy resolution, decoys, flare, or Cup | `server/ToolService.luau` | `Logic/ToolRules`, `ActionFeedbackService`, `MovementService`, `Net/Remotes` |
| Tool/movement cooldown projection, accepted/rejected feedback, hotbar bars, or active markers | `Logic/CooldownRules.luau` / `server/ActionFeedbackService.luau` | `server/ToolService`, `server/MovementService`, `server/WaxService`, `Net/Remotes.ActionFeedback`, `StateEntry.actionCooldowns`/`isFlaring`/`isCupping`, `client/HotbarController`, `Config/Feel.hotbar` |
| In-run wax/charge/Match loot, wall-pocket planning, water-safe placement, exact built-surface placement, pickup art, or pickup behaviour | `Config/Loot.luau` | `Logic/FloorPlanner`, `Logic/GroundGeometry`, `Logic/LootRules`, `NewModelsAndObjects/LootPickup`, `server/LootService`, `PlayerState`, `ToolService` |
| Threat stats/content or depth spawn weights | `Config/Threats.luau` | `Config/Floors` allow-lists, `Logic/FloorPlanner` |
| Threat model geometry, local creature animation, or visual culling | `client/ThreatVisualController.luau` / `shared/NewModelsAndObjects/` | `server/ThreatVisualProxy`, `server/ThreatService`, `Config/Threats.visuals.procedural`, `Config/Feel.debug` |
| Creature attack animation/audio, victim-only hit sting, or how often a threat in contact visibly swings | `shared/NewModelsAndObjects/DarkCrawler.luau` (`strike`) / `client/ThreatVisualController.luau` | `ThreatVisualProtocol.attributes.attack`/`attackVictim`, `server/ThreatVisualProxy.signalAttack`, `server/ThreatService.applyContact`, `Config/Threats.visuals.procedural.attackPulseIntervalSeconds`/`attackAudio`, `Config/Audio.cues.*Attack`/`ThreatHit` |
| Threat AI, crawler light bands/retreat memory, room/pool routing, ground-following, ceiling-ambush dive/return, movement, or contact | `Logic/ThreatBrain.luau` / `Logic/RoomNavigation.luau` | `server/ThreatService`, `Logic/LightField`, `server/LightSources`, `Config/Threats.behavior`, `Config/Threats.definitions.*.ambush`, `Logic/FloorPlanner`, `Config/Floors.terrain` |
| Threat-visible light source | `server/LightSources.luau` | `Logic/LightField`, `WaxService`, `ToolService`, `RemainsService` |
| Localized water pools, wading, water lethality, or hazard animation | `server/HazardService.luau` / `server/FloorBuilder.luau` | `Logic/FloorPlanner`, `Logic/HazardRules`, `Config/Hazards`, `WaxService`, `client/EnvironmentAnimationController` |
| How often water appears at all, or how many pools a wet floor carries | `Config/Floors.floodedFloorChance` / `.floodedRoomsPerFloor` | `Logic/FloorPlanner` (`weightedModule`, `guaranteeDryRoute`, `enforceFloodedBudget`), `Config/Floors.roomModules` weights (kind of pool only) |
| Unstable-dripstone count curve, eligibility, variant, trigger, fall, impact, wax loss, low-wax snuff, or first-fall tutorial | `Logic/DripstoneRules.luau` / `server/DripstoneService.luau` | `Config/Hazards.unstableDripstone`, `Config/Feel.tutorialHints`, `Logic/FloorPlanner`, `server/FloorBuilder`, `WaxService`, `DeathService`, `client/HintController`, `LightSources`, `Types/World.DripstonePlacement` |
| Dangerous-dripstone model, fracture tell, warning/fall animation, dust/debris, shake, or impact grading | `shared/NewModelsAndObjects/UnstableDripstone.luau` / `client/DripstoneController.luau` | `shared/DripstoneVisualProtocol`, `Logic/DripstoneRules`, `Config/Hazards.unstableDripstone`, `Config/Audio`, `Net/Remotes.RunEvent` |
| Burnable vine curtains: which doorways may be gated, the light threshold that ignites one, ignite/burn time, how far fire spreads between curtains, or curtain art | `Config/Vines.luau` / `Logic/VineRules.luau` / `server/VineService.luau` | `Logic/FloorPlanner`, `server/FloorBuilder`, `Config/Light.maxBurnRate`, `Config/Basin.effects.maxBurnRateCapMultiplier`, `Types/World.VinePlacement`, `Net/Remotes.RunEvent` |
| Ashamed Lurker: which arches can host one, depth gating, trip lane, grab, stare-to-clear, or relocation | `Config/AshamedLurker.luau` / `Logic/AshamedLurkerRules.luau` / `server/AshamedLurkerService.luau` | `Logic/FloorPlanner` (`planLurkers`), `server/FloorBuilder` (proxy + `LurkerSite`), `shared/AshamedLurkerVisualProtocol`, `client/AshamedLurkerController`, `NewModelsAndObjects/AshamedLurker`, `Net/Remotes.LurkerGaze`, `Config/Security.remoteRateLimits.LurkerGaze`, `WaxService.drainExternal`, `Types/World.LurkerPlacement` |
| Stone Warden room selection, spawn, pathing, stun, or hazard interaction | `Config/StoneWarden.luau` / `Logic/FloorPlanner.luau` / `server/StoneWardenService.luau` / `server/StoneWardenSystem/` | `server/WardenRegistry.luau`, `server/DripstoneService`, `Config/Hazards.unstableDripstone.wardenStunSeconds`, `RunOrchestrator`, `Types/World.WardenPlacement` |
| Cave moss on walls and around waterlines | `Config/Floors.caveMoss` | `server/FloorBuilder`, `Config/Hazards.waterPool.shoreMoss*` |
| Snuffing, teammate relighting, solo Match self-relighting, burnout, death results | `server/DeathService.luau` | `Config/Death`, `Config/Loot`, `Logic/LootRules`, `client/RelightPromptController`, `WaxService`, `CharacterService`, `Interfaces/Remains`, `server/SpectatorService` (owns everything after the death) |
| What a terminally dead player IS: the ghost candle's body, its walk speed, its almost-nothing light, following a teammate, or the ghost-only footfall trail | `Config/Spectator.luau` | `Logic/SpectatorRules` (every decision), `server/SpectatorService` (authority), `server/CharacterService.spawnSpectator` (the body + collision groups), `client/SpectatorController` (marks, readout, key), `Net/Remotes.SpectatorAction`/`SpectatorState`, `Config/Feel.controls.spectatorFollowKey`, `Tests/SpectatorRulesTests`. Two rules may never be relaxed: a ghost never enters `server/LightSources` (nothing in the cave may perceive it), and trail samples are sent ONLY to players who are dead |
| Where a ghost may be put when it follows | `Logic/SpectatorRules.anchorPosition` + `server/SpectatorService.anchorTo` | The anchor is always a living teammate's own feet, so a ghost can only ever appear somewhere a living player already is. Never offset it sideways (rock) and never let it lead the party |
| Session remains storage, placement, recovery, or light | `server/RemainsService.luau` | `Interfaces/Remains`, `Config/Remains`, `DeathService`, `LightSources`, `RunOrchestrator` |
| End-of-run screen, death debug, replay, whole-party return, or a resolved survivor's early main-lobby extraction/party-bonus forfeit | `client/ResultsText.luau` / `server/RunOrchestrator.luau` | `server/DeathService`, `server/ExtractionService.forfeitPartyBonus`, `server/PartyLobbyService.returnPlayerToMainLobby`, `Net/Remotes`, `server/SpectatorService` (the "WATCH THE PARTY" dismiss is only offered while `partyStillInside`, and the card returns by itself on `runResolved`) |
| Non-glowing wax-drop trails or hunter breadcrumbs | `server/DripTrailService.luau` | `Config/DripTrail`, `ThreatService`, `Logic/ThreatBrain` |
| Basin offers, flat grant band, sacrifice choices/modifiers, or permanent vision costs | `server/BasinService.luau` | `Logic/SacrificeRules`, `Config/Basin`, `Types/Sacrifice`, `server/WaxService` (`StateSync`), `client/BasinPrompt`, `client/FeelController`, `PlayerState` |
| Brazier preview, payout, group bonus | `server/BrazierService.luau` | `Logic/ExtractionValue`, `Logic/CargoRules`, `Config/Brazier`, `Config/Extraction`, `server/ExtractionService`, `Interfaces/Persistence`, `client/ResultsText` |
| Floor topology, room selection, deterministic separated threat/loot offsets, Warden branch, ceiling eligibility, guaranteed ground patches, pool footprints, or dangerous-dripstone placement | `Logic/FloorPlanner.luau` | `Config/Floors`, `Config/Threats`, `Config/Hazards`, `Config/StoneWarden`, `Logic/PlacementReservations`, `Logic/DripstoneRules`, `Logic/GroundGeometry`, `Logic/RoofGeometry`, `Logic/DoorwayGeometry`, `Types/World` |
| Cave geometry, recessed floors, CaveKit formations, gameplay dressing reservations, Lurker-arch protection, per-edge doorway sizing, hazard zones, or exact room-surface handoff | `server/FloorBuilder.luau` | `server/ThreatService`, `shared/NewModelsAndObjects/CaveKit`, `shared/NewModelsAndObjects/UnstableDripstone`, `Config/Floors.geometry`, `.caveDressing`, `.terrain`, `.roof`, `Logic/PlacementReservations`, `Config/Threats`, `Config/Hazards`, `HazardService`, `Logic/FloorPlanner`, `Logic/GroundGeometry`, `Logic/RoofGeometry` |
| Cave-floor height field, swells, doorway lanes, pools, or a gameplay placement's exact local ground | `Logic/GroundGeometry.luau` | `Config/Floors`, `Logic/DoorwayGeometry`, `Logic/FloorPlanner`, `server/FloorBuilder` |
| Inverted Terrain roof shape, relief seed, edge blending, rock thickness, minimum clearance, or exact underside height | `Logic/RoofGeometry.luau` / `server/FloorBuilder.luau` | `Config/Floors.roof`, `Logic/GroundGeometry`, `Logic/FloorPlanner`, `shared/NewModelsAndObjects/CaveKit` |
| Expedition countdown, runner inclusion, separated multiplayer entry slots, uncapped on-demand floor construction, descent, replay, lobby return, or reset | `server/RunOrchestrator.luau` / `Logic/EntrySpawnRules.luau` | `server/PartyLobbyService`, `Config/RunSettings`, `Config/Character`, `Config/Floors`, `FloorPlanner`, `FloorBuilder`, service `reset`s |
| Remote rate limits or finite-payload validation | `server/RequestGuard.luau` | `Logic/TokenBucket`, `Config/Security`, every inbound remote handler |
| Impossible-movement correction | `server/MovementSanityService.luau` | `Config/Security`, `Config/Movement`, approved burst credits in `MovementService`, authorized teleports in `RunOrchestrator`, `CharacterService` |
| Prototype server-log telemetry | `server/Telemetry.luau` | `Config/Security`, emitting service |
| HUD or run messages | relevant file in `src/client/` | `Net/Remotes`; `ResultsText` handles `RunEvent`, `WaxBar` handles `StateSync`, `HotbarController` handles `ActionFeedback` plus cooldown reconciliation |
| Cursor capture, clickable UI cursor release, or native Roblox menu interaction | `client/CursorController.luau` | the UI controller that opens the screen, `WickInExpedition`, `client/CameraController` |
| In-run local presentation settings (mouse sensitivity / audio volume) | `client/SettingsController.luau` | `client/CursorController`, `client/AudioCues`, `WickInExpedition` |
| Lobby UI, party list, ready button, or tier buttons | `client/LobbyController.luau` | `server/PartyLobbyService`, `Interfaces/CaveTiers`, `Net/Remotes` |
| Gameplay input enabled/disabled across lobby/run transitions | `client/LobbyController.luau` | `client/DialController`, `client/MovementController`, `client/ToolController`, `WickInExpedition` player attribute |
| Low-wax, water grading, or nearby-threat cue and flicker context | `client/FeelController.luau` / `client/WaxBar.luau` | `Config/Feel`, `client/CandleLightController`, `client/AudioCues`, `Net/Remotes`, `WaxService` |
| Harmless cave one-shot timing, silence probability, anti-repeat history, focus-audio gating, surface/water eligibility, or the five natural sound families | `client/AmbientCaveDirector.luau` | `Config/Feel.ambientCave`, `Config/Audio.cues.Cave*`, `client/AudioCues.isBusQuiet`, `AmbientRockfallController`, `AmbientWaterDripController` |
| Ambient loose-rock placement/roll or ceiling-drip placement (presentation only; no timers) | `client/AmbientRockfallController.luau` / `client/AmbientWaterDripController.luau` | `Config/Feel.ambientRockfall` / `.ambientWaterDrip`, `client/AmbientCaveDirector`, `NewModelsAndObjects/CaveKit.looseRock` |
| First-three-floor threat, dripstone, water, or gust teaching hints | `client/HintController.luau` | `server/ThreatService`, `server/DripstoneService`, `Config/Feel.tutorialHints`, `Net/Remotes.TutorialHint`, `WaxService` (`StateSync`) |
| Sound cue, mix bus, variation, voice budget, cave processing, obstruction filter, ducking, rolloff, preload failure handling, loop, or cooldown | `Config/Audio.luau` | `client/AudioCues`, `client/MusicController`, `Tests/AudioConfigTests`, and the controller that requests the named cue |
| VoidFly buzz timing, proximity, or cave-wall suppression | `client/ThreatVisualController.luau` | `Config/Threats.visuals.procedural.ceilingFlyBuzz`, `Config/Audio.cues.FlyBuzz`, `client/AudioCues` |
| Menu music, cave playlist order/delays, or music fades | `client/MusicController.luau` | `Config/Audio.music`, `client/AudioCues`, `WickInExpedition` |
| Keyboard/touch binding or visible control hotbar | `Config/Feel.luau` | `client/HotbarController`, `ToolController`, `MovementController` |
| Shared UI palette, fonts, motion presets, or the composited WICK wordmark/candle-glyph widgets | `client/UITheme.luau` | every themed UI controller (`LobbyController`, `BasinPrompt`, `ResultsText`, `SettingsController`, `WaxBar`, `HotbarController`); `replicatedfirst/WickLoadingScreen.client.luau` duplicates the wordmark/glyph inline and must be kept in sync by hand |
| World darkness / Lighting setup at runtime, or the uncapped-floor falling-part kill-plane setting | `server/EnvironmentSetup.luau` / `default.project.json` | `default.project.json` owns Studio-edit-mode Lighting/Atmosphere defaults and disables `Workspace.FallHeightEnabled`; floors stack below Y=-500 and must never inherit Roblox's default cleanup boundary |
| Earliest-possible boot/loading screen | `replicatedfirst/WickLoadingScreen.client.luau` | `client/UITheme.luau` (the module it duplicates, since ReplicatedFirst cannot require `ReplicatedStorage.Shared` this early) |
| Remote contract | `shared/Net/Remotes.luau` | every sender and receiver |
| Domain data shape | matching `shared/Types/*.luau` | `Types/init.luau`, config and consumers |
| Lineage stub or future carryover design | `shared/Interfaces/Lineage.luau` | `DESIGN.md`, `Interfaces/init.luau`; add no consumer until the design is settled |

## Directory ownership

### `src/shared/Config/` — tuning and content data

Each file owns one data domain; `Config/init.luau` aggregates them. Add values and generic content here, not behaviour branches.

- `Wax`, `WaxTypes`: candle economy and burn profiles.
- `Light`: dial limits, separate visible/threat-field light-curve endpoints, and client candle
  rendering/fade/flicker tuning.
- `Movement`: walk/run speed, low terrain-recovery hop power, action costs/cooldowns, and drain thresholds.
- `Character`: candle geometry and rig proportions.
- `Tools`, `Threats`, `Hazards`, `Loot`: generic-system content and tuning. `Tools` also owns
  authoritative grounded-Decoy probe bounds and its miniature decoy presentation; `Hazards` owns
  unstable-dripstone scaling, safety caps, three data-driven variants, fall/light suppression,
  and impact presentation values.
- `AshamedLurker`: the deep-floor arch creature — depth gate, per-floor budget, the doorway size and
  clear-lane window its placement must satisfy, trip/grab volumes and wax cost, stare validation,
  how long a shamed one stays away, and its presentation/scare values.
- `StoneWarden`: encounter depth/chance, planner-only room identity and offsets, protected pad size,
  emergence/chase timing, and movement speed.
- `Extraction`: the authoritative Raw Wax economy — units per deposit, cargo cap, per-depth value,
  party bonus, contracts, disconnect/forfeit rules, and persistence-facing payout boundaries.
- `Mining`: Standard/Twin/Deep/Bright deposit rows, clean-strike counts, helper payout limits,
  brightness gates, reach/LOS, bounded input rewind, timing bands, movement commitment, placement
  safety, seam/pickaxe presentation, continuous strike-rail layout, and impact presentation.
- `Sound`: the noise-emitter registry (loudness / radius / decay per event kind) for the second
  perception field. Who *listens* is a `hearing` block on a `Threats` row, not a value here.
- `DripTrail`, `Basin`, `Brazier`: respective system values.
- `Remains`: session-pool storage bounds, pickup placement, and light values.
- `Depth`: the uncapped canonical depth model's authored-table range, internal bands, and bounded
  past-authored scaling curves.
- `Floors`: planning/tool batch size, chain/loop topology bias, room modules, spawn budgets, and
  geometry dimensions. Its per-floor tables are indexed by GLOBAL depth, not expedition ordinal.
- `RunSettings`, `Death`: run timing/party and revival values.
- `Spectator`: the ghost candle a terminally dead player becomes — body/transparency/speed, the faint
  light and when it expires, follow grace/leash/cooldown, and the ghost-only footfall trail.
- `CaveTiers`, `Lobby`, `Security`: durable-access tier rows, lobby/teleport retry values, and
  server trust-boundary tuning.
- `LobbyRoom`: the static physical hub's geometry (room shell, spawn point/spread, shop placeholder,
  boards), local lamp range/brightness, elevator-to-tier mapping/zone radius, descent-ride travel
  and shaft depth/perimeter-rib spacing, thickness, and outset, lobby-only movement speeds, and
  board copy (welcome/goal and how-to-play text; the controls panel is generated from
  `Feel.controls` instead of duplicated here).
- `Threats.visuals.procedural`: proxy offsets, cosmetic state cadence, attack-beat pacing, client
  culling, and the emergency grey-box visual fallback.
- `Feel`, `Audio`: cosmetic feedback, shared control bindings, hotbar cooldown/active/denial
  presentation, debug-label gating, one ambient-cave scheduler, cue registry, nested mix buses,
  variation/polyphony, reverb/EQ/occlusion, and Focus-driven ducking.

### `src/shared/Logic/` — pure rules (no Roblox Instances)

- `CandleGeometry`: wax-to-body/flame geometry.
- `DepthRules`: the canonical depth model. `globalDepth = startDepth + localFloor - 1`, input
  validation (depth 0/negative/NaN/infinite/fractional are rejected, never clamped), uncapped valid
  ordinals, internal depth bands, bounded threat/hazard/room/reward scaling curves, and the stable
  per-floor seed derived from (run seed, cave tier, global depth). No gameplay service may define a
  depth curve of its own.
- `WaxDrain`: recurring drain pipeline (`breakdown` attributes it by source; `perSecond` sums it)
  and movement-mode calculation.
- `WaxAccounting`: every authoritative wax mutation plus its per-run ledger. A spend can only
  remove and a grant can only add, whatever amount or reason is passed, so no call site can mint
  wax. Reasons come from the closed `Types/Wax.WaxSource` set; an unknown one records as `Other`.
- `BrightnessMap`: burn rate to light values.
- `FlameFlicker`: deterministic owner-seeded, layered combustion brightness/warmth signal; it
  operates only on cosmetic renderer targets and never changes gameplay light.
- `LightField`: shared light intensity (including teammate illumination), Drawn-attractor queries,
  the DESIGN-mandated dark-hunter perception filter (Decoy decoys are ignored), and explicit
  panic-light lookup so only Flare forces retreat.
- `ToolRules`: generic activation validation plus pure horizontal Decoy clamping, parabolic-arc
  sampling, and surface-slope rules.
- `CooldownRules`: read-only `forAction`/`snapshot` projection of server-owned tool cooldowns for
  presentation.
- `EntrySpawnRules`: stable, collider-separated party slots inside the entry room's guaranteed-clear
  central footprint.
- `LootRules`: wax-profile replacement, free-tool-charge awards, and Match self-relight charges.
- `SoundField`: the second perception field. Decaying noise events, summed perceived loudness at a
  point (distance falloff × time decay, so repeated noises overlap and ADD), and the curiosity check
  a `hearing` profile runs. Returns a PLACE, never a player.
- `CargoRules`: pure Raw Wax cargo grant/clear/copy/value-bucket operations. Integer units, origin
  depth validated through `DepthRules`, a hard cap, and no conversion into living Wax.
- `MiningRules`: the timing sweep → accuracy band, the per-strike wandering band centre
  (`bandCenter`, deterministic from deposit id + strike index so server scoring and client drawing
  cannot disagree), bounded shared-click conversion (`resolveInputClock`), progress per band, row
  selection, brightness/LOS validation, which noise row a swing emits,
  and two separate validation passes — `canBeginStrike` when the stance opens and
  `canResolveStrike` on every strike and every tick it is held, because the world moves while
  somebody stands at a rock.
- `ThreatBrain`: generic roaming, dark-hunter low-light hunt / view-aware middle-band sneak /
  watched-spacing / retreat bands, territorial-ambush
  decisions, curiosity toward heard noise (ranked below every prey read and above the drip trail),
  movement, and staged-contact counting.
- `RoomNavigation`: reciprocal doorway graph, one-doorway waypoints, localized-pool detours,
  room-interior clamps, and fail-closed Basin exclusion.
- `AshamedLurkerRules`: which arches can host one, where its lane, reach and face sit inside a given
  opening, whether a measured speed and position trip it, whether the delayed grab connects, and
  whether a reported camera is a genuine stare. `clearLaneWidth`/`isPlacementAllowed` are THE
  guarantee that an occupied arch is still a route — planner, builder, server and client all read
  them rather than repeating the geometry.
- `HazardRules`: water decisions.
- `DripstoneRules`: unstable variant lookup, floor target curve, analytic fall, impact footprint,
  conservative silhouette extent, and temporary light-suppression math.
- `GroundGeometry`: deterministic cave-floor field, including actual off-centre doorway lanes,
  planned swells, and water bowls, shared by planning and Terrain construction.
- `RoofGeometry`: deterministic inverted-roof field, relief, and exact clearance-clamped underside
  sampling shared by planning and Terrain construction.
- `SacrificeRules`: offers, grants, modifiers.
- `ExtractionValue`: what a bag of Raw Wax is worth, as a breakdown for display. Replaced `RewardMath`
  when Phase 8 removed the Living Wax payout.
- `CargoRules`: the five cargo verbs — grant, clear, split, merge, take. Conservation is the invariant.
- `LampRules`: Lamp Network prerequisites, contract availability, and wager arithmetic.
- `SpectatorRules`: the ghost candle's rules — who is a ghost, who it may follow, when a living
  runner's footfall is worth recording, how a mark fades and expires, the follow cycle (last teammate
  → free roam, never a wrap), when a ghost must be pulled back, and where to. `anchorPosition` is the
  guarantee that a ghost only ever appears where a living player is standing; planner, server and
  client all read these rather than repeating the arithmetic.
- `FloorPlanner`: seeded floor-plan generation from a `PlanRequest` (`globalDepth` drives every
  content curve and geometry seed; `localFloor` is only the expedition ordinal). Each floor of a run
  gets its own seed from `DepthRules.getFloorSeed`, so a floor is reproducible from
  (run seed, tier, global depth) alone rather than from how many floors preceded it. It also owns
  main-chain-biased assembly, loop-seeking placement, guaranteed available loop connections,
  guaranteed dry critical route,
  deterministic pool placement, mutually separated gameplay footprints, an optional planner-owned
  Stone Warden encounter branch, collidable ground-patch placement, protected unstable-
  dripstone placement, and each room's planned `ceilingHeight` (wide per-room roll) which biases
  threat spawns — tall rooms favour the Drawn moth family, low rooms favour the ceiling-diving
  VoidFly. `RoomPlacement.ceilingHeight` is read by `FloorBuilder`, `RoofGeometry`, and dripstone
  eligibility; add it wherever a room is built. `ThreatSpawn.offset` carries deterministic XZ into
  both authoritative spawning and FloorBuilder's ambush decoration reservation. `FloorPlan.dripstones` carries deterministic XZ,
  variant, and visual seed; planner and builder resolve Y from the same GroundGeometry/RoofGeometry
  fields, while generated model bounds determine the final shallow impact embed.
- `DoorwayGeometry`: deterministic per-shared-edge doorway width/height/offset. One source of truth
  so `FloorBuilder` (cuts the opening) and `RoomNavigation` (aims threats through it) always agree.
- `TokenBucket`: deterministic per-player request-throttle math.

### `src/shared/NewModelsAndObjects/` — procedural creature & cave presentation

Luau builders, not imported mesh assets — Rojo maps this directory into
`ReplicatedStorage.Shared.NewModelsAndObjects`. `server/ThreatVisualProxy` replicates one invisible
anchored Part plus cosmetic attributes per threat (`ThreatVisualProtocol`); `client/ThreatVisualController`
builds the detailed body locally around that proxy, animates it, and culls it. Creature `step()`
functions are presentation only, and creature models never drain wax — `Config/Threats` and
`ThreatService` own every cost. Default visual mapping: `DarkHunter` category → `DarkCrawler`;
`Drawn` category → `CaveMoth`; `visualStyle = "Bug"` → `CeilingFly`. The emergency grey-box fallback
is `Config.Threats.visuals.procedural.enabled = false`.

- `CaveKit`: `server/FloorBuilder` calls it with deterministic seeds for cave dressing; dressing
  never decides topology, hazards, safe routes, or interaction-pad placement.
- `UnstableDripstone`: a procedural environmental model builder, not a creature. Needle/Fork/Hammer
  are data rows under `Config.Hazards.unstableDripstone.variants` sharing one behavior system and
  one warning language (asymmetric lean, dry near-black fractured collar, sparse dust, then a
  committed wobble/fracture). The formation is anchored and collision/query/touch-neutral;
  `DripstoneService` selects triggers/victims from server-sampled positions and every client derives
  the vertical analytic fall from replicated state/timestamps. No glow, billboard UI, enemy labels,
  AI, or collision damage belongs in this builder. Audio asset IDs `9125929705` (fracture) and
  `9118609396` (impact) belong in `Config/Audio`, never in these builders.
- `AshamedLurker`: the arch creature's body, built LOCALLY by `client/AshamedLurkerController` around
  the server's one invisible proxy part (same split as the threat proxies). Its whole geometry is
  derived from the doorway it occupies and its face is placed by `Logic/AshamedLurkerRules.facePosition`,
  the same function the server validates a stare against, so the visible head and the checked point
  cannot drift. Poses are non-compounding (`PartKit.Joint.base`). No gameplay state lives here.
- `LootPickup`: diegetic wax/flare/decoy/Match pickup models, server-built by `LootService`.
- `DarkCrawler`, `CaveMoth`, `CeilingFly`: each owns its own hardcoded palette/eye-glow constants
  (e.g. `CaveMoth`'s faint yellow attraction-driven eyes, `DarkCrawler`'s crimson idle/locked eyes)
  independently of `Config.Threats.visuals.darkHunter`/`.drawn` — those Config rows tune the
  emergency grey-box fallback body, not the detailed procedural one. Keep that split in mind before
  assuming a Config edit changes what players actually see with `visuals.procedural.enabled = true`
  (the default).
- Attack animation is a one-way cosmetic echo of contact the server has already resolved. Wherever
  `ThreatService.applyContact` actually lands an effect it calls `ThreatVisualProxy.signalAttack`,
  which paces beats by `Threats.visuals.procedural.attackPulseIntervalSeconds` and bumps the
  `ThreatVisualProtocol.attributes.attack` counter after writing `attackVictim`;
  `ThreatVisualController` plays one spatial creature cue, a victim-only close-mixed sting, and one
  `DarkCrawler:strike()` per increment. The counter is monotonic rather than a flag so a beat
  cannot be lost inside a replication frame, and a body rebuilt after culling absorbs the pulses
  it missed instead of replaying them. Damage never waits on, and never reads, this contract — a
  visual builder that decided when a hit lands would be the bug this shape exists to prevent.
- The VoidFly's deterministic room-local offset is owned by `FloorPlanner`; `FloorBuilder` reserves
  that patch from harmless dressing and hands its exact paired surface fields to `ThreatService`,
  whose proxy follows the current irregular roof sample and owns the smoothed dive/return — the
  client builder must never raycast or guess a ceiling height of its own. The CeilingFly is never
  killed: a Flare immediately interrupts/clears its staged attack and temporarily repels it, while
  a nearby teammate remains the cooperative counter. Ordinary maximum burn does not repel it.
  Buzz timing/proximity live in
  `Threats.visuals.procedural.ceilingFlyBuzz`; the client emits the spatial cue only when nearby
  cave geometry does not block it.
- Detailed bodies stay non-collidable/non-queryable and are removed from Workspace beyond the
  configured cull distance; server replication remains one proxy Part per threat regardless of a
  body's visual complexity. Collision-neutral CaveKit/dripstone detail does not cast dynamic
  shadows (structural cave surfaces and collidable boulders do), so cave-wide torch shadow budget
  stays stable under `CandleLightController`'s one-shadow-per-client rule.

### `src/server/` — authoritative adapters

Server services own validation, state mutation, and Roblox Instances; rules belong in shared logic. Service names match their domains. Cross-cutting ownership: `EnvironmentSetup` forces runtime Lighting darkness (DESIGN §16) on boot, separately from the Studio-edit-mode defaults `default.project.json` pins; `LobbyRoomBuilder` builds the one static physical hub at boot; `ElevatorService` owns its entire tier-select/ready/start interaction, calling into `PartyLobbyService.tryStart`/`canStart` rather than duplicating leader/ready/unlock validation; `PlayerState` stores run state; `PartyLobbyService` owns lobby and teleport handoff; `RequestGuard` and `MovementSanityService` enforce public-server boundaries; `Telemetry` writes structured prototype logs; `CharacterService` owns every player body Instance — the run candle, the lobby avatar, the elevator ride candle, and the ghost candle — plus the collision groups that separate the living from the dead; `SpectatorService` owns what a dead player is (follow target, anchor pulls, faint expiring light, footfall buffers, and their dead-players-only replication) and nothing about the run outcome; `LootService` and `RemainsService` own pickup Instances; `ToolService` resolves grounded Decoy placement and owns decoy Instances/lifetimes; `ActionFeedbackService` converts authoritative cooldown state into immediate accepted/rejected feedback in `GetServerTimeNow` space; `LightSources` assembles the sole light-perception field while `DripTrailService` exposes separate geometric breadcrumbs; `WaxService` owns recurring/external drain, partial-light suppression, burnout handling, and periodic cooldown plus Basin-vision sync projection; `DripstoneService` owns the shared one-shot Dormant → Warning → Falling → Spent lifecycle and multi-player impact selection; `ThreatVisualProxy` owns replicated presentation roots and attributes while `ThreatService` owns authoritative ground-plane movement, exact roof-surface sampling, smoothed ambush height, idle wall-perch placement, and contact; `RunSummaryService` turns a resolved player's wax ledger into one structured development log line and writes nothing else; and `RunOrchestrator` owns expedition phase transitions, the run's authoritative `startDepth`, on-demand construction of each next floor, and teardown.

### `src/client/` — local input and display

- `CameraController`: candle first-person view/visibility and explicit camera-subject reassignment
  whenever restart replaces a ghost or dead candle character.
- `EnvironmentAnimationController`: local water sheen/bobbing. Animation never changes the
  server-owned hazard surface or exposure bounds.
- `DripstoneController`: reconstructs tagged formations' warning and analytic fall from replicated
  state/timestamps, then renders local dust, debris, spatial cues, camera shake, impact dimming,
  and flame flicker. It never selects triggers, victims, wax loss, or suppression.
- `ElevatorController`: reconstructs the server-timestamped `elevatorRide` curve every render frame
  for the tagged car and cosmetic rider candles, then adds the restrained camera tremor and in-car
  readout. `ElevatorService` still owns rider selection, timing, distance, and final transforms;
  clients only remove replication cadence from presentation.
- `CursorController`: first-person mouse capture is the default everywhere a character exists
  (lobby or expedition alike) — a released cursor is always an explicit named claim from the UI
  screen that needs it (Basin, Settings, results, native Roblox menu, etc.), never an automatic
  consequence of being outside an expedition.
- `DialController`, `MovementController`, `ToolController`: input and server requests; tool and
  cooldown movement acknowledgement waits for accepted server feedback.
- `SprintFeedbackController`: renders accepted sprint strain through restrained FOV, peripheral
  overlays, heat shimmer, and post-camera instability; it changes no movement or wax state.
- `CandleLightController`: is the sole candle-light renderer. It interpolates server-published
  candle targets, applies the owner-seeded/server-time `FlameFlicker` brightness and colour signal
  coherently to fill/shadow/bounce, and limits dynamic shadows to one full-range spherical
  local-player accent per client. Flicker never varies range, the enable threshold, or the stable
  carrier.
- `FeelController`: renders local environment/threat feedback plus replicated permanent Basin vision
  costs, and forwards local threat context to `CandleLightController`; it creates no candle PointLight.
- `AudioCues`: config-to-Sound adapter and local mixer. It builds Master → Music/Ambience/World/
  Focus/UI groups, applies EQ/reverb/Focus sidechains, preloads unique assets, varies cues inside
  authored bounds, scopes spatial cooldowns per emitter, enforces cue/bus/global voice limits,
  filters obstructed spatial one-shots, and exposes bus activity to ambience pacing.
  `MusicController` owns shuffled, delayed, fading tracks.
- Mining presentation follows the same authority boundary in four focused modules:
  `MiningController` owns targeting, input latches, and remote/session routing; `MiningHUD` owns the
  continuous rail, prompt, hints, cargo count, and touch styling; `MiningViewmodelController` owns
  only the local seam-directed pickaxe; and `MiningWorldPresentation` owns glow, spatial
  strike/break layers, chips, and co-op break deduplication. A stalled engage or strike closes its
  local request/stance instead of admitting an uncorrelated second action; server `disengage` is
  idempotent and release-only, so it bypasses the scored-request bucket and cannot leave movement
  locked.
- `AmbientCaveDirector`: the only harmless cave-event clock. It combines exponential silence,
  refractory time, an authored silent outcome, anti-repeat history, Focus-bus quiet gating, and real
  wall/ceiling/ground probes for strata strain, fissure breath, calcite ticks, hidden water, gravel
  creep, rockfall, and drip.
- `AmbientRockfallController` and `AmbientWaterDripController`: surface-valid presentation modules
  called by the director. They own no timer and never create a server hazard, hitbox, noise event, or
  remote route.
- `ThreatVisualController`: builds, animates, and distance-culls detailed procedural creatures
  locally around server-owned non-colliding proxies.
- `AshamedLurkerController`: the same build/animate/cull job for arch creatures, plus the one client
  report the feature needs — a rate-limited camera position and look vector for the stare, which the
  server re-validates from scratch — and the grab scare (shake, grade, spatial cue).
- `HintController`: fades contextual threat and hazard teaching text above the hotbar on floors
  one through three; contact messages are server-triggered and hazard messages use `StateSync`.
- `HotbarController`: responsive desktop/touch control legend with server-timed cooldown bars,
  readable upward-rounded timers, friendly rejection text, reset-safe feedback animations,
  free-charge counts, authoritative Flare/Cup active markers plus `RELIGHT`/`UNCUP` labels, and presentation-only mirrors
  attached to native ContextActionService touch buttons.
- `LobbyController`: gameplay-input/GUI toggling across the lobby<->expedition boundary and a
  small non-modal status readout for server-broadcast lobby messages. Tier-select/ready/start live
  entirely in the physical lobby now (`ElevatorService`/`ElevatorController`).
- `SettingsController`: local in-run settings menu (`M`) for mouse sensitivity and audio volume;
  it never changes authoritative gameplay values.
- `SpectatorController`: everything a ghost sees and the one key it has. Footfalls are drawn as world
  parts so cave geometry occludes them and none of them emits light; the readout names the teammate
  being followed; the key asks the server to take it to the next one. It never decides who is a
  spectator (only the server tells it, and only ghosts are ever told) or where a ghost goes.
- `RelightPromptController`: hides an ordinary snuffed candle's impossible self-relight prompt
  locally, but keeps the server-authorized solo Match prompt visible to its owner.
- `WaxBar`, `BasinPrompt`, `ResultsText`: UI driven by server state/events.
- `UITheme`: shared palette, fonts, and motion presets (tween/corner/stroke/panel/button helpers)
  plus the composited WICK wordmark and candle-glyph widgets, consumed by most themed UI above.
  Not a controller itself — no `.start()`, nothing boots it.

### `src/replicatedfirst/` — earliest-possible boot screen

- `WickLoadingScreen.client.luau`: shows before `ReplicatedStorage.Shared` is guaranteed to exist,
  so it cannot require `UITheme` and instead duplicates the wordmark/candle-glyph drawing inline
  (kept in sync with `UITheme` by a comment on both sides). Installs a static custom teleport GUI,
  adopts that GUI on the destination, and keeps the animated screen up until a lobby or run body
  exists, so a reserved expedition can never expose the hub between transfer and cave spawn.

### `src/shared/Types/`, `Net/`, and `Interfaces/`

- `Types/` defines contracts; `Types/init.luau` re-exports them.
- `Net/Remotes` is the complete server/client contract. `StateSync` includes render-only hazard
  exposure, Basin vision modifiers, active wax type, free tool charges, `isFlaring`, and `actionCooldowns` as
  `{ [actionId]: { endsAt, duration } }` in `Workspace:GetServerTimeNow()` space. `ActionFeedback`
  carries the same clock-space cooldown plus accepted/rejected status and an optional denial reason
  immediately after a tool request; `StateSync` remains the reconciliation path.
  `MineStrike` carries intent plus, for a strike, the shared-clock click sample accepted only through
  `MiningRules.resolveInputClock`; `MineState` returns the private stance/HUD result, and its
  depletion payload repeats the final grade/shard flags so paid-helper presentation cannot depend
  on cross-remote arrival order. Confirmed strike/depletion payloads also repeat the deposit root so
  an immediate local release cannot turn accepted contact non-spatial.
  `RunEvent("mineImpact", payload)` broadcasts the accepted deposit, grade, shard/depletion flags,
  and striker id so nearby teammates hear and see the same physical contact the cave AI heard.
  `LurkerGaze` is the only client-authored camera report in the game (Roblox does not replicate a
  camera), and `AshamedLurkerService` re-derives every condition from authoritative state before it
  counts; `RunEvent("lurkerGrab", payload)` broadcasts a confirmed grab's position, depth, and victim
  for the local scare. `LobbyAction`/`LobbyState` carry the one-party lobby contract; `TutorialHint` carries a
  server-selected threat or dripstone hint id after authoritative contact;
  `RunEvent("elevatorRide", payload)` carries the server timestamp, duration, distance, rest pivot,
  tier, and rider IDs for client interpolation, while `RunEvent("dripstoneImpact", payload)`
  broadcasts the server-confirmed impact position, depth, variant, and hit-player IDs; `RestartRun`
  and `ReturnToLobby` are the two resolved-run exits.
  `SpectatorAction` carries a ghost's only request ("follow" the next teammate, or "release") and never
  a target, position or floor; `SpectatorState` carries the follow status plus the teammate footfalls
  that ghost has not seen yet, and is fired ONLY at players who are dead — the audience is the rule,
  not an optimisation, so no living client can be modified into receiving one.
  Server handlers validate and rate-limit all inbound data.
- `Types/World.DripstonePlacement` is planned data: room index, room-local XZ, variant id, and
  visual seed. `FloorBuilder` resolves exact roof and landing heights from the deterministic fields.
- `Types/World.ThreatSpawn` is planned data: definition id, room index, and deterministic room-local
  offset. Runtime services must not reroll a gameplay spawn position.
- `Types/Tool` owns the data shapes for authoritative `ThrowPlacement` probes and `DecoyVisual`
  construction; behaviour remains generic over the optional fields.
- `Types/Light.LightSource` declares Drawn attraction, dark-hunter light perception, and the
  separate `forcesDarkHunterRetreat` panic-light flag. Decoy decoys set only Drawn attraction;
  ordinary flames affect hunter reads but only Flare sets forced retreat, matching DESIGN §6.
- `Interfaces/Persistence` is the ProfileStore boundary (Studio uses its isolated mock);
  `CaveTiers` derives persistent access; `Party` stores the one-party lobby state; `Remains`
  stores session-local pools. `Lineage` is the only remaining stub.
- `LightVisualProtocol` owns the CollectionService tag and attributes through which
  `CharacterService` publishes authoritative candle-render targets to clients. Its optional `color`
  attribute is the one opt-out: an emitter that is not a burning wick (only the ghost candle) declares
  its own colour and skips the warm combustion flicker.
- `AshamedLurkerVisualProtocol` owns the CollectionService tag plus the state, server timestamp,
  trap side, doorway width/height, seed, and site index the client builds and animates a body from.
  The server changes state and moves the proxy; clients never report anything back through it.
- `DripstoneVisualProtocol` owns the CollectionService tag plus shared state, timestamp, rest
  transform, landing, fall-distance, variant, depth, and seed attributes. The server changes
  lifecycle state; every client derives the same presentation without per-frame replication.
- `LobbyVisualProtocol` owns the lobby/run presentation boundary: static car/readout tags plus
  `tierId`, and the `runBody`/`rideBody`/`spectatorBody` attributes that distinguish the third-person
  lobby avatar, non-draining first-person ride candle, authoritative run candle, and the ghost candle.
  `ElevatorController` receives the changing ride timeline once through `RunEvent`; it never infers
  authority from tags. Nothing gameplay-side reads `spectatorBody` — every rule that stops a ghost
  acting reads `PlayerRunState.alive`.
- `Tests/` holds the dependency-free pure-rule harness and suites. Add regression coverage beside the owning logic change and keep expectations config-derived.

## Safe extension recipes

- **New threat:** add a `Config/Threats.definitions` row with depth weights and include the ID in
  eligible `Config/Floors.roomModules`. Reuse `visualStyle`, `ambush`, and `contactAttack` profiles
  when relevant; no per-threat class/ID branch.
- **New in-run loot:** add a `Config/Loot.definitions` row using an existing kind. Wax-profile, free-charge, and Match pickups need no service branch.
- **New sacrifice with an existing target:** add a `Config/Basin.pool` row. A new target also requires its type and one `SacrificeRules` handler.
- **New room module:** add a `Config/Floors.roomModules` row; planner/builder consume it generically.
- **New unstable-dripstone silhouette:** add one variant row under
  `Config/Hazards.unstableDripstone.variants`; reuse the fractured collar/lean/dust warning
  language. Do not add a service branch unless the gameplay contract itself changes.
- **New tunable system:** create a focused config file, export it from `Config/init.luau`, document its values in `TUNING.md`, and add its route here.
- **New remote:** add its name/payload to `Net/Remotes.luau`, wire both endpoints, validate server input, and update this document if it adds a route.
- **New player-state field:** update `Types/Player.luau`, `PlayerState.freshState`, and intentionally decide whether it belongs in `StateSync` (`Net/Remotes` and `WaxService.replicate`).
- **New persistent profile field:** update the profile type/default/reconcile handling in `Interfaces/Persistence`, then update only focused consumers. Never bypass ProfileStore with raw DataStore calls.
- **New cave tier:** add one data row in `Config/CaveTiers`; verify its unlock threshold, `startDepth`, planner limits, threat multiplier, lobby presentation, and brazier multiplier together. Also add a matching row to `Config/LobbyRoom.elevators` — the physical lobby has no other way to select a tier, so a tier without an elevator is unreachable.

## Supporting files

- `default.project.json`: Rojo source-to-Roblox mapping.
- `IMPLEMENTATION-NOTES.md`: caveats and manual testing.
- `IMPLEMENTATION-ROADMAP.md`: implemented phase status and ranked remaining work.
- `PUBLISH-CHECKLIST.md`: dependency, build, Studio, two-client, and live publish gates.
- `NEXT-PASS-PROMPT.md`: follow-up context; not design authority.
- `rokit.toml`, `wally.toml`, `selene.toml`, `stylua.toml`: tooling/dependency and lint/format configuration.

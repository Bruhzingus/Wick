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
Elevators → RunOrchestrator → MovementSanity → DripTrail → Tools → Wax → Dripstone → Threats → Death → Movement → Brazier
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
| Lobby party, ready/leader state, tier selection, or start flow | `server/ElevatorService.luau` | `server/PartyLobbyService.tryStart`/`canStart`, `Interfaces/Party`, `Config/LobbyRoom`, `client/ElevatorController`, `client/LobbyController` |
| Reserved-server teleport, teleport-data handoff, destination arrival body, or leader-start validation | `server/PartyLobbyService.luau` | `server/init.server.luau`, `server/RunOrchestrator`, `Config/Lobby`, `server/ElevatorService` (calls `tryStart`/`canStart`), `replicatedfirst/WickLoadingScreen.client.luau` (covers the transfer until a destination body exists) |
| Physical lobby geometry, shaft wall/perimeter-rib construction, local lighting, spawn point, shop placeholder, elevator alcoves, or signage | `server/LobbyRoomBuilder.luau` | `Config/LobbyRoom`, `Interfaces/CaveTiers`, `shared/LobbyVisualProtocol`, `Config/Feel.controls` (controls-sign text) |
| Elevator descent authority (rider capture, gate, ride-candle swap, timestamp, final car/rider transform) | `server/ElevatorService.luau` | `Config/LobbyRoom` (`rideDistance`/`rideShaftDepth`), `Config/RunSettings.startCountdownSeconds`, `server/CharacterService.spawnRideCandle`, `server/LobbyRoomBuilder` (tagged car models), `server/PartyLobbyService` (delays teleport until the ride completes) |
| Smooth elevator ride rendering (analytic car/rider interpolation, shudder, in-car readout) | `client/ElevatorController.luau` | `shared/LobbyVisualProtocol`, `Net/Remotes.RunEvent("elevatorRide")`, `client/CameraController.setElevatorOffset`, `Config/LobbyRoom` (distance/shake values) |
| Lobby avatar, non-draining elevator candle, or authoritative run candle | `server/CharacterService.luau` (`spawnLobby` / `spawnRideCandle` / `spawn`) | `shared/LobbyVisualProtocol.attributes.runBody`/`rideBody`, `server/ElevatorService`, `server/PartyLobbyService`, `server/RunOrchestrator.spawnRunner` |
| First-person vs. third-person camera and elevator camera offset | `client/CameraController.luau` | `shared/LobbyVisualProtocol.attributes.runBody`, `client/ElevatorController` — the ride-candle swap enters first person at elevator commitment |
| Lobby-only sprint | `client/LobbyMovementController.luau` | `Config/LobbyRoom` (speeds), `Config/Feel.controls.movement.Sprint` (binding), `client/MovementController` (owns the same key during a run) |
| Cross-server deepest-floor standings, same-server score overlay, or immediate board refresh | `shared/Interfaces/Leaderboard.luau` (store) / `server/LeaderboardService.luau` (board) | `server/BrazierService` + `server/DeathService` (submit and request refresh), `server/LobbyRoomBuilder.leaderboardLabel`, `Config/LobbyRoom` (rows/refresh) |
| Depth scaling, the depth ceiling, depth bands, per-floor seed derivation, or "how deep is this" | `Logic/DepthRules.luau` | `Config/Depth`, `Config/CaveTiers.startDepth`, `Logic/FloorPlanner`, `Logic/RewardMath`, `server/RunOrchestrator`, `server/PlayerState.globalDepth` |
| Wax drain, burnout, shrink, state sync | `server/WaxService.luau` | `Logic/WaxDrain`, `Logic/WaxAccounting`, `Logic/CandleGeometry`, `Config/Wax`, `Config/Character`, `PlayerState`, `DeathService` |
| Any change to a player's wax, or why a run ran out of it | `Logic/WaxAccounting.luau` | `server/WaxService` (the only path that can also trigger burnout), `Types/Wax.WaxSource`, `server/RunSummaryService`, `PlayerState.waxLedger` |
| Development run summary ("why did this run end?") | `server/RunSummaryService.luau` | `Logic/WaxAccounting`, `server/Telemetry`, `DeathService`, `BrazierService`, `RunOrchestrator` |
| Dial, drag request cadence, reconciliation, or visible/threat-output curve | `server/DialService.luau` / `client/DialController.luau` | `Logic/BrightnessMap`, `Config/Light`, `Config/Feel.dialInput`, `WaxService`, `LightSources` |
| Candle light fades, deterministic combustion flicker/warmth, spherical shadow accent, emitter stabilization, bounce/bloom/grading, shadow softness/range, or multiplayer stability | `client/CandleLightController.luau` / `Logic/FlameFlicker.luau` | `server/CharacterService`, `server/FloorBuilder`, `shared/NewModelsAndObjects/CaveKit`, `shared/LightVisualProtocol`, `Config/Light.rendering`, `client/FeelController`, `default.project.json` |
| Candle rig, body, camera, visual movement, or restart camera ownership | `server/CharacterService.luau` / `client/CameraController.luau` | `Config/Character`, `Logic/CandleGeometry`, `server/RunOrchestrator`, `RunEvent` floor handoff |
| Hop height, sprint, or movement input | `server/MovementService.luau` / `server/CharacterService.luau` | `client/MovementController`, `Config/Movement`, `Logic/WaxDrain` |
| Sprint FOV, peripheral strain, heat shimmer, camera instability, or sprint flame feedback | `client/SprintFeedbackController.luau` | `client/MovementController`, `client/FeelController`, `Config/Feel`, `server/CharacterService`, `Config/Character` |
| Tool stats, grounded-Decoy placement/visuals, or effect | `Config/Tools.luau` | `server/ToolService`, `Logic/ToolRules`, `Types/Tool`, `client/ToolController`, `LightSources` |
| Tool validation, grounded Decoy resolution, decoys, flare, or Cup/Snuff | `server/ToolService.luau` | `Logic/ToolRules`, `ActionFeedbackService`, `MovementService`, `Net/Remotes` |
| Tool/movement cooldown projection, accepted/rejected feedback, hotbar bars, or active markers | `Logic/CooldownRules.luau` / `server/ActionFeedbackService.luau` | `server/ToolService`, `server/MovementService`, `server/WaxService`, `Net/Remotes.ActionFeedback`, `StateEntry.actionCooldowns`/`isFlaring`/`isCupping`, `client/HotbarController`, `Config/Feel.hotbar` |
| In-run wax/charge/Match loot, wall-pocket planning, water-safe placement, exact built-surface placement, pickup art, or pickup behaviour | `Config/Loot.luau` | `Logic/FloorPlanner`, `Logic/GroundGeometry`, `Logic/LootRules`, `NewModelsAndObjects/LootPickup`, `server/LootService`, `PlayerState`, `ToolService` |
| Threat stats/content or depth spawn weights | `Config/Threats.luau` | `Config/Floors` allow-lists, `Logic/FloorPlanner` |
| Threat model geometry, local creature animation, or visual culling | `client/ThreatVisualController.luau` / `shared/NewModelsAndObjects/` | `server/ThreatVisualProxy`, `server/ThreatService`, `Config/Threats.visuals.procedural`, `Config/Feel.debug` |
| Threat AI, crawler light bands/retreat memory, room/pool routing, ground-following, ceiling-ambush dive/return, movement, or contact | `Logic/ThreatBrain.luau` / `Logic/RoomNavigation.luau` | `server/ThreatService`, `Logic/LightField`, `server/LightSources`, `Config/Threats.behavior`, `Config/Threats.definitions.*.ambush`, `Logic/FloorPlanner`, `Config/Floors.terrain` |
| Threat-visible light source | `server/LightSources.luau` | `Logic/LightField`, `WaxService`, `ToolService`, `RemainsService` |
| Localized water pools, wading, water lethality, or hazard animation | `server/HazardService.luau` / `server/FloorBuilder.luau` | `Logic/FloorPlanner`, `Logic/HazardRules`, `Config/Hazards`, `WaxService`, `client/EnvironmentAnimationController` |
| How often water appears at all, or how many pools a wet floor carries | `Config/Floors.floodedFloorChance` / `.floodedRoomsPerFloor` | `Logic/FloorPlanner` (`weightedModule`, `guaranteeDryRoute`, `enforceFloodedBudget`), `Config/Floors.roomModules` weights (kind of pool only) |
| Unstable-dripstone count curve, eligibility, variant, trigger, fall, impact, wax loss, low-wax snuff, or first-fall tutorial | `Logic/DripstoneRules.luau` / `server/DripstoneService.luau` | `Config/Hazards.unstableDripstone`, `Config/Feel.tutorialHints`, `Logic/FloorPlanner`, `server/FloorBuilder`, `WaxService`, `DeathService`, `client/HintController`, `LightSources`, `Types/World.DripstonePlacement` |
| Dangerous-dripstone model, fracture tell, warning/fall animation, dust/debris, shake, or impact grading | `shared/NewModelsAndObjects/UnstableDripstone.luau` / `client/DripstoneController.luau` | `shared/DripstoneVisualProtocol`, `Logic/DripstoneRules`, `Config/Hazards.unstableDripstone`, `Config/Audio`, `Net/Remotes.RunEvent` |
| Burnable vine curtains: which doorways may be gated, the light threshold that opens one, burn time, or curtain art | `Config/Vines.luau` / `Logic/VineRules.luau` / `server/VineService.luau` | `Logic/FloorPlanner`, `server/FloorBuilder`, `Config/Light.maxBurnRate`, `Config/Basin.effects.maxBurnRateCapMultiplier`, `Types/World.VinePlacement`, `Net/Remotes.RunEvent` |
| Stone Warden spawn, pathing, stun, or hazard interaction | `server/StoneWardenSystem/` / `server/WardenRegistry.luau` | `server/ServerInit.server.lua`, `server/DripstoneService`, `Config/Hazards.unstableDripstone.wardenStunSeconds`, `RunOrchestrator` |
| Cave moss on walls and around waterlines | `Config/Floors.caveMoss` | `server/FloorBuilder`, `Config/Hazards.waterPool.shoreMoss*` |
| Snuffing, teammate relighting, solo Match self-relighting, burnout, wisps, death results | `server/DeathService.luau` | `Config/Death`, `Config/Loot`, `Logic/LootRules`, `client/RelightPromptController`, `WaxService`, `CharacterService`, `Interfaces/Remains` |
| Session remains storage, placement, recovery, or light | `server/RemainsService.luau` | `Interfaces/Remains`, `Config/Remains`, `DeathService`, `LightSources`, `RunOrchestrator` |
| End-of-run screen, death debug, replay, or back-to-lobby flow | `client/ResultsText.luau` / `server/RunOrchestrator.luau` | `server/DeathService`, `server/PartyLobbyService`, `Net/Remotes` |
| Non-glowing wax-drop trails or hunter breadcrumbs | `server/DripTrailService.luau` | `Config/DripTrail`, `ThreatService`, `Logic/ThreatBrain` |
| Basin offers, sacrifice choices/modifiers | `server/BasinService.luau` | `Logic/SacrificeRules`, `Config/Basin`, `client/BasinPrompt`, `PlayerState` |
| Brazier preview, payout, group bonus | `server/BrazierService.luau` | `Logic/RewardMath`, `Config/Brazier`, `Interfaces/Persistence`, `client/ResultsText` |
| Floor topology, room selection, deterministic threat offsets, ceiling eligibility, guaranteed ground patches, pool footprints, or dangerous-dripstone placement | `Logic/FloorPlanner.luau` | `Config/Floors`, `Config/Threats`, `Config/Hazards`, `Logic/DripstoneRules`, `Logic/GroundGeometry`, `Logic/RoofGeometry`, `Logic/DoorwayGeometry`, `Types/World` |
| Cave geometry, recessed floors, CaveKit formations, ambush dressing reservations, per-edge doorway sizing, hazard zones, or exact room-surface handoff | `server/FloorBuilder.luau` | `server/ThreatService`, `shared/NewModelsAndObjects/CaveKit`, `shared/NewModelsAndObjects/UnstableDripstone`, `Config/Floors.geometry`, `.caveDressing`, `.terrain`, `.roof`, `Config/Threats`, `Config/Hazards`, `HazardService`, `Logic/FloorPlanner`, `Logic/GroundGeometry`, `Logic/RoofGeometry` |
| Cave-floor height field, swells, doorway lanes, pools, or a gameplay placement's exact local ground | `Logic/GroundGeometry.luau` | `Config/Floors`, `Logic/DoorwayGeometry`, `Logic/FloorPlanner`, `server/FloorBuilder` |
| Inverted Terrain roof shape, relief seed, edge blending, rock thickness, minimum clearance, or exact underside height | `Logic/RoofGeometry.luau` / `server/FloorBuilder.luau` | `Config/Floors.roof`, `Logic/GroundGeometry`, `Logic/FloorPlanner`, `shared/NewModelsAndObjects/CaveKit` |
| Expedition countdown, runner inclusion, separated multiplayer entry slots, descent, replay, lobby return, or reset | `server/RunOrchestrator.luau` / `Logic/EntrySpawnRules.luau` | `server/PartyLobbyService`, `Config/RunSettings`, `Config/Character`, `Config/Floors`, `FloorPlanner`, `FloorBuilder`, service `reset`s |
| Remote rate limits or finite-payload validation | `server/RequestGuard.luau` | `Logic/TokenBucket`, `Config/Security`, every inbound remote handler |
| Impossible-movement correction | `server/MovementSanityService.luau` | `Config/Security`, `Config/Movement`, approved burst credits in `MovementService`, authorized teleports in `RunOrchestrator`, `CharacterService` |
| Prototype server-log telemetry | `server/Telemetry.luau` | `Config/Security`, emitting service |
| HUD or run messages | relevant file in `src/client/` | `Net/Remotes`; `ResultsText` handles `RunEvent`, `WaxBar` handles `StateSync`, `HotbarController` handles `ActionFeedback` plus cooldown reconciliation |
| Cursor capture, clickable UI cursor release, or native Roblox menu interaction | `client/CursorController.luau` | the UI controller that opens the screen, `WickInExpedition`, `client/CameraController` |
| In-run local presentation settings (mouse sensitivity / audio volume) | `client/SettingsController.luau` | `client/CursorController`, `client/AudioCues`, `WickInExpedition` |
| Lobby UI, party list, ready button, or tier buttons | `client/LobbyController.luau` | `server/PartyLobbyService`, `Interfaces/CaveTiers`, `Net/Remotes` |
| Gameplay input enabled/disabled across lobby/run transitions | `client/LobbyController.luau` | `client/DialController`, `client/MovementController`, `client/ToolController`, `WickInExpedition` player attribute |
| Low-wax, water grading, or nearby-threat cue and flicker context | `client/FeelController.luau` / `client/WaxBar.luau` | `Config/Feel`, `client/CandleLightController`, `client/AudioCues`, `Net/Remotes`, `WaxService` |
| Rare ambient side-wall rockfall timing, cave-surface placement, small-rock roll, or local stone cue | `client/AmbientRockfallController.luau` | `Config/Feel.ambientRockfall`, `Config/Audio.cues.AmbientRockfall`, `client/AudioCues`, `NewModelsAndObjects/CaveKit.looseRock` |
| Rare ambient water-drip timing, ceiling source placement, or local drip cue | `client/AmbientWaterDripController.luau` | `Config/Feel.ambientWaterDrip`, `Config/Audio.cues.AmbientWaterDrip`, `client/AudioCues` |
| First-three-floor threat, dripstone, water, or gust teaching hints | `client/HintController.luau` | `server/ThreatService`, `server/DripstoneService`, `Config/Feel.tutorialHints`, `Net/Remotes.TutorialHint`, `WaxService` (`StateSync`) |
| Sound cue asset, volume, spatial rolloff, loop, or cooldown | `Config/Audio.luau` | `client/AudioCues` and the controller that requests the named cue |
| VoidFly buzz timing, proximity, or cave-wall suppression | `client/ThreatVisualController.luau` | `Config/Threats.visuals.procedural.ceilingFlyBuzz`, `Config/Audio.cues.FlyBuzz`, `client/AudioCues` |
| Menu music, cave playlist order/delays, or music fades | `client/MusicController.luau` | `Config/Audio.music`, `client/AudioCues`, `WickInExpedition` |
| Keyboard/touch binding or visible control hotbar | `Config/Feel.luau` | `client/HotbarController`, `ToolController`, `MovementController` |
| Shared UI palette, fonts, motion presets, or the composited WICK wordmark/candle-glyph widgets | `client/UITheme.luau` | every themed UI controller (`LobbyController`, `BasinPrompt`, `ResultsText`, `SettingsController`, `WaxBar`, `HotbarController`); `replicatedfirst/WickLoadingScreen.client.luau` duplicates the wordmark/glyph inline and must be kept in sync by hand |
| World darkness / Lighting setup at runtime | `server/EnvironmentSetup.luau` | `default.project.json` (owns the Studio-edit-mode Lighting/Atmosphere defaults this overrides at runtime) |
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
- `DripTrail`, `Basin`, `Brazier`: respective system values.
- `Remains`: session-pool storage bounds, pickup placement, and light values.
- `Depth`: the canonical depth model's tuning — technical ceiling, authored-table range, internal
  bands, past-authored scaling curves, and the development-only deep-run switch.
- `Floors`: default run length, room modules, spawn budgets, geometry dimensions. Its per-floor
  tables are indexed by GLOBAL depth, not by expedition floor number.
- `RunSettings`, `Death`: run timing/party/wisp and revival values.
- `CaveTiers`, `Lobby`, `Security`: durable-access tier rows, lobby/teleport retry values, and
  server trust-boundary tuning.
- `LobbyRoom`: the static physical hub's geometry (room shell, spawn point/spread, shop placeholder,
  boards), local lamp range/brightness, elevator-to-tier mapping/zone radius, descent-ride travel
  and shaft depth/perimeter-rib spacing, thickness, and outset, lobby-only movement speeds, and
  board copy (welcome/goal and how-to-play text; the controls panel is generated from
  `Feel.controls` instead of duplicated here).
- `Threats.visuals.procedural`: proxy offsets, cosmetic state cadence, client culling, and the
  emergency grey-box visual fallback.
- `Feel`, `Audio`: cosmetic feedback, shared control bindings, hotbar cooldown/active/denial
  presentation, debug-label gating, and cue registry.

### `src/shared/Logic/` — pure rules (no Roblox Instances)

- `CandleGeometry`: wax-to-body/flame geometry.
- `DepthRules`: the canonical depth model. `globalDepth = startDepth + localFloor - 1`, input
  validation (depth 0/negative/NaN/infinite/fractional are rejected, never clamped), the prototype
  depth ceiling, internal depth bands, the threat/hazard/room/reward scaling curves, and the stable
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
- `CooldownRules`: read-only `forAction`/`snapshot` projection of server-owned tool and
  voluntary-Snuff relight gates for presentation.
- `EntrySpawnRules`: stable, collider-separated party slots inside the entry room's guaranteed-clear
  central footprint.
- `LootRules`: wax-profile replacement, free-tool-charge awards, and Match self-relight charges.
- `ThreatBrain`: generic roaming, dark-hunter hunt/stalk/retreat bands, territorial-ambush
  decisions, movement, and staged-contact counting.
- `RoomNavigation`: reciprocal doorway graph, one-doorway waypoints, localized-pool detours,
  room-interior clamps, and fail-closed Basin exclusion.
- `HazardRules`: water decisions.
- `DripstoneRules`: unstable variant lookup, floor target curve, analytic fall, impact footprint,
  conservative silhouette extent, and temporary light-suppression math.
- `GroundGeometry`: deterministic cave-floor field, including actual off-centre doorway lanes,
  planned swells, and water bowls, shared by planning and Terrain construction.
- `RoofGeometry`: deterministic inverted-roof field, relief, and exact clearance-clamped underside
  sampling shared by planning and Terrain construction.
- `SacrificeRules`: offers, grants, modifiers.
- `RewardMath`: payout breakdown.
- `FloorPlanner`: seeded floor-plan generation from a `PlanRequest` (`globalDepth` drives every
  content curve and geometry seed; `localFloor` is only the expedition ordinal). Each floor of a run
  gets its own seed from `DepthRules.getFloorSeed`, so a floor is reproducible from
  (run seed, tier, global depth) alone rather than from how many floors preceded it. It also owns
  loop connections, guaranteed dry critical route,
  deterministic pool placement, collidable ground-patch placement, protected unstable-
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
- `LootPickup`: diegetic wax/flare/decoy/Match pickup models, server-built by `LootService`.
- `DarkCrawler`, `CaveMoth`, `CeilingFly`: each owns its own hardcoded palette/eye-glow constants
  (e.g. `CaveMoth`'s faint yellow attraction-driven eyes, `DarkCrawler`'s crimson idle/locked eyes)
  independently of `Config.Threats.visuals.darkHunter`/`.drawn` — those Config rows tune the
  emergency grey-box fallback body, not the detailed procedural one. Keep that split in mind before
  assuming a Config edit changes what players actually see with `visuals.procedural.enabled = true`
  (the default).
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

Server services own validation, state mutation, and Roblox Instances; rules belong in shared logic. Service names match their domains. Cross-cutting ownership: `EnvironmentSetup` forces runtime Lighting darkness (DESIGN §16) on boot, separately from the Studio-edit-mode defaults `default.project.json` pins; `LobbyRoomBuilder` builds the one static physical hub at boot; `ElevatorService` owns its entire tier-select/ready/start interaction, calling into `PartyLobbyService.tryStart`/`canStart` rather than duplicating leader/ready/unlock validation; `PlayerState` stores run state; `PartyLobbyService` owns lobby and teleport handoff; `RequestGuard` and `MovementSanityService` enforce public-server boundaries; `Telemetry` writes structured prototype logs; `CharacterService` owns candle/wisp Instances; `LootService` and `RemainsService` own pickup Instances; `ToolService` resolves grounded Decoy placement and owns decoy Instances/lifetimes; `ActionFeedbackService` converts authoritative cooldown state into immediate accepted/rejected feedback in `GetServerTimeNow` space; `LightSources` assembles the sole light-perception field while `DripTrailService` exposes separate geometric breadcrumbs; `WaxService` owns recurring/external drain, partial-light suppression, burnout handling, and periodic cooldown sync projection; `DripstoneService` owns the shared one-shot Dormant → Warning → Falling → Spent lifecycle and multi-player impact selection; `ThreatVisualProxy` owns replicated presentation roots and attributes while `ThreatService` owns authoritative ground-plane movement, exact roof-surface sampling, smoothed ambush height, idle wall-perch placement, and contact; `RunSummaryService` turns a resolved player's wax ledger into one structured development log line and writes nothing else; and `RunOrchestrator` owns expedition phase transitions, the run's authoritative `startDepth`, and teardown.

### `src/client/` — local input and display

- `CameraController`: candle first-person view/visibility and explicit camera-subject reassignment
  whenever restart replaces a dead wisp/candle character.
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
- `FeelController`: renders local environment/threat feedback and forwards local threat context
  to `CandleLightController`; it creates no candle PointLight. `AudioCues`: safe
  config-to-Sound adapter and master local-volume group; `MusicController`: menu playback plus
  shuffled, delayed, fading cave tracks.
- `AmbientRockfallController`: rare client-only wall-to-ground loose-rock presentation. It raycasts
  real cave surfaces, pivots a collision-neutral `CaveKit.looseRock`, and emits a restrained spatial
  cue; it never creates a server hazard, hitbox, or remote route.
- `AmbientWaterDripController`: rare client-only sound-only ambience. It places an invisible spatial
  emitter below a locally sampled cave roof and never creates a visual, hazard, hitbox, or remote route.
- `ThreatVisualController`: builds, animates, and distance-culls detailed procedural creatures
  locally around server-owned non-colliding proxies.
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
  exposure, active wax type, free tool charges, `isFlaring`, and `actionCooldowns` as
  `{ [actionId]: { endsAt, duration } }` in `Workspace:GetServerTimeNow()` space. `ActionFeedback`
  carries the same clock-space cooldown plus accepted/rejected status and an optional denial reason
  immediately after a tool request; `StateSync` remains the reconciliation path.
  `LobbyAction`/`LobbyState` carry the one-party lobby contract; `TutorialHint` carries a
  server-selected threat or dripstone hint id after authoritative contact;
  `RunEvent("elevatorRide", payload)` carries the server timestamp, duration, distance, rest pivot,
  tier, and rider IDs for client interpolation, while `RunEvent("dripstoneImpact", payload)`
  broadcasts the server-confirmed impact position, depth, variant, and hit-player IDs; `RestartRun`
  and `ReturnToLobby` are the two resolved-run exits.
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
  `CharacterService` publishes authoritative candle-render targets to clients.
- `DripstoneVisualProtocol` owns the CollectionService tag plus shared state, timestamp, rest
  transform, landing, fall-distance, variant, depth, and seed attributes. The server changes
  lifecycle state; every client derives the same presentation without per-frame replication.
- `LobbyVisualProtocol` owns the lobby/run presentation boundary: static car/readout tags plus
  `tierId`, and the `runBody`/`rideBody` attributes that distinguish the third-person lobby avatar,
  non-draining first-person ride candle, and authoritative run candle. `ElevatorController`
  receives the changing ride timeline once through `RunEvent`; it never infers authority from tags.
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

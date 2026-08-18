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
Elevators → RunOrchestrator → MovementSanity → DripTrail → Tools → Loot/Mining → Dynamite → Wax →
Dripstone → Vines → Tripwire → MossFire → AshamedLurker → Noise → Threats → the wick-pack (EnemyService,
immediately after the ordinary roster — same noise field, same snapshot) → Death → Spectators →
ContractWatch → Brazier → WallLamp
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
| Profile schema, loading, saving, session locking, or pre-expedition session release | `shared/Interfaces/Persistence.luau` | `server/init.server.luau`, `server/PartyLobbyService.luau`, `wally.toml`, profile consumers. `releaseForTeleport` waits for ProfileStore's final release save; a failed party teleport must reopen the source session before lobby interaction resumes |
| Cave family definition, difficulty curve, topology, ecology, ore, palette, or price | `shared/Config/CaveFamilies.luau` | `Logic/CaveFamilyRules` (ALL interpretation), `Config/CaveTiers` (derived projection only — never edit it), `Interfaces/CaveTiers`, `Interfaces/Persistence`, `server/PartyLobbyService`, `server/RunOrchestrator`, `server/FloorBuilder`, `TUNING.md`. No service, planner or builder may branch on a family id |
| Which falling formations a family hangs, its ambient soundscape, or what has grown on its creatures | `shared/Config/CaveFamilies.luau` (`hazardEcology` / `ambience` / `presentation.creatures`) | `Logic/CaveFamilyRules` (`dripstoneVariantWeightMultiplier`, `ambientWeightMultiplier`, `ambientSilenceMultiplier`, `creatureDressing`), `Logic/DripstoneRules.selectVariant`, `client/AmbientCaveDirector`, `NewModelsAndObjects/CreatureDressing`, `Tests/CaveFamilyRulesTests`. A family sets RATES and MATERIALS only: never a stat, a radius, or a cue gain |
| A family-exclusive creature, formation or sound event | the shared config row (`Config/Threats`, `Config/Hazards.unstableDripstone.variants`, `Config/Feel.ambientCave.soundEvents`) + a `0` weight in every other family | `Logic/CaveFamilyRules.validate` requires every family to answer for every authored row, so a new one fails the suite rather than leaking into all three caves. There is no branch: zero IS "not here" |
| Adding a fourth cave family | `shared/Config/CaveFamilies.luau` (one row) | `Tests/CaveFamilyRulesTests`, `Tests/CaveTiersTests`, `client/PartyPanelController` (generic ballot rendering). It must change topology, environmental pressure, threat ecology or another existing system — cosmetic-only duplication is prohibited (ARCHITECTURE invariants). No elevator row is needed: cars are parties, not caves |
| Which ore tier a seam is cut from, or adding an ore tier | `shared/Config/Ore.luau` (the tier row) + a band in that family's `ore.availability` | `Logic/OreRules`, `Logic/FloorPlanner` (stamps `oreTier` per placement), `Tests/OreRulesTests`. Deliberately independent of `Config/Mining.rows`, which owns how a seam is WORKED |
| Falling-hazard density, depth curve, per-room/per-floor spread, or the readable-tip rule | `shared/Config/Hazards.unstableDripstone` | `Logic/DripstoneRules` (curve + tip readability), `Logic/CaveFamilyRules.hazardousRoomFraction` (how widely a family spreads them), `Logic/FloorPlanner.planDripstones`, `Tests/DripstoneRulesTests`, `Tests/FloorPlannerTests`. Readability is measured at the formation TIP, never at the roof — see the note in the config |
| A cave family's rock, textures, wall-cover shape, ground-cover density, or formation materials | `shared/Config/CaveFamilies.presentation` | `server/FloorBuilder` (resolves the palette/materials and seats collision-neutral surface cover on the shared ground field), `Tests/CaveFamilyRulesTests` (requires distinct textures per family AND holds every colour below a luminance bound). Colour alone is not a different cave; the material and silhouette are what the candle catches |
| What a set-piece creature hides against (Ashamed Lurker socket, Warden courses) | `Logic/CaveFamilyRules.creatureDressing` | `NewModelsAndObjects/AshamedLurker` (`rockColor`/`rockLightColor`/`rockMaterial` build options), `server/StoneWardenSystem/StoneWardenModel.setPalette`, `client/AshamedLurkerController`, `AshamedLurkerVisualProtocol.attributes.familyId`. Both were hardcoded to Stone slate, so both only actually hid in one cave of three |
| A cave family's AIR — how far the candle reaches, how much distance shows, glare around the flame | `shared/Config/CaveFamilies.presentation.atmosphere*` | `Logic/CaveFamilyRules.atmosphere` (clamps density above a shared darkness floor), `server/EnvironmentSetup.applyCaveFamily`, `server/RunOrchestrator` (once per expedition), `Tests/CaveFamilyRulesTests`. Density is the one a player feels: it decides how big the cave seems. No family may thin it enough to make an unlit room legible |
| How big a cave SOUNDS (reverb tail and wetness) | `shared/Config/CaveFamilies.presentation.reverb*` | `Logic/CaveFamilyRules.acoustics`, `client/AudioCues.setCaveAcoustics`, `client/CaveAcousticsController`. A SCALE and OFFSET on the authored per-bus reverb, never a replacement — `Config/Audio`'s different tails per bus must keep their relationship. Resets to neutral in the lobby |
| The player's own footsteps, their cadence, or what a surface sounds like | `client/FootstepController.luau` + `Config/Feel.footsteps` | `Config/CaveFamilies.presentation.footstepCue`, `Logic/CaveFamilyRules.footstepCue`, `Config/Audio.cues.Footstep*`. **Self-audible only** — walking emits nothing through `NoiseService`, because `Config/Sound.emitters` is what the cave hears and making footsteps a noise source would hand every hearing threat a permanent track on every moving player |
| What a cave calls its Warden | `Logic/CaveFamilyRules.wardenDisplayName` | `server/StoneWardenService`, `StoneWardenSystem/StoneWardenBehavior` (the death line). Display name only: the config id, room module, service and files stay `StoneWarden` in every family |
| Room shapes: the shape pool, weights, containment, or the twin-lobe neck | `Logic/RoomFootprint.luau` | `Config/CaveFamilies.roomShapeWeights`, `Logic/FloorPlanner` (rolls and validates), `server/FloorBuilder.fillRoomTerrain` (carves the rock), `Tests/RoomFootprintTests`. The room CELL is untouched — it still owns indexing, adjacency, doorway anchors and cleanup |
| Moss flammable vegetation: chance, ignition, spread, light, or heat | `shared/Config/MossFire.luau` | `Logic/MossFireRules` (all rules), `Logic/FloorPlanner.planMossFire` (placement + connectivity graph), `server/MossFireService` (authority), `server/LightSources` (shared light list), `Logic/WaxAccounting` (`EnvironmentalFire`), `Tests/MossFireRulesTests` |
| Lamp Network node list, costs, prerequisites, contract rows, wager curve, or rollback flags | `shared/Config/LampNetwork.luau` | `Logic/LampRules` (all interpretation), `Interfaces/LampNetwork` (currency + profile), `server/ShopService.purchaseLamp`, `client/ShopController` (the surface that names and prices them), `server/LobbyRoomBuilder.buildShopSchematic` (the storefront housings), `LAMP-NETWORK.md` |
| Lamp Network prerequisite/contract/wager RULES (pure, testable cold) | `shared/Logic/LampRules.luau` | `Interfaces/LampNetwork`, `server/ShopService`, `Tests/LampRulesTests` |
| Buying a lamp node, or the atomic charge-and-grant | `shared/Interfaces/LampNetwork.luau` | `Interfaces/Persistence.applyTransaction`/`grantLampNode`, `server/ShopService`. The charge and the grant must stay in one yield-free block; a duplicate transaction must still grant |
| What a signed contract DOES to a run (tools, wax, Basin, paying depth, tether, void conditions) | `shared/Logic/ContractRules.luau` | `Config/LampNetwork` (the `effect` block on each row is the authority), `server/PlayerState.freshState`, `server/BasinService`, `server/ContractWatchService`, `server/ExtractionService`, `Logic/ExtractionValue`. Every rule must be enforced by the system that already owns what it takes away — never by a contract-shaped branch bolted alongside it |
| Enforcing a rule that can only be judged mid-run (currently only the tether) | `server/ContractWatchService.luau` | `Logic/ContractRules`, `server/ExtractionService.voidContract`, `server/PlayerState`. Decides nothing about money |
| Ringing the Signal Bell: who may, what it costs, the cooldown, the noise, who hears it | `server/SignalBellService.luau` | `Config/LampNetwork.bell`, `Config/Sound.emitters.SignalBell` (the radius the cave hears), `Logic/WaxAccounting` (`SignalBellCost`), `server/NoiseService`, `client/SignalBellController`. The bell is NOT a tool: no `Config/Tools` row, no hotbar slot, no threat interaction |
| The bell key, its spatial cue and its occluded ripple | `client/SignalBellController.luau` | `Config/Feel.controls.signalBellKey`, `Config/Audio.cues.SignalBell`, `RunEvent("bellRing")`. THE SOUND carries through rock; the ripple never does and emits no light |
| Dynamite: supply cadence, carry cap, fuse, throw, blast, per-creature lethality, vault rolls | `shared/Config/Dynamite.luau` | `Logic/DynamiteRules` (ALL decisions), `server/DynamiteService` (authority + Instances), `Config/Threats.definitions.*.blast` (per-creature hit points), `Tests/DynamiteRulesTests`, `TUNING.md`. **This is the one place DESIGN's no-combat pillar is relaxed (DESIGN §6a, owner decision), and four values BOUND that exception rather than tune it:** `supply` gaps, `supply.maxCarried`, `blast.playerWaxCost`, `blast.alertRadius`. Widening any of them widens the exception |
| A creature's dynamite lethality | `shared/Config/Threats.definitions.*.blast` | `Logic/DynamiteRules.profileFor`/`isLethal`, `server/ThreatService.applyBlast`. Expressed in "sticks at point blank" because blast damage is 1.0 at the centre. Omitting the block takes `Config/Dynamite.threat.default`, which is deliberately KILLABLE — a silently immune row would be invisible in play |
| The Stone Warden's response to a blast (damage, stun, limp) | `server/StoneWardenSystem/StoneWardenBehavior.lua` (`Blast`) | `server/WardenRegistry` (the `blast` callback), `Config/Dynamite.threat.warden*`. `wardenHitPoints` exceeds the carry cap on purpose: DESIGN §9's promise that the encounter has exactly ONE real counter (a falling crown) must stay true, so a stick buys time and never a kill in practice |
| Blast vaults: how many, how deep, what is inside, what may never be stacked on one | `Logic/FloorPlanner` (attach + stocking) + `Config/Dynamite.vault` | `Logic/RoomNavigation.build` (vaults are absent from the graph so nothing roams in), `Config/Floors.roomModules.BlastVault` (`connections = 1` and an EMPTY `allowedThreats` are both load-bearing), `server/FloorBuilder` (the family-styled door), `server/DynamiteService.registerFloor`, `Tests/FloorPlannerTests`. The vault is attached AFTER the loop pass, which is the safety proof rather than a check: it is a leaf by construction, so nothing behind the door is ever on the way to anything |
| The blast door's look, its charge pocket, or the yellow outlined socket silhouette | `server/FloorBuilder` (rock, rubble, fractures, pocket) + `client/DynamiteController` (the marker) | `Config/Dynamite.visual`, `Config/CaveFamilies.presentation.blastDoorStyle`, `Logic/CaveFamilyRules.blastDoorStyle`, `DynamiteVisualProtocol`. The marker is PER PLAYER — only somebody carrying a stick sees it — which is why it is client-built. Fill-free Highlight with NO PointLight: visible without lighting one voxel of rock (ART-BIBLE §4) |
| Deposit row definitions (Twin / Deep / Bright seam kinds) | `shared/Config/Mining.rows` | `Logic/MiningRules` (selection, per-row progress, burn gate), `Logic/FloorPlanner` (stamps `rowId` per placement), `server/MiningService` (honours strikes, yield, paid miners), `server/ExtractionService.grantForDeposit` |
| The Locked Store: which room is sealed, its curtain, its guaranteed stock | `Logic/FloorPlanner` (selection, curtain, stock) + `Logic/VineRules.roomMayBeSealed` (the dead-end proof) | `Config/LampNetwork.generation.lockedStore`, `VineRules.allRoomsReachable` (`exemptIndices`), `Tests/FloorPlannerTests`. The store is the ONLY room a curtain may fully seal and the ONLY vined room allowed a deposit; both exceptions rest on it being a dead end, so that requirement may never be relaxed |
| Reading the pay table, signing a contract, placing a wager, or what a lit passive node (Twin/Deep/Dim/Bright Seam, Signal Bell, Locked Store) confirms it does below | `client/ShopController.luau` (the surface, incl. `PASSIVE_NODE_CONFIRMATION`) + `server/ShopService.luau` (the authority) | `Remotes("ShopState"/"ShopAction")`, `client/LampTreeView` + `client/LampNodeIcons` (the node graph it draws), `server/PartyLobbyService` (the counter prompt opens it), `client/init.client.luau` (starts it). Every choice the client sends is revalidated server-side. Supersedes the removed `server/LampHubService.luau`, which answered the same nodes' now-removed physical lamp fixtures |
| Which lamps a given player sees burning | `client/LampNetworkController.luau` | `shared/LobbyVisualProtocol.lampHousingTag`, `LobbyState.ownedLampNodes`. Per-viewer by necessity: ownership is per-player and the hub is shared |
| Elevator party membership, first-rider leadership, ready/vote/start flow, explicit leave, leader kick, or temporary re-entry block | `server/ElevatorService.luau` | `server/PartyLobbyService.tryLaunch`, `Interfaces/Party`, `Logic/PartyRules`, `Logic/PartyVote`, `Config/Lobby`, `Config/LobbyRoom`, `client/PartyPanelController` |
| Whether the descent lever's lamp is lit | `server/ElevatorService.luau` (`setLeverArmed`) | `LobbyRoomBuilder.ElevatorParts.leverLamp` — the lever takes no input at all; the lamp says only "this car can still be sent down", and goes dark as the handle throws. The lever's geometry is `LobbyRoomBuilder.descentLever`, which decides nothing about when a descent is allowed |
| Reserved-server teleport, teleport-data handoff, destination arrival body, rejoin routing, or final party-launch validation | `server/PartyLobbyService.luau` / `server/RejoinService.luau` | `Interfaces/Party` (destination arrivals use real party id `0`; only `nil` means no selected expedition), `Tests/PartyInterfaceTests`, `Interfaces/Persistence.releaseForTeleport` (the whole party's source sessions finish releasing before expedition teleport), `server/init.server.luau`, `server/RunOrchestrator`, `Config/Lobby`, `server/ElevatorService` (calls `tryLaunch` after the vote resolves), `replicatedfirst/WickLoadingScreen.client.luau` (covers the transfer until a destination body exists). Rejoin routing originates only from a public lobby: a reserved expedition server, or an arrival already carrying `wickExpedition`, is already at its destination and must never dispatch another rejoin teleport |
| Physical lobby geometry, arrival tunnel/track/carts, wall-candle exclusion spans, local lighting, spawn point, the shop stall and its Lamp Network schematic, elevator alcoves, the cosmetic scaffold climb, or signage | `server/LobbyRoomBuilder.luau` | `Config/LobbyRoom`, `Interfaces/CaveTiers`, `Interfaces/LampNetwork`, `shared/LobbyVisualProtocol`, `Config/Feel.controls` (controls-sign text) |
| Why an expedition server builds the hub but NOT its `LandingSpawn` | `server/init.server.luau` (`isReservedExpedition`) → `LobbyRoomBuilder.build(withLandingSpawn)` | An expedition runs on a reserved server on the same PlaceId, so the hub is built there too. An arriving member is deliberately left bodyless until `RunOrchestrator` carves floor one, and with `Character`/`CameraSubject` both nil Roblox parks the default camera at the map's only SpawnLocation — which was this duplicate hub. That was the "you briefly teleport back to the lobby, then to the cave" report: one `TeleportAsync`, one stray camera. The signal is the same one `server/RejoinService` uses (`PrivateServerId` set with `PrivateServerOwnerId == 0`). The hub itself still builds because `PartyLobbyService.returnToLobby` puts bodies back in it when a run resolves |
| The lobby platform course (platform positions, landing styles and sizes, summit dressing) | `Config/LobbyRoom.parkour` | `server/LobbyRoomBuilder.buildParkour`/`parkourLanding`/`buildParkourSummit`, `Config/LobbyRoom.jumpPower`/`runSpeed`, `Tests/LobbyParkourTests`. `steps` is an authored list of surface points: X/Z place a platform and Y is the height you STAND ON, with each style's depth hung below it. The route is a line that turns ONCE, on purpose — earlier switchback and spiral versions were respectively skippable (adjacent lanes, small rises) and ugly (jump distance caps the spiral's span, so it comes out taller than it is wide, a thicket of posts). Every platform gets exactly one post and nothing spans between them: the volume a player jumps through stays empty. The tests re-derive reachability, that no platform can be skipped, that entry is capped at the second platform, and clearance from the ceiling beams, standings boards, elevator band and wax carts. Deliberately has NO service, remote, tag, attribute or state: nothing observes a player climbing it, and nothing may be added that does — the moment completion is detectable it stops being a diversion and becomes a reason not to board the elevator |
| Recent-update board, join-time unseen entries, or once-per-build dismissal | `Config/LobbyRoom.updateLog` + `client/UpdateLogController.luau` | `server/LobbyRoomBuilder.buildUpdateBoard`, `server/PartyLobbyService` (`LobbyState.unseenUpdates` / server-derived `dismissUpdates`), `Interfaces/Persistence.lastSeenUpdateVersion`, `client/UITheme`, `client/init.client.luau`. The client never sends a version |
| The in-lobby build counter sign | `Config/Version.luau` | `server/LobbyRoomBuilder.buildVersionSign`, `Config/LobbyRoom.versionSignOffset/Width/Height`. Bump `Version.number` by one in the same change as every other edit |
| Elevator descent authority (rider capture, closed-gate containment, ride-candle swap, timestamp, final car/rider transform) | `server/ElevatorService.luau` | `Config/LobbyRoom` (`rideDistance`/`rideShaftDepth`), `Config/RunSettings.startCountdownSeconds`, `server/CharacterService.spawnRideCandle` / `.setLobbyBodyRideControlled` (server-owned but unanchored in-car movement), `server/LobbyRoomBuilder` (tagged car models), `server/PartyLobbyService` (delays teleport until the ride completes) |
| Smooth elevator ride rendering (analytic car/rider interpolation, free look/in-car movement preservation, shudder, in-car readout) | `client/ElevatorController.luau` | `shared/LobbyVisualProtocol`, `Net/Remotes.RunEvent("elevatorRide")`, `client/CameraController.setElevatorOffset`, `Config/LobbyRoom` (distance/shake values) |
| Lobby avatar, non-draining elevator candle, or authoritative run candle | `server/CharacterService.luau` (`spawnLobby` / `spawnRideCandle` / `spawn`) | `shared/LobbyVisualProtocol.attributes.runBody`/`rideBody`, `server/ElevatorService`, `server/PartyLobbyService`, `server/RunOrchestrator.spawnRunner` |
| First-person vs. third-person camera and elevator camera offset | `client/CameraController.luau` | `shared/LobbyVisualProtocol.attributes.runBody`, `client/ElevatorController` — the ride-candle swap enters first person at elevator commitment |
| Lobby default run speed | `server/CharacterService.spawnLobby` | `Config/LobbyRoom.runSpeed`; the Landing has no manual sprint binding |
| Cross-server deepest-floor standings, same-server score overlay, periodic/manual board refresh, or leaderboard row rendering | `shared/Interfaces/Leaderboard.luau` (store) / `server/LeaderboardService.luau` (board) | `server/BrazierService` + `server/DeathService` (submit and request refresh), `server/LobbyRoomBuilder.leaderboardDisplay` (row labels + refresh prompt), `Config/LobbyRoom` (rows, refresh cadence, prompt cooldown) |
| Uncapped depth scaling, depth bands, per-floor seed derivation, or "how deep is this" | `Logic/DepthRules.luau` | `Config/Depth`, `Config/CaveTiers.startDepth` (always 1), `Logic/FloorPlanner`, `Logic/ExtractionValue`, `server/RunOrchestrator`, `server/PlayerState.globalDepth` |
| An object spawning inside, under, or on top of the cave floor (loot, deposits, Warden wax fixture) | `server/SurfaceProbe.luau` | `Config/Floors.geometry.placementProbe` (local-headroom Terrain-only rays, complete circular support, per-sample analytic heights, tangent-plane residual and visible-bounds seating), `Logic/SurfaceRules`, `Config/Mining.visual.surfaceProbeRadius`, `server/LootService`, `server/MiningService`, `server/StoneWardenService`. `Logic/FloorPlanner` owns the final X/Z and mutual placement reservations; `server/FloorBuilder` + `Logic/GroundGeometry` add a small blended level shelf at that position's natural elevation, finish every room/shaft Terrain mutation, then cross one Heartbeat before any built-surface query. `RunOrchestrator` serializes builds across that yield. Production calls `resolvePlannedPosition` and refuses an unmeasured/unsupported result instead of relocating or spawning a lifted guess. `RunOrchestrator.floor_spawn_audit` reports planned/built, refused-surface, and diagnostic support-warning counts |
| Mining: deposit progress/wear, LOS and current-reachable-dial burn validation, bounded click-clock scoring, strike sequence, shared impact event, depletion, or run count | `server/MiningService.luau` | `Logic/MiningRules` (every rule, including `resolveInputClock`), `Config/Mining`, `Types/SacrificeModifiers.minBurnRate/maxBurnRate`, `shared/MiningVisualProtocol`, `NewModelsAndObjects/WaxDeposit`, `client/MiningController`, `Net/Remotes.MineStrike` / `RunEvent("mineImpact")`, `Config/Security.remoteRateLimits.MineStrike`. Brightness sacrifices alter emitted light but may not make a row's dial window unreachable |
| Mining target selection, pending-input latches, stance/remote coordination, movement release, or teammate impact routing | `client/MiningController.luau` | `Logic/MiningRules.sweepPhase`/`bandCenter`, `client/MiningHUD`, `client/MiningViewmodelController`, `client/MiningWorldPresentation`, `Net/Remotes.MineState` + `RunEvent("mineImpact")` + `StateEntry.rawWax` |
| Mining fracture rail, row-aware prompt, rejection/result copy, touch-button styling, or carried-Raw-Wax readout | `client/MiningHUD.luau` | `Config/Mining.qte`/`timing`/`feedback`, `client/UITheme`, `client/MiningController` |
| Seam-directed pickaxe model, draw/stow, outcome-specific swing/rebound, aim bias, or trail | `client/MiningViewmodelController.luau` | `Config/Mining.pickaxe`, `client/MiningController`; cosmetic only, with no remote or outcome authority |
| Mining proximity ember, wear-coupled seam glow, spatial grade/break layers, contact chips, or shared/private break deduplication | `client/MiningWorldPresentation.luau` | `Config/Mining.visual.glow`/`feedback`, `Config/Audio.cues.Mine*`, `shared/MiningVisualProtocol`, `client/AudioCues`, `client/MiningController`. The removed first-strike `SeamHiss` has no cue, replicated strike-count attribute, or runtime playback path; the primed crackle and explosion remain |
| Raw Wax cargo: per-depth grant, cap, loss/forfeit, party ledger, extraction, or persistence payout | `server/ExtractionService.luau` | `Config/Extraction`, `Logic/CargoRules`, `Logic/ExtractionValue`, `server/MiningService` (calls `grantForDeposit`), `server/BrazierService`, `server/DeathService`, `server/RunOrchestrator`, `Types/Mining.RawWaxCargo`/`RawWaxRun`, `Tests/CargoRulesTests` |
| Where deposits may appear | `Logic/FloorPlanner.planDeposits` | `Config/Mining.placement`, `Config/Mining.visual.surfaceProbeRadius`, `Logic/MiningRules.targetCount`, `Tests/FloorPlannerTests` (protected-route/open-footprint invariants). Ordinary seams remain in random wall/geology pockets or are omitted; paid store/vault stock uses reserved doorway-relative cache alcoves and never a centre fallback |
| What the cave can hear, or making an action noisy | `Config/Sound.luau` (row) + one `server/NoiseService.emit` call | `Logic/SoundField`, `Config/Threats` `hearing` rows, `Logic/ThreatBrain` (Investigate), `server/ThreatService` (protected-room filtering) |
| A threat reacting to sound | `Config/Threats.definitions[id].hearing` | `Logic/ThreatBrain.thinkInvestigate`, `Logic/SoundField.audibleFor`. Never add an `if mining` branch to a threat |
| Wax drain, burnout, shrink, state sync | `server/WaxService.luau` | `Logic/WaxDrain`, `Logic/WaxAccounting`, `Logic/CandleGeometry`, `Config/Wax`, `Config/Character`, `PlayerState`, `DeathService` |
| Any change to a player's wax, or why a run ran out of it | `Logic/WaxAccounting.luau` | `server/WaxService` (the only path that can also trigger burnout), `Types/Wax.WaxSource`, `server/RunSummaryService`, `PlayerState.waxLedger` |
| Development run summary ("why did this run end?") | `server/RunSummaryService.luau` | `Logic/WaxAccounting`, `server/Telemetry`, `DeathService`, `BrazierService`, `RunOrchestrator` |
| Dial, drag request cadence, reconciliation, or visible/threat-output curve | `server/DialService.luau` / `client/DialController.luau` | `Logic/BrightnessMap`, `Config/Light`, `Config/Feel.dialInput`, `WaxService`, `LightSources` |
| Candle light fades, deterministic combustion flicker/warmth, spherical shadow accent, emitter stabilization, bounce/bloom/grading, shadow softness/range, or multiplayer stability | `client/CandleLightController.luau` / `Logic/FlameFlicker.luau` | `server/CharacterService`, `server/FloorBuilder`, `shared/NewModelsAndObjects/CaveKit`, `shared/LightVisualProtocol`, `Config/Light.rendering`, `client/FeelController`, `default.project.json`. An emitter may declare `LightVisualProtocol.attributes.color` to opt out of the configured flame colour and the warm flicker; only the ghost candle does, and `Config/Light.rendering` stays the answer for every burning wick |
| Candle rig, body, camera, visual movement, or restart camera ownership | `server/CharacterService.luau` / `client/CameraController.luau` | `Config/Character`, `Logic/CandleGeometry`, `server/RunOrchestrator`, `RunEvent` floor handoff |
| What a body collides with (living candle vs ghost) | `server/CharacterService.init` (collision groups) | `Config/Spectator`. `WickSpectator` is non-collidable with `WickRunner` and with itself, and collidable with everything else, so a ghost is stopped by rock and can never block a doorway the party needs |
| Hop height or default run speed | `server/MovementService.luau` / `server/CharacterService.luau` | `Config/Movement`, `Logic/WaxDrain` |
| Default-run FOV, peripheral strain, heat shimmer, camera instability, or flame feedback | `client/SprintFeedbackController.luau` | `client/FeelController`, `Config/Feel`, `server/CharacterService`, `Config/Character` |
| Tool stats, grounded-Decoy placement/visuals, or effect | `Config/Tools.luau` | `server/ToolService`, `Logic/ToolRules`, `Types/Tool`, `client/ToolController`, `LightSources` |
| Tool validation, grounded Decoy resolution, decoys, flare, or Cup | `server/ToolService.luau` | `Logic/ToolRules`, `ActionFeedbackService`, `MovementService`, `Net/Remotes` |
| Throwing, one-step seating/lighting, fuse animation or detonating dynamite; what a blast does to candles, creatures, the Warden and blast doors | `server/DynamiteService.luau` | `Logic/DynamiteRules` (every decision), `Config/Dynamite`, `Net/Remotes.DynamiteAction` / `RunEvent("dynamiteExploded"/"dynamiteLit")`, `server/ThreatService.applyBlast`, `server/WardenRegistry.blast`, `server/WaxService.drainExternal` (`DynamiteBlast`), `server/NoiseService` + `Config/Sound.emitters.DynamiteBlast`, `client/DynamiteController`, `NewModelsAndObjects/Dynamite`. A wall interaction atomically spends, seats and lights one stick; a loose throw visibly follows its validated arc |
| Tool cooldown projection, accepted/rejected feedback, hotbar bars, or active markers | `Logic/CooldownRules.luau` / `server/ActionFeedbackService.luau` | `server/ToolService`, `server/WaxService`, `Net/Remotes.ActionFeedback`, `StateEntry.actionCooldowns`/`isFlaring`/`isCupping`, `client/HotbarController`, `Config/Feel.hotbar` |
| In-run modifier/charge/Match loot, how many pickups a floor rolls, per-cave depth gating, wall-pocket planning, the cross-room peripheral ring sweep that keeps pickups off the room centre, water-safe placement, exact built-surface placement, pickup art, or pickup behaviour | `Config/Loot.luau` | `Logic/FloorPlanner` (all X/Z choice and reservations), `Logic/GroundGeometry`, `Logic/LootRules`, `Logic/CandleModifiers`, `NewModelsAndObjects/LootPickup`, `server/FloorBuilder` (local seating shelf), `server/LootService`, `server/SurfaceProbe.resolvePlannedPosition`, `PlayerState`, `ToolService` |
| What a collected item DOES to a candle — stacking bonuses and their diminishing returns, Frozen Wax melting at maximum brightness, Extra Wicks' duration and its Cup suppression, Candle Sleeve absorption and charge cost | `Logic/CandleModifiers.luau` | `Config/CandleModifiers`, `Logic/WaxDrain` (`DrainContext.candle`), `Logic/BrightnessMap`, `server/WaxService` (the tick, the Frozen Wax grant, and `drainExternal`'s single sleeve chokepoint), `server/LightSources`, `server/ToolService`, `Types/Wax.CandleModifierState` |
| Threat stats/content or depth spawn weights | `Config/Threats.luau` | `Config/Floors` allow-lists, `Logic/FloorPlanner`, `Tests/ThreatRulesTests` (every allow-listed id must be a real row, and every row must draw a body no other row draws) |
| How many threats a floor carries | `Config/Floors.threatBudgetPerFloor` | `Logic/FloorPlanner` (`base x caveBase x caveBand`, and DESIGN §18 forbids computing it any other way), `Config/CaveFamilies` band multipliers, `TUNING.md`. **Adding a threat ROW does not add bodies** — the roll normalises across whatever a room allows, so a new creature dilutes the mix until this number moves |
| A creature that hunts by sound, predicts a route, or triggers the ceiling | `Config/Threats.definitions[id].hearing` / `.intercept` / `.ceilingStrike` | `Logic/ThreatBrain` (`thinkCeilingStriker`, `interceptTarget`), `server/ThreatService` (`isTerritorial`, `updateCeilingStrike`), `server/DripstoneService.triggerNearest`, `Tests/ThreatBrainTests`. The commitment window and the wind-up are reaction guarantees and are deliberately absent from `ThreatDepthScaling` so no curve can erode them |
| How a creature's stats change with depth, or whether contact can extinguish rather than only drain | `Config/Threats.definitions[id].depthScaling` / `.sustainedContact` | `Logic/ThreatRules` (`atDepth` resolves a row ONCE per spawned body in `server/ThreatService.spawnFloor`; `snuffsWithoutWarning` is what protects a room in `Logic/FloorPlanner`), `Logic/ThreatBrain.advanceContactSeconds`. **A creature the player cannot tell apart from another is not a second row** — it is one row with a curve |
| Threat model geometry, local creature animation, or visual culling | `client/ThreatVisualController.luau` / `shared/NewModelsAndObjects/` | `server/ThreatVisualProxy`, `server/ThreatService`, `Config/Threats.visuals.procedural`, `Tests/ThreatAnimationConfigTests`, `Config/Feel.debug` |
| Creature attack phases/audio, victim-only hit sting, or how often a threat in contact visibly swings | `shared/NewModelsAndObjects/DarkCrawler.luau` / `CaveMoth.luau` / `CeilingFly.luau` / `CaveListener.luau` / `Knotwalker.luau` / `Calver.luau` (`strike`, `consumeImpact`) / `client/ThreatVisualController.luau` | `Config/Threats.visuals.procedural.attackMotion`/`attackAudio`, `ThreatVisualProtocol.attributes.attack`/`attackVictim`, `server/ThreatVisualProxy.signalAttack`, `server/ThreatService.applyContact`, `Config/Audio.cues.*Lunge`/`*Attack`/`ThreatHit`, `Tests/ThreatAnimationConfigTests`. Ordinary attacks echo confirmed contact; only Calver uses `intentSequence`/`intentStartedAt`/`intentAction` to reconstruct a pre-effect ceiling hammer from server time |
| Threat footsteps, moth wingbeats, or how loud a creature's movement is at a given speed | `shared/NewModelsAndObjects/DarkCrawler.luau` / `CaveListener.luau` / `Knotwalker.luau` (`consumeFootfall`) / `client/ThreatVisualController.luau` | `Config/Threats.visuals.procedural.locomotionAudio`, per-kind step cues, `Config/Audio.cues.MothWing`, `client/AudioCues.playAt` level multiplier |
| Threat AI, crawler light bands/retreat memory, room/pool routing, Terrain-only ground-following, ceiling-ambush dive/return, roof-strike, route interception, movement, or contact | `Logic/ThreatBrain.luau` / `Logic/RoomNavigation.luau` | `server/ThreatService`, `server/SurfaceProbe`, `Logic/ThreatRules.roofStructuralClearanceRadius`, `Logic/LightField`, `server/LightSources`, `Config/Threats.behavior`, `Config/Threats.definitions.*.ambush`/`.ceilingStrike`/`.intercept`, `Logic/FloorPlanner`, `server/FloorBuilder`, `Config/Floors.terrain`. Roof-bound homes reserve/carve their full territory plus body radius; a Terrain Spherecast stops patrol/pursuit before structural rock |
| Threat-visible light source | `server/LightSources.luau` | `Logic/LightField`, `WaxService`, `ToolService`, `RemainsService` |
| Localized water pools, wading, water lethality, or hazard animation | `server/HazardService.luau` / `server/FloorBuilder.luau` | `Logic/FloorPlanner`, `Logic/HazardRules`, `Config/Hazards`, `WaxService`, `client/EnvironmentAnimationController` |
| How often water appears at all, or how many pools a wet floor carries | `Config/Floors.floodedFloorChance` / `.floodedRoomsPerFloor` | `Logic/FloorPlanner` (`weightedModule`, `guaranteeDryRoute`, `enforceFloodedBudget`), `Config/Floors.roomModules` weights (kind of pool only) |
| Unstable-dripstone count curve, eligibility, variant, trigger, fall, impact, wax loss, low-wax snuff, or first-fall tutorial | `Logic/DripstoneRules.luau` / `server/DripstoneService.luau` | `Config/Hazards.unstableDripstone`, `Config/Feel.tutorialHints`, `Logic/FloorPlanner`, `server/FloorBuilder`, `WaxService`, `DeathService`, `client/HintController`, `LightSources`, `Types/World.DripstonePlacement` |
| Dangerous-dripstone model, fracture tell, warning/fall animation, dust/debris, shake, or impact grading | `shared/NewModelsAndObjects/UnstableDripstone.luau` / `client/DripstoneController.luau` | `shared/DripstoneVisualProtocol`, `Logic/DripstoneRules`, `Config/Hazards.unstableDripstone`, `Config/Audio`, `Net/Remotes.RunEvent` |
| Optional doorway barriers: safe placement, Moss vine density, vine ignition/spread, Ice melt rates, the icicle barricade's crust/fang/spike/bloom art, or the 10-second meltwater puddle | `Config/Vines.luau` / `Config/Icicles.luau` / `Logic/VineRules.luau` / `Logic/IcicleRules.luau` / `server/VineService.luau` | `Config/CaveFamilies.environment.doorwayBarrierStyle`, `Logic/FloorPlanner`, `server/FloorBuilder`, `Types/SacrificeModifiers.maxBurnRate`, `Types/World.VinePlacement`, `Net/Remotes.RunEvent`. Thresholds resolve against each candle's current ceiling, so Basin brightness penalties never disable clearing. Historical `VinePlacement`/`VineService` names own both styles; no service branches on family id. The barricade's geometry is built by `FloorBuilder` and handed to `VineService` sorted by MELT RANK (thin tips first, welded crust last), so a piece's index is how deep into the ice it sits — reordering that list changes how the melt looks |
| **A cave's overall colour temperature** — "this cave looks warm/muddy/orange and should look cold" | `Config/CaveFamilies.luau` (`presentation.colorGrade`) | `Logic/CaveFamilyRules.colorGrade` clamps it; `server/EnvironmentSetup.applyCaveFamily` mounts one named `ColorCorrectionEffect`. **Do NOT reach for a material palette — it cannot work.** `EnvironmentSetup.apply` pins Ambient/OutdoorAmbient/Brightness to black, so every lit pixel comes from one warm carried flame and `surface × light` means a blue surface renders warm no matter how blue it is authored. The grade multiplies the final image, so it recolours without adding light; every channel is clamped ≤ 1 so it can only ever subtract, and black stays black |
| A cave family's surface dressing: how its walls/formations catch the candle, a second material layer over its floor, or the icicle fringe across its ceilings and doorway mouths | `Config/CaveFamilies.luau` (`presentation.coverFinish` / `formationFinish` / `floorGlaze` / `icicleFringe`) | `Logic/CaveFamilyRules` resolves them and owns `surfaceFinishVaries`; `server/FloorBuilder.newMossPatch` + the ceiling-facet pass apply the cover finish, `CaveKit.configure` carries the formation finish into every spire/boulder/column; `CaveKit.icicles` is the spike form. **A material is read by specular behaviour before hue — reach for the reflectance/transparency RANGES before recolouring anything.** Nothing emits: a self-lit variant was built and cut. Every count is zero and every finish neutral in Stone and Moss, and each pass must consume ZERO random rolls in that case or the Stone regression baseline shifts |
| Ashamed Lurker placement, trip lane, grab, stare-to-clear, relocation, or procedural state poses | `Config/AshamedLurker.luau` / `Logic/AshamedLurkerRules.luau` / `server/AshamedLurkerService.luau` / `NewModelsAndObjects/AshamedLurker.luau` | `Logic/FloorPlanner` (`planLurkers`), `server/FloorBuilder` (proxy + `LurkerSite`; probes built Terrain at the guaranteed-open inner lane and carries that Y to the doorway root), `server/SurfaceProbe`, `shared/AshamedLurkerVisualProtocol`, `client/AshamedLurkerController`, `Net/Remotes.LurkerGaze`, `Config/Security.remoteRateLimits.LurkerGaze`, `WaxService.drainExternal`, `Types/World.LurkerPlacement`, `Tests/AshamedLurkerRulesTests`. The socket/backplate remain intentionally embedded masonry; the built-floor probe prevents the whole flesh body shifting vertically into the arch. `triggeredStateSeconds` is grab delay + full recovery; `visualLungeStuds` separately clamps presentation inside the trapped half. A survived grab fires `Config/Feel.tutorialHints.AshamedLurker` once per player through `Interfaces/Persistence.claimFirstSighting`; `drainExternal` keeps source id `"AshamedLurker"` for the matching death hint |
| Stone Warden room selection, fixture/collapse, spawn, pathing, immediate touch death, Motor6D motion, stun, or hazard interaction | `Config/StoneWarden.luau` / `Logic/FloorPlanner.luau` / `server/StoneWardenService.luau` / `server/StoneWardenSystem/StoneWardenBehavior.lua` / `StoneWardenModel.lua` / `StoneWardenAnimator.lua` | `client/StoneWardenController`, `server/SurfaceProbe` (the wax tray and pile use exact measured support; the tray is normal-aligned before its pieces are mounted), `server/WardenRegistry.luau`, `server/DripstoneService.triggerNearest`, `Config/Hazards.unstableDripstone.wardenStunSeconds`, `Net/Remotes.RunEvent("wardenCollapse"/"wardenAttack")`, `Tests/StoneWardenConfigTests`, `RunOrchestrator`, `Types/World.WardenPlacement`. Path failure holds position and retries instead of walking directly through cave rock. Only the invisible 6×12×4 root collides/queries/touches; visible slabs are massless and neutral. Contact follow-through begins after `DeathService.kill` and can never become a warning window |
| The dead candle tableau: depth gate, roll, which room may hold it, ring layout, corpse prop | `Config/DeadCandle.luau` / `Logic/DeadCandleRules.luau` / `NewModelsAndObjects/DeadCandle.luau` / `server/DeadCandleService.luau` | `Logic/FloorPlanner` (places it after the threat budget and before the locked store; emits its pickups into `lootSpawns` and its flies into `threatSpawns` so roof-dressing reservation and the no-double-jeopardy dripstone rule apply for free), `server/FloorBuilder` (corpse reservation + flat pad), `server/SurfaceProbe`, `RunOrchestrator` (`populate("dead_candle")`, `plannedDeadCandle`/`builtDeadCandle` in the spawn audit), `Types/World.DeadCandlePlacement`, `Tests/DeadCandleRulesTests`. The prop is scenery only — no prompt, no collision, no light; the encounter IS its ordinary loot and ordinary creatures, arranged |
| VoidFly patrol path, structural clearance, harassment commitment, chase speed, or what noise does to one | `Config/Threats.definitions.VoidFly.ambush` + `.hearing` | `Logic/ThreatBrain` (`patrolTarget`, `thinkAmbusher`, the `step` leash and pursuit speed), `Logic/ThreatRules.roofProfile` / `roofStructuralClearanceRadius`, `Logic/FloorPlanner` + `server/FloorBuilder` (fit/reserve/carve full territory plus body radius), `server/ThreatService` (Terrain Spherecast and `ambushNeedsImmediateReaction`), `Types/Threat.AmbushProfile`/`ThreatState.pursuitUntil`, `Tests/ThreatBrainTests` / `ThreatRulesTests` / `FloorPlannerTests`. Pursuit reach is preserved; real structural rock stops the body |
| The wick-pack: per-species floor budget, pairing rules (never two Gnawers, Gnawer+Longarm needs a large room), or which cave dresses which body | `Logic/EnemySpawnRules.luau` (budget) + `Logic/EnemyVariantRules.luau` (dressing) | `Config/WaxGrub` / `Config/StoneGnawer` / `Config/Longarm` (per-creature tuning, all rescaled from the vendored pack's raw units to fractions of `Config.Wax.maxWax` — see each file's header), `shared/Enemies/*` (builders, animation, the pack's own `VariantStats`/`ElderStats`, mirrored not required — see `EnemyVariantRules` header for why requiring the pack directly was reverted), `server/EnemyService` (one shared tick for every live body), `server/EnemyRegistry` (dynamite-blast lookup, mirrors `WardenRegistry`), `Tests/EnemySpawnRulesTests`, `docs/wick-enemies/ENCOUNTERS.md` (pairing rationale) / `VARIANTS.md` (dressing rationale). Budgeted per species against depth rather than drawn from the shared per-room threat roll, so pairing rules can be enforced structurally |
| Wax Grub latch/drain, stomp-to-scare, or drip-trail feeding | `shared/Enemies/WaxGrub.luau` (model/animation) + `server/EnemySystem/WaxGrubBehavior.luau` (authority) | `Config/WaxGrub`, `server/DripTrailService.getTrail`/`consume` (trail-following and eating a caught-up-to drop is NEW, not in the vendored pack), `server/WaxService.drainExternal`, `Config/Feel.itemHints.WaxGrub`/`shakeHintCooldownSeconds`. Stomping scares; it never kills — there is no player attack, and a grub that died to a footstep would make the brood pointless |
| Stone Gnawer's eat/listen/warn/charge/stagger state machine, its hearing reach per noise kind, or its long-range "hunt a structural noise" channel | `shared/Enemies/StoneGnawer.luau` (model/animation) + `server/EnemySystem/StoneGnawerBehavior.luau` (authority) | `Config/StoneGnawer` (`hearSprint`/`hearWalk`/`hearLanding`/`hearDripstone`, `huntRadius`/`huntKinds` — two separate channels, never blurred), `Logic/SoundField`, `server/NoiseService`, `server/WaxService.drainExternal` (`chargeDamage` is a wax-drain fraction, not Humanoid damage). The charge cannot be steered by pathfinding once committed — that IS the counter |
| Longarm's fold-to-fit-doorways stoop, its two-band reach (slash vs. grab), the post-grab ignore window, or decoy preference | `shared/Enemies/Longarm.luau` (model/animation, `Stance.stoopHeight`/`stoopRide` measured off the built rig) + `server/EnemySystem/LongarmBehavior.luau` (authority) | `Config/Longarm` (`reachMax`/`reachGrab`, `grazeDamage`/`grabDamage` rescaled to `Config.Wax.maxWax` fractions, `ignoreSeconds` — NOT OPTIONAL, see file header), `server/WaxService.drainExternal`, `client/DynamiteViewmodelController` unrelated. In the `flee` state it paths AWAY from its target toward a decoy, ignoring its normal target entirely |
| The Grub Queen's boss floor layout, her resource-race encounter, sealed mid-fight mining caches, or the mandatory-kill descent gate | `shared/Logic/BossFloorPlan.luau` (the authored five-room plus-shaped floor) + `server/BossEncounterService.luau` (her, her two chained Longarm guards, and the sealed caches) | `Config/GrubQueen` (`health`/`dynamiteDamage` as a flat charge count, never distance-scaled; `requiresKillToDescend`), `shared/Enemies/GrubQueen.luau`, `server/EnemySystem/GrubQueenBehavior.luau`, `server/QueenRegistry.luau` (dynamite-blast lookup, mirrors `WardenRegistry` — she is NOT in `EnemyRegistry`, because her damage model is a different shape), `server/RunOrchestrator.canDescendFrom` (refuses descent from a Queen floor while she's alive), `server/MiningService` (the sealed caches are ordinary deposits), `server/LootService` (respawning wax/dynamite `lootSpawns`, wax faster than dynamite — see `BossFloorPlan.WAX_RESPAWN_SECONDS`/`DYNAMITE_RESPAWN_SECONDS`), `DESIGN.md §9a`. This is the one hazard in the game a party cannot simply avoid |
| The Knotwalker's doorway tripwire: laying it, catching a player, the speed-scaled stun, burning it off, or expiry | `server/TripwireService.luau` (authority — outlives the creature that laid it, tested as a swept segment against the player's last-tick position, never a proximity check) | `Config/Tripwire` (geometry, trip stun band, burn-off timing), `Logic/TripwireRules.trips` (the swept-segment math), `Config/Threats.Knotwalker.trapline` (how many wires, laying tell, response radius — the CREATURE's numbers; the wire's own physics live in `Config/Tripwire` regardless of who strung it), `Logic/VineRules.burnsVines` (the burn-off reuses the SAME brightness gate a vine curtain answers to, deliberately, so the dial means one thing everywhere), `client/TripwireController`, `Net/Remotes.RunEvent`. Retired the Knotwalker's earlier route-interception AI outright rather than keeping both — see `Config/Threats.Knotwalker` header |
| Whether jumping is audible to the cave | `Config/Sound.emitters.Landing` | `server/DripTrailService` (emits on the airborne→grounded transition), `server/CharacterService.isAirborne`, `Logic/SoundField`, `Tests/SoundFieldTests`. Only the landing emits — walking stays silent, which is the Cave Listener's contract |
| Cave moss on walls and around waterlines | `Config/Floors.caveMoss` | `server/FloorBuilder`, `Config/Hazards.waterPool.shoreMoss*` |
| Snuffing, teammate relighting, solo Match self-relighting, burnout, death results | `server/DeathService.luau` | `Config/Death`, `Config/Loot`, `Logic/LootRules`, `client/RelightPromptController`, `WaxService`, `CharacterService`, `Interfaces/Remains`, `server/SpectatorService` (owns everything after the death). `snuff`/`kill`/`burnOut` take an optional trailing `sourceId` (the killing threat/hazard's id, e.g. `"Moth"`, `"StoneWarden"`) threaded through to the `"results"` RunEvent as `deathSourceId`, for `Config/Feel.deathHints` |
| What a terminally dead player IS: the ghost candle's body, its walk speed, its almost-nothing light, following a teammate, or the ghost-only footfall trail | `Config/Spectator.luau` | `Logic/SpectatorRules` (every decision), `server/SpectatorService` (authority), `server/CharacterService.spawnSpectator` (the body + collision groups), `client/SpectatorController` (marks, readout, key), `Net/Remotes.SpectatorAction`/`SpectatorState`, `Config/Feel.controls.spectatorFollowKey`, `Tests/SpectatorRulesTests`. Two rules may never be relaxed: a ghost never enters `server/LightSources` (nothing in the cave may perceive it), and trail samples are sent ONLY to players who are dead |
| Where a ghost may be put when it follows | `Logic/SpectatorRules.anchorPosition` + `server/SpectatorService.anchorTo` | The anchor is always a living teammate's own feet, so a ghost can only ever appear somewhere a living player already is. Never offset it sideways (rock) and never let it lead the party |
| Session remains storage, placement, recovery, or light | `server/RemainsService.luau` | `Interfaces/Remains`, `Config/Remains`, `DeathService`, `LightSources`, `RunOrchestrator` |
| End-of-run screen, death debug, replay, whole-party return, or a resolved survivor's early main-lobby extraction/party-bonus forfeit | `client/ResultsText.luau` / `server/RunOrchestrator.luau` | `server/DeathService`, `server/ExtractionService.forfeitPartyBonus`, `server/PartyLobbyService.returnPlayerToMainLobby`, `Net/Remotes`, `server/SpectatorService` (the "WATCH THE PARTY" dismiss is only offered while `partyStillInside`, and the card returns by itself on `runResolved`) |
| Non-glowing wax-drop trails or hunter breadcrumbs | `server/DripTrailService.luau` | `Config/DripTrail`, `ThreatService`, `Logic/ThreatBrain` |
| Basin offers, progressive prerequisites, explicit card explanations, acknowledged choice transaction, flat grant band, sacrifice choices/modifiers, or permanent vision costs | `server/BasinService.luau` | `Logic/SacrificeRules`, `Config/Basin`, `Types/Sacrifice`, `server/CharacterService.basePosition` (live proximity validation), `server/WaxService` (`StateSync`), `client/BasinPrompt`, `client/FeelController`, `server/ToolService` (Flare/Decoy duration), `server/DeathService` (relight cost), `PlayerState`, `RunEvent("basinChoice")` |
| Brazier preview/payout, individual or unanimous group extraction, or Raw-Wax extraction economy (gram value by origin depth, cave/contract/party permille scalars) | `server/BrazierService.luau` | `Logic/ExtractionValue` (the only place cargo becomes currency — exact integer permille math, `maxSinglePayout` caps it), `Logic/CargoRules`, `Config/Brazier` (fixture look + validation/hold, DESIGN §12), `Config/Extraction` (`valuePerGramPermilleByDepth`, origin-depth pricing, cave admission fees), `server/ExtractionService.unresolvedPartyMembers` (authoritative ready denominator; the party bonus is settled here as an "everyone came back" credit, not a proximity check at the brazier), `Interfaces/Persistence`, `client/ResultsText`, `RunEvent`. **Reverted from a one-iteration "Gas Lantern"**: no lamp list, no floor-wide cascade, no five-second free-look, no camera turn, and no enemy purge on ignition live here any more — lighting a brazier reaches nothing outside its own room. What's left: hold a prompt, get paid, see your card. Living Wax pays nothing; only mined Raw Wax, priced by the depth it was mined FROM (never where it's cashed in), does |
| Lighting the cave as a mid-run player verb: room wall lamps, the completion room's crowned lamp, and the floor-wide catch cascade it triggers | `server/WallLampService.luau` | `Config/WallLamp` (geometry, output, interaction hold times, cascade timing), `Logic/WallLampRules` (hold-satisfied gate, re-validated at the moment of light, not just at hold-start), `NewModelsAndObjects/WallLamp`, `server/FloorBuilder` (deterministic per-room wall selection, Terrain-probed mounting, never a carved recess), `server/LightSources` (every lit lamp joins the same perception field as flames/flares/decoys/remains — dark-hunters pushed out, the Drawn pulled in), `client/WallLampController`, `client/LampPresentation` (the crowned lamp's aura breathing), `Config/Lantern` (now ONLY the decorative, non-perceived work lamp on the Descent Ladder headframe — the last surviving piece of the retired Gas Lantern fixture set). Free in wax, priced in attention: no cost tag, because standing rooted in the open lighting one IS the cost |
| What the Basin's Cauldron, the Gas Lantern and the Descent Ladder LOOK like, or what a cave family builds them from | `Config/Cauldron.luau` / `Config/Lantern.luau` / `Config/DescentLadder.luau` + `NewModelsAndObjects/Cauldron`,`Lantern`,`DescentLadder` | `Config/CaveFamilies.presentation.fixtureStyle` (per-family palette and rig), `Logic/CaveFamilyRules.fixtureStyle`, `Types/Fixtures`, `server/FloorBuilder` (builds all three and carves the shaft), `client/EnvironmentAnimationController` (the Cauldron's ripple), `Tests/CaveFamilyRulesTests`. PRESENTATION ONLY, deliberately split from `Config/Basin` and `Config/Brazier`, which own the rules these fixtures wear |
| The way down: the elevator prompt, ride/exit/return clocks, cage/hatch/gate poses, rider capture, in-cage containment, one-way ejection, or temporary enemy grace | `server/DescentLadderService.luau` | `Config/DescentLadder` (including `riderCapacity`, `arrival`, and return timing), `Logic/DescentElevatorRules` (pure timeline/deck/exit rules), `NewModelsAndObjects/DescentLadder` (invisible containment behind the open frame), `server/RunOrchestrator` (answers "may they go?" and accepts the exact lower-cage landing), `PlayerState.threatProtectedUntil`, `server/ThreatService`, `server/AshamedLurkerService`, `server/StoneWardenBehavior`, `server/CharacterService.setRunBodyRideControlled` (server-owned but unanchored movement), `server/MovementSanityService`, `client/DescentLadderController`, `RunEvent("descentRide"|"descentReturn")`, `Tests/DescentElevatorRulesTests`. THE CAGE CARRIES TWO and resolves each arrival independently. Riders may move and look freely only inside its closed boundary; after landing, leaving is permanent for that cycle; lingering or entering players are pushed out, then collision-safely placed before the gate shuts and the empty cage returns visibly |
| Floor topology, room selection, deterministic separated threat/loot offsets, Warden branch, ceiling eligibility, guaranteed ground patches, pool footprints, dangerous-dripstone placement, or successor-floor world alignment | `Logic/FloorPlanner.luau` / `Logic/FloorStacking.luau` | `Config/Floors`, `Config/Threats`, `Config/Hazards`, `Config/StoneWarden`, `Logic/PlacementReservations`, `Logic/DripstoneRules`, `Logic/GroundGeometry`, `Logic/RoofGeometry`, `Logic/DoorwayGeometry`, `Types/World.worldOrigin`, `server/RunOrchestrator`, `server/FloorBuilder`, `Tests/FloorStackingTests`. Grid topology remains floor-local; only world X/Z translates so each successor entry sits under the prior completion elevator |
| Cave geometry, recessed floors, CaveKit formations, gameplay dressing reservations, Lurker-arch protection, per-edge doorway sizing, hazard zones, or exact room-surface handoff | `server/FloorBuilder.luau` | `server/ThreatService`, `shared/NewModelsAndObjects/CaveKit`, `shared/NewModelsAndObjects/UnstableDripstone`, `Config/Floors.geometry`, `.caveDressing`, `.terrain`, `.roof`, `Logic/PlacementReservations`, `Config/Threats`, `Config/Hazards`, `HazardService`, `Logic/FloorPlanner`, `Logic/GroundGeometry`, `Logic/RoofGeometry` |
| How rare the abandoned mining equipment is, which piece a floor gets, where one may stand, or what it is made of | `Config/MineRelics.luau` / `Logic/MineRelicRules.luau` | `NewModelsAndObjects/MineRelics` (the eleven silhouettes), `server/FloorBuilder` (the placement sweep, run right before the boulder/column dressing so a relic reserves against them), `Logic/RoomFootprint.clearOfRoutes`, `Logic/PlacementReservations`, `Logic/CaveFamilyRules.relicWeathering`, `shared/MineRelicVisualProtocol`, `Config/Feel.ambientRelic`, `Tests/MineRelicRulesTests`. PURE DRESSING: no loot, no prompt, no light/sound field, no rule reads one. Collision sits on mass only — ground-flush rails and spill stay non-collidable, because a collidable object at ankle height is a movement snag rather than an obstacle. `footprintRadius`/`wallOffset` must cover what the geometry actually reaches, and `clearOfRoutes` is what keeps collidable mass out of every doorway lane and the navigation hub |
| Cave-floor height field, swells, doorway lanes, pools, or a gameplay placement's exact local ground | `Logic/GroundGeometry.luau` | `Config/Floors`, `Logic/DoorwayGeometry`, `Logic/FloorPlanner`, `server/FloorBuilder` |
| Inverted Terrain roof shape, relief seed, edge blending, rock thickness, minimum clearance, or exact underside height | `Logic/RoofGeometry.luau` / `server/FloorBuilder.luau` | `Config/Floors.roof`, `Logic/GroundGeometry`, `Logic/FloorPlanner`, `shared/NewModelsAndObjects/CaveKit` |
| Expedition countdown, runner inclusion, separated multiplayer entry slots, uncapped on-demand floor construction, descent, replay, lobby return, or reset | `server/RunOrchestrator.luau` / `Logic/EntrySpawnRules.luau` | `server/PartyLobbyService`, `Config/RunSettings`, `Config/Character`, `Config/Floors`, `FloorPlanner`, `FloorBuilder`, service `reset`s |
| How much of a cave the descent WAITS for, versus how much arrives afterwards | `server/RunOrchestrator.luau` (`ensureLookahead` / `buildOnePendingFloor`) | `Config/RunSettings.floorLookahead`; floor one is the only mandatory initial build and everything else is queued and drained one floor per frame. If lookahead misses, `canDescendFrom` builds the immediate successor synchronously before the descent service commits riders or broadcasts the ride. This guard can cost a frame, but it guarantees the physical landing exists before motion begins. Timings land in `floor_spawn_audit` (`planMs`/`carveMs`/`populateMs`) and `run_started` (`blockingFloorMs`) telemetry, and `replicatedfirst/WickLoadingScreen.client.luau` prints which startup gate held the screen |
| Remote rate limits or finite-payload validation | `server/RequestGuard.luau` | `Logic/TokenBucket`, `Config/Security`, every inbound remote handler |
| Impossible-movement correction | `server/MovementSanityService.luau` | `Config/Security`, `Config/Movement`, approved burst credits in `MovementService`, authorized teleports in `RunOrchestrator`, `CharacterService` |
| Prototype server-log telemetry | `server/Telemetry.luau` | `Config/Security`, emitting service |
| HUD or run messages | relevant file in `src/client/` | `Net/Remotes`; `ResultsText` handles `RunEvent`, `WaxBar` handles `StateSync`, `HotbarController` handles `ActionFeedback` plus cooldown reconciliation |
| Cursor capture, clickable UI cursor release, or native Roblox menu interaction | `client/CursorController.luau` | the UI controller that opens the screen, `WickInExpedition`, `client/CameraController` |
| Landing or active-run local presentation settings (mouse sensitivity, master audio, music, or ambience) | `client/SettingsController.luau` | `Config/Audio.settings`, `client/CursorController`, `client/AudioCues`, `client/MusicController`, `WickInExpedition`, `WickShopOpen` (mutual exclusion with the shop) |
| In-elevator party panel, cursor release, roster/leader/kick controls, ready button, cave votes, cave cost/benefit cards, or explicit leave | `client/PartyPanelController.luau` | `client/CursorController`, `server/ElevatorService`, `server/PartyLobbyService`, `Config/CaveFamilies` (static benefits), `Interfaces/CaveTiers` (server-authored costs), `Net/Remotes.LobbyAction`/`LobbyState` |
| Lobby status readout or lobby/expedition/test-lab gameplay-GUI toggling | `client/LobbyController.luau` | `server/PartyLobbyService`, `WickInExpedition`, `Net/Remotes.LobbyState` / `DevTestRoom` |
| Gameplay input enabled/disabled across lobby/run/test-lab transitions | `client/LobbyController.luau` | `client/DialController`, `client/ToolController`, `WickInExpedition` player attribute |
| Low-wax, water grading, or nearby-threat cue and flicker context | `client/FeelController.luau` / `client/WaxBar.luau` | `Config/Feel`, `client/CandleLightController`, `client/AudioCues`, `Net/Remotes`, `WaxService` |
| Harmless cave one-shot timing, silence probability, anti-repeat history, focus-audio gating, surface/water eligibility, or the per-family soundscape | `client/AmbientCaveDirector.luau` | `Config/Feel.ambientCave`, `Config/CaveFamilies.ambience`, `Logic/CaveFamilyRules.ambientWeightMultiplier`, `RunEvent("floor").familyId`, `Config/Audio.cues.Cave*`, `client/AudioCues.isBusQuiet`, `AmbientRockfallController`, `AmbientWaterDripController`. Three candidates are NOT rows in `ambientCave.soundEvents` and are weighted by the shared id constants on `CaveFamilyRules` (`ambientRockfallId`/`ambientWaterDripId`/`ambientRelicId`); every family must answer for all of them or `CaveFamilyRules.validate` and `Tests/AudioConfigTests` fail |
| The abandoned workings settling — the one ambient event anchored to a real object rather than a raycast surface | `Config/Feel.ambientRelic` / `client/AmbientCaveDirector.playRelicEvent` | `Config/Audio.cues.CaveOldWorkings`, `shared/MineRelicVisualProtocol` (tag + emitter attachment), `Config/MineRelics`, `Config/CaveFamilies.ambience.candidateWeights.OldWorkings`, `Config/Feel.ambientCave.relicWeight`. It refuses when no tagged relic is in range, which is most floors — a fallback emitter would make every cave sound like it had machinery in it |
| Ambient loose-rock placement/roll or ceiling-drip placement (presentation only; no timers) | `client/AmbientRockfallController.luau` / `client/AmbientWaterDripController.luau` | `Config/Feel.ambientRockfall` / `.ambientWaterDrip`, `client/AmbientCaveDirector`, `NewModelsAndObjects/CaveKit.looseRock` |
| First-three-floor threat, dripstone, water, or gust teaching hints | `client/HintController.luau` | `server/ThreatService`, `server/DripstoneService`, `Config/Feel.tutorialHints`, `Net/Remotes.TutorialHint`, `WaxService` (`StateSync`) |
| The once-ever line explaining what a pickup does, shown the first time a player collects that item | `Config/Feel.itemHints` | `server/LootService` (fires it), `Interfaces/Persistence.claimFirstSighting` (the test-and-set that makes it once-ever, backed by `Profile.seenHints`), `client/HintController` (`resolve`, which exempts one-shot hints from the depth cap and throttles), `Net/Remotes.TutorialHint` |
| The "next time" line on the results screen explaining what to do differently, keyed by which threat/hazard actually killed the player | `Config/Feel.deathHints` | `server/DeathService` (threads a `sourceId` from every `kill`/`snuff`/`burnOut` call site through to `RunEvent("results").deathSourceId`), `client/ResultsText.luau` (`showResults`, looks up `deathSourceId` falling back to `deathCause`; a real player-facing element, not gated behind `Config.Feel.debug.showDeathDebug`). Every `WaxService.drainExternal` caller also passes a matching trailing `sourceId` |
| Sound cue, mix bus, variation, voice budget, cave processing, obstruction filter, ducking, rolloff, preload failure handling, loop, or cooldown | `Config/Audio.luau` | `client/AudioCues`, `client/MusicController`, `Tests/AudioConfigTests`, and the controller that requests the named cue |
| VoidFly buzz timing, proximity, cave-wall suppression, or stable ceiling-flight presentation | `client/ThreatVisualController.luau` | `NewModelsAndObjects/ThreatVisualRules` owns the pure one-way launch transition that prevents patrol pauses from reversing the cling pose; `Config/Threats.visuals.procedural.ceilingFlyBuzz`, `Config/Audio.cues.FlyBuzz`, `client/AudioCues`, `Tests/ThreatAnimationConfigTests` |
| Music playlist order/delays, fades, or the per-client Music-bus slider | `client/MusicController.luau` / `client/SettingsController.luau` | `Config/Audio.music` / `.settings`, `client/AudioCues`, `WickInExpedition` |
| Keyboard/touch binding or visible control hotbar | `Config/Feel.luau` | `client/HotbarController`, `ToolController`, `client/DynamiteController`. Dynamite throw acknowledgement is visual-only; its control row deliberately carries no audio cue |
| Shared UI palette, fonts, motion presets, or the composited WICK wordmark/candle-glyph widgets | `client/UITheme.luau` | every themed UI controller (`LobbyController`, `PartyPanelController`, `BasinPrompt`, `ResultsText`, `SettingsController`, `WaxBar`, `HotbarController`); `replicatedfirst/WickLoadingScreen.client.luau` duplicates the wordmark/glyph inline and must be kept in sync by hand |
| World darkness / Lighting setup at runtime, or the uncapped-floor falling-part kill-plane | `server/EnvironmentSetup.luau` (`reserveDepth`) / `default.project.json` | `default.project.json` owns Studio-edit-mode Lighting/Atmosphere defaults and a deep static `FallenPartsDestroyHeight`; at runtime `RunOrchestrator.buildFloor` calls `EnvironmentSetup.reserveDepth(FloorBuilder.baseY(floor))` for every floor it carves, because depth is uncapped and Roblox's default boundary (-500) sits between floor 6 and floor 7 |
| A runner who has lost their body or fallen out of a floor | `server/RunOrchestrator.luau` (`recoverStrandedRunners`) | `CharacterService.hasIntactBody`, `DeathService.rebindRelightPrompt`, `Config/RunSettings.floorRecoveryDrop`; a repair that preserves wax, cargo and depth — never a death |
| Earliest-possible boot/loading screen or bodyless-stall diagnosis | `replicatedfirst/WickLoadingScreen.client.luau` | `server/Telemetry.loadingStage` publishes `Workspace.WickLoadingStage`/`WickLoadingStageSince`; authorized TeleportData makes the live loading diagnostics panel name the blocked gate and server phase before StarterPlayerScripts exist. `client/UITheme.luau` is the module the screen duplicates because ReplicatedFirst cannot require `ReplicatedStorage.Shared` this early. Gates in order: `body` (a Character exists) → `camera` (`CurrentCamera.CameraSubject` is that body's humanoid, i.e. `client/CameraController` has bound; bounded by `MAX_SECONDS` because it depends on StarterPlayerScripts rather than on the server) → `replication` → `minimumBeat` → `assets`. The camera gate is a second line of defence behind the `LandingSpawn` fix above: it is what guarantees the screen never lifts while the view is still parked somewhere that is not the player's own body |
| PIN-gated developer diagnostics, red through-wall ore/enemy/item/descent markers, or live client/server stats | `client/DevDiagnosticsController.luau` / `server/DevDiagnosticsService.luau` | `replicatedfirst/WickLoadingScreen.client.luau` (teleport/loading continuity), `Config/Diagnostics`, `Config/Security.remoteRateLimits.DevDiagnostics`, `Net/Remotes.DevDiagnostics`, `client/ThreatVisualController`/`AshamedLurkerController` (tag their locally built bodies), `server/LootService` (tags and names active pickup spawns), `server/FloorBuilder` (tags every next-floor beam), `server/PartyLobbyService`/`RejoinService` (carry per-player authorization across teleports), and `server/StoneWardenSystem/StoneWardenBehavior` (Warden discovery tag). Unlock is server-authorized from a Landing body; every marker and panel is created locally and is observation-only |
| PIN-gated physical enemy test room, its lobby terminal/console geometry, cave-grouped compact picker, static entity field guide, infinite test candle, ordinary/set-piece spawn controls, containment/throttling, or scoped teardown | `server/DevTestRoomService.luau` / `server/DevTestRoomBuilder.luau` | `Config/DevTestRoom` (`controls.boards` owns the grouped panels — one column per cave on the picker, grouped by what a press changes on the tools board, both reflowed by the builder from `controls.buttonSize`/`buttonSpacing`/`buttonTopInset` and each group's `columns`, with the row/height budget asserted in `Tests/DevTestRoomRulesTests`; `guide.boards` owns canonical behavior/counter cards), `Logic/DevTestRoomRules`, `server/DevTestSessionRegistry`, `client/DevTestRoomController`, `Net/Remotes.DevTestRoom`, `Config/Security.remoteRateLimits.DevTestRoom`, `ThreatService.spawnTest/clearTest/updateTestTargets`, `ToolService.setDevTestGeometry`, `AshamedLurkerService.clearDepth`, `DripstoneService.clearDepth`, `StoneWardenService.spawnEncounter`, `WaxService`/`DeathService` (protected test authority). Diagnostics authorization remains observation-only; this separate session owns every mutation and accepts no remote spawn action |
| Remote contract | `shared/Net/Remotes.luau` | every sender and receiver |
| Domain data shape | matching `shared/Types/*.luau` | `Types/init.luau`, config and consumers |
| Lineage stub or future carryover design | `shared/Interfaces/Lineage.luau` | `DESIGN.md`, `Interfaces/init.luau`; add no consumer until the design is settled |

## Directory ownership

### `src/shared/Config/` — tuning and content data

Each file owns one data domain; `Config/init.luau` aggregates them. Add values and generic content here, not behaviour branches.

- `Wax`, `CandleModifiers`: candle economy, and the in-run roguelike modifier pool a run stacks onto
  a neutral candle (Life/Bright/Frozen Wax, Extra Wicks, Candle Sleeve). There are no swappable burn
  profiles; the live profile is derived by `Logic/CandleModifiers.profile`.
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
- `Dynamite`: the found consumable (DESIGN §6a) and the sealed vaults it opens — supply cadence and
  carry cap, both fuses, the throw's placement bounds, blast radius/self-damage/floor alarm,
  per-creature and Warden lethality, the door's break radius and prompts, vault rolls and stock, and
  every visual value for the stick, the crate, the socket marker and the family-styled door. Four of
  its values bound the no-combat exception rather than tune it; they are called out in the file.
- `DeadCandle`: the Floor 10+ tableau — depth gate, per-floor chance, how many pickups and flies it
  brings, the two ring radii they are laid out on, and the burned-out candle prop's own geometry and
  cold wax colours. It owns no stat: the creatures are the ordinary VoidFly row and the pickups are
  ordinary loot rolls.
- `StoneWarden`: encounter depth/chance, planner-only room identity and offsets, protected pad size,
  guarded-wax tray/pickup footprint, opening-collapse formations and tremor, emergence/chase timing,
  attack presentation, and movement speed.
- `Extraction`: the authoritative Raw Wax economy — the per-gram depth curve, cargo cap in grams,
  party bonus, contracts, disconnect/forfeit rules, and persistence-facing payout boundaries.
- `Mining`: Standard/Twin/Deep/Dim/Bright/Explosive deposit rows, per-swing gram yields, clean-strike
  counts, the explosive seam's prime curve and blast, helper payout limits,
  brightness gates, reach/LOS, bounded input rewind, timing bands, movement commitment, placement
  safety, seam/pickaxe presentation, continuous strike-rail layout, and impact presentation.
- `Sound`: the noise-emitter registry (loudness / radius / decay per event kind) for the second
  perception field. Who *listens* is a `hearing` block on a `Threats` row, not a value here.
- `DripTrail`, `Basin`, `Brazier`: respective system values.
- `Cauldron`, `Lantern`, `DescentLadder`: the three per-floor fixtures' PRESENTATION and, for the
  ladder, its ride timing. Deliberately separate from `Basin`/`Brazier`, which own the rules those
  first two fixtures wear; what a fixture is built FROM is `CaveFamilies.presentation.fixtureStyle`.
- `Remains`: session-pool storage bounds, pickup placement, and light values.
- `Depth`: the uncapped canonical depth model's authored-table range, internal bands, and bounded
  past-authored scaling curves.
- `Floors`: planning/tool batch size, chain/loop topology bias, room modules, spawn budgets, and
  geometry dimensions. Its per-floor tables are indexed by GLOBAL depth, not expedition ordinal.
- `RunSettings`, `Death`: run timing/party and revival values.
- `Spectator`: the ghost candle a terminally dead player becomes — body/transparency/speed, the faint
  light and when it expires, follow grace/leash/cooldown, and the ghost-only footfall trail.
- `CaveFamilies`: **THE authoritative description of what a cave IS** — Stone, Moss and Ice. One row
  per family carrying its stable id, admission/unlock prices, base and per-band threat/hazard
  multipliers, the shared passive wax drain, topology and geometry biases, room-shape weights,
  environment probabilities, threat-ecology weights and introduction shifts, presentation palettes,
  and its ore availability. Nothing else may describe a cave and nothing may branch on a family id.
- `CaveTiers`: **DERIVED, not authored.** A projection of the `CaveFamilies` rows onto the numeric
  tier id the lobby, shop, party, elevator and pre-family saves already speak. Do not add a field
  here; add it to the family profile.
- `Ore`: ore tier rows and the shared per-depth seam-count envelope. Adding a fourth tier is a row
  here plus a band in a family's `ore.availability` — no cave logic changes.
- `MossFire`: Moss's uncommon flammable vegetation — per-depth chance, placement and clearance rules,
  per-room and per-floor caps, ignition exposure curve and its closed source list, spread intervals,
  burn durations by vegetation kind, light values, and the Living Wax heat cost.
- `Lobby`, `Security`: lobby vote/launch timing, the leader-kick re-entry block, teleport retry values,
  and server trust-boundary tuning.
- `LobbyRoom`: the static physical hub's geometry (room shell, tunnel, rails, carts, spawn point/spread,
  shop and boards), local ceiling/elevator/wall-candle range and brightness, candle fixture exclusions,
  elevator party mapping/zone radius/safe ejection point, descent-ride travel
  and shaft depth/perimeter-rib spacing, thickness, and outset, the lobby's default run speed, and
  board copy (welcome/goal, how-to-play and ordered update entries; the controls panel is generated
  from `Feel.controls` instead of duplicated here).
- `Diagnostics`, `DevTestRoom`: the observation-only developer overlay and the separate physical enemy
  lab. `DevTestRoom` owns the four-bay chamber/terminal layout, cave-grouped compact control boards,
  static entity-guide cards, fixed console actions, virtual depth, spawn cap, free charges (including
  the dynamite stack, which `GIVE DYNAMITE` restates on demand) and utility timings; all lab mutations
  remain server-owned.
- `Threats.visuals.procedural`: proxy offsets, cosmetic state cadence, attack-beat pacing, client
  culling, and the emergency grey-box visual fallback.
- `Feel`, `Audio`: cosmetic feedback, tool/utility control bindings, hotbar cooldown/active/denial
  presentation, debug-label gating, one ambient-cave scheduler, cue registry, nested mix buses,
  variation/polyphony, reverb/EQ/occlusion, and Focus-driven ducking.

### `src/shared/Logic/` — pure rules (no Roblox Instances)

- `CandleGeometry`: wax-to-body/flame geometry.
- `DescentElevatorRules`: the one-way cage timeline, rotated deck occupancy, and deterministic lower
  exit position. It has no Instances and owns no floor state.
- `FloorStacking`: translates floor-local room grids into world positions and aligns each successor
  entry with the previous completion elevator without changing procedural topology.
- `CaveFamilyRules`: **the only place a cave-family profile is interpreted.** Identity and safe
  fallback resolution, profile validation (including the invariant that every family shares one
  passive wax drain), the three-factor threat/hazard budget product, threat weight multipliers and
  introduction shifts, topology/ceiling/doorway/vine resolution, shape-weight selection, and the
  pure v3→v4 save migration from numeric tier ids to stable family ids.
- `DynamiteRules`: everything dynamite decides — the bag and its carry cap, the stateless
  every-N-floors supply schedule (walked from the RUN seed, because floors are planned independently
  and out of order so a per-floor stream cannot keep a promise across floors), blast falloff for both
  candles and bodies, per-creature lethality against accumulated damage, and the thrown-stick door
  break radius. No clock, no dice, no Instances.
- `OreRules`: which TIER of ore a seam is cut from, resolved from the family's deepest-first
  availability bands. Separate from `MiningRules`, which owns how a seam is WORKED; the two are
  independent axes and neither reads the other. Written so a fourth tier needs no code change.
- `RoomFootprint`: the open interior shape inside a room's cell (Rectangle / Ellipse / Capsule /
  TwinLobe) — the shape field, containment, connectedness, twin-lobe neck width, the open mask that
  unions the shape with doorway lanes, the navigation hub and protected reservations, and the
  bounded roll that falls back to Rectangle rather than relaxing a safety rule. The room CELL is
  untouched: it still owns indexing, adjacency, doorway anchors and cleanup bounds.
- `MossFireRules`: eligibility and per-depth chance for flammable vegetation, the closed ignition
  source list and its continuous exposure curve, connectivity-graph spread, burn durations, fire
  light values, and the Living Wax heat cost with its per-cluster cap.
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
- `CargoRules`: pure Raw Wax cargo grant/clear/copy/value-bucket operations. Integer grams, origin
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
- `RoomNavigation`: reciprocal doorway graph, one-doorway waypoints, localized-pool detours and
  room-interior clamps. `roomAt` returns nil for a body in a doorway (it is outside both cells), so
  `nearestRoom` is public and is the ONLY sanctioned recovery — anything that answers "which room's
  fields am I under" must use it rather than a remembered room, because a remembered room can be the
  far side of the floor while the nearest is always a cell the point is genuinely between. **No room is excluded from the graph** (owner decision, DESIGN §10): the
  Basin's `basinNeighbors` list, the public `isProtected` query, the approach-waypoint that stopped a
  threat outside the safe room and the fail-closed `constrainStep` have all been deleted rather than
  neutered. A reciprocal doorway is an edge; what stops a body is physical geometry, not a hole in the
  graph. Whether a room is dangerous is now decided by what SPAWNS there.
- `AshamedLurkerRules`: which arches can host one, where its lane, reach and face sit inside a given
  opening, whether a measured speed and position trip it, whether the delayed grab connects, and
  whether a reported camera is a genuine stare. `clearLaneWidth`/`isPlacementAllowed` are THE
  guarantee that an occupied arch is still a route — planner, builder, server and client all read
  them rather than repeating the geometry.
- `HazardRules`: water decisions.
- `DripstoneRules`: unstable variant lookup, floor target curve, analytic fall, impact footprint,
  conservative silhouette extent, and temporary light-suppression math.
- `GroundGeometry`: deterministic cave-floor field, including actual off-centre doorway lanes,
  planned swells, water bowls, and height-preserving blended seating shelves for rigid planned loot
  and deposits, shared by planning and Terrain construction.
- `RoofGeometry`: deterministic inverted-roof field, relief, and exact clearance-clamped underside
  sampling shared by planning and Terrain construction.
- `SacrificeRules`: offers, grants, modifiers.
- `ExtractionValue`: what a bag of Raw Wax is worth, as a breakdown for display. Replaced `RewardMath`
  when Phase 8 removed the Living Wax payout.
- `CargoRules`: the five cargo verbs — grant, clear, split, merge, take. Conservation is the invariant.
- `LampRules`: Lamp Network prerequisites, contract availability, and wager arithmetic.
- `PartyRules`: who may kick a rider before launch and server-clock math for the temporary same-car
  re-entry block. Live rosters remain in `Interfaces/Party`; vote tally/tiebreak remains `PartyVote`.
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
`Drawn` category → `CaveMoth`; explicit `visualStyle` maps `Bug` → `CeilingFly`, `Listener` →
`CaveListener`, `Knotwalker` → `Knotwalker`, and `Calver` → `Calver`. The emergency grey-box
fallback is `Config.Threats.visuals.procedural.enabled = false`.

- `CaveKit`: `server/FloorBuilder` calls it with deterministic seeds for cave dressing; dressing
  never decides topology, hazards, safe routes, or interaction-pad placement.
- `MineRelics`: eleven abandoned-workings silhouettes built to CaveKit's visual laws (flat plates,
  square stock, simple cylinders — detail spent on silhouette and on DAMAGE, never on fidelity).
  Every piece builds with its ground contact at the origin; a `Wall` piece additionally builds
  everything it leans on toward +Z, which is the convention the placer's wall probe and each row's
  `wallOffset` both depend on. Collision is on MASS only: an invisible box collider per substantial
  body, and nothing at all on rails, sleepers, ballast, spill or dropped tools. Nothing here is Neon
  or carries a light — the lantern on the hook post is a lamp that went out.
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
  cannot drift. Config-authored Dormant, Triggered, and Ashamed layers write every articulated joint
  once from `PartKit.Joint.base`; the Triggered pose commits body → arm → head/jaw to the unchanged
  grab check, then holds and staggers recovery, while Ashamed articulates both arms over the face
  before retreat. Fade parts are cached and all presentation parts are massless. No gameplay state
  lives here.
- `LootPickup`: diegetic wax/flare/decoy/Match pickup models, server-built by `LootService`.
- `DarkCrawler`, `CaveMoth`, `CeilingFly`, `CaveListener`, `Knotwalker`, `Calver`: each owns its own hardcoded palette/eye-glow constants
  (e.g. `CaveMoth`'s faint yellow attraction-driven eyes, `DarkCrawler`'s crimson idle/locked eyes)
  independently of `Config.Threats.visuals.darkHunter`/`.drawn` — those Config rows tune the
  emergency grey-box fallback body, not the detailed procedural one. Keep that split in mind before
  assuming a Config edit changes what players actually see with `visuals.procedural.enabled = true`
  (the default).
- Ordinary attack animation is a one-way cosmetic echo of contact the server has already resolved. Wherever
  `ThreatService.applyContact` actually lands an effect it calls `ThreatVisualProxy.signalAttack`,
  which paces beats by the default `attackPulseIntervalSeconds` (or a staged row's own contact
  cooldown, so VoidFly shows every 0.8-second bite) and bumps the
  `ThreatVisualProtocol.attributes.attack` counter after writing `attackVictim`;
  `ThreatVisualController` starts that body's attack animation on each increment. All six bodies
  expose `strike()`/`consumeImpact()`, with anticipation, strike/contact, overshoot/hold, and recovery
  owned by `Config/Threats.visuals.procedural.attackMotion`. The counter is monotonic rather than a flag so a beat
  cannot be lost inside a replication frame, and a body rebuilt after culling absorbs the pulses
  it missed instead of replaying them. Damage never waits on, and never reads, this contract — a
  visual builder that decided when a hit lands would be the bug this shape exists to prevent.
- Calver is the deliberate exception to “animation follows effect”: its visible roof hammer is the
  warning before a later, separate ceiling trigger. `ThreatService.updateCeilingStrike` publishes a
  server timestamp/action/sequence through `ThreatVisualProxy.signalIntent`; the client reconstructs
  elapsed motion and the hammers arrive at the unchanged 1.10-second wind-up. A late/cull-rebuilt
  client absorbs old intent, and the subsequent dripstone lifecycle remains wholly server-owned.
- **Creature audio is sourced from the animation, not from a timer.** Each body reports the frames
  its own motion produces — `consumeFootfall` (a foot reaching the ground, carrying the gait's
  weight) and `consumeImpact` (a swing arriving) — and the controller turns those into cues. That is
  why an attack is *two* sounds: the pulse plays the lunge cue (the body committing, and the last
  warning a player gets), and the animation's own strike frame plays the arrival cue plus the
  victim-only sting a few frames later. Footsteps scale with the gait weight through
  `AudioCues.playAt`'s level multiplier, which is clamped to 0..1 so a caller can only ever make a
  cue quieter than its `Config/Audio` row — the mix stays config-owned. Moths do not walk, so their
  locomotion layer is an interval flutter (`locomotionAudio.mothWing*`) rather than a per-beat cue.
- The VoidFly's deterministic room-local offset is owned by `FloorPlanner`; `FloorBuilder` reserves
  that patch from harmless dressing and hands its exact paired surface fields to `ThreatService`,
  whose proxy follows the current irregular roof sample and owns the smoothed dive/return — the
  client builder must never raycast or guess a ceiling height of its own. The CeilingFly is never
  killed: a Flare immediately interrupts/clears its staged attack and temporarily repels it, while
  a nearby teammate remains the cooperative counter. Ordinary maximum burn does not repel it.
  A live harassment (`ThreatState.pursuitUntil`) lets it follow its victim past the territory to
  `ambush.pursuitRadius`, and `ThreatService.ambushNeedsImmediateReaction` widens to that same reach
  so a flare lit off-patch still interrupts the dive on the tick it was burned.
  Buzz timing/proximity live in
  `Threats.visuals.procedural.ceilingFlyBuzz`; the client emits the spatial cue only when nearby
  cave geometry does not block it. **That buzz is now the creature's only tell**: `CeilingFly`
  carries no Neon and no eye glow, so a fly the player has not heard is one they will not see.
  Halving the buzz interval or removing its occlusion model both change how findable the creature
  is far more than any stat on its row does.
- Detailed bodies stay non-collidable/non-queryable and are removed from Workspace beyond the
  configured cull distance; server replication remains one proxy Part per threat regardless of a
  body's visual complexity. Collision-neutral CaveKit/dripstone detail does not cast dynamic
  shadows (structural cave surfaces and collidable boulders do), so cave-wide torch shadow budget
  stays stable under `CandleLightController`'s one-shadow-per-client rule.

### `src/server/` — authoritative adapters

Server services own validation, state mutation, and Roblox Instances; rules belong in shared logic. Service names match their domains. Cross-cutting ownership: `EnvironmentSetup` forces runtime Lighting darkness (DESIGN §16) on boot, separately from the Studio-edit-mode defaults `default.project.json` pins, and owns `Workspace.FallenPartsDestroyHeight` — the engine boundary an uncapped downward-stacking cave must always be held above; `LobbyRoomBuilder` builds the one static physical hub at boot; `DevTestRoomBuilder` builds the separate fixed laboratory shell and `DevTestRoomService` owns its PIN/session/spawn lifecycle without entering expedition ownership; `ElevatorService` owns party-car occupancy, ready/vote phase driving, physical leave/kick ejection and descent, calling into `PartyLobbyService.tryLaunch` for the reserved-server boundary; `PlayerState` stores run state; `PartyLobbyService` owns lobby state projection and teleport handoff; `RequestGuard` and `MovementSanityService` enforce public-server boundaries; `Telemetry` writes structured prototype logs; `CharacterService` owns every player body Instance — the run candle, the lobby avatar, the elevator ride candle, and the ghost candle — plus the collision groups that separate the living from the dead; `SpectatorService` owns what a dead player is (follow target, anchor pulls, faint expiring light, footfall buffers, and their dead-players-only replication) and nothing about the run outcome; `LootService` and `RemainsService` own pickup Instances; `ToolService` resolves grounded Decoy placement and owns decoy Instances/lifetimes; `ActionFeedbackService` converts authoritative cooldown state into immediate accepted/rejected feedback in `GetServerTimeNow` space; `LightSources` assembles the sole light-perception field while `DripTrailService` exposes separate geometric breadcrumbs; `WaxService` owns recurring/external drain, partial-light suppression, burnout handling, and periodic cooldown plus Basin-vision sync projection; `DripstoneService` owns the shared one-shot Dormant → Warning → Falling → Spent lifecycle and multi-player impact selection; `MossFireService` owns burning Moss vegetation — ignition progress derived entirely from server-owned positions and flame state (there is no remote and no client input), spread along the planned connectivity graph and nowhere else, the per-floor active-fire cap, the Living Wax heat cost, and full teardown on reset; `ThreatVisualProxy` owns replicated presentation roots and attributes while `ThreatService` owns authoritative ground-plane movement, exact roof-surface sampling, smoothed ambush height, idle wall-perch placement, and contact; `RunSummaryService` turns a resolved player's wax ledger into one structured development log line and writes nothing else; and `RunOrchestrator` owns expedition phase transitions, the run's authoritative `startDepth`, on-demand construction of each next floor, the stranded-runner watchdog that guarantees no live runner can end up bodyless or below their own floor, and teardown.

`StoneWardenSystem` keeps its exceptional server-rendered body split internally: `StoneWardenModel`
builds the invisible authoritative root plus a collision-neutral Motor6D stone hierarchy;
`StoneWardenAnimator` writes only base-relative joint poses per instance; `StoneWardenBehavior` alone
owns emergence, pathing, stun deadlines, root touch validation, and immediate death. Animation may
read root velocity/proximity and confirmed contact, but never moves the root or inserts a pre-kill
action window.

### `src/client/` — local input and display

- `CameraController`: candle first-person view/visibility and explicit camera-subject reassignment
  whenever restart replaces a ghost or dead candle character.
- `EnvironmentAnimationController`: local water sheen/bobbing. Animation never changes the
  server-owned hazard surface or exposure bounds.
- `DripstoneController`: reconstructs tagged formations' warning and analytic fall from replicated
  state/timestamps, then renders local dust, debris, spatial cues, camera shake, impact dimming,
  and flame flicker. It never selects triggers, victims, wax loss, or suppression.
- `ElevatorController`: reconstructs the server-timestamped `elevatorRide` curve every render frame
	for the tagged car and cosmetic rider candles, preserves each server-owned rider's in-car XZ and
	facing so movement and free look stay live, then adds the restrained camera tremor and in-car
	readout. `ElevatorService` still owns rider selection, timing, containment, distance, and final
	transforms; clients only remove replication cadence from presentation.
- `DescentLadderController`: reconstructs both `descentRide` and `descentReturn` curves. It carries
	rider visuals only on the downward leg while preserving their server-owned in-cage movement and
	facing inside the closed boundary; the upward leg is visibly an empty cage.
- `CursorController`: first-person mouse capture is the default everywhere a character exists
  (lobby or expedition alike) — a released cursor is always an explicit named claim from the UI
  screen that needs it (Basin, Settings, results, native Roblox menu, etc.), never an automatic
  consequence of being outside an expedition.
- `DialController`, `ToolController`: input and server requests; tool cooldown acknowledgement waits
  for accepted server feedback.
- `SprintFeedbackController`: renders default-run strain through restrained FOV, peripheral overlays,
  heat shimmer, and post-camera instability after replicated speed confirms movement; it changes no
  movement or wax state.
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
  `MusicController` owns shuffled, delayed, fading tracks; `SettingsController` applies the
  per-client Music and Ambience bus gains through `AudioCues`.
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
- `StoneWardenController`: renders only server-confirmed Warden wake/contact events: the third-wax
  chamber tremor plus spatial wake/attack cues. Pickups, ceiling triggers, pursuit and kills remain
  server-owned.
- `HintController`: fades contextual threat and hazard teaching text above the hotbar on floors
  one through three; contact messages are server-triggered and hazard messages use `StateSync`.
- `HotbarController`: the desktop control legend, with server-timed cooldown bars, readable
  upward-rounded timers, friendly rejection text, reset-safe feedback animations, free-charge counts,
  and authoritative Flare/Cup active markers plus `RELIGHT`/`UNCUP` labels. It stands down entirely on
  touch — every chip names a KEY — and forwards the same labels, counts, cooldowns and active states
  to `TouchControls` instead.
- `TouchControls`: the one cluster that owns every on-screen action button a touch player has. Tools,
  dynamite, the Signal Bell and MINE/STOP register an id, a label and a row; none of them names a
  position. It sizes targets from the viewport and keeps the cluster clear of the two corners Roblox
  already owns (thumbstick bottom-left, jump button bottom-right). This replaced native
  ContextActionService touch buttons, whose positions each caller had to guess inside an engine-owned
  frame — on a phone those guesses overlapped each other and the jump button.
- `LobbyController`: gameplay-input/GUI toggling across the lobby<->expedition boundary and a
  small non-modal status readout for server-broadcast lobby messages.
- `PartyPanelController`: the interactive surface claimed while standing in an elevator. It releases
  the cursor through `CursorController`, renders the server party/leader/ready/vote state, presents
  server-authored costs beside config-authored Raw Wax/ore benefits, and sends ready, vote, leave and
  leader-kick intents. It decides none of their outcomes.
- `UpdateLogController`: a closable join-time panel for server-filtered `LobbyState.unseenUpdates`.
  It claims the cursor while open and dismisses without naming a version; the server persists its own
  latest configured build.
- `SettingsController`: local Landing and active-run settings menu (`M`) for mouse sensitivity,
  master audio, Music, and Ambience. Ambience remains at or above its configured 10% minimum; none
  of these controls changes authoritative gameplay values.
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
  exposure, Basin vision modifiers, a `candle` snapshot of the run's collected modifiers (stacks plus
  their RESOLVED live effect, so no client owns the diminishing-returns curve), free tool charges,
  `isFlaring`, and `actionCooldowns` as
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
  `RunEvent("basinChoice", payload)` acknowledges a private Basin selection after server validation;
  the client closes only after acceptance and keeps a live offer retryable after a proximity rejection.
  `LurkerGaze` is the only client-authored camera report in the game (Roblox does not replicate a
  camera), and `AshamedLurkerService` re-derives every condition from authoritative state before it
  counts; `RunEvent("lurkerGrab", payload)` broadcasts a confirmed grab's position, depth, and victim
  for the local scare. `RunEvent("wardenCollapse", payload)` broadcasts the server-confirmed third
  wax pickup's position/depth and triggered-formation count; `RunEvent("wardenAttack", payload)`
  carries confirmed Warden contact position/victim for audio only. `LobbyAction`/`LobbyState` carry
  the per-elevator party contract, including ready/vote/leave/kick intents and recipient-specific
  costs; `TutorialHint` carries a
  server-selected threat or dripstone hint id after authoritative contact;
  `RunEvent("elevatorRide", payload)` carries the lobby car's timestamped curve.
  `RunEvent("descentRide"|"descentReturn", payload)` carries the cave cage's timestamp, duration,
  full floor-gap distance and rest pivot; only the downward payload contains rider IDs. The client
  interpolates both legs while the server owns final poses, floor arrival, ejection and protection.
  `RunEvent("dripstoneImpact", payload)`
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
  `CaveTiers` derives persistent access; `Party` stores independent elevator rosters plus their
  readiness, ballots, first-rider leader and temporary leader-removal blocks; `Remains`
  stores session-local pools. `Lineage` is the only remaining stub.
- `LightVisualProtocol` owns the CollectionService tag and attributes through which
  `CharacterService` publishes authoritative candle-render targets to clients. Its optional `color`
  attribute is the one opt-out: an emitter that is not a burning wick (only the ghost candle) declares
  its own colour and skips the warm combustion flicker.
- `ThreatVisualProtocol` owns the normal-threat proxy presentation contract. Its `surfaceY` is the
  authoritative built-floor plane beneath a threat; `ThreatVisualController` seats each grounded
  body's animated `Foot`/`Toe` contact geometry on it every frame, while flying/perched/ceiling
  bodies continue to follow the proxy transform. Confirmed-contact
  `attack`/`attackVictim` stays separate from Calver's presentation-only timestamped
  `intentSequence`/`intentStartedAt`/`intentAction`; neither route carries or decides gameplay state.
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
  eligible `Config/Floors.roomModules`. Reuse `visualStyle`, `ambush`, `intercept`, `ceilingStrike`,
  `hearing` and `contactAttack` profiles when relevant; no per-threat class/ID branch. Two things that
  are easy to miss: a new row must draw a body no other row draws (`Tests/ThreatRulesTests`), and
  adding a row does NOT add bodies to a floor — the spawn roll normalises, so a new creature dilutes
  the mix until `Config/Floors.threatBudgetPerFloor` moves.
- **New FAMILY-EXCLUSIVE threat:** the above, plus a weight in `CaveFamilies.threatEcology` for its own
  family and an explicit `0` in every other. There is no branch and no allow-list split: zero already
  means "not here" to both the planner's eligibility check and its spawn roll.
- **New in-run loot:** add a `Config/Loot.definitions` row using an existing kind. Free-charge and Match pickups, and any modifier row that reuses an existing `Types/Wax.CandleModifierId`, need no service branch. A genuinely new modifier also needs its id, a `Config/CandleModifiers` row, a `Logic/CandleModifiers` branch, and a `LootPickup` silhouette.
- **New sacrifice with an existing target:** add a `Config/Basin.pool` row. A new target also requires its type and one `SacrificeRules` handler.
- **New room module:** add a `Config/Floors.roomModules` row; planner/builder consume it generically.
- **Tuning dynamite:** `Config/Dynamite` only. Four of its values are DESIGN surface rather than
  tuning because they bound the no-combat exception (DESIGN §6a) — the supply gaps, `maxCarried`,
  `blast.playerWaxCost` and `blast.alertRadius`. Changing one of those is a design change; say so.
- **Making a new creature killable by dynamite:** nothing. It already is, through
  `Config/Dynamite.threat.default`. Add a `blast` block to its `Config/Threats` row only when it
  should differ, and write `hitPoints` in "sticks at point blank".
- **New unstable-dripstone silhouette:** add one variant row under
  `Config/Hazards.unstableDripstone.variants`; reuse the fractured collar/lean/dust warning
  language. Do not add a service branch unless the gameplay contract itself changes.
- **New tunable system:** create a focused config file, export it from `Config/init.luau`, document its values in `TUNING.md`, and add its route here.
- **New remote:** add its name/payload to `Net/Remotes.luau`, wire both endpoints, validate server input, and update this document if it adds a route.
- **New player-state field:** update `Types/Player.luau`, `PlayerState.freshState`, and intentionally decide whether it belongs in `StateSync` (`Net/Remotes` and `WaxService.replicate`).
- **New persistent profile field:** update the profile type/default/reconcile handling in `Interfaces/Persistence`, then update only focused consumers. Never bypass ProfileStore with raw DataStore calls.
- **New cave family/tier:** add the authored row in `Config/CaveFamilies` and let derived
  `Config/CaveTiers` project it. Verify family rules, access price, ballot cost/benefit presentation,
  planner pressure, ore and payout together. Do not add an elevator: every car draws the same generic
  ballot.

## Supporting files

- `default.project.json`: Rojo source-to-Roblox mapping.
- `IMPLEMENTATION-NOTES.md`: caveats and manual testing.
- `IMPLEMENTATION-ROADMAP.md`: implemented phase status and ranked remaining work.
- `PUBLISH-CHECKLIST.md`: dependency, build, Studio, two-client, and live publish gates.
- `NEXT-PASS-PROMPT.md`: follow-up context; not design authority.
- `rokit.toml`, `wally.toml`, `selene.toml`, `stylua.toml`: tooling/dependency and lint/format configuration.

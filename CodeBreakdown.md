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
RunOrchestrator → MovementSanity → DripTrail → Tools → Wax → Dripstone → Threats → Death → Movement → Brazier
```

- `src/server/init.server.luau` owns boot and tick ordering. Change it only to wire a service or deliberately reorder simulation.
- `src/server/StudioTestRunner.server.luau` independently runs `shared/Tests` only in Studio; it never executes in published servers.
- `src/server/PartyLobbyService.luau` owns the public-lobby/reserved-server boundary; `RunOrchestrator` owns only an expedition after that handoff.
- `src/client/init.client.luau` starts all client controllers.
- `src/shared/Net/Remotes.luau` owns all remote names/payload shapes and is the only remote creator.
- `src/server/PlayerState.luau` is the only live per-player run-state store.
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
| Lobby party, ready/leader state, tier selection, or start flow | `server/PartyLobbyService.luau` | `Interfaces/Party`, `Config/Lobby`, `client/LobbyController`, `Net/Remotes` |
| Reserved-server teleport or teleport-data handoff | `server/PartyLobbyService.luau` | `server/init.server.luau`, `server/RunOrchestrator`, `Config/Lobby` |
| Wax drain, burnout, shrink, state sync | `server/WaxService.luau` | `Logic/WaxDrain`, `Logic/CandleGeometry`, `Config/Wax`, `Config/Character`, `PlayerState`, `DeathService` |
| Dial, drag request cadence, reconciliation, or light-output curve | `server/DialService.luau` / `client/DialController.luau` | `Logic/BrightnessMap`, `Config/Light`, `Config/Feel.dialInput`, `WaxService`, `LightSources` |
| Candle light fades, deterministic combustion flicker/warmth, spherical shadow accent, emitter stabilization, bounce/bloom/grading, shadow softness/range, or multiplayer stability | `client/CandleLightController.luau` / `Logic/FlameFlicker.luau` | `server/CharacterService`, `server/FloorBuilder`, `shared/NewModelsAndObjects/CaveKit`, `shared/LightVisualProtocol`, `Config/Light.rendering`, `client/FeelController`, `default.project.json` |
| Candle rig, body, camera, visual movement, or restart camera ownership | `server/CharacterService.luau` / `client/CameraController.luau` | `Config/Character`, `Logic/CandleGeometry`, `server/RunOrchestrator`, `RunEvent` floor handoff |
| Sprint, dodge, slide, movement input | `server/MovementService.luau` | `client/MovementController`, `Config/Movement`, `Logic/WaxDrain` |
| Sprint FOV, peripheral strain, heat shimmer, camera instability, or sprint flame feedback | `client/SprintFeedbackController.luau` | `client/MovementController`, `client/FeelController`, `Config/Feel`, `server/CharacterService`, `Config/Character` |
| Tool stats, grounded-Cast placement/visuals, or effect | `Config/Tools.luau` | `server/ToolService`, `Logic/ToolRules`, `Types/Tool`, `client/ToolController`, `LightSources` |
| Tool validation, grounded Cast resolution, decoys, flare, or Cup/Snuff | `server/ToolService.luau` | `Logic/ToolRules`, `ActionFeedbackService`, `MovementService`, `Net/Remotes` |
| Tool/movement cooldown projection, accepted/rejected feedback, hotbar bars, or active labels | `Logic/CooldownRules.luau` / `server/ActionFeedbackService.luau` | `server/ToolService`, `server/MovementService`, `server/WaxService`, `Net/Remotes.ActionFeedback`, `StateEntry.actionCooldowns`, `client/HotbarController`, `Config/Feel.hotbar` |
| In-run wax/charge loot, wall-pocket planning, exact-ground placement, pickup art, or pickup behaviour | `Config/Loot.luau` | `Logic/FloorPlanner`, `Logic/GroundGeometry`, `Logic/LootRules`, `NewModelsAndObjects/LootPickup`, `server/LootService`, `PlayerState`, `ToolService` |
| Threat stats/content or depth spawn weights | `Config/Threats.luau` | `Config/Floors` allow-lists, `Logic/FloorPlanner` |
| Threat model geometry, local creature animation, or visual culling | `client/ThreatVisualController.luau` / `shared/NewModelsAndObjects/` | `server/ThreatVisualProxy`, `server/ThreatService`, `Config/Threats.visuals.procedural`, `Config/Feel.debug` |
| Threat AI, crawler light bands/retreat memory, room/pool routing, ground-following, ceiling-ambush dive/return, movement, or contact | `Logic/ThreatBrain.luau` / `Logic/RoomNavigation.luau` | `server/ThreatService`, `Logic/LightField`, `server/LightSources`, `Config/Threats.behavior`, `Config/Threats.definitions.*.ambush`, `Logic/FloorPlanner`, `Config/Floors.terrain` |
| Threat-visible light source | `server/LightSources.luau` | `Logic/LightField`, `WaxService`, `ToolService`, `RemainsService` |
| Draft, localized water pools, wading, water lethality, or hazard animation | `server/HazardService.luau` / `server/FloorBuilder.luau` | `Logic/HazardRules`, `Config/Hazards`, `WaxService`, `client/EnvironmentAnimationController` |
| Unstable-dripstone count curve, eligibility, variant, trigger, fall, impact, wax loss, or partial snuff | `Logic/DripstoneRules.luau` / `server/DripstoneService.luau` | `Config/Hazards.unstableDripstone`, `Logic/FloorPlanner`, `server/FloorBuilder`, `WaxService`, `LightSources`, `Types/World.DripstonePlacement` |
| Dangerous-dripstone model, fracture tell, warning/fall animation, dust/debris, shake, or impact grading | `shared/NewModelsAndObjects/UnstableDripstone.luau` / `client/DripstoneController.luau` | `shared/DripstoneVisualProtocol`, `Logic/DripstoneRules`, `Config/Hazards.unstableDripstone`, `Config/Audio`, `Net/Remotes.RunEvent` |
| Snuffing, relighting, burnout, wisps, death results | `server/DeathService.luau` | `Config/Death`, `client/RelightPromptController`, `WaxService`, `CharacterService`, `Interfaces/Remains` |
| Session remains storage, placement, recovery, or light | `server/RemainsService.luau` | `Interfaces/Remains`, `Config/Remains`, `DeathService`, `LightSources`, `RunOrchestrator` |
| End-of-run screen, death debug, replay, or back-to-lobby flow | `client/ResultsText.luau` / `server/RunOrchestrator.luau` | `server/DeathService`, `server/PartyLobbyService`, `Net/Remotes` |
| Non-glowing wax-drop trails or hunter breadcrumbs | `server/DripTrailService.luau` | `Config/DripTrail`, `ThreatService`, `Logic/ThreatBrain` |
| Basin offers, sacrifice choices/modifiers | `server/BasinService.luau` | `Logic/SacrificeRules`, `Config/Basin`, `client/BasinPrompt`, `PlayerState` |
| Brazier preview, payout, group bonus | `server/BrazierService.luau` | `Logic/RewardMath`, `Config/Brazier`, `Interfaces/Persistence`, `client/ResultsText` |
| Floor topology, room selection, deterministic threat offsets, ceiling eligibility, guaranteed ground patches, pool footprints, or dangerous-dripstone placement | `Logic/FloorPlanner.luau` | `Config/Floors`, `Config/Threats`, `Config/Hazards`, `Logic/DripstoneRules`, `Logic/GroundGeometry`, `Logic/RoofGeometry`, `Logic/DoorwayGeometry`, `Types/World` |
| Cave geometry, recessed floors, CaveKit formations, ambush dressing reservations, per-edge doorway sizing, hazard zones, or exact room-surface handoff | `server/FloorBuilder.luau` | `server/ThreatService`, `shared/NewModelsAndObjects/CaveKit`, `shared/NewModelsAndObjects/UnstableDripstone`, `Config/Floors.geometry`, `.caveDressing`, `.terrain`, `.roof`, `Config/Threats`, `Config/Hazards`, `HazardService`, `Logic/FloorPlanner`, `Logic/GroundGeometry`, `Logic/RoofGeometry` |
| Cave-floor height field, swells, doorway lanes, pools, or a gameplay placement's exact local ground | `Logic/GroundGeometry.luau` | `Config/Floors`, `Logic/DoorwayGeometry`, `Logic/FloorPlanner`, `server/FloorBuilder` |
| Inverted Terrain roof shape, relief seed, edge blending, rock thickness, minimum clearance, or exact underside height | `Logic/RoofGeometry.luau` / `server/FloorBuilder.luau` | `Config/Floors.roof`, `Logic/GroundGeometry`, `Logic/FloorPlanner`, `shared/NewModelsAndObjects/CaveKit` |
| Expedition countdown, runner inclusion, descent, replay, lobby return, or reset | `server/RunOrchestrator.luau` | `server/PartyLobbyService`, `Config/RunSettings`, `FloorPlanner`, `FloorBuilder`, service `reset`s |
| Remote rate limits or finite-payload validation | `server/RequestGuard.luau` | `Logic/TokenBucket`, `Config/Security`, every inbound remote handler |
| Impossible-movement correction | `server/MovementSanityService.luau` | `Config/Security`, `Config/Movement`, approved burst credits in `MovementService`, authorized teleports in `RunOrchestrator`, `CharacterService` |
| Prototype server-log telemetry | `server/Telemetry.luau` | `Config/Security`, emitting service |
| HUD or run messages | relevant file in `src/client/` | `Net/Remotes`; `ResultsText` handles `RunEvent`, `WaxBar` handles `StateSync`, `HotbarController` handles `ActionFeedback` plus cooldown reconciliation |
| Cursor capture, clickable UI cursor release, or native Roblox menu interaction | `client/CursorController.luau` | the UI controller that opens the screen, `WickInExpedition`, `client/CameraController` |
| In-run local presentation settings (mouse sensitivity / audio volume) | `client/SettingsController.luau` | `client/CursorController`, `client/AudioCues`, `WickInExpedition` |
| Lobby UI, party list, ready button, or tier buttons | `client/LobbyController.luau` | `server/PartyLobbyService`, `Interfaces/CaveTiers`, `Net/Remotes` |
| Gameplay input enabled/disabled across lobby/run transitions | `client/LobbyController.luau` | `client/DialController`, `client/MovementController`, `client/ToolController`, `WickInExpedition` player attribute |
| Low-wax, draft/water grading, or nearby-threat cue and flicker context | `client/FeelController.luau` / `client/WaxBar.luau` | `Config/Feel`, `client/CandleLightController`, `client/AudioCues`, `Net/Remotes`, `WaxService` |
| First-three-floor threat/water/gust teaching hints | `client/HintController.luau` | `server/ThreatService`, `Config/Feel.tutorialHints`, `Net/Remotes.TutorialHint`, `WaxService` (`StateSync`) |
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
- `Light`: dial limits, light-curve inputs, and client candle rendering/fade/flicker tuning.
- `Movement`: action speeds, costs, cooldowns, drain thresholds.
- `Character`: candle geometry and rig proportions.
- `Tools`, `Threats`, `Hazards`, `Loot`: generic-system content and tuning. `Tools` also owns
  authoritative grounded-Cast probe bounds and its miniature decoy presentation; `Hazards` owns
  unstable-dripstone scaling, safety caps, three data-driven variants, fall/light suppression,
  and impact presentation values.
- `DripTrail`, `Basin`, `Brazier`: respective system values.
- `Remains`: session-pool storage bounds, pickup placement, and light values.
- `Floors`: floor counts, room modules, spawn budgets, geometry dimensions.
- `RunSettings`, `Death`: run timing/party/wisp and revival values.
- `CaveTiers`, `Lobby`, `Security`: durable-access tier rows, lobby/teleport retry values, and
  server trust-boundary tuning.
- `Threats.visuals.procedural`: proxy offsets, cosmetic state cadence, client culling, and the
  emergency grey-box visual fallback.
- `Feel`, `Audio`: cosmetic feedback, shared control bindings, hotbar cooldown/active/denial
  presentation, debug-label gating, and cue registry.

### `src/shared/Logic/` — pure rules (no Roblox Instances)

- `CandleGeometry`: wax-to-body/flame geometry.
- `WaxDrain`: recurring drain pipeline and movement-mode calculation.
- `BrightnessMap`: burn rate to light values.
- `FlameFlicker`: deterministic owner-seeded, layered combustion brightness/warmth signal; it
  operates only on cosmetic renderer targets and never changes gameplay light.
- `LightField`: light intensity, Drawn-attractor queries, and the DESIGN-mandated dark-hunter
  perception filter (Cast decoys are ignored by that category).
- `ToolRules`: generic activation validation plus pure horizontal Cast clamping, parabolic-arc
  sampling, and surface-slope rules.
- `CooldownRules`: read-only `forAction`/`snapshot` projection of server-owned tool, Dodge, Slide,
  and voluntary-Snuff relight gates for presentation.
- `LootRules`: wax-profile replacement and free-tool-charge awards.
- `ThreatBrain`: generic roaming, dark-hunter hunt/stalk/retreat bands, territorial-ambush
  decisions, movement, and staged-contact counting.
- `RoomNavigation`: reciprocal doorway graph, one-doorway waypoints, localized-pool detours,
  room-interior clamps, and fail-closed Basin exclusion.
- `HazardRules`: water and draft decisions.
- `DripstoneRules`: unstable variant lookup, floor target curve, analytic fall, impact footprint,
  conservative silhouette extent, and temporary light-suppression math.
- `GroundGeometry`: deterministic cave-floor field, including actual off-centre doorway lanes,
  planned swells, and water bowls, shared by planning and Terrain construction.
- `RoofGeometry`: deterministic inverted-roof field, relief, and exact clearance-clamped underside
  sampling shared by planning and Terrain construction.
- `SacrificeRules`: offers, grants, modifiers.
- `RewardMath`: payout breakdown.
- `FloorPlanner`: seeded floor-plan generation, loop connections, guaranteed dry critical route,
  deterministic pool/draft placement, collidable ground-patch placement, protected unstable-
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
- `LootPickup`: diegetic wax/flare/decoy pickup models, server-built by `LootService`.
- `DarkCrawler`, `CaveMoth`, `CeilingFly`: each owns its own hardcoded palette/eye-glow constants
  (e.g. `CaveMoth`'s faint yellow attraction-driven eyes, `DarkCrawler`'s crimson idle/locked eyes)
  independently of `Config.Threats.visuals.darkHunter`/`.drawn` — those Config rows tune the
  emergency grey-box fallback body, not the detailed procedural one. Keep that split in mind before
  assuming a Config edit changes what players actually see with `visuals.procedural.enabled = true`
  (the default).
- The VoidFly's deterministic room-local offset is owned by `FloorPlanner`; `FloorBuilder` reserves
  that patch from harmless dressing and hands its exact paired surface fields to `ThreatService`,
  whose proxy follows the current irregular roof sample and owns the smoothed dive/return — the
  client builder must never raycast or guess a ceiling height of its own. The CeilingFly is not
  killed by brightness; `ThreatBrain` only temporarily repels it at maximum exposed burn, during a
  Flare, or when a teammate is close. Buzz timing/proximity live in
  `Threats.visuals.procedural.ceilingFlyBuzz`; the client emits the spatial cue only when nearby
  cave geometry does not block it.
- Detailed bodies stay non-collidable/non-queryable and are removed from Workspace beyond the
  configured cull distance; server replication remains one proxy Part per threat regardless of a
  body's visual complexity. Collision-neutral CaveKit/dripstone detail does not cast dynamic
  shadows (structural cave surfaces and collidable boulders do), so cave-wide torch shadow budget
  stays stable under `CandleLightController`'s one-shadow-per-client rule.

### `src/server/` — authoritative adapters

Server services own validation, state mutation, and Roblox Instances; rules belong in shared logic. Service names match their domains. Cross-cutting ownership: `EnvironmentSetup` forces runtime Lighting darkness (DESIGN §16) on boot, separately from the Studio-edit-mode defaults `default.project.json` pins; `PlayerState` stores run state; `PartyLobbyService` owns lobby and teleport handoff; `RequestGuard` and `MovementSanityService` enforce public-server boundaries; `Telemetry` writes structured prototype logs; `CharacterService` owns candle/wisp Instances; `LootService` and `RemainsService` own pickup Instances; `ToolService` resolves grounded Cast placement and owns decoy Instances/lifetimes; `ActionFeedbackService` converts authoritative cooldown state into immediate accepted/rejected feedback in `GetServerTimeNow` space; `LightSources` assembles the sole light-perception field while `DripTrailService` exposes separate geometric breadcrumbs; `WaxService` owns recurring/external drain, partial-light suppression, burnout handling, and periodic cooldown sync projection; `DripstoneService` owns the shared one-shot Dormant → Warning → Falling → Spent lifecycle and multi-player impact selection; `ThreatVisualProxy` owns replicated presentation roots and attributes while `ThreatService` owns authoritative ground-plane movement, exact roof-surface sampling, smoothed ambush height, and contact; and `RunOrchestrator` owns expedition phase transitions and teardown.

### `src/client/` — local input and display

- `CameraController`: candle first-person view/visibility and explicit camera-subject reassignment
  whenever restart replaces a dead wisp/candle character.
- `EnvironmentAnimationController`: local water sheen/bobbing and draft-volume pulsing. Animation
  never changes the server-owned hazard surface or exposure bounds.
- `DripstoneController`: reconstructs tagged formations' warning and analytic fall from replicated
  state/timestamps, then renders local dust, debris, spatial cues, camera shake, impact dimming,
  and flame flicker. It never selects triggers, victims, wax loss, or suppression.
- `CursorController`: keeps first-person capture during play and releases the cursor for every
  interactive WICK screen and Roblox's native menu.
- `DialController`, `MovementController`, `ToolController`: input and server requests; tool and
  cooldown movement acknowledgement waits for accepted server feedback.
- `SprintFeedbackController`: renders accepted sprint strain through restrained FOV, peripheral
  overlays, heat shimmer, and post-camera instability; it changes no movement or wax state.
- `CandleLightController`: is the sole candle-light renderer. It interpolates server-published
  candle targets, applies the owner-seeded/server-time `FlameFlicker` brightness and colour signal
  coherently to fill/shadow/bounce, and limits dynamic shadows to one full-range spherical
  local-player accent per client. Flicker never varies range, the enable threshold, or the stable
  carrier.
- `FeelController`: renders local environment/threat feedback and forwards local draft/threat
  context to `CandleLightController`; it creates no candle PointLight. `AudioCues`: safe
  config-to-Sound adapter and master local-volume group; `MusicController`: menu playback plus
  shuffled, delayed, fading cave tracks.
- `ThreatVisualController`: builds, animates, and distance-culls detailed procedural creatures
  locally around server-owned non-colliding proxies.
- `HintController`: fades contextual threat and hazard teaching text above the hotbar on floors
  one through three; contact messages are server-triggered and hazard messages use `StateSync`.
- `HotbarController`: responsive desktop/touch control legend with server-timed cooldown bars,
  readable upward-rounded timers, friendly rejection text, reset-safe feedback animations,
  free-charge counts, authoritative `RELIGHT`/`UNCUP` active labels, and presentation-only mirrors
  attached to native ContextActionService touch buttons.
- `LobbyController`: one-party member/readiness display and leader-only cave-tier/start controls.
- `SettingsController`: local in-run settings menu (`M`) for mouse sensitivity and audio volume;
  it never changes authoritative gameplay values.
- `RelightPromptController`: hides a snuffed candle's impossible self-relight prompt locally;
  the server-created prompt remains available to teammates.
- `WaxBar`, `BasinPrompt`, `ResultsText`: UI driven by server state/events.
- `UITheme`: shared palette, fonts, and motion presets (tween/corner/stroke/panel/button helpers)
  plus the composited WICK wordmark and candle-glyph widgets, consumed by most themed UI above.
  Not a controller itself — no `.start()`, nothing boots it.

### `src/replicatedfirst/` — earliest-possible boot screen

- `WickLoadingScreen.client.luau`: shows before `ReplicatedStorage.Shared` is guaranteed to exist,
  so it cannot require `UITheme` and instead duplicates the wordmark/candle-glyph drawing inline
  (kept in sync with `UITheme` by a comment on both sides). Tears itself down once loading finishes.

### `src/shared/Types/`, `Net/`, and `Interfaces/`

- `Types/` defines contracts; `Types/init.luau` re-exports them.
- `Net/Remotes` is the complete server/client contract. `StateSync` includes render-only hazard
  exposure, active wax type, free tool charges, and `actionCooldowns` as
  `{ [actionId]: { endsAt, duration } }` in `Workspace:GetServerTimeNow()` space. `ActionFeedback`
  carries the same clock-space cooldown plus accepted/rejected status and an optional denial reason
  immediately after a tool, Dodge, or Slide request; `StateSync` remains the reconciliation path.
  `LobbyAction`/`LobbyState` carry the
  one-party lobby contract; `TutorialHint` carries a server-selected threat definition id after
  authoritative contact; `RunEvent("dripstoneImpact", payload)` broadcasts the server-confirmed
  impact position, depth, variant, and hit-player IDs; `RestartRun` and `ReturnToLobby` are the two resolved-run exits.
  Server handlers validate and rate-limit all inbound data.
- `Types/World.DripstonePlacement` is planned data: room index, room-local XZ, variant id, and
  visual seed. `FloorBuilder` resolves exact roof and landing heights from the deterministic fields.
- `Types/World.ThreatSpawn` is planned data: definition id, room index, and deterministic room-local
  offset. Runtime services must not reroll a gameplay spawn position.
- `Types/Tool` owns the data shapes for authoritative `CastPlacement` probes and `DecoyVisual`
  construction; behaviour remains generic over the optional fields.
- `Types/Light.LightSource` declares both Drawn attraction and dark-hunter repulsion perception;
  Cast decoys set only the former, matching DESIGN §6.
- `Interfaces/Persistence` is the ProfileStore boundary (Studio uses its isolated mock);
  `CaveTiers` derives persistent access; `Party` stores the one-party lobby state; `Remains`
  stores session-local pools. `Lineage` is the only remaining stub.
- `LightVisualProtocol` owns the CollectionService tag and attributes through which
  `CharacterService` publishes authoritative candle-render targets to clients.
- `DripstoneVisualProtocol` owns the CollectionService tag plus shared state, timestamp, rest
  transform, landing, fall-distance, variant, depth, and seed attributes. The server changes
  lifecycle state; every client derives the same presentation without per-frame replication.
- `Tests/` holds the dependency-free pure-rule harness and suites. Add regression coverage beside the owning logic change and keep expectations config-derived.

## Safe extension recipes

- **New threat:** add a `Config/Threats.definitions` row with depth weights and include the ID in
  eligible `Config/Floors.roomModules`. Reuse `visualStyle`, `ambush`, and `contactAttack` profiles
  when relevant; no per-threat class/ID branch.
- **New in-run loot:** add a `Config/Loot.definitions` row using an existing kind. Wax-profile and free-charge pickups need no service branch.
- **New sacrifice with an existing target:** add a `Config/Basin.pool` row. A new target also requires its type and one `SacrificeRules` handler.
- **New room module:** add a `Config/Floors.roomModules` row; planner/builder consume it generically.
- **New unstable-dripstone silhouette:** add one variant row under
  `Config/Hazards.unstableDripstone.variants`; reuse the fractured collar/lean/dust warning
  language. Do not add a service branch unless the gameplay contract itself changes.
- **New tunable system:** create a focused config file, export it from `Config/init.luau`, document its values in `TUNING.md`, and add its route here.
- **New remote:** add its name/payload to `Net/Remotes.luau`, wire both endpoints, validate server input, and update this document if it adds a route.
- **New player-state field:** update `Types/Player.luau`, `PlayerState.freshState`, and intentionally decide whether it belongs in `StateSync` (`Net/Remotes` and `WaxService.replicate`).
- **New persistent profile field:** update the profile type/default/reconcile handling in `Interfaces/Persistence`, then update only focused consumers. Never bypass ProfileStore with raw DataStore calls.
- **New cave tier:** add one data row in `Config/CaveTiers`; verify its unlock threshold, planner limits, threat multiplier, lobby presentation, and brazier multiplier together.

## Supporting files

- `default.project.json`: Rojo source-to-Roblox mapping.
- `IMPLEMENTATION-NOTES.md`: caveats and manual testing.
- `IMPLEMENTATION-ROADMAP.md`: implemented phase status and ranked remaining work.
- `PUBLISH-CHECKLIST.md`: dependency, build, Studio, two-client, and live publish gates.
- `NEXT-PASS-PROMPT.md`: follow-up context; not design authority.
- `rokit.toml`, `wally.toml`, `selene.toml`, `stylua.toml`: tooling/dependency and lint/format configuration.

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
RunOrchestrator → MovementSanity → DripTrail → Tools → Wax → Threats → Death → Movement → Brazier
```

- `src/server/init.server.luau` owns boot and tick ordering. Change it only to wire a service or deliberately reorder simulation.
- `src/server/StudioTestRunner.server.luau` independently runs `shared/Tests` only in Studio; it never executes in published servers.
- `src/server/PartyLobbyService.luau` owns the public-lobby/reserved-server boundary; `RunOrchestrator` owns only an expedition after that handoff.
- `src/client/init.client.luau` starts all client controllers.
- `src/shared/Net/Remotes.luau` owns all remote names/payload shapes and is the only remote creator.
- `src/server/PlayerState.luau` is the only live per-player run-state store.

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
| Candle rig, body, camera, visual movement | `server/CharacterService.luau` | `Config/Character`, `Logic/CandleGeometry`, `client/CameraController` |
| Sprint, dodge, slide, movement input | `server/MovementService.luau` | `client/MovementController`, `Config/Movement`, `Logic/WaxDrain` |
| Tool stats or effect | `Config/Tools.luau` | `server/ToolService`, `Logic/ToolRules`, `client/ToolController`, `LightSources` |
| Tool validation, cooldown, aim, decoys, flare, Cup/Snuff | `server/ToolService.luau` | `Logic/ToolRules`, `MovementService`, `Net/Remotes` |
| In-run wax/charge loot, planning, or pickup behaviour | `Config/Loot.luau` | `Logic/FloorPlanner`, `Logic/LootRules`, `server/LootService`, `PlayerState`, `ToolService` |
| Threat stats/content or depth spawn weights | `Config/Threats.luau` | `Config/Floors` allow-lists, `Logic/FloorPlanner` |
| Threat AI, perception, room-to-room routing, movement, contact | `Logic/ThreatBrain.luau` / `Logic/RoomNavigation.luau` | `server/ThreatService`, `Logic/LightField`, `server/LightSources`, `Logic/FloorPlanner` |
| Threat-visible light source | `server/LightSources.luau` | `Logic/LightField`, `WaxService`, `ToolService`, `DripTrailService` |
| Draft, water, wading, water lethality | `server/HazardService.luau` | `Logic/HazardRules`, `Config/Hazards`, `WaxService`, `FloorBuilder` |
| Snuffing, relighting, burnout, wisps, death results | `server/DeathService.luau` | `Config/Death`, `WaxService`, `CharacterService`, `Interfaces/Remains` |
| Session remains storage, placement, recovery, or light | `server/RemainsService.luau` | `Interfaces/Remains`, `Config/Remains`, `DeathService`, `LightSources`, `RunOrchestrator` |
| End-of-run screen, death debug, or immediate restart | `client/ResultsText.luau` | `server/DeathService`, `server/RunOrchestrator`, `Net/Remotes` |
| Drip trails | `server/DripTrailService.luau` | `Config/DripTrail`, `LightSources`, `ThreatService` |
| Basin offers, sacrifice choices/modifiers | `server/BasinService.luau` | `Logic/SacrificeRules`, `Config/Basin`, `client/BasinPrompt`, `PlayerState` |
| Brazier preview, payout, group bonus | `server/BrazierService.luau` | `Logic/RewardMath`, `Config/Brazier`, `Interfaces/Persistence`, `client/ResultsText` |
| Floor topology, room selection, spawns | `Logic/FloorPlanner.luau` | `Config/Floors`, `Types/World` |
| Cave geometry, floor positions, zones | `server/FloorBuilder.luau` | `Config/Floors`, `HazardService`, `Logic/FloorPlanner` |
| Expedition countdown, runner inclusion, descent, reset | `server/RunOrchestrator.luau` | `server/PartyLobbyService`, `Config/RunSettings`, `FloorPlanner`, `FloorBuilder`, service `reset`s |
| Remote rate limits or finite-payload validation | `server/RequestGuard.luau` | `Logic/TokenBucket`, `Config/Security`, every inbound remote handler |
| Impossible-movement correction | `server/MovementSanityService.luau` | `Config/Security`, `Config/Movement`, approved burst credits in `MovementService`, authorized teleports in `RunOrchestrator`, `CharacterService` |
| Prototype server-log telemetry | `server/Telemetry.luau` | `Config/Security`, emitting service |
| HUD or run messages | relevant file in `src/client/` | `Net/Remotes`; `ResultsText` handles `RunEvent`, `WaxBar` handles `StateSync` |
| Lobby UI, party list, ready button, or tier buttons | `client/LobbyController.luau` | `server/PartyLobbyService`, `Interfaces/CaveTiers`, `Net/Remotes` |
| Gameplay input enabled/disabled across lobby/run transitions | `client/LobbyController.luau` | `client/DialController`, `client/MovementController`, `client/ToolController`, `WickInExpedition` player attribute |
| Low-wax, draft, water, flame-flicker, or nearby-threat feedback | `client/FeelController.luau` / `client/WaxBar.luau` | `Config/Feel`, `client/AudioCues`, `Net/Remotes`, `WaxService` |
| Sound cue asset, volume, loop, or cooldown | `Config/Audio.luau` | `client/AudioCues` and the controller that requests the named cue |
| Keyboard/touch binding or visible control hotbar | `Config/Feel.luau` | `client/HotbarController`, `ToolController`, `MovementController` |
| Remote contract | `shared/Net/Remotes.luau` | every sender and receiver |
| Domain data shape | matching `shared/Types/*.luau` | `Types/init.luau`, config and consumers |
| Lineage stub or future carryover design | `shared/Interfaces/Lineage.luau` | `DESIGN.md`, `Interfaces/init.luau`; add no consumer until the design is settled |

## Directory ownership

### `src/shared/Config/` — tuning and content data

Each file owns one data domain; `Config/init.luau` aggregates them. Add values and generic content here, not behaviour branches.

- `Wax`, `WaxTypes`: candle economy and burn profiles.
- `Light`: dial limits and light-curve inputs.
- `Movement`: action speeds, costs, cooldowns, drain thresholds.
- `Character`: candle geometry and rig proportions.
- `Tools`, `Threats`, `Hazards`, `Loot`: generic-system content and tuning.
- `DripTrail`, `Basin`, `Brazier`: respective system values.
- `Remains`: session-pool storage bounds, pickup placement, and light values.
- `Floors`: floor counts, room modules, spawn budgets, geometry dimensions.
- `RunSettings`, `Death`: run timing/party/wisp and revival values.
- `CaveTiers`, `Lobby`, `Security`: durable-access tier rows, lobby/teleport retry values, and
  server trust-boundary tuning.
- `Feel`, `Audio`: cosmetic feedback, shared control bindings/hotbar presentation, debug-label gating, and cue registry.

### `src/shared/Logic/` — pure rules (no Roblox Instances)

- `CandleGeometry`: wax-to-body/flame geometry.
- `WaxDrain`: recurring drain pipeline and movement-mode calculation.
- `BrightnessMap`: burn rate to light values.
- `LightField`: light intensity and attractor queries.
- `ToolRules`: generic activation validation and aim clamping.
- `LootRules`: wax-profile replacement and free-tool-charge awards.
- `ThreatBrain`: generic threat decisions and movement.
- `RoomNavigation`: reciprocal doorway graph, one-doorway waypoints, room-interior clamps, and
  fail-closed Basin exclusion.
- `HazardRules`: water and draft decisions.
- `SacrificeRules`: offers, grants, modifiers.
- `RewardMath`: payout breakdown.
- `FloorPlanner`: seeded floor-plan generation.
- `TokenBucket`: deterministic per-player request-throttle math.

### `src/server/` — authoritative adapters

Server services own validation, state mutation, and Roblox Instances; rules belong in shared logic. Service names match their domains. Cross-cutting ownership: `PlayerState` stores run state; `PartyLobbyService` owns lobby and teleport handoff; `RequestGuard` and `MovementSanityService` enforce public-server boundaries; `Telemetry` writes structured prototype logs; `CharacterService` owns candle/wisp Instances; `LootService` and `RemainsService` own pickup Instances; `LightSources` assembles the sole perception field; `WaxService` owns recurring and external-drain burnout handling; and `RunOrchestrator` owns expedition phase transitions and teardown.

### `src/client/` — local input and display

- `CameraController`: candle first-person view/visibility.
- `DialController`, `MovementController`, `ToolController`: input, local acknowledgement cues, and server requests only.
- `FeelController`: local flame/environment/threat feedback; `AudioCues`: safe config-to-Sound adapter.
- `HotbarController`: responsive desktop/touch control legend sourced from the same bindings as input.
- `LobbyController`: one-party member/readiness display and leader-only cave-tier/start controls.
- `WaxBar`, `BasinPrompt`, `ResultsText`: UI driven by server state/events.

### `src/shared/Types/`, `Net/`, and `Interfaces/`

- `Types/` defines contracts; `Types/init.luau` re-exports them.
- `Net/Remotes` is the complete server/client contract. `StateSync` includes render-only hazard
  exposure, active wax type, and free tool charges. `LobbyAction`/`LobbyState` carry the
  one-party lobby contract. Server handlers validate and rate-limit all inbound data.
- `Interfaces/Persistence` is the ProfileStore boundary (Studio uses its isolated mock);
  `CaveTiers` derives persistent access; `Party` stores the one-party lobby state; `Remains`
  stores session-local pools. `Lineage` is the only remaining stub.
- `Tests/` holds the dependency-free pure-rule harness and suites. Add regression coverage beside the owning logic change and keep expectations config-derived.

## Safe extension recipes

- **New threat:** add a `Config/Threats.definitions` row with depth weights and include the ID in eligible `Config/Floors.roomModules`. No per-threat class/branch.
- **New in-run loot:** add a `Config/Loot.definitions` row using an existing kind. Wax-profile and free-charge pickups need no service branch.
- **New sacrifice with an existing target:** add a `Config/Basin.pool` row. A new target also requires its type and one `SacrificeRules` handler.
- **New room module:** add a `Config/Floors.roomModules` row; planner/builder consume it generically.
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

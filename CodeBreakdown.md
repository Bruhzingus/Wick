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
RunOrchestrator → DripTrail → Tools → Wax → Threats → Death → Movement → Brazier
```

- `src/server/init.server.luau` owns boot and tick ordering. Change it only to wire a service or deliberately reorder simulation.
- `src/client/init.client.luau` starts all client controllers.
- `src/shared/Net/Remotes.luau` owns all remote names/payload shapes and is the only remote creator.
- `src/server/PlayerState.luau` is the only live per-player run-state store.

## Change routing

| Change | Start here | Also inspect |
| --- | --- | --- |
| Game rules, scope, or player experience | `DESIGN.md` | `ARCHITECTURE.md` |
| Tunable value or content row | matching `shared/Config/*.luau` | `TUNING.md`, consumer |
| Wax drain, burnout, shrink, state sync | `server/WaxService.luau` | `Logic/WaxDrain`, `Logic/CandleGeometry`, `Config/Wax`, `Config/Character`, `PlayerState`, `DeathService` |
| Dial or light-output curve | `server/DialService.luau` / `client/DialController.luau` | `Logic/BrightnessMap`, `Config/Light`, `WaxService`, `LightSources` |
| Candle rig, body, camera, visual movement | `server/CharacterService.luau` | `Config/Character`, `Logic/CandleGeometry`, `client/CameraController` |
| Sprint, dodge, slide, movement input | `server/MovementService.luau` | `client/MovementController`, `Config/Movement`, `Logic/WaxDrain` |
| Tool stats or effect | `Config/Tools.luau` | `server/ToolService`, `Logic/ToolRules`, `client/ToolController`, `LightSources` |
| Tool validation, cooldown, aim, decoys, flare, Cup/Snuff | `server/ToolService.luau` | `Logic/ToolRules`, `MovementService`, `Net/Remotes` |
| Threat stats/content | `Config/Threats.luau` | `Config/Floors` allow-lists |
| Threat AI, perception, movement, contact | `Logic/ThreatBrain.luau` | `server/ThreatService`, `Logic/LightField`, `server/LightSources` |
| Threat-visible light source | `server/LightSources.luau` | `Logic/LightField`, `WaxService`, `ToolService`, `DripTrailService` |
| Draft, water, wading, water lethality | `server/HazardService.luau` | `Logic/HazardRules`, `Config/Hazards`, `WaxService`, `FloorBuilder` |
| Snuffing, relighting, burnout, wisps, death results | `server/DeathService.luau` | `Config/Death`, `WaxService`, `CharacterService`, `Interfaces/Remains` |
| Drip trails | `server/DripTrailService.luau` | `Config/DripTrail`, `LightSources`, `ThreatService` |
| Basin offers, sacrifice choices/modifiers | `server/BasinService.luau` | `Logic/SacrificeRules`, `Config/Basin`, `client/BasinPrompt`, `PlayerState` |
| Brazier preview, payout, group bonus | `server/BrazierService.luau` | `Logic/RewardMath`, `Config/Brazier`, `Interfaces/Persistence`, `client/ResultsText` |
| Floor topology, room selection, spawns | `Logic/FloorPlanner.luau` | `Config/Floors`, `Types/World` |
| Cave geometry, floor positions, zones | `server/FloorBuilder.luau` | `Config/Floors`, `HazardService`, `Logic/FloorPlanner` |
| Countdown, party inclusion, descent, reset | `server/RunOrchestrator.luau` | `Config/RunSettings`, `FloorPlanner`, `FloorBuilder`, service `reset`s |
| HUD or run messages | relevant file in `src/client/` | `Net/Remotes`; `ResultsText` handles `RunEvent`, `WaxBar` handles `StateSync` |
| Remote contract | `shared/Net/Remotes.luau` | every sender and receiver |
| Domain data shape | matching `shared/Types/*.luau` | `Types/init.luau`, config and consumers |
| Deferred persistence/party/lineage/remains/tier system | matching `shared/Interfaces/*.luau` | `Interfaces/init.luau` and its consumer |

## Directory ownership

### `src/shared/Config/` — tuning and content data

Each file owns one data domain; `Config/init.luau` aggregates them. Add values and generic content here, not behaviour branches.

- `Wax`, `WaxTypes`: candle economy and burn profiles.
- `Light`: dial limits and light-curve inputs.
- `Movement`: action speeds, costs, cooldowns, drain thresholds.
- `Character`: candle geometry and rig proportions.
- `Tools`, `Threats`, `Hazards`: generic-system content and tuning.
- `DripTrail`, `Basin`, `Brazier`: respective system values.
- `Floors`: floor counts, room modules, spawn budgets, geometry dimensions.
- `RunSettings`, `Death`: run timing/party/wisp and revival values.

### `src/shared/Logic/` — pure rules (no Roblox Instances)

- `CandleGeometry`: wax-to-body/flame geometry.
- `WaxDrain`: recurring drain pipeline and movement-mode calculation.
- `BrightnessMap`: burn rate to light values.
- `LightField`: light intensity and attractor queries.
- `ToolRules`: generic activation validation and aim clamping.
- `ThreatBrain`: generic threat decisions and movement.
- `HazardRules`: water and draft decisions.
- `SacrificeRules`: offers, grants, modifiers.
- `RewardMath`: payout breakdown.
- `FloorPlanner`: seeded floor-plan generation.

### `src/server/` — authoritative adapters

Server services own validation, state mutation, and Roblox Instances; rules belong in shared logic. Service names match their domains. Cross-cutting ownership: `PlayerState` stores state, `CharacterService` owns candle/wisp Instances, `LightSources` assembles the sole perception field, `WaxService` owns recurring and external-drain burnout handling, and `RunOrchestrator` owns phase transitions and teardown.

### `src/client/` — local input and display

- `CameraController`: candle first-person view/visibility.
- `DialController`, `MovementController`, `ToolController`: input and server requests only.
- `WaxBar`, `BasinPrompt`, `ResultsText`: UI driven by server state/events.

### `src/shared/Types/`, `Net/`, and `Interfaces/`

- `Types/` defines contracts; `Types/init.luau` re-exports them.
- `Net/Remotes` is the complete server/client contract. Server handlers validate all inbound data.
- `Interfaces/` holds explicitly in-memory stubs. Replace a deferred system through its one interface implementation plus its consumer, rather than spreading APIs.

## Safe extension recipes

- **New threat:** add a `Config/Threats.definitions` row and include the ID in eligible `Config/Floors.roomModules`. No per-threat class/branch.
- **New sacrifice with an existing target:** add a `Config/Basin.pool` row. A new target also requires its type and one `SacrificeRules` handler.
- **New room module:** add a `Config/Floors.roomModules` row; planner/builder consume it generically.
- **New tunable system:** create a focused config file, export it from `Config/init.luau`, document its values in `TUNING.md`, and add its route here.
- **New remote:** add its name/payload to `Net/Remotes.luau`, wire both endpoints, validate server input, and update this document if it adds a route.
- **New player-state field:** update `Types/Player.luau`, `PlayerState.freshState`, and intentionally decide whether it belongs in `StateSync` (`Net/Remotes` and `WaxService.replicate`).

## Supporting files

- `default.project.json`: Rojo source-to-Roblox mapping.
- `IMPLEMENTATION-NOTES.md`: caveats and manual testing.
- `NEXT-PASS-PROMPT.md`: follow-up context; not design authority.
- `rokit.toml`, `wally.toml`, `selene.toml`, `stylua.toml`: tooling/dependency and lint/format configuration.

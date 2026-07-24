# STRUCTURE — as built (vertical slice)

This file describes what actually exists. The rule set lives in `ARCHITECTURE.md`; the numbers
live in `src/shared/Config/` and are indexed by `TUNING.md`. Implementation caveats and the
manual test script live in `IMPLEMENTATION-NOTES.md`.

**The one organizing idea:** pure rules in `shared/Logic` (no Instances, no services — testable
cold), one thin server adapter per system (owns Instances, mutates state through the store),
one thin client controller per input surface. Threat perception is a single light-source list;
every tool works by editing that list.

## src/shared — types, config, pure logic

```
Types/          Domain types, re-exported from init.luau. Closed unions where design fixes the
                set (ToolId, ThreatCategory, HazardId, DeathCause); open string ids where content
                grows by config row (ThreatId, SacrificeId, RoomModuleId).
Config/         THE TUNING SURFACE. One file per system + init.luau aggregator. See TUNING.md.
Interfaces/     In-memory STUBS: Persistence, CaveTiers, Lineage, Remains, Party. Swap one file
                each to make real. Party takes present players as input (stays pure).
Net/Remotes.luau  Every RemoteEvent name + payload type. Server creates, client waits. The only
                file allowed to Instance.new a remote.
Logic/          Pure functions only:
  CandleGeometry.luau   wax -> body height / flame heights (single source of the shrink rule)
  WaxDrain.luau         the complete per-second drain pipeline + movement-mode-from-speed
  BrightnessMap.luau    burn rate -> light range/brightness/field intensity (one curve)
  LightField.luau       intensity at a point; strongest attractor near a point
  ToolRules.luau        activation validation + aim clamping (generic over ToolDef flags)
  ThreatBrain.luau      think/step for every threat row; categories differ only by lightResponse sign
  HazardRules.luau      water surface vs body height -> None/Wading/Lethal; draft snuff rules
  SacrificeRules.luau   offer rolling, depth-scaled grants, modifier application (dispatch by target)
  RewardMath.luau       the brazier formula, returned as a breakdown for display
  FloorPlanner.luau     config + seed -> FloorPlan (rooms, doorways, spawns, hazards, special rooms)
```

## src/server — authority (init.server.luau boots; the rest are ModuleScripts)

```
PlayerState.luau      THE store: { [userId]: PlayerRunState }. Only place state lives.
EnvironmentSetup.luau Runtime darkness (keeps default.project.json a plain scaffold).
CharacterService.luau Candle rig (root + welded cylinder + flame + PointLight), height scaling,
                      walk speed application, wisp spawn/freeze. Parts only, no decisions.
MovementService.luau  Dodge/slide/sprint validation, wax charges, walk-speed decision, slide expiry.
DialService.luau      Burn-rate requests: validate number, clamp vs config + sacrifice cap.
ToolService.luau      Tool activations, generic over ToolDef flags; owns decoys + flare lifetimes.
DripTrailService.luau Emits/expires drip points; serves them as breadcrumbs and light sources.
LightSources.luau     Assembles the full light field each tick (flames, flares, decoys, drips).
HazardService.luau    Zone registry (data boxes, no Touched); exposure queries via HazardRules.
WaxService.luau       THE authoritative tick: sample -> exposure -> water rule -> drain -> height
                      -> visuals -> replication. External drains route here for burnout detection.
ThreatService.luau    Spawns silhouettes from plans; brain in, part positions out; contact effects.
DeathService.luau     Snuffed state + relight prompts (reviver pays), terminal deaths, wisps.
BasinService.luau     Private offers per player (prompt -> roll -> choose -> apply), one per floor.
BrazierService.luau   Live reward preview, held-prompt commit, payout via Persistence stub.
FloorBuilder.luau     FloorPlan -> grey geometry; returns positions/zones for other services.
RunOrchestrator.luau  Phase machine: countdown -> build -> descend (per-player) -> all done -> reset.
```

Tick order (single Heartbeat in init.server): Orchestrator → DripTrail → Tools → **Wax** →
Threats → Death timers → Movement (slide expiry) → Brazier previews.

## src/client — display and input (init.client.luau boots)

```
CameraController.luau  First-person from the flame; own body kept visible (the emotional hook).
DialController.luau    Scroll wheel + draggable edge slider with config snap points; reconciles
                       to the server's clamped value when idle.
MovementController.luau Sprint/dodge/slide bindings (keyboard + CAS touch buttons); applies only
                       server-approved dodge velocity.
ToolController.luau    Keys 1-4 + touch buttons, one binding per tool row; Cast sends an aim point.
WaxBar.luau            The entire HUD: melt-line bar + lost-ceiling marker; dims when snuffed.
BasinPrompt.luau       Bare-text offer list (tap or number keys).
ResultsText.luau       All run text: countdown/floor/messages, live brazier arithmetic, results.
```

## Where authority lives

- Every wax number: server. Clients send *requests* (dial value, tool id, action); the server
  validates types, NaN, cooldowns, costs, and sacrifice flags before anything changes.
- Character physics: client-owned (Roblox humanoid networking). Server measures real speed for
  drain and uses server-sampled positions for hazards/threats/water. See IMPLEMENTATION-NOTES.
- The water rule, the shrink rule, threat decisions, sacrifice math, reward math: pure shared
  functions. They can be unit-tested without Studio.

## Extension recipes

- **New threat** → row in `Config/Threats.definitions` (+ allow it in room modules).
- **New sacrifice** → row in `Config/Basin.pool` (new target = one handler in SacrificeRules).
- **New wax type** → row in `Config/WaxTypes` + id in `Types/Wax`.
- **New room module** → row in `Config/Floors.roomModules`.
- **Deferred system goes real** → replace the one file in `shared/Interfaces/`.

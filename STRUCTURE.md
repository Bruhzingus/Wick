# STRUCTURE — as built (Phase 0–5 prototype)

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
                grows by config row (ThreatId, LootId, SacrificeId, RoomModuleId).
Config/         THE TUNING SURFACE. One file per system + init.luau aggregator. Feel owns
                cosmetic feedback/shared bindings; Audio is the safe cue-to-asset registry;
                CaveTiers, Lobby, and Security own access, session-flow, and trust-boundary
                values. See TUNING.md.
Interfaces/     Replaceable backend boundaries. Persistence uses ProfileStore (Mock in Studio);
                CaveTiers, Party, and session-local Remains are implemented. Lineage is the only
                remaining stub; global remains stay deferred.
Net/Remotes.luau  Every RemoteEvent name + payload type. Server creates, client waits. The only
                file allowed to Instance.new a remote.
Logic/          Pure functions only:
  CandleGeometry.luau   wax -> body height / flame heights (single source of the shrink rule)
  WaxDrain.luau         the complete per-second drain pipeline + movement-mode-from-speed
  BrightnessMap.luau    burn rate -> light range/brightness/field intensity (one curve)
  LightField.luau       intensity at a point; strongest attractor near a point
  ToolRules.luau        activation validation + aim clamping (generic over ToolDef flags)
  LootRules.luau        wax-profile replacement + free charges for the existing tool path
  ThreatBrain.luau      think/step for every threat row; categories differ only by lightResponse sign
  RoomNavigation.luau   FloorPlan door graph -> one-doorway waypoint; Basin exclusion/step guard
  HazardRules.luau      water surface vs body height -> None/Wading/Lethal; draft snuff rules
  SacrificeRules.luau   offer rolling, depth-scaled grants, modifier application (dispatch by target)
  RewardMath.luau       the brazier formula, returned as a breakdown for display
  FloorPlanner.luau     config + seed -> FloorPlan (rooms, depth-weighted threats, loot, hazards)
  TokenBucket.luau      deterministic request-throttle state transition
Tests/          Compact deterministic harness + one suite per pure-rule domain. `Tests/init.luau`
                is the inert registry called by the Studio-only server runner.
```

## src/server — authority (init.server.luau boots; the rest are ModuleScripts)

```
PlayerState.luau      THE store: { [userId]: PlayerRunState }. Only place state lives.
EnvironmentSetup.luau Runtime darkness (keeps default.project.json a plain scaffold).
RequestGuard.luau     Per-player remote token buckets + finite number/vector validation helpers.
Telemetry.luau        Structured `[WICK]` prototype events written to server Output.
MovementSanityService.luau
                      Tracks one-second trusted movement anchors, one-time approved action
                      allowances, and authorized spawn/descent teleports; corrects excess travel.
PartyLobbyService.luau
                      One auto-joined party, leader/ready/tier validation, live reserved-server
                      teleport, and Studio local-start fallback.
CharacterService.luau Candle rig (root + welded cylinder + flame + PointLight), height scaling,
                      walk speed application, wisp spawn/freeze. Parts only, no decisions.
MovementService.luau  Dodge/slide/sprint validation, wax charges, walk-speed decision, slide expiry.
DialService.luau      Burn-rate requests: validate number, clamp vs config + sacrifice cap.
ToolService.luau      Tool activations, generic over ToolDef flags; owns decoys + flare lifetimes.
DripTrailService.luau Emits/expires drip points; serves them as breadcrumbs and light sources.
LightSources.luau     Assembles the full light field each tick (flames, flares, decoys, drips).
LootService.luau      Planned wax/charge pickup Instances; validates and applies pickup effects.
RemainsService.luau   Rebuilds session remains, atomically recovers up to candle capacity while
                      preserving overflow, and contributes their light.
HazardService.luau    Zone registry (data boxes, no Touched); exposure queries via HazardRules.
WaxService.luau       THE authoritative tick: sample -> exposure -> water rule -> drain -> height
                      -> visuals -> replication. External drains route here for burnout detection.
ThreatService.luau    Spawns silhouettes from plans; applies generic brain decisions through
                      room-graph waypoints; filters protected Basin perception/contact.
DeathService.luau     Snuffed state + relight prompts (reviver pays), terminal deaths, wisps.
BasinService.luau     Private offers per player (prompt -> roll -> choose -> apply), one per floor.
BrazierService.luau   Live reward preview, held-prompt commit, ProfileStore payout + tier unlock.
FloorBuilder.luau     FloorPlan -> grey geometry; returns positions/zones for other services.
RunOrchestrator.luau  Expedition phase machine after lobby handoff: countdown -> build -> descend
                      (per-player) -> all done -> reset.
StudioTestRunner.server.luau
                      Studio-only Script: runs shared pure-rule suites once and reports a grouped
                      PASS/FAIL result without blocking the normal gameplay boot Script.
```

Tick order (single Heartbeat in init.server): Orchestrator → Movement sanity → DripTrail → Tools
→ **Wax** → Threats → Death timers → Movement (slide expiry) → Brazier previews.

## src/client — display and input (init.client.luau boots)

```
CameraController.luau  First-person from the flame; own body kept visible (the emotional hook).
AudioCues.luau         Config cue name -> local Sound lifecycle; empty/invalid asset IDs no-op.
FeelController.luau    Cosmetic flame flicker, hazard grading, and nearby-threat cue requests.
DialController.luau    Scroll wheel + draggable edge slider with config snap points; reconciles
                       to the server's clamped value when idle.
MovementController.luau Sprint/dodge/slide bindings (keyboard + CAS touch buttons); applies only
                       server-approved dodge velocity.
ToolController.luau    Keys 1-4 + touch buttons, one binding per tool row; Cast sends an aim point.
HotbarController.luau  Responsive desktop/touch binding legend + free tool-charge counts.
WaxBar.luau            Melt-line bar + lost-ceiling marker; dims when snuffed and pulses when low.
BasinPrompt.luau       Bare-text offer list (tap or number keys).
ResultsText.luau       All run text: countdown/floor/messages, live brazier arithmetic, results.
LobbyController.luau   One-party member/ready list, cave-tier buttons, and leader start control;
                       hides gameplay UI until the expedition begins.
```

## Runtime topology

- A public server is a minimal grey-box lobby with one auto-joined party, capped at four.
- The leader selects a tier that every member has unlocked; every member readies; the leader
  starts.
- In Studio, `PartyLobbyService` starts the expedition in the same server because teleports are
  unavailable. In a published live server, it reserves another server of the same place and
  passes the tier/member list through teleport data.
- A reserved server waits up to `Lobby.arrivalWaitSeconds` for expected profiles before starting
  its countdown; slower late arrivals remain eligible to join the active expedition.
- The expedition server is disposable. Profile data is the only durable state. Remains persist
  only across runs in that one server and are lost when it closes.

## Where authority lives

- Every wax number: server. Clients send *requests* (dial value, tool id, action); the server
  validates types, NaN, cooldowns, costs, and sacrifice flags before anything changes.
- Character physics: client-owned (Roblox humanoid networking). Server measures real speed for
  drain, uses server-sampled positions for hazards/threats/water, and corrects excess sustained
  displacement while accounting for approved dodge/slide bursts. See IMPLEMENTATION-NOTES.
- The water rule, the shrink rule, threat decisions, sacrifice math, reward math: pure shared
  functions. They can be unit-tested without Studio.
- Durable profile currency/tier access: `Interfaces/Persistence` through ProfileStore. Studio
  always uses isolated mock data; gameplay code never calls DataStore directly.

## Extension recipes

- **New threat** → row in `Config/Threats.definitions` (+ allow it in room modules).
- **New sacrifice** → row in `Config/Basin.pool` (new target = one handler in SacrificeRules).
- **New wax type** → row in `Config/WaxTypes` + id in `Types/Wax`.
- **New room module** → row in `Config/Floors.roomModules`.
- **Persistent profile change** → update the type/default/save path in
  `Interfaces/Persistence`, then the focused consumer; never add raw DataStore calls.
- **Deferred system goes real** → preserve its focused `shared/Interfaces/` boundary and add
  Instance/UI adapters only where needed. Currently this applies to Lineage; global remains are
  a backend replacement, not a second gameplay API.

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
Config/         THE TUNING SURFACE. One file per system + init.luau aggregator. Light owns
                candle rendering/flicker values; Feel owns other cosmetic feedback/shared
                bindings; Audio is the safe cue-to-asset registry; CaveTiers, Lobby, and Security
                own access, session-flow, and trust-boundary values; LobbyRoom owns the static
                physical hub's geometry, elevator/tier mapping, descent-ride travel, lobby-only
                movement speeds, and board copy. See TUNING.md.
Interfaces/     Replaceable backend boundaries. Persistence uses ProfileStore (Mock in Studio);
                CaveTiers, Party, session-local Remains, and the cross-server deepest-floor
                Leaderboard (OrderedDataStore; disabled in Studio) are implemented. Lineage is the
                only remaining stub; global remains stay deferred. Server-only: Persistence requires
                ServerScriptService, so no client may require Interfaces.
Net/Remotes.luau  Every RemoteEvent name + payload type. Server creates, client waits. The only
                file allowed to Instance.new a remote.
LightVisualProtocol.luau
                Tag/attribute contract for server-published, client-rendered candle light.
DripstoneVisualProtocol.luau
                Tag/state/timestamp contract for one shared unstable formation lifecycle.
LobbyVisualProtocol.luau
                The lobby/run presentation boundary: the in-car readout tag, its tierId attribute,
                and the runBody attribute that tells a candle/wisp apart from the lobby's Roblox
                avatar (static; all set once at build/spawn).
NewModelsAndObjects/
                Procedural creature/cave presentation builders plus the shared proxy attribute
                contract. Creature bodies animate locally; CaveKit and UnstableDripstone geometry
                and diegetic LootPickup models are server-built, while dangerous formations
                animate locally from shared state.
Logic/          Pure functions only:
  CandleGeometry.luau   wax -> body height / flame heights (single source of the shrink rule)
  WaxDrain.luau         the complete per-second drain pipeline + movement-mode-from-speed
  BrightnessMap.luau    burn rate -> light range/brightness/field intensity (one curve)
  FlameFlicker.luau     owner-seeded layered cosmetic brightness/warmth signal
  LightField.luau       intensity/attractor queries + dark-hunter source perception filter
  ToolRules.luau        activation validation + grounded-Decoy clamp/arc/surface rules
  CooldownRules.luau    read-only tool/Snuff-relight cooldown projection
  LootRules.luau        wax-profile replacement + free charges for the existing tool path
  ThreatBrain.luau      generic roam/hunt/stalk/retreat/ambush, staged-contact count, and movement
  RoomNavigation.luau   Door graph + localized-pool detours; Basin exclusion/step guard
  HazardRules.luau      water surface vs body height -> None/Wading/Lethal
  DripstoneRules.luau   target curve, silhouette extent, analytic fall, hit disc, light suppression
  GroundGeometry.luau   shared seeded floor field, doorway lanes, swells, and water bowls
  RoofGeometry.luau     seeded relief + exact underside sampled by planner and Terrain builder
  DoorwayGeometry.luau  one shared-edge seed -> width/height/lateral offset, read by both the
                        builder (cuts the opening) and navigation (aims threats through it)
  SacrificeRules.luau   offer rolling, depth-scaled grants, modifier application (dispatch by target)
  RewardMath.luau       the brazier formula, returned as a breakdown for display
  FloorPlanner.luau     config + seed -> looped plan, dry route, deterministic threat offsets,
                        ceiling caps, pools, rises, and dripstones
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
                      One auto-joined party, leader/ready/tier validation (`tryStart`/`canStart`,
                      also called by ElevatorService), live reserved-server teleport, Studio
                      local-start fallback, lobby-body spawn on join/return, and post-run
                      lobby/unlock refresh.
LobbyRoomBuilder.luau One fixed mineshaft hub ("The Landing") built once at boot, not seeded/rebuilt
                      per run: SpawnLocation, shop stall, welcome/how-to-play/standings boards, and
                      three elevator alcoves — each a movable car model, a ribbed descent shaft, and
                      a header board. Places Instances and hands out references; decides nothing.
ElevatorService.luau  The physical lobby's entire tier-select/ready/start interaction AND the descent
                      ride: elevator zone -> Party.setTier/setReady mapping (unlock-guarded), live
                      header boards, leader-only descend lever, and the car+riders descent that
                      replaces the old flat loading countdown. Also recovers anyone who falls into
                      an open shaft.
LeaderboardService.luau
                      Repaints the hub's standings board from Interfaces.Leaderboard on a timer.
CharacterService.luau Candle rig (root + welded cylinder + flame), height scaling, tagged light
                      target attributes, walk speed application, wisp spawn/freeze. Also owns the
                      lobby body — the player's REAL Roblox avatar (`spawnLobby`) — tracked apart
                      from run rigs, so WaxService/MovementSanityService never see it.
MovementService.luau  Sprint validation and walk-speed decision.
DialService.luau      Burn-rate requests: validate number, clamp vs config + sacrifice cap.
ActionFeedbackService.luau
                      Immediate accepted/rejected action feedback in synchronized server-time space.
ToolService.luau      Tool activations; resolves grounded Decoy candles and owns decoy/flare lifetimes.
DripTrailService.luau Emits/expires dull wax drops; serves geometric hunter breadcrumbs only.
LightSources.luau     Assembles the full light field (flames, flares, decoys, remains).
LootService.luau      Planned wax/charge models on exact GroundGeometry surfaces; validates and
                      applies pickup effects.
RemainsService.luau   Rebuilds session remains, atomically recovers up to candle capacity while
                      preserving overflow, and contributes their light.
HazardService.luau    Zone registry (data boxes, no Touched); exposure queries via HazardRules.
WaxService.luau       THE authoritative tick: sample -> exposure -> water rule -> drain -> height
                      -> visuals -> replication. External drains and timed light suppression route
                      here so burnout, candle output, and threat perception remain consistent.
DripstoneService.luau Shared Dormant -> Warning -> Falling -> Spent state machine; fixed trigger,
                      multi-player impact selection, wax loss, partial snuff, and impact broadcast.
ThreatVisualProxy.luau
                      One invisible replicated root per threat plus quantized cosmetic attributes.
ThreatService.luau    Applies generic brain decisions through room-graph waypoints to visual
                      proxies; exact roof-following/smoothed dives for ambush profiles; idle
                      wall-perch resting for perch profiles; filters other floors plus
                      protected/snuffed-player perception and contact.
DeathService.luau     Snuffed state + relight prompts (reviver pays), terminal deaths, wisps.
BasinService.luau     Private offers per player (prompt -> roll -> choose -> apply), one per floor.
BrazierService.luau   Live reward preview, held-prompt commit, ProfileStore payout + tier unlock.
FloorBuilder.luau     FloorPlan -> paired floor/inverted-roof Terrain fields plus exact room-surface
                      runtime data; reserves ambush patches from deterministic CaveKit dressing;
                      builds recessed pools, unstable formations, geometry, and zones.
RunOrchestrator.luau  Expedition phase machine after lobby handoff: countdown -> build -> descend
                      (per-player) -> all done -> reset.
StudioTestRunner.server.luau
                      Studio-only Script: runs shared pure-rule suites once and reports a grouped
                      PASS/FAIL result without blocking the normal gameplay boot Script.
VineService.luau      Tracks per-doorway burn-through state against `Logic/VineRules`, using the
                      same isLit/isCupping/burnRate/isFlaring inputs WaxService already computes.
ServerInit.server.lua Boots the Stone Warden system: finds real ground per eligible floor
                      (Floor 4+) by raycasting that floor's own Terrain, and spawns one dormant
                      pile + relic per floor, parented so RunOrchestrator's floor teardown cleans
                      it up automatically.
StoneWardenSystem/    StoneWardenBehavior.lua (dormant -> emerging -> active state machine,
                      PathfindingService chase, contact kill, dripstone-stun via WardenRegistry)
                      and StoneWardenModel.lua (procedural rubble-pile and active-golem geometry
                      from the shared cool-rock palette). Written as loose `.lua`, not strict
                      Luau — the one exception to the codebase's usual Config/Logic split; values
                      are hardcoded in the behavior script rather than pulled from `shared/Config`.
WardenRegistry.luau   Lets `DripstoneService` look up and stun the active Warden on a floor by
                      depth without either system holding a direct reference to the other.
```

Tick order (single Heartbeat in init.server): Elevators → Orchestrator → Movement sanity →
DripTrail → Tools → **Wax** → Dripstone → Threats → Death timers → Movement →
Brazier previews.

## src/client — display and input (init.client.luau boots)

```
CameraController.luau  First-person from the flame; owns restart subject reassignment and body visibility.
SprintFeedbackController.luau
                      Local accepted-sprint FOV, vignette/shimmer/streaks, and unstable camera motion.
EnvironmentAnimationController.luau  Local water-sheen/bob and wind-volume animation.
DripstoneController.luau
                      Tagged warning/fall reconstruction plus dust, debris, positional fracture/
                      impact cues, camera shake, impact grading, and flame flicker.
ElevatorController.luau
                      Rider-side ride presentation only: camera shudder and the in-car descent
                      readout, reset on arrival or on a ride that never produced a floor. The car
                      and gate are moved server-side so the whole room sees them. Never selects
                      tiers, timing, or victims.
AudioCues.luau         Config cue name -> local Sound lifecycle, loop volume, and load diagnostics;
                       supports world-attached spatial cues; WickMaster owns local volume.
MusicController.luau   Menu music + shuffled non-repeating cave playlist with delayed starts,
                       silent gaps, preloading, and fade-in/fade-out transitions.
CandleLightController.luau
                      Sole candle-light renderer: eased authoritative targets, deterministic
                      party-visible combustion flicker, one stable spherical shadow accent,
                      omni fill/bounce, and post FX without flickering range or carrier position.
FeelController.luau    Hazard grading and nearby-threat cues; forwards local threat flicker context.
ThreatVisualController.luau
                      Client-built creature bodies, local animation/culling, and occluded fly buzzes.
DialController.luau    Scroll wheel + draggable edge slider with config snap points; reconciles
                       to the server's clamped value when idle.
MovementController.luau Sprint binding (keyboard + CAS touch button).
ToolController.luau    Keys 1-4 + touch buttons; Decoy proposes horizontal aim and cues only accepted use.
HotbarController.luau  Responsive legend, free charges, active Cup/Snuff labels, and reconciled cooldown bars.
HintController.luau    Fading first-three-floor threat and environmental teaching hints.
WaxBar.luau            Melt-line bar + lost-ceiling marker; dims when snuffed and pulses when low.
BasinPrompt.luau       Themed offer panel (UITheme cards, tap or number keys); server rolls/validates.
ResultsText.luau       All run text: countdown/floor/messages, live brazier arithmetic, results,
                       replay, and back-to-lobby controls.
LobbyController.luau   Gameplay-input/GUI toggling across the lobby<->expedition boundary and a
                       small non-modal status readout; tier-select/ready/start now live entirely
                       in the physical lobby (ElevatorService/ElevatorController), not here.
LobbyMovementController.luau
                       Hub-only sprint on the shared Feel sprint binding. Costs no wax and is not
                       authoritative (the lobby body has no PlayerState); binds only while
                       MovementController's expedition bindings are off, so exactly one owns the key.
CursorController.luau  Keeps first-person mouse capture during play; releases it for every
                       interactive WICK screen and Roblox's native menu.
SettingsController.luau
                      Local in-run settings menu (M): mouse sensitivity and audio volume only;
                      never touches authoritative gameplay values.
RelightPromptController.luau
                      Hides a snuffed candle's impossible self-relight prompt locally; the
                      server-created prompt stays available to teammates.
UITheme.luau           Shared palette/fonts/motion presets and composited WICK-logo widgets
                       (wordmark, candle glyph) consumed by most of the above UI controllers.
```

## src/replicatedfirst — earliest-possible boot screen

```
WickLoadingScreen.client.luau
                      Runs before ReplicatedStorage.Shared is guaranteed available, so it cannot
                      require UITheme; it duplicates the wordmark/candle-glyph drawing inline
                      (kept in sync with UITheme by comment on both sides) and tears itself down
                      once the game has finished loading.
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
  displacement at the configured run speed. See IMPLEMENTATION-NOTES.
- The water rule, the shrink rule, threat decisions, sacrifice math, reward math: pure shared
  functions. They can be unit-tested without Studio.
- Dripstone trigger/impact selection, wax loss, and temporary light suppression are server-owned.
  The server replicates one lifecycle timestamp; clients reconstruct the same anchored warning and
  analytic vertical fall without network-owned physics or `Touched` damage.
- Durable profile currency/tier access: `Interfaces/Persistence` through ProfileStore. Studio
  always uses isolated mock data; gameplay code never calls DataStore directly.

## Extension recipes

- **New threat** → row in `Config/Threats.definitions` (+ allow it in room modules).
- **New sacrifice** → row in `Config/Basin.pool` (new target = one handler in SacrificeRules).
- **New wax type** → row in `Config/WaxTypes` + id in `Types/Wax`.
- **New room module** → row in `Config/Floors.roomModules`.
- **New unstable-dripstone silhouette** → variant row in
  `Config/Hazards.unstableDripstone.variants`; preserve the shared fractured-collar/lean/dust tell
  and the generic DripstoneRules/Service lifecycle.
- **Persistent profile change** → update the type/default/save path in
  `Interfaces/Persistence`, then the focused consumer; never add raw DataStore calls.
- **Deferred system goes real** → preserve its focused `shared/Interfaces/` boundary and add
  Instance/UI adapters only where needed. Currently this applies to Lineage; global remains are
  a backend replacement, not a second gameplay API.

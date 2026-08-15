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
                movement speeds, and board copy; Spectator owns the whole ghost-candle form a dead
                player takes (body, faint light, following, ghost-only trail); Cauldron, Lantern and
                DescentLadder own the three per-floor fixtures' presentation and the ladder's ride
                timing, kept apart from Basin/Brazier which own the rules those fixtures wear. See
                TUNING.md.
Interfaces/     Replaceable backend boundaries. Persistence uses ProfileStore (Mock in Studio);
                CaveTiers, Party, session-local Remains, and the cross-server deepest-floor
                Leaderboard (OrderedDataStore; disabled in Studio) are implemented. Lineage is the
                only remaining stub; global remains stay deferred. Server-only: Persistence requires
                ServerScriptService, so no client may require Interfaces.
Net/Remotes.luau  Every RemoteEvent name + payload type. Server creates, client waits. The only
                file allowed to Instance.new a remote.
MiningVisualProtocol.luau
                Tag/attribute contract for server-owned deposit progress, plus the MineState payload
                kinds. Rail motion is never replicated: authoritative sweep stamps/bands reconstruct
                it, while a bounded shared-clock click sample removes ordinary scoring latency.
LightVisualProtocol.luau
                Tag/attribute contract for server-published, client-rendered candle light.
DripstoneVisualProtocol.luau
                Tag/state/timestamp contract for one shared unstable formation lifecycle.
DynamiteVisualProtocol.luau
                Tag/attribute contract for a blast door. Attributes rather than a remote because the
                socket marker is PER PLAYER — only somebody carrying a stick may see it — so the door
                publishes what it is once and the client decides what to draw.
LobbyVisualProtocol.luau
                The lobby/run presentation boundary: the in-car readout tag, its tierId attribute,
                and the runBody attribute that tells a candle/wisp apart from the lobby's Roblox
                avatar (static; all set once at build/spawn).
MineRelicVisualProtocol.luau
                Tag plus emitter-attachment name for one abandoned working. No state and no
                attributes on purpose: the server builds a relic once and never touches it, and the
                only client that reads one is the ambience director looking for something to creak.
NewModelsAndObjects/
                Procedural creature/cave presentation builders plus the shared proxy attribute
                contract. WaxDeposit builds and wears down the one Raw Wax seam silhouette. Creature bodies animate locally; CaveKit and UnstableDripstone geometry
                and diegetic LootPickup models are server-built, while dangerous formations
                animate locally from shared state. MineRelics builds the eleven abandoned-workings
                silhouettes (ore cart, rail run, buffer stop, prop frame, crates, powder kegs,
                windlass, hook post, barrow, tool rack, ladder) — pure dressing with collision on
                mass only, weathered per family through `CaveFamilyRules.relicWeathering`.
                Cauldron, Lantern and DescentLadder build the three per-floor fixtures — the Basin's
                vessel, the cold-until-lit gas lamp a run ends at plus its directional room light,
                and the one-person cage, its
                headframe, its lined shaft and its hatch — all styled from one resolved
                `CaveFamilyRules.fixtureStyle` block and owning no rule of their own.
Logic/          Pure functions only:
  CandleGeometry.luau   wax -> body height / flame heights (single source of the shrink rule)
  WaxDrain.luau         the complete per-second drain pipeline + movement-mode-from-speed
  BrightnessMap.luau    burn rate -> light range/brightness/field intensity (one curve)
  FlameFlicker.luau     owner-seeded layered cosmetic brightness/warmth signal
  LightField.luau       intensity/attractor queries + dark-hunter source perception filter
  SoundField.luau       the SECOND perception field: decaying noise events, summed loudness at a
                        point, and the curiosity check a listener runs. Distance falloff x time
                        decay, so repeated noises overlap and add
  MiningRules.luau      strike validation (begin and resolve as separate checks), the timing sweep
                        -> fracture-rail accuracy band, bounded click-clock conversion, progress per
                        band, and which noise row a swing emits
  ToolRules.luau        activation validation + grounded-Decoy clamp/arc/surface rules
  DynamiteRules.luau    the found consumable (DESIGN §6a): the bag and its carry cap, the stateless
                        every-N-floors supply schedule walked from the RUN seed rather than a floor's,
                        blast falloff for candles and for bodies, per-creature lethality, and the
                        thrown-stick door break radius
  CooldownRules.luau    read-only tool cooldown projection
  LootRules.luau        wax-profile replacement + free charges for the existing tool path
  ThreatBrain.luau      generic roam/hunt/stalk/retreat/ambush, staged-contact count, and movement
  RoomNavigation.luau   Door graph + localized-pool detours. NO room is excluded: the Basin and sealed
                        blast vaults are ordinary nodes, so anything can roam anywhere on a floor
  HazardRules.luau      water surface vs body height -> None/Wading/Lethal
  DripstoneRules.luau   target curve, silhouette extent, analytic fall, hit disc, light suppression
  GroundGeometry.luau   shared seeded floor field, doorway lanes, swells, and water bowls
  RoofGeometry.luau     seeded relief + exact underside sampled by planner and Terrain builder
  DoorwayGeometry.luau  one shared-edge seed -> width/height/lateral offset, read by both the
                        builder (cuts the opening) and navigation (aims threats through it)
  SacrificeRules.luau   offer rolling, depth-scaled grants, modifier application (dispatch by target)
  ExtractionValue.luau  what a bag of Raw Wax is worth, as a breakdown for display
  CargoRules.luau       the five cargo verbs; conservation is the invariant
  LampRules.luau        Lamp Network prerequisites, contracts, and wager arithmetic
  SpectatorRules.luau   ghost-candle rules: who is a ghost, who it may follow, when a footfall is
                        recorded, how a trail ages out, the follow cycle, and when a ghost is pulled
  FloorPlanner.luau     config + seed -> looped plan, dry route, deterministic threat offsets,
                        Warden branches, ceiling caps, pools, rises, and dripstones
  MineRelicRules.luau   which abandoned working a floor gets: depth eligibility, the fixed catalog
                        cycle that stops two floors running from sharing a silhouette, the floor and
                        room rolls, and config validation
  PlacementReservations.luau
                        pure XZ footprint overlap ledger shared by planning and cave dressing
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
                      header boards, the descent lever's lamp (the lever takes no input), and the
                      car+riders descent that
                      replaces the old flat loading countdown. Also recovers anyone who falls into
                      an open shaft.
LeaderboardService.luau
                      Repaints the hub's standings board from Interfaces.Leaderboard on a timer.
CharacterService.luau Candle rig (root + welded cylinder + flame), height scaling, tagged light
                      target attributes, walk speed application. Also owns the lobby body — the
                      player's REAL Roblox avatar (`spawnLobby`) — and the translucent ghost candle
                      (`spawnSpectator`), each tracked apart from run rigs so
                      WaxService/MovementSanityService never see them. Registers the two collision
                      groups that let a ghost be stopped by rock and by nothing else.
MovementService.luau  Server-owned default-run and slower-state walk-speed decision.
DialService.luau      Burn-rate requests: validate number, clamp vs config + sacrifice cap.
ActionFeedbackService.luau
                      Immediate accepted/rejected action feedback in synchronized server-time space.
ToolService.luau      Tool activations; resolves grounded Decoy candles and owns decoy/flare lifetimes.
DripTrailService.luau Emits/expires dull wax drops; serves geometric hunter breadcrumbs only.
LightSources.luau     Assembles the full light field (flames, flares, decoys, remains).
NoiseService.luau     The sound field's registry: emit/expire decaying noise events. Emitters are
                      mining strikes, default running (throttled), dripstone impacts, and vine ignition —
                      each one call at a site that already knew the event happened.
MiningService.luau    Raw Wax deposits: owns progress, depletion, the one-open-swing table, the
                      movement commitment, wear, noise, per-swing cargo grants, and shared contact
                      broadcast. Also owns the Explosive Seam's fuse — the prime roll, the three-second
                      countdown, and the blast that calls every threat on the floor to one place (the
                      only line in the file that touches ThreatService).
                      Stamps every sweep server-side; only scoring may use the finite/in-window
                      shared click sample, while validation/cooldowns/progress remain arrival-owned.
LootService.luau      Planned wax/charge models on exact GroundGeometry surfaces; validates and
                      applies pickup effects.
DynamiteService.luau  The found consumable's whole authority (DESIGN §6a): the throw's landing (the
                      Decoy's own arc solver), the blast-door socket's place/light pair, both fuses,
                      and the blast itself — player wax through WaxService, scaled body damage through
                      ThreatService.applyBlast, the Warden through WardenRegistry, door breaks, the
                      noise, and the floor-wide alarm. The one place in the game a threat can die.
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
                      protected/snuffed-player perception and contact. Also filters noise events by
                      protected room and hands deaf rows an empty list.
DeathService.luau     Snuffed state + relight prompts (reviver pays), terminal deaths; hands a
                      terminal death to SpectatorService and owns nothing about the ghost after that.
SpectatorService.luau The form a terminally dead player takes: the ghost candle's follow target and
                      anchor pulls, its almost-nothing light and that light's expiry, the per-runner
                      footfall buffers, and their replication TO DEAD PLAYERS ONLY. Never enters the
                      light or sound field, so nothing in the cave can perceive a ghost.
BasinService.luau     Private offers per player (prompt -> roll -> choose -> apply), one per floor.
BrazierService.luau   Live reward preview, held-prompt commit, ProfileStore payout + tier unlock.
                      Also latches the floor's Gas Lantern lit — shared and one-way, while each
                      player's reward stays independent — lights FloorBuilder's room-wide lamp
                      network outward, and on first ignition clears that depth's enemies through
                      their owning services. Owns the
                      separate unanimous group-ready prompt and the five-second normal-camera scene
                      for a complete group or the last unresolved runner; early individuals get an
                      immediate card. CharacterService only freezes and initially faces the body.
DescentLadderService.luau
                      The way down: the cage's prompt, the ride's clock, and every pose written to
                      the cage and its hatch. Owns no floor knowledge; RunOrchestrator hands it one
                      callback that answers whether a player may set off (building the floor below
                      if the lookahead has not reached it, so the carve hides inside the ride) and
                      one that performs the move when the cage lands.
FloorBuilder.luau     FloorPlan -> paired floor/inverted-roof Terrain fields plus exact room-surface
                      runtime data; reserves gameplay and Lurker-arch space from deterministic
                      CaveKit dressing; builds recessed pools, unstable formations, geometry, zones,
                      and real-Terrain surface mounts for the one-lamp-per-room cave network.
RunOrchestrator.luau  Expedition phase machine after lobby handoff: countdown -> build -> descend
                      (per-player) -> all done -> reset. Descent is no longer a zone poll: the two
                      halves of it (may this player go / put them on the next floor) are handed to
                      DescentLadderService, which is also ticked here so a landing cage carves in
                      the same slot the old check did.
StudioTestRunner.server.luau
                      Studio-only Script: runs shared pure-rule suites once and reports a grouped
                      PASS/FAIL result without blocking the normal gameplay boot Script.
VineService.luau      Tracks per-doorway ignition and burn-through against `Logic/VineRules`, using
                      the same isLit/isCupping/burnRate/isFlaring inputs WaxService already computes,
                      and spreads fire from a lit curtain to the others in range on the floor.
AshamedLurkerService.luau
                      Owns the deep-floor arch creature: measured-speed trip detection, the delayed
                      grab check, camera-report validation for the stare, the wax it takes through
                      `WaxService.drainExternal`, and moving its one proxy part to a different arch
                      50 s after being shamed off. Bodies are built by every client, never here;
                      `despawnDepth` invalidates its runtime and destroys its proxy when a floor lights.
StoneWardenService.luau
                      Realizes the planner-owned optional Warden room on FloorBuilder's exact ground
                      field and emits spawn diagnostics. Production encounter handles are retained by
                      depth for explicit lantern, floor-retirement, and run-reset cleanup; developer
                      test encounters remain owned by their test sessions.
StoneWardenSystem/    StoneWardenBehavior.lua (dormant -> emerging -> active state machine,
                      PathfindingService chase, contact kill, dripstone-stun via WardenRegistry)
                      and StoneWardenModel.lua (procedural rubble-pile and active-golem geometry
                      from the shared cool-rock palette). Written as loose `.lua`, not strict
                      Luau; its tunable behaviour values come from `shared/Config/StoneWarden`.
WardenRegistry.luau   Lets `DripstoneService` look up and stun the active Warden on a floor by
                      depth without either system holding a direct reference to the other.
```

Tick order (single Heartbeat in init.server): Elevators → Orchestrator (which internally runs
stranded-runner recovery → **descent ladders** → one queued floor carve → floor retirement, in that
order and for that reason) → Movement sanity →
DripTrail → Tools → Mining (abandon invalidated swings) → Dynamite (fuses, before Wax so a candle
caught in its own blast pays on the same tick) → **Wax** → Dripstone → Vines → Ashamed Lurkers →
Noise (expire spent events) → Threats → Death timers → Spectators (record the survivors' footfalls,
body anyone who just stopped being one) → Movement → Brazier previews.

## src/client — display and input (init.client.luau boots)

```
CameraController.luau  First-person from the flame; owns restart subject reassignment and body visibility.
SprintFeedbackController.luau
                      Local default-run FOV, vignette/shimmer/streaks, and unstable camera motion.
EnvironmentAnimationController.luau  Local water-sheen/bob, wind-volume animation, and the Basin
                      Cauldron's slow wax swell — one tag-and-attribute animator, not two systems.
DripstoneController.luau
                      Tagged warning/fall reconstruction plus dust, debris, positional fracture/
                      impact cues, camera shake, impact grading, and flame flicker.
ElevatorController.luau
                      Rider-side ride presentation only: camera shudder and the in-car descent
                      readout, reset on arrival or on a ride that never produced a floor. The car
                      and gate are moved server-side so the whole room sees them. Never selects
                      tiers, timing, or victims.
DescentLadderController.luau
                      The cave ladder's ride, drawn the same way: one timestamped curve evaluated
                      locally for the cage and the rider it carries, plus the winch loop and the
                      rider's camera shudder (through the same CameraController offset writer the
                      lobby ride uses). Decides nothing; the hatch is server-posed.
LanternPresentation.luau
                      The Gas Lantern's ignition beat: the flare that decays back to the lamp's
                      steady output and delayed quieter copies of the ignition cue that answer it.
                      Creates no camera override or travelling glow geometry.
AudioCues.luau         Config cue name -> bounded local mixer. Builds WickMaster plus Music/
                       Ambience/World/Focus/UI buses, preload/failure diagnostics, per-emitter
                       cooldowns, variation, voice limits/stealing, EQ/reverb, Focus ducking, and
                       raycast/EQ obstruction for world-attached spatial cues.
MusicController.luau   Menu music (including its lobby-only volume multiplier) + shuffled
                       non-repeating cave playlist with delayed starts, silent gaps, preloading,
                       and fade-in/fade-out transitions.
AmbientCaveDirector.luau
                      Sole harmless cave-event clock: exponential silence, refractory time, silent
                      outcomes, anti-repeat history, Focus gating, and real surface placement for
                      five natural families plus rockfall/drip. Also the abandoned-workings settle,
                      the one candidate anchored to a real tagged relic rather than a raycast
                      surface — it refuses outright when the floor has no equipment on it.
AmbientRockfallController.luau / AmbientWaterDripController.luau
                      Geometry-valid presentation called by AmbientCaveDirector; no independent
                      timer, gameplay noise, hitbox, or server state.
CandleLightController.luau
                      Sole candle-light renderer: eased authoritative targets, deterministic
                      party-visible combustion flicker, one stable spherical shadow accent,
                      omni fill/bounce, and post FX without flickering range or carrier position.
FeelController.luau    Hazard grading and nearby-threat cues; forwards local threat flicker context.
ThreatVisualController.luau
                      Client-built creature bodies, local animation/culling, and occluded fly buzzes.
DialController.luau    Scroll wheel + draggable edge slider with config snap points; reconciles
                       to the server's clamped value when idle.
ToolController.luau    Keys 1-3 + TouchControls buttons; Decoy proposes horizontal aim and cues only
                       accepted use.
TouchControls.luau     The one cluster that owns every on-screen action button on touch: tools,
                       dynamite, the Signal Bell, MINE/STOP. Callers register an id, label and row;
                       placement, sizing and staying clear of Roblox's thumbstick and jump button
                       are this file's alone.
DynamiteController.luau
                      Dynamite's whole client surface: the throw key (5), the blast door's place/light
                      prompts, and the socket marker — a glowing yellow stick drawn ONLY for a player
                      who is carrying one, which is why it is client-built rather than in FloorBuilder.
                      Neon with no PointLight, so it is visible without lighting the cave.
MiningController.luau  Nearest visible-deposit selection, pending-input/session coordination,
                       movement release, and private/shared result routing. Decides nothing.
MiningHUD.luau         Continuous fracture rail, row-aware prompt, hint/result motion, the
                       count-only carried Raw Wax readout, and the touch/desktop placement of all
                       three (a phone viewport is a quarter the authored height).
MiningViewmodelController.luau
                      Cosmetic seam-directed first-person pickaxe: draw/stow, anticipation,
                      outcome-specific contact/rebound/recovery, aim bias, and trail.
MiningWorldPresentation.luau
                      Wear-coupled seam glow, spatial contact/grade/break layers, chips, and
                      shared/private break-presentation deduplication.
HotbarController.luau  Responsive legend, free charges, active Cup/Flare labels, and reconciled cooldown bars.
HintController.luau    Fading first-three-floor threat and environmental teaching hints.
WaxBar.luau            Melt-line bar + lost-ceiling marker; dims when snuffed and pulses when low.
BasinPrompt.luau       Themed offer panel (UITheme cards, tap or number keys); server rolls/validates.
ResultsText.luau       All run text: countdown/floor/messages, live brazier arithmetic, results,
                       replay, and back-to-lobby controls.
LobbyController.luau   Gameplay-input/GUI toggling across the lobby<->expedition boundary and a
                       small non-modal status readout; tier-select/ready/start now live entirely
                       in the physical lobby (ElevatorService/ElevatorController), not here.
CursorController.luau  Keeps first-person mouse capture during play; releases it for every
                       interactive WICK screen and Roblox's native menu.
SettingsController.luau
                      Local Landing/active-run settings menu (M): mouse sensitivity and audio volume,
                      plus a Landing-only menu-music slider; never touches authoritative gameplay values.
RelightPromptController.luau
                      Hides a snuffed candle's impossible self-relight prompt locally; the
                      server-created prompt stays available to teammates.
SpectatorController.luau
                      A ghost's whole surface: draws the replicated teammate footfalls as fading
                      marks on the floor (world parts, so rock occludes them and nothing emits
                      light), the "following X" readout, the follow key, and a touch button for it.
                      Decides nothing — the server owns the cycle, the anchor, and the floor filter.
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
- **New noise emitter** → row in `Config/Sound.emitters` + one `NoiseService.emit` call at the site
  that already knows the event happened. Never a branch in a threat.
- **A threat gains ears** → one `hearing` block on its `Config/Threats` row. Keep it to
  dark-hunters: a Drawn row that hears would blur the light/dark category read.
- **New sacrifice** → row in `Config/Basin.pool` (new target = one handler in SacrificeRules).
- **New candle modifier** → id in `Types/Wax.CandleModifierId`, tuning row in
  `Config/CandleModifiers`, a branch in `Logic/CandleModifiers.applyPickup` (plus `profile`/`step` if
  it is continuous), a `Config/Loot` pickup row, and a silhouette in
  `NewModelsAndObjects/LootPickup`. A modifier that only stacks an existing effect is config-only.
- **New room module** → row in `Config/Floors.roomModules`.
- **New abandoned working** → a builder in `NewModelsAndObjects/MineRelics` keyed by id, plus a row in
  `Config/MineRelics.catalog`. `Tests/MineRelicRulesTests` fails if either exists without the other.
  Build it with its ground contact at the origin and, for a `Wall` piece, everything it leans on at
  +Z; declare `footprintRadius` and `wallOffset` to cover what the geometry actually reaches.
- **Restyling a floor fixture for a family** → the `presentation.fixtureStyle` block on that
  `Config/CaveFamilies` row (a rig plus four colour/material pairs). Never a branch on a family id in
  a builder or a service: `Logic/CaveFamilyRules.fixtureStyle` is the only way to ask.
  `Tests/CaveFamilyRulesTests` holds every fixture colour under the same darkness bound the rock has
  and refuses two families sharing a rig.
- **Retuning a floor fixture** → `Config/Cauldron`, `Config/Lantern` or `Config/DescentLadder`. The
  ladder's `rideDistance`/`shaftDepth` are ceilings, not guarantees: `FloorBuilder` clamps both to
  what fits above the cave below, so neither can ever cut into the next floor's roof.
- **Tuning dynamite** → `Config/Dynamite`. Note that four of its values are DESIGN surface rather than
  tuning, because they are what bound the no-combat exception (DESIGN §6a): `supply` (how often the
  cave hands one over), `supply.maxCarried`, `blast.playerWaxCost`, and `blast.alertRadius`.
- **A creature's dynamite lethality** → a `blast` block on its `Config/Threats` row, in "sticks at
  point blank". Omitting it takes `Config/Dynamite.threat.default`, which is deliberately KILLABLE:
  a new row that was silently immune would be a bug nobody could see in play.
- **New unstable-dripstone silhouette** → variant row in
  `Config/Hazards.unstableDripstone.variants`; preserve the shared fractured-collar/lean/dust tell
  and the generic DripstoneRules/Service lifecycle.
- **Persistent profile change** → update the type/default/save path in
  `Interfaces/Persistence`, then the focused consumer; never add raw DataStore calls.
- **Deferred system goes real** → preserve its focused `shared/Interfaces/` boundary and add
  Instance/UI adapters only where needed. Currently this applies to Lineage; global remains are
  a backend replacement, not a second gameplay API.

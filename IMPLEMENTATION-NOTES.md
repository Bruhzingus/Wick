# IMPLEMENTATION NOTES — Phase 0–5 prototype

What was built, where it deviates from the letter of the spec, what was underspecified, and
where the shortcuts are. Companion to `STRUCTURE.md` (layout) and `TUNING.md` (numbers).

## What was built

Every system in the spec, wired together: server-authoritative wax on a fixed tick · shrinking
candle rig with authoritative height · first-person camera with visible body · continuous
brightness dial (scroll + slider, server-clamped) · wax-bar HUD plus a control/charge hotbar ·
client-only low-wax, water, threat, and flame feedback · run/hop
with measured-speed drain · all three tools as light-field edits · one generic threat system with
two categories, eight depth-weighted rows, a Snuffer, and territorial VoidFly · config-planned wax/charge loot ·
session-local recoverable remains · water (real
height comparison, shrink interaction emergent) · rare server-authoritative one-shot unstable
dripstone with a warned fall, variant-scaled wax impact, and low-wax snuff · non-glowing wax-drop trail
(navigation + hunter breadcrumbs only) · both death states, relight paid by the reviver, and a
spectating ghost candle after a terminal one (translucent body, follows a teammate, almost no light,
sees only its teammates' footfalls) · procedural floors from weighted modules with paired rocky floor/roof Terrain fields ·
private Basin with depth-worsening exchange · brazier with live arithmetic
preview and group/tier multipliers · full run loop with result-screen restart · deterministic
pure-rule tests · request throttling, finite-payload checks, movement sanity correction, and
structured server-log telemetry · ProfileStore-backed currency/progression · three cave tiers ·
one-party ready/leader lobby with a Studio-local or live reserved-server expedition handoff.
Replaceable backend access routes through `shared/Interfaces`; Lineage is the only remaining stub.

## Deviations from the letter of the spec (all deliberate, all reversible)

1. **`ToolDef.effect` (per-category ± table) was replaced with physical light params.** The
   opposite-reaction rule is still pure data — tools edit the light field (Config/Tools), and
   the categories react in opposite directions via the sign of `lightResponse` (Config/Threats).
   This is *more* data-driven (zero per-tool branches anywhere), but if you want the signed
   table back as documentation, it's a Types+Config change only.
2. **Snuffer moved out of Hazards.** A snuffer is an enemy, so the threat system uses the generic
   `contactEffect: "Drain" | "Snuff"` field. The Snuffer now ships as a rare, depth-weighted
   Drawn row; its contact causes the normal revivable snuffed state.
3. **Water kill = terminal snuff.** "Instant and absolute": flame-height contact goes straight
   to the ghost candle (`deathCause = "Snuffed"`), no rescue window. The revivable snuffed state is
   reachable via Snuffer-type threats.
5. **There is no voluntary snuff.** Players have no action that puts their own flame out; CUP
   covers the light the flame throws instead, so going dark is a held state with upkeep rather than
   an extinguish that needs relighting. Every snuffed state is therefore world-inflicted.
6. **`modelHeight` moved** from Config/Hazards to Config/Character (it's body geometry consumed
   by both the visual and the water rule). No value is duplicated.
7. **Loot charges are activations, not a second inventory.** `freeToolCharges` lives in run state,
   is granted by LootRules, and is consumed inside ToolService before wax. It never bypasses
   cooldowns, lighting requirements, death state, or Basin tool sacrifices.
8. **`FloorDef` replaced by `FloorPlan`** (the planner's richer output). Nothing consumed FloorDef.
9. **The Phase 5 hub is a same-place prototype lobby.** Every player in a public server
   auto-joins one capped party. The leader chooses the tier, everyone readies, and a live server
   reserves another copy of the same place. There is no invite code, party browser, multi-party
   hub, matchmaking queue, or rejoin recovery yet.

## Underspecified, resolved by judgment (flagged in code comments too)

- **Basin room placement**: attached beyond the brazier room; holds the descent pad. Safe (no
  threats/hazards spawn there).
- **Descent**: per-player, walking into the pad. The party can split across floors.
- **"Double the next price"**: implemented as the next Basin grant halved (divisor 2), consumed
  by the next exchange, not stacking.
- **Movement drain while snuffed/unlit**: none — melting is the flame's doing. Water degrades
  regardless of lit state.
- **Snuffed players remain valid dark-hunter prey** (they are maximally dark). Brutal; tunable
  only by threat numbers; flag if it plays badly.
- **The run candle has a low terrain-recovery hop** (`Movement.hopPower`), not a full athletic
  jump; there is no fall damage of any kind.
- **Cup upkeep** (`Cup.waxCost`) is charged per second held, in the drain pipeline — so it CAN
  contribute to burning out, unlike activation costs which use strict `>` and never kill.

## Playtest round 1 changes (2026-07-23)

- **Camera**: eye now sits `Character.cameraLift` above the body top, and the local player's
  Flame and Wick are hidden client-side (they sat at the eye and filled the screen). Body and
  rim stay visible — looking down still shows the shrink. Other players see the full candle.
- **Self-shadows off**: every candle rig part has `CastShadow = false` — kills the giant radial
  self-shadow and its jagged tessellation artifacts.
- **Stable candle shadows**: the server publishes candle-light targets as tagged attachment
  attributes. Each client eases those targets locally and gives only its own candle one spherical
  shadowed PointLight over a dominant omnidirectional fill. The two layers share the full candle
  range and never rotate with the camera, removing the old cone and 30-stud visibility boundaries;
  teammate lights remain smooth fill only.
- **Torch-quality local rendering**: the local shadow emitter follows an invisible client-only
  carrier with a short stabilizing response, exact idle settle, and teleport snap. Only 35% of
  output participates in the engine shadow map, so terrain/caster LOD cannot make rock disappear;
  a short amber layer, restrained bloom, and warm grading retain surface depth.
- **Natural combustion flicker**: `CandleLightController` is the only candle-light renderer. After
  easing each server-published target, it samples an owner-seeded, synchronized-time blend on a
  seamless bounded-coordinate loop: slow drift, body flutter, fine turbulence, and rare
  guttering. The same brightness/warmth
  result drives that candle's fill, shadow accent, and bounce, so it reads as one flame instead of
  competing lights. Full-screen bloom/grading follows the stable eased target to avoid a camera
  exposure strobe. PointLight range, enable threshold, and carrier position stay stable; the
  server's gameplay light, wax drain, and threat perception never flicker. Teammates' baseline
  signal is deterministic across clients, while `FeelController` only forwards local threat
  context that can make the owning candle look less stable.
- **Caster budget**: Terrain, structural room walls/ceilings, and collidable boulders cast torch
  shadows. High-count collision-neutral wall rocks, cave-mouth details, ceiling straws, and hanging
  formations receive light but do not cast; this prevents doorway transitions from admitting
  hundreds of tiny casters at once. Workspace streaming is explicitly disabled.
- **30% larger candle capacity**: authoritative starting/max wax is 1.3 units. Geometry, HUD fill,
  low-wax warnings, ceiling loss, and remains percentages normalize against that base capacity, so
  endurance rises without stretching the candle or overfilling UI.
- **Stumpy candle**: heights 4/0.8, radius 1.4, plus melted rim + dark wick + elongated flame.
  Water modules now cut localized recessed 0.45/1.2/2.0-depth pools; the surrounding Terrain uses a
  smooth `smoothstep` bowl falloff with dry rock at the rim rather than a vertical wall, so exit is
  always possible by walking up the slope (no separate rim-rock props or stepped geometry are
  built — this reads as gradual rocky shore, not a modeled "escape step"). FloorPlanner guarantees
  one dry entry-to-Basin route.
- **Threat models**: the server replicates one invisible anchored proxy per threat while each
  client builds and animates the detailed DarkCrawler, CaveMoth, or CeilingFly locally. Local bodies
  have collision/query/touch disabled and leave Workspace past the configured 120-stud cull range.
  ThreatBrain, contact, snuffing, and every wax change remain server-owned. The primitive
  silhouettes remain behind `Threats.visuals.procedural.enabled = false` as a Studio fallback.
  Name labels remain gated by `Feel.debug.showThreatLabels` and default off.
- **Crawler light response**: non-ambush dark hunters attack candles below the hunt threshold and
  hold an 11-stud gap in the ordinary-light band. Only Flare can force retreat; after estimated
  straight-line travel they remain blind for two additional seconds even though the burst is gone.
- **VoidFly audio**: clients schedule quiet spatial buzzes 9–20 seconds apart while a fly is
  within 32 studs. A cave-geometry raycast suppresses the cue through walls but ends just before
  the roof-mounted proxy so its own anchor surface cannot self-occlude it. The shared audio cooldown
  prevents nearby flies from becoming a constant chorus.
- **VoidFly roof contract**: its deterministic planned XZ and full territory are reserved from harmless cave dressing.
  The server carries FloorBuilder's exact paired ground/roof fields into ThreatService, samples the
  current irregular underside throughout patrol and retreat, and holds the visual root 1.5 studs
  below it. Ceiling ambushers are capped at 30-stud nominal rooms so the tell remains inspectable
  and audible. Dive/return height is speed-limited separately from ground-plane AI, contact cannot
  count until the dive reaches attack height, and broken contact resets the four-hit sequence.
- **Early-floor teaching hints**: floors one through three show small fading bottom-screen guidance
  after server-confirmed threat contact or a replicated transition into water exposure.
  Per-message and global cooldowns keep multiplayer contact and recurring drains from spamming UI.
- **VoidFly frequency**: its per-depth selection weights are 1.6 times the previous values. This
  preserves the existing depth curve and floor-one exclusion while making eligible fly selections
  60% more likely relative to an unchanged threat pool.
- **Cave terrain**: cell 64, 6–12 authored rooms per floor, Slate materials, taller varied ceilings, wall
  relief, planned ramped ground shelves, CaveKit multi-facet boulders/spires/ceiling straws, and
  deep wedge-built rock throats. Formation counts are lower than the old single-shard dressing
  because each procedural formation owns several visual facets plus a focused collider.
  Doorway openings roll 8–56 studs wide and 8–13 studs high from a shared-edge seed, making
  adjacent wall openings agree. Rooms attempt seven broad, slightly overlapping ramped shelves;
  only special-room centers, doorway lanes, and recessed water footprints remain level/low.
  Sparse CaveKit boulders supplement the terrain instead of faking variance with scatter. Ground
  placements and recessed pools are pure FloorPlan data because their collision changes traversal;
  roof, rim, and wall details remain cosmetic.
- **Structured roofs**: the old flat ceiling slab is replaced by a sealed inverted Terrain height
  field written in the same voxel pass as the floor. `GroundGeometry` and `RoofGeometry` give the
  planner and builder the same deterministic floor/underside samples. Broad waves plus smaller
  ripples fade into walls/door arches, and the underside stays at least 8.5 studs over local ground.
  Harmless hanging dressing is length-clamped against that exact gap; unstable placement separately
  requires enough room for its full silhouette plus a 4.5-stud fall.
- **Unstable dripstone**: `FloorPlanner` creates a separate environmental plan, not a threat row.
  Only ordinary rooms with nominal ceilings at or below 34 studs qualify; entry, Basin, Brazier,
  VoidFly, and Snuffer rooms are excluded. Desired F1–10 counts are 1/2/2/4/5/7/8/10/12/15 before
  doorway, spacing, harmless-majority, ≤50%-dangerous-room, and per-room caps. Needle, Fork, and
  Hammer share the permanent fractured-collar/lean/dust tell and one server lifecycle. A fixed
  footprint commits a 1.65/1.8/2-second warning, then an anchored analytic vertical fall. Impact
  removes 20%/35%/50% of maximum wax; a candle already below 30% is snuffed. If the candle
  survives, the same 42%-for-two-seconds light multiplier applies to rendering and threat
  perception. On Floors 1–3, each player's first nearby fall also sends the bottom-screen avoidance
  hint, even when they escape the impact.
  Clients reconstruct motion from
  replicated state/timestamps and render only dust, debris, spatial sound, shake, grading, and
  flicker; all players in the shared impact disc are selected server-side. Placement uses the real
  off-centre doorway profile and reserves at least 4.5 studs of unobstructed drop plus a
  radius-aware escape lane. The final pose uses generated model bounds, avoiding floating forked
  variants while retaining a shallow Terrain embed.
- **Lobby/input lifecycle**: movement/tool ContextActionService bindings and touch buttons exist
  only during an expedition. Basin choices dismiss on floor/run/lobby/death transitions. Dial
  dragging coalesces server requests to 0.15-second intervals and always sends the release value.
- **Music lifecycle**: `MusicController` fades the looping menu cue on expedition transitions.
  Underground it waits 18–42 seconds before the first track, draws from a shuffled four-track bag
  without immediate repeats, leaves 10–24 seconds of silence between tracks, and fades every track
  in/out. Music and effects share the local `WickMaster` volume group.

## Physical lobby and elevator descent (2026-07-25)

- **The lobby is now a real place, "The Landing."** Previously the lobby was a 2D `ScreenGui` over
  an empty Workspace and the player had no character at all until floor 1 was built. It is now a
  small, fixed mineshaft hub (`server/LobbyRoomBuilder.luau`, built once at boot, not seeded or
  rebuilt per run) with a spawn point, a placeholder shop stall, three elevator alcoves (one per
  cave tier), and informational signage. Every connecting player gets their normal Roblox avatar
  there (`CharacterService.spawnLobby`). Once the leader commits an elevator, each captured rider
  is replaced with a full, lit cosmetic candle (`CharacterService.spawnRideCandle`). Ride candles
  are tracked separately from run rigs, so `WaxService`, threats, hazards, and movement correction
  never see them: they are a presentation-only bridge into the real expedition candle.
- **Elevators fully replace the old 2D tier-select/ready/start panel.** Standing in an elevator's
  zone counts as readiness for that tier (`server/ElevatorService.luau`); the leader's chosen
  elevator sets the party's tier (`Interfaces.Party.setTier`, unchanged); a leader-only lever
  starts the expedition through the exact same validated path the old UI used, now exported as
  `PartyLobbyService.tryStart`/`canStart` so nothing duplicates the leader/ready/unlock checks.
  `client/LobbyController.luau` shrank to gameplay-input/GUI toggling across the
  lobby↔expedition boundary plus a small non-modal status readout for server-broadcast messages.
- **The elevator ride stands in for the old flat countdown, using the same timer.**
  `server/ElevatorService.luau` captures the riders, closes the gate, swaps them to ride candles,
  and broadcasts one `RunEvent("elevatorRide", ...)` payload containing the server timestamp,
  duration, distance, and resting car transform. `client/ElevatorController.luau` evaluates the
  same smooth curve every render frame for the tagged car and its ride candles; the server applies
  only the final authoritative transform. This avoids visible replication steps while keeping the
  server in charge of who rides and when the expedition starts. Shaft ribs are four perimeter
  beams at each interval, never solid cross-shaft plates: no scenery intersects the car or passes
  upward through a rider's head. The remaining mechanical tremor is horizontal-only.
- **The floor-1 candle is a clean respawn, not a reused Instance.** `CharacterService.spawn`
  internally clears the cosmetic ride candle first, so `RunOrchestrator.spawnRunner` needed no
  special-casing. The ride candle is full-height and uses the normal candle camera marker, making
  the player first-person as soon as descent begins without starting wax drain early.
- **First-person mouse capture is now the default everywhere a character exists**, not just during
  an expedition. `CursorController` no longer auto-frees the cursor whenever
  `WickInExpedition` is false — a released cursor is always an explicit named claim (Basin,
  Settings, results, the native Roblox menu), matching how those screens already worked.
- **Shop is a placeholder.** One stall + a `ProximityPrompt` that replies "The shop is still being
  stocked" via the existing `RunEvent("message", ...)` channel. No purchase logic and no new
  persistence fields — `Profile.cosmetics`/currency-spending remain a follow-up design, tracked in
  `IMPLEMENTATION-ROADMAP.md`.
- **Adding a cave tier now also means adding an elevator.** `Config.LobbyRoom.elevators` is a
  manually maintained row per `Config.CaveTiers` entry; a tier without a matching elevator row has
  no way to be selected in the physical lobby.

## Known shortcuts and trust boundaries

- **Character physics is client-owned** (standard Roblox humanoid networking). The server
  measures speed/position and `MovementSanityService` keeps a one-second trusted anchor. It allows
  sustained run speed with configured slack/jitter, then corrects excess displacement. This is
  prototype mitigation, not a production anti-cheat:
  it does not prove every replicated path is legitimate and may need tuning under real latency.
- **Threat navigation is a lightweight floor graph, not PathfindingService.** Every threat row
  follows reciprocal doorway-centre waypoints from `RoomNavigation`; semantic targets are clamped
  inside rooms and diverted around localized pools. Basin sources/players/trails/contact are
  excluded with a final fail-closed step guard. ThreatService raycasts onto the real ground
  contour and chooses a temporary sidestep when solid cave geometry blocks its line.
- **All floors are physically live at once** (stacked 80 studs apart). Threat budgets are small;
  no culling. Fine at slice scale.
- **VoidFly uses reusable threat profiles**, not an ID branch: `ambush` confines it to a home
  territory and handles group/Flare retreat; `contactAttack` stages four low-damage strikes.
  A live Flare forces an immediate rethink and clears that staged sequence without damaging it.
- **Loot uses diegetic pickup art.** FloorPlanner deterministically places wax caches and prepared
  Flare/Decoy props in doorway-safe peripheral wall pockets. LootService samples the same
  GroundGeometry field used to build Terrain, so models sit above wall berms and ground swells
  instead of raycasting into roofs or decorations. Prompts and effects remain server-owned.
- **Remains are session-local only.** Terminal deaths deposit recoverable wax for later runs in
  the same server. Pools are remapped into safe rooms, attract the Drawn through LightSources,
  cannot be reclaimed by their owner, and disappear when the server closes. A collector takes
  only the wax their candle can hold; overflow stays in the pool for a later claim.
- **Lit braziers don't join the light field** (visual glow only). Trivial to add in
  LightSources if the party using ignited braziers as safe light is wanted.
- **Persistence uses ProfileStore.** Live published servers load session-locked
  `WickProfiles_v1` profiles; Studio always uses `ProfileStore.Mock`, so local play cannot touch
  production keys and Studio currency is intentionally ephemeral. The current schema stores
  currency, unlocked tier, cosmetics, run count, deepest floor, and total delivered wax.
- **Cave progression is intentionally small.** Currency unlocks Shallows/Descent/Deep thresholds;
  the selected tier controls maximum floors, threat budget, and reward multiplier. There is no
  purchase screen or broader economy yet.
- **The public lobby is one party per server.** It is enough for a friend prototype if both
  players join the same public server. It is not matchmaking, and a full party rejects later
  joiners instead of routing them elsewhere.
- **Reserved arrival synchronization is bounded.** Teleport data carries the expected member
  IDs. The expedition shows a waiting lobby until all expected profiles join or eight seconds
  elapse, then starts the normal countdown. A slower late arrival can still enter the active run;
  this is not disconnect/rejoin recovery.
- **Live teleport cannot be exercised in Studio.** Studio uses the local-start branch. The
  reserved-server path must be checked after publishing, using two real Roblox clients/accounts.
- **Security telemetry is log-only.** `[WICK]` events appear in server Output/logs; no analytics
  dashboard, retention pipeline, or alerting is connected.
- **Music uses uploaded project tracks.** `Config/Audio.luau` maps the looping menu cue and four
  non-looping cave tracks to Roblox asset IDs. `MusicController` reports load or permission
  failures as `[WICK AUDIO]` warnings; `AudioCues` now does the same during one-shot preload and
  suppresses known-unavailable assets for that client. Unassigned cue IDs remain safe no-ops.
- **Audio has one bounded mix graph.** `AudioCues` constructs Master → Music/Ambience/World/Focus/UI,
  preloads unique assets, applies narrow gain/pitch variation, scopes spatial cooldowns per emitter,
  uses bus priority when the global voice cap must steal, filters obstructed one-shots, and keeps
  cave EQ/reverb behind Focus-driven ducking.
- **The audio system is production-oriented; the source library is not production-final.** Mining
  and the five cave families are audible, but each cue currently has one licensed source plus
  restrained pitch/gain variation, and several files are reused between cave and mining events.
  Sixteen wider-loop cues (dial, low wax, water, threat proximity, tools, sprint, Basin, Brazier,
  deaths, relight, and floor entry) still have empty IDs and intentionally no-op. Dedicated
  multi-take recording, upload/permission approval, loudness normalization, and device audition are
  required before calling the game's audio asset-complete or mastered.
- **Harmless cave punctuation has one per-client director.** Rockfall, drip, strata strain, fissure breath,
  calcite ticks, hidden water, and gravel creep share one exponential clock, refractory period,
  silent outcome, anti-repeat history, and critical-audio quiet gate. Failed geometry probes become
  silence; stone/gravel ignore Terrain water while hidden water may anchor there. None falls back to
  a fake source at the player or emits a hunter-heard NoiseService event.
  This is a subjective cosmetic soundscape, not a replicated geological event: nearby co-op clients
  are not guaranteed to receive the same family, position, or time.
- **Sprint feedback communicates candle strain, not extra authority.** The server still owns speed,
  measured Run drain, teammate-visible flame lean, and denser physical wax drops.
  `SprintFeedbackController` only renders a restrained 74→85 FOV blend, peripheral
  vignette/shimmer/streaks, and slight post-camera instability after replicated WalkSpeed confirms
  that sprinting was accepted.

## Automated pure-rule tests

`src/shared/Tests/` contains a dependency-free harness and config-derived suites for the pure
gameplay rules. The current registry covers the config and rule contracts, including Audio,
WaxDrain/Accounting/Pacing, BrightnessMap, FlameFlicker, LightField, SoundField, ThreatBrain,
RoomNavigation, Hazard/Dripstone rules, sacrifice/reward/cargo/extraction rules, FloorPlanner,
CandleGeometry, Tool/Cooldown/Loot rules, TokenBucket, Lamp/Vine rules, AshamedLurkerRules, and
MiningRules. Dripstone
generation tests also exercise the shared GroundGeometry and RoofGeometry fields where planning
depends on exact local clearance. The tests focus on contracts and invariants, so ordinary tuning
changes do not require rewriting expected constants.

`src/server/StudioTestRunner.server.luau` runs the registry once whenever a Studio server starts.
It does nothing in a published server. Look in Studio's Output window for
`[WICK TESTS] PASS: <N> deterministic tests`; a failure is emitted as one red error containing
every failed suite/case, while the normal game boot continues for manual testing.

The command-line toolchain can parse, lint, format-check, and Rojo-build these files, but it has
no Roblox runtime executable. A Studio Play or Start Server session is therefore the execution
gate before publishing.

## Mining interaction and extraction loop

Mining asks one question: **is this optional detour worth the light, noise, immobility, and time?**
Raw Wax is extraction income and never converts into living Wax; the pickaxe remains contextual and
cannot affect threats. Standard, Twin, Deep, and Bright rows vary duration, yield, helper payout,
and burn requirement while sharing one authoritative interaction.

**The interaction.** Standing within 6.5 studs of a seam raises a contextual first-person pickaxe.
Clicking (left click / an on-screen MINE button / right trigger — one `ContextActionService` action,
so every platform behaves identically) **engages** the seam: the player is planted, the pick comes up
over the shoulder, and a marker begins sweeping one continuous fracture rail. Every subsequent click
is a **strike**. Strike → the pick falls and recovers → the aperture has moved → read it again. The
row decides how many clean strikes break the deposit; missing still chips it, but more slowly and
with a louder server-owned noise event.

**The stance is a lock, and the lock always shows its exit.** `movementSpeedMultiplier` is 0 while
engaged, so mining and repositioning are mutually exclusive. The way out is any movement key: the
client polls W/A/S/D/Space (polls, rather than binds, so mining never steals a key from
`MovementController`) and disengages on the frame one is pressed, with right click / B as an explicit
alternative and a STOP button on touch. The on-screen prompt switches to "move to stop" for the whole
stance — a locked state that does not advertise its exit is a trap.

**Why the band moves.** A continuously sweeping rail with a fixed target would be a metronome you
could hit blind. `MiningRules.bandCenter(depositId, strikeIndex)` re-derives the target's position
for every strike from an integer hash — pure, deterministic, identical on server and client — so each
strike is a fresh read rather than a learned tempo.

**Fair timing without client-owned outcomes.** The client never sends a phase, accuracy, or progress.
It sends the shared `Workspace:GetServerTimeNow()` sample taken at the click. The server converts
that sample into its private monotonic clock only through `MiningRules.resolveInputClock`: reports
outside the 220 ms rewind / 40 ms future bounds fall back to packet arrival. Validation, cooldown,
progress, depletion, noise, and the next sweep remain arrival-authoritative. The down-stroke starts
locally on input so the tool never waits for a round trip; it changes no number.

**Two validation passes, not one.** `canBeginStrike` runs when the stance opens; `canResolveStrike`
runs again on every strike and every tick the stance is held, because the world moves while somebody
stands at a rock. Server line-of-sight is checked alongside range, light, Cup, burn gate, life, and
floor. Being obstructed, pushed away, dimmed below a Bright Seam's gate, snuffed, descending, or
another player breaking the same seam all end the stance instead of paying it out. Depletion is
guarded by a flag rather than by progress, so two players striking on the same frame cannot both be
credited. A Twin helper is revalidated at the break frame before the depleted flag flips, so a stale
session that just moved, died, cupped, dimmed, or lost sight cannot receive the helper grant.

**Feedback.** Swing/effort, stone body, grade transient or scrape, debris, and recovery are separate
layers routed through the Focus bus. Variation is narrow enough to preserve material identity;
Perfect rises only four percent across a clean sequence. Accepted contact is broadcast through
`RunEvent("mineImpact")`, so nearby teammates hear the same spatial seam and see the same chips the
cave AI heard. A final hit resolves as break/debris rather than stacking every ordinary grade cue.

**The rail answers every hit with one hierarchy.** The continuous Good aperture carries a brighter
Perfect core, one marker, one short contact trace, and replacing result text. There is no segmented
disc, radial burst, combo typography, or full-screen circle. A miss receives only a three-pixel
decaying jolt; a break receives one restrained line while the world fracture and audio carry weight.
Entrance/exit use 160/130 ms opacity/scale motion with no Back overshoot.

**Client presentation has explicit ownership.** `MiningController` coordinates target, input latches,
and authoritative remote state; `MiningHUD` owns the rail/prompt/cargo surface;
`MiningViewmodelController` owns the cosmetic pickaxe and target-aligned motion; and
`MiningWorldPresentation` owns seam glow, spatial material layers, debris, and shared/private break
deduplication. None of the three presentation modules can send a mining request or choose an outcome.

**Exposure is the price.** Mining costs no wax. It costs time standing genuinely still, with an
uncovered flame (a cupped or unlit candle is refused outright), making noise — see below.

**Where a deposit sits.** `server/SurfaceProbe` resolves the analytic ground field against the built
Terrain and seats the model by its visible bounding box, sinking it `visual.surfaceEmbed` into the
floor. Both halves matter: the probe stops a rock resting on an overhang or floating over a voxel
gap, and the bounding-box seat is what stopped deposits burying themselves — a deposit's root is the
boulder's *centre*, so pivoting it straight onto the ground put half the rock underground and left
only a few flecks of wax showing through the floor. `LootService` uses the identical path.

**The seam's ember.** Wax reads amber rather than candle-cream, and each seam carries client-only
Neon shells that fade up as you approach (`visual.glow`). It is presentation only — no PointLight, no
change to what any threat can perceive — and it stays mostly transparent even at the rock. Server
progress now wears seams after every strike, and the local ember multiplies by that remaining wear
instead of leaving spent wax glowing.

## Raw Wax extraction economy

Breaking a deposit grants the row's integer unit count, stamped with the GLOBAL depth it came from,
to `PlayerRunState.rawWax`. `server/ExtractionService` is the sole mutation/payout authority;
`Logic/CargoRules` owns pure cargo shape and `Logic/ExtractionValue` prices an extracted bag.

**What it cannot do.** Refill a candle, be consumed, or otherwise alter survival. Living Wax remains
the survival meter; Raw Wax is carried income. Cargo has a count readout, no bar or drain, and never
converts back into living Wax.

**Ownership and loss.** Cargo is individual, and a snuff/revive leaves it untouched. Terminal death
drops half on the candle remains and destroys half. A disconnect moves the bag into one owner-locked
pile for 120 seconds before the party may claim it; the bag never exists in both state and world at
once. `ExtractionService` owns those transfers and the reconciliation ledger.

**Why it cannot be duplicated.** A deposit can be broken once, and `ExtractionService.grantForDeposit`
latches its stable per-run id. Extraction is independently latched by `rawWax.extracted` plus the
persistence transaction id, so a duplicated brazier commit pays nothing twice.

**What it measures.** One `raw_wax_run` telemetry line per player per run: deposits reachable on
floors they stood on, deposits started, deposits abandoned, deposits completed, units acquired /
lost / extracted / still carried, the origin-depth distribution and its weighted mean, extraction
depth, Living Wax remaining, and a reconciliation error that is non-zero only if units appeared or
vanished outside `CargoRules`. Server log telemetry remains the detailed balance record.

## The sound field (Phase 6)

The cave gained a **second perception field** alongside light. It follows the same shape: pure rules
in `Logic/SoundField`, one server registry (`NoiseService`) that emitters call, and one optional
`hearing` block per threat row. There is no `if mining` branch anywhere in threat code.

- **Only dark-hunters listen.** Lurker, Stalker, and Hollow have ears; every Drawn row and the
  territorial VoidFly are deaf. This is load-bearing: if the Drawn could hear, a noisy action would
  pull both families at once and the light-vs-dark read the whole threat design rests on would blur.
- **Loudness sums and decays.** Distance falloff × time decay, added across events. A single clean
  strike sits under a Lurker's curiosity threshold at every distance; two or three overlapping ones
  do not. "Repeated hits lure them" is not special-cased — it is what adding decaying events does.
- **Fumbling is louder.** A missed swing emits a louder, wider, longer-lived event than a clean one,
  so hitting the timing window is the player's only lever on how exposed mining makes them. Skill
  buys safety directly.
- **Hearing is curiosity, never acquisition.** A roused hunter enters `Investigate` and walks — at a
  fraction of its speed — to the loudness-weighted centre of what it heard. It never learns where
  the player *is*, never speeds up, and gives up on its own. Any real prey read interrupts and
  clears the memory. Investigate ranks below every prey read and above the cold drip trail.
- **Existing loud events are wired too:** sprinting (throttled, and quiet enough that one footfall
  never crosses a threshold alone), dripstone impacts, and vine curtains catching fire. These are
  the noise floor mining stands out against.

Noise inside the Basin is filtered exactly like its light and its drips: it does not exist outside.

**Known open question for playtesting:** the Stone Warden does *not* listen. Waking it on repeated
or close strikes was considered and deliberately left out of this phase; it remains a relic-touch
threat. Adding it later is one `hearing`-style check against `NoiseService` in its behaviour script.

Spawn reliability is now observable rather than inferred. Every constructed floor emits one
`[WICK] floor_spawn_audit` line with planned/built threat, loot, Lurker, and Warden counts. A mismatch
means runtime construction rejected planned data and should be treated as a bug. Warden floors add
an optional weathered chamber with protected pile/relic/counter pads; ordinary collidable dressing
respects threat and loot footprints, and Lurker arches omit the random throat-rock clusters that
could cover the client-built creature.

## Manual test script (gameplay verification is on you)

Setup: run `wally install`, then `rojo build -o Wick.rbxlx`; open the place and run `rojo serve`
for live source sync. For two-player tests use Studio's Test tab → Clients and Servers → 2
players. Studio deliberately bypasses teleport and starts the expedition locally.

**A. Core loop (solo, 5 min)**
1. Play. Confirm Output first reports `[WICK TESTS] PASS: <N> deterministic tests`. You spawn as
   your normal Roblox avatar in the physical lobby ("The Landing"). Walk into the Shallows
   elevator (readies you for that tier), then pull its lever (visible once ready and the tier is
   unlocked). Confirm you immediately become a lit candle in first person, and that the car and
   candle descend together in one continuous motion without visible steps. After the ride you
   spawn in a dark room. Look down — you see your own cylinder body.
2. Confirm the bottom control legend shows 1–4 tools plus Shift Sprint
   plus `WHEEL / RIGHT SLIDER = BRIGHTNESS` (a compact keyless legend and the actual action
   buttons appear on touch). Use every cooldown action: its chip shows a shrinking amber bar and
   upward-rounded tenths-of-a-second pill; Shift has no bar. On touch, confirm the same fill,
   timer, and `RELIGHT` / active-marker title are mirrored onto the native action button. Scroll the
   wheel / drag the right-edge slider: light radius visibly grows and shrinks; the left wax bar
   drains faster at high dial. Snap points flash at the configured .3/.5/.7 burn landmarks.
3. Hold Shift and run: bar drains faster than standing. Space/mobile Jump performs only a low hop;
   confirm it clears a small crack or terrain seam without resembling a normal avatar jump.
   Reject DECOY against an illegal surface and confirm it reads `AIM AT OPEN GROUND`.
4. Walk around: small dull wax drops appear behind you and fade on a timer. Confirm they emit no
   light and do not pull a moth toward the trail by themselves.
5. Stand still at ~40% dial for a minute: the body visibly shortens as wax falls.
   Below 25% the wax bar pulses orange; below 10% it pulses red. While standing and walking,
   confirm brightness and warmth continuously vary with an organic, non-looping rhythm and rare
   soft dips. The visible range edge must remain fixed, with no doorway/chunk pop or snapping;
   sprint and nearby danger may intensify the motion without changing wax drain or
   threat reactions.

**B. Threats (solo)**
6. Find a dark-hunter (black silhouette): sweep the ordinary dial from low to high — it may change
   from hunting to holding distance, but ordinary maximum light never forces a retreat. Contact
   drains wax fast (bar, not health).
7. Press 1 (FLARE) as it closes: it breaks off. The flash is brighter than the normal maximum and
   the 0.13-wax cost (10% of a full default candle) is visible on the bar. Its chip reads
   `● FLARING`; press again immediately to confirm there is no cooldown and another 0.13 wax is
   paid. After running away, the hunter must remain blind for the configured two-second window.
8. Find a Moth/Swarm: burn bright — it comes to you. Hold 3 (CUP): the screen goes near-black and
   it loses you, while the flame stays lit and the bar keeps paying upkeep. Press 3 again to uncover.
9. With a drawn chasing: aim at legal cave ground and press 2 (DECOY). A miniature lit candle rests
   on the real floor, stops before walls, and the drawn diverts to it until it burns out (~6s).
   Try a wall, steep face, and your own feet: an illegal landing flashes red without spending wax.

**C. Hazards (the important one)**
10. Compare Shallows, Flooded, and the rare deep Sump. Confirm one dry path always reaches the
    Basin, while optional deeper water changes from survivable to lethal as the candle shrinks.

**D. Basin, brazier, descent (solo)**
12. In the safe amber-floored room, hold the Basin prompt: three private offers with real wax
    numbers. Choose one (tap or 1/2/3). Bar rises; the loss is live (capped dial ceiling /
    no drips…). Re-prompting says the Basin is spent for this floor.
13. Stand at the brazier pedestal: bottom text shows the live formula
    (wax × depth × group × tier = total). Hold to commit: results text, reward paid, candle freezes.
14. Or step on the dark pad in the Basin room: you drop to Floor 2 ("Floor 2" flashes).
    Deeper floors have more threats and pay more.
15. Die or cash out: the result/death breakdown states why the run ended. Once every runner is
    resolved, choose Restart Run for an immediate replay or Back to Lobby to refresh currency,
    reveal newly unlocked caves, clear readiness, and choose a tier. If nobody chooses, the world
    automatically rebuilds after 60s.

**E. Two clients**
16. Both clients auto-join the same lobby party and spawn as normal avatars in the physical lobby.
    Confirm only the leader's chosen elevator sets the party's tier (the other client walking into
    a different elevator does nothing to the shared tier), changing the leader's elevator clears
    everyone's readiness, and the descend lever only appears usable once both are standing in the
    matching elevator and the tier is unlocked. Pull the lever and confirm both switch to lit ride
    candles, enter first person, and descend smoothly together before spawning into the same run.
    Each sees the other's candle height ≈ their wax. Trigger different actions simultaneously and confirm each
    client renders only its own cooldowns while both see the same decoy candle in the cave. Watch
    one idle candle on both clients: its baseline flicker pattern should agree, stay visually
    distinct from the other owner's seed, and never add a second shadowed party light.
17. Both stand at one brazier: preview shows group ×1.25 for each. One commits alone on a later
    run to compare. The other's run continues after A cashes out.
18. A burns out fully: A becomes a translucent ghost candle standing over its own remains, in first
    person, with the tool legend gone and a "GHOST · following B" readout in its place. A's results
    card offers WATCH THE PARTY while B is still down there; dismissing it returns mouse-look.
    Confirm on A's screen: cold footfall marks appear along the ground where B has walked, brighten
    at B's newest step, and fade out after ~45 s. Confirm on B's screen: no marks at all, ever — the
    trail is only ever sent to dead players. A can walk around, is stopped by cave walls, and cannot
    body-block B in a doorway (they pass through each other). A's own glow is small enough not to
    light a room and goes out after 2 min while A keeps moving.
19. With A ghosting, walk B a long way off or take B down a descent hole. A is pulled onto B's
    position (never into rock, never ahead of B), A's marks reset to the new floor's trail, and the
    readout follows. Press A's follow key (F) with two living teammates: it cycles B → C → free roam,
    and pressing it while lost takes A straight to the next candle. When every runner is resolved,
    A's results card comes back on its own with RESTART RUN and BACK TO LOBBY.
20. Threats ignore A completely: walk a ghost through a dark-hunter's territory and confirm no
    contact, no attraction, no retreat, no noise, and that A's glow never appears in a threat's
    light read (a ghost is not in the light field).

**F. Loot, depth scaling, and remains**
21. Pick up Beeswax/Tallow/Cold Wax. The message names the new profile; dial output and drain
    change immediately without increasing the wax meter.
22. Pick up a Prepared Flare or Prepared Decoy. The hotbar charge count rises. Use that tool:
    configured readiness/effect are normal, the charge disappears first, and wax is not charged
    for that use.
23. Compare early and deep floors. Lurker/Moth dominate shallow rolls; Hollow, Ash Moth, and the
    rare Snuffer become eligible deeper down. Snuffer contact extinguishes instead of draining.
24. Have A die terminally with wax remaining (for example, wait out a snuff), then end the run.
    On the next descent in the same server, find A's orange remains pool. A cannot claim it; B can
    recover up to their available capacity. If wax remains, the pool and light stay for another
    eligible claim; they disappear only when fully recovered.

**G. Progression and public handoff**
25. In Studio, confirm only The Shallows is initially unlocked and that profile values reset with
    the mock session. Do not use Studio results as evidence of live persistence.
26. After publishing, join the same public server with a friend, ready both players, and have the
    leader start. Confirm both clients complete the elevator ride, stay behind the custom loading
    screen until their destination bodies exist, and enter the expedition without a brief lobby
    respawn. Cash out and use Back to Lobby:
    currency and any newly affordable tier should appear immediately while the party stays
    together and readiness clears. Leave, rejoin, and also confirm that progress survives.
27. Confirm the selected tier changes its maximum depth and displayed reward multiplier. A member
    who has not unlocked the selected tier must prevent the party from starting.

**H. Unstable dripstone and roof (solo + two clients)**
28. In solo, inspect several low and medium-height ordinary rooms across seeded runs. Confirm the
    roof has broad continuous Terrain relief comparable to the floor, closes cleanly into every
    wall/door arch, and never leaves a flat ceiling slab, open seam, or passage below the minimum
    clearance. Harmless stalactites/ceiling details must touch the sampled underside rather than
    float at the old nominal plane.
29. On Floors 1–3, find the rare Needle/Fork/Hammer silhouettes. Confirm dangerous formations
    consistently combine an off-axis lean, dry dark fractured collar, and sparse dust while most
    ordinary dripstone remains harmless. There must be no glowing marker or UI warning. Entry,
    Basin, Brazier, roofs above 34 nominal studs, and rooms occupied by VoidFly/Snuffer must contain
    no unstable formation.
30. Walk into one fixed trigger, then leave the landing footprint during its 1.65–2-second
    wobble/fracture warning. Confirm it falls vertically at the original location, does not home,
    and misses. Repeat by rushing underneath and confirm the shorter reaction distance comes only
    from movement speed; changing brightness must not change the trigger footprint.
31. Take direct hits at known wax. Confirm Needle/Fork/Hammer remove 20%/35%/50% of maximum capacity,
    while a candle already below 30% is snuffed. On Floors 1–3, confirm the first nearby fall shows
    the bottom hint even on a miss; it explains the fractured collar, falling dust, and leaving the
    landing ground before release. The surviving
    flame flickers and outputs 42% light for two seconds, nearby threat perception follows that
    same reduction, and dust/debris, stone audio, brief shake, and darkening occur.
32. With two clients, have A trigger a formation while B approaches the landing area. Both clients
    must see the same warning/release timing and final spent formation. A and B are each damaged
    only if the server finds them in the shared impact disc. A client outside the 36-stud
    presentation radius receives no local impact debris/audio/shake, and brief darkening remains
    exclusive to a direct hit. Repeat after restart to confirm all formation state resets cleanly.

**Stone Warden spawn audit (solo, Floor 4+)**

- Temporarily set `Config/StoneWarden.spawnChancePerEligibleFloor` to `1`, reach Floor 4, and find
  the optional weathered chamber. Confirm the dormant pile, relic bowl, and Heavy Crown are all
  inside the playable room on level ground, with no ordinary threat, loot, pool, vine, deposit, or
  Lurker sharing it.
- Touch the relic. Confirm only players on that floor are considered, the Warden emerges without
  visible proxy/root blocks, walks rather than remaining anchored, and contact resolves through the
  normal WICK results flow. Lead it beneath the room's Crown and confirm it becomes unable to move
  or kill for the configured stun window.
- Inspect Output for `floor_spawn_audit`; planned and built counts must match on every generated
  floor. Restore the chance to `0.45` after the forced test.

**I. Ashamed Lurker (solo + two clients, Floor 4+)**

Roughly half of deep floors carry one, so re-roll seeds (or raise
`Config/AshamedLurker.chancePerEligibleDoorway` temporarily) until an arch has one. Nothing about it
is verifiable from the Studio Explorer alone: the server owns one invisible proxy part named
`AshamedLurker<n>`; the body only exists on clients, under `Workspace/WickLurkerBodies`.

33. Find an occupied arch on Floor 4 or deeper. Confirm it reads as a small starved humanoid clinging
    to ONE springer with a long arm across only its own half — not a rock pile, no glowing eyes —
    and that it is legible walking in from BOTH sides of the doorway. Confirm it never appears in the
    entry, Basin, or Brazier rooms, and never in an arch that also carries a vine curtain.
34. Walk (do not sprint) through the open half. It must not react, and the lane must be comfortably
    passable. Walk through the trapped half: still no reaction. Walking is always safe.
35. Sprint through the trapped half. Confirm the lunge, the joint-crack cue, and a 20%-of-max-wax
    loss on the bar with no Humanoid damage and no health bar anywhere. Confirm the scare lands:
    camera shake, the loud spatial cue, and a brief grade on the victim only.
36. Sprint through it again but veer into the open half during the wind-up. Confirm the creature
    still lunges and misses, and that NO wax is lost. Repeat immediately to confirm one pass can
    never be grabbed twice.
37. With the dial at least half way up, walk to within 12 studs and put the face in the centre of
    your view for half a second. Confirm the eye fissure darts, both arms cover the face, and it
    withdraws into the arch. Repeat from the opposite side of the doorway, and from directly in
    front of it — which half you stand in must not matter.
38. Try to break the stare: look away for a moment mid-hold (progress must visibly restart rather
    than resume), back off past 12 studs, put a wall between you and the face, and drop the dial
    below half (or CUP). None of these may clear it — but FLARE must always be bright enough.
39. After it is gone, wait 50 seconds on the same floor. Confirm it reappears — at a different arch
    if the floor had another qualifying one, otherwise at the same arch — fully dormant and able to
    trigger again. Sprinting through its old arch in the meantime must do nothing.
40. With two clients, have A shame it off while B watches from the other side of the doorway. Both
    must see the same retreat at the same moment, and the arch must be clear for BOTH afterwards.
    Then have A sprint-trigger it while B stands nearby: only A loses wax, B still feels the shake if
    within 60 studs. Restart the run and confirm every creature is gone and rebuilt cleanly.

**J. Mining and the sound field (solo + two clients, any floor)**

Deposit count is weighted by global-depth band and may be zero through three, at most one per
optional room. Re-roll seeds until you find one. The server-owned model is tagged
`WickWaxDeposit`; progress lives in attributes on the root, so Explorer can confirm authority.

41. Find a seam. Confirm the boulder **rests on the floor** — not half-buried with only flecks of wax
    showing, not floating, and not perched on a rock formation or an overhang — and that it sits
    against a wall in a side room, never in the entry, Basin, or Brazier room, never on the route you
    had to walk anyway, and never behind a vine curtain. Confirm you can stand and work it on dry
    ground. **Do the same check for every loot pickup on the floor**: both use `server/SurfaceProbe`,
    so a buried pickup and a buried deposit are the same bug.
42. Approach from ~30 studs. Confirm the wax reads amber against the cold rock, and that a slight
    ember comes up as you close in and fades as you back off — a warmth on the seam, never a light
    that marks it across the room. Confirm a depleted seam has no ember at all. Confirm the pickaxe
    appears in first person only within reach and never has collision or a hitbox.
43. Aim at a seam and confirm its row name appears; look away or put cave geometry between camera
    and seam and confirm the prompt disappears. Click once. Confirm you **plant**, the pick fades up
    and biases toward the seam, and one thin rail settles in. Click the bright core for this row's
    configured clean-strike count. Confirm the aperture moves, the seam wears after every accepted
    strike, and contact branches physically into bite/glance/break paths.
44. Listen. Confirm every strike has an audible crunch of impact underneath it regardless of
    accuracy, that Perfect, Good and Miss are three clearly different NOTES layered on top of that
    crunch rather than one sound at three volumes, that they come from the ROCK rather than from your
    head, that repeated Perfects vary only subtly rather than becoming chipmunked, and that break
    debris/low-end body is the biggest sound of the sequence.
44a. Watch the rail. Confirm one short trace and replacing result line acknowledge contact—no
    segmented disc, expanding circle, combo label, or whole-HUD bounce. A Miss gets only a slight
    sideways jolt; a break gets one restrained line while world fracture carries completion.
45. Press W mid-stance. Confirm you are released on that frame — rail fading, pick lowered, walk speed
    normal, no progress lost from the seam — and that you actually move rather than sticking for a
    moment. Repeat with Q (the dedicated cancel — checks the stance without moving you at all), with
    right click, with the touch STOP button, by cupping the flame, and by being snuffed. Then engage
    and stand still for the idle timeout: the stance must release itself. There
    must be no way to end up planted with no way out.
46. Try to mine unlit and try to mine while cupping. Both must be refused with an on-screen reason.
47. Double-click engage and spam strike at 0/100/200/300 ms emulated latency. Confirm pending clicks
    are swallowed, duplicate engage replays the same stance, no response can hide a live stance, and
    movement always releases the root. Click the visible Perfect centre at each latency and confirm
    it remains Perfect inside the configured rewind bound. Engage and press W before the response:
    no stale rail or “STRIKE THE BRIGHT CORE” hint may flash. After an accepted strike, immediately
    press Q/W: authoritative progress/noise and exactly one owner contact must still present even
    though the stance closes. Stall engage and strike replies past 1.25 seconds: the pending
    request/stance must close rather than admitting a second uncorrelated action, and neither late
    reply may reopen the rail. Exhaust the MineStrike request bucket before Q/W and confirm the
    idempotent release still restores movement. At 200/300 ms, explicitly check whether the
    authoritative crunch/trace visibly trails pick contact; that high-latency feel remains a publish
    acceptance gate.
48. Mine a seam within earshot of a Lurker, Stalker, or Hollow. Confirm the FIRST strike is usually
    ignored and that repeated strikes bring one — walking, at less than hunting speed, toward the
    seam rather than straight at you. Confirm it loses interest and drifts off if you stop and stay
    dark. Confirm a moth or Snuffer in the same room never reacts to the noise at all.
49. Swing the pickaxe directly into a threat. Confirm nothing whatsoever happens to it: no damage, no
    stun, no knockback, no collision. There must be no way to fight anything.
50. With two clients, have A and B engage the same seam. Confirm both see the same wear and hear/see
    each other's accepted spatial impact/chips, that each reads an aperture from their own strike
    count (so the two rails agree only while both have
    struck the same number of times — they are per-stance, not per-seam). On Standard, confirm only
    the breaker is paid; on Twin, confirm both miners still engaged at depletion receive the full
    configured grant. A paid helper must hear one break and see one debris burst, not the shared
    world event plus a duplicate private reward event. Everyone is released rather than left
    planted at a spent rock. Then have A engage and descend to the next floor: the stance must end,
    not follow them down. Restart the run and confirm every deposit is destroyed and rebuilt.
51. **Sound floor.** Sprint past a dark-hunter repeatedly and confirm it can eventually get curious,
    but that a single pass does not. Trigger a dripstone near one and confirm the impact draws it to
    the rubble. Neither may be louder in practice than working a seam.
51a. **Ambient pacing.** Listen for at least 20 minutes. Confirm strata strain, fissure breath,
    calcite ticks, hidden water, and gravel creep originate on believable sampled surfaces, remain
    naturally filtered through intervening rock, never overlap a Focus cue, do not repeat back to
    back, and include long stretches where nothing happens. Rockfall/gravel must never settle on a
    water surface; hidden water may. They must not attract hunters or leak into the lobby.

52. **Uncapped depth.** Start The Shallows and descend through Floor 7, then continue past Floor 20.
    Every descent must already have a successor ready, preserve the dry entry → Basin route and
    protected-room invariants, and emit the correct increasing `globalDepth`. The run now constructs
    only the current floor plus its successor instead of eagerly building a capped expedition.
42. **Wax accounting.** With `Config/Security.telemetryEnabled` on, finish a run by extraction, by
    burnout, by snuff, and by disconnecting mid-run. Each produces one `run_wax_summary` line with
    per-source losses/gains, the deepest global depth, and the outcome. `reconciliationError` must
    read `0.0000`; anything else means a wax mutation bypassed `Logic/WaxAccounting`.

**K. Raw Wax extraction economy**

Read the `raw_wax_run` and `raw_wax_lost` lines with `Config/Security.telemetryEnabled` on. Every
step below is checked against the SERVER log, not the card, because the card is a projection.

53. **Grant authority.** Break each row and confirm exactly its configured integer units are added
    (Standard/Twin 2, Deep 6, Bright 4), no living-wax meter moved except a legitimate Perfect shard,
    and the HUD gained a count—not a second bar. The top-left readout should fade in, acknowledge a
    rise subtly, group origins by depth, remain hidden on a no-mining run, and reconcile through
    `StateSync`.
54. **No duplicate grants.** With two clients, have A and B work the same seam and release on the
    same beat. Exactly one of them may be granted cargo; the other's swing must cancel. Confirm
    paid-player count never exceeds the row's `maxPaidMiners`; Twin may pay two present miners.
55. **Cargo cannot help you survive.** Carry cargo down to a dangerously low candle. Confirm there is
    no prompt, key, or Basin option that turns it into wax, and that burnout arrives exactly as it
    would with an empty hold.
56. **Snuff and revive.** Get snuffed while carrying cargo and be relit by a teammate. Confirm the
    carried total is unchanged across both the snuff and the revive, and that nothing dropped on the
    floor for anyone to pick up.
57. **Terminal loss.** Burn out while carrying cargo. Confirm half drops on the candle remains for
    the party and half is destroyed, with both sides represented once in the reconciliation ledger.
58. **Extraction.** Carry cargo to a brazier and commit. Confirm `raw_wax_run outcome=Extraction`
    with `extracted` equal to the carried bag, `carried=0`, and reward derived from origin depth,
    extraction depth, tier, contracts, and party result. Leftover living Wax must pay nothing. Hold
    the prompt repeatedly: neither run latch nor persistence transaction may pay twice.
59. **Disconnect.** Alt-F4 mid-run while carrying cargo. Confirm the bag moves into one owner-locked
    pile, rejoining inside 120 seconds restores it by claiming that pile, and after grace expiry a
    teammate may claim it. At no instant may both bag and pile contain the units.
60. **Split party and floor transitions.** With two clients on different floors, have each mine
    their own seam, then descend. Confirm cargo follows each player across the transition, that the
    two totals never merge or leak into each other, and that A extracting does not change B's cargo.
61. **Reconciliation.** In every run above, `reconciliationError` must read `0` — anything else means
    units appeared or vanished outside `CargoRules`/`ExtractionService`. Also confirm `depositsStarted`
    and `depositsAbandoned` match what you actually did: start a seam, walk away, and finish the run
    without breaking it.
62. **Persistence idempotency.** Retry the same extraction transaction after a simulated profile
    write retry. The existing transaction id must reconcile the already-credited payout, never add it
    again.

**Regression sweep:** dial cap after CapMaxBrightness sacrifice (slider springs back to the cap) ·
Decoy follows a server-checked arc (try rolling ground, a far wall,
and a Sump — it lands ≤ 25 studs away and never underwater) · CUP dims to a near-dark ember without
extinguishing the flame · tools rejected while snuffed · Basin modal disappears on
floor/result/lobby/death transitions · no movement/tool bindings or touch buttons in the lobby.

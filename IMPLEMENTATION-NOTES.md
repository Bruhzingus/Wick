# IMPLEMENTATION NOTES — Phase 0–5 prototype

What was built, where it deviates from the letter of the spec, what was underspecified, and
where the shortcuts are. Companion to `STRUCTURE.md` (layout) and `TUNING.md` (numbers).

## What was built

Every system in the spec, wired together: server-authoritative wax on a fixed tick · shrinking
candle rig with authoritative height · first-person camera with visible body · continuous
brightness dial (scroll + slider, server-clamped) · wax-bar HUD plus a control/charge hotbar ·
client-only low-wax, draft, water, threat, and flame feedback · run/dodge/slide
with measured-speed drain · all four tools as light-field edits · one generic threat system with
two categories, eight depth-weighted rows, a Snuffer, and territorial VoidFly · config-planned wax/charge loot ·
session-local recoverable remains · draft (gutter + snuff timer, CUP-countered) and water (real
height comparison, shrink interaction emergent) · non-glowing wax-drop trail (navigation + hunter
breadcrumbs only) · both death states, relight paid by the reviver, burnout wisp · procedural floors from
weighted modules · private Basin with depth-worsening exchange · brazier with live arithmetic
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
   to wisp (`deathCause = "Snuffed"`), no rescue window. The revivable snuffed state is reachable
   via drafts (see 4).
4. **Draft snuff timer added** (`Draft.snuffAfterSeconds`). DESIGN says drafts gutter the flame;
   without a snuff consequence the revivable death state would be unreachable in v1 and CUP
   would be a numbers-only tool. Uncupped, lit exposure past the timer = snuffed (revivable).
5. **Voluntary SNUFF is self-reversible** after `selfRelightDelaySeconds` (otherwise it's suicide
   when solo). World-snuffs are never self-reversible.
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
- **Jumping is disabled** (a candle does not jump); no fall damage of any kind.
- **Cup upkeep** (`Cup.waxCost`) is charged per second held, in the drain pipeline — so it CAN
  contribute to burning out, unlike activation costs which use strict `>` and never kill.

## Playtest round 1 changes (2026-07-23)

- **Camera**: eye now sits `Character.cameraLift` above the body top, and the local player's
  Flame and Wick are hidden client-side (they sat at the eye and filled the screen). Body and
  rim stay visible — looking down still shows the shrink. Other players see the full candle.
- **Self-shadows off**: every candle rig part has `CastShadow = false` — kills the giant radial
  self-shadow and its jagged tessellation artifacts.
- **Stumpy candle**: heights 4/0.8, radius 1.4, plus melted rim + dark wick + elongated flame.
  Water modules now cut localized recessed 0.45/1.2/2.0-depth pools with dry perimeter rock and
  submerged escape steps. FloorPlanner guarantees one dry entry-to-Basin route.
- **Threat models**: dark-hunters use connected near-black gaunt humanoid bodies with overlapping
  torso, pelvis, head, arms, hands, legs, and feet. Paired angled deep-crimson Neon eye slits retain
  a short low glow; the Drawn use neutral layered moth wings held in the vertical silhouette plane,
  a narrow thorax/abdomen, and upward-swept antennae so they remain readable head-on.
  VoidFly reuses the hunter-eye treatment on its specialized ceiling-bug profile.
  Name labels remain gated by
  `Feel.debug.showThreatLabels` and default off for horror/readability tests.
- **Cave terrain**: cell 52, 6–12 rooms per floor, Slate materials, taller varied ceilings, wall
  relief, planned ramped ground shelves, angular boulders/columns, deep wedge-built rock throats,
  ceiling shards, and crossed tapering stalactites. Scaled balls are not used for cave rock.
  Doorway openings roll 11–22 studs wide and 8.5–16 studs high from a shared-edge seed, making
  adjacent wall openings agree. Rooms attempt seven broad, slightly overlapping ramped shelves;
  only special-room centers, doorway lanes, and recessed water footprints remain level/low.
  Sparse angular boulders supplement the terrain instead of faking variance with scatter. Ground
  placements and recessed pools are pure FloorPlan data because their collision changes traversal;
  roof, rim, and wall details remain cosmetic.
- **Lobby/input lifecycle**: movement/tool ContextActionService bindings and touch buttons exist
  only during an expedition. Basin choices dismiss on floor/run/lobby/death transitions. Dial
  dragging coalesces server requests to 0.15-second intervals and always sends the release value.

## Known shortcuts and trust boundaries

- **Character physics is client-owned** (standard Roblox humanoid networking). The server
  measures speed/position and `MovementSanityService` keeps a one-second trusted anchor. It allows
  sustained run speed with configured slack/jitter plus each approved dodge/slide distance once,
  then corrects excess displacement. This is prototype mitigation, not a production anti-cheat:
  it does not prove every replicated path is legitimate and may need tuning under real latency.
- **Dodge velocity is applied client-side** after server approval/charge (physics ownership).
- **Threat navigation is a lightweight floor graph, not PathfindingService.** Every threat row
  follows reciprocal doorway-centre waypoints from `RoomNavigation`; semantic targets are clamped
  inside rooms and diverted around localized pools. Basin sources/players/trails/contact are
  excluded with a final fail-closed step guard. ThreatService raycasts onto the real ground
  contour and chooses a temporary sidestep when solid cave geometry blocks its line.
- **All floors are physically live at once** (stacked 80 studs apart). Threat budgets are small;
  no culling. Fine at slice scale.
- **Draft zones are avoidable room-interior pockets** with explicit cold haze, edge strips, and a
  local CUP reminder. Tune `Hazards.draftZone`, `Hazards.draftVisual`, and `Feel.draftWarning`
  rather than weakening the mechanical draft to solve readability.
- **VoidFly uses reusable threat profiles**, not an ID branch: `ambush` confines it to a home
  territory and handles group/max-burn retreat; `contactAttack` stages four low-damage strikes.
- **Loot uses primitive pickup art.** FloorPlanner deterministically places wax profiles and
  prepared Flare/Cast charges. LootService owns prompts and applies effects server-side.
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
- **Menu and cave loops use the uploaded project tracks.** `Config/Audio.luau` maps `MenuMusic`
  and `CaveAmbience` to their Roblox asset IDs, while `AudioCues` reports load or permission
  failures as `[WICK AUDIO]` warnings. Unassigned one-shot cue IDs remain safe no-ops.

## Automated pure-rule tests

`src/shared/Tests/` contains a dependency-free harness and config-derived suites for the pure
gameplay rules. The current registry covers WaxDrain, BrightnessMap, LightField, ThreatBrain,
RoomNavigation, HazardRules, SacrificeRules, RewardMath, FloorPlanner, CandleGeometry, ToolRules,
LootRules, and TokenBucket. The tests focus on contracts and invariants, so ordinary tuning
changes do not require rewriting expected constants.

`src/server/StudioTestRunner.server.luau` runs the registry once whenever a Studio server starts.
It does nothing in a published server. Look in Studio's Output window for
`[WICK TESTS] PASS: 59 deterministic tests`; a failure is emitted as one red error containing
every failed suite/case, while the normal game boot continues for manual testing.

The command-line toolchain can parse, lint, format-check, and Rojo-build these files, but it has
no Roblox runtime executable. A Studio Play or Start Server session is therefore the execution
gate before publishing.

## Manual test script (gameplay verification is on you)

Setup: run `wally install`, then `rojo build -o Wick.rbxlx`; open the place and run `rojo serve`
for live source sync. For two-player tests use Studio's Test tab → Clients and Servers → 2
players. Studio deliberately bypasses teleport and starts the expedition locally.

**A. Core loop (solo, 5 min)**
1. Play. Confirm Output first reports `[WICK TESTS] PASS: 59 deterministic tests`. In the lobby,
   choose **READY**, then as leader choose **START EXPEDITION**. After the 5s run countdown you
   spawn in a dark room holding a lit candle. Look down — you see your own cylinder body.
2. Confirm the bottom control legend shows 1–4 tools plus Q Dodge, C Slide, and Shift Sprint
   plus `WHEEL / RIGHT SLIDER = BRIGHTNESS` (a compact keyless legend and the actual action
   buttons appear on touch). Scroll the wheel / drag the right-edge slider: light radius visibly
   grows and shrinks; the left wax bar drains faster at high dial. Snap points flash at 25/50/75%.
3. Hold Shift and run: bar drains faster than standing. Q dodges (burst + small wax dip),
   C slides (speed burst + dip). Both respect cooldowns.
4. Walk around: small dull wax drops appear behind you and fade on a timer. Confirm they emit no
   light and do not pull a moth toward the trail by themselves.
5. Stand still at ~40% dial for a minute: the body visibly shortens as wax falls.
   Below 25% the wax bar pulses orange; below 10% it pulses red.

**B. Threats (solo)**
6. Find a dark-hunter (black silhouette): stand bright near it — it keeps distance or flees.
   Dial to minimum — it approaches; contact drains wax fast (bar, not health).
7. Press 2 (FLARE) as it closes: it breaks off. Cost is visible on the bar.
8. Find a Moth/Swarm: burn bright — it comes to you. Press 1 (SNUFF): screen goes near-black,
   it loses you. Press 1 again after ~1.5s to relight.
9. With a drawn chasing: press 3 (CAST) — the blob lands ahead and the drawn diverts to it
   until it burns out (~6s).

**C. Hazards (the important one)**
10. Cold interior haze pocket = draft: stand lit in it — the local flame flickers harder, the
    warning calls out CUP, extra wax drains, and after ~4s your flame snuffs. Solo snuff resolves
    immediately to results because no teammate can relight you.
    Repeat holding 4 (CUP): slow, near-dark, but the draft cannot touch you.
11. Compare Shallows, Flooded, and the rare deep Sump. Confirm one dry path always reaches the
    Basin, while optional deeper water changes from survivable to lethal as the candle shrinks.

**D. Basin, brazier, descent (solo)**
12. In the safe amber-floored room, hold the Basin prompt: three private offers with real wax
    numbers. Choose one (tap or 1/2/3). Bar rises; the loss is live (capped dial ceiling /
    no slide / no drips…). Re-prompting says the Basin is spent for this floor.
13. Stand at the brazier pedestal: bottom text shows the live formula
    (wax × depth × group × tier = total). Hold to commit: results text, reward paid, candle freezes.
14. Or step on the dark pad in the Basin room: you drop to Floor 2 ("Floor 2" flashes).
    Deeper floors have more threats and pay more.
15. Die or cash out: the result/death breakdown states why the run ended. Once every runner is
    resolved, choose Restart Run for an immediate replay or Back to Lobby to refresh currency,
    reveal newly unlocked caves, clear readiness, and choose a tier. If nobody chooses, the world
    automatically rebuilds after 60s.

**E. Two clients**
16. Both clients auto-join the same lobby party. Confirm only the leader sees Start, both players
    appear in the list, changing tier clears ready state, and Start is rejected until both are
    ready. Ready both clients, start, and confirm both spawn into the same run. Each sees the
    other's candle height ≈ their wax.
17. Player A stands in a draft until snuffed. B walks over, holds "Relight": B's bar drops by
    0.15, A's flame returns. (A's bar was grey while down.)
18. A takes "Never be relit" at a Basin, then snuffs in a draft: A dies outright — correct.
19. Both stand at one brazier: preview shows group ×1.25 for each. One commits alone on a later
    run to compare. The other's run continues after A cashes out.
20. A burns out fully: A becomes a faint blue wisp that can drift with B and sheds dim light;
    after 2 min it goes still.

**F. Loot, depth scaling, and remains**
21. Pick up Beeswax/Tallow/Cold Wax. The message names the new profile; dial output and drain
    change immediately without increasing the wax meter.
22. Pick up a Prepared Flare or Prepared Decoy. The hotbar charge count rises. Use that tool:
    cooldown/effect are normal, the charge disappears first, and wax is not charged for that use.
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
    leader start. Confirm both clients leave the lobby, the reserved server waits for expected
    arrivals before countdown, and both enter the expedition. Cash out and use Back to Lobby:
    currency and any newly affordable tier should appear immediately while the party stays
    together and readiness clears. Leave, rejoin, and also confirm that progress survives.
27. Confirm the selected tier changes its maximum depth and displayed reward multiplier. A member
    who has not unlocked the selected tier must prevent the party from starting.

**Regression sweep:** dial cap after CapMaxBrightness sacrifice (slider springs back to the cap) ·
dodge unavailable mid-cooldown · Cast aim clamped (try casting at a far wall — it lands ≤ 25
studs away) · SNUFF costs nothing · tools rejected while snuffed · Basin modal disappears on
floor/result/lobby/death transitions · no movement/tool bindings or touch buttons in the lobby.

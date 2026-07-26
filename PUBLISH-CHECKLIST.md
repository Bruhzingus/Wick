# Publish Checklist — friend prototype

Do not treat a successful Rojo build as a gameplay pass. Complete each gate in order.

## 1. Dependencies and build

- [ ] Run `rokit install` if the pinned tools are not already available.
- [ ] Run `wally install`. Confirm `ServerPackages/ProfileStore.lua` exists.
- [ ] Run `selene src`.
- [ ] Run `stylua --check src`.
- [ ] Run `rojo build -o Wick.rbxlx`.
- [ ] Open `Wick.rbxlx` in Studio. Start `rojo serve` and connect the Rojo plugin if you will keep
  editing while Studio is open.

## 2. Studio runtime gate

- [ ] Start Play/Server and open Output.
- [ ] Confirm exactly one successful signal:
  `[WICK TESTS] PASS: 94 deterministic tests`.
- [ ] Treat any `[WICK TESTS] FAIL`, red runtime error, infinite yield, or missing package as a
  publish blocker.
- [ ] Remember: Studio uses ProfileStore Mock and starts expeditions locally. It cannot prove live
  persistence or reserved-server teleport behavior.

## 3. Solo smoke test

- [ ] Confirm you spawn in the physical lobby ("The Landing") as your **own Roblox avatar** in third
  person — not a candle — and that Shift sprints across the room.
- [ ] Confirm you can walk to and read the welcome board, the HOW TO PLAY board (its CONTROLS panel
  must list the real keybinds), and the DEEPEST DESCENTS standings board. In Studio the standings
  board reads "Standings are unavailable in Studio" — that is correct, not a failure.
- [ ] Confirm the shop stall's prompt replies with its placeholder message as on-screen status text.
- [ ] Stand in the Shallows elevator. Confirm its header board names the tier, lists you with a
  filled readiness dot, and that the lever becomes usable (solo satisfies "every member ready").
- [ ] Step into the Descent or Deep elevator. Confirm its header reads LOCKED with the light it
  needs, that the party tier does **not** change, and that a status line explains why.
- [ ] Before pulling the lever, confirm expedition tool/dial bindings and their touch buttons are
  absent (walking and lobby sprint work; dial/tools do not).
- [ ] Pull the lever. Confirm the gate closes, the car physically descends its shaft with you inside
  it (shaft ribs passing, camera shudder, in-car readout counting down), and that you arrive as a
  lit candle in first person with wax bar, dial, and hotbar visible; the hotbar names
  wheel/right-slider brightness. There must be no flat cut between the lobby and floor 1.
- [ ] Exercise 1 Snuff, 2 Flare, 3 Decoy, 4 Cup, Space/mobile Jump Hop, and
  Shift Sprint. Confirm the hop clears a small crack without reading as a full-height avatar jump.
- [ ] Confirm Snuff and Decoy show a shrinking bar and readable numeric pill only
  after server acceptance. The value rounds upward by tenths and never shows ready early; an
  immediate repeat flashes red without replaying success feedback. Flare, Cup, and Sprint show no
  cooldown bar.
- [ ] Reject Decoy against an invalid surface and confirm its chip briefly reads
  `AIM AT OPEN GROUND`; verify other rejected actions show their configured friendly reason.
- [ ] Confirm Snuff reads `RELIGHT` for its full 1.5-second commitment. Cup reads `● UNCUP`, Flare
  reads `● FLARING` for its 1.5-second burst, and both use the active chip style. Flare removes
  0.13 wax per press, has no cooldown, and renders brighter than maximum normal light; Cup may be
  raised/lowered without cooldown.
- [ ] Aim Decoy across uneven floor, toward a wall, and into a Sump: a miniature candle follows its
  server-checked arc, grounds before the wall on legal dry terrain, attracts a Drawn threat without
  repelling a dark-hunter, and expires after six seconds. Illegal near/steep/wet casts must spend
  neither wax nor cooldown and must briefly read `AIM AT OPEN GROUND`.
- [ ] In touch emulation, confirm native action buttons mirror cooldown fill/tenths and switch to
  the same `RELIGHT` / active-marker titles. Return to the lobby and start again; no old timer, denial, active title,
  or free-charge label may survive the transition.
- [ ] Confirm high brightness drains faster, low-wax feedback appears, and no action grants wax.
- [ ] Confirm a fresh candle reports/fills to 1.3 wax, remains the normal full model height, and
  the HUD/low-wax warning still represent percentage of capacity rather than overflowing.
- [ ] Walk and sprint beside jagged cave walls at low and maximum brightness. Confirm the local
  spherical shadow accent follows without harsh stepping, the amber near-field does not reveal
  beyond the authoritative range, bloom remains restrained, and a second client adds no shadow
  popping. Cross the entry-room doorway repeatedly while turning the camera; camera rotation while
  stationary must not change the light or make rock faces appear.
- [ ] At a fixed dial, watch an idle candle for at least 30 seconds. Confirm its whole light has
  subtle non-looping brightness and warmth variation plus occasional soft guttering; fill, shadow,
  and bounce must move together while full-screen bloom/grading stays stable. Its range edge,
  enabled state, and emitter position must not pulse, snap, or expose a new chunk. Sprint and
  and nearby-threat context may make the local flame less stable, but must not change wax drain or
  authoritative threat reactions.
- [ ] Lure one threat across at least two rooms. Confirm it uses doorways, does not cut through a
  wall, and never enters or attacks through the safe Basin.
- [ ] In a dark room, confirm a dark-hunter reads as one connected humanoid body (not floating
  spheres), and that its angled deep-crimson eye slits appear before the near-black body resolves
  without illuminating it. Face a moth directly and confirm its broad vertical wings remain
  visible around the narrow body instead of collapsing into a sphere-and-rods silhouette.
- [ ] Walk a long route and look back. Confirm only small dull wax beads remain: no Neon material,
  PointLight, visible glow, or moth attraction from the trail itself.
- [ ] Confirm at least one dry route reaches the Basin. Check that water appears as recessed
  animated puddles/pools with dry rock around them, then enter and escape shallow/deep pools at
  high and low wax. Confirm flame-height contact still kills.
- [ ] Approach a VoidFly from outside and inside its territory. Confirm it stays local, snuffs only
  after four uninterrupted successful strikes, and does not retreat from maximum ordinary burn.
  Trigger Flare while it approaches and during a staged attack: it must immediately retreat, clear
  accumulated strikes, and remain blind temporarily. In several low/sloped-roof rooms, confirm it patrols 1.5 studs below
  the exact underside, never intersects Terrain or harmless formations, dives/returns without a
  vertical snap, and cannot appear in a nominal roof above 30 studs. Stay within 32 studs in the
  same room until its quiet buzz plays; confirm the buzz is positional, is not self-occluded by its
  own roof anchor, and remains inaudible through the neighboring room's wall.
- [ ] Test a DarkCrawler at low, medium, and high light. Confirm it attacks low/no light, holds
  roughly 11 studs in ordinary light, and never flees from the dial alone. Use Flare and confirm it
  retreats immediately, then remains blind for two seconds beyond estimated straight-line travel
  even after the burst disappears.
- [ ] On floors 1–3, take contact from each available threat and enter water zones. Confirm a
  small relevant hint fades above the hotbar, does not spam under continuous exposure, and remains
  local to the affected player. Repeat on floor 4 and confirm no tutorial hint appears.
- [ ] Across several seeded runs, confirm floor 1 still excludes VoidFly and eligible depths select
  it more often without changing total threat budgets or the shape of its depth curve.
- [ ] Confirm DarkCrawler, CaveMoth, and CeilingFly bodies follow their invisible proxies without
  jitter, animate independently on each client, never block a local raycast, and cull past 120 studs.
- [ ] Inspect entry, Basin, dry, and flooded rooms. Confirm each has angular raised ground, adjacent
  doorways visibly differ in their actual opening width/height, and every ceiling is a sealed,
  irregular Terrain underside with broad rock structure rather than a flat slab. Confirm the roof
  blends cleanly into walls/door arches, retains at least the configured local-ground clearance,
  and its jagged CaveKit formations touch the sampled underside. Confirm broad floor slopes cover
  most room interiors, water occupies recessed low points, and only doorway/special interaction
  lanes remain deliberately level. Walk over several shelves; confirm threats follow height and
  avoid pool interiors.
- [ ] Confirm the automated target-curve case passes for F1–10 =
  1/2/2/4/5/7/8/10/12/15 before safety caps. Across seeded runs, inspect the actual capped
  placement: no more than half of ordinary rooms are dangerous, per-room caps are 1/2/3 for the
  three depth bands, and harmless roof formations remain the majority. Entry, Basin, Brazier,
  >34-stud nominal roofs, and VoidFly/Snuffer rooms must be clear.
- [ ] Learn each dangerous Needle/Fork/Hammer by its shared off-axis lean, dark dry fractured
  collar, and sparse dust. Confirm ordinary formations do not use the full tell, and there is no
  glow or UI marker. Trigger one and leave the landing footprint during its 1.65/1.8/2-second
  wobble/fracture warning; it must fall vertically at the original spot and miss rather than home.
- [ ] Take direct hits at known wax. Confirm Needle/Fork/Hammer remove 20%/35%/50% of maximum wax;
  below 30% wax confirm the impact snuffs instead. On Floors 1–3, confirm the first nearby fall
  gives each player the bottom-screen fractured-collar/falling-dust avoidance hint, even on a miss.
  A survivor stays lit at 42%
  output for two seconds; threats perceive the same temporary light; and the local flame flicker,
  impact dust/debris, positional stone sound, camera shake, and
  brief hit grading occur once. Brightness and sprint must not alter the fixed trigger—only
  visibility and available reaction distance.
- [ ] Inspect loot across several rooms. Confirm pickups are readable wax/flare/decoy props rather
  than Neon spheres, rest above peripheral wall berms or raised cave ground, and never float,
  clip into rock, sit on a roof, or block a doorway. Collect one and confirm its effect.
- [ ] Use one Basin offer, one descent pad, and one brazier.
- [ ] Die once. Confirm the result explains the cause and the restart request works once all
  runners are resolved.
- [ ] After restarting, confirm the new candle immediately owns the first-person camera, looking
  down shows its body, mouse-look works, and no dead wisp or detached camera remains selected.
- [ ] Watch Output for unexpected errors and review `[WICK]` telemetry events.
- [ ] Enter an expedition and confirm cave music does not start immediately. Let multiple tracks
  complete: each must fade in/out, include a silent gap, vary its shuffled order, and never repeat
  immediately. Return to the lobby mid-track and confirm it fades into menu music.
- [ ] Change LOCAL AUDIO while music and an effect are audible; confirm the shared volume changes
  both without interrupting either sound.
- [ ] Hold Sprint while stationary: no sprint overlay or FOV change should appear. Move forward
  while holding Sprint: FOV should ease from 74 to 85 over about 0.4s, with restrained edge
  darkening/shimmer and slight camera instability, then return smoothly on release.
- [ ] Confirm sprint feedback disappears while cupping, snuffed, dead, finished, or in the lobby.
- [ ] With two clients, watch the other candle sprint: its flame should stretch/lean backward and
  its non-glowing wax drops should be denser than while walking.

## 4. Studio two-client test

Use Studio Test → Clients and Servers → 2 players.

- [ ] Both players appear in the same party in the physical lobby as their own avatars, and can see
  each other; only the leader's chosen elevator sets the shared tier.
- [ ] Each elevator's header board lists exactly who is standing in that car, with a filled dot for
  ready and a hollow dot for not — updating as either player walks in and out.
- [ ] The descend lever is disabled until both players are standing in the matching elevator, and
  only ever appears on the car matching the party's current tier.
- [ ] The leader switching to a different unlocked elevator clears both players' readiness. A locked
  tier's elevator never changes the party tier and never enables the lever.
- [ ] Pull the lever and confirm both players ride the same car down together and enter the same run.
- [ ] Return to the lobby afterwards and confirm the car is back at the top of its shaft with the
  gate open, and that both players are standing in The Landing — not anywhere the cave generated.
- [ ] Have a third client join after that return and confirm they arrive in the same room.
- [ ] Confirm the two candle colliders begin in separate entry slots inside the room, with no
  launch, wall clipping, or movement-sanity correction. Repeat after both descend together.
- [ ] Watch player A's idle candle from A and B. Confirm both clients reconstruct the same
  owner-seeded baseline timing while player B has a visibly different seed. Party flicker must
  remain fill-only on the observing client and must not create an extra shadow-map pop.
- [ ] Snuff player A and relight them with B; only B pays the relight wax.
- [ ] Have player A Cup away from player B and confirm A is almost completely dark. Move B's
  uncovered flame beside A and confirm the shared light field treats A as illuminated; Cup both
  players and confirm the near-dark state returns.
- [ ] Have both players approach a VoidFly. Confirm the second nearby runner scares it away
  temporarily and that it returns smoothly to the current sampled roof inside its fixed territory
  rather than chasing through the cave. Confirm both clients see the same authoritative flight and
  dive position while their occasional buzz timing remains local.
- [ ] Have A trigger unstable dripstone while B crosses its landing area. Both clients must see the
  same warning, release, and spent state. Each player inside the authoritative impact disc takes
  variant-scaled damage (or is snuffed below 30% wax); players outside it do not. Nearby
  presentation scales with distance, a direct hit alone receives the brief darkening, and
  restarting clears every spent formation.
- [ ] Kill both players, restart from either results screen, and confirm both clients independently
  reacquire their new candle in first person with centered mouse-look.
- [ ] Resolve another run and choose Back to Lobby. Confirm both clients return to cave selection,
  the party stays together, readiness clears, and current currency/unlocks refresh.
- [ ] Confirm private Basin offers are not shared between clients.
- [ ] At one brazier, confirm the two-player preview uses the group multiplier.
- [ ] Cash out one player and confirm the other can continue.
- [ ] Leave session-local remains, start the next run in that same server, and confirm the owner
  cannot recover it. A collector receives only available wax capacity; any overflow remains in the
  pool until an eligible player empties it.

## 5. Audio

- [ ] Confirm the uploaded menu music is audible, then start a run and confirm it switches to cave
  ambience without both loops playing together.
- [ ] Adjust the Settings audio slider and confirm the active loop changes volume.
- [ ] Watch client Output for `[WICK AUDIO]` load/permission warnings.
- [ ] Empty one-shot IDs are intentional safe no-ops; they are not broken loading.
- [ ] Confirm project music assets `122061612190896`, `71682768476112`, `136582960170775`,
  `104375150403939`, and `113564986043204` are permitted for the publishing experience and
  owned/usable by its account or group.
- [ ] Confirm Creator Store cues `9114506042` (fly), `9125929705` (dripstone fracture), and
  `9118609396` (dripstone impact) load and remain usable by the publishing experience.

## 6. Publish settings

- [ ] Publish the synced/built place to the intended Roblox experience.
- [ ] Set the place's maximum server size to **4** to match `RunSettings.partyCap`.
- [ ] Set experience access/test permissions so the friend account can join.
- [ ] Keep both lobby and expedition in this same place for the current prototype; the server code
  reserves another server of `game.PlaceId`.
- [ ] Do not expect Studio API-access settings to validate profiles: the code deliberately forces
  ProfileStore Mock whenever `RunService:IsStudio()` is true.

## 7. Required live two-account test

Roblox reserved-server teleports do not run in Studio. Publish first, then use two real accounts
or clients.

- [ ] Have one account join the live experience and the friend join that same server; both spawn as
  their own Roblox avatars in the physical lobby.
- [ ] Stand in the same elevator (leader's choice sets the tier) and pull the lever as leader.
- [ ] Confirm both clients see the gate close and the car begin to descend, then teleport together.
  Roblox's own loading UI sits in the middle of the ride and cannot be suppressed — that is a
  platform constraint, not a defect. On arrival the reserved server waits for expected arrivals
  before countdown (bounded at 8 seconds), and each arriving client resumes in a lobby body.
- [ ] Complete or cash out a run, choose Back to Lobby, and confirm currency/deepest-floor progress
  and newly unlocked tiers refresh without rejoining.
- [ ] Confirm the DEEPEST DESCENTS board shows real standings on a live server (it is inert in
  Studio by design) and that your own best floor appears after a run resolves. Allow up to
  `LobbyRoom.leaderboardRefreshSeconds` for the board to repaint.
- [ ] Leave, rejoin, and confirm that progress still persists. Confirm a newly unlocked tier changes
  max depth, threat budget, and reward multiplier.
- [ ] Test one failed/disconnected player scenario and record what happened. Rejoin recovery is
  not implemented; do not promise it to testers.

## Prototype limitations to tell the friend

- One auto-joined party per public server; no invite codes, queue matchmaking, or party browser.
- A full four-player server rejects additional party members rather than routing them.
- Remains are session-local and vanish when the expedition server closes.
- Movement protection and server-log telemetry are prototype safeguards, not production
  anti-cheat/analytics.
- Most art remains grey-box; pickups now use distinct procedural wax/flare/decoy props. Menu/cave
  music, the fly buzz, and dripstone fracture/impact cues are populated; most other one-shot cue
  rows remain intentional silent placeholders.

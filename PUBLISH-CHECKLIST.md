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
  `[WICK TESTS] PASS: 59 deterministic tests`.
- [ ] Treat any `[WICK TESTS] FAIL`, red runtime error, infinite yield, or missing package as a
  publish blocker.
- [ ] Remember: Studio uses ProfileStore Mock and starts expeditions locally. It cannot prove live
  persistence or reserved-server teleport behavior.

## 3. Solo smoke test

- [ ] In the lobby, confirm Shallows is unlocked, choose Ready, and start as leader.
- [ ] Before starting, confirm gameplay movement/tool bindings and their touch buttons are absent.
- [ ] Confirm lobby UI hides, the 5-second countdown completes, and the candle spawns in first
  person with wax bar, dial, and hotbar visible; the hotbar names wheel/right-slider brightness.
- [ ] Exercise 1 Snuff, 2 Flare, 3 Cast, 4 Cup, Q Dodge, C Slide, and Shift Sprint.
- [ ] Confirm high brightness drains faster, low-wax feedback appears, and no action grants wax.
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
- [ ] Cross an interior draft pocket with and without Cup. Confirm it is visible, avoidable, and
  does not seal the only doorway.
- [ ] Approach a VoidFly from outside and inside its territory. Confirm it stays local, snuffs only
  after four successful strikes, and retreats temporarily from maximum burn intensity.
- [ ] Inspect entry, Basin, dry, and flooded rooms. Confirm each has angular raised ground, adjacent
  doorways visibly differ in their actual opening width/height, and every ceiling has jagged hanging
  formations rather than stretched rock balls. Confirm broad slopes cover most room interiors,
  water occupies recessed low points, and only doorway/special interaction lanes remain deliberately
  level. Walk over several shelves; confirm threats follow height and avoid pool interiors.
- [ ] Use one loot pickup, one Basin offer, one descent pad, and one brazier.
- [ ] Die once. Confirm the result explains the cause and the restart request works once all
  runners are resolved.
- [ ] After restarting, confirm the new candle immediately owns the first-person camera, looking
  down shows its body, mouse-look works, and no dead wisp or detached camera remains selected.
- [ ] Watch Output for unexpected errors and review `[WICK]` telemetry events.

## 4. Studio two-client test

Use Studio Test → Clients and Servers → 2 players.

- [ ] Both players appear in the same party; only the leader sees Start.
- [ ] Start is rejected until both players are ready.
- [ ] Changing tier clears readiness. A locked tier cannot be selected/started.
- [ ] Start the Studio-local expedition and confirm both players enter the same run.
- [ ] Snuff player A and relight them with B; only B pays the relight wax.
- [ ] Have both players approach a VoidFly. Confirm the second nearby runner scares it away
  temporarily and that it returns to its fixed territory rather than chasing through the cave.
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
- [ ] Confirm project assets `122061612190896` and `71682768476112` are permitted for the
  publishing experience and owned/usable by its account or group.

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

- [ ] Have one account join the live experience and the friend join that same server.
- [ ] Confirm both are in one lobby party, ready both, and start as leader.
- [ ] Confirm both clients teleport together, the reserved server waits for expected arrivals
  before countdown (bounded at 8 seconds), and the lobby UI stays hidden once the run starts.
- [ ] Complete or cash out a run, choose Back to Lobby, and confirm currency/deepest-floor progress
  and newly unlocked tiers refresh without rejoining.
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
- Art and pickups are grey-box; only the uploaded menu/cave loops are currently populated, while
  one-shot audio cues remain silent until IDs are supplied.

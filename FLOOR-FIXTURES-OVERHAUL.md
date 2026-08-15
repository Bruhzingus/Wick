# FLOOR FIXTURES OVERHAUL — the Cauldron, the Gas Lantern, and the Descent Ladder

**Status: built.** This file was a proposal; it is now a record of what shipped and what was
deliberately left. The design canon graduated into `DESIGN.md` (§10 The Cauldron, §12 The Gas
Lantern, §12a The Descent Ladder); the tuning surface into `TUNING.md`; ownership into
`CodeBreakdown.md` and `STRUCTURE.md`. Read those first — this file only records the decisions and
the open questions, so that the next pass knows what was chosen and why.

## What the three fixtures were

- **Basin**: a flat orange Neon cylinder sixteen studs across, one stud thick, lying on the floor.
- **Descent**: a floating cyan Neon disc, a vertical light beam and a glowing orb, with an invisible
  zone around them. Walk into the zone and you were on the next floor that frame. No mechanism, no
  consent, no travel.
- **Brazier**: `newPart(Vector3.new(2, 3, 2), ...)`. One dark grey box — the least developed object in
  the game, owning its most loaded moment.

## What they are now

### The Cauldron (`Config/Cauldron`, `NewModelsAndObjects/Cauldron`)

A squat vessel on a three-legged tripod standing on a low cairn: family-tinted body, a proud rim,
two bands, molten wax sunk below the lip and moving slowly, cooled wax run down the outside in the
drip trail's own dull brown, and a dull ember glow under the belly. Nothing in it emits light — the
wax and the coals are Neon with no PointLight, so the room is still one you find with your own flame.

Its ripple is rendered by `client/EnvironmentAnimationController` from the same tag-and-attribute
pattern the water surfaces already use, rather than by a second animation system.

**Zero mechanical change.** `BasinService`, `SacrificeRules`, the pool, the grant band, offer privacy
and one-exchange-per-floor are untouched. The only edit to `BasinService` was raising the prompt
anchor to the rim.

### The Gas Lantern (`Config/Lantern`, `NewModelsAndObjects/Lantern`)

Enclosed glass panes in an iron frame on a low post, with a valve, a burner and a vent. Cold and dark
until lit; on ignition the panes clear rather than brighten, a pale blue-white core with warm tips
appears behind them, and the one deliberate exception to "the candle is the only light" switches on.
A chain hangs from the post whose length is cut from the floor's own global depth.

The end-card beat keeps the ordinary first-person camera: the extracting candle is frozen and turned
toward the completion room's sole Gas Lantern, then may look freely for five seconds while the rest of
the cave-wide network follows from nearest to farthest. Every generated room gets exactly one wall
lamp. The completion room's lamp is the interactive Gas Lantern, with no decorative companion; every
other room gets one network lamp. `FloorBuilder` selects a deterministic wall in each room, prefers
intact rock, and falls back to a position beside a doorway when all four walls are open. It samples the
real per-room ground field to keep the fixture above the berm, then probes Terrain at the lamp's base,
middle, and top. The nearest valid surface and its horizontal room-facing normal place the fixture just
proud of the rendered rock. No Terrain is carved, so a fixture cannot produce a recessed pocket or an
invented flat wall. Random wall relief is excluded from the same tight footprint. Neither generated
Terrain nor dressing can cover a fixture. A small point glow resolves the lamp itself while a wide,
lower-intensity amber SpotLight
faces into the room and supplies coverage without a sun-like source. The lamps are the only visual
effect — no flying motes or glowing orbs. They are shared world state. An early individual extractor
sees results immediately; the final runner or every member of a unanimous group extraction receives
the free-look beat together. No new save data, no floor tracking, and no dependence on retired
geometry. Reward arithmetic does not change. On the first ignition, every enemy owned by that floor
is removed; deeper-floor enemies and non-enemy hazards remain.

**Zero mechanical change to the reward.** `Config/Brazier` still owns the payout, the prompt range,
the hold and the tolerance. `BrazierService` keeps its name because the SYSTEM did not change.

### The Descent Ladder (`Config/DescentLadder`, `NewModelsAndObjects/DescentLadder`, `server/DescentLadderService`, `client/DescentLadderController`)

A one-person open-frame cage on a chain winch, in a headframe with a sheave, over a shaft genuinely
carved out of the rock and lined with rib rings and guide rails. A `ProximityPrompt` on the cage's
lever replaces the trigger volume. Boarding puts the rider on the deck, anchors them, shuts the
hatch over the mouth and starts a timestamped ride that every client draws locally; the cage's bottom
pose and its return to rest are the only transforms the server writes, exactly as the lobby elevator
does it.

## Decisions taken on the open questions

1. **Extraction sequence** — individual early extraction remains immediate. The final unresolved
   runner gets five seconds of normal first-person free look before results. A second unanimous
   proximity prompt lets every unresolved runner on the same floor opt into a synchronized group
   payout and shared free-look scene; proximity alone never grants consent.
2. **Shared lit state** — the lamp goes permanently lit for everyone the first time anybody lights
   it. Per-player lit state was rejected: the reward is already independent per player, so the only
   thing private state would add is two people at one fixture disagreeing about whether it is on
   fire.
3. **Ladder room placement** — the cheaper shared-room version, on the pad `descentRegion` already
   occupied. A dedicated `elevatorRoomIndex` in `FloorPlanner` remains a separable follow-up if one
   chamber holding two fixtures stops reading cleanly in play.
4. **"Last floor"** — verified: no such concept exists anywhere. Expeditions are uncapped, the next
   floor is built on demand, and nothing gates on a maximum. `FloorBuilder`'s stale comment claiming
   the descent pad was "unusable on the last floor by plan" was wrong and is gone. The ladder is
   present on every floor.
5. **Depth chain** — built. It was cheap once the length came from the floor's own global depth at
   build time rather than from anything accumulated.

## Changes made after the first pass (owner direction)

- **All three fixtures share one chamber.** `FloorPlanner` now resolves `brazierRoomIndex` to the
  Basin room, so the Cauldron stands at the centre with the Gas Lantern and the Descent Ladder at
  opposite quarters, ~45 studs apart. The room a floor is scored in is the room it ends in: you stand
  between the machine that banks your haul and the machine that takes you deeper and pick one. Both
  plan fields were KEPT rather than merged into one, so every downstream refusal ("never in the entry,
  Basin or Brazier room", "never on the guaranteed route", "a vault is never the completion room")
  keeps asking its own question and just gets the same answer twice — and separating the rooms again
  is one line in the planner rather than an unpicking of a dozen call sites. The room the chamber
  hangs off is now ordinary and carries ordinary content.
- **The ladder carries one work lamp.** Retiring the cyan beacon left the way down as a dark rig you
  could walk past. A three-quarter-size Gas Lantern now hangs off the headframe on a bracket, just
  outside the mouth — outboard on purpose, because the column over the shaft is the cage's own path
  and the cage's yoke reaches nearly to the beam when parked. Range 20 / brightness 0.85 in a 64-stud
  room: enough to resolve the rig as you approach, not enough to light the chamber.
- **The lamp cannot be exploited and could never have been.** An earlier comment in this codebase
  claimed a lit cage would advertise its rider to the floor. That was wrong: `server/LightSources`
  builds the threat-perception field from server-owned flames, flares, decoys and remains and never
  scans the world for `PointLight`s, so a decorative light is invisible to every creature. The comment
  has been corrected rather than left as a plausible-sounding but false justification.
- **Both lamps are one object at two sizes.** `Lantern.buildWorkLamp` shares the panes, frame, cap and
  bail with the full-size fixture, so the two lamps in a chamber can only ever change together. The
  big lantern also gained the bail it was missing — the loop you carry a lantern by is its single most
  recognisable feature, and this is the one lamp in the game nobody has to carry.

## Decisions taken that the brief did not ask about

- **The hatch.** An empty shaft in a walkable room is a hole a teammate falls into, and the cage is
  genuinely away for a ride plus the winch hauling it back. Two leaves fold flat over the mouth for
  that whole window, server-posed so everybody sees the same thing at the same instant.
- **The ride is not safe.** The rider is pinned and the server still holds their position at the
  mouth, so anything that had already reached them still can. No invulnerability was added: the
  protected room was removed from this game on purpose (DESIGN §10), and four seconds of it at every
  ladder would be a rules change wearing an animation's clothes.
- **The carve is clamped.** `rideDistance` and `shaftDepth` are ceilings. `FloorBuilder` computes what
  actually fits between two floors from `floorGap`, `ceilingMaxHeight` and `roof.rockThickness` and
  clamps both against it, so a retune of any of the five numbers can never cut a hole in the ceiling
  of a cave nobody has walked into yet.
- **The floor carve moved into the ride.** `canDescendFrom` builds the floor below if the lookahead
  has not reached it, so on the rare frame a carve is owed it happens while the cage is already
  moving. The one expensive frame in a descent is now spent inside an animation nobody can walk out
  of.
- **The three fixtures reserve against cave dressing.** They never used to need to: a flat disc and a
  floating beacon passed through everything. A boulder rolled on top of the shaft mouth would now be
  an obstacle in front of the only way down. (Planned content needed no new rule: the Basin room is
  already excluded from loot, deposits, threat spawns, relics, dripstones and remains.)
- **The deck is cleared before it drops.** The cage is a walkable platform in a room a party crosses
  together, so a second player standing on it when somebody pulls the winch is the ordinary case with
  four runners, not an edge case. Only the rider is anchored, so anyone else would fall into a shaft
  about to be covered. They are stepped onto the collar instead — one short move outward, which is
  what the moment physically is. Left alone they would have been recovered by the stranded-runner
  watchdog, but to the floor's ENTRY: a room-length punishment for standing in the wrong square.
- **Client rides are keyed by floor, not a single slot.** A party splits across floors constantly and
  two people riding two different ladders within the same few seconds is ordinary play. With one slot
  the second departure silently cancelled the first, leaving a player's own descent with no camera
  shudder and a body that stopped following the cage under it.

## Still deferred

- **Co-descent.** Multiple party members riding one cage together. If revisited it is an *addition*
  to the per-player model (a cage that carries 1–N riders who happen to arrive together), not a
  redesign of it. The only thing standing in its way today is that `rides` is keyed one-per-cage.
- **A dedicated ladder room.** See decision 3.
- **A moving sheave.** The wheel is static. The lobby's is too.

# IMPLEMENTATION NOTES — vertical slice

What was built, where it deviates from the letter of the spec, what was underspecified, and
where the shortcuts are. Companion to `STRUCTURE.md` (layout) and `TUNING.md` (numbers).

## What was built

Every system in the spec, wired together: server-authoritative wax on a fixed tick · shrinking
candle rig with authoritative height · first-person camera with visible body · continuous
brightness dial (scroll + slider, server-clamped) · wax-bar HUD (the only HUD) · run/dodge/slide
with measured-speed drain · all four tools as light-field edits · one generic threat system with
two categories (4 config rows) · draft (gutter + snuff timer, CUP-countered) and water (real
height comparison, shrink interaction emergent) · drip trail (nav + hunter breadcrumbs + faint
light) · both death states, relight paid by the reviver, burnout wisp · procedural floors from
weighted modules · private Basin with depth-worsening exchange · brazier with live arithmetic
preview and group multiplier · full run loop with auto-restart. Deferred systems are called only
through `shared/Interfaces` stubs.

## Deviations from the letter of the spec (all deliberate, all reversible)

1. **`ToolDef.effect` (per-category ± table) was replaced with physical light params.** The
   opposite-reaction rule is still pure data — tools edit the light field (Config/Tools), and
   the categories react in opposite directions via the sign of `lightResponse` (Config/Threats).
   This is *more* data-driven (zero per-tool branches anywhere), but if you want the signed
   table back as documentation, it's a Types+Config change only.
2. **Snuffer moved out of Hazards.** A snuffer is an enemy, so the threat system got a generic
   `contactEffect: "Drain" | "Snuff"` field instead. No snuffer row ships in v1 (spec built only
   draft + water); adding one is a Config/Threats row.
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
7. **`toolCharges` dropped from PlayerRunState** — consumable charges belong to deferred loot.
8. **`FloorDef` replaced by `FloorPlan`** (the planner's richer output). Nothing consumed FloorDef.
9. **Party stub reshaped** to take present players as input and return everyone (capped), so two
   Studio clients share a run today. Still a stub; still one file to replace.

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
  `waterDepth` retuned 3 → 2.2 so the water death line stays ~44% wax.
- **Threat models**: category-shaped silhouettes (gaunt spindle for dark-hunters, winged hover
  for the drawn) scaled by `bodySize`, with name labels. **Labels are a grey-box tuning aid** —
  DESIGN §16 says threats are silhouettes; gate or remove labels before evaluating horror.
- **Cave dressing**: cell 44, +1 room per floor, Slate materials, per-room ceiling variance,
  wall relief strips, seeded per depth (cosmetic-only rng — gameplay math reads none of it).
  Boulders are the one collidable addition; they may occasionally crowd a prompt — reroll by
  changing the depth seed constant in FloorBuilder if a floor comes out bad.

## Known shortcuts and trust boundaries

- **Character physics is client-owned** (standard Roblox humanoid networking). The server never
  trusts claimed values — it *measures* speed and position from the replicated character — but a
  speed-hacking client would still move fast (and pay proportional drain). Real mitigation
  (server-side movement validation) is a later hardening pass.
- **Dodge velocity is applied client-side** after server approval/charge (physics ownership).
- **Threat obstacle handling is a single raycast** — a blocked move stops and rethinks. Threats
  don't path around walls; rooms are open enough that it reads fine in grey-box.
- **All floors are physically live at once** (stacked 80 studs apart). Threat budgets are small;
  no culling. Fine at slice scale.
- **Draft zones have a faint visible haze slab** so placement is verifiable in grey-box. Delete
  the visual in FloorBuilder when audio/VFX take over readability.
- **Wax-type pickups and consumables are not placed** — profiles are live in the math (a
  `state.waxTypeId` write is all a pickup needs), but no loot spawns in floors yet.
- **Lit braziers don't join the light field** (visual glow only). Trivial to add in
  LightSources if the party using ignited braziers as safe light is wanted.
- **Persistence is the in-memory stub**: currency accrues per server session and vanishes on
  restart. ProfileStore swap = one file.
- **No sound.** DESIGN §20 calls audio the top risk; nothing here addresses it.

## Manual test script (gameplay verification is on you)

Setup: `rojo serve` + Studio with the place from `rojo build`. For two-player tests use
Studio's Test tab → Clients and Servers → 2 players.

**A. Core loop (solo, 5 min)**
1. Play. After the 5s countdown you spawn in a dark room holding a lit candle. Look down — you
   see your own cylinder body.
2. Scroll the wheel / drag the right-edge slider: light radius visibly grows and shrinks; the
   left wax bar drains faster at high dial. Snap points tick at 25/50/75%.
3. Hold Shift and run: bar drains faster than standing. Q dodges (burst + small wax dip),
   C slides (speed burst + dip). Both respect cooldowns.
4. Walk around: faint drips appear behind you and fade on a timer.
5. Stand still at ~40% dial for a minute: the body visibly shortens as wax falls.

**B. Threats (solo)**
6. Find a dark-hunter (black silhouette): stand bright near it — it keeps distance or flees.
   Dial to minimum — it approaches; contact drains wax fast (bar, not health).
7. Press 2 (FLARE) as it closes: it breaks off. Cost is visible on the bar.
8. Find a Moth/Swarm: burn bright — it comes to you. Press 1 (SNUFF): screen goes near-black,
   it loses you. Press 1 again after ~1.5s to relight.
9. With a drawn chasing: press 3 (CAST) — the blob lands ahead and the drawn diverts to it
   until it burns out (~6s).

**C. Hazards (the important one)**
10. Doorway with haze = draft: stand lit in it — extra drain, and after ~4s your flame snuffs
    (screen dark, you're incapacitated — solo this becomes terminal in 20s; that's correct).
    Repeat holding 4 (CUP): slow, near-dark, but the draft cannot touch you.
11. Flooded Hall at high wax (tall body): wade in — rapid drain while wading, survivable. Now
    return below ~half wax (short body): the same water kills you instantly. This shrink
    interaction is the mechanic to feel — it's pure numbers, no trigger.

**D. Basin, brazier, descent (solo)**
12. In the safe amber-floored room, hold the Basin prompt: three private offers with real wax
    numbers. Choose one (tap or 1/2/3). Bar rises; the loss is live (capped dial ceiling /
    no slide / no drips…). Re-prompting says the Basin is spent for this floor.
13. Stand at the brazier pedestal: bottom text shows the live formula
    (wax × depth × group = total). Hold to commit: results text, reward paid, candle freezes.
14. Or step on the dark pad in the Basin room: you drop to Floor 2 ("Floor 2" flashes).
    Deeper floors have more threats and pay more.
15. Die or cash out: after 15s the world rebuilds and a fresh run counts down.

**E. Two clients**
16. Both spawn into the same run. Each sees the other's candle height ≈ their wax (party state
    with no UI).
17. Player A stands in a draft until snuffed. B walks over, holds "Relight": B's bar drops by
    0.15, A's flame returns. (A's bar was grey while down.)
18. A takes "Never be relit" at a Basin, then snuffs in a draft: A dies outright — correct.
19. Both stand at one brazier: preview shows group ×1.25 for each. One commits alone on a later
    run to compare. The other's run continues after A cashes out.
20. A burns out fully: A becomes a faint blue wisp that can drift with B and sheds dim light;
    after 2 min it goes still.

**Regression sweep:** dial cap after CapMaxBrightness sacrifice (slider springs back to the cap) ·
dodge unavailable mid-cooldown · Cast aim clamped (try casting at a far wall — it lands ≤ 25
studs away) · SNUFF costs nothing · tools rejected while snuffed.

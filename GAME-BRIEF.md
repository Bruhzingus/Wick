# WICK — Complete Game Brief

**Purpose of this document.** A self-contained handoff for an AI model (or a new human collaborator)
who has never seen this project, written so that a productive conversation about *game design ideas*
can start immediately. It describes what the game is, how every system actually works, what is
already built, what is deliberately forbidden, and where new ideas are genuinely wanted.

It is a *summary*, not authority. Authority lives in `DESIGN.md` (product), `ARCHITECTURE.md`
(engineering rules), `TUNING.md` (every number), `CodeBreakdown.md` (file ownership), and
`IMPLEMENTATION-ROADMAP.md` (build status). Where this brief and those disagree, they win.

- **Platform:** Roblox
- **Genre:** Co-op horror dungeon crawler / roguelite, first-person, no combat
- **Team:** Solo developer, AI-assisted
- **Status:** Grey-box prototype, implemented through "Phase 5" — the full loop is playable but
  unpolished, unverified in a published live server, and largely without production art or audio.
- **Party size:** 1–4. Solo is a first-class supported mode, not a test config.
- **Target run length:** 10–20 minutes.

---

## 1. The pitch

> You play as a living candle descending into caves that have been dark for a very long time. Your
> health, your light, your fuel, and your clock are all the same thing: your wax. Every second you
> are lit, you are dying. The game is about what you choose to spend yourself on.
>
> You go down to bring light back. The deeper you go, the more it's worth. The less of you there is
> left.

**Structural reference:** Lethal Company — expedition-based, escalating danger, leave whenever you
want, risk/reward on the way out.
**Tonal reference:** a candlelit ghost story.
**Tone target:** *genuinely frightening.* Not tense-but-safe, not melancholy. Dread, hostility, and
real fear. First-person and near-total darkness serve this directly.

It is **not** an action game and there is **no combat**. You cannot kill anything, ever.

---

## 2. The five design pillars

Every proposal gets tested against these. If an idea violates one, either the idea is wrong or the
pillar is wrong — decide which, don't quietly ignore it.

1. **One resource, four meanings.** Wax is health, light, fuel, and timer simultaneously. Never add
   a second core meter.
2. **You cannot win a fight.** Threats are read and managed, never defeated. Powerlessness against
   enemies, agency over yourself.
3. **Every cost is paid in wax.** Tools, revives, mistakes, sacrifices. You fight by spending
   yourself.
4. **Content is combinatorial, never authored.** Small pools plus combination rules — no hand-built
   levels, no scripted set pieces.
5. **Legibility over fidelity.** Darkness, silhouette, flat readable shapes. The art constraint *is*
   the style, not a budget apology.

---

## 3. The core resource: wax

One meter. Four simultaneous meanings:

| Meaning | How it manifests |
|---|---|
| **Health** | Damage removes wax |
| **Light** | Burning is what illuminates the world |
| **Fuel** | Drains continuously just from being lit |
| **Clock** | When it hits zero, your run is over |

Because one meter does four jobs, every action trades against every other action. Spending wax on a
tool is spending health. Burning bright to see is spending time. There is no stamina, no mana, no
separate torch fuel, and there never will be.

**How the player reads their own wax (first-person):**
- **A stylized wax-column HUD bar** — a melt line, not a generic RPG health bar. It has its own tiny
  procedural flame that brightens with burn intensity and reddens at critical wax.
- **Your light radius shrinks as you burn.** The world literally closes in around you. This is the
  most important felt signal in the game.
- **Looking down shows your own candle body**, lower and lower as the run goes on.
- **Other players' bodies visibly shrink**, so party state is readable at a glance with zero UI.

**The shrink rule (single most important derived formula):**
`bodyHeight = 0.8 + 3.2 × waxFraction` — 4.0 studs at full wax, 0.8 studs near burnout. This is one
pure function (`Logic/CandleGeometry`) and it is what makes the water mechanic work (§8).

**Key numbers:** starting wax 1.3 (= max), idle drain 0.00025/s, burn drain 0.0018/s at burnRate 1
scaled by an exponent of 1.5, movement drain 0.001/s walking and 0.004/s running (× a global 0.25
multiplier). Every wax number is server-authoritative. (Phase 2, "wax pacing correction," cut idle/
burn/movement roughly in half-to-60% and removed the per-cave-tier drain multiplier below — see
TUNING.md's "wax pacing budget model" for the full derivation.)

---

## 4. The brightness dial — the primary verb

The player continuously controls burn intensity. With no combat, this *is* the game's main verb.

- **High:** large light radius, threats visible early, rapid consumption, loud to the Drawn
- **Low:** near-blind, minimal consumption, long survival, invisible to the Drawn but exposed to
  dark-hunters

**The dial deliberately owns only a useful middle band** — it runs 0.18 to 0.78, not 0 to 1. Its low
end is still visibly lit; its high end is still an ordinary open flame. Neither end is a hard enemy
counter. **CUP owns near-darkness. FLARE owns overwhelming panic light.** This split is intentional:
it stops the dial from becoming a two-position "enemy off switch."

Light range 10→30 studs, brightness 0.9→2.6, threat-field intensity 0.18→0.42 across the dial.

**Controls, mobile-first:** an on-screen draggable vertical slider with gentle snap points at .3/.5/
.7; desktop also gets the scroll wheel. Granularity is where skill lives in a game that deliberately
removed execution skill — *knowing this corridor needs 40% and not 60% is the ceiling.* But input
must never demand precision a thumb can't deliver.

---

## 5. Movement

**Run and a small hop. That is the complete moveset.** Walk 8 studs/s, run 16, hop power 30.

This is a deliberate reduction (the developer's previous project had deep first-person movement tech;
it is explicitly not carried over). Rationale: skill belongs in *decisions*, not execution; Roblox is
mobile-majority; a candle should not feel athletic.

- **Movement costs wax**, a small amount, so speed is a considered purchase rather than a punishment
  for walking around.
- **The hop is terrain recovery, not movement tech** — enough to clear a crevice or terrain seam,
  never enough to support precision platforming. There is no fall damage.
- **Default running is presented as strain, not power.** FOV widens slightly (74→85), periphery darkens and
  shimmers, camera destabilizes, the flame stretches taller/narrower and leans back ~10°, and wax
  drops fall denser. All of it stays at the edge of conscious notice: desperate combustion, never
  arcade speed lines.

---

## 6. Tools, not combat

Three tools. Each helps against one threat category and **hurts** against the other. There is never a
correct answer — only a read of the room. Tools work by editing a single shared light field; there
are zero per-tool behavior branches in the enemy code.

**No tool extinguishes your own flame.** CUP is the go-dark action: it covers the light the flame
throws instead of killing it, so darkness is a held state with ongoing upkeep rather than a toggle
you have to undo. Going out is something the world does to you.

| Tool | Cost | Effect | Helps vs | Hurts vs |
|---|---|---|---|---|
| **FLARE** | 0.13 wax (10% of a candle), no cooldown | A burst of panic light (intensity 3, brightness 6, range 60, 1.5s) | Dark-hunters recoil and stay blinded ~2s after retreating; interrupts a VoidFly dive | The Drawn come straight at you |
| **DECOY** | 0.04 wax permanently, 3s cooldown | Throw a lump of your wax to burn on the ground for 6s (server-validated parabolic throw, max 25 studs) | The Drawn go to it instead of you | Useless against dark-hunters — they ignore decoys entirely |
| **CUP** | 0.005 wax **per second held**, no cooldown | Shield the flame: light × 0.035, speed × 0.5. The only way to go dark; the flame stays lit | Near-invisible to the Drawn | Blind, slow, in dark-hunter territory. Doesn't hide you from a teammate's uncovered flame |

**Why tools rather than combat:** full combat is thematically incoherent and dissolves the threat
taxonomy — if enemies can be killed, the dark-hunter/drawn distinction stops mattering and the
brightness dial degrades to a lighting preference. It also drags in animation, hit feedback, and
weapon balance: the two weakest axes on a solo project. Pure avoidance risks powerlessness fatigue.
Tools give agency without violence.

Found consumables can grant free Flare/Decoy charges, which run through the exact same validation
and cooldown path — they are activations, not a second inventory.

---

## 7. The enemies

### The two categories — the core tension generator

**These exist so there is never a dominant strategy.** Every room is a read on which category you
face. Getting it wrong is fatal in either direction. This must not be diluted.

**DARK-HUNTERS** — live in the black, avoid flame. They come for you when you are *dark*.
- Ordinary brightness changes whether they hunt or stalk, but **cannot force them away.** Only FLARE
  (panic light) triggers a retreat.
- Most drain wax on contact. They follow your physical wax-drop trail as breadcrumbs.
- **Visual:** near-black (RGB 5,3,7), gaunt, *connected one-piece* humanoid silhouettes, deliberately
  hard to resolve even in direct light. The only feature visible at range is a pair of narrow angled
  **deep-crimson eye slits** (RGB 128,0,7) — the warning you get before the body is ever confirmed.

**THE DRAWN** — moth logic. They come *toward* light. Burning bright kills you; darkness hides you.
- **Visual:** neutral stone/taupe bodies (RGB 48,45,44) with broad, pale, translucent layered moth
  wings that dominate the silhouette. Wings must read first, never collapsing to a thin shape.
- **Eyes:** faint warm **yellow** (255,214,120), brightening toward near-white-yellow as the moth is
  actively drawn in. Yellow vs. crimson is the family tell and the two must never be confusable.
- Idle moths perch on cave walls rather than drifting across the floor; a perched moth cannot drain
  you, but any light it can sense pulls it straight off the stone.

### The eight shipped threat rows

| Threat | Category | Speed | Detect | Light response | Wax dmg/s | Notes |
|---|---|---|---|---|---|---|
| **Lurker** | DarkHunter | 8 | 18 | −1.0 | 0.05 | The common prowling form |
| **Stalker** | DarkHunter | 11 | 24 | −0.6 | 0.08 | Fast; keeps distance at medium light |
| **Hollow** | DarkHunter | 5.5 | 30 | −0.8 | 0.06 | Slow, broad, heavy drainer; largest |
| **VoidFly** | DarkHunter | 7 | 16 | −1.0 | staged | See below |
| **Moth** | Drawn | 9 | 30 | +1.0 | 0.04 | The common moth |
| **Swarm** | Drawn | 6.5 | 22 | +0.7 | 0.10 | Slow cluster, heavy drain |
| **Ash Moth** | Drawn | 8.5 | 38 | +1.2 | 0.025 | Smaller, quicker, paler, deep floors |
| **Snuffer** | Drawn | 5 | 26 | +0.75 | **0** | Visually identical to a moth — **extinguishes on contact instead of draining.** A completely different threat to read |

`lightResponse` sign is the whole system: negative = repelled, positive = attracted, magnitude =
sensitivity. Adding a threat is one config row, never a new class.

**Threat behavior states:** roam / hunt / stalk / retreat / ambush, all in one generic pure brain
(`Logic/ThreatBrain`). Hunters take you below light 0.15; only a local Flare contribution above 0.45
forces retreat. Threats route through real doorways via a room graph, follow the ground contour,
sidestep rock formations, avoid water pools, and are excluded entirely from the Basin.

### VOIDFLY — the positional exception

A tiny territorial dark-hunter that clings to **one fixed patch of ceiling** (5-stud patrol, 9-stud
activation, 15-stud hard territory boundary). It does not patrol the cave or start a long chase.
Walking beneath it triggers repeated low-damage dives — **four strikes at 0.012 wax, roughly 0.8s
apart, and the fourth snuffs your candle.**

- **The brightness dial cannot repel it.** Ordinary max burn does nothing.
- **FLARE** immediately burns it off an active dive, clears the accumulated strike count, and drives
  it back 13 studs for 5 seconds.
- **A nearby teammate does the same thing.** This is the game's clearest cooperative counter.
- Neither effect damages it. It is never killed.
- It only spawns under roofs ≤30 studs so its audio/visual tell stays in range, and it broadcasts a
  quiet, wall-occluded spatial buzz every 9–20 seconds.
- Visually: a compact, near-black, insect/bat-proportioned dark-hunter about 1/3 the size of the
  ground crawlers, with small translucent grey-violet wings.

---

## 8. Environmental threats

**Design note: environmental threats avoid pathfinding and combat AI and should carry a large share
of the difficulty. Prefer them over new enemy types** — while preserving clear physical warnings,
safe routing, and room-level rarity.

### WATER — depth-based, and the best emergent mechanic in the game

- Wading through shallow water **degrades wax rapidly** (0.2/s) — survivable, costly.
- Water reaching **the flame at the top of your model** is an **instant, terminal kill** (straight to
  wisp, no rescue window).
- **Because your model shrinks as you burn, water that was safe to wade at the start of a run becomes
  lethal later. The route you took in is not the route you can take out.** This costs almost nothing
  to implement and produces genuine dread. Protect it.
- Water sits in **localized recessed pools**, never room-covering lakes. Dry rock always rings a
  pool; the bed slopes to a shallow bank. Three depths: Shallows 0.45, Flooded 1.2, Sump 2.0.
- Generation **guarantees a dry route from entry through the Brazier to the Basin**, so water is
  always a positioning risk and never a mandatory lethal gate.
- ~40% of floors are wet at all; a wet floor typically carries one pool.

### UNSTABLE DRIPSTONE — the rare warned one-shot hazard

Hanging ceiling formations that fall. Never an enemy, never combat.

- **Three variants**, all sharing one warning language: an asymmetric lean, a dry near-black
  fractured collar, and sparse falling dust that harmless dripstone never combines.
  - **Needle** — one narrow spire, 1.65s warning, 5-stud trigger, **20% max wax**
  - **Fork** — two-pronged split, 1.8s warning, 5.25-stud trigger, **35% max wax**
  - **Hammer** — heavy three-pronged, 2s warning, 5.5-stud trigger, **50% max wax**
- Entering the fixed trigger footprint **commits** the warning; it never cancels and the formation
  never homes, so a player can always escape the marked landing area. A runner can trigger one ahead
  of the party.
- **A candle already below 30% wax is snuffed outright instead of damaged** — a second mistake at low
  wax becomes a co-op emergency rather than a silent terminal drain.
- A survivor stays lit but drops to **42% output for 2 seconds**, and that suppression is
  server-owned, so rendered light and threat perception can never disagree.
- **The warning is entirely geological — no glow, no UI marker, no billboard.** Brightness changes
  how easily the tell is read; default running spends reaction distance. Neither secretly changes detection.
- Only placed in ordinary rooms with roofs ≤34 studs (a bright candle must be able to inspect it).
  Entry, Basin, and Brazier rooms are always protected, as are rooms holding a VoidFly or Snuffer.
- **Count per floor 1–10: 1, 2, 2, 4, 5, 7, 8, 10, 12, 15**, then capped by safety rules — no more
  than half of ordinary rooms may be dangerous, per-room caps of 1/2/3 by depth band, and unstable
  formations may never exceed 40% of the harmless ceiling-formation count. Failed placements reduce
  the count rather than relaxing safety.
- Floors 1–3 give a one-time bottom-screen hint the first time a formation falls near you.

### BURNING VINES — the dial as a key

Deep-floor doorway curtains that only clear when a candle is pushed to the top of its dial.

- First appear on **floor 5**; 1 curtain on floors 5–6, 2 on 7–8, 3 on 9–10.
- Require **96% of max burn rate** within 9 studs for **3.2 continuous seconds**. FLARE also burns
  them, but is never required.
- A Basin brightness cap (×0.6) can never qualify — which is exactly the point.
- **Two hard invariants enforced by the planner:** a vined doorway is never the only way into a room,
  and vines never sit on the guaranteed entry→Brazier→Basin route. So a player who capped their
  brightness at the Basin is inconvenienced, never locked out.
- The tension is real: burning at max brightness for 3.2 seconds in a deep cave is a loud, expensive,
  Drawn-attracting commitment.

### STONE WARDEN — a chasing golem

A rare, floor-scoped hazard, eligible from **floor 4**. A dormant rubble pile with a relic beside it
is spawned once per eligible floor. Touching the relic wakes it: a 4-second emergence, then a
`PathfindingService` chase of the nearest player. Contact is an **instant kill** (sets Humanoid health
to zero). It pauses when its target stops moving. **Leading it under a falling dripstone crown stuns
it for 15 seconds**, during which it cannot walk or kill — the one intended counterplay, and it exists
specifically to weaponize an existing environmental hazard rather than add combat.

It deliberately has **no relationship to the dial or the tool set** — unlike the two core threat
categories, there is no brightness read, no Flare/Cup/Decoy interaction, only positioning it
under a hazard. `DESIGN.md` flags this as a narrower, more purely pathfinding-driven relationship than
the rest of the threat suite, worth watching in playtesting rather than expanding into a second full
threat family. It is also the one system in the codebase written as loose `.lua` with hardcoded
values rather than strict Luau pulling from `shared/Config` — a known architectural exception, not a
Config change.

---

## 9. The drip trail

Moving leaves small, dull drops of cooled wax behind you (every 8 studs walking, 5.2 running, 24
points max, 35-second lifetime).

- **They never glow, never emit light, never use Neon, and never attract the Drawn.** They are inert
  physical evidence.
- **Navigation** — did I already come this way?
- **Exposure** — dark-hunters follow the physical breadcrumbs.
- You don't place it. You *are* it. An involuntary consequence of movement.
- In first person you must **look back** to see your own trail, which makes checking it a deliberate,
  vulnerable act. That's a feature.

---

## 10. Death, revival, and the wisp

Two death states, and the distinction matters:

**BURN OUT** — wax reached zero. Slow, visible, predictable. **Terminal. Not revivable.**
**SNUFFED** — extinguished by a threat (Snuffer, VoidFly, dripstone at low wax) while wax remained.
Sudden, situational. **Revivable within 20 seconds.**

- **Relighting:** a teammate relights you from their own flame — 8-stud reach, 1-second hold, and it
  **costs the reviver 0.15 wax personally.** Small enough that helping is the default, large enough
  to notice. Never paid from a shared pool.
- **MATCH** — a rare found consumable, **solo-only.** A solo candle snuffed while carrying one gets a
  self-relight prompt; using it consumes the Match. It never works in multiplayer and never revives a
  burned-out candle. (Without a Match, a solo snuff resolves immediately as terminal.)
- **Every snuff is world-inflicted.** Players have no action that puts their own flame out — CUP
  covers the light instead — so this state is never self-imposed and never self-reversible.
- **Snuffed players remain valid dark-hunter prey** (they are maximally dark). Deliberately brutal;
  flagged as tunable if it plays badly.

**When you burn out you become a WISP** — a ghost that stays with the party for 120 seconds, moves at
14 studs/s, and emits a small light (range 6, brightness 0.4). Death doesn't mean sitting out. **What
exactly a wisp should be able to do is still an open design question** (§17) — the constraint is that
it must be helpful enough to stay engaged without ever making burnout strategically desirable.

**REMAINS:** a terminal death deposits 50% of the dead candle's remaining wax as a recoverable pool
on a later floor. It emits light (and therefore attracts the Drawn). Recovery is atomic and capped at
the collector's capacity, preserving the overflow. The owner may not reclaim their own. Remains
persist only inside that one server session.

---

## 11. The Basin — the sacrifice ritual

A still chamber between floors containing raw molten wax. **The one guaranteed-safe room per floor** —
no threats, no hazards, excluded from threat perception and navigation entirely. It also holds the
descent pad to the next floor.

**It gives you wax. The price is a permanent sacrifice for the rest of the run.**

This sets the run's rhythm: **tension → safety → weighty decision → tension.**

- **Every floor, guaranteed. Private** — each player sees only their own three offers.
- **Sacrifice pool:** maximum brightness capped (×0.6) · your drip trail · your ability to relight
  others · your ability to *be* relit · access to a specific tool · mild permanent perception
  impairments · the Basin's next price doubled. Sprint is not a sacrifice.
- **Grants a flat 0.20–0.35 wax at every depth.** The accumulating permanent losses are the scaling
  cost; a next-price penalty may reduce an offer but never below 0.20.

**Emergent specialization.** There is no class system and there will not be one. By floor 5 each
player has made four or five permanent sacrifices. One can't burn bright but moves fast. One is slow
and luminous. One can relight everyone but can't be relit. **The party discovered what it is by what
it gave up.** With the Basin private, players learn each other's states through play rather than by
comparing menus — the negotiation layer is deliberately absent for now.

---

## 12. The Brazier — ending a run

**Every floor has a brazier. Lighting it ends your run.** You pour what remains of yourself into it.

**No return trip. No backtracking. No escape sequence.** The run ends on a decision you made, not a
corridor you survived. (An extraction sequence is explicitly CUT.)

```
Reward = waxDelivered × depthMultiplier × (1 + 0.25 × additionalPlayersPresent)
                      × caveTierMultiplier × rewardPerWaxUnit
```

Depth multipliers, floors 1–10: **1, 1.5, 2.2, 3, 4, 5, 6.5, 8, 10, 12.5.** `rewardPerWaxUnit` is
1000. Group radius 12 studs, 1-second commit hold.

**The risk curve in one formula:**
- Stop shallow → lots of wax, small multiplier
- Push deep → big multiplier, little left to deliver
- Push too deep → burn out, deliver nothing

**Individual cash-out with a group bonus.** Any player may light a brazier and end **their own** run
at any time; the party continues without them. The bonus is a **multiplier, not a split pot** — a
divided fixed pot would mean fewer participants equals a bigger share, an incentive to ditch the
party right before the brazier. A multiplier means nobody's share shrinks when someone else arrives,
so everyone has a reason to wait for the straggler. Leaving is always available and always costs
something.

**Show the numbers.** A live preview updates 4× per second within 10 studs, so players can stand at
the floor-4 brazier with 55% wax and do real arithmetic about whether floor 5 is worth it. Legible
tension beats mysterious tension. *(Revisitable if it proves to break atmosphere.)*

---

## 13. The run loop, end to end

**1 — The Landing (hub).** A fixed mineshaft lobby built once at server boot, shown in **third person
with the player's real Roblox avatar.** It contains a spawn point, a placeholder shop stall, welcome
/how-to-play/standings boards (a cross-server deepest-floor leaderboard), and **three elevator
alcoves, one per cave tier.**

**2 — Party and tier.** Everyone in the server auto-joins one party, capped at 4. **The physical
elevators are the entire interaction:** standing in one is your readiness for that tier; the leader's
chosen elevator sets the party's tier; a leader-only lever starts the expedition. A tier nobody has
unlocked is locked out at the elevator.

**3 — The descent.** Pulling the lever closes the gate, swaps every committed rider into a full lit
candle, and enters first person. The elevator car physically descends 220 studs down a ribbed shaft
with a subtle mechanical camera tremor. **The ride *is* the loading screen**, not decoration over one
— one server timestamp is broadcast and every client evaluates the same curve locally, so there is no
replicated-CFrame judder. Ride candles spend no wax and never touch hazards or threat perception.

**4 — Floor 1.** A live server then teleports the party into a **reserved server** (Studio starts
locally instead). Players spawn in the entry room on separated slots, and the countdown ends.

**5 — Explore a floor.** Compact 64-stud cells favor a main chain with looped alternate connections.
Find the Brazier. Find
the Basin. Pick up 2–4 planned loot spawns tucked into wall pockets. Read every room: is the danger
here attracted to light or repelled by it? Watch the ceiling. Watch the water level against your own
shrinking body.

**6 — At the Brazier: decide.** Cash out now at this floor's multiplier, or push on with less wax.

**7 — At the Basin: pay.** Take wax, give up something permanent. Then step onto the descent pad —
**descent is per player, so the party can split across floors.**

**8 — Repeat** until you cash out, burn out, or get snuffed with nobody left to relight you. Floors
get bigger, threat budgets ramp (1 → 3.7, then multiplied by tier), enemies get deeper rows, dripstone
counts climb, vines appear on floor 5, the Stone Warden on floor 4.

**9 — Results.** A death breakdown by cause, or a payout breakdown. Then either an immediate replay
or a return to the hub with refreshed currency and unlocks.

---

## 14. Meta progression

**Core principle: reward DEPTH, not POWER.** If delivered wax buys a bigger starting pool, the game
gets easier every session and the tension curve flattens permanently. Buy *efficiency and access*
instead:

- **Cave access** — deeper, harder tiers unlock. **The primary progression axis** (Lethal Company
  model).
- Burn-rate reductions · Basin discounts · wax-type unlocks · starting tool charges · cosmetics.

**Every one lets the player go further, not hit harder. The game stays exactly as tense at the new
depth as at the old one, indefinitely.**

**The three cave tiers (fully implemented):**

| Tier | Cost | Max floors | Threat budget | Reward | Dripstone | Wax drain | Atmosphere |
|---|---|---|---|---|---|---|---|
| Shallows | 0 | 6 | ×0.6 | ×1.0 | ×1.0 | ×1.0 | lighter grey |
| Descent | 1,500 | 8 | ×1.1 | ×1.15 | ×1.2 | ×1.0 | mid |
| Deep | 6,000 | 10 | ×1.35 | ×1.5 | ×1.45 | ×1.0 | darkest |

Wax drain no longer varies by tier (Phase 2): a flat per-tier drain tax duplicated the difficulty
already coming from threat budget/dripstone/reward, without being something a player reads or
responds to. Tier difficulty is threat budget, dripstone density, reward, and floor count only.

Note the tier retints the global atmosphere — deeper tiers read as a visibly darker shade of cave.

**Wax types (in-run loot).** Found wax changes your burn profile for the rest of the run. Switching
mid-run is a real decision — go brighter and hungrier now that the multiplier is high?

| Type | Drain | Brightness | Attracts Drawn |
|---|---|---|---|
| Standard | 1.0 | 1.0 | yes |
| Beeswax | 0.8 | 0.85 | yes — slow, dim, efficient |
| Tallow | 1.3 | 1.3 | yes — fast, bright, hungry |
| **Cold wax** (rare) | 1.0 | 0.9 | **no — invisible to the Drawn, including your decoys** |

---

## 15. Art direction

**Budget: near zero. The constraint is the style.** What looks bad in games is *failed realism*, not
simplicity. Deliberate simplicity reads as intentional.

### Style laws (non-negotiable)
- **Light is the only source of visual information.** Nothing self-illuminates except fire, embers,
  and the candle's own wax.
- **Legibility over fidelity.** Flat, readable silhouettes. No surface noise or clutter competing
  with the outline.
- **Enemies are silhouettes, never fully rendered.** Identifiable by outline plus one or two light
  accents (eyes, wing edge) long before any surface detail resolves.
- **Environments are readable geometry, not decorated spaces.** Bare rock, water, and structural form
  — no props, no set dressing, no narrative clutter.
- **Color is almost exclusively warm firelight vs. cold stone.** Any other color is meaningful and
  rare, never decorative.

### Light logic
Strict first person, camera anchored just above the candle's own body. **One light source exists:
your own flame** — range 6–40 studs, brightness 0.5–4, both continuously tied to the dial.
`Lighting.Brightness`, `Ambient`, and `OutdoorAmbient` are forced to **zero** at runtime. Beyond the
flame's radius is true black. A very faint cool haze (RGB 158,168,189, density 0.18) sits at distance
so black doesn't read as a void — it's a horizon, not a light source.

Post-processing: restrained bloom on near-white highlights only (0.14 / threshold 0.92), a warm
grade (255,242,220), one soft spherical shadow following the flame. **No lens flares, no volumetric
shafts, no HDR glow.** The target is a real candle in a real dark room, not a fantasy glow.

The flame itself flickers with owner-seeded layered noise — slow fuel drift (0.48 Hz), body flutter
(3.15 Hz), fine turbulence (9.2 Hz), plus rare soft guttering that dips and warms. Never a mechanical
loop, never a strobe. It is deterministic and synchronized, so every player sees the same flame.

### Palette (pulled from shipped config, not aspiration)

| Group | Values |
|---|---|
| **Flame** | core 255,247,222 · mid 255,186,92 · outer 255,116,44 |
| **Ember / UI gold** | 255,150,66 · deep 190,84,38 · highlight 255,201,120 · danger red 255,92,60 |
| **Wax body** | 235,225,200 · deep shade 203,187,155 · rim 242,233,210 · wick 35,28,22 |
| **Drip trail** | 112,88,62 — dull matte brown, **never glowing, never Neon** |
| **Rock** | 52,56,66 / 62,66,78 / 45,49,59 / 70,73,84 — cool blue-charcoal slate. Materials: Slate, Basalt, Concrete, Rock. Matte, non-reflective |
| **Damp rock** | 28,31,39 |
| **Water** | 42,66,92 — dark teal-blue-grey, semi-transparent, faint sheen, no glow |
| **True black** | 9,8,10 |
| **Dark-hunter** | body 5,3,7 · eyes 128,0,7 |
| **The Drawn** | body 48,45,44 · thorax 67,62,59 · wings 112,106,101 @18% transparent · eyes 255,214,120 → 255,236,168 |
| **Dripstone** | collar 38,40,47 · crown 49,51,59 · **fracture lines 17,18,22 (the tell)** · dust 82,78,72 → 40,40,43 |
| **UI** | panel 18,15,18 · raised 27,22,25 · bronze stroke 120,96,66 · text 237,227,209 |

### The candle (player character)
**A short, stumpy, hand-dipped tallow candle — NOT tall and elegant.** Wide cylindrical body (radius
1.4), a melted drooping rim at the top (12% wider than the body), a short dark charred wick, one
modest elongated flame. Reads as humble and mortal, not decorative. Matte wax surface — it is *lit
by* its flame, it does not emit.

**Body height ranges 4.0 → 0.8 studs. The body height IS the health bar.** Always depict that
shrinking relationship when illustrating the game.

### The caves
Natural, irregular dark rock — **never decorated.** A cave family (Stone, Moss, Ice) tints the rock and changes how the floor generates; it never lights it and never dresses it. Floors are broad,
overlapping, ramped rock shelves that are genuinely climbed (7 attempted per room), not a flat plane
with props on it; only doorway lanes and interaction centers stay level. Ceilings are sealed inverted
Terrain height fields with broad rolling waves and smaller rock ripples that blend into walls and
door arches — never a flat slab. Rooms are 64-stud cells with ceilings from ~15 (tight crevice) to
~46 studs (tall cavern). **Every doorway is a rough, jagged rock-cut opening with a deterministic but
different width and height (8–56 wide, 8–13 tall)** — so doorway variance comes from the opening
itself, not decoration around a repeated rectangle.

### The logo
The **WICK** wordmark, composited from UI shapes: "W", "C", "K" in a gilded gold-to-ember gradient,
with the letter **"I" replaced by a live miniature candle glyph** complete with its own flickering
flame. The candle-as-letter motif is the game's core visual signature.

---

## 16. Audio

**Horror lives on audio, and it is the single largest risk in the project.** Darkness solves the
visual problem but *amplifies* the audio dependency — if you can't see, hearing does all the work.

Current state: menu and cave ambience tracks are uploaded and wired (a shuffled non-repeating bag
with 18–42s of silence before the first track and 10–24s between them, with 4/5s fades). Positional
cues exist for VoidFly buzz, dripstone fracture, dripstone impact, and ambient rockfall. **Most
one-shot cue rows are still unassigned.**

What needs to exist: quiet **positional creature audio that lets a blind player identify threat
direction and category by ear** — a dark-hunter must sound different from the Drawn. A constant low
bed of cave dread rather than silence. Restrained, natural stingers for tools, damage, and death that
don't undercut the quiet. Music sparse and infrequent, with long silent gaps, so it never competes
with the cues players actually need to survive. **Dread and hostility, not jump scares.**

---

## 17. Technical shape (enough to reason about feasibility)

- **Roblox: hub place + instanced expeditions.** Players gather in a hub, form a party, and
  `TeleportService` into a reserved server. Instances are disposable — no persistent world state.
  Persistence is player profiles only. **This is not an MMO and must never become one.**
- **Toolchain:** Rojo (filesystem ↔ Studio, the precondition for AI-assisted development), Git,
  strict Luau everywhere, Rokit, Wally, ProfileStore (never raw DataStore — session-lock failures
  cause duplication and rollback), a dependency-free deterministic test harness.
- **The one organizing idea:** pure rules in `shared/Logic` (no Instances, no services — testable
  cold), one thin authoritative server adapter per system, one thin client controller per input
  surface. Threat perception is a **single light-source list**, and every tool works by editing that
  list.
- **Entropy defense:** one responsibility per file · content lives in data, not code · pure logic
  separated from Roblox Instances · a living `ARCHITECTURE.md` read at the start of every session.
- **Authority:** every wax number is server-decided; clients send *requests* that are type-, NaN-,
  cooldown-, cost-, and sacrifice-validated. Character physics is client-owned (Roblox humanoid
  networking), with server-sampled positions for hazards/threats/water and correction of impossible
  sustained displacement. Every remote is rate-limited by a per-player token bucket.
- **Content is data:** adding a threat, sacrifice, wax type, room module, loot row, cave tier, or
  dripstone silhouette is *one config row*. If an idea would require a new class or a per-content
  branch in a service, the idea is probably shaped wrong for this codebase.
- **Floors are generated** by a seeded pure planner from weighted room modules with chain-biased,
  loop-seeking connections, then built as paired Terrain height fields (floor + inverted roof).
  Live runs construct the current floor and its successor on demand, with no floor cap. The planner
  guarantees the dry route, places pools/rises/dripstones/vines/threat offsets deterministically, and
  rolls each room's ceiling height — which biases threat selection (tall rooms favour moths, low
  rooms favour the VoidFly).

---

## 18. Where the ideas are actually wanted

### Genuinely open questions
- **Wisp capability** — what exactly can a burned-out player *do*? Must stay engaging without ever
  making burnout strategically desirable. This is the biggest unsolved design question.
- **Basin sacrifice pool weighting** — how fast should the exchange rate worsen?
- **Whether the reward numbers stay visible**, if legible arithmetic proves to break atmosphere.
- **Proximity voice chat** — core mechanic, supported, or absent?
- **Monetization** — cosmetics only, or cosmetics plus cave access?
- **Difficulty scaling with party size.**
- **Fiction** — why are the caves dark? What *are* candles? Possibly better left unexplained.

### Known risks worth attacking
1. **Sound design** — the weakest axis and the largest risk, amplified by the darkness.
2. **Pacing** — a game about burning slowly could read as tedious. Is the deeper/scarcer pacing dread
   or just walking time?
3. **Powerlessness fatigue** — tools mitigate it; watch for it anyway.
4. **Threat balance** — if one category is clearly more dangerous, players default to one brightness
   setting and the entire core tension collapses.
5. **First-person legibility** — near-darkness could tip from tense to frustrating. Watch whether
   players get *lost* rather than scared.
6. **Exploits** — wax is currency, so all wax math must stay server-authoritative.

### Live playtest questions
Does the dial create meaningful choices or does one setting dominate? Can players read a death
breakdown and name a better choice? Are silhouettes and audio readable without threat labels? Does
the Basin create a painful decision rather than a mandatory heal? Do wisps stay engaged? Can two
friends reliably form, teleport, cash out, restart, and retain progress?

---

## 19. The guardrails — check ideas against these first

### CUT — decided against, do not revisit without cause
Complementary sacrifices (cross-player Basin synergy) · **combat of any kind** · classes ·
extraction/escape sequence after lighting the brazier

### DEFERRED — real, but behind focused interfaces, not now
Lineage (carryover between candles) · contextual Basin offers (ability-usage tracking) · public Basin
· global cross-server brazier persistence · global/cross-server remains · full hub matchmaking, party
invites, multiple concurrent parties, disconnect/rejoin recovery

### NEVER
Crafting · trading · PvP · player housing · pets · dialogue trees · authored story · **multiple
cosmetic-only biome duplication** · **a second core resource** · guilds · seasonal content

> *The most common failure mode for solo projects is adding "just one more system" at 2am. This list
> exists to make that a conscious violation rather than a drift.*

---

## 20. Honest state of the build

**What is real and wired:** the entire loop above. Server-authoritative wax on a fixed tick,
shrinking rig, first-person camera, dial, all three tools, eight threat rows across both categories
plus VoidFly, water with the emergent shrink interaction, dripstone, vines, the Stone Warden, drip
trail, both death states, wisps, remains, loot, procedural Terrain floors, private Basin, brazier with
live arithmetic, results/replay, deterministic pure-rule tests, remote hardening and movement sanity,
ProfileStore progression, three cave tiers, and the physical elevator lobby with reserved-server
handoff. Vines and the Stone Warden (§8) are both settled parts of `DESIGN.md` §9.

**What is not:** live-server verification of teleports and durable profiles (Studio uses a local start
and an isolated mock profile) · most one-shot audio · production art (everything is procedural
grey-box geometry) · full matchmaking, invites, or rejoin recovery · Lineage (the only remaining
interface stub) · any monetization.

**One open design tension worth knowing about:** `DESIGN.md` itself flags the Stone Warden as having
a narrower relationship to the player than the two core threat categories — no dial or tool
interaction, only positioning it under a hazard — and asks that it be watched in playtesting rather
than grown into a second threat family. It is also the one system in the codebase written as loose
`.lua` with hardcoded values, outside the strict-Luau/Config architecture everything else follows.

---

## 21. Glossary

- **Wax** — the single resource: health, light, fuel, timer
- **Burn rate / the dial** — how hard you're burning, 0.18–0.78
- **The Basin** — the guaranteed-safe between-floor site of permanent sacrifice in exchange for wax
- **The Brazier** — end-of-run delivery point; lighting it cashes out and ends *your* run
- **Snuffed** — extinguished with wax remaining; revivable for 20s
- **Burn out** — wax exhausted; terminal; you become a wisp
- **Wisp** — a burned-out player, still mobile, still slightly useful
- **Remains** — the session-local recoverable wax pool a terminal death leaves behind
- **Dark-hunters** — threats that avoid light and drain wax on contact; only FLARE repels them
- **The Drawn** — moth-logic threats attracted to light
- **VoidFly** — territorial ceiling dark-hunter; four dives snuff you; FLARE or a teammate repels it
- **Snuffer** — a Drawn that extinguishes instead of draining; visually identical to a moth
- **Unstable dripstone** — the rare, warned, one-shot ceiling hazard
- **Vines** — deep-floor doorway curtains that only full brightness can burn through
- **Stone Warden** — relic-triggered chasing golem, stunned by a falling dripstone crown
- **FLARE / DECOY / CUP** — the three tools; CUP is the only way to go dark
- **The Landing** — the physical mineshaft hub lobby
- **Cave tier** — Shallows / Descent / Deep; the primary meta-progression axis
- **Lineage** *(deferred)* — meta-progression carryover between candles

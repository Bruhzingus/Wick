# WICK — Design Document

**Status:** Grey-box public-playtest prototype implemented through Phase 5. Core design settled.
**Platform:** Roblox
**Genre:** Co-op horror dungeon crawler / roguelite
**Team:** Solo developer, AI-assisted
**Last updated:** July 2026

> **Implementation status.** The original vertical slice is built, and the prototype now also
> includes deterministic tests, feel/audio plumbing, run-variety content, server hardening,
> ProfileStore-backed progression, cave tiers, and a minimal one-party lobby/reserved-server
> handoff. These additions do not change the settled design pillars below. See
> `IMPLEMENTATION-ROADMAP.md` for exact phase status and prototype limitations.

> **How to use this document.** This is a complete handoff. It contains every settled decision, the reasoning behind each, what has been explicitly cut or deferred and why, and what remains open. If you are picking this up with no prior context, everything you need is here.
>
> **Sections 1–15 are settled.** Do not re-litigate without a specific reason. Section 20 lists
> what remains open. Section 21 records the completed original vertical-slice target;
> `IMPLEMENTATION-ROADMAP.md` records current implementation status.

---

## 1. The pitch

**You play as a living candle descending into caves that have been dark for a very long time. Your health, your light, your fuel, and your clock are all the same thing: your wax. Every second you are lit, you are dying. The game is about what you choose to spend yourself on.**

You go down to bring light back. The deeper you go, the more it's worth. The less of you there is left.

**Positioning:** co-op horror with roguelite structure. Structural reference is Lethal Company — expedition-based, escalating danger, leave whenever you want, risk/reward on the way out. Tonal reference is a candlelit ghost story.

**Tone: genuinely frightening.** Not tense-but-safe, not melancholy. Dread, hostility, and real fear are the target. First-person camera and near-total darkness serve this directly.

It is **not** an action game and there is **no combat**.

---

## 2. Design pillars

Every decision gets tested against these. If a proposed feature violates one, either the feature is wrong or the pillar is wrong — decide which, don't ignore it.

1. **One resource, four meanings.** Wax is health, light, fuel, and timer simultaneously. Never add a second core meter.
2. **You cannot win a fight.** Threats are read and managed, never defeated. Powerlessness against enemies, agency over yourself.
3. **Every cost is paid in wax.** Tools, revives, mistakes, sacrifices. You fight by spending yourself.
4. **Content is combinatorial, never authored.** Small pools plus combination rules.
5. **Legibility over fidelity.** Darkness, silhouette, flat readable shapes. The art constraint is the style.

---

## 3. The core resource: wax

A single meter. Four meanings at once:

- **Health** — damage removes wax
- **Light** — burning is what illuminates the world
- **Fuel** — drains continuously just from being lit
- **Clock** — when it's gone, the run is over

Because one meter does four jobs, every action trades against every other action. Spending wax on a tool is spending health. Burning bright to see is spending time. There is no separate stamina, mana, or torch resource, and there never will be.

### How the player reads it

**Camera is first-person.** This is settled, and it changes how wax is communicated.

- **A stylized numeric bar.** Diegetic in feel — a wax level, a melt line — not a generic RPG health bar. This is the primary readout since you cannot see your own body from outside.
- **Your light radius shrinks as you burn.** The world literally closes in around you. This is the most important felt signal and it costs nothing to implement.
- **You can see your own candle body by looking down.** Lower and lower as the run goes on.
- **Other players' bodies visibly shrink.** Party wax state remains readable at a glance without UI, which is what matters for co-op.

**Note on the trade:** an earlier version used third-person specifically so players would watch themselves shrink. First-person loses that external view but gains claustrophobia and fear, which serve the "genuinely frightening" target far better. The shrinking light radius carries most of the emotional weight the shrinking model would have.

---

## 4. The brightness dial

The player controls burn intensity — the spine of the game and, given there is no combat, effectively the primary verb.

- **High:** large light radius, threats visible early, rapid consumption
- **Low:** near-blind, minimal consumption, long survival

The dial deliberately owns a useful middle band rather than the full lighting extremes. Its low
end remains visibly lit and its high end remains an ordinary open flame: both still change map
visibility, wax drain, Drawn attraction, and how dark-hunters read the player, but neither is a
hard enemy counter. CUP owns near-darkness; FLARE owns overwhelming panic light.

**Continuous value internally, with a control scheme built for touch first:**

- **Mobile:** an on-screen vertical slider at the screen edge, draggable with a thumb, with light snap points so precise dragging isn't required
- **Desktop:** scroll wheel, plus the same slider

Granularity is where skill lives in a game that has deliberately removed execution-based skill. Knowing this corridor needs 40% and not 60% *is* the ceiling. But the input must never demand precision that a thumb can't deliver.

---

## 5. Movement

**Run and a small hop.** That is the complete moveset.

A deliberate reduction. The developer's previous project has a deep first-person movement system — wall-running, stamina, boost chaining — and that depth is **explicitly not carried over.**

**Rationale:**
- Skill belongs in *decisions* (when to push, when to burn bright, when to turn back), not execution
- Roblox is mobile-majority; precision movement is the biggest ceiling on reach
- A candle should not feel athletic
- This is a separate project, not a reskin

**Movement costs wax — a small amount.** Moving fast burns faster than standing still. Tunable, and deliberately kept small: this exists to make speed a considered purchase, not to punish walking around.

**The hop is terrain recovery, not movement tech.** It is deliberately low: enough to clear a
small crevice, crack, or terrain seam that could otherwise trap the player, but not enough to make
the candle feel athletic or create a precision-platforming layer.

**Sprint presentation is strain, not power.** Entering a real run gently widens the first-person
view while the periphery darkens and shimmers, the camera becomes slightly unstable, the flame
flickers faster and leans backward, and wax drops become denser. These effects must remain at the
edge of conscious notice: desperate candle combustion, never arcade speed lines or a superhero
boost. Stopping returns smoothly to the normal view.

---

## 6. Tools, not combat

**There is no combat.** You cannot kill anything. Tools spend wax to change what threats *do*.

Every tool helps against one threat category and hurts against the other. There is never a correct answer, only a read.

**No tool puts your flame out.** Going dark is CUP's job: it covers the light rather than killing
the flame, so darkness is always a held, reversible state you pay upkeep for. Being extinguished is
something the world does to you (§7), never something you choose.

**FLARE** — a burst of brightness. Expensive, with no cooldown; every repeated use pays in wax.
→ Dark-hunters recoil and remain briefly blinded after retreating. The drawn come straight at you.

**DECOY** — throw a lump of your wax to burn on the ground as a decoy. Costs wax permanently.
→ The drawn go to it instead of you until it burns out. Useless against dark-hunters.

**CUP** — shield the flame with your hands: the game's only way to go dark. Move slowly, shed
almost no light, and keep paying upkeep for as long as you hold it. No cooldown.
→ The drawn barely notice you and dark-hunters gain the space, but you are near-blind and the
flame keeps burning. Cupping suppresses only your own emitted
light: standing inside a nearby teammate's uncovered flame still makes you illuminated.

FLARE and CUP show an active marker in the control hotbar while their effect is live.

**Why tools rather than combat or pure avoidance:** full combat is thematically incoherent and dissolves the threat taxonomy — if enemies can be killed, the dark-hunter/drawn distinction stops mattering and the brightness dial degrades to a lighting preference. It also drags in animation, hit feedback, and weapon balance: content volume and art, the two weakest axes here. Pure avoidance risks powerlessness fatigue. Tools give agency without violence.

---

## 7. Death and revival

**BURN OUT** — wax reached zero. Slow, visible, predictable. **Terminal.** Not revivable.

**SNUFFED** — extinguished by a threat while wax remained. Sudden, situational. **Revivable.**

**Relighting:** a teammate relights a snuffed player from their own flame at a **small wax cost to the reviver.** Small enough that helping is the default, large enough to notice. The cost is paid by the reviver personally, never from a shared pool.

**MATCH** â€” a rare found consumable for a **solo run only**. If a solo candle is snuffed while carrying one, it receives a prompt to relight itself; doing so consumes the Match. It never enables a self-revive in a multiplayer expedition, and it cannot revive a burned-out candle.

**When you burn out mid-run:** you become a **wisp** — a ghost that remains with the party and can still do something slightly useful. Exact capability is open (see §20), but the intent is that death doesn't mean sitting out, and the wisp should be helpful enough to stay engaged without being a strategy.

---

## 8. The drip trail

Moving leaves small, dull drops of wax behind you. They do not glow, illuminate the cave, or
attract the Drawn.

- **Navigation** — did I already come this way?
- **Exposure** — dark-hunters can follow the physical breadcrumbs.

You don't place it. You *are* it. An involuntary consequence of movement.

**First-person note:** you have to look back to see your own trail, which makes checking it a deliberate, vulnerable act. That's a feature.

---

## 9. Threat taxonomy

### The two categories

**DARK-HUNTERS** — live in the black, avoid flame. Ordinary brightness changes whether they hunt
or stalk but cannot force them away; FLARE is the deliberate retreat counter. Cupping the flame
puts you in their territory.
At the lower end of the ordinary dial they commit to an attack without requiring Cup. In the
middle band they hold their distance while watched, but slowly close to attack when outside the
player's view; turning back toward one forces it to give up that approach. Bright ordinary flame
still buys space rather than a hard retreat.
Most attack and drain wax on contact. The VoidFly is the positional exception: it makes several
small attacks before it can snuff a candle. FLARE immediately burns it off an active dive and
clears its accumulated attack sequence; a nearby teammate also drives it off. Neither effect
damages or kills it.
Their bodies are connected near-black, gaunt humanoid silhouettes that are intentionally difficult
to resolve at range. Paired angled deep-crimson eye slits are the distant warning; their short eye
glow must not reveal the full body.

**THE DRAWN** — moth logic. They come *toward* light. Burning bright kills you. Darkness hides you.
Their models use neutral stone/taupe bodies and layered moth wings, readable without competing
with flame, water, wind, or hunter-eye colors. A faint yellow eye-glow — distinct from a
dark-hunter's crimson — is the readable tell for how strongly one is currently drawn in: dim at
rest, brighter as it closes.

These exist so there is **never a dominant strategy.** Every room is a read on which category you face. Getting it wrong is fatal in either direction. This is the core tension generator and must not be diluted.

### Environmental threats

**WATER** — depth-based, not binary:
- Wading through shallow water **degrades wax rapidly** — survivable, costly
- Water reaching **the flame at the top of your model** is an **instant kill**
- Water collects in localized recessed pools and puddles rather than covering an entire room.
  Dry rock must remain around every pool, with a traversable submerged bank so water is dangerous
  because of candle height and positioning—not because the player is physically softlocked.

**The emergent interaction here is the best mechanic in this section and should be protected:** because your model shrinks as you burn, water that was safe to wade at the start of a run becomes lethal later. The route you took in is not the route you can take out. This costs almost nothing to implement and produces genuine dread.

**SNUFFERS** — deal no damage; they extinguish you outright. A completely different threat to read.

**VOIDFLY** — a tiny territorial dark-hunter that circles one fixed patch of ceiling. It does not
patrol the cave or begin a long chase. Walking beneath it causes repeated low-damage dives; several
uninterrupted attacks can snuff the candle. A FLARE interrupts a close approach or active attack
and frightens it away temporarily; bringing a teammate close does the same. The ordinary
brightness dial cannot repel it. Avoidance is positioning and cooperation, never combat.

**UNSTABLE DRIPSTONE** — a rare one-shot environmental hazard, never an enemy or combat encounter.
Dangerous formations appear only in ordinary rooms whose nominal ceiling is no higher than 34
studs, where a bright candle can reasonably inspect the roof. Entry, Basin, and Brazier rooms are
always protected, as are rooms assigned a VoidFly or Snuffer. The cave therefore asks the player to
look up without hiding unavoidable damage above the useful light range.

The learnable warning is geological rather than UI: Needle, Fork, and Hammer formations all share
an asymmetric lean, a dry nearly-black fractured collar, and sparse falling dust that harmless
dripstone does not combine. Entering the fixed trigger footprint commits a 1.65 / 1.8 / 2-second
wobble-and-fracture warning, followed by a deterministic vertical fall. The formation never homes
and the warning never cancels, so players can avoid the marked landing area; a runner can also
trigger it ahead of teammates. Brightness changes how easily the physical tell can be read, and
sprinting consumes reaction distance, but neither secretly changes detection.

An impact removes 20% / 35% / 50% of maximum wax by Needle / Fork / Hammer variant. A candle
already below 30% wax is snuffed outright instead, making a second mistake at low wax a co-op
emergency rather than a silent terminal drain. A surviving candle remains lit but its output drops
to 42% for two seconds; rendered light and threat perception use that same server-owned
suppression, so the partial snuff cannot disagree with enemy behaviour. Nearby players receive a
stone impact, dust/debris, shake, brief darkening, and violent flame flicker. Every player still
inside the shared impact footprint is hit independently in multiplayer. On Floors 1–3, each player
near their first falling formation receives a bottom-screen reminder to read the fractured collar
and falling dust, then leave the ground beneath it before the formation falls—whether or not they
are hit.

The uncapped target is `round(1 + 0.5 × (depth − 1))` on Floors 1–3,
`round(4 × 1.3^(depth − 4))` on Floors 4–6, and `round(7 × 1.2^(depth − 6))` on Floors 7+.
That produces **1, 2, 2, 4, 5, 7, 8, 10, 12, 15** for Floors 1–10. Placement then preserves
uncertainty: no more than half of ordinary rooms may be dangerous; one formation per room is
allowed on Floors 1–3, two on Floors 4–6, and three on Floors 7+; total unstable formations may
not exceed 40% of the total harmless ceiling-formation count. Failed safe placements reduce the
result rather than relaxing doorway, spacing, roof-visibility, or harmless-majority rules.

**Design note:** environmental threats avoid pathfinding and combat AI and should carry a large
share of difficulty. Prefer them over new enemy types, while preserving clear physical warnings,
safe routing, and room-level rarity.

**BURNING VINES** — a deep-floor doorway curtain that only opens for a candle pushed to the top of
its dial. First eligible on Floor 5 (1 curtain on Floors 5–6, 2 on 7–8, 3 on 9–10). A curtain catches
after ~96% of max burn rate (or a Flare) is held within 9 studs for ~1.1 continuous seconds; cupping
never counts, whatever the dial reads underneath it. Once alight it needs no one standing there: the
fire eats the whole curtain over ~2.6 seconds and throws to any other curtain within 30 studs, which
catches in turn — the growth on a floor is one connected thing, so taking a section takes the run of
it. This turns the ordinary brightness dial into a rare, deliberate key rather than only a
lighting/exposure trade — opening the dial wide in a deep cave is loud, expensive, and pulls the
Drawn, and a spreading fire is louder still.

Two invariants are enforced by the floor planner itself, not by convention: a vined doorway is never
a room's only entrance, and vines never sit on the guaranteed entry → Brazier → Basin route. A player
whose ceiling was capped at the Basin, or who sacrificed Flare, can always reach everything a vine
guards by another route — vines inconvenience, they never lock a Basin sacrifice out of content.

**THE STONE WARDEN** — a rare, floor-scoped chase encounter, eligible from Floor 4. When selected,
the planner adds one optional, normal-looking weathered chamber whose flat encounter pads and nearby
unstable-dripstone crown guarantee the encounter can physically function. A dormant rubble pile sits
beside a relic; touching the relic wakes it after a several-second emergence. Once active it
pathfinds toward the nearest player and kills on contact. It is not a "threat row" like a dark-hunter
or the Drawn — it ignores the brightness dial and the tool set entirely, and there is exactly one
counter: leading it beneath a falling unstable-dripstone crown roots it in rubble for a stun window,
during which it cannot move or kill. At most one Warden exists on an eligible floor, and it is
destroyed with that floor at run end or restart.

**Design tension, flagged deliberately:** the Warden is intentionally read-and-avoid rather than
read-and-manage — there is no brightness-dial or tool interaction with it at all, only positioning it
under a hazard. That is a narrower relationship than the two core threat categories have with the
player, and it leans harder on literal pathfinding than the rest of the threat suite. It stays in
scope because its one counterplay (weaponizing an existing environmental hazard against it) is exactly
the kind of interaction pillar 2 wants, but it should be watched in playtesting rather than expanded
into a second full threat family.

---

## 10. The Basin

A still chamber between floors containing raw molten wax. The one guaranteed-safe room per floor.

**It gives you wax. The price is a permanent sacrifice for the rest of the run.**

This sets the run's rhythm: **tension → safety → weighty decision → tension.**

**Frequency: every floor, guaranteed.**

**Visibility: private.** Each player sees only their own offers.

### Sacrifice pool

- Maximum brightness capped
- Your drip trail
- Your ability to relight others
- Your ability to *be* relit
- Access to a specific tool
- The Basin's next price, doubled
- Mild permanent perception impairments (darkened periphery, dimmer or desaturated sight)

**The wax grant does not worsen with depth.** Every offer pays `0.20–0.35` wax. The escalating cost
is the accumulated permanent loss: a candle reaching Floor 8 has already surrendered far more of
itself than one reaching Floor 2. A doubled-next-price penalty may reduce the next offer, but never
below `0.20`.

Sacrifices should usually be small, legible degradations rather than obvious binary choices.
Removing sprint is not part of the pool; mild perception costs are preferred when expanding it.

### Deferred and cut

- **Contextual offers** (only offering abilities you've actually used, requiring per-player usage tracking) — **deferred.** v1 uses a weighted random pool. Revisit once the core is proven.
- **Complementary sacrifices** (your loss unlocking a teammate's gain) — **CUT.** Cross-player sacrifice logic for a benefit that isn't load-bearing.

---

## 11. Emergent specialization

**There is no class system and there will not be one.**

By Floor 5 each player has made four or five different permanent sacrifices. One can't burn bright but moves fast. One is slow and luminous. One can relight everyone but can't be relit. The party discovered what it is by what it gave up.

**Scope note:** with the Basin private and complementary sacrifices cut, specialization still emerges but the *negotiation* layer does not. Players will discover each other's states through play rather than by comparing menus. Public offers and cross-player synergy remain viable additions later if the core proves out — they are additive, not foundational.

---

## 12. The Brazier — ending a run

**Every floor has a brazier. Lighting it ends your run.** You pour what remains of yourself into it.

**No return trip. No backtracking. No escape sequence.** The run ends on a decision you made, not a corridor you survived.

### Reward formula

```
Reward = (wax delivered) × (depth multiplier) × (1 + 0.25 × additional players at this brazier)
```

Placeholder multipliers: Floor 2 ≈ 1.5×, Floor 4 ≈ 3×, Floor 6 ≈ 5×. Tuning required.

*(Implementation note: the shipped formula also multiplies by the selected cave tier's reward
multiplier and a wax→currency scalar — `Config/Brazier.rewardPerWaxUnit` — layered on cleanly when
cave tiers (Phase 4) were added. Neither changes the risk curve above; see `TUNING.md` for the
full formula and current values.)*

**The risk curve in one formula:**
- Stop shallow → lots of wax, small multiplier
- Push deep → big multiplier, little left to deliver
- Push too deep → burn out, deliver nothing

**Show the numbers.** Players should be able to stand at the Floor 4 brazier with 55% wax and do real arithmetic about whether Floor 5 is worth it. Legible tension beats mysterious tension. *(Revisitable if it proves to break atmosphere.)*

### Individual cash-out with group bonus

Any player may light a brazier and end **their own** run at any time. The party continues.

**The bonus is a multiplier, not a split pot.** A divided fixed pot would mean fewer participants equals a bigger individual share — an incentive to ditch the party right before the brazier. The multiplier means nobody's share shrinks when someone else arrives, so everyone has reason to wait for the straggler.

After banking their individual payout, a player may return to the main lobby before the rest of the
expedition resolves. This is an **early extraction**: cave, contract, wager, and other individual
modifiers remain banked, but that player permanently forfeits any still-pending party extraction
boost. The remaining runners continue and receive a small `[username] has extracted early.` notice.

Leaving is always available and always costs something.

---

## 13. Meta progression

**Core principle: reward DEPTH, not POWER.**

If delivered wax buys a bigger starting pool, the game gets easier every session and the tension curve flattens. Buy *efficiency and access* instead:

- **Cave access** — deeper, harder tiers unlock. Primary progression axis. *(Lethal Company model.)*
- **Burn rate reductions** — last longer at the same brightness
- **Basin discounts** — sacrifices cost less
- **Wax type unlocks** — permanent access to better burn profiles
- **Starting tools** — begin with a flare charge or two
- **Cosmetics** — candle shapes, flame colours, wax finishes

Every one lets the player go *further*, not hit *harder*. The game stays exactly as tense at the new depth as at the old one, indefinitely.

**Lit braziers persist per party.** A party's lit braziers are tracked as their shared progress. Server-wide global persistence is **deferred** — the systems and storytelling upside are real, but it's a v2 concern.

---

## 14. Wax types (in-run loot)

Loot exists; it isn't weapons. Found wax changes your burn profile for the rest of the run.

- **Beeswax** — slow, dim, efficient
- **Tallow** — fast, bright, hungry
- **Cold wax** *(rare)* — burns without attracting the drawn

Also: consumables such as spare flare charges, pre-made decoys, and the solo-only Match self-revive.

Switching mid-run is a real decision — go brighter and hungrier now that the multiplier is high?

---

## 15. Art direction

**Budget: near zero. The constraint is the style.**

**Setting: grey rocky caves with built-in variance.** Not a themed biome — natural stone, with variation baked into the generation so floors don't repeat visually. Colour exists almost exclusively as flame colour and wax tone.

A candle is a cylinder, a flame, and dull wax-drop geometry. Everything else on screen is darkness
and silhouette. Dark-hunters are black shapes led by red eyes; the Drawn are neutral moth forms at
the edge of light.

**This reads as deliberate rather than cheap.** What looks bad in games is *failed realism*, not simplicity.

**Style rules:**
- Light is the only source of visual information
- Enemies are silhouettes, never fully rendered
- Environments are readable geometry, not decorated spaces

---

## 16. Cut and deferred — do not build these

### CUT — decided against, do not revisit without cause
- Complementary sacrifices (cross-player Basin synergy)
- Combat of any kind
- Classes
- Extraction / escape sequence after lighting the brazier

### PROTOTYPE IMPLEMENTED — production-scale versions remain deferred
- **Session-local remains** (recoverable wax pools in later runs on the same server; cross-server
  remains are still deferred)
- **Profile persistence** (ProfileStore in live servers; isolated mock profiles in Studio)
- **Cave tier unlock and selection UI**
- **One-party lobby and reserved-server handoff** (not full matchmaking or an invite system)

### DEFERRED — keep behind focused interfaces
- **Lineage** (carryover between candles)
- **Contextual Basin offers** (ability-usage tracking)
- **Public Basin** (shared visibility of offers)
- **Global brazier persistence** (server-wide, cross-party)
- **Global/cross-server remains**
- **Full hub matchmaking, party invites, multiple concurrent parties, and rejoin recovery**

### NEVER
Crafting · trading · PvP · player housing · pets · dialogue trees · authored story · multiple biomes · a second core resource · guilds · seasonal content

*The most common failure mode for solo projects is adding "just one more system" at 2am. This list exists to make that a conscious violation rather than a drift.*

---

## 17. Technical architecture

**Roblox structure:** hub place + instanced expeditions. Players gather in a hub, form a party, and `TeleportService` into a reserved server. Instances are disposable — no persistent world state, no world server. `MessagingService` for cross-server events. Persistence is player profiles only.

**This is not an MMO and must never become one.** It's a lobby and a session.

**Party size cap: 4.**
**Solo is a fully supported mode**, not merely a testing configuration.

### Toolchain

- **Rojo** — filesystem ↔ Studio sync. The precondition for AI-assisted development.
- **Git**
- **Strict Luau** (`--!strict` everywhere)
- **Rokit** — toolchain manager (not Aftman, which is archived)
- **Wally** — packages
- **ProfileStore** — never raw DataStore. Session locking failures cause duplication and rollback.
- **Jest-Lua / TestEZ** — tests, especially on combinatorial systems

### Entropy defense

1. One responsibility per file, aggressively
2. Content lives in data, not code
3. Pure logic separated from Roblox Instances
4. A living `ARCHITECTURE.md` read at the start of every agent session

---

## 18. Floor generation

**Target: procedural, if it can be built cleanly. Fall back to hand-built room modules with randomised connections if not.**

The pragmatic middle — and the recommended starting point — is **modular assembly**: a small set of hand-built room pieces stitched together with randomised connections, contents, and threat placement. This gives genuine run-to-run variance without the difficulty of making fully generated caves feel intentional.

Room modules, connection rules, and content weights all live in config, so moving further toward full procedural generation later is a data change, not a rewrite.

Generated floors guarantee a dry route from entry through the Brazier to the Basin. Flooded rooms
remain optional branches or alternate loop routes, preserving the shrinking-water decision without
allowing a mandatory lethal gate. Each shared connection receives a deterministic but different
physical width and height, so doorway variance comes from the wall opening itself rather than only
decoration around a repeated rectangle. Deep angular rock throats, loop connections, jagged ceiling
shards, stalagmites, stalactites, and ramped collidable ground shelves provide the current grey-box
structural variance. Each room attempts seven broad, partially overlapping ramped shelves so slopes
cover most of the traversable interior instead of reading as props on a flat slab; only connection
lanes and special interaction centers remain deliberately level. Ceilings are sealed inverted
Terrain height fields with broad deterministic waves and smaller rock ripples, not flat Parts.
Their relief fades into walls and door arches at room edges, while a minimum-clearance clamp keeps
the shaped roof safely above the exact local ground field. Harmless ceiling dressing is
clearance-clamped, and unstable dripstone reserves at least 4.5 studs of real fall beneath its
full procedural silhouette before it is accepted; both anchor to the exact sampled underside.
Localized pools occupy the unraised recessed
floor openings between shelves, making water a natural low-point obstacle. Players physically
climb the rock variation, while threats avoid pool footprints, follow the ground contour, and
sidestep solid cave formations.

Ordinary room footprints are compact (currently 64 studs, 20% below the earlier 80-stud grey-box
scale) while ceiling, enclosure, doorway, terrain, and dressing rolls preserve room-to-room size
variation. Assembly favors a readable main chain, folds that chain toward existing rooms, and then
opens adjacent loop edges. This keeps dead ends uncommon and makes alternate routes toward the
Basin a normal outcome rather than a rare accident.

Expeditions have no floor cap. The server builds the current floor and its successor, then plans one
more successor after each descent. Per-depth content curves cap their own density and magnitude;
the ordinal itself remains unbounded.

---

## 19. Risk register

1. **Sound design.** Horror lives on audio and it's the weakest axis here. Darkness solves the visual problem but *amplifies* the audio dependency — if you can't see, hearing does all the work. **With the tone target now set to genuinely frightening, this is the single largest risk in the project.** Budget real time or real money.
2. **Pacing.** A game about burning slowly could read as tedious. Playtest early with uninvested people.
3. **Powerlessness fatigue.** Tools mitigate it, but watch for it in the first prototype.
4. **Threat balance.** If one category is clearly more dangerous, players default to one brightness setting and the core tension collapses.
5. **First-person legibility.** Reduced spatial awareness in near-darkness could tip from tense to frustrating. Watch whether players get lost rather than scared.
6. **Exploits.** Wax is currency. All wax math must be server-authoritative.
7. **Scope.** Everything above is achievable. Anything from §16 is not.

---

## 20. Open questions

### Settled — recorded for reference
Name: **WICK** · Camera: **first-person** · Tone: **genuinely frightening** · Combat: **none, tools only** · Tools: **all four in v1** · Party cap: **4** · Solo: **supported** · Basin: **every floor, private** · Dark-hunters: **wax damage, not instant kill** · Water: **depth-based, flame contact is lethal** · Brazier: **individual cash-out, group multiplier, no walk-back** · Reward math: **visible** · Movement cost: **yes, small** · Setting: **grey rocky caves with variance** · Run length target: **10–20 minutes average, with outliers both directions**

### Still open
- **Wisp capability** — what exactly can a burned-out player do?
- **Basin sacrifice pool weighting** — how often should mild perception costs appear beside larger losses?
- **Whether the reward numbers stay visible** if they prove to break atmosphere
- **Proximity voice chat** — core mechanic, supported, or absent?
- **Monetization** — cosmetics only, or cosmetics plus cave access
- **Difficulty scaling with party size**
- **Fiction** — why are the caves dark? What are candles? (Possibly better left unexplained.)

---

## 21. Original build target — vertical slice (completed)

*This supersedes any earlier single-room prototype spec.*

**Systemically complete, visually raw.** Every core system present and wired together. Grey boxes, primitive parts, zero art, zero audio, no UI beyond the stylized wax bar.

**In scope:**
Wax · brightness dial (mobile-first control) · movement with small wax cost · all three tools · both threat categories · depth-based water · drip trail · both death states · wisp · modular floor assembly · the Basin (private, every floor, random pool) · the Brazier and reward math · full run flow · solo play

**Originally out of scope:**
Art, finished audio assets, polish, menus, particle effects, party UI, matchmaking, persistence,
cave tiers, and everything in §16.

The implemented Phase 0–5 prototype deliberately goes beyond this original target with grey-box
party UI, ProfileStore persistence, cave tiers, and reserved-server expeditions. It remains a
prototype: audio asset IDs, production art, full matchmaking/invites, rejoin recovery, and live
multi-server validation are not complete.

**The question it answers:** standing in the dark in first person, trading light for time, with something out there — is that actually frightening and tense?

**If yes**, this document is worth building out.
**If no**, no amount of systems will save it.

---

## 22. Glossary

- **Wax** — the single resource: health, light, fuel, timer
- **The Basin** — between-floor site of permanent sacrifice in exchange for wax
- **The Brazier** — end-of-run delivery point; lighting it cashes out
- **Snuffed** — extinguished with wax remaining; revivable
- **Burn out** — wax exhausted; terminal; you become a wisp
- **Wisp** — a burned-out player, slightly helpful to the party
- **Dark-hunters** — threats that avoid light and drain wax on contact
- **VoidFly** — territorial dark-hunter; repeated dives snuff, FLARE/grouping repels it
- **The drawn** — threats attracted to light
- **Flare / Decoy / Cup** — the three tools; Cup is the only way to go dark
- **Unstable dripstone** — rare, warned, one-shot ceiling hazard that removes wax and briefly
  suppresses a surviving flame
- **Vines** — deep-floor doorway curtain that only clears at full burn rate or Flare; never a room's
  only entrance
- **Stone Warden** — rare relic-triggered chasing hazard from Floor 4; stunned only by a falling
  dripstone crown; no dial or tool interaction
- **Remains** — session-local wax pool left by a terminally dead player; global storage is deferred
- **Lineage** *(deferred)* — meta-progression carryover between candles

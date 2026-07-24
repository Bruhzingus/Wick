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

**Note on the trade:** an earlier draft used third-person specifically so players would watch themselves shrink. First-person loses that external view but gains claustrophobia and fear, which serve the "genuinely frightening" target far better. The shrinking light radius carries most of the emotional weight the shrinking model would have.

---

## 4. The brightness dial

The player controls burn intensity — the spine of the game and, given there is no combat, effectively the primary verb.

- **High:** large light radius, threats visible early, rapid consumption
- **Low:** near-blind, minimal consumption, long survival

**Continuous value internally, with a control scheme built for touch first:**

- **Mobile:** an on-screen vertical slider at the screen edge, draggable with a thumb, with light snap points so precise dragging isn't required
- **Desktop:** scroll wheel, plus the same slider

Granularity is where skill lives in a game that has deliberately removed execution-based skill. Knowing this corridor needs 40% and not 60% *is* the ceiling. But the input must never demand precision that a thumb can't deliver.

---

## 5. Movement

**Run, dodge, slide.** That is the complete moveset.

A deliberate reduction. The developer's previous project has a deep first-person movement system — wall-running, stamina, boost chaining — and that depth is **explicitly not carried over.**

**Rationale:**
- Skill belongs in *decisions* (when to push, when to burn bright, when to turn back), not execution
- Roblox is mobile-majority; precision movement is the biggest ceiling on reach
- A candle should not feel athletic
- This is a separate project, not a reskin

**Movement costs wax — a small amount.** Moving fast burns faster than standing still. Tunable, and deliberately kept small: this exists to make speed a considered purchase, not to punish walking around.

---

## 6. Tools, not combat

**There is no combat.** You cannot kill anything. Tools spend wax to change what threats *do*.

Every tool helps against one threat category and hurts against the other. There is never a correct answer, only a read.

### The four tools — all four ship in v1

**SNUFF** — extinguish yourself completely. Free.
→ The drawn lose you entirely. Dark-hunters now own the space you're standing in. You are blind.

**FLARE** — a burst of brightness. Expensive.
→ Dark-hunters recoil. The drawn come straight at you.

**CAST** — throw a lump of your wax to burn on the ground as a decoy. Costs wax permanently.
→ The drawn go to it instead of you until it burns out. Useless against dark-hunters.

**CUP** — shield the flame with your hands. Move slowly, shed almost no light.
→ Immune to draft. The tool for crossing windy ground.

**Why tools rather than combat or pure avoidance:** full combat is thematically incoherent and dissolves the threat taxonomy — if enemies can be killed, the dark-hunter/drawn distinction stops mattering and the brightness dial degrades to a lighting preference. It also drags in animation, hit feedback, and weapon balance: content volume and art, the two weakest axes here. Pure avoidance risks powerlessness fatigue. Tools give agency without violence.

---

## 7. Death and revival

**BURN OUT** — wax reached zero. Slow, visible, predictable. **Terminal.** Not revivable.

**SNUFFED** — extinguished by a threat while wax remained. Sudden, situational. **Revivable.**

**Relighting:** a teammate relights a snuffed player from their own flame at a **small wax cost to the reviver.** Small enough that helping is the default, large enough to notice. The cost is paid by the reviver personally, never from a shared pool.

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

**DARK-HUNTERS** — live in the black, avoid flame. Burning bright keeps you safe. Snuffing puts you in their territory.
Most attack and drain wax on contact. The VoidFly is the positional exception: it makes several
small attacks before it can snuff a candle, and max light or a nearby teammate drives it off.
Their bodies are connected near-black, gaunt humanoid silhouettes that are intentionally difficult
to resolve at range. Paired angled deep-crimson eye slits are the distant warning; their short eye
glow must not reveal the full body.

**THE DRAWN** — moth logic. They come *toward* light. Burning bright kills you. Darkness hides you.
Their models use neutral stone/taupe bodies and layered moth wings, readable without competing
with flame, water, wind, or hunter-eye colors.

These exist so there is **never a dominant strategy.** Every room is a read on which category you face. Getting it wrong is fatal in either direction. This is the core tension generator and must not be diluted.

### Environmental threats

**DRAFT** — visible wind pockets inside rooms and near broken openings, guttering the flame.
They leave space to route around and are countered by CUP.

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
uninterrupted attacks can snuff the candle. Burning at the candle's current maximum or bringing a
teammate close frightens it away temporarily. Avoidance is positioning and cooperation, never combat.

**Design note:** environmental threats are very cheap — no AI, no models — and should carry a large share of difficulty. Prefer them over new enemy types.

---

## 10. The Basin

A still chamber between floors containing raw molten wax. The one guaranteed-safe room per floor.

**It gives you wax. The price is a permanent sacrifice for the rest of the run.**

This sets the run's rhythm: **tension → safety → weighty decision → tension.**

**Frequency: every floor, guaranteed.**

**Visibility: private.** Each player sees only their own offers.

### Sacrifice pool

- Maximum brightness capped
- A movement ability — no slide, or shortened dodge
- Your drip trail
- Your ability to relight others
- Your ability to *be* relit
- Access to a specific tool
- The Basin's next price, doubled

**The exchange rate worsens with depth.** Floor 2 costs something you barely use. Floor 6 costs something you need — and you take it anyway, because the alternative is not reaching Floor 7.

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

**The risk curve in one formula:**
- Stop shallow → lots of wax, small multiplier
- Push deep → big multiplier, little left to deliver
- Push too deep → burn out, deliver nothing

**Show the numbers.** Players should be able to stand at the Floor 4 brazier with 55% wax and do real arithmetic about whether Floor 5 is worth it. Legible tension beats mysterious tension. *(Revisitable if it proves to break atmosphere.)*

### Individual cash-out with group bonus

Any player may light a brazier and end **their own** run at any time. The party continues.

**The bonus is a multiplier, not a split pot.** A divided fixed pot would mean fewer participants equals a bigger individual share — an incentive to ditch the party right before the brazier. The multiplier means nobody's share shrinks when someone else arrives, so everyone has reason to wait for the straggler.

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

Also: consumables such as spare flare charges and pre-made decoys.

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
lanes and special interaction centers remain deliberately level. Localized pools occupy the
unraised recessed floor openings between shelves, making water a natural low-point obstacle.
Players physically climb the rock variation, while threats avoid pool footprints, follow the
ground contour, and sidestep solid cave formations.

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
- **Basin sacrifice pool weighting** — how fast should the exchange rate worsen?
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
Wax · brightness dial (mobile-first control) · movement with small wax cost · all four tools · both threat categories · draft · depth-based water · drip trail · both death states · wisp · modular floor assembly · the Basin (private, every floor, random pool) · the Brazier and reward math · full run flow · solo play

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
- **VoidFly** — territorial dark-hunter; repeated dives snuff, max burn/grouping repels it
- **The drawn** — threats attracted to light
- **Snuff / Flare / Cast / Cup** — the four tools
- **Draft** — wind that gutters the flame; countered by Cup
- **Remains** — session-local wax pool left by a terminally dead player; global storage is deferred
- **Lineage** *(deferred)* — meta-progression carryover between candles

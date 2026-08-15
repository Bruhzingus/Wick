# WICK — Design Document

**Status:** Grey-box public-playtest prototype implemented through Phase 5. Core design settled.
**Platform:** Roblox
**Genre:** Co-op horror dungeon crawler / roguelite
**Team:** Solo developer, AI-assisted
**Last updated:** July 2026

> **Implementation status.** The original vertical slice is built, and the prototype now also
> includes deterministic tests, feel/audio plumbing, run-variety content, server hardening,
> ProfileStore-backed progression, cave tiers, and independent elevator-party/reserved-server
> handoffs. These additions do not change the settled design pillars below. See
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
2. **You cannot win a fight.** Threats are read and managed, never defeated. Powerlessness against enemies, agency over yourself. *(One authored exception exists — dynamite, a rare found consumable that can kill and that hurts you too. See §6a for what keeps it an exception rather than a combat system.)*
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

**There is no combat.** Tools spend wax to change what threats *do*; they never damage them. The one
thing in the game that can kill is dynamite, a rare found consumable that is not a tool and that is
covered separately in §6a.

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

---

## 6a. Dynamite — the authored exception

**Owner decision, taken deliberately and recorded here rather than left as a contradiction in the
code.** Everything above and in §9 still holds for the tool set: FLARE, DECOY and CUP manipulate
threats and never damage them, and that remains the rule the game is built on. Dynamite is the one
thing in the cave that breaks it.

**It is not a fourth tool.** It is a **found consumable** with a count, like the Match: no wax cost,
no cooldown, no Basin sacrifice that can take it, and no `ToolId`. You either have one or you do not.

**What it does.** A stick is thrown (aimed, along the same validated arc the Decoy uses) or placed into
the yellow outlined charge position on a blast door, where that one committed interaction seats and
lights it. After a short fuse it detonates:
every candle in radius loses wax falling off with distance — **including the one that lit it** — every
creature in radius takes blast damage and **can die**, any blast door in radius breaks, and the whole
floor is called to the crater by a very loud, slow-decaying noise.

**Lethality scales per creature**, expressed as "sticks at point blank": one stick removes a Dark
Crawler, a Cave Listener survives one that was not right underneath it, and the Stone Warden takes
three — more than a candle can carry, so **§9's promise that the Warden has exactly one real counter
still holds**. What a stick buys against the Warden is a stun and then a limp, never a kill in
practice. Damage accumulates on a body and never heals.

**Why the pillar survives this.** Pillar 2 says you cannot win a *fight*, and dynamite does not give
you one — it gives you a single, rare, expensive act of removal that is loud enough to make the next
minute worse. Four numbers hold the line, and all four are config rather than convention:

1. **Supply.** Roughly one stick every one to three floors, on a deterministic schedule; a crate of
   three every ten to twenty. You cannot solve rooms with it.
2. **A carry cap of four.** Finding a crate while nearly full genuinely wastes sticks.
3. **Self-harm.** The largest single discrete wax hit in the game, survivable from full on purpose —
   what should end a greedy run is what arrives afterwards, not the explosion.
4. **Noise.** The same floor-wide summons a detonating Explosive Seam causes.

**Its other use is the quiet one, and the reason it exists.** Blast vaults (§18) are sealed dead-end
rooms holding guaranteed ore and no creature spawns. Spending a stick on rock instead of on the thing in
front of you is the trade the whole item is built around.

Dynamite shows a live count in the control hotbar, and nothing else — it has no active state and no
cooldown to draw.

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

It **circles**, literally: the patch is a real flight path, and its centre drifts inside the same
territory, so the stone it hung over on the way in is not where it is on the way back. Nothing on
its body emits light — it is a knot of dark with no eye glow at all — so the only thing that gives
it away before it commits is the **buzz**, which the cave's own rock can muffle.

**Once it commits it harasses.** A dive is a commitment, not a swipe: for a short fixed window it
follows its victim past the edge of its patch at above walking speed, so strolling out of its
territory no longer shakes it. The three ways out are the three the creature was always built
around — burn a flare, get to a teammate, or **run** (it is deliberately slower than a run and
faster than a walk). When the window ends it breaks off, goes home and ignores everybody for a few
seconds, so a harassment is survivable by outlasting it and can never become a permanent siege.

**It hears you.** It is the roster's most sensitive listener and its threshold is low enough that a
single landing clears it — jumping around under a low ceiling is what wakes one. Being heard widens
the disc it will come down for and lets it reposition on its patch toward the sound; it never leads
one out of its room, and a noise never becomes a target.

**THE DEAD CANDLE** *(Floor 10+, rare)* — somebody else's candle, burned out on the floor with three
pickups still lying around it and three VoidFlies living on the corpse. It introduces no new
mechanic: the reward is ordinary loot and the danger is ordinary creatures, arranged so the loot is
inside overlapping territories. What it asks is whether you want it, and the answers scale — one
flare, one teammate or one run answers one fly, and this asks what you do about three. A party that
reads the room and leaves loses nothing. Never in the entry, Basin, Brazier or Warden room, never
under a ceiling too tall for the creature it comes with, and, like every VoidFly room, never
stacked with falling stone.

**UNSTABLE DRIPSTONE** — a rare one-shot environmental hazard, never an enemy or combat encounter.
Dangerous formations appear only in ordinary rooms whose nominal ceiling is no higher than 34
studs, where a bright candle can reasonably inspect the roof. Entry, Basin, and Brazier rooms are
always protected, as are rooms assigned a threat that extinguishes with no window to react — which
is the VoidFly and only the VoidFly. A moth's snuff takes seconds of unbroken contact a player can
run, dim, or decoy their way out of, so it is not double jeopardy and does not protect its room;
the rule guards against stacking two *unavoidable* extinguishes. The cave therefore asks the player to
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
share of difficulty — preserve clear physical warnings, safe routing, and room-level rarity in all of
them.

This note previously read "prefer them over new enemy types," and that preference has been
**deliberately lifted** (owner decision) so each cave family could gain a signature creature of its
own. What replaced it is a stricter bar rather than an open door: a new creature has to be something a
player can tell apart from every other creature at a glance, has to be anchored to an existing system
rather than introducing a new one, and has to have exactly one counterplay a player can name. The
three below each clear it, and the Calver in particular is closer to an environmental threat than to
an enemy — it never touches anybody.

### Signature creatures

One per cave family, found in that cave and nowhere else. They are ordinary `Config/Threats` rows in
the ordinary spawn roll; the other two families weight them to zero, which the planner already reads
as "not here". No new AI system, no new code path, no `if familyId ==` anywhere behind them.

**CAVE LISTENER** (Stone) — functionally blind, and the only creature in the game that does not care
how bright you are burning. It hunts entirely by sound, on the same `hearing` block every listening
row already uses: one clean pick strike is enough to rouse one at range, where a crawler needs several
overlapping. Its silhouette is a wedge — a huge flattened skull carried low with two membranous ear
fans that sweep forward the moment it hears something, which is the readable tell for "it is coming to
look" long before the crimson is visible. It outruns a walk but not a run, so escaping after rousing
one spends wax. **Counterplay: stop making noise.** Going quiet breaks its information source, and
light is not the answer — which is precisely why it belongs in the
cave where players learn the game.

**KNOTWALKER** (Moss) — it does not chase you; it walks the room graph toward where you are HEADING.
Moss generates more loops, more branches and far more TwinLobe rooms than anywhere else, and this is
that topology turned into a creature: the danger is in the room you have not seen yet. Narrow across
the shoulders and long in the forelimbs, built to thread a lobe's neck. Three things keep it fair, all
enforced in `Types/Threat.InterceptProfile`: it needs a real heading before it will predict at all, it
aims exactly ONE room ahead, and once it has committed it cannot re-aim until that commitment lapses.
**Counterplay: change route, or go back the way you came** — which is now empty.

**CALVER** (Ice) — it clings to the roof of Ice's tall vaults and, when a candle passes beneath,
hammers the rock to bring down a formation that was already hanging there. **It never touches anybody:
zero contact damage, no attack, no dive.** Everything it can drop was placed by the planner, was
inspectable from across the room, and still runs its own full warning when it goes — the creature
changes WHEN the ceiling fails, never WHETHER. Its wind-up is the longest attack animation in the game
and runs BEFORE the formation's warning rather than instead of it, so the two windows add. With
nothing in reach it only scrapes: loud, locatable, harmless. **Counterplay: get out from under it** —
deliberately the opposite of the reflex every other threat has trained. A flare still drives it off
its patch like any other dark-hunter.

All three are dark-hunters and all three carry the crimson angled eye slits, so the category read a
player makes at range is unchanged. None appears before Floor 3 — the tutorial band teaches light, and
a creature that ignores light, predicts your route, or drops the ceiling would muddy that lesson
before it has landed.

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
a room's only entrance, and vines never sit on the guaranteed entry → Brazier → Basin route. Maximum
brightness is always measured against that candle's current reachable dial ceiling, so a brightness
sacrifice can never disable the key. The alternate route still prevents mandatory exposure.

**FROZEN BARS** — Ice never grows vines. In their place, the same optional doorway sites hold thick
vertical icicles joined by two frozen rails, reading like prison bars across the entrance. They are
solid to players and use the same planner proof as vines, so they never become mandatory progression.
An uncovered candle held at its current maximum brightness melts one barricade in about 6 continuous seconds; a
Flare melts it in about 1.2 seconds. Progress remains if the candle backs away. The bars do not catch
fire or spread to another doorway. When they finish melting they leave a shallow cosmetic puddle,
which blocks nothing, harms nobody, and disappears after exactly 10 seconds.

**THE STONE WARDEN** — a rare, floor-scoped chase encounter, eligible from Floor 4. When selected,
the planner adds one optional, normal-looking weathered chamber whose flat encounter pads and nearby
unstable-dripstone crown guarantee the encounter can physically function. The dormant body is an
outcrop in one doorless wall of that chamber, with three pieces of guarded wax on a low tray in the
open floor in front of it. Each piece is picked up separately. Taking the third shakes the chamber,
commits three additional pre-visible dripstones to their ordinary full warning and fall, and wakes the
Warden; the guaranteed Heavy Crown counter does not fall in this opening collapse. It then steps out
of the wall over a several-second emergence. Once active it
pathfinds toward the nearest player and kills on contact. It is not a "threat row" like a dark-hunter
or the Drawn — it ignores the brightness dial and the tool set entirely, and there is exactly one
counter: leading it beneath a falling unstable-dripstone crown roots it in rubble for a stun window,
during which it cannot move or kill. At most one Warden exists on an eligible floor, and it is
destroyed with that floor at run end or restart.

**Naming.** The encounter is called the **Stone Warden** in Stone, the **Moss Warden** in Moss and the
**Ice Warden** in Ice, and its courses are built from that family's own formation palette and
materials — so the dormant mass genuinely reads as part of the wall it stands up out of. Every other
reskinned creature follows `{Family} {Name}` with Stone keeping the plain original; this row is the
one place that rule is read as ALREADY applied, because following it literally would rename Stone's
encounter to "Warden" and produce "Moss Stone Warden". Config ids, room modules, services and files
are unchanged: this is a display name and a palette.

**Design tension, flagged deliberately:** the Warden is intentionally read-and-avoid rather than
read-and-manage — there is no brightness-dial or tool interaction with it at all, only positioning it
under a hazard. That is a narrower relationship than the two core threat categories have with the
player, and it leans harder on literal pathfinding than the rest of the threat suite. It stays in
scope because its one counterplay (weaponizing an existing environmental hazard against it) is exactly
the kind of interaction pillar 2 wants, and it should be watched in playtesting. The earlier note here
warned against expanding it "into a second full threat family"; that warning was about THIS encounter
growing, and it stands. It is not a bar on the signature creatures above, which are ordinary threat
rows in the ordinary spawn system rather than bespoke set-piece encounters.

---

## 10. The Basin

A still chamber between floors containing raw molten wax.

**It is no longer a guaranteed-safe room** (owner decision). Nothing in the cave is: threats roam the
whole floor, the Basin and sealed blast vaults included, and a candle standing at the Basin can be
perceived, followed and touched exactly as it can anywhere else. What the Basin still is, is a place
the floor does not deliberately populate — no threat SPAWNS there — so it is usually quiet, and
"usually" is now doing the work "guaranteed" used to.

This changes the run rhythm below from *tension → safety → weighty decision → tension* to *tension →
quiet → weighty decision → tension*, and the decision is now made with one eye on the doorway. Reading
four sacrifice cards is no longer free; the panel does not immobilise the player, so walking away from
a half-read offer is the cost of being wrong about how quiet the room was.

**It gives you wax. The price is a permanent sacrifice for the rest of the run.**

This sets the run's rhythm: **tension → safety → weighty decision → tension.**

**Frequency: every floor, guaranteed.**

**Visibility: private.** Each player sees only their own offers.

### One chamber, three fixtures

The Basin room is the **completion chamber**: the Cauldron stands at its centre, the Gas Lantern in
one corner and the Descent Ladder in the other, roughly forty-five studs apart. The room where a
floor is scored is therefore also the room where it ends — you stand between the machine that banks
your haul and the machine that takes you deeper and pick one.

That fork used to be spread across two adjoining rooms, which made the decision a walk rather than a
look. The room the chamber hangs off is now an ordinary cave room and carries ordinary content.

### The Cauldron

The wax is held in a physical vessel: a squat iron or stone cauldron on a three-legged tripod,
standing on a low cairn, with molten wax moving slowly in the bottom of it and cooled wax run down
the outside in the drip trail's own dull brown. Family-tinted like every other built object in the
cave (`Config/Cauldron`, `NewModelsAndObjects/Cauldron`).

**It is presentation and nothing else.** The pool, the four private offers, the grant band, the
progressive prerequisites and the one-exchange-per-floor rule are all untouched by it — the prompt is
anchored a little higher and that is the whole of the mechanical difference. Nothing here is a light
source: the wax surface and the coals under the belly are self-illuminating pixels with no PointLight,
so the room is still one you find with your own flame.

### Sacrifice pool

- Progressive maximum-brightness and minimum-brightness pressure
- Progressive movement speed, wax capacity, wax-drain and tool-cooldown penalties
- Progressively shorter Flares and Decoys, and progressively more expensive teammate relights
- Progressive perception impairments (darkened periphery, dimmer or desaturated sight)
- The Basin's next price, doubled

Each visit shows four private offers. Every card states the exact mechanical consequence, whether it
stacks, and any named tool it affects; metaphorical titles never replace the rule text. Progressive
rows unlock in order, so a candle receives the first stage of a degradation before the second or
third can enter its pool. Basin sacrifices may worsen an ability but never remove the ability, a tool,
or access to a brightness-gated interaction completely.

**The wax grant does not worsen with depth.** Every offer pays `0.20–0.35` wax. The escalating cost
is the accumulated permanent loss: a candle reaching Floor 8 has already surrendered far more of
itself than one reaching Floor 2. A doubled-next-price penalty may reduce the next offer, but never
below `0.20`.

Sacrifices should usually be small, legible, stacking degradations rather than binary removals.
Removing sprint is not part of the pool; new progressive or tool-specific modifiers are preferred.

### Deferred and cut

- **Contextual offers** (only offering abilities you've actually used, requiring per-player usage tracking) — **deferred.** v1 uses a weighted random pool. Revisit once the core is proven.
- **Complementary sacrifices** (your loss unlocking a teammate's gain) — **CUT.** Cross-player sacrifice logic for a benefit that isn't load-bearing.

---

## 11. Emergent specialization

**There is no class system and there will not be one.**

By Floor 5 each player has made four or five different permanent sacrifices. One can't burn bright but moves fast. One is slow and luminous. One can relight everyone but can't be relit. The party discovered what it is by what it gave up.

**Scope note:** with the Basin private and complementary sacrifices cut, specialization still emerges but the *negotiation* layer does not. Players will discover each other's states through play rather than by comparing menus. Public offers and cross-player synergy remain viable additions later if the core proves out — they are additive, not foundational.

---

## 12. The Gas Lantern — ending a run

**Every floor has a gas lantern. Lighting it ends your run.** You pour what remains of yourself into
it.

**No return trip. No backtracking. No escape sequence.** The run ends on a decision you made, not a corridor you survived.

### The fixture

An actual lantern: enclosed glass panes around the flame, an iron frame, a valve and a burner, on a
low post. Cold and dark until it is lit — unlit glass, dead wick, nothing glowing — so the ignition
keeps its full impact, the same way the blast door reads dead until it is blown.

**The enclosed glass is the point.** Every other flame in this game is carried in the open, in your
own hands, shrinking. This is the one the player does not have to carry, and the reward for finishing
a floor is being allowed to make one. It stays lit for everyone once anybody lights it.

**Gas, not wax.** The lantern is fed by its own supply, so it does not draw on the player's candle to
stay lit. This is fiction, not a mechanic: the reward has always been a value READ from the Raw Wax
the player is carrying, never a cost paid to the fixture.

**The flame is not candle-orange and not descent-blue.** Candle-orange belongs to the flame the player
carries, everywhere; the cold blue that used to mark the way down was retired with the descent beacon
and reads hostile. A gas flame — a pale blue-white core with warm tips — is the honest third answer
and adds no new hue to a deliberately tight palette.

**The cave-wide wall-lamp catch.** Every generated room carries exactly one cold lamp on its actual
cave wall. In the completion room, that one fixture is the interactive Gas Lantern; there is no
decorative companion. Every other room receives one network lamp. The builder chooses intact walls
deterministically where possible and uses a doorway-safe side position when a room has no sealed wall.
It samples the room's real procedural ground to keep the fixture above foreground rock, then raycasts
the base, middle, and top of the complete fixture into Terrain. The nearest valid surface and its
horizontal room-facing normal define a mount just proud of the rendered wall. No Terrain is carved,
so a lamp creates neither an inset nor an artificial flat pocket in a sloped wall. Random wall dressing
is excluded from the same tight footprint. Rock therefore cannot cover a lamp, its flame, or the Gas
Lantern's prompt. None of these lamps stand in a circle or a rack in the completion chamber. The Gas
Lantern catches first, followed by the other rooms' lamps from nearest to farthest across the explored
floor. A small point glow resolves each fixture while a broad, low-intensity amber beam faces into its
room; coverage comes from direction and range rather than a sun-bright flame. Nothing emits flying
sparks or glowing orbs; the lamps themselves are
the effect. On a final or unanimous group extraction, each extracting player is frozen in place but
keeps the ordinary first-person camera for five seconds. The view begins facing the two local lamps,
then belongs entirely to the player while the network catches. A group sees the same shared ignitions
at the same time and receives its results together. It is deliberately
**symbolic, not persistent**: no new save data, no floor tracking, and no dependence on older floor
geometry that may already have been retired. The lantern's depth chain remains cut from this floor's
own depth, which reports how far the run has come without depending on a single thing behind it.

**Payout resolution is unchanged.** Interact → the existing reward computation →
ignition → the existing results card → the existing instant `ReturnToLobby` whenever the player is
ready. An individual extracting while another runner remains gets the results card immediately; the
last unresolved runner receives the five-second free-look beat. The first ignition also makes that
floor enemy-free: generic threats, Ashamed Lurkers, and its
Stone Warden cease to exist as the cave lights. Non-enemy hazards remain, and only the lit floor is
cleared; deeper floors keep their enemies so party members who continue still face a real run.

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

The Gas Lantern also offers **GROUP EXTRACT** as a separate unanimous ready action. Every unresolved
runner must be alive, lit, on the same floor, within the lantern's validated interaction radius, and
must confirm for themselves. Readiness cancels when a player leaves that state. The last confirmation
starts every member's independent payout on the same server tick, freezes them together, and gives
all of them the same five-second free-look lamp scene before their result cards appear. One player can
never use group extraction to pull out a teammate who wanted to continue.

Leaving is always available and always costs something.

---

## 12a. The Descent Elevator — moving between floors

**Every floor has one way down, and it is a machine.** A two-person open-frame cage on a chain winch,
standing in a headframe over a shaft cut into the completion chamber's floor. Family-styled like the
vault door: iron-banded timber in Stone, lashed wood on knotted rope in Moss, chipped ice on a
frost-crusted chain in Ice.

**One small light, and only one.** A work lamp hangs off the headframe beside the mouth — the Gas
Lantern at three-quarter size, already burning. It exists because retiring the old cyan beacon left
the way down as a dark rig you could walk past; it is dim enough that the far wall stays black and it
lights nothing but the machine it is bolted to. It is decorative: the threat-perception field is
assembled from server-owned flames, flares, decoys and remains and never by scanning the world for
lights, so this makes the fixture easier for a player to find and never makes its rider easier to
hunt.

**It replaced a trigger box.** The way down used to be a floating cyan beacon with an invisible zone
around it: walk into the zone and you were instantly on the next floor. There was no mechanism, no
consent, and no travel.

**The interaction is a prompt**, like mining, blast doors and the Signal Bell. Nothing in this game
happens because a player walked into a volume.

**The ride is real travel, not a fade.** The player is put on the cage, the hatch folds shut over the
mouth, and the cage descends a lined shaft with rib rings passing it — lit only by the candle in the
rider's own hands, because a lit cage would advertise the shaft and the player in it to everything on
the floor. Each floor keeps its own local procedural layout, but its world origin is shifted so its
entry room sits directly under the previous completion chamber's elevator. The cage therefore travels
the complete floor gap and physically stops in the next room; there is no landing cut or fade. The
hoist cable and yoke run along the cage's rear-right edge, outside every rider's first-person head
volume; no load-bearing member crosses the centre sightline during the ride.

**It is one-way and exactly one floor.** The lower landing has no call button or ride control. Riders
get a short window to step out; once a rider leaves, the open cage rejects re-entry. Anyone still on
the deck is pushed gently through the lower gate, with a final server-owned placement only as a
collision safety net. The gate then closes and the empty cage visibly returns upward. It has no
connection to `ReturnToLobby`; a player who wants to leave the cave lights the lantern.

**The cage carries up to two.** Pulling the winch also boards one eligible companion already standing
on the deck. Each rider's arrival resolves independently, so one death or disconnect cannot refuse
the other's descent. Anyone beyond capacity stays on the upper collar.

**The forced threshold is enemy-safe, briefly.** From gate closure through the ride, exit window, and
a short post-arrival grace, ordinary threats, the Stone Warden and the Ashamed Lurker cannot target or
contact-kill a rider. Wax drain and environmental hazards continue normally. This is not a safe room:
it is narrowly scoped protection for the interval in which the machine controls the player's body.

---

## 13. Meta progression

**Core principle: reward DEPTH, not POWER.**

If delivered wax buys a bigger starting pool, the game gets easier every session and the tension curve flattens. Buy *efficiency and access* instead:

- **Cave access** — deeper, harder tiers unlock. Primary progression axis. *(Lethal Company model.)*
- **Burn rate reductions** — last longer at the same brightness
- **Basin discounts** — sacrifices cost less
- **Candle modifier unlocks** — permanent access to better in-run modifier rows
- **Starting tools** — begin with a flare charge or two
- **Cosmetics** — candle shapes, flame colours, wax finishes

Every one lets the player go *further*, not hit *harder*. The game stays exactly as tense at the new depth as at the old one, indefinitely.

**Lit braziers persist per party.** A party's lit braziers are tracked as their shared progress. Server-wide global persistence is **deferred** — the systems and storytelling upside are real, but it's a v2 concern.

---

## 14. Candle modifiers (in-run loot)

Loot exists; it isn't weapons. Found wax **adds to the candle you already have** — it never swaps you
into a different candle.

**Why this replaced the old "wax types".** The original pool (Beeswax, Tallow, Cold wax) was a set of
*profiles* you switched between: picking one up overwrote whichever you were carrying. Three problems
followed from that, and all three are structural rather than tuning:

1. **Finding loot could make your run worse.** Walking over a Beeswax cache after choosing Tallow
   silently undid a decision, so the correct play was often to leave loot on the floor.
2. **Every pickup was the same decision.** With one profile slot there was nothing to build toward:
   floor 12 offered exactly the choice floor 2 did.
3. **The swings were too big to reason about.** A 30% change to both drain and brightness at once is
   not a decision a player can evaluate mid-cave; it is a coin flip they live with for a run.

The pool is now **stacking, roguelike, and small**. No single pickup is worth more than 5% of
anything, they accumulate, and the run you end up with is the one you assembled.

- **Life Wax** — −3% burn rate per stack. Kept for the whole run; diminishing past −50%.
- **Bright Wax** — +5% maximum brightness per stack. Kept for the whole run; diminishing past +30%.
- **Extra Wicks** — 1–3 wicks; +25% light for 3–5 minutes and **no extra wax**. Cupping still puts
  you at exactly the darkness it always did — you cannot cup three wicks and keep them.
- **Frozen Wax** — a 5% block that melts back into the candle at +0.25% every 10 seconds spent
  **burning at maximum**, and disappears when it is spent. Not a heal: a reason to commit to a dial
  you were already afraid of. Alone in this pool it is **uncapped** — the stacking pair are bounded
  because they are permanent, and a permanent effect that ran away would eventually make a candle
  that does not burn. Frozen Wax is temporary and rate-limited by its own trigger condition, so a
  ceiling would do nothing but punish a player for finding a third block.
- **Candle Sleeve** *(rare, deep floors only — Stone 15+, Moss 10+, Ice 5+)* — a cardboard sleeve.
  40% less damage from enemies and environmental impacts, for five hits, then it tears. It buys a
  mistake back; it does not make you safe.

Also: consumables such as spare flare charges, pre-made decoys, the solo-only Match self-revive, and
**dynamite** — a loose stick every one to three floors, or rarely a crate of three (§6a). Dynamite is
the only consumable the cave supplies on a schedule rather than through the weighted pool, because
its whole design depends on the player being able to expect one soon without knowing which floor.

**Pickups are sparse.** A shallow floor averages about one and can honestly have none; deep floors
carry more. A cache is meant to be worth crossing a room for, not something you walk past three of.

---

## 15. Art direction

**Budget: near zero. The constraint is the style.**

**Setting: dark rocky caves with built-in variance.** Never decorated spaces — natural stone, with
variation baked into the generation so floors don't repeat visually. Colour exists almost exclusively
as flame colour, wax tone, and the muted hue of the rock a cave family is cut from.

**Three cave families: Stone, Moss and Ice.** Each is a different cave, not a different skin: they
differ in how fast difficulty grows, how their maps generate, what pressure their environment applies,
which of the existing threat roster they draw on, and how valuable their native ore is. All three
begin on floor 1 and all three drain passive wax at exactly the same rate — a family is never harder
because an unavoidable timer runs faster. Stone is cool blue-charcoal slate, Moss is dark wet
green-grey, Ice is dark blue-grey with restrained pale ice. None of them is bright and none of them
emits light: light remains the only source of visual information in every family.

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
- **Elevator parties and reserved-server handoff** (independent cars, not full matchmaking or an
  invite system)

### DEFERRED — keep behind focused interfaces
- **Lineage** (carryover between candles)
- **Contextual Basin offers** (ability-usage tracking)
- **Public Basin** (shared visibility of offers)
- **Global brazier persistence** (server-wide, cross-party)
- **Global/cross-server remains**
- **Full hub matchmaking, party invites/browser, and rejoin recovery**

### NEVER
Crafting · trading · PvP · player housing · pets · dialogue trees · authored story · cosmetic-only biome duplication · a second core resource · guilds · seasonal content

**On cave families, which replaced the old blanket 'never multiple biomes'.** Wick supports a small
fixed set of mechanically distinct cave families. Every family must change topology, environmental
pressure, threat ecology, or another existing system. Families share the same generator, the same
validator, the same survival resource, and the same no-combat rules. Cosmetic-only biome duplication
— the same cave three times in different colours — remains prohibited, and that is what the original
entry was protecting against.

*The most common failure mode for solo projects is adding "just one more system" at 2am. This list exists to make that a conscious violation rather than a drift.*

---

## 17. Technical architecture

**Roblox structure:** hub place + instanced expeditions. Players gather in a hub, form a party, and `TeleportService` into a reserved server. Instances are disposable — no persistent world state, no world server. `MessagingService` for cross-server events. Persistence is player profiles only.

**This is not an MMO and must never become one.** It's a lobby and a session.

**Party size cap: 4.**
**Solo is a fully supported mode**, not merely a testing configuration.

**An elevator car is a party queue.** Entering a car opens its party panel and explicitly releases
the shift-locked cursor. The panel lists all four seats, lets each rider ready or stand down, shows
every cave's personal entry cost, permanent ownership cost, and Raw Wax/ore benefit, then accepts one
vote per rider once everyone is ready. It also provides an explicit leave action. The first rider
aboard is the leader; before the roster commits to launch, that leader may remove another rider. A
removed rider remains in the hub but cannot re-enter that same party for 20 seconds, preventing an
immediate random rejoin without turning the prototype into an invite or ban system.

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

Generated floors guarantee a dry route from entry to the completion chamber — the one room holding
the Cauldron, the Gas Lantern and the Descent Ladder, which the planner still addresses by two names
(`basinRoomIndex` and `brazierRoomIndex`) so the two can be separated again without unpicking every
rule that refuses to place content in either. Flooded rooms
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

Grid coordinates remain local to each generated floor, including the entry room at `(0, 0)`. World
origins do not: each successor is translated in X/Z so that local entry lies directly under the prior
completion chamber's elevator pad. This translation changes no topology roll or room connection; it
only turns the between-floor shaft into one continuous piece of world geometry.

### Cave families

A floor is generated for exactly one cave family, and the family resolves every curve the generator
reads. All three begin at global depth 1: a family is a different cave, never a deeper starting point.

| | Stone | Moss | Ice |
|---|---|---|---|
| Identity | the balanced baseline | obstructed information | exposure and instability |
| Base threat / hazard | 0.60 / 1.00 | 1.10 / 1.20 | 1.35 / 1.45 |
| Band growth | flat — the regression baseline | rises through every band | rises fastest |
| Passive wax drain | 1.00 | 1.00 | 1.00 |
| Topology | balanced loops and branches | more loops, folded tighter | fewer loops, longer connectors |
| Ceilings | full authored range | biased low-to-middling | biased tall |
| Water | 0.40 of floors | 0.55 | 0.30 |
| Doorway obstacles | burning vines, baseline | burning vines two floors earlier, 1.75x | barred icicles, baseline |
| Rock and texture | cool blue-charcoal, flat layered slate | dark wet green-grey, coarse rock and basalt | dark blue-grey, packed glacier and ice |
| Falling hazards | baseline | wider spread than Stone | densest, and the only family that hangs long spires |
| Formation mix | the authored four, unchanged | forks and heavy crowns, plus the Sodden Mass | needles and long spires, plus the Splintered Lance |
| Signature creature | Cave Listener | Knotwalker | Calver |
| Creature dressing | bare — the reference build | damp shag caught in the joints, coarse wet skin | frost rime on upward faces, thin spurs |
| Ambience | the baseline both others are authored against | wettest and busiest: ticks, seeps, hidden water | driest and quietest: strata strain and a glacier groan overhead |
| Air | the reference (density 0.42) | thickest (0.55) — a flame dies sooner and distance is hidden | thinnest (0.30), most haze — light carries and halls have a far end |
| Acoustic | the authored per-bus reverb, unscaled | dead and close (decay ×0.60) — soft growth, tight knotted rooms | long and hard (decay ×1.65) — the cave answers you |
| Underfoot | flat slate: a hard, ringing step | wet growth: soft, dull, absorbed | packed glacier: a brittle crunch with no tail |
| Native ore | Tier 1 | Tier 2 | Tier 3 |

A family owns what a cave CONTAINS and what it is MADE OF. It never owns a stat, a radius, a speed, a
perception value or a cue's volume: what a creature does once it is in front of you, and how loud
anything is, are identical in all three. That line is what keeps "this cave is different" from
quietly becoming "this cave hides things from you."

**Difficulty resolves as a three-factor product**, and nothing may compute it any other way:

```
resolvedThreatBudget = baseThreatBudgetForFloor × caveBaseThreatMultiplier × caveThreatBandMultiplier
resolvedHazardBudget = baseHazardBudgetForFloor × caveBaseHazardMultiplier × caveHazardBandMultiplier
```

Party scaling, room caps, hazard caps, introduction rules, protected-room rules and planner safety
validation all still apply on top. When requested content cannot be placed safely the placement is
reduced; a safety rule is never relaxed to reach a number.

### Falling hazards

Unstable formations — dripstone in Stone and Moss, icicles in Ice — are the cave's one falling hazard,
sharing one behaviour system and one warning language everywhere. Density grows sharply with depth and
with how dangerous the cave is: floors 1–3 stay sparse because that is where a player learns to read
the dust, the tremor and the warning, and everything past floor four is what "deeper is more
dangerous" is made of.

**A family chooses WHICH formations its ceilings hang.** All six variants live in one shared pool and
each family weights it; a family may refuse a row outright but may never delete one, because every id
has to stay resolvable wherever a plan names it (and the Warden's counter crown is hard-named in every
cave). Stone hangs the authored four at their authored weights and is the regression baseline here as
everywhere. Ice leans on needles and long spires and adds the **Splintered Lance**: the widest trigger
disc paired with the shortest warning, so its hazard commits sooner in space and resolves faster in
time — exposure, expressed as a ceiling. Moss leans on forks and heavy crowns and adds the **Sodden
Mass**: the widest committed ground in the game and the LONGEST warning, so the danger is never that
you cannot read it, only that its disc reaches around a TwinLobe wall you cannot see past. The
topology obstructs; the hazard never does.

**Fall physics stay global.** `fallAcceleration` and the fall-duration clamp are identical in every
family and deliberately so: the clamp band sits below human reaction time, so it is the tail of an
animation rather than a window a player acts inside. The window is `warningSeconds`, which is
per-variant. Making a family's fall faster would be a difficulty change with nothing readable attached
to it, which is the one thing this system does not do.

**Readability is measured at the formation's TIP, not at the roof it hangs from.** A full-brightness
candle must be able to inspect anything that can fall on you, and what matters for that is where the
dangerous end is — so a long spire may hang from a tall vault while a short needle in the same room
may not. Three guarantees hold at every depth: no formation may drop into a doorway lane, most of
what hangs overhead is still harmless scenery, and every floor keeps at least one ordinary room with
nothing above it. Half of every shallow floor stays completely safe.

How many formations one room can physically hold is settled by geometry, so a family's lever on
falling hazards is how many ROOMS are dangerous. Past roughly floor twelve a floor saturates and the
families converge — that is the floor being full, not the scaling failing.

### Room footprints

The invisible square room CELL is unchanged and still owns room indexing, adjacency, graph
connections, overlap prevention, doorway anchors, connector targets and cleanup bounds. What varies is
the OPEN INTERIOR inside that cell: an ordinary room takes one of four outer footprints — Rectangle,
Ellipse, Capsule or TwinLobe — weighted per family, with every family keeping half its ordinary rooms
rectangular. Entry, Basin, completion and Warden rooms are always the full rectangle.

Gameplay safety overrides shape aesthetics. The final open footprint is the union of the shape mask,
the doorway-lane masks, the navigation-hub mask, the protected interaction masks, and every planned
spawn's clearance — so a shape can never seal a doorway, orphan the hub, or bury a fixture. A shape
that would need to is refused before it is recorded, and after a bounded number of refusals the room
falls back to Rectangle. A TwinLobe's neck may never be narrower than the mandatory navigation lane.

### Blast vaults

Sealed dead-end pockets opened with a stick of dynamite (§6a) and by nothing else. From Floor 3, a
floor may carry **none, one, or two**.

A vault is **attached after the loop pass**, which is the whole safety proof rather than a check: it
is a brand-new cell with exactly one doorway, added once the only pass that could have given it a
second one has already run. So it is a leaf by construction — nothing behind that door is ever on the
way to anywhere, and blowing it open can never be progression.

Its single doorway is filled with real rock cut from **that cave family's own palette** — rock in
Stone, mossy rock in Moss, ice in Ice — broken into packed rubble with visible fracture lines, so it
reads as destructible before the player owns anything to destroy it with. A **charge pocket** is bored
into the face; a player *carrying dynamite* sees a yellow outline of the stick marking it, and nobody
else does. One committed interaction places and lights the charge.

**Inside is guaranteed ore and no creature spawns.** That bargain is the point: the cost of the room is
the stick and the noise the stick makes, never a second trap waiting behind the rock. A vault carrying
an authored encounter as well would make opening one a gamble, and the item is too rare to gamble
with. Vaults also never stack with anything else — no vines, no falling formations, no lurker arch, no
flammable growth, no dead candle, and never the Warden's den or the locked store.

**Nothing is sealed in behind you, and nothing is sealed out.** Like every other room, a vault is
ordinary ground for a roaming threat once its door is gone — and the noise of taking that door off is
exactly what tends to bring one. The promise is about what the planner PUTS there, never about what
can walk in afterwards.

### Moss flammable vegetation

Uncommon tagged clusters of dry growth in ordinary Moss rooms — the one thing in the game a player's
own flame can set alight. Never in a protected room, never on the guaranteed route, never across a
doorway lane or a reserved footprint, and at most one per room, so no obstruction one forms is ever
mandatory. Ignition comes only from an uncovered flame above a burn threshold, a burning Decoy, or a
Flare; a cupped flame contributes exactly zero. Fire spreads along the cluster's own planned
connectivity graph and nowhere else: wet walls and ordinary damp moss never burn, and flammability is
never inferred from a colour or a material at runtime. A burning cluster is ordinary environmental
light in the shared light field — it attracts the Drawn and can never force the panic retreat only a
real Flare causes — and its heat costs Living Wax, adding no second meter.

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
- **Basin sacrifice pool weighting** — which progressive costs should appear most often beside perception costs?
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
- **The Cauldron** — the Basin's physical vessel; presentation for the sacrifice, no rules of its own
- **The Gas Lantern** — end-of-run delivery point; lighting it cashes out (the fixture formerly
  called the Brazier — the system, the payout and the code that owns them keep that name)
- **The Descent Elevator** — the two-person cage that carries riders one floor down, then returns empty
- **Snuffed** — extinguished with wax remaining; revivable
- **Burn out** — wax exhausted; terminal; you become a wisp
- **Wisp** — a burned-out player, slightly helpful to the party
- **Dark-hunters** — threats that avoid light and drain wax on contact
- **VoidFly** — territorial dark-hunter; repeated dives snuff, FLARE/grouping repels it
- **The drawn** — threats attracted to light
- **Flare / Decoy / Cup** — the three tools; Cup is the only way to go dark
- **Dynamite** — rare found consumable; the one thing that can kill, and it hurts you too (§6a)
- **Blast vault** — sealed dead-end room of guaranteed ore and no creature spawns, opened with dynamite
- **Unstable dripstone** — rare, warned, one-shot ceiling hazard that removes wax and briefly
  suppresses a surviving flame
- **Doorway barriers** — burning vines in Stone/Moss and meltable barred icicles in Ice; never a room's
  only entrance
- **Stone Warden** — rare three-wax-pickup chasing hazard from Floor 4; stunned only by a falling
  dripstone crown; no dial or tool interaction
- **Remains** — session-local wax pool left by a terminally dead player; global storage is deferred
- **Lineage** *(deferred)* — meta-progression carryover between candles

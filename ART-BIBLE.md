# WICK — Visual & Asset Reference

A prompting reference for generating concept art, 3D assets, textures, UI art, or audio for WICK.
Every color, proportion, and material below is pulled directly from the shipped game config, not
invented — treat this as ground truth for what the game actually looks like today, not aspiration.

**How to use this doc:** each numbered section is self-contained. Copy the relevant section
(mood + style laws + the specific subject) straight into an image-gen prompt. Section 1 and 2
(pitch and style laws) should be pasted into *every* asset prompt regardless of subject — they're
what keeps a dark-hunter, a cave wall, and a UI icon all reading as the same game.

---

## 1. The pitch (paste into every prompt for tone)

A living candle descends into caves that have been dark for a very long time. Health, light, fuel,
and time are all the same resource: wax. Every second lit is a second spent. First-person,
genuinely frightening — dread and hostility, not jump-scare theatrics. A candlelit ghost story, not
an action game. There is no combat; the only power the player has is choosing how bright to burn.

**Mood keywords:** dread, isolation, claustrophobia, dying light, cold stone, held breath, a single
point of warmth in an enormous dark, something patient in the black.

---

## 2. Style laws — non-negotiable, repeat in every prompt

- **Light is the only source of visual information.** Nothing should be visible, colored, or
  detailed except what the candle's flame is currently illuminating. Nothing self-illuminates
  except fire, embers, and the candle's own wax. Everything else is read by warm light falling on
  cold, desaturated stone.
- **Legibility over fidelity — this is the actual art style, not a budget compromise.** Flat,
  readable silhouettes. Failed realism is what looks cheap; deliberate simplicity reads as
  intentional. Do not add surface noise, clutter, or busy detail that competes with the silhouette.
- **Enemies are silhouettes, never fully rendered.** A creature should be identifiable by outline
  and one or two color/light accents (eyes, wing edge) well before any surface detail resolves.
- **Environments are readable geometry, not decorated spaces.** No set dressing, no props, no
  narrative clutter — bare rock, water, and structural form only.
- **Color is almost exclusively warm firelight vs. cold stone/dark.** Any other color (a threat's
  eyes, a wing, a wax type) is meaningful and rare — it should never be used decoratively.
- **Nothing is a flat color-swap reskin.** Each element below has a specific silhouette logic, not
  just a palette.

---

## 3. Camera & light logic

Strict **first-person**, camera anchored just above the candle's own body (so looking down shows
your own shrinking wax column — this shot is a core piece of visual identity, always worth
depicting). One light source exists: the player's own flame, a warm point light whose **range**
shrinks and grows continuously as the player adjusts their burn rate (6–40 studs) and whose
**brightness** does the same (0.5–4). There is no ambient light, no fill light, no skybox glow —
`Lighting.Brightness`, `Ambient`, and `OutdoorAmbient` are forced to zero at runtime. Beyond the
flame's radius is true black. A very faint cool haze/fog sits in the far distance (fog tint ≈
RGB 158, 168, 189, density 0.18) so pitch black doesn't read as a void, but it carries almost no
information — it's a horizon, not a light source.

**Post-processing recipe** (for matching in-engine look in concept renders): restrained bloom only
on the brightest highlights (intensity 0.14, threshold 0.92 — i.e. only near-white points bloom,
not general glow), a warm color grade (tint ≈ RGB 255, 242, 220, +contrast, slightly desaturated),
one soft spherical shadow following the flame. No lens flares, no volumetric light shafts, no HDR
glow blooming — the target look is a real candle in a real dark room, not a stylized fantasy glow.

---

## 4. Color palette

**The air is part of the palette.** Each cave family sets its own Atmosphere density, haze and glare,
not just a tint — and density is the property a player actually *feels*, because it decides how far
the candle reaches before the dark closes, which in a game where light is the only source of visual
information is the same question as how big the world is. Moss has the thickest air in the game (a
flame dies sooner, distance is simply hidden); Ice has the thinnest and the most haze (light carries,
and a long hall has a visible far end); Stone is the reference both are authored against. Glare is the
small bloom right around the flame — moisture in Moss, ice crystals in Ice, nothing in Stone.

**None of it may light the cave.** The rules below bind every family, and the family validator holds
density above a hard floor for exactly this reason: a family may change how far your flame carries, and
may never change whether you need one. Thin air must never become "you can see across an unlit room."

**Rock is authored for saturation, not for brightness.** Candlelight is warm (~255, 242, 220), so it
multiplies red by 1.0 and blue by only ~0.86 — meaning rock whose blue merely *exceeds* its red
arrives at the eye as neutral grey-brown, because the light spends the difference on the way. A cave
that is nominally blue and still reads as a muddy tunnel is always this mistake. The fix is never to
brighten it: widen the blue-to-red gap at the source instead. Ice runs roughly 5:1, which costs almost
no luminance (blue carries 7% of perceived brightness against green's 72%) and is why its rock can be
*darker* than a neutral grey while reading distinctly colder. Green is the channel to watch — it is
72% of perceived brightness, so a teal drifts over a darkness bound long before a blue does.

**A surface is defined by how it hands the candle back, not by its colour.** This is the single most
useful idea in this section and the one most often missed. The eye identifies a material by its
SPECULAR behaviour — whether a highlight sits still, slides, or never appears — long before it reads
hue, and in a world lit by one moving flame that behaviour is nearly all the information there is. Ice
frost was once authored as a well-chosen blue with every facet opaque, matte, one material, and flush
against the wall; it rendered as blue cardboard, and no amount of retinting reached it. What fixed it
was `presentation.coverFinish` / `formationFinish`: per-facet **material, transparency, reflectance and
tilt**, all as RANGES. The ranges are the point — adjacent facets must answer the same flame
*differently*, or the surface reads as one moulded object however good the single value is. A uniform
reflectance is only slightly less flat than none, because then the whole wall flashes at once.

**Nothing in any cave emits, and reflectance is the honest version of wanting it to.** A self-lit
"cold light" channel — faint cyan wall seams plus a small lit crystal landmark per chamber — was
built and cut. On screen it read as glowing sticks floating in the dark, not as ice, and it bought
visibility the game is designed not to give away. Reflectance reaches the same instinct correctly: it
makes a surface catch the light the player *brought*, so it raises how good the ice looks without
touching how much anyone can see. If a future surface needs to be seen, the answer is always
reflectance, transparency and silhouette — never emission.

**Candlelight (warm — the only "alive" colors in the game):**
| Role | RGB | Notes |
|---|---|---|
| Flame core | 255, 247, 222 | near-white-hot center |
| Flame mid | 255, 186, 92 | |
| Flame outer | 255, 116, 44 | tip/edge, fades toward transparent |
| Ember / UI accent gold | 255, 150, 66 | primary "lit" accent color everywhere (UI, embers, glow) |
| Ember deep | 190, 84, 38 | |
| Gold (logo/UI highlight) | 255, 201, 120 | |
| Danger / low-wax red | 255, 92, 60 | |

**Wax (the character):**
| Role | RGB | Notes |
|---|---|---|
| Wax body | 235, 225, 200 (body) / 243, 234, 212 (UI) | warm bone/cream, not pure white |
| Wax deep shade | 203, 187, 155 | |
| Rim (melted lip) | 242, 233, 210 | slightly brighter than body |
| Wick | 35, 28, 22 | near-black char |
| Dripped wax trail | 112, 88, 62 | dull matte brown, **never glowing, never Neon** |

**Cave rock (cold — everything NOT lit by the flame):**
| Role | RGB | Notes |
|---|---|---|
| Rock formation variants | 52,56,66 / 62,66,78 / 45,49,59 / 70,73,84 | cool blue-charcoal slate tones |
| Damp rock tint | 28, 31, 39 | near-black, used where wet |
| Materials | Slate, Basalt, Concrete, Rock (Roblox material set) | matte, non-reflective; wet patches get slight Slate reflectance only |

**Water:**
| Role | RGB | Notes |
|---|---|---|
| Pool surface | 42, 66, 92 | dark teal-blue-grey, semi-transparent, faint sheen, no glow |

**Void / atmosphere:**
| Role | RGB | Notes |
|---|---|---|
| True black / unlit | 9, 8, 10 | as close to pure black as UI/void surfaces get |
| Distant fog | ~158, 168, 189 (density 0.18, haze 0.65) | very faint cool grey-blue, horizon only |

**Threats (see §6 for full creature descriptions):**
| Role | RGB | Notes |
|---|---|---|
| Dark-hunter body | 5, 3, 7 | essentially pure black |
| Dark-hunter eyes | 128, 0, 7 | deep blood-crimson, narrow angled slits |
| The Drawn body | 48, 45, 44 | charcoal-taupe stone-grey |
| The Drawn thorax | 67, 62, 59 | slightly lighter taupe |
| The Drawn wings | 112, 106, 101, ~18% transparent | pale grey-taupe, translucent |
| The Drawn eyes (calm / attracted) | 255, 214, 120 → 255, 236, 168 | faint warm yellow, brightens with attraction — never red |
| VoidFly wings | 78, 75, 82 | cool grey-violet, translucent |
| VoidFly eyes | 22, 19, 18 | UNLIT — glass, low reflectance, no glow of any kind (see §6b) |
| Dead candle wax / spilled pool | 196, 188, 172 / 170, 162, 148 | cold grey-white spent wax; emits nothing |

**Unstable dripstone (hazard):**
| Role | RGB | Notes |
|---|---|---|
| Collar/pivot | 38, 40, 47 | |
| Crown | 49, 51, 59 | |
| Fracture lines | 17, 18, 22 | near-black, the "tell" |
| Dust | 82,78,72 fading to 40,40,43 | pale to dark as it settles |

**UI accent (see §11):** near-black panel 18,15,18 · bronze/lit-stone stroke 120,96,66 · warm text
237,227,209.

---

## 5. The player character — the candle

**Silhouette:** a short, stumpy, hand-dipped tallow candle — NOT tall and elegant. Wide cylindrical
body, melted drooping rim at the top edge, a short dark charred wick, one modest elongated flame.
Reads as humble and mortal, not decorative.

**Exact proportions (studs, for 3D modeling reference):**
- Body: cylinder, radius 1.4, height ranges from **4.0 at full wax down to 0.8 near burnout** — the
  single most important visual rule in the whole game: *the body height IS the health bar.* Always
  depict this shrinking relationship when illustrating the wax mechanic.
- Melted rim at the top: height 0.3, ~12% wider radius than the body — a soft drooped lip of
  melting wax, not a sharp edge.
- Wick: thin dark cylinder, ~0.45 tall, protruding from the rim.
- Flame: one elongated flame-shape (teardrop, narrower than tall — roughly 0.63 wide × 1.08 tall at
  base scale), warm orange gradient core-to-tip per the flame palette above. Flickers with slow
  organic drift, body flutter, and fine turbulence — never a mechanical loop, never a strobe.
  Occasionally gutters/dims briefly and recovers, like real fire fed by imperfect air.
- Default running: the flame stretches taller/narrower and leans backward ~10°, as if straining against
  its own speed — presented as strain, never as a power-up glow.
- Material: matte, soft-lit wax surface — SmoothPlastic-equivalent, not glossy/wet, not glowing
  itself (only the flame and its light glow; the wax body is lit *by* the flame, it doesn't emit).

**Camera relationship:** the player's eye sits just above the body's top surface. Looking straight
down reveals the body and rim. Other players' candles are seen at full height including the flame.

**Prompt-ready line:** *"A short stumpy tallow candle, wide cylindrical body of warm cream wax with
a melted drooping rim, dark charred wick, one flickering warm-orange elongated flame, sitting in
absolute blackness, softly lit only by its own flame, matte non-glossy wax surface, no other light
source, first-person low-angle view looking down at the candle's own shrinking body."*

---

## 6. Creatures

Shared rule for all creatures: **connected, gaunt, one-piece silhouettes** — the game explicitly
moved away from "floating spheres and rods" toward single readable bodies after early playtesting
flagged that primitive-part creatures didn't read as one creature. Always draw/model as one
continuous form, not a cluster of separate primitive shapes.

### 6-0. Cave-family dressing — what a family may do to a creature

A creature standing in Moss or Ice is the SAME creature, weathered. The family adds **real additive
geometry on an unchanged skeleton** — never a recolour, and never a different build:

- **Moss — shag.** Short wet growth caught where a body actually collects it: the shoulder yoke, the
  outer thigh, the forearm. A few strands hang long enough to sway on the gait, so a Moss body's
  MOVEMENT reads half a beat before its outline does. Skin material goes to coarse wet rock.
- **Ice — rime.** Pale frost plates crusted on **upward-facing surfaces only** — shoulder tops, the
  back of the crown, the tops of the feet — plus thin spurs off the elbow and heel that catch the
  flame exactly as a limb swings. The upward-only rule is what sells it as weather rather than paint.
- **Stone — nothing.** Bare. It is the reference every creature was authored against.

**What a family may NEVER touch, in any creature, ever:** proportions, joint layout, animation,
silhouette category, the crimson dark-hunter eye slits, the Drawn's wings and warm yellow halo, and
**the head** — growth is refused on the skull and brow whatever the coverage says, so the eyes are
still the first thing that resolves at range in every cave. Growth palettes are drawn from each
family's COVER colours, which sit apart from its ROCK colours, so a dressed creature stands out
against the wall behind it rather than blending into it. **A threat may be dressed for its cave and may
never be camouflaged against it.**

The two set-pieces are the exception that proves the rule: the Ashamed Lurker's wall socket and the
Warden's courses take their family's actual rock, because both creatures are *supposed* to be
mistakable for the wall until they move. Their flesh is identical in every cave.

### 6a. Dark-hunters — avoid light, drain wax on contact

**Silhouette:** a near-black, gaunt, humanoid figure — connected body, deliberately hard to resolve
at range even when lit, meant to remain ambiguous rather than fully readable. The **only** clearly
visible feature at a distance is a pair of **narrow, angled, deep-crimson eye slits** — the eyes
should read as a warning glimpsed before the body is ever confirmed. The eye slits are angled
(~20°), narrow, and glow faintly (this is the ONE emissive element on an otherwise fully
non-reflective, light-absorbing black body). The body itself must never be lit brightly enough to
reveal detail — it stays a silhouette even in direct flame light.

**One creature, one body.** This used to be listed as three "variants" separated by size and stats —
but they always shared this exact silhouette, nothing in the game ever labelled them, and the audio
cues were called `DarkCrawlerAttack` and `DarkCrawlerLunge` for all three. They are now one row whose
sensing, light resistance and hearing sharpen with depth (`Config/Threats.DarkCrawler.depthScaling`).
Nothing about the art changes with depth, and deliberately so: a body that silently grew or shifted
as a run went on would be one the player could never finish learning to read.

**Prompt-ready line:** *"A gaunt, near-black humanoid silhouette in absolute darkness, body
completely unlit and unreadable, only a pair of narrow angled deep-crimson glowing eye slits
visible, connected one-piece figure (not separate floating parts), horror creature design, avoids
light, first-person candlelit horror game."*

### 6b. VoidFly — tiny territorial ceiling-dweller

A **tiny** dark-hunter (silhouette scale roughly 1/3 the size of the ground hunters) that circles one
fixed patch of cave ceiling and dives down at anything passing beneath. Same near-black dark-hunter
body language, but insect/bat-like in proportion — compact body, small translucent grey-violet wings
(RGB 78,75,82, ~20% transparent). Reads as a territorial cave insect, not a full humanoid. Stays
close to the ceiling except during its dive.

**It is the one dark-hunter with NO eye glow, and that is the creature.** It used to carry the
family's red-eyed warning tell, which made a fly on a dark ceiling a pair of embers hanging in the
black — findable from further away than it is dangerous from. Its eyes are now unlit, near-black and
wet-looking (RGB 22,19,18, glass, low reflectance): two specular points a candle finds, and nothing
at all without one. What replaced the glow is **sound** — it never parks, and its buzz is the whole
warning. Every other dark-hunter keeps its crimson slits; this is a deliberate single exception, not
a drift in the family palette.

**The dead candle (Floor 10+ tableau).** Somebody else's candle, fallen and burned out: a stubby
cylinder of cold grey-white wax leaned over at ~72 degrees with a black wick still in it, lying in a
thin set pool of its own spill flush with the rock. **It emits nothing** — every other candle in the
game is a light source, and this is the silhouette of one with the light taken out, so it is only
ever found inside the player's own. Three pickups lie in a ring around it and three VoidFlies hold
the ceiling above; the scene should read as a story from across the room and as a decision up close.

### 6c. The Drawn — moth logic, attracted to light

**Silhouette:** neutral **stone/taupe** colored moth-form (explicitly NOT black, NOT colorful — a
warm-grey earth tone that won't compete with flame color or hunter-red). Body RGB 48,45,44 with a
slightly lighter taupe thorax (67,62,59). **Broad vertical wings** are the dominant visual feature —
large, pale grey-taupe (112,106,101), softly translucent (~18%) — layered moth wings that must
remain clearly visible framing the body; the design must NOT collapse into a narrow
"sphere-and-rods" reading at a distance. Wings, not the body, are what should be legible first.

**Eyes:** a pair of compound eyes with a soft halo behind each one — a small **faint warm yellow**
glow (RGB 255,214,120), explicitly **not** red (red is reserved for dark-hunters, and the two
families must never be confused at a glance). This is a "found light," not a warning: dim and easy
to miss at rest, brightening toward a warmer near-white-yellow (255,236,168) specifically as the
moth is actively drawn in and closing distance — the eye glow is a readable tell for how urgently
it wants your flame right now.

**One creature, one body.** Four "variants" used to be listed here, and the entry for the rarest
admitted the problem outright: it shared the exact same silhouette, palette and eye glow, and was
distinguished only by extinguishing on contact instead of draining. A variant a player cannot see is
not a variant. They are now one cave moth, and the behaviour that was worth keeping is a property of
it: unbroken contact past the early floors puts your candle out rather than only costing wax
(`Config/Threats.Moth.sustainedContact`). The tell for that is the **eye glow already described
above** — brightening as it closes — plus the wax bar, not a second body.

**Prompt-ready line:** *"A large pale taupe/stone-grey moth creature, broad translucent layered
wings dominating the silhouette, neutral earthy grey-brown body (not black, not colorful), a pair
of faint warm yellow glowing eyes (not red) with a soft halo, drawn toward a candle flame in total
darkness, wings clearly readable and never collapsing into a thin silhouette, horror-adjacent but
not monstrous — insect logic, not predator logic."*

### 6d. Signature creatures — one per cave family

All three are dark-hunters and all three carry the crimson angled slits, so the category read is
unchanged. Each is found in exactly one cave.

**CAVE LISTENER** (Stone). A wedge nosing along the floor, not a person: hips high, shoulders low, an
enormous flattened skull carried almost dragging. **No eyes in the usual place** — the crimson tell
runs along the JAW LINE of that skull instead, same colour, same ~20° angle, same faint glow. Two
broad membranous ear fans spread off the sides of the head and are the animated tell: slack and folded
while it is drifting, swept forward and taut the moment it has heard something. The membranes are the
one surface on this creature light passes THROUGH rather than dying in.

*Prompt-ready line:* *"A low, wide, four-limbed near-black creature with an enormous flat spade-shaped
skull held near the ground, two large translucent ribbed ear-fans spread from the sides of the head,
no visible eyes except thin crimson glowing slits along the jaw, blind and listening, candlelit horror
cave, connected one-piece body."*

**KNOTWALKER** (Moss). Built to thread a gap: extremely narrow across the shoulders, short-legged,
with forelimbs longer than its whole torso carried raised and forward, reaching. Collarbones sweep
FORWARD rather than out so the shoulders can fold through an opening. A small head held high — small
because all a player needs from it is the two slits. **The hands are the warning:** the reach extends
and the fingers spread when it has committed to a prediction, and fold in when it has lost you.

*Prompt-ready line:* *"A tall, extremely narrow near-black humanoid creature, almost invisible
head-on, with very long thin reaching forearms and spread bony fingers held forward, small high head
with narrow angled crimson glowing eye slits, squeezing through a gap in wet cave rock, candlelit
horror, connected one-piece body."*

**CALVER** (Ice). A plate with limbs, pressed flat to the ceiling — 2.3 studs across and barely half a
stud deep, with overlapping back plates. Six limbs: four splayed grippers hooked up into the rock, and
two heavy forelimbs folded back over its own carapace that exist only to swing down into the ceiling.
Those two are thicker than anything else on it, and a player who looks up sees a shape with hammers on
it. **Eyes face DOWN**, on the underside of a head that hangs below the leading edge, so the crimson
is where somebody standing beneath can actually see it. It never comes down.

*Prompt-ready line:* *"A wide flat near-black six-limbed creature clinging upside down to a cave
ceiling, overlapping dark carapace plates, four splayed hooked gripping limbs and two thick heavy
hammer-like forelimbs folded over its back, small downward-facing head with crimson glowing eye slits
looking at the floor below, candlelit ice cave, connected one-piece body."*

---

## 7. Environment — the caves

**Philosophy:** natural, irregular, grey rocky caves with variance baked into generation — never a
decorated space. Color exists almost nowhere except flame light falling on stone, and the muted hue of the rock a cave family is cut from — Stone cool blue-charcoal, Moss dark wet green-grey, Ice saturated cold blue. No family is bright and nothing in any cave emits — what separates the three is hue, surface finish and silhouette (§4).

- **Ice's own dressing** (all collision-neutral, all data-driven from `presentation`): sparse flat
  panes of clear ice over the floor so it stops reading as one poured surface; chunky low-poly icicle
  clusters across ceilings and, more importantly, hung on the actual arch curve of every doorway,
  because a player looks at an opening before walking through it; angled frost shards on walls and
  ground. Its frozen doorway barricades are built from four layers — crust welded into the arch and
  jambs, uneven hanging fangs, shorter floor spikes offset to interlock with them, and frost bloom —
  and melt tips-first rather than fading out. A barricade must always read as ice that GREW in the
  opening, never as a gate somebody installed in it.

- **Rock:** jagged, broken, multi-facet formations — boulders, spires, ceiling straws/stalactites,
  broken angular wall shards. Materials are Slate/Basalt/Concrete/Rock in the cool dark palette
  from §4 (never warm-toned rock). Wet surfaces get a faint Slate sheen, never a wide reflective
  puddle-shine.
- **Floors:** broad, overlapping, ramped rock shelves — the ground is genuinely uneven and climbed,
  not a flat plane with props scattered on it. Only doorway lanes and special-purpose room centers
  (spawn, Basin, Brazier) stay level.
- **Ceilings:** irregular, sealed, cavern-like relief — broad rolling waves plus smaller rocky
  ripples, never a flat slab. Ceilings blend smoothly into walls and doorway arches.
- **Doorways:** each connection between rooms is a rough, jagged rock-cut opening, varying
  significantly in width and height from one doorway to the next (roughly 8–56 studs wide, 8–13
  tall) — no two openings should look like repeated copies of the same doorway cutout.
- **Burning-vine curtains:** a dark, gnarled root crown grown into the arch with two sparse ranks of
  crooked hanging roots, short woody side branches, and occasional dry seed pods. Narrow black gaps
  remain between roots; the curtain is a connected thorny silhouette, never an opaque green sheet.
  Bark is near-black wet olive-brown Wood, while the tiny dead pods are muted dry tan and matte.
  There are no broad leaf plates and no Grass/LeafyGrass material; those tile into bright rippling
  noise under a moving candle. Qualifying maximum-brightness light produces orange embers across the
  root face immediately, without a PointLight; the cold plant itself never glows.
- **Scale reference:** rooms use compact 64-stud cells, ceilings range from tight low crevices
  (~15 studs) to tall caverns (~46 studs).

**Prompt-ready line:** *"An irregular natural cave interior, jagged broken grey-blue slate and
basalt rock, uneven ramped rock-shelf floor, sealed rocky uneven ceiling with no flat surfaces, a
rough asymmetric rock-cut doorway opening to another chamber, completely unlit except for one warm
point of firelight from off-frame, everything outside the light pure black, no decoration, no
props, natural stone only."*

---

## 8. Environmental hazards

**Water pools:** small, localized, recessed pools/puddles — never room-covering lakes. Dark
teal-blue-grey (RGB 42,66,92), semi-transparent with a faint animated sheen, no glow, no
particle effects beyond subtle surface motion. Dry rock always rings the pool; the bed slopes
gradually to a shallow bank rather than a hard drop, so the water reads as a natural low point in
the rock, not a level-design wall.

**Unstable dripstone (rare one-shot hazard):** a hanging ceiling rock formation with a visible
*tell*: an off-axis lean, a dry near-black fractured collar (RGB 17,18,22) at its base/neck, and
sparse falling dust (pale 82,78,72 settling to dark 40,40,43). Three named silhouette variants,
all sharing this collar/lean/dust language:
- **Needle** — a single narrow tapering spire, most delicate.
- **Fork** — a two-pronged split formation.
- **Hammer** — a heavy three-pronged, blunt formation, largest and most ominous.

No glow, no particle sparkle, no UI marker on any of these — the warning is entirely geological and
must be readable by eye alone (lean angle + dark fractured collar + falling dust).

---

## 9. Special rooms

**The Basin:** a still chamber holding raw molten wax — the quiet room per floor. Should read as
warmer and calmer than the rest of the cave, a place of ritual rather than danger. At its centre is
**the Cauldron**: a squat iron or stone vessel on a three-legged tripod standing on a low cairn,
molten amber wax sunk below a proud rim and moving slowly, cooled wax run down the outside in the
drip trail's own dull brown, and a dull ember hint under the belly. Family-tinted like every other
built object. The offer itself stays private — each player experiences it alone.

*The wax surface and the coals are Neon and carry no PointLight. They are visible in the dark without
lighting one voxel of rock, which is the exact line §4 draws — the Basin is a room you find with your
own flame, not a lamp.*

**The Gas Lantern:** the end-of-run delivery point, and the one flame in this game the player does not
have to carry. Enclosed glass panes in an iron frame on a low post, with a valve, a burner and a vent
stack; a chain hangs off the post whose length is how deep this run has come. Cold and dark until it
is lit — unlit glass, dead wick, nothing glowing — so the ignition keeps its full impact, the same way
the blast door reads dead until it is blown.

Lighting it clears the panes rather than brightening them, so what you see is the flame behind them: a
hot pale blue-white core with warm orange tips. **Not candle-orange** — that belongs to the flame the
player carries, everywhere, always — and **not the old descent blue**, which read cold and hostile and
has been retired with the beacon it belonged to. The lamp then throws restrained amber light, the
single deliberate exception to "the candle is the only light source" in the whole game. Exactly one
matching cold wall lamp lives in every generated cave room and catches outward when the Gas Lantern is
lit; the completion room's sole lamp is the interactive Gas Lantern, with no companion. Each fixture
mounts just proud of the nearest real Terrain wall surface, never in a carved recess, floor circle, or
decorative rack, and no fixture should bleach the rock white. The backplate follows the wall's horizontal
room-facing normal without cutting a flat indent into sloped rock. A small amber point glow belongs to
the glass; a broad, restrained beam faces into the room and
does the useful lighting without enlarging the visible flame.

**The Descent Ladder:** what an expedition rigs for itself once it is past the company's polished
lobby car. A one-person open-frame cage on a chain winch, standing in a headframe over a shaft cut
into the chamber floor, with a hatch that folds over the mouth when the cage is away. Open framing is
load-bearing on the whole idea — the rider has to see real rock going past. Family-styled like the
vault door: iron-banded timber in Stone, lashed wood on knotted rope in Moss, chipped ice on a
frost-crusted chain in Ice.

**One work lamp hangs off its headframe**, just outside the mouth: the Gas Lantern at three-quarter
size, already burning, on a bracket with its own bail and hook. It is the only lit thing on the
fixture — the cage, the shaft, the collar and the hatch are all dark, so the ride itself is lit by
the rider's own candle and by nothing else. It exists because retiring the cyan descent beacon left
the way down as a dark rig you could walk past, and it says "a machine is over here" the way a lamp
somebody hung would, rather than the way a magic blue pillar did. Dim enough that the far wall of the
chamber stays black.

*The Gas Lantern, cave-network lamps, and work lamp are deliberately the same object at related sizes
— same panes, same frame, same cap, same bail — so they read as the expedition's own equipment rather
than as unrelated props. The perception field never sees any of them; see §3.*

**All three stand in one chamber**, the Cauldron at its centre with the Lantern and the Ladder at
opposite quarters. The room a floor is scored in is the room it ends in.

---

## 10. The wax drop trail

Small, dull, irregular blobs of cooled wax left behind on the ground when moving — flattened
teardrop/disc shapes (~0.18 studs), color RGB 112,88,62 (dull brown, matte). **Critically: these
never glow, never emit light, never use an emissive/Neon material.** They are a purely physical,
inert trace — visual evidence of passage, not a light source or particle effect.

---

## 10b. Dynamite, and the one glowing thing in the cave

**The stick and the crate obey every rule above.** A stick is a slim deep-red waxed-paper tube
(RGB 139,46,38) with two darker wrap sleeves, a pale label band (188,170,138) across the middle, a
hard near-black crimp at each end, and a fuse built as several short segments walked along a curve so
it reads as cord rather than as an aerial. The four reads that matter — slim body, notched ends, pale
band, angled fuse — are chosen to survive being three-quarters in shadow at candle range. **Nothing on
it glows**, and a crate is the same object at three-quarter size, four of them standing in an
open-topped wooden box with two iron bands. No lid: what is in it must be readable from outside.

**The blast door** is packed rubble cut from that cave family's own rock, with dark fracture lines
across the face. It has to look *destructible* before the player owns anything to destroy it with,
which is why it is many small broken facets rather than a slab — a flat plane reads as the edge of the
map.

**The socket marker is the one deliberate exception in this document**, and it is narrower than it
looks. It is a Neon yellow stick (RGB 255,214,74) marking the door's charge pocket, drawn **only for a
player who is actually carrying dynamite**, and it carries **no PointLight**. So it is visible in the
dark without illuminating a single voxel of rock: you still cannot see the door, the room, or anything
in it by its light. It is closer to a HUD element that happens to live in world space than to a light
in the cave, and §4's rule that light is the only source of visual *information about the world* is
untouched. **Yellow specifically** because every other readable glow is already spoken for — crimson
is a dark-hunter's eyes, warm orange is flame, and pale yellow is a Drawn's halo, so the marker is
pitched brighter and colder than the last of those. A burning fuse's spark head is the same kind of
exception for the same reason: bright pixels, zero light emission.

---

## 11. UI & logo

**UI palette:** near-black stone panels (RGB 18,15,18 base, 27,22,25 raised), bronze/lit-stone
edges and strokes (RGB 120,96,66 / 64,53,46 soft), warm parchment-cream text (237,227,209), muted
secondary text (163,150,135). Accent color throughout is the same ember/gold family as the
candlelight palette in §4 — UI should feel like it's lit by the same fire as the game world, not
like a separate modern interface layer.

**The WICK wordmark/logo:** composited from UI shapes rather than an uploaded image — letters "W",
"C", "K" rendered in a gilded gold-to-ember gradient wash with a warm rim light; the letter "I" is
replaced by a small **live candle glyph** (a miniature version of the player candle, complete with
its own flickering flame) — the flame is the wordmark's focal light source. This candle-as-letter
motif is the game's core visual signature and should be the centerpiece of any logo/key-art work.

**The wax-bar HUD:** the primary HUD element is a small candle rendered in UI (not a generic
health bar) — a wax column that visibly shortens as the player burns, with its own small
procedural flame (glow disc + two-layer flame body) that brightens/whitens with burn intensity and
reddens when wax is critically low. Reinforces "you are the candle" at all times on screen.

---

## 12. Audio mood direction

(Grounded in documented tone/design intent — the game currently has minimal actual audio content,
so treat this section as a brief for what needs to exist, not a description of finished audio.)

Horror carried primarily through **sound in the absence of sight** — since almost everything is
visually dark, hearing must do the work vision can't. Target mood: dread and hostility, not jump
scares; a genuinely frightening candlelit ghost story, not tense-but-safe ambience. Key needs:
quiet, positional creature audio that lets a blind player identify threat direction and category
by ear (a dark-hunter should sound different from the Drawn); a constant low bed of cave
ambience/dread rather than silence; restrained, natural stingers for tool use, damage, and death
that don't undercut the quiet; and music that stays sparse and infrequent (long silent gaps between
tracks) so it never competes with the moment-to-moment audio cues players actually need to survive.

**Each cave family sounds different, and only in one axis: RATE.** Moss is the wettest and busiest —
calcite ticks, water drips and a close wall-seep that reads as a few studs away. Ice is the driest and
quietest — strata strain, air down long open halls, and a low glacier groan authored to the CEILING,
because in the family whose signature pressure hangs overhead the cave's own voice should come from
where the danger is. Stone is the baseline both were written against.

**A family may change how OFTEN a sound plays. It may never change how LOUD anything is** — not a
cue's gain, not its bus, not the mixer. That separation is what stops "this cave sounds different"
from becoming "this cave hides an approaching threat," and it is enforced in the family validator
rather than left to taste. Cave music stays one shared pool: it plays for a few minutes every fifteen,
so it is the wrong layer to carry identity, and splitting a handful of tracks three ways would make a
family loop one track for a whole descent.

**Reverb is the acoustic size of the cave, and it colours everything.** Each family scales the
authored per-bus reverb rather than replacing it, so the deliberately different tails for ambience,
world and focus audio keep their relationship while the space they describe changes. Moss is dead and
close (decay ×0.60): tight knotted rooms, the densest internal formations in the game, and soft wet
growth over every surface, so sound has nowhere to run and nothing hard to come back off. Ice is long
and hard (×1.65): the fewest formations, the longest connectors, the tallest ceilings, every surface
glassy — a sound you make in Ice comes back to you, which is the family's exposure expressed in the
one channel that reaches you even with your eyes shut. Stone is the authored mix untouched.

**You hear your own footsteps, and they tell you what you are standing on.** Flat slate rings, wet
growth absorbs, packed glacier crunches, and standing water overrides all three. The cadence is paced
from measured speed rather than a timer, so Cup-slowed movement is audibly slower underfoot and a
sprint is audibly faster — your own body is a readable signal about your own state. Two rules bind
this layer: it sits **under** creature locomotion, because your feet must never mask the thing you are
straining to hear; and it is **self-audible only** — walking emits nothing the cave can hear, or every
listening threat would hold a permanent track on every moving player.

---

## 13. Quick-reference block (paste before any single-asset prompt)

> Dark, near-total-black horror environment lit by exactly one warm candle flame (point light,
> range varies). Flat, legible silhouettes — legibility over fidelity, deliberate simplicity, not
> a budget shortcut. Cold desaturated blue-grey stone (RGB ~52-70, 56-73, 66-84) everywhere light
> doesn't reach; warm orange-gold firelight (RGB ~255,150-247,44-222) is the only saturated color
> in the frame. No ambient light, no glow except fire/embers, no decorative color. First-person.
> Genuinely frightening tone — dread, not jump scares. No combat, no gore, no weapons.

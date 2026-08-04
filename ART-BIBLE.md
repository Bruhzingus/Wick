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

A **tiny** dark-hunter (silhouette scale roughly 1/3 the size of the ground hunters) that clings to
one fixed patch of cave ceiling and dives down at anything passing beneath. Same near-black
dark-hunter body language and faint red-eyed warning tell, but insect/bat-like in proportion —
compact body, small translucent grey-violet wings (RGB 78,75,82, ~20% transparent). Reads as a
territorial cave insect, not a full humanoid. Stays close to the ceiling except during its dive.

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
decorated space. Color exists almost nowhere except flame light falling on stone, and the muted hue of the rock a cave family is cut from — Stone cool blue-charcoal, Moss dark wet green-grey, Ice dark blue-grey. No family is bright and no family emits light.

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

**The Basin:** a still, safe chamber holding raw molten wax — the one guaranteed-safe room per
floor. Should read as warmer and calmer than the rest of the cave (an amber-lit floor/glow), a
place of ritual rather than danger — a shallow stone basin/font of glowing liquid wax at its
center, private (each player experiences it alone).

**The Brazier:** a tall stone pedestal/bowl built to be lit — the end-of-run delivery point. Reads
as a destination and a decision point: imposing, ancient, stone construction, unlit until a player
commits their wax to it, at which point it should read as a triumphant but costly release of light
and warmth (the "pouring yourself in" moment).

---

## 10. The wax drop trail

Small, dull, irregular blobs of cooled wax left behind on the ground when moving — flattened
teardrop/disc shapes (~0.18 studs), color RGB 112,88,62 (dull brown, matte). **Critically: these
never glow, never emit light, never use an emissive/Neon material.** They are a purely physical,
inert trace — visual evidence of passage, not a light source or particle effect.

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

---

## 13. Quick-reference block (paste before any single-asset prompt)

> Dark, near-total-black horror environment lit by exactly one warm candle flame (point light,
> range varies). Flat, legible silhouettes — legibility over fidelity, deliberate simplicity, not
> a budget shortcut. Cold desaturated blue-grey stone (RGB ~52-70, 56-73, 66-84) everywhere light
> doesn't reach; warm orange-gold firelight (RGB ~255,150-247,44-222) is the only saturated color
> in the frame. No ambient light, no glow except fire/embers, no decorative color. First-person.
> Genuinely frightening tone — dread, not jump scares. No combat, no gore, no weapons.

--!strict
-- CAVE FAMILIES — the one authoritative description of what a cave IS.
--
-- Wick ships three mechanically distinct families: Stone, Moss and Ice. All three begin at global
-- depth 1. Moss and Ice are not deeper starting points; they are harder because their difficulty
-- grows faster, their maps generate differently, their environmental pressure differs, and their
-- native ore is worth more. Passive wax drain is IDENTICAL in all three (see `waxDrainMultiplier`):
-- a family may never be harder because an unavoidable timer runs faster, only because of things a
-- player can read and respond to.
--
-- THIS FILE IS THE ONLY PLACE A FAMILY IS DESCRIBED. `Config/CaveTiers` is derived from these rows
-- (it exists so the numeric tier id the lobby, shop, party and persistence layers already speak
-- keeps working); `Logic/CaveFamilyRules` owns evaluation and validation; nothing else may branch on
-- a family id. A new family is a new row here plus its threat-ecology and presentation entries — not
-- a new code path.
--
-- WHAT A FAMILY OWNS, in one list, because it has grown past what any one section conveys:
--   * DIFFICULTY — base and per-band threat/hazard multipliers.
--   * TOPOLOGY AND GEOMETRY — loops, branches, ceilings, doorway widths, room footprints.
--   * ENVIRONMENT — water, vines, whether anything in it burns.
--   * THREAT ECOLOGY — which of the roster it draws, and its own signature creature.
--   * HAZARD ECOLOGY — which falling formations its ceilings hang.
--   * AMBIENCE — how often the cave makes each of its sounds.
--   * PRESENTATION — rock, cover, formations, and what has grown on the creatures living in it.
--   * ORE — what its rock is made of and why anyone would come here.
--
-- Note what is NOT in that list: no stat, no radius, no speed, no perception value and no cue gain.
-- A family decides what a cave CONTAINS and what it is MADE OF. What a creature does once it is in
-- front of you, and how loud anything is, are the same everywhere.
--
-- WHY FAMILIES AND NOT "BIOMES". The old prohibition in DESIGN §16 / GAME-BRIEF §19 was against
-- COSMETIC biome duplication: the same cave three times in different colours. That prohibition
-- stands. A family must change topology, environmental pressure, threat ecology, or another existing
-- system; all three share one generator, one validator, one survival resource, and the same
-- no-combat rules.

local Types = require(script.Parent.Parent.Types)

-- Stable, persisted identifiers. Display names are presentation and may be retuned freely; these
-- three strings are written into save data and must never change.
export type CaveFamilyId = "STONE" | "MOSS" | "ICE"

-- The four outer room footprints an ordinary room may take (Logic/RoomFootprint). The invisible
-- square room CELL is unchanged by all of them — see that module for why that separation matters.
export type RoomShapeKind = "Rectangle" | "Ellipse" | "Capsule" | "TwinLobe"

-- Keyed by Config/Depth band id ("Introduction", "Standard", "Dangerous", "Expert", "Extreme").
export type BandMultipliers = { [string]: number }

export type TopologyProfile = {
	-- Multiplies Config/Floors.loopConnectionChance and the minimum guaranteed loop count. >1 means
	-- more cycles, so more rooms have a second way out.
	loopBias: number,
	-- Multiplies the chance assembly branches from an older room rather than continuing the newest
	-- chain. >1 means more optional side branches hanging off the main route.
	optionalBranchBias: number,
	-- Multiplies the chance a placement is allowed to fold back beside an existing room. <1 spreads
	-- the floor out into longer runs; >1 compacts it into knots.
	connectorLengthBias: number,
	-- Scales the ceiling roll's spread around its family's preferred band. >1 = more extreme highs
	-- and lows in one floor.
	verticalVariation: number,
}

export type GeometryProfile = {
	-- Multiplies the open footprint's extent inside the room cell. Stone is exactly 1 at both ends,
	-- which is what keeps a Stone Rectangle bit-for-bit identical to the pre-family generator.
	roomSizeScaleMin: number,
	roomSizeScaleMax: number,
	-- The ceiling band this family PREFERS. The roll still spans the full
	-- Config/Floors.geometry.ceilingMin/MaxHeight range; `ceilingPreferenceStrength` is how strongly
	-- it is pulled toward this window, so every family keeps some tall and some tight rooms.
	ceilingPreferredMin: number,
	ceilingPreferredMax: number,
	ceilingPreferenceStrength: number, -- 0 = ignore the preference, 1 = always inside it
	-- Multiplies collidable internal formation counts (boulders, rock columns, root/ice masses).
	internalFormationDensity: number,
	-- Multiplies the rolled doorway width. NEVER allowed to take an opening below the shared safe
	-- minimum — Logic/CaveFamilyRules clamps it, so a narrower bias makes doorways tighter on
	-- average and can never make one impassable.
	doorwayWidthBias: number,
	-- Multiplies the unstable-formation (dripstone / icicle) placement target on top of the depth
	-- curve and this family's own hazard budget.
	dripstoneFactor: number,
}

export type EnvironmentProfile = {
	-- Chance an assembled floor is wet at all (replaces Config/Floors.floodedFloorChance per family).
	wetFloorProbability: number,
	-- Are burnable vine curtains generated in this family at all?
	vinesEnabled: boolean,
	-- Presentation and clearing behaviour for the optional doorway obstruction. The planner remains
	-- family-agnostic: it stamps this data onto each placement and the shared service interprets it.
	doorwayBarrierStyle: "Vines" | "Icicles",
	-- Floors EARLIER than Config/Vines.minDepth that curtains start appearing. 2 means "two floors
	-- earlier". Never lets curtains appear below global depth 1.
	vineIntroductionShift: number,
	-- Multiplies Logic/VineRules.targetCount.
	vineCountFactor: number,
	-- Does this family grow the uncommon dry clusters a player's own flame can set alight
	-- (Config/MossFire)? A family that does not never plans one at all, rather than planning one and
	-- filtering it out later. Wet cave walls and ordinary damp moss are not flammable in ANY family:
	-- only explicitly tagged clusters ever burn.
	flammableVegetation: boolean,
}

export type ThreatEcologyProfile = {
	-- Multiplies a threat's rolled spawn weight in this family. Missing = 1. These change WHICH of
	-- the existing roster a floor draws, never how a threat behaves: no stat, state, or AI rule in
	-- Config/Threats is touched by a family.
	weightMultipliers: { [Types.ThreatId]: number },
	-- Floors EARLIER this row's authored spawn-weight table is sampled at. 1 means a threat that
	-- normally arrives on floor 5 arrives on floor 4. Never samples below index 1.
	introductionShift: { [Types.ThreatId]: number },
}

export type HazardEcologyProfile = {
	-- Multiplies a falling-formation variant's authored weight in this family
	-- (Config/Hazards.unstableDripstone.variants). Missing = 1. Exactly the shape of
	-- `threatEcology.weightMultipliers`, and for the same reason: a family changes WHICH of the
	-- existing pool its ceilings hang, never how a formation behaves once it is hanging there.
	--
	-- A FAMILY NARROWS THE POOL, IT NEVER DELETES A ROW. Zero is allowed and means "never rolled
	-- here", but every id stays resolvable by Logic/DripstoneRules.variantById — which matters because
	-- the client controller, the server service and the builder all look a variant up from an id that
	-- came out of a plan, and Config/StoneWarden.counterDripstoneVariantId hard-names one in EVERY
	-- family regardless of what that family would otherwise roll.
	variantWeightMultipliers: { [string]: number },
}

export type AmbienceProfile = {
	-- Multiplies an ambient candidate's authored weight in this family. Keyed by the SOUND EVENT id
	-- from Config/Feel.ambientCave.soundEvents, plus the two non-cue candidates the director also
	-- rolls ("Rockfall" and "WaterDrip"). Missing = 1.
	--
	-- WHAT A FAMILY MAY DO TO AUDIO, and it is a short list: change how OFTEN an event is chosen. It
	-- may never change a cue's volume, its bus, or the mixer — those live in Config/Audio and are the
	-- same in every cave, which is what stops "this family sounds different" quietly becoming "this
	-- family hides an approaching threat". Logic/CaveFamilyRules.validate enforces the completeness of
	-- this table so a newly authored event cannot leak into a family nobody weighted it for.
	candidateWeights: { [string]: number },
	-- Multiplies Config/Feel.ambientCave.silentWeight — the authored non-event. A family may be busier
	-- or quieter than the baseline; it may never be SILENT, because a cave that stopped speaking would
	-- be using the absence of audio as a difficulty lever. Validated above zero.
	silenceWeight: number,
}

-- WHAT HAS TAKEN HOLD ON A BODY THAT LIVES IN THIS CAVE. The one thing a family adds to a creature,
-- and deliberately the only thing.
--
-- ADDITIVE SURFACE GEOMETRY ON AN UNCHANGED SKELETON. Proportions, joint layout, animation, silhouette
-- category, the crimson dark-hunter eye slits and the Drawn's wings and warm halo are IDENTICAL in
-- every family — those are what a player reads a threat by in the dark, and a family may not touch
-- them. What differs is real geometry built on top: damp growth caught where a Moss body collects it,
-- frost crusted on the upward faces of an Ice one. `style = "None"` builds nothing at all, which is
-- what keeps a Stone body bit-for-bit what it was before families could dress a creature.
--
-- THIS RAISES CONTRAST, IT NEVER LOWERS IT. Each family's growth palette is drawn from its COVER
-- colours, which are already authored to sit apart from its ROCK colours — so a dressed body stands
-- out against the wall behind it rather than blending into it. A threat may be dressed for its cave
-- and may never be camouflaged against it.
export type CreatureGrowthStyle = "None" | "Shag" | "Rime"

export type CreatureDressingProfile = {
	growthStyle: CreatureGrowthStyle,
	-- Fraction of a body's eligible anchor points that carry a feature. The head is excluded and each
	-- style still leaves gaps: this is weathering on a creature, not a replacement silhouette.
	growthCoverage: number,
	-- Scale multiplier on each feature.
	growthSize: number,
	-- Held below the same darkness bound as every other dressing colour (Tests/CaveFamilyRulesTests):
	-- a body that catches more light than the rock it stands on would be a difficulty change made with
	-- an art asset.
	growthPalette: { Color3 },
	growthMaterial: Enum.Material,
	-- Overrides the skin material a body builds itself with, so a candle sweeping a limb catches a
	-- different grain — the same argument the rock palette already makes about `terrainMaterial`.
	-- `nil` leaves the body's own authored material alone.
	skinMaterial: Enum.Material?,
	-- NEVER APPLIED TO THE HEAD. The eye slits have to be the first thing that resolves at range in
	-- every family, so growth is refused on the skull and brow whatever the coverage says. Stated here
	-- because it is a rule about the family layer, and enforced by the bodies that build it.
	headExclusion: boolean,
}

-- A SECOND MATERIAL LAYER OVER THE FAMILY'S FLOOR. The terrain underfoot is one continuous surface
-- with one material, and at candle range a large span of it reads as exactly that however good the
-- height field under it is. These are thin, collision-neutral sheets laid on the real sampled ground:
-- flat glaze in Ice, nothing at all in a family that sets `sheetsPerRoom` to zero.
--
-- DELIBERATELY SPARSE AND DELIBERATELY NOT UNDERFOOT EVERYWHERE. The point is to break the floor's
-- uniformity, not to replace it — a floor that is entirely glazed has just swapped one uniform surface
-- for another, and has additionally started to look like a surface a player should expect to slide on.
-- Nothing here has collision, friction or any physical property at all.
export type FloorGlazeProfile = {
	sheetsPerRoom: number,
	minSize: number,
	maxSize: number,
	thickness: number,
	palette: { Color3 },
	material: Enum.Material,
	transparency: number,
	reflectance: number,
}

-- CHUNKY ICICLES ALONG THE CEILING AND, MORE IMPORTANTLY, AROUND THE DOORWAY MOUTHS. The family
-- already hangs stalactites through `Config/Floors`, and in Ice those come out ice-coloured — but a
-- stalactite silhouette is a stalactite silhouette whatever it is painted, and what makes a cave read
-- as ICE at a glance is a fringe of sharp parallel spikes across the top of the opening you are about
-- to walk through. Built from the family's own `formationPalette` and `formationMaterials` rather than
-- a fourth palette, because these ARE this family's formations.
--
-- COLLISION-NEUTRAL, like every other piece of roof dressing. Ceiling hazard and ambush reservations
-- are respected by the placement pass so a fringe can never sit where something is meant to fall.
export type IcicleFringeProfile = {
	clustersPerRoom: number,
	-- Clusters hung inside each doorway mouth, which is where this profile earns its keep.
	clustersPerDoorway: number,
	spikesPerCluster: number,
	minLength: number,
	maxLength: number,
	rootThickness: number,
	spread: number,
}

-- HOW A SURFACE HANDS THE CANDLE BACK, which is the whole of what makes a material read as what it
-- is when the only light in the world is one flame you are carrying.
--
-- THE MISTAKE THIS TYPE EXISTS TO FIX. Ice's wall and ground cover was authored as colour alone:
-- every facet fully opaque, zero reflectance, one material, 0.22 studs thick, lying flush against a
-- flat wall. On screen that is not ice — it is a blue sticker, and no amount of retinting a sticker
-- makes it ice, because the eye identifies ice by SPECULAR BEHAVIOUR long before it identifies it by
-- hue. A wet-looking highlight that slides across a facet as you move is the entire read.
--
-- SO THE VARIATION IS THE POINT, not the values. Real ice is several substances at once — clear
-- lenses, milky packed crust, wet polished faces — and the thing that sells it is that adjacent
-- facets answer the same flame DIFFERENTLY. One material at one reflectance across a whole wall
-- reads as a single moulded object however well-chosen that one material is, which is exactly the
-- failure the family palette rules already describe for colour and had no vocabulary for here.
--
-- NOTHING HERE EMITS, and that is not an oversight. A self-lit "cold light" channel was built and
-- cut: on screen it read as glowing sticks floating in the dark, not as ice. Reflectance is the
-- honest version of the same instinct — it makes a surface catch the light you brought instead of
-- inventing light the cave does not have, so it raises how GOOD the ice looks without touching how
-- MUCH a player can see, which is the line the whole game rests on.
export type SurfaceFinishProfile = {
	-- Rolled per facet. More than one entry is what stops a surface reading as one moulded object.
	materials: { Enum.Material },
	transparencyMin: number,
	transparencyMax: number,
	reflectanceMin: number,
	reflectanceMax: number,
	-- Multiplies the authored patch thickness. Paper-thin cover reads as a decal stuck on the rock
	-- rather than as a crust that grew out of it.
	thicknessScale: number,
	-- Multiplies the authored patch size. Smaller facets at a higher density read as crystalline;
	-- fewer larger ones read as panels.
	sizeScale: number,
	-- Degrees a facet may be tilted OFF the surface it sits on. Flush facets all flash at once as the
	-- flame sweeps past, which is the single strongest "these are flat quads" tell; tilted ones catch
	-- it one at a time and the wall acquires a grain.
	tiltDegrees: number,
}

-- THE ONE THING THAT CAN ACTUALLY MAKE A CAVE READ COLD, and the reason every attempt to do it with
-- material colour failed.
--
-- THE ARITHMETIC NOBODY CAN TINT THEIR WAY AROUND. `server/EnvironmentSetup.apply` pins
-- `Lighting.Ambient`, `OutdoorAmbient` and `Brightness` to black and zero — deliberately, because the
-- darkness is what the whole game rests on. The consequence is that EVERY lit pixel in a cave is lit
-- by exactly one kind of source: something warm the player is carrying. A rendered colour is
-- `surface x light`, so with a warm light and no ambient term at all, a blue surface CANNOT come out
-- blue. Dimly lit it goes muddy brown-green; brightly lit — a flare at close range — it clips toward
-- the light's own hue and comes out orange. Ice's rock was already authored at roughly five parts
-- blue to one part red and still rendered as a warm tunnel, and that was not a failure of the value.
-- It is not reachable from the material end.
--
-- WHY A GRADE IS ALLOWED WHERE A LIGHT IS NOT. A ColorCorrectionEffect multiplies the FINAL IMAGE. It
-- adds no light to the scene, and multiplying by zero is zero — so unlit geometry stays exactly as
-- black as it was, no unlit room becomes legible, no creature gains a silhouette it did not have, and
-- every threat-visibility and wax-pressure assumption in the game is untouched. It changes what the
-- light you already brought LOOKS like, and nothing else. That is a genuinely different act from
-- raising ambient, which is why this is the mechanism and self-lit geometry was not.
--
-- BOUNDED SO IT CAN ONLY EVER DARKEN. Every tint channel is clamped to at most 1 by
-- `Logic/CaveFamilyRules`, which makes the invariant structural rather than a matter of taste: a
-- grade may subtract from a channel and may never amplify one, so no family can use it to brighten
-- its cave by any amount, in any channel, ever. `Brightness` is deliberately not exposed at all.
export type ColorGradeProfile = {
	-- Multiplies the final image per channel. Cool-white here is what turns warm-lit rock cold.
	tintColor: Color3,
	-- Added to the image's saturation. A small positive value helps the blue that survives the tint
	-- actually read as blue rather than as grey.
	saturation: number,
	contrast: number,
}

export type PresentationProfile = {
	-- Global Atmosphere, applied once per expedition (server/EnvironmentSetup.applyCaveFamily).
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	-- WHAT THIS CAVE'S LIGHT LOOKS LIKE ONCE IT HAS LANDED. See `ColorGradeProfile` above: with
	-- ambient pinned to black, this is the only lever in the game that can change a cave's overall
	-- colour temperature, and material palettes cannot substitute for it.
	colorGrade: ColorGradeProfile,
	-- THE AIR THE CANDLELIGHT TRAVELS THROUGH, and the most fundamental visual difference between
	-- these caves — more than the rock, because in a game where light is the only source of visual
	-- information, how far light REACHES is how big the world feels.
	--
	-- These three were previously left at one global value, so all three families had identical air:
	-- Moss's wet, close, growth-choked warren and Ice's open glacier halls swallowed a flame at exactly
	-- the same distance. Colour was doing all the work and none of it was spatial.
	--
	-- `atmosphereDensity` is how quickly the dark closes in — higher means the flame dies sooner and
	-- the cave feels smaller. `atmosphereHaze` is how much distant geometry washes toward the
	-- atmosphere colour, which is what gives a long hall visible depth instead of a hard edge into
	-- black. `atmosphereGlare` is the bloom immediately around a light source: a little of it reads as
	-- moisture or ice crystals hanging in the air right in front of you.
	--
	-- NONE OF THEM MAY LIGHT THE CAVE. ART-BIBLE §4 binds all three: they change how far the flame you
	-- are carrying reaches, never whether anything is visible without one. Tests hold density above a
	-- floor for exactly that reason — thin air must never become "you can see across a dark room".
	atmosphereDensity: number,
	atmosphereHaze: number,
	atmosphereGlare: number,
	-- The rock palette AND its surface textures. ART-BIBLE §4's rule that rock is never warm-toned and
	-- never self-lit binds every one of these: a Moss cave is a DARK wet-green-grey cave and an Ice
	-- cave is a DARK blue-grey one, both lit only by the flame you carry. Nothing here emits light,
	-- and Tests/CaveFamilyRulesTests holds every colour below an explicit darkness bound so a future
	-- retune cannot brighten a cave by accident.
	--
	-- COLOUR ALONE IS NOT A DIFFERENT CAVE. Three families sharing one material with three tints read
	-- as one cave under three gels, because the surface grain — the thing the candle actually catches —
	-- would be identical. Each family therefore carries its own materials as well: flat layered slate,
	-- coarse wet rock, dense packed glacier. The test suite requires the combination to be distinct.
	wallColor: Color3,
	rockColor: Color3,
	terrainColor: Color3,
	terrainMaterial: Enum.Material,
	-- NAME OF A MaterialService MaterialVariant (Studio-authored, PBR-textured) THAT REPLACES HOW
	-- `terrainMaterial` RENDERS, or nil to leave the engine default alone. `nil` in every family but
	-- Ice, and required to stay that way by CaveFamilyRules.validate.
	--
	-- WHY THIS IS ITS OWN FIELD RATHER THAN A FOURTH COLOUR/MATERIAL PAIR. Roblox Terrain has no
	-- per-voxel or per-instance variant the way a BasePart has `part.MaterialVariant` — the ONLY way to
	-- skin Terrain with a custom variant is `MaterialService:SetBaseMaterialOverride(material, name)`,
	-- and that override is GLOBAL PER PLACE for the given base Enum.Material: it also reskins every
	-- BasePart using that same base material that has not been given its own explicit
	-- `part.MaterialVariant` (server/FloorBuilder never sets one on a wall slab, rock shard, or
	-- formation). Applied here it is therefore not floor-and-ceiling-only — it is
	-- "everything currently rendered as `terrainMaterial`'s base Enum.Material, cave-wide" — which is
	-- fine ONLY because every other family leaves this nil, and nothing outside the family system may
	-- construct geometry from an arbitrary Enum.Material of its own accord.
	terrainMaterialVariant: string?,
	-- Structural wall slabs, and the jagged shards broken across every wall face.
	wallMaterial: Enum.Material,
	rockMaterial: Enum.Material,
	-- HOW VISIBLE THIS FAMILY'S WALL SLABS ARE. A slab is one flat box `cellSize` wide by the full
	-- ceiling height — up to 64 x 46 studs — so it is the biggest unbroken surface in any room, and a
	-- low-contrast part material at that scale reads as flat paint rather than as rock.
	--
	-- KEEP THIS AT 0 UNLESS SOMETHING HAS CHANGED STRUCTURALLY. A slab carries collision, so anything
	-- above 0 is a wall a player can walk into and cannot see. It was briefly set to 1 for Ice on the
	-- theory that solid terrain stood behind every slab and hiding one would reveal it; that is false
	-- (terrain's 4-stud voxel resolution cannot hold the 2-stud band the mask leaves), and the result
	-- was invisible walls. The field is kept rather than deleted because the value is legitimately
	-- per-family and a future builder change could make hiding them correct — but it is a correctness
	-- setting, not an art one.
	wallSlabTransparency: number,
	-- Collision-neutral surface dressing: the moss, frost or growth that creeps up this family's walls.
	-- `coverDensityFactor` scales the authored patch counts in Config/Floors.caveMoss.
	coverPalette: { Color3 },
	coverMaterial: Enum.Material,
	coverDensityFactor: number,
	-- Flat growth stays an organic patch; rigid frost uses one angled shard per patch so it cannot
	-- read as rectangular panels glued to the wall. Ground cover is likewise data-driven: zero keeps
	-- the family floor bare, while a positive count scatters collision-neutral crust over the real
	-- sampled surface.
	coverShape: "Patch" | "Shard",
	groundCoverPatchesPerRoom: number,
	-- How this family's wall and ground cover answers the flame. See `SurfaceFinishProfile` above —
	-- a NEUTRAL finish (one material, no reflectance, no tilt, unit scales) reproduces the authored
	-- behaviour exactly and consumes no extra random rolls, which is what lets Stone and Moss opt out
	-- without their floors changing by a single part.
	coverFinish: SurfaceFinishProfile,
	-- The same question asked of every FORMATION this family builds — stalactites, stalagmites, soda
	-- straws, icicle fringes, boulders and columns — applied through `CaveKit.configure`. Kept
	-- separate from the cover finish because a hanging formation and a wall crust are different
	-- substances even within one family: Ice's formations are clearer and glassier than its frost.
	formationFinish: SurfaceFinishProfile,
	-- The second material layer over this family's floor, and the icicle fringe across its ceilings
	-- and doorway mouths. See each type above for what it is for.
	floorGlaze: FloorGlazeProfile,
	icicleFringe: IcicleFringeProfile,
	-- The palette and materials every hanging/standing FORMATION is built from — stalactites,
	-- stalagmites, soda straws, boulders, and the unstable formations that fall. This is what makes an
	-- Ice cave's unstable formations read as icicles: the falling HAZARD is the same object with the
	-- same warning, timing and impact rules (Config/Hazards.unstableDripstone, Logic/DripstoneRules),
	-- dressed in this family's rock.
	formationPalette: { Color3 },
	formationMaterials: { Enum.Material },
	formationWetMaterial: Enum.Material,
	-- WHAT A BLAST VAULT'S DOOR IS CUT FROM (Config/Dynamite.visual.styleColors / styleMaterials). The
	-- rock a family is made of is the rock across its vault door, which is why this is a family field
	-- and not one shared slab: a single grey door would be the one object in the game that ignored
	-- which cave it was standing in. Presentation and material only — the door's thickness, its socket,
	-- its break radius and everything a stick does to it are identical in all three caves.
	blastDoorStyle: Types.BlastDoorStyle,
	-- WHAT AN EXPEDITION'S OWN GEAR IS BUILT FROM DOWN HERE (`Types/Fixtures`). The three per-floor
	-- fixtures — the Basin's Cauldron, the Brazier a run ends at, and the Descent Ladder — share
	-- one style block for the same reason the vault door has one: a single grey hoist standing in
	-- three different caves would be the one set of objects in the game that ignored which cave it
	-- was in. Presentation and material only: the sacrifice pool, the reward formula and the ride's
	-- timing are identical in all three families.
	fixtureStyle: Types.FixtureStyle,
	-- Suffix appended to a threat's visual style so clients can dress the SAME body differently per
	-- family (Shared/NewModelsAndObjects/ThreatVisualProtocol). Presentation only: collision, speed,
	-- damage, perception, states and silhouette category are untouched, and crimson dark-hunter eyes
	-- / yellow Drawn eyes / readable moth wings are preserved in every variant.
	threatVariantId: string,
	-- Multiplies a threat body's dressing tint toward the family hue. Kept low: a threat must never
	-- be camouflaged against the rock it stands on.
	threatVariantTintStrength: number,
	-- The geometry a family adds to every creature body. See CreatureDressingProfile above for the
	-- (short) list of what a family may change about a creature and the much longer list of what it
	-- may not.
	creatures: CreatureDressingProfile,
	-- WHAT THIS CAVE SOUNDS LIKE UNDERFOOT (`Config/Audio.cues`). The most frequent sound in the whole
	-- game, so it is also the one that most decides whether the three caves feel like different places
	-- to walk through rather than the same place repainted.
	--
	-- SELF-AUDIBLE ONLY. Walking emits nothing through server/NoiseService — see the cue rows for why
	-- making it audible to threats would be a very different and much worse game.
	footstepCue: string,
	-- HOW BIG THIS CAVE SOUNDS. Applied on top of the per-bus reverb authored in Config/Audio rather
	-- than replacing it, which is the whole point: that file has carefully different tails for
	-- ambience, world and focus audio, and a family must change the SPACE those tails describe without
	-- flattening the relationship between them.
	--
	-- Reverb is the single strongest "this is a different place" signal in audio — stronger than any
	-- individual sound, because it colours EVERY sound at once, including ones authored years apart.
	-- All three caves previously shared one acoustic, so a knotted wet Moss warren and an open Ice
	-- glacier hall rang exactly alike and the ear had nothing to tell them apart with.
	--
	-- `reverbDecayScale` multiplies each bus's decay time: how long the tail runs, which the ear reads
	-- directly as how large and how hard-walled the space is. `reverbWetOffset` is added to each bus's
	-- wet level in dB: how MUCH of the room you hear against the dry source, which reads as how
	-- reflective the surfaces are. Negative is drier and deader.
	reverbDecayScale: number,
	reverbWetOffset: number,
}

export type OreTierWeight = { tier: number, weight: number }

export type OreAvailabilityBand = {
	-- Lowest global depth this row applies from. Rows are scanned deepest-first.
	minDepth: number,
	tiers: { OreTierWeight },
}

export type OreProfile = {
	-- The tier this family's rock is made of, and the reason a harder cave is worth entering.
	nativeTier: number,
	-- Deepest-first availability. Every family's shallow band is exactly its native tier.
	availability: { OreAvailabilityBand },
}

export type CaveFamilyProfile = {
	id: CaveFamilyId,
	displayName: string,
	-- Numeric row this family occupies in the derived Config/CaveTiers table, and therefore the value
	-- already persisted by pre-family saves. This is what makes the migration a pure rename rather
	-- than a grant: Descent (2) IS Moss, Deep (3) IS Ice.
	legacyTierId: number,
	-- Per-descent admission, and the one-off price of never paying it again. Currency, so integers.
	entryFee: number,
	unlockCost: number,
	-- Scales every Raw Wax payout from this cave, as a PERMILLE integer (1000 = unchanged).
	--
	-- NOTE FOR THE OWNER: the cave-family brief specified reward multipliers of 1.00 / 1.25 / 1.50.
	-- The shipped economy is 1.00 / 2.50 / 4.50, and every fee, price and break-even in TUNING.md
	-- (plus ExtractionValueTests' fixed expectations) is derived from those. Restating them at the
	-- brief's numbers would cut Moss income by half and Ice income by two thirds while leaving their
	-- admissions untouched, which is a deliberate economy rebalance rather than a cave-family change.
	-- The shipped values are kept here and the divergence is recorded rather than applied silently.
	payoutPermille: number,

	baseThreatMultiplier: number,
	baseHazardMultiplier: number,
	threatBandMultipliers: BandMultipliers,
	hazardBandMultipliers: BandMultipliers,

	-- EQUAL IN ALL THREE FAMILIES, and required to stay that way by CaveFamilyRules.validate. See the
	-- file header: a faster unavoidable timer is not difficulty, it is a shorter run.
	waxDrainMultiplier: number,

	topology: TopologyProfile,
	geometry: GeometryProfile,
	-- Relative likelihood of each outer footprint for an ORDINARY room. Entry, Basin and completion
	-- rooms are always Rectangle (Logic/RoomFootprint.isProtectedShape).
	roomShapeWeights: { [RoomShapeKind]: number },
	environment: EnvironmentProfile,
	threatEcology: ThreatEcologyProfile,
	hazardEcology: HazardEcologyProfile,
	ambience: AmbienceProfile,
	presentation: PresentationProfile,
	ore: OreProfile,
}

-- Bumped whenever the SHAPE of a profile changes (a field added, removed, or given a new meaning),
-- never for a retune. Recorded in telemetry beside a generated floor so a report can be read against
-- the schema it was produced under.
-- Bumped to 6 when a family gained `presentation.terrainMaterialVariant` — the name of a Studio-authored
-- MaterialService override for its terrain material. Nil everywhere but Ice.
-- Bumped to 5 when a family gained the three dressing layers above: `presentation.floorGlaze` (a
-- second material layer over its floor), `presentation.icicleFringe` (spikes across its ceilings and
-- doorway mouths). Nothing in any cave emits — that law is unchanged.
-- Bumped to 4 when a family gained `presentation.fixtureStyle` — what the Cauldron, the Brazier
-- and the Descent Ladder are built from in this cave.
-- Bumped to 3 when a family also gained its own AIR (atmosphere density/haze/glare), its own
-- ACOUSTIC (reverb decay scale and wet offset) and its own FOOTSTEP CUE. Bumped to 2 when it gained: `hazardEcology` (which formations its ceilings
-- hang), `ambience` (how often the cave makes each of its sounds), and `presentation.creatures` (the
-- geometry that has taken hold on a body living here). A shape change, not a retune.
local PROFILE_VERSION = 6

-- THE THREE DRESSING LAYERS TURNED OFF. Stone and Moss share this: neither glazes its floor, neither
-- fringes its openings with ice, and neither has anything in it that emits. Stated once as a named
-- constant rather than pasted into two rows, so "this family builds none of the new dressing" is a
-- thing a reader can see at a glance instead of eleven zeros they have to check.
--
-- The colours still have to be real Color3s even though nothing reads them at a count of zero: an
-- unauthored colour resolves to white, and a future retune that raises a count without noticing the
-- palette was a placeholder is exactly the kind of mistake this file exists to make impossible.
local NO_FLOOR_GLAZE: FloorGlazeProfile = {
	sheetsPerRoom = 0,
	minSize = 6,
	maxSize = 14,
	thickness = 0.3,
	palette = { Color3.fromRGB(40, 46, 56) },
	material = Enum.Material.Slate,
	transparency = 0.4,
	reflectance = 0,
}

-- THE FINISH THAT CHANGES NOTHING. Every field is the value the builder used before finishes
-- existed, and `CaveFamilyRules.surfaceFinishVaries` reads exactly this shape as "neutral" and skips
-- the rolls entirely — so a Stone or Moss patch is bit-for-bit the patch it was, down to the random
-- stream every later boulder and column is drawn from.
--
-- `materials` is left EMPTY rather than naming a material, and that is the load-bearing detail: an
-- empty list means "use the family's authored `coverMaterial` / formation materials", so this
-- constant cannot drift out of sync with the two families that use it. A single-entry list naming
-- Grass here would have quietly overridden Moss's own material the day somebody retuned it.
local NEUTRAL_FINISH: SurfaceFinishProfile = {
	materials = {},
	transparencyMin = 0,
	transparencyMax = 0,
	reflectanceMin = 0,
	reflectanceMax = 0,
	thicknessScale = 1,
	sizeScale = 1,
	tiltDegrees = 0,
}

-- ICE'S ONE ROCK COLOUR, used by both its walls and its terrain so the floor and the walls are the
-- same colour BY CONSTRUCTION rather than by two literals that happen to agree today. A room shows
-- both surfaces at once — floor and ceiling are terrain, wall slabs are parts — so any drift between
-- them shows up immediately as the cave changing colour at the join.
local ICE_ROCK = Color3.fromRGB(18, 58, 92)

local NO_ICICLE_FRINGE: IcicleFringeProfile = {
	clustersPerRoom = 0,
	clustersPerDoorway = 0,
	spikesPerCluster = 5,
	minLength = 1.5,
	maxLength = 4,
	rootThickness = 0.5,
	spread = 2,
}

local Families: { CaveFamilyProfile } = {
	{
		id = "STONE",
		displayName = "Stone Caves",
		legacyTierId = 1,
		-- Free forever, and never purchasable. Whatever else happens to a player's balance there is
		-- always a cave they can walk into with nothing, which is what stops a bad streak in a paid
		-- cave from locking someone out of the game entirely.
		entryFee = 0,
		unlockCost = 0,
		payoutPermille = 1000,

		-- THE REGRESSION BASELINE. Every number in this row is the value the pre-family generator
		-- already used, so a Stone floor at a given seed and depth must come out of the refactor
		-- unchanged except for the room shapes the shape weights below deliberately introduce.
		baseThreatMultiplier = 0.6,
		baseHazardMultiplier = 1,
		threatBandMultipliers = {
			Introduction = 1,
			Standard = 1,
			Dangerous = 1,
			Expert = 1,
			Extreme = 1,
		},
		hazardBandMultipliers = {
			Introduction = 1,
			Standard = 1,
			Dangerous = 1,
			Expert = 1,
			Extreme = 1,
		},
		waxDrainMultiplier = 1,

		topology = {
			loopBias = 1,
			optionalBranchBias = 1,
			connectorLengthBias = 1,
			verticalVariation = 1,
		},
		geometry = {
			roomSizeScaleMin = 1,
			roomSizeScaleMax = 1,
			-- The full authored range, with zero preference strength: Stone's ceiling roll is the
			-- unmodified uniform roll it has always been.
			ceilingPreferredMin = 15,
			ceilingPreferredMax = 46,
			ceilingPreferenceStrength = 0,
			internalFormationDensity = 1,
			doorwayWidthBias = 1,
			dripstoneFactor = 1,
		},
		roomShapeWeights = {
			Rectangle = 50,
			Ellipse = 20,
			Capsule = 15,
			TwinLobe = 15,
		},
		environment = {
			wetFloorProbability = 0.4,
			vinesEnabled = true,
			doorwayBarrierStyle = "Vines",
			vineIntroductionShift = 0,
			vineCountFactor = 1,
			-- Stone is bare wet rock. Nothing in it is dry enough to catch.
			flammableVegetation = false,
		},
		threatEcology = {
			-- The shared roster stays neutral here; Stone's identity in the mix comes from the Listener
			-- rather than from bending the three rows every family draws.
			weightMultipliers = {
				DarkCrawler = 1,
				Moth = 1,
				VoidFly = 1,
				-- STONE'S SIGNATURE CREATURE, and nowhere else's. A family-exclusive row needs no new
				-- mechanism at all: it sits in the ordinary Config/Floors allow-lists and the other two
				-- families weight it to zero, which the planner already reads as "not here"
				-- (Logic/FloorPlanner.roomHasThreatAtDepth gates on this being above zero).
				Listener = 1,
				Knotwalker = 0,
				Calver = 0,
			},
			introductionShift = {},
		},
		hazardEcology = {
			-- THE REGRESSION BASELINE, here as everywhere else in this row: the four original variants at
			-- their authored weights, which is exactly the mix Stone hung before a family could weight
			-- them at all. The two family-signature formations are refused.
			variantWeightMultipliers = {
				Needle = 1,
				Fork = 1,
				Hammer = 1,
				Spire = 1,
				Lance = 0,
				Mass = 0,
			},
		},
		ambience = {
			-- Stone is the soundscape the other two are authored AGAINST: every candidate at its
			-- Config/Feel weight, which is what a cave has always sounded like here.
			candidateWeights = {
				StrataStrain = 1,
				FissureBreath = 1,
				CalciteTicks = 1,
				HiddenWaterPulse = 1,
				GravelCreep = 1,
				DistantSettle = 1,
				ColdDraft = 1,
				DripCluster = 1,
				SeepRun = 0,
				GlacierGroan = 0,
				Rockfall = 1,
				WaterDrip = 1,
				-- Stone is the reference cave and the one whose rock people actually worked, so this is
				-- where the old equipment is loudest about still being here.
				OldWorkings = 1,
			},
			silenceWeight = 1,
		},
		presentation = {
			atmosphereColor = Color3.new(0.62, 0.66, 0.74),
			atmosphereDecay = Color3.new(0.22, 0.24, 0.3),
			-- NO GRADE AT ALL. Stone is the cave every other family's look is authored against, and it
			-- is the one this game's warm candle art was tuned in — an identity tint keeps it exactly
			-- the cave it has always been.
			colorGrade = {
				tintColor = Color3.new(1, 1, 1),
				saturation = 0,
				contrast = 0,
			},
			-- THE REFERENCE AIR. Every number the other two families set is authored against these, and
			-- these are the values a Stone cave already had.
			atmosphereDensity = 0.42,
			atmosphereHaze = 1.2,
			atmosphereGlare = 0,
			wallColor = Color3.fromRGB(52, 56, 66),
			rockColor = Color3.fromRGB(62, 66, 78),
			terrainColor = Color3.fromRGB(48, 52, 62),
			-- FLAT LAYERED SLATE, everywhere. The authored look, and the texture the other two are
			-- deliberately different from.
			terrainMaterial = Enum.Material.Slate,
			-- Stone is the regression baseline: the engine's own Slate, untouched.
			terrainMaterialVariant = nil,
			wallMaterial = Enum.Material.Slate,
			rockMaterial = Enum.Material.Slate,
			-- The authored look: Stone has always shown its wall slabs, and it is the regression baseline.
			wallSlabTransparency = 0,
			-- Stone's cover is the damp cave moss it already carried; the palette is
			-- Config/Floors.caveMoss's, restated here so every family answers the same question in
			-- the same place.
			coverPalette = {
				Color3.fromRGB(16, 46, 26),
				Color3.fromRGB(11, 37, 22),
				Color3.fromRGB(23, 55, 31),
				Color3.fromRGB(8, 29, 18),
			},
			coverMaterial = Enum.Material.Grass,
			coverDensityFactor = 1,
			coverShape = "Patch",
			groundCoverPatchesPerRoom = 0,
			-- THE REGRESSION BASELINE KEEPS BUILDING NOTHING. Stone's floor is the floor, its ceilings
			-- hang what they always hung, and nothing in it emits — which is what lets the new dressing
			-- ship without a single part changing in the family every other family is measured against.
			floorGlaze = NO_FLOOR_GLAZE,
			icicleFringe = NO_ICICLE_FRINGE,
			coverFinish = NEUTRAL_FINISH,
			formationFinish = NEUTRAL_FINISH,
			-- The authored cool blue-charcoal slate, unchanged.
			formationPalette = {
				Color3.fromRGB(52, 56, 66),
				Color3.fromRGB(62, 66, 78),
				Color3.fromRGB(45, 49, 59),
				Color3.fromRGB(70, 73, 84),
			},
			formationMaterials = {
				Enum.Material.Slate,
				Enum.Material.Basalt,
				Enum.Material.Concrete,
				Enum.Material.Rock,
			},
			formationWetMaterial = Enum.Material.Slate,
			blastDoorStyle = "Rock",
			-- THE MINING-RIG BUILD, and the reference the other two are authored against: iron-banded
			-- timber on a chain winch, which is what the people who cut these shafts would have bolted
			-- together. Every colour sits in the same dark band the rock does — a fixture is found by
			-- the flame, never before it.
			fixtureStyle = {
				rig = "Timbered",
				frameColor = Color3.fromRGB(46, 44, 48),
				frameMaterial = Enum.Material.Metal,
				deckColor = Color3.fromRGB(58, 44, 32),
				deckMaterial = Enum.Material.Wood,
				lineColor = Color3.fromRGB(58, 58, 64),
				lineMaterial = Enum.Material.Metal,
				vesselColor = Color3.fromRGB(40, 38, 40),
				vesselMaterial = Enum.Material.Metal,
			},
			threatVariantId = "Stone",
			threatVariantTintStrength = 0,
			-- NOTHING GROWS ON A STONE BODY, and nothing is meant to. This family is the reference every
			-- creature in the game was authored against: bare skin, its own material, no additive
			-- geometry. A Stone crawler is the crawler.
			creatures = {
				growthStyle = "None",
				growthCoverage = 0,
				growthSize = 1,
				growthPalette = {},
				growthMaterial = Enum.Material.Grass,
				skinMaterial = nil,
				headExclusion = true,
			},
			-- Flat layered slate: a hard, ringing step with a short tail.
			footstepCue = "FootstepStone",
			-- THE AUTHORED ACOUSTIC, unscaled. Config/Audio's per-bus reverb was tuned in a Stone cave, so
			-- Stone is exactly what it says and the other two are read against it.
			reverbDecayScale = 1,
			reverbWetOffset = 0,
		},
		ore = {
			nativeTier = 1,
			-- Deepest-first. Stone's whole ore story is that it eventually reaches what the other
			-- families start with, and only rarely.
			availability = {
				{
					minDepth = 40,
					tiers = { { tier = 1, weight = 65 }, { tier = 2, weight = 25 }, { tier = 3, weight = 10 } },
				},
				{ minDepth = 20, tiers = { { tier = 1, weight = 85 }, { tier = 2, weight = 15 } } },
				{ minDepth = 1, tiers = { { tier = 1, weight = 100 } } },
			},
		},
	},
	{
		id = "MOSS",
		displayName = "Moss Caves",
		legacyTierId = 2,
		entryFee = 350,
		-- The brief's unlock cost for Moss is 1,500. The shipped price is 5,250 — fifteen descents'
		-- worth at the 350 fee, which is the relationship every permanent unlock in the game is
		-- priced on. Dropping it to 1,500 would make owning Moss cheaper than four descents and is a
		-- deliberate economy change; recorded, not applied. See `payoutPermille` above.
		unlockCost = 5250,
		payoutPermille = 2500,

		-- MOSS IS THE CAVE OF OBSTRUCTED INFORMATION. Floor 1 should land near Stone floor 5 without
		-- pretending internally to BE floor 5: the base multipliers do that work, and the band
		-- multipliers then pull away from Stone faster the deeper the run goes.
		baseThreatMultiplier = 1.1,
		baseHazardMultiplier = 1.2,
		threatBandMultipliers = {
			Introduction = 1,
			Standard = 1.1,
			Dangerous = 1.22,
			Expert = 1.36,
			Extreme = 1.52,
		},
		hazardBandMultipliers = {
			Introduction = 1,
			Standard = 1.1,
			Dangerous = 1.25,
			Expert = 1.42,
			Extreme = 1.62,
		},
		waxDrainMultiplier = 1,

		topology = {
			-- More cycles and more optional branches, folded tighter: Moss is a knot you lose your
			-- bearings in, not a maze you get lost in.
			loopBias = 1.25,
			optionalBranchBias = 1.2,
			connectorLengthBias = 0.9,
			verticalVariation = 0.95,
		},
		geometry = {
			roomSizeScaleMin = 0.85,
			roomSizeScaleMax = 1.05,
			-- Biased low-to-middling, but NOT uniformly cramped: the preference strength deliberately
			-- leaves a real share of open, tall rooms so the family has somewhere to breathe.
			ceilingPreferredMin = 15,
			ceilingPreferredMax = 36,
			ceilingPreferenceStrength = 0.6,
			internalFormationDensity = 1.35,
			doorwayWidthBias = 0.92,
			dripstoneFactor = 0.9,
		},
		roomShapeWeights = {
			Rectangle = 50,
			Ellipse = 10,
			Capsule = 10,
			-- The twin lobe is Moss's signature: two bays joined by a neck, with the rock between
			-- them doing the occluding.
			TwinLobe = 30,
		},
		environment = {
			wetFloorProbability = 0.55,
			vinesEnabled = true,
			doorwayBarrierStyle = "Vines",
			vineIntroductionShift = 2,
			vineCountFactor = 1.75,
			-- THE ONLY FAMILY THAT BURNS. Uncommon even here: most Moss rooms have nothing to light.
			flammableVegetation = true,
		},
		threatEcology = {
			-- MOSS IS MOTH COUNTRY: damp, overgrown, and covered in things worth perching on. Each
			-- multiplier is this family's old per-row values averaged under those rows' own spawn
			-- weights, so the mix a floor draws here is the mix it always drew. The VoidFly stays
			-- neutral — a ceiling ambusher does not care what grows on the walls.
			weightMultipliers = {
				DarkCrawler = 1.05,
				Moth = 1.15,
				VoidFly = 1,
				Listener = 0,
				-- MOSS'S SIGNATURE CREATURE. See Stone's row for why an exclusive creature is only ever a
				-- zero in the other two families rather than a mechanism of its own.
				Knotwalker = 1,
				Calver = 0,
			},
			-- Moss meets its moths a floor early.
			introductionShift = {
				Moth = 1,
			},
		},
		hazardEcology = {
			-- MOSS'S CEILINGS ARE HEAVY AND BLUNT. Forks and crowns over needles, and the Sodden Mass
			-- carrying about a quarter of the family's formations — the widest committed ground in the
			-- game, in the family whose own topology is what keeps you from seeing what you stepped
			-- under. The Spire is nearly refused: Moss biases its ceilings low
			-- (`geometry.ceilingPreferred*`), so a 15.5-stud spire mostly burns placement attempts on
			-- rooms that cannot physically hang it.
			variantWeightMultipliers = {
				Needle = 0.8,
				Fork = 1.3,
				Hammer = 1.5,
				Spire = 0.35,
				Lance = 0,
				Mass = 2.6,
			},
		},
		ambience = {
			-- MOSS IS THE WETTEST CAVE AND THE BUSIEST ONE. Water is everywhere it is not in Ice
			-- (`environment.wetFloorProbability` 0.55), and wet rock does not strain and crack the way
			-- dry packed glacier does — it ticks, it seeps and it sloughs. The strata groan is pulled
			-- down hardest and the water candidates hardest up.
			candidateWeights = {
				StrataStrain = 0.7,
				FissureBreath = 0.85,
				CalciteTicks = 1.2,
				HiddenWaterPulse = 1.6,
				GravelCreep = 1.1,
				DistantSettle = 0.8,
				ColdDraft = 0.7,
				DripCluster = 1.55,
				SeepRun = 1,
				GlacierGroan = 0,
				Rockfall = 0.9,
				WaterDrip = 1.7,
				-- Wet timber and growth deaden a settle. The equipment is still there and still rots;
				-- you just hear less of it through the moss.
				OldWorkings = 0.75,
			},
			-- The one cave that is never quite quiet. Deliberately a small move: this changes how often
			-- the director spends a turn on nothing, and nothing else — no cue gets louder anywhere.
			silenceWeight = 0.85,
		},
		presentation = {
			atmosphereColor = Color3.new(0.5, 0.55, 0.5),
			atmosphereDecay = Color3.new(0.16, 0.19, 0.16),
			-- A whisper of green and a touch off the red, no more. Moss already reads as a wet green
			-- warren through its moss, its rock and the densest air in the game; a strong grade on top
			-- would tip it into a filter over a cave rather than a cave.
			colorGrade = {
				tintColor = Color3.new(0.94, 1, 0.95),
				saturation = 0.04,
				contrast = 0,
			},
			-- THICK, WET, CLOSE. The densest air in the game: a Moss flame dies noticeably sooner than a
			-- Stone one, which is the family's obstructed-information identity expressed in the one
			-- medium every other system already speaks. The haze is pulled DOWN with it — dense damp air
			-- scatters short and hides distance rather than revealing it, so you get a wall of dark at
			-- the edge of the flame instead of a receding depth cue. Glare is real here: moisture hanging
			-- a couple of studs in front of you, caught by your own candle.
			atmosphereDensity = 0.55,
			atmosphereHaze = 0.85,
			atmosphereGlare = 0.12,
			-- Dark wet stone with the green kept out of the ROCK itself; the moss carries the hue so
			-- the walls never read as decorated.
			wallColor = Color3.fromRGB(46, 52, 48),
			rockColor = Color3.fromRGB(56, 62, 56),
			terrainColor = Color3.fromRGB(42, 48, 44),
			-- COARSE WET ROCK rather than slate: chunky and granular where Stone is flat and layered,
			-- so a candle sweeping a Moss wall catches a visibly different grain even before the moss
			-- on it registers. Basalt shards break that surface up further.
			terrainMaterial = Enum.Material.Rock,
			-- No Studio-authored skin for Moss's terrain; the engine's own Rock is unchanged.
			terrainMaterialVariant = nil,
			wallMaterial = Enum.Material.Rock,
			rockMaterial = Enum.Material.Basalt,
			-- Unchanged: Moss reads as coarse wet rock on the slabs and has never been the complaint.
			wallSlabTransparency = 0,
			-- Red kept far below green: the candle multiplies red by ~1.0 and green by ~0.75, so any
			-- moss whose red approaches its green reads as brown mud under it.
			coverPalette = {
				Color3.fromRGB(18, 44, 24),
				Color3.fromRGB(13, 36, 21),
				Color3.fromRGB(25, 52, 29),
				Color3.fromRGB(10, 29, 17),
			},
			coverMaterial = Enum.Material.Grass,
			coverDensityFactor = 2.2,
			coverShape = "Patch",
			groundCoverPatchesPerRoom = 0,
			-- Moss's floor identity is already the densest wall cover in the game plus the most internal
			-- formations; glazing it as well would be a second answer to a question the family has
			-- answered. Nothing grows into spikes here and nothing down here glows.
			floorGlaze = NO_FLOOR_GLAZE,
			icicleFringe = NO_ICICLE_FRINGE,
			coverFinish = NEUTRAL_FINISH,
			formationFinish = NEUTRAL_FINISH,
			-- Wetter, greener stone. Still cool and still dark: the green sits in the rock rather than
			-- on it, so a formation reads as damp cave rather than as a decorated prop.
			formationPalette = {
				Color3.fromRGB(46, 54, 48),
				Color3.fromRGB(56, 63, 55),
				Color3.fromRGB(40, 47, 43),
				Color3.fromRGB(63, 70, 60),
			},
			formationMaterials = {
				Enum.Material.Slate,
				Enum.Material.Rock,
				Enum.Material.Mud,
				Enum.Material.Basalt,
			},
			formationWetMaterial = Enum.Material.Mud,
			blastDoorStyle = "MossRock",
			-- LASHED, NOT BOLTED. A Moss expedition rigs its hoist out of what the warren gives it:
			-- damp boards tied with rope fibre, less rigid framing, no ironwork to rust in the wet. The
			-- rope run is the same knotted line the cage hangs from and a wall lamp's bracket uses.
			fixtureStyle = {
				rig = "Lashed",
				frameColor = Color3.fromRGB(48, 46, 36),
				frameMaterial = Enum.Material.WoodPlanks,
				deckColor = Color3.fromRGB(52, 50, 38),
				deckMaterial = Enum.Material.Wood,
				lineColor = Color3.fromRGB(74, 66, 44),
				lineMaterial = Enum.Material.Fabric,
				vesselColor = Color3.fromRGB(38, 44, 38),
				vesselMaterial = Enum.Material.Basalt,
			},
			threatVariantId = "Moss",
			threatVariantTintStrength = 0.22,
			-- SHAG. Short wet growth caught where a body actually collects it — the shoulder yoke, the
			-- outer thigh, the forearm — with a few strands long enough to sway on the gait, so a Moss
			-- body's MOVEMENT is legible half a beat before its outline is. Reads as something that has
			-- stood in a wet cave long enough to be colonised.
			--
			-- Darker than the family's wall moss so a creature never reads as a piece of the wall that
			-- detached itself.
			creatures = {
				growthStyle = "Shag",
				growthCoverage = 0.55,
				growthSize = 1,
				growthPalette = {
					Color3.fromRGB(21, 46, 27),
					Color3.fromRGB(15, 37, 22),
					Color3.fromRGB(27, 53, 30),
				},
				growthMaterial = Enum.Material.Grass,
				-- Coarse wet rock rather than the body's own slate: the same grain change the family
				-- makes to its walls, made to the thing standing in front of them.
				skinMaterial = Enum.Material.Rock,
				headExclusion = true,
			},
			-- Wet growth over coarse rock: soft, dull, absorbed.
			footstepCue = "FootstepMoss",
			-- DEAD AND CLOSE. Short tail, much less of it: knotted rooms with no long sightline, packed with
			-- soft wet growth (coverDensityFactor 2.2) and broken up by the densest internal formations in
			-- the game. Sound has nowhere to run and nothing hard to come back off, and the ear reads that
			-- as a space pressing in — which is the same thing the topology and the thick air are saying.
			reverbDecayScale = 0.6,
			reverbWetOffset = -4,
		},
		ore = {
			nativeTier = 2,
			availability = {
				{ minDepth = 20, tiers = { { tier = 2, weight = 85 }, { tier = 3, weight = 15 } } },
				{ minDepth = 1, tiers = { { tier = 2, weight = 100 } } },
			},
		},
	},
	{
		id = "ICE",
		displayName = "Ice Caves",
		legacyTierId = 3,
		entryFee = 1000,
		-- The brief's unlock cost for Ice is 6,000; the shipped price is 15,000, again fifteen
		-- descents. Recorded, not applied — see MOSS above.
		unlockCost = 15000,
		payoutPermille = 4500,

		-- ICE IS THE CAVE OF EXPOSURE. Longer sightlines and open routes mean threats see you sooner
		-- and from further, so its curve is the steepest in the game.
		baseThreatMultiplier = 1.35,
		baseHazardMultiplier = 1.45,
		threatBandMultipliers = {
			Introduction = 1,
			Standard = 1.15,
			Dangerous = 1.35,
			Expert = 1.57,
			Extreme = 1.82,
		},
		hazardBandMultipliers = {
			Introduction = 1,
			Standard = 1.15,
			Dangerous = 1.38,
			Expert = 1.62,
			Extreme = 1.92,
		},
		waxDrainMultiplier = 1,

		topology = {
			-- Fewer cycles, longer connectors: Ice reads as a system of halls rather than a warren,
			-- and being caught in one is a longer walk out of it.
			loopBias = 0.9,
			optionalBranchBias = 1.1,
			connectorLengthBias = 1.2,
			verticalVariation = 1.15,
		},
		geometry = {
			roomSizeScaleMin = 0.95,
			roomSizeScaleMax = 1.18,
			ceilingPreferredMin = 22,
			ceilingPreferredMax = 46,
			ceilingPreferenceStrength = 0.6,
			-- Fewer things to hide behind, which is the whole point of the family.
			internalFormationDensity = 0.8,
			doorwayWidthBias = 1.12,
			-- FALLING ICE IS ICE'S SIGNATURE PRESSURE, and this sits slightly above the brief's nominal
			-- 1.35 to pay for something the brief could not have known: Ice biases its ceilings tall,
			-- and the tallest vaults cannot carry a falling hazard at all. Even the longest spire cannot
			-- bring a tip down into the readable band from a forty-five-stud roof, and that limit is a
			-- readability rule that does not bend — so Ice has roughly a tenth fewer eligible rooms than
			-- Stone or Moss by construction. This makes up that ground through the rooms it CAN use.
			dripstoneFactor = 1.45,
		},
		roomShapeWeights = {
			Rectangle = 50,
			Ellipse = 20,
			-- Long vaults and fracture-like connectors.
			Capsule = 25,
			TwinLobe = 5,
		},
		environment = {
			wetFloorProbability = 0.3,
			-- Ice never grows vines. It uses barred icicle curtains through the same optional-route
			-- placement contract, with a different data-stamped style and clearing behaviour.
			vinesEnabled = true,
			doorwayBarrierStyle = "Icicles",
			vineIntroductionShift = 0,
			vineCountFactor = 1,
			-- Nothing grows in Ice, so nothing in it burns.
			flammableVegetation = false,
		},
		threatEcology = {
			-- ICE IS HUNTING GROUND: open, bare, nothing to perch on and nowhere to hide. The crawler
			-- and the ceiling ambusher both gain; the moth is slightly rarer than the roster average.
			-- Averaged from the old per-row values on the same basis as Moss above.
			weightMultipliers = {
				DarkCrawler = 1.2,
				Moth = 0.95,
				VoidFly = 1.2,
				Listener = 0,
				Knotwalker = 0,
				-- ICE'S SIGNATURE CREATURE. See Stone's row for why an exclusive creature is only ever a
				-- zero in the other two families rather than a mechanism of its own.
				Calver = 1,
			},
			-- Ice meets its crawlers a floor early — the deep-crawler shift, which is what two of that
			-- family's three old shifts were once they became one row.
			introductionShift = {
				DarkCrawler = 1,
			},
		},
		hazardEcology = {
			-- ICE'S CEILINGS ARE THIN AND SHARP. Needles and long spires — the two the family already
			-- hangs more of than anywhere else — plus the Splintered Lance at roughly a quarter of its
			-- formations. The blunt Heavy Crown is nearly refused: it is the slowest, widest, most
			-- forgiving thing in the pool and it reads as the opposite of what this family is.
			--
			-- NOTE THE HAMMER IS 0.5 AND NOT 0. Config/StoneWarden.counterDripstoneVariantId hard-names
			-- the Heavy Crown as the Warden's one counter in EVERY family, so Ice keeps drawing them
			-- naturally as well — a player who has never seen one outside a Warden den would not read
			-- the counter as an ordinary cave formation they can lead something under.
			variantWeightMultipliers = {
				Needle = 1.6,
				Fork = 0.8,
				Hammer = 0.5,
				Spire = 1.9,
				Lance = 3,
				Mass = 0,
			},
		},
		ambience = {
			-- ICE IS DRY, HARD AND STRUCTURAL. Nothing grows, nothing seeps
			-- (`environment.wetFloorProbability` 0.3, `vinesEnabled` false), and nothing loose creeps
			-- across a floor that is frozen in place. What is left is the cave itself under load: strata
			-- strain, air moving down long open halls, and the glacier groan overhead.
			candidateWeights = {
				StrataStrain = 1.5,
				FissureBreath = 1.15,
				CalciteTicks = 0.9,
				HiddenWaterPulse = 0.45,
				GravelCreep = 0.75,
				DistantSettle = 1.25,
				ColdDraft = 1.35,
				DripCluster = 0.45,
				SeepRun = 0,
				GlacierGroan = 1,
				Rockfall = 1.15,
				WaterDrip = 0.5,
				-- Iron frozen into a wall and timber gone brittle in the cold both move suddenly rather
				-- than slowly, which is the same reason Ice is the quietest cave and the most abrupt.
				OldWorkings = 1.2,
			},
			-- THE QUIETEST CAVE, AND THE MOST SUDDEN — and safe in exactly the direction that matters. A
			-- thinner ambient bed makes creature locomotion EASIER to hear, not harder: ambience is on
			-- the Ambience bus, locomotion is on World/Focus, and the director already refuses to fire
			-- while Focus has been live. The forbidden direction is a family loud enough to MASK an
			-- approach, which is why no family raises a cue's gain and Moss's busier profile is a much
			-- smaller move than this one.
			silenceWeight = 1.15,
		},
		presentation = {
			-- THE SINGLE STRONGEST LEVER ON WHETHER THIS CAVE READS AS ICE, and the one that was doing the
			-- least work before. Atmosphere colour is what every distant surface washes toward, so with
			-- Ice's very high haze (1.75) it tints a larger fraction of the screen than any material in
			-- the family. At the old near-neutral grey-blue the haze was washing distance toward GREY,
			-- and grey under a warm candle grade is why the cave read as a muddy tunnel rather than a
			-- glacier. Pulling red down and blue up turns the same haze into cold depth.
			--
			-- Colour only: `atmosphereDensity` below is untouched, so how far a flame carries here — the
			-- thing a player actually feels — is exactly what it was.
			atmosphereColor = Color3.new(0.34, 0.56, 0.75),
			atmosphereDecay = Color3.new(0.1, 0.17, 0.28),
			-- THE LINE THAT MAKES THIS AN ICE CAVE, and the one every previous attempt was missing.
			-- Read `ColorGradeProfile` before touching it: with ambient pinned to black, warm light is
			-- the ONLY light, so warm-lit rock is the only thing that can ever be on screen no matter
			-- how blue the rock itself is authored. This is what takes the red back out of it.
			--
			-- The red channel does nearly all the work. Cutting it by a quarter is what turns "warm
			-- stone" into "ice", because the warm candle grade (255, 242, 220) and the flare are both
			-- pushing hardest in exactly that channel. Green is trimmed lightly so the result lands on
			-- blue-teal rather than on pure blue, and blue itself is left at 1 — a grade may only ever
			-- subtract, so raising it is not available and is not needed.
			--
			-- IT CANNOT BRIGHTEN ANYTHING. Every channel is at or below 1, black multiplies to black,
			-- and an unlit room is exactly as unreadable as it was. If Ice ever needs to read colder
			-- still, take more red — do not touch a material palette, and never reach for a light.
			colorGrade = {
				tintColor = Color3.new(0.75, 0.93, 1),
				-- The tint alone lands slightly grey; this is what lets the surviving blue read as a
				-- colour rather than as a desaturated wash.
				saturation = 0.12,
				contrast = 0.03,
			},
			-- THIN, CLEAR, AND FAR. The lightest air in the game, and the visual half of the exposure the
			-- family is built on: your flame reaches further here, which sounds like a kindness and is
			-- not — Ice's threats sense you from further too (`baseThreatMultiplier` 1.35, longest
			-- sightlines, fewest things to hide behind), so seeing further mostly means watching
			-- something come. The high haze is what gives its long halls visible depth rather than a hard
			-- edge into black; the glare is ice crystals in the air.
			atmosphereDensity = 0.3,
			atmosphereHaze = 1.75,
			atmosphereGlare = 0.18,
			-- SATURATION, NOT BRIGHTNESS, IS WHAT MAKES ROCK READ COLD. The previous values were already
			-- nominally blue and still came out muddy, and the reason is arithmetic: the candle grade is
			-- roughly (255, 242, 220), so it multiplies red by 1.0 and blue by only ~0.86. A rock whose
			-- blue merely EXCEEDS its red arrives at the eye as neutral grey-brown, because the light
			-- spends the difference on the way. The fix is to widen the gap at the source — blue here is
			-- roughly five times red rather than under three — and the candle then lands it on cold
			-- blue-teal instead of on grey.
			--
			-- THIS COSTS NO BRIGHTNESS, which is the whole reason it is available. Blue carries only 7%
			-- of perceived luminance against green's 72%, so tripling the blue-to-red ratio moves the
			-- luminance these are bound by (Tests/CaveFamilyRulesTests, ROCK_LIMIT 0.30) barely at all —
			-- every one of these is DARKER than the value it replaces while reading far colder. A cave
			-- may take a hue; it may never take brightness, and this takes only the hue.
			wallColor = ICE_ROCK,
			-- Barely above the wall, where it used to be half again as bright. The broken shards are
			-- the largest PARTS in a room (up to ~10 x 13 studs), so any gap between this and the
			-- terrain tone shows up as bright panels stuck on a dark cave — see the palette note below.
			rockColor = Color3.fromRGB(26, 70, 108),
			-- THE SAME COLOUR AS THE WALLS, and the same VALUE rather than a matching literal, so the
			-- two cannot drift apart the next time either is retuned.
			--
			-- This deliberately abandons the offset the other two families still use, where terrain is
			-- pitched a shade darker than the walls to compensate for terrain rendering brighter. That
			-- compensation assumes the written colour is the colour you get, and for Ice it is not:
			-- `SetMaterialColor` clamps a terrain material's colour to a limited range around its own
			-- default, and Glacier's default is pale blue-white, so the tint lands wherever the engine
			-- allows regardless of how it was pitched. A hand-tuned offset on top of an engine clamp is
			-- two corrections fighting over a value neither of them controls; matching the walls
			-- exactly is the honest version and is what was actually asked for.
			terrainColor = ICE_ROCK,
			-- ACTUAL ICE, which is the one thing every other candidate here was not.
			--
			-- The floor is the problem this line exists to solve. Roblox terrain renders TOP faces from
			-- a different texture than sides, so a material with a distinct top gives a cave a floor
			-- made of visibly different stuff from its walls out of one material and one colour — and
			-- Glacier's top is a smooth snow-ice that washed warm under a close flame. That is why the
			-- ceiling read blue-green and the floor read tan in the same room.
			--
			-- THREE MATERIALS RULED OUT, so nobody re-runs them: Glacier splits top from side, as
			-- above. Slate is uniform but its texture is a smooth streaky layered surface with no crack
			-- detail. Basalt is uniform and dark but carries rust and green flecks that go orange under
			-- warm light. `Ice` is the only one that is uniform across faces AND is genuinely ice.
			--
			-- It also fixes the tint. `SetMaterialColor` clamps toward a material's own default, so a
			-- pale default can never be made cold; Ice's default is already blue, which is what finally
			-- lets `ICE_ROCK` land somewhere near where it is written.
			terrainMaterial = Enum.Material.Ice,
			-- THE STUDIO-AUTHORED PBR SKIN FOR `Enum.Material.Ice`, registered once via
			-- `MaterialService:SetBaseMaterialOverride` (server/FloorBuilder.build). Ice is the only
			-- family whose `wallMaterial`, `rockMaterial`, `coverFinish`, `formationFinish` and
			-- `formationMaterials` ALSO resolve to plain `Enum.Material.Ice` below, and terrain material
			-- overrides are global per place (see the field's own comment on `PresentationProfile`) — so
			-- this variant is not floor-and-ceiling-only, it is every one of those surfaces at once, in
			-- this family alone. That was a deliberate, explicit tradeoff, not an oversight: scoping the
			-- skin to terrain only is not something Roblox exposes.
			terrainMaterialVariant = "GlacialCaveIce",
			-- BACK TO ICE FROM GLACIER, because a material does not render the same way on a part as
			-- it does on terrain — different texture set, different projection. Glacier on a PART is a
			-- rippled water-like surface, nothing like the cracked rock Glacier TERRAIN produces, and
			-- putting it on the doorway slabs is what made the openings read as the wrong material
			-- entirely. `Ice` is the crystalline cracked surface, which is what these want.
			wallMaterial = Enum.Material.Ice,
			rockMaterial = Enum.Material.Ice,
			-- VISIBLE, AND IT HAS TO STAY THAT WAY. Hiding these was tried and produced invisible walls
			-- players walked into, so this is a correctness bound rather than a taste setting.
			--
			-- THE REASONING THAT FAILED, recorded so nobody repeats it: `fillRoomTerrain` does fill
			-- every column outside the room's open mask, and `RoomFootprint` caps that mask at
			-- `cellSize/2 - wallClearance` (30 studs) while the slabs sit at the cell edge (~32) — so on
			-- paper a 2-stud band of solid terrain stands in front of every slab and hiding one would
			-- merely reveal rock. It does not. Terrain is written at 4-STUD VOXEL RESOLUTION, and a
			-- 2-stud band cannot be represented at 4-stud resolution: it snaps away, and the slab is
			-- left standing in open air as the actual wall.
			--
			-- The simplest proof is the one that should have been applied first: these slabs are
			-- plainly VISIBLE in game. If terrain stood in front of them they would not be. Anything
			-- that is visible is, by definition, not behind something else — so hiding it removes a
			-- surface rather than uncovering one, and the collision it carries becomes invisible.
			wallSlabTransparency = 0,
			-- PULLED ONTO THE ROCK'S OWN TONE, and this was the reason the cave looked like two
			-- materials rather than one. These were authored near the dressing luminance bound (0.40)
			-- on the theory that frost should be the brightest thing in the room; the terrain they sit
			-- against renders far darker, so what actually shipped was saturated teal panels stuck to
			-- a dark cave. Frost is not a different substance from the rock it grew on, and the
			-- brightest entry here is now barely above `ICE_ROCK` rather than double it.
			--
			-- BRIGHTNESS WAS NEVER WHAT SOLD IT. What separates cover from wall is the FINISH below —
			-- which facet catches the flame and how — and that works far better against a matched tone
			-- than against a contrasting one, because a highlight reads as a highlight only when the
			-- surface under it is not already bright.
			coverPalette = {
				Color3.fromRGB(26, 70, 106),
				Color3.fromRGB(18, 58, 92),
				Color3.fromRGB(34, 82, 118),
				Color3.fromRGB(14, 48, 80),
			},
			coverMaterial = Enum.Material.Ice,
			-- RAISED WITH THE SIZE DROP IN `coverFinish`, not independently of it. Those two numbers
			-- are one decision: many small facets read as crystalline, few large ones as panels, and
			-- changing either alone just makes the wall sparse or cluttered.
			coverDensityFactor = 2.5,
			coverShape = "Shard",
			groundCoverPatchesPerRoom = 12,
			-- WHAT ACTUALLY MAKES THIS CAVE READ AS ICE. The palette above was already blue and the
			-- cave still looked like painted cardboard, because every facet was opaque, matte, flush
			-- and identical — see `SurfaceFinishProfile` for why specular behaviour, not hue, is how
			-- the eye identifies ice.
			--
			-- FOUR MATERIALS ACROSS ONE WALL. Ice is the crystalline default, Glacier is the milky
			-- packed crust between the clear parts, and Glass is the occasional genuinely clear lens.
			-- Ice appears twice so it stays the dominant read and the other two stay accents.
			--
			-- The reflectance range is the single most important line in this row: at zero, frost is a
			-- blue sticker at any hue; at these values a highlight slides across each facet
			-- independently as the player's flame moves, which is the entire tell. The range is wide
			-- on purpose — uniform reflectance is only slightly less flat than none.
			coverFinish = {
				-- NO GLASS HERE, deliberately, and it is the single biggest thing separating "looks
				-- cheap" from "looks like rock" on this layer. Roblox's Glass carries no surface
				-- texture at all, so a Glass facet is a flat untextured polygon — fine on the small
				-- 3D formations below, where silhouette does the work, and the worst possible choice
				-- on a broad flat quad lying against a wall, which is exactly what wall cover is. Ice
				-- and Glacier both have real grain and hold up at that size.
				materials = {
					Enum.Material.Ice,
					Enum.Material.Glacier,
					Enum.Material.Ice,
				},
				transparencyMin = 0.02,
				transparencyMax = 0.22,
				-- KEPT DELIBERATELY LOW, and this was overcooked once at 0.08–0.36. Roblox
				-- `Reflectance` blends a part toward a reflection of the ENVIRONMENT, and this game has
				-- no environment to speak of — ambient is black and there is no meaningful skybox — so
				-- a high value does not read as a wet ice highlight, it just washes the part pale and
				-- warm. Rolled per facet, that produced exactly the scattered mismatch it was meant to
				-- prevent: some shards teal, their neighbours bleached. A little is grain; a lot is a
				-- different material.
				reflectanceMin = 0.01,
				reflectanceMax = 0.09,
				-- 0.22 studs read as paper. Ice crusts have volume and cast a real edge.
				thicknessScale = 2.6,
				-- SMALL ENOUGH NOT TO BE A PANEL. This is the number that decides whether wall cover
				-- reads as frost or as sheets stuck to the rock, and the threshold is lower than it
				-- looks: the authored patch runs to 7 studs, and anything past roughly 3 on a flat
				-- wall face stops reading as a crystal and starts reading as a quad. Paired with the
				-- raised `coverDensityFactor` so the wall gains facets rather than losing cover.
				sizeScale = 0.4,
				-- Tilted well off the wall so the facets stop flashing in unison.
				tiltDegrees = 24,
			},
			-- Clearer and glassier than the frost: a hanging icicle is nearer to lens than to crust.
			-- Transparency is capped well below the cover's, because this finish also dresses the
			-- UNSTABLE formations, and a falling hazard has to stay unmistakably solid — its fracture
			-- lines are a warning a player is meant to read at range (ART-BIBLE §8).
			formationFinish = {
				-- No Glass here either. A near-clear, highly reflective facet on a boulder or a wall
				-- shard does not read as ice — with no environment behind it, it reads as a pale flat
				-- quad that belongs to a different cave than everything around it.
				materials = {
					Enum.Material.Ice,
					Enum.Material.Glacier,
					Enum.Material.Ice,
				},
				transparencyMin = 0,
				transparencyMax = 0.1,
				reflectanceMin = 0.01,
				reflectanceMax = 0.07,
				thicknessScale = 1,
				sizeScale = 1,
				tiltDegrees = 0,
			},
			-- A SECOND MATERIAL LAYER ON A FLOOR THAT HAD ONE. The eight frost shards above are small
			-- and angular — they dress the ground without changing what it IS. These are broad flat
			-- panes of clear ice with real reflectance, so a candle crossing one throws back a highlight
			-- the packed glacier around it cannot, and the floor stops reading as a single poured
			-- surface. Six per room, against a 64-stud cell: sparse enough to stay an interruption.
			floorGlaze = {
				sheetsPerRoom = 6,
				minSize = 7,
				maxSize = 17,
				thickness = 0.32,
				palette = {
					Color3.fromRGB(24, 66, 100),
					Color3.fromRGB(18, 56, 90),
					Color3.fromRGB(32, 78, 114),
				},
				material = Enum.Material.Glass,
				-- Clear enough to read as ice over rock rather than as a painted panel, opaque enough
				-- that the highlight has something to sit on.
				transparency = 0.52,
				reflectance = 0.16,
			},
			-- THE SILHOUETTE THAT SAYS "ICE CAVE" BEFORE ANY MATERIAL DOES. Three clusters hung inside
			-- every doorway mouth is the load-bearing number here: a player looks at an opening before
			-- they walk through it, so fringing the openings puts the family's signature shape directly
			-- in the path of attention for a fraction of the parts that dressing whole ceilings costs.
			icicleFringe = {
				clustersPerRoom = 7,
				clustersPerDoorway = 3,
				spikesPerCluster = 6,
				minLength = 1.8,
				maxLength = 6.5,
				rootThickness = 0.62,
				spread = 2.6,
			},
			-- ICICLES. The same unstable formation with the same warning, fall timing and impact rules,
			-- dressed in ice: pale blue-grey and glassy rather than matte slate. Deliberately not white
			-- and deliberately not emissive — a self-lit cavern would undo the rule that light is the
			-- only source of visual information.
			-- On the rock's tone for the same reason the cover palette is: a stalactite is made of the
			-- cave, not stuck to it.
			formationPalette = {
				Color3.fromRGB(22, 64, 98),
				Color3.fromRGB(30, 76, 112),
				Color3.fromRGB(16, 52, 84),
				Color3.fromRGB(38, 88, 124),
			},
			formationMaterials = {
				Enum.Material.Glacier,
				Enum.Material.Ice,
				Enum.Material.Slate,
				Enum.Material.Glacier,
			},
			formationWetMaterial = Enum.Material.Ice,
			blastDoorStyle = "Ice",
			-- CHIPPED AND CRUSTED. An Ice cage is a sled cut from packed glacier riding a chain the
			-- frost has already taken; the vessel is the same dark blue-grey stone the walls are. The
			-- palette is the coldest of the three and still the darkest thing in the room until a
			-- candle reaches it.
			fixtureStyle = {
				rig = "Chipped",
				frameColor = Color3.fromRGB(40, 66, 88),
				frameMaterial = Enum.Material.Metal,
				deckColor = Color3.fromRGB(46, 88, 118),
				deckMaterial = Enum.Material.Glacier,
				lineColor = Color3.fromRGB(52, 84, 104),
				lineMaterial = Enum.Material.Metal,
				vesselColor = Color3.fromRGB(26, 48, 70),
				vesselMaterial = Enum.Material.Slate,
			},
			threatVariantId = "Ice",
			threatVariantTintStrength = 0.32,
			-- RIME. Not growth — nothing grows here. Frost crusted onto the UPWARD-FACING surfaces only:
			-- the tops of the shoulders, the back of the crown, the tops of the feet, plus thin spurs off
			-- the elbow and heel that catch the flame exactly as a limb swings. Reads as something that
			-- does not move often and has frozen where it stands.
			--
			-- LOWER COVERAGE THAN MOSS ON PURPOSE. Pale-on-black is the highest-contrast dressing in the
			-- game, so an Ice body already reads at longer range than a Stone one. That direction is safe
			-- — a more visible enemy is an easier one, and no stat moves — but it is why the coverage and
			-- the feature size are both pulled down, and why `headExclusion` matters most here: the
			-- crimson slits must still be the first thing that resolves, not the second.
			creatures = {
				growthStyle = "Rime",
				growthCoverage = 0.82,
				growthSize = 1.55,
				growthPalette = {
					Color3.fromRGB(48, 92, 124),
					Color3.fromRGB(36, 76, 110),
					Color3.fromRGB(60, 104, 138),
				},
				growthMaterial = Enum.Material.Glacier,
				-- The body stays near-black, but its nominated skin surfaces now catch the same hard grain as
				-- the frost on them. Eyes, moth wings, membranes and heads remain untouched by each builder.
				skinMaterial = Enum.Material.Glacier,
				headExclusion = true,
			},
			-- Packed glacier: a brittle crunch, bright and with no tail at all.
			footstepCue = "FootstepIce",
			-- LONG AND HARD. The biggest acoustic in the game: fewest internal formations to break sound up
			-- (0.8), longest connectors, tallest ceilings, and every surface glassy. A sound you make here
			-- comes back to you, which is exactly the exposure the family is built on — in Ice the cave
			-- answers, and everything in it hears you do it.
			reverbDecayScale = 1.65,
			reverbWetOffset = 3,
		},
		ore = {
			nativeTier = 3,
			availability = {
				{ minDepth = 1, tiers = { { tier = 3, weight = 100 } } },
			},
		},
	},
}

return {
	profileVersion = PROFILE_VERSION,
	-- The family every unknown, absent, or rolled-back id resolves to. Stone is free and always
	-- owned, so a bad id can never grant access to something a player has not bought.
	defaultId = "STONE" :: CaveFamilyId,
	families = Families,
}

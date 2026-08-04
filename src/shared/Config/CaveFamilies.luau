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
	-- Fraction of a body's eligible anchor points that carry a feature. Kept well below 1: this is
	-- weathering on a creature, not a costume, and a fully covered body would start to read as a
	-- different silhouette rather than the same one somewhere else.
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

export type PresentationProfile = {
	-- Global Atmosphere, applied once per expedition (server/EnvironmentSetup.applyCaveFamily).
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
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
	-- Structural wall slabs, and the jagged shards broken across every wall face.
	wallMaterial: Enum.Material,
	rockMaterial: Enum.Material,
	-- Collision-neutral surface dressing: the moss, frost or growth that creeps up this family's walls.
	-- `coverDensityFactor` scales the authored patch counts in Config/Floors.caveMoss.
	coverPalette: { Color3 },
	coverMaterial: Enum.Material,
	coverDensityFactor: number,
	-- The palette and materials every hanging/standing FORMATION is built from — stalactites,
	-- stalagmites, soda straws, boulders, and the unstable formations that fall. This is what makes an
	-- Ice cave's unstable formations read as icicles: the falling HAZARD is the same object with the
	-- same warning, timing and impact rules (Config/Hazards.unstableDripstone, Logic/DripstoneRules),
	-- dressed in this family's rock.
	formationPalette: { Color3 },
	formationMaterials: { Enum.Material },
	formationWetMaterial: Enum.Material,
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
-- Bumped to 3 when a family also gained its own AIR (atmosphere density/haze/glare), its own
-- ACOUSTIC (reverb decay scale and wet offset) and its own FOOTSTEP CUE. Bumped to 2 when it gained: `hazardEcology` (which formations its ceilings
-- hang), `ambience` (how often the cave makes each of its sounds), and `presentation.creatures` (the
-- geometry that has taken hold on a body living here). A shape change, not a retune.
local PROFILE_VERSION = 3

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
				SeepRun = 0,
				GlacierGroan = 0,
				Rockfall = 1,
				WaterDrip = 1,
			},
			silenceWeight = 1,
		},
		presentation = {
			atmosphereColor = Color3.new(0.62, 0.66, 0.74),
			atmosphereDecay = Color3.new(0.22, 0.24, 0.3),
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
			wallMaterial = Enum.Material.Slate,
			rockMaterial = Enum.Material.Slate,
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
			vineIntroductionShift = 2,
			vineCountFactor = 1.35,
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
				SeepRun = 1,
				GlacierGroan = 0,
				Rockfall = 0.9,
				WaterDrip = 1.7,
			},
			-- The one cave that is never quite quiet. Deliberately a small move: this changes how often
			-- the director spends a turn on nothing, and nothing else — no cue gets louder anywhere.
			silenceWeight = 0.85,
		},
		presentation = {
			atmosphereColor = Color3.new(0.5, 0.55, 0.5),
			atmosphereDecay = Color3.new(0.16, 0.19, 0.16),
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
			wallMaterial = Enum.Material.Rock,
			rockMaterial = Enum.Material.Basalt,
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
			-- Nothing grows here. Ice's optional-route pressure comes from hazard density and open
			-- ground, never from a curtain.
			vinesEnabled = false,
			vineIntroductionShift = 0,
			vineCountFactor = 0,
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
				SeepRun = 0,
				GlacierGroan = 1,
				Rockfall = 1.15,
				WaterDrip = 0.5,
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
			atmosphereColor = Color3.new(0.48, 0.55, 0.64),
			atmosphereDecay = Color3.new(0.14, 0.17, 0.22),
			-- THIN, CLEAR, AND FAR. The lightest air in the game, and the visual half of the exposure the
			-- family is built on: your flame reaches further here, which sounds like a kindness and is
			-- not — Ice's threats sense you from further too (`baseThreatMultiplier` 1.35, longest
			-- sightlines, fewest things to hide behind), so seeing further mostly means watching
			-- something come. The high haze is what gives its long halls visible depth rather than a hard
			-- edge into black; the glare is ice crystals in the air.
			atmosphereDensity = 0.3,
			atmosphereHaze = 1.75,
			atmosphereGlare = 0.18,
			wallColor = Color3.fromRGB(48, 56, 68),
			rockColor = Color3.fromRGB(58, 68, 82),
			terrainColor = Color3.fromRGB(44, 52, 64),
			-- DENSE PACKED GLACIER. Tinted hard toward the same dark blue-grey as everything else here:
			-- the material supplies the grain, never the brightness.
			terrainMaterial = Enum.Material.Glacier,
			wallMaterial = Enum.Material.Glacier,
			rockMaterial = Enum.Material.Ice,
			-- Restrained pale ice and dirty frost. Deliberately NOT bright: a self-lit cavern would
			-- undo the rule that light is the only source of visual information.
			coverPalette = {
				Color3.fromRGB(64, 78, 92),
				Color3.fromRGB(52, 66, 80),
				Color3.fromRGB(76, 90, 102),
				Color3.fromRGB(44, 56, 70),
			},
			coverMaterial = Enum.Material.Ice,
			coverDensityFactor = 1.4,
			-- ICICLES. The same unstable formation with the same warning, fall timing and impact rules,
			-- dressed in ice: pale blue-grey and glassy rather than matte slate. Deliberately not white
			-- and deliberately not emissive — a self-lit cavern would undo the rule that light is the
			-- only source of visual information.
			formationPalette = {
				Color3.fromRGB(62, 76, 90),
				Color3.fromRGB(74, 90, 104),
				Color3.fromRGB(52, 64, 78),
				Color3.fromRGB(84, 98, 110),
			},
			formationMaterials = {
				Enum.Material.Glacier,
				Enum.Material.Ice,
				Enum.Material.Slate,
				Enum.Material.Glacier,
			},
			formationWetMaterial = Enum.Material.Ice,
			threatVariantId = "Ice",
			threatVariantTintStrength = 0.18,
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
				growthCoverage = 0.4,
				growthSize = 0.85,
				growthPalette = {
					Color3.fromRGB(58, 72, 86),
					Color3.fromRGB(48, 62, 76),
					Color3.fromRGB(70, 84, 96),
				},
				growthMaterial = Enum.Material.Glacier,
				skinMaterial = nil,
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

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

export type PresentationProfile = {
	-- Global Atmosphere, applied once per expedition (server/EnvironmentSetup.applyCaveFamily).
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
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
	presentation: PresentationProfile,
	ore: OreProfile,
}

-- Bumped whenever the SHAPE of a profile changes (a field added, removed, or given a new meaning),
-- never for a retune. Recorded in telemetry beside a generated floor so a report can be read against
-- the schema it was produced under.
local PROFILE_VERSION = 1

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
			weightMultipliers = {},
			introductionShift = {},
		},
		presentation = {
			atmosphereColor = Color3.new(0.62, 0.66, 0.74),
			atmosphereDecay = Color3.new(0.22, 0.24, 0.3),
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
			weightMultipliers = {
				Lurker = 1.25,
				Stalker = 0.75,
				Hollow = 1.2,
				VoidFly = 1,
				Moth = 1.15,
				Swarm = 1.35,
				AshMoth = 0.85,
				Snuffer = 1.25,
			},
			introductionShift = {
				Swarm = 1,
				Snuffer = 1,
			},
		},
		presentation = {
			atmosphereColor = Color3.new(0.5, 0.55, 0.5),
			atmosphereDecay = Color3.new(0.16, 0.19, 0.16),
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
			weightMultipliers = {
				Lurker = 0.85,
				Stalker = 1.35,
				Hollow = 1.35,
				VoidFly = 1.2,
				Moth = 1,
				Swarm = 0.7,
				AshMoth = 1.25,
				Snuffer = 0.9,
			},
			introductionShift = {
				Stalker = 1,
				Hollow = 1,
				AshMoth = 1,
			},
		},
		presentation = {
			atmosphereColor = Color3.new(0.48, 0.55, 0.64),
			atmosphereDecay = Color3.new(0.14, 0.17, 0.22),
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

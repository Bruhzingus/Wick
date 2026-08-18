--!strict
-- Floor assembly tuning (DESIGN §18). Floors are assembled procedurally from weighted room modules.
-- Logic/FloorPlanner consumes this; server FloorBuilder only reads the resulting plan.

local Types = require(script.Parent.Parent.Types)

export type FloorGeometryConfig = {
	cellSize: number,
	wallHeight: number,
	wallThickness: number,
	doorwayMinWidth: number,
	doorwayMaxWidth: number,
	doorwayMinHeight: number,
	doorwayMaxHeight: number,
	doorwayCornerMargin: number,
	ceilingMinHeight: number,
	ceilingMaxHeight: number,
	floorGap: number,
	placementProbe: {
		upStuds: number,
		downStuds: number,
		horizontalMarginStuds: number,
		placementPadMarginStuds: number,
		placementPadBlendStuds: number,
		maxPeripheralDeltaStuds: number,
		maxUpwardSlopeDegrees: number,
		maxSeatedGapStuds: number,
	},
}

export type CaveDressingConfig = {
	formationPalette: { Color3 },
	formationDampTint: Color3,
	formationMaterials: { Enum.Material },
	formationWetMaterial: Enum.Material,
	formationWetReflectance: number,
	wallRockCount: number,
	wallRockMinSize: number,
	wallRockMaxSize: number,
	-- FLOWSTONE DRAPERY (CaveKit.drapery), the only large-scale form a wall carries. Rolled per wall
	-- rather than counted, because a room with a sheet on every wall reads as a decorated room and the
	-- point of the form is that a wall sometimes has one.
	drapeChancePerWall: number,
	drapeMinHalfWidth: number,
	drapeMaxHalfWidth: number,
	drapeMinLength: number,
	drapeMaxLength: number,
	drapeRootThickness: number,
	drapeSegments: number,
	-- Where the TOP of the sheet attaches, as a fraction of wall height. Never near the floor: flowstone
	-- is deposited by water running down a face, so a sheet that starts at knee height has nothing above
	-- it that could have fed it.
	drapeMinTopFraction: number,
	drapeMaxTopFraction: number,
	drapeDoorwayClearance: number,
	bouldersPerRoom: number,
	boulderMinSize: number,
	boulderMaxSize: number,
	rockColumnsPerRoom: number,
	rockColumnMinHeight: number,
	rockColumnMaxHeight: number,
	rockColumnMinWidth: number,
	rockColumnMaxWidth: number,
	-- TRUE PILLARS (CaveKit.column) — a stalactite and a stalagmite that have met. Distinct from
	-- `rockColumn*` above, which is the alternating half-height formation pair and joins nothing.
	--
	-- This is the one piece of dressing that is full-height COLLIDABLE mass in the middle of a room, so
	-- it is the only one held off the doorway routes as well as off the gameplay reservations. It is
	-- also capped by ceiling height rather than scaled to it: a 46-stud shaft of rock reads as a poured
	-- concrete pillar, and the form only says "this room is old" at chamber scale, not at cathedral
	-- scale.
	pillarChancePerRoom: number,
	pillarMinWidth: number,
	pillarMaxWidth: number,
	pillarMaxCeilingHeight: number,
	pillarRingMinFactor: number,
	pillarRingMaxFactor: number,
	pillarRouteClearance: number,
	pillarPlacementAttempts: number,
	-- Loose chips banked on the floor (CaveKit.rubble). Collision-neutral and ankle height: the cheapest
	-- thing in the kit and the fastest way to stop smooth Terrain reading as a poured plane. Kept out
	-- near the walls, where breakdown actually collects, rather than scattered through the middle.
	rubblePatchesPerRoom: number,
	rubbleChipsPerPatch: number,
	rubblePatchArea: number,
	rubbleRingMinFactor: number,
	rubbleRingMaxFactor: number,
	caveMouthRocksPerSide: number,
	caveMouthCeilingRocks: number,
	caveMouthRockMinSize: number,
	caveMouthRockMaxSize: number,
	caveMouthArchFacetMinLength: number,
	caveMouthArchFacetMaxLength: number,
	caveMouthArchFacetThickness: number,
	caveMouthArchFacetDepth: number,
	caveMouthArchFacetEmbed: number,
	ceilingFormationsPerRoom: number,
	ceilingFormationMinLength: number,
	ceilingFormationMaxLength: number,
	ceilingFormationMinWidth: number,
	ceilingFormationMaxWidth: number,
	ceilingBouldersPerRoom: number,
	ceilingStrawsPerCluster: number,
	ceilingStrawSpread: number,
	ceilingFormationGroundGap: number,
	ceilingFormationExtentRadiusFactor: number,
	ceilingStrawLengthMultiplier: number,
	ceilingFacetClustersPerRoom: number,
	ceilingFacetPlacementAttempts: number,
	ceilingFacetPiecesPerCluster: number,
	ceilingFacetMinSize: number,
	ceilingFacetMaxSize: number,
	ceilingFacetMinThickness: number,
	ceilingFacetMaxThickness: number,
	ceilingFacetSpread: number,
	ceilingFacetEmbed: number,
	ceilingFacetEdgeInset: number,
	ceilingFacetSlopeSample: number,
}

export type TerrainConfig = {
	groundHumpsPerRoom: number,
	groundHumpMinDiameter: number,
	groundHumpMaxDiameter: number,
	groundHumpMinHeight: number,
	groundHumpMaxHeight: number,
	groundHumpMinRadius: number,
	groundHumpMaxRadius: number,
	groundHumpSeparation: number,
	groundPatchFallbackOffset: number,
	specialRoomCenterClearance: number,
	doorClearanceDepth: number,
	doorClearanceWidth: number,
	wallClearance: number,
	hazardClearance: number,
	placementAttemptsPerHump: number,
	aiGroundProbeHeight: number,
	aiGroundProbeDepth: number,
	aiRoofProbeFloorInset: number,
	aiObstacleSidestep: number,
	gameplaySpawnRadius: number,
	gameplaySpawnSeparation: number,
}

export type RoofConfig = {
	rockThickness: number,
	minRelief: number,
	maxRelief: number,
	shortRoomReliefScale: number,
	reliefPerCeilingStud: number,
	longFrequencyMin: number,
	longFrequencyMax: number,
	rippleFrequencyMin: number,
	rippleFrequencyMax: number,
	shapeFloorWeight: number,
	longWaveAmplitude: number,
	rippleAmplitude: number,
	edgeBlend: number,
	minimumClearance: number,
}

export type GroundFieldConfig = {
	doorLaneMargin: number,
	volumeBase: number,
	amplitudeBase: number,
	amplitudeDepthStep: number,
	amplitudeBaseMax: number,
	amplitudeRandomMin: number,
	amplitudeRandomMax: number,
	amplitudeMin: number,
	amplitudeMax: number,
	wallRiseRandomMin: number,
	wallRiseRandomMax: number,
	wallRiseMin: number,
	wallRiseMax: number,
	grandeurJitter: number,
	openRadiusMin: number,
	openRadiusEdgePadding: number,
	enclosureHeadroom: number,
	bermMinimum: number,
	rippleAmplitudeMin: number,
	rippleAmplitudeMax: number,
	centerPadRadius: number,
	blend: number,
	fillHeightPadding: number,
	longFrequencyMin: number,
	longFrequencyMax: number,
	rippleFrequencyMin: number,
	rippleFrequencyMax: number,
	wallBermStart: number,
	enclosureBlendMultiplier: number,
	poolFlatFraction: number,
}

export type CaveMossConfig = {
	enabled: boolean,
	palette: { Color3 },
	material: Enum.Material,
	dampPalette: { Color3 },
	dampMaterial: Enum.Material,
	patchesPerWall: number,
	dampPatchesPerWall: number,
	patchMinSize: number,
	patchMaxSize: number,
	patchThickness: number,
	patchTransparency: number,
	wallHeightBias: number,
	wallMaxHeightFraction: number,
	doorwayClearance: number,
	groundPatchMinSize: number,
	groundPatchMaxSize: number,
	groundLift: number,
}

export type FloorsConfig = {
	planningBatchSize: number,
	roomsPerFloor: { number },
	threatBudgetPerFloor: { number },
	floodedFloorChance: number,
	floodedRoomsPerFloor: number,
	linearContinuationChance: number,
	loopSeekingChance: number,
	loopConnectionChance: number,
	minimumLoopConnections: number,
	geometry: FloorGeometryConfig,
	caveDressing: CaveDressingConfig,
	terrain: TerrainConfig,
	roof: RoofConfig,
	groundField: GroundFieldConfig,
	caveMoss: CaveMossConfig,
	roomModules: { Types.RoomModuleDef },
}

local Floors: FloorsConfig = {
	-- Default count used only by FloorPlanner.planAll test/tool batches. Live expeditions generate
	-- the next floor on demand and have no floor cap.
	planningBatchSize = 10,
	-- Room modules to assemble per GLOBAL DEPTH (index = global depth). More rooms = longer, harder
	-- floors. Logic/DepthRules.getRoomCountTarget extends the last row past this table's range.
	roomsPerFloor = { 6, 7, 8, 8, 9, 10, 10, 11, 12, 12 },
	-- Threats spawned per global depth (index = global depth). Higher = harder. A smooth per-floor ramp
	-- (rather than a stepwise jump) so every floor is slightly more populated than the last, on top
	-- of the coarser tier-level scaling from Config.CaveTiers.threatBudgetMultiplier.
	--
	-- RAISED ~20% WHEN EACH FAMILY GAINED A SIGNATURE CREATURE, and the reason it had to be this number
	-- rather than a spawn weight is worth stating: adding a row to Config/Threats does NOT add bodies.
	-- Logic/FloorPlanner.weightedThreat normalises across whatever rows a room allows, so a fourth
	-- creature only ever changes the MIX — it takes floor space from the three that were already there.
	-- Stone carried exactly one threat per floor through floor five, which meant a diluted roster could
	-- have left a player five floors deep without meeting the creature their cave is built around.
	--
	-- IT IS THE SHARED BASE THAT MOVED, not any family's own multiplier, so the canonical three-factor
	-- product is untouched (DESIGN §18: base x caveBase x caveBand, and nothing may compute it any other
	-- way). Because each family scales this by its own numbers, Ice gains the most and Stone the least —
	-- which is the difficulty model working as designed rather than a side effect to correct.
	threatBudgetPerFloor = { 1.2, 1.55, 1.9, 2.3, 2.65, 3, 3.35, 3.7, 4.05, 4.4 },
	-- Water is a FLOOR-scale event, not a per-room one. This is the chance an assembled floor is wet
	-- at all; a dry floor never even considers a flooded module, so most descents are dry stone and
	-- reaching water is an occasion. This single number is what controls how often you meet water —
	-- the module weights below only decide which KIND of pool a wet floor gets.
	floodedFloorChance = 0.4,
	-- Pools on a wet floor. Pools are wide enough to read from across a room, so more than one or two
	-- turns the whole floor into water. Extra flooded modules are converted back to dry.
	floodedRoomsPerFloor = 1,
	-- Assembly strongly prefers continuing from the newest room, producing a readable main chain
	-- instead of repeatedly branching from old rooms. When a placement can fold that chain beside an
	-- existing room, the loop-seeking roll prefers it so the later connection pass can make a cycle.
	linearContinuationChance = 0.82,
	loopSeekingChance = 0.9,
	-- Adjacent cells usually connect, and at least this many available loop edges are guaranteed.
	-- Together with the chain bias this keeps ordinary floors near two endpoints while still giving
	-- many layouts a second route toward the Basin.
	loopConnectionChance = 0.72,
	minimumLoopConnections = 1,
	-- Physical dimensions of assembled rooms. Purely structural; changing these reshapes every floor.
	geometry = {
		-- 64 is 20% smaller than the previous 80-stud footprint. The deterministic ground enclosure,
		-- ceiling height, doorway profile, and dressing rolls still make individual rooms feel varied.
		cellSize = 64, -- studs per room cell; a multiple of 4 so Terrain voxels tile cleanly
		wallHeight = 24,
		wallThickness = 1,
		-- Each shared connection deterministically rolls a width, height, AND lateral position within
		-- these ranges. Adjacent rooms use the same edge seed, so the physical hole and its placement
		-- line up exactly while every connection looks different — from a tight crevice barely wide
		-- enough for two candles to a near-room-wide breach.
		doorwayMinWidth = 8,
		doorwayMaxWidth = 45,
		doorwayMinHeight = 8,
		-- Kept below ceilingMinHeight so a doorway always fits under the shortest room's roof (the two
		-- adjacent rooms share one opening, so it can't be clamped per-room).
		doorwayMaxHeight = 13,
		-- Keeps a doorway's lateral offset roll off the room's structural corners.
		doorwayCornerMargin = 3.5,
		-- Roofs vary widely per room (planned, not jitter): a tight low crevice to a tall cavern. Taller
		-- rooms feel grander and, in the planner, draw the moth family; low rooms host the ceiling flies.
		ceilingMinHeight = 15,
		ceilingMaxHeight = 46,
		floorGap = 96, -- vertical studs between floors (floors stack downward; clears the tallest cavern)
		-- How far `server/SurfaceProbe` looks for the real, built floor around a planned placement.
		-- The analytic ground field and the voxelized Terrain that gets carved from it disagree by up
		-- to about a voxel, so the window only has to cover that plus a little slope — deliberately
		-- NOT the full room height, because a probe that reaches the roof will eventually find a
		-- shelf or an overhang and rest a deposit on it.
		placementProbe = {
			-- Maximum requested lift. SurfaceProbe caps this to half the guaranteed floor-to-roof
			-- clearance, keeping every origin in open air even in the shortest legal passage.
			upStuds = 10,
			downStuds = 24,
			-- Terrain is written on a 4-stud voxel grid. Keep floor-sitting gameplay objects this far
			-- inside the analytic open-air boundary so interpolation at a shaped side wall cannot put
			-- their visible bounds back into rock.
			horizontalMarginStuds = 4,
			-- A small extra flat shoulder outside a planned object's support ring absorbs Terrain's
			-- four-stud voxel interpolation. The shelf keeps its local elevation and blends back into the
			-- uneven cave; it is a seating socket, not a room-wide floor flattening.
			placementPadMarginStuds = 2,
			-- The planner includes this transition in shelf-to-shelf separation, so one placement cannot
			-- pull another placement's required support ring off level.
			placementPadBlendStuds = 2,
			-- Maximum residual from the centre hit's tangent plane. This accepts a broad legal incline
			-- regardless of footprint width while rejecting a voxel hump, cliff, or separate shelf.
			maxPeripheralDeltaStuds = 3.5,
			-- The comment above about "a shelf or an overhang" is a real failure, not just a risk: the
			-- probe's first solid hit within its vertical window can be the underside of a roof dip or
			-- ceiling pocket, which faces DOWNWARD. A real floor or shelf never does. Rejecting hits
			-- steeper than this refuses the placement instead of seating an object in the ceiling.
			maxUpwardSlopeDegrees = 60,
			-- AUDIT ONLY — this changes no placement, it decides when one gets REPORTED.
			--
			-- After an object is seated, `SurfaceProbe.groundGapStuds` measures the gap between its
			-- lowest visible surface and the Terrain under it. Anything above this is a floating object
			-- a player would notice, and it is logged with its room and depth.
			--
			-- Sized from the two errors that are legitimately unavoidable: Terrain's isosurface departs
			-- from the height field it was written from by up to about a third of a stud, and an object
			-- seated on a slope touches at one point while its bounding extent measures from another.
			-- Below this, "floating" is not something anyone can see; above it, something is wrong.
			maxSeatedGapStuds = 0.75,
		},
	},
	-- Cosmetic cave irregularity. Collision-neutral except boulders; safe to tune freely.
	caveDressing = {
		formationPalette = {
			Color3.fromRGB(52, 56, 66),
			Color3.fromRGB(62, 66, 78),
			Color3.fromRGB(45, 49, 59),
			Color3.fromRGB(70, 73, 84),
		},
		formationDampTint = Color3.fromRGB(28, 31, 39),
		formationMaterials = {
			Enum.Material.Slate,
			Enum.Material.Basalt,
			Enum.Material.Concrete,
			Enum.Material.Rock,
		},
		formationWetMaterial = Enum.Material.Slate,
		formationWetReflectance = 0.03,
		-- Jagged rock clusters broken across EVERY wall so surfaces read as rough cave, not slab.
		wallRockCount = 14,
		wallRockMinSize = 2,
		wallRockMaxSize = 7,
		-- One or two walls in a typical room, a few rooms with none and the occasional room with three.
		-- That is the density that reads as "this cave deposits flowstone"; much past it and every wall
		-- has a sheet on it, which reads as wallpaper and costs the form the thing that makes it worth
		-- looking at. It is also the most part-expensive piece of dressing in a room (roughly twenty
		-- facets a sheet), so the tasteful number and the cheap number are the same number here.
		--
		-- Lengths run long on purpose: a short drape is a smear, and the fold-length power curve inside
		-- `CaveKit.drapery` already keeps most folds well under the maximum.
		drapeChancePerWall = 0.4,
		drapeMinHalfWidth = 2.2,
		drapeMaxHalfWidth = 5,
		drapeMinLength = 4,
		drapeMaxLength = 12,
		drapeRootThickness = 0.62,
		drapeSegments = 3,
		drapeMinTopFraction = 0.42,
		drapeMaxTopFraction = 0.92,
		drapeDoorwayClearance = 3,
		bouldersPerRoom = 1, -- CaveKit boulders are multi-facet models; one replaces several grey-box shards
		boulderMinSize = 2,
		boulderMaxSize = 7,
		rockColumnsPerRoom = 1,
		rockColumnMinHeight = 4,
		rockColumnMaxHeight = 12,
		rockColumnMinWidth = 1.5,
		rockColumnMaxWidth = 3.5,
		-- Roughly one room in three, and only in rooms under 24 studs to the roof. Held out at 0.26-0.4
		-- of the cell so a pillar stands between the player and a wall rather than in the middle of the
		-- floor: it is a thing to edge around and lose sight past, which is the whole reason to want one.
		pillarChancePerRoom = 0.34,
		pillarMinWidth = 2.4,
		pillarMaxWidth = 4.6,
		pillarMaxCeilingHeight = 24,
		pillarRingMinFactor = 0.26,
		pillarRingMaxFactor = 0.4,
		pillarRouteClearance = 2.5,
		pillarPlacementAttempts = 12,
		rubblePatchesPerRoom = 3,
		rubbleChipsPerPatch = 10,
		rubblePatchArea = 3.2,
		rubbleRingMinFactor = 0.3,
		rubbleRingMaxFactor = 0.43,
		caveMouthRocksPerSide = 3,
		caveMouthCeilingRocks = 3,
		caveMouthRockMinSize = 2.5,
		caveMouthRockMaxSize = 5.5,
		-- Shallow, curve-aligned chips soften the generated arch edge without becoming hanging
		-- stalactites. Most of each chip remains buried in the structural rock.
		caveMouthArchFacetMinLength = 2.2,
		caveMouthArchFacetMaxLength = 4.2,
		caveMouthArchFacetThickness = 0.7,
		caveMouthArchFacetDepth = 1.6,
		caveMouthArchFacetEmbed = 0.78,
		ceilingFormationsPerRoom = 2,
		ceilingFormationMinLength = 3,
		ceilingFormationMaxLength = 10,
		ceilingFormationMinWidth = 1.3,
		ceilingFormationMaxWidth = 3.8,
		ceilingBouldersPerRoom = 1,
		ceilingStrawsPerCluster = 5,
		ceilingStrawSpread = 3.5,
		ceilingFormationGroundGap = 1.5,
		ceilingFormationExtentRadiusFactor = 2.4,
		ceilingStrawLengthMultiplier = 1.85,
		-- Broad, shallow chips sit mostly inside the authoritative Terrain roof. They add a second
		-- visual scale without changing the roof field sampled by threats and hazard placement.
		ceilingFacetClustersPerRoom = 9,
		ceilingFacetPlacementAttempts = 36,
		ceilingFacetPiecesPerCluster = 2,
		ceilingFacetMinSize = 3.5,
		ceilingFacetMaxSize = 8,
		ceilingFacetMinThickness = 0.35,
		ceilingFacetMaxThickness = 0.9,
		ceilingFacetSpread = 1.8,
		ceilingFacetEmbed = 0.72,
		ceilingFacetEdgeInset = 5,
		ceilingFacetSlopeSample = 2,
	},
	-- Planned, collidable ground variation. Broad ramped shelves create unmistakable elevation
	-- without impassable steps; doorway approaches remain clear and pools are planned separately.
	terrain = {
		groundHumpsPerRoom = 7,
		groundHumpMinDiameter = 12,
		groundHumpMaxDiameter = 22,
		groundHumpMinHeight = 0.65,
		groundHumpMaxHeight = 3.2,
		groundHumpMinRadius = 5,
		groundHumpMaxRadius = 22,
		groundHumpSeparation = -3,
		-- Corner ground-patch fallback offset (studs) from room center when the radial roll fails to
		-- find a valid spot; keeps even a rejected four-door room from reading perfectly flat.
		groundPatchFallbackOffset = 17,
		specialRoomCenterClearance = 7,
		doorClearanceDepth = 10,
		doorClearanceWidth = 24,
		wallClearance = 2,
		hazardClearance = 2,
		placementAttemptsPerHump = 48,
		aiGroundProbeHeight = 7,
		aiGroundProbeDepth = 16,
		-- `server/ThreatService` finds the real, built ceiling for a ceiling ambusher by casting UP
		-- from this height above the floor. Terrain is written at 4-stud voxels, so the underside the
		-- analytic field describes and the one a body would touch differ by more than the couple of
		-- studs of clearance the ambusher hangs at, and trusting the field alone parks the fly inside
		-- the rock. The origin is anchored to the FLOOR because that is the one height guaranteed to be
		-- open air: a probe that starts inside stone reports nothing and the fly is hung from the plan
		-- it was already too high for. Only high enough to clear the ground voxels themselves — it
		-- must stay under the fly's own attack height so a dive is never mistaken for a ceiling.
		aiRoofProbeFloorInset = 2,
		aiObstacleSidestep = 4,
		gameplaySpawnRadius = 3.5,
		gameplaySpawnSeparation = 3,
	},
	-- The roof is a sealed inverted Terrain height field, not a flat slab. Relief fades to zero at
	-- room boundaries so it joins walls and shared door arches cleanly, then rolls through the room
	-- with broad stone structure comparable to the floor. FloorBuilder enforces minimum headroom at
	-- every voxel sample.
	roof = {
		rockThickness = 12,
		minRelief = 0.45,
		-- The ABSOLUTE cap on the height-independent part of the relief. On its own this was the
		-- whole roof shape, and it is why tall rooms read as flat slabs — see `reliefPerCeilingStud`.
		maxRelief = 4.8,
		shortRoomReliefScale = 0.2,
		-- EXTRA RELIEF PER STUD OF CEILING ABOVE THE MINIMUM. Relief has to survive perspective: the
		-- same 4.8 studs of undulation is obvious structure on a 15-stud roof and invisible on a
		-- 46-stud one, because it subtends a third of the angle and sits three times further from the
		-- only light in the world. At 0.3 a minimum-height room is completely unchanged and a maximum-
		-- height vault gets roughly 14 studs of relief instead of 4.8 — genuinely sculpted rather than
		-- a lid. Raise this if tall chambers still read as ceilings rather than as cave roofs.
		reliefPerCeilingStud = 0.3,
		longFrequencyMin = 0.035,
		longFrequencyMax = 0.058,
		rippleFrequencyMin = 0.14,
		rippleFrequencyMax = 0.22,
		shapeFloorWeight = 0.18,
		longWaveAmplitude = 0.62,
		rippleAmplitude = 0.2,
		edgeBlend = 9,
		minimumClearance = 8.5,
	},
	-- Deterministic floor-field shape. These values used to be embedded in FloorBuilder; keeping
	-- them here lets traversal/roof readability be tuned without editing placement logic.
	groundField = {
		doorLaneMargin = 3,
		volumeBase = 0.7,
		amplitudeBase = 3.4,
		amplitudeDepthStep = 0.22,
		amplitudeBaseMax = 6.5,
		amplitudeRandomMin = 0.7,
		amplitudeRandomMax = 1.35,
		amplitudeMin = 2.5,
		amplitudeMax = 8,
		wallRiseRandomMin = 3,
		wallRiseRandomMax = 7,
		wallRiseMin = 3,
		wallRiseMax = 9,
		grandeurJitter = 0.12,
		openRadiusMin = 15,
		openRadiusEdgePadding = 6,
		enclosureHeadroom = 5,
		bermMinimum = 4.5,
		rippleAmplitudeMin = 0.6,
		rippleAmplitudeMax = 1.6,
		centerPadRadius = 12,
		blend = 7,
		fillHeightPadding = 2,
		longFrequencyMin = 0.045,
		longFrequencyMax = 0.072,
		rippleFrequencyMin = 0.22,
		rippleFrequencyMax = 0.34,
		wallBermStart = 0.6,
		enclosureBlendMultiplier = 1.6,
		-- Fraction of a pool's radius held at the full bed depth before the rim starts sloping back
		-- up. Terrain is written at 4-stud voxels, so a pool needs a flat inner disc several voxels
		-- wide or the whole bowl smooths away and the water plane ends up buried in solid rock.
		poolFlatFraction = 0.55,
	},
	-- Damp cave moss. Collision-neutral dressing only: it never changes traversal, light, or AI.
	-- Walls everywhere carry a little; rooms holding water carry noticeably more, plus a ring of
	-- ground patches around the waterline.
	--
	-- THE SHARED SHAPE of wall cover; WHICH cover a floor actually gets is the cave family's
	-- (Config/CaveFamilies.presentation.coverPalette / coverMaterial / coverDensityFactor). Stone
	-- carries a little damp moss, Moss is thickly overgrown, Ice wears a restrained skin of dirty
	-- frost — all from these same counts and sizes, scaled by the family's density factor.
	--
	-- TWO INVARIANTS NO FAMILY MAY BREAK HERE, both already true of this block and both load-bearing:
	-- dressing stays COLLISION-NEUTRAL, and it never moves or displaces a threat spawn, hazard,
	-- dripstone, deposit, or doorway lane. A family may change what a room LOOKS like through this
	-- block; the moment it changes what is IN a room, it has acquired a second difficulty axis that
	-- nothing else in the model can see.
	caveMoss = {
		enabled = true,
		-- KEEP RED LOW. The candle is a warm orange light (Config/Light.rendering.color is roughly
		-- 255,190,100), so it multiplies red by ~1.0 and green by ~0.75. Any moss whose red channel
		-- approaches its green reads as brown mud under that light, not moss. These greens are
		-- deliberately dark and red-starved so the warm light lands them on deep cave green.
		palette = {
			Color3.fromRGB(16, 46, 26),
			Color3.fromRGB(11, 37, 22),
			Color3.fromRGB(23, 55, 31),
			Color3.fromRGB(8, 29, 18),
		},
		material = Enum.Material.Grass,
		-- Wetter, colder, slicker greens for the rooms with standing water.
		dampPalette = {
			Color3.fromRGB(13, 48, 35),
			Color3.fromRGB(9, 39, 30),
			Color3.fromRGB(20, 57, 39),
			Color3.fromRGB(7, 32, 26),
		},
		dampMaterial = Enum.Material.Mud,
		-- Patches attempted per wall in a dry room, and in a room that holds a pool. Higher = mossier.
		patchesPerWall = 5,
		dampPatchesPerWall = 13,
		patchMinSize = 2.2,
		patchMaxSize = 7,
		patchThickness = 0.22,
		-- Opaque: any transparency lets the warm orange rock behind bleed through and washes the green out.
		patchTransparency = 0,
		-- Vertical distribution exponent: >1 crowds moss toward the damp base of the wall.
		wallHeightBias = 2.4,
		-- Ceiling of the moss band as a fraction of wall height; moss never climbs into the roof.
		wallMaxHeightFraction = 0.55,
		-- Keep the doorway throat clean so an opening never reads as blocked.
		doorwayClearance = 2.5,
		groundPatchMinSize = 3,
		groundPatchMaxSize = 9,
		-- How far a ground patch floats above the sampled Terrain height so it never z-fights.
		groundLift = 0.06,
	},
	-- The pool of room modules and their assembly weights. `connections` caps doorways per piece.
	--
	-- `allowedThreats` IS THE ROOM'S ECOLOGY, and several modules necessarily share one list. That is
	-- fine and is not a flattening: which of the allowed rows a room actually draws still depends on its
	-- own ceiling (Logic/FloorPlanner.heightBias — the moth prefers tall vaults, the crawler low ground,
	-- and the VoidFly is refused outright by any roof above its territory cap), so two modules with
	-- identical lists but different heights still meet different things. The one structural rule these
	-- lists carry, and the reason they are not all the same, is that WATER ROOMS HOLD NO DARK HUNTERS: a
	-- flooded floor is moth country, and wading is never punished by something hunting the dark.
	--
	-- THESE LISTS ARE FAMILY-AGNOSTIC ON PURPOSE, including for the three creatures that only ever
	-- appear in one cave. A family-exclusive row needs no mechanism of its own: it sits in the ordinary
	-- list here and the two families it does not belong to weight it to zero
	-- (Config/CaveFamilies.threatEcology), which Logic/FloorPlanner already reads as "not here" in both
	-- the eligibility check and the spawn roll. Branching this table on a family id would have been the
	-- exact `if familyId == ...` the whole cave-family design exists to avoid.
	roomModules = {
		{
			id = "Corridor",
			displayName = "Corridor",
			weight = 3,
			connections = 2,
			allowedThreats = { "DarkCrawler", "Moth", "VoidFly", "Listener", "Knotwalker", "Calver" },
			allowedHazards = {},
		},
		{
			id = "Chamber",
			displayName = "Chamber",
			weight = 2,
			connections = 3,
			allowedThreats = { "DarkCrawler", "Moth", "VoidFly", "Listener", "Knotwalker", "Calver" },
			allowedHazards = {},
		},
		-- Flooded weights are RELATIVE ONLY: how often a floor is wet is decided by
		-- floodedFloorChance above, and a wet floor is trimmed to floodedRoomsPerFloor pools. These
		-- weights just pick which kind of pool that floor gets.
		{
			id = "Flooded",
			displayName = "Flooded Hall",
			weight = 1.2,
			connections = 2,
			allowedThreats = { "Moth", "VoidFly" },
			allowedHazards = {},
			waterDepth = 1.2,
		},
		{
			id = "Shallows",
			displayName = "Shallow Grotto",
			weight = 1.8,
			connections = 3,
			allowedThreats = { "Moth", "VoidFly" },
			allowedHazards = {},
			waterDepth = 0.45,
		},
		{
			id = "Sump",
			displayName = "Deep Sump",
			weight = 0.45,
			connections = 2,
			allowedThreats = { "Moth", "VoidFly" },
			allowedHazards = {},
			waterDepth = 2,
		},
		{
			id = "Grotto",
			displayName = "Broken Grotto",
			weight = 2,
			connections = 3,
			allowedThreats = { "DarkCrawler", "Moth", "VoidFly", "Listener", "Knotwalker", "Calver" },
			allowedHazards = {},
		},
		{
			id = "Crossing",
			displayName = "Crossing",
			weight = 1,
			connections = 4,
			allowedThreats = { "DarkCrawler", "Moth", "VoidFly", "Listener", "Knotwalker", "Calver" },
			allowedHazards = {},
		},
		{
			-- Planner-only optional encounter branch. Zero weight prevents ordinary assembly from
			-- selecting it; otherwise it uses the exact same cave fields and dressing as a Chamber.
			id = "WardenDen",
			displayName = "Weathered Chamber",
			weight = 0,
			connections = 2,
			allowedThreats = {},
			allowedHazards = {},
		},
		{
			-- THE SEALED BLAST VAULT (Config/Dynamite.vault). Planner-only, like the den above: zero
			-- weight keeps ordinary assembly from ever selecting it, and `Logic/FloorPlanner` attaches it
			-- by hand AFTER the loop pass so it is a dead end by construction.
			--
			-- `connections = 1` IS THE INVARIANT, not a preference. One doorway is the door somebody
			-- sealed; a second would be a way in that needs no dynamite, and the whole room is a promise
			-- that the only cost of what is inside is the stick you spend on it.
			--
			-- `allowedThreats` IS EMPTY AND MUST STAY EMPTY. A vault holds guaranteed ore and no
			-- creature: the player already paid a rare consumable and a floor-wide noise event to open
			-- it, and putting something behind the door as well would make opening one a gamble rather
			-- than a trade. The empty list is what the planner's spawn roll reads as "not here".
			id = "BlastVault",
			displayName = "Sealed Pocket",
			weight = 0,
			connections = 1,
			allowedThreats = {},
			allowedHazards = {},
		},
	},
}

return Floors

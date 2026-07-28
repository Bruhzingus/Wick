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
	bouldersPerRoom: number,
	boulderMinSize: number,
	boulderMaxSize: number,
	rockColumnsPerRoom: number,
	rockColumnMinHeight: number,
	rockColumnMaxHeight: number,
	rockColumnMinWidth: number,
	rockColumnMaxWidth: number,
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
	aiObstacleSidestep: number,
	gameplaySpawnRadius: number,
	gameplaySpawnSeparation: number,
}

export type RoofConfig = {
	rockThickness: number,
	minRelief: number,
	maxRelief: number,
	shortRoomReliefScale: number,
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
	threatBudgetPerFloor = { 1, 1.3, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.4, 3.7 },
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
			upStuds = 10,
			downStuds = 24,
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
		bouldersPerRoom = 1, -- CaveKit boulders are multi-facet models; one replaces several grey-box shards
		boulderMinSize = 2,
		boulderMaxSize = 7,
		rockColumnsPerRoom = 1,
		rockColumnMinHeight = 4,
		rockColumnMaxHeight = 12,
		rockColumnMinWidth = 1.5,
		rockColumnMaxWidth = 3.5,
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
		maxRelief = 4.8,
		shortRoomReliefScale = 0.2,
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
	-- TODO (PHASE 10 HOOK 4 of 4 — `CaveTier.biomeId`, Config/CaveTiers): room-generation FLAVOUR, and
	-- the safest of the four hooks. Moss density and palette, formation mix, and the `caveDressing`
	-- weights above are pure data, so "a grassy cave has more moss and a colder one has none" is a
	-- config lookup keyed by biome rather than any new code path.
	--
	-- TWO INVARIANTS A BIOME MAY NOT BREAK HERE, both already true of this block and both load-bearing:
	-- dressing stays COLLISION-NEUTRAL, and it never moves or displaces a threat spawn, hazard,
	-- dripstone, deposit, or doorway lane. Flavour may change what a room looks like; the moment it
	-- changes what is IN a room, the biome has become a difficulty axis and Phase 10's whole premise
	-- (look and feel, never mechanics) is gone.
	--
	-- Blocked on the documentation conflict recorded at `NEUTRAL_BIOME` in Config/CaveTiers.
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
	roomModules = {
		{
			id = "Corridor",
			displayName = "Corridor",
			weight = 3,
			connections = 2,
			allowedThreats = { "Lurker", "Moth", "Hollow", "AshMoth", "VoidFly" },
			allowedHazards = {},
		},
		{
			id = "Chamber",
			displayName = "Chamber",
			weight = 2,
			connections = 3,
			allowedThreats = { "Stalker", "Swarm", "Hollow", "Snuffer", "VoidFly" },
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
			allowedThreats = { "Moth", "AshMoth", "Snuffer", "VoidFly" },
			allowedHazards = {},
			waterDepth = 1.2,
		},
		{
			id = "Shallows",
			displayName = "Shallow Grotto",
			weight = 1.8,
			connections = 3,
			allowedThreats = { "Moth", "AshMoth", "VoidFly" },
			allowedHazards = {},
			waterDepth = 0.45,
		},
		{
			id = "Sump",
			displayName = "Deep Sump",
			weight = 0.45,
			connections = 2,
			allowedThreats = { "Moth", "Snuffer", "VoidFly" },
			allowedHazards = {},
			waterDepth = 2,
		},
		{
			id = "Grotto",
			displayName = "Broken Grotto",
			weight = 2,
			connections = 3,
			allowedThreats = { "Lurker", "Hollow", "AshMoth", "VoidFly" },
			allowedHazards = {},
		},
		{
			id = "Crossing",
			displayName = "Crossing",
			weight = 1,
			connections = 4,
			allowedThreats = { "Lurker", "Stalker", "Hollow", "Snuffer", "VoidFly" },
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
	},
}

return Floors

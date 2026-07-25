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
}

export type FloorsConfig = {
	maxFloors: number,
	roomsPerFloor: { number },
	threatBudgetPerFloor: { number },
	hazardChancePerRoom: number,
	loopConnectionChance: number,
	geometry: FloorGeometryConfig,
	caveDressing: CaveDressingConfig,
	terrain: TerrainConfig,
	roof: RoofConfig,
	groundField: GroundFieldConfig,
	roomModules: { Types.RoomModuleDef },
}

local Floors: FloorsConfig = {
	-- How many floors a full descent can reach. More = longer runs and deeper multipliers available.
	maxFloors = 10,
	-- Room modules to assemble per floor (index = floor number). More rooms = longer, harder floors.
	roomsPerFloor = { 6, 7, 8, 8, 9, 10, 10, 11, 12, 12 },
	-- Threats spawned per floor (index = floor number). Higher = harder.
	threatBudgetPerFloor = { 1, 1, 1, 2, 2, 2, 2, 3, 3, 3 },
	-- Chance (0..1) that a room rolls one hazard from its allowedHazards. Modules with waterDepth
	-- always receive one localized pool regardless. Higher = harder.
	hazardChancePerRoom = 0.4,
	-- Adjacent cells may gain a second connection, producing alternate routes and less linear caves.
	loopConnectionChance = 0.35,
	-- Physical dimensions of assembled rooms. Purely structural; changing these reshapes every floor.
	geometry = {
		cellSize = 80, -- studs per room cell, square (roomy; also a multiple of 4 so Terrain voxels tile cleanly)
		wallHeight = 24,
		wallThickness = 1,
		-- Each shared connection deterministically rolls a width, height, AND lateral position within
		-- these ranges. Adjacent rooms use the same edge seed, so the physical hole and its placement
		-- line up exactly while every connection looks different — from a tight crevice barely wide
		-- enough for two candles to a near-room-wide breach.
		doorwayMinWidth = 8,
		doorwayMaxWidth = 56,
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
	},
	-- The pool of room modules and their assembly weights. `connections` caps doorways per piece.
	roomModules = {
		{
			id = "Corridor",
			displayName = "Corridor",
			weight = 3,
			connections = 2,
			allowedThreats = { "Lurker", "Moth", "Hollow", "AshMoth", "VoidFly" },
			allowedHazards = { "Draft" },
		},
		{
			id = "Chamber",
			displayName = "Chamber",
			weight = 2,
			connections = 3,
			allowedThreats = { "Stalker", "Swarm", "Hollow", "Snuffer", "VoidFly" },
			allowedHazards = { "Draft" },
		},
		{
			id = "Flooded",
			displayName = "Flooded Hall",
			weight = 1.2,
			connections = 2,
			allowedThreats = { "Moth", "AshMoth", "Snuffer", "VoidFly" },
			allowedHazards = { "Draft" },
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
			allowedHazards = { "Draft" },
		},
		{
			id = "Crossing",
			displayName = "Crossing",
			weight = 1,
			connections = 4,
			allowedThreats = { "Lurker", "Stalker", "Hollow", "Snuffer", "VoidFly" },
			allowedHazards = { "Draft" },
		},
	},
}

return Floors

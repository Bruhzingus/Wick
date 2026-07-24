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
	floorGap: number,
}

export type CaveDressingConfig = {
	ceilingJitter: number,
	wallReliefStrips: number,
	wallReliefDepth: number,
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
	caveMouthMinClearWidth: number,
	caveMouthMinClearHeight: number,
	ceilingFormationsPerRoom: number,
	ceilingFormationMinLength: number,
	ceilingFormationMaxLength: number,
	ceilingFormationMinWidth: number,
	ceilingFormationMaxWidth: number,
	ceilingBouldersPerRoom: number,
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
	groundPlateauFraction: number,
	groundRampThickness: number,
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

export type FloorsConfig = {
	maxFloors: number,
	roomsPerFloor: { number },
	threatBudgetPerFloor: { number },
	hazardChancePerRoom: number,
	loopConnectionChance: number,
	geometry: FloorGeometryConfig,
	caveDressing: CaveDressingConfig,
	terrain: TerrainConfig,
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
		cellSize = 52, -- studs per room cell, square
		wallHeight = 20,
		wallThickness = 1,
		-- Each shared connection deterministically rolls within these ranges. Adjacent rooms use
		-- the same edge seed, so the physical holes line up while their silhouettes vary.
		doorwayMinWidth = 11,
		doorwayMaxWidth = 22,
		doorwayMinHeight = 8.5,
		doorwayMaxHeight = 16,
		floorGap = 80, -- vertical studs between floors (floors stack downward)
	},
	-- Cosmetic cave irregularity. Collision-neutral except boulders; safe to tune freely.
	caveDressing = {
		ceilingJitter = 8, -- +/- studs of per-room ceiling height variance
		wallReliefStrips = 5, -- rock-relief strips per doorless wall (0 = flat grey-box walls)
		wallReliefDepth = 1.8, -- max studs the relief protrudes into the room
		bouldersPerRoom = 2, -- sparse collidable angular rocks; terrain carries most visual variance
		boulderMinSize = 2,
		boulderMaxSize = 7,
		rockColumnsPerRoom = 2,
		rockColumnMinHeight = 4,
		rockColumnMaxHeight = 12,
		rockColumnMinWidth = 1.5,
		rockColumnMaxWidth = 3.5,
		caveMouthRocksPerSide = 3,
		caveMouthCeilingRocks = 3,
		caveMouthRockMinSize = 2.5,
		caveMouthRockMaxSize = 5.5,
		caveMouthMinClearWidth = 10,
		caveMouthMinClearHeight = 8.5,
		ceilingFormationsPerRoom = 5,
		ceilingFormationMinLength = 3,
		ceilingFormationMaxLength = 10,
		ceilingFormationMinWidth = 1.3,
		ceilingFormationMaxWidth = 3.8,
		ceilingBouldersPerRoom = 2,
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
		groundPlateauFraction = 0.26,
		groundRampThickness = 0.55,
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

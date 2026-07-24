--!strict
-- Floor assembly tuning (DESIGN §18). Floors are assembled procedurally from weighted room modules.
-- Logic/FloorPlanner consumes this; server FloorBuilder only reads the resulting plan.

local Types = require(script.Parent.Parent.Types)

export type FloorGeometryConfig = {
	cellSize: number,
	wallHeight: number,
	wallThickness: number,
	doorwayWidth: number,
	doorwayHeight: number,
	floorGap: number,
}

export type CaveDressingConfig = {
	ceilingJitter: number,
	wallReliefStrips: number,
	wallReliefDepth: number,
	bouldersPerRoom: number,
	boulderMinSize: number,
	boulderMaxSize: number,
}

export type FloorsConfig = {
	maxFloors: number,
	roomsPerFloor: { number },
	threatBudgetPerFloor: { number },
	hazardChancePerRoom: number,
	geometry: FloorGeometryConfig,
	caveDressing: CaveDressingConfig,
	roomModules: { Types.RoomModuleDef },
}

local Floors: FloorsConfig = {
	-- How many floors a full descent can reach. More = longer runs and deeper multipliers available.
	maxFloors = 8,
	-- Room modules to assemble per floor (index = floor number). More rooms = longer, harder floors.
	roomsPerFloor = { 4, 5, 5, 6, 6, 7, 7, 8 },
	-- Threats spawned per floor (index = floor number). Higher = harder.
	threatBudgetPerFloor = { 1, 2, 2, 3, 3, 4, 4, 5 },
	-- Chance (0..1) that a room rolls one hazard from its allowedHazards. Rooms with waterDepth
	-- always flood regardless. Higher = harder.
	hazardChancePerRoom = 0.5,
	-- Physical dimensions of assembled rooms. Purely structural; changing these reshapes every floor.
	geometry = {
		cellSize = 44, -- studs per room cell, square
		wallHeight = 14,
		wallThickness = 1,
		doorwayWidth = 10,
		doorwayHeight = 10,
		floorGap = 80, -- vertical studs between floors (floors stack downward)
	},
	-- Cosmetic cave irregularity. Collision-neutral except boulders; safe to tune freely.
	caveDressing = {
		ceilingJitter = 3, -- +/- studs of per-room ceiling height variance
		wallReliefStrips = 3, -- rock-relief strips per doorless wall (0 = flat grey-box walls)
		wallReliefDepth = 0.9, -- max studs the relief protrudes into the room
		bouldersPerRoom = 2, -- collidable rocks scattered per ordinary room
		boulderMinSize = 2,
		boulderMaxSize = 5,
	},
	-- The pool of room modules and their assembly weights. `connections` caps doorways per piece.
	roomModules = {
		{
			id = "Corridor",
			displayName = "Corridor",
			weight = 3,
			connections = 2,
			allowedThreats = { "Lurker", "Moth" },
			allowedHazards = { "Draft" },
		},
		{
			id = "Chamber",
			displayName = "Chamber",
			weight = 2,
			connections = 3,
			allowedThreats = { "Stalker", "Swarm" },
			allowedHazards = { "Draft" },
		},
		{
			id = "Flooded",
			displayName = "Flooded Hall",
			weight = 1,
			connections = 2,
			allowedThreats = { "Moth" },
			allowedHazards = { "Draft" },
			-- 2.2 against body heights 0.8..4: wadeable above ~44% wax, lethal below (TUNING.md).
			waterDepth = 2.2,
		},
		{
			id = "Crossing",
			displayName = "Crossing",
			weight = 1,
			connections = 4,
			allowedThreats = { "Lurker", "Stalker" },
			allowedHazards = { "Draft" },
		},
	},
}

return Floors

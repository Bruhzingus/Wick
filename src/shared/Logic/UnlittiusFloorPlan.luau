--!strict
-- UNLITTIUS' FLOOR, authored rather than generated — the second hand-built floor in the game
-- (DESIGN §9b), and deliberately not the same SHAPE as the Grub Queen's.
--
-- WHY IT IS HAND-BUILT, same answer as hers (`Logic/BossFloorPlan`): the encounter has a specific
-- shape and that shape IS the fight.
--
-- WHY IT IS A HORSESHOE AND HERS IS A PLUS. This is the difference that matters, and the first pass of
-- this file got it wrong by making him a plus with different contents — two bosses whose floors are
-- the same skeleton are two bosses on the same floor.
--
--   HER FLOOR IS A HUB. Five rooms around a centre, every arm a dead end, and every journey crosses
--   her chamber. It is a floor you keep RE-ENTERING: out to the wax, back through her, out to the
--   dynamite, back through her.
--
--   HIS FLOOR IS A PROCESSION. You come in at one corner and leave at the other, and the shrine is
--   the turn at the top of the arc rather than a room in the middle of a wheel:
--
--                 [ W VIGIL ] — [ SHRINE ] — [ E VIGIL ]
--                      |                          |
--                  [ ENTRY ]                 [ THE WAY DOWN ]
--
--   You enter at the bottom-left, climb the west vigil into his chamber, and the way down is through
--   the east vigil on the far side. There is one route and it runs THROUGH him — but it runs through
--   once, in one direction, which is what makes his floor read as a place you are passing into rather
--   than a hub you keep coming back out of. The eight candles are what turns that single crossing into
--   a long stay.
--
-- WHAT ELSE IS DIFFERENT, AND WHY EACH DIFFERENCE EXISTS:
--
--   * NO DYNAMITE ANYWHERE. Her floor is a resource race for sticks because sticks are the only thing
--     that can kill her. Nothing can hurt him, so a dynamite wing would be a room full of an answer to
--     a question this fight does not ask. What the party spends here is WAX — their own light, which
--     is also what they light his shrine with — and that is the whole economy.
--   * WAX IN BOTH VIGILS. Her floor separates surviving from winning; his merges them, because the
--     candle in your hand is both. Both vigils carry it, so the lap can be run in either direction and
--     neither is the safe one.
--   * THE WAY DOWN IS VISIBLE FROM THE SHRINE, through the east doorway, for the whole fight —
--     reachable on foot and refused until he is banished
--     (`Config/Unlittius.encounter.requiresBanishToDescend`, checked in RunOrchestrator's descent
--     guard). Geometry expresses the idea; the rule enforces it.
--   * NO AUTHORED DRIPSTONE IN THE CHAMBER. Her floor is loaded with it. His must not be: he pulls the
--     ceiling down himself as a telegraphed attack with floor markers, and a chamber that also dropped
--     rock on its own would teach the player to distrust the telegraph. The vigils keep theirs.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local UnlittiusConfig = require(script.Parent.Parent.Config.Unlittius)
local RoomFootprint = require(script.Parent.RoomFootprint)

local UnlittiusFloorPlan = {}

-- Room order in the returned plan. Fixed and indexed by name, because the encounter service reads
-- these by meaning ("the shrine") and must never depend on ordering.
local SHRINE, ENTRY, WEST_VIGIL, EAST_VIGIL, DESCENT = 1, 2, 3, 4, 5

UnlittiusFloorPlan.CENTER_ROOM = SHRINE
UnlittiusFloorPlan.ENTRY_ROOM = ENTRY
UnlittiusFloorPlan.WEST_ROOM = WEST_VIGIL
UnlittiusFloorPlan.EAST_ROOM = EAST_VIGIL
UnlittiusFloorPlan.DESCENT_ROOM = DESCENT

-- HIS CHAMBER IS THE SECOND-TALLEST ROOM THE GAME BUILDS, and the height is load-bearing three times
-- over: he floats six studs up and stands twelve, the summon and dripstone poses put his talons
-- overhead, and the banish drags him the whole way to the ceiling to be embedded there. A low roof
-- would clip his hood, hide the animation the encounter ends on, and leave the relief where nobody can
-- see it.
UnlittiusFloorPlan.CENTER_CEILING = 40
local VIGIL_CEILING = 28
local ENTRY_CEILING = 26

-- Openings held at least this large. Slightly wider than hers: his floor is a procession and the
-- doorways are part of the walk rather than pinch points between dead ends.
UnlittiusFloorPlan.DOORWAY_MINIMUM = { minimumWidth = 28, minimumHeight = 16 }

-- Wax returns faster here than on her floor, because on his it is being spent on the objective as well
-- as on staying alive. A party that cannot top up loses to arithmetic rather than to the fight.
UnlittiusFloorPlan.WAX_RESPAWN_SECONDS = 32

-- HOW MUCH OF THE CHAMBER HIS ATTACKS MAY USE, as a radius from the shrine centre.
--
-- MEASURED AGAINST THE ROOM THE BUILDER ACTUALLY CARVES, not chosen: a room is one grid cell, so its
-- open interior reaches `RoomFootprint.maximumHalfExtent()` (30 studs) from the centre. A dripstone
-- zone is a disc of `Config.Unlittius.dripstone.impactRadius`, so the zone CENTRE has to stay far
-- enough inside that the whole disc lands on floor a player can be standing on.
function UnlittiusFloorPlan.chamberRadius(): number
	return RoomFootprint.maximumHalfExtent() - UnlittiusConfig.dripstone.impactRadius - 1.5
end

local function room(
	moduleId: string,
	gridX: number,
	gridZ: number,
	doorways: { Types.Direction },
	ceilingHeight: number
): Types.RoomPlacement
	return {
		moduleId = moduleId :: any,
		gridX = gridX,
		gridZ = gridZ,
		doorways = doorways,
		ceilingHeight = ceilingHeight,
		-- FULL RECTANGLES. Shapes make ordinary caves feel irregular; here the chamber's every square
		-- stud is the ring the fight is run on, and a lobed room would put a candle behind a pinch.
		footprint = RoomFootprint.rectangle(),
	}
end

-- The complete authored plan for one Unlittius floor.
function UnlittiusFloorPlan.plan(
	globalDepth: number,
	localFloor: number,
	familyId: string,
	worldOrigin: Vector3
): Types.FloorPlan
	local rooms: { Types.RoomPlacement } = {}
	-- N is -Z and S is +Z (Logic/DoorwayGeometry.NORMAL). The arc sits along -Z with its two legs
	-- reaching back toward +Z, so the party walks north up one leg, across the top, and south down the
	-- other. Every doorway below has its reciprocal on the room it opens into.
	rooms[SHRINE] = room("Chamber", 0, -1, { "W", "E" }, UnlittiusFloorPlan.CENTER_CEILING)
	rooms[ENTRY] = room("Chamber", -1, 0, { "N" }, ENTRY_CEILING)
	rooms[WEST_VIGIL] = room("Chamber", -1, -1, { "E", "S" }, VIGIL_CEILING)
	rooms[EAST_VIGIL] = room("Chamber", 1, -1, { "W", "S" }, VIGIL_CEILING)
	rooms[DESCENT] = room("Chamber", 1, 0, { "N" }, VIGIL_CEILING)

	local cell = FloorsConfig.geometry.cellSize
	local fixtures = UnlittiusFloorPlan.fixtures()

	-- FALLING STONE IN THE VIGILS AND NOWHERE ELSE. See the header: the chamber's ceiling is his, and a
	-- telegraph has to be the only thing that means "rock is about to land here".
	local dripstones: { Types.DripstonePlacement } = {}
	local variants = { "Spire", "Lance", "Mass", "Fork" }
	local function addDripstone(roomIndex: number, x: number, z: number)
		local index = #dripstones
		table.insert(dripstones, {
			roomIndex = roomIndex,
			localOffset = Vector3.new(x, 0, z),
			variantId = variants[(index % #variants) + 1],
			visualSeed = globalDepth * 6421 + index * 104_729,
		})
	end
	local ring = cell * 0.28
	addDripstone(WEST_VIGIL, ring * 0.5, ring * 0.4)
	addDripstone(WEST_VIGIL, -ring * 0.6, -ring * 0.3)
	addDripstone(EAST_VIGIL, -ring * 0.5, ring * 0.4)
	addDripstone(EAST_VIGIL, ring * 0.6, -ring * 0.3)
	addDripstone(DESCENT, -ring * 0.6, ring * 0.2)

	-- THE SEALED CACHE, one, in the east vigil — the room you pass through on the way OUT. The same
	-- idea her floor's caches carry and the only reason to stand still in either fight: wax under rock
	-- that has to be mined free while the room is trying to kill you. One rather than two because his
	-- fight already asks the party to stand still eight times, once per candle.
	local deposits: { Types.DepositPlacement } = {
		{
			roomIndex = EAST_VIGIL,
			localOffset = fixtures.sealedWaxOffset,
			visualSeed = globalDepth * 37 + 13,
			rowId = "Rich",
			oreTier = 2,
		},
	}

	local lootSpawns: { Types.LootSpawn } = {}
	for _, offset in fixtures.westWaxOffsets do
		table.insert(lootSpawns, {
			lootId = "LifeWax" :: any,
			roomIndex = WEST_VIGIL,
			offset = offset,
			respawnSeconds = UnlittiusFloorPlan.WAX_RESPAWN_SECONDS,
		})
	end
	for _, offset in fixtures.eastWaxOffsets do
		table.insert(lootSpawns, {
			lootId = "LifeWax" :: any,
			roomIndex = EAST_VIGIL,
			offset = offset,
			respawnSeconds = UnlittiusFloorPlan.WAX_RESPAWN_SECONDS,
		})
	end

	return {
		depth = localFloor,
		globalDepth = globalDepth,
		familyId = familyId,
		worldOrigin = worldOrigin,
		diagnostics = { shapedRooms = 0, shapeFallbacks = 0, shapeRejections = 0 },
		rooms = rooms,
		entryRoomIndex = ENTRY,
		basinRoomIndex = DESCENT,
		-- The Gas Lantern, in the ENTRY, for the same reason her floor puts it there: banishing him is
		-- required to go DOWN, never to leave the cave. A party that has run out of light must be able
		-- to see the way out and choose it.
		brazierRoomIndex = ENTRY,
		-- NO ORDINARY ROSTER. His summoned Gnawers are the floor's creatures and they arrive on his
		-- schedule; a wandering Knotwalker would be noise in a chamber already at capacity.
		threatSpawns = {},
		enemySpawns = {},
		lootSpawns = lootSpawns,
		hazards = {},
		dripstones = dripstones,
		vines = {},
		lurkers = {},
		warden = nil,
		deadCandle = nil,
		deposits = deposits,
		blastVaults = {},
		mossFire = {},
		groundPatches = {},
		-- The same flag her floor sets. Everything downstream that already knows "this is a boss floor"
		-- — the doorway minimums, the loot respawn pass, the audit — keeps working unchanged, and the
		-- ROTATION (`Logic/BossRotation`) is what decides which boss it is.
		bossEncounter = true,
		lockedStoreRoomIndex = nil,
	}
end

function UnlittiusFloorPlan.isUnlittiusPlan(plan: Types.FloorPlan): boolean
	return plan.bossEncounter == true and #plan.enemySpawns == 0 and #plan.threatSpawns == 0
end

-- Where the encounter's own fixtures go, in room-local offsets. Kept beside the layout for the reason
-- hers are: moving a vigil means moving what is in it, and the two disagreeing is how a cache ends up
-- inside a wall.
function UnlittiusFloorPlan.fixtures()
	local cell = FloorsConfig.geometry.cellSize
	return {
		-- DEAD CENTRE of the shrine room, unlike her. She sits back from the middle so a player entering
		-- sees her whole silhouette against the far wall; his shrine is a RING and the ring has to be
		-- concentric with the room or one arc of it ends up against a wall with nowhere to stand.
		shrineOffset = Vector3.zero,
		-- The eight candle posts are NOT authored here. They are generated from
		-- `Logic/UnlittiusRules.candleOffsets` around this centre, because the ring radius is a tuning
		-- value in `Config/Unlittius` that the encounter, his attack ranges and the client's progress
		-- read all share — a second copy here would drift the first time it moved.
		candleRingRadius = UnlittiusConfig.encounter.candleRingRadius,
		-- Wax, spread across both vigils so neither is a single spot to farm from.
		westWaxOffsets = {
			Vector3.new(-cell * 0.2, 0, -cell * 0.18),
			Vector3.new(cell * 0.14, 0, cell * 0.2),
			Vector3.new(-cell * 0.24, 0, cell * 0.08),
		},
		eastWaxOffsets = {
			Vector3.new(cell * 0.2, 0, -cell * 0.18),
			Vector3.new(-cell * 0.14, 0, cell * 0.2),
			Vector3.new(cell * 0.24, 0, cell * 0.08),
		},
		sealedWaxOffset = Vector3.new(cell * 0.3, 0, -cell * 0.3),
	}
end

return UnlittiusFloorPlan

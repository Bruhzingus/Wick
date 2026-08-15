--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local RoomNavigation = require(script.Parent.Parent.Logic.RoomNavigation)
local DoorwayGeometry = require(script.Parent.Parent.Logic.DoorwayGeometry)

local cell = FloorsConfig.geometry.cellSize
local clearance = FloorsConfig.geometry.wallThickness * 2

local function testPlan(): (Types.FloorPlan, { Vector3 })
	local plan: Types.FloorPlan = {
		depth = 1,
		globalDepth = 1,
		worldOrigin = Vector3.zero,
		rooms = {
			{ moduleId = "Corridor", gridX = 0, gridZ = 0, doorways = { "E" }, ceilingHeight = 20 },
			{ moduleId = "Crossing", gridX = 1, gridZ = 0, doorways = { "W", "S" }, ceilingHeight = 20 },
			{ moduleId = "Corridor", gridX = 1, gridZ = 1, doorways = { "N", "E" }, ceilingHeight = 20 },
			{ moduleId = "Basin", gridX = 2, gridZ = 1, doorways = { "W" }, ceilingHeight = 20 },
		},
		entryRoomIndex = 1,
		basinRoomIndex = 4,
		brazierRoomIndex = 3,
		threatSpawns = {},
		lootSpawns = {},
		hazards = {},
		dripstones = {},
		groundPatches = {},
		-- `RoomNavigation.build` reads this to keep sealed vaults out of the graph entirely, so a plan
		-- handed to it has to carry the field even when the floor has no vault.
		blastVaults = {},
	}
	local centers: { Vector3 } = {
		Vector3.new(0, 0, 0),
		Vector3.new(cell, 0, 0),
		Vector3.new(cell, 0, cell),
		Vector3.new(cell * 2, 0, cell),
	}
	return plan, centers
end

local suite: Harness.Suite = {
	name = "RoomNavigation",
	tests = {
		Harness.test("cross-room routes aim through each connected doorway", function()
			local plan, centers = testPlan()
			local navigation = RoomNavigation.build(plan, centers)
			local target = centers[3]

			-- Doorways are off-centre, so the crossing aims at the opening's actual lateral offset.
			local eastOffset = DoorwayGeometry.profile(0, 0, "E", plan.globalDepth).offset
			local southOffset = DoorwayGeometry.profile(1, 0, "S", plan.globalDepth).offset

			local firstWaypoint = RoomNavigation.nextWaypoint(navigation, centers[1], target, clearance)
			Harness.vectorNear(
				firstWaypoint,
				Vector3.new(cell / 2 + clearance, 0, eastOffset),
				nil,
				"the first leg should cross the east doorway (at its offset) instead of cutting through a wall"
			)

			local secondWaypoint = RoomNavigation.nextWaypoint(navigation, firstWaypoint, target, clearance)
			Harness.vectorNear(
				secondWaypoint,
				Vector3.new(cell + southOffset, 0, cell / 2 + clearance),
				nil,
				"the second leg should cross the south doorway (at its offset)"
			)
		end),

		Harness.test("a sealed blast vault is an ordinary room in the graph", function()
			local plan, centers = testPlan()
			-- Hang a vault off the crossing, exactly as the planner does: a new leaf cell with one
			-- doorway back the way it came, and the parent listing the reciprocal side.
			table.insert(plan.rooms, {
				moduleId = "BlastVault",
				gridX = 1,
				gridZ = -1,
				doorways = { "S" },
				ceilingHeight = 19,
				footprint = plan.rooms[1].footprint,
			})
			table.insert(plan.rooms[2].doorways, "N")
			table.insert(centers, Vector3.new(cell, 0, -cell))
			table.insert(plan.blastVaults, {
				roomIndex = 5,
				direction = "S",
				socketFraction = 0.5,
				socketHeightFraction = 0.45,
				visualSeed = 1,
				style = "Rock",
			})

			local navigation = RoomNavigation.build(plan, centers)
			-- A reciprocal doorway is an edge, and a vault's is reciprocal. What stops a body while the
			-- door is still standing is the door itself — a collidable, queryable part the obstacle
			-- raycast in ThreatService sees — not a hole in the graph. Modelling the seal here as well
			-- would leave a blown-open vault unreachable until the floor was rebuilt.
			Harness.expect(
				table.find(navigation.neighbors[2], 5) ~= nil,
				"the crossing must neighbour the vault it has a shared doorway with"
			)
			Harness.equal(#navigation.neighbors[5], 1, "a vault's one doorway is its one edge")
			Harness.equal(navigation.neighbors[5][1], 2)
		end),

		Harness.test("the Basin is an ordinary room: routes go all the way in", function()
			local plan, centers = testPlan()
			local navigation = RoomNavigation.build(plan, centers)
			local basinCenter = centers[plan.basinRoomIndex]

			-- The Basin used to be carved out of the graph, and a threat aimed at it was walked to the
			-- ordinary side of its doorway and stopped there. Nothing is protected now (DESIGN §10), so
			-- it is a neighbour like any other and a route through its doorway is an ordinary crossing.
			Harness.expect(
				table.find(navigation.neighbors[plan.brazierRoomIndex], plan.basinRoomIndex) ~= nil,
				"the Basin must be a real neighbour of the room it shares a doorway with"
			)
			Harness.expect(
				table.find(navigation.neighbors[plan.basinRoomIndex], plan.brazierRoomIndex) ~= nil,
				"the edge must be reciprocal, so a threat can leave again"
			)

			-- Room 3 opens east onto the Basin, so a target inside it aims at that doorway rather than
			-- stopping a clearance short of the threshold the way the old approach waypoint did.
			local eastOffset = DoorwayGeometry.profile(1, 1, "E", plan.globalDepth).offset
			local crossing =
				RoomNavigation.nextWaypoint(navigation, centers[plan.brazierRoomIndex], basinCenter, clearance)
			Harness.vectorNear(
				crossing,
				Vector3.new(cell + cell / 2 + clearance, 0, cell + eastOffset),
				nil,
				"a threat should aim through the Basin doorway like any other"
			)

			-- And once inside, it can be given a target inside the Basin without being bounced out.
			local inside = RoomNavigation.nextWaypoint(navigation, basinCenter, basinCenter, clearance)
			Harness.vectorNear(inside, basinCenter, nil, "a threat standing in the Basin may stay there")
		end),

		Harness.test("a position on another floor still resolves to no room", function()
			local plan, centers = testPlan()
			local navigation = RoomNavigation.build(plan, centers)
			-- The vertical guard is the one filter that survived: a floor's graph must never claim a
			-- point belonging to the floor above or below, however the rooms happen to share cells.
			local positionOnAnotherFloor = centers[plan.basinRoomIndex]
				- Vector3.new(0, FloorsConfig.geometry.floorGap, 0)
			Harness.isNil(RoomNavigation.roomAt(navigation, positionOnAnotherFloor))
			-- The recovery below must respect the same boundary. A body that is not on this floor has no
			-- nearest room here, however close it looks from directly above.
			Harness.isNil(RoomNavigation.nearestRoom(navigation, positionOnAnotherFloor))
		end),

		Harness.test("a body outside every cell recovers to the nearest room, not a remembered one", function()
			local plan, centers = testPlan()
			local navigation = RoomNavigation.build(plan, centers)

			-- The room grid is SPARSE: cell (0,-1) north of the entry was never placed, so a body pushed
			-- out there is inside no room at all. This is the case `surfaceAt` in server/ThreatService
			-- used to answer with the threat's SPAWN room, which is what hung ceiling flies above the
			-- roof — a birthplace on the far side of the floor describes a ceiling that is not overhead.
			local strayed = centers[1] + Vector3.new(0, 0, -cell)
			Harness.isNil(RoomNavigation.roomAt(navigation, strayed), "a cell that was never placed holds no room")
			Harness.equal(
				RoomNavigation.nearestRoom(navigation, strayed),
				1,
				"recovery must pick the room the point is actually beside"
			)

			-- The same point recovers to the same room whichever room a caller might have remembered,
			-- because it is a function of position alone. That is the whole guarantee.
			local besideTheBasin = centers[plan.basinRoomIndex] + Vector3.new(cell, 0, 0)
			Harness.equal(
				RoomNavigation.nearestRoom(navigation, besideTheBasin),
				plan.basinRoomIndex,
				"a point off the far edge of the floor belongs to the room it is nearest"
			)
		end),

		Harness.test("roaming picks any connected room, Basin included, and prefers not to double back", function()
			local plan, centers = testPlan()
			local navigation = RoomNavigation.build(plan, centers)
			local rng = Random.new(5)

			-- The Crossing (room 2) opens west to the Corridor and south to the Brazier room.
			local destination, center = RoomNavigation.roamDestination(navigation, centers[2], nil, rng)
			Harness.expect(
				destination == 1 or destination == 3,
				"a roam must land in a room this one actually has a doorway to"
			)
			Harness.vectorNear(center :: Vector3, centers[destination :: number])

			for _ = 1, 8 do
				local onward = RoomNavigation.roamDestination(navigation, centers[2], 1, rng)
				Harness.equal(onward, 3, "with another doorway open, a roam should not turn straight around")
			end

			-- Room 3 opens onto the Crossing and onto the Basin. Arriving from the Crossing, the roam
			-- should now prefer the Basin rather than turning around — the safe room used to be the one
			-- destination it could never pick, and a dead end was the only reason it doubled back here.
			for _ = 1, 8 do
				local onward = RoomNavigation.roamDestination(navigation, centers[3], 2, rng)
				Harness.equal(onward, plan.basinRoomIndex, "a roam must be able to carry something into the Basin")
			end

			-- And a threat standing in the Basin has somewhere to go, rather than being stranded by a
			-- graph that refused to contain it.
			local fromBasin = RoomNavigation.roamDestination(navigation, centers[plan.basinRoomIndex], nil, rng)
			Harness.equal(fromBasin, 3, "a threat in the Basin must be able to roam back out")
		end),

		Harness.test("localized pools divert same-room threat waypoints around the bank", function()
			local plan, centers = testPlan()
			plan.hazards = {
				{
					hazardId = "Water",
					roomIndex = 2,
					waterDepth = 1.2,
					localOffset = Vector3.zero,
					size = Vector3.new(12, 1.2, 12),
				},
			}
			local navigation = RoomNavigation.build(plan, centers)
			local from = centers[2] + Vector3.new(-12, 0, 0)
			local target = centers[2] + Vector3.new(12, 0, 0)
			local waypoint = RoomNavigation.nextWaypoint(navigation, from, target, clearance)
			Harness.expect(math.abs(waypoint.Z - centers[2].Z) > 1, "threat should choose a pool-bank corner")
			Harness.expect(waypoint.X < centers[2].X, "first detour should remain on the approach side")
		end),
	},
}

return suite

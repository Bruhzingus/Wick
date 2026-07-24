--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local RoomNavigation = require(script.Parent.Parent.Logic.RoomNavigation)

local cell = FloorsConfig.geometry.cellSize
local clearance = FloorsConfig.geometry.wallThickness * 2

local function testPlan(): (Types.FloorPlan, { Vector3 })
	local plan: Types.FloorPlan = {
		depth = 1,
		rooms = {
			{ moduleId = "Corridor", gridX = 0, gridZ = 0, doorways = { "E" } },
			{ moduleId = "Crossing", gridX = 1, gridZ = 0, doorways = { "W", "S" } },
			{ moduleId = "Corridor", gridX = 1, gridZ = 1, doorways = { "N", "E" } },
			{ moduleId = "Basin", gridX = 2, gridZ = 1, doorways = { "W" } },
		},
		entryRoomIndex = 1,
		basinRoomIndex = 4,
		brazierRoomIndex = 3,
		threatSpawns = {},
		lootSpawns = {},
		hazards = {},
		groundPatches = {},
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

			local firstWaypoint = RoomNavigation.nextWaypoint(navigation, centers[1], target, clearance)
			Harness.vectorNear(
				firstWaypoint,
				Vector3.new(cell / 2 + clearance, 0, 0),
				nil,
				"the first leg should cross the east doorway instead of cutting diagonally through a wall"
			)

			local secondWaypoint = RoomNavigation.nextWaypoint(navigation, firstWaypoint, target, clearance)
			Harness.vectorNear(
				secondWaypoint,
				Vector3.new(cell, 0, cell / 2 + clearance),
				nil,
				"the second leg should cross the south doorway"
			)
		end),

		Harness.test("the Basin is protected and routes stop on the ordinary-room side", function()
			local plan, centers = testPlan()
			local navigation = RoomNavigation.build(plan, centers)
			local basinCenter = centers[plan.basinRoomIndex]

			Harness.expect(RoomNavigation.isProtected(navigation, basinCenter))
			Harness.expect(not RoomNavigation.isProtected(navigation, centers[plan.brazierRoomIndex]))

			local approach =
				RoomNavigation.nextWaypoint(navigation, centers[plan.brazierRoomIndex], basinCenter, clearance)
			Harness.vectorNear(
				approach,
				Vector3.new(cell + cell / 2 - clearance, 0, cell),
				nil,
				"a threat should wait before the Basin threshold"
			)
			Harness.expect(not RoomNavigation.isProtected(navigation, approach))

			local constrained =
				RoomNavigation.constrainStep(navigation, centers[plan.brazierRoomIndex], basinCenter, clearance)
			Harness.vectorNear(constrained, approach, nil, "the final movement guard should reject Basin entry")

			local recoveryTarget =
				RoomNavigation.nextWaypoint(navigation, basinCenter, centers[plan.brazierRoomIndex], clearance)
			local recoveryStep = basinCenter + (recoveryTarget - basinCenter).Unit * clearance
			Harness.vectorNear(
				RoomNavigation.constrainStep(navigation, basinCenter, recoveryStep, clearance),
				recoveryStep,
				nil,
				"an already-invalid Basin position should be allowed to move toward an ordinary doorway"
			)
		end),

		Harness.test("stacked floors do not share safe-room classification", function()
			local plan, centers = testPlan()
			local navigation = RoomNavigation.build(plan, centers)
			local positionOnAnotherFloor = centers[plan.basinRoomIndex]
				- Vector3.new(0, FloorsConfig.geometry.floorGap, 0)
			Harness.isNil(RoomNavigation.roomAt(navigation, positionOnAnotherFloor))
			Harness.expect(not RoomNavigation.isProtected(navigation, positionOnAnotherFloor))
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

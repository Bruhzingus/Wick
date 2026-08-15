--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FloorPlanner = require(ReplicatedStorage.Shared.Logic.FloorPlanner)
local FloorStacking = require(ReplicatedStorage.Shared.Logic.FloorStacking)
local Harness = require(script.Parent.Harness)

return {
	name = "FloorStacking",
	tests = {
		{
			name = "successor entry is directly beneath the previous descent",
			run = function()
				local plans = FloorPlanner.planAll(91427, 6)
				for index = 1, #plans - 1 do
					local expected = FloorStacking.descentOrigin(plans[index], Config.Floors.geometry.cellSize)
					local actual = FloorStacking.roomCenter(
						plans[index + 1],
						plans[index + 1].entryRoomIndex,
						Config.Floors.geometry.cellSize
					)
					Harness.near(actual.X, expected.X)
					Harness.near(actual.Z, expected.Z)
				end
			end,
		},
		{
			name = "world translation does not change local topology",
			run = function()
				local first = FloorPlanner.plan({ globalDepth = 7, rng = Random.new(55) })
				local moved = FloorPlanner.plan({
					globalDepth = 7,
					rng = Random.new(55),
					worldOrigin = Vector3.new(128, 99, -64),
				})
				Harness.equal(#moved.rooms, #first.rooms)
				Harness.equal(moved.worldOrigin.Y, 0)
				for index, room in first.rooms do
					Harness.equal(moved.rooms[index].gridX, room.gridX)
					Harness.equal(moved.rooms[index].gridZ, room.gridZ)
					Harness.equal(moved.rooms[index].moduleId, room.moduleId)
				end
			end,
		},
	},
}

--!strict
-- Pure world-placement rules for vertically linking procedural floors.
--
-- Room grid coordinates stay local to a floor. Only `FloorPlan.worldOrigin` moves, which preserves
-- the floor's deterministic topology and doorway geometry while putting the next entry directly
-- beneath the current completion chamber's actual Descent Ladder pad.

local Types = require(script.Parent.Parent.Types)

local FloorStacking = {}

function FloorStacking.roomCenter(plan: Types.FloorPlan, roomIndex: number, cellSize: number): Vector3
	local room = plan.rooms[roomIndex]
	if room == nil then
		error("FloorStacking.roomCenter: invalid room index " .. tostring(roomIndex), 2)
	end
	return plan.worldOrigin + Vector3.new(room.gridX * cellSize, 0, room.gridZ * cellSize)
end

function FloorStacking.descentOrigin(plan: Types.FloorPlan, cellSize: number): Vector3
	return FloorStacking.roomCenter(plan, plan.basinRoomIndex, cellSize) + Vector3.new(cellSize / 4, 0, cellSize / 4)
end

function FloorStacking.nextFloorOrigin(plan: Types.FloorPlan, cellSize: number): Vector3
	local descent = FloorStacking.descentOrigin(plan, cellSize)
	return Vector3.new(descent.X, 0, descent.Z)
end

return FloorStacking

--!strict
-- Pure: config + seed -> FloorPlan. Rooms are cells on a grid, attached one at a time to a random
-- open side of an existing room (respecting each module's connection cap). The builder receives
-- placements and doorways; it decides nothing.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)

local FloorPlanner = {}

local DIRECTIONS: { Types.Direction } = { "N", "S", "E", "W" }
local OFFSETS: { [Types.Direction]: { x: number, z: number } } = {
	N = { x = 0, z = -1 },
	S = { x = 0, z = 1 },
	E = { x = 1, z = 0 },
	W = { x = -1, z = 0 },
}
local OPPOSITE: { [Types.Direction]: Types.Direction } = { N = "S", S = "N", E = "W", W = "E" }

local function cellKey(x: number, z: number): string
	return x .. "," .. z
end

local function moduleById(id: Types.RoomModuleId): Types.RoomModuleDef?
	for _, def in FloorsConfig.roomModules do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function weightedModule(rng: Random): Types.RoomModuleDef
	local totalWeight = 0
	for _, def in FloorsConfig.roomModules do
		totalWeight += def.weight
	end
	local roll = rng:NextNumber() * totalWeight
	for _, def in FloorsConfig.roomModules do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end
	return FloorsConfig.roomModules[#FloorsConfig.roomModules]
end

-- All (roomIndex, direction) pairs where a new room could attach.
local function openSides(
	rooms: { Types.RoomPlacement },
	occupied: { [string]: boolean },
	ignoreConnectionCap: boolean
): { { roomIndex: number, direction: Types.Direction } }
	local sides: { { roomIndex: number, direction: Types.Direction } } = {}
	for index, room in rooms do
		local def = moduleById(room.moduleId)
		local cap = if def ~= nil then def.connections else 2
		if not ignoreConnectionCap and #room.doorways >= cap then
			continue
		end
		for _, direction in DIRECTIONS do
			local offset = OFFSETS[direction]
			if not occupied[cellKey(room.gridX + offset.x, room.gridZ + offset.z)] then
				table.insert(sides, { roomIndex = index, direction = direction })
			end
		end
	end
	return sides
end

local function attachRoom(
	rooms: { Types.RoomPlacement },
	occupied: { [string]: boolean },
	side: { roomIndex: number, direction: Types.Direction },
	moduleId: Types.RoomModuleId
): number
	local parent = rooms[side.roomIndex]
	local offset = OFFSETS[side.direction]
	local placement: Types.RoomPlacement = {
		moduleId = moduleId,
		gridX = parent.gridX + offset.x,
		gridZ = parent.gridZ + offset.z,
		doorways = { OPPOSITE[side.direction] },
	}
	table.insert(parent.doorways, side.direction)
	table.insert(rooms, placement)
	occupied[cellKey(placement.gridX, placement.gridZ)] = true
	return #rooms
end

local function gridDistance(a: Types.RoomPlacement, b: Types.RoomPlacement): number
	return math.abs(a.gridX - b.gridX) + math.abs(a.gridZ - b.gridZ)
end

function FloorPlanner.plan(depth: number, rng: Random): Types.FloorPlan
	local roomCount = FloorsConfig.roomsPerFloor[math.clamp(depth, 1, #FloorsConfig.roomsPerFloor)]
	local rooms: { Types.RoomPlacement } = {}
	local occupied: { [string]: boolean } = {}

	local first = weightedModule(rng)
	table.insert(rooms, { moduleId = first.id, gridX = 0, gridZ = 0, doorways = {} })
	occupied[cellKey(0, 0)] = true

	for _ = 2, roomCount do
		local sides = openSides(rooms, occupied, false)
		if #sides == 0 then
			sides = openSides(rooms, occupied, true) -- caps exhausted; relax rather than under-build
		end
		if #sides == 0 then
			break
		end
		attachRoom(rooms, occupied, sides[rng:NextInteger(1, #sides)], weightedModule(rng).id)
	end

	local entryRoomIndex = 1

	-- Brazier in the room farthest from entry; the Basin (safe room + descent) attaches beyond it.
	local brazierRoomIndex = entryRoomIndex
	local bestDistance = -1
	for index, room in rooms do
		local distance = gridDistance(rooms[entryRoomIndex], room)
		if distance > bestDistance then
			bestDistance = distance
			brazierRoomIndex = index
		end
	end

	local basinSides = openSides(rooms, occupied, true)
	-- Prefer attaching the Basin to the brazier room so the safe room sits past the payout.
	local basinSide = basinSides[rng:NextInteger(1, math.max(#basinSides, 1))]
	for _, side in basinSides do
		if side.roomIndex == brazierRoomIndex then
			basinSide = side
			break
		end
	end
	local basinRoomIndex = attachRoom(rooms, occupied, basinSide, "Basin")

	-- Threats: budgeted count, each in a random eligible room (never the entry or the Basin).
	local threatSpawns: { Types.ThreatSpawn } = {}
	local budget = FloorsConfig.threatBudgetPerFloor[math.clamp(depth, 1, #FloorsConfig.threatBudgetPerFloor)]
	local eligible: { number } = {}
	for index, room in rooms do
		local def = moduleById(room.moduleId)
		if index ~= entryRoomIndex and index ~= basinRoomIndex and def ~= nil and #def.allowedThreats > 0 then
			table.insert(eligible, index)
		end
	end
	if #eligible > 0 then
		for _ = 1, budget do
			local roomIndex = eligible[rng:NextInteger(1, #eligible)]
			local def = moduleById(rooms[roomIndex].moduleId) :: Types.RoomModuleDef
			table.insert(threatSpawns, {
				threatId = def.allowedThreats[rng:NextInteger(1, #def.allowedThreats)],
				roomIndex = roomIndex,
			})
		end
	end

	-- Hazards: flooded modules always flood; other rooms roll once against hazardChancePerRoom.
	local hazards: { Types.HazardPlacement } = {}
	for index, room in rooms do
		if index == entryRoomIndex or index == basinRoomIndex then
			continue
		end
		local def = moduleById(room.moduleId)
		if def == nil then
			continue
		end
		if def.waterDepth ~= nil then
			table.insert(hazards, { hazardId = "Water", roomIndex = index, waterDepth = def.waterDepth })
		end
		if #def.allowedHazards > 0 and rng:NextNumber() < FloorsConfig.hazardChancePerRoom then
			local hazardId = def.allowedHazards[rng:NextInteger(1, #def.allowedHazards)]
			if hazardId ~= "Water" then -- flooding is module-driven, never rolled
				table.insert(hazards, { hazardId = hazardId, roomIndex = index })
			end
		end
	end

	return {
		depth = depth,
		rooms = rooms,
		entryRoomIndex = entryRoomIndex,
		basinRoomIndex = basinRoomIndex,
		brazierRoomIndex = brazierRoomIndex,
		threatSpawns = threatSpawns,
		hazards = hazards,
	}
end

-- Every floor of a full descent, from one seed.
function FloorPlanner.planAll(seed: number): { Types.FloorPlan }
	local rng = Random.new(seed)
	local plans: { Types.FloorPlan } = {}
	for depth = 1, FloorsConfig.maxFloors do
		table.insert(plans, FloorPlanner.plan(depth, rng))
	end
	return plans
end

return FloorPlanner

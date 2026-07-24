--!strict
-- Pure: config + seed -> FloorPlan. Rooms are cells on a grid, attached one at a time to a random
-- open side of an existing room (respecting each module's connection cap). The builder receives
-- placements and doorways; it decides nothing.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)

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

local function hasDirection(doorways: { Types.Direction }, wanted: Types.Direction): boolean
	return table.find(doorways, wanted) ~= nil
end

local function overlapsXZ(
	firstOffset: Vector3,
	firstSize: Vector3,
	secondOffset: Vector3,
	secondSize: Vector3,
	padding: number
): boolean
	return math.abs(firstOffset.X - secondOffset.X) <= (firstSize.X + secondSize.X) / 2 + padding
		and math.abs(firstOffset.Z - secondOffset.Z) <= (firstSize.Z + secondSize.Z) / 2 + padding
end

local function blocksDoorway(room: Types.RoomPlacement, offset: Vector3, size: Vector3): boolean
	local geometry = FloorsConfig.geometry
	local terrain = FloorsConfig.terrain
	local halfCell = geometry.cellSize / 2
	local minX = offset.X - size.X / 2
	local maxX = offset.X + size.X / 2
	local minZ = offset.Z - size.Z / 2
	local maxZ = offset.Z + size.Z / 2
	local halfLane = terrain.doorClearanceWidth / 2
	for _, direction in room.doorways do
		if
			direction == "N"
			and minZ <= -halfCell + terrain.doorClearanceDepth
			and minX <= halfLane
			and maxX >= -halfLane
		then
			return true
		elseif
			direction == "S"
			and maxZ >= halfCell - terrain.doorClearanceDepth
			and minX <= halfLane
			and maxX >= -halfLane
		then
			return true
		elseif
			direction == "E"
			and maxX >= halfCell - terrain.doorClearanceDepth
			and minZ <= halfLane
			and maxZ >= -halfLane
		then
			return true
		elseif
			direction == "W"
			and minX <= -halfCell + terrain.doorClearanceDepth
			and minZ <= halfLane
			and maxZ >= -halfLane
		then
			return true
		end
	end
	return false
end

local function fitsInsideRoom(offset: Vector3, size: Vector3): boolean
	local terrain = FloorsConfig.terrain
	local radius = FloorsConfig.geometry.cellSize / 2 - terrain.wallClearance
	return math.abs(offset.X) + size.X / 2 <= radius and math.abs(offset.Z) + size.Z / 2 <= radius
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

local function weightedDryModule(connectionCount: number, rng: Random): Types.RoomModuleDef
	local eligible: { Types.RoomModuleDef } = {}
	local totalWeight = 0
	for _, def in FloorsConfig.roomModules do
		if def.waterDepth == nil and def.connections >= connectionCount then
			table.insert(eligible, def)
			totalWeight += def.weight
		end
	end
	if #eligible == 0 then
		for _, def in FloorsConfig.roomModules do
			if def.waterDepth == nil then
				return def
			end
		end
		return FloorsConfig.roomModules[1]
	end
	local roll = rng:NextNumber() * totalWeight
	for _, def in eligible do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end
	return eligible[#eligible]
end

local function weightAtDepth(weights: { number }, depth: number): number
	if #weights == 0 then
		return 0
	end
	return math.max(0, weights[math.clamp(depth, 1, #weights)])
end

local function weightedThreat(allowedThreats: { Types.ThreatId }, depth: number, rng: Random): Types.ThreatId?
	local totalWeight = 0
	for _, threatId in allowedThreats do
		local def = ThreatsConfig.definitions[threatId]
		if def ~= nil then
			totalWeight += weightAtDepth(def.spawnWeightByDepth, depth)
		end
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * totalWeight
	for _, threatId in allowedThreats do
		local def = ThreatsConfig.definitions[threatId]
		if def ~= nil then
			roll -= weightAtDepth(def.spawnWeightByDepth, depth)
			if roll <= 0 then
				return threatId
			end
		end
	end
	return nil
end

local function roomHasThreatAtDepth(def: Types.RoomModuleDef, depth: number): boolean
	for _, threatId in def.allowedThreats do
		local threatDef = ThreatsConfig.definitions[threatId]
		if threatDef ~= nil and weightAtDepth(threatDef.spawnWeightByDepth, depth) > 0 then
			return true
		end
	end
	return false
end

local function weightedLoot(depth: number, rng: Random): Types.LootId?
	local ids: { Types.LootId } = {}
	for lootId in LootConfig.definitions do
		table.insert(ids, lootId)
	end
	table.sort(ids)

	local totalWeight = 0
	for _, lootId in ids do
		totalWeight += weightAtDepth(LootConfig.definitions[lootId].spawnWeightByDepth, depth)
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * totalWeight
	for _, lootId in ids do
		roll -= weightAtDepth(LootConfig.definitions[lootId].spawnWeightByDepth, depth)
		if roll <= 0 then
			return lootId
		end
	end
	return nil
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

local function addLoopConnections(rooms: { Types.RoomPlacement }, rng: Random)
	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end
	for _, room in rooms do
		local def = moduleById(room.moduleId)
		for _, direction: Types.Direction in { "E", "S" } do
			local offset = OFFSETS[direction]
			local neighborIndex = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighborIndex == nil or hasDirection(room.doorways, direction) then
				continue
			end
			local neighbor = rooms[neighborIndex]
			local neighborDef = moduleById(neighbor.moduleId)
			if
				def ~= nil
				and neighborDef ~= nil
				and #room.doorways < def.connections
				and #neighbor.doorways < neighborDef.connections
				and rng:NextNumber() < FloorsConfig.loopConnectionChance
			then
				table.insert(room.doorways, direction)
				table.insert(neighbor.doorways, OPPOSITE[direction])
			end
		end
	end
end

local function pathBetween(rooms: { Types.RoomPlacement }, startIndex: number, goalIndex: number): { number }
	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end
	local queue = { startIndex }
	local head = 1
	local parent: { [number]: number } = {}
	local visited: { [number]: boolean } = { [startIndex] = true }
	while head <= #queue do
		local index = queue[head]
		head += 1
		if index == goalIndex then
			break
		end
		local room = rooms[index]
		for _, direction in room.doorways do
			local offset = OFFSETS[direction]
			local neighbor = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighbor ~= nil and not visited[neighbor] then
				visited[neighbor] = true
				parent[neighbor] = index
				table.insert(queue, neighbor)
			end
		end
	end
	local path = { goalIndex }
	local current = goalIndex
	while current ~= startIndex and parent[current] ~= nil do
		current = parent[current]
		table.insert(path, current)
	end
	return path
end

local function guaranteeDryRoute(
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	rng: Random
)
	for _, index in pathBetween(rooms, entryRoomIndex, basinRoomIndex) do
		local room = rooms[index]
		local def = moduleById(room.moduleId)
		if def ~= nil and def.waterDepth ~= nil then
			room.moduleId = weightedDryModule(#room.doorways, rng).id
		end
	end
end

function FloorPlanner.plan(depth: number, rng: Random, threatBudgetMultiplier: number?): Types.FloorPlan
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
	addLoopConnections(rooms, rng)

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
	-- Water may reward exploration but can never be the only route from spawn to the safe Basin.
	guaranteeDryRoute(rooms, entryRoomIndex, basinRoomIndex, rng)

	-- Threats: budgeted count, each in a random eligible room (never the entry or the Basin).
	local threatSpawns: { Types.ThreatSpawn } = {}
	local baseBudget = FloorsConfig.threatBudgetPerFloor[math.clamp(depth, 1, #FloorsConfig.threatBudgetPerFloor)]
	local budget = math.max(0, math.floor(baseBudget * math.max(threatBudgetMultiplier or 1, 0) + 0.5))
	local eligible: { number } = {}
	for index, room in rooms do
		local def = moduleById(room.moduleId)
		if index ~= entryRoomIndex and index ~= basinRoomIndex and def ~= nil and roomHasThreatAtDepth(def, depth) then
			table.insert(eligible, index)
		end
	end
	if #eligible > 0 then
		for _ = 1, budget do
			local roomIndex = eligible[rng:NextInteger(1, #eligible)]
			local def = moduleById(rooms[roomIndex].moduleId) :: Types.RoomModuleDef
			local threatId = weightedThreat(def.allowedThreats, depth, rng)
			if threatId ~= nil then
				table.insert(threatSpawns, {
					threatId = threatId,
					roomIndex = roomIndex,
				})
			end
		end
	end

	-- Loot: config-budgeted, depth-weighted, and fully positioned in the pure plan.
	local lootSpawns: { Types.LootSpawn } = {}
	local lootRoomIndices: { number } = {}
	for index in rooms do
		if index ~= entryRoomIndex and index ~= basinRoomIndex then
			table.insert(lootRoomIndices, index)
		end
	end
	local lootCount = LootConfig.spawnsPerFloor[math.clamp(depth, 1, #LootConfig.spawnsPerFloor)]
	if #lootRoomIndices > 0 then
		for _ = 1, lootCount do
			local lootId = weightedLoot(depth, rng)
			if lootId == nil then
				break
			end
			table.insert(lootSpawns, {
				lootId = lootId,
				roomIndex = lootRoomIndices[rng:NextInteger(1, #lootRoomIndices)],
				offset = Vector3.new(
					rng:NextNumber(-LootConfig.spawnOffsetRadius, LootConfig.spawnOffsetRadius),
					0,
					rng:NextNumber(-LootConfig.spawnOffsetRadius, LootConfig.spawnOffsetRadius)
				),
			})
		end
	end

	-- Hazards: flooded modules contain one localized recessed pool; other rooms roll once.
	local hazards: { Types.HazardPlacement } = {}
	local waterByRoom: { [number]: Types.HazardPlacement } = {}
	for index, room in rooms do
		if index == entryRoomIndex or index == basinRoomIndex then
			continue
		end
		local def = moduleById(room.moduleId)
		if def == nil then
			continue
		end
		if def.waterDepth ~= nil then
			local pool = HazardsConfig.waterPool
			local water: Types.HazardPlacement = {
				hazardId = "Water",
				roomIndex = index,
				waterDepth = def.waterDepth,
				localOffset = Vector3.new(
					rng:NextNumber(-pool.maxCenterOffset, pool.maxCenterOffset),
					0,
					rng:NextNumber(-pool.maxCenterOffset, pool.maxCenterOffset)
				),
				size = Vector3.new(
					rng:NextNumber(pool.minSize, pool.maxSize),
					def.waterDepth,
					rng:NextNumber(pool.minSize, pool.maxSize)
				),
			}
			table.insert(hazards, water)
			waterByRoom[index] = water
		end
		if #def.allowedHazards > 0 and rng:NextNumber() < FloorsConfig.hazardChancePerRoom then
			local hazardId = def.allowedHazards[rng:NextInteger(1, #def.allowedHazards)]
			if hazardId ~= "Water" then -- flooding is module-driven, never rolled
				local zone = HazardsConfig.draftZone
				local alongX = rng:NextInteger(0, 1) == 1
				local size = if alongX
					then Vector3.new(zone.length, zone.height, zone.width)
					else Vector3.new(zone.width, zone.height, zone.length)
				local offset = if alongX
					then Vector3.new(0, 0, rng:NextNumber(-zone.maxCenterOffset, zone.maxCenterOffset))
					else Vector3.new(rng:NextNumber(-zone.maxCenterOffset, zone.maxCenterOffset), 0, 0)
				table.insert(hazards, {
					hazardId = hazardId,
					roomIndex = index,
					localOffset = offset,
					size = size,
				})
			end
		end
	end

	-- Broad rock swells are real walkable ground, not visual clutter. Every room receives
	-- attempted elevation, including the entry and Basin; their central interaction areas stay
	-- clear. Door approaches, pools, and other shelves retain safe walking gaps.
	local groundPatches: { Types.GroundPatch } = {}
	local terrain = FloorsConfig.terrain
	for roomIndex, room in rooms do
		local water = waterByRoom[roomIndex]
		local roomGroundCount = 0
		for _ = 1, terrain.groundHumpsPerRoom do
			for _ = 1, terrain.placementAttemptsPerHump do
				local angle = rng:NextNumber(0, math.pi * 2)
				local radius = rng:NextNumber(terrain.groundHumpMinRadius, terrain.groundHumpMaxRadius)
				local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local diameter = rng:NextNumber(terrain.groundHumpMinDiameter, terrain.groundHumpMaxDiameter)
				local size = Vector3.new(
					diameter * rng:NextNumber(0.75, 1.2),
					rng:NextNumber(terrain.groundHumpMinHeight, terrain.groundHumpMaxHeight),
					diameter * rng:NextNumber(0.75, 1.2)
				)
				local overlapsWater = water ~= nil
					and overlapsXZ(
						offset,
						size,
						water.localOffset :: Vector3,
						water.size :: Vector3,
						terrain.hazardClearance
					)
				local overlapsSpecialCenter = (roomIndex == entryRoomIndex or roomIndex == basinRoomIndex)
					and overlapsXZ(
						offset,
						size,
						Vector3.zero,
						Vector3.new(terrain.specialRoomCenterClearance * 2, 0, terrain.specialRoomCenterClearance * 2),
						0
					)
				local overlapsGround = false
				for _, existing in groundPatches do
					if
						existing.roomIndex == roomIndex
						and overlapsXZ(offset, size, existing.localOffset, existing.size, terrain.groundHumpSeparation)
					then
						overlapsGround = true
						break
					end
				end
				if
					fitsInsideRoom(offset, size)
					and not overlapsWater
					and not overlapsSpecialCenter
					and not overlapsGround
					and not blocksDoorway(room, offset, size)
				then
					table.insert(groundPatches, {
						roomIndex = roomIndex,
						localOffset = offset,
						size = size,
					})
					roomGroundCount += 1
					break
				end
			end
		end
		if roomGroundCount == 0 then
			-- A four-door room can reject unlucky radial rolls. Corner fallbacks are outside every
			-- doorway's protected center lane and guarantee that even entry/Basin rooms are not flat.
			local fallbackSize = Vector3.new(
				terrain.groundHumpMinDiameter * 0.8,
				terrain.groundHumpMinHeight,
				terrain.groundHumpMinDiameter * 0.8
			)
			for _, xSign in { -1, 1 } do
				for _, zSign in { -1, 1 } do
					local fallbackOffset = Vector3.new(xSign * 17, 0, zSign * 17)
					local overlapsWater = water ~= nil
						and overlapsXZ(
							fallbackOffset,
							fallbackSize,
							water.localOffset :: Vector3,
							water.size :: Vector3,
							terrain.hazardClearance
						)
					if
						fitsInsideRoom(fallbackOffset, fallbackSize)
						and not overlapsWater
						and not blocksDoorway(room, fallbackOffset, fallbackSize)
					then
						table.insert(groundPatches, {
							roomIndex = roomIndex,
							localOffset = fallbackOffset,
							size = fallbackSize,
						})
						roomGroundCount = 1
						break
					end
				end
				if roomGroundCount > 0 then
					break
				end
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
		lootSpawns = lootSpawns,
		hazards = hazards,
		groundPatches = groundPatches,
	}
end

-- Every floor of a full descent, from one seed.
function FloorPlanner.planAll(seed: number, maxFloors: number?, threatBudgetMultiplier: number?): { Types.FloorPlan }
	local rng = Random.new(seed)
	local plans: { Types.FloorPlan } = {}
	local floorCount = math.clamp(maxFloors or FloorsConfig.maxFloors, 1, FloorsConfig.maxFloors)
	for depth = 1, floorCount do
		table.insert(plans, FloorPlanner.plan(depth, rng, threatBudgetMultiplier))
	end
	return plans
end

return FloorPlanner

--!strict
-- Pure: config + seed -> FloorPlan. Rooms are cells on a grid, attached one at a time to a random
-- open side of an existing room (respecting each module's connection cap). The builder receives
-- placements and doorways; it decides nothing.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)
local DripstoneRules = require(script.Parent.DripstoneRules)
local GroundGeometry = require(script.Parent.GroundGeometry)
local RoofGeometry = require(script.Parent.RoofGeometry)

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

local function blocksDoorway(room: Types.RoomPlacement, depth: number, offset: Vector3, size: Vector3): boolean
	local geometry = FloorsConfig.geometry
	local terrain = FloorsConfig.terrain
	local halfCell = geometry.cellSize / 2
	for _, direction in room.doorways do
		local normal = OFFSETS[direction]
		local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, depth)
		local toward = offset.X * normal.x + offset.Z * normal.z
		local normalHalf = math.abs(normal.x) * size.X / 2 + math.abs(normal.z) * size.Z / 2
		if toward + normalHalf >= halfCell - terrain.doorClearanceDepth then
			local lateralCenter = offset.X * math.abs(normal.z) + offset.Z * math.abs(normal.x)
			local lateralHalf = math.abs(normal.z) * size.X / 2 + math.abs(normal.x) * size.Z / 2
			local laneHalf = math.max(terrain.doorClearanceWidth / 2, profile.width / 2)
			if
				lateralCenter - lateralHalf <= profile.offset + laneHalf
				and lateralCenter + lateralHalf >= profile.offset - laneHalf
			then
				return true
			end
		end
	end
	return false
end

local function fitsInsideRoom(offset: Vector3, size: Vector3): boolean
	local terrain = FloorsConfig.terrain
	local radius = FloorsConfig.geometry.cellSize / 2 - terrain.wallClearance
	return math.abs(offset.X) + size.X / 2 <= radius and math.abs(offset.Z) + size.Z / 2 <= radius
end

local function plannedLootOffset(room: Types.RoomPlacement, depth: number, rng: Random): Vector3
	local halfCell = FloorsConfig.geometry.cellSize / 2
	local footprint = Vector3.new(LootConfig.placementFootprint, 0, LootConfig.placementFootprint)
	for _ = 1, LootConfig.placementAttempts do
		local side = DIRECTIONS[rng:NextInteger(1, #DIRECTIONS)]
		local normal = OFFSETS[side]
		local wallDistance = halfCell - rng:NextNumber(LootConfig.wallInsetMin, LootConfig.wallInsetMax)
		local lateral = rng:NextNumber(-LootConfig.wallLateralRange, LootConfig.wallLateralRange)
		local offset = Vector3.new(
			normal.x * wallDistance + math.abs(normal.z) * lateral,
			0,
			normal.z * wallDistance + math.abs(normal.x) * lateral
		)
		if fitsInsideRoom(offset, footprint) and not blocksDoorway(room, depth, offset, footprint) then
			return offset
		end
	end

	-- Deep corner inset: outside ordinary doorway lanes but still on the elevated wall berm.
	local fallback = halfCell - LootConfig.wallInsetMax
	return Vector3.new(fallback, 0, fallback)
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

-- How strongly this threat wants this room's ceiling height. The light-seeking moth family (Drawn)
-- prefers tall caverns; the ceiling-diving VoidFly prefers tight low rooms; ground hunters lean low.
local function heightBias(def: Types.ThreatDef, tallness: number): number
	if def.ambush ~= nil then
		return 0.35 + 1.65 * (1 - tallness)
	elseif def.category == "Drawn" then
		return 0.35 + 1.65 * tallness
	end
	return 0.8 + 0.4 * (1 - tallness)
end

local function threatWeight(def: Types.ThreatDef, depth: number, ceilingHeight: number, tallness: number): number
	local ambush = def.ambush
	if ambush ~= nil and ceilingHeight > ambush.maximumCeilingHeight then
		return 0
	end
	return weightAtDepth(def.spawnWeightByDepth, depth) * heightBias(def, tallness)
end

local function weightedThreat(
	allowedThreats: { Types.ThreatId },
	depth: number,
	ceilingHeight: number,
	rng: Random
): Types.ThreatId?
	local g = FloorsConfig.geometry
	local span = g.ceilingMaxHeight - g.ceilingMinHeight
	local tallness = if span > 0 then math.clamp((ceilingHeight - g.ceilingMinHeight) / span, 0, 1) else 0.5

	local totalWeight = 0
	for _, threatId in allowedThreats do
		local def = ThreatsConfig.definitions[threatId]
		if def ~= nil then
			totalWeight += threatWeight(def, depth, ceilingHeight, tallness)
		end
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * totalWeight
	for _, threatId in allowedThreats do
		local def = ThreatsConfig.definitions[threatId]
		if def ~= nil then
			roll -= threatWeight(def, depth, ceilingHeight, tallness)
			if roll <= 0 then
				return threatId
			end
		end
	end
	return nil
end

local function roomHasThreatAtDepth(def: Types.RoomModuleDef, depth: number, ceilingHeight: number): boolean
	for _, threatId in def.allowedThreats do
		local threatDef = ThreatsConfig.definitions[threatId]
		if
			threatDef ~= nil
			and weightAtDepth(threatDef.spawnWeightByDepth, depth) > 0
			and (threatDef.ambush == nil or ceilingHeight <= threatDef.ambush.maximumCeilingHeight)
		then
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

local function weightedDripstoneVariant(rng: Random)
	local variants = HazardsConfig.unstableDripstone.variants
	local totalWeight = 0
	for _, variant in variants do
		totalWeight += math.max(0, variant.weight)
	end
	if totalWeight <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * totalWeight
	for _, variant in variants do
		roll -= math.max(0, variant.weight)
		if roll <= 0 then
			return variant
		end
	end
	return variants[#variants]
end

local function shuffle(indices: { number }, rng: Random)
	for index = #indices, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		indices[index], indices[swapIndex] = indices[swapIndex], indices[index]
	end
end

-- Excludes rooms holding a VoidFly or Snuffer (DESIGN §9: both are protected from unstable
-- dripstone). Both happen to share contactEffect == "Snuff"; keying on that generic field instead
-- of the two literal IDs means a future Snuff-style threat is automatically covered.
local function roomHasCeilingThreat(threatSpawns: { Types.ThreatSpawn }, roomIndex: number): boolean
	for _, spawn in threatSpawns do
		if spawn.roomIndex == roomIndex then
			local def = ThreatsConfig.definitions[spawn.threatId]
			if def ~= nil and def.contactEffect == "Snuff" then
				return true
			end
		end
	end
	return false
end

local function overlapsRoomHazard(
	hazards: { Types.HazardPlacement },
	roomIndex: number,
	offset: Vector3,
	radius: number
): boolean
	local probeSize = Vector3.new(radius * 2, 0, radius * 2)
	for _, hazard in hazards do
		if hazard.roomIndex ~= roomIndex or hazard.localOffset == nil or hazard.size == nil then
			continue
		end
		if
			overlapsXZ(
				offset,
				probeSize,
				hazard.localOffset,
				hazard.size,
				HazardsConfig.unstableDripstone.doorwaySafetyPadding
			)
		then
			return true
		end
	end
	return false
end

local function planDripstones(
	depth: number,
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	threatSpawns: { Types.ThreatSpawn },
	hazards: { Types.HazardPlacement },
	groundPatches: { Types.GroundPatch },
	rng: Random
): { Types.DripstonePlacement }
	local config = HazardsConfig.unstableDripstone
	local swellsByRoom: { [number]: { GroundGeometry.Swell } } = {}
	for _, patch in groundPatches do
		local swells = swellsByRoom[patch.roomIndex]
		if swells == nil then
			swells = {}
			swellsByRoom[patch.roomIndex] = swells
		end
		table.insert(swells, {
			x = patch.localOffset.X,
			z = patch.localOffset.Z,
			radius = math.max(patch.size.X, patch.size.Z) / 2,
			height = patch.size.Y,
		})
	end
	local poolsByRoom: { [number]: { GroundGeometry.Pool } } = {}
	for _, hazard in hazards do
		if
			hazard.hazardId == "Water"
			and hazard.localOffset ~= nil
			and hazard.size ~= nil
			and hazard.waterDepth ~= nil
		then
			local offset = hazard.localOffset
			local size = hazard.size
			poolsByRoom[hazard.roomIndex] = {
				{
					x = offset.X,
					z = offset.Z,
					radius = (size.X + size.Z) / 4,
					depth = hazard.waterDepth + HazardsConfig.waterPool.poolBedDepthPad,
				},
			}
		end
	end

	local candidateRooms: { number } = {}
	local ordinaryRoomCount = 0
	local groundFields: { [number]: GroundGeometry.Field } = {}
	local roofFields: { [number]: RoofGeometry.Field } = {}
	for roomIndex, room in rooms do
		if roomIndex == entryRoomIndex or roomIndex == basinRoomIndex or roomIndex == brazierRoomIndex then
			continue
		end
		ordinaryRoomCount += 1
		-- This is an environmental readability rule, not a client camera decision. A high cavern
		-- stays harmless even if one local roof ripple happens to hang lower.
		if
			room.ceilingHeight <= config.maxEligibleCeilingHeight
			and not roomHasCeilingThreat(threatSpawns, roomIndex)
		then
			table.insert(candidateRooms, roomIndex)
			groundFields[roomIndex] = GroundGeometry.fieldFor(
				room,
				depth,
				false,
				{},
				swellsByRoom[roomIndex] or {},
				poolsByRoom[roomIndex] or {}
			)
			roofFields[roomIndex] = RoofGeometry.fieldFor(room, depth)
		end
	end
	shuffle(candidateRooms, rng)

	if #candidateRooms == 0 or ordinaryRoomCount == 0 then
		return {}
	end

	local maxPerRoom = if depth <= 3
		then config.maxPerRoomEarly
		elseif depth <= 6 then config.maxPerRoomMid
		else config.maxPerRoomDeep
	local maxHazardousRooms = math.max(1, math.floor(ordinaryRoomCount * config.maxHazardousRoomFraction))
	local harmlessPerRoom = FloorsConfig.caveDressing.ceilingFormationsPerRoom
		+ FloorsConfig.caveDressing.ceilingBouldersPerRoom
	local harmlessCount = #rooms * harmlessPerRoom
	local harmlessCap = math.floor(harmlessCount * config.maxUnstableToHarmlessRatio)
	local target = math.min(DripstoneRules.targetCount(depth), maxHazardousRooms * maxPerRoom, harmlessCap)
	if target <= 0 then
		return {}
	end

	local placements: { Types.DripstonePlacement } = {}
	local placementsByRoom: { [number]: number } = {}
	local hazardousRoomCount = 0

	local function tryPlace(roomIndex: number): boolean
		local room = rooms[roomIndex]
		local variant = weightedDripstoneVariant(rng)
		if variant == nil then
			return false
		end
		local groundField = groundFields[roomIndex]
		local roofField = roofFields[roomIndex]
		if groundField == nil or roofField == nil then
			return false
		end
		for _ = 1, config.placementAttempts do
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(config.minCenterOffset, config.maxCenterOffset)
			local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			local safetyRadius = variant.triggerRadius + config.doorwaySafetyPadding
			local footprint = Vector3.new(safetyRadius * 2, 0, safetyRadius * 2)
			if not fitsInsideRoom(offset, footprint) or blocksDoorway(room, depth, offset, footprint) then
				continue
			end
			if overlapsRoomHazard(hazards, roomIndex, offset, variant.triggerRadius) then
				continue
			end
			local groundHeight = GroundGeometry.offset(groundField, offset.X, offset.Z)
			local localRoofHeight =
				RoofGeometry.undersideHeight(room.ceilingHeight, roofField, groundHeight, offset.X, offset.Z)
			if localRoofHeight > config.maxEligibleCeilingHeight then
				continue
			end
			local fallDistance = localRoofHeight - DripstoneRules.visualLength(variant) - groundHeight
			if fallDistance < config.minimumFallDistance then
				continue
			end
			local separated = true
			for _, existing in placements do
				if existing.roomIndex == roomIndex then
					local dx = existing.localOffset.X - offset.X
					local dz = existing.localOffset.Z - offset.Z
					if dx * dx + dz * dz < config.minFormationSpacing * config.minFormationSpacing then
						separated = false
						break
					end
				end
			end
			if not separated then
				continue
			end
			table.insert(placements, {
				roomIndex = roomIndex,
				localOffset = offset,
				variantId = variant.id,
				visualSeed = rng:NextInteger(1, 2_000_000_000),
			})
			return true
		end
		return false
	end

	-- First distribute one formation per selected room. Deeper floors may then revisit those same
	-- rooms, preserving at least half of ordinary rooms as completely safe.
	for round = 1, maxPerRoom do
		for _, roomIndex in candidateRooms do
			if #placements >= target then
				break
			end
			local existingCount = placementsByRoom[roomIndex] or 0
			if round == 1 then
				if hazardousRoomCount >= maxHazardousRooms then
					break
				end
			elseif existingCount == 0 then
				continue
			end
			if existingCount >= round then
				continue
			end
			if tryPlace(roomIndex) then
				placementsByRoom[roomIndex] = existingCount + 1
				if existingCount == 0 then
					hazardousRoomCount += 1
				end
			end
		end
	end
	return placements
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

-- Wide per-room ceiling height (planned): a full-range roll so roofs vary from tight crevices to
-- tall caverns. This is what the threat weighting reads to place moths high and flies low.
local function rollCeiling(rng: Random): number
	local g = FloorsConfig.geometry
	return g.ceilingMinHeight + (g.ceilingMaxHeight - g.ceilingMinHeight) * rng:NextNumber()
end

local function attachRoom(
	rooms: { Types.RoomPlacement },
	occupied: { [string]: boolean },
	side: { roomIndex: number, direction: Types.Direction },
	moduleId: Types.RoomModuleId,
	rng: Random
): number
	local parent = rooms[side.roomIndex]
	local offset = OFFSETS[side.direction]
	local placement: Types.RoomPlacement = {
		moduleId = moduleId,
		gridX = parent.gridX + offset.x,
		gridZ = parent.gridZ + offset.z,
		doorways = { OPPOSITE[side.direction] },
		ceilingHeight = rollCeiling(rng),
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
	table.insert(rooms, { moduleId = first.id, gridX = 0, gridZ = 0, doorways = {}, ceilingHeight = rollCeiling(rng) })
	occupied[cellKey(0, 0)] = true

	for _ = 2, roomCount do
		local sides = openSides(rooms, occupied, false)
		if #sides == 0 then
			sides = openSides(rooms, occupied, true) -- caps exhausted; relax rather than under-build
		end
		if #sides == 0 then
			break
		end
		attachRoom(rooms, occupied, sides[rng:NextInteger(1, #sides)], weightedModule(rng).id, rng)
	end
	addLoopConnections(rooms, rng)

	local entryRoomIndex = 1

	-- Brazier in the room farthest from entry that still has an open neighboring grid cell, so the
	-- Basin (safe room + descent) can always attach directly beyond it (DESIGN §18: the guaranteed
	-- dry route runs entry -> Brazier -> Basin). Scanning by distance and skipping any farthest
	-- candidate that turns out to be fully boxed in by other rooms' occupied cells prevents the
	-- Basin from silently landing on an unrelated room.
	local brazierRoomIndex = entryRoomIndex
	local basinSide: { roomIndex: number, direction: Types.Direction }? = nil
	local bestDistance = -1
	for index, room in rooms do
		local distance = gridDistance(rooms[entryRoomIndex], room)
		if distance > bestDistance then
			local candidateSide: { roomIndex: number, direction: Types.Direction }? = nil
			for _, side in openSides(rooms, occupied, true) do
				if side.roomIndex == index then
					candidateSide = side
					break
				end
			end
			if candidateSide ~= nil then
				bestDistance = distance
				brazierRoomIndex = index
				basinSide = candidateSide
			end
		end
	end
	if basinSide == nil then
		-- Every room is fully boxed in (pathological grid saturation) — fall back to any open
		-- side so the mandatory Basin still always gets built, even without brazier adjacency.
		local sides = openSides(rooms, occupied, true)
		basinSide = sides[rng:NextInteger(1, math.max(#sides, 1))]
	end
	local basinRoomIndex =
		attachRoom(rooms, occupied, basinSide :: { roomIndex: number, direction: Types.Direction }, "Basin", rng)
	-- Water may reward exploration but can never be the only route from spawn to the safe Basin.
	guaranteeDryRoute(rooms, entryRoomIndex, basinRoomIndex, rng)

	-- Threats: budgeted count, each in a random eligible room (never the entry or the Basin).
	local threatSpawns: { Types.ThreatSpawn } = {}
	local baseBudget = FloorsConfig.threatBudgetPerFloor[math.clamp(depth, 1, #FloorsConfig.threatBudgetPerFloor)]
	local budget = math.max(0, math.floor(baseBudget * math.max(threatBudgetMultiplier or 1, 0) + 0.5))
	local eligible: { number } = {}
	for index, room in rooms do
		local def = moduleById(room.moduleId)
		if
			index ~= entryRoomIndex
			and index ~= basinRoomIndex
			and def ~= nil
			and roomHasThreatAtDepth(def, depth, room.ceilingHeight)
		then
			table.insert(eligible, index)
		end
	end
	if #eligible > 0 then
		for _ = 1, budget do
			local roomIndex = eligible[rng:NextInteger(1, #eligible)]
			local def = moduleById(rooms[roomIndex].moduleId) :: Types.RoomModuleDef
			local threatId = weightedThreat(def.allowedThreats, depth, rooms[roomIndex].ceilingHeight, rng)
			if threatId ~= nil then
				table.insert(threatSpawns, {
					threatId = threatId,
					roomIndex = roomIndex,
					offset = Vector3.new(
						rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4),
						0,
						rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4)
					),
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
			local roomIndex = lootRoomIndices[rng:NextInteger(1, #lootRoomIndices)]
			table.insert(lootSpawns, {
				lootId = lootId,
				roomIndex = roomIndex,
				offset = plannedLootOffset(rooms[roomIndex], depth, rng),
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
			if hazardId == "Draft" then -- flooding is module-driven, never rolled
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
					and not blocksDoorway(room, depth, offset, size)
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
					local fallbackOffset = Vector3.new(
						xSign * terrain.groundPatchFallbackOffset,
						0,
						zSign * terrain.groundPatchFallbackOffset
					)
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
						and not blocksDoorway(room, depth, fallbackOffset, fallbackSize)
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

	local dripstones = planDripstones(
		depth,
		rooms,
		entryRoomIndex,
		basinRoomIndex,
		brazierRoomIndex,
		threatSpawns,
		hazards,
		groundPatches,
		rng
	)

	return {
		depth = depth,
		rooms = rooms,
		entryRoomIndex = entryRoomIndex,
		basinRoomIndex = basinRoomIndex,
		brazierRoomIndex = brazierRoomIndex,
		threatSpawns = threatSpawns,
		lootSpawns = lootSpawns,
		hazards = hazards,
		dripstones = dripstones,
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

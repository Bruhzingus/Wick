--!strict
-- Pure: converts a FloorPlan's reciprocal doorways into a small room graph and returns
-- doorway-centred movement waypoints. The Basin is deliberately excluded from that graph.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)

export type Navigation = {
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	neighbors: { [number]: { number } },
	basinNeighbors: { number },
	avoidanceByRoom: { [number]: { { center: Vector3, size: Vector3 } } },
}

local RoomNavigation = {}

local OFFSETS: { [Types.Direction]: { x: number, z: number } } = {
	N = { x = 0, z = -1 },
	S = { x = 0, z = 1 },
	E = { x = 1, z = 0 },
	W = { x = -1, z = 0 },
}

local OPPOSITE: { [Types.Direction]: Types.Direction } = {
	N = "S",
	S = "N",
	E = "W",
	W = "E",
}

local function cellKey(x: number, z: number): string
	return x .. "," .. z
end

local function hasDirection(doorways: { Types.Direction }, wanted: Types.Direction): boolean
	for _, direction in doorways do
		if direction == wanted then
			return true
		end
	end
	return false
end

local function appendUnique(values: { number }, value: number)
	for _, existing in values do
		if existing == value then
			return
		end
	end
	table.insert(values, value)
end

function RoomNavigation.build(plan: Types.FloorPlan, roomCenters: { Vector3 }): Navigation
	local indicesByCell: { [string]: number } = {}
	local neighbors: { [number]: { number } } = {}
	for index, room in plan.rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
		neighbors[index] = {}
	end

	local basinNeighbors: { number } = {}
	for index, room in plan.rooms do
		for _, direction in room.doorways do
			local offset = OFFSETS[direction]
			local neighborIndex = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighborIndex == nil then
				continue
			end
			local neighbor = plan.rooms[neighborIndex]
			if not hasDirection(neighbor.doorways, OPPOSITE[direction]) then
				continue
			end

			if index == plan.basinRoomIndex then
				if neighborIndex ~= plan.basinRoomIndex then
					appendUnique(basinNeighbors, neighborIndex)
				end
			elseif neighborIndex == plan.basinRoomIndex then
				appendUnique(basinNeighbors, index)
			else
				appendUnique(neighbors[index], neighborIndex)
			end
		end
	end

	local avoidanceByRoom: { [number]: { { center: Vector3, size: Vector3 } } } = {}
	for _, hazard in plan.hazards do
		if hazard.hazardId == "Water" and hazard.localOffset ~= nil and hazard.size ~= nil then
			local roomCenter = roomCenters[hazard.roomIndex]
			avoidanceByRoom[hazard.roomIndex] = avoidanceByRoom[hazard.roomIndex] or {}
			table.insert(avoidanceByRoom[hazard.roomIndex], {
				center = roomCenter + hazard.localOffset,
				size = hazard.size,
			})
		end
	end

	return {
		plan = plan,
		roomCenters = roomCenters,
		neighbors = neighbors,
		basinNeighbors = basinNeighbors,
		avoidanceByRoom = avoidanceByRoom,
	}
end

-- Returns the containing room on this navigation's floor. The vertical guard prevents rooms on
-- the stacked floors (which often share X/Z cells) from being mistaken for one another.
function RoomNavigation.roomAt(navigation: Navigation, position: Vector3): number?
	local halfCell = FloorsConfig.geometry.cellSize / 2
	local halfFloorGap = FloorsConfig.geometry.floorGap / 2
	for index, center in navigation.roomCenters do
		if
			math.abs(position.Y - center.Y) <= halfFloorGap
			and math.abs(position.X - center.X) <= halfCell
			and math.abs(position.Z - center.Z) <= halfCell
		then
			return index
		end
	end
	return nil
end

function RoomNavigation.isProtected(navigation: Navigation, position: Vector3): boolean
	return RoomNavigation.roomAt(navigation, position) == navigation.plan.basinRoomIndex
end

local function nearestOrdinaryRoom(navigation: Navigation, position: Vector3): number?
	local firstCenter = navigation.roomCenters[1]
	if firstCenter == nil or math.abs(position.Y - firstCenter.Y) > FloorsConfig.geometry.floorGap / 2 then
		return nil
	end

	local nearest: number? = nil
	local nearestDistance = math.huge
	for index, center in navigation.roomCenters do
		if index == navigation.plan.basinRoomIndex then
			continue
		end
		local deltaX = position.X - center.X
		local deltaZ = position.Z - center.Z
		local distance = deltaX * deltaX + deltaZ * deltaZ
		if distance < nearestDistance then
			nearest = index
			nearestDistance = distance
		end
	end
	return nearest
end

local function pathBetween(navigation: Navigation, startIndex: number, destinationIndex: number): { number }?
	if startIndex == destinationIndex then
		return { startIndex }
	end

	local queue: { number } = { startIndex }
	local head = 1
	local previous: { [number]: number } = {}
	local visited: { [number]: boolean } = { [startIndex] = true }

	while head <= #queue do
		local current = queue[head]
		head += 1
		for _, neighbor in navigation.neighbors[current] or {} do
			if visited[neighbor] then
				continue
			end
			visited[neighbor] = true
			previous[neighbor] = current
			if neighbor == destinationIndex then
				local path: { number } = { destinationIndex }
				local cursor = destinationIndex
				while cursor ~= startIndex do
					cursor = previous[cursor]
					table.insert(path, 1, cursor)
				end
				return path
			end
			table.insert(queue, neighbor)
		end
	end
	return nil
end

local function clampInsideRoom(navigation: Navigation, roomIndex: number, position: Vector3, clearance: number): Vector3
	local center = navigation.roomCenters[roomIndex]
	local interiorRadius = math.max(FloorsConfig.geometry.cellSize / 2 - clearance, 0)
	return Vector3.new(
		center.X + math.clamp(position.X - center.X, -interiorRadius, interiorRadius),
		center.Y,
		center.Z + math.clamp(position.Z - center.Z, -interiorRadius, interiorRadius)
	)
end

local function pointInsideXZ(point: Vector3, center: Vector3, size: Vector3, padding: number): boolean
	return math.abs(point.X - center.X) <= size.X / 2 + padding and math.abs(point.Z - center.Z) <= size.Z / 2 + padding
end

local function segmentIntersectsXZ(from: Vector3, to: Vector3, center: Vector3, size: Vector3, padding: number): boolean
	local halfX = size.X / 2 + padding
	local halfZ = size.Z / 2 + padding
	local minX, maxX = center.X - halfX, center.X + halfX
	local minZ, maxZ = center.Z - halfZ, center.Z + halfZ
	local delta = to - from
	local tMin, tMax = 0, 1

	local function clip(start: number, change: number, minimum: number, maximum: number): boolean
		if change == 0 then
			return start >= minimum and start <= maximum
		end
		local first = (minimum - start) / change
		local second = (maximum - start) / change
		if first > second then
			first, second = second, first
		end
		tMin = math.max(tMin, first)
		tMax = math.min(tMax, second)
		return tMin <= tMax
	end

	return clip(from.X, delta.X, minX, maxX) and clip(from.Z, delta.Z, minZ, maxZ)
end

local function routeAroundAvoidance(
	navigation: Navigation,
	roomIndex: number,
	position: Vector3,
	target: Vector3,
	clearance: number
): Vector3
	for _, region in navigation.avoidanceByRoom[roomIndex] or {} do
		local padding = clearance + FloorsConfig.geometry.wallThickness
		local cornerGap = FloorsConfig.geometry.wallThickness
		local halfX = region.size.X / 2 + padding + cornerGap
		local halfZ = region.size.Z / 2 + padding + cornerGap
		local candidates = {
			Vector3.new(region.center.X - halfX, target.Y, region.center.Z - halfZ),
			Vector3.new(region.center.X - halfX, target.Y, region.center.Z + halfZ),
			Vector3.new(region.center.X + halfX, target.Y, region.center.Z - halfZ),
			Vector3.new(region.center.X + halfX, target.Y, region.center.Z + halfZ),
		}

		if pointInsideXZ(position, region.center, region.size, padding) then
			local nearest = candidates[1]
			local nearestDistance = (nearest - position).Magnitude
			for _, candidate in candidates do
				local distance = (candidate - position).Magnitude
				if distance < nearestDistance then
					nearest = candidate
					nearestDistance = distance
				end
			end
			return nearest
		elseif pointInsideXZ(target, region.center, region.size, padding) then
			local nearest = candidates[1]
			local nearestDistance = (nearest - position).Magnitude
			for _, candidate in candidates do
				local distance = (candidate - position).Magnitude
				if distance < nearestDistance then
					nearest = candidate
					nearestDistance = distance
				end
			end
			target = nearest
		elseif segmentIntersectsXZ(position, target, region.center, region.size, padding) then
			local best: Vector3? = nil
			local bestDistance = math.huge
			for _, candidate in candidates do
				if not segmentIntersectsXZ(position, candidate, region.center, region.size, padding) then
					local distance = (candidate - position).Magnitude + (target - candidate).Magnitude
					if distance < bestDistance then
						best = candidate
						bestDistance = distance
					end
				end
			end
			if best ~= nil then
				target = best
			end
		end
	end
	return target
end

local function cardinalFromDelta(delta: Vector3): Types.Direction?
	if math.abs(delta.X) >= math.abs(delta.Z) then
		if delta.X > 0 then
			return "E"
		elseif delta.X < 0 then
			return "W"
		end
	else
		return if delta.Z > 0 then "S" else "N"
	end
	return nil
end

local function crossingWaypoint(navigation: Navigation, fromIndex: number, toIndex: number, clearance: number): Vector3
	local fromCenter = navigation.roomCenters[fromIndex]
	local toCenter = navigation.roomCenters[toIndex]
	local delta = Vector3.new(toCenter.X - fromCenter.X, 0, toCenter.Z - fromCenter.Z)
	if delta.Magnitude == 0 then
		return fromCenter
	end
	local direction = delta.Unit
	local crossingDistance = FloorsConfig.geometry.cellSize / 2 + clearance
	local base = fromCenter + direction * crossingDistance
	-- Aim at the doorway's real (off-centre) opening rather than the wall midpoint, so threats path
	-- straight through the gap instead of nosing into the solid wall beside an offset doorway.
	local fromRoom = navigation.plan.rooms[fromIndex]
	local cardinal = cardinalFromDelta(delta)
	if fromRoom ~= nil and cardinal ~= nil then
		-- Same seed source the builder cut the opening with: the canonical depth, not the ordinal.
		local profile = DoorwayGeometry.profile(fromRoom.gridX, fromRoom.gridZ, cardinal, navigation.plan.globalDepth)
		base += DoorwayGeometry.lateralAxis(cardinal) * profile.offset
	end
	return base
end

local function basinApproachWaypoint(navigation: Navigation, ordinaryRoomIndex: number, clearance: number): Vector3
	local ordinaryCenter = navigation.roomCenters[ordinaryRoomIndex]
	local basinCenter = navigation.roomCenters[navigation.plan.basinRoomIndex]
	local delta = Vector3.new(basinCenter.X - ordinaryCenter.X, 0, basinCenter.Z - ordinaryCenter.Z)
	if delta.Magnitude == 0 then
		return ordinaryCenter
	end
	local direction = delta.Unit
	local approachDistance = math.max(FloorsConfig.geometry.cellSize / 2 - clearance, 0)
	return ordinaryCenter + direction * approachDistance
end

local function closestReachableBasinNeighbor(navigation: Navigation, currentRoomIndex: number): (number?, { number }?)
	local closestNeighbor: number? = nil
	local closestPath: { number }? = nil
	for _, neighbor in navigation.basinNeighbors do
		local path = pathBetween(navigation, currentRoomIndex, neighbor)
		if path ~= nil and (closestPath == nil or #path < #closestPath) then
			closestNeighbor = neighbor
			closestPath = path
		end
	end
	return closestNeighbor, closestPath
end

-- Resolves a semantic brain target into the next physical target. Cross-room travel always aims
-- through a reciprocal doorway. A target in the Basin resolves to a stopping point on the
-- ordinary-room side of its doorway.
function RoomNavigation.nextWaypoint(
	navigation: Navigation,
	position: Vector3,
	targetPosition: Vector3,
	clearance: number
): Vector3
	local currentRoomIndex = RoomNavigation.roomAt(navigation, position)
	if currentRoomIndex == navigation.plan.basinRoomIndex then
		-- Defensive recovery for a pre-existing invalid state: leave by the closest Basin doorway.
		local neighbor = navigation.basinNeighbors[1]
		if neighbor == nil then
			return position
		end
		return crossingWaypoint(navigation, navigation.plan.basinRoomIndex, neighbor, clearance)
	end
	currentRoomIndex = currentRoomIndex or nearestOrdinaryRoom(navigation, position)
	if currentRoomIndex == nil then
		return position
	end

	local targetRoomIndex = RoomNavigation.roomAt(navigation, targetPosition)
	local targetIsProtected = targetRoomIndex == navigation.plan.basinRoomIndex
	if targetIsProtected then
		local basinNeighbor, path = closestReachableBasinNeighbor(navigation, currentRoomIndex)
		if basinNeighbor == nil or path == nil then
			local clamped = clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
			return routeAroundAvoidance(navigation, currentRoomIndex, position, clamped, clearance)
		end
		if currentRoomIndex == basinNeighbor then
			local approach = basinApproachWaypoint(navigation, basinNeighbor, clearance)
			return routeAroundAvoidance(navigation, currentRoomIndex, position, approach, clearance)
		end
		local crossing = crossingWaypoint(navigation, currentRoomIndex, path[2], clearance)
		return routeAroundAvoidance(navigation, currentRoomIndex, position, crossing, clearance)
	end

	targetRoomIndex = targetRoomIndex or nearestOrdinaryRoom(navigation, targetPosition)
	if targetRoomIndex == nil or targetRoomIndex == navigation.plan.basinRoomIndex then
		local clamped = clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
		return routeAroundAvoidance(navigation, currentRoomIndex, position, clamped, clearance)
	end
	if currentRoomIndex == targetRoomIndex then
		local clamped = clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
		return routeAroundAvoidance(navigation, currentRoomIndex, position, clamped, clearance)
	end

	local path = pathBetween(navigation, currentRoomIndex, targetRoomIndex)
	if path == nil or path[2] == nil then
		local clamped = clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
		return routeAroundAvoidance(navigation, currentRoomIndex, position, clamped, clearance)
	end
	local crossing = crossingWaypoint(navigation, currentRoomIndex, path[2], clearance)
	return routeAroundAvoidance(navigation, currentRoomIndex, position, crossing, clearance)
end

-- Final fail-closed guard: an outside threat cannot step into the Basin. A defensive recovery
-- path may keep moving an already-invalid threat toward the first ordinary doorway until it exits.
function RoomNavigation.constrainStep(
	navigation: Navigation,
	previousPosition: Vector3,
	nextPosition: Vector3,
	clearance: number
): Vector3
	if not RoomNavigation.isProtected(navigation, nextPosition) then
		return nextPosition
	end
	local previousRoomIndex = RoomNavigation.roomAt(navigation, previousPosition)
	if previousRoomIndex == navigation.plan.basinRoomIndex then
		local neighbor = navigation.basinNeighbors[1]
		if neighbor == nil then
			return previousPosition
		end
		local recoveryTarget = crossingWaypoint(navigation, navigation.plan.basinRoomIndex, neighbor, clearance)
		local recoveryDirection = recoveryTarget - previousPosition
		local attemptedDirection = nextPosition - previousPosition
		if recoveryDirection.Magnitude > 0 and attemptedDirection:Dot(recoveryDirection) > 0 then
			return nextPosition
		end
		return previousPosition
	end
	if previousRoomIndex == nil then
		return previousPosition
	end
	return clampInsideRoom(navigation, previousRoomIndex, nextPosition, clearance)
end

return RoomNavigation

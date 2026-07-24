--!strict
-- Pure: converts a FloorPlan's reciprocal doorways into a small room graph and returns
-- doorway-centred movement waypoints. The Basin is deliberately excluded from that graph.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)

export type Navigation = {
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	neighbors: { [number]: { number } },
	basinNeighbors: { number },
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

	return {
		plan = plan,
		roomCenters = roomCenters,
		neighbors = neighbors,
		basinNeighbors = basinNeighbors,
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

local function crossingWaypoint(navigation: Navigation, fromIndex: number, toIndex: number, clearance: number): Vector3
	local fromCenter = navigation.roomCenters[fromIndex]
	local toCenter = navigation.roomCenters[toIndex]
	local delta = Vector3.new(toCenter.X - fromCenter.X, 0, toCenter.Z - fromCenter.Z)
	if delta.Magnitude == 0 then
		return fromCenter
	end
	local direction = delta.Unit
	local crossingDistance = FloorsConfig.geometry.cellSize / 2 + clearance
	return fromCenter + direction * crossingDistance
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
			return clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
		end
		if currentRoomIndex == basinNeighbor then
			return basinApproachWaypoint(navigation, basinNeighbor, clearance)
		end
		return crossingWaypoint(navigation, currentRoomIndex, path[2], clearance)
	end

	targetRoomIndex = targetRoomIndex or nearestOrdinaryRoom(navigation, targetPosition)
	if targetRoomIndex == nil or targetRoomIndex == navigation.plan.basinRoomIndex then
		return clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
	end
	if currentRoomIndex == targetRoomIndex then
		return clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
	end

	local path = pathBetween(navigation, currentRoomIndex, targetRoomIndex)
	if path == nil or path[2] == nil then
		return clampInsideRoom(navigation, currentRoomIndex, targetPosition, clearance)
	end
	return crossingWaypoint(navigation, currentRoomIndex, path[2], clearance)
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

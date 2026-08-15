--!strict
-- Pure: converts a FloorPlan's reciprocal doorways into a small room graph and returns
-- doorway-centred movement waypoints.
--
-- EVERY ROOM IS ORDINARY. There is no protected room and no room a threat may not walk into — not the
-- Basin, not a sealed blast vault, not anything (owner decision). A reciprocal doorway is an edge, and
-- that is the whole rule.
--
-- This module used to carve the Basin out of the graph: it kept a separate `basinNeighbors` list, a
-- public `isProtected` query, an approach-waypoint that stopped a threat on the ordinary side of the
-- Basin's doorway, and a fail-closed `constrainStep` that refused any move into it. All of that is
-- gone. If a room should be dangerous or safe, that is now decided by what SPAWNS there (the planner's
-- threat budget) and by what a player does about what wanders in — never by a room a creature is
-- physically forbidden to enter.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)

export type Navigation = {
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	neighbors: { [number]: { number } },
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

	-- ONE RULE, NO EXCEPTIONS: a doorway both rooms agree on is an edge. The Basin and sealed blast
	-- vaults are ordinary rooms here like everything else.
	--
	-- A VAULT'S EDGE IS REAL EVEN WHILE ITS DOOR IS INTACT, and that is deliberate rather than an
	-- oversight. The door is a collidable, queryable part, so the wall raycast in `server/ThreatService`
	-- is what actually stops a body — the same thing that stops one walking through a boulder. Modelling
	-- the seal in the graph as well would mean a blown-open vault stayed unreachable until a rebuild.
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
			appendUnique(neighbors[index], neighborIndex)
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

-- The nearest room to a point that is not inside any room's cell — a body pushed into a wall seam, or
-- one whose ground sample drifted past a boundary. No room is skipped: there is no room a threat is
-- forbidden to be recovered into.
--
-- PUBLIC BECAUSE `roomAt` RETURNING NIL IS NOT A RARE CASE. A body standing in a doorway is outside
-- both cells it connects, which happens constantly, and anything that answers "what is under/over me"
-- has the same recovery problem the two pathing functions below do. The alternative every caller
-- reaches for otherwise is some remembered room, and a remembered room is unbounded: it can be the
-- far side of the floor, whereas this is always one of the cells the point is actually between.
function RoomNavigation.nearestRoom(navigation: Navigation, position: Vector3): number?
	local firstCenter = navigation.roomCenters[1]
	if firstCenter == nil or math.abs(position.Y - firstCenter.Y) > FloorsConfig.geometry.floorGap / 2 then
		return nil
	end

	local nearest: number? = nil
	local nearestDistance = math.huge
	for index, center in navigation.roomCenters do
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

-- Where an idle threat drifts next: a room connected to the one it is standing in, returned as
-- (index, centre). Backtracking into `cameFrom` is avoided while any other doorway exists, so a
-- roaming threat works its way through the floor instead of rattling between the same two rooms; a
-- dead end may still turn around.
--
-- ANY connected room is a legal destination, including the Basin and a blast vault. A roam that
-- carries something into the room a player thought was quiet is the point.
function RoomNavigation.roamDestination(
	navigation: Navigation,
	position: Vector3,
	cameFrom: number?,
	rng: Random
): (number?, Vector3?)
	local roomIndex = RoomNavigation.roomAt(navigation, position) or RoomNavigation.nearestRoom(navigation, position)
	if roomIndex == nil then
		return nil, nil
	end

	local options: { number } = {}
	local backtrack: number? = nil
	for _, neighbor in navigation.neighbors[roomIndex] or {} do
		if neighbor == cameFrom then
			backtrack = neighbor
		else
			table.insert(options, neighbor)
		end
	end

	local chosen = if #options > 0 then options[rng:NextInteger(1, #options)] else backtrack
	if chosen == nil then
		return nil, nil
	end
	local center = navigation.roomCenters[chosen]
	if center == nil then
		return nil, nil
	end
	return chosen, center
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
		-- Same seed source AND the same family the builder cut the opening with: the canonical depth,
		-- not the ordinal, and the plan's own family, because a family biases doorway width. Passing
		-- a different family here would aim threats at an opening the wrong size.
		local profile = DoorwayGeometry.profile(
			fromRoom.gridX,
			fromRoom.gridZ,
			cardinal,
			navigation.plan.globalDepth,
			navigation.plan.familyId
		)
		base += DoorwayGeometry.lateralAxis(cardinal) * profile.offset
	end
	return base
end

-- Resolves a semantic brain target into the next physical target. Cross-room travel always aims
-- through a reciprocal doorway.
--
-- EVERY ROOM IS A LEGAL DESTINATION. This used to carry a whole second path for a target inside the
-- Basin — find the nearest room adjacent to it, walk there, then stop short of its doorway — so that a
-- threat could be drawn toward the safe room and never arrive. That is gone: a target in the Basin
-- routes exactly like a target anywhere else.
function RoomNavigation.nextWaypoint(
	navigation: Navigation,
	position: Vector3,
	targetPosition: Vector3,
	clearance: number
): Vector3
	local currentRoomIndex = RoomNavigation.roomAt(navigation, position)
		or RoomNavigation.nearestRoom(navigation, position)
	if currentRoomIndex == nil then
		return position
	end

	local targetRoomIndex = RoomNavigation.roomAt(navigation, targetPosition)
		or RoomNavigation.nearestRoom(navigation, targetPosition)
	if targetRoomIndex == nil then
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

-- `constrainStep` USED TO LIVE HERE and has been deleted rather than left returning its input.
--
-- It was the fail-closed half of the Basin guarantee: whatever the brain decided and whatever the
-- waypoint resolver returned, a body was refused any step that would land it inside the safe room.
-- With no protected room left it could only ever have been the identity function, and a guard named
-- `constrainStep` that constrains nothing is worse than no guard at all — the next reader trusts it.
--
-- What still stops a body going somewhere it should not is physical and lives in
-- `server/ThreatService`: an obstacle raycast against real geometry, which is what already handles
-- boulders, columns and an intact blast door.

return RoomNavigation

--!strict
-- Pure vine-curtain rules: how many a floor wants, which doorways may carry one, and whether a
-- given flame is currently burning through. Planner, server and tests all read these, so the
-- "never the only way in" guarantee is one testable function rather than a builder convention.

local Types = require(script.Parent.Parent.Types)
local LightConfig = require(script.Parent.Parent.Config.Light)
local VinesConfig = require(script.Parent.Parent.Config.Vines)

local VineRules = {}

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

-- Burn rate the dial must reach, expressed against this candle's effective ceiling. A Basin
-- brightness sacrifice changes emitted light but never disables the maximum-brightness key.
function VineRules.requiredBurnRate(maxBurnRate: number?): number
	local ceiling = if maxBurnRate ~= nil and maxBurnRate == maxBurnRate
		then math.clamp(maxBurnRate, LightConfig.minBurnRate, LightConfig.maxBurnRate)
		else LightConfig.maxBurnRate
	return ceiling * VinesConfig.requiredBurnRateFraction
end

-- Is this flame burning the curtain right now? CUP is a near-dark ember and never qualifies,
-- whatever the dial says underneath it.
function VineRules.burnsVines(
	isLit: boolean,
	isCupping: boolean,
	burnRate: number,
	isFlaring: boolean,
	maxBurnRate: number?
): boolean
	if not isLit or isCupping then
		return false
	end
	if isFlaring and VinesConfig.flareBurns then
		return true
	end
	return burnRate >= VineRules.requiredBurnRate(maxBurnRate)
end

-- Does a curtain alight at `origin` throw fire to one at `other`? Curtains on the same floor are
-- the same growth: light one section and the fire runs along it. Spread never widens a floor's
-- guarantees (it only opens doorways that were already optional), so no reachability check here.
function VineRules.spreadsTo(origin: Vector3, other: Vector3): boolean
	local radius = VinesConfig.spreadRadius
	if radius <= 0 then
		return false
	end
	return (origin - other).Magnitude <= radius
end

function VineRules.targetCount(depth: number): number
	if not VinesConfig.enabled or depth < VinesConfig.minDepth then
		return 0
	end
	local counts = VinesConfig.perFloorByDepth
	if #counts == 0 then
		return 0
	end
	return math.max(0, counts[math.clamp(math.floor(depth), 1, #counts)])
end

export type Doorway = { roomIndex: number, direction: Types.Direction }

local function sealKey(roomIndex: number, direction: Types.Direction): string
	return roomIndex .. direction
end

-- THE guarantee: with every listed doorway treated as impassable, is every room on the floor still
-- reachable from the entry? Curtains are checked against the whole set, not one at a time — two
-- individually redundant doorways can still cut a room off together.
-- `exemptIndices` are rooms that are ALLOWED to end up unreachable — currently only a Locked Store,
-- whose whole purpose is to be sealed. Everything not listed must still be walkable from the entry.
--
-- The rule this function enforces is scoped to rooms that carry a player onward: the Brazier, the
-- Basin, the descent to the next floor, and every connector between them. A dead-end side room that
-- leads nowhere is not part of that guarantee, and `roomMayBeSealed` above is what proves a candidate
-- really is one before it is ever exempted here.
function VineRules.allRoomsReachable(
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	sealed: { Doorway },
	exemptIndices: { [number]: boolean }?
): boolean
	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end

	-- Each sealed opening is shared, so refuse it from either side.
	local blocked: { [string]: boolean } = {}
	for _, doorway in sealed do
		blocked[sealKey(doorway.roomIndex, doorway.direction)] = true
		local room = rooms[doorway.roomIndex]
		if room ~= nil then
			local offset = OFFSETS[doorway.direction]
			local neighbor = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighbor ~= nil then
				blocked[sealKey(neighbor, OPPOSITE[doorway.direction])] = true
			end
		end
	end

	-- How many rooms actually have to be reached. An exempt room is discounted from the requirement
	-- rather than pretended to be visited, so a store that happens to still be reachable by some other
	-- opening does not make the count disagree with itself.
	local required = #rooms
	if exemptIndices ~= nil then
		for index in exemptIndices do
			if rooms[index] ~= nil then
				required -= 1
			end
		end
	end

	local visited: { [number]: boolean } = { [entryRoomIndex] = true }
	local queue = { entryRoomIndex }
	local head = 1
	local reached = 1
	while head <= #queue do
		local index = queue[head]
		head += 1
		local room = rooms[index]
		for _, direction in room.doorways do
			if blocked[sealKey(index, direction)] then
				continue
			end
			local offset = OFFSETS[direction]
			local neighbor = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighbor ~= nil and not visited[neighbor] then
				visited[neighbor] = true
				if exemptIndices == nil or not exemptIndices[neighbor] then
					reached += 1
				end
				table.insert(queue, neighbor)
			end
		end
	end
	return reached >= required
end

-- MAY THIS ROOM BE SEALED OUTRIGHT? True only for a genuine DEAD END: a room with exactly one
-- doorway, which is not the entry, the Brazier, the Basin, or any other protected room.
--
-- The planner's ordinary rule is that a curtain must never be the only way into a room, and it exists
-- so that required content — the Brazier, the Basin, the descent to the next floor — can never end up
-- behind a costly exposure gate. The project owner scoped that rule to rooms
-- that carry a player ONWARD: a side room that leads nowhere may be sealed.
--
-- THE DEAD-END REQUIREMENT IS WHAT MAKES THAT SAFE STRUCTURALLY RATHER THAN BY ARGUMENT. A path
-- through a room must enter by one doorway and leave by another. With exactly one doorway there is no
-- second door to leave by, so:
--
--   * no route can pass through it, therefore it can never sit on the guaranteed entry -> Brazier ->
--     Basin route;
--   * sealing it cannot disconnect any other room, because nothing reaches anywhere else through it.
--
-- Neither property depends on which rooms happen to be where, so this cannot be broken by a future
-- change to room assembly. `protectedIndices` covers the rooms that must stay walkable regardless.
function VineRules.roomMayBeSealed(
	room: Types.RoomPlacement,
	roomIndex: number,
	protectedIndices: { [number]: boolean }
): boolean
	if protectedIndices[roomIndex] then
		return false
	end
	return #room.doorways == 1
end

-- Single-doorway convenience: sealing just this one leaves the floor fully connected.
function VineRules.doorwayIsRedundant(
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	roomIndex: number,
	direction: Types.Direction
): boolean
	return VineRules.allRoomsReachable(rooms, entryRoomIndex, { { roomIndex = roomIndex, direction = direction } })
end

return VineRules

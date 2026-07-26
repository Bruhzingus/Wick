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

-- Burn rate the dial must reach. Expressed against the configured ceiling, so a player whose
-- ceiling was lowered at the Basin can no longer reach it — which is exactly why a vined doorway
-- may never be a room's only entrance.
function VineRules.requiredBurnRate(): number
	return LightConfig.maxBurnRate * VinesConfig.requiredBurnRateFraction
end

-- Is this flame burning the curtain right now? CUP is a near-dark ember and never qualifies,
-- whatever the dial says underneath it.
function VineRules.burnsVines(isLit: boolean, isCupping: boolean, burnRate: number, isFlaring: boolean): boolean
	if not isLit or isCupping then
		return false
	end
	if isFlaring and VinesConfig.flareBurns then
		return true
	end
	return burnRate >= VineRules.requiredBurnRate()
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
function VineRules.allRoomsReachable(
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	sealed: { Doorway }
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
				reached += 1
				table.insert(queue, neighbor)
			end
		end
	end
	return reached == #rooms
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

--!strict
-- Pure: config + seed -> FloorPlan. Rooms are cells on a grid, attached one at a time to a random
-- open side of an existing room (respecting each module's connection cap). The builder receives
-- placements and doorways; it decides nothing.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local VinesConfig = require(script.Parent.Parent.Config.Vines)
local MiningConfig = require(script.Parent.Parent.Config.Mining)
local MiningRules = require(script.Parent.MiningRules)
local AshamedLurkerConfig = require(script.Parent.Parent.Config.AshamedLurker)
local StoneWardenConfig = require(script.Parent.Parent.Config.StoneWarden)
local AshamedLurkerRules = require(script.Parent.AshamedLurkerRules)
local DepthRules = require(script.Parent.DepthRules)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)
local DripstoneRules = require(script.Parent.DripstoneRules)
local GroundGeometry = require(script.Parent.GroundGeometry)
local RoofGeometry = require(script.Parent.RoofGeometry)
local VineRules = require(script.Parent.VineRules)
local PlacementReservations = require(script.Parent.PlacementReservations)

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

local function overlapsWater(
	hazards: { Types.HazardPlacement },
	roomIndex: number,
	offset: Vector3,
	footprint: Vector3
): boolean
	for _, hazard in hazards do
		if
			hazard.hazardId == "Water"
			and hazard.roomIndex == roomIndex
			and hazard.localOffset ~= nil
			and hazard.size ~= nil
		then
			if overlapsXZ(offset, footprint, hazard.localOffset, hazard.size, 0) then
				return true
			end
		end
	end
	return false
end

local function plannedLootOffset(
	room: Types.RoomPlacement,
	roomIndex: number,
	depth: number,
	hazards: { Types.HazardPlacement },
	reservations: { PlacementReservations.Reservation },
	rng: Random
): Vector3
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
		if
			fitsInsideRoom(offset, footprint)
			and not blocksDoorway(room, depth, offset, footprint)
			and not overlapsWater(hazards, roomIndex, offset, footprint)
			and not PlacementReservations.overlaps(
				reservations,
				roomIndex,
				offset,
				LootConfig.placementFootprint / 2,
				FloorsConfig.terrain.gameplaySpawnSeparation
			)
		then
			return offset
		end
	end

	-- Deep corner insets stay outside ordinary doorway lanes and away from a room's central pool.
	local fallback = halfCell - LootConfig.wallInsetMax
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local offset = Vector3.new(fallback * xSign, 0, fallback * zSign)
			if
				not overlapsWater(hazards, roomIndex, offset, footprint)
				and not PlacementReservations.overlaps(
					reservations,
					roomIndex,
					offset,
					LootConfig.placementFootprint / 2,
					FloorsConfig.terrain.gameplaySpawnSeparation
				)
			then
				return offset
			end
		end
	end
	-- A pool that reaches every peripheral shelf is malformed relative to room-module constraints.
	-- Keep the result deterministic and let the built-world ground probe still prevent Terrain embed.
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

-- A dry floor never even considers a flooded module, so water is decided once per floor rather than
-- accumulating room by room (see FloorsConfig.floodedFloorChance).
local function weightedModule(rng: Random, allowWater: boolean): Types.RoomModuleDef
	local totalWeight = 0
	for _, def in FloorsConfig.roomModules do
		if def.weight > 0 and (allowWater or def.waterDepth == nil) then
			totalWeight += def.weight
		end
	end
	local roll = rng:NextNumber() * totalWeight
	local last = FloorsConfig.roomModules[1]
	for _, def in FloorsConfig.roomModules do
		if def.weight <= 0 or (not allowWater and def.waterDepth ~= nil) then
			continue
		end
		last = def
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end
	return last
end

local function weightedDryModule(connectionCount: number, rng: Random): Types.RoomModuleDef
	local eligible: { Types.RoomModuleDef } = {}
	local totalWeight = 0
	for _, def in FloorsConfig.roomModules do
		if def.weight > 0 and def.waterDepth == nil and def.connections >= connectionCount then
			table.insert(eligible, def)
			totalWeight += def.weight
		end
	end
	if #eligible == 0 then
		for _, def in FloorsConfig.roomModules do
			if def.weight > 0 and def.waterDepth == nil then
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

local function weightedWaterModule(connectionCount: number, rng: Random): Types.RoomModuleDef?
	local eligible: { Types.RoomModuleDef } = {}
	local totalWeight = 0
	for _, def in FloorsConfig.roomModules do
		if def.waterDepth ~= nil and def.connections >= connectionCount then
			table.insert(eligible, def)
			totalWeight += def.weight
		end
	end
	if #eligible == 0 or totalWeight <= 0 then
		return nil
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

-- Water settles into the room's own natural recesses. The cave floor already rolls by several studs,
-- so this samples that exact height field (including the room's planned rock swells) and picks its
-- lowest valid dip instead of punching a bowl through flat ground.
--
-- Two properties come out of anchoring to the terrain rather than to the room centre:
--   * The bed is never RAISED above the natural floor, so the carve only flattens the bottom of a
--     dip that is already there; it can never form a crater or a plateau.
--   * The waterline is pinned to the bed, not to the room's base plane, so wading depth is exactly
--     the module's declared depth however deep the recess happens to be. `minimumFreeboard` keeps
--     that waterline below the base plane, which is what keeps the plaza and door lanes dry.
--
-- Flooded rooms are never the entry, Basin, or Brazier room (the first two are excluded outright and
-- the third always sits on the guaranteed dry route), so the field is built with the same
-- non-open footprint and empty flat-spot list the builder will use.
local function planWaterPool(
	room: Types.RoomPlacement,
	depth: number,
	waterDepth: number,
	swells: { GroundGeometry.Swell },
	rng: Random
): (Vector3, Vector3, number)
	local pool = HazardsConfig.waterPool
	local field = GroundGeometry.fieldFor(room, depth, false, {}, swells, {})

	local diameter = rng:NextNumber(pool.minSize, pool.maxSize)
	local size = Vector3.new(
		diameter * rng:NextNumber(1 - pool.aspectJitter, 1 + pool.aspectJitter),
		waterDepth,
		diameter * rng:NextNumber(1 - pool.aspectJitter, 1 + pool.aspectJitter)
	)

	type Candidate = { offset: Vector3, height: number }
	local candidates: { Candidate } = {}
	local limit = FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.wallClearance - pool.minSize / 2
	local step = math.max(pool.basinSearchStep, 1)
	local x = -limit
	while x <= limit do
		local z = -limit
		while z <= limit do
			table.insert(candidates, { offset = Vector3.new(x, 0, z), height = GroundGeometry.offset(field, x, z) })
			z += step
		end
		x += step
	end
	-- Deepest first, with a positional tiebreak so equal heights (the flat plaza and door lanes are
	-- all exactly zero) never leave the plan depending on table.sort's ordering of equal elements.
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		if a.height ~= b.height then
			return a.height < b.height
		end
		if a.offset.X ~= b.offset.X then
			return a.offset.X < b.offset.X
		end
		return a.offset.Z < b.offset.Z
	end)

	for index, candidate in candidates do
		if index > pool.basinCandidateLimit then
			break
		end
		if fitsInsideRoom(candidate.offset, size) and not blocksDoorway(room, depth, candidate.offset, size) then
			return candidate.offset, size, math.max(waterDepth + pool.minimumFreeboard, -candidate.height)
		end
	end

	-- Every recess sat across a doorway approach. The flat centre pad is the one place no door lane
	-- reaches, so a minimum pool goes there rather than dropping the floor's water entirely.
	return Vector3.zero, Vector3.new(pool.minSize, waterDepth, pool.minSize), waterDepth + pool.minimumFreeboard
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
	rng: Random,
	dripstoneMultiplier: number?
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
					depth = hazard.bedDepth :: number,
				},
			}
		end
	end

	local candidateRooms: { number } = {}
	local ordinaryRoomCount = 0
	local groundFields: { [number]: GroundGeometry.Field } = {}
	local roofFields: { [number]: RoofGeometry.Field } = {}
	for roomIndex, room in rooms do
		if
			roomIndex == entryRoomIndex
			or roomIndex == basinRoomIndex
			or roomIndex == brazierRoomIndex
			or room.moduleId == StoneWardenConfig.roomModuleId
		then
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

	-- Per-room cap by internal depth band rather than by literal floor numbers, so the boundaries
	-- live in Config/Depth with every other depth rule.
	local band = DepthRules.getDepthBand(depth)
	local maxPerRoom = if band == "Introduction"
		then config.maxPerRoomEarly
		elseif band == "Standard" then config.maxPerRoomMid
		else config.maxPerRoomDeep
	local maxHazardousRooms = math.max(1, math.floor(ordinaryRoomCount * config.maxHazardousRoomFraction))
	local harmlessPerRoom = FloorsConfig.caveDressing.ceilingFormationsPerRoom
		+ FloorsConfig.caveDressing.ceilingBouldersPerRoom
	local harmlessCount = #rooms * harmlessPerRoom
	local harmlessCap = math.floor(harmlessCount * config.maxUnstableToHarmlessRatio)
	local depthScaled = DripstoneRules.targetCount(depth) * DepthRules.getHazardBudgetMultiplier(depth)
	local scaledTarget = math.floor(depthScaled * math.max(dripstoneMultiplier or 1, 0) + 0.5)
	local target = math.min(scaledTarget, maxHazardousRooms * maxPerRoom, harmlessCap)
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

local function roomConnectionCap(room: Types.RoomPlacement): number
	local def = moduleById(room.moduleId)
	return if def ~= nil then def.connections else 2
end

-- All (roomIndex, direction) pairs where a new room could attach.
local function openSides(
	rooms: { Types.RoomPlacement },
	occupied: { [string]: boolean },
	ignoreConnectionCap: boolean
): { { roomIndex: number, direction: Types.Direction } }
	local sides: { { roomIndex: number, direction: Types.Direction } } = {}
	for index, room in rooms do
		local cap = roomConnectionCap(room)
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

local function sideFoldsBesideExistingRoom(
	rooms: { Types.RoomPlacement },
	occupied: { [string]: boolean },
	side: { roomIndex: number, direction: Types.Direction }
): boolean
	local parent = rooms[side.roomIndex]
	local offset = OFFSETS[side.direction]
	local targetX = parent.gridX + offset.x
	local targetZ = parent.gridZ + offset.z
	for _, direction in DIRECTIONS do
		local neighborOffset = OFFSETS[direction]
		local neighborX = targetX + neighborOffset.x
		local neighborZ = targetZ + neighborOffset.z
		if neighborX == parent.gridX and neighborZ == parent.gridZ then
			continue
		end
		if occupied[cellKey(neighborX, neighborZ)] then
			return true
		end
	end
	return false
end

-- Prefer a readable main chain, but fold it toward occupied cells often enough that the loop pass
-- has real alternate edges to open. Both preferences are probabilistic, so silhouettes still vary.
local function chooseAttachmentSide(
	rooms: { Types.RoomPlacement },
	occupied: { [string]: boolean },
	sides: { { roomIndex: number, direction: Types.Direction } },
	rng: Random
): { roomIndex: number, direction: Types.Direction }
	local candidates = sides
	if rng:NextNumber() < FloorsConfig.loopSeekingChance then
		local folding: { { roomIndex: number, direction: Types.Direction } } = {}
		for _, side in sides do
			if sideFoldsBesideExistingRoom(rooms, occupied, side) then
				table.insert(folding, side)
			end
		end
		if #folding > 0 then
			candidates = folding
		end
	end
	if rng:NextNumber() < FloorsConfig.linearContinuationChance then
		local newest: { { roomIndex: number, direction: Types.Direction } } = {}
		for _, side in candidates do
			if side.roomIndex == #rooms then
				table.insert(newest, side)
			end
		end
		if #newest > 0 then
			candidates = newest
		end
	end
	return candidates[rng:NextInteger(1, #candidates)]
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
	local candidates: { { roomIndex: number, neighborIndex: number, direction: Types.Direction } } = {}
	for roomIndex, room in rooms do
		for _, direction: Types.Direction in { "E", "S" } do
			local offset = OFFSETS[direction]
			local neighborIndex = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighborIndex == nil or hasDirection(room.doorways, direction) then
				continue
			end
			table.insert(candidates, {
				roomIndex = roomIndex,
				neighborIndex = neighborIndex,
				direction = direction,
			})
		end
	end
	for index = #candidates, 2, -1 do
		local other = rng:NextInteger(1, index)
		candidates[index], candidates[other] = candidates[other], candidates[index]
	end
	local added = 0
	for _, candidate in candidates do
		local room = rooms[candidate.roomIndex]
		local neighbor = rooms[candidate.neighborIndex]
		if
			#room.doorways < roomConnectionCap(room)
			and #neighbor.doorways < roomConnectionCap(neighbor)
			and (added < FloorsConfig.minimumLoopConnections or rng:NextNumber() < FloorsConfig.loopConnectionChance)
		then
			table.insert(room.doorways, candidate.direction)
			table.insert(neighbor.doorways, OPPOSITE[candidate.direction])
			added += 1
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

-- Water is budgeted per FLOOR, not per room. Extra flooded modules are converted back to dry, and
-- if a wet floor lost every pool it rolled to the guaranteed dry route, one off-route room is
-- flooded instead — so Config/Floors.floodedFloorChance is the rate that actually ships rather than
-- an upper bound. The guaranteed entry -> Basin path is never touched here.
local function enforceFloodedBudget(
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	floodedFloor: boolean,
	rng: Random
)
	local budget = if floodedFloor then math.max(FloorsConfig.floodedRoomsPerFloor, 0) else 0

	local flooded: { number } = {}
	for index, room in rooms do
		local def = moduleById(room.moduleId)
		if def ~= nil and def.waterDepth ~= nil then
			table.insert(flooded, index)
		end
	end
	shuffle(flooded, rng)
	for position = budget + 1, #flooded do
		local room = rooms[flooded[position]]
		room.moduleId = weightedDryModule(#room.doorways, rng).id
	end
	if #flooded >= budget then
		return
	end

	local onRoute: { [number]: boolean } = {}
	for _, index in pathBetween(rooms, entryRoomIndex, basinRoomIndex) do
		onRoute[index] = true
	end
	local candidates: { number } = {}
	for index in rooms do
		if
			not onRoute[index]
			and index ~= entryRoomIndex
			and index ~= basinRoomIndex
			and rooms[index].moduleId ~= StoneWardenConfig.roomModuleId
		then
			table.insert(candidates, index)
		end
	end
	shuffle(candidates, rng)

	local placed = #flooded
	for _, index in candidates do
		if placed >= budget then
			break
		end
		local room = rooms[index]
		-- A four-door crossing has no flooded module wide enough; skip it rather than drop doorways.
		local def = weightedWaterModule(#room.doorways, rng)
		if def ~= nil then
			room.moduleId = def.id
			placed += 1
		end
	end
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

-- Vine curtains: deep-floor doorways that only a candle pushed to the top of its dial opens. A
-- doorway qualifies only when sealing it (together with every curtain already placed) leaves the
-- whole floor reachable from the entry, and never when it sits on the guaranteed entry -> Basin
-- route. Someone whose dial was capped at the Basin therefore loses shortcuts, never access.
local function planVines(
	depth: number,
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	rng: Random
): { Types.VinePlacement }
	local target = VineRules.targetCount(depth)
	if target <= 0 then
		return {}
	end

	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end

	local routeEdges: { [string]: boolean } = {}
	local route = pathBetween(rooms, entryRoomIndex, basinRoomIndex)
	for step = 1, #route - 1 do
		local a, b = route[step], route[step + 1]
		routeEdges[a .. ">" .. b] = true
		routeEdges[b .. ">" .. a] = true
	end

	-- One entry per shared opening, recorded from its lower-indexed room.
	local candidates: { VineRules.Doorway } = {}
	for index, room in rooms do
		for _, direction in room.doorways do
			local offset = OFFSETS[direction]
			local neighbor = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if
				neighbor == nil
				or neighbor < index
				or index == basinRoomIndex
				or neighbor == basinRoomIndex
				or room.moduleId == StoneWardenConfig.roomModuleId
				or rooms[neighbor].moduleId == StoneWardenConfig.roomModuleId
				or routeEdges[index .. ">" .. neighbor]
			then
				continue
			end
			table.insert(candidates, { roomIndex = index, direction = direction })
		end
	end

	local order: { number } = {}
	for index in candidates do
		table.insert(order, index)
	end
	shuffle(order, rng)

	local placements: { Types.VinePlacement } = {}
	local sealed: { VineRules.Doorway } = {}
	for _, candidateIndex in order do
		if #placements >= target then
			break
		end
		if rng:NextNumber() >= VinesConfig.chancePerEligibleDoorway then
			continue
		end
		local candidate = candidates[candidateIndex]
		table.insert(sealed, candidate)
		if VineRules.allRoomsReachable(rooms, entryRoomIndex, sealed) then
			table.insert(placements, {
				roomIndex = candidate.roomIndex,
				direction = candidate.direction,
				visualSeed = rng:NextInteger(1, 2_000_000_000),
			})
		else
			table.remove(sealed)
		end
	end
	return placements
end

-- Ashamed Lurkers: deep-floor arch creatures. An arch qualifies only when its deterministic
-- doorway profile leaves a real walking lane beside the trapped half (Rules.isPlacementAllowed),
-- when neither side is a protected room, and when no vine curtain already seals it — a curtain and
-- a creature in the same opening would make one route depend on the other.
--
-- Every creature reserves several arches: one to start in, the rest to reappear in after a player
-- shames it off the first. Sites are never shared, so two creatures can never end up in one opening.
-- A floor that cannot find enough qualifying arches simply carries fewer creatures; the size and
-- clear-lane rules are never relaxed to reach a count.
local function planLurkers(
	depth: number,
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	vines: { Types.VinePlacement },
	rng: Random
): { Types.LurkerPlacement }
	local target = AshamedLurkerRules.targetCount(depth)
	if target <= 0 then
		return {}
	end

	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end

	local vined: { [string]: boolean } = {}
	for _, vine in vines do
		vined[vine.roomIndex .. vine.direction] = true
		local room = rooms[vine.roomIndex]
		local offset = OFFSETS[vine.direction]
		local neighbor = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
		if neighbor ~= nil then
			vined[neighbor .. OPPOSITE[vine.direction]] = true
		end
	end

	local function isProtected(index: number): boolean
		return index == entryRoomIndex
			or index == basinRoomIndex
			or index == brazierRoomIndex
			or rooms[index].moduleId == StoneWardenConfig.roomModuleId
	end

	-- One entry per shared opening, recorded from its lower-indexed room.
	local candidates: { Types.LurkerSite } = {}
	for index, room in rooms do
		if isProtected(index) then
			continue
		end
		for _, direction in room.doorways do
			local offset = OFFSETS[direction]
			local neighbor = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighbor == nil or neighbor < index or isProtected(neighbor) or vined[index .. direction] then
				continue
			end
			local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, depth)
			if not AshamedLurkerRules.isPlacementAllowed(profile.width, profile.height) then
				continue
			end
			table.insert(candidates, {
				roomIndex = index,
				direction = direction,
				trapSide = if rng:NextNumber() < 0.5 then "Left" else "Right",
			})
		end
	end

	local order: { number } = {}
	for index in candidates do
		table.insert(order, index)
	end
	shuffle(order, rng)

	local placements: { Types.LurkerPlacement } = {}
	local cursor = 1
	while #placements < target and cursor <= #order do
		local site = candidates[order[cursor]]
		cursor += 1
		if rng:NextNumber() >= AshamedLurkerConfig.chancePerEligibleDoorway then
			continue
		end
		-- Take this arch plus the next few unclaimed ones as its relocation set.
		local sites: { Types.LurkerSite } = { site }
		while #sites < AshamedLurkerConfig.sitesPerLurker and cursor <= #order do
			table.insert(sites, candidates[order[cursor]])
			cursor += 1
		end
		table.insert(placements, {
			sites = sites,
			visualSeed = rng:NextInteger(1, 2_000_000_000),
		})
	end
	return placements
end

-- Raw Wax deposits (PHASE 6). Zero or one per floor, and the placement rules are all refusals:
--
--   * NEVER the entry, Basin, or Brazier room, and never a room on the guaranteed entry -> Brazier
--     -> Basin route. Mining is a detour a player chooses to take, so a deposit may not sit
--     anywhere the floor already requires them to walk.
--   * NEVER inside or beside water, an unstable formation, a vine curtain's doorway, or a threat's
--     own spawn point. A player committed to a swing is standing still at half speed; the spot
--     itself must not be the thing that kills them.
--   * NEVER blocking a doorway lane, and always with dry standing room in front of the seam.
--
-- A floor that cannot satisfy all of that simply carries no deposit. The count is reduced; the
-- safety rules are never relaxed to reach it.
local function planDeposits(
	depth: number,
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	threatSpawns: { Types.ThreatSpawn },
	hazards: { Types.HazardPlacement },
	dripstones: { Types.DripstonePlacement },
	vines: { Types.VinePlacement },
	rng: Random
): { Types.DepositPlacement }
	local target = MiningRules.targetCount(depth, rng:NextNumber())
	if target <= 0 then
		return {}
	end
	local placement = MiningConfig.placement

	-- Both legs of the mandatory route are excluded, not just the rooms at their ends.
	local onRoute: { [number]: boolean } = {}
	for _, index in pathBetween(rooms, entryRoomIndex, brazierRoomIndex) do
		onRoute[index] = true
	end
	for _, index in pathBetween(rooms, brazierRoomIndex, basinRoomIndex) do
		onRoute[index] = true
	end

	-- A vined doorway already gates its room behind a loud, expensive commitment. Putting the one
	-- deposit behind one would stack two deliberate detours into a single decision and make the
	-- read on either of them impossible.
	local vinedRooms: { [number]: boolean } = {}
	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end
	for _, vine in vines do
		vinedRooms[vine.roomIndex] = true
		local room = rooms[vine.roomIndex]
		local offset = OFFSETS[vine.direction]
		local neighbor = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
		if neighbor ~= nil then
			vinedRooms[neighbor] = true
		end
	end

	local candidateRooms: { number } = {}
	for index in rooms do
		if
			not onRoute[index]
			and not vinedRooms[index]
			and index ~= entryRoomIndex
			and index ~= basinRoomIndex
			and rooms[index].moduleId ~= StoneWardenConfig.roomModuleId
		then
			table.insert(candidateRooms, index)
		end
	end
	shuffle(candidateRooms, rng)
	if #candidateRooms == 0 then
		return {}
	end

	local halfCell = FloorsConfig.geometry.cellSize / 2
	-- The reserved footprint is the seam PLUS the dry ground a player has to stand on to work it,
	-- so a deposit is never placed where the interaction itself would put someone in a pool.
	local reserved = placement.footprint + placement.standingClearance
	local footprint = Vector3.new(reserved, 0, reserved)

	local function tryPlace(roomIndex: number): Types.DepositPlacement?
		local room = rooms[roomIndex]
		for _ = 1, placement.placementAttempts do
			local side = DIRECTIONS[rng:NextInteger(1, #DIRECTIONS)]
			local normal = OFFSETS[side]
			local wallDistance = halfCell - rng:NextNumber(placement.wallInsetMin, placement.wallInsetMax)
			local lateral = rng:NextNumber(-placement.wallLateralRange, placement.wallLateralRange)
			local offset = Vector3.new(
				normal.x * wallDistance + math.abs(normal.z) * lateral,
				0,
				normal.z * wallDistance + math.abs(normal.x) * lateral
			)
			if
				not fitsInsideRoom(offset, footprint)
				or blocksDoorway(room, depth, offset, footprint)
				or overlapsWater(hazards, roomIndex, offset, footprint)
			then
				continue
			end
			-- Explicit separation from anything that can hurt someone standing still. Checked
			-- against the planned positions rather than the built world, so the guarantee holds
			-- before a single Instance exists and is reproducible in a cold test.
			local clear = true
			for _, formation in dripstones do
				if formation.roomIndex == roomIndex then
					local delta = formation.localOffset - offset
					if Vector3.new(delta.X, 0, delta.Z).Magnitude < placement.minHazardSeparation then
						clear = false
						break
					end
				end
			end
			if not clear then
				continue
			end
			for _, spawn in threatSpawns do
				if spawn.roomIndex == roomIndex then
					local delta = spawn.offset - offset
					if Vector3.new(delta.X, 0, delta.Z).Magnitude < placement.minThreatSeparation then
						clear = false
						break
					end
				end
			end
			if not clear then
				continue
			end
			return {
				roomIndex = roomIndex,
				localOffset = offset,
				visualSeed = rng:NextInteger(1, 2_000_000_000),
			}
		end
		return nil
	end

	local placements: { Types.DepositPlacement } = {}
	for _, roomIndex in candidateRooms do
		if #placements >= target then
			break
		end
		local placed = tryPlace(roomIndex)
		if placed ~= nil then
			table.insert(placements, placed)
		end
	end
	return placements
end

-- One floor. `globalDepth` is the canonical difficulty depth and drives every content curve and
-- every deterministic geometry seed; `localFloor` is only this expedition's ordinal (world stacking,
-- floor keys, "Floor 3" on screen) and defaults to the global depth for a run that starts at 1.
export type PlanRequest = {
	globalDepth: number,
	localFloor: number?,
	rng: Random,
	threatBudgetMultiplier: number?,
	dripstoneMultiplier: number?,
}

function FloorPlanner.plan(request: PlanRequest): Types.FloorPlan
	-- Fail loudly. An unsupported depth must never silently fall back to shallow-floor content.
	DepthRules.assertSupportedDepth(request.globalDepth, "FloorPlanner.plan")
	local depth = request.globalDepth
	local localFloor = request.localFloor or depth
	if not DepthRules.isValidFloorNumber(localFloor) then
		error("FloorPlanner.plan: invalid localFloor " .. tostring(localFloor), 2)
	end
	local rng = request.rng
	local threatBudgetMultiplier = request.threatBudgetMultiplier
	local dripstoneMultiplier = request.dripstoneMultiplier

	local roomCount = DepthRules.getRoomCountTarget(depth)
	local rooms: { Types.RoomPlacement } = {}
	local occupied: { [string]: boolean } = {}

	-- One roll decides whether this whole floor is wet. Most floors are dry stone and never consider
	-- a flooded module at all, so meeting water is an event rather than scenery.
	local floodedFloor = rng:NextNumber() < FloorsConfig.floodedFloorChance

	local first = weightedModule(rng, floodedFloor)
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
		local side = chooseAttachmentSide(rooms, occupied, sides, rng)
		attachRoom(rooms, occupied, side, weightedModule(rng, floodedFloor).id, rng)
	end

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

	-- The Warden is a rare optional branch, never a surprise object dropped into arbitrary terrain.
	-- Its room still uses normal cave generation; only its three encounter footprints are protected.
	local warden: Types.WardenPlacement? = nil
	if
		StoneWardenConfig.enabled
		and depth >= StoneWardenConfig.minGlobalDepth
		and rng:NextNumber() < StoneWardenConfig.spawnChancePerEligibleFloor
	then
		local encounterSides: { { roomIndex: number, direction: Types.Direction } } = {}
		for _, side in openSides(rooms, occupied, true) do
			if
				side.roomIndex ~= entryRoomIndex
				and side.roomIndex ~= basinRoomIndex
				and side.roomIndex ~= brazierRoomIndex
			then
				table.insert(encounterSides, side)
			end
		end
		if #encounterSides == 0 then
			encounterSides = openSides(rooms, occupied, true)
		end
		if #encounterSides > 0 then
			local side = encounterSides[rng:NextInteger(1, #encounterSides)]
			local roomIndex = attachRoom(rooms, occupied, side, StoneWardenConfig.roomModuleId, rng)
			rooms[roomIndex].ceilingHeight = StoneWardenConfig.roomCeilingHeight
			warden = {
				roomIndex = roomIndex,
				pileOffset = StoneWardenConfig.pileOffset,
				relicOffset = StoneWardenConfig.relicOffset,
				counterDripstoneOffset = StoneWardenConfig.counterDripstoneOffset,
				visualSeed = rng:NextInteger(1, 2_000_000_000),
			}
		end
	end
	-- Open loops after the Basin exists so an adjacent Basin cell can become a genuine second way
	-- down instead of every floor ending in a mandatory leaf.
	addLoopConnections(rooms, rng)
	-- Water may reward exploration but can never be the only route from spawn to the safe Basin.
	guaranteeDryRoute(rooms, entryRoomIndex, basinRoomIndex, rng)
	-- Then hold the floor to its pool budget: the dry route can convert away every pool the assembly
	-- rolled, and a lucky assembly can roll far more than a floor should carry.
	enforceFloodedBudget(rooms, entryRoomIndex, basinRoomIndex, floodedFloor, rng)

	-- Gameplay footprints are reserved before cosmetic dressing is rolled. The Warden room owns
	-- three large clear pads; threats and loot add their own reservations below.
	local reservations: { PlacementReservations.Reservation } = {}
	if warden ~= nil then
		for _, offset in { warden.pileOffset, warden.relicOffset, warden.counterDripstoneOffset } do
			PlacementReservations.add(
				reservations,
				warden.roomIndex,
				offset,
				StoneWardenConfig.encounterClearance,
				"Warden"
			)
		end
	end

	-- Threats are planned after water below, so their spawn points cannot land in a pool.
	local threatSpawns: { Types.ThreatSpawn } = {}

	-- Broad rock swells are real walkable ground, not visual clutter. Every room receives
	-- attempted elevation, including the entry and Basin; their central interaction areas stay
	-- clear. Door approaches and other shelves retain safe walking gaps.
	--
	-- These are planned BEFORE water now: water settles into whatever recesses the finished rolling
	-- ground leaves behind, so it has to read a height field that already contains the swells.
	local groundPatches: { Types.GroundPatch } = {}
	local terrain = FloorsConfig.terrain
	for roomIndex, room in rooms do
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
				local overlapsSpecialCenter = (roomIndex == entryRoomIndex or roomIndex == basinRoomIndex)
					and overlapsXZ(
						offset,
						size,
						Vector3.zero,
						Vector3.new(terrain.specialRoomCenterClearance * 2, 0, terrain.specialRoomCenterClearance * 2),
						0
					)
				if
					not overlapsSpecialCenter
					and PlacementReservations.overlaps(reservations, roomIndex, offset, math.max(size.X, size.Z) / 2)
				then
					overlapsSpecialCenter = true
				end
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
					if
						fitsInsideRoom(fallbackOffset, fallbackSize)
						and not blocksDoorway(room, depth, fallbackOffset, fallbackSize)
						and not PlacementReservations.overlaps(
							reservations,
							roomIndex,
							fallbackOffset,
							math.max(fallbackSize.X, fallbackSize.Z) / 2
						)
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

	-- Water: one localized pool per flooded module, settled into that room's deepest natural recess
	-- (see planWaterPool). Reads the finished swells, so the pool lands in a dip the rolling ground
	-- actually left rather than in a bowl punched through it.
	local swellsByRoom: { [number]: { GroundGeometry.Swell } } = {}
	for _, patch in groundPatches do
		local list = swellsByRoom[patch.roomIndex]
		if list == nil then
			list = {}
			swellsByRoom[patch.roomIndex] = list
		end
		table.insert(list, {
			x = patch.localOffset.X,
			z = patch.localOffset.Z,
			radius = math.max(patch.size.X, patch.size.Z) / 2,
			height = patch.size.Y,
		})
	end

	local hazards: { Types.HazardPlacement } = {}
	for index, room in rooms do
		if index == entryRoomIndex or index == basinRoomIndex then
			continue
		end
		local def = moduleById(room.moduleId)
		if def == nil or def.waterDepth == nil then
			continue
		end
		local offset, size, bedDepth = planWaterPool(room, depth, def.waterDepth, swellsByRoom[index] or {}, rng)
		table.insert(hazards, {
			hazardId = "Water",
			roomIndex = index,
			waterDepth = def.waterDepth,
			bedDepth = bedDepth,
			localOffset = offset,
			size = size,
		})
	end

	-- Spread threats through distinct eligible rooms before reusing one. Every accepted footprint is
	-- dry, inside the navigable room, out of doorway lanes, and separated from earlier gameplay.
	local baseBudget = FloorsConfig.threatBudgetPerFloor[math.clamp(depth, 1, #FloorsConfig.threatBudgetPerFloor)]
		* DepthRules.getThreatBudgetMultiplier(depth)
	local budget = math.max(0, math.floor(baseBudget * math.max(threatBudgetMultiplier or 1, 0) + 0.5))
	local eligible: { number } = {}
	for index, room in rooms do
		local def = moduleById(room.moduleId)
		if
			index ~= entryRoomIndex
			and index ~= basinRoomIndex
			and (warden == nil or index ~= warden.roomIndex)
			and def ~= nil
			and roomHasThreatAtDepth(def, depth, room.ceilingHeight)
		then
			table.insert(eligible, index)
		end
	end
	shuffle(eligible, rng)
	local threatFootprint =
		Vector3.new(FloorsConfig.terrain.gameplaySpawnRadius * 2, 0, FloorsConfig.terrain.gameplaySpawnRadius * 2)
	for spawnIndex = 1, budget do
		if #eligible == 0 then
			break
		end
		local roomIndex = eligible[(spawnIndex - 1) % #eligible + 1]
		if spawnIndex > #eligible and (spawnIndex - 1) % #eligible == 0 then
			shuffle(eligible, rng)
			roomIndex = eligible[1]
		end
		local room = rooms[roomIndex]
		local def = moduleById(room.moduleId) :: Types.RoomModuleDef
		local threatId = weightedThreat(def.allowedThreats, depth, room.ceilingHeight, rng)
		if threatId == nil then
			continue
		end
		for _ = 1, 32 do
			local offset = Vector3.new(
				rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4),
				0,
				rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4)
			)
			if
				fitsInsideRoom(offset, threatFootprint)
				and not blocksDoorway(room, depth, offset, threatFootprint)
				and not overlapsWater(hazards, roomIndex, offset, threatFootprint)
				and not PlacementReservations.overlaps(
					reservations,
					roomIndex,
					offset,
					FloorsConfig.terrain.gameplaySpawnRadius,
					FloorsConfig.terrain.gameplaySpawnSeparation
				)
			then
				table.insert(threatSpawns, {
					threatId = threatId,
					roomIndex = roomIndex,
					offset = offset,
				})
				PlacementReservations.add(
					reservations,
					roomIndex,
					offset,
					FloorsConfig.terrain.gameplaySpawnRadius,
					"Threat"
				)
				break
			end
		end
	end

	-- Loot is planned only after the final pool layout exists. Earlier planning let a wall-pocket
	-- roll survive even when the same room later carved water through that shelf.
	local lootSpawns: { Types.LootSpawn } = {}
	local lootRoomIndices: { number } = {}
	for index in rooms do
		if index ~= entryRoomIndex and index ~= basinRoomIndex and (warden == nil or index ~= warden.roomIndex) then
			table.insert(lootRoomIndices, index)
		end
	end
	shuffle(lootRoomIndices, rng)
	local lootCount = LootConfig.spawnsPerFloor[math.clamp(depth, 1, #LootConfig.spawnsPerFloor)]
	if #lootRoomIndices > 0 then
		for _ = 1, lootCount do
			local lootId = weightedLoot(depth, rng)
			if lootId == nil then
				break
			end
			local roomIndex = lootRoomIndices[(_ - 1) % #lootRoomIndices + 1]
			local offset = plannedLootOffset(rooms[roomIndex], roomIndex, depth, hazards, reservations, rng)
			table.insert(lootSpawns, {
				lootId = lootId,
				roomIndex = roomIndex,
				offset = offset,
			})
			PlacementReservations.add(reservations, roomIndex, offset, LootConfig.placementFootprint / 2, "Loot")
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
		rng,
		dripstoneMultiplier
	)
	if warden ~= nil then
		table.insert(dripstones, {
			roomIndex = warden.roomIndex,
			localOffset = warden.counterDripstoneOffset,
			variantId = StoneWardenConfig.counterDripstoneVariantId,
			visualSeed = warden.visualSeed,
		})
	end

	local vines = planVines(depth, rooms, entryRoomIndex, basinRoomIndex, rng)

	-- Deposits are planned LAST, so every hazard, threat, and curtain they have to avoid already
	-- exists in the plan. Nothing placed after this can land on top of one.
	local lurkers = planLurkers(depth, rooms, entryRoomIndex, basinRoomIndex, brazierRoomIndex, vines, rng)
	local deposits = planDeposits(
		depth,
		rooms,
		entryRoomIndex,
		basinRoomIndex,
		brazierRoomIndex,
		threatSpawns,
		hazards,
		dripstones,
		vines,
		rng
	)

	return {
		depth = localFloor,
		globalDepth = depth,
		rooms = rooms,
		entryRoomIndex = entryRoomIndex,
		basinRoomIndex = basinRoomIndex,
		brazierRoomIndex = brazierRoomIndex,
		threatSpawns = threatSpawns,
		lootSpawns = lootSpawns,
		hazards = hazards,
		dripstones = dripstones,
		vines = vines,
		lurkers = lurkers,
		warden = warden,
		deposits = deposits,
		groundPatches = groundPatches,
	}
end

-- A finite floor batch for tests and tooling. Each floor gets its OWN seed derived from
-- (run seed, cave tier, global depth), so a floor is reproducible on its own and two different
-- global depths never share a derived stream. Live expeditions call `plan` on demand and are not
-- capped by this helper's batch size.
function FloorPlanner.planAll(
	seed: number,
	floorCount: number?,
	threatBudgetMultiplier: number?,
	dripstoneMultiplier: number?,
	startDepth: number?,
	tierId: number?
): { Types.FloorPlan }
	local start = startDepth or 1
	DepthRules.assertSupportedDepth(start, "FloorPlanner.planAll")
	local requested = floorCount or FloorsConfig.planningBatchSize
	local plannedCount = DepthRules.planningBatchCount(start, math.max(requested, 1))
	local plans: { Types.FloorPlan } = {}
	for localFloor = 1, plannedCount do
		local globalDepth = DepthRules.getGlobalDepth(start, localFloor)
		table.insert(
			plans,
			FloorPlanner.plan({
				globalDepth = globalDepth,
				localFloor = localFloor,
				rng = Random.new(DepthRules.getFloorSeed(seed, tierId or 0, globalDepth)),
				threatBudgetMultiplier = threatBudgetMultiplier,
				dripstoneMultiplier = dripstoneMultiplier,
			})
		)
	end
	return plans
end

return FloorPlanner

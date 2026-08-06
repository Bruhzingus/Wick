--!strict
-- Pure: config + seed -> FloorPlan. Rooms are cells on a grid, attached one at a time to a random
-- open side of an existing room (respecting each module's connection cap). The builder receives
-- placements and doorways; it decides nothing.
--
-- CAVE FAMILIES. Every difficulty curve, topology bias, ecology weight, environmental probability and
-- room footprint on a floor is resolved from ONE cave-family profile (Config/CaveFamilies via
-- Logic/CaveFamilyRules). There is deliberately no `if familyId == ...` anywhere in this file: the
-- planner asks for resolved numbers and never learns which cave it is building.
--
-- BUILD ORDER, and why it is this order. Each step depends on every step above it:
--
--   1. resolve the cave profile
--   2. assemble the room graph and the required rooms
--   3. place doorway anchors (implicit in the graph: an edge IS an anchor)
--   4. plan the guaranteed dry route
--   5. plan protected masks and spawn candidates
--   6. roll each ordinary room's outer footprint
--   7. validate containment and connectedness, falling back to Rectangle
--   8. union the protected masks over the shape
--   9. everything downstream (ground, water, threats, loot, hazards, curtains, seams) is validated
--      against that final open footprint rather than against the room cell
--
-- Presentation dressing happens only after all of that, in the builder.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local VinesConfig = require(script.Parent.Parent.Config.Vines)
local MiningConfig = require(script.Parent.Parent.Config.Mining)
local MossFireConfig = require(script.Parent.Parent.Config.MossFire)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)
local LootRules = require(script.Parent.LootRules)
local MiningRules = require(script.Parent.MiningRules)
local MossFireRules = require(script.Parent.MossFireRules)
local AshamedLurkerConfig = require(script.Parent.Parent.Config.AshamedLurker)
local StoneWardenConfig = require(script.Parent.Parent.Config.StoneWarden)
local AshamedLurkerRules = require(script.Parent.AshamedLurkerRules)
local CaveFamilyRules = require(script.Parent.CaveFamilyRules)
local DepthRules = require(script.Parent.DepthRules)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)
local DripstoneRules = require(script.Parent.DripstoneRules)
local EchoGateRules = require(script.Parent.EchoGateRules)
local GroundGeometry = require(script.Parent.GroundGeometry)
local OreRules = require(script.Parent.OreRules)
local RoofGeometry = require(script.Parent.RoofGeometry)
local RoomFootprint = require(script.Parent.RoomFootprint)
local ThreatRules = require(script.Parent.ThreatRules)
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

local function blocksDoorway(
	room: Types.RoomPlacement,
	depth: number,
	familyId: string?,
	offset: Vector3,
	size: Vector3
): boolean
	local geometry = FloorsConfig.geometry
	local terrain = FloorsConfig.terrain
	local halfCell = geometry.cellSize / 2
	for _, direction in room.doorways do
		local normal = OFFSETS[direction]
		local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, depth, familyId)
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

-- Does this gameplay footprint sit inside the room's OPEN AIR? Two independent checks, and both
-- must pass: the old cell-radius bound (nothing may reach the structural wall) and, once shapes
-- exist, the room's final open footprint (nothing may end up inside the rock a shape leaves behind).
--
-- `mask` is nil only for callers that run before shapes are rolled, where the cell bound is the whole
-- room by definition.
local function fitsInsideRoom(mask: RoomFootprint.OpenMask?, offset: Vector3, size: Vector3): boolean
	local terrain = FloorsConfig.terrain
	local radius = FloorsConfig.geometry.cellSize / 2 - terrain.wallClearance
	if math.abs(offset.X) + size.X / 2 > radius or math.abs(offset.Z) + size.Z / 2 > radius then
		return false
	end
	if mask == nil then
		return true
	end
	return RoomFootprint.containsBox(mask, offset, size)
end

-- Terrain is voxelized after planning. Expand anything that must sit on that Terrain by one
-- configured voxel margin before testing the analytic room boundary; this keeps its final sampled
-- footprint away from the eroded side-wall band and naturally pulls accepted placements inward.
local function surfaceSafeFootprint(size: Vector3): Vector3
	local margin = FloorsConfig.geometry.placementProbe.horizontalMarginStuds
	return Vector3.new(size.X + margin * 2, size.Y, size.Z + margin * 2)
end

-- Walk a rolled offset toward the room centre until its footprint sits in open air, or give up.
--
-- WHY THIS EXISTS. Placement rolls are authored against the room CELL — "somewhere in the outer
-- third", "against a wall", "off-centre". In a shaped room a chunk of the cell is rock, so a
-- perfectly good bearing can land inside it. Discarding those rolls would mean shaped families
-- silently carried fewer threats and fewer seams than the budgets they were given, which is a
-- balance change disguised as a geometry change. Pulling the same bearing inward keeps the roll's
-- INTENT (its direction and its relationship to the room's edge) and lands it on the room's real
-- boundary instead of the cell's.
--
-- It never relaxes anything: the caller still applies every safety refusal to whatever comes back,
-- and a bearing that cannot be resolved is refused outright. Converges in bounded steps because the
-- navigation hub at the centre is open air in every room by construction.
local function anchorInside(mask: RoomFootprint.OpenMask?, offset: Vector3, size: Vector3): Vector3?
	if fitsInsideRoom(mask, offset, size) then
		return offset
	end
	if mask == nil then
		return nil
	end
	local candidate = offset
	for _ = 1, 5 do
		candidate = candidate * 0.86
		if fitsInsideRoom(mask, candidate, size) then
			return candidate
		end
	end
	return nil
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
	familyId: string,
	mask: RoomFootprint.OpenMask?,
	hazards: { Types.HazardPlacement },
	reservations: { PlacementReservations.Reservation },
	rng: Random
): Vector3
	local halfCell = FloorsConfig.geometry.cellSize / 2
	local footprint = surfaceSafeFootprint(Vector3.new(LootConfig.placementFootprint, 0, LootConfig.placementFootprint))
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
			fitsInsideRoom(mask, offset, footprint)
			and not blocksDoorway(room, depth, familyId, offset, footprint)
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

	-- Deep corner insets stay outside ordinary doorway lanes and away from a room's central pool. A
	-- shaped room may have rock in its corners, so the fallback is now also checked against the open
	-- footprint rather than assumed reachable.
	local fallback = halfCell - LootConfig.wallInsetMax
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			local offset = Vector3.new(fallback * xSign, 0, fallback * zSign)
			if
				fitsInsideRoom(mask, offset, footprint)
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
	end

	-- THE PERIPHERAL RING SWEEP. Every random pocket and every corner has been refused, which in a
	-- shaped room mostly means "those particular bearings are rock", not "this room has no shelves".
	--
	-- The old code answered that by walking its last corner straight in toward the origin, so the
	-- harder a room was to place in the closer to dead centre its item ended up — and the hardest
	-- rooms returned the origin outright. This sweeps EVERY bearing at the outer radius before it
	-- gives up a single stud of it, and stops conceding ground entirely at `minimumCenterDistance`.
	-- Bearings are derived from the ring index rather than drawn from `rng`, so a room that needs
	-- twelve probes and one that needs one consume the same seeded stream.
	local outerRadius = halfCell - LootConfig.wallInsetMin
	local innerRadius = math.min(outerRadius, LootConfig.minimumCenterDistance)
	local rings = math.max(1, math.floor(LootConfig.fallbackRings))
	local samples = math.max(1, math.floor(LootConfig.fallbackRingSamples))
	-- Two passes over the same rings. The first honours every other gameplay footprint on the floor;
	-- the second drops only the mutual-separation rule, because an item standing a little close to
	-- another item is a far better outcome than an item in the middle of the room.
	for _, respectReservations in { true, false } do
		for ring = 0, rings - 1 do
			local radius = if rings == 1
				then outerRadius
				else outerRadius + (innerRadius - outerRadius) * (ring / (rings - 1))
			-- Offset each ring's start bearing by half a step of the ring above it, so the rings
			-- interleave instead of stacking every candidate along the same twelve spokes.
			local startAngle = ring * math.pi / samples
			for step = 0, samples - 1 do
				local angle = startAngle + step * math.pi * 2 / samples
				local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				if
					fitsInsideRoom(mask, offset, footprint)
					and not blocksDoorway(room, depth, familyId, offset, footprint)
					and not overlapsWater(hazards, roomIndex, offset, footprint)
					and (
						not respectReservations
						or not PlacementReservations.overlaps(
							reservations,
							roomIndex,
							offset,
							LootConfig.placementFootprint / 2,
							FloorsConfig.terrain.gameplaySpawnSeparation
						)
					)
				then
					return offset
				end
			end
		end
	end

	-- Forty-eight peripheral shelves in two passes all came back solid. The room's own navigation hub
	-- is open air in every footprint by construction, so this is the one placement that cannot fail —
	-- and it is why a pickup can look badly placed but can never end up inside or under the map.
	return Vector3.zero
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

-- Can this room's ceiling host this row at all? Only roof-bound rows have an opinion; everything that
-- walks the floor is welcome under any roof the generator rolls.
local function roomAllowsRoofRow(def: Types.ThreatDef, ceilingHeight: number): boolean
	local roof = ThreatRules.roofProfile(def)
	return roof == nil or ceilingHeight <= roof.maximumCeilingHeight
end

-- A threat's rolled weight in THIS cave family. Two family levers, both acting on the existing
-- authored row rather than replacing it:
--
--   * the introduction shift samples the row's own spawn-weight table as though the floor were
--     deeper, which is how a family brings an existing threat forward a floor or two;
--   * the weight multiplier scales the result, which is how a family changes the MIX.
--
-- Neither touches a stat, a state, or any AI rule. A family decides which of the existing roster a
-- floor draws and nothing else.
local function threatWeight(
	family: CaveFamilyRules.CaveFamilyProfile,
	def: Types.ThreatDef,
	depth: number,
	ceilingHeight: number,
	tallness: number
): number
	-- Any roof-bound row is refused outright by a room whose ceiling is above its cap: the physical
	-- tell has to stay inside candle range. Asked of ThreatRules so both roof profiles are covered.
	local roof = ThreatRules.roofProfile(def)
	if roof ~= nil and ceilingHeight > roof.maximumCeilingHeight then
		return 0
	end
	local sampleDepth = CaveFamilyRules.threatDepthIndex(family, def.id, depth)
	return weightAtDepth(def.spawnWeightByDepth, sampleDepth)
		* heightBias(def, tallness)
		* CaveFamilyRules.threatWeightMultiplier(family, def.id)
end

local function weightedThreat(
	family: CaveFamilyRules.CaveFamilyProfile,
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
			totalWeight += threatWeight(family, def, depth, ceilingHeight, tallness)
		end
	end
	if totalWeight <= 0 then
		return nil
	end

	local roll = rng:NextNumber() * totalWeight
	for _, threatId in allowedThreats do
		local def = ThreatsConfig.definitions[threatId]
		if def ~= nil then
			roll -= threatWeight(family, def, depth, ceilingHeight, tallness)
			if roll <= 0 then
				return threatId
			end
		end
	end
	return nil
end

local function roomHasThreatAtDepth(
	family: CaveFamilyRules.CaveFamilyProfile,
	def: Types.RoomModuleDef,
	depth: number,
	ceilingHeight: number
): boolean
	for _, threatId in def.allowedThreats do
		local threatDef = ThreatsConfig.definitions[threatId]
		if
			threatDef ~= nil
			and weightAtDepth(threatDef.spawnWeightByDepth, CaveFamilyRules.threatDepthIndex(family, threatId, depth)) > 0
			and CaveFamilyRules.threatWeightMultiplier(family, threatId) > 0
			and roomAllowsRoofRow(threatDef, ceilingHeight)
		then
			return true
		end
	end
	return false
end

-- Which pickup this slot draws. A row's family/depth gate (Config/Loot.minDepthByFamily) is checked
-- BEFORE its weight rather than folded into one, so a deep-cave item is genuinely absent from a
-- shallow floor instead of merely improbable on one.
local function weightedLoot(depth: number, familyId: string, rng: Random): Types.LootId?
	-- Rows with no weight at this depth are dropped from the pool entirely rather than left in it at
	-- zero. `rng:NextNumber()` can return exactly 0, and a leading zero-weight row would then satisfy
	-- `roll <= 0` and be selected — a row the config said was unavailable here.
	local ids: { Types.LootId } = {}
	local totalWeight = 0
	for lootId, def in LootConfig.definitions do
		local weight = weightAtDepth(def.spawnWeightByDepth, depth)
		if weight > 0 and LootRules.isAvailable(def, familyId, depth) then
			table.insert(ids, lootId)
			totalWeight += weight
		end
	end
	if totalWeight <= 0 then
		return nil
	end
	table.sort(ids)

	local roll = rng:NextNumber() * totalWeight
	for _, lootId in ids do
		roll -= weightAtDepth(LootConfig.definitions[lootId].spawnWeightByDepth, depth)
		if roll <= 0 then
			return lootId
		end
	end
	return ids[#ids]
end

-- How many pickups this floor plans. Rolled from the depth's band, so a shallow floor can honestly
-- have none and a deep one reliably has a few (Config/Loot.spawnsPerFloor).
local function rolledLootCount(depth: number, rng: Random): number
	local bands = LootConfig.spawnsPerFloor
	if #bands == 0 then
		return 0
	end
	local band = bands[math.clamp(depth, 1, #bands)]
	local minimum = math.max(0, math.floor(band.minimum))
	local maximum = math.max(minimum, math.floor(band.maximum))
	return rng:NextInteger(minimum, maximum)
end

-- WHICH FORMATION THIS FAMILY'S CEILING HANGS. The authored weights in Config/Hazards are scaled by
-- the family's own (Logic/CaveFamilyRules.dripstoneVariantWeightMultiplier), so Ice hangs needles,
-- long spires and its Splintered Lance while Moss hangs forks, heavy crowns and its Sodden Mass —
-- the same object, the same warning language, genuinely different behaviour at the tip.
local function weightedDripstoneVariant(family: CaveFamilyRules.CaveFamilyProfile, rng: Random)
	return DripstoneRules.selectVariant(family, rng:NextNumber())
end

local function shuffle(indices: { number }, rng: Random)
	for index = #indices, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		indices[index], indices[swapIndex] = indices[swapIndex], indices[index]
	end
end

-- Excludes rooms holding a threat that extinguishes on contact with no window to react (DESIGN §9:
-- unavoidable extinguish stacked under falling stone is double jeopardy). Asks the shared predicate
-- rather than naming a row, so the rule follows the roster instead of a list of ids.
--
-- A SUSTAINED-CONTACT ROW IS DELIBERATELY NOT PROTECTED. The cave moth can now put a candle out, but
-- only after seconds of contact a player can run, dim, or decoy their way out of; a room is
-- protected for threats there is no answer to, and protecting every moth room would clear the
-- hazard off most of the floor.
local function roomHasCeilingThreat(threatSpawns: { Types.ThreatSpawn }, roomIndex: number): boolean
	for _, spawn in threatSpawns do
		if spawn.roomIndex == roomIndex then
			local def = ThreatsConfig.definitions[spawn.threatId]
			if def ~= nil and ThreatRules.snuffsWithoutWarning(def) then
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
	familyId: string,
	mask: RoomFootprint.OpenMask?,
	waterDepth: number,
	swells: { GroundGeometry.Swell },
	rng: Random
): (Vector3, Vector3, number)
	local pool = HazardsConfig.waterPool
	local field = GroundGeometry.fieldFor(room, depth, false, {}, swells, {}, familyId)

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

	local function accepts(candidate: { offset: Vector3, height: number }): boolean
		return fitsInsideRoom(mask, candidate.offset, size)
			and not blocksDoorway(room, depth, familyId, candidate.offset, size)
	end

	-- First choice: the DEEPEST valid recess, from the shortlist. This is what makes a pool read as
	-- water that settled where the ground already dipped.
	for index, candidate in candidates do
		if index > pool.basinCandidateLimit then
			break
		end
		if accepts(candidate) then
			return candidate.offset, size, math.max(waterDepth + pool.minimumFreeboard, -candidate.height)
		end
	end

	-- SECOND CHOICE: any valid spot at all, still deepest-first. In a shaped room a large share of the
	-- cell is rock, so the deepest few recesses can easily all be inside it — and before this pass
	-- existed, that dropped the pool onto the room's centre pad, which is the one place it must never
	-- go: the navigation hub is where threats, spawns and every inward-anchored placement converge.
	-- Scanning the rest is cheap and keeps the pool in a real dip.
	for index, candidate in candidates do
		if index > pool.basinCandidateLimit and accepts(candidate) then
			return candidate.offset, size, math.max(waterDepth + pool.minimumFreeboard, -candidate.height)
		end
	end

	-- The room genuinely has nowhere to put one. Carrying no pool is correct: this floor's water
	-- budget is spent elsewhere or not at all, and the room stays dry rather than having a puddle
	-- forced into its only walkable ground.
	return Vector3.zero, Vector3.zero, 0
end

local function planDripstones(
	family: CaveFamilyRules.CaveFamilyProfile,
	depth: number,
	rooms: { Types.RoomPlacement },
	masks: { [number]: RoomFootprint.OpenMask },
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
		-- READABILITY, measured at the TIP rather than at the roof. A room qualifies when SOME authored
		-- variant could bring a tip down into the readable band; which variant it actually gets is
		-- checked again per placement below. A tall chamber is therefore excluded only when nothing in
		-- the whole pool could reach that band, instead of being excluded for being tall — which is
		-- what used to leave the tallest cave family with the fewest falling hazards in the game.
		if
			room.ceilingHeight <= DripstoneRules.maxReachableRoofHeight(family)
			and not roomHasCeilingThreat(threatSpawns, roomIndex)
		then
			table.insert(candidateRooms, roomIndex)
			groundFields[roomIndex] = GroundGeometry.fieldFor(
				room,
				depth,
				false,
				{},
				swellsByRoom[roomIndex] or {},
				poolsByRoom[roomIndex] or {},
				family.id
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
	-- How WIDELY hazards may be spread, also by band. Deeper floors put them in more rooms rather than
	-- only stacking more into the same ones: "more of them, further apart" reads as a more dangerous
	-- cave, where "more of them in one place" reads as one bad room you learn to avoid.
	local authoredFraction = if band == "Introduction"
		then config.hazardousRoomFractionEarly
		elseif band == "Standard" then config.hazardousRoomFractionMid
		else config.hazardousRoomFractionDeep
	local hazardousRoomFraction = CaveFamilyRules.hazardousRoomFraction(family, depth, authoredFraction)
	-- Clamped to leave at least one ordinary room with nothing overhead, however deep the floor and
	-- however hazardous the cave. A floor with no safe ground is a corridor with a timer.
	local maxHazardousRooms =
		math.clamp(math.floor(ordinaryRoomCount * hazardousRoomFraction), 1, math.max(1, ordinaryRoomCount - 1))
	local harmlessPerRoom = FloorsConfig.caveDressing.ceilingFormationsPerRoom
		+ FloorsConfig.caveDressing.ceilingBouldersPerRoom
	local harmlessCount = #rooms * harmlessPerRoom
	local harmlessCap = math.floor(harmlessCount * config.maxUnstableToHarmlessRatio)
	-- Two independent scalings, and neither is allowed to stand in for the other: the DEPTH extension
	-- (Logic/DepthRules) grows the authored curve past the hand-authored floors, and the FAMILY
	-- multiplier (base x band x this family's own formation factor) is how Moss and Ice pull away from
	-- Stone. The planner's own caps below still bind above both.
	local depthScaled = DripstoneRules.targetCount(depth) * DepthRules.getHazardBudgetMultiplier(depth)
	local scaledTarget = math.floor(depthScaled * CaveFamilyRules.hazardBudgetMultiplier(family, depth) + 0.5)
	local target = math.min(scaledTarget, maxHazardousRooms * maxPerRoom, harmlessCap)
	if target <= 0 then
		return {}
	end

	local placements: { Types.DripstonePlacement } = {}
	local placementsByRoom: { [number]: number } = {}
	local hazardousRoomCount = 0

	local function tryPlace(roomIndex: number): boolean
		local room = rooms[roomIndex]
		local groundField = groundFields[roomIndex]
		local roofField = roofFields[roomIndex]
		if groundField == nil or roofField == nil then
			return false
		end
		for _ = 1, config.placementAttempts do
			-- THE VARIANT IS ROLLED PER ATTEMPT, not once per room, and that is what lets a tall
			-- chamber carry a hazard at all. The readable-tip check below refuses a short needle under
			-- a high roof; rolling once per room meant a tall room that happened to draw a needle
			-- burned all its attempts on a shape that could never fit and came away empty. Rolling per
			-- attempt keeps the authored weights intact while letting the room's own height select for
			-- the reach it needs — which is why long spires end up in exactly the vaults that want one.
			local variant = weightedDripstoneVariant(family, rng)
			if variant == nil then
				return false
			end
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = rng:NextNumber(config.minCenterOffset, config.maxCenterOffset)
			local offset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			-- TWO DIFFERENT FOOTPRINTS, because they answer two different questions, and conflating
			-- them was quietly costing every deep floor most of its falling hazards.
			--
			-- The DOORWAY test keeps the full padded halo: a formation must not drop anywhere near a
			-- lane somebody is walking through, and that padding is the safety rule.
			--
			-- The CONTAINMENT test only needs the disc that actually hurts. Requiring the padded halo to
			-- fit inside the room as well meant a formation could never sit further than about sixteen
			-- studs from the room centre — so the outer half of every room was unusable, only two or
			-- three fitted per room however large the budget was, and past roughly floor eight every
			-- cave family saturated at the same count no matter how much more hazard it was carrying.
			-- Nothing is relaxed by separating them: the lane guarantee is unchanged, and formations
			-- can now hang against the walls, which is where they belong.
			local safetyRadius = variant.triggerRadius + config.doorwaySafetyPadding
			local doorwayFootprint = Vector3.new(safetyRadius * 2, 0, safetyRadius * 2)
			local triggerFootprint = Vector3.new(variant.triggerRadius * 2, 0, variant.triggerRadius * 2)
			if
				not fitsInsideRoom(masks[roomIndex], offset, triggerFootprint)
				or blocksDoorway(room, depth, family.id, offset, doorwayFootprint)
			then
				continue
			end
			if overlapsRoomHazard(hazards, roomIndex, offset, variant.triggerRadius) then
				continue
			end
			local groundHeight = GroundGeometry.offset(groundField, offset.X, offset.Z)
			local localRoofHeight =
				RoofGeometry.undersideHeight(room.ceilingHeight, roofField, groundHeight, offset.X, offset.Z)
			-- The readable-tip rule, now against the variant that was actually rolled and the exact
			-- local roof it would hang from. A short needle under a tall ripple is refused here even
			-- though its room qualified; a long spire under the same ripple is accepted.
			if not DripstoneRules.isReadableTip(localRoofHeight - groundHeight, variant) then
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
	family: CaveFamilyRules.CaveFamilyProfile,
	rooms: { Types.RoomPlacement },
	occupied: { [string]: boolean },
	sides: { { roomIndex: number, direction: Types.Direction } },
	rng: Random
): { roomIndex: number, direction: Types.Direction }
	local candidates = sides
	if rng:NextNumber() < CaveFamilyRules.loopSeekingChance(family) then
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
	if rng:NextNumber() < CaveFamilyRules.linearContinuationChance(family) then
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

-- Wide per-room ceiling height (planned): a full-range roll pulled toward this family's preferred
-- band. This is what the threat weighting reads to place moths high and flies low, and it is why
-- Ice reads as a system of halls and Moss as a warren without either losing the other's extremes.
local function rollCeiling(family: CaveFamilyRules.CaveFamilyProfile, rng: Random): number
	return CaveFamilyRules.rollCeilingHeight(family, rng)
end

local function attachRoom(
	family: CaveFamilyRules.CaveFamilyProfile,
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
		ceilingHeight = rollCeiling(family, rng),
		-- Provisional. Every room's real footprint is rolled once the graph, the loop edges and the
		-- Echo Lock are all final (see `plan`), because a shape has to be validated against the
		-- doorways it will actually have.
		footprint = RoomFootprint.rectangle(),
	}
	table.insert(parent.doorways, side.direction)
	table.insert(rooms, placement)
	occupied[cellKey(placement.gridX, placement.gridZ)] = true
	return #rooms
end

local function gridDistance(a: Types.RoomPlacement, b: Types.RoomPlacement): number
	return math.abs(a.gridX - b.gridX) + math.abs(a.gridZ - b.gridZ)
end

local function addLoopConnections(
	family: CaveFamilyRules.CaveFamilyProfile,
	rooms: { Types.RoomPlacement },
	rng: Random
)
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
	local minimumLoops = CaveFamilyRules.minimumLoopConnections(family)
	local loopChance = CaveFamilyRules.loopConnectionChance(family)
	for _, candidate in candidates do
		local room = rooms[candidate.roomIndex]
		local neighbor = rooms[candidate.neighborIndex]
		if
			#room.doorways < roomConnectionCap(room)
			and #neighbor.doorways < roomConnectionCap(neighbor)
			and (added < minimumLoops or rng:NextNumber() < loopChance)
		then
			table.insert(room.doorways, candidate.direction)
			table.insert(neighbor.doorways, OPPOSITE[candidate.direction])
			added += 1
		end
	end
end

-- Add at most one barred shortcut after the ordinary graph and dry critical route already exist.
-- Both endpoint rooms are therefore connected before this edge is added, and sealing the new edge
-- must leave the entire original graph reachable. The gate adds a choice; it never creates access.
local function planEchoGate(
	depth: number,
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	warden: Types.WardenPlacement?,
	unlockedNodes: { [string]: boolean },
	rng: Random
): Types.EchoGatePlacement?
	if not EchoGateRules.canPlan(unlockedNodes, depth) then
		return nil
	end
	if rng:NextNumber() >= math.clamp(LampConfig.generation.echoLock.chancePerFloor, 0, 1) then
		return nil
	end

	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end
	local wardenRoomIndex = if warden ~= nil then warden.roomIndex else nil
	local candidates: { { roomIndex: number, neighborIndex: number, direction: Types.Direction } } = {}
	-- E/S visits every shared adjacency exactly once.
	for roomIndex, room in rooms do
		if
			not EchoGateRules.roomIsEligible(
				roomIndex,
				entryRoomIndex,
				basinRoomIndex,
				brazierRoomIndex,
				wardenRoomIndex
			)
		then
			continue
		end
		for _, direction: Types.Direction in { "E", "S" } do
			local offset = OFFSETS[direction]
			local neighborIndex = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			local neighbor = if neighborIndex ~= nil then rooms[neighborIndex] else nil
			if
				neighborIndex == nil
				or neighbor == nil
				or hasDirection(room.doorways, direction)
				or not EchoGateRules.roomIsEligible(
					neighborIndex,
					entryRoomIndex,
					basinRoomIndex,
					brazierRoomIndex,
					wardenRoomIndex
				)
				or #room.doorways >= roomConnectionCap(room)
				or #neighbor.doorways >= roomConnectionCap(neighbor)
			then
				continue
			end
			table.insert(candidates, {
				roomIndex = roomIndex,
				neighborIndex = neighborIndex,
				direction = direction,
			})
		end
	end

	local order: { number } = {}
	for index in candidates do
		table.insert(order, index)
	end
	shuffle(order, rng)
	for _, candidateIndex in order do
		local candidate = candidates[candidateIndex]
		local room = rooms[candidate.roomIndex]
		local neighbor = rooms[candidate.neighborIndex]
		table.insert(room.doorways, candidate.direction)
		table.insert(neighbor.doorways, OPPOSITE[candidate.direction])

		-- Fail closed if a future topology change ever makes the assumption above untrue.
		if VineRules.doorwayIsRedundant(rooms, entryRoomIndex, candidate.roomIndex, candidate.direction) then
			return {
				roomIndex = candidate.roomIndex,
				direction = candidate.direction,
				visualSeed = rng:NextInteger(1, 2_000_000_000),
			}
		end
		table.remove(room.doorways)
		table.remove(neighbor.doorways)
	end
	return nil
end

local function echoBlockedEdges(
	rooms: { Types.RoomPlacement },
	echoGate: Types.EchoGatePlacement?
): { [string]: boolean }
	local blocked: { [string]: boolean } = {}
	if echoGate == nil then
		return blocked
	end
	blocked[echoGate.roomIndex .. echoGate.direction] = true
	local room = rooms[echoGate.roomIndex]
	if room == nil then
		return blocked
	end
	local offset = OFFSETS[echoGate.direction]
	local targetX, targetZ = room.gridX + offset.x, room.gridZ + offset.z
	for index, candidate in rooms do
		if candidate.gridX == targetX and candidate.gridZ == targetZ then
			blocked[index .. OPPOSITE[echoGate.direction]] = true
			break
		end
	end
	return blocked
end

local function pathBetween(
	rooms: { Types.RoomPlacement },
	startIndex: number,
	goalIndex: number,
	blockedDoorways: { [string]: boolean }?
): { number }
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
			if blockedDoorways ~= nil and blockedDoorways[index .. direction] then
				continue
			end
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

-- Optional doorway barriers: burnable vines or meltable Ice bars, selected by family data. A
-- doorway qualifies only when sealing it (together with every curtain already placed) leaves the
-- whole floor reachable from the entry, and never when it sits on the guaranteed entry -> Basin
-- route. Someone whose dial was capped at the Basin therefore loses shortcuts, never access.
local function planVines(
	family: CaveFamilyRules.CaveFamilyProfile,
	depth: number,
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	lockedStoreRoomIndex: number?,
	echoGate: Types.EchoGatePlacement?,
	rng: Random
): { Types.VinePlacement }
	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end

	local placements: { Types.VinePlacement } = {}
	local sealed: { VineRules.Doorway } = {}
	local echoBlocked = echoBlockedEdges(rooms, echoGate)
	-- Prove every ordinary curtain safe while the Echo Lock is closed. Otherwise its optional edge
	-- could make a load-bearing base doorway look redundant and turn the bell into a requirement.
	if echoGate ~= nil then
		table.insert(sealed, { roomIndex = echoGate.roomIndex, direction = echoGate.direction })
	end
	-- The one room on this floor allowed to end up unreachable. Nil when there is no store, which keeps
	-- the reachability rule exactly as strict as it has always been on every ordinary floor.
	local storeExemption: { [number]: boolean }? = if lockedStoreRoomIndex ~= nil
		then { [lockedStoreRoomIndex] = true }
		else nil

	-- THE LOCKED STORE'S OWN BARRIER, placed before ordinary obstructions and outside the target count.
	--
	-- This is the one curtain in the game allowed to be a room's ONLY way in, and it is safe because the
	-- store is required to be a dead end (VineRules.roomMayBeSealed): nothing routes through a room with
	-- one doorway, so this can neither disconnect another room nor land on the guaranteed route. It is
	-- also recorded in `sealed`, so the reachability check every ordinary vine still runs accounts for it
	-- rather than being blind to it.
	--
	-- Recorded from the LOWER-indexed side of the shared opening, matching the convention the candidate
	-- sweep below uses, so one physical curtain is never described two ways.
	--
	-- DELIBERATELY NOT SUBJECT TO THE FAMILY'S AMBIENT COUNT. A Locked Store always receives the
	-- family's data-stamped style: vines in Stone/Moss and barred icicles in Ice.
	if lockedStoreRoomIndex ~= nil then
		local storeIndex = lockedStoreRoomIndex :: number
		local store = rooms[storeIndex]
		local direction = store.doorways[1]
		if store ~= nil and direction ~= nil then
			local offset = OFFSETS[direction]
			local neighbor = indicesByCell[cellKey(store.gridX + offset.x, store.gridZ + offset.z)]
			local doorway: VineRules.Doorway = if neighbor ~= nil and neighbor < storeIndex
				then { roomIndex = neighbor, direction = OPPOSITE[direction] }
				else { roomIndex = storeIndex, direction = direction }
			table.insert(sealed, doorway)
			table.insert(placements, {
				roomIndex = doorway.roomIndex,
				direction = doorway.direction,
				visualSeed = rng:NextInteger(1, 2_000_000_000),
				style = family.environment.doorwayBarrierStyle,
			})
		end
	end

	-- This family's own curtain budget: its introduction shift brings curtains forward (Moss meets
	-- them two floors earlier than Stone) and its count factor scales the authored per-floor number.
	-- A family with doorway obstructions disabled returns zero here at every depth.
	local target = CaveFamilyRules.vineTargetCount(family, depth)
	if target <= 0 then
		return placements
	end

	local routeEdges: { [string]: boolean } = {}
	local route = pathBetween(rooms, entryRoomIndex, basinRoomIndex, echoBlocked)
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
				or echoBlocked[index .. direction]
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

	-- `placements` and `sealed` already hold the store's curtain if there is one. The target counts only
	-- ORDINARY curtains, so a floor with a store gets its normal complement of vines plus the store's —
	-- the store is extra content, not a vine budget spent elsewhere.
	local ordinaryPlaced = 0
	for _, candidateIndex in order do
		if ordinaryPlaced >= target then
			break
		end
		if rng:NextNumber() >= VinesConfig.chancePerEligibleDoorway then
			continue
		end
		local candidate = candidates[candidateIndex]
		table.insert(sealed, candidate)
		-- The store is exempt from the reachability requirement — being unreachable is what it is for.
		-- Without this exemption its own curtain would fail the check for every ORDINARY vine on the
		-- floor, and a floor with a store would silently lose all its other curtains.
		if VineRules.allRoomsReachable(rooms, entryRoomIndex, sealed, storeExemption) then
			ordinaryPlaced += 1
			table.insert(placements, {
				roomIndex = candidate.roomIndex,
				direction = candidate.direction,
				visualSeed = rng:NextInteger(1, 2_000_000_000),
				style = family.environment.doorwayBarrierStyle,
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
	familyId: string,
	depth: number,
	rooms: { Types.RoomPlacement },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	vines: { Types.VinePlacement },
	echoGate: Types.EchoGatePlacement?,
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
	for key in echoBlockedEdges(rooms, echoGate) do
		vined[key] = true
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
			local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, depth, familyId)
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

-- Raw Wax deposits. Zero to four per floor, with the upper counts reserved for deep floors; the
-- placement rules are all refusals:
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
	family: CaveFamilyRules.CaveFamilyProfile,
	depth: number,
	rooms: { Types.RoomPlacement },
	masks: { [number]: RoomFootprint.OpenMask },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	threatSpawns: { Types.ThreatSpawn },
	hazards: { Types.HazardPlacement },
	dripstones: { Types.DripstonePlacement },
	vines: { Types.VinePlacement },
	echoGate: Types.EchoGatePlacement?,
	unlockedNodes: { [string]: boolean },
	lockedStoreRoomIndex: number?,
	rng: Random
): { Types.DepositPlacement }
	local target = MiningRules.targetCount(depth, rng:NextNumber())
	-- A floor with no ordinary seam can still hold a store: the store is guaranteed content the node
	-- bought, not a share of the floor's own budget.
	if target <= 0 and lockedStoreRoomIndex == nil then
		return {}
	end
	local placement = MiningConfig.placement

	-- Both legs of the mandatory route are excluded, not just the rooms at their ends.
	local onRoute: { [number]: boolean } = {}
	local echoBlocked = echoBlockedEdges(rooms, echoGate)
	for _, index in pathBetween(rooms, entryRoomIndex, brazierRoomIndex, echoBlocked) do
		onRoute[index] = true
	end
	for _, index in pathBetween(rooms, brazierRoomIndex, basinRoomIndex, echoBlocked) do
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

	local storeIndex = lockedStoreRoomIndex

	local halfCell = FloorsConfig.geometry.cellSize / 2
	-- The reserved footprint is the seam PLUS the dry ground a player has to stand on to work it,
	-- so a deposit is never placed where the interaction itself would put someone in a pool.
	local reserved = placement.footprint + placement.standingClearance
	-- The standing-room reservation already supplies most of the side-wall clearance. Use whichever
	-- is larger rather than stacking both buffers and accidentally removing seams from narrow rooms.
	local surfaceSafeWidth =
		math.max(reserved, placement.footprint + FloorsConfig.geometry.placementProbe.horizontalMarginStuds * 2)
	local footprint = Vector3.new(surfaceSafeWidth, 0, surfaceSafeWidth)

	-- A seam sits against a wall, not out in the middle of the floor. In a SHAPED room the wall is no
	-- longer the cell edge, so a bearing rolled at full cell distance often lands in the rock a shape
	-- left behind. Rather than discard the roll, the same bearing is walked inward until it meets the
	-- room's real boundary — which keeps the "seams hug the rock" intent in every footprint instead of
	-- quietly costing shaped families half their seams.
	--
	-- ONLY the containment test is retried this way. Every other refusal (a doorway lane, water, a
	-- hazard, a threat's own spawn) rejects the bearing outright, because those are all reasons the
	-- spot itself is unsafe rather than reasons it is in the wrong place.
	-- THE one place a candidate offset is judged. Every refusal below is a reason the SPOT is unsafe
	-- for someone standing still through a swing, so both the ordinary wall rotation and the store's
	-- guaranteed sweep go through it unchanged — a fallback may look in more places, never accept
	-- more.
	local function tryPlaceAt(roomIndex: number, offset: Vector3): Types.DepositPlacement?
		local room = rooms[roomIndex]
		if
			not fitsInsideRoom(masks[roomIndex], offset, footprint)
			or blocksDoorway(room, depth, family.id, offset, footprint)
			or overlapsWater(hazards, roomIndex, offset, footprint)
		then
			return nil
		end
		-- Explicit separation from anything that can hurt someone standing still. Checked against the
		-- planned positions rather than the built world, so the guarantee holds before a single
		-- Instance exists and is reproducible in a cold test.
		for _, formation in dripstones do
			if formation.roomIndex == roomIndex then
				local delta = formation.localOffset - offset
				if Vector3.new(delta.X, 0, delta.Z).Magnitude < placement.minHazardSeparation then
					return nil
				end
			end
		end
		for _, spawn in threatSpawns do
			if spawn.roomIndex == roomIndex then
				local delta = spawn.offset - offset
				if Vector3.new(delta.X, 0, delta.Z).Magnitude < placement.minThreatSeparation then
					return nil
				end
			end
		end
		return {
			roomIndex = roomIndex,
			localOffset = offset,
			visualSeed = rng:NextInteger(1, 2_000_000_000),
			-- Rolled per deposit, from the same seeded stream, so two seams on one floor can be
			-- different kinds and the whole floor stays reproducible from its seed.
			rowId = MiningRules.selectRow(depth, unlockedNodes, rng:NextNumber()).id,
			-- WHAT the rock is, as opposed to how it is worked. Independent of `rowId` by design:
			-- a Twin Seam of Tier 1 and a Twin Seam of Tier 3 are mined identically. Resolved from
			-- this cave family's own availability curve (Logic/OreRules), which is the entire
			-- reason a harder family is worth descending into.
			oreTier = OreRules.selectTier(family, depth, rng:NextNumber()),
		}
	end

	local function tryPlace(roomIndex: number): Types.DepositPlacement?
		for _ = 1, placement.placementAttempts do
			local side = DIRECTIONS[rng:NextInteger(1, #DIRECTIONS)]
			local normal = OFFSETS[side]
			local wallDistance = halfCell - rng:NextNumber(placement.wallInsetMin, placement.wallInsetMax)
			local lateral = rng:NextNumber(-placement.wallLateralRange, placement.wallLateralRange)
			local anchored = anchorInside(
				masks[roomIndex],
				Vector3.new(
					normal.x * wallDistance + math.abs(normal.z) * lateral,
					0,
					normal.z * wallDistance + math.abs(normal.x) * lateral
				),
				footprint
			)
			if anchored ~= nil then
				local placed = tryPlaceAt(roomIndex, anchored :: Vector3)
				if placed ~= nil then
					return placed
				end
			end
		end
		return nil
	end

	-- The store's last resort: a fixed sweep of the room's own navigation hub. Deterministic (no rolls
	-- of its own beyond what `tryPlaceAt` consumes on success) and ordered outward-then-inward so the
	-- seam still prefers to sit off-centre when it can.
	local hubRadius = FloorsConfig.groundField.centerPadRadius
	local function tryPlaceInHub(roomIndex: number): Types.DepositPlacement?
		for _, fraction in { 0.75, 0.5, 0.25, 0 } do
			for step = 0, 7 do
				local angle = step * math.pi / 4
				local radius = hubRadius * fraction
				local placed = tryPlaceAt(roomIndex, Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
				if placed ~= nil then
					return placed
				end
				if radius <= 0 then
					break
				end
			end
		end
		return nil
	end

	local placements: { Types.DepositPlacement } = {}

	-- THE LOCKED STORE'S GUARANTEED SEAM. The only deposit in the game permitted in a vined room, and
	-- the exception is the whole point of the node: a vault a player burned a curtain open to reach must
	-- never be empty.
	--
	-- The blanket "no deposits behind a curtain" rule exists so a curtain and a seam are never stacked
	-- into one unreadable gamble — a player should not have to bet a loud, expensive burn on whether
	-- there is anything back there. A store INVERTS that: what is inside is guaranteed and known, so the
	-- decision is clean rather than a coin flip.
	--
	-- Placed before the ordinary rotation and OUTSIDE the floor's target count, so a store is extra
	-- content rather than a seam moved out of some other room.
	if storeIndex ~= nil then
		local wanted = math.max(0, math.floor(LampConfig.generation.lockedStore.deposits))
		for _ = 1, wanted do
			local placed = tryPlace(storeIndex :: number)
			if placed == nil then
				-- The wall-anchored rotation found nowhere. For an ORDINARY room that is the correct
				-- answer — the count drops and nothing is compromised — but a store is guaranteed
				-- content a player paid a node for, so it gets one deterministic sweep across the
				-- room's own navigation hub, which is open air in every footprint by construction.
				--
				-- EVERY SAFETY REFUSAL STILL APPLIES: the sweep goes through the same `tryPlaceAt`,
				-- so a hub position that blocks a doorway, sits in water, or crowds a hazard or a
				-- threat spawn is rejected exactly as a wall position would be. This widens where the
				-- planner looks; it does not widen what it will accept.
				placed = tryPlaceInHub(storeIndex :: number)
			end
			if placed == nil then
				break
			end
			table.insert(placements, placed)
		end
	end

	local ordinaryPlaced = 0
	for _, roomIndex in candidateRooms do
		if ordinaryPlaced >= target then
			break
		end
		local placed = tryPlace(roomIndex)
		-- A failed wall pocket is a presentation failure, not permission to erase the floor's seam.
		-- Keep every safety test and the one-seam-per-room rule, but sweep this off-route room's
		-- guaranteed navigation hub before giving up on it.
		if placed == nil then
			placed = tryPlaceInHub(roomIndex)
		end
		if placed ~= nil then
			ordinaryPlaced += 1
			table.insert(placements, placed)
		end
	end
	return placements
end

-- MOSS FLAMMABLE VEGETATION (Config/MossFire). Uncommon tagged clusters of dry growth — the one
-- thing in the game a player's own flame can set alight.
--
-- EVERY RULE HERE IS A REFUSAL, and they are the same shape as the deposit rules for the same reason:
--
--   * NEVER the entry, Basin, completion or Warden room, and never a room on the guaranteed
--     entry -> Brazier -> Basin route. Fire is a choice a player makes, so it may not sit anywhere
--     the floor already requires them to walk.
--   * NEVER on the navigation hub, across a doorway lane, or inside any reserved gameplay footprint
--     — spawns, seams, hazards and fixtures all keep their clearance.
--   * NEVER outside the room's own open footprint.
--   * AT MOST ONE per room, always.
--
-- A floor that cannot satisfy all of that simply carries fewer clusters. The count is reduced; the
-- safety rules are never relaxed to reach it. Because a cluster can never be on a route or in a lane,
-- the collidable obstruction some of them form can never be load-bearing: another valid route always
-- exists, which is what makes burning one an option rather than a toll.
local function planMossFire(
	family: CaveFamilyRules.CaveFamilyProfile,
	depth: number,
	rooms: { Types.RoomPlacement },
	masks: { [number]: RoomFootprint.OpenMask },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	warden: Types.WardenPlacement?,
	echoGate: Types.EchoGatePlacement?,
	reservations: { PlacementReservations.Reservation },
	hazards: { Types.HazardPlacement },
	rng: Random
): { Types.MossFireCluster }
	local placements: { Types.MossFireCluster } = {}
	if not MossFireRules.isEligibleFamily(family.id) then
		return placements
	end
	local chance = MossFireRules.chanceForDepth(depth)
	if chance <= 0 then
		return placements
	end

	local placement = MossFireConfig.placement
	local onRoute: { [number]: boolean } = {}
	local echoBlocked = echoBlockedEdges(rooms, echoGate)
	for _, index in pathBetween(rooms, entryRoomIndex, brazierRoomIndex, echoBlocked) do
		onRoute[index] = true
	end
	for _, index in pathBetween(rooms, brazierRoomIndex, basinRoomIndex, echoBlocked) do
		onRoute[index] = true
	end

	local clusterFootprint = Vector3.new(placement.clusterRadius * 2, 0, placement.clusterRadius * 2)

	for roomIndex, room in rooms do
		if
			onRoute[roomIndex]
			or roomIndex == entryRoomIndex
			or roomIndex == basinRoomIndex
			or roomIndex == brazierRoomIndex
			or room.moduleId == StoneWardenConfig.roomModuleId
			or (warden ~= nil and roomIndex == warden.roomIndex)
		then
			continue
		end
		-- The roll is consumed for every eligible room whether or not a cluster lands, so whether one
		-- happened to fit cannot shift the rest of the floor's seeded stream.
		local wanted = rng:NextNumber() < chance
		local anchorAngle = rng:NextNumber(0, math.pi * 2)
		local anchorDistance = rng:NextNumber(placement.minCenterOffset, placement.maxCenterOffset)
		local obstructs = rng:NextNumber() < placement.obstructionChance
		if not wanted then
			continue
		end

		local anchor: Vector3? = nil
		local angle, distance = anchorAngle, anchorDistance
		for _ = 1, placement.placementAttempts do
			local candidate = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			if
				fitsInsideRoom(masks[roomIndex], candidate, clusterFootprint)
				and not blocksDoorway(room, depth, family.id, candidate, clusterFootprint)
				and not overlapsWater(hazards, roomIndex, candidate, clusterFootprint)
				and not PlacementReservations.overlaps(
					reservations,
					roomIndex,
					candidate,
					placement.clusterRadius,
					placement.gameplayClearance
				)
			then
				anchor = candidate
				break
			end
			-- Walk around the room rather than in toward its centre: a cluster belongs against the
			-- growth on the walls, and the hub must stay clear whatever happens.
			angle += math.pi * 2 / placement.placementAttempts
			distance = placement.minCenterOffset
				+ (placement.maxCenterOffset - placement.minCenterOffset) * rng:NextNumber()
		end
		if anchor == nil then
			continue
		end
		local origin = anchor :: Vector3

		-- THE CONNECTIVITY GRAPH, built here and recorded on the plan. Nodes are chained so the graph
		-- is connected by construction (node n always joins node n-1), and near pairs are additionally
		-- joined so fire can take more than one path through a cluster. Nothing is discovered at
		-- runtime: what can carry fire is decided before a single Instance exists, which is what keeps
		-- spread deterministic, testable cold, and incapable of reaching a wet wall.
		local nodeCount = rng:NextInteger(placement.nodesMin, placement.nodesMax)
		local nodes: { Types.MossFireNode } = {}
		local edges: { { a: number, b: number } } = {}
		for nodeIndex = 1, nodeCount do
			local nodeAngle = rng:NextNumber(0, math.pi * 2)
			local nodeRadius = rng:NextNumber(0, placement.clusterRadius * 0.8)
			local offset = origin + Vector3.new(math.cos(nodeAngle) * nodeRadius, 0, math.sin(nodeAngle) * nodeRadius)
			table.insert(nodes, {
				localOffset = offset,
				kindId = MossFireRules.selectKind(rng:NextNumber()).id,
			})
			if nodeIndex > 1 then
				table.insert(edges, { a = nodeIndex - 1, b = nodeIndex })
			end
		end
		for a = 1, #nodes do
			for b = a + 2, #nodes do
				local delta = nodes[a].localOffset - nodes[b].localOffset
				if Vector3.new(delta.X, 0, delta.Z).Magnitude <= placement.nodeSpacingMax then
					table.insert(edges, { a = a, b = b })
				end
			end
		end

		table.insert(placements, {
			roomIndex = roomIndex,
			localOffset = origin,
			nodes = nodes,
			edges = edges,
			obstructs = obstructs,
			visualSeed = rng:NextInteger(1, 2_000_000_000),
		})
		-- Reserved so nothing planned after this can land on top of it, and so a second cluster can
		-- never be squeezed into the same room.
		PlacementReservations.add(reservations, roomIndex, origin, placement.clusterRadius, "MossFire")
	end

	return placements
end

-- Anchor the Warden's encounter to ONE WALL of its den instead of scattering it around the room
-- centre. The dormant body is an outcrop in that wall; the wax it guards stands in the open floor
-- in front of it, in the same view; the Heavy Crown that counters it sits off to one side of the walk
-- between them. A DOORLESS side is required — the stone a Warden peels out of cannot be the gap
-- people walk through — which is why this runs only once the room's final doorways exist.
--
-- Exactly one roll is drawn on every path, so a den with four doorways (no blank wall at all, and
-- only possible if the connection cap ever allows it) consumes the same seeded stream as any other.
local function layOutWarden(room: Types.RoomPlacement, warden: Types.WardenPlacement, rng: Random)
	local layout = StoneWardenConfig.layout
	local halfCell = FloorsConfig.geometry.cellSize / 2
	local candidates: { Types.Direction } = {}
	for _, direction: Types.Direction in { "N", "S", "E", "W" } do
		if not hasDirection(room.doorways, direction) then
			table.insert(candidates, direction)
		end
	end
	local sides: { Types.Direction } = if #candidates > 0 then candidates else { "N", "S", "E", "W" }
	local direction = sides[rng:NextInteger(1, #sides)]

	local normal = OFFSETS[direction]
	-- Toward that wall from the room centre, and along its face.
	local outward = Vector3.new(normal.x, 0, normal.z)
	local lateral = Vector3.new(-outward.Z, 0, outward.X)
	warden.wallDirection = direction
	warden.pileOffset = outward * (halfCell - layout.wallSetback)
	warden.waxOffset = outward * layout.waxStandoff
	warden.counterDripstoneOffset = outward * layout.counterStandoff + lateral * layout.counterLateral
	table.clear(warden.collapseDripstoneOffsets)
	for _, collapse in layout.collapseDripstones do
		table.insert(warden.collapseDripstoneOffsets, outward * collapse.standoff + lateral * collapse.lateral)
	end
end

-- One floor. `globalDepth` is the canonical difficulty depth and drives every content curve and
-- every deterministic geometry seed; `localFloor` is only this expedition's ordinal (world stacking,
-- floor keys, "Floor 3" on screen) and defaults to the global depth for a run that starts at 1.
export type PlanRequest = {
	globalDepth: number,
	localFloor: number?,
	rng: Random,
	-- Which cave family this floor belongs to (Config/CaveFamilies). Absent resolves to the free
	-- family, which is the correct reading for a test, a tool, or any caller that predates families —
	-- and can never grant access, because the free family is owned by everybody.
	--
	-- THIS REPLACED `threatBudgetMultiplier` AND `dripstoneMultiplier`. Those were two loose numbers a
	-- caller could set independently of each other and of everything else the cave is; a floor could
	-- be planned with Ice's threat budget and Stone's hazards, and nothing would object. A family id
	-- is one value that resolves all of it consistently.
	familyId: string?,
	-- Lamp Network node ids the PARTY between them owns, as a set. Used only to decide which deposit
	-- rows may appear (Logic/MiningRules.selectRow). A floor is shared, so this is a union rather than
	-- the leader's own set: one friend's purchase has to put seams in the ground for everybody, or the
	-- row would vanish whenever the buyer was not the one who pulled the lever.
	unlockedNodes: { [string]: boolean }?,
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
	-- STEP 1 OF THE BUILD ORDER: resolve the cave profile. Everything below reads this and nothing
	-- below branches on which family it turned out to be.
	local family = CaveFamilyRules.resolve(request.familyId)
	-- Absent means "nobody owns anything", which yields Standard seams only — the correct reading for a
	-- test, a tool, or any caller that predates deposit rows.
	local unlockedNodes = request.unlockedNodes or {}

	local roomCount = DepthRules.getRoomCountTarget(depth)
	local rooms: { Types.RoomPlacement } = {}
	local occupied: { [string]: boolean } = {}

	-- One roll decides whether this whole floor is wet. Most Stone floors are dry and never consider
	-- a flooded module at all, so meeting water is an event rather than scenery; Moss meets it more
	-- often and Ice less.
	local floodedFloor = rng:NextNumber() < CaveFamilyRules.wetFloorProbability(family)

	local first = weightedModule(rng, floodedFloor)
	table.insert(rooms, {
		moduleId = first.id,
		gridX = 0,
		gridZ = 0,
		doorways = {},
		ceilingHeight = rollCeiling(family, rng),
		footprint = RoomFootprint.rectangle(),
	})
	occupied[cellKey(0, 0)] = true

	for _ = 2, roomCount do
		local sides = openSides(rooms, occupied, false)
		if #sides == 0 then
			sides = openSides(rooms, occupied, true) -- caps exhausted; relax rather than under-build
		end
		if #sides == 0 then
			break
		end
		local side = chooseAttachmentSide(family, rooms, occupied, sides, rng)
		attachRoom(family, rooms, occupied, side, weightedModule(rng, floodedFloor).id, rng)
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
	local basinRoomIndex = attachRoom(
		family,
		rooms,
		occupied,
		basinSide :: { roomIndex: number, direction: Types.Direction },
		"Basin",
		rng
	)

	-- The Warden is a rare optional branch, never a surprise object dropped into arbitrary terrain.
	-- Its room still uses normal cave generation; only its core encounter footprints are protected.
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
			local roomIndex = attachRoom(family, rooms, occupied, side, StoneWardenConfig.roomModuleId, rng)
			rooms[roomIndex].ceilingHeight = StoneWardenConfig.roomCeilingHeight
			warden = {
				roomIndex = roomIndex,
				-- Placeholder layout only. The encounter is anchored to a doorless WALL of this room,
				-- and this room does not have its final doorways yet — the loop pass and the Echo Lock
				-- both still run below. `layOutWarden` fixes every offset once they do.
				wallDirection = "N",
				pileOffset = Vector3.zero,
				waxOffset = Vector3.zero,
				counterDripstoneOffset = Vector3.zero,
				collapseDripstoneOffsets = {},
				visualSeed = rng:NextInteger(1, 2_000_000_000),
			}
		end
	end
	-- Open loops after the Basin exists so an adjacent Basin cell can become a genuine second way
	-- down instead of every floor ending in a mandatory leaf.
	addLoopConnections(family, rooms, rng)
	-- Water may reward exploration but can never be the only route from spawn to the safe Basin.
	guaranteeDryRoute(rooms, entryRoomIndex, basinRoomIndex, rng)
	-- Then hold the floor to its pool budget: the dry route can convert away every pool the assembly
	-- rolled, and a lucky assembly can roll far more than a floor should carry.
	enforceFloodedBudget(rooms, entryRoomIndex, basinRoomIndex, floodedFloor, rng)

	-- Echo Lock is added only after the ordinary graph and dry critical route are final. Systems that
	-- prove required access below explicitly treat it as closed, while geometry sees the doorway in
	-- time to keep its lane clear.
	local echoGate =
		planEchoGate(depth, rooms, entryRoomIndex, basinRoomIndex, brazierRoomIndex, warden, unlockedNodes, rng)

	-- The den's doorways are final now, so the Warden can be given its wall. Everything downstream —
	-- the protected masks, the flat pads, the reservations, the guaranteed counter-dripstone — reads
	-- the offsets this writes, so it has to happen before any of them and after the last doorway.
	if warden ~= nil then
		layOutWarden(rooms[warden.roomIndex], warden, rng)
	end

	-- STEPS 6-8 OF THE BUILD ORDER: roll each ordinary room's outer footprint, validate it, then union
	-- the protected masks over it.
	--
	-- This happens HERE and not earlier because a shape has to be validated against the doorways the
	-- room will actually have, and a room does not have its final doorways until the loop pass and the
	-- Echo Lock are both done. It happens BEFORE everything below because every placement from here on
	-- — ground swells, water, threats, loot, formations, curtains, seams — is checked against the open
	-- footprint rather than against the room cell.
	--
	-- ENTRY, BASIN AND COMPLETION STAY RECTANGLES. They carry the expedition's mandatory fixtures and
	-- its transition spawn slots; there is no aesthetic gain worth making any of those a
	-- shape-dependent question. The Warden's den is treated the same way for the same reason: its
	-- core encounter pads are large, fixed, and off-centre.
	local masks: { [number]: RoomFootprint.OpenMask } = {}
	local shapeFallbacks = 0
	local shapeRejections = 0
	local shapedRooms = 0
	for roomIndex, room in rooms do
		local isProtected = RoomFootprint.isProtectedShape(roomIndex, entryRoomIndex, basinRoomIndex, brazierRoomIndex)
			or (warden ~= nil and roomIndex == warden.roomIndex)
		if isProtected then
			room.footprint = RoomFootprint.rectangle()
		else
			-- The shape roll is drawn BEFORE the parameter rolls and unconditionally, so a room that
			-- ends up falling back to Rectangle still consumes the same values from the seeded stream
			-- as one that does not. Without that, whether a shape validated would shift every
			-- subsequent roll on the floor and the same seed would produce different caves.
			local result = RoomFootprint.roll(family, rng:NextNumber(), rng)
			room.footprint = result.footprint
			shapeRejections += result.rejections
			if result.fellBack then
				shapeFallbacks += 1
			end
			if result.footprint.kind ~= "Rectangle" then
				shapedRooms += 1
			end
		end
		masks[roomIndex] = RoomFootprint.maskFor(room, depth, family.id)
	end

	-- The protected interaction zones, unioned over whatever the shapes left. These are the fixtures
	-- the floor cannot function without, so they are open air by construction rather than by luck:
	-- the Basin's descent pad, the Brazier's pedestal, and the Warden's core encounter pads. The
	-- rooms holding them are already rectangles, so this is belt-and-braces — and it stays here so
	-- that making one of them a shaped room later is a safe change rather than a silent break.
	local halfCell = FloorsConfig.geometry.cellSize / 2
	local basinMask = masks[basinRoomIndex]
	if basinMask ~= nil then
		RoomFootprint.reserve(basinMask, halfCell / 2, halfCell / 2, halfCell / 4 + 2)
	end
	local brazierMask = masks[brazierRoomIndex]
	if brazierMask ~= nil then
		RoomFootprint.reserve(brazierMask, -halfCell / 2, -halfCell / 2, 6)
	end
	if warden ~= nil then
		local wardenMask = masks[warden.roomIndex]
		if wardenMask ~= nil then
			for _, offset in { warden.pileOffset, warden.waxOffset, warden.counterDripstoneOffset } do
				RoomFootprint.reserve(wardenMask, offset.X, offset.Z, StoneWardenConfig.encounterClearance)
			end
		end
	end

	-- Gameplay footprints are reserved before cosmetic dressing is rolled. The Warden room owns
	-- three large clear pads; threats and loot add their own reservations below.
	local reservations: { PlacementReservations.Reservation } = {}
	if warden ~= nil then
		for _, offset in { warden.pileOffset, warden.waxOffset, warden.counterDripstoneOffset } do
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
					fitsInsideRoom(masks[roomIndex], offset, size)
					and not overlapsSpecialCenter
					and not overlapsGround
					and not blocksDoorway(room, depth, family.id, offset, size)
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
					local anchoredFallback = anchorInside(
						masks[roomIndex],
						Vector3.new(
							xSign * terrain.groundPatchFallbackOffset,
							0,
							zSign * terrain.groundPatchFallbackOffset
						),
						fallbackSize
					)
					local fallbackOffset = anchoredFallback or Vector3.zero
					if
						anchoredFallback ~= nil
						and not blocksDoorway(room, depth, family.id, fallbackOffset, fallbackSize)
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
		local offset, size, bedDepth =
			planWaterPool(room, depth, family.id, masks[index], def.waterDepth, swellsByRoom[index] or {}, rng)
		-- A zero-sized pool means the room had nowhere safe for one (see planWaterPool). The room stays
		-- dry rather than carrying a puddle on its navigation hub; the module stays flooded in name
		-- only, which costs nothing because every water rule keys off this hazard record.
		if size.X <= 0 or size.Z <= 0 then
			continue
		end
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
	--   resolvedThreatBudget = baseThreatBudgetForFloor x caveBaseThreatMultiplier x caveThreatBandMultiplier
	--
	-- The first factor is the authored per-floor curve extended past its hand-written range by
	-- Logic/DepthRules; the other two come from the family (Logic/CaveFamilyRules). Party scaling,
	-- room caps and every protected-room rule below still apply on top.
	local baseBudget = FloorsConfig.threatBudgetPerFloor[math.clamp(depth, 1, #FloorsConfig.threatBudgetPerFloor)]
		* DepthRules.getThreatBudgetMultiplier(depth)
	local budget = math.max(0, math.floor(baseBudget * CaveFamilyRules.threatBudgetMultiplier(family, depth) + 0.5))
	local eligible: { number } = {}
	for index, room in rooms do
		local def = moduleById(room.moduleId)
		if
			index ~= entryRoomIndex
			and index ~= basinRoomIndex
			and (warden == nil or index ~= warden.roomIndex)
			and def ~= nil
			and roomHasThreatAtDepth(family, def, depth, room.ceilingHeight)
		then
			table.insert(eligible, index)
		end
	end
	shuffle(eligible, rng)
	local threatFootprint =
		Vector3.new(FloorsConfig.terrain.gameplaySpawnRadius * 2, 0, FloorsConfig.terrain.gameplaySpawnRadius * 2)
	-- One threat, in the first eligible room from `startIndex` that can safely hold it. Returns whether
	-- it landed.
	--
	-- WALKING THE ROTATION RATHER THAN GIVING UP ON ONE ROOM is what keeps a floor's threat budget
	-- exact. Before shapes, any eligible room could hold a spawn, so the first pick always worked. Now
	-- a room can be a narrow capsule that also carries a pool, and if that room happened to win the
	-- shuffle the floor silently lost a threat — a difficulty change caused by a geometry change,
	-- which is exactly the kind of quiet drift the budget formula exists to prevent. Nothing is
	-- relaxed: every refusal still stands, the threat just goes next door.
	local function placeThreat(startIndex: number): boolean
		for step = 0, #eligible - 1 do
			local roomIndex = eligible[(startIndex + step - 1) % #eligible + 1]
			local room = rooms[roomIndex]
			local def = moduleById(room.moduleId) :: Types.RoomModuleDef
			local threatId = weightedThreat(family, def.allowedThreats, depth, room.ceilingHeight, rng)
			if threatId == nil then
				continue
			end
			for _ = 1, 32 do
				local rolled = Vector3.new(
					rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4),
					0,
					rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4)
				)
				-- Pulled onto the room's real floor if the roll landed in the rock a shape left behind.
				local anchored = anchorInside(masks[roomIndex], rolled, threatFootprint)
				if anchored == nil then
					continue
				end
				local offset = anchored :: Vector3
				if
					not blocksDoorway(room, depth, family.id, offset, threatFootprint)
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
					return true
				end
			end
		end
		return false
	end

	for spawnIndex = 1, budget do
		if #eligible == 0 then
			break
		end
		if spawnIndex > #eligible and (spawnIndex - 1) % #eligible == 0 then
			shuffle(eligible, rng)
		end
		placeThreat((spawnIndex - 1) % #eligible + 1)
	end

	-- THE LOCKED STORE (Config/LampNetwork.generation.lockedStore). Chosen HERE, before loot, vines and
	-- deposits, because all three have to know about it: loot and deposits stock it, and the vine
	-- planner seals it. Choosing it later would mean re-opening decisions those passes had already made.
	--
	-- The roll is consumed unconditionally when the node is unlocked and the depth qualifies, so a floor
	-- that rolls a store but has no spare dead end draws the same number of values from the seeded stream
	-- as one that places it. Without that, whether a store existed would shift every subsequent roll on
	-- the floor and the same seed would produce different caves for different players.
	local lockedStoreRoomIndex: number? = nil
	if
		LampConfig.enabled
		and LampConfig.generation.enabled
		and unlockedNodes["lamp.locked_store"]
		and depth >= LampConfig.generation.lockedStore.minDepth
	then
		local wanted = rng:NextNumber() < LampConfig.generation.lockedStore.chancePerFloor
		local protectedIndices: { [number]: boolean } = {
			[entryRoomIndex] = true,
			[basinRoomIndex] = true,
			[brazierRoomIndex] = true,
		}
		if warden ~= nil then
			protectedIndices[warden.roomIndex] = true
		end
		local candidates: { number } = {}
		for index, room in rooms do
			if
				VineRules.roomMayBeSealed(room, index, protectedIndices)
				and room.moduleId ~= StoneWardenConfig.roomModuleId
			then
				table.insert(candidates, index)
			end
		end
		shuffle(candidates, rng)
		if wanted and #candidates > 0 then
			lockedStoreRoomIndex = candidates[1]
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
	-- The store's guaranteed stock. Placed FIRST and separately from the ordinary rotation, so it is a
	-- promise the room keeps rather than a room that happened to win a shuffle — a sealed vault a player
	-- burned their way into must never be empty.
	if lockedStoreRoomIndex ~= nil then
		local storeIndex = lockedStoreRoomIndex :: number
		for _ = 1, math.max(0, math.floor(LampConfig.generation.lockedStore.loot)) do
			local lootId = weightedLoot(depth, family.id, rng)
			if lootId == nil then
				break
			end
			local offset = plannedLootOffset(
				rooms[storeIndex],
				storeIndex,
				depth,
				family.id,
				masks[storeIndex],
				hazards,
				reservations,
				rng
			)
			table.insert(lootSpawns, { lootId = lootId, roomIndex = storeIndex, offset = offset })
			PlacementReservations.add(reservations, storeIndex, offset, LootConfig.placementFootprint / 2, "Loot")
		end
	end
	-- Rolled BEFORE the room check, so the seeded stream advances the same way on a floor that has no
	-- eligible room as on one that does.
	local lootCount = rolledLootCount(depth, rng)
	if #lootRoomIndices > 0 then
		for _ = 1, lootCount do
			local lootId = weightedLoot(depth, family.id, rng)
			if lootId == nil then
				break
			end
			local roomIndex = lootRoomIndices[(_ - 1) % #lootRoomIndices + 1]
			local offset = plannedLootOffset(
				rooms[roomIndex],
				roomIndex,
				depth,
				family.id,
				masks[roomIndex],
				hazards,
				reservations,
				rng
			)
			table.insert(lootSpawns, {
				lootId = lootId,
				roomIndex = roomIndex,
				offset = offset,
			})
			PlacementReservations.add(reservations, roomIndex, offset, LootConfig.placementFootprint / 2, "Loot")
		end
	end

	local dripstones = planDripstones(
		family,
		depth,
		rooms,
		masks,
		entryRoomIndex,
		basinRoomIndex,
		brazierRoomIndex,
		threatSpawns,
		hazards,
		groundPatches,
		rng
	)
	if warden ~= nil then
		table.insert(dripstones, {
			roomIndex = warden.roomIndex,
			localOffset = warden.counterDripstoneOffset,
			variantId = StoneWardenConfig.counterDripstoneVariantId,
			visualSeed = warden.visualSeed,
		})
		for index, offset in warden.collapseDripstoneOffsets do
			local collapse = StoneWardenConfig.layout.collapseDripstones[index]
			if collapse ~= nil then
				table.insert(dripstones, {
					roomIndex = warden.roomIndex,
					localOffset = offset,
					variantId = collapse.variantId,
					visualSeed = warden.visualSeed + index,
				})
			end
		end
	end

	local vines = planVines(family, depth, rooms, entryRoomIndex, basinRoomIndex, lockedStoreRoomIndex, echoGate, rng)

	-- Deposits are planned LAST, so every hazard, threat, and curtain they have to avoid already
	-- exists in the plan. Nothing placed after this can land on top of one.
	local lurkers =
		planLurkers(family.id, depth, rooms, entryRoomIndex, basinRoomIndex, brazierRoomIndex, vines, echoGate, rng)
	local deposits = planDeposits(
		family,
		depth,
		rooms,
		masks,
		entryRoomIndex,
		basinRoomIndex,
		brazierRoomIndex,
		threatSpawns,
		hazards,
		dripstones,
		vines,
		echoGate,
		unlockedNodes,
		lockedStoreRoomIndex,
		rng
	)

	-- Flammable vegetation is planned AFTER everything it has to keep clear of, so its reservation
	-- check sees the finished floor rather than a partial one. It reserves its own footprint too, so
	-- nothing that came before can be reached by a fire that started in it.
	local mossFire = planMossFire(
		family,
		depth,
		rooms,
		masks,
		entryRoomIndex,
		basinRoomIndex,
		brazierRoomIndex,
		warden,
		echoGate,
		reservations,
		hazards,
		rng
	)

	return {
		depth = localFloor,
		globalDepth = depth,
		familyId = family.id,
		-- Generation diagnostics, for the floor-spawn audit telemetry. Counts only: a report needs to
		-- know that shapes are being rejected without a plan carrying a log around.
		diagnostics = {
			shapedRooms = shapedRooms,
			shapeFallbacks = shapeFallbacks,
			shapeRejections = shapeRejections,
		},
		rooms = rooms,
		entryRoomIndex = entryRoomIndex,
		basinRoomIndex = basinRoomIndex,
		brazierRoomIndex = brazierRoomIndex,
		threatSpawns = threatSpawns,
		lootSpawns = lootSpawns,
		hazards = hazards,
		dripstones = dripstones,
		vines = vines,
		echoGate = echoGate,
		lurkers = lurkers,
		warden = warden,
		deposits = deposits,
		mossFire = mossFire,
		groundPatches = groundPatches,
		lockedStoreRoomIndex = lockedStoreRoomIndex,
	}
end

-- A finite floor batch for tests and tooling. Each floor gets its OWN seed derived from
-- (run seed, cave family, global depth), so a floor is reproducible on its own and two different
-- global depths never share a derived stream. Live expeditions call `plan` on demand and are not
-- capped by this helper's batch size.
--
-- THE CAVE PARTICIPATES IN THE SEED through its family's `legacyTierId`, which is a stable property
-- of the family row (Config/CaveFamilies) rather than a hash of its name. Two families therefore
-- never generate the same floor from the same run seed, and renaming a family cannot silently
-- reshuffle every cave in the game.
function FloorPlanner.planAll(
	seed: number,
	floorCount: number?,
	familyId: string?,
	startDepth: number?
): { Types.FloorPlan }
	local start = startDepth or 1
	DepthRules.assertSupportedDepth(start, "FloorPlanner.planAll")
	local requested = floorCount or FloorsConfig.planningBatchSize
	local plannedCount = DepthRules.planningBatchCount(start, math.max(requested, 1))
	local tierId = CaveFamilyRules.legacyTierId(familyId)
	local plans: { Types.FloorPlan } = {}
	for localFloor = 1, plannedCount do
		local globalDepth = DepthRules.getGlobalDepth(start, localFloor)
		table.insert(
			plans,
			FloorPlanner.plan({
				globalDepth = globalDepth,
				localFloor = localFloor,
				rng = Random.new(DepthRules.getFloorSeed(seed, tierId, globalDepth)),
				familyId = familyId,
			})
		)
	end
	return plans
end

return FloorPlanner

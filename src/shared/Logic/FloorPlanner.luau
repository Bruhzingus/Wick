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
local DeadCandleConfig = require(script.Parent.Parent.Config.DeadCandle)
local DynamiteConfig = require(script.Parent.Parent.Config.Dynamite)
local DynamiteRules = require(script.Parent.DynamiteRules)
local AshamedLurkerRules = require(script.Parent.AshamedLurkerRules)
local DeadCandleRules = require(script.Parent.DeadCandleRules)
local CaveFamilyRules = require(script.Parent.CaveFamilyRules)
local DepthRules = require(script.Parent.DepthRules)
local FloorStacking = require(script.Parent.FloorStacking)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)
local DripstoneRules = require(script.Parent.DripstoneRules)
local GroundGeometry = require(script.Parent.GroundGeometry)
local OreRules = require(script.Parent.OreRules)
local RoofGeometry = require(script.Parent.RoofGeometry)
local RoomFootprint = require(script.Parent.RoomFootprint)
local SurfaceRules = require(script.Parent.SurfaceRules)
local ThreatRules = require(script.Parent.ThreatRules)
local VineRules = require(script.Parent.VineRules)
local PlacementReservations = require(script.Parent.PlacementReservations)
local EnemySpawnRules = require(script.Parent.EnemySpawnRules)

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
local function placementSurfaceMargin(): number
	local probe = FloorsConfig.geometry.placementProbe
	return math.max(probe.horizontalMarginStuds, probe.placementPadMarginStuds + probe.placementPadBlendStuds)
end

local function surfaceSafeFootprint(size: Vector3): Vector3
	local margin = placementSurfaceMargin()
	return Vector3.new(size.X + margin * 2, size.Y, size.Z + margin * 2)
end

type GuaranteedCacheLayout = {
	lootOffset: Vector3,
	depositOffsets: { Vector3 },
}

-- Paid one-door caches cannot rely on the ordinary random wall search: their room may be a narrow
-- shaped dead end, while the content behind the barrier is a promise. Give every such room one
-- doorway-relative layout. The pickup sits against the back geology; up to three seams form a
-- separated inner triangle. All discs overlap the guaranteed navigation hub, so reserving them opens
-- connected alcoves rather than isolated pockets, and every support sample remains inside the roof's
-- minimum-clearance interior band.
local function guaranteedCacheLayout(room: Types.RoomPlacement): GuaranteedCacheLayout
	local doorway = room.doorways[1]
	local outward = if doorway ~= nil then OFFSETS[doorway] else { x = 0, z = -1 }
	local back = Vector3.new(-outward.x, 0, -outward.z)
	local right = Vector3.new(-back.Z, 0, back.X)
	local side = math.sqrt(3) * 4.5
	return {
		lootOffset = back * 17.5,
		depositOffsets = {
			back * 4.5 + right * side,
			back * 4.5 - right * side,
			-back * 9,
		},
	}
end

local function lootShelfOuterRadius(): number
	return LootConfig.placementFootprint / 2 + placementSurfaceMargin()
end

local function depositShelfOuterRadius(): number
	return math.max(
		(MiningConfig.placement.footprint + MiningConfig.placement.standingClearance) / 2,
		MiningConfig.visual.surfaceProbeRadius + placementSurfaceMargin()
	)
end

local function reserveGuaranteedCache(mask: RoomFootprint.OpenMask, layout: GuaranteedCacheLayout)
	RoomFootprint.reserve(mask, layout.lootOffset.X, layout.lootOffset.Z, lootShelfOuterRadius())
	for _, offset in layout.depositOffsets do
		RoomFootprint.reserve(mask, offset.X, offset.Z, depositShelfOuterRadius())
	end
end

-- A placement shelf levels its complete support ring to the natural height at its centre. In the
-- roof's outer wall-transition band minimum headroom is deliberately not forced, so containment in
-- open X/Z alone is insufficient: a high berm can leave no safe air from which to probe or room for
-- the reward itself. Check the exact shelf height against the exact local roof at all nine samples.
local function placementShelfHasHeadroom(
	room: Types.RoomPlacement,
	groundField: GroundGeometry.Field,
	roofField: RoofGeometry.Field,
	offset: Vector3,
	supportRadius: number
): boolean
	local shelfHeight = GroundGeometry.offset(groundField, offset.X, offset.Z)
	local probe = FloorsConfig.geometry.placementProbe
	local function sampleClears(dx: number, dz: number): boolean
		local localX = offset.X + dx
		local localZ = offset.Z + dz
		local roofHeight = RoofGeometry.undersideHeight(room.ceilingHeight, roofField, shelfHeight, localX, localZ)
		return SurfaceRules.plannedProbeLift(
			probe.upStuds,
			roofHeight - shelfHeight,
			FloorsConfig.roof.minimumClearance
		) ~= nil
	end
	if not sampleClears(0, 0) then
		return false
	end
	local radius = math.max(0, supportRadius)
	for step = 0, 7 do
		local angle = step * math.pi / 4
		if not sampleClears(math.cos(angle) * radius, math.sin(angle) * radius) then
			return false
		end
	end
	return true
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
	groundField: GroundGeometry.Field,
	roofField: RoofGeometry.Field,
	hazards: { Types.HazardPlacement },
	reservations: { PlacementReservations.Reservation },
	rng: Random
): Vector3?
	local halfCell = FloorsConfig.geometry.cellSize / 2
	local footprint = surfaceSafeFootprint(Vector3.new(LootConfig.placementFootprint, 0, LootConfig.placementFootprint))
	local probe = FloorsConfig.geometry.placementProbe
	-- Two seating shelves must keep their entire transition outside the other pickup's support ring.
	-- The ordinary gameplay padding remains the floor when it is ever larger than that terrain need.
	local shelfSeparation = math.max(
		FloorsConfig.terrain.gameplaySpawnSeparation,
		probe.placementPadMarginStuds + probe.placementPadBlendStuds
	)
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
			and placementShelfHasHeadroom(room, groundField, roofField, offset, LootConfig.placementFootprint / 2)
			and not blocksDoorway(room, depth, familyId, offset, footprint)
			and not overlapsWater(hazards, roomIndex, offset, footprint)
			and not PlacementReservations.overlaps(
				reservations,
				roomIndex,
				offset,
				LootConfig.placementFootprint / 2,
				shelfSeparation
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
				and placementShelfHasHeadroom(room, groundField, roofField, offset, LootConfig.placementFootprint / 2)
				and not overlapsWater(hazards, roomIndex, offset, footprint)
				and not PlacementReservations.overlaps(
					reservations,
					roomIndex,
					offset,
					LootConfig.placementFootprint / 2,
					shelfSeparation
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
				and placementShelfHasHeadroom(room, groundField, roofField, offset, LootConfig.placementFootprint / 2)
				and not blocksDoorway(room, depth, familyId, offset, footprint)
				and not overlapsWater(hazards, roomIndex, offset, footprint)
				and not PlacementReservations.overlaps(
					reservations,
					roomIndex,
					offset,
					LootConfig.placementFootprint / 2,
					shelfSeparation
				)
			then
				return offset
			end
		end
	end

	-- Nothing safe and peripheral exists in this room. The caller may try another room; it may not
	-- discard reservations or manufacture a centre placement that changes the exploration reward.
	return nil
end

local function moduleById(id: Types.RoomModuleId): Types.RoomModuleDef?
	for _, def in FloorsConfig.roomModules do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Grounded rows need only their ordinary spawn disc. A roof-bound row's home is the centre of a
-- territory, so planning and structural carving must protect the full root leash plus body radius.
local function threatStructuralClearanceRadius(threatId: Types.ThreatId): number
	local def = ThreatsConfig.definitions[threatId]
	if def ~= nil then
		local roofClearance = ThreatRules.roofStructuralClearanceRadius(def)
		if roofClearance ~= nil then
			return roofClearance
		end
	end
	return FloorsConfig.terrain.gameplaySpawnRadius
end

-- A SEALED BLAST VAULT (Config/Dynamite.vault). Recognised by module id, the same way the Warden's den
-- is, so every pass that has to leave one alone asks one question in one shape.
--
-- WHAT EVERY CALLER OF THIS IS PROTECTING. A vault is guaranteed ore behind a door that costs a rare
-- consumable and a floor-wide noise event to open. Stacking anything else on it — a second barrier, a
-- falling formation, a lurker's arch, a fire that could block the only way out — would turn one clean
-- trade into an unreadable pile, so the answer is always "not here".
local function isBlastVault(room: Types.RoomPlacement?): boolean
	return room ~= nil and room.moduleId == DynamiteConfig.vault.roomModuleId
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
	lockedStoreRoomIndex: number?,
	threatSpawns: { Types.ThreatSpawn },
	reservations: { PlacementReservations.Reservation },
	hazards: { Types.HazardPlacement },
	groundPatches: { Types.GroundPatch },
	rng: Random
): { Types.DripstonePlacement }
	local config = HazardsConfig.unstableDripstone
	local placementProbe = FloorsConfig.geometry.placementProbe
	local shelfTransition = placementProbe.placementPadMarginStuds + placementProbe.placementPadBlendStuds
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
			or roomIndex == lockedStoreRoomIndex
			or room.moduleId == StoneWardenConfig.roomModuleId
			or isBlastVault(room)
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
			-- Falling formations are planned after pickups and authoritative spawn footprints. Preserve
			-- their exact X/Z instead of allowing a later builder to relocate either participant.
			if
				PlacementReservations.overlaps(reservations, roomIndex, offset, variant.triggerRadius, shelfTransition)
			then
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
		-- Provisional. Every room's real footprint is rolled once the graph and the loop edges are
		-- final (see `plan`), because a shape has to be validated against the doorways it will
		-- actually have.
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
			and not isBlastVault(rooms[index])
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
	rng: Random
): { Types.VinePlacement }
	local indicesByCell: { [string]: number } = {}
	for index, room in rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end

	local placements: { Types.VinePlacement } = {}
	local sealed: { VineRules.Doorway } = {}
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
				-- The store doorway was seeded above as its paid barrier. Do not add the same physical
				-- curtain again through the ordinary candidate pass.
				or index == lockedStoreRoomIndex
				or neighbor == lockedStoreRoomIndex
				or room.moduleId == StoneWardenConfig.roomModuleId
				or rooms[neighbor].moduleId == StoneWardenConfig.roomModuleId
				-- A vault's one doorway already carries a blast door. A curtain across it would be a
				-- second barrier on the same opening, and burning through it would still leave the rock.
				or isBlastVault(room)
				or isBlastVault(rooms[neighbor])
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
			or isBlastVault(rooms[index])
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
--   * NEVER on a pickup this floor has already placed. Deposits and loot are rolled against the SAME
--     wall band — both hug the rock, both at a similar inset — so this is a collision the placement
--     rules make likely rather than a freak one, and a seam is a solid rock the item then sits inside.
--
-- A floor that cannot satisfy all of that simply carries no deposit. The count is reduced; the
-- safety rules are never relaxed to reach it.
local function planDeposits(
	family: CaveFamilyRules.CaveFamilyProfile,
	depth: number,
	rooms: { Types.RoomPlacement },
	masks: { [number]: RoomFootprint.OpenMask },
	groundFields: { [number]: GroundGeometry.Field },
	roofFields: { [number]: RoofGeometry.Field },
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	threatSpawns: { Types.ThreatSpawn },
	lootSpawns: { Types.LootSpawn },
	hazards: { Types.HazardPlacement },
	dripstones: { Types.DripstonePlacement },
	vines: { Types.VinePlacement },
	unlockedNodes: { [string]: boolean },
	lockedStoreRoomIndex: number?,
	blastVaults: { Types.BlastVaultPlacement },
	guaranteedCacheLayouts: { [number]: GuaranteedCacheLayout },
	rng: Random
): { Types.DepositPlacement }
	local target = MiningRules.targetCount(depth, rng:NextNumber())
	-- A floor with no ordinary seam can still hold a store or a vault: both are guaranteed content
	-- behind a barrier the player paid to remove, not a share of the floor's own budget.
	if target <= 0 and lockedStoreRoomIndex == nil and #blastVaults == 0 then
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
			-- Vaults are stocked BELOW, outside the floor's target count, exactly as the locked store
			-- is. Leaving them in the ordinary rotation would let a floor spend its one seam on a room
			-- nobody can reach without a stick.
			and not isBlastVault(rooms[index])
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
	local placementProbe = FloorsConfig.geometry.placementProbe
	-- A deposit's seating shelf extends beyond its measured support ring. Two seams in a vault must
	-- stay far enough apart that neither shelf transition reaches the other's eight support samples.
	local depositShelfSeparation = math.max(
		reserved,
		MiningConfig.visual.surfaceProbeRadius * 2
			+ placementProbe.placementPadMarginStuds
			+ placementProbe.placementPadBlendStuds
	)
	-- The standing-room reservation already supplies most of the side-wall clearance. Use whichever
	-- is larger rather than stacking both buffers and accidentally removing seams from narrow rooms.
	local surfaceSafeWidth = math.max(reserved, (MiningConfig.visual.surfaceProbeRadius + placementSurfaceMargin()) * 2)
	local footprint = Vector3.new(surfaceSafeWidth, 0, surfaceSafeWidth)

	-- Declared here rather than beside the placement passes below because `tryPlaceAt` reads it: a
	-- candidate offset has to be separated from the seams already accepted on this floor, and a blast
	-- vault is the first room allowed to hold more than one.
	local placements: { Types.DepositPlacement } = {}

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
	-- for someone standing still through a swing, so both random wall pockets and authored cache
	-- alcoves go through it unchanged. A reserved cache may widen the shaped-room mask, but it never
	-- relaxes headroom, doorway, water, hazard, threat, loot, or seam separation.
	local function tryPlaceAt(roomIndex: number, offset: Vector3, reservedCacheSlot: boolean?): Types.DepositPlacement?
		local room = rooms[roomIndex]
		local groundField = groundFields[roomIndex]
		local roofField = roofFields[roomIndex]
		local contained = if reservedCacheSlot
			then fitsInsideRoom(nil, offset, footprint)
			else fitsInsideRoom(masks[roomIndex], offset, footprint)
		if
			groundField == nil
			or roofField == nil
			or not contained
			or not placementShelfHasHeadroom(
				room,
				groundField,
				roofField,
				offset,
				MiningConfig.visual.surfaceProbeRadius
			)
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
		-- A SEAM IS NOT PLACED ON TOP OF A PICKUP. Loot is planned before deposits and hugs the same wall
		-- band from the same four bearings, so without this the two rolls collide regularly — and because
		-- the seam is a solid boulder shouldered into the rock, the collision buries the item inside it:
		-- visible only as a floating prompt in a wall, and on the wrong side of the geometry to reach.
		--
		-- The separation is `reserved`, the same distance two seams keep from each other, because it is
		-- the same requirement: the seam plus the dry ground a player stands on to work it. An item inside
		-- that disc would put a pickup prompt underfoot for the whole of a swing even when it was not
		-- actually buried.
		for _, spawn in lootSpawns do
			if spawn.roomIndex == roomIndex then
				local delta = spawn.offset - offset
				if Vector3.new(delta.X, 0, delta.Z).Magnitude < reserved then
					return nil
				end
			end
		end
		-- SEAMS DO NOT SHARE A SHELF. Every ordinary room takes at most one deposit, so this used to be
		-- unreachable; a blast vault takes up to three, and without this the room's own wall rotation
		-- could hand two of them the same pocket and stack one rock inside another. The separation holds
		-- both the dry standing footprint and the full shelf transition outside the other's support ring,
		-- so two seams in one vault remain two level places a player can actually work.
		for _, existing in placements do
			if existing.roomIndex == roomIndex then
				local delta = existing.localOffset - offset
				if Vector3.new(delta.X, 0, delta.Z).Magnitude < depositShelfSeparation then
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
		for stockIndex = 1, wanted do
			local index = storeIndex :: number
			local layout = guaranteedCacheLayouts[index]
			local cacheOffset = if layout ~= nil then layout.depositOffsets[stockIndex] else nil
			local placed = if cacheOffset ~= nil then tryPlaceAt(index, cacheOffset, true) else nil
			if placed == nil then
				-- The store is optional; the conservation check below removes its label and curtain if a
				-- future config change invalidates one of these authored peripheral slots.
				break
			end
			table.insert(placements, placed)
		end
	end

	-- EVERY BLAST VAULT'S GUARANTEED ORE (Config/Dynamite.vault.depositsMin/Max). Same exception, same
	-- reasoning, and the same refusal set as the locked store above: a room a player spent a rare
	-- consumable and a floor-wide noise event to open must never be empty, and nothing about HOW a seam
	-- is placed is relaxed to achieve that. The count is rolled per vault, so opening two on one floor
	-- is not the same room twice.
	--
	-- Outside `target`, like the store, so a vault is extra content rather than a seam taken from
	-- somewhere a player could have reached for free.
	for _, vault in blastVaults do
		local wanted = rng:NextInteger(
			math.max(0, math.floor(DynamiteConfig.vault.depositsMin)),
			math.max(0, math.floor(DynamiteConfig.vault.depositsMax))
		)
		local layout = guaranteedCacheLayouts[vault.roomIndex]
		for stockIndex = 1, wanted do
			local cacheOffset = if layout ~= nil then layout.depositOffsets[stockIndex] else nil
			local placed = if cacheOffset ~= nil then tryPlaceAt(vault.roomIndex, cacheOffset, true) else nil
			if placed == nil then
				-- Vault geometry and cache masks are authored to make this unreachable. Never weaken the
				-- placement contract with a random or navigation-centre escape hatch.
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
		-- Ordinary seams are exploration rewards and remain against the room geology. Paid caches use
		-- their reserved doorway-relative alcoves above; a free seam with no safe wall pocket is omitted
		-- rather than moved into the navigation centre.
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
	lockedStoreRoomIndex: number?,
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
	for _, index in pathBetween(rooms, entryRoomIndex, brazierRoomIndex) do
		onRoute[index] = true
	end
	for _, index in pathBetween(rooms, brazierRoomIndex, basinRoomIndex) do
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
			-- A store has one paid doorway and authored cache stock. A collidable cluster may neither
			-- consume that stock's alcove nor stand between the player and the only exit.
			or roomIndex == lockedStoreRoomIndex
			-- A vault has one doorway. An `obstructs` cluster burning in there could stand between the
			-- player and their only way out, which no other cluster in the game can ever do.
			or isBlastVault(room)
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
	-- World X/Z origin for the local room grid. Live runs set this from the previous floor's ladder;
	-- tests and standalone tooling default to the surface origin.
	worldOrigin: Vector3?,
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
	-- row would vanish whenever the buyer was not the party's leader.
	unlockedNodes: { [string]: boolean }?,
	-- THE EXPEDITION'S OWN SEED, not this floor's. Floors are planned independently and out of order,
	-- so a schedule that has to be right ACROSS floors — currently only dynamite supply, which promises
	-- a stick every one-to-three floors — cannot be derived from `rng`, which is already a function of
	-- this one depth. `Logic/DynamiteRules.supplyForDepth` walks the run's gaps from this value.
	-- Absent means zero, which is a valid schedule and the correct reading for a test or a tool.
	runSeed: number?,
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
	local runSeed = request.runSeed or 0
	local requestedOrigin = request.worldOrigin or Vector3.zero
	local worldOrigin = Vector3.new(requestedOrigin.X, 0, requestedOrigin.Z)

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

	-- THE COMPLETION CHAMBER is anchored to the room farthest from entry that still has an open
	-- neighbouring grid cell, so the Basin can always attach directly beyond it. Scanning by distance
	-- and skipping any farthest candidate that turns out to be fully boxed in by other rooms' occupied
	-- cells prevents the Basin from silently landing on an unrelated room.
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

	-- ALL THREE PER-FLOOR FIXTURES SHARE ONE CHAMBER (owner decision). The Cauldron stands at its
	-- centre, the Gas Lantern in one corner and the Descent Ladder in the other, so the room where a
	-- floor is scored is also the room where it ends — you stand between the machine that banks your
	-- haul and the machine that takes you deeper, and pick one. That fork was previously spread over
	-- two rooms joined by a doorway, which made the decision a walk rather than a look.
	--
	-- KEPT AS A SEPARATE PLAN FIELD RATHER THAN DELETED, and deliberately. Every downstream refusal
	-- ("never in the entry, Basin or Brazier room", "never on the guaranteed route", "a vault is never
	-- the completion room") keeps asking its own question and simply gets the same answer twice, so
	-- nothing had to learn that the two rooms merged — and separating them again later is one line
	-- here rather than an unpicking of a dozen call sites. The room the Basin hangs off is now an
	-- ordinary cave room and is free to hold ordinary content.
	local brazierRoomIndex = basinRoomIndex

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
				-- and this room does not have its final doorways yet — the loop pass still runs below.
				-- `layOutWarden` fixes every offset once it has.
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

	-- BLAST VAULTS (Config/Dynamite.vault). Sealed dead-end pockets full of ore and empty of creatures,
	-- opened by a stick of dynamite and by nothing else.
	--
	-- ATTACHED HERE, AFTER THE LOOP PASS, AND THAT ORDER IS THE SAFETY PROOF. A vault is a brand-new
	-- cell with exactly one doorway, added once the only pass that could have given it a second one has
	-- already run. So it is a leaf by construction rather than by a check: nothing behind that door is
	-- ever on the way to anywhere, and blowing it open can never be progression. The Warden's den is
	-- attached before the loop pass precisely because it is allowed to become a through-room; a vault
	-- is not.
	--
	-- The rolls are consumed unconditionally so a floor with no spare side draws the same values from
	-- the seeded stream as one that places both vaults — the same rule every optional branch here obeys.
	local blastVaults: { Types.BlastVaultPlacement } = {}
	local blastVaultRooms: { [number]: boolean } = {}
	if DynamiteConfig.enabled and DynamiteConfig.vault.enabled and depth >= DynamiteConfig.vault.minDepth then
		local wanted = 0
		if rng:NextNumber() < DynamiteConfig.vault.chancePerFloor then
			wanted = 1
			if rng:NextNumber() < DynamiteConfig.vault.secondVaultChance then
				wanted = 2
			end
		end
		wanted = math.min(wanted, math.max(0, math.floor(DynamiteConfig.vault.maxPerFloor)))
		local style = CaveFamilyRules.blastDoorStyle(family)
		for _ = 1, wanted do
			-- Re-read the open sides every iteration: attaching the first vault occupies a cell and
			-- consumes one of its parent's connection slots, so the second has to see the floor as it is
			-- now rather than as it was.
			local sides: { { roomIndex: number, direction: Types.Direction } } = {}
			for _, side in openSides(rooms, occupied, true) do
				-- Never hung off a mandatory room. A vault door in the entry, the Basin or the Brazier
				-- room would put a locked, unopenable-looking wall in the one place a player is
				-- guaranteed to stand and stare at, and a Warden den already owns its own doorless wall.
				if
					side.roomIndex ~= entryRoomIndex
					and side.roomIndex ~= basinRoomIndex
					and side.roomIndex ~= brazierRoomIndex
					and rooms[side.roomIndex].moduleId ~= StoneWardenConfig.roomModuleId
					and not blastVaultRooms[side.roomIndex]
				then
					table.insert(sides, side)
				end
			end
			if #sides == 0 then
				break
			end
			local side = sides[rng:NextInteger(1, #sides)]
			local roomIndex = attachRoom(family, rooms, occupied, side, "BlastVault", rng)
			rooms[roomIndex].ceilingHeight = DynamiteConfig.vault.ceilingHeight
			blastVaultRooms[roomIndex] = true
			table.insert(blastVaults, {
				roomIndex = roomIndex,
				-- Recorded from the VAULT side, pointing back at the room it hangs off, exactly as a
				-- vine curtain records its own side of a shared opening.
				direction = OPPOSITE[side.direction],
				-- Where the charge pocket sits on the face. Kept off the extreme edges so the socket is
				-- never half-buried in the arch, and rolled so two doors on one floor differ.
				socketFraction = rng:NextNumber(0.34, 0.66),
				socketHeightFraction = rng:NextNumber(0.38, 0.54),
				visualSeed = rng:NextInteger(1, 2_000_000_000),
				style = style,
			})
		end
	end
	-- Water may reward exploration but can never be the only route from spawn to the safe Basin.
	guaranteeDryRoute(rooms, entryRoomIndex, basinRoomIndex, rng)
	-- Then hold the floor to its pool budget: the dry route can convert away every pool the assembly
	-- rolled, and a lucky assembly can roll far more than a floor should carry.
	enforceFloodedBudget(rooms, entryRoomIndex, basinRoomIndex, floodedFloor, rng)

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
	-- room will actually have, and a room does not have its final doorways until the loop pass is
	-- done. It happens BEFORE everything below because every placement from here on
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
			-- A vault stays a rectangle too. It is a small room whose ONE doorway carries a fixture and
			-- which has to hold up to three seams with standing room at each; a shape roll that ate a
			-- corner would quietly take a seam out of the room the player just spent a stick to open.
			or isBlastVault(room)
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
	-- Wick-pack bodies (shared/Enemies). Placed after the threat budget, against the same
	-- reservations, so the two rosters cannot spawn on top of each other.
	local enemySpawns: { Types.EnemySpawn } = {}

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
			local structuralRadius = threatStructuralClearanceRadius(threatId)
			local structuralFootprint = Vector3.new(structuralRadius * 2, 0, structuralRadius * 2)
			for _ = 1, 32 do
				local rolled = Vector3.new(
					rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4),
					0,
					rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4)
				)
				-- Pulled onto the room's real floor if the roll landed in the rock a shape left behind.
				local anchored = anchorInside(masks[roomIndex], rolled, structuralFootprint)
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
						structuralRadius,
						FloorsConfig.terrain.gameplaySpawnSeparation
					)
				then
					table.insert(threatSpawns, {
						threatId = threatId,
						roomIndex = roomIndex,
						offset = offset,
					})
					PlacementReservations.add(reservations, roomIndex, offset, structuralRadius, "Threat")
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

	-- THE WICK-PACK ROSTER (Logic/EnemySpawnRules, shared/Enemies).
	--
	-- Placed here, immediately after the ordinary threat budget and against the SAME reservation set,
	-- which is the whole reason it lives at this point in the function rather than in a pass of its
	-- own: a Longarm and a Knotwalker that spawned on the same square would be two bodies inside each
	-- other, and reservations are what already prevents that for everything else on a floor.
	--
	-- ROOM SIZE IS A REAL CONSTRAINT FOR TWO OF THEM. A Gnawer charges in a straight line and needs
	-- somewhere to be dodged; a Longarm reaching nine studs in a corridor is not an encounter, it is a
	-- toll. Both therefore ask the room how wide it is before taking it, and simply do not spawn on a
	-- floor that has nowhere suitable — an absent creature is always better than an unfair one.
	local enemyBudget = EnemySpawnRules.budgetForDepth(depth, rng)

	-- The narrowest open span across this room, in studs.
	--
	-- Read off the room's own SHAPE rather than off the grid cell it sits in, because shapes are what
	-- made this question worth asking: a room can be a full rectangle or a narrow capsule on the same
	-- cell, and only one of those has anywhere to dodge a charge. `primaryX`/`primaryZ` are the shape's
	-- half-extents, so the smaller of the two doubled is the tightest way through it.
	local function roomClearWidth(roomIndex: number): number
		local room = rooms[roomIndex]
		if room == nil then
			return 0
		end
		local shape = room.footprint
		return math.min(shape.primaryX, shape.primaryZ) * 2
	end

	-- One body of `enemyId`, in the first eligible room from `startIndex` wide enough to hold it.
	-- Walks the rotation exactly as `placeThreat` does and for the same reason: a floor that rolled a
	-- Gnawer should get one, not lose it because the shuffle happened to offer a capsule first.
	local function placeEnemy(enemyId: string, startIndex: number, minimumWidth: number): boolean
		if #eligible == 0 then
			return false
		end
		local radius = FloorsConfig.terrain.gameplaySpawnRadius
		local footprint = Vector3.new(radius * 2, 0, radius * 2)
		for step = 0, #eligible - 1 do
			local roomIndex = eligible[(startIndex + step - 1) % #eligible + 1]
			if roomClearWidth(roomIndex) < minimumWidth then
				continue
			end
			local room = rooms[roomIndex]
			for _ = 1, 24 do
				local rolled = Vector3.new(
					rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4),
					0,
					rng:NextNumber(-FloorsConfig.geometry.cellSize / 4, FloorsConfig.geometry.cellSize / 4)
				)
				local anchored = anchorInside(masks[roomIndex], rolled, footprint)
				if anchored == nil then
					continue
				end
				local offset = anchored :: Vector3
				if
					not blocksDoorway(room, depth, family.id, offset, footprint)
					and not overlapsWater(hazards, roomIndex, offset, footprint)
					and not PlacementReservations.overlaps(
						reservations,
						roomIndex,
						offset,
						radius,
						FloorsConfig.terrain.gameplaySpawnSeparation
					)
				then
					table.insert(enemySpawns, {
						enemyId = enemyId,
						roomIndex = roomIndex,
						offset = offset,
						-- Drawn from the floor's own RNG, so the same floor seed dresses the same
						-- creature the same way every time it is built.
						seed = rng:NextInteger(1, 2 ^ 30),
					})
					PlacementReservations.add(reservations, roomIndex, offset, radius, "Threat")
					return true
				end
			end
		end
		return false
	end

	local placedGnawer = false
	for _ = 1, enemyBudget.gnawers do
		if
			placeEnemy(
				"StoneGnawer",
				rng:NextInteger(1, math.max(#eligible, 1)),
				EnemySpawnRules.minimumGnawerRoomWidth()
			)
		then
			placedGnawer = true
		end
	end
	for _ = 1, enemyBudget.longarms do
		-- GNAWER + LONGARM IS ONLY ALLOWED IN A GENUINELY LARGE SPACE. Both punish being in the open,
		-- and ENCOUNTERS.md calls the pair "miserable in a corridor" — so when a Gnawer already has
		-- this floor, the Longarm needs a room big enough that the two are separable problems.
		local minimumWidth = if placedGnawer then 40 else 24
		placeEnemy("Longarm", rng:NextInteger(1, math.max(#eligible, 1)), minimumWidth)
	end
	-- Broods last: they are the most tolerant of a tight room and should take whatever is left rather
	-- than consuming the good rooms the tier-3 bodies need.
	for _ = 1, enemyBudget.broods do
		placeEnemy("WaxGrub", rng:NextInteger(1, math.max(#eligible, 1)), 0)
	end

	-- THE DEAD CANDLE (Config/DeadCandle, Logic/DeadCandleRules). Placed HERE — after the ordinary
	-- threat budget and before everything that reads `threatSpawns` — because its three flies are
	-- ordinary threat spawns and have to be visible to every rule that follows: the roof-dressing
	-- reservation FloorBuilder derives from them, and the double-jeopardy rule that keeps unstable
	-- formations out of a room holding a no-warning snuffer. Placing it later would have produced a
	-- tableau with stalactites hanging over it, which DESIGN §9 forbids.
	--
	-- The roll is consumed unconditionally at qualifying depth, on the same reasoning as the locked
	-- store below: whether a floor HAS one must not shift every later roll on the floor.
	local lootSpawns: { Types.LootSpawn } = {}
	local deadCandle: Types.DeadCandlePlacement? = nil
	if DeadCandleRules.depthAllows(depth) then
		local wanted = rng:NextNumber() < DeadCandleConfig.chancePerEligibleFloor
		local protectedIndices: { [number]: boolean } = {
			[entryRoomIndex] = true,
			[basinRoomIndex] = true,
			[brazierRoomIndex] = true,
		}
		if warden ~= nil then
			protectedIndices[warden.roomIndex] = true
		end
		-- Never in a vault. The tableau's whole point is three flies living on the loot, and a vault is
		-- the one room in the game that promises no creature is behind the door.
		for _, vault in blastVaults do
			protectedIndices[vault.roomIndex] = true
		end
		local candidates: { number } = {}
		for index, room in rooms do
			if DeadCandleRules.roomIsEligible(room, index, protectedIndices, moduleById(room.moduleId)) then
				table.insert(candidates, index)
			end
		end
		shuffle(candidates, rng)

		local layoutConfig = DeadCandleConfig.layout
		local flyStructuralRadius = threatStructuralClearanceRadius(DeadCandleConfig.threatId :: Types.ThreatId)
		-- Two different promises share this layout. The smaller footprint keeps the initial bodies and
		-- pickups out of doorway lanes and water; the structural footprint proves every fly can patrol
		-- its full territory without putting its silhouette in the room's rock.
		local tableauGameplayRadius = math.max(layoutConfig.flyRingRadius, layoutConfig.lootRingRadius)
			+ FloorsConfig.terrain.gameplaySpawnRadius
		local tableauStructuralRadius = layoutConfig.flyRingRadius + flyStructuralRadius
		local tableauGameplayFootprint =
			surfaceSafeFootprint(Vector3.new(tableauGameplayRadius * 2, 0, tableauGameplayRadius * 2))
		local tableauStructuralFootprint = Vector3.new(tableauStructuralRadius * 2, 0, tableauStructuralRadius * 2)
		local pieceFootprint =
			surfaceSafeFootprint(Vector3.new(LootConfig.placementFootprint, 0, LootConfig.placementFootprint))
		local flySpawnFootprint = surfaceSafeFootprint(
			Vector3.new(FloorsConfig.terrain.gameplaySpawnRadius * 2, 0, FloorsConfig.terrain.gameplaySpawnRadius * 2)
		)
		local flyStructuralFootprint = Vector3.new(flyStructuralRadius * 2, 0, flyStructuralRadius * 2)

		-- Every piece individually, not just the disc. The disc test proves the tableau fits the room;
		-- these prove no single pickup or fly ended up in a pool, in a doorway lane, or on top of
		-- something the floor placed earlier. A tableau that cannot satisfy all of them moves rather
		-- than being relaxed — the encounter is optional content and may never bend a placement rule.
		local function tableauFits(roomIndex: number, corpse: Vector3): boolean
			local room = rooms[roomIndex]
			local mask = masks[roomIndex]
			if
				blocksDoorway(room, depth, family.id, corpse, tableauGameplayFootprint)
				or overlapsWater(hazards, roomIndex, corpse, tableauGameplayFootprint)
				or PlacementReservations.overlaps(
					reservations,
					roomIndex,
					corpse,
					tableauStructuralRadius,
					FloorsConfig.terrain.gameplaySpawnSeparation
				)
			then
				return false
			end
			local pieces = DeadCandleRules.layout(corpse)
			for _, offset in pieces.loot do
				if
					not fitsInsideRoom(mask, offset, pieceFootprint)
					or blocksDoorway(room, depth, family.id, offset, pieceFootprint)
					or overlapsWater(hazards, roomIndex, offset, pieceFootprint)
				then
					return false
				end
			end
			for _, offset in pieces.flies do
				if
					not fitsInsideRoom(mask, offset, flyStructuralFootprint)
					or blocksDoorway(room, depth, family.id, offset, flySpawnFootprint)
				then
					return false
				end
			end
			return true
		end

		if wanted then
			for _, roomIndex in candidates do
				local placed = false
				for _ = 1, 24 do
					local rolled = Vector3.new(
						rng:NextNumber(-FloorsConfig.geometry.cellSize / 5, FloorsConfig.geometry.cellSize / 5),
						0,
						rng:NextNumber(-FloorsConfig.geometry.cellSize / 5, FloorsConfig.geometry.cellSize / 5)
					)
					local anchored = anchorInside(masks[roomIndex], rolled, tableauStructuralFootprint)
					if anchored == nil or not tableauFits(roomIndex, anchored) then
						continue
					end
					local corpse = anchored :: Vector3
					local pieces = DeadCandleRules.layout(corpse)
					deadCandle = {
						roomIndex = roomIndex,
						localOffset = corpse,
						visualSeed = rng:NextInteger(1, 1000000),
					}
					PlacementReservations.add(
						reservations,
						roomIndex,
						corpse,
						layoutConfig.corpseClearance,
						"DeadCandle"
					)
					-- The haul the dead player never carried out, rolled from the ordinary depth-and-family
					-- loot pool. It is not a special reward table: what makes it worth the flies is that
					-- there are three of them in one place, at a depth where three is a real haul.
					for _, offset in pieces.loot do
						local lootId = weightedLoot(depth, family.id, rng)
						if lootId == nil then
							break
						end
						table.insert(lootSpawns, { lootId = lootId, roomIndex = roomIndex, offset = offset })
						PlacementReservations.add(
							reservations,
							roomIndex,
							offset,
							LootConfig.placementFootprint / 2,
							"Loot"
						)
					end
					-- The nest. Ordinary spawns of an ordinary row: they share one room and their
					-- territories overlap over the corpse, which is the entire encounter.
					for _, offset in pieces.flies do
						table.insert(threatSpawns, {
							threatId = DeadCandleConfig.threatId :: Types.ThreatId,
							roomIndex = roomIndex,
							offset = offset,
						})
						PlacementReservations.add(reservations, roomIndex, offset, flyStructuralRadius, "Threat")
					end
					placed = true
					break
				end
				if placed then
					break
				end
			end
		end
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
		local function roomAlreadyOccupied(index: number): boolean
			for _, spawn in threatSpawns do
				if spawn.roomIndex == index then
					return true
				end
			end
			for _, hazard in hazards do
				if hazard.roomIndex == index then
					return true
				end
			end
			return false
		end
		local candidates: { number } = {}
		for index, room in rooms do
			if
				VineRules.roomMayBeSealed(room, index, protectedIndices)
				and room.moduleId ~= StoneWardenConfig.roomModuleId
				-- A store is named only after its authored cache layout is uncontested. Ordinary threats and
				-- hazards already own their rooms; choosing one of those dead ends and hoping random stock
				-- still fit is how a sealed room could end up empty.
				and not roomAlreadyOccupied(index)
				-- Never a vault. Two sealed rooms in one is one sealed room with two locks, and the
				-- store's own curtain would be unopenable until somebody spent a stick on the door.
				and not isBlastVault(room)
				-- Never the dead candle's room. A store is a promise — a guaranteed seam and guaranteed
				-- stock behind a curtain a player burned wax to open — and the tableau has already
				-- reserved the open ground that promise needs. Two authored encounters in one dead end
				-- would also read as one confusing pile rather than as either of them.
				and (deadCandle == nil or index ~= deadCandle.roomIndex)
			then
				table.insert(candidates, index)
			end
		end
		shuffle(candidates, rng)
		if wanted and #candidates > 0 then
			lockedStoreRoomIndex = candidates[1]
		end
	end

	-- Reserve the authored cache alcoves before any stock is planned. The builder repeats the same
	-- discs from the resulting loot/deposit rows, so a shaped room cannot close back over them.
	local guaranteedCacheLayouts: { [number]: GuaranteedCacheLayout } = {}
	for _, vault in blastVaults do
		local layout = guaranteedCacheLayout(rooms[vault.roomIndex])
		guaranteedCacheLayouts[vault.roomIndex] = layout
		reserveGuaranteedCache(masks[vault.roomIndex], layout)
	end
	if lockedStoreRoomIndex ~= nil then
		local storeIndex = lockedStoreRoomIndex :: number
		local layout = guaranteedCacheLayout(rooms[storeIndex])
		guaranteedCacheLayouts[storeIndex] = layout
		reserveGuaranteedCache(masks[storeIndex], layout)
	end

	-- The exact natural fields FloorBuilder will turn into Terrain, before per-object shelves are added.
	-- Placement uses them for local headroom as well as X/Z containment; the roof's edge blend does not
	-- guarantee minimum clearance, so a peripheral candidate must prove it explicitly.
	local placementSwellsByRoom: { [number]: { GroundGeometry.Swell } } = {}
	for _, patch in groundPatches do
		local list = placementSwellsByRoom[patch.roomIndex]
		if list == nil then
			list = {}
			placementSwellsByRoom[patch.roomIndex] = list
		end
		table.insert(list, {
			x = patch.localOffset.X,
			z = patch.localOffset.Z,
			radius = math.max(patch.size.X, patch.size.Z) / 2,
			height = patch.size.Y,
		})
	end
	local placementPoolsByRoom: { [number]: { GroundGeometry.Pool } } = {}
	for _, hazard in hazards do
		if
			hazard.hazardId == "Water"
			and hazard.localOffset ~= nil
			and hazard.size ~= nil
			and hazard.bedDepth ~= nil
		then
			local localOffset = hazard.localOffset :: Vector3
			local size = hazard.size :: Vector3
			placementPoolsByRoom[hazard.roomIndex] = {
				{
					x = localOffset.X,
					z = localOffset.Z,
					radius = (size.X + size.Z) / 4,
					depth = hazard.bedDepth :: number,
				},
			}
		end
	end
	local placementGroundFields: { [number]: GroundGeometry.Field } = {}
	local placementRoofFields: { [number]: RoofGeometry.Field } = {}
	for roomIndex, room in rooms do
		local flatSpots: { GroundGeometry.FlatSpot } = {}
		if roomIndex == brazierRoomIndex then
			table.insert(flatSpots, {
				x = -FloorsConfig.geometry.cellSize / 4,
				z = -FloorsConfig.geometry.cellSize / 4,
				r = 6,
			})
		end
		if deadCandle ~= nil and roomIndex == deadCandle.roomIndex then
			table.insert(flatSpots, {
				x = deadCandle.localOffset.X,
				z = deadCandle.localOffset.Z,
				r = DeadCandleConfig.layout.corpseClearance,
			})
		end
		if warden ~= nil and roomIndex == warden.roomIndex then
			for _, offset in { warden.pileOffset, warden.waxOffset, warden.counterDripstoneOffset } do
				table.insert(flatSpots, {
					x = offset.X,
					z = offset.Z,
					r = StoneWardenConfig.encounterClearance,
				})
			end
		end
		placementGroundFields[roomIndex] = GroundGeometry.fieldFor(
			room,
			depth,
			roomIndex == entryRoomIndex or roomIndex == basinRoomIndex or roomIndex == brazierRoomIndex,
			flatSpots,
			placementSwellsByRoom[roomIndex] or {},
			placementPoolsByRoom[roomIndex] or {},
			family.id
		)
		placementRoofFields[roomIndex] = RoofGeometry.fieldFor(room, depth)
	end

	-- The rest of the floor's loot is planned only after the final pool layout exists. Earlier planning
	-- let a wall-pocket roll survive even when the same room later carved water through that shelf.
	-- (`lootSpawns` itself is declared above, because a dead candle stocks it before this point.)
	local lootRoomIndices: { number } = {}
	for index in rooms do
		if
			index ~= entryRoomIndex
			and index ~= basinRoomIndex
			and (warden == nil or index ~= warden.roomIndex)
			and index ~= lockedStoreRoomIndex
			-- Vaults are stocked separately below, for the same reason the locked store is: what is
			-- behind a sealed door has to be a promise, not a room that happened to win a shuffle.
			and not isBlastVault(rooms[index])
		then
			table.insert(lootRoomIndices, index)
		end
	end
	shuffle(lootRoomIndices, rng)

	-- Commit one pickup at a safe peripheral position, rotating through candidate rooms when the first
	-- room has no remaining shelf. This keeps the planned count when another room can carry it without
	-- ever dropping reservations or using the navigation centre as an escape hatch.
	local function commitLoot(lootId: Types.LootId, roomIndex: number, offset: Vector3)
		table.insert(lootSpawns, { lootId = lootId, roomIndex = roomIndex, offset = offset })
		PlacementReservations.add(reservations, roomIndex, offset, LootConfig.placementFootprint / 2, "Loot")
	end

	local function placeLootInRooms(lootId: Types.LootId, candidates: { number }, startIndex: number): boolean
		if #candidates == 0 then
			return false
		end
		for step = 0, #candidates - 1 do
			local candidateIndex = (startIndex + step - 1) % #candidates + 1
			local roomIndex = candidates[candidateIndex]
			local groundField = placementGroundFields[roomIndex]
			local roofField = placementRoofFields[roomIndex]
			if groundField == nil or roofField == nil then
				continue
			end
			local offset = plannedLootOffset(
				rooms[roomIndex],
				roomIndex,
				depth,
				family.id,
				masks[roomIndex],
				groundField,
				roofField,
				hazards,
				reservations,
				rng
			)
			if offset ~= nil then
				local plannedOffset = offset :: Vector3
				commitLoot(lootId, roomIndex, plannedOffset)
				return true
			end
		end
		return false
	end

	-- Guaranteed cache stock uses the reserved doorway-relative back-wall slot, never a runtime or
	-- navigation-centre fallback. The slot is inside the structural cell and the mask was unioned with
	-- its full shelf before this pass; these checks keep config changes from silently breaking that
	-- authored proof.
	local function placeGuaranteedLoot(lootId: Types.LootId, roomIndex: number, stockIndex: number): boolean
		local layout = guaranteedCacheLayouts[roomIndex]
		local groundField = placementGroundFields[roomIndex]
		local roofField = placementRoofFields[roomIndex]
		if layout == nil or stockIndex ~= 1 or groundField == nil or roofField == nil then
			return false
		end
		local offset = layout.lootOffset
		local room = rooms[roomIndex]
		local footprint =
			surfaceSafeFootprint(Vector3.new(LootConfig.placementFootprint, 0, LootConfig.placementFootprint))
		local probe = FloorsConfig.geometry.placementProbe
		local shelfSeparation = math.max(
			FloorsConfig.terrain.gameplaySpawnSeparation,
			probe.placementPadMarginStuds + probe.placementPadBlendStuds
		)
		if
			not fitsInsideRoom(nil, offset, footprint)
			or not placementShelfHasHeadroom(room, groundField, roofField, offset, LootConfig.placementFootprint / 2)
			or blocksDoorway(room, depth, family.id, offset, footprint)
			or overlapsWater(hazards, roomIndex, offset, footprint)
			or PlacementReservations.overlaps(
				reservations,
				roomIndex,
				offset,
				LootConfig.placementFootprint / 2,
				shelfSeparation
			)
		then
			return false
		end
		commitLoot(lootId, roomIndex, offset)
		return true
	end

	-- The store's guaranteed stock. Placed FIRST and separately from the ordinary rotation, so it is a
	-- promise the room keeps rather than a room that happened to win a shuffle — a sealed vault a player
	-- burned their way into must never be empty.
	if lockedStoreRoomIndex ~= nil then
		local storeIndex = lockedStoreRoomIndex :: number
		for stockIndex = 1, math.max(0, math.floor(LampConfig.generation.lockedStore.loot)) do
			local lootId = weightedLoot(depth, family.id, rng)
			if lootId == nil then
				lockedStoreRoomIndex = nil
				break
			end
			if not placeGuaranteedLoot(lootId, storeIndex, stockIndex) then
				-- Do not label or seal an empty room. The store feature is optional; its promise is not.
				lockedStoreRoomIndex = nil
				break
			end
		end
	end
	-- Every blast vault's guaranteed pickup, from the ordinary depth-and-family pool. The ore is what a
	-- vault is FOR; this is the small extra that makes opening one feel like finding a cache rather
	-- than finding a wall with rocks behind it.
	for _, vault in blastVaults do
		for stockIndex = 1, math.max(0, math.floor(DynamiteConfig.vault.loot)) do
			local lootId = weightedLoot(depth, family.id, rng)
			if lootId == nil then
				break
			end
			if
				not placeGuaranteedLoot(lootId, vault.roomIndex, stockIndex)
				and not placeLootInRooms(lootId, { vault.roomIndex }, 1)
			then
				break
			end
		end
	end

	-- THE FLOOR'S DYNAMITE SUPPLY (Config/Dynamite.supply, Logic/DynamiteRules.supplyForDepth).
	--
	-- EMITTED INTO `lootSpawns` LIKE ANY OTHER PICKUP, and that is the whole trick: every downstream
	-- system — peripheral placement, the surface probe that keeps an item out of the ground, the
	-- prompt, the pickup message, the first-sighting hint — treats a stick exactly as it treats a block
	-- of Life Wax, with no knowledge that dynamite exists. The Dead Candle stocks itself the same way.
	--
	-- IT IS NOT A ROLL. The schedule is walked from the RUN seed rather than this floor's, so the cave
	-- keeps a promise across floors ("a stick every one to three") that a per-floor chance could not:
	-- see `DynamiteRules.supplyForDepth` for why the two are not the same thing at the same average.
	--
	-- NEVER IN A VAULT. A stick sealed behind a door that needs a stick is the one placement this item
	-- must never produce, and `lootRoomIndices` already excludes vaults — so this reuses that list
	-- rather than restating the rule.
	if DynamiteConfig.enabled and #lootRoomIndices > 0 then
		local supply = DynamiteRules.supplyForDepth(runSeed, depth)
		local supplyRows: { Types.LootId } = {}
		for _ = 1, supply.sticks do
			table.insert(supplyRows, "DynamiteStick")
		end
		for _ = 1, supply.crates do
			table.insert(supplyRows, "DynamiteCrate")
		end
		for rowIndex, lootId in supplyRows do
			-- Offset into the rotation so a stick and a crate on the same floor are never asked to share
			-- one room's shelf.
			placeLootInRooms(lootId, lootRoomIndices, (rowIndex - 1) % #lootRoomIndices + 1)
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
			placeLootInRooms(lootId, lootRoomIndices, (_ - 1) % #lootRoomIndices + 1)
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
		lockedStoreRoomIndex,
		threatSpawns,
		reservations,
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
	-- MossFire is the final placement pass and consults the shared reservation registry. Commit the
	-- complete dripstone list here (including authored Warden formations) so growth can never be
	-- planned through a trigger footprint even if a future room exemption changes.
	for _, formation in dripstones do
		local variant = DripstoneRules.variantById(formation.variantId)
		if variant ~= nil then
			PlacementReservations.add(
				reservations,
				formation.roomIndex,
				formation.localOffset,
				variant.triggerRadius,
				"Dripstone"
			)
		end
	end

	local vines = planVines(family, depth, rooms, entryRoomIndex, basinRoomIndex, lockedStoreRoomIndex, rng)

	-- Deposits are planned after every hazard, threat, curtain and pickup they must avoid. MossFire is
	-- deliberately later, and reads the seam reservations committed below. Because `lootSpawns` is
	-- handed in here too, neither category can be dropped on top of the other.
	local lurkers = planLurkers(family.id, depth, rooms, entryRoomIndex, basinRoomIndex, brazierRoomIndex, vines, rng)
	local deposits = planDeposits(
		family,
		depth,
		rooms,
		masks,
		placementGroundFields,
		placementRoofFields,
		entryRoomIndex,
		basinRoomIndex,
		brazierRoomIndex,
		threatSpawns,
		lootSpawns,
		hazards,
		dripstones,
		vines,
		unlockedNodes,
		lockedStoreRoomIndex,
		blastVaults,
		guaranteedCacheLayouts,
		rng
	)
	if lockedStoreRoomIndex ~= nil then
		local storeIndex = lockedStoreRoomIndex :: number
		local stockedLoot, stockedDeposits = 0, 0
		for _, spawn in lootSpawns do
			if spawn.roomIndex == storeIndex then
				stockedLoot += 1
			end
		end
		for _, deposit in deposits do
			if deposit.roomIndex == storeIndex then
				stockedDeposits += 1
			end
		end
		local storeConfig = LampConfig.generation.lockedStore
		if stockedLoot < storeConfig.loot or stockedDeposits < storeConfig.deposits then
			-- A store is optional, but a store that exists is a promise. If a future config/model change
			-- invalidates an authored slot, remove the label and its one curtain instead of leaving a paid
			-- sealed room with partial stock. Any already-planned reward simply becomes ordinary loot.
			local storeRoom = rooms[storeIndex]
			for vineIndex = #vines, 1, -1 do
				local vine = vines[vineIndex]
				local vineRoom = rooms[vine.roomIndex]
				local direction = OFFSETS[vine.direction]
				local touchesStore = vine.roomIndex == storeIndex
					or (
						vineRoom.gridX + direction.x == storeRoom.gridX
						and vineRoom.gridZ + direction.z == storeRoom.gridZ
					)
				if touchesStore then
					table.remove(vines, vineIndex)
				end
			end
			lockedStoreRoomIndex = nil
		end
	end
	-- Deposits are planned after the other gameplay content, but MossFire is deliberately last and
	-- reads this shared registry. Commit each seam's standing area and full shelf transition before
	-- that pass so a flammable/collidable cluster cannot grow through the ore or its working space.
	local placementProbe = FloorsConfig.geometry.placementProbe
	local depositReservationRadius = math.max(
		(MiningConfig.placement.footprint + MiningConfig.placement.standingClearance) / 2,
		MiningConfig.visual.surfaceProbeRadius
			+ placementProbe.placementPadMarginStuds
			+ placementProbe.placementPadBlendStuds
	)
	for _, deposit in deposits do
		PlacementReservations.add(
			reservations,
			deposit.roomIndex,
			deposit.localOffset,
			depositReservationRadius,
			"Deposit"
		)
	end

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
		lockedStoreRoomIndex,
		reservations,
		hazards,
		rng
	)

	return {
		depth = localFloor,
		globalDepth = depth,
		familyId = family.id,
		worldOrigin = worldOrigin,
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
		enemySpawns = enemySpawns,
		lootSpawns = lootSpawns,
		hazards = hazards,
		dripstones = dripstones,
		vines = vines,
		lurkers = lurkers,
		warden = warden,
		deadCandle = deadCandle,
		deposits = deposits,
		blastVaults = blastVaults,
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
	local worldOrigin = Vector3.zero
	for localFloor = 1, plannedCount do
		local globalDepth = DepthRules.getGlobalDepth(start, localFloor)
		local plan = FloorPlanner.plan({
			globalDepth = globalDepth,
			localFloor = localFloor,
			rng = Random.new(DepthRules.getFloorSeed(seed, tierId, globalDepth)),
			familyId = familyId,
			worldOrigin = worldOrigin,
		})
		table.insert(plans, plan)
		worldOrigin = FloorStacking.nextFloorOrigin(plan, FloorsConfig.geometry.cellSize)
	end
	return plans
end

return FloorPlanner

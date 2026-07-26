--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local FloorPlanner = require(script.Parent.Parent.Logic.FloorPlanner)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local VinesConfig = require(script.Parent.Parent.Config.Vines)
local DepthConfig = require(script.Parent.Parent.Config.Depth)
local DepthRules = require(script.Parent.Parent.Logic.DepthRules)
local DoorwayGeometry = require(script.Parent.Parent.Logic.DoorwayGeometry)
local VineRules = require(script.Parent.Parent.Logic.VineRules)
local DripstoneRules = require(script.Parent.Parent.Logic.DripstoneRules)
local GroundGeometry = require(script.Parent.Parent.Logic.GroundGeometry)
local RoofGeometry = require(script.Parent.Parent.Logic.RoofGeometry)

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

type DripstoneVariant = typeof(HazardsConfig.unstableDripstone.variants[1])

local function cellKey(x: number, z: number): string
	return x .. "," .. z
end

local function dripstoneVariantById(id: string): DripstoneVariant?
	for _, variant in HazardsConfig.unstableDripstone.variants do
		if variant.id == id then
			return variant
		end
	end
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

local function weightAtDepth(weights: { number }, depth: number): number
	if #weights == 0 then
		return 0
	end
	return math.max(0, weights[math.clamp(depth, 1, #weights)])
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

local function expectedThreatCount(plan: Types.FloorPlan, threatBudgetMultiplier: number?): number
	local hasEligibleRoom = false
	for index, room in plan.rooms do
		local def = moduleById(room.moduleId)
		if
			index ~= plan.entryRoomIndex
			and index ~= plan.basinRoomIndex
			and def ~= nil
			and roomHasThreatAtDepth(def, plan.globalDepth, room.ceilingHeight)
		then
			hasEligibleRoom = true
			break
		end
	end
	if not hasEligibleRoom then
		return 0
	end

	local budgetIndex = math.clamp(plan.globalDepth, 1, #FloorsConfig.threatBudgetPerFloor)
	local multiplier = math.max(threatBudgetMultiplier or 1, 0)
	local base = FloorsConfig.threatBudgetPerFloor[budgetIndex] * DepthRules.getThreatBudgetMultiplier(plan.globalDepth)
	return math.max(0, math.floor(base * multiplier + 0.5))
end

local function hasDirection(doorways: { Types.Direction }, wanted: Types.Direction): boolean
	for _, direction in doorways do
		if direction == wanted then
			return true
		end
	end
	return false
end

-- Deliberately keyed on the CANONICAL depth, not the expedition ordinal: identical inputs must
-- produce an identical floor whichever floor of a run it happens to be.
local function planSignature(plan: Types.FloorPlan): string
	local pieces: { string } = {
		tostring(plan.globalDepth),
		tostring(plan.entryRoomIndex),
		tostring(plan.basinRoomIndex),
		tostring(plan.brazierRoomIndex),
	}
	for _, room in plan.rooms do
		table.insert(
			pieces,
			string.format(
				"R:%s:%d:%d:%s:%.12g",
				room.moduleId,
				room.gridX,
				room.gridZ,
				table.concat(room.doorways, ","),
				room.ceilingHeight
			)
		)
	end
	for _, spawn in plan.threatSpawns do
		table.insert(
			pieces,
			string.format(
				"T:%s:%d:%.12g:%.12g:%.12g",
				spawn.threatId,
				spawn.roomIndex,
				spawn.offset.X,
				spawn.offset.Y,
				spawn.offset.Z
			)
		)
	end
	for _, spawn in plan.lootSpawns do
		table.insert(
			pieces,
			string.format(
				"L:%s:%d:%.12g:%.12g:%.12g",
				spawn.lootId,
				spawn.roomIndex,
				spawn.offset.X,
				spawn.offset.Y,
				spawn.offset.Z
			)
		)
	end
	for _, hazard in plan.hazards do
		table.insert(
			pieces,
			string.format(
				"H:%s:%d:%s:%s:%s",
				hazard.hazardId,
				hazard.roomIndex,
				tostring(hazard.waterDepth),
				tostring(hazard.localOffset),
				tostring(hazard.size)
			)
		)
	end
	for _, vine in plan.vines do
		table.insert(pieces, string.format("V:%d:%s:%d", vine.roomIndex, vine.direction, vine.visualSeed))
	end
	for _, dripstone in plan.dripstones do
		table.insert(
			pieces,
			string.format(
				"D:%d:%.12g:%.12g:%.12g:%s:%d",
				dripstone.roomIndex,
				dripstone.localOffset.X,
				dripstone.localOffset.Y,
				dripstone.localOffset.Z,
				dripstone.variantId,
				dripstone.visualSeed
			)
		)
	end
	for _, patch in plan.groundPatches do
		table.insert(
			pieces,
			string.format(
				"G:%d:%.12g:%.12g:%.12g:%.12g:%.12g:%.12g",
				patch.roomIndex,
				patch.localOffset.X,
				patch.localOffset.Y,
				patch.localOffset.Z,
				patch.size.X,
				patch.size.Y,
				patch.size.Z
			)
		)
	end
	return table.concat(pieces, "|")
end

-- The combined guarantee for anyone who cannot swim deep OR burn vines open: a route from entry to
-- the Basin that crosses no flooded module and no vine curtain.
local function hasWaterFreePath(plan: Types.FloorPlan): boolean
	local indicesByCell: { [string]: number } = {}
	for index, room in plan.rooms do
		indicesByCell[cellKey(room.gridX, room.gridZ)] = index
	end
	local vined: { [string]: boolean } = {}
	for _, vine in plan.vines do
		vined[vine.roomIndex .. vine.direction] = true
		local room = plan.rooms[vine.roomIndex]
		local offset = OFFSETS[vine.direction]
		local neighborIndex = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
		if neighborIndex ~= nil then
			vined[neighborIndex .. OPPOSITE[vine.direction]] = true
		end
	end
	local queue = { plan.entryRoomIndex }
	local head = 1
	local visited: { [number]: boolean } = { [plan.entryRoomIndex] = true }
	while head <= #queue do
		local index = queue[head]
		head += 1
		if index == plan.basinRoomIndex then
			return true
		end
		local room = plan.rooms[index]
		for _, direction in room.doorways do
			if vined[index .. direction] then
				continue
			end
			local offset = OFFSETS[direction]
			local neighborIndex = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
			if neighborIndex == nil or visited[neighborIndex] then
				continue
			end
			local def = moduleById(plan.rooms[neighborIndex].moduleId)
			if neighborIndex == plan.basinRoomIndex or (def ~= nil and def.waterDepth == nil) then
				visited[neighborIndex] = true
				table.insert(queue, neighborIndex)
			end
		end
	end
	return false
end

local suite: Harness.Suite = {
	name = "FloorPlanner",
	tests = {
		Harness.test("the same seed reproduces every floor exactly", function()
			local first = FloorPlanner.planAll(731_947)
			local second = FloorPlanner.planAll(731_947)
			Harness.equal(#first, FloorsConfig.floorsPerRun)
			Harness.equal(#second, #first)
			for index, plan in first do
				Harness.equal(planSignature(plan), planSignature(second[index]), "seed changed at floor " .. index)
				Harness.equal(plan.depth, index)
			end
		end),

		Harness.test("unstable dripstones stay rare, inspectable, and spatially safe", function()
			local config = HazardsConfig.unstableDripstone
			local totalPlacements = 0
			for seed = 1, 16 do
				for _, plan in FloorPlanner.planAll(seed * 61_739) do
					local swellsByRoom: { [number]: { GroundGeometry.Swell } } = {}
					for _, patch in plan.groundPatches do
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
					for _, hazard in plan.hazards do
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
					local placementsByRoom: { [number]: number } = {}
					local hazardousRooms: { [number]: boolean } = {}
					local ordinaryRoomCount = 0
					for roomIndex in plan.rooms do
						if
							roomIndex ~= plan.entryRoomIndex
							and roomIndex ~= plan.basinRoomIndex
							and roomIndex ~= plan.brazierRoomIndex
						then
							ordinaryRoomCount += 1
						end
					end

					for placementIndex, placement in plan.dripstones do
						totalPlacements += 1
						Harness.expect(placement.roomIndex ~= plan.entryRoomIndex)
						Harness.expect(placement.roomIndex ~= plan.basinRoomIndex)
						Harness.expect(placement.roomIndex ~= plan.brazierRoomIndex)
						Harness.expect(placement.visualSeed >= 1 and placement.visualSeed <= 2_000_000_000)
						Harness.equal(placement.visualSeed, math.floor(placement.visualSeed))
						Harness.near(placement.localOffset.Y, 0)

						local room = plan.rooms[placement.roomIndex]
						Harness.expect(room ~= nil, "dripstone room index must resolve")
						Harness.expect(
							(room :: Types.RoomPlacement).ceilingHeight <= config.maxEligibleCeilingHeight,
							"unstable dripstone requires an inspectable ceiling"
						)

						local variant = dripstoneVariantById(placement.variantId)
						Harness.expect(variant ~= nil, "dripstone placement requires a configured variant")
						local resolvedVariant = variant :: DripstoneVariant
						local groundField = GroundGeometry.fieldFor(
							room :: Types.RoomPlacement,
							plan.depth,
							false,
							{},
							swellsByRoom[placement.roomIndex] or {},
							poolsByRoom[placement.roomIndex] or {}
						)
						local roofField = RoofGeometry.fieldFor(room :: Types.RoomPlacement, plan.depth)
						local groundHeight =
							GroundGeometry.offset(groundField, placement.localOffset.X, placement.localOffset.Z)
						local roofHeight = RoofGeometry.undersideHeight(
							(room :: Types.RoomPlacement).ceilingHeight,
							roofField,
							groundHeight,
							placement.localOffset.X,
							placement.localOffset.Z
						)
						Harness.expect(
							roofHeight - DripstoneRules.visualLength(resolvedVariant) - groundHeight
								>= config.minimumFallDistance - 1e-6,
							"planned formation did not retain its minimum real fall clearance"
						)
						local radialOffset = math.sqrt(
							placement.localOffset.X * placement.localOffset.X
								+ placement.localOffset.Z * placement.localOffset.Z
						)
						Harness.expect(radialOffset >= config.minCenterOffset - 1e-6)
						Harness.expect(radialOffset <= config.maxCenterOffset + 1e-6)

						local interiorRadius = FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.wallClearance
						local safetyRadius = resolvedVariant.triggerRadius + config.doorwaySafetyPadding
						Harness.expect(
							math.abs(placement.localOffset.X) + safetyRadius <= interiorRadius + 1e-6,
							"dripstone trigger footprint crossed the room's X bound"
						)
						Harness.expect(
							math.abs(placement.localOffset.Z) + safetyRadius <= interiorRadius + 1e-6,
							"dripstone trigger footprint crossed the room's Z bound"
						)
						for _, direction in (room :: Types.RoomPlacement).doorways do
							local normal = OFFSETS[direction]
							local toward = placement.localOffset.X * normal.x + placement.localOffset.Z * normal.z
							if
								toward + safetyRadius
								>= FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.doorClearanceDepth
							then
								local profile = DoorwayGeometry.profile(
									(room :: Types.RoomPlacement).gridX,
									(room :: Types.RoomPlacement).gridZ,
									direction,
									plan.depth
								)
								local lateral = placement.localOffset.X * math.abs(normal.z)
									+ placement.localOffset.Z * math.abs(normal.x)
								local laneHalf =
									math.max(FloorsConfig.terrain.doorClearanceWidth / 2, profile.width / 2)
								Harness.expect(
									lateral + safetyRadius < profile.offset - laneHalf
										or lateral - safetyRadius > profile.offset + laneHalf,
									"dripstone footprint blocked the real off-centre doorway"
								)
							end
						end

						for priorIndex = 1, placementIndex - 1 do
							local prior = plan.dripstones[priorIndex]
							if prior.roomIndex == placement.roomIndex then
								local dx = prior.localOffset.X - placement.localOffset.X
								local dz = prior.localOffset.Z - placement.localOffset.Z
								Harness.expect(
									dx * dx + dz * dz >= config.minFormationSpacing ^ 2 - 1e-6,
									"unstable formations were placed too close together"
								)
							end
						end

						placementsByRoom[placement.roomIndex] = (placementsByRoom[placement.roomIndex] or 0) + 1
						hazardousRooms[placement.roomIndex] = true
					end

					local maxPerRoom = if plan.depth <= 3
						then config.maxPerRoomEarly
						elseif plan.depth <= 6 then config.maxPerRoomMid
						else config.maxPerRoomDeep
					local hazardousRoomCount = 0
					for roomIndex, count in placementsByRoom do
						hazardousRoomCount += 1
						Harness.expect(count <= maxPerRoom, "room exceeded its depth-band formation cap")
						Harness.expect(hazardousRooms[roomIndex])
					end
					local hazardousRoomCap =
						math.max(1, math.floor(ordinaryRoomCount * config.maxHazardousRoomFraction))
					Harness.expect(
						hazardousRoomCount <= hazardousRoomCap,
						"too many ordinary rooms contained unstable formations"
					)
					Harness.expect(
						hazardousRoomCount <= ordinaryRoomCount - hazardousRoomCount,
						"most ordinary rooms must remain free of unstable formations"
					)

					local harmlessFormationCount = #plan.rooms
						* (
							FloorsConfig.caveDressing.ceilingFormationsPerRoom
							+ FloorsConfig.caveDressing.ceilingBouldersPerRoom
						)
					Harness.expect(
						#plan.dripstones <= math.floor(harmlessFormationCount * config.maxUnstableToHarmlessRatio),
						"unstable-to-harmless formation ratio exceeded its cap"
					)
				end
			end
			Harness.expect(totalPlacements > 0, "test seeds produced no unstable dripstones")
		end),

		Harness.test("every plan is a connected reciprocal grid with one safe Basin", function()
			for _, plan in FloorPlanner.planAll(91_337) do
				Harness.equal(
					#plan.rooms,
					DepthRules.getRoomCountTarget(plan.globalDepth) + 1,
					"ordinary rooms plus exactly one Basin expected"
				)
				Harness.expect(plan.entryRoomIndex >= 1 and plan.entryRoomIndex <= #plan.rooms)
				Harness.expect(plan.basinRoomIndex >= 1 and plan.basinRoomIndex <= #plan.rooms)
				Harness.expect(plan.brazierRoomIndex >= 1 and plan.brazierRoomIndex <= #plan.rooms)
				Harness.expect(plan.entryRoomIndex ~= plan.basinRoomIndex)
				Harness.expect(plan.brazierRoomIndex ~= plan.basinRoomIndex)
				Harness.equal(plan.rooms[plan.entryRoomIndex].gridX, 0)
				Harness.equal(plan.rooms[plan.entryRoomIndex].gridZ, 0)
				Harness.equal(plan.rooms[plan.basinRoomIndex].moduleId, "Basin")

				local basinCount = 0
				local indicesByCell: { [string]: number } = {}
				for index, room in plan.rooms do
					if room.moduleId == "Basin" then
						basinCount += 1
					end
					local key = cellKey(room.gridX, room.gridZ)
					Harness.isNil(indicesByCell[key], "two rooms occupy " .. key)
					indicesByCell[key] = index
				end
				Harness.equal(basinCount, 1)

				for _, room in plan.rooms do
					for _, direction in room.doorways do
						local offset = OFFSETS[direction]
						local neighborIndex = indicesByCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
						Harness.expect(neighborIndex ~= nil, "doorway points into an empty grid cell")
						local neighbor = plan.rooms[neighborIndex :: number]
						Harness.expect(
							hasDirection(neighbor.doorways, OPPOSITE[direction]),
							"neighbor is missing the reciprocal doorway"
						)
					end
				end

				local entry = plan.rooms[plan.entryRoomIndex]
				local brazier = plan.rooms[plan.brazierRoomIndex]
				local brazierDistance = math.abs(brazier.gridX - entry.gridX) + math.abs(brazier.gridZ - entry.gridZ)
				local farthestDistance = 0
				for index, room in plan.rooms do
					if index ~= plan.basinRoomIndex then
						farthestDistance = math.max(
							farthestDistance,
							math.abs(room.gridX - entry.gridX) + math.abs(room.gridZ - entry.gridZ)
						)
					end
				end
				Harness.equal(brazierDistance, farthestDistance, "brazier must be farthest from entry")
			end
		end),

		Harness.test("every generated floor has a water-free, vine-free route from entry to Basin", function()
			for seed = 1, 40 do
				for _, plan in FloorPlanner.planAll(seed * 7_919) do
					Harness.expect(hasWaterFreePath(plan), "water or vines blocked required route for seed " .. seed)
				end
			end
		end),

		-- Water is a per-FLOOR event. Two ways to get this wrong, both guarded here: the dry-route
		-- guarantee can convert away every pool a floor rolled (water disappears from the game), and
		-- a lucky assembly can flood half a floor.
		Harness.test("water appears on its configured share of floors, one pool at a time", function()
			local floorsWithWater = 0
			local totalFloors = 0
			for seed = 1, 40 do
				for _, plan in FloorPlanner.planAll(seed * 7_919) do
					totalFloors += 1
					local pools = 0
					for _, hazard in plan.hazards do
						if hazard.hazardId == "Water" then
							pools += 1
						end
					end
					Harness.expect(
						pools <= FloorsConfig.floodedRoomsPerFloor,
						string.format("floor carried %d pools, budget is %d", pools, FloorsConfig.floodedRoomsPerFloor)
					)
					if pools > 0 then
						floorsWithWater += 1
					end
				end
			end
			-- 400 floors at p = floodedFloorChance: this window is several standard deviations wide,
			-- so it only trips on a real change in the rate, never on seed noise.
			local rate = floorsWithWater / totalFloors
			Harness.expect(
				math.abs(rate - FloorsConfig.floodedFloorChance) <= 0.12,
				string.format(
					"%.0f%% of floors held water; expected about %.0f%%",
					rate * 100,
					FloorsConfig.floodedFloorChance * 100
				)
			)
		end),

		Harness.test("vine curtains only gate doorways the floor can do without", function()
			local totalVines = 0
			for seed = 1, 24 do
				for _, plan in FloorPlanner.planAll(seed * 15_485_863) do
					Harness.expect(#plan.vines <= VineRules.targetCount(plan.depth), "floor exceeded its vine budget")
					if plan.depth < VinesConfig.minDepth then
						Harness.equal(#plan.vines, 0, "vines appeared before their minimum depth")
					end

					local sealed: { VineRules.Doorway } = {}
					for _, vine in plan.vines do
						totalVines += 1
						local room = plan.rooms[vine.roomIndex]
						Harness.expect(room ~= nil, "vine room index must resolve")
						Harness.expect(
							hasDirection((room :: Types.RoomPlacement).doorways, vine.direction),
							"vine must sit on a doorway that exists"
						)
						Harness.expect(vine.roomIndex ~= plan.basinRoomIndex, "the Basin must never be curtained")
						Harness.expect(vine.visualSeed >= 1 and vine.visualSeed <= 2_000_000_000)
						table.insert(sealed, { roomIndex = vine.roomIndex, direction = vine.direction })
					end

					-- Checked against ALL of this floor's curtains at once: two individually redundant
					-- doorways must not combine into an isolated room for a player with a capped dial.
					Harness.expect(
						VineRules.allRoomsReachable(plan.rooms, plan.entryRoomIndex, sealed),
						"vine curtains isolated part of the floor"
					)
				end
			end
			Harness.expect(totalVines > 0, "test seeds produced no vine curtains")
		end),

		Harness.test("threat and hazard placements obey module allow-lists and safe-room exclusions", function()
			for _, plan in FloorPlanner.planAll(44_021) do
				Harness.equal(#plan.threatSpawns, expectedThreatCount(plan))
				for _, spawn in plan.threatSpawns do
					Harness.expect(spawn.roomIndex ~= plan.entryRoomIndex)
					Harness.expect(spawn.roomIndex ~= plan.basinRoomIndex)
					local def = moduleById(plan.rooms[spawn.roomIndex].moduleId)
					Harness.expect(def ~= nil)
					local threatDef = ThreatsConfig.definitions[spawn.threatId]
					Harness.expect(threatDef ~= nil, "spawned threat requires a config definition")
					Harness.expect(
						weightAtDepth((threatDef :: Types.ThreatDef).spawnWeightByDepth, plan.depth) > 0,
						"spawned threat is unavailable at this depth"
					)
					Harness.near(spawn.offset.Y, 0)
					local offsetLimit = FloorsConfig.geometry.cellSize / 4
					Harness.expect(math.abs(spawn.offset.X) <= offsetLimit)
					Harness.expect(math.abs(spawn.offset.Z) <= offsetLimit)
					local allowed = false
					for _, threatId in (def :: Types.RoomModuleDef).allowedThreats do
						if threatId == spawn.threatId then
							allowed = true
							break
						end
					end
					Harness.expect(allowed, "threat spawned outside its module allow-list")
				end

				local lootIndex = math.clamp(plan.depth, 1, #LootConfig.spawnsPerFloor)
				Harness.equal(#plan.lootSpawns, LootConfig.spawnsPerFloor[lootIndex])
				for _, spawn in plan.lootSpawns do
					Harness.expect(spawn.roomIndex ~= plan.entryRoomIndex)
					Harness.expect(spawn.roomIndex ~= plan.basinRoomIndex)
					local def = LootConfig.definitions[spawn.lootId]
					Harness.expect(def ~= nil, "loot spawn requires a config definition")
					Harness.expect(
						weightAtDepth((def :: Types.LootDef).spawnWeightByDepth, plan.depth) > 0,
						"loot spawned outside its depth range"
					)
					Harness.near(spawn.offset.Y, 0)
					local halfCell = FloorsConfig.geometry.cellSize / 2
					local wallInset = halfCell - math.max(math.abs(spawn.offset.X), math.abs(spawn.offset.Z))
					Harness.expect(
						wallInset >= LootConfig.wallInsetMin and wallInset <= LootConfig.wallInsetMax,
						"loot should live in the configured peripheral wall band"
					)
					local playableRadius = halfCell - FloorsConfig.terrain.wallClearance
					Harness.expect(
						math.abs(spawn.offset.X) + LootConfig.placementFootprint / 2 <= playableRadius
							and math.abs(spawn.offset.Z) + LootConfig.placementFootprint / 2 <= playableRadius,
						"loot footprint must stay inside the room"
					)
					for _, hazard in plan.hazards do
						if
							hazard.hazardId == "Water"
							and hazard.roomIndex == spawn.roomIndex
							and hazard.localOffset ~= nil
							and hazard.size ~= nil
						then
							local waterOffset = hazard.localOffset
							local waterSize = hazard.size
							Harness.expect(
								math.abs(spawn.offset.X - waterOffset.X)
										> (LootConfig.placementFootprint + waterSize.X) / 2
									or math.abs(spawn.offset.Z - waterOffset.Z)
										> (LootConfig.placementFootprint + waterSize.Z) / 2,
								"loot footprint must not overlap a planned water pool"
							)
						end
					end
				end

				-- Rebuilt here so the water assertions can sample the SAME height field the planner
				-- searched for its natural recess.
				local swellsByRoom: { [number]: { GroundGeometry.Swell } } = {}
				for _, patch in plan.groundPatches do
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

				local waterCountByRoom: { [number]: number } = {}
				for _, hazard in plan.hazards do
					Harness.expect(hazard.roomIndex ~= plan.entryRoomIndex)
					Harness.expect(hazard.roomIndex ~= plan.basinRoomIndex)
					local def = moduleById(plan.rooms[hazard.roomIndex].moduleId)
					Harness.expect(def ~= nil)
					local roomDef = def :: Types.RoomModuleDef
					if hazard.hazardId == "Water" then
						Harness.expect(roomDef.waterDepth ~= nil, "water requires a flooded module")
						Harness.near(hazard.waterDepth :: number, roomDef.waterDepth :: number)
						Harness.expect(hazard.localOffset ~= nil, "water requires a localized pool offset")
						Harness.expect(hazard.size ~= nil, "water requires a localized pool footprint")
						local poolSize = hazard.size :: Vector3
						local poolOffset = hazard.localOffset :: Vector3
						Harness.expect(poolSize.X < FloorsConfig.geometry.cellSize)
						Harness.expect(poolSize.Z < FloorsConfig.geometry.cellSize)
						-- A pool narrower than a few Terrain voxels smooths away into the floor and
						-- becomes invisible and un-wadeable, which is the bug this bound exists for.
						Harness.expect(
							math.min(poolSize.X, poolSize.Z) >= HazardsConfig.waterPool.minSize * 0.85,
							"water pool too small to survive the 4-stud Terrain voxel grid"
						)
						local interiorRadius = FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.wallClearance
						Harness.expect(
							math.abs(poolOffset.X) + poolSize.X / 2 <= interiorRadius + 1e-6
								and math.abs(poolOffset.Z) + poolSize.Z / 2 <= interiorRadius + 1e-6,
							"water pool crossed the room bound"
						)

						-- The bed must clear the waterline by at least the configured freeboard, which is
						-- what keeps the surface below the room's flat base plane so the central plaza and
						-- every doorway lane stay dry however deep the chosen recess is.
						local bedDepth = hazard.bedDepth :: number
						Harness.expect(
							bedDepth >= (hazard.waterDepth :: number) + HazardsConfig.waterPool.minimumFreeboard - 1e-6,
							"pool bed left no freeboard under the room's base plane"
						)

						-- The bed is only ever allowed to DEEPEN the natural recess. If it sat above the
						-- room's own floor there the carve would be a plateau inside a dip.
						local naturalField = GroundGeometry.fieldFor(
							plan.rooms[hazard.roomIndex],
							plan.depth,
							false,
							{},
							swellsByRoom[hazard.roomIndex] or {},
							{}
						)
						local naturalHeight = GroundGeometry.offset(naturalField, poolOffset.X, poolOffset.Z)
						Harness.expect(
							-bedDepth <= naturalHeight + 1e-6,
							"pool bed was raised above the natural recess floor it settled into"
						)
						waterCountByRoom[hazard.roomIndex] = (waterCountByRoom[hazard.roomIndex] or 0) + 1
					end
				end

				local groundCountByRoom: { [number]: number } = {}
				for _, patch in plan.groundPatches do
					groundCountByRoom[patch.roomIndex] = (groundCountByRoom[patch.roomIndex] or 0) + 1
					Harness.expect(patch.size.X >= FloorsConfig.terrain.groundHumpMinDiameter * 0.75)
					Harness.expect(patch.size.Z >= FloorsConfig.terrain.groundHumpMinDiameter * 0.75)
					Harness.expect(patch.size.Y >= FloorsConfig.terrain.groundHumpMinHeight)
					Harness.expect(patch.size.Y <= FloorsConfig.terrain.groundHumpMaxHeight)
					local interiorRadius = FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.wallClearance
					Harness.expect(math.abs(patch.localOffset.X) + patch.size.X / 2 <= interiorRadius)
					Harness.expect(math.abs(patch.localOffset.Z) + patch.size.Z / 2 <= interiorRadius)
					if patch.roomIndex == plan.entryRoomIndex or patch.roomIndex == plan.basinRoomIndex then
						local clearance = FloorsConfig.terrain.specialRoomCenterClearance
						Harness.expect(
							math.abs(patch.localOffset.X) > patch.size.X / 2 + clearance
								or math.abs(patch.localOffset.Z) > patch.size.Z / 2 + clearance,
							"special-room ground must leave its center clear"
						)
					end
				end
				for roomIndex in plan.rooms do
					Harness.expect(
						(groundCountByRoom[roomIndex] or 0) >= 1,
						"every room requires visible ground elevation"
					)
				end

				for index, room in plan.rooms do
					local def = moduleById(room.moduleId)
					if
						index ~= plan.entryRoomIndex
						and index ~= plan.basinRoomIndex
						and def ~= nil
						and def.waterDepth ~= nil
					then
						Harness.equal(
							waterCountByRoom[index] or 0,
							1,
							"flooded rooms require exactly one water placement"
						)
					end
				end
			end
		end),

		Harness.test("ceiling ambushers only spawn beneath their configured roof cap", function()
			local ambushSpawnCount = 0
			for seed = 1, 32 do
				for _, plan in FloorPlanner.planAll(seed * 104_729) do
					for _, spawn in plan.threatSpawns do
						local threatDef = ThreatsConfig.definitions[spawn.threatId]
						if threatDef == nil or threatDef.ambush == nil then
							continue
						end
						ambushSpawnCount += 1
						local room = plan.rooms[spawn.roomIndex]
						Harness.expect(room ~= nil, "ambush room index must resolve")
						Harness.expect(
							(room :: Types.RoomPlacement).ceilingHeight <= threatDef.ambush.maximumCeilingHeight,
							"ceiling ambusher spawned above its inspectable-roof cap"
						)
					end
				end
			end
			Harness.expect(ambushSpawnCount > 0, "test seeds produced no ceiling ambushers")
		end),

		Harness.test("cave-tier floor and threat multipliers change the generated expedition", function()
			local maxFloors = math.min(6, FloorsConfig.floorsPerRun)
			local multiplier = 0.6
			local plans = FloorPlanner.planAll(82_104, maxFloors, multiplier)
			Harness.equal(#plans, maxFloors)
			for _, plan in plans do
				Harness.equal(#plan.threatSpawns, expectedThreatCount(plan, multiplier))
			end

			for _, plan in FloorPlanner.planAll(82_104, maxFloors, 0) do
				Harness.equal(#plan.threatSpawns, expectedThreatCount(plan, 0))
			end
		end),

		Harness.test("a run generates and keeps its invariants all the way to the depth ceiling", function()
			local ceiling = DepthConfig.prototypeCeiling
			local plans = FloorPlanner.planAll(46_021, ceiling, nil, nil, 1, 1)
			Harness.equal(#plans, ceiling, "a development run must reach the prototype ceiling")

			local checkedDeep = 0
			for index, plan in plans do
				Harness.equal(plan.depth, index)
				Harness.equal(plan.globalDepth, index)
				Harness.equal(#plan.rooms, DepthRules.getRoomCountTarget(plan.globalDepth) + 1)
				Harness.equal(#plan.threatSpawns, expectedThreatCount(plan))

				-- Every safety invariant the shallow floors are held to still holds this deep.
				Harness.expect(plan.entryRoomIndex ~= plan.basinRoomIndex, "entry and Basin merged at depth " .. index)
				Harness.expect(plan.brazierRoomIndex ~= plan.basinRoomIndex, "brazier in the Basin at depth " .. index)
				Harness.equal(plan.rooms[plan.basinRoomIndex].moduleId, "Basin")
				Harness.expect(hasWaterFreePath(plan), "no guaranteed dry route at depth " .. index)
				for _, spawn in plan.threatSpawns do
					Harness.expect(
						spawn.roomIndex ~= plan.entryRoomIndex and spawn.roomIndex ~= plan.basinRoomIndex,
						"a threat spawned in a protected room at depth " .. index
					)
				end
				for _, placement in plan.dripstones do
					Harness.expect(
						placement.roomIndex ~= plan.entryRoomIndex
							and placement.roomIndex ~= plan.basinRoomIndex
							and placement.roomIndex ~= plan.brazierRoomIndex,
						"a dripstone was placed in a protected room at depth " .. index
					)
				end
				if index == 11 or index == 15 or index == ceiling then
					checkedDeep += 1
				end
			end
			Harness.equal(checkedDeep, 3, "depths 11, 15 and 20 must all be covered")
		end),

		Harness.test("a floor is reproducible from its global depth, not its position in a run", function()
			-- Same run seed and tier: the fifth floor of a surface run and the first floor of a run
			-- that starts at depth 5 are the same cave.
			local fromSurface = FloorPlanner.planAll(555_111, 6, nil, nil, 1, 2)
			local fromDepthFive = FloorPlanner.planAll(555_111, 2, nil, nil, 5, 2)
			Harness.equal(fromSurface[5].globalDepth, 5)
			Harness.equal(fromDepthFive[1].globalDepth, 5)
			Harness.equal(fromDepthFive[1].depth, 1, "the expedition ordinal is independent of the depth")
			Harness.equal(
				planSignature(fromSurface[5]),
				planSignature(fromDepthFive[1]),
				"the same global depth produced a different floor"
			)
		end),

		Harness.test("different global depths never reuse a floor plan", function()
			local plans = FloorPlanner.planAll(9_182, DepthConfig.prototypeCeiling, nil, nil, 1, 3)
			local seen: { [string]: number } = {}
			for _, plan in plans do
				local signature = planSignature(plan)
				Harness.isNil(seen[signature], "two depths produced an identical plan")
				seen[signature] = plan.globalDepth
			end
		end),

		Harness.test("an unsupported depth is refused instead of generating shallow content", function()
			for _, badDepth in { 0, -3, DepthConfig.prototypeCeiling + 1, 2.5 } do
				local ok = pcall(function()
					FloorPlanner.plan({ globalDepth = badDepth, rng = Random.new(1) })
				end)
				Harness.expect(not ok, "depth " .. tostring(badDepth) .. " should have been refused")
			end
			-- A run that would descend past the ceiling is shortened, never truncated into bad data.
			local plans = FloorPlanner.planAll(4_242, 12, nil, nil, DepthConfig.prototypeCeiling - 2, 1)
			Harness.equal(#plans, 3)
			Harness.equal(plans[#plans].globalDepth, DepthConfig.prototypeCeiling)
		end),
	},
}

return suite

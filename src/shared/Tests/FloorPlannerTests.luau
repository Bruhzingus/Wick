--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local FloorPlanner = require(script.Parent.Parent.Logic.FloorPlanner)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local VinesConfig = require(script.Parent.Parent.Config.Vines)
local MiningConfig = require(script.Parent.Parent.Config.Mining)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)
local DepthRules = require(script.Parent.Parent.Logic.DepthRules)
local LootRules = require(script.Parent.Parent.Logic.LootRules)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)
local OreRules = require(script.Parent.Parent.Logic.OreRules)
local RoomFootprint = require(script.Parent.Parent.Logic.RoomFootprint)
local DoorwayGeometry = require(script.Parent.Parent.Logic.DoorwayGeometry)
local VineRules = require(script.Parent.Parent.Logic.VineRules)
local AshamedLurkerConfig = require(script.Parent.Parent.Config.AshamedLurker)
local StoneWardenConfig = require(script.Parent.Parent.Config.StoneWarden)
local AshamedLurkerRules = require(script.Parent.Parent.Logic.AshamedLurkerRules)
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

-- The tallest roof a roof-bound row may hang from, or nil for anything that walks the floor. Written
-- out here rather than imported from `Logic/ThreatRules.roofProfile` on this suite's usual principle:
-- a test that called the planner's own helper would only prove the planner agrees with itself.
--
-- BOTH roof profiles are named explicitly. When this suite only knew about `ambush`, a second
-- roof-bound row was not a failure — it was silently skipped by the eligibility check and would have
-- nil-indexed in the spawn audit below, so the bug it exists to catch would have gone unreported.
local function roofCeilingCap(def: Types.ThreatDef): number?
	local ambush = def.ambush
	if ambush ~= nil then
		return ambush.maximumCeilingHeight
	end
	local striker = def.ceilingStrike
	if striker ~= nil then
		return striker.maximumCeilingHeight
	end
	return nil
end

local function ceilingAllows(def: Types.ThreatDef, ceilingHeight: number): boolean
	local cap = roofCeilingCap(def)
	return cap == nil or ceilingHeight <= cap
end

local function roomHasThreatAtDepth(
	familyId: string?,
	def: Types.RoomModuleDef,
	depth: number,
	ceilingHeight: number
): boolean
	local family = CaveFamilyRules.resolve(familyId)
	for _, threatId in def.allowedThreats do
		local threatDef = ThreatsConfig.definitions[threatId]
		if
			threatDef ~= nil
			and weightAtDepth(threatDef.spawnWeightByDepth, CaveFamilyRules.threatDepthIndex(family, threatId, depth)) > 0
			and CaveFamilyRules.threatWeightMultiplier(family, threatId) > 0
			and ceilingAllows(threatDef, ceilingHeight)
		then
			return true
		end
	end
	return false
end

-- Re-derives the planner's own budget formula from the family profile rather than importing it, so
-- the test proves the documented three-factor product rather than that the planner agrees with
-- itself:
--
--   resolvedThreatBudget = baseThreatBudgetForFloor x caveBaseThreatMultiplier x caveThreatBandMultiplier
local function expectedThreatCount(plan: Types.FloorPlan): number
	local hasEligibleRoom = false
	for index, room in plan.rooms do
		local def = moduleById(room.moduleId)
		if
			index ~= plan.entryRoomIndex
			and index ~= plan.basinRoomIndex
			and def ~= nil
			and roomHasThreatAtDepth(plan.familyId, def, plan.globalDepth, room.ceilingHeight)
		then
			hasEligibleRoom = true
			break
		end
	end
	if not hasEligibleRoom then
		return 0
	end

	local family = CaveFamilyRules.resolve(plan.familyId)
	local band = DepthRules.getDepthBand(plan.globalDepth)
	local multiplier = family.baseThreatMultiplier * family.threatBandMultipliers[band]
	local budgetIndex = math.clamp(plan.globalDepth, 1, #FloorsConfig.threatBudgetPerFloor)
	local base = FloorsConfig.threatBudgetPerFloor[budgetIndex] * DepthRules.getThreatBudgetMultiplier(plan.globalDepth)
	return math.max(0, math.floor(base * multiplier + 0.5))
end

-- Independent re-derivations of the geometry guarantees, written plainly here rather than imported
-- from the planner: a test that called the planner's own helpers would only prove it is
-- self-consistent, not that the placement is actually safe.
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

local function fitsInsideRoom(offset: Vector3, size: Vector3): boolean
	local radius = FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.wallClearance
	return math.abs(offset.X) + size.X / 2 <= radius and math.abs(offset.Z) + size.Z / 2 <= radius
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

-- Room indices along a shortest doorway path. Used to reconstruct the guaranteed route so a
-- placement test can assert what is NOT allowed to sit on it.
local function routeBetween(plan: Types.FloorPlan, startIndex: number, goalIndex: number): { number }
	local indicesByCell: { [string]: number } = {}
	for index, room in plan.rooms do
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
		for _, direction in plan.rooms[index].doorways do
			local offset = OFFSETS[direction]
			local room = plan.rooms[index]
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
	if plan.echoGate ~= nil then
		table.insert(
			pieces,
			string.format("E:%d:%s:%d", plan.echoGate.roomIndex, plan.echoGate.direction, plan.echoGate.visualSeed)
		)
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
			Harness.equal(#first, FloorsConfig.planningBatchSize)
			Harness.equal(#second, #first)
			for index, plan in first do
				Harness.equal(planSignature(plan), planSignature(second[index]), "seed changed at floor " .. index)
				Harness.equal(plan.depth, index)
			end
		end),

		Harness.test("Stone Wardens use a protected optional encounter room with a counter", function()
			local wardenFloors = 0
			for seed = 1, 30 do
				for _, plan in FloorPlanner.planAll(seed * 93_931) do
					if plan.globalDepth < StoneWardenConfig.minGlobalDepth then
						Harness.equal(plan.warden, nil, "a Warden appeared before its minimum global depth")
						continue
					end
					local warden = plan.warden
					if warden == nil then
						continue
					end
					wardenFloors += 1
					Harness.equal(plan.rooms[warden.roomIndex].moduleId, StoneWardenConfig.roomModuleId)

					-- The encounter is anchored to a DOORLESS WALL. The dormant body is an outcrop in
					-- that wall, so the side it sleeps in can never be the gap people walk through, and
					-- the relic it guards has to stand in the open floor in front of it rather than
					-- somewhere behind the thing guarding it.
					local den = plan.rooms[warden.roomIndex]
					Harness.expect(
						not hasDirection(den.doorways, warden.wallDirection),
						"the Warden's wall must be a doorless side of its den"
					)
					local halfCell = FloorsConfig.geometry.cellSize / 2
					local normal = OFFSETS[warden.wallDirection]
					local outward = Vector3.new(normal.x, 0, normal.z)
					Harness.near(
						warden.pileOffset:Dot(outward),
						halfCell - StoneWardenConfig.layout.wallSetback,
						1e-6,
						"the dormant body must sit against its wall rather than out in open floor"
					)
					Harness.expect(
						warden.relicOffset:Dot(outward) > 0
							and warden.relicOffset.Magnitude < warden.pileOffset.Magnitude,
						"the relic must stand between the room centre and the Warden's wall"
					)
					Harness.expect(
						(warden.relicOffset - warden.pileOffset).Magnitude > StoneWardenConfig.encounterClearance,
						"the relic must not end up underneath the body guarding it"
					)
					for _, offset in { warden.pileOffset, warden.relicOffset, warden.counterDripstoneOffset } do
						Harness.expect(
							math.abs(offset.X) <= halfCell and math.abs(offset.Z) <= halfCell,
							"a Warden fixture was laid outside its own room cell"
						)
					end

					local counterFound = false
					for _, dripstone in plan.dripstones do
						if
							dripstone.roomIndex == warden.roomIndex
							and dripstone.localOffset == warden.counterDripstoneOffset
							and dripstone.variantId == StoneWardenConfig.counterDripstoneVariantId
						then
							counterFound = true
						end
					end
					Harness.expect(counterFound, "a Warden room requires its guaranteed unstable-dripstone counter")

					for _, spawn in plan.threatSpawns do
						Harness.expect(spawn.roomIndex ~= warden.roomIndex, "ordinary threat shared the Warden room")
					end
					for _, spawn in plan.lootSpawns do
						Harness.expect(spawn.roomIndex ~= warden.roomIndex, "loot shared the Warden room")
					end
					for _, hazard in plan.hazards do
						Harness.expect(hazard.roomIndex ~= warden.roomIndex, "water shared the Warden room")
					end
					for _, deposit in plan.deposits do
						Harness.expect(deposit.roomIndex ~= warden.roomIndex, "deposit shared the Warden room")
					end
				end
			end
			Harness.expect(wardenFloors > 0, "test seeds produced no Stone Warden encounters")
		end),

		Harness.test("rooms are compact and topology favors chains with alternate connections", function()
			Harness.equal(FloorsConfig.geometry.cellSize, 64, "room footprint must stay 20% below the old 80 studs")
			local floorsChecked = 0
			local roomsChecked = 0
			local deadEnds = 0
			local floorsWithCycles = 0
			for seed = 1, 32 do
				for _, plan in FloorPlanner.planAll(seed * 32_771) do
					floorsChecked += 1
					local doorwayEnds = 0
					for _, room in plan.rooms do
						roomsChecked += 1
						doorwayEnds += #room.doorways
						if #room.doorways == 1 then
							deadEnds += 1
						end
					end
					local edges = doorwayEnds / 2
					if edges >= #plan.rooms then
						floorsWithCycles += 1
					end
				end
			end
			Harness.expect(floorsChecked > 0 and roomsChecked > 0)
			Harness.expect(deadEnds / roomsChecked < 0.4, "more than 40% of rooms became dead ends")
			Harness.expect(
				floorsWithCycles / floorsChecked > 0.5,
				"most floors should contain at least one alternate connection"
			)
		end),

		Harness.test("raw wax deposits are optional detours, never on the mandatory route", function()
			local placement = MiningConfig.placement
			local floorsWithDeposit = 0
			local floorsChecked = 0
			for seed = 1, 24 do
				for _, plan in FloorPlanner.planAll(seed * 44_617) do
					floorsChecked += 1
					Harness.expect(
						#plan.deposits <= placement.maxPerFloor,
						"a floor must never carry more than the configured deposit count"
					)
					if #plan.deposits > 0 then
						floorsWithDeposit += 1
					end

					-- Both legs of the guaranteed route are off limits, not merely their endpoints:
					-- a deposit a player walks past on the way to the Basin is not a decision.
					local onRoute: { [number]: boolean } = {}
					for _, index in routeBetween(plan, plan.entryRoomIndex, plan.brazierRoomIndex) do
						onRoute[index] = true
					end
					for _, index in routeBetween(plan, plan.brazierRoomIndex, plan.basinRoomIndex) do
						onRoute[index] = true
					end

					for _, deposit in plan.deposits do
						Harness.expect(
							deposit.roomIndex ~= plan.entryRoomIndex
								and deposit.roomIndex ~= plan.basinRoomIndex
								and deposit.roomIndex ~= plan.brazierRoomIndex,
							"a deposit must never sit in a protected room"
						)
						Harness.equal(
							onRoute[deposit.roomIndex],
							nil,
							"a deposit must never sit on the guaranteed entry -> Brazier -> Basin route"
						)

						local room = plan.rooms[deposit.roomIndex]
						local reserved = math.max(
							placement.footprint + placement.standingClearance,
							placement.footprint + FloorsConfig.geometry.placementProbe.horizontalMarginStuds * 2
						)
						local footprint = Vector3.new(reserved, 0, reserved)
						Harness.expect(
							fitsInsideRoom(deposit.localOffset, footprint),
							"a deposit plus its standing room must fit inside its room"
						)
						Harness.expect(
							not blocksDoorway(room, plan.globalDepth, plan.familyId, deposit.localOffset, footprint),
							"a deposit must never block a doorway lane"
						)

						-- Dry standing room: nobody is ever committed to a swing in a pool.
						for _, hazard in plan.hazards do
							if
								hazard.hazardId == "Water"
								and hazard.roomIndex == deposit.roomIndex
								and hazard.localOffset ~= nil
								and hazard.size ~= nil
							then
								Harness.expect(
									not overlapsXZ(
										deposit.localOffset,
										footprint,
										hazard.localOffset :: Vector3,
										hazard.size :: Vector3,
										0
									),
									"a deposit's interaction footprint must be dry"
								)
							end
						end

						-- Never under something that falls, never at a threat's own spawn point.
						for _, formation in plan.dripstones do
							if formation.roomIndex == deposit.roomIndex then
								local delta = formation.localOffset - deposit.localOffset
								Harness.expect(
									Vector3.new(delta.X, 0, delta.Z).Magnitude >= placement.minHazardSeparation,
									"a deposit must keep clear of unstable formations — a swing is time standing still"
								)
							end
						end
						for _, spawn in plan.threatSpawns do
							if spawn.roomIndex == deposit.roomIndex then
								local delta = spawn.offset - deposit.localOffset
								Harness.expect(
									Vector3.new(delta.X, 0, delta.Z).Magnitude >= placement.minThreatSeparation,
									"a deposit must never be placed on top of a threat's spawn point"
								)
							end
						end
					end
				end
			end

			Harness.expect(floorsChecked > 0, "the sweep must actually generate floors")
			-- Common enough to learn, and still not on every single floor at the shallow end. The
			-- planner reduces the count rather than relaxing safety, so the realised rate sits at or
			-- below what the weights asked for.
			local rate = floorsWithDeposit / floorsChecked
			Harness.expect(
				rate > 0.35 and rate <= 1,
				string.format("deposit rate %.2f is outside the intended optional-content band", rate)
			)
		end),

		Harness.test("the Locked Store is sealed, stocked, and never on the way anywhere", function()
			-- THE test for the one relaxation in the vine system. Every other curtain must leave the floor
			-- fully connected; a store's curtain is allowed to be a room's only way in, and this proves the
			-- exception cannot reach anything it was not meant to.
			--
			-- The relaxation is scoped by the owner's rule: it applies only to rooms that carry nobody
			-- onward. `VineRules.roomMayBeSealed` enforces that as a DEAD END (one doorway), which makes it
			-- structural — no path can pass through a room with a single door.
			local unlocked: { [string]: boolean } = {}
			for _, node in LampConfig.nodes do
				unlocked[node.id] = true
			end

			-- Walked here rather than through VineRules, so this is not proving the planner correct with
			-- the same function the planner used to make the decision.
			local function reachableFrom(plan: Types.FloorPlan): { [number]: boolean }
				local byCell: { [string]: number } = {}
				for index, room in plan.rooms do
					byCell[room.gridX .. "," .. room.gridZ] = index
				end
				local blocked: { [string]: boolean } = {}
				for _, vine in plan.vines do
					blocked[vine.roomIndex .. vine.direction] = true
					local room = plan.rooms[vine.roomIndex]
					local offset = OFFSETS[vine.direction]
					local neighbor = byCell[(room.gridX + offset.x) .. "," .. (room.gridZ + offset.z)]
					if neighbor ~= nil then
						blocked[neighbor .. OPPOSITE[vine.direction]] = true
					end
				end
				local seen: { [number]: boolean } = { [plan.entryRoomIndex] = true }
				local queue, head = { plan.entryRoomIndex }, 1
				while head <= #queue do
					local index = queue[head]
					head += 1
					local room = plan.rooms[index]
					for _, direction in room.doorways do
						if blocked[index .. direction] then
							continue
						end
						local offset = OFFSETS[direction]
						local neighbor = byCell[(room.gridX + offset.x) .. "," .. (room.gridZ + offset.z)]
						if neighbor ~= nil and not seen[neighbor] then
							seen[neighbor] = true
							table.insert(queue, neighbor)
						end
					end
				end
				return seen
			end

			local store = LampConfig.generation.lockedStore
			local storesSeen = 0
			for seed = 1, 24 do
				for depth = 1, 12 do
					local plan = FloorPlanner.plan({
						globalDepth = depth,
						rng = Random.new(seed * 7919 + depth * 104729),
						unlockedNodes = unlocked,
					})
					local storeIndex = plan.lockedStoreRoomIndex
					local reachable = reachableFrom(plan)

					-- The guarantee the relaxation must never touch: the required rooms stay walkable.
					Harness.expect(reachable[plan.brazierRoomIndex] == true, "the Brazier must stay reachable")
					Harness.expect(reachable[plan.basinRoomIndex] == true, "the Basin must stay reachable")
					-- And nothing ELSE may be cut off either — only a store may be.
					for index in plan.rooms do
						if index ~= storeIndex then
							Harness.expect(
								reachable[index] == true,
								string.format("room %d was cut off (seed %d, depth %d)", index, seed, depth)
							)
						end
					end

					if storeIndex ~= nil then
						storesSeen += 1
						local index = storeIndex :: number
						Harness.equal(#plan.rooms[index].doorways, 1, "a store must be a dead end")
						Harness.expect(index ~= plan.entryRoomIndex, "a store must not be the entry")
						Harness.expect(index ~= plan.brazierRoomIndex, "a store must not be the Brazier")
						Harness.expect(index ~= plan.basinRoomIndex, "a store must not be the Basin")
						Harness.expect(
							plan.warden == nil or index ~= plan.warden.roomIndex,
							"a store must not be the Warden's chamber"
						)
						Harness.expect(reachable[index] ~= true, "a store must actually be sealed off")
						Harness.expect(depth >= store.minDepth, "a store must never appear above its minimum depth")

						local deposits, loot = 0, 0
						for _, entry in plan.deposits do
							if entry.roomIndex == index then
								deposits += 1
							end
						end
						for _, entry in plan.lootSpawns do
							if entry.roomIndex == index then
								loot += 1
							end
						end
						-- A vault somebody burned a curtain open to reach must never be empty.
						Harness.expect(deposits >= store.deposits, "a store must hold its guaranteed seam")
						Harness.expect(loot >= store.loot, "a store must hold its guaranteed loot")
					end
				end
			end
			Harness.expect(storesSeen > 0, "the sweep must actually produce some stores to check")
		end),

		Harness.test("no Locked Store exists until the node is owned", function()
			-- The rollback and the unlock are the same gate here: an empty unlock set must produce exactly
			-- the floors the game shipped with before this feature.
			for seed = 1, 16 do
				for depth = 1, 12 do
					local plan = FloorPlanner.plan({
						globalDepth = depth,
						rng = Random.new(seed * 4231 + depth * 91),
						unlockedNodes = {},
					})
					Harness.isNil(plan.lockedStoreRoomIndex, "an unowned node must never seal a room")
				end
			end
		end),

		Harness.test("the Echo Lock is an owned, optional reciprocal loop between ordinary rooms", function()
			for seed = 1, 16 do
				for depth = 1, 12 do
					local plan = FloorPlanner.plan({
						globalDepth = depth,
						rng = Random.new(seed * 6203 + depth * 131),
						unlockedNodes = {},
					})
					Harness.isNil(plan.echoGate, "an unowned Echo Lock must never change floor topology")
				end
			end

			local gatesSeen = 0
			for seed = 1, 64 do
				for depth = LampConfig.generation.echoLock.minDepth, 12 do
					local plan = FloorPlanner.plan({
						globalDepth = depth,
						rng = Random.new(seed * 95_491 + depth * 389),
						unlockedNodes = { ["lamp.echo_lock"] = true },
					})
					local gate = plan.echoGate
					if gate == nil then
						continue
					end
					gatesSeen += 1
					Harness.expect(gate.roomIndex ~= plan.entryRoomIndex, "the entry must never be barred")
					Harness.expect(gate.roomIndex ~= plan.basinRoomIndex, "the Basin must never be barred")
					Harness.expect(gate.roomIndex ~= plan.brazierRoomIndex, "the Brazier must never be barred")
					Harness.expect(
						plan.warden == nil or gate.roomIndex ~= plan.warden.roomIndex,
						"the Warden room must never be barred"
					)

					local byCell: { [string]: number } = {}
					for index, room in plan.rooms do
						byCell[cellKey(room.gridX, room.gridZ)] = index
					end
					local room = plan.rooms[gate.roomIndex]
					local offset = OFFSETS[gate.direction]
					local neighborIndex = byCell[cellKey(room.gridX + offset.x, room.gridZ + offset.z)]
					Harness.expect(neighborIndex ~= nil, "the Echo Lock must name a real adjacent room")
					local neighbor = plan.rooms[neighborIndex :: number]
					Harness.equal(
						hasDirection(neighbor.doorways, OPPOSITE[gate.direction]),
						true,
						"the added doorway must be reciprocal"
					)
					Harness.expect(
						neighborIndex ~= plan.entryRoomIndex
							and neighborIndex ~= plan.basinRoomIndex
							and neighborIndex ~= plan.brazierRoomIndex
							and (plan.warden == nil or neighborIndex ~= plan.warden.roomIndex),
						"both Echo Lock endpoints must be ordinary rooms"
					)

					-- Walk the graph with the new edge removed. Every room must still be reachable:
					-- this independently proves the bell opens a shortcut, never required content.
					local blocked: { [string]: boolean } = {
						[gate.roomIndex .. gate.direction] = true,
						[(neighborIndex :: number) .. OPPOSITE[gate.direction]] = true,
					}
					local seen: { [number]: boolean } = { [plan.entryRoomIndex] = true }
					local queue, head = { plan.entryRoomIndex }, 1
					while head <= #queue do
						local index = queue[head]
						head += 1
						for _, direction in plan.rooms[index].doorways do
							if blocked[index .. direction] then
								continue
							end
							local step = OFFSETS[direction]
							local other =
								byCell[cellKey(plan.rooms[index].gridX + step.x, plan.rooms[index].gridZ + step.z)]
							if other ~= nil and not seen[other] then
								seen[other] = true
								table.insert(queue, other)
							end
						end
					end
					for index in plan.rooms do
						Harness.expect(
							seen[index] == true,
							string.format(
								"Echo edge removal disconnected room %d at seed %d depth %d",
								index,
								seed,
								depth
							)
						)
					end

					for _, vine in plan.vines do
						Harness.expect(
							not (vine.roomIndex == gate.roomIndex and vine.direction == gate.direction),
							"an Echo Lock and vine curtain must not share an opening"
						)
					end
				end
			end
			Harness.expect(gatesSeen > 0, "the owned-node sweep must produce Echo Locks to verify")
		end),

		Harness.test("multiple seams on a floor are separate detours, never a route", function()
			-- THE structural answer to "a second deposit turns a detour into a route": the planner takes
			-- at most one deposit per room, so three seams on a deep floor are three separate departures
			-- from the main chain rather than a line a player walks along.
			for seed = 1, 24 do
				for _, plan in FloorPlanner.planAll(seed * 51_803) do
					local seen: { [number]: boolean } = {}
					for _, deposit in plan.deposits do
						Harness.expect(
							not seen[deposit.roomIndex],
							"two deposits shared a room, which would make mining a route"
						)
						seen[deposit.roomIndex] = true
					end
				end
			end
		end),

		Harness.test("deep floors carry more seams than shallow ones", function()
			-- The depth-weighted count curve is what makes mining contribute to the descent rather than
			-- sitting flat against it. Measured as a mean over many seeds, so this pins the shape and
			-- not one lucky floor.
			local totals: { [number]: number } = {}
			local counts: { [number]: number } = {}
			for seed = 1, 40 do
				for depth, plan in FloorPlanner.planAll(seed * 33_809) do
					totals[depth] = (totals[depth] or 0) + #plan.deposits
					counts[depth] = (counts[depth] or 0) + 1
				end
			end

			local function mean(depth: number): number
				local total, count = totals[depth], counts[depth]
				return if total ~= nil and count ~= nil and count > 0 then total / count else 0
			end

			Harness.expect(mean(2) < 1, "a shallow floor must usually carry one seam or none")
			Harness.expect(
				mean(8) > mean(2),
				string.format("floor 8 (%.2f) must out-carry floor 2 (%.2f)", mean(8), mean(2))
			)
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
						-- READABILITY, measured where the danger actually is. The room may be a tall
						-- cavern; what a player has to be able to inspect is the TIP that is going to
						-- fall on them, so the bound applies to the tip, against the exact local roof and
						-- floor the formation actually hangs between.
						Harness.expect(
							roofHeight - groundHeight - DripstoneRules.visualLength(resolvedVariant)
								<= config.maxEligibleTipHeight + 1e-6,
							"an unstable formation hung its tip above the readable band"
						)
						local radialOffset = math.sqrt(
							placement.localOffset.X * placement.localOffset.X
								+ placement.localOffset.Z * placement.localOffset.Z
						)
						Harness.expect(radialOffset >= config.minCenterOffset - 1e-6)
						Harness.expect(radialOffset <= config.maxCenterOffset + 1e-6)

						-- TWO BOUNDS, TWO RADII, deliberately. Containment is about the disc that actually
						-- hurts, so it is checked against the trigger radius; the doorway-lane guarantee
						-- below keeps the full padded halo. Holding the padded halo inside the walls as
						-- well would make the outer half of every room unusable for no safety gain.
						local interiorRadius = FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.wallClearance
						local safetyRadius = resolvedVariant.triggerRadius + config.doorwaySafetyPadding
						Harness.expect(
							math.abs(placement.localOffset.X) + resolvedVariant.triggerRadius <= interiorRadius + 1e-6,
							"dripstone trigger disc crossed the room's X bound"
						)
						Harness.expect(
							math.abs(placement.localOffset.Z) + resolvedVariant.triggerRadius <= interiorRadius + 1e-6,
							"dripstone trigger disc crossed the room's Z bound"
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

						if plan.warden == nil or placement.roomIndex ~= plan.warden.roomIndex then
							placementsByRoom[placement.roomIndex] = (placementsByRoom[placement.roomIndex] or 0) + 1
							hazardousRooms[placement.roomIndex] = true
						end
					end

					local maxPerRoom = if plan.depth <= 3
						then config.maxPerRoomEarly
						elseif plan.depth <= 6 then config.maxPerRoomMid
						else config.maxPerRoomDeep
					local hazardousFraction = if plan.depth <= 3
						then config.hazardousRoomFractionEarly
						elseif plan.depth <= 6 then config.hazardousRoomFractionMid
						else config.hazardousRoomFractionDeep
					local hazardousRoomCount = 0
					for roomIndex, count in placementsByRoom do
						hazardousRoomCount += 1
						Harness.expect(count <= maxPerRoom, "room exceeded its depth-band formation cap")
						Harness.expect(hazardousRooms[roomIndex])
					end
					local hazardousRoomCap = math.max(1, math.floor(ordinaryRoomCount * hazardousFraction))
					Harness.expect(
						hazardousRoomCount <= hazardousRoomCap,
						"too many ordinary rooms contained unstable formations"
					)
					-- THE TEACHING GUARANTEE, and it is deliberately scoped to the shallow band. Floors
					-- 1-3 are where a player learns to read the dust, the tremor and the warning, and
					-- they cannot learn that in a room raining rock — so half of every shallow floor
					-- stays completely safe. Deeper floors spread hazards across more of the map on
					-- purpose; the per-room cap and the harmless ratio below still bound them.
					if plan.depth <= 3 then
						Harness.expect(
							hazardousRoomCount <= ordinaryRoomCount - hazardousRoomCount,
							"most ordinary rooms on a shallow floor must remain free of unstable formations"
						)
					end
					-- However deep it goes, a floor always keeps some ordinary room with nothing
					-- overhead: a cave with no safe ground is a corridor with a timer.
					Harness.expect(
						hazardousRoomCount < ordinaryRoomCount,
						"every ordinary room on the floor carried a falling hazard"
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
					DepthRules.getRoomCountTarget(plan.globalDepth) + 1 + (if plan.warden ~= nil then 1 else 0),
					"ordinary rooms plus Basin and optional Warden room expected"
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

		Harness.test("ashamed lurkers only take deep, ordinary arches that keep a walking lane", function()
			local totalLurkers = 0
			local totalSites = 0
			for seed = 1, 24 do
				for _, plan in FloorPlanner.planAll(seed * 15_485_863) do
					Harness.expect(
						#plan.lurkers <= AshamedLurkerRules.targetCount(plan.depth),
						"floor exceeded its lurker budget"
					)
					if plan.depth < AshamedLurkerConfig.minDepth then
						Harness.equal(#plan.lurkers, 0, "a lurker appeared before its minimum depth")
					end

					-- No two creatures, and no creature twice, may claim the same opening: relocation
					-- has to move it somewhere it is not already standing.
					local claimed: { [string]: boolean } = {}
					for _, lurker in plan.lurkers do
						totalLurkers += 1
						Harness.expect(#lurker.sites >= 1, "a lurker needs somewhere to stand")
						Harness.expect(lurker.visualSeed >= 1 and lurker.visualSeed <= 2_000_000_000)
						for _, site in lurker.sites do
							totalSites += 1
							local room = plan.rooms[site.roomIndex]
							Harness.expect(room ~= nil, "lurker room index must resolve")
							local placement = room :: Types.RoomPlacement
							Harness.expect(
								hasDirection(placement.doorways, site.direction),
								"a lurker must sit in a doorway that exists"
							)
							Harness.expect(site.roomIndex ~= plan.entryRoomIndex, "never in the entry room")
							Harness.expect(site.roomIndex ~= plan.basinRoomIndex, "never in the Basin room")
							Harness.expect(site.roomIndex ~= plan.brazierRoomIndex, "never in the Brazier room")

							local key = site.roomIndex .. site.direction
							Harness.equal(claimed[key], nil, "two lurker sites claimed the same opening")
							claimed[key] = true

							-- The arch it was given must genuinely leave a lane beside it.
							local profile = DoorwayGeometry.profile(
								placement.gridX,
								placement.gridZ,
								site.direction,
								plan.globalDepth
							)
							Harness.expect(
								AshamedLurkerRules.isPlacementAllowed(profile.width, profile.height),
								"a lurker took an arch that fails the placement rules"
							)
							Harness.expect(
								AshamedLurkerRules.clearLaneWidth(profile.width)
									>= AshamedLurkerConfig.placement.minSafeLaneWidth,
								"a lurker's arch lost its walking lane"
							)

							-- A vine curtain in the same opening would make one hazard depend on the other.
							for _, vine in plan.vines do
								local sameSide = vine.roomIndex == site.roomIndex and vine.direction == site.direction
								local vineRoom = plan.rooms[vine.roomIndex]
								local offset = OFFSETS[vine.direction]
								local neighborIsSite = vineRoom.gridX + offset.x == placement.gridX
									and vineRoom.gridZ + offset.z == placement.gridZ
									and OPPOSITE[vine.direction] == site.direction
								Harness.expect(
									not (sameSide or neighborIsSite),
									"a lurker and a vine curtain shared one opening"
								)
							end
						end
					end
				end
			end
			Harness.expect(totalLurkers > 0, "test seeds produced no ashamed lurkers")
			Harness.expect(totalSites > totalLurkers, "lurkers were never given anywhere to relocate to")
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

				-- The count is now ROLLED from a band rather than fixed, so the assertion is the band.
				local lootIndex = math.clamp(plan.globalDepth, 1, #LootConfig.spawnsPerFloor)
				local lootBand = LootConfig.spawnsPerFloor[lootIndex]
				Harness.expect(
					#plan.lootSpawns >= lootBand.minimum and #plan.lootSpawns <= lootBand.maximum,
					("a floor planned %d pickups, outside its %d..%d band"):format(
						#plan.lootSpawns,
						lootBand.minimum,
						lootBand.maximum
					)
				)
				for _, spawn in plan.lootSpawns do
					Harness.expect(spawn.roomIndex ~= plan.entryRoomIndex)
					Harness.expect(spawn.roomIndex ~= plan.basinRoomIndex)
					local def = LootConfig.definitions[spawn.lootId]
					Harness.expect(def ~= nil, "loot spawn requires a config definition")
					Harness.expect(
						weightAtDepth((def :: Types.LootDef).spawnWeightByDepth, plan.globalDepth) > 0,
						"loot spawned outside its depth range"
					)
					Harness.expect(
						LootRules.isAvailable(def :: Types.LootDef, plan.familyId, plan.globalDepth),
						"loot spawned in a cave or at a depth its family gate forbids"
					)
					Harness.near(spawn.offset.Y, 0)
					-- WHERE A PICKUP MAY BE. Not "in the authored wall band" any more: a shaped room can
					-- refuse that band entirely, and the ring sweep is allowed to give ground inward for
					-- exactly that reason. What may NEVER change is the pair of clearances the sweep was
					-- built to hold — off the wall, and out of the room's central walking line — with the
					-- guaranteed navigation hub as the one documented exception (see plannedLootOffset).
					local halfCell = FloorsConfig.geometry.cellSize / 2
					local wallInset = halfCell - math.max(math.abs(spawn.offset.X), math.abs(spawn.offset.Z))
					local centerDistance = Vector3.new(spawn.offset.X, 0, spawn.offset.Z).Magnitude
					Harness.expect(
						wallInset >= LootConfig.wallInsetMin - 1e-6,
						"loot must keep the configured clearance from the room wall"
					)
					Harness.expect(
						centerDistance >= LootConfig.minimumCenterDistance - 1e-6 or centerDistance <= 1e-6,
						"loot must stay out of the room's central walking line"
					)
					local playableRadius = halfCell - FloorsConfig.terrain.wallClearance
					local surfaceSafeWidth = LootConfig.placementFootprint
						+ FloorsConfig.geometry.placementProbe.horizontalMarginStuds * 2
					Harness.expect(
						math.abs(spawn.offset.X) + surfaceSafeWidth / 2 <= playableRadius
							and math.abs(spawn.offset.Z) + surfaceSafeWidth / 2 <= playableRadius,
						"loot plus its Terrain safety margin must stay inside the room"
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
						local cap = if threatDef ~= nil then roofCeilingCap(threatDef) else nil
						if cap == nil then
							continue
						end
						ambushSpawnCount += 1
						local room = plan.rooms[spawn.roomIndex]
						Harness.expect(room ~= nil, "roof-bound room index must resolve")
						Harness.expect(
							(room :: Types.RoomPlacement).ceilingHeight <= cap,
							"a roof-bound creature spawned above its inspectable-roof cap"
						)
					end
				end
			end
			Harness.expect(ambushSpawnCount > 0, "test seeds produced no ceiling ambushers")
		end),

		-- THE LOOT ECONOMY, measured rather than asserted from the config table. Two independent
		-- promises are being kept here and they pull in opposite directions, which is why both are
		-- checked over a real population of floors instead of by reading the weights:
		--
		--   1. Ordinary floors are SPARSE — around 0 to 2 pickups early, more as a run goes deep.
		--   2. The Candle Sleeve is genuinely rare AND genuinely absent above its family's gate.
		Harness.test("pickups stay sparse early, grow with depth, and the Sleeve stays gated", function()
			local shallowTotal, shallowFloors = 0, 0
			local deepTotal, deepFloors = 0, 0
			local sleevesAboveGate = 0
			local sleevesBelowGate = 0
			local totalPickups = 0

			for _, familyId in { "STONE", "MOSS", "ICE" } do
				local gate = (LootConfig.definitions.CandleSleeve.minDepthByFamily :: { [string]: number })[familyId]
				for _, depth in { 1, 2, 3, 4, 20 } do
					for seed = 1, 24 do
						local plan = FloorPlanner.plan({
							globalDepth = depth,
							localFloor = 1,
							rng = Random.new(seed * 6_700_417 + depth * 31),
							familyId = familyId,
						})
						local count = #plan.lootSpawns
						totalPickups += count
						if depth <= 4 then
							shallowTotal += count
							shallowFloors += 1
							Harness.expect(count <= 2, "a shallow floor planned more than two pickups")
						else
							deepTotal += count
							deepFloors += 1
						end
						for _, spawn in plan.lootSpawns do
							if spawn.lootId == "CandleSleeve" then
								if depth >= gate then
									sleevesAboveGate += 1
								else
									sleevesBelowGate += 1
								end
							end
						end
					end
				end
			end

			local shallowAverage = shallowTotal / shallowFloors
			local deepAverage = deepTotal / deepFloors
			Harness.expect(
				shallowAverage <= 1.4,
				("shallow floors averaged %.2f pickups; the pool is meant to be sparse"):format(shallowAverage)
			)
			Harness.expect(
				deepAverage > shallowAverage,
				("deep floors (%.2f) must be richer than shallow ones (%.2f)"):format(deepAverage, shallowAverage)
			)
			-- Absolute, not statistical: a gate that leaks even once is not a gate.
			Harness.equal(sleevesBelowGate, 0, "a Candle Sleeve spawned above its family's depth gate")
			-- And past the gate it must still be the rarest thing in the pool by a wide margin.
			Harness.expect(
				sleevesAboveGate * 10 <= totalPickups,
				("the Candle Sleeve was %d of %d pickups; it is meant to be much rarer than every other item"):format(
					sleevesAboveGate,
					totalPickups
				)
			)
		end),

		Harness.test("every cave family scales its own expedition and Moss and Ice outpace Stone", function()
			local batchSize = math.min(8, FloorsConfig.planningBatchSize)
			local totals: { [string]: number } = {}
			for _, familyId in { "STONE", "MOSS", "ICE" } do
				local plans = FloorPlanner.planAll(82_104, batchSize, familyId)
				Harness.equal(#plans, batchSize)
				local total = 0
				for _, plan in plans do
					Harness.equal(plan.familyId, familyId, "a plan must record the family that produced it")
					-- The budget the planner actually spent equals the documented three-factor product.
					Harness.equal(#plan.threatSpawns, expectedThreatCount(plan), familyId .. " threat budget")
					total += #plan.threatSpawns
				end
				totals[familyId] = total
			end
			Harness.expect(totals.MOSS > totals.STONE, "Moss must carry more threat pressure than Stone")
			Harness.expect(totals.ICE > totals.MOSS, "Ice must carry more threat pressure than Moss")
		end),

		Harness.test("an unknown cave family falls back to the free one rather than erroring", function()
			local plans = FloorPlanner.planAll(82_104, 3, "NOT_A_FAMILY")
			Harness.equal(#plans, 3)
			for _, plan in plans do
				Harness.equal(plan.familyId, "STONE", "an unknown family id must resolve to the free family")
			end
		end),

		Harness.test("every family generates safely at every representative depth", function()
			-- THE INTEGRATION SWEEP. Stone, Moss and Ice at floors 1, 3, 5, 8, 12, 16 and a technical
			-- ceiling, solo and four-player. Everything checked here is a guarantee a shape is not
			-- allowed to break: entry/Basin/completion stay rectangles, every planned position sits in
			-- real open air, doorway lanes and the navigation hub survive, and the dry route holds.
			--
			-- The party size is threaded through the SEED rather than through a scaling parameter,
			-- because party scaling is applied downstream of planning; what this proves is that a floor
			-- generated for either party size is structurally sound, which is the planner's own job.
			local depths = { 1, 3, 5, 8, 12, 16, 240 }
			local checkedShaped = 0
			-- How often the peripheral ring sweep ran out of shelves and fell back to the room's own
			-- navigation hub. That fallback is the reason a pickup can never end up under the map, but
			-- an item in the exact middle of a room is the failure the sweep exists to prevent, so this
			-- counts them across every family, depth and party size and holds the rate near zero.
			local plannedPickups = 0
			local hubFallbacks = 0
			for _, familyId in { "STONE", "MOSS", "ICE" } do
				for _, partySeed in { 1, 4 } do
					for _, depth in depths do
						local plan = FloorPlanner.plan({
							globalDepth = depth,
							localFloor = 1,
							rng = Random.new(depth * 7919 + partySeed * 104_729),
							familyId = familyId,
						})
						local label = string.format("%s depth %d party %d", familyId, depth, partySeed)
						Harness.equal(plan.familyId, familyId, label)
						Harness.expect(#plan.rooms > 0, label .. ": a floor must have rooms")

						-- Protected rooms keep the canonical rectangle, and every ordinary room's
						-- footprint is contained, connected and valid.
						for index, room in plan.rooms do
							local footprint = room.footprint :: any
							Harness.expect(footprint ~= nil, label .. ": every room needs a footprint")
							if
								index == plan.entryRoomIndex
								or index == plan.basinRoomIndex
								or index == plan.brazierRoomIndex
								or (plan.warden ~= nil and index == plan.warden.roomIndex)
							then
								Harness.equal(footprint.kind, "Rectangle", label .. ": protected room " .. index)
							end
							Harness.expect(RoomFootprint.isValid(footprint), label .. ": invalid footprint")
							if footprint.kind ~= "Rectangle" then
								checkedShaped += 1
							end
						end

						-- Every planned gameplay position is inside its room's real open air, not
						-- inside the rock a shape left behind.
						local masks: { [number]: any } = {}
						local function maskFor(roomIndex: number)
							local cached = masks[roomIndex]
							if cached == nil then
								cached = RoomFootprint.maskFor(plan.rooms[roomIndex], plan.globalDepth, plan.familyId)
								masks[roomIndex] = cached
							end
							return cached
						end
						local threatBox = Vector3.new(
							FloorsConfig.terrain.gameplaySpawnRadius * 2,
							0,
							FloorsConfig.terrain.gameplaySpawnRadius * 2
						)
						for _, spawn in plan.threatSpawns do
							Harness.expect(
								RoomFootprint.containsBox(maskFor(spawn.roomIndex), spawn.offset, threatBox),
								label .. ": a threat spawned inside solid rock"
							)
						end
						local lootSurfaceWidth = LootConfig.placementFootprint
							+ FloorsConfig.geometry.placementProbe.horizontalMarginStuds * 2
						local lootBox = Vector3.new(lootSurfaceWidth, 0, lootSurfaceWidth)
						for _, spawn in plan.lootSpawns do
							Harness.expect(
								RoomFootprint.containsBox(maskFor(spawn.roomIndex), spawn.offset, lootBox),
								label .. ": an item spawned inside solid rock"
							)
							plannedPickups += 1
							local centerDistance = Vector3.new(spawn.offset.X, 0, spawn.offset.Z).Magnitude
							if centerDistance <= 1e-6 then
								hubFallbacks += 1
							else
								Harness.expect(
									centerDistance >= LootConfig.minimumCenterDistance - 1e-6,
									label .. ": an item was planned inside the room's central walking line"
								)
							end
							local def = LootConfig.definitions[spawn.lootId] :: Types.LootDef
							Harness.expect(
								LootRules.isAvailable(def, plan.familyId, plan.globalDepth),
								label .. ": an item ignored its family depth gate"
							)
							if spawn.lootId == "CandleSleeve" then
								local gate = (def.minDepthByFamily :: { [string]: number })[plan.familyId]
								Harness.expect(
									gate ~= nil and plan.globalDepth >= gate,
									label .. ": a Candle Sleeve appeared above its gate"
								)
							end
						end
						local reserved = math.max(
							MiningConfig.placement.footprint + MiningConfig.placement.standingClearance,
							MiningConfig.placement.footprint
								+ FloorsConfig.geometry.placementProbe.horizontalMarginStuds * 2
						)
						local depositBox = Vector3.new(reserved, 0, reserved)
						for _, deposit in plan.deposits do
							Harness.expect(
								RoomFootprint.containsBox(maskFor(deposit.roomIndex), deposit.localOffset, depositBox),
								label .. ": a seam and its standing room did not fit the open floor"
							)
							-- Every seam records an ore tier this family actually offers at this depth.
							local shares =
								OreRules.tierProbabilities(CaveFamilyRules.resolve(plan.familyId), plan.globalDepth)
							Harness.expect(
								(shares[deposit.oreTier] or 0) > 0,
								label .. ": a seam carried ore this cave does not contain"
							)
						end
						for _, formation in plan.dripstones do
							-- The Warden's counter-hazard is placed on a reserved pad rather than
							-- through the ordinary sweep, so it is exempt from the footprint check.
							if plan.warden ~= nil and formation.roomIndex == plan.warden.roomIndex then
								continue
							end
							Harness.expect(
								RoomFootprint.isOpen(
									maskFor(formation.roomIndex),
									formation.localOffset.X,
									formation.localOffset.Z
								),
								label .. ": an unstable formation hangs inside solid rock"
							)
						end
						for _, hazard in plan.hazards do
							local size = hazard.size
							local offset = hazard.localOffset
							if size == nil or offset == nil then
								continue
							end
							Harness.expect(
								(size :: Vector3).X > 0 and (size :: Vector3).Z > 0,
								label .. ": a zero-sized pool was recorded"
							)
							Harness.expect(
								RoomFootprint.isOpen(
									maskFor(hazard.roomIndex),
									(offset :: Vector3).X,
									(offset :: Vector3).Z
								),
								label .. ": a pool was carved into solid rock"
							)
						end

						-- The floor's own guarantees are untouched by any of it.
						Harness.expect(hasWaterFreePath(plan), label .. ": the dry entry -> Basin route was lost")
						Harness.expect(
							plan.basinRoomIndex ~= plan.entryRoomIndex,
							label .. ": the Basin must not be the entry"
						)
					end
				end
			end
			Harness.expect(checkedShaped > 0, "the sweep produced no shaped rooms to check")
			Harness.expect(plannedPickups > 0, "the sweep produced no pickups to check")
			-- The whole point of the ring sweep: the room hub is a safety net, not a placement strategy.
			Harness.expect(
				hubFallbacks * 20 <= plannedPickups,
				("%d of %d pickups fell back to the room hub — the peripheral sweep is not doing its job"):format(
					hubFallbacks,
					plannedPickups
				)
			)
		end),

		Harness.test("repeated floors at one depth stay reproducible and independently cleanable", function()
			-- Cleanup is per floor and keyed by the expedition ordinal, so the same global depth
			-- reached twice must produce the same cave both times — otherwise a rebuilt floor would
			-- not match the one whose Instances were just torn down.
			for _, familyId in { "STONE", "MOSS", "ICE" } do
				for _, depth in { 1, 5, 12 } do
					local first = FloorPlanner.plan({
						globalDepth = depth,
						localFloor = 2,
						rng = Random.new(depth * 31 + 7),
						familyId = familyId,
					})
					local second = FloorPlanner.plan({
						globalDepth = depth,
						localFloor = 2,
						rng = Random.new(depth * 31 + 7),
						familyId = familyId,
					})
					Harness.equal(planSignature(first), planSignature(second), familyId .. " depth " .. depth)
					-- The room footprints are part of that reproducibility, not a separate roll.
					for index, room in first.rooms do
						local other = second.rooms[index]
						Harness.equal((room.footprint :: any).kind, (other.footprint :: any).kind)
						Harness.near((room.footprint :: any).primaryX, (other.footprint :: any).primaryX, 1e-9)
						Harness.near((room.footprint :: any).rotation, (other.footprint :: any).rotation, 1e-9)
					end
				end
			end
		end),

		Harness.test("Moss loops and obstructs while Ice opens out and stretches", function()
			-- The families have to be visibly different SHAPES of floor, not just different numbers.
			-- Measured over many seeds because any single floor can be atypical.
			local function survey(familyId: string)
				local doorways, rooms, shaped, twinLobes, capsules, ceiling = 0, 0, 0, 0, 0, 0
				for seed = 1, 40 do
					for _, plan in FloorPlanner.planAll(seed * 15_485_863, 8, familyId) do
						for index, room in plan.rooms do
							rooms += 1
							doorways += #room.doorways
							ceiling += room.ceilingHeight
							local kind = (room.footprint :: any).kind
							if kind ~= "Rectangle" then
								shaped += 1
							end
							if kind == "TwinLobe" then
								twinLobes += 1
							elseif kind == "Capsule" then
								capsules += 1
							end
							local _ = index
						end
					end
				end
				return {
					connectivity = doorways / rooms,
					shapedShare = shaped / rooms,
					twinLobeShare = twinLobes / rooms,
					capsuleShare = capsules / rooms,
					meanCeiling = ceiling / rooms,
				}
			end

			local stone, moss, ice = survey("STONE"), survey("MOSS"), survey("ICE")
			-- Moss is the cave of obstructed information: more cycles, and the twin-lobe rooms whose
			-- central rock mass is what does the obstructing.
			Harness.expect(moss.connectivity > stone.connectivity, "Moss must loop more than Stone")
			Harness.expect(moss.twinLobeShare > stone.twinLobeShare, "Moss must lean on twin lobes")
			Harness.expect(moss.twinLobeShare > ice.twinLobeShare, "Ice must not be the twin-lobe family")
			-- Ice is the cave of exposure: fewer cycles, taller rooms, long capsule vaults.
			Harness.expect(ice.connectivity < stone.connectivity, "Ice must loop less than Stone")
			Harness.expect(ice.meanCeiling > moss.meanCeiling, "Ice must run taller than Moss")
			Harness.expect(ice.capsuleShare > moss.capsuleShare, "Ice must lean on long vaults")
			-- And about half of every family's ordinary rooms are non-rectangular by config. Protected
			-- rooms are always rectangles, so the share across ALL rooms lands below a half.
			for _, survey_ in { stone, moss, ice } do
				Harness.expect(
					survey_.shapedShare > 0.2 and survey_.shapedShare < 0.5,
					string.format("shaped-room share %.2f is outside the intended band", survey_.shapedShare)
				)
			end
		end),

		Harness.test("a planning batch keeps its invariants deep past authored content", function()
			local deepTestDepth = 30
			local plans = FloorPlanner.planAll(46_021, deepTestDepth, "STONE", 1)
			Harness.equal(#plans, deepTestDepth, "deep planning must not be truncated")

			local checkedDeep = 0
			for index, plan in plans do
				Harness.equal(plan.depth, index)
				Harness.equal(plan.globalDepth, index)
				Harness.equal(
					#plan.rooms,
					DepthRules.getRoomCountTarget(plan.globalDepth) + 1 + (if plan.warden ~= nil then 1 else 0)
				)
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
				if index == 11 or index == 15 or index == deepTestDepth then
					checkedDeep += 1
				end
			end
			Harness.equal(checkedDeep, 3, "depths 11, 15 and 30 must all be covered")
		end),

		Harness.test("a floor is reproducible from its global depth, not its position in a run", function()
			-- Same run seed and tier: the fifth floor of a surface run and the first floor of a run
			-- that starts at depth 5 are the same cave.
			local fromSurface = FloorPlanner.planAll(555_111, 6, "MOSS", 1)
			local fromDepthFive = FloorPlanner.planAll(555_111, 2, "MOSS", 5)
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
			local plans = FloorPlanner.planAll(9_182, 30, "ICE", 1)
			local seen: { [string]: number } = {}
			for _, plan in plans do
				local signature = planSignature(plan)
				Harness.isNil(seen[signature], "two depths produced an identical plan")
				seen[signature] = plan.globalDepth
			end
		end),

		Harness.test("invalid depths are refused while valid deep batches remain uncapped", function()
			for _, badDepth in { 0, -3, 2.5 } do
				local ok = pcall(function()
					FloorPlanner.plan({ globalDepth = badDepth, rng = Random.new(1) })
				end)
				Harness.expect(not ok, "depth " .. tostring(badDepth) .. " should have been refused")
			end
			local plans = FloorPlanner.planAll(4_242, 12, "STONE", 98)
			Harness.equal(#plans, 12)
			Harness.equal(plans[#plans].globalDepth, 109)
		end),
	},
}

return suite

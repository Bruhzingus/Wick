--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local FloorPlanner = require(script.Parent.Parent.Logic.FloorPlanner)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)

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

local function roomHasThreatAtDepth(def: Types.RoomModuleDef, depth: number): boolean
	for _, threatId in def.allowedThreats do
		local threatDef = ThreatsConfig.definitions[threatId]
		if threatDef ~= nil and weightAtDepth(threatDef.spawnWeightByDepth, depth) > 0 then
			return true
		end
	end
	return false
end

local function hasDirection(doorways: { Types.Direction }, wanted: Types.Direction): boolean
	for _, direction in doorways do
		if direction == wanted then
			return true
		end
	end
	return false
end

local function planSignature(plan: Types.FloorPlan): string
	local pieces: { string } = {
		tostring(plan.depth),
		tostring(plan.entryRoomIndex),
		tostring(plan.basinRoomIndex),
		tostring(plan.brazierRoomIndex),
	}
	for _, room in plan.rooms do
		table.insert(
			pieces,
			string.format("R:%s:%d:%d:%s", room.moduleId, room.gridX, room.gridZ, table.concat(room.doorways, ","))
		)
	end
	for _, spawn in plan.threatSpawns do
		table.insert(pieces, string.format("T:%s:%d", spawn.threatId, spawn.roomIndex))
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
			string.format("H:%s:%d:%s", hazard.hazardId, hazard.roomIndex, tostring(hazard.waterDepth))
		)
	end
	return table.concat(pieces, "|")
end

local suite: Harness.Suite = {
	name = "FloorPlanner",
	tests = {
		Harness.test("the same seed reproduces every floor exactly", function()
			local first = FloorPlanner.planAll(731_947)
			local second = FloorPlanner.planAll(731_947)
			Harness.equal(#first, FloorsConfig.maxFloors)
			Harness.equal(#second, #first)
			for index, plan in first do
				Harness.equal(planSignature(plan), planSignature(second[index]), "seed changed at floor " .. index)
				Harness.equal(plan.depth, index)
			end
		end),

		Harness.test("every plan is a connected reciprocal grid with one safe Basin", function()
			for _, plan in FloorPlanner.planAll(91_337) do
				local depthIndex = math.clamp(plan.depth, 1, #FloorsConfig.roomsPerFloor)
				Harness.equal(
					#plan.rooms,
					FloorsConfig.roomsPerFloor[depthIndex] + 1,
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

		Harness.test("threat and hazard placements obey module allow-lists and safe-room exclusions", function()
			for _, plan in FloorPlanner.planAll(44_021) do
				local eligibleThreatRooms = 0
				for index, room in plan.rooms do
					local def = moduleById(room.moduleId)
					if
						index ~= plan.entryRoomIndex
						and index ~= plan.basinRoomIndex
						and def ~= nil
						and roomHasThreatAtDepth(def, plan.depth)
					then
						eligibleThreatRooms += 1
					end
				end

				local budgetIndex = math.clamp(plan.depth, 1, #FloorsConfig.threatBudgetPerFloor)
				local expectedThreats = if eligibleThreatRooms > 0
					then FloorsConfig.threatBudgetPerFloor[budgetIndex]
					else 0
				Harness.equal(#plan.threatSpawns, expectedThreats)
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
					Harness.expect(math.abs(spawn.offset.X) <= LootConfig.spawnOffsetRadius)
					Harness.expect(math.abs(spawn.offset.Z) <= LootConfig.spawnOffsetRadius)
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
						waterCountByRoom[hazard.roomIndex] = (waterCountByRoom[hazard.roomIndex] or 0) + 1
					else
						local allowed = false
						for _, hazardId in roomDef.allowedHazards do
							if hazardId == hazard.hazardId then
								allowed = true
								break
							end
						end
						Harness.expect(allowed, "hazard spawned outside its module allow-list")
					end
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

		Harness.test("cave-tier floor and threat multipliers change the generated expedition", function()
			local maxFloors = math.min(6, FloorsConfig.maxFloors)
			local multiplier = 0.6
			local plans = FloorPlanner.planAll(82_104, maxFloors, multiplier)
			Harness.equal(#plans, maxFloors)
			for _, plan in plans do
				local budgetIndex = math.clamp(plan.depth, 1, #FloorsConfig.threatBudgetPerFloor)
				local expected =
					math.max(0, math.floor(FloorsConfig.threatBudgetPerFloor[budgetIndex] * multiplier + 0.5))
				Harness.equal(#plan.threatSpawns, expected)
			end

			for _, plan in FloorPlanner.planAll(82_104, maxFloors, 0) do
				Harness.equal(#plan.threatSpawns, 0)
			end
		end),
	},
}

return suite

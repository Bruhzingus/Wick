--!strict
-- FloorPlan -> cave geometry from primitives. Decides nothing mechanical: room positions,
-- doorways, hazards and special rooms come from the plan; dimensions from Config/Floors.
-- The ONLY randomness here is cosmetic dressing (relief, boulders, ceiling variance), seeded
-- per depth so rebuilds look identical — gameplay math never reads any of it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local HazardService = require(script.Parent.HazardService)

local FloorBuilder = {}

export type FloorRuntime = {
	model: Model,
	depth: number,
	entryPosition: Vector3,
	basinPosition: Vector3,
	brazierPosition: Vector3,
	descentRegion: HazardService.Zone,
	roomCenters: { Vector3 },
	draftZones: { HazardService.Zone },
	waterRegions: { HazardService.WaterRegion },
}

local WALL_COLOR = Color3.fromRGB(46, 44, 50)
local FLOOR_COLOR = Color3.fromRGB(38, 36, 42)
local ROCK_COLOR = Color3.fromRGB(32, 30, 36)
local BASIN_COLOR = Color3.fromRGB(90, 70, 40)

local function newPart(
	size: Vector3,
	position: Vector3,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.Slate
	part.Anchored = true
	part.Parent = parent
	return part
end

local DOOR_NORMALS: { [Types.Direction]: Vector3 } = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

-- One wall of a room, split around a doorway if that side has one. Doorless walls get
-- cosmetic rock-relief strips (collision-neutral) so surfaces read as cave, not corridor.
local function buildWall(
	roomCenter: Vector3,
	direction: Types.Direction,
	hasDoorway: boolean,
	parent: Instance,
	height: number,
	rng: Random
)
	local g = Config.Floors.geometry
	local d = Config.Floors.caveDressing
	local normal = DOOR_NORMALS[direction]
	local along = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X)) -- wall's long axis
	local across = Vector3.new(math.abs(normal.X), 0, math.abs(normal.Z)) -- wall's thickness axis
	local wallCenter = roomCenter + normal * (g.cellSize / 2 - g.wallThickness / 2) + Vector3.new(0, height / 2, 0)

	local function slab(length: number, offsetAlong: number, slabHeight: number, offsetUp: number)
		local size = along * length + across * g.wallThickness + Vector3.new(0, slabHeight, 0)
		local position = wallCenter + along * offsetAlong + Vector3.new(0, offsetUp, 0)
		newPart(size, position, WALL_COLOR, parent)
	end

	if not hasDoorway then
		slab(g.cellSize, 0, height, 0)
		for _ = 1, d.wallReliefStrips do
			local length = rng:NextNumber(2, 6)
			local depth = rng:NextNumber(0.25, d.wallReliefDepth)
			local stripHeight = height * rng:NextNumber(0.4, 0.95)
			local offsetAlong = rng:NextNumber(-1, 1) * (g.cellSize / 2 - length / 2 - g.wallThickness)
			local position = roomCenter
				+ normal * (g.cellSize / 2 - g.wallThickness - depth / 2)
				+ along * offsetAlong
				+ Vector3.new(0, stripHeight / 2, 0)
			local relief =
				newPart(along * length + across * depth + Vector3.new(0, stripHeight, 0), position, ROCK_COLOR, parent)
			relief.CanCollide = false
		end
		return
	end
	local segment = (g.cellSize - g.doorwayWidth) / 2
	slab(segment, (g.doorwayWidth + segment) / 2, height, 0)
	slab(segment, -(g.doorwayWidth + segment) / 2, height, 0)
	-- Lintel above the doorway gap: spans doorwayHeight..height, centre doorwayHeight/2 above wall centre.
	local lintelHeight = height - g.doorwayHeight
	if lintelHeight > 0 then
		slab(g.doorwayWidth, 0, lintelHeight, g.doorwayHeight / 2)
	end
end

function FloorBuilder.build(plan: Types.FloorPlan): FloorRuntime
	local g = Config.Floors.geometry
	local d = Config.Floors.caveDressing
	local floorY = -(plan.depth - 1) * g.floorGap
	-- Cosmetic-only rng, seeded by depth: identical dressing on rebuild, zero gameplay reads.
	local rng = Random.new(plan.depth * 7919 + 101)

	local model = Instance.new("Model")
	model.Name = "Floor_" .. plan.depth

	local roomCenters: { Vector3 } = {}
	local draftZones: { HazardService.Zone } = {}
	local waterRegions: { HazardService.WaterRegion } = {}

	for index, room in plan.rooms do
		local center = Vector3.new(room.gridX * g.cellSize, floorY, room.gridZ * g.cellSize)
		roomCenters[index] = center
		local isBasin = index == plan.basinRoomIndex
		local isEntry = index == plan.entryRoomIndex
		-- Per-room ceiling variance; never below the doorway (plus lintel clearance).
		local ceilingHeight =
			math.max(g.wallHeight + rng:NextNumber(-d.ceilingJitter, d.ceilingJitter), g.doorwayHeight + 1)

		-- Floor and ceiling slabs enclose the room so darkness is real.
		newPart(
			Vector3.new(g.cellSize, g.wallThickness, g.cellSize),
			center - Vector3.new(0, g.wallThickness / 2, 0),
			if isBasin then BASIN_COLOR else FLOOR_COLOR,
			model
		)
		newPart(
			Vector3.new(g.cellSize, g.wallThickness, g.cellSize),
			center + Vector3.new(0, ceilingHeight + g.wallThickness / 2, 0),
			WALL_COLOR,
			model
		)

		local doorwaySet: { [Types.Direction]: boolean } = {}
		for _, direction in room.doorways do
			doorwaySet[direction] = true
		end
		for direction in DOOR_NORMALS do
			buildWall(center, direction, doorwaySet[direction] == true, model, ceilingHeight, rng)
		end

		-- Boulders: collidable scatter in ordinary rooms only (entry stays a safe spawn).
		if not isBasin and not isEntry then
			for _ = 1, d.bouldersPerRoom do
				local base = rng:NextNumber(d.boulderMinSize, d.boulderMaxSize)
				local size = Vector3.new(base, base * rng:NextNumber(0.6, 1.1), base * rng:NextNumber(0.7, 1.3))
				local offset = Vector3.new(
					rng:NextNumber(-1, 1) * g.cellSize * 0.32,
					size.Y / 2,
					rng:NextNumber(-1, 1) * g.cellSize * 0.32
				)
				local boulder = newPart(size, center + offset, ROCK_COLOR, model)
				boulder.CFrame = CFrame.new(boulder.Position) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
			end
		end
	end

	-- Hazards from the plan: draft zones fill the room's doorways; water fills the room.
	for _, hazard in plan.hazards do
		local center = roomCenters[hazard.roomIndex]
		local room = plan.rooms[hazard.roomIndex]
		if hazard.hazardId == "Draft" then
			for _, direction in room.doorways do
				local normal = DOOR_NORMALS[direction]
				local zoneCenter = center + normal * (g.cellSize / 2) + Vector3.new(0, g.doorwayHeight / 2, 0)
				local along = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X))
				local across = Vector3.new(math.abs(normal.X), 0, math.abs(normal.Z))
				local zone: HazardService.Zone = {
					center = zoneCenter,
					size = along * g.doorwayWidth + across * (g.cellSize / 3) + Vector3.new(0, g.doorwayHeight, 0),
				}
				table.insert(draftZones, zone)
				-- Faintly visible so placement is verifiable in grey-box; reads as haze, not art.
				local visual =
					newPart(zone.size, zone.center, Color3.fromRGB(120, 125, 135), model, Enum.Material.SmoothPlastic)
				visual.Transparency = 0.92
				visual.CanCollide = false
			end
		elseif hazard.hazardId == "Water" then
			local depth = hazard.waterDepth :: number -- Water placements always carry waterDepth
			local surface = newPart(
				Vector3.new(g.cellSize, depth, g.cellSize),
				center + Vector3.new(0, depth / 2, 0),
				Color3.fromRGB(25, 35, 55),
				model,
				Enum.Material.SmoothPlastic
			)
			surface.Transparency = 0.5
			surface.CanCollide = false
			table.insert(waterRegions, {
				surfaceY = floorY + depth,
				center = center,
				size = Vector3.new(g.cellSize, depth, g.cellSize),
			})
		end
	end

	-- Basin room fixtures: the pool, and the descent pad (unusable on the last floor by plan).
	local basinCenter = roomCenters[plan.basinRoomIndex]
	local poolRadius = g.cellSize / 8
	local pool = newPart(
		Vector3.new(poolRadius * 2, 1, poolRadius * 2),
		basinCenter + Vector3.new(0, 0.5, 0),
		Color3.fromRGB(255, 180, 80),
		model,
		Enum.Material.Neon
	)
	pool.Shape = Enum.PartType.Cylinder
	pool.CFrame = CFrame.new(pool.Position) * CFrame.Angles(0, 0, math.rad(90))

	local padSize = g.cellSize / 8
	local descentCenter = basinCenter + Vector3.new(g.cellSize / 4, 0, g.cellSize / 4)
	newPart(
		Vector3.new(padSize, 0.4, padSize),
		descentCenter + Vector3.new(0, 0.2, 0),
		Color3.fromRGB(20, 16, 24),
		model,
		Enum.Material.Neon
	)

	-- Brazier pedestal.
	local brazierCenter = roomCenters[plan.brazierRoomIndex] + Vector3.new(-g.cellSize / 4, 0, -g.cellSize / 4)
	newPart(Vector3.new(2, 3, 2), brazierCenter + Vector3.new(0, 1.5, 0), Color3.fromRGB(35, 30, 30), model)

	model.Parent = workspace

	return {
		model = model,
		depth = plan.depth,
		entryPosition = roomCenters[plan.entryRoomIndex],
		basinPosition = basinCenter,
		brazierPosition = brazierCenter + Vector3.new(0, 3, 0),
		descentRegion = { center = descentCenter + Vector3.new(0, 2, 0), size = Vector3.new(padSize, 4, padSize) },
		roomCenters = roomCenters,
		draftZones = draftZones,
		waterRegions = waterRegions,
	}
end

return FloorBuilder

--!strict
-- FloorPlan -> cave geometry from primitives. Decides nothing mechanical: room positions,
-- doorways, hazards and special rooms come from the plan; dimensions from Config/Floors.
-- The ONLY randomness here is cosmetic dressing (relief, boulders, ceiling variance), seeded
-- per depth so rebuilds look identical — gameplay math never reads any of it.

local CollectionService = game:GetService("CollectionService")
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
local WATER_COLOR = Color3.fromRGB(38, 78, 110)
local WATER_TAG = "WickWaterSurface"
local DRAFT_VISUAL_TAG = "WickDraftVisual"

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

local function newJaggedShard(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	parent: Instance,
	rng: Random
): WedgePart
	local shard = Instance.new("WedgePart")
	shard.Name = name
	shard.Size = size
	shard.CFrame = CFrame.new(position)
		* CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 2 * math.pi), rng:NextNumber(-0.18, 0.18))
	shard.Color = color
	shard.Material = Enum.Material.Slate
	shard.Anchored = true
	shard.Parent = parent
	return shard
end

local DOOR_NORMALS: { [Types.Direction]: Vector3 } = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

-- A per-room description of the cave floor's height. The floor is not flat: it swells into rock
-- toward the walls and stays level where gameplay needs it — the central plaza (spawns, nav, and
-- centre fixtures), the doorway lanes, and a few marked fixture pads. All slopes are gentle so the
-- Humanoid walks them freely and the AI's downward ground probe follows them without snagging.
type FlatSpot = { x: number, z: number, r: number }
type GroundField = {
	amp: number,
	padRadius: number,
	blend: number,
	laneHalfWidth: number,
	doorways: { [Types.Direction]: boolean },
	flatSpots: { FlatSpot },
	freq: { number },
	phase: { number },
}

local function smoothstep(edge0: number, edge1: number, x: number): number
	if edge1 <= edge0 then
		return if x < edge0 then 0 else 1
	end
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function makeGroundField(
	room: Types.RoomPlacement,
	depth: number,
	doorways: { [Types.Direction]: boolean },
	flatSpots: { FlatSpot }
): GroundField
	local seed = math.abs(room.gridX * 40499 + room.gridZ * 86969 + depth * 1300099) % 2_147_483_647
	local r = Random.new(seed)
	return {
		-- Gentle amplitude that grows a little with depth; deeper caves read rougher but stay walkable.
		amp = math.clamp(2.2 + depth * 0.16, 2.2, 4.6),
		padRadius = 8.5, -- flat plaza radius around the room centre
		blend = 6, -- studs over which level ground eases into relief; keeps every slope shallow
		laneHalfWidth = Config.Floors.terrain.doorClearanceWidth / 2,
		doorways = doorways,
		flatSpots = flatSpots,
		freq = { 0.34, 0.41, 0.27 },
		phase = { r:NextNumber(0, 2 * math.pi), r:NextNumber(0, 2 * math.pi), r:NextNumber(0, 2 * math.pi) },
	}
end

-- Height of the floor above the room's base level at a room-local point. Zero on the plaza, in the
-- doorway lanes, and on fixture pads; smoothly rising elsewhere. Deterministic, so rebuilds match.
local function groundOffset(field: GroundField, localX: number, localZ: number): number
	if field.amp <= 0 then
		return 0
	end
	local mask =
		smoothstep(field.padRadius, field.padRadius + field.blend, math.sqrt(localX * localX + localZ * localZ))
	for _, spot in field.flatSpots do
		local dx, dz = localX - spot.x, localZ - spot.z
		mask = math.min(mask, smoothstep(spot.r, spot.r + field.blend, math.sqrt(dx * dx + dz * dz)))
	end
	for direction, open in field.doorways do
		if open then
			local normal = DOOR_NORMALS[direction]
			local along = localX * normal.X + localZ * normal.Z
			if along > 0 then
				local perp = math.abs(localX * normal.Z - localZ * normal.X)
				mask = math.min(mask, smoothstep(field.laneHalfWidth - field.blend, field.laneHalfWidth, perp))
			end
		end
	end
	if mask <= 0 then
		return 0
	end
	local f, p = field.freq, field.phase
	local raw = math.sin(localX * f[1] + p[1]) * 0.6
		+ math.sin(localZ * f[2] + p[2]) * 0.5
		+ math.sin((localX + localZ) * f[3] + p[3]) * 0.4
	return field.amp * (0.5 + 0.5 * (raw / 1.5)) * mask
end

local function surfaceCFrame(position: Vector3, normal: Vector3): CFrame
	local reference = if math.abs(normal.X) < 0.9 then Vector3.xAxis else Vector3.zAxis
	local right = reference:Cross(normal).Unit
	return CFrame.fromMatrix(position, right, normal)
end

-- Lay a grid of tilted slate tiles over the room's sealed flat base, following groundOffset. Near-
-- level tiles are skipped so the base slab reads as the plaza; the rest overlap and run thick
-- downward so the slopes join into one continuous surface with nothing to fall through.
local function buildUndulatingFloor(center: Vector3, field: GroundField, baseColor: Color3, parent: Instance)
	local g = Config.Floors.geometry
	local tiles = 6
	local tileSize = g.cellSize / tiles
	local overlap, thickness, eps = 1.4, 5, 1.5
	for i = 1, tiles do
		for j = 1, tiles do
			local localX = -g.cellSize / 2 + tileSize * (i - 0.5)
			local localZ = -g.cellSize / 2 + tileSize * (j - 0.5)
			local height = groundOffset(field, localX, localZ)
			if height < 0.2 then
				continue
			end
			local slopeX = (groundOffset(field, localX + eps, localZ) - groundOffset(field, localX - eps, localZ))
				/ (2 * eps)
			local slopeZ = (groundOffset(field, localX, localZ + eps) - groundOffset(field, localX, localZ - eps))
				/ (2 * eps)
			local normal = Vector3.new(-slopeX, 1, -slopeZ).Unit
			local surface = center + Vector3.new(localX, height, localZ)
			local part = Instance.new("Part")
			part.Name = "CaveFloor"
			part.Size = Vector3.new(tileSize + overlap, thickness, tileSize + overlap)
			part.CFrame = surfaceCFrame(surface - normal * (thickness / 2), normal)
			part.Color = baseColor:Lerp(ROCK_COLOR, math.clamp(height / field.amp, 0, 1) * 0.6)
			part.Material = Enum.Material.Slate
			part.Anchored = true
			part.Parent = parent
		end
	end
end

local function doorwayDimensions(
	gridX: number,
	gridZ: number,
	direction: Types.Direction,
	depth: number
): (number, number)
	local g = Config.Floors.geometry
	local normal = DOOR_NORMALS[direction]
	-- Doubled edge midpoint is identical from either adjacent room, so both wall halves create
	-- the same opening without adding redundant doorway-profile data to FloorPlan.
	local edgeX2 = gridX * 2 + normal.X
	local edgeZ2 = gridZ * 2 + normal.Z
	local seed = math.abs(edgeX2 * 92_837_111 + edgeZ2 * 689_287_499 + depth * 283_923_481) % 2_147_483_647
	local edgeRng = Random.new(seed)
	return edgeRng:NextNumber(g.doorwayMinWidth, g.doorwayMaxWidth),
		edgeRng:NextNumber(g.doorwayMinHeight, g.doorwayMaxHeight)
end

-- One wall of a room, split around a doorway if that side has one. Doorless walls get
-- cosmetic rock-relief strips (collision-neutral) so surfaces read as cave, not corridor.
local function buildWall(
	roomCenter: Vector3,
	direction: Types.Direction,
	hasDoorway: boolean,
	parent: Instance,
	height: number,
	doorwayWidth: number,
	doorwayHeight: number,
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
	local segment = (g.cellSize - doorwayWidth) / 2
	slab(segment, (doorwayWidth + segment) / 2, height, 0)
	slab(segment, -(doorwayWidth + segment) / 2, height, 0)
	-- Lintel above the doorway gap: spans doorwayHeight..height, centre doorwayHeight/2 above wall centre.
	local lintelHeight = height - doorwayHeight
	if lintelHeight > 0 then
		slab(doorwayWidth, 0, lintelHeight, doorwayHeight / 2)
	end

	-- Deep, collision-neutral rock clusters obscure the rectangular wall cutout so each
	-- connection reads as its own eroded cave throat while preserving a guaranteed clear lane.
	for _, side in { -1, 1 } do
		for _ = 1, d.caveMouthRocksPerSide do
			local base = rng:NextNumber(d.caveMouthRockMinSize, d.caveMouthRockMaxSize)
			local rock = newJaggedShard(
				"CaveMouthRock",
				Vector3.new(base * rng:NextNumber(0.7, 1.2), base * rng:NextNumber(0.8, 1.5), base),
				roomCenter
					+ normal * (g.cellSize / 2 - g.wallThickness - rng:NextNumber(0.2, base * 0.7))
					+ along * side * rng:NextNumber(
						d.caveMouthMinClearWidth / 2 + base * 0.3,
						doorwayWidth / 2 + base * 0.4
					)
					+ Vector3.new(0, rng:NextNumber(base / 2, doorwayHeight - base / 2), 0),
				ROCK_COLOR,
				parent,
				rng
			)
			rock.CanCollide = false
			rock.CanQuery = false
		end
	end
	for _ = 1, d.caveMouthCeilingRocks do
		local base = rng:NextNumber(d.caveMouthRockMinSize, d.caveMouthRockMaxSize)
		local lowestCenter = d.caveMouthMinClearHeight + base / 2
		local topCenter = math.max(lowestCenter, doorwayHeight + rng:NextNumber(-base * 0.25, base * 0.35))
		local rock = newJaggedShard(
			"CaveMouthArchRock",
			Vector3.new(
				base * rng:NextNumber(0.8, 1.5),
				base * rng:NextNumber(0.65, 1.2),
				base * rng:NextNumber(0.8, 1.25)
			),
			roomCenter
				+ normal * (g.cellSize / 2 - g.wallThickness - rng:NextNumber(0.2, base * 0.65))
				+ along * rng:NextNumber(-doorwayWidth * 0.48, doorwayWidth * 0.48)
				+ Vector3.new(0, topCenter, 0),
			ROCK_COLOR,
			parent,
			rng
		)
		rock.CanCollide = false
		rock.CanQuery = false
	end
end

local function buildCeilingFormation(
	center: Vector3,
	ceilingHeight: number,
	length: number,
	width: number,
	parent: Instance,
	rng: Random
)
	local segmentRatios = { 0.42, 0.34, 0.24 }
	local widthRatios = { 1, 0.68, 0.38 }
	local descended = 0
	for index, ratio in segmentRatios do
		local segmentHeight = length * ratio
		local segmentWidth = width * widthRatios[index]
		local segmentCenter = center + Vector3.new(0, ceilingHeight - descended - segmentHeight / 2, 0)
		local segment = newJaggedShard(
			"Stalactite",
			Vector3.new(
				segmentWidth * rng:NextNumber(0.82, 1.18),
				segmentHeight,
				segmentWidth * rng:NextNumber(0.82, 1.18)
			),
			segmentCenter,
			ROCK_COLOR,
			parent,
			rng
		)
		segment.CanCollide = false
		segment.CanQuery = false

		-- A crossed second shard removes the single triangular-prism read and gives the hanging
		-- formation a rough pyramidal silhouette from every direction.
		local cross = newJaggedShard(
			"Stalactite",
			Vector3.new(segmentWidth * 0.68, segmentHeight * 0.92, segmentWidth * 0.78),
			segmentCenter + Vector3.new(0, -segmentHeight * 0.05, 0),
			ROCK_COLOR,
			parent,
			rng
		)
		cross.CFrame *= CFrame.Angles(0, math.rad(90), math.rad(180))
		cross.CanCollide = false
		cross.CanQuery = false
		descended += segmentHeight * 0.82
	end
end

local function buildGroundRise(center: Vector3, size: Vector3, parent: Instance, rng: Random)
	local terrain = Config.Floors.terrain
	local plateauX = size.X * terrain.groundPlateauFraction
	local plateauZ = size.Z * terrain.groundPlateauFraction
	local riseHeight = size.Y
	local plateau = newPart(
		Vector3.new(plateauX, riseHeight, plateauZ),
		center + Vector3.new(0, riseHeight / 2, 0),
		ROCK_COLOR,
		parent
	)
	plateau.Name = "GroundRise"

	local runX = math.max((size.X - plateauX) / 2, 0.1)
	local runZ = math.max((size.Z - plateauZ) / 2, 0.1)
	local xSlopeLength = math.sqrt(runX * runX + riseHeight * riseHeight)
	local zSlopeLength = math.sqrt(runZ * runZ + riseHeight * riseHeight)
	local xAngle = math.atan2(riseHeight, runX)
	local zAngle = math.atan2(riseHeight, runZ)
	for _, side in { -1, 1 } do
		local xRamp = newPart(
			Vector3.new(xSlopeLength, terrain.groundRampThickness, plateauZ),
			center + Vector3.new(side * (plateauX / 2 + runX / 2), riseHeight / 2, 0),
			ROCK_COLOR,
			parent
		)
		xRamp.Name = "GroundRiseRamp"
		xRamp.CFrame = CFrame.new(xRamp.Position) * CFrame.Angles(0, 0, -side * xAngle)

		local zRamp = newPart(
			Vector3.new(plateauX, terrain.groundRampThickness, zSlopeLength),
			center + Vector3.new(0, riseHeight / 2, side * (plateauZ / 2 + runZ / 2)),
			ROCK_COLOR,
			parent
		)
		zRamp.Name = "GroundRiseRamp"
		zRamp.CFrame = CFrame.new(zRamp.Position) * CFrame.Angles(side * zAngle, 0, 0)
	end

	-- Small non-colliding shards break the plateau and ramp seams without introducing steps that
	-- trap Humanoids or confuse the threat ground ray.
	for _ = 1, 3 do
		local shardWidth = rng:NextNumber(math.min(plateauX, plateauZ) * 0.18, math.min(plateauX, plateauZ) * 0.4)
		local shardHeight = rng:NextNumber(0.35, math.min(1.1, riseHeight * 0.45))
		local shard = newJaggedShard(
			"GroundRiseShard",
			Vector3.new(shardWidth, shardHeight, shardWidth * rng:NextNumber(0.55, 1)),
			center
				+ Vector3.new(
					rng:NextNumber(-plateauX * 0.28, plateauX * 0.28),
					riseHeight + shardHeight / 2 - 0.12,
					rng:NextNumber(-plateauZ * 0.28, plateauZ * 0.28)
				),
			ROCK_COLOR,
			parent,
			rng
		)
		shard.CanCollide = false
		shard.CanQuery = false
	end
end

local function buildPoolFloor(center: Vector3, placement: Types.HazardPlacement, floorColor: Color3, parent: Instance)
	local geometry = Config.Floors.geometry
	local pool = Config.Hazards.waterPool
	local offset = placement.localOffset :: Vector3
	local poolSize = placement.size :: Vector3
	local depth = placement.waterDepth :: number
	local halfCell = geometry.cellSize / 2
	local minX, maxX = -halfCell, halfCell
	local minZ, maxZ = -halfCell, halfCell
	local poolMinX, poolMaxX = offset.X - poolSize.X / 2, offset.X + poolSize.X / 2
	local poolMinZ, poolMaxZ = offset.Z - poolSize.Z / 2, offset.Z + poolSize.Z / 2

	local function slab(sizeX: number, sizeZ: number, localX: number, localZ: number, topY: number)
		if sizeX <= 0 or sizeZ <= 0 then
			return
		end
		newPart(
			Vector3.new(sizeX, geometry.wallThickness, sizeZ),
			center + Vector3.new(localX, topY - geometry.wallThickness / 2, localZ),
			floorColor,
			parent
		)
	end

	-- Four surrounding shelves leave a real opening instead of laying water over a flat floor.
	slab(poolMinX - minX, geometry.cellSize, (minX + poolMinX) / 2, 0, 0)
	slab(maxX - poolMaxX, geometry.cellSize, (poolMaxX + maxX) / 2, 0, 0)
	slab(poolSize.X, poolMinZ - minZ, offset.X, (minZ + poolMinZ) / 2, 0)
	slab(poolSize.X, maxZ - poolMaxZ, offset.X, (poolMaxZ + maxZ) / 2, 0)
	slab(poolSize.X, poolSize.Z, offset.X, offset.Z, -depth)

	-- Submerged steps on one bank prevent a deep optional pool from becoming an inescapable
	-- softlock. Water can still drown a short candle before it reaches the bank.
	local stepCount = math.max(1, math.ceil(depth / pool.escapeStepMaxRise))
	local run = math.min(pool.escapeRun, poolSize.X * 0.45)
	local stepWidth = run / stepCount
	for stepIndex = 1, stepCount do
		local topY = -depth * stepIndex / stepCount
		slab(stepWidth, poolSize.Z * 0.5, poolMinX + stepWidth * (stepIndex - 0.5), offset.Z, topY)
	end
end

local function addWaterSurfaceGui(surface: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "WaterSheen"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.PixelsPerStud = 16
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = surface

	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BorderSizePixel = 0
	sheen.BackgroundColor3 = WATER_COLOR
	sheen.BackgroundTransparency = 0.3
	sheen.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Name = "FlowGradient"
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 42, 68)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(92, 145, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 58, 88)),
	})
	gradient.Rotation = 18
	gradient.Parent = sheen
end

local function addWindParticles(haze: BasePart, along: Vector3)
	local animation = Config.Hazards.animation
	local attachment = Instance.new("Attachment")
	attachment.Name = "WindOrigin"
	attachment.CFrame = CFrame.lookAt(Vector3.zero, along)
	attachment.Parent = haze

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WindStreaks"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(180, 225, 255), Color3.fromRGB(90, 145, 205))
	emitter.LightEmission = 0.35
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.Lifetime = NumberRange.new(0.8, 1.35)
	emitter.Rate = animation.windParticleRate
	emitter.Speed = NumberRange.new(animation.windParticleMinSpeed, animation.windParticleMaxSpeed)
	emitter.SpreadAngle = Vector2.new(8, 16)
	emitter.Rotation = NumberRange.new(-20, 20)
	emitter.RotSpeed = NumberRange.new(-15, 15)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.55, 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.58),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
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
	local groundFields: { [number]: GroundField } = {}
	local draftZones: { HazardService.Zone } = {}
	local waterRegions: { HazardService.WaterRegion } = {}
	local waterByRoom: { [number]: Types.HazardPlacement } = {}
	for _, hazard in plan.hazards do
		if hazard.hazardId == "Water" then
			waterByRoom[hazard.roomIndex] = hazard
		end
	end

	for index, room in plan.rooms do
		local center = Vector3.new(room.gridX * g.cellSize, floorY, room.gridZ * g.cellSize)
		roomCenters[index] = center
		local isBasin = index == plan.basinRoomIndex
		local isEntry = index == plan.entryRoomIndex
		local waterPlacement = waterByRoom[index]
		-- Per-room ceiling variance; never below the doorway (plus lintel clearance).
		local ceilingHeight =
			math.max(g.wallHeight + rng:NextNumber(-d.ceilingJitter, d.ceilingJitter), g.doorwayMaxHeight + 1)

		local doorwaySet: { [Types.Direction]: boolean } = {}
		for _, direction in room.doorways do
			doorwaySet[direction] = true
		end

		-- Off-centre fixtures must stay level under the undulating floor. The room centre is always
		-- flat; mark extra pads for the descent pad and brazier so they never sit on a slope.
		local flatSpots: { FlatSpot } = {}
		if index == plan.basinRoomIndex then
			table.insert(flatSpots, { x = g.cellSize / 4, z = g.cellSize / 4, r = g.cellSize / 8 + 2 })
		end
		if index == plan.brazierRoomIndex then
			table.insert(flatSpots, { x = -g.cellSize / 4, z = -g.cellSize / 4, r = 5 })
		end
		local field = makeGroundField(room, plan.depth, doorwaySet, flatSpots)
		if waterPlacement ~= nil then
			field.amp = 0 -- pools own their recessed bed; leave the surrounding shelves level.
		end
		groundFields[index] = field

		-- Floor and ceiling enclose the room so darkness is real. The flat slab is the sealed cave
		-- bottom; the undulating tiles ride on top of it, giving the ground real height and slope.
		if waterPlacement ~= nil then
			buildPoolFloor(center, waterPlacement, FLOOR_COLOR, model)
		else
			newPart(
				Vector3.new(g.cellSize, g.wallThickness, g.cellSize),
				center - Vector3.new(0, g.wallThickness / 2, 0),
				if isBasin then BASIN_COLOR else FLOOR_COLOR,
				model
			)
			buildUndulatingFloor(center, field, if isBasin then BASIN_COLOR else FLOOR_COLOR, model)
		end
		newPart(
			Vector3.new(g.cellSize, g.wallThickness, g.cellSize),
			center + Vector3.new(0, ceilingHeight + g.wallThickness / 2, 0),
			WALL_COLOR,
			model
		)
		for direction in DOOR_NORMALS do
			local doorwayWidth, doorwayHeight = doorwayDimensions(room.gridX, room.gridZ, direction, plan.depth)
			buildWall(
				center,
				direction,
				doorwaySet[direction] == true,
				model,
				ceilingHeight,
				doorwayWidth,
				doorwayHeight,
				rng
			)
		end

		-- Every room gets a broken roof silhouette. Layered tapering formations hang far enough
		-- into the room to catch candlelight; broad caps hide the remaining ceiling-slab read.
		for _ = 1, d.ceilingBouldersPerRoom do
			local width = rng:NextNumber(5, 11)
			local cap = newJaggedShard(
				"CeilingRock",
				Vector3.new(width, rng:NextNumber(1.5, 3.5), width * rng:NextNumber(0.65, 1.25)),
				center
					+ Vector3.new(
						rng:NextNumber(-g.cellSize * 0.36, g.cellSize * 0.36),
						ceilingHeight - rng:NextNumber(0.2, 1.1),
						rng:NextNumber(-g.cellSize * 0.36, g.cellSize * 0.36)
					),
				ROCK_COLOR,
				model,
				rng
			)
			cap.CanCollide = false
			cap.CanQuery = false
		end
		for _ = 1, d.ceilingFormationsPerRoom do
			local angle = rng:NextNumber(0, 2 * math.pi)
			local radius = rng:NextNumber(g.cellSize * 0.13, g.cellSize * 0.4)
			buildCeilingFormation(
				center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius),
				ceilingHeight,
				math.min(rng:NextNumber(d.ceilingFormationMinLength, d.ceilingFormationMaxLength), ceilingHeight * 0.62),
				rng:NextNumber(d.ceilingFormationMinWidth, d.ceilingFormationMaxWidth),
				model,
				rng
			)
		end

		-- Boulders: collidable scatter in ordinary rooms only (entry stays a safe spawn).
		if not isBasin and not isEntry and waterPlacement == nil then
			for _ = 1, d.bouldersPerRoom do
				local base = rng:NextNumber(d.boulderMinSize, d.boulderMaxSize)
				local size = Vector3.new(base, base * rng:NextNumber(0.6, 1.1), base * rng:NextNumber(0.7, 1.3))
				local ox = rng:NextNumber(-1, 1) * g.cellSize * 0.32
				local oz = rng:NextNumber(-1, 1) * g.cellSize * 0.32
				local offset = Vector3.new(ox, size.Y / 2 + groundOffset(field, ox, oz), oz)
				local boulder = newJaggedShard("Boulder", size, center + offset, ROCK_COLOR, model, rng)
				local secondShard = newJaggedShard(
					"Boulder",
					size * rng:NextNumber(0.5, 0.72),
					center + offset + Vector3.new(0, size.Y * 0.2, 0),
					ROCK_COLOR,
					model,
					rng
				)
				secondShard.CanCollide = false
				secondShard.CanQuery = false
				boulder.CanCollide = true
			end
			-- Tall perimeter formations create strong height silhouettes without occupying the
			-- room's central travel lanes. Alternating columns hang from the ceiling or rise from
			-- the floor; ceiling-hung pieces are collision-neutral.
			for columnIndex = 1, d.rockColumnsPerRoom do
				local width = rng:NextNumber(d.rockColumnMinWidth, d.rockColumnMaxWidth)
				local columnHeight =
					math.min(rng:NextNumber(d.rockColumnMinHeight, d.rockColumnMaxHeight), ceilingHeight * 0.7)
				local angle = rng:NextNumber(0, 2 * math.pi)
				local radius = rng:NextNumber(g.cellSize * 0.31, g.cellSize * 0.4)
				local hangsFromCeiling = columnIndex % 2 == 0
				local cx, cz = math.cos(angle) * radius, math.sin(angle) * radius
				local y = if hangsFromCeiling
					then ceilingHeight - columnHeight / 2
					else columnHeight / 2 + groundOffset(field, cx, cz)
				local column = newJaggedShard(
					if hangsFromCeiling then "Stalactite" else "Stalagmite",
					Vector3.new(width, columnHeight, width * rng:NextNumber(0.75, 1.25)),
					center + Vector3.new(cx, y, cz),
					ROCK_COLOR,
					model,
					rng
				)
				column.CanCollide = not hangsFromCeiling
				column.CanQuery = not hangsFromCeiling
			end
		end
	end

	-- Planned ground swells are angular plateaus with four shallow ramps. They remain walkable,
	-- avoid the repeated ball silhouette, and change both Humanoid and threat ground following.
	for _, patch in plan.groundPatches do
		local field = groundFields[patch.roomIndex]
		local lift = if field ~= nil then groundOffset(field, patch.localOffset.X, patch.localOffset.Z) else 0
		buildGroundRise(
			roomCenters[patch.roomIndex] + patch.localOffset + Vector3.new(0, lift, 0),
			patch.size,
			model,
			rng
		)
	end

	-- Hazards from the plan: drafts are avoidable interior pockets; water occupies recessed pools.
	for _, hazard in plan.hazards do
		local center = roomCenters[hazard.roomIndex]
		if hazard.hazardId == "Draft" then
			local size = hazard.size :: Vector3
			local localOffset = hazard.localOffset :: Vector3
			local zone: HazardService.Zone = {
				center = center + localOffset + Vector3.new(0, size.Y / 2, 0),
				size = size,
			}
			table.insert(draftZones, zone)
			local visualConfig = Config.Hazards.draftVisual
			if visualConfig.enabled then
				local haze = newPart(zone.size, zone.center, visualConfig.hazeColor, model, Enum.Material.ForceField)
				haze.Name = "DraftHaze"
				haze.Transparency = visualConfig.hazeTransparency
				haze.CanCollide = false
				haze.CanQuery = false
				haze:SetAttribute("WickBaseTransparency", visualConfig.hazeTransparency)
				haze:SetAttribute("WickAnimationPhase", rng:NextNumber(0, math.pi * 2))
				CollectionService:AddTag(haze, DRAFT_VISUAL_TAG)

				local light = Instance.new("PointLight")
				light.Name = "DraftGlow"
				light.Color = visualConfig.markerColor
				light.Brightness = visualConfig.lightBrightness
				light.Range = visualConfig.lightRange
				light.Shadows = false
				light.Parent = haze

				local along = if size.X >= size.Z then Vector3.xAxis else Vector3.zAxis
				local across = if size.X >= size.Z then Vector3.zAxis else Vector3.xAxis
				local length = math.max(size.X, size.Z)
				addWindParticles(haze, along)
				for _, side in { -1, 1 } do
					local marker = newPart(
						along * visualConfig.markerWidth + across * visualConfig.markerDepth + Vector3.new(0, size.Y, 0),
						zone.center + along * side * (length / 2 - visualConfig.markerWidth / 2),
						visualConfig.markerColor,
						model,
						Enum.Material.Neon
					)
					marker.Name = "DraftEdge"
					marker.Transparency = visualConfig.markerTransparency
					marker.CanCollide = false
					marker.CanQuery = false
				end
			end
		elseif hazard.hazardId == "Water" then
			local depth = hazard.waterDepth :: number
			local offset = hazard.localOffset :: Vector3
			local size = hazard.size :: Vector3
			local pool = Config.Hazards.waterPool
			local surfaceY = center.Y + pool.surfaceOffset
			local surface = newPart(
				Vector3.new(size.X, pool.visualThickness, size.Z),
				center + offset + Vector3.new(0, pool.surfaceOffset - pool.visualThickness / 2, 0),
				WATER_COLOR,
				model,
				Enum.Material.Glass
			)
			surface.Name = "WaterSurface"
			surface.Transparency = 0.38
			surface.Reflectance = 0.08
			surface.CanCollide = false
			surface.CanQuery = false
			surface:SetAttribute("WickBaseY", surface.Position.Y)
			surface:SetAttribute("WickBaseTransparency", surface.Transparency)
			surface:SetAttribute("WickAnimationPhase", rng:NextNumber(0, math.pi * 2))
			CollectionService:AddTag(surface, WATER_TAG)
			addWaterSurfaceGui(surface)

			-- Loose collision-neutral stones break the rectangular cutout into an irregular pool.
			for rockIndex = 1, pool.rimRocks do
				local angle = (rockIndex / pool.rimRocks) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
				local rockSize = rng:NextNumber(pool.rimRockMinSize, pool.rimRockMaxSize)
				local rim = newJaggedShard(
					"PoolRimRock",
					Vector3.new(rockSize * 1.4, rockSize, rockSize),
					center
						+ offset
						+ Vector3.new(math.cos(angle) * size.X * 0.52, rockSize * 0.15, math.sin(angle) * size.Z * 0.52),
					ROCK_COLOR,
					model,
					rng
				)
				rim.CanCollide = false
				rim.CanQuery = false
			end
			table.insert(waterRegions, {
				surfaceY = surfaceY,
				center = center + offset,
				size = Vector3.new(size.X, depth + pool.surfaceOffset, size.Z),
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

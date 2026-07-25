--!strict
-- FloorPlan -> cave geometry from primitives. Decides nothing mechanical: room positions,
-- doorways, hazards and special rooms come from the plan; dimensions from Config/Floors.
-- The ONLY randomness here is cosmetic dressing (relief, boulders, ceiling variance), seeded
-- per depth so rebuilds look identical — gameplay math never reads any of it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local DoorwayGeometry = require(ReplicatedStorage.Shared.Logic.DoorwayGeometry)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local RoofGeometry = require(ReplicatedStorage.Shared.Logic.RoofGeometry)
local DripstoneVisualProtocol = require(ReplicatedStorage.Shared.DripstoneVisualProtocol)
local CaveKit = require(ReplicatedStorage.Shared.NewModelsAndObjects.CaveKit)
local UnstableDripstone = require(ReplicatedStorage.Shared.NewModelsAndObjects.UnstableDripstone)
local HazardService = require(script.Parent.HazardService)

local FloorBuilder = {}

export type DripstoneRuntime = {
	model: Model,
	depth: number,
	impactPosition: Vector3,
	fallDistance: number,
	variantId: string,
}

-- Exact paired fields used to carve one room's playable Terrain. Ceiling-bound gameplay objects
-- consume this runtime data rather than guessing from the room's nominal height or raycasting
-- against decorative props.
export type RoomSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
	roofField: RoofGeometry.Field,
}

type AmbushReservation = {
	offset: Vector3,
	clearance: number,
}

export type FloorRuntime = {
	model: Model,
	depth: number,
	entryPosition: Vector3,
	basinPosition: Vector3,
	brazierPosition: Vector3,
	descentRegion: HazardService.Zone,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomSurface },
	draftZones: { HazardService.Zone },
	waterRegions: { HazardService.WaterRegion },
	dripstones: { DripstoneRuntime },
}

-- Cold, dark slate — the cave reads as wet stone, not warm sandstone. Floor, walls, and rock all
-- sit in the same slate family; the terrain tint (see TERRAIN_COLOR) is matched to the walls.
local WALL_COLOR = Color3.fromRGB(52, 56, 66)
local ROCK_COLOR = Color3.fromRGB(62, 66, 78)
local WATER_COLOR = Color3.fromRGB(42, 66, 92)
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
-- centre fixtures), the doorway lanes, and a few marked fixture pads. Planned ground rises become
-- smooth mounds (see swells). All slopes are gentle so the jumpless Humanoid walks them freely and
-- the AI's downward ground probe follows them without snagging. The surface is realised as smooth
-- Roblox Terrain, so the slopes are genuinely continuous rather than faceted parts.
type FlatSpot = GroundGeometry.FlatSpot
type Swell = GroundGeometry.Swell
-- A smoothly carved bowl below the floor; water settles into it (see the room loop).
type Pool = GroundGeometry.Pool
-- Planning and construction share the exact floor field through GroundGeometry.
type GroundField = GroundGeometry.Field

local TERRAIN_MATERIAL = Enum.Material.Slate
-- Matched to the wall slate so floor and walls read as one stone (terrain is lit brighter, so it is
-- pitched a touch darker/cooler to land on the same tone once the candle hits it).
local TERRAIN_COLOR = Color3.fromRGB(48, 52, 62)
local terrainColorApplied = false

local function makeGroundField(
	room: Types.RoomPlacement,
	depth: number,
	openFootprint: boolean,
	flatSpots: { FlatSpot },
	swells: { Swell },
	pools: { Pool }
): GroundField
	return GroundGeometry.fieldFor(room, depth, openFootprint, flatSpots, swells, pools)
end

-- Floor height (signed, relative to the room's base level) at a room-local point. Level on the
-- plaza, the doorway lanes, and fixture pads; rolling rock elsewhere that rises toward the walls;
-- planned mounds domed on top; carved bowls where water pools. Continuous — that keeps Terrain smooth.
local function groundOffset(field: GroundField, localX: number, localZ: number): number
	return GroundGeometry.offset(field, localX, localZ)
end

-- Exact visible roof underside at a room-local sample. At the boundary, the nominal ceiling must
-- meet the wall top with no seam; within the chamber the roof may lift just enough to preserve
-- minimum headroom above an unusually high floor swell.
local function roofUndersideY(
	center: Vector3,
	groundField: GroundField,
	roofField: RoofGeometry.Field,
	ceilingHeight: number,
	localX: number,
	localZ: number
): number
	local groundHeight = groundOffset(groundField, localX, localZ)
	return center.Y + RoofGeometry.undersideHeight(ceilingHeight, roofField, groundHeight, localX, localZ)
end

-- Carve floor and inverted roof in one voxel pass. Writing a second overlapping Terrain region
-- would let its Air cells erase the floor, so the two solid fields are unioned per voxel.
local function fillRoomTerrain(
	center: Vector3,
	field: GroundField,
	roofField: RoofGeometry.Field,
	ceilingHeight: number
)
	local terrain = workspace.Terrain
	if not terrainColorApplied then
		terrain:SetMaterialColor(TERRAIN_MATERIAL, TERRAIN_COLOR)
		terrainColorApplied = true
	end

	local half = Config.Floors.geometry.cellSize / 2
	local floorY = center.Y
	-- Solid rock extends above the irregular underside, sealing light without a flat ceiling slab.
	local topY = floorY + ceilingHeight + Config.Floors.roof.rockThickness
	local region = Region3.new(
		Vector3.new(center.X - half, floorY - 18, center.Z - half),
		Vector3.new(center.X + half, topY, center.Z + half)
	):ExpandToGrid(4)
	local size = region.Size
	local nx = math.floor(size.X / 4 + 0.5)
	local ny = math.floor(size.Y / 4 + 0.5)
	local nz = math.floor(size.Z / 4 + 0.5)
	local origin = region.CFrame.Position - size / 2

	local materials: { { { Enum.Material } } } = table.create(nx)
	local occupancies: { { { number } } } = table.create(nx)
	for xi = 1, nx do
		local worldX = origin.X + (xi - 0.5) * 4
		local matY: { { Enum.Material } } = table.create(ny)
		local occY: { { number } } = table.create(ny)
		for yi = 1, ny do
			local voxelBottom = origin.Y + (yi - 1) * 4
			local matZ: { Enum.Material } = table.create(nz)
			local occZ: { number } = table.create(nz)
			for zi = 1, nz do
				local worldZ = origin.Z + (zi - 0.5) * 4
				local localX, localZ = worldX - center.X, worldZ - center.Z
				local groundHeight = groundOffset(field, localX, localZ)
				local floorSurfaceY = floorY + groundHeight
				local roofSurfaceY = floorY
					+ RoofGeometry.undersideHeight(ceilingHeight, roofField, groundHeight, localX, localZ)
				local floorOccupancy = math.clamp((floorSurfaceY - voxelBottom) / 4, 0, 1)
				local voxelTop = voxelBottom + 4
				local roofOccupancy = math.clamp((voxelTop - roofSurfaceY) / 4, 0, 1)
				local occ = math.max(floorOccupancy, roofOccupancy)
				matZ[zi] = if occ > 0 then TERRAIN_MATERIAL else Enum.Material.Air
				occZ[zi] = occ
			end
			matY[yi] = matZ
			occY[yi] = occZ
		end
		materials[xi] = matY
		occupancies[xi] = occY
	end
	terrain:WriteVoxels(region, 4, materials, occupancies)
end

-- One wall of a room, split around its (offset) doorway if that side has one. Doorless walls get
-- cosmetic rock-relief strips (collision-neutral) so surfaces read as cave, not corridor.
local function buildWall(
	roomCenter: Vector3,
	direction: Types.Direction,
	hasDoorway: boolean,
	parent: Instance,
	height: number,
	doorwayWidth: number,
	doorwayHeight: number,
	doorwayOffset: number,
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

	local gapOffset, gapHalfWidth = 0, 0
	if not hasDoorway then
		slab(g.cellSize, 0, height, 0)
	else
		gapOffset, gapHalfWidth = doorwayOffset, doorwayWidth / 2
		-- Gap spans [offset - w/2, offset + w/2] along the wall. Two unequal side slabs.
		local gapLeft = doorwayOffset - doorwayWidth / 2
		local gapRight = doorwayOffset + doorwayWidth / 2
		local leftLength = gapLeft - (-g.cellSize / 2)
		local rightLength = g.cellSize / 2 - gapRight
		if leftLength > 0 then
			slab(leftLength, (-g.cellSize / 2 + gapLeft) / 2, height, 0)
		end
		if rightLength > 0 then
			slab(rightLength, (gapRight + g.cellSize / 2) / 2, height, 0)
		end

		-- Arched top instead of a flat lintel. The opening rises to a rounded peak on an ELLIPTICAL
		-- springing (sqrt profile) so it reads as a circular cave mouth rather than the old flat-topped
		-- parabolic hood, and it is cut from many thin columns so the curve is smooth, not stepped.
		--
		-- Reachability guarantee: archTop is always >= doorwayHeight, so this collidable rock only ever
		-- fills ABOVE the opening — it is overhead structure, never a wall in the lane. The ground field
		-- (GroundGeometry) independently keeps that lane flat out to the gap, so the player can always
		-- walk up to and through the arch; nothing here can wall it off.
		local archRise = math.max(0, math.min(doorwayHeight * 0.6, height - doorwayHeight - 0.5))
		local halfSpan = doorwayWidth / 2
		local function archTopAt(xc: number): number
			local t = math.clamp((xc - doorwayOffset) / halfSpan, -1, 1)
			return doorwayHeight + archRise * math.sqrt(math.max(0, 1 - t * t))
		end
		-- One column per ~2.2 studs keeps the step size (and so the faceting) constant whether the
		-- opening is a tight crevice or a room-wide breach.
		local archColumns = math.clamp(math.round(doorwayWidth / 2.2), 10, 30)
		local colWidth = doorwayWidth / archColumns
		for i = 0, archColumns - 1 do
			local xc = gapLeft + (i + 0.5) * colWidth
			local archTop = archTopAt(xc)
			local slabHeight = height - archTop
			if slabHeight > 0 then
				slab(colWidth + 0.2, xc, slabHeight, archTop / 2)
			end
		end

		-- Break the clean cut edge with shallow rock chips aligned to the arch curve, in the same
		-- eroded-slate style as the ground and walls. Collision-neutral, with each chip mostly embedded.
		-- Its visible lip stays close to the continuous opening curve.
		local averageFacetLength = (d.caveMouthArchFacetMinLength + d.caveMouthArchFacetMaxLength) / 2
		local archFacets = math.max(d.caveMouthCeilingRocks, math.round(doorwayWidth / averageFacetLength))
		for i = 1, archFacets do
			local tt = ((i - 0.5) / archFacets) * 2 - 1 -- -1..1 across the span
			local xc = doorwayOffset + tt * halfSpan
			local archTop = archTopAt(xc)
			local curveDenominator = math.max(math.sqrt(math.max(0, 1 - tt * tt)), 0.08)
			local slope = -(archRise * tt) / (halfSpan * curveDenominator)
			local tangent = (along + Vector3.yAxis * slope).Unit
			local facetUp = normal:Cross(tangent).Unit
			local facetLength = rng:NextNumber(d.caveMouthArchFacetMinLength, d.caveMouthArchFacetMaxLength)
			local facetThickness = d.caveMouthArchFacetThickness
			local verticalHalfExtent = math.abs(tangent.Y) * facetLength / 2 + math.abs(facetUp.Y) * facetThickness / 2
			local facet = Instance.new("Part")
			facet.Name = "CaveMouthArchFacet"
			facet.Size = Vector3.new(facetLength, facetThickness, d.caveMouthArchFacetDepth)
			facet.CFrame = CFrame.fromMatrix(
				roomCenter
					+ normal * (g.cellSize / 2 - g.wallThickness)
					+ along * xc
					+ Vector3.new(0, archTop + verticalHalfExtent * d.caveMouthArchFacetEmbed, 0),
				tangent,
				facetUp,
				normal
			)
			facet.Color = ROCK_COLOR
			facet.Material = Enum.Material.Slate
			facet.Anchored = true
			facet.CanCollide = false
			facet.CanQuery = false
			facet.CanTouch = false
			facet.CastShadow = false
			facet.Parent = parent
		end

		-- Collision-neutral rock clusters break the cut edges so each connection reads as its own
		-- eroded cave throat while preserving the guaranteed clear lane through the gap.
		for _, side in { -1, 1 } do
			for _ = 1, d.caveMouthRocksPerSide do
				local base = rng:NextNumber(d.caveMouthRockMinSize, d.caveMouthRockMaxSize)
				local rock = newJaggedShard(
					"CaveMouthRock",
					Vector3.new(base * rng:NextNumber(0.7, 1.2), base * rng:NextNumber(0.8, 1.5), base),
					roomCenter
						+ normal * (g.cellSize / 2 - g.wallThickness - rng:NextNumber(0.2, base * 0.7))
						+ along * (doorwayOffset + side * rng:NextNumber(
							doorwayWidth / 2 + base * 0.1,
							doorwayWidth / 2 + base * 0.6
						))
						+ Vector3.new(0, rng:NextNumber(base / 2, doorwayHeight - base / 2), 0),
					ROCK_COLOR,
					parent,
					rng
				)
				rock.CanCollide = false
				rock.CanQuery = false
				rock.CastShadow = false
			end
		end
	end

	-- Rough EVERY wall with jagged rock so surfaces read as broken cave, not a flat slab. Clusters
	-- avoid the doorway opening. Collision-neutral, so they change nothing mechanically.
	for _ = 1, d.wallRockCount do
		local size = rng:NextNumber(d.wallRockMinSize, d.wallRockMaxSize)
		local alongPos = rng:NextNumber(-1, 1) * (g.cellSize / 2 - size)
		if gapHalfWidth > 0 and math.abs(alongPos - gapOffset) < gapHalfWidth + size * 0.6 then
			continue
		end
		local protrude = rng:NextNumber(0.5, d.wallRockMaxSize * 0.55)
		local yPos = rng:NextNumber(size * 0.5, math.max(size * 0.5, height - size * 0.5))
		local shard = newJaggedShard(
			"WallRock",
			Vector3.new(size * rng:NextNumber(0.7, 1.4), size * rng:NextNumber(0.9, 1.8), protrude),
			roomCenter
				+ normal * (g.cellSize / 2 - g.wallThickness - protrude / 2)
				+ along * alongPos
				+ Vector3.new(0, yPos, 0),
			ROCK_COLOR,
			parent,
			rng
		)
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CastShadow = false
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
	CaveKit.configure({
		palette = d.formationPalette,
		dampTint = d.formationDampTint,
		materials = d.formationMaterials,
		wetMaterial = d.formationWetMaterial,
		wetReflectance = d.formationWetReflectance,
	})
	local floorY = -(plan.depth - 1) * g.floorGap
	-- Cosmetic-only rng, seeded by depth: identical dressing on rebuild, zero gameplay reads.
	local rng = Random.new(plan.depth * 7919 + 101)

	local model = Instance.new("Model")
	model.Name = "Floor_" .. plan.depth

	local roomCenters: { Vector3 } = {}
	local roomSurfaces: { [number]: RoomSurface } = {}
	local groundFields: { [number]: GroundField } = {}
	local roofFields: { [number]: RoofGeometry.Field } = {}
	local draftZones: { HazardService.Zone } = {}
	local waterRegions: { HazardService.WaterRegion } = {}
	local dripstoneRuntimes: { DripstoneRuntime } = {}
	local waterByRoom: { [number]: Types.HazardPlacement } = {}
	local dripstonesByRoom: { [number]: { Types.DripstonePlacement } } = {}
	local ambushesByRoom: { [number]: { AmbushReservation } } = {}
	for _, hazard in plan.hazards do
		if hazard.hazardId == "Water" then
			waterByRoom[hazard.roomIndex] = hazard
		end
	end
	for _, placement in plan.dripstones do
		local list = dripstonesByRoom[placement.roomIndex]
		if list == nil then
			list = {}
			dripstonesByRoom[placement.roomIndex] = list
		end
		table.insert(list, placement)
	end
	for _, spawn in plan.threatSpawns do
		local definition = Config.Threats.definitions[spawn.threatId]
		local ambush = if definition ~= nil then definition.ambush else nil
		if ambush == nil then
			continue
		end
		local list = ambushesByRoom[spawn.roomIndex]
		if list == nil then
			list = {}
			ambushesByRoom[spawn.roomIndex] = list
		end
		table.insert(list, {
			offset = spawn.offset,
			-- The fly may patrol, dive, and retreat anywhere in its full territory. Reserve that
			-- gameplay disc plus a small visual/body margin, not just its initial ceiling point.
			clearance = math.max(0, ambush.territoryRadius + ambush.roofDecorationClearance),
		})
	end

	-- Planned ground rises become smooth Terrain mounds baked into each room's height field, instead
	-- of the old stacked part shelves. Grouped per room so the field can dome them naturally.
	local swellsByRoom: { [number]: { Swell } } = {}
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

	for index, room in plan.rooms do
		local center = Vector3.new(room.gridX * g.cellSize, floorY, room.gridZ * g.cellSize)
		roomCenters[index] = center
		local isBasin = index == plan.basinRoomIndex
		local isEntry = index == plan.entryRoomIndex
		local waterPlacement = waterByRoom[index]
		-- Planned per-room ceiling: wide variation (tight crevice to tall cavern) that also decides
		-- which threats the planner favours here. Always above the doorway (config guarantees it).
		local ceilingHeight = room.ceilingHeight

		-- Each doorway rolls a deterministic width/height/lateral-offset shared with the neighbour, so
		-- openings vary in size and position while the terrain lane lines up exactly with the gap.
		local doorProfiles: { [Types.Direction]: { width: number, height: number, offset: number } } = {}
		for _, direction in room.doorways do
			local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, plan.depth)
			doorProfiles[direction] = profile
		end

		-- Off-centre fixtures must stay level under the rocky floor. The room centre is always flat;
		-- mark extra pads for the descent beacon and brazier so they never sit on a slope.
		local flatSpots: { FlatSpot } = {}
		if index == plan.basinRoomIndex then
			table.insert(flatSpots, { x = g.cellSize / 4, z = g.cellSize / 4, r = g.cellSize / 8 + 2 })
		end
		if index == plan.brazierRoomIndex then
			table.insert(flatSpots, { x = -g.cellSize / 4, z = -g.cellSize / 4, r = 6 })
		end

		-- Flooded rooms carve a smooth bowl into the rocky floor; water settles into that low point.
		local pools: { Pool } = {}
		local waterRadius = 0
		local waterSurfaceY = floorY
		if waterPlacement ~= nil then
			local offset = waterPlacement.localOffset :: Vector3
			local poolSize = waterPlacement.size :: Vector3
			waterRadius = (poolSize.X + poolSize.Z) / 4
			waterSurfaceY = floorY - Config.Hazards.waterPool.surfaceOffset
			table.insert(pools, {
				x = offset.X,
				z = offset.Z,
				radius = waterRadius,
				depth = (waterPlacement.waterDepth :: number) + Config.Hazards.waterPool.poolBedDepthPad,
			})
		end

		local openFootprint = isBasin or isEntry or index == plan.brazierRoomIndex
		local field = makeGroundField(room, plan.depth, openFootprint, flatSpots, swellsByRoom[index] or {}, pools)
		groundFields[index] = field
		local roofField = RoofGeometry.fieldFor(room, plan.depth)
		roofFields[index] = roofField
		roomSurfaces[index] = {
			center = center,
			ceilingHeight = ceilingHeight,
			groundField = field,
			roofField = roofField,
		}

		-- Every room gets continuous rocky floor banks and a separately seeded, inverted rocky roof.
		-- The fields share one write so neither can erase the other.
		fillRoomTerrain(center, field, roofField, ceilingHeight)

		-- The water plane sits just under the surrounding floor. The Terrain bowl clips its edges, so
		-- a rectangular plane reads as a natural pool; the Y-comparison hazard only bites once a candle
		-- actually descends below the surface.
		if waterPlacement ~= nil then
			local poolCenter = center + (waterPlacement.localOffset :: Vector3)
			local surface = newPart(
				Vector3.new(waterRadius * 2, Config.Hazards.waterPool.visualThickness, waterRadius * 2),
				Vector3.new(poolCenter.X, waterSurfaceY, poolCenter.Z),
				WATER_COLOR,
				model,
				Enum.Material.Glass
			)
			surface.Name = "WaterSurface"
			surface.Transparency = 0.3
			surface.Reflectance = 0.08
			surface.CanCollide = false
			surface.CanQuery = false
			surface:SetAttribute("WickBaseY", surface.Position.Y)
			surface:SetAttribute("WickBaseTransparency", surface.Transparency)
			surface:SetAttribute("WickAnimationPhase", rng:NextNumber(0, math.pi * 2))
			CollectionService:AddTag(surface, WATER_TAG)
			addWaterSurfaceGui(surface)
			table.insert(waterRegions, {
				surfaceY = waterSurfaceY,
				center = poolCenter,
				size = Vector3.new(waterRadius * 2, 2, waterRadius * 2),
			})
		end

		for direction in DOOR_NORMALS do
			local profile = doorProfiles[direction]
			if profile ~= nil then
				buildWall(
					center,
					direction,
					true,
					model,
					ceilingHeight,
					profile.width,
					profile.height,
					profile.offset,
					rng
				)
			else
				buildWall(center, direction, false, model, ceilingHeight, 0, 0, 0, rng)
			end
		end

		-- Every room gets a deterministic CaveKit roof silhouette. These are presentation-only and
		-- cannot obstruct movement or AI queries.
		local roomDripstones = dripstonesByRoom[index] or {}
		local roomAmbushes = ambushesByRoom[index] or {}
		local function clearOfUnstable(x: number, z: number, decorationRadius: number): boolean
			for _, placement in roomDripstones do
				local variant = DripstoneRules.variantById(placement.variantId)
				local dx, dz = placement.localOffset.X - x, placement.localOffset.Z - z
				local triggerRadius = if variant ~= nil then variant.triggerRadius else 0
				local clearance = triggerRadius
					+ decorationRadius
					+ Config.Hazards.unstableDripstone.decorationEgressPadding
				if dx * dx + dz * dz <= clearance * clearance then
					return false
				end
			end
			return true
		end
		local function clearOfAmbush(x: number, z: number, decorationRadius: number): boolean
			for _, reservation in roomAmbushes do
				local dx, dz = reservation.offset.X - x, reservation.offset.Z - z
				local clearance = reservation.clearance + decorationRadius
				if dx * dx + dz * dz <= clearance * clearance then
					return false
				end
			end
			return true
		end
		local function clearOfCeilingReservations(x: number, z: number, decorationRadius: number): boolean
			return clearOfUnstable(x, z, decorationRadius) and clearOfAmbush(x, z, decorationRadius)
		end

		-- A sparse layer of broad, shallow facets breaks up the large smooth Terrain spans at candle
		-- range. These parts are purely visual: gameplay roof queries still sample RoofGeometry, and
		-- ceiling enemy/hazard reservations remain empty. Most of every piece is buried in Terrain so
		-- the layer reads as fractured roof planes rather than hanging props.
		local ceilingFacetClusters = 0
		local ceilingFacetHalfRange = g.cellSize / 2 - d.ceilingFacetEdgeInset - d.ceilingFacetMaxSize / 2
		for _ = 1, d.ceilingFacetPlacementAttempts do
			if ceilingFacetClusters >= d.ceilingFacetClustersPerRoom then
				break
			end
			local x = rng:NextNumber(-ceilingFacetHalfRange, ceilingFacetHalfRange)
			local z = rng:NextNumber(-ceilingFacetHalfRange, ceilingFacetHalfRange)
			local decorationRadius = d.ceilingFacetMaxSize / 2 + d.ceilingFacetSpread
			if not clearOfCeilingReservations(x, z, decorationRadius) then
				continue
			end

			local roofY = roofUndersideY(center, field, roofField, ceilingHeight, x, z)
			local sample = d.ceilingFacetSlopeSample
			local xSampleY = roofUndersideY(center, field, roofField, ceilingHeight, x + sample, z)
			local zSampleY = roofUndersideY(center, field, roofField, ceilingHeight, x, z + sample)
			local facetRight = Vector3.new(sample, xSampleY - roofY, 0).Unit
			local provisionalBack = Vector3.new(0, zSampleY - roofY, sample).Unit
			local facetUp = provisionalBack:Cross(facetRight).Unit
			local facetBack = facetRight:Cross(facetUp).Unit
			local surfaceFrame =
				CFrame.fromMatrix(Vector3.new(center.X + x, roofY, center.Z + z), facetRight, facetUp, facetBack)

			for pieceIndex = 1, d.ceilingFacetPiecesPerCluster do
				local size = rng:NextNumber(d.ceilingFacetMinSize, d.ceilingFacetMaxSize)
				local thickness = rng:NextNumber(d.ceilingFacetMinThickness, d.ceilingFacetMaxThickness)
				local yaw = rng:NextNumber(0, math.pi * 2)
				local spread = if pieceIndex == 1 then 0 else rng:NextNumber(0, d.ceilingFacetSpread)
				local spreadAngle = rng:NextNumber(0, math.pi * 2)
				local facet = if pieceIndex % 2 == 0 then Instance.new("WedgePart") else Instance.new("Part")
				facet.Name = "CeilingFacet"
				facet.Size = Vector3.new(size, thickness, size * rng:NextNumber(0.55, 1))
				facet.CFrame = surfaceFrame
					* CFrame.new(
						math.cos(spreadAngle) * spread,
						thickness * (d.ceilingFacetEmbed - 0.5),
						math.sin(spreadAngle) * spread
					)
					* CFrame.Angles(0, yaw, 0)
				facet.Color = d.formationPalette[rng:NextInteger(1, #d.formationPalette)]
				facet.Material = d.formationMaterials[rng:NextInteger(1, #d.formationMaterials)]
				facet.Anchored = true
				facet.CanCollide = false
				facet.CanQuery = false
				facet.CanTouch = false
				facet.CastShadow = false
				facet.Parent = model
			end
			ceilingFacetClusters += 1
		end

		local strawClusters = 0
		for _ = 1, d.ceilingBouldersPerRoom * 5 do
			if strawClusters >= d.ceilingBouldersPerRoom then
				break
			end
			local x = rng:NextNumber(-g.cellSize * 0.34, g.cellSize * 0.34)
			local z = rng:NextNumber(-g.cellSize * 0.34, g.cellSize * 0.34)
			if not clearOfCeilingReservations(x, z, d.ceilingStrawSpread) then
				continue
			end
			local roofY = roofUndersideY(center, field, roofField, ceilingHeight, x, z)
			local localClearance = roofY - (center.Y + groundOffset(field, x, z))
			local requestedHeight = rng:NextNumber(d.ceilingFormationMinLength, d.ceilingFormationMaxLength * 0.65)
			local strawHeight = math.min(
				requestedHeight,
				(localClearance - d.ceilingFormationGroundGap) / d.ceilingStrawLengthMultiplier
			)
			if strawHeight < 0.5 then
				continue
			end
			CaveKit.sodaStraws(model, CFrame.new(center.X + x, roofY, center.Z + z), d.ceilingStrawsPerCluster, {
				height = strawHeight,
				radius = d.ceilingStrawSpread,
				seed = rng:NextInteger(1, 1_000_000),
				collide = false,
			})
			strawClusters += 1
		end
		local harmlessFormations = 0
		for _ = 1, d.ceilingFormationsPerRoom * 5 do
			if harmlessFormations >= d.ceilingFormationsPerRoom then
				break
			end
			local angle = rng:NextNumber(0, 2 * math.pi)
			local radius = rng:NextNumber(g.cellSize * 0.13, g.cellSize * 0.4)
			local x, z = math.cos(angle) * radius, math.sin(angle) * radius
			local formationHeight =
				math.min(rng:NextNumber(d.ceilingFormationMinLength, d.ceilingFormationMaxLength), ceilingHeight * 0.62)
			local formationRadius = rng:NextNumber(d.ceilingFormationMinWidth, d.ceilingFormationMaxWidth) / 2
			if not clearOfCeilingReservations(x, z, formationRadius) then
				continue
			end
			local roofY = roofUndersideY(center, field, roofField, ceilingHeight, x, z)
			local localClearance = roofY - (center.Y + groundOffset(field, x, z))
			formationHeight = math.min(
				formationHeight,
				localClearance - d.ceilingFormationGroundGap - formationRadius * d.ceilingFormationExtentRadiusFactor
			)
			if formationHeight < 0.75 then
				continue
			end
			CaveKit.stalactite(model, CFrame.new(center.X + x, roofY, center.Z + z), {
				height = formationHeight,
				radius = formationRadius,
				levels = 4,
				seed = rng:NextInteger(1, 1_000_000),
				wet = waterPlacement ~= nil,
				collide = false,
			})
			harmlessFormations += 1
		end

		-- Boulders: collidable scatter in ordinary rooms only (entry stays a safe spawn).
		if not isBasin and not isEntry and waterPlacement == nil then
			for _ = 1, d.bouldersPerRoom do
				for _ = 1, 8 do
					local base = rng:NextNumber(d.boulderMinSize, d.boulderMaxSize)
					local ox = rng:NextNumber(-1, 1) * g.cellSize * 0.32
					local oz = rng:NextNumber(-1, 1) * g.cellSize * 0.32
					if not clearOfCeilingReservations(ox, oz, base * 0.75) then
						continue
					end
					local groundY = groundOffset(field, ox, oz)
					CaveKit.boulder(model, CFrame.new(center + Vector3.new(ox, groundY, oz)), base, {
						seed = rng:NextInteger(1, 1_000_000),
						collide = true,
					})
					break
				end
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
				local seed = rng:NextInteger(1, 1_000_000)
				local decorationRadius = width / 2
				if
					not clearOfUnstable(cx, cz, decorationRadius)
					or (hangsFromCeiling and not clearOfAmbush(cx, cz, decorationRadius))
				then
					continue
				end
				local roofY = roofUndersideY(center, field, roofField, ceilingHeight, cx, cz)
				local groundY = center.Y + groundOffset(field, cx, cz)
				local safeHeight = roofY
					- groundY
					- d.ceilingFormationGroundGap
					- width / 2 * d.ceilingFormationExtentRadiusFactor
				columnHeight = math.min(columnHeight, safeHeight)
				if columnHeight < 1 then
					continue
				end
				if hangsFromCeiling then
					CaveKit.stalactite(model, CFrame.new(center.X + cx, roofY, center.Z + cz), {
						height = columnHeight,
						radius = width / 2,
						levels = 4,
						seed = seed,
						collide = false,
					})
				else
					CaveKit.stalagmite(model, CFrame.new(center.X + cx, groundY, center.Z + cz), {
						height = columnHeight,
						radius = width / 2,
						levels = 4,
						seed = seed,
						collide = true,
					})
				end
			end
		end
	end

	-- (Planned ground rises are folded into the Terrain height field above, as smooth mounds.)

	-- Resolve planned XZ placements against the exact paired floor/roof fields. Models are anchored
	-- and collision-neutral; DripstoneService owns the one shared gameplay state.
	for _, placement in plan.dripstones do
		local room = plan.rooms[placement.roomIndex]
		local center = roomCenters[placement.roomIndex]
		local groundField = groundFields[placement.roomIndex]
		local roofField = roofFields[placement.roomIndex]
		local variant = DripstoneRules.variantById(placement.variantId)
		if center == nil or groundField == nil or roofField == nil or variant == nil then
			continue
		end
		local x, z = placement.localOffset.X, placement.localOffset.Z
		local roofY = roofUndersideY(center, groundField, roofField, room.ceilingHeight, x, z)
		local groundY = center.Y + groundOffset(groundField, x, z)
		local clearanceFallDistance = roofY - DripstoneRules.visualLength(variant) - groundY
		-- Planner and builder sample the same pure fields. Keep this guard as a fail-closed defense
		-- against future config drift: an unreadably short drop is omitted, never made unavoidable.
		if clearanceFallDistance < Config.Hazards.unstableDripstone.minimumFallDistance then
			continue
		end
		local anchor = CFrame.new(center.X + x, roofY, center.Z + z)
		local formation = UnstableDripstone.build(model, anchor, variant, placement.visualSeed)
		-- The multi-prong variants do not share one exact tip length. Land their real bounding-box
		-- bottom into the Terrain instead of using the conservative planning envelope as a visual pose.
		local boundingBoxCFrame, boundingBoxSize = formation:GetBoundingBox()
		local visibleBottomY = boundingBoxCFrame.Position.Y - boundingBoxSize.Y / 2
		local fallDistance = math.max(0, visibleBottomY - groundY + Config.Hazards.unstableDripstone.impactEmbedDepth)
		local impactPosition = Vector3.new(center.X + x, groundY, center.Z + z)
		formation:SetAttribute(DripstoneVisualProtocol.attributes.state, DripstoneVisualProtocol.states.dormant)
		formation:SetAttribute(DripstoneVisualProtocol.attributes.stateStartedAt, workspace:GetServerTimeNow())
		formation:SetAttribute(DripstoneVisualProtocol.attributes.restCFrame, anchor)
		formation:SetAttribute(DripstoneVisualProtocol.attributes.impactPosition, impactPosition)
		formation:SetAttribute(DripstoneVisualProtocol.attributes.fallDistance, fallDistance)
		formation:SetAttribute(DripstoneVisualProtocol.attributes.variantId, placement.variantId)
		formation:SetAttribute(DripstoneVisualProtocol.attributes.visualSeed, placement.visualSeed)
		formation:SetAttribute(DripstoneVisualProtocol.attributes.depth, plan.depth)
		CollectionService:AddTag(formation, DripstoneVisualProtocol.tag)
		table.insert(dripstoneRuntimes, {
			model = formation,
			depth = plan.depth,
			impactPosition = impactPosition,
			fallDistance = fallDistance,
			variantId = placement.variantId,
		})
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

	-- The descent objective: a cold, bright beacon with a light pillar so it reads as "the way down"
	-- from across the room and can never be buried under rock. Every part passes through the player.
	local descentColor = Color3.fromRGB(150, 205, 255)
	local function beaconPart(name: string, size: Vector3, offset: Vector3, transparency: number): Part
		local part = newPart(size, descentCenter + offset, descentColor, model, Enum.Material.Neon)
		part.Name = name
		part.Transparency = transparency
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		return part
	end

	local disc = beaconPart("DescentBeacon", Vector3.new(0.6, padSize, padSize), Vector3.new(0, 0.3, 0), 0.05)
	disc.Shape = Enum.PartType.Cylinder
	disc.CFrame = CFrame.new(disc.Position) * CFrame.Angles(0, 0, math.rad(90))

	local beamHeight = math.max(g.wallHeight, 30)
	local beam = beaconPart("DescentBeam", Vector3.new(beamHeight, 2.2, 2.2), Vector3.new(0, beamHeight / 2, 0), 0.72)
	beam.Shape = Enum.PartType.Cylinder
	beam.CFrame = CFrame.new(beam.Position) * CFrame.Angles(0, 0, math.rad(90))

	local orb = beaconPart("DescentOrb", Vector3.new(2.6, 2.6, 2.6), Vector3.new(0, 3, 0), 0.05)
	orb.Shape = Enum.PartType.Ball
	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = descentColor
	beaconLight.Brightness = 3
	beaconLight.Range = 24
	beaconLight.Shadows = false
	beaconLight.Parent = orb

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
		roomSurfaces = roomSurfaces,
		draftZones = draftZones,
		waterRegions = waterRegions,
		dripstones = dripstoneRuntimes,
	}
end

return FloorBuilder

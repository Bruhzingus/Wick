--!strict
-- FloorPlan -> cave geometry from primitives. Decides nothing mechanical: room positions,
-- doorways, hazards and special rooms come from the plan; dimensions from Config/Floors.
-- The ONLY randomness here is cosmetic dressing (relief, boulders, ceiling variance), seeded
-- per depth so rebuilds look identical — gameplay math never reads any of it.

local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
-- Required directly and only for its exported variant type; every VALUE this file reads still comes
-- through the `Config` aggregate above, like everything else here.
local WallLampConfig = require(ReplicatedStorage.Shared.Config.WallLamp)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local DoorwayGeometry = require(ReplicatedStorage.Shared.Logic.DoorwayGeometry)
local BossFloorPlan = require(ReplicatedStorage.Shared.Logic.BossFloorPlan)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local ThreatRules = require(ReplicatedStorage.Shared.Logic.ThreatRules)
local RoofGeometry = require(ReplicatedStorage.Shared.Logic.RoofGeometry)
local RoomFootprint = require(ReplicatedStorage.Shared.Logic.RoomFootprint)
local FloorStacking = require(ReplicatedStorage.Shared.Logic.FloorStacking)
local AshamedLurkerRules = require(ReplicatedStorage.Shared.Logic.AshamedLurkerRules)
local MineRelicRules = require(ReplicatedStorage.Shared.Logic.MineRelicRules)
local PlacementReservations = require(ReplicatedStorage.Shared.Logic.PlacementReservations)
local DripstoneVisualProtocol = require(ReplicatedStorage.Shared.DripstoneVisualProtocol)
local AshamedLurkerVisualProtocol = require(ReplicatedStorage.Shared.AshamedLurkerVisualProtocol)
local DynamiteVisualProtocol = require(ReplicatedStorage.Shared.DynamiteVisualProtocol)
local CaveKit = require(ReplicatedStorage.Shared.NewModelsAndObjects.CaveKit)
local MineRelics = require(ReplicatedStorage.Shared.NewModelsAndObjects.MineRelics)
local UnstableDripstone = require(ReplicatedStorage.Shared.NewModelsAndObjects.UnstableDripstone)
local Cauldron = require(ReplicatedStorage.Shared.NewModelsAndObjects.Cauldron)
local Brazier = require(ReplicatedStorage.Shared.NewModelsAndObjects.Brazier)
local WallLamp = require(ReplicatedStorage.Shared.NewModelsAndObjects.WallLamp)
local DescentLadder = require(ReplicatedStorage.Shared.NewModelsAndObjects.DescentLadder)
local HazardService = require(script.Parent.HazardService)
local SurfaceProbe = require(script.Parent.SurfaceProbe)

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

-- One built vine curtain. VineService owns its burn state; the builder only produces the geometry
-- and the opening it seals.
export type VineRuntime = {
	model: Model,
	barrier: BasePart,
	strands: { BasePart },
	depth: number,
	position: Vector3,
	style: "Vines" | "Icicles",
	puddleParent: Instance,
	puddlePosition: Vector3,
	puddleSize: Vector3,
}

-- ONE BUILT BLAST DOOR (Config/Dynamite). Fills a sealed vault's single doorway with real rock and
-- carries the charge pocket a stick is seated into. `server/DynamiteService` owns whether it has been
-- charged, lit, or broken; the builder produces only geometry and the two points that matter.
--
-- UNLIKE A VINE CURTAIN, THIS BARRIER ANSWERS QUERIES (`CanQuery = true`). A curtain is deliberately
-- invisible to AI probes because threats are meant to slip through the growth; a blast door is solid
-- rock, so the obstacle raycasts `server/ThreatService` already runs have to see it and route around
-- it. Together with the vault's empty `allowedThreats` list, that is what makes "no enemies behind the
-- door" true rather than merely likely.
export type BlastDoorRuntime = {
	model: Model,
	barrier: BasePart,
	-- Every visible piece of the face, so a break can throw the whole thing at once.
	pieces: { BasePart },
	socket: Attachment,
	depth: number,
	position: Vector3,
	roomIndex: number,
	style: Types.BlastDoorStyle,
	openingWidth: number,
	openingHeight: number,
}

-- One resolved arch an Ashamed Lurker can occupy: the doorway's floor centre (local +X along the
-- wall, local Z through the opening) plus the opening's real dimensions and which half is trapped.
export type LurkerSite = {
	cframe: CFrame,
	doorWidth: number,
	doorHeight: number,
	trapSide: AshamedLurkerRules.TrapSide,
}

-- One built Ashamed Lurker: a single invisible anchored proxy the server moves between its arches.
-- The visible body is built locally by every client around this part (AshamedLurkerVisualProtocol).
export type LurkerRuntime = {
	proxy: BasePart,
	sites: { LurkerSite },
	depth: number,
}

-- One built cluster of flammable vegetation. MossFireService owns every bit of its state; the
-- builder produces only the parts and the planned connectivity graph that decides what can carry
-- fire to what. The graph is copied straight from the plan rather than re-derived from part
-- positions, so a dressing change can never alter what burns.
export type MossFireNodeRuntime = {
	part: BasePart,
	kindId: string,
}

export type MossFireRuntime = {
	model: Model,
	depth: number,
	position: Vector3,
	nodes: { MossFireNodeRuntime },
	edges: { { a: number, b: number } },
	-- The collidable mass burning clears, when this cluster forms one. Never load-bearing: a cluster
	-- is never on a route, in a doorway lane, or on the navigation hub.
	obstruction: BasePart?,
}

-- THE CAULDRON HAS NO RUNTIME, and that absence is the point (Config/Cauldron). It is pure
-- presentation over a mechanic that was already complete: `server/BasinService` needs the room point
-- it already had (`basinPosition`) and nothing else, and the vessel's own moving surface is animated
-- by a client from a tag. A runtime handed out here would be a handle nobody could do anything with.
--
-- ONE BUILT BRAZIER (Config/Brazier). `server/BrazierService` owns the payout, the prompt and
-- whether the fire has been lit; the builder produces the cold prop and the rim position the prompt
-- and the ignition VFX use.
--
-- IT NO LONGER CARRIES THE CAVE'S LAMPS. It used to: the fixture a run ended at held the whole
-- floor's lamp list and lit it in a sequence on commit. Lighting the cave is a player action now
-- with its own service, so the two runtimes are separate and neither has to know the other exists.
export type BrazierRuntime = {
	depth: number,
	position: Vector3,
	built: Brazier.BuiltBrazier,
}

-- EVERY WALL LAMP ON ONE FLOOR (Config/WallLamp), cold, with the crowned one called out separately
-- because it is the only one whose ignition answers the rest.
--
-- THE ROOM LAMPS ARE ORDERED HERE, by the builder that placed them, nearest to the crowned lamp
-- first — not re-derived at cascade time from where they ended up. A sequence sorted by position at
-- ignition would silently re-order itself the first time the room layout changed.
--
-- They are handed over on this runtime rather than tagged and looked up, because that is how every
-- other per-floor system in this file already answers "which of these belong to this floor": the
-- builder returns them, the orchestrator passes them to the one service that owns them, and nothing
-- has to scan the world or key a tag by depth. (The lamps ARE also tagged, but for a different
-- consumer entirely: the client finds them that way to draw its own prompt.)
export type WallLampRuntime = {
	depth: number,
	main: WallLamp.BuiltWallLamp?,
	lamps: { WallLamp.BuiltWallLamp },
}

-- ONE BUILT DESCENT LADDER (Config/DescentLadder). `server/DescentLadderService` owns the prompt,
-- the ride and every pose written to the cage and the hatch; the builder produces geometry and the
-- two points that matter — where a rider stands, and where the cage rests.
export type LadderRuntime = {
	depth: number,
	position: Vector3,
	built: DescentLadder.BuiltLadder,
}

export type FloorRuntime = {
	model: Model,
	depth: number,
	entryPosition: Vector3,
	basinPosition: Vector3,
	brazier: BrazierRuntime,
	lamps: WallLampRuntime,
	-- THE WAY DOWN, and no longer a zone. It used to be a `HazardService.Zone` polled every tick
	-- against every runner's position: walk into the box, arrive on the next floor. It is now a
	-- machine with a prompt on it (FLOOR-FIXTURES-OVERHAUL), so what a floor hands out is the fixture
	-- rather than a volume.
	ladder: LadderRuntime,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomSurface },
	-- Exact grid-aligned regions written for this floor. Retirement clears these same regions rather
	-- than guessing a broad bound that could erase another floor or leave rock behind.
	terrainRegions: { Region3 },
	waterRegions: { HazardService.WaterRegion },
	dripstones: { DripstoneRuntime },
	vines: { VineRuntime },
	-- Sealed vault doors (Config/Dynamite.vault). Empty on most floors; at most two.
	blastDoors: { BlastDoorRuntime },
	lurkers: { LurkerRuntime },
	mossFire: { MossFireRuntime },
}

-- THE ROCK PALETTE, resolved per cave family (Config/CaveFamilies.presentation).
--
-- ART-BIBLE §4's law still binds every family: rock is never warm-toned and never self-lit, because
-- the whole visual grammar of the game is that light is the only source of visual information. A Moss
-- cave is a DARK wet-green-grey cave and an Ice cave is a DARK blue-grey one; neither is bright, and
-- nothing in either emits light. What a family changes is the HUE the flame finds when it gets there.
--
-- These module-level values are the resolved palette for the floor currently being built. `build`
-- sets them from the plan's family before it writes a single part, so every helper below reads one
-- consistent palette without six parameters being threaded through all of them.
local WALL_COLOR = Color3.fromRGB(52, 56, 66)
local ROCK_COLOR = Color3.fromRGB(62, 66, 78)
-- The SURFACE GRAIN, not just the tint. Colour alone would read as one cave under three gels; the
-- material is what the candle actually catches as it sweeps a wall.
local WALL_MATERIAL = Enum.Material.Slate
local ROCK_MATERIAL = Enum.Material.Slate
local WATER_COLOR = Color3.fromRGB(42, 66, 92)
local WATER_TAG = "WickWaterSurface"

-- The family this floor belongs to. Resolved once per `build`; presentation only.
local activeFamily = CaveFamilyRules.resolve(nil)

-- THE one place a floor's world height comes from. Floors stack downward by this expedition's own
-- ordinal; `build` places every room from it, and RunOrchestrator reserves engine headroom beneath it
-- before carving (server/EnvironmentSetup.reserveDepth). Both callers must agree exactly, so neither
-- re-derives it.
function FloorBuilder.baseY(localFloor: number): number
	return -(localFloor - 1) * Config.Floors.geometry.floorGap
end

-- A planned shelf needs whichever horizontal buffer is larger: the voxel-wall safety margin or its
-- own flat shoulder plus blend. Keeping this derivation shared inside the builder makes the dressing
-- reservation and the carved Terrain mask cover the same complete transition if either config moves.
local function placementSurfaceMargin(): number
	local probe = Config.Floors.geometry.placementProbe
	return math.max(probe.horizontalMarginStuds, probe.placementPadMarginStuds + probe.placementPadBlendStuds)
end

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
	-- Defaulting to the FAMILY wall stone rather than a hardcoded slate is what makes a wall slab in a
	-- Moss cave feel like coarse wet rock and one in an Ice cave like packed glacier. Callers that pass
	-- an explicit material (water glass, beacon neon) are unaffected.
	part.Material = material or WALL_MATERIAL
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
	shard.Material = ROCK_MATERIAL

	-- THE BIGGEST FLAT SURFACES ANYWHERE IN A ROOM, and so the ones that most decide whether a wall
	-- reads as broken rock or as panelling. A wall shard runs up to roughly 10 x 13 studs, and at
	-- that size a single opaque material with no reflectance is unambiguously a flat quad however it
	-- is tinted — in Ice, whose rock material is glassy, they read as sheets of green glass stuck to
	-- the wall. Giving them the family's formation finish is what breaks that up: adjacent shards
	-- take different materials and answer the candle at different strengths, so the wall acquires
	-- depth instead of faceted colour.
	--
	-- Guarded, like every other finish site: a family with a neutral finish draws no extra rolls and
	-- its walls are byte-identical to what they were.
	local finish = activeFamily.presentation.formationFinish
	if CaveFamilyRules.surfaceFinishVaries(finish) then
		if #finish.materials > 0 then
			shard.Material = finish.materials[rng:NextInteger(1, #finish.materials)]
		end
		shard.Reflectance = rng:NextNumber(finish.reflectanceMin, finish.reflectanceMax)
		shard.Transparency = rng:NextNumber(finish.transparencyMin, finish.transparencyMax)
	end

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

-- The wall sequence must never hang through a doorway. Special rooms are still ordinary assembled
-- rooms and can have their exits on different sides from run to run, so select the first sealed wall
-- from this stable order rather than assuming any particular corner is clear.
local LAMP_WALL_ORDER: { Types.Direction } = { "N", "E", "S", "W" }

type RoomLampPlan = {
	normal: Vector3,
	offsets: { number },
}

type WallDecorationExclusion = {
	minAlong: number,
	maxAlong: number,
	minY: number,
	maxY: number,
}

local function lampWallDirection(room: Types.RoomPlacement): Types.Direction
	local hasDoorway: { [Types.Direction]: boolean } = {}
	for _, direction in room.doorways do
		hasDoorway[direction] = true
	end
	for _, direction in LAMP_WALL_ORDER do
		if not hasDoorway[direction] then
			return direction
		end
	end
	-- A four-way completion chamber is exceptional, but the crowned lamp still needs a wall. Use the
	-- deterministic first wall; doorwayLampOffset moves it onto the intact rock beside the opening.
	return LAMP_WALL_ORDER[1]
end

local function doorwayLampOffset(
	room: Types.RoomPlacement,
	direction: Types.Direction,
	globalDepth: number,
	familyId: string?,
	cellSize: number,
	wallThickness: number,
	lampWidth: number,
	seed: number
): number
	local install = Config.WallLamp.installation
	local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, globalDepth, familyId)
	local halfLamp = lampWidth / 2
	local clearance = math.max(install.clearanceStuds, 0)
	local maximumOffset = math.max(0, cellSize / 2 - wallThickness - halfLamp - clearance)
	local sideGap = profile.width / 2 + halfLamp + clearance
	local left = profile.offset - sideGap
	local right = profile.offset + sideGap
	local leftFits = left >= -maximumOffset
	local rightFits = right <= maximumOffset
	if leftFits and rightFits then
		return if seed % 2 == 0 then left else right
	elseif leftFits then
		return left
	elseif rightFits then
		return right
	end
	-- The configured doorway corner margin makes this unreachable with the shipped dimensions. Keep a
	-- bounded fallback so a future geometry retune cannot place a fixture beyond the room's wall.
	return math.clamp(if math.abs(left) < math.abs(right) then left else right, -maximumOffset, maximumOffset)
end

local function roomLampPlan(
	room: Types.RoomPlacement,
	roomIndex: number,
	globalDepth: number,
	familyId: string?,
	cellSize: number,
	wallThickness: number
): RoomLampPlan?
	if not Config.WallLamp.enabled then
		return nil
	end
	local seed = math.abs(room.gridX * 92821 + room.gridZ * 68917 + globalDepth * 193 + roomIndex * 389)

	local hasDoorway: { [Types.Direction]: boolean } = {}
	for _, direction in room.doorways do
		hasDoorway[direction] = true
	end
	local start = seed % #LAMP_WALL_ORDER + 1
	local selected: Types.Direction? = nil
	-- Prefer intact rock, but rotate the stable order per room so the network does not line every lamp
	-- up on the same compass wall.
	for pass = 1, 2 do
		for offset = 0, #LAMP_WALL_ORDER - 1 do
			local direction = LAMP_WALL_ORDER[(start + offset - 1) % #LAMP_WALL_ORDER + 1]
			if pass == 2 or not hasDoorway[direction] then
				selected = direction
				break
			end
		end
		if selected ~= nil then
			break
		end
	end
	if selected == nil then
		return nil
	end

	local offsets: { number } = {}
	if hasDoorway[selected] then
		-- With no sealed wall available, use the intact rock beside the doorway.
		table.insert(
			offsets,
			doorwayLampOffset(
				room,
				selected,
				globalDepth,
				familyId,
				cellSize,
				wallThickness,
				WallLamp.extent("Room").width,
				seed
			)
		)
	else
		table.insert(offsets, 0)
	end
	return { normal = DOOR_NORMALS[selected], offsets = offsets }
end

local function wallInstallationFloorOffset(
	field: GroundField,
	outward: Vector3,
	offsets: { number },
	cellSize: number,
	wallThickness: number
): number
	local install = Config.WallLamp.installation
	local along = Vector3.new(math.abs(outward.Z), 0, math.abs(outward.X))
	local fixtureInset = math.max(install.fallbackInsetStuds, 0) + install.projectionStuds
	local fixtureDistance = cellSize / 2 - wallThickness - fixtureInset
	local approachDistance = math.max(0, fixtureDistance - math.max(install.approachSampleStuds, 0))
	local middleDistance = (fixtureDistance + approachDistance) / 2
	local minimumOffset = math.min(table.unpack(offsets))
	local maximumOffset = math.max(table.unpack(offsets))
	local middleOffset = (minimumOffset + maximumOffset) / 2
	local highestGround = -math.huge
	-- Sample the fixture centre and its room approach. The mount starts above this maximum rather than
	-- above a guessed room plane, so the wall berm cannot hide a surface-mounted lamp from below.
	for _, lateral in { minimumOffset, middleOffset, maximumOffset } do
		for _, distance in { fixtureDistance, middleDistance, approachDistance } do
			local localPosition = outward * distance + along * lateral
			highestGround = math.max(highestGround, GroundGeometry.offset(field, localPosition.X, localPosition.Z))
		end
	end
	return math.max(install.minimumFloorStuds, highestGround + math.max(install.groundClearanceStuds, 0))
end

type WallMountSurface = {
	position: Vector3,
	inward: Vector3,
}

local function wallMountSurface(
	roomCenter: Vector3,
	outward: Vector3,
	alongOffset: number,
	baseY: number,
	topY: number,
	cellSize: number,
	wallThickness: number
): WallMountSurface
	local install = Config.WallLamp.installation
	local intendedInward = -outward
	local along = Vector3.new(math.abs(outward.Z), 0, math.abs(outward.X))
	local nominalSurface = roomCenter + outward * (cellSize / 2 - wallThickness) + along * alongOffset
	local fallback = nominalSurface + intendedInward * math.max(install.fallbackInsetStuds, 0)
	local probeStartDistance = math.max(
		0,
		cellSize / 2
			- wallThickness
			- math.max(install.fallbackInsetStuds, 0)
			- math.max(install.approachSampleStuds, 0)
	)
	local probeStart = roomCenter + outward * probeStartDistance + along * alongOffset
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Include
	parameters.FilterDescendantsInstances = { workspace.Terrain }
	parameters.IgnoreWater = true

	local closestDistance = math.huge
	local closestResult: RaycastResult? = nil
	for _, y in { baseY, (baseY + topY) / 2, topY } do
		local origin = Vector3.new(probeStart.X, y, probeStart.Z)
		local result = workspace:Raycast(origin, outward * cellSize, parameters)
		if result ~= nil and result.Instance == workspace.Terrain then
			local distance = (result.Position - roomCenter):Dot(outward)
			if distance >= probeStartDistance and distance < closestDistance then
				closestDistance = distance
				closestResult = result
			end
		end
	end

	if closestResult == nil then
		return {
			position = Vector3.new(fallback.X, baseY, fallback.Z),
			inward = intendedInward,
		}
	end

	local result = closestResult :: RaycastResult
	local horizontalNormal = Vector3.new(result.Normal.X, 0, result.Normal.Z)
	local resolvedInward = if horizontalNormal.Magnitude > 0.1
			and horizontalNormal.Unit:Dot(intendedInward) > 0.25
		then horizontalNormal.Unit
		else intendedInward
	local surfacePosition = result.Position + resolvedInward * math.max(install.surfaceOutsetStuds, 0)
	return {
		position = Vector3.new(surfacePosition.X, baseY, surfacePosition.Z),
		inward = resolvedInward,
	}
end

-- The lamps are installed against the Terrain wall before its irregular cosmetic relief is known.
-- Reserve the fixture's whole authored footprint so a random WallRock or moss patch can never grow
-- over one and hide it — which matters far more now than it did when these only lit during a results
-- screen: a lamp a player cannot see is a lamp they cannot choose to light.
--
-- Both exclusions come from `WallLamp.extent`, so the reserved rock and the geometry that gets built
-- into it can only ever change together.
local function lampWallExclusion(
	variant: WallLampConfig.WallLampVariant,
	offsets: { number },
	installationFloorOffset: number
): WallDecorationExclusion
	local install = Config.WallLamp.installation
	local extent = WallLamp.extent(variant)
	local mountHeight = if variant == "Main" then install.mainMountHeight else install.roomMountHeight
	local mountY = installationFloorOffset + mountHeight
	local margin = math.max(install.clearanceStuds, 0)
	local minimumOffset = math.min(table.unpack(offsets))
	local maximumOffset = math.max(table.unpack(offsets))
	local halfWidth = extent.width / 2
	return {
		minAlong = minimumOffset - halfWidth - margin,
		maxAlong = maximumOffset + halfWidth + margin,
		minY = math.max(0, mountY - extent.below - margin),
		maxY = mountY + extent.above + margin,
	}
end

local function overlapsWallExclusion(
	exclusion: WallDecorationExclusion,
	alongPosition: number,
	halfAlong: number,
	yPosition: number,
	halfHeight: number
): boolean
	return alongPosition + halfAlong >= exclusion.minAlong
		and alongPosition - halfAlong <= exclusion.maxAlong
		and yPosition + halfHeight >= exclusion.minY
		and yPosition - halfHeight <= exclusion.maxY
end

-- One flat scab of whatever this family's walls are covered in — damp moss in Stone and Moss, dirty
-- frost in Ice. Purely decorative: it never collides, never answers a raycast, and never casts a
-- shadow, so no gameplay query can see it.
--
-- `damp` still means "this room holds water", and still selects the wetter, slicker palette. In a
-- family whose cover is frost that reads as meltwater rime rather than moss, which is the correct
-- thing for a room with standing water in it either way.
local function newMossPatch(
	parent: Instance,
	frame: CFrame,
	length: number,
	width: number,
	damp: boolean,
	rng: Random
): BasePart
	local moss = Config.Floors.caveMoss
	local presentation = activeFamily.presentation
	-- Damp organic growth uses the shared wet palette; crystalline cover stays the family's own ice
	-- even beside water, where turning it into green Mud would make one Ice room look like Moss.
	local usesDampGrowth = damp and presentation.coverShape == "Patch"
	local palette = if usesDampGrowth then moss.dampPalette else presentation.coverPalette
	local patch = if presentation.coverShape == "Shard" then Instance.new("WedgePart") else Instance.new("Part")
	patch.Name = if presentation.coverShape == "Shard" then "FrostShard" else "CaveMoss"
	patch.CFrame = frame
	patch.Color = palette[rng:NextInteger(1, #palette)]
	patch.Material = if usesDampGrowth then moss.dampMaterial else presentation.coverMaterial
	patch.Transparency = moss.patchTransparency
	patch.Size = Vector3.new(length, moss.patchThickness, width)

	-- HOW THIS FAMILY'S COVER ANSWERS THE FLAME (Config/CaveFamilies.SurfaceFinishProfile). Colour
	-- alone made Ice's frost read as a blue sticker: opaque, matte, flush and identical facet to
	-- facet. Per-facet material, transparency, reflectance and tilt are what turn the same palette
	-- into ice, because the eye identifies ice by how a highlight moves across it.
	--
	-- SKIPPED ENTIRELY FOR A NEUTRAL FINISH, and that guard is load-bearing rather than tidy: Stone
	-- is the regression baseline, every later placement on the floor draws from this same random
	-- stream, and an unconditional roll here would shift every boulder, column and relic behind it.
	-- Damp organic growth also opts out — a wet moss scab is not a crystal facet, and giving it
	-- reflectance would make Moss's walls look varnished.
	if not usesDampGrowth and CaveFamilyRules.surfaceFinishVaries(presentation.coverFinish) then
		local finish = presentation.coverFinish
		if #finish.materials > 0 then
			patch.Material = finish.materials[rng:NextInteger(1, #finish.materials)]
		end
		patch.Transparency = rng:NextNumber(finish.transparencyMin, finish.transparencyMax)
		patch.Reflectance = rng:NextNumber(finish.reflectanceMin, finish.reflectanceMax)
		patch.Size = Vector3.new(
			length * finish.sizeScale,
			moss.patchThickness * finish.thicknessScale,
			width * finish.sizeScale
		)
		-- Tilted about both in-plane axes, so a wall of facets breaks up in two directions rather
		-- than hinging as one sheet.
		local tilt = math.rad(finish.tiltDegrees)
		patch.CFrame = frame * CFrame.Angles(rng:NextNumber(-tilt, tilt), 0, rng:NextNumber(-tilt, tilt))
	end

	patch.Anchored = true
	patch.CanCollide = false
	patch.CanQuery = false
	patch.CanTouch = false
	patch.CastShadow = false
	patch.Parent = parent
	return patch
end

-- A per-room description of the cave floor's height. The floor is not flat: it swells into rock
-- toward the walls and stays level where gameplay needs it — the central plaza (spawns, nav, and
-- centre fixtures), the doorway lanes, and a few marked fixture pads. Planned ground rises become
-- smooth mounds (see swells). All slopes remain gentle enough to walk without spending the
-- player's small recovery hop, and the AI's downward ground probe follows them without snagging.
-- The surface is realised as smooth Roblox Terrain, so the slopes are genuinely continuous rather
-- than faceted parts.
type FlatSpot = GroundGeometry.FlatSpot
type Swell = GroundGeometry.Swell
-- A smoothly carved bowl below the floor; water settles into it (see the room loop).
type Pool = GroundGeometry.Pool
-- Planning and construction share the exact floor field through GroundGeometry.
type GroundField = GroundGeometry.Field

-- Matched to the family's wall stone so floor and walls read as one rock. Stone and Moss pitch their
-- terrain a shade darker than their walls, because terrain renders brighter and the offset lands the
-- two on the same tone once the candle hits them. Ice does NOT: its terrain colour is literally the
-- same value as its wall colour (`Config/CaveFamilies.ICE_ROCK`), because `SetMaterialColor` clamps a
-- terrain material's colour toward that material's own default and Glacier's default is pale — so a
-- hand-tuned offset there would be a second correction fighting an engine clamp over a value neither
-- controls. Resolved per floor, alongside the rest of the palette.
local TERRAIN_MATERIAL = Enum.Material.Slate
local TERRAIN_COLOR = Color3.fromRGB(48, 52, 62)
-- The colour already pushed to the Terrain singleton for each material this session. Terrain
-- material colours are a GLOBAL property of the place, not of a floor, so this is written once per
-- (material, colour) pair rather than on every floor.
--
-- Keyed by material AND compared by value on purpose. Two families can legitimately share a terrain
-- material with different tints; a plain "already applied" flag would let the second expedition on a
-- server inherit the first one's colour, which is a bug that only ever shows up on a long-lived
-- server and never in a single-run test.
local terrainColorApplied: { [Enum.Material]: Color3 } = {}

-- THE STUDIO-AUTHORED SKIN ALREADY REGISTERED FOR EACH BASE MATERIAL THIS SESSION. Exactly the
-- `terrainColorApplied` reasoning above, for the other global-per-place Terrain setting
-- (`Config/CaveFamilies.PresentationProfile.terrainMaterialVariant`): written once per material rather
-- than on every floor, and keyed so a second family sharing a base material could never silently
-- clobber the first one's variant.
local terrainMaterialVariantApplied: { [Enum.Material]: string? } = {}

local function applyTerrainMaterialVariant(material: Enum.Material, variantName: string?)
	if variantName == nil or terrainMaterialVariantApplied[material] == variantName then
		return
	end
	MaterialService:SetBaseMaterialOverride(material, variantName)
	terrainMaterialVariantApplied[material] = variantName
end

local function makeGroundField(
	room: Types.RoomPlacement,
	depth: number,
	openFootprint: boolean,
	flatSpots: { FlatSpot },
	swells: { Swell },
	pools: { Pool }
): GroundField
	return GroundGeometry.fieldFor(room, depth, openFootprint, flatSpots, swells, pools, activeFamily.id)
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
--
-- THE ROOM FOOTPRINT IS THE THIRD SOLID FIELD, and it is what makes shaped rooms real. Outside the
-- room's open mask the whole column is rock, floor to roof; the mask's own blend gives that rock face
-- an eroded lip instead of a voxel cliff. Because the mask is a UNION (shape, navigation hub, doorway
-- lanes, protected discs), no shape can ever seal a doorway or bury the hub — those terms keep their
-- air whatever the shape does. See Logic/RoomFootprint.
local function fillRoomTerrain(
	center: Vector3,
	field: GroundField,
	roofField: RoofGeometry.Field,
	ceilingHeight: number,
	mask: RoomFootprint.OpenMask
): Region3
	local terrain = workspace.Terrain
	if terrainColorApplied[TERRAIN_MATERIAL] ~= TERRAIN_COLOR then
		terrain:SetMaterialColor(TERRAIN_MATERIAL, TERRAIN_COLOR)
		terrainColorApplied[TERRAIN_MATERIAL] = TERRAIN_COLOR
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

	-- COLUMNS FIRST, VOXELS SECOND. All three fields this carve unions — the ground height, the roof
	-- underside and the room's open footprint — are functions of (x, z) alone; not one of them can
	-- read the vertical index. Sampling them inside the Y loop meant every column was evaluated once
	-- per voxel layer, so a room roughly 19 layers tall did nineteen atan2/sin/sqrt passes to arrive
	-- at the same nineteen identical answers. This is by far the heaviest arithmetic in a floor build,
	-- and it collapses to one pass per column with the identical result.
	local columnCount = nx * nz
	local columnFloorY: { number } = table.create(columnCount)
	local columnRoofY: { number } = table.create(columnCount)
	local columnOutside: { number } = table.create(columnCount)
	for xi = 1, nx do
		local localX = origin.X + (xi - 0.5) * 4 - center.X
		local rowBase = (xi - 1) * nz
		for zi = 1, nz do
			local localZ = origin.Z + (zi - 0.5) * 4 - center.Z
			local groundHeight = groundOffset(field, localX, localZ)
			local column = rowBase + zi
			columnFloorY[column] = floorY + groundHeight
			columnRoofY[column] = floorY
				+ RoofGeometry.undersideHeight(ceilingHeight, roofField, groundHeight, localX, localZ)
			-- Solid wherever the room's open footprint is not. Unioned with the floor and roof rather
			-- than written separately, for the same reason those two are: a second pass would carve
			-- Air back through whatever the first one filled.
			columnOutside[column] = 1 - RoomFootprint.openness(mask, localX, localZ)
		end
	end

	local materials: { { { Enum.Material } } } = table.create(nx)
	local occupancies: { { { number } } } = table.create(nx)
	for xi = 1, nx do
		local rowBase = (xi - 1) * nz
		local matY: { { Enum.Material } } = table.create(ny)
		local occY: { { number } } = table.create(ny)
		for yi = 1, ny do
			local voxelBottom = origin.Y + (yi - 1) * 4
			local voxelTop = voxelBottom + 4
			local matZ: { Enum.Material } = table.create(nz)
			local occZ: { number } = table.create(nz)
			for zi = 1, nz do
				local column = rowBase + zi
				local floorOccupancy = math.clamp((columnFloorY[column] - voxelBottom) / 4, 0, 1)
				local roofOccupancy = math.clamp((voxelTop - columnRoofY[column]) / 4, 0, 1)
				local occ = math.max(floorOccupancy, roofOccupancy, columnOutside[column])
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
	return region
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
	damp: boolean,
	protectDoorwayBody: boolean,
	rng: Random,
	decorationExclusion: WallDecorationExclusion?
)
	local g = Config.Floors.geometry
	local d = Config.Floors.caveDressing
	local normal = DOOR_NORMALS[direction]
	local along = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X)) -- wall's long axis
	local across = Vector3.new(math.abs(normal.X), 0, math.abs(normal.Z)) -- wall's thickness axis
	local wallCenter = roomCenter + normal * (g.cellSize / 2 - g.wallThickness / 2) + Vector3.new(0, height / 2, 0)

	-- ONE FLAT BOX PER WALL, `cellSize` wide by the full ceiling height — up to 64 x 46 studs of
	-- unbroken plane. That is by far the largest single surface in a room, and at that scale a
	-- low-contrast part material stops reading as a texture at all and becomes flat paint, which is
	-- what made Ice's walls look like solid blue panels rather than rock.
	--
	-- A family may hide the WALL slabs (`presentation.wallSlabTransparency`). Those are structural
	-- rather than decorative: `fillRoomTerrain` already fills every column outside the room's open
	-- mask with solid rock floor-to-roof, so the real, well-textured cave wall is already standing
	-- exactly where those boxes are — they were simply painted on top of it. Hiding them reveals the
	-- terrain and costs nothing, because transparency never touches collision.
	--
	-- THE ARCH COLUMNS ARE THE EXCEPTION, and getting this wrong is very visible: the rock ABOVE a
	-- doorway is the one place a slab is not standing in front of terrain. The doorway lane
	-- deliberately keeps that whole column as AIR so the opening is passable, so the arch slabs are
	-- the only thing filling it. Hiding them does not reveal rock behind — there is none — it opens a
	-- see-through hole above every doorway in the floor. `alwaysVisible` is what keeps that from being
	-- a thing a family can switch on by accident.
	local function slab(
		length: number,
		offsetAlong: number,
		slabHeight: number,
		offsetUp: number,
		alwaysVisible: boolean?
	)
		local size = along * length + across * g.wallThickness + Vector3.new(0, slabHeight, 0)
		local position = wallCenter + along * offsetAlong + Vector3.new(0, offsetUp, 0)
		local part = newPart(size, position, WALL_COLOR, parent)
		part.Transparency = if alwaysVisible then 0 else activeFamily.presentation.wallSlabTransparency
		-- An invisible slab must not keep casting the shadow of a wall the player can no longer see,
		-- or the terrain behind it renders in permanent shade.
		part.CastShadow = part.Transparency < 1
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
				-- Always visible: this is overhead rock filling a column the terrain deliberately left
				-- as air, so it has nothing behind it to fall back on.
				slab(colWidth + 0.2, xc, slabHeight, archTop / 2, true)
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
		if not protectDoorwayBody then
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
		local alongSize = size * rng:NextNumber(0.7, 1.4)
		local verticalSize = size * rng:NextNumber(0.9, 1.8)
		if
			decorationExclusion ~= nil
			and overlapsWallExclusion(decorationExclusion, alongPos, alongSize / 2, yPos, verticalSize / 2)
		then
			continue
		end
		local shard = newJaggedShard(
			"WallRock",
			Vector3.new(alongSize, verticalSize, protrude),
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

	-- FLOWSTONE DRAPERY: the one large-scale form a wall carries. It lives here rather than in the room
	-- loop because only `buildWall` knows where this wall's face actually is and where its doorway gap
	-- has been cut — the room loop works in a cell-centred XZ mask that has no concept of a wall face.
	--
	-- Collision-neutral like everything else hung on a face, so it may stand as proud of the rock as it
	-- likes; both tests below are about not burying a doorway or a lamp, never about traversal.
	if rng:NextNumber() < d.drapeChancePerWall then
		local halfWidth = rng:NextNumber(d.drapeMinHalfWidth, d.drapeMaxHalfWidth)
		local topY = height * rng:NextNumber(d.drapeMinTopFraction, d.drapeMaxTopFraction)
		-- TRIMMED TO THE FLOOR RATHER THAN REJECTED BY IT. A sheet that stops short of the ground is
		-- what flowstone does; one that reaches it closes the wall off, and a player reads a closed
		-- curtain as the edge of the room rather than as the rock behind it.
		local length = math.min(rng:NextNumber(d.drapeMinLength, d.drapeMaxLength), topY - 1.5)
		local alongPos = rng:NextNumber(-1, 1) * math.max(g.cellSize / 2 - halfWidth - 1, 0)
		local blocksDoorway = gapHalfWidth > 0
			and math.abs(alongPos - gapOffset) < gapHalfWidth + halfWidth + d.drapeDoorwayClearance
		local blocksFixture = decorationExclusion ~= nil
			and overlapsWallExclusion(decorationExclusion, alongPos, halfWidth, topY - length / 2, length / 2)
		if length >= d.drapeMinLength * 0.6 and not blocksDoorway and not blocksFixture then
			-- `along` carries no sign (it is built from absolute components), so it cannot be used as
			-- the sheet's own X axis: on two of the four walls it would mirror the form into the rock.
			-- Deriving the frame from the inward normal gives a genuinely right-handed basis on all
			-- four, with +Z out of the wall, which is what `CaveKit.drapery` hangs its folds against.
			local inward = -normal
			local up = Vector3.new(0, 1, 0)
			CaveKit.drapery(
				parent,
				CFrame.fromMatrix(
					roomCenter
						+ normal * (g.cellSize / 2 - g.wallThickness)
						+ along * alongPos
						+ Vector3.new(0, topY, 0),
					up:Cross(inward),
					up,
					inward
				),
				{
					radius = halfWidth,
					height = length,
					taper = d.drapeRootThickness,
					levels = d.drapeSegments,
					wet = damp,
					seed = rng:NextInteger(1, 1_000_000),
				}
			)
		end
	end

	-- Damp cave moss creeps up from the base of every wall, and takes over the walls of rooms that
	-- hold standing water. Purely decorative, and kept out of the doorway throat so an opening never
	-- reads as overgrown when it is actually clear.
	local moss = Config.Floors.caveMoss
	if moss.enabled then
		-- Scaled by the family's cover density: Moss walls are thickly overgrown, Ice walls carry a
		-- restrained skin of frost, Stone is unchanged at 1. Collision-neutral in every family.
		local authoredCount = if damp then moss.dampPatchesPerWall else moss.patchesPerWall
		local patchCount = math.floor(authoredCount * math.max(0, activeFamily.presentation.coverDensityFactor) + 0.5)
		local faceOffset = g.cellSize / 2 - g.wallThickness - moss.patchThickness / 2
		local mossCeiling = height * moss.wallMaxHeightFraction
		for _ = 1, patchCount do
			local length = rng:NextNumber(moss.patchMinSize, moss.patchMaxSize)
			local width = rng:NextNumber(moss.patchMinSize, moss.patchMaxSize)
			local halfSpan = math.max(length, width) / 2
			local alongPos = rng:NextNumber(-1, 1) * math.max(g.cellSize / 2 - halfSpan, 0)
			if
				gapHalfWidth > 0
				and math.abs(alongPos - gapOffset) < gapHalfWidth + halfSpan + moss.doorwayClearance
			then
				continue
			end
			-- Biased toward the damp floor line rather than spread evenly up the wall.
			local rise = rng:NextNumber(0, 1) ^ moss.wallHeightBias
			local yPos = math.clamp(rise * mossCeiling, halfSpan * 0.2, math.max(halfSpan * 0.2, height))
			if
				decorationExclusion ~= nil
				and overlapsWallExclusion(decorationExclusion, alongPos, halfSpan, yPos, halfSpan)
			then
				continue
			end
			local position = roomCenter + normal * faceOffset + along * alongPos + Vector3.new(0, yPos, 0)
			local inward = -normal
			local base = CFrame.fromMatrix(position, along, inward, along:Cross(inward))
			newMossPatch(parent, base * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), length, width, damp, rng)
		end
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

function FloorBuilder.build(plan: Types.FloorPlan): FloorRuntime
	local g = Config.Floors.geometry
	local d = Config.Floors.caveDressing
	-- THE ONE PLACE THIS FLOOR LEARNS WHICH CAVE IT IS. Everything below reads the resolved palette
	-- rather than the family id; nothing here branches on which family it turned out to be.
	activeFamily = CaveFamilyRules.resolve(plan.familyId)
	local presentation = activeFamily.presentation
	WALL_COLOR = presentation.wallColor
	ROCK_COLOR = presentation.rockColor
	WALL_MATERIAL = presentation.wallMaterial
	ROCK_MATERIAL = presentation.rockMaterial
	TERRAIN_COLOR = presentation.terrainColor
	TERRAIN_MATERIAL = presentation.terrainMaterial
	applyTerrainMaterialVariant(TERRAIN_MATERIAL, presentation.terrainMaterialVariant)
	-- Formations take the family's own rock. This is all "Ice icicles" are and all they need to be:
	-- the falling hazard is the SAME unstable formation with the same warning, fall timing, impact
	-- footprint and light suppression (Config/Hazards.unstableDripstone, Logic/DripstoneRules), built
	-- out of pale blue-grey glacier instead of slate. No new hazard, no new rule, no new state.
	-- Does this family's formation finish actually change anything? Resolved once per floor rather
	-- than per part, and used to decide whether the kit is handed a finish at all — a neutral family
	-- must configure the kit exactly as it did before finishes existed, down to the random stream.
	local formationFinish = presentation.formationFinish
	local formationFinishVaries = CaveFamilyRules.surfaceFinishVaries(formationFinish)
	CaveKit.configure({
		palette = presentation.formationPalette,
		dampTint = d.formationDampTint,
		materials = if formationFinishVaries and #formationFinish.materials > 0
			then formationFinish.materials
			else presentation.formationMaterials,
		wetMaterial = presentation.formationWetMaterial,
		wetReflectance = d.formationWetReflectance,
		-- ...and the finish itself, which is what separates an ice spire from an ice-COLOURED rock
		-- spire. Passed as nil for a neutral family so the kit takes its untouched path.
		reflectanceMin = if formationFinishVaries then formationFinish.reflectanceMin else nil,
		reflectanceMax = if formationFinishVaries then formationFinish.reflectanceMax else nil,
		transparencyMin = if formationFinishVaries then formationFinish.transparencyMin else nil,
		transparencyMax = if formationFinishVaries then formationFinish.transparencyMax else nil,
	})
	-- The abandoned workings are made of iron and timber in every cave — they were carried down, not
	-- grown — so the only thing a family says about them is what has since taken hold ON them, which
	-- is resolved from the same surface cover it creeps up its own walls with.
	MineRelics.configure(
		CaveFamilyRules.relicWeathering(
			plan.familyId,
			Config.MineRelics.palette.growthChance,
			Config.MineRelics.palette.growthSize
		)
	)
	-- Floors stack by this expedition's own ordinal; how deep the cave "is" never moves the world.
	--
	-- UNLESS THE PLAN SAYS OTHERWISE (`Types/World.FloorPlan.floorY`), which exactly one caller does:
	-- the developer laboratory builds both authored boss floors at its own height, beside itself,
	-- rather than at the depth its scope key would stack them to. Every expedition floor leaves the
	-- field nil and is stacked from its ordinal as it always was.
	local floorY = plan.floorY or FloorBuilder.baseY(plan.depth)
	-- Cosmetic-only rng, seeded by the canonical depth: identical dressing on rebuild, zero gameplay
	-- reads. It matches the planner's seed source so a given global depth always dresses the same.
	local rng = Random.new(plan.globalDepth * 7919 + 101)

	local model = Instance.new("Model")
	model.Name = "Floor_" .. plan.depth

	local roomCenters: { Vector3 } = {}
	local roomSurfaces: { [number]: RoomSurface } = {}
	local terrainRegions: { Region3 } = {}
	local groundFields: { [number]: GroundField } = {}
	local roofFields: { [number]: RoofGeometry.Field } = {}
	local waterRegions: { HazardService.WaterRegion } = {}
	local dripstoneRuntimes: { DripstoneRuntime } = {}
	local waterByRoom: { [number]: Types.HazardPlacement } = {}
	local dripstonesByRoom: { [number]: { Types.DripstonePlacement } } = {}
	local ambushesByRoom: { [number]: { AmbushReservation } } = {}
	local mainRoom = plan.rooms[plan.brazierRoomIndex]
	local mainLampDirection = lampWallDirection(mainRoom)
	local mainLampNormal = DOOR_NORMALS[mainLampDirection]
	local mainLampSeed =
		math.abs(mainRoom.gridX * 92821 + mainRoom.gridZ * 68917 + plan.globalDepth * 193 + plan.brazierRoomIndex * 389)
	local mainLampOffset = 0
	if table.find(mainRoom.doorways, mainLampDirection) ~= nil then
		mainLampOffset = doorwayLampOffset(
			mainRoom,
			mainLampDirection,
			plan.globalDepth,
			plan.familyId,
			g.cellSize,
			g.wallThickness,
			WallLamp.extent("Main").width,
			mainLampSeed
		)
	end
	local roomLampPlans: { [number]: RoomLampPlan } = {}
	for index, room in plan.rooms do
		if index == plan.brazierRoomIndex then
			-- The crowned lamp is this room's one lamp, and it is placed by the main path above rather
			-- than through this loop. A second, ordinary lamp on another wall of the same chamber would
			-- put a lamp a player can light next to the lamp that lights the whole floor, which is a
			-- choice with an obviously correct answer and therefore not a choice.
			continue
		end
		local lampPlan = roomLampPlan(room, index, plan.globalDepth, plan.familyId, g.cellSize, g.wallThickness)
		if lampPlan ~= nil then
			roomLampPlans[index] = lampPlan
		end
	end
	local gameplayReservations: { PlacementReservations.Reservation } = {}
	for _, spawn in plan.threatSpawns do
		local definition = Config.Threats.definitions[spawn.threatId]
		local roofClearance = if definition ~= nil then ThreatRules.roofStructuralClearanceRadius(definition) else nil
		PlacementReservations.add(
			gameplayReservations,
			spawn.roomIndex,
			spawn.offset,
			roofClearance or Config.Floors.terrain.gameplaySpawnRadius,
			"Threat"
		)
	end
	for _, spawn in plan.lootSpawns do
		PlacementReservations.add(
			gameplayReservations,
			spawn.roomIndex,
			spawn.offset,
			Config.Loot.placementFootprint / 2 + placementSurfaceMargin(),
			"Loot"
		)
	end
	-- Seams reserve against the DRESSING pass too, not only against the terrain mask below. Deposits sit
	-- 21-27 studs out from the room centre, and rock columns (4-12 studs tall, rolled at 19.8-25.6 studs)
	-- and CaveKit boulders (up to 7 studs, rolled within +/-20.5) land in exactly that band — so without
	-- this a perfectly well-placed seam could be stood on top of by a cosmetic prop and never be seen.
	for _, deposit in plan.deposits do
		local surfaceShelfRadius = Config.Mining.visual.surfaceProbeRadius + placementSurfaceMargin()
		PlacementReservations.add(
			gameplayReservations,
			deposit.roomIndex,
			deposit.localOffset,
			math.max(
				(Config.Mining.placement.footprint + Config.Mining.placement.standingClearance) / 2,
				surfaceShelfRadius
			),
			"Deposit"
		)
	end
	-- The dead candle's own body. Its loot and its flies already reserved themselves through the two
	-- lists above; this is the corpse and its spilled wax, which a rock column standing in the middle of
	-- would turn from a tableau into a pile of unrelated objects.
	if plan.deadCandle ~= nil then
		PlacementReservations.add(
			gameplayReservations,
			plan.deadCandle.roomIndex,
			plan.deadCandle.localOffset,
			Config.DeadCandle.layout.corpseClearance,
			"DeadCandle"
		)
	end
	-- THE THREE PER-FLOOR FIXTURES, reserved against the DRESSING pass as well as against the terrain
	-- mask. They never used to need this: a flat wax disc and a floating beacon passed through
	-- everything, so a boulder standing in the middle of one cost nothing. They are real objects now —
	-- one of them is a hole in the floor with a headframe over it — and a rock column rolled on top of
	-- the shaft mouth would be an obstacle in front of the only way down.
	do
		local quarter = g.cellSize / 4
		local ladderClearance = Config.DescentLadder.cageWidth / 2 + Config.DescentLadder.shaftClearance + 3.4
		for _, fixture in
			{
				{ room = plan.entryRoomIndex, offset = Vector3.zero, radius = ladderClearance },
				{ room = plan.basinRoomIndex, offset = Vector3.zero, radius = Config.Cauldron.plinthRadius + 1.5 },
				{
					room = plan.basinRoomIndex,
					offset = Vector3.new(quarter, 0, quarter),
					radius = ladderClearance,
				},
				{
					room = plan.brazierRoomIndex,
					offset = Vector3.new(-quarter, 0, -quarter),
					-- The Brazier's cairn, plus room to stand at it. It reclaimed this exact footprint
					-- from the floor-standing lantern that briefly held the extraction: the planner has
					-- reserved and flattened this quarter of the completion room since before either
					-- object existed (Logic/FloorPlanner, `brazierMask`).
					radius = Config.Brazier.fixture.cairnRadius + 2,
				},
			}
		do
			PlacementReservations.add(gameplayReservations, fixture.room, fixture.offset, fixture.radius, "Fixture")
		end
	end
	if plan.warden ~= nil then
		for _, offset in
			{
				plan.warden.pileOffset,
				plan.warden.waxOffset,
				plan.warden.counterDripstoneOffset,
			}
		do
			PlacementReservations.add(
				gameplayReservations,
				plan.warden.roomIndex,
				offset,
				Config.StoneWarden.encounterClearance,
				"Warden"
			)
		end
	end
	local lurkerEdges: { [string]: boolean } = {}
	for _, placement in plan.lurkers do
		for _, site in placement.sites do
			local room = plan.rooms[site.roomIndex]
			local normal = DOOR_NORMALS[site.direction]
			local edgeX2 = room.gridX * 2 + normal.X
			local edgeZ2 = room.gridZ * 2 + normal.Z
			lurkerEdges[edgeX2 .. "," .. edgeZ2] = true
		end
	end
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
		-- EVERY roof-bound row, not only the ambusher. Asked of ThreatRules because the two profiles
		-- that put a creature on a ceiling agree about territory and dressing clearance even though they
		-- disagree about everything else — and reading `definition.ambush` here meant a striker held a
		-- patch nothing had been kept out of.
		local roof = if definition ~= nil then ThreatRules.roofProfile(definition) else nil
		if roof == nil then
			continue
		end
		local list = ambushesByRoom[spawn.roomIndex]
		if list == nil then
			list = {}
			ambushesByRoom[spawn.roomIndex] = list
		end
		table.insert(list, {
			offset = spawn.offset,
			-- A roof-bound body may patrol, act, and retreat anywhere in its full territory. Reserve that
			-- gameplay disc plus a small visual/body margin, not just its initial ceiling point.
			clearance = math.max(0, roof.territoryRadius + roof.roofDecorationClearance),
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

	-- THE FLOOR'S ABANDONED WORKINGS (Config/MineRelics). Rolled once, here, before any room is
	-- looked at: most descents pass through rock nobody ever worked, and the draw list is walked
	-- rather than re-rolled so two floors running cannot hand back the same silhouette. Placement
	-- itself happens inside the room loop, alongside the rest of the dressing.
	local relicDraw: { MineRelicRules.RelicDef } = if MineRelicRules.rollFloorHasWorkings(rng)
		then MineRelicRules.floorDraw(plan.globalDepth)
		else {}
	local relicsPlaced = 0

	-- Minimum opening size for this whole floor, or nil to let every doorway roll freely. Only the
	-- Grub Queen's authored plan asks for one; it is recognised by its Queen-bearing shape rather than
	-- by a flag, so nothing else in the builder has to learn what a boss floor is.
	local doorwayMinimum: DoorwayGeometry.FloorProfile? = if BossFloorPlan.isBossPlan(plan)
		then BossFloorPlan.DOORWAY_MINIMUM
		else nil

	for index, room in plan.rooms do
		local horizontalCenter = FloorStacking.roomCenter(plan, index, g.cellSize)
		local center = Vector3.new(horizontalCenter.X, floorY, horizontalCenter.Z)
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
			local profile = DoorwayGeometry.profile(
				room.gridX,
				room.gridZ,
				direction,
				plan.globalDepth,
				plan.familyId,
				-- WIDER ON THE BOSS FLOOR. Her brood and her two chained guards circulate through every
				-- opening while the player runs the same loop the other way, and an ordinary rolled
				-- opening biases TIGHT by design — which would turn each arm of her chamber into a
				-- queue. Nil on every other floor, so ordinary caves are untouched.
				doorwayMinimum
			)
			doorProfiles[direction] = profile
		end

		-- Off-centre fixtures must stay level under the rocky floor. The room centre is always flat;
		-- mark extra pads for the Descent Ladder and the Gas Lantern so they never sit on a slope. The
		-- ladder's pad has to stay wide enough for the headframe's legs to stand on real rock either
		-- side of the shaft mouth, not just for the mouth itself.
		local flatSpots: { FlatSpot } = {}
		if index == plan.entryRoomIndex then
			local arrivalRadius = Config.DescentLadder.cageWidth / 2
				+ Config.DescentLadder.shaftClearance
				+ Config.DescentLadder.arrival.forcedExitStuds
			table.insert(flatSpots, { x = 0, z = 0, r = arrivalRadius })
		end
		if index == plan.basinRoomIndex then
			table.insert(flatSpots, { x = g.cellSize / 4, z = g.cellSize / 4, r = g.cellSize / 8 + 2 })
		end
		if index == plan.brazierRoomIndex then
			-- The lantern is wall-mounted now, but this retained central pad keeps the established chamber
			-- route level beneath its prompt range.
			table.insert(flatSpots, { x = -g.cellSize / 4, z = -g.cellSize / 4, r = 6 })
		end
		-- The dead candle lies in a pool of its own set wax. That reads as spilled liquid only if the
		-- rock under it is level, so the corpse gets the same flat pad the Basin's ladder and the
		-- Warden's fixtures get.
		if plan.deadCandle ~= nil and index == plan.deadCandle.roomIndex then
			table.insert(flatSpots, {
				x = plan.deadCandle.localOffset.X,
				z = plan.deadCandle.localOffset.Z,
				r = Config.DeadCandle.layout.corpseClearance,
			})
		end
		if plan.warden ~= nil and index == plan.warden.roomIndex then
			for _, offset in
				{
					plan.warden.pileOffset,
					plan.warden.waxOffset,
					plan.warden.counterDripstoneOffset,
				}
			do
				table.insert(flatSpots, {
					x = offset.X,
					z = offset.Z,
					r = Config.StoneWarden.encounterClearance,
				})
			end
		end

		-- Flooded rooms hold one pool, already settled by the planner into this room's deepest natural
		-- recess. The bed is flattened at the planned depth (never raised above the recess floor), and
		-- the waterline is pinned to that bed rather than to the room's base plane, so wading depth is
		-- exactly the module's declared depth however deep the dip happens to be.
		local pools: { Pool } = {}
		local waterRadius = 0
		local waterSurfaceY = floorY
		if waterPlacement ~= nil then
			local offset = waterPlacement.localOffset :: Vector3
			local poolSize = waterPlacement.size :: Vector3
			local bedDepth = waterPlacement.bedDepth :: number
			waterRadius = (poolSize.X + poolSize.Z) / 4
			waterSurfaceY = floorY - bedDepth + (waterPlacement.waterDepth :: number)
			table.insert(pools, {
				x = offset.X,
				z = offset.Z,
				radius = waterRadius,
				depth = bedDepth,
			})
		end

		local openFootprint = isBasin or isEntry or index == plan.brazierRoomIndex
		-- First evaluate the untouched authored floor (including structural fixture pads). Loot and ore
		-- then receive small level shelves at THAT local elevation. This preserves raised edges and broad
		-- room undulation while giving each rigid model a planar contact patch after voxelization.
		local naturalField =
			makeGroundField(room, plan.globalDepth, openFootprint, flatSpots, swellsByRoom[index] or {}, pools)
		local placementFlatSpots = table.clone(flatSpots)
		local padMargin = Config.Floors.geometry.placementProbe.placementPadMarginStuds
		local padBlend = Config.Floors.geometry.placementProbe.placementPadBlendStuds
		for _, spawn in plan.lootSpawns do
			if spawn.roomIndex == index then
				table.insert(placementFlatSpots, {
					x = spawn.offset.X,
					z = spawn.offset.Z,
					r = Config.Loot.placementFootprint / 2 + padMargin,
					height = GroundGeometry.offset(naturalField, spawn.offset.X, spawn.offset.Z),
					blend = padBlend,
				})
			end
		end
		for _, deposit in plan.deposits do
			if deposit.roomIndex == index then
				table.insert(placementFlatSpots, {
					x = deposit.localOffset.X,
					z = deposit.localOffset.Z,
					r = Config.Mining.visual.surfaceProbeRadius + padMargin,
					height = GroundGeometry.offset(naturalField, deposit.localOffset.X, deposit.localOffset.Z),
					blend = padBlend,
				})
			end
		end
		flatSpots = placementFlatSpots

		-- Both deterministic terrain fields are seeded by the canonical depth, exactly as the planner
		-- seeded them; a mismatch here would put planned placements on the wrong ground.
		local field =
			makeGroundField(room, plan.globalDepth, openFootprint, flatSpots, swellsByRoom[index] or {}, pools)
		groundFields[index] = field
		local roofField = RoofGeometry.fieldFor(room, plan.globalDepth)
		roofFields[index] = roofField
		roomSurfaces[index] = {
			center = center,
			ceilingHeight = ceilingHeight,
			groundField = field,
			roofField = roofField,
		}

		-- The room's open footprint, rebuilt from the SAME inputs the planner used (the room, the
		-- canonical depth, the family) so the rock this carves is exactly the rock every placement on
		-- this floor was validated against. Every planned gameplay position is then unioned in as a
		-- protected disc — belt-and-braces, because the planner already refused anything outside the
		-- footprint, but it means a future placement pass that forgets to check cannot bury something.
		local mask = RoomFootprint.maskFor(room, plan.globalDepth, plan.familyId)
		for _, spot in flatSpots do
			RoomFootprint.reserve(mask, spot.x, spot.z, spot.r)
		end
		for _, spawn in plan.threatSpawns do
			if spawn.roomIndex == index then
				local definition = Config.Threats.definitions[spawn.threatId]
				local roofClearance = if definition ~= nil
					then ThreatRules.roofStructuralClearanceRadius(definition)
					else nil
				RoomFootprint.reserve(
					mask,
					spawn.offset.X,
					spawn.offset.Z,
					roofClearance or Config.Floors.terrain.gameplaySpawnRadius
				)
			end
		end
		for _, spawn in plan.lootSpawns do
			if spawn.roomIndex == index then
				RoomFootprint.reserve(
					mask,
					spawn.offset.X,
					spawn.offset.Z,
					Config.Loot.placementFootprint / 2 + placementSurfaceMargin()
				)
			end
		end
		if plan.deadCandle ~= nil and plan.deadCandle.roomIndex == index then
			RoomFootprint.reserve(
				mask,
				plan.deadCandle.localOffset.X,
				plan.deadCandle.localOffset.Z,
				Config.DeadCandle.layout.corpseClearance
			)
		end
		for _, deposit in plan.deposits do
			if deposit.roomIndex == index then
				local standingRadius = (Config.Mining.placement.footprint + Config.Mining.placement.standingClearance)
					/ 2
				local surfaceSafeRadius = Config.Mining.visual.surfaceProbeRadius + placementSurfaceMargin()
				RoomFootprint.reserve(
					mask,
					deposit.localOffset.X,
					deposit.localOffset.Z,
					math.max(standingRadius, surfaceSafeRadius)
				)
			end
		end

		-- Every room gets continuous rocky floor banks and a separately seeded, inverted rocky roof,
		-- with solid rock outside its open footprint. All three share one write so none can erase
		-- another.
		table.insert(terrainRegions, fillRoomTerrain(center, field, roofField, ceilingHeight, mask))

		-- Ice needs a floor identity as strong as its walls. These are thin, collision-neutral crusts
		-- seated on the same analytic field that carved the Terrain, so they catch candlelight without
		-- changing friction, movement, placement probes, or any gameplay query. Other families answer
		-- with zero in their presentation row; the builder never branches on a family id.
		local groundCoverTarget = math.max(0, math.floor(presentation.groundCoverPatchesPerRoom + 0.5))
		local groundCoverBuilt = 0
		local coverHalfRange = g.cellSize * 0.34
		for _ = 1, groundCoverTarget * 4 do
			if groundCoverBuilt >= groundCoverTarget then
				break
			end
			local length =
				rng:NextNumber(Config.Floors.caveMoss.groundPatchMinSize, Config.Floors.caveMoss.groundPatchMaxSize)
			local width =
				rng:NextNumber(Config.Floors.caveMoss.groundPatchMinSize, Config.Floors.caveMoss.groundPatchMaxSize)
			local radius = math.max(length, width) / 2
			local localX = rng:NextNumber(-coverHalfRange, coverHalfRange)
			local localZ = rng:NextNumber(-coverHalfRange, coverHalfRange)
			if
				not RoomFootprint.isOpen(mask, localX, localZ)
				or not RoomFootprint.isOpen(mask, localX - radius, localZ - radius)
				or not RoomFootprint.isOpen(mask, localX + radius, localZ - radius)
				or not RoomFootprint.isOpen(mask, localX - radius, localZ + radius)
				or not RoomFootprint.isOpen(mask, localX + radius, localZ + radius)
			then
				continue
			end
			local inPool = false
			for _, pool in pools do
				local dx, dz = localX - pool.x, localZ - pool.z
				if dx * dx + dz * dz < (pool.radius + radius) ^ 2 then
					inPool = true
					break
				end
			end
			if inPool then
				continue
			end

			local groundY = center.Y + groundOffset(field, localX, localZ)
			local sample = 1.5
			local xSampleY = center.Y + groundOffset(field, localX + sample, localZ)
			local zSampleY = center.Y + groundOffset(field, localX, localZ + sample)
			local surfaceRight = Vector3.new(sample, xSampleY - groundY, 0).Unit
			local provisionalBack = Vector3.new(0, zSampleY - groundY, sample).Unit
			local surfaceUp = provisionalBack:Cross(surfaceRight).Unit
			local surfaceBack = surfaceRight:Cross(surfaceUp).Unit
			local frame = CFrame.fromMatrix(
				Vector3.new(center.X + localX, groundY + Config.Floors.caveMoss.groundLift, center.Z + localZ),
				surfaceRight,
				surfaceUp,
				surfaceBack
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			newMossPatch(model, frame, length, width, false, rng)
			groundCoverBuilt += 1
		end

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

			-- A shoreline of moss follows the waterline around the bowl rim, sitting on the real
			-- carved ground rather than a guessed plane, so the pool reads as damp from any angle.
			local moss = Config.Floors.caveMoss
			if moss.enabled then
				local pool = Config.Hazards.waterPool
				for shoreIndex = 1, pool.shoreMossPatches do
					local angle = (shoreIndex - 1) / pool.shoreMossPatches * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
					local ringRadius = waterRadius
						+ rng:NextNumber(-pool.shoreMossRingPadding * 0.4, pool.shoreMossRingPadding)
					local localX = (waterPlacement.localOffset :: Vector3).X + math.cos(angle) * ringRadius
					local localZ = (waterPlacement.localOffset :: Vector3).Z + math.sin(angle) * ringRadius
					local length = rng:NextNumber(moss.groundPatchMinSize, moss.groundPatchMaxSize)
					local width = rng:NextNumber(moss.groundPatchMinSize, moss.groundPatchMaxSize)
					if
						math.abs(localX) + length / 2 > g.cellSize / 2 - Config.Floors.terrain.wallClearance
						or math.abs(localZ) + width / 2 > g.cellSize / 2 - Config.Floors.terrain.wallClearance
					then
						continue
					end
					local groundY = center.Y + groundOffset(field, localX, localZ) + moss.groundLift
					newMossPatch(
						model,
						CFrame.new(center.X + localX, groundY, center.Z + localZ)
							* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
						length,
						width,
						true,
						rng
					)
				end
			end

			table.insert(waterRegions, {
				surfaceY = waterSurfaceY,
				center = poolCenter,
				size = Vector3.new(waterRadius * 2, 2, waterRadius * 2),
			})
		end

		local isDamp = waterPlacement ~= nil
		local networkPlan = roomLampPlans[index]
		local mainInstallationFloorOffset = if index == plan.brazierRoomIndex
			then wallInstallationFloorOffset(field, mainLampNormal, { mainLampOffset }, g.cellSize, g.wallThickness)
			else nil
		local networkInstallationFloorOffset = if networkPlan ~= nil
			then wallInstallationFloorOffset(
				field,
				networkPlan.normal,
				networkPlan.offsets,
				g.cellSize,
				g.wallThickness
			)
			else nil
		local mainExclusion = if index == plan.brazierRoomIndex
			then lampWallExclusion("Main", { mainLampOffset }, mainInstallationFloorOffset :: number)
			else nil
		local networkExclusion = if networkPlan ~= nil
			then lampWallExclusion("Room", networkPlan.offsets, networkInstallationFloorOffset :: number)
			else nil
		for direction in DOOR_NORMALS do
			local normal = DOOR_NORMALS[direction]
			local decorationExclusion = if mainExclusion ~= nil and mainLampNormal == normal
				then mainExclusion
				elseif
					networkPlan ~= nil
					and networkExclusion ~= nil
					and networkPlan.normal == normal
				then networkExclusion
				else nil
			local profile = doorProfiles[direction]
			if profile ~= nil then
				local edgeKey = (room.gridX * 2 + normal.X) .. "," .. (room.gridZ * 2 + normal.Z)
				buildWall(
					center,
					direction,
					true,
					model,
					ceilingHeight,
					profile.width,
					profile.height,
					profile.offset,
					isDamp,
					lurkerEdges[edgeKey] == true,
					rng,
					decorationExclusion
				)
			else
				buildWall(
					center,
					direction,
					false,
					model,
					ceilingHeight,
					0,
					0,
					0,
					isDamp,
					false,
					rng,
					decorationExclusion
				)
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
		local function clearOfGameplay(x: number, z: number, decorationRadius: number): boolean
			return not PlacementReservations.overlaps(
				gameplayReservations,
				index,
				Vector3.new(x, 0, z),
				decorationRadius,
				Config.Floors.terrain.gameplaySpawnSeparation
			)
		end
		local function clearOfPools(x: number, z: number, decorationRadius: number): boolean
			local margin = decorationRadius + Config.MineRelics.placement.poolClearance
			for _, pool in pools do
				local dx, dz = x - pool.x, z - pool.z
				if dx * dx + dz * dz < (pool.radius + margin) ^ 2 then
					return false
				end
			end
			return true
		end

		-- ONE ABANDONED WORKING, if this room drew one. Placed BEFORE the cosmetic dressing below and
		-- reserved into `gameplayReservations` on success, so the boulders and rock columns that follow
		-- treat it exactly the way they already treat a deposit or a pickup: they stay off it.
		--
		-- Entry, Basin and Brazier rooms are excluded, and so is every route: unlike a stalactite or a
		-- boulder, a relic is COLLIDABLE MASS in a room a player has to cross in the dark, and putting
		-- one in the walk between two doorways would be the one way this dressing could cost somebody a
		-- run. `RoomFootprint.clearOfRoutes` is the check that guarantees it cannot.
		local isBrazierRoom = index == plan.brazierRoomIndex
		if
			relicsPlaced < #relicDraw
			and not isBasin
			and not isEntry
			and not isBrazierRoom
			and MineRelicRules.rollRoomAttempt(rng)
		then
			local def = relicDraw[relicsPlaced + 1]
			local placement = Config.MineRelics.placement
			local ringMin, ringMax = MineRelicRules.ringBand(def, g.cellSize)
			local bearings = math.max(1, math.floor(placement.placementBearings))
			local radiiPerBearing = math.max(1, math.floor(placement.placementRadiiPerBearing))
			local startBearing = rng:NextNumber(0, math.pi * 2)
			local relicSeed = rng:NextInteger(1, 1_000_000)
			local isWall = def.anchoring == "Wall"
			local footprint = def.footprintRadius
			local seated = false

			if MineRelicRules.fitsRoom(def, ceilingHeight) then
				for bearing = 0, bearings - 1 do
					if seated then
						break
					end
					local angle = startBearing + bearing * (math.pi * 2 / bearings)
					local outX, outZ = math.cos(angle), math.sin(angle)
					for radiusStep = 0, radiiPerBearing - 1 do
						-- Evenly spaced across the band with a jitter of one step, so the sweep genuinely
						-- covers the band instead of landing on the same three rings on every bearing.
						local span = (ringMax - ringMin) / radiiPerBearing
						local radius = ringMin + radiusStep * span + rng:NextNumber(0, span)
						local x, z = outX * radius, outZ * radius

						-- A wall piece walks outward until the mask says rock, then backs off by its own
						-- declared stand-off. That puts a ladder ON the face of a shaped room rather than a
						-- guessed distance from a cell edge the room's footprint curves away from.
						if isWall then
							local reach = x
							local reachZ = z
							for _ = 1, placement.wallProbeSteps do
								local nextX = reach + outX * placement.wallProbeStep
								local nextZ = reachZ + outZ * placement.wallProbeStep
								if not RoomFootprint.isOpen(mask, nextX, nextZ) then
									break
								end
								reach, reachZ = nextX, nextZ
							end
							x = reach - outX * def.wallOffset
							z = reachZ - outZ * def.wallOffset
						end

						-- Open air is checked on the centre and the three non-outward compass points. The
						-- outward one is skipped on purpose for a wall piece: leaning on the rock is what it
						-- is for, so requiring air behind it would reject every valid spot.
						local inwardOpen = RoomFootprint.isOpen(mask, x - outX * footprint, z - outZ * footprint)
						local lateralOpen = RoomFootprint.isOpen(mask, x - outZ * footprint, z + outX * footprint)
							and RoomFootprint.isOpen(mask, x + outZ * footprint, z - outX * footprint)
						local outwardOpen = isWall
							or RoomFootprint.isOpen(mask, x + outX * footprint, z + outZ * footprint)
						if
							not RoomFootprint.isOpen(mask, x, z)
							or not inwardOpen
							or not lateralOpen
							or not outwardOpen
							or not RoomFootprint.clearOfRoutes(mask, x, z, footprint + placement.routeClearance)
							or not clearOfGameplay(x, z, footprint)
							or not clearOfCeilingReservations(x, z, footprint)
							or not clearOfPools(x, z, footprint)
						then
							continue
						end

						-- Seated on the real floor gradient rather than level, and sunk far enough that the
						-- analytic field and the voxelized Terrain carved from it cannot leave it floating.
						local groundY = center.Y + groundOffset(field, x, z)
						local sample = placement.slopeSample
						local xSampleY = center.Y + groundOffset(field, x + sample, z)
						local zSampleY = center.Y + groundOffset(field, x, z + sample)
						local surfaceRight = Vector3.new(sample, xSampleY - groundY, 0).Unit
						local provisionalBack = Vector3.new(0, zSampleY - groundY, sample).Unit
						local surfaceUp = provisionalBack:Cross(surfaceRight).Unit
						local surfaceBack = surfaceRight:Cross(surfaceUp).Unit
						-- A wall piece looks back into the room (its own +Z is the rock); an open piece takes
						-- a free yaw. A yaw of `atan2(-dx, -dz)` produces the LookVector (dx, 0, dz), so
						-- looking inward along -(outX, outZ) is `atan2(outX, outZ)`.
						local yaw = if isWall then math.atan2(outX, outZ) else rng:NextNumber(0, math.pi * 2)
						local seat = CFrame.fromMatrix(
							Vector3.new(center.X + x, groundY - placement.sinkStuds, center.Z + z),
							surfaceRight,
							surfaceUp,
							surfaceBack
						) * CFrame.Angles(0, yaw, 0)

						if MineRelics.build(model, def.id, seat, relicSeed) ~= nil then
							PlacementReservations.add(
								gameplayReservations,
								index,
								Vector3.new(x, 0, z),
								footprint,
								"MineRelic"
							)
							relicsPlaced += 1
							seated = true
							break
						end
					end
				end
			end
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
			-- Roof dressing follows the room's open air too: a facet hung where the footprint is solid
			-- would be buried inside the rock it is meant to be breaking up.
			if not clearOfCeilingReservations(x, z, decorationRadius) or not RoomFootprint.isOpen(mask, x, z) then
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
				-- THE FAMILY'S rock, not `Config/Floors.caveDressing`'s. This read the shared authored
				-- palette until now, which meant the fractured roof planes overhead — a large, close,
				-- constantly-in-frame surface — stayed Stone's grey slate in every cave, so an Ice
				-- chamber had a grey ceiling over its blue walls. Stone is unaffected: its own
				-- presentation palette and materials ARE these four entries, in the same order and
				-- count, so the same rolls select the same values.
				facet.Color = presentation.formationPalette[rng:NextInteger(1, #presentation.formationPalette)]
				facet.Material = presentation.formationMaterials[rng:NextInteger(1, #presentation.formationMaterials)]
				-- Roof facets set their own surface rather than going through CaveKit, so the family
				-- finish has to be applied here too or the ceiling stays matte while everything
				-- hanging off it turns glassy — which reads worse than leaving both matte.
				if formationFinishVaries then
					if #formationFinish.materials > 0 then
						facet.Material = formationFinish.materials[rng:NextInteger(1, #formationFinish.materials)]
					end
					facet.Reflectance = rng:NextNumber(formationFinish.reflectanceMin, formationFinish.reflectanceMax)
					facet.Transparency =
						rng:NextNumber(formationFinish.transparencyMin, formationFinish.transparencyMax)
				end
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
			if not clearOfCeilingReservations(x, z, d.ceilingStrawSpread) or not RoomFootprint.isOpen(mask, x, z) then
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
			if not clearOfCeilingReservations(x, z, formationRadius) or not RoomFootprint.isOpen(mask, x, z) then
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

		--------------------------------------------------------------------------------
		-- FAMILY SURFACE DRESSING — the second floor layer, the icicle fringe, and the one
		-- self-lit thing a cave is allowed. All three are data-driven from the family's
		-- presentation row (Config/CaveFamilies) and every one of them is a no-op at a count
		-- of zero, which is how Stone and Moss opt out without this code knowing they exist.
		--
		-- EVERYTHING BUILT HERE IS COLLISION-NEUTRAL, without exception: CanCollide, CanQuery
		-- and CanTouch all false, so no movement cast, AI probe, placement query or hazard
		-- reservation can see a single part of it. That is what lets this section be as
		-- visually busy as it likes at zero risk to anything the planner already proved.
		--------------------------------------------------------------------------------

		-- A SECOND MATERIAL LAYER OVER THE FLOOR: broad flat panes of clear ice seated on the
		-- same analytic ground field the Terrain was carved from, so they follow the real
		-- slope rather than floating over it. Sparse on purpose — the point is to interrupt a
		-- uniform surface, and a floor glazed everywhere is just a different uniform surface.
		local glaze = CaveFamilyRules.floorGlaze(activeFamily.id)
		local sheetsBuilt = 0
		for _ = 1, glaze.sheetsPerRoom * 5 do
			if sheetsBuilt >= glaze.sheetsPerRoom then
				break
			end
			local length = rng:NextNumber(glaze.minSize, glaze.maxSize)
			local width = rng:NextNumber(glaze.minSize, glaze.maxSize)
			local radius = math.max(length, width) / 2
			local localX = rng:NextNumber(-1, 1) * (g.cellSize * 0.34)
			local localZ = rng:NextNumber(-1, 1) * (g.cellSize * 0.34)
			-- Open air on the centre and all four corners, so a pane never juts out of a
			-- shaped room's rock. Pools are skipped: a sheet of ice lying across standing
			-- water would read as frozen-over, and the water is a live hazard that has to
			-- stay legible as water.
			if
				not RoomFootprint.isOpen(mask, localX, localZ)
				or not RoomFootprint.isOpen(mask, localX - radius, localZ - radius)
				or not RoomFootprint.isOpen(mask, localX + radius, localZ - radius)
				or not RoomFootprint.isOpen(mask, localX - radius, localZ + radius)
				or not RoomFootprint.isOpen(mask, localX + radius, localZ + radius)
				or not clearOfPools(localX, localZ, radius)
			then
				continue
			end

			local groundY = center.Y + groundOffset(field, localX, localZ)
			local sample = 1.5
			local xSampleY = center.Y + groundOffset(field, localX + sample, localZ)
			local zSampleY = center.Y + groundOffset(field, localX, localZ + sample)
			local sheetRight = Vector3.new(sample, xSampleY - groundY, 0).Unit
			local provisionalBack = Vector3.new(0, zSampleY - groundY, sample).Unit
			local sheetUp = provisionalBack:Cross(sheetRight).Unit
			local sheetBack = sheetRight:Cross(sheetUp).Unit

			local sheet = Instance.new("Part")
			sheet.Name = "IceSheet"
			sheet.Size = Vector3.new(length, glaze.thickness, width)
			sheet.CFrame = CFrame.fromMatrix(
				-- Sunk by most of its own thickness so the pane reads as ice that formed IN a
				-- dip in the rock rather than a slab dropped on top of it.
				Vector3.new(center.X + localX, groundY - glaze.thickness * 0.35, center.Z + localZ),
				sheetRight,
				sheetUp,
				sheetBack
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			sheet.Color = glaze.palette[rng:NextInteger(1, #glaze.palette)]
			sheet.Material = glaze.material
			sheet.Transparency = glaze.transparency
			sheet.Reflectance = glaze.reflectance
			sheet.Anchored = true
			sheet.CanCollide = false
			sheet.CanQuery = false
			sheet.CanTouch = false
			sheet.CastShadow = false
			sheet.Parent = model
			sheetsBuilt += 1
		end

		-- THE ICICLE FRINGE. Clusters across the open ceiling, and — the half that actually
		-- sells the family — clusters hung inside every doorway mouth, because a player looks
		-- at an opening before they walk through it.
		local fringe = CaveFamilyRules.icicleFringe(activeFamily.id)
		local fringeBuilt = 0
		for _ = 1, fringe.clustersPerRoom * 5 do
			if fringeBuilt >= fringe.clustersPerRoom then
				break
			end
			local x = rng:NextNumber(-1, 1) * (g.cellSize * 0.36)
			local z = rng:NextNumber(-1, 1) * (g.cellSize * 0.36)
			if not clearOfCeilingReservations(x, z, fringe.spread) or not RoomFootprint.isOpen(mask, x, z) then
				continue
			end
			local roofY = roofUndersideY(center, field, roofField, ceilingHeight, x, z)
			local clearance = roofY - (center.Y + groundOffset(field, x, z))
			-- Held clear of the floor by the same gap the harmless formations use, so a fringe
			-- can never hang into the space a player walks through.
			local length = math.min(fringe.maxLength, clearance - d.ceilingFormationGroundGap)
			if length < fringe.minLength then
				continue
			end
			CaveKit.icicles(model, CFrame.new(center.X + x, roofY, center.Z + z), fringe.spikesPerCluster, {
				height = length,
				radius = fringe.spread,
				taper = fringe.rootThickness,
				levels = 3,
				seed = rng:NextInteger(1, 1_000_000),
				collide = false,
			})
			fringeBuilt += 1
		end

		-- Doorway mouths. Hung just INSIDE the room from the arch of each opening this room
		-- actually has, at a length capped well under the opening's own height so the fringe
		-- frames the doorway rather than obstructing the sightline through it.
		for direction, doorProfile in doorProfiles do
			local doorNormal = DOOR_NORMALS[direction]
			local doorAlong = Vector3.new(math.abs(doorNormal.Z), 0, math.abs(doorNormal.X))
			-- The SAME arch curve `buildWall` cuts the opening with, so the fringe hangs off the
			-- rock lip instead of off a flat line through the middle of a curved mouth. Hanging
			-- these at the flat `doorProfile.height` would leave the centre clusters floating in
			-- open air below the apex and bury the outer ones in the jamb.
			local archRise = math.max(0, math.min(doorProfile.height * 0.6, ceilingHeight - doorProfile.height - 0.5))
			for cluster = 1, fringe.clustersPerDoorway do
				-- -1..1 across the span, inset so no cluster sits exactly on a jamb.
				local tt = ((cluster - 0.5) / fringe.clustersPerDoorway * 2 - 1) * 0.78
				local lateral = doorProfile.offset + tt * (doorProfile.width / 2)
				-- Two studs inside the wall face: outside it there is only solid rock.
				local inward = doorNormal * (g.cellSize / 2 - 2)
				local localOffset = inward + doorAlong * lateral
				local archTop = doorProfile.height + archRise * math.sqrt(math.max(0, 1 - tt * tt))
				local archY = center.Y + groundOffset(field, localOffset.X, localOffset.Z) + archTop
				-- A third of the opening's height at most. A doorway a player cannot read the
				-- far side of is a doorway they will not walk through, and the barricades that
				-- deliberately DO seal an opening are a different system entirely.
				local length = math.min(fringe.maxLength, doorProfile.height * 0.32)
				if length < fringe.minLength then
					continue
				end
				CaveKit.icicles(
					model,
					CFrame.new(center.X + localOffset.X, archY, center.Z + localOffset.Z),
					fringe.spikesPerCluster,
					{
						height = length,
						radius = fringe.spread * 0.7,
						taper = fringe.rootThickness,
						levels = 3,
						seed = rng:NextInteger(1, 1_000_000),
						collide = false,
					}
				)
			end
		end

		-- Boulders: collidable scatter in ordinary rooms only (entry stays a safe spawn). Counts are
		-- scaled by the family's internal-formation density — Moss packs its rooms with obstruction,
		-- Ice deliberately leaves fewer things to hide behind — and every piece must land in open air,
		-- because a collidable prop buried in the rock of a shaped room is a prop nobody will ever see.
		local boulderCount = CaveFamilyRules.internalFormationCount(activeFamily, d.bouldersPerRoom)
		if not isBasin and not isEntry and waterPlacement == nil then
			for _ = 1, boulderCount do
				for _ = 1, 8 do
					local base = rng:NextNumber(d.boulderMinSize, d.boulderMaxSize)
					local ox = rng:NextNumber(-1, 1) * g.cellSize * 0.32
					local oz = rng:NextNumber(-1, 1) * g.cellSize * 0.32
					if
						not clearOfCeilingReservations(ox, oz, base * 0.75)
						or not clearOfGameplay(ox, oz, base * 0.75)
						or not RoomFootprint.isOpen(mask, ox, oz)
					then
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
			for columnIndex = 1, CaveFamilyRules.internalFormationCount(activeFamily, d.rockColumnsPerRoom) do
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
					or not RoomFootprint.isOpen(mask, cx, cz)
					or (hangsFromCeiling and not clearOfAmbush(cx, cz, decorationRadius))
					or (not hangsFromCeiling and not clearOfGameplay(cx, cz, decorationRadius))
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

			-- A TRUE PILLAR: the stalactite and the stalagmite above, grown together. It is the oldest
			-- thing that can be in a cave and the one silhouette that says so without narrating
			-- anything, which is why it earns the only piece of full-height collidable dressing in the
			-- game.
			--
			-- HELD OFF THE ROUTES, unlike the boulders and stalagmites above, which are checked against
			-- gameplay reservations only. Those are waist-to-chest obstacles a player rounds by reflex;
			-- a pillar spans floor to roof, so one seated in the walk between two doorways is a wall in
			-- the dark rather than a thing to edge past. `clearOfRoutes` is the same guarantee a mine
			-- relic gets, for the same reason.
			--
			-- Skipped in tall chambers by `pillarMaxCeilingHeight`: past roughly two dozen studs the
			-- form stops reading as a joined pair at candle range and starts reading as a poured column,
			-- because the player only ever sees the few studs of it their own flame reaches.
			if ceilingHeight <= d.pillarMaxCeilingHeight and rng:NextNumber() < d.pillarChancePerRoom then
				for _ = 1, d.pillarPlacementAttempts do
					local pillarWidth = rng:NextNumber(d.pillarMinWidth, d.pillarMaxWidth)
					local footprint = pillarWidth / 2
					local angle = rng:NextNumber(0, 2 * math.pi)
					local radius =
						rng:NextNumber(g.cellSize * d.pillarRingMinFactor, g.cellSize * d.pillarRingMaxFactor)
					local px, pz = math.cos(angle) * radius, math.sin(angle) * radius
					if
						not RoomFootprint.isOpen(mask, px, pz)
						or not RoomFootprint.clearOfRoutes(mask, px, pz, footprint + d.pillarRouteClearance)
						or not clearOfGameplay(px, pz, footprint)
						or not clearOfCeilingReservations(px, pz, footprint)
						or not clearOfPools(px, pz, footprint)
					then
						continue
					end
					local groundY = center.Y + groundOffset(field, px, pz)
					local roofY = roofUndersideY(center, field, roofField, ceilingHeight, px, pz)
					-- Built to the REAL gap between the two surfaces at this exact spot rather than to a
					-- rolled height. A pillar is defined by touching both ends; one stopping a stud short
					-- of the roof is a fat stalagmite, and the entire read is gone.
					local span = roofY - groundY
					if span < 3 then
						continue
					end
					CaveKit.column(model, CFrame.new(center.X + px, groundY, center.Z + pz), span, {
						radius = footprint,
						seed = rng:NextInteger(1, 1_000_000),
						wet = waterPlacement ~= nil,
					})
					PlacementReservations.add(
						gameplayReservations,
						index,
						Vector3.new(px, 0, pz),
						footprint,
						"CavePillar"
					)
					break
				end
			end
		end

		-- BREAKDOWN CHIPS banked out near the walls, in EVERY room including the entry and the Basin.
		-- The cave floor is smooth Terrain and reads as poured at candle range, which is the exact
		-- problem `CaveKit.rubble` was written for; it is ankle height, carries no collider and answers
		-- no query, so there is no room in the game it could make worse to stand in.
		--
		-- Pools are the one exclusion: chips lying across standing water would float on it, and the
		-- water is a live hazard that has to stay legible as water.
		for _ = 1, d.rubblePatchesPerRoom do
			for _ = 1, 6 do
				local angle = rng:NextNumber(0, 2 * math.pi)
				local radius = rng:NextNumber(g.cellSize * d.rubbleRingMinFactor, g.cellSize * d.rubbleRingMaxFactor)
				local rx, rz = math.cos(angle) * radius, math.sin(angle) * radius
				if not RoomFootprint.isOpen(mask, rx, rz) or not clearOfPools(rx, rz, d.rubblePatchArea) then
					continue
				end
				CaveKit.rubble(
					model,
					CFrame.new(center.X + rx, center.Y + groundOffset(field, rx, rz), center.Z + rz),
					d.rubblePatchArea,
					d.rubbleChipsPerPatch,
					{ seed = rng:NextInteger(1, 1_000_000) }
				)
				break
			end
		end
	end

	-- THE DESCENT SHAFTS ARE THE FINAL TERRAIN MUTATION. FloorStacking places the successor entry below
	-- this floor's descent pad, and both ends reopen the same column so either build order produces the
	-- same passage. Cut them before the query barrier: a barrier followed by another FillBlock would
	-- hand every surface consumer a stale collision snapshot again.
	do
		local shaftOrigin = FloorStacking.descentOrigin(plan, g.cellSize)
		-- HORIZONTAL COMPONENT ONLY, then `floorY`. `descentOrigin` is derived from `worldOrigin`
		-- and therefore carries its Y; adding `floorY` to the whole vector would count a non-zero
		-- origin height twice. Every expedition floor passes Y = 0, so this reads identically for
		-- them and correctly for a floor placed by hand.
		local shaftCenter = Vector3.new(shaftOrigin.X, floorY, shaftOrigin.Z)
		local cutConfig = Config.DescentLadder
		local shaftHalf = cutConfig.cageWidth / 2 + cutConfig.shaftClearance + 1
		local shaftCutBottom = shaftCenter.Y - g.floorGap + 4
		local shaftCutTop = shaftCenter.Y + 2
		local shaftCutHeight = shaftCutTop - shaftCutBottom
		workspace.Terrain:FillBlock(
			CFrame.new(shaftCenter.X, (shaftCutBottom + shaftCutTop) / 2, shaftCenter.Z),
			Vector3.new(shaftHalf * 2, shaftCutHeight, shaftHalf * 2),
			Enum.Material.Air
		)
		if plan.depth > 1 then
			local entryCenter = roomCenters[plan.entryRoomIndex]
			local arrivalCutBottom = entryCenter.Y + 4
			local arrivalCutTop = entryCenter.Y + g.floorGap + 2
			local arrivalCutHeight = arrivalCutTop - arrivalCutBottom
			workspace.Terrain:FillBlock(
				CFrame.new(entryCenter.X, (arrivalCutBottom + arrivalCutTop) / 2, entryCenter.Z),
				Vector3.new(shaftHalf * 2, arrivalCutHeight, shaftHalf * 2),
				Enum.Material.Air
			)
		end
	end

	-- TERRAIN QUERY COMMIT BARRIER. Voxel edits change the data immediately, but Roblox does not expose
	-- the new Terrain to spatial queries until a subsequent simulation step. Everything below that asks
	-- where the built floor actually is (starting with Lurker sites, followed by all population services
	-- after this builder returns) fails closed on a missing hit. Crossing this one shared boundary keeps
	-- those strict checks honest without bringing back guessed Y offsets or per-object retries.
	RunService.Heartbeat:Wait()

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

	-- Family-stamped vine or icicle barriers seal a doorway until cleared. Collision is CanQuery = false so it
	-- stops bodies without becoming an invisible wall in every AI probe and cast trace; threats slip
	-- through the growth, players do not. The planner already guaranteed the opening is redundant.
	local vineRuntimes: { VineRuntime } = {}
	local vines = Config.Vines
	for _, placement in plan.vines do
		local room = plan.rooms[placement.roomIndex]
		local center = roomCenters[placement.roomIndex]
		local field = groundFields[placement.roomIndex]
		if room == nil or center == nil or field == nil then
			continue
		end
		local vineVisual = vines.visual
		local iceVisual = Config.Icicles.visual
		local isIce = placement.style == "Icicles"
		local barrierThickness = if isIce then iceVisual.barDepth else vineVisual.barrierThickness
		local barrierSkirt = if isIce then iceVisual.barrierSkirt else vineVisual.barrierSkirt
		local archRiseFraction = if isIce then iceVisual.archRiseFraction else vineVisual.archRiseFraction
		local normal = DOOR_NORMALS[placement.direction]
		local along = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X))
		local across = Vector3.new(math.abs(normal.X), 0, math.abs(normal.Z))
		local profile =
			DoorwayGeometry.profile(room.gridX, room.gridZ, placement.direction, plan.globalDepth, plan.familyId)

		-- The doorway lane is held flat by the ground field, so sampling just inside the room gives
		-- the same height the player actually walks through the opening at.
		local laneLocal = normal * (g.cellSize / 2 - 4) + along * profile.offset
		local groundY = center.Y + groundOffset(field, laneLocal.X, laneLocal.Z)
		-- Matches the tallest arch buildWall can cut, so the curtain always covers the whole opening.
		local curtainHeight = profile.height * (1 + archRiseFraction)
		local openingCenter = center + normal * (g.cellSize / 2) + along * profile.offset

		local curtain = Instance.new("Model")
		curtain.Name = if isIce then "IcicleBarricade" else "VineCurtain"

		local barrier = Instance.new("Part")
		barrier.Name = if isIce then "IcicleBarrier" else "VineBarrier"
		barrier.Size = along * profile.width
			+ across * barrierThickness
			+ Vector3.new(0, curtainHeight + barrierSkirt, 0)
		barrier.Position = Vector3.new(openingCenter.X, groundY + (curtainHeight - barrierSkirt) / 2, openingCenter.Z)
		barrier.Transparency = 1
		barrier.Anchored = true
		barrier.CanCollide = true
		barrier.CanQuery = false
		barrier.CanTouch = false
		barrier.CastShadow = false
		barrier.Parent = curtain

		-- The curtain is several layers of jittered strands stacked through the opening rather than one
		-- evenly spaced comb: layers are offset by half a slot from each other and every strand is
		-- scattered further still, so strands cross and there is no straight sightline through.
		local strands: { BasePart } = {}
		local vineRng = Random.new(placement.visualSeed)
		local spread = profile.width * (1 + vineVisual.lateralOverhangFraction * 2)
		local slot = spread / vineVisual.strandCount
		if isIce then
			-- FROZEN SHUT, NOT BARRED SHUT. See Config/Icicles for the four layers this is built from
			-- and why the previous nine-bars-and-two-rails build had to go: it read as a gate somebody
			-- installed, and a natural obstruction may never read as an installed object.
			--
			-- Every piece is collision-neutral; the single invisible barrier above owns all blocking.
			-- Each is recorded with a MELT RANK — 0 for the thin extremities, 1 for the welded crust —
			-- and the pieces are handed to VineService sorted by it, so the barricade melts tips-first
			-- the way ice actually does instead of fading out all at once.
			local ranked: { { part: BasePart, rank: number } } = {}
			-- Local frame at the foot of the opening: +X runs across the doorway, +Y up, +Z through it.
			local doorFrame = CFrame.new(Vector3.new(openingCenter.X, groundY, openingCenter.Z))
				* CFrame.Angles(0, if normal.X ~= 0 then -math.pi / 2 else 0, 0)
			local halfWidth = profile.width / 2

			local function icePiece(name: string, size: Vector3, frame: CFrame, rank: number, wedge: boolean?): BasePart
				local part = if wedge then Instance.new("WedgePart") else Instance.new("Part")
				part.Name = name
				part.Size = size
				part.CFrame = frame
				-- Thin extremities take clear glass and the mass behind them takes packed ice, so the
				-- barricade separates into layers under a candle instead of reading as one moulded slab.
				local fine = rank < 0.35
				part.Color = iceVisual.palette[vineRng:NextInteger(1, #iceVisual.palette)]
				part.Material = if fine then iceVisual.tipMaterial else iceVisual.material
				part.Transparency = (if fine then iceVisual.tipTransparency else iceVisual.transparency)
					* vineRng:NextNumber(0.7, 1.3)
				-- Jittered rather than flat, on the same argument the family surface finishes make: a
				-- constant reflectance across every piece is only slightly less flat than none, because
				-- the whole barricade then flashes as one object as the flame sweeps it.
				part.Reflectance = iceVisual.reflectance * vineRng:NextNumber(0.45, 1.55)
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Parent = curtain
				table.insert(ranked, { part = part, rank = rank })
				return part
			end

			-- One tapered icicle. `dir` is -1 hanging from the arch and 1 rising off the floor; the
			-- levels are yaw-offset from each other for the same reason CaveKit's spires are, because
			-- an unrotated taper is a wedding cake rather than fractured ice.
			local function icicle(base: CFrame, dir: number, length: number, rootThickness: number, levels: number)
				local lean = math.rad(iceVisual.fangLeanDegrees) * vineRng:NextNumber(-1, 1)
				local leanBearing = vineRng:NextNumber(0, math.pi * 2)
				local cursor = base * CFrame.Angles(math.cos(leanBearing) * lean, 0, math.sin(leanBearing) * lean)
				local levelLength = length / levels
				local yaw = vineRng:NextNumber(0, math.pi)
				for level = 1, levels do
					local t0 = (level - 1) / levels
					local t1 = level / levels
					local width = rootThickness
						* (1 - (1 - iceVisual.fangTipFraction) * (t0 + t1) / 2)
						* vineRng:NextNumber(0.86, 1.12)
					yaw += vineRng:NextNumber(0.5, 1.3)
					-- Overlap into the level above so no seam can open along the taper.
					local blockLength = levelLength * 1.3
					local block = cursor * CFrame.new(0, dir * blockLength * 0.36, 0) * CFrame.Angles(0, yaw, 0)
					icePiece(
						"IcicleFang",
						Vector3.new(width, blockLength, width * vineRng:NextNumber(0.78, 1.1)),
						block,
						-- The rank IS the position along the taper, so a tip is the first thing to go.
						t0 * 0.8 + 0.05
					)
					cursor = cursor * CFrame.new(0, dir * levelLength, 0)
				end
				-- Two crossed wedges make a ridged broken point rather than a flat-cut stub.
				local tipWidth = rootThickness * iceVisual.fangTipFraction * 2.1
				local tipLength = rootThickness * 1.6
				local tipYaw = vineRng:NextNumber(0, math.pi)
				for _, turn in { 0, math.pi } do
					icePiece(
						"IcicleTip",
						Vector3.new(tipWidth, tipLength, tipWidth * 0.55),
						cursor
							* CFrame.Angles(0, tipYaw + turn, 0)
							* CFrame.new(0, dir * tipLength * 0.5, tipWidth * 0.24)
							* CFrame.Angles(if dir > 0 then 0 else math.pi, 0, 0),
						0,
						true
					)
				end
			end

			-- CRUST along the arch: the frozen mass the fangs have grown out of.
			for archIndex = 1, iceVisual.crustBlocksAlongArch do
				local t = (archIndex - 0.5) / iceVisual.crustBlocksAlongArch
				local blockWidth = profile.width / iceVisual.crustBlocksAlongArch * vineRng:NextNumber(1.05, 1.45)
				local blockHeight = iceVisual.crustThickness * vineRng:NextNumber(0.8, 1.6)
				icePiece(
					"IcicleCrust",
					Vector3.new(blockWidth, blockHeight, iceVisual.crustDepth * vineRng:NextNumber(0.8, 1.15)),
					doorFrame
						* CFrame.new(
							(t - 0.5) * profile.width,
							curtainHeight - blockHeight * vineRng:NextNumber(0.2, 0.5),
							vineRng:NextNumber(-1, 1) * iceVisual.fangDepthJitter
						)
						* CFrame.Angles(0, vineRng:NextNumber(-0.15, 0.15), vineRng:NextNumber(-0.1, 0.1)),
					1
				)
			end
			-- CRUST down both jambs: the barricade is welded to the rock on every side it touches.
			for _, side in { -1, 1 } do
				for jambIndex = 1, iceVisual.crustBlocksPerJamb do
					local t = (jambIndex - 0.5) / iceVisual.crustBlocksPerJamb
					local blockHeight = curtainHeight / iceVisual.crustBlocksPerJamb * vineRng:NextNumber(1, 1.4)
					local blockWidth = iceVisual.crustThickness * vineRng:NextNumber(0.9, 1.9)
					icePiece(
						"IcicleCrust",
						Vector3.new(blockWidth, blockHeight, iceVisual.crustDepth * vineRng:NextNumber(0.8, 1.15)),
						doorFrame
							* CFrame.new(
								side * (halfWidth - blockWidth * vineRng:NextNumber(0.1, 0.45)),
								t * curtainHeight,
								vineRng:NextNumber(-1, 1) * iceVisual.fangDepthJitter
							)
							* CFrame.Angles(0, vineRng:NextNumber(-0.2, 0.2), side * vineRng:NextNumber(0, 0.14)),
						0.92
					)
				end
			end

			-- FANGS from the arch. A fixed count across any width (see the config note) with lengths
			-- rolled across the full authored range, so the bottom edge is a jagged line.
			local fangSlot = profile.width / (iceVisual.fangCount + 1)
			for fangIndex = 1, iceVisual.fangCount do
				local lateral = (fangIndex - (iceVisual.fangCount + 1) / 2) * fangSlot
				local length = curtainHeight
					* vineRng:NextNumber(iceVisual.fangMinLengthFraction, iceVisual.fangMaxLengthFraction)
				icicle(
					doorFrame
						* CFrame.new(
							lateral + vineRng:NextNumber(-1, 1) * fangSlot * 0.18,
							curtainHeight,
							vineRng:NextNumber(-1, 1) * iceVisual.fangDepthJitter
						),
					-1,
					length,
					iceVisual.fangRootThickness * vineRng:NextNumber(0.75, 1.25),
					iceVisual.fangLevels
				)
			end

			-- SPIKES off the floor, on their own slot count so they land between the fangs rather than
			-- under them. This is what closes the opening without a horizontal rail.
			local spikeSlot = profile.width / (iceVisual.spikeCount + 1)
			for spikeIndex = 1, iceVisual.spikeCount do
				local lateral = (spikeIndex - (iceVisual.spikeCount + 1) / 2) * spikeSlot
				local length = curtainHeight
					* vineRng:NextNumber(iceVisual.spikeMinLengthFraction, iceVisual.spikeMaxLengthFraction)
				icicle(
					doorFrame
						* CFrame.new(
							lateral + vineRng:NextNumber(-1, 1) * spikeSlot * 0.22,
							0,
							vineRng:NextNumber(-1, 1) * iceVisual.fangDepthJitter
						),
					1,
					length,
					iceVisual.spikeRootThickness * vineRng:NextNumber(0.8, 1.3),
					iceVisual.spikeLevels
				)
			end

			-- BLOOM: frost shards over the crust and the fang roots, catching the flame at an angle the
			-- smooth ice behind them does not.
			for _ = 1, iceVisual.bloomCount do
				local size = vineRng:NextNumber(iceVisual.bloomMinSize, iceVisual.bloomMaxSize)
				-- Weighted toward the top, where the crust and the roots actually are.
				local height = curtainHeight * (1 - vineRng:NextNumber(0, 1) ^ 2 * 0.85)
				icePiece(
					"IcicleBloom",
					Vector3.new(size, size * vineRng:NextNumber(0.4, 0.9), size * vineRng:NextNumber(0.5, 1)),
					doorFrame
						* CFrame.new(
							vineRng:NextNumber(-1, 1) * halfWidth * 0.95,
							height,
							vineRng:NextNumber(-1, 1) * (iceVisual.crustDepth * 0.5)
						)
						* CFrame.Angles(
							vineRng:NextNumber(0, math.pi * 2),
							vineRng:NextNumber(0, math.pi * 2),
							vineRng:NextNumber(0, math.pi * 2)
						),
					0.1,
					true
				)
			end

			-- Sorted tips-first so VineService's index-ordered melt reads as ice retreating up the fangs,
			-- with the welded crust the last thing to let go. Equal ranks are left in whatever order the
			-- sort leaves them: pieces at the same depth into the ice are MEANT to go together, so
			-- stability buys nothing here.
			table.sort(ranked, function(a, b)
				return a.rank < b.rank
			end)
			for _, entry in ranked do
				table.insert(strands, entry.part)
			end
		else
			-- A VINE CURTAIN IS A ROOT SYSTEM, NOT A TEXTURED WALL. The retired build hung three ranks
			-- of long cylinders and then stapled three broad LeafyGrass plates to every one. Under the
			-- player's warm point light those overlapping tiled surfaces became the bright rippling sheet
			-- this obstacle is specifically supposed not to be. Build one connected, crooked silhouette:
			-- a root crown entering from the arch, two sparse ranks of segmented hanging roots, short side
			-- branches and a few dead pods. Narrow black gaps survive between the roots, and there is no
			-- large plane on which a material can smear.
			local doorFrame = CFrame.new(Vector3.new(openingCenter.X, groundY, openingCenter.Z))
				* CFrame.Angles(0, if normal.X ~= 0 then -math.pi / 2 else 0, 0)
			local halfWidth = profile.width / 2

			local function doorPoint(x: number, y: number, z: number): Vector3
				return (doorFrame * CFrame.new(x, y, z)).Position
			end

			-- Cylinder length is local +X. Constructing its full basis directly avoids `lookAt`'s
			-- undefined up-vector when a hanging segment is almost perfectly vertical.
			local function rootSegment(
				name: string,
				from: Vector3,
				to: Vector3,
				thickness: number,
				color: Color3,
				material: Enum.Material
			): BasePart?
				local delta = to - from
				if delta.Magnitude <= vineVisual.branchThickness then
					return nil
				end
				local axisX = delta.Unit
				local reference = if math.abs(axisX:Dot(Vector3.yAxis)) < 0.95 then Vector3.yAxis else normal
				local axisZ = axisX:Cross(reference).Unit
				local axisY = axisZ:Cross(axisX).Unit
				local part = Instance.new("Part")
				part.Name = name
				part.Shape = Enum.PartType.Cylinder
				part.Size = Vector3.new(delta.Magnitude + vineVisual.segmentOverlap, thickness, thickness)
				part.CFrame = CFrame.fromMatrix((from + to) / 2, axisX, axisY, axisZ)
				part.Color = color
				part.Material = material
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Parent = curtain
				table.insert(strands, part)
				return part
			end

			local function barkColor(): Color3
				return vineVisual.strandPalette[vineRng:NextInteger(1, #vineVisual.strandPalette)]
			end

			-- The crown is a broken horizontal braid seated into the arch. It gives every hanging root a
			-- visible source and prevents the repeated verticals from reading as bars somebody installed.
			local crownReach = profile.width * vineVisual.lateralOverhangFraction
			local crownLeft = -halfWidth - crownReach
			local crownRight = halfWidth + crownReach
			for rootIndex = 1, vineVisual.archRootCount do
				local t0 = (rootIndex - 1) / vineVisual.archRootCount
				local t1 = rootIndex / vineVisual.archRootCount
				local from = doorPoint(
					crownLeft + (crownRight - crownLeft) * t0,
					curtainHeight + vineRng:NextNumber(-vineVisual.archRootThickness, vineVisual.archRootThickness),
					vineRng:NextNumber(-vineVisual.archRootDepthJitter, vineVisual.archRootDepthJitter)
				)
				local to = doorPoint(
					crownLeft + (crownRight - crownLeft) * t1,
					curtainHeight + vineRng:NextNumber(-vineVisual.archRootThickness, vineVisual.archRootThickness),
					vineRng:NextNumber(-vineVisual.archRootDepthJitter, vineVisual.archRootDepthJitter)
				)
				rootSegment(
					"VineCrown",
					from,
					to,
					vineVisual.archRootThickness
						* vineRng:NextNumber(1 - vineVisual.strandThicknessJitter, 1 + vineVisual.strandThicknessJitter),
					barkColor(),
					vineVisual.strandMaterial
				)
			end

			-- Irregular knots interrupt the crown's line and sell the roots as one old mass grown into the
			-- stone. They use ellipsoids, not flat leaves or random shards, so they retain a clean outline.
			for _ = 1, vineVisual.archKnotCount do
				local size = vineRng:NextNumber(vineVisual.archKnotMinSize, vineVisual.archKnotMaxSize)
				local knot = Instance.new("Part")
				knot.Name = "VineKnot"
				knot.Shape = Enum.PartType.Ball
				knot.Size = Vector3.new(
					size * vineRng:NextNumber(1, 1 + vineVisual.strandThicknessJitter),
					size,
					size * vineRng:NextNumber(1 - vineVisual.strandThicknessJitter, 1)
				)
				knot.CFrame = CFrame.new(
					doorPoint(
						vineRng:NextNumber(crownLeft, crownRight),
						curtainHeight + vineRng:NextNumber(-vineVisual.archRootThickness, vineVisual.archRootThickness),
						vineRng:NextNumber(-vineVisual.archRootDepthJitter, vineVisual.archRootDepthJitter)
					)
				) * CFrame.Angles(
					vineRng:NextNumber(0, math.pi),
					vineRng:NextNumber(0, math.pi),
					vineRng:NextNumber(0, math.pi)
				)
				knot.Color = barkColor()
				knot.Material = vineVisual.strandMaterial
				knot.Anchored = true
				knot.CanCollide = false
				knot.CanQuery = false
				knot.CanTouch = false
				knot.CastShadow = false
				knot.Parent = curtain
				table.insert(strands, knot)
			end

			for layerIndex = 1, vineVisual.layerCount do
				local layerOffset = (layerIndex - (vineVisual.layerCount + 1) / 2) * vineVisual.layerSpacing
				-- Half-slot stagger per layer: the roots close the route as a silhouette without producing
				-- the opaque, z-fighting surface that three leaf-covered layers produced.
				local stagger = ((layerIndex - 1) % 2) * slot / 2
				for strandIndex = 1, vineVisual.strandCount do
					local t = (strandIndex - 0.5) / vineVisual.strandCount
					local lateral = (t - 0.5) * spread
						+ stagger
						+ vineRng:NextNumber(-vineVisual.lateralJitter, vineVisual.lateralJitter)
					local strandLength = curtainHeight
						* vineRng:NextNumber(vineVisual.strandMinLengthFraction, vineVisual.strandMaxLengthFraction)
					local lean = vineRng:NextNumber(-vineVisual.strandLeanStuds, vineVisual.strandLeanStuds)
					local wave = vineRng:NextNumber(-vineVisual.strandWaveStuds, vineVisual.strandWaveStuds)
					local depthWave =
						vineRng:NextNumber(-vineVisual.strandDepthWaveStuds, vineVisual.strandDepthWaveStuds)
					local phase = vineRng:NextNumber(0, math.pi * 2)
					local thickness = vineVisual.strandThickness
						* vineRng:NextNumber(1 - vineVisual.strandThicknessJitter, 1 + vineVisual.strandThicknessJitter)

					local function pointOnRoot(alpha: number): Vector3
						return doorPoint(
							lateral + lean * alpha + math.sin(phase + alpha * math.pi * 2) * wave,
							curtainHeight - strandLength * alpha,
							layerOffset + math.sin(phase + alpha * math.pi) * depthWave
						)
					end

					for segmentIndex = 1, vineVisual.segmentsPerStrand do
						local a = (segmentIndex - 1) / vineVisual.segmentsPerStrand
						local b = segmentIndex / vineVisual.segmentsPerStrand
						rootSegment(
							"VineRoot",
							pointOnRoot(a),
							pointOnRoot(b),
							thickness
								* vineRng:NextNumber(
									1 - vineVisual.strandThicknessJitter,
									1 + vineVisual.strandThicknessJitter
								),
							barkColor(),
							vineVisual.strandMaterial
						)
					end

					-- One or two short branch bones break the repeated hanging rhythm. An occasional matte pod
					-- gives the plant a dry, combustible read without rebuilding the old wall from broad leaves.
					for branchIndex = 1, vineVisual.branchCountPerStrand do
						local alpha = branchIndex / (vineVisual.branchCountPerStrand + 1)
						local branchStart = pointOnRoot(alpha)
						local branchLength = vineRng:NextNumber(vineVisual.branchMinLength, vineVisual.branchMaxLength)
						local branchSide = if vineRng:NextNumber() < 0.5 then -1 else 1
						local branchEnd = branchStart
							+ along * branchLength * branchSide
							+ Vector3.yAxis * vineRng:NextNumber(
								-vineVisual.branchThickness,
								vineVisual.branchThickness
							)
							+ across
								* vineRng:NextNumber(-vineVisual.strandDepthWaveStuds, vineVisual.strandDepthWaveStuds)
						rootSegment(
							"VineBranch",
							branchStart,
							branchEnd,
							vineVisual.branchThickness,
							barkColor(),
							vineVisual.strandMaterial
						)
						if vineRng:NextNumber() < vineVisual.podChancePerBranch then
							local podSize = vineRng:NextNumber(vineVisual.podMinSize, vineVisual.podMaxSize)
							local pod = Instance.new("Part")
							pod.Name = "VineDryPod"
							pod.Shape = Enum.PartType.Ball
							pod.Size = Vector3.new(podSize, podSize * vineVisual.podAspectRatio, podSize)
							pod.Position = branchEnd
							pod.Color = vineVisual.dryTipPalette[vineRng:NextInteger(1, #vineVisual.dryTipPalette)]
							pod.Material = vineVisual.dryTipMaterial
							pod.Anchored = true
							pod.CanCollide = false
							pod.CanQuery = false
							pod.CanTouch = false
							pod.CastShadow = false
							pod.Parent = curtain
							table.insert(strands, pod)
						end
					end
				end
			end

			-- Fire consumes the exposed dry tips first and climbs into the crown. The old insertion order
			-- erased one entire strand at a time from left to right, which looked like parts unloading.
			table.sort(strands, function(a, b)
				return a.Position.Y < b.Position.Y
			end)
		end

		curtain.PrimaryPart = barrier
		curtain.Parent = model
		table.insert(vineRuntimes, {
			model = curtain,
			barrier = barrier,
			strands = strands,
			depth = plan.depth,
			position = Vector3.new(openingCenter.X, groundY + curtainHeight / 2, openingCenter.Z),
			style = placement.style,
			puddleParent = model,
			puddlePosition = Vector3.new(openingCenter.X, groundY + 0.04, openingCenter.Z),
			puddleSize = along * (profile.width + 2) + across * 4 + Vector3.new(0, 0.08, 0),
		})
	end

	-- BLAST DOORS (Config/Dynamite). Real rock wedged into a sealed vault's one doorway, cut from this
	-- cave family's own palette so it reads as part of the wall rather than as an installed object.
	--
	-- THE FACE IS BROKEN INTO MANY SMALL FACETS, not built as a slab, for one reason that matters more
	-- than looks: this is the only rock in the game a player can destroy, so it has to LOOK destructible
	-- before anybody owns dynamite. Packed rubble with visible fracture lines says "this was filled in";
	-- a flat plane says "this is the edge of the map". The charge pocket then says what to do about it.
	local blastDoorRuntimes: { BlastDoorRuntime } = {}
	for _, vault in plan.blastVaults do
		local room = plan.rooms[vault.roomIndex]
		local center = roomCenters[vault.roomIndex]
		local field = groundFields[vault.roomIndex]
		if room == nil or center == nil or field == nil then
			continue
		end
		local dynamiteVisual = Config.Dynamite.visual
		local normal = DOOR_NORMALS[vault.direction]
		local along = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X))
		local across = Vector3.new(math.abs(normal.X), 0, math.abs(normal.Z))
		local profile =
			DoorwayGeometry.profile(room.gridX, room.gridZ, vault.direction, plan.globalDepth, plan.familyId)

		-- Sampled just inside the room where the ground field holds the doorway lane flat, exactly as
		-- the vine curtain does, so the door meets the floor a player walks in on.
		local laneLocal = normal * (g.cellSize / 2 - 4) + along * profile.offset
		local groundY = center.Y + groundOffset(field, laneLocal.X, laneLocal.Z)
		local openingCenter = center + normal * (g.cellSize / 2) + along * profile.offset
		-- THE ARCH, not the doorway rectangle. `buildWall` cuts an opening that rises above
		-- `profile.height`, so a door built to that number leaves a crescent gap along the top. The
		-- vine curtain solves this the same way and for the same reason.
		local doorHeight = profile.height * (1 + dynamiteVisual.doorArchRiseFraction)
		local doorColor = dynamiteVisual.styleColors[vault.style]
		local doorMaterial = dynamiteVisual.styleMaterials[vault.style]
		local crackColor = dynamiteVisual.styleCrackColors[vault.style]

		local door = Instance.new("Model")
		door.Name = "BlastDoor"

		-- ONE invisible part owns blocking, as every other barrier on this floor does. The facets are
		-- collision-neutral, so a break is a presentation problem rather than a physics one.
		local barrier = Instance.new("Part")
		barrier.Name = "BlastDoorBarrier"
		barrier.Size = along * profile.width + across * dynamiteVisual.doorThickness + Vector3.new(0, doorHeight, 0)
		barrier.Position = Vector3.new(openingCenter.X, groundY + doorHeight / 2, openingCenter.Z)
		barrier.Transparency = 1
		barrier.Anchored = true
		barrier.CanCollide = true
		-- The one line that differs from a vine curtain, and it is deliberate. See BlastDoorRuntime.
		barrier.CanQuery = true
		barrier.CanTouch = false
		barrier.CastShadow = false
		barrier.Parent = door

		local pieces: { BasePart } = {}
		local doorRng = Random.new(vault.visualSeed)

		-- The solid plug behind the facets. Slightly inset on every side so the broken face is what a
		-- player sees and this only stops light and sightlines getting through the gaps between facets.
		local plug = newPart(
			along * (profile.width - 0.6)
				+ across * (dynamiteVisual.doorThickness * 0.5)
				+ Vector3.new(0, doorHeight - 0.4, 0),
			Vector3.new(openingCenter.X, groundY + doorHeight / 2, openingCenter.Z),
			doorColor:Lerp(Color3.new(0, 0, 0), 0.25),
			door,
			doorMaterial
		)
		plug.Name = "BlastDoorFill"
		plug.CanCollide = false
		plug.CanQuery = false
		table.insert(pieces, plug)

		-- WHICH WAY THE PLAYER IS STANDING. `normal` runs from the vault's own centre out through its one
		-- doorway, so `+normal` is the approach side — the face anybody who is not already sealed inside
		-- will ever look at. Everything visible below is hung on a FACE using this signed axis.
		--
		-- `across` is the same axis UNSIGNED and is only good for sizing a part's depth. Using it to
		-- offset by is what buried the whole decorated face inside the plug: the rubble, the fracture
		-- lines and the charge pocket were all placed within a stud of the slab's centre, inside 3.2
		-- studs of solid rock, so the door read as a blank wall and the socket could not be seen at all.
		local faceOffset = dynamiteVisual.doorThickness / 2

		-- Packed rubble on BOTH faces. Scattered on a jittered grid so each face reads as filled-in
		-- rather than tiled, and `newJaggedShard` turns each piece so no two catch the flame alike.
		local rockCount = math.max(1, math.floor(dynamiteVisual.doorFaceRocks))
		local columns = math.max(1, math.ceil(math.sqrt(rockCount * profile.width / math.max(doorHeight, 1))))
		local rows = math.max(1, math.ceil(rockCount / columns))
		for _, side in { 1, -1 } do
			for index = 0, rockCount - 1 do
				local column = index % columns
				local row = math.floor(index / columns)
				local u = (column + 0.5) / columns + doorRng:NextNumber(-0.35, 0.35) / columns
				local v = (row + 0.5) / rows + doorRng:NextNumber(-0.35, 0.35) / rows
				local size = doorRng:NextNumber(dynamiteVisual.doorRockMinSize, dynamiteVisual.doorRockMaxSize)
				local lateral = (math.clamp(u, 0.04, 0.96) - 0.5) * profile.width
				local height = math.clamp(v, 0.04, 0.96) * doorHeight
				-- Sunk about a third of its own size into the face, so each chunk protrudes and breaks
				-- the silhouette instead of floating clear of the rock or vanishing inside it.
				local depth = faceOffset - size * doorRng:NextNumber(0.2, 0.4)
				local piece = newJaggedShard(
					"BlastDoorRubble",
					Vector3.new(size, size * doorRng:NextNumber(0.6, 1.1), size * doorRng:NextNumber(0.5, 0.9)),
					Vector3.new(
						openingCenter.X + along.X * lateral + normal.X * depth * side,
						groundY + height,
						openingCenter.Z + along.Z * lateral + normal.Z * depth * side
					),
					doorColor:Lerp(ROCK_COLOR, doorRng:NextNumber(0, 0.3)),
					door,
					doorRng
				)
				-- `newJaggedShard` defaults to the family's rock material; a door is the family's DOOR
				-- material, which for Ice is packed glacier rather than the formation ice.
				piece.Material = doorMaterial
				piece.CanCollide = false
				piece.CanQuery = false
				table.insert(pieces, piece)
			end
		end

		-- THE FRACTURE LINES, on the approach face where they can actually be read. Thin dark seams
		-- across the rock — the geological tell that this particular wall is the breakable one, in the
		-- same language the unstable-dripstone collar uses.
		for index = 1, math.max(0, math.floor(dynamiteVisual.doorCrackCount)) do
			local v = (index - 0.5) / math.max(1, dynamiteVisual.doorCrackCount)
			local crack = newPart(
				along * (profile.width * doorRng:NextNumber(0.45, 0.9))
					+ across * dynamiteVisual.doorCrackThickness
					+ Vector3.new(0, dynamiteVisual.doorCrackThickness, 0),
				Vector3.new(
					openingCenter.X + normal.X * (faceOffset + 0.05),
					groundY + v * doorHeight,
					openingCenter.Z + normal.Z * (faceOffset + 0.05)
				),
				crackColor,
				door,
				doorMaterial
			)
			crack.Name = "BlastDoorFracture"
			-- Tilted after placement: `newPart` positions rather than framing, and a seam that runs dead
			-- level across every door would read as masonry coursing rather than as a fracture.
			crack.CFrame = crack.CFrame * CFrame.Angles(0, 0, doorRng:NextNumber(-0.35, 0.35))
			crack.CanCollide = false
			crack.CanQuery = false
			table.insert(pieces, crack)
		end

		-- THE CHARGE POCKET: a hole bored into the APPROACH face at the offset the planner rolled.
		-- Deliberately a recess rather than a bracket — somebody drilled this face and did not come back.
		local socketLateral = (vault.socketFraction - 0.5) * profile.width
		-- Measured against the DOORWAY height rather than the arched door height, so the pocket stays at
		-- a height a candle can actually reach up to instead of drifting into the arch on a tall opening.
		local socketY = groundY + vault.socketHeightFraction * profile.height
		local pocketDepth = faceOffset - dynamiteVisual.doorSocketDepth / 2
		local pocket = newPart(
			along * 0.75 + across * dynamiteVisual.doorSocketDepth + Vector3.new(0, 1.7, 0),
			Vector3.new(
				openingCenter.X + along.X * socketLateral + normal.X * pocketDepth,
				socketY,
				openingCenter.Z + along.Z * socketLateral + normal.Z * pocketDepth
			),
			Color3.fromRGB(12, 12, 14),
			door,
			Enum.Material.Slate
		)
		pocket.Name = "BlastDoorSocketRecess"
		pocket.CanCollide = false
		pocket.CanQuery = false
		table.insert(pieces, pocket)

		-- The marker anchor sits PROUD of the face, not in the recess. A glowing stick half-sunk into a
		-- hole is exactly as invisible as one buried in the slab was, and this is the one piece of the
		-- door whose entire job is to be seen from across a dark room.
		local socketCenter = Vector3.new(
			openingCenter.X + along.X * socketLateral + normal.X * (faceOffset + dynamiteVisual.socketStandoff),
			socketY,
			openingCenter.Z + along.Z * socketLateral + normal.Z * (faceOffset + dynamiteVisual.socketStandoff)
		)

		local socket = Instance.new("Attachment")
		socket.Name = DynamiteVisualProtocol.socketAttachmentName
		-- Anchored to the BARRIER rather than to a facet: the facets are thrown away when the door
		-- breaks, and the socket has to survive long enough for the break to be reported from it.
		-- PARENT FIRST — `WorldPosition` is resolved against the parent, so writing it on an orphan
		-- attachment silently puts the charge pocket at the world origin.
		socket.Parent = barrier
		socket.WorldPosition = socketCenter

		door.PrimaryPart = barrier
		door:SetAttribute(DynamiteVisualProtocol.attributes.depth, plan.depth)
		door:SetAttribute(DynamiteVisualProtocol.attributes.open, true)
		door:SetAttribute(DynamiteVisualProtocol.attributes.charged, false)
		door:SetAttribute(DynamiteVisualProtocol.attributes.style, vault.style)
		CollectionService:AddTag(door, DynamiteVisualProtocol.doorTag)
		door.Parent = model

		table.insert(blastDoorRuntimes, {
			model = door,
			barrier = barrier,
			pieces = pieces,
			socket = socket,
			depth = plan.depth,
			position = Vector3.new(openingCenter.X, groundY + doorHeight / 2, openingCenter.Z),
			roomIndex = vault.roomIndex,
			style = vault.style,
			openingWidth = profile.width,
			openingHeight = doorHeight,
		})
	end

	-- Ashamed Lurkers. The builder resolves each reserved arch to a floor-centre frame and creates ONE
	-- invisible anchored proxy per creature; AshamedLurkerService moves it between those arches and
	-- every client builds the visible body around it. Nothing here collides or answers a query: the
	-- creature never physically blocks the opening it occupies.
	local lurkerRuntimes: { LurkerRuntime } = {}
	for placementIndex, placement in plan.lurkers do
		local sites: { LurkerSite } = {}
		for _, site in placement.sites do
			local room = plan.rooms[site.roomIndex]
			local center = roomCenters[site.roomIndex]
			local field = groundFields[site.roomIndex]
			if room == nil or center == nil or field == nil then
				continue
			end
			local normal = DOOR_NORMALS[site.direction]
			local along = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X))
			local profile =
				DoorwayGeometry.profile(room.gridX, room.gridZ, site.direction, plan.globalDepth, plan.familyId)
			-- Sampled just inside the room, where the ground field holds the doorway lane flat, so the
			-- root sits on the floor the player actually walks through.
			local laneLocal = normal * (g.cellSize / 2 - 4) + along * profile.offset
			local groundY = center.Y + groundOffset(field, laneLocal.X, laneLocal.Z)
			local laneWorld = center + laneLocal
			local builtGroundY = SurfaceProbe.tryGroundY(groundY, laneWorld.X, laneWorld.Z, 0)
			if builtGroundY ~= nil then
				groundY = builtGroundY
			else
				warn(
					string.format(
						"[FloorBuilder] refused Lurker site at depth %d room %d: doorway lane has no measured Terrain floor",
						plan.depth,
						site.roomIndex
					)
				)
				continue
			end
			local openingCenter = center + normal * (g.cellSize / 2) + along * profile.offset
			local floorCenter = Vector3.new(openingCenter.X, groundY, openingCenter.Z)
			table.insert(sites, {
				cframe = CFrame.lookAt(floorCenter, floorCenter + normal),
				doorWidth = profile.width,
				doorHeight = profile.height,
				trapSide = AshamedLurkerRules.normalizeTrapSide(site.trapSide),
			})
		end
		if #sites == 0 then
			continue
		end

		local proxy = Instance.new("Part")
		proxy.Name = "AshamedLurker" .. placementIndex
		proxy.Size = Vector3.one * 0.5
		proxy.CFrame = sites[1].cframe
		proxy.Transparency = 1
		proxy.Anchored = true
		proxy.CanCollide = false
		proxy.CanQuery = false
		proxy.CanTouch = false
		proxy.CastShadow = false
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.trapSide, sites[1].trapSide)
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.doorWidth, sites[1].doorWidth)
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.doorHeight, sites[1].doorHeight)
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.visualSeed, placement.visualSeed)
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.site, 1)
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.depth, plan.depth)
		-- The cave whose rock this creature's socket and back plates imitate. Written once at build:
		-- a floor never changes family, and a client rebuilding the body after a cull reads it back.
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.familyId, activeFamily.id)
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.stateStartedAt, workspace:GetServerTimeNow())
		proxy:SetAttribute(AshamedLurkerVisualProtocol.attributes.state, AshamedLurkerVisualProtocol.states.dormant)
		proxy.Parent = model
		-- Tagged last: a client must never see a proxy before its attributes exist.
		CollectionService:AddTag(proxy, AshamedLurkerVisualProtocol.tag)

		table.insert(lurkerRuntimes, {
			proxy = proxy,
			sites = sites,
			depth = plan.depth,
		})
	end

	-- Flammable vegetation. Visibly DEAD growth — dry red-starved browns and olives against the living
	-- moss on the walls — because a player has to be able to tell what will burn before they hold a
	-- flame to it. The nodes themselves are collision-neutral dressing; only the optional obstruction
	-- collides, and only until the cluster catches.
	local mossFireRuntimes: { MossFireRuntime } = {}
	local fireVisual = Config.MossFire.visual
	for clusterIndex, cluster in plan.mossFire do
		local center = roomCenters[cluster.roomIndex]
		local field = groundFields[cluster.roomIndex]
		if center == nil or field == nil then
			continue
		end
		local clusterRng = Random.new(cluster.visualSeed)
		local clusterModel = Instance.new("Model")
		clusterModel.Name = "MossFireCluster" .. clusterIndex

		local nodes: { MossFireNodeRuntime } = {}
		for _, node in cluster.nodes do
			local localX, localZ = node.localOffset.X, node.localOffset.Z
			local groundY = center.Y + groundOffset(field, localX, localZ)
			local size = clusterRng:NextNumber(fireVisual.nodeSizeMin, fireVisual.nodeSizeMax)
			local part = Instance.new("Part")
			part.Name = "DryGrowth"
			part.Size =
				Vector3.new(size, size * clusterRng:NextNumber(0.5, 1.1), size * clusterRng:NextNumber(0.7, 1.2))
			part.CFrame = CFrame.new(center.X + localX, groundY + size * 0.35, center.Z + localZ)
				* CFrame.Angles(0, clusterRng:NextNumber(0, math.pi * 2), 0)
			part.Color = fireVisual.strandPalette[clusterRng:NextInteger(1, #fireVisual.strandPalette)]
			part.Material = fireVisual.strandMaterial
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Parent = clusterModel
			table.insert(nodes, { part = part, kindId = node.kindId })
		end

		local obstruction: BasePart? = nil
		if cluster.obstructs and #nodes > 0 then
			local localX, localZ = cluster.localOffset.X, cluster.localOffset.Z
			local groundY = center.Y + groundOffset(field, localX, localZ)
			local barrier = Instance.new("Part")
			barrier.Name = "VegetationObstruction"
			barrier.Size = Vector3.new(
				Config.MossFire.placement.clusterRadius,
				fireVisual.obstructionHeight,
				fireVisual.obstructionThickness
			)
			barrier.CFrame = CFrame.new(
				center.X + localX,
				groundY + fireVisual.obstructionHeight / 2,
				center.Z + localZ
			) * CFrame.Angles(0, clusterRng:NextNumber(0, math.pi * 2), 0)
			barrier.Transparency = 1
			barrier.Anchored = true
			barrier.CanCollide = true
			-- CanQuery false for the same reason a vine barrier is: it stops bodies without becoming an
			-- invisible wall in every AI probe and cast trace.
			barrier.CanQuery = false
			barrier.CanTouch = false
			barrier.CastShadow = false
			barrier.Parent = clusterModel
			obstruction = barrier
		end

		if #nodes == 0 then
			clusterModel:Destroy()
			continue
		end
		clusterModel.PrimaryPart = nodes[1].part
		clusterModel.Parent = model
		table.insert(mossFireRuntimes, {
			model = clusterModel,
			depth = plan.depth,
			position = center + cluster.localOffset,
			nodes = nodes,
			-- Copied from the plan, never re-derived from where the parts ended up.
			edges = cluster.edges,
			obstruction = obstruction,
		})
	end

	-- THE THREE PER-FLOOR FIXTURES (FLOOR-FIXTURES-OVERHAUL). All three are family-styled from one
	-- resolved block, and not one of them changes a rule: the sacrifice pool, the reward formula and
	-- where the way down lives are exactly what they were when these were a flat disc, a grey box and
	-- a floating beacon.
	local fixtureStyle = CaveFamilyRules.fixtureStyle(plan.familyId)

	-- THE BASIN'S CAULDRON, at the room's own centre where the flat wax disc used to lie.
	local basinCenter = roomCenters[plan.basinRoomIndex]
	local cauldron = Cauldron.build(fixtureStyle, basinCenter, rng)
	cauldron.model.Parent = model

	-- THE DESCENT LADDER, on the pad `descentRegion` used to occupy — structurally still the Basin's
	-- room, deliberately kept there rather than given a room type of its own (a separable follow-up if
	-- one chamber holding two fixtures ever stops reading cleanly). The quarter-cell offset and the
	-- flat spot reserved for it in the room loop above are unchanged.
	local descentOrigin = FloorStacking.descentOrigin(plan, g.cellSize)
	local descentCenter = Vector3.new(descentOrigin.X, floorY, descentOrigin.Z)
	local ladderConfig = Config.DescentLadder
	-- The complete shaft was cut before the Terrain-query commit barrier above. Build only its lining
	-- and moving cage here; no later Terrain mutation may invalidate the surface snapshot.
	local ladder =
		DescentLadder.build(fixtureStyle, { color = WALL_COLOR, material = WALL_MATERIAL }, descentCenter, g.floorGap)
	ladder.model.Parent = model
	ladder.cage.Parent = model
	-- The diagnostics overlay counted descent beams; it now counts cages. Same question, same tag,
	-- one object instead of three.
	CollectionService:AddTag(ladder.cage, Config.Diagnostics.descentTag)
	ladder.cage:SetAttribute(ladderConfig.depthAttribute, plan.depth)

	-- THE BRAZIER, on the quarter-cell pad the planner has reserved and flattened for it since before
	-- the fixture existed in this shape (`brazierMask` in Logic/FloorPlanner, and the dressing
	-- reservation in the room loop above). `brazierRoomIndex` resolves to the Basin room, so the
	-- Cauldron, the way down, the fire you cash out at and the lamp that answers the floor all share
	-- one chamber: everything a floor ends with is in one room, and you pick.
	local brazierRoomCenter = roomCenters[plan.brazierRoomIndex]
	local brazierOrigin = brazierRoomCenter + Vector3.new(-g.cellSize / 4, 0, -g.cellSize / 4)
	local brazier = Brazier.build(fixtureStyle, brazierOrigin)
	brazier.model.Parent = model

	-- THE CROWNED LAMP, on this room's chosen wall — where the Gas Lantern used to hang, and using the
	-- identical real-surface probe. It is no longer what ends a run; it is what a player lights to
	-- answer the whole floor for everybody still in it.
	local outward = mainLampNormal
	local install = Config.WallLamp.installation
	local mainGroundField = groundFields[plan.brazierRoomIndex]
	local mainInstallationFloorOffset =
		wallInstallationFloorOffset(mainGroundField, outward, { mainLampOffset }, g.cellSize, g.wallThickness)
	local mainExtent = WallLamp.extent("Main")
	local mainMountY = brazierRoomCenter.Y + mainInstallationFloorOffset + install.mainMountHeight
	local mainMount = wallMountSurface(
		brazierRoomCenter,
		outward,
		mainLampOffset,
		-- Probed across the fixture's real vertical span rather than upward from its base: these lamps
		-- hang from a plate and grow in both directions, so the lowest iron is below the mount point.
		mainMountY - mainExtent.below,
		mainMountY + mainExtent.above,
		g.cellSize,
		g.wallThickness
	)
	local mainSurface = Vector3.new(mainMount.position.X, mainMountY, mainMount.position.Z)
	local mainLamp: WallLamp.BuiltWallLamp? = nil
	if Config.WallLamp.enabled then
		local built = WallLamp.build(fixtureStyle, mainSurface, mainMount.inward, "Main")
		built.model.Parent = model
		mainLamp = built
	end

	-- EVERY OTHER ROOM'S LAMP. One per room, cold, on the same real-surface probe as the crowned one.
	local wallLamps: { WallLamp.BuiltWallLamp } = {}
	local roomExtent = WallLamp.extent("Room")
	for roomIndex, lampPlan in roomLampPlans do
		local roomCenter = roomCenters[roomIndex]
		local roomGroundField = groundFields[roomIndex]
		local lampOutward = lampPlan.normal
		local lampInstallationFloorOffset =
			wallInstallationFloorOffset(roomGroundField, lampOutward, lampPlan.offsets, g.cellSize, g.wallThickness)
		local lampMountY = roomCenter.Y + lampInstallationFloorOffset + install.roomMountHeight
		for _, offset in lampPlan.offsets do
			local mount = wallMountSurface(
				roomCenter,
				lampOutward,
				offset,
				lampMountY - roomExtent.below,
				lampMountY + roomExtent.above,
				g.cellSize,
				g.wallThickness
			)
			local surface = Vector3.new(mount.position.X, lampMountY, mount.position.Z)
			local lamp = WallLamp.build(fixtureStyle, surface, mount.inward, "Room")
			lamp.model.Parent = model
			table.insert(wallLamps, lamp)
		end
	end
	-- CASCADE ORDER, decided here and not at ignition time. Nearest the crowned lamp first, so what a
	-- player somewhere out in the cave hears is the light travelling toward them.
	local cascadeOrigin = if mainLamp ~= nil then (mainLamp :: WallLamp.BuiltWallLamp).flamePosition else brazierOrigin
	table.sort(wallLamps, function(a: WallLamp.BuiltWallLamp, b: WallLamp.BuiltWallLamp): boolean
		local aDistance = (a.flamePosition - cascadeOrigin).Magnitude
		local bDistance = (b.flamePosition - cascadeOrigin).Magnitude
		if aDistance ~= bDistance then
			return aDistance < bDistance
		end
		if a.flamePosition.X ~= b.flamePosition.X then
			return a.flamePosition.X < b.flamePosition.X
		end
		return a.flamePosition.Z < b.flamePosition.Z
	end)

	-- DELIBERATELY LEFT UNPARENTED. The caller owns where a floor lives (RunOrchestrator puts it in
	-- WickFloors), and parenting to `workspace` here only to be reparented a line later inserted every
	-- floor into the world twice — a second registration of a few thousand parts for no gain, and one
	-- frame in which a floor existed outside the folder that teardown destroys.
	return {
		model = model,
		depth = plan.depth,
		entryPosition = roomCenters[plan.entryRoomIndex],
		basinPosition = basinCenter,
		-- Server proximity uses the bowl's rim, the same point the prompt hangs off. Measuring from the
		-- room's base plane would reject a valid activation whenever this room's berm raised the cairn.
		brazier = {
			depth = plan.depth,
			position = brazier.rimPosition,
			built = brazier,
		},
		lamps = {
			depth = plan.depth,
			main = mainLamp,
			lamps = wallLamps,
		},
		ladder = { depth = plan.depth, position = descentCenter, built = ladder },
		roomCenters = roomCenters,
		roomSurfaces = roomSurfaces,
		terrainRegions = terrainRegions,
		waterRegions = waterRegions,
		dripstones = dripstoneRuntimes,
		vines = vineRuntimes,
		blastDoors = blastDoorRuntimes,
		lurkers = lurkerRuntimes,
		mossFire = mossFireRuntimes,
	}
end

return FloorBuilder

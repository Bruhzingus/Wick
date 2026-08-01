--!strict
-- Pure deterministic cave-floor height field shared by planning and construction. Gameplay
-- placement must sample this module rather than reverse-engineering FloorBuilder's Terrain.

local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local Types = require(script.Parent.Parent.Types)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)

export type FlatSpot = { x: number, z: number, r: number }
export type Swell = { x: number, z: number, radius: number, height: number }
export type Pool = { x: number, z: number, radius: number, depth: number }
export type DoorInfo = { offset: number, halfWidth: number }
export type Field = {
	amp: number,
	rippleAmp: number,
	padRadius: number,
	blend: number,
	wallRise: number,
	openRadius: number,
	bermHeight: number,
	maxHeight: number,
	doors: { [Types.Direction]: DoorInfo },
	flatSpots: { FlatSpot },
	swells: { Swell },
	pools: { Pool },
	freq: { number },
	phase: { number },
}

local GroundGeometry = {}

local DOOR_NORMALS: { [Types.Direction]: Vector3 } = {
	N = Vector3.new(0, 0, -1),
	S = Vector3.new(0, 0, 1),
	E = Vector3.new(1, 0, 0),
	W = Vector3.new(-1, 0, 0),
}

local function smoothstep(edge0: number, edge1: number, x: number): number
	if edge1 <= edge0 then
		return if x < edge0 then 0 else 1
	end
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- `familyId` only reaches the doorway profile, which is where a cave family's width bias lives. The
-- height field itself is family-neutral: what a family changes is the SHAPE of the open air (see
-- Logic/RoomFootprint), not how the floor rolls inside it.
function GroundGeometry.fieldFor(
	room: Types.RoomPlacement,
	depth: number,
	openFootprint: boolean,
	flatSpots: { FlatSpot },
	swells: { Swell },
	pools: { Pool },
	familyId: string?
): Field
	local g = FloorsConfig.geometry
	local tuning = FloorsConfig.groundField
	local doors: { [Types.Direction]: DoorInfo } = {}
	for _, direction in room.doorways do
		local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, depth, familyId)
		doors[direction] = {
			offset = profile.offset,
			halfWidth = profile.width / 2 + tuning.doorLaneMargin,
		}
	end

	local seed = math.abs(room.gridX * 40_499 + room.gridZ * 86_969 + depth * 1_300_099) % 2_147_483_647
	local rng = Random.new(seed)
	local span = g.ceilingMaxHeight - g.ceilingMinHeight
	local tallness = if span > 0 then math.clamp((room.ceilingHeight - g.ceilingMinHeight) / span, 0, 1) else 0.5
	local volume = tuning.volumeBase + tallness
	local ampBase = math.clamp(
		tuning.amplitudeBase + depth * tuning.amplitudeDepthStep,
		tuning.amplitudeBase,
		tuning.amplitudeBaseMax
	)
	local amp = math.clamp(
		ampBase * rng:NextNumber(tuning.amplitudeRandomMin, tuning.amplitudeRandomMax) * volume,
		tuning.amplitudeMin,
		tuning.amplitudeMax
	)
	local wallRise = math.clamp(
		rng:NextNumber(tuning.wallRiseRandomMin, tuning.wallRiseRandomMax) * volume,
		tuning.wallRiseMin,
		tuning.wallRiseMax
	)
	local grandeur = if openFootprint
		then 1
		else math.clamp(tallness + rng:NextNumber(-tuning.grandeurJitter, tuning.grandeurJitter), 0, 1)
	local openRadius = tuning.openRadiusMin
		+ (g.cellSize / 2 + tuning.openRadiusEdgePadding - tuning.openRadiusMin) * grandeur
	local encloseCap = math.max(tuning.bermMinimum, room.ceilingHeight - tuning.enclosureHeadroom - amp)
	local bermHeight = encloseCap * (1 - grandeur) + tuning.bermMinimum * grandeur

	return {
		amp = amp,
		rippleAmp = rng:NextNumber(tuning.rippleAmplitudeMin, tuning.rippleAmplitudeMax),
		padRadius = tuning.centerPadRadius,
		blend = tuning.blend,
		wallRise = wallRise,
		openRadius = openRadius,
		bermHeight = bermHeight,
		maxHeight = amp + math.max(wallRise, bermHeight) + tuning.fillHeightPadding,
		doors = doors,
		flatSpots = flatSpots,
		swells = swells,
		pools = pools,
		freq = {
			rng:NextNumber(tuning.longFrequencyMin, tuning.longFrequencyMax),
			rng:NextNumber(tuning.longFrequencyMin, tuning.longFrequencyMax),
			rng:NextNumber(tuning.rippleFrequencyMin, tuning.rippleFrequencyMax),
			rng:NextNumber(tuning.rippleFrequencyMin, tuning.rippleFrequencyMax),
		},
		phase = {
			rng:NextNumber(0, 2 * math.pi),
			rng:NextNumber(0, 2 * math.pi),
			rng:NextNumber(0, 2 * math.pi),
			rng:NextNumber(0, 2 * math.pi),
		},
	}
end

-- Signed height relative to the room's base plane.
function GroundGeometry.offset(field: Field, localX: number, localZ: number): number
	local half = FloorsConfig.geometry.cellSize / 2
	local tuning = FloorsConfig.groundField
	local mask =
		smoothstep(field.padRadius, field.padRadius + field.blend, math.sqrt(localX * localX + localZ * localZ))
	for _, spot in field.flatSpots do
		local dx, dz = localX - spot.x, localZ - spot.z
		mask = math.min(mask, smoothstep(spot.r, spot.r + field.blend, math.sqrt(dx * dx + dz * dz)))
	end
	for direction, door in field.doors do
		local normal = DOOR_NORMALS[direction]
		local toward = localX * normal.X + localZ * normal.Z
		if toward > 0 then
			local lateral = localX * math.abs(normal.Z) + localZ * math.abs(normal.X)
			local laneCentre = door.offset * (toward / half)
			mask =
				math.min(mask, smoothstep(door.halfWidth - field.blend, door.halfWidth, math.abs(lateral - laneCentre)))
		end
	end

	local f, p = field.freq, field.phase
	local big = field.amp * (math.sin(localX * f[1] + p[1]) + math.sin(localZ * f[2] + p[2])) / 2
	local ripple = field.rippleAmp
		* (math.sin((localX + localZ) * f[3] + p[3]) + math.sin((localX - localZ) * f[4] + p[4]))
		/ 2
	local undulation = big + ripple
	local edgeness = math.max(math.abs(localX), math.abs(localZ)) / half
	local wallBerm = field.wallRise * smoothstep(tuning.wallBermStart, 1, edgeness)
	local distCentre = math.sqrt(localX * localX + localZ * localZ)
	local enclose = field.bermHeight
		* smoothstep(field.openRadius, field.openRadius + field.blend * tuning.enclosureBlendMultiplier, distCentre)
	local height = (undulation + math.max(wallBerm, enclose)) * mask

	for _, swell in field.swells do
		local dx, dz = localX - swell.x, localZ - swell.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < swell.radius then
			height = math.max(height, swell.height * (1 - smoothstep(0, swell.radius, distance)) * mask)
		end
	end
	-- Pools carve a FLAT-BOTTOMED bowl, not a cone. The cave floor is realised as Terrain written at
	-- 4-stud voxels, and a conical dip only reaches its full depth at the single centre point — which
	-- almost never coincides with a voxel sample, so the whole pool used to smooth away into the
	-- surrounding rock. A flat inner disc guarantees several samples at the true bed height, and the
	-- remaining rim still slopes gently enough to wade out of.
	for _, pool in field.pools do
		local dx, dz = localX - pool.x, localZ - pool.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance < pool.radius then
			local flatRadius = pool.radius * math.clamp(tuning.poolFlatFraction, 0, 0.95)
			height = math.min(height, -pool.depth * (1 - smoothstep(flatRadius, pool.radius, distance)))
		end
	end
	return height
end

return GroundGeometry

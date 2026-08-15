--!strict
-- Pure deterministic roof relief shared by planning and construction. The planner can decide
-- whether a ceiling is inspectable without asking FloorBuilder, and the builder samples the exact
-- same field while carving the sealed Terrain roof.

local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local Types = require(script.Parent.Parent.Types)

export type Field = {
	maxRelief: number,
	frequencies: { number },
	phases: { number },
}

local RoofGeometry = {}

local function smoothstep(edge0: number, edge1: number, x: number): number
	if edge1 <= edge0 then
		return if x < edge0 then 0 else 1
	end
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

function RoofGeometry.fieldFor(room: Types.RoomPlacement, depth: number): Field
	local geometry = FloorsConfig.geometry
	local roof = FloorsConfig.roof
	local span = geometry.ceilingMaxHeight - geometry.ceilingMinHeight
	local tallness = if span > 0 then math.clamp((room.ceilingHeight - geometry.ceilingMinHeight) / span, 0, 1) else 0.5
	local seed = math.abs(room.gridX * 151_121 + room.gridZ * 313_373 + depth * 1_000_003 + 73) % 2_147_483_647
	local rng = Random.new(seed)

	-- Low crevices keep shallow structure; tall rooms can support a much bolder hanging roof.
	local maxRelief = roof.minRelief
		+ (roof.maxRelief - roof.minRelief)
			* (roof.shortRoomReliefScale + (1 - roof.shortRoomReliefScale) * tallness)

	-- ...AND THEN AGAIN, PROPORTIONALLY TO HOW FAR AWAY THE ROOF ACTUALLY IS.
	--
	-- The lerp above is bounded by `roof.maxRelief`, an ABSOLUTE stud count, and that is what made
	-- tall rooms read as flat slabs. Relief has to survive perspective: a 4.8-stud undulation on a
	-- roof 15 studs over your head is obvious structure, and the identical 4.8 studs on a 46-stud
	-- vault subtends roughly a third of the angle, is three times further from your candle, and
	-- reads as a painted ceiling. Holding the number constant does not hold the LOOK constant.
	--
	-- This is why the Ice family in particular had visibly flat roofs and the other two did not: Ice
	-- is the only family that biases its ceilings tall (`geometry.ceilingPreferred*` 22–46), so it
	-- spent most of its rooms in exactly the band where a fixed relief disappears. The fix is not an
	-- Ice fix — nothing here knows what family it is — it is the general one that family exposed.
	--
	-- Added on top rather than replacing the lerp, and measured from the MINIMUM ceiling, so a room
	-- at the bottom of the range gets exactly the relief it got before and only rooms that are
	-- genuinely far overhead gain any.
	local geometryRange = math.max(room.ceilingHeight - geometry.ceilingMinHeight, 0)
	maxRelief += geometryRange * roof.reliefPerCeilingStud
	return {
		maxRelief = maxRelief,
		frequencies = {
			rng:NextNumber(roof.longFrequencyMin, roof.longFrequencyMax),
			rng:NextNumber(roof.longFrequencyMin, roof.longFrequencyMax),
			rng:NextNumber(roof.rippleFrequencyMin, roof.rippleFrequencyMax),
			rng:NextNumber(roof.rippleFrequencyMin, roof.rippleFrequencyMax),
		},
		phases = {
			rng:NextNumber(0, math.pi * 2),
			rng:NextNumber(0, math.pi * 2),
			rng:NextNumber(0, math.pi * 2),
			rng:NextNumber(0, math.pi * 2),
		},
	}
end

-- Positive studs by which the visible underside hangs below the room's nominal ceiling.
function RoofGeometry.relief(field: Field, localX: number, localZ: number): number
	local geometry = FloorsConfig.geometry
	local roof = FloorsConfig.roof
	local half = geometry.cellSize / 2
	local distanceFromEdge = half - math.max(math.abs(localX), math.abs(localZ))
	local edgeMask = smoothstep(0, roof.edgeBlend, distanceFromEdge)
	if edgeMask <= 0 then
		return 0
	end

	local f = field.frequencies
	local p = field.phases
	local longWave = (math.sin(localX * f[1] + p[1]) + math.sin(localZ * f[2] + p[2]) + 2) / 4
	local ripple = (math.sin((localX + localZ) * f[3] + p[3]) + math.sin((localX - localZ) * f[4] + p[4]) + 2) / 4
	local shaped = (roof.shapeFloorWeight + longWave * roof.longWaveAmplitude + ripple * roof.rippleAmplitude)
		/ (roof.shapeFloorWeight + roof.longWaveAmplitude + roof.rippleAmplitude)
	return math.clamp(field.maxRelief * shaped * edgeMask, 0, field.maxRelief)
end

-- Exact visible underside relative to the room base. The roof joins the wall at its nominal height,
-- while interior samples lift above high floor relief to preserve configured headroom.
function RoofGeometry.undersideHeight(
	ceilingHeight: number,
	field: Field,
	groundHeight: number,
	localX: number,
	localZ: number
): number
	local shapedHeight = ceilingHeight - RoofGeometry.relief(field, localX, localZ)
	local half = FloorsConfig.geometry.cellSize / 2
	if math.max(math.abs(localX), math.abs(localZ)) >= half - FloorsConfig.roof.edgeBlend then
		return shapedHeight
	end
	return math.max(shapedHeight, groundHeight + FloorsConfig.roof.minimumClearance)
end

return RoofGeometry

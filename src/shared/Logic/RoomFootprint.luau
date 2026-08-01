--!strict
-- ROOM FOOTPRINTS — the open interior shape inside a room's cell.
--
-- THE CELL IS UNCHANGED AND STAYS UNCHANGED. The square room cell on the assembly grid still owns
-- room indexing, adjacency, graph connections, overlap prevention, doorway anchors, connector
-- targets and cleanup bounds. Nothing in this module touches any of that. A footprint only decides
-- which part of the INSIDE of that cell is open air and which part is rock, which is why adding
-- shapes cannot break pathing, spawn placement or floor teardown: those all still reason about the
-- cell, and every one of them additionally checks openness through the mask built here.
--
-- GAMEPLAY SAFETY OVERRIDES SHAPE AESTHETICS, always. The final open footprint is
--
--     shape mask
--   OR doorway-lane masks
--   OR navigation-hub mask
--   OR protected interaction masks
--   OR protected player / item / threat spawn masks
--
-- so a shape can never seal a doorway, orphan the hub, or bury a fixture. A shape that would need to
-- is rejected before it is ever recorded (see `roll`), and after a bounded number of rejections the
-- room falls back to Rectangle rather than the rules being relaxed to accommodate it.

local Types = require(script.Parent.Parent.Types)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local CaveFamilyRules = require(script.Parent.CaveFamilyRules)
local DoorwayGeometry = require(script.Parent.DoorwayGeometry)

local RoomFootprint = {}

export type Kind = CaveFamilyRules.RoomShapeKind

-- One room's outer footprint. Pure data, planner-owned, carried on the RoomPlacement so the builder
-- reproduces exactly the shape the planner validated its placements against.
--
-- The fields are shared across kinds rather than split into a union, because every consumer wants
-- one `fieldValue` call and a tagged union would make that a branch at every call site instead of
-- one branch here.
export type Footprint = {
	kind: Kind,
	-- Radians. The whole form is defined in a local frame and rotated into the room.
	rotation: number,
	-- Small bounded offset of the form's centre from the room centre.
	centerX: number,
	centerZ: number,
	-- Primary form half-extents. Rectangle: half width / half depth. Ellipse: X and Z radii.
	-- Capsule: `primaryX` is the half-length of the central segment and `primaryZ` its radius.
	-- TwinLobe: the first lobe's radii.
	primaryX: number,
	primaryZ: number,
	-- TwinLobe only: the second lobe's radii, and the centre-to-centre distance along local X.
	secondaryX: number,
	secondaryZ: number,
	lobeOffset: number,
	-- Boundary irregularity as a fraction of the local radius, plus its phase. Kept small: this is
	-- erosion on a cave wall, not a decorative outline.
	roughness: number,
	roughPhase: number,
}

export type Lane = {
	normalX: number,
	normalZ: number,
	offset: number,
	halfWidth: number,
}

export type Disc = { x: number, z: number, radius: number }

-- The complete open-air description of one room. Rebuilt identically by planner and builder from
-- (room, depth, family), plus whatever protected discs the caller unions in.
export type OpenMask = {
	footprint: Footprint,
	hubRadius: number,
	lanes: { Lane },
	discs: { Disc },
	-- How wide the rock lip is when the BUILDER writes terrain, measured OUTWARD from the boundary.
	-- Purely a construction smoothing width, and deliberately not applied to placement: the lip exists
	-- so the voxel boundary reads as eroded rock rather than a cliff, and because it lies entirely
	-- outside the boundary it costs a room none of the floor a placement may use. Placement uses the
	-- exact boundary (see `isOpen`) and gets its wall clearance from the room-cell check that has
	-- always enforced it.
	blend: number,
	halfCell: number,
}

local ROUGH_LOBES = 5

local function smoothstep(edge0: number, edge1: number, x: number): number
	if edge1 <= edge0 then
		return if x < edge0 then 0 else 1
	end
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- The largest half-extent any footprint may reach. Exactly the radius the pre-family
-- `fitsInsideRoom` used, so a Rectangle at this size is the old full-cell room to the stud.
function RoomFootprint.maximumHalfExtent(): number
	return FloorsConfig.geometry.cellSize / 2 - FloorsConfig.terrain.wallClearance
end

-- The mandatory navigation-lane width. A TwinLobe neck may never be narrower than this, and every
-- doorway lane is at least this wide however tight the opening itself rolled.
function RoomFootprint.requiredLaneWidth(): number
	return FloorsConfig.terrain.doorClearanceWidth
end

-- THE canonical full-cell rectangle. Entry, Basin and completion rooms always use this, and it is
-- also the fallback every rejected shape lands on.
function RoomFootprint.rectangle(): Footprint
	local half = RoomFootprint.maximumHalfExtent()
	return {
		kind = "Rectangle" :: Kind,
		rotation = 0,
		centerX = 0,
		centerZ = 0,
		primaryX = half,
		primaryZ = half,
		secondaryX = 0,
		secondaryZ = 0,
		lobeOffset = 0,
		roughness = 0,
		roughPhase = 0,
	}
end

--------------------------------------------------------------------------------
-- Shape field
--------------------------------------------------------------------------------

-- Radial roughness factor at a local bearing. Multiplies the shape's radius, so the boundary ripples
-- in and out by at most `roughness` of itself and the form stays star-shaped about its own centre —
-- which is what guarantees roughness can never pinch a shape into two pieces.
local function roughFactor(footprint: Footprint, localX: number, localZ: number): number
	if footprint.roughness <= 0 then
		return 1
	end
	local bearing = math.atan2(localZ, localX)
	return 1 + footprint.roughness * math.sin(bearing * ROUGH_LOBES + footprint.roughPhase)
end

local function ellipseField(localX: number, localZ: number, radiusX: number, radiusZ: number): number
	local rx = math.max(radiusX, 0.001)
	local rz = math.max(radiusZ, 0.001)
	local nx, nz = localX / rx, localZ / rz
	return math.sqrt(nx * nx + nz * nz)
end

-- Normalized distance from the form: <= 1 is inside, 1 is the boundary, > 1 is rock. Every kind
-- reduces to this one number so callers never branch on `kind`.
function RoomFootprint.fieldValue(footprint: Footprint, roomX: number, roomZ: number): number
	local dx = roomX - footprint.centerX
	local dz = roomZ - footprint.centerZ
	local cos, sin = math.cos(-footprint.rotation), math.sin(-footprint.rotation)
	local localX = dx * cos - dz * sin
	local localZ = dx * sin + dz * cos
	local rough = roughFactor(footprint, localX, localZ)

	local kind = footprint.kind
	if kind == "Rectangle" then
		local qx = math.abs(localX) / math.max(footprint.primaryX, 0.001)
		local qz = math.abs(localZ) / math.max(footprint.primaryZ, 0.001)
		return math.max(qx, qz) / math.max(rough, 0.05)
	elseif kind == "Ellipse" then
		return ellipseField(localX, localZ, footprint.primaryX, footprint.primaryZ) / math.max(rough, 0.05)
	elseif kind == "Capsule" then
		-- Distance to the central segment, normalized by the capsule radius. The segment runs along
		-- local X, so clamping X into the segment and measuring the remainder gives the rounded ends
		-- for free.
		local clampedX = math.clamp(localX, -footprint.primaryX, footprint.primaryX)
		local ox, oz = localX - clampedX, localZ
		local distance = math.sqrt(ox * ox + oz * oz)
		return distance / math.max(footprint.primaryZ, 0.001) / math.max(rough, 0.05)
	end

	-- TwinLobe: the union of two overlapping ellipses, so the smaller field value wins.
	local half = footprint.lobeOffset / 2
	local first = ellipseField(localX + half, localZ, footprint.primaryX, footprint.primaryZ)
	local second = ellipseField(localX - half, localZ, footprint.secondaryX, footprint.secondaryZ)
	return math.min(first, second) / math.max(rough, 0.05)
end

function RoomFootprint.inside(footprint: Footprint, roomX: number, roomZ: number): boolean
	return RoomFootprint.fieldValue(footprint, roomX, roomZ) <= 1
end

-- Conservative world-axis half-extents, roughness included. Used only for containment.
function RoomFootprint.extents(footprint: Footprint): (number, number)
	local kind = footprint.kind
	local localHalfX, localHalfZ
	if kind == "Rectangle" or kind == "Ellipse" then
		localHalfX, localHalfZ = footprint.primaryX, footprint.primaryZ
	elseif kind == "Capsule" then
		localHalfX, localHalfZ = footprint.primaryX + footprint.primaryZ, footprint.primaryZ
	else
		local half = footprint.lobeOffset / 2
		localHalfX = math.max(half + footprint.primaryX, half + footprint.secondaryX)
		localHalfZ = math.max(footprint.primaryZ, footprint.secondaryZ)
	end
	local scale = 1 + math.max(0, footprint.roughness)
	localHalfX *= scale
	localHalfZ *= scale
	local cos, sin = math.abs(math.cos(footprint.rotation)), math.abs(math.sin(footprint.rotation))
	local worldHalfX = localHalfX * cos + localHalfZ * sin
	local worldHalfZ = localHalfX * sin + localHalfZ * cos
	return math.abs(footprint.centerX) + worldHalfX, math.abs(footprint.centerZ) + worldHalfZ
end

-- Does the whole form fit inside the cell, clear of the structural walls?
function RoomFootprint.isContained(footprint: Footprint, limit: number?): boolean
	local bound = limit or RoomFootprint.maximumHalfExtent()
	local halfX, halfZ = RoomFootprint.extents(footprint)
	return isFiniteNumber(halfX) and isFiniteNumber(halfZ) and halfX <= bound + 1e-6 and halfZ <= bound + 1e-6
end

-- THE narrowest cross-section of a TwinLobe, measured across the span between the two lobe centres.
-- Sampled rather than solved: the union of two unequal ellipses has no tidy closed form for its
-- minimum width, and a fixed sample count keeps this pure and deterministic.
--
-- Every other kind is CONVEX, so it has no neck at all: there is no interior pinch a body could fail
-- to pass through, and its narrowest dimension is just how wide that room is. Those kinds return
-- their own minimum width for diagnostics, and `isValid` deliberately does not hold them to the
-- lane requirement — a slender hall is a legitimate room, and the open mask independently guarantees
-- a full-width navigation hub and full-width doorway lanes inside it either way.
function RoomFootprint.neckWidth(footprint: Footprint): number
	if footprint.kind ~= "TwinLobe" then
		if footprint.kind == "Capsule" then
			return footprint.primaryZ * 2
		end
		return math.min(footprint.primaryX, footprint.primaryZ) * 2
	end

	local half = footprint.lobeOffset / 2
	local samples = 33
	local narrowest = math.huge
	for index = 0, samples - 1 do
		local t = index / (samples - 1)
		local localX = -half + footprint.lobeOffset * t
		-- Half-extent in local Z of each lobe at this X, taking the union (both lobes are centred on
		-- Z = 0, so the union's half-extent is the larger of the two).
		local firstDx = (localX + half) / math.max(footprint.primaryX, 0.001)
		local secondDx = (localX - half) / math.max(footprint.secondaryX, 0.001)
		local firstHalf = if math.abs(firstDx) < 1 then footprint.primaryZ * math.sqrt(1 - firstDx * firstDx) else 0
		local secondHalf = if math.abs(secondDx) < 1
			then footprint.secondaryZ * math.sqrt(1 - secondDx * secondDx)
			else 0
		narrowest = math.min(narrowest, math.max(firstHalf, secondHalf))
	end
	return narrowest * 2
end

-- A footprint is connected when nothing on it can be walked around: every kind but TwinLobe is
-- convex by construction, and a TwinLobe is connected exactly when its neck is a real opening.
function RoomFootprint.isConnected(footprint: Footprint): boolean
	if footprint.kind ~= "TwinLobe" then
		return footprint.primaryX > 0 and footprint.primaryZ > 0
	end
	return RoomFootprint.neckWidth(footprint) > 0
end

-- Every property a footprint must satisfy before it may be recorded on a room.
function RoomFootprint.isValid(footprint: Footprint, requiredNeck: number?): boolean
	if not isFiniteNumber(footprint.primaryX) or not isFiniteNumber(footprint.primaryZ) then
		return false
	end
	if footprint.primaryX <= 0 or footprint.primaryZ <= 0 then
		return false
	end
	if footprint.roughness < 0 or footprint.roughness >= 1 then
		return false
	end
	if not RoomFootprint.isContained(footprint) then
		return false
	end
	if not RoomFootprint.isConnected(footprint) then
		return false
	end
	if footprint.kind ~= "TwinLobe" then
		return true
	end
	local neck = requiredNeck or RoomFootprint.requiredLaneWidth()
	-- `neckWidth` measures the ideal boundary; roughness can pull it in by at most its own fraction,
	-- so the neck has to clear the requirement with that worst case already subtracted.
	return RoomFootprint.neckWidth(footprint) * (1 - footprint.roughness) >= neck
end

--------------------------------------------------------------------------------
-- Open mask
--------------------------------------------------------------------------------

local NORMALS: { [Types.Direction]: { x: number, z: number } } = {
	N = { x = 0, z = -1 },
	S = { x = 0, z = 1 },
	E = { x = 1, z = 0 },
	W = { x = -1, z = 0 },
}

-- The doorway lane, hub and shape for one room. Deterministic from the room, the canonical depth and
-- the family — exactly the inputs GroundGeometry.fieldFor uses, so the flat walking lane the ground
-- field holds open and the open air this mask carves are the same lane by construction.
function RoomFootprint.maskFor(room: Types.RoomPlacement, globalDepth: number, familyId: string?): OpenMask
	local g = FloorsConfig.geometry
	local tuning = FloorsConfig.groundField
	local lanes: { Lane } = {}
	for _, direction in room.doorways do
		local profile = DoorwayGeometry.profile(room.gridX, room.gridZ, direction, globalDepth, familyId)
		local normal = NORMALS[direction]
		table.insert(lanes, {
			normalX = normal.x,
			normalZ = normal.z,
			offset = profile.offset,
			-- At least the mandatory lane width even when the opening itself rolled tighter, so the
			-- walk from the threshold to the hub always fits the largest ground threat.
			halfWidth = math.max(profile.width / 2, RoomFootprint.requiredLaneWidth() / 2) + tuning.doorLaneMargin,
		})
	end
	return {
		footprint = room.footprint or RoomFootprint.rectangle(),
		hubRadius = tuning.centerPadRadius,
		lanes = lanes,
		discs = {},
		blend = tuning.blend,
		halfCell = g.cellSize / 2,
	}
end

-- Reserve a circle of open air. Used for protected interaction zones and every planned spawn, so a
-- shape can never bury one.
function RoomFootprint.reserve(mask: OpenMask, x: number, z: number, radius: number)
	table.insert(mask.discs, { x = x, z = z, radius = math.max(0, radius) })
end

local function laneOpenness(mask: OpenMask, lane: Lane, roomX: number, roomZ: number, blend: number): number
	local toward = roomX * lane.normalX + roomZ * lane.normalZ
	if toward <= 0 then
		return 0
	end
	local lateral = roomX * math.abs(lane.normalZ) + roomZ * math.abs(lane.normalX)
	-- The lane converges from the doorway's own lateral offset at the wall to the room centre,
	-- matching GroundGeometry.offset exactly.
	local laneCentre = lane.offset * (toward / mask.halfCell)
	local distance = math.abs(lateral - laneCentre)
	return 1 - smoothstep(lane.halfWidth, lane.halfWidth + blend, distance)
end

-- 1 = open air, 0 = solid rock, eased across a `blend`-wide band at every boundary. The union is a
-- max: anything any term opens stays open, so the shape can never close a lane, the hub, or a
-- protected disc.
--
-- THE BAND SITS OUTSIDE EVERY BOUNDARY, NEVER INSIDE IT. Each term reaches a full 1 at its own
-- authored edge and only then begins to fall away, so the region a placement is allowed to use is
-- carved as complete air and the eroded lip grows into rock nothing was ever planned in. Easing the
-- band inward instead — which is what this used to do — meant the builder wrote partly-solid Terrain
-- across the outermost `blend` studs of every room, including the canonical full-cell rectangle:
-- deposits and pickups planned against the exact boundary came out buried in that skirt or perched
-- part-way up it, and a reserved disc narrower than the blend (a loot spawn is 1.7 studs against a
-- 7-stud lip) never actually opened any air at all.
local function opennessAt(mask: OpenMask, roomX: number, roomZ: number, blend: number): number
	local footprint = mask.footprint
	-- Convert the blend width from studs into the shape's own normalized units using its smallest
	-- radius, so a tight capsule gets the same physical lip as a broad ellipse.
	local scale = math.max(math.min(footprint.primaryX, footprint.primaryZ), 1)
	local band = math.max(blend / scale, 0)
	local q = RoomFootprint.fieldValue(footprint, roomX, roomZ)
	local best = 1 - smoothstep(1, 1 + band, q)
	if best >= 1 then
		return 1
	end

	local hubDistance = math.sqrt(roomX * roomX + roomZ * roomZ)
	best = math.max(best, 1 - smoothstep(mask.hubRadius, mask.hubRadius + blend, hubDistance))
	if best >= 1 then
		return 1
	end

	for _, lane in mask.lanes do
		best = math.max(best, laneOpenness(mask, lane, roomX, roomZ, blend))
		if best >= 1 then
			return 1
		end
	end

	for _, disc in mask.discs do
		local dx, dz = roomX - disc.x, roomZ - disc.z
		local distance = math.sqrt(dx * dx + dz * dz)
		best = math.max(best, 1 - smoothstep(disc.radius, disc.radius + blend, distance))
		if best >= 1 then
			return 1
		end
	end
	return math.clamp(best, 0, 1)
end

-- CONSTRUCTION openness: what fraction of this column the builder should leave as air. Uses the wide
-- terrain blend so the rock face reads as an eroded lip rather than a voxel cliff.
function RoomFootprint.openness(mask: OpenMask, roomX: number, roomZ: number): number
	return opennessAt(mask, roomX, roomZ, mask.blend)
end

-- PLACEMENT openness: may something stand here? Tested against the EXACT boundary, with no blend at
-- all, so a full-cell rectangle answers precisely the question the pre-family planner asked — "is
-- this inside the room?" — and a Stone floor's placements are unchanged by the existence of shapes.
-- Wall clearance is still enforced, by the room-cell bound the planner checks alongside this.
--
-- This is a STRICTER question than `openness > 0`, and deliberately so: everything inside the exact
-- boundary is carved as complete air (see `opennessAt`), so anything this accepts is a place the
-- built world genuinely has floor and headroom for.
function RoomFootprint.isOpen(mask: OpenMask, roomX: number, roomZ: number): boolean
	return opennessAt(mask, roomX, roomZ, 0) > 0
end

-- Does an axis-aligned gameplay footprint sit entirely in open air? Corners plus centre: a rock lip
-- can bite a corner without covering the centre, and a footprint with a corner in the wall is a
-- placement that will end up embedded.
function RoomFootprint.containsBox(mask: OpenMask, offset: Vector3, size: Vector3): boolean
	local halfX, halfZ = size.X / 2, size.Z / 2
	if not RoomFootprint.isOpen(mask, offset.X, offset.Z) then
		return false
	end
	for _, xSign in { -1, 1 } do
		for _, zSign in { -1, 1 } do
			if not RoomFootprint.isOpen(mask, offset.X + xSign * halfX, offset.Z + zSign * halfZ) then
				return false
			end
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Rolling a shape
--------------------------------------------------------------------------------

export type RollResult = {
	footprint: Footprint,
	-- How many candidate parameter sets were rejected before one was accepted.
	rejections: number,
	-- True when every candidate failed and the room fell back to the canonical rectangle.
	fellBack: boolean,
}

-- How many deterministic parameter sets a room may try before falling back. Centralized here rather
-- than at the call site so every shape everywhere retries the same number of times.
local MAX_ATTEMPTS = 6

-- Shrink a candidate uniformly until it fits the cell. Every linear field scales together, so this
-- preserves the form's proportions, its rotation, and (for a TwinLobe) the RATIO of its neck to its
-- lobes exactly — only the absolute size changes.
--
-- WHY SCALE RATHER THAN REJECT. A rotated ellipse with generous radii does not fit a square cell:
-- at 45 degrees its bounding box is about 1.4x its own axes. Refusing those candidates outright made
-- roughly a third of all rooms fall back to Rectangle, which is not a safety outcome — it is the
-- shape pool quietly not working. Refusal is reserved for the one thing that genuinely cannot be
-- fixed by shrinking: a TwinLobe whose neck is too narrow to walk through, which shrinking makes
-- worse rather than better.
local function fitToCell(footprint: Footprint, limit: number): Footprint
	local halfX, halfZ = RoomFootprint.extents(footprint)
	local worst = math.max(halfX, halfZ)
	if worst <= limit or worst <= 0 then
		return footprint
	end
	local scale = limit / worst
	footprint.primaryX *= scale
	footprint.primaryZ *= scale
	footprint.secondaryX *= scale
	footprint.secondaryZ *= scale
	footprint.lobeOffset *= scale
	footprint.centerX *= scale
	footprint.centerZ *= scale
	return footprint
end

local function candidateFor(kind: Kind, scale: number, rng: Random): Footprint
	local limit = RoomFootprint.maximumHalfExtent()
	-- A family's room-size scale multiplies the FRACTION of the cell a form fills. The ceiling is
	-- above 1 on purpose: `fitToCell` is what enforces containment, so Ice can genuinely ask for
	-- rooms larger than Stone's wherever its rotation leaves room for them.
	local function fraction(low: number, high: number): number
		return limit * math.clamp(rng:NextNumber(low, high) * scale, 0.15, 1.25)
	end

	local rotation = rng:NextNumber(0, math.pi * 2)
	-- A bounded nudge off centre, small enough that the navigation hub is never left outside the
	-- form and large enough that two rooms with the same radii still read differently.
	local offsetLimit = limit * 0.12
	local centerX = rng:NextNumber(-offsetLimit, offsetLimit)
	local centerZ = rng:NextNumber(-offsetLimit, offsetLimit)
	-- Erosion on a cave wall, not a decorative outline. Kept small enough that the worst-case pinch it
	-- can introduce still leaves a TwinLobe's neck above the mandatory lane width.
	local roughness = rng:NextNumber(0.02, 0.05)
	local roughPhase = rng:NextNumber(0, math.pi * 2)

	if kind == "Rectangle" then
		-- The canonical rectangle is axis-aligned, centred and smooth-edged. At scale 1 it is exactly
		-- the pre-family full-cell room, which is what Stone regression is measured against.
		local half = limit * math.clamp(scale, 0.15, 1)
		return {
			kind = kind,
			rotation = 0,
			centerX = 0,
			centerZ = 0,
			primaryX = half,
			primaryZ = half,
			secondaryX = 0,
			secondaryZ = 0,
			lobeOffset = 0,
			roughness = 0,
			roughPhase = 0,
		}
	elseif kind == "Ellipse" then
		return fitToCell({
			kind = kind,
			rotation = rotation,
			centerX = centerX,
			centerZ = centerZ,
			primaryX = fraction(0.78, 1),
			primaryZ = fraction(0.62, 0.95),
			secondaryX = 0,
			secondaryZ = 0,
			lobeOffset = 0,
			roughness = roughness,
			roughPhase = roughPhase,
		}, limit)
	elseif kind == "Capsule" then
		local radius = fraction(0.4, 0.58)
		return fitToCell({
			kind = kind,
			rotation = rotation,
			centerX = centerX,
			centerZ = centerZ,
			primaryX = math.max(limit - radius, radius * 0.35) * rng:NextNumber(0.6, 1),
			primaryZ = radius,
			secondaryX = 0,
			secondaryZ = 0,
			lobeOffset = 0,
			roughness = roughness,
			roughPhase = roughPhase,
		}, limit)
	end

	-- TwinLobe. Both lobes are generous and their centres stay close enough together that the union
	-- has a real waist rather than an isthmus, because the neck check is a hard refusal rather than a
	-- clamp: it is better to reroll a lobe pair than to quietly shrink one until it passes.
	--
	-- `lobeOffset` is the CENTRE-TO-CENTRE distance, so each lobe sits at plus or minus half of it.
	local primaryX = fraction(0.52, 0.68)
	local primaryZ = fraction(0.66, 0.85)
	local secondaryX = fraction(0.46, 0.62)
	local secondaryZ = fraction(0.58, 0.8)
	local lobeOffset = (primaryX + secondaryX) * rng:NextNumber(0.4, 0.62)
	return fitToCell({
		kind = kind,
		rotation = rotation,
		centerX = centerX * 0.5,
		centerZ = centerZ * 0.5,
		primaryX = primaryX,
		primaryZ = primaryZ,
		secondaryX = secondaryX,
		secondaryZ = secondaryZ,
		lobeOffset = lobeOffset,
		roughness = roughness,
		roughPhase = roughPhase,
	}, limit)
end

-- Protected rooms — entry, Basin and completion — are always the canonical rectangle. They carry the
-- expedition's mandatory fixtures and its transition spawn slots, and there is no aesthetic gain
-- worth making any of those a shape-dependent question.
function RoomFootprint.isProtectedShape(
	roomIndex: number,
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number
): boolean
	return roomIndex == entryRoomIndex or roomIndex == basinRoomIndex or roomIndex == brazierRoomIndex
end

-- Roll this room's outer footprint. `shapeRoll` selects the kind from the family's weights (one
-- uniform value, so the kind is pinnable in a test); the parameter sets come from the floor's own
-- seeded stream. Every candidate must be contained, connected, and — for a TwinLobe — leave a neck
-- at least as wide as the mandatory navigation lane. After `MAX_ATTEMPTS` refusals the room takes
-- the canonical rectangle: the count is reduced, never the safety rule.
function RoomFootprint.roll(profile: CaveFamilyRules.CaveFamilyProfile, shapeRoll: number, rng: Random): RollResult
	local kind = CaveFamilyRules.selectShapeKind(profile, shapeRoll)
	local rejections = 0
	for _ = 1, MAX_ATTEMPTS do
		local scale = CaveFamilyRules.rollRoomSizeScale(profile, rng)
		local candidate = candidateFor(kind, scale, rng)
		if RoomFootprint.isValid(candidate) then
			return { footprint = candidate, rejections = rejections, fellBack = false }
		end
		rejections += 1
	end
	return { footprint = RoomFootprint.rectangle(), rejections = rejections, fellBack = true }
end

return RoomFootprint

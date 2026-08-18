--!strict
-- Resolving a PLANNED placement onto the surface the world actually got built with.
--
-- The problem this exists to solve: `Logic/GroundGeometry` describes the cave floor as a continuous
-- analytic field, but the floor a player stands on is voxelized smooth Terrain. Those two disagree
-- by up to a voxel in either direction, which is the difference between an object resting on the
-- ground and an object buried in it. Every gameplay object that sits on the floor — loot pickups,
-- Raw Wax deposits, fixtures, and grounded threats — has to reconcile the two the SAME way, so this
-- is one file rather than a raycast copy-pasted into each service.
--
-- THREE RULES, all learned from things that went wrong:
--
--   1. PROBE FROM NEAR THE PLANNED SURFACE, NOT FROM THE CEILING. A ray cast down from roof height
--      can start inside the roof rock (the roof is irregular relief, not a flat lid), and it can
--      catch a shelf or an overhang thirty studs above the floor. Starting a short way above where
--      the ground was planned finds THIS spot's ground and nothing else.
--   2. ONLY TERRAIN COUNTS AS GROUND. The include filter removes the entire collision-neutral
--      dressing layer — CaveKit formations, dripstones, other pickups, other
--      deposits — so an object can never come to rest on top of scenery, or on top of the object
--      that spawned a moment before it.
--   3. THE SURFACE HAS TO FACE UP. Rule 1 shrinks the window a stray hit can come from, but does not
--      close it: a roof dip or ceiling pocket that happens to sit inside that window is still real
--      Terrain, and would otherwise read as valid ground. `Logic/SurfaceRules` rejects any hit whose
--      normal isn't roughly vertical, so the underside of an overhang can never pass as a floor.
--
-- Water is ignored deliberately: placement rules already keep these objects out of pools, and where
-- a ray does clip a pool edge the meaningful surface is the rock under it, not the surface film.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local RoofGeometry = require(ReplicatedStorage.Shared.Logic.RoofGeometry)
local SurfaceRules = require(ReplicatedStorage.Shared.Logic.SurfaceRules)

local SurfaceProbe = {}

export type RoomGroundSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
	roofField: RoofGeometry.Field,
}

export type ResolveResult = {
	position: Vector3,
	normal: Vector3,
	relocated: boolean,
	emergency: boolean,
	-- `failed` means the exact planned footprint could not be verified against built Terrain. Position
	-- is diagnostic in that case; production callers must refuse it rather than seat an Instance there.
	failed: boolean,
}

type GroundSample = {
	position: Vector3,
	normal: Vector3,
}

local params: RaycastParams? = nil

-- Dynamic callers have no room-local roof field, so use the midpoint of the configured interior open
-- band. Planned room placements use their exact local floor-to-roof gap in `resolveOffset` below.
local function probeLiftStuds(): number
	return SurfaceRules.openBandProbeLift(
		Config.Floors.geometry.placementProbe.upStuds,
		Config.Floors.roof.minimumClearance
	)
end

local function raycastParams(): RaycastParams
	local existing = params
	if existing ~= nil then
		return existing
	end
	local created = RaycastParams.new()
	-- Terrain is the floor. Restricting the query to it prevents a collidable fixture, player, or
	-- previously spawned object from becoming another object's "ground" as population order changes.
	created.FilterType = Enum.RaycastFilterType.Include
	created.FilterDescendantsInstances = { Workspace.Terrain }
	created.IgnoreWater = true
	-- THE important line. Everything decorative in this cave is non-collidable, and none of it is
	-- ground.
	created.RespectCanCollide = true
	params = created
	return created
end

local function sampleGround(plannedY: number, x: number, z: number, requestedLift: number?): GroundSample?
	local probe = Config.Floors.geometry.placementProbe
	local lift = if requestedLift ~= nil then math.max(0, requestedLift) else probeLiftStuds()
	if lift <= 0 then
		return nil
	end
	local origin = Vector3.new(x, plannedY + lift, z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(lift + probe.downStuds), 0), raycastParams())
	if hit == nil then
		return nil
	end
	-- The first solid crossing in the search window is usually the floor, but it can also be the
	-- underside of a roof dip or ceiling pocket the ray happened to pass under first. That surface
	-- faces down, not up, so reject it rather than seat an object in the ceiling.
	if not SurfaceRules.isUpwardFacing(hit.Normal, probe.maxUpwardSlopeDegrees) then
		return nil
	end
	return {
		position = hit.Position,
		normal = hit.Normal.Unit,
	}
end

local function supportOffsets(sampleRadius: number): { Vector2 }
	local radius = math.max(0, sampleRadius)
	if radius <= 0 then
		return {}
	end
	local offsets: { Vector2 } = {}
	for step = 0, 7 do
		local angle = step * math.pi / 4
		table.insert(offsets, Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius))
	end
	return offsets
end

type PlannedHeightAt = (offset: Vector2, centre: GroundSample) -> number
type ProbeLiftAt = (offset: Vector2) -> number?

-- Resolve one built-Terrain surface and prove the whole circular footprint is supported by the same
-- local tangent patch. All eight rays are mandatory. A caller may provide the analytic height at
-- each sample; otherwise (for a moving dynamite stick) the centre tangent predicts a safe local
-- origin without assuming the floor is world-horizontal.
local function tryGroundSurface(
	plannedY: number,
	x: number,
	z: number,
	sampleRadius: number,
	plannedHeightAt: PlannedHeightAt?,
	probeLiftAt: ProbeLiftAt?
): GroundSample?
	local centreLift = if probeLiftAt ~= nil then probeLiftAt(Vector2.zero) else nil
	if probeLiftAt ~= nil and centreLift == nil then
		return nil
	end
	local centre = sampleGround(plannedY, x, z, centreLift)
	if centre == nil then
		return nil
	end

	local offsets = supportOffsets(sampleRadius)
	local peripheral: { SurfaceRules.FootprintSample } = {}
	for _, offset in offsets do
		local localPlannedY: number
		if plannedHeightAt ~= nil then
			localPlannedY = plannedHeightAt(offset, centre)
		else
			local normal = centre.normal
			localPlannedY = centre.position.Y - (normal.X * offset.X + normal.Z * offset.Y) / normal.Y
		end
		local localLift = if probeLiftAt ~= nil then probeLiftAt(offset) else nil
		if probeLiftAt ~= nil and localLift == nil then
			return nil
		end
		local sampled = sampleGround(localPlannedY, x + offset.X, z + offset.Y, localLift)
		if sampled == nil then
			return nil
		end
		table.insert(peripheral, { offset = offset, y = sampled.position.Y })
	end
	local seatY = SurfaceRules.footprintSeatY(
		centre.position.Y,
		centre.normal,
		peripheral,
		#offsets,
		Config.Floors.geometry.placementProbe.maxPeripheralDeltaStuds
	)
	if seatY == nil then
		return nil
	end
	return {
		position = Vector3.new(x, seatY, z),
		normal = centre.normal,
	}
end

-- Public point/footprint query for dynamic objects that do not have a room-local analytic field.
function SurfaceProbe.tryGroundY(plannedY: number, x: number, z: number, sampleRadius: number): number?
	local sample = tryGroundSurface(plannedY, x, z, sampleRadius, nil, nil)
	return if sample ~= nil then sample.position.Y else nil
end

-- Does this footprint clear every analytic pool in the room? The built-Terrain ray intentionally
-- ignores water, so nothing here can tell a pool from the rock under it — the analytic field has to
-- be asked instead at the planner-owned position.
local function isDryOffset(field: GroundGeometry.Field, offset: Vector3, sampleRadius: number): boolean
	for _, pool in field.pools do
		local dx = offset.X - pool.x
		local dz = offset.Z - pool.z
		local dryRadius = pool.radius + sampleRadius
		if dx * dx + dz * dz < dryRadius * dryRadius then
			return false
		end
	end
	return true
end

local function resolveOffset(surface: RoomGroundSurface, offset: Vector3, sampleRadius: number): GroundSample?
	if not isDryOffset(surface.groundField, offset, sampleRadius) then
		return nil
	end
	local x = surface.center.X + offset.X
	local z = surface.center.Z + offset.Z
	local plannedY = surface.center.Y + GroundGeometry.offset(surface.groundField, offset.X, offset.Z)
	local function groundOffsetAt(sampleOffset: Vector2): number
		return GroundGeometry.offset(surface.groundField, offset.X + sampleOffset.X, offset.Z + sampleOffset.Y)
	end
	return tryGroundSurface(plannedY, x, z, sampleRadius, function(sampleOffset: Vector2, _centre: GroundSample): number
		return surface.center.Y + groundOffsetAt(sampleOffset)
	end, function(sampleOffset: Vector2): number?
		local localX = offset.X + sampleOffset.X
		local localZ = offset.Z + sampleOffset.Y
		local groundOffset = groundOffsetAt(sampleOffset)
		local roofOffset =
			RoofGeometry.undersideHeight(surface.ceilingHeight, surface.roofField, groundOffset, localX, localZ)
		return SurfaceRules.plannedProbeLift(
			Config.Floors.geometry.placementProbe.upStuds,
			roofOffset - groundOffset,
			Config.Floors.roof.minimumClearance
		)
	end)
end

local function resolveResult(sample: GroundSample): ResolveResult
	return {
		position = sample.position,
		normal = sample.normal,
		relocated = false,
		emergency = false,
		failed = false,
	}
end

-- Resolve the planner-owned X/Z onto built Terrain without changing it. The planner already proved
-- this footprint open, dry, separated, and off the navigation route, and FloorBuilder carved that
-- exact reservation. Runtime relocation discarded those guarantees and let independent services
-- converge on the same room hub. A missing surface is now an explicit refusal, never permission to
-- invent another position.
function SurfaceProbe.resolvePlannedPosition(
	surface: RoomGroundSurface,
	preferredOffset: Vector3,
	sampleRadius: number
): ResolveResult
	local preferred = resolveOffset(surface, preferredOffset, sampleRadius)
	if preferred ~= nil then
		return resolveResult(preferred)
	end

	local x = surface.center.X + preferredOffset.X
	local z = surface.center.Z + preferredOffset.Z
	local analyticY = surface.center.Y
		+ GroundGeometry.offset(surface.groundField, preferredOffset.X, preferredOffset.Z)
	return {
		-- Diagnostic only. Every production caller refuses `failed`; no Instance may be seated here.
		position = Vector3.new(x, analyticY, z),
		normal = Vector3.yAxis,
		relocated = false,
		emergency = false,
		failed = true,
	}
end

-- Seat a built model on a surface and turn it to face `faceTowards`.
--
-- The contact is measured from the model's real VISIBLE PARTS along the sampled Terrain normal, not
-- from its pivot or from world Y. A builder is free to put its primary part wherever the gameplay
-- query wants it, while the visible silhouette is aligned to the actual tangent plane beneath it.
--
-- `bottomOffset` is the signed distance from that tangent plane: positive lifts, negative sinks.
function SurfaceProbe.seat(
	model: Model,
	surfacePosition: Vector3,
	faceTowards: Vector3,
	bottomOffset: number,
	surfaceNormal: Vector3?
): Vector3
	local normal = if surfaceNormal ~= nil and surfaceNormal.Magnitude > 1e-3 then surfaceNormal.Unit else Vector3.yAxis

	local toward = faceTowards - surfacePosition
	local tangent = toward - normal * toward:Dot(normal)
	if tangent.Magnitude < 1e-3 then
		local reference = if math.abs(normal:Dot(Vector3.zAxis)) < 0.95 then Vector3.zAxis else Vector3.xAxis
		tangent = reference - normal * reference:Dot(normal)
	end
	local rotation = CFrame.lookAt(Vector3.zero, tangent.Unit, normal).Rotation
	local function orient(at: Vector3): CFrame
		return CFrame.new(at) * rotation
	end

	local position = surfacePosition
	model:PivotTo(orient(position))
	-- Fully transparent roots are interaction anchors, not silhouette. Computing the lower extent from
	-- visible parts prevents an arbitrary root size/position from changing how deeply the art sits.
	local lowestPlaneDistance = math.huge
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local frame = descendant.CFrame
			local size = descendant.Size
			local normalHalfExtent = (
				math.abs(frame.RightVector:Dot(normal)) * size.X
				+ math.abs(frame.UpVector:Dot(normal)) * size.Y
				+ math.abs(frame.LookVector:Dot(normal)) * size.Z
			) / 2
			local planeDistance = (frame.Position - surfacePosition):Dot(normal) - normalHalfExtent
			lowestPlaneDistance = math.min(lowestPlaneDistance, planeDistance)
		end
	end
	if lowestPlaneDistance == math.huge then
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		local boundsHalfExtent = (
			math.abs(boundsCFrame.RightVector:Dot(normal)) * boundsSize.X
			+ math.abs(boundsCFrame.UpVector:Dot(normal)) * boundsSize.Y
			+ math.abs(boundsCFrame.LookVector:Dot(normal)) * boundsSize.Z
		) / 2
		lowestPlaneDistance = (boundsCFrame.Position - surfacePosition):Dot(normal) - boundsHalfExtent
	end
	local lift = bottomOffset - lowestPlaneDistance
	if lift ~= 0 then
		-- Moving along the sampled normal also moves X/Z on an incline, leaving the planner's reserved
		-- centre. A world-Y move of lift/normal.Y changes signed plane distance by exactly `lift` while
		-- preserving the authoritative horizontal position.
		position += Vector3.yAxis * (lift / math.max(normal.Y, 1e-4))
		model:PivotTo(orient(position))
	end
	return position
end

-- HOW FAR IS THIS MODEL ACTUALLY OFF THE GROUND? Positive floats, negative is buried, nil means there
-- is no Terrain under it at all.
--
-- Everything above this line reasons about where an object SHOULD go. This measures where one ENDED
-- UP, from its own visible silhouette, and it does not care which service placed it. That
-- independence is the point: every floating-object bug so far has
-- been found by someone noticing one in a screenshot, because the placement code's only self-check
-- was the same probe that had already been fooled. A caller that measures its own result afterwards
-- reports the failure with a room and a number instead.
--
-- Deliberately measured from the model's lowest visible extent rather than its pivot: a builder is
-- free to put its root anywhere, and the gap a player SEES is under the art.
function SurfaceProbe.groundGapStuds(model: Model): number?
	local lowestY = math.huge
	local sumX, sumZ, count = 0, 0, 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local size = descendant.Size
			local frame = descendant.CFrame
			local halfHeight = (
				math.abs(frame.RightVector.Y) * size.X
				+ math.abs(frame.UpVector.Y) * size.Y
				+ math.abs(frame.LookVector.Y) * size.Z
			) / 2
			lowestY = math.min(lowestY, frame.Position.Y - halfHeight)
			sumX += frame.Position.X
			sumZ += frame.Position.Z
			count += 1
		end
	end
	if count == 0 then
		return nil
	end

	local probe = Config.Floors.geometry.placementProbe
	-- Start above the silhouette's base, so a partly buried object still has an origin in open air and
	-- reports how deep it sank rather than reporting nothing.
	local lift = probeLiftStuds()
	local origin = Vector3.new(sumX / count, lowestY + lift, sumZ / count)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(lift + probe.downStuds), 0), raycastParams())
	if hit == nil then
		return nil
	end
	return lowestY - hit.Position.Y
end

return SurfaceProbe

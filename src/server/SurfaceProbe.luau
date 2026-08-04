--!strict
-- Resolving a PLANNED placement onto the surface the world actually got built with.
--
-- The problem this exists to solve: `Logic/GroundGeometry` describes the cave floor as a continuous
-- analytic field, but the floor a player stands on is voxelized smooth Terrain. Those two disagree
-- by up to a voxel in either direction, which is the difference between an object resting on the
-- ground and an object buried in it. Every gameplay object that sits on the floor — loot pickups,
-- Raw Wax deposits — has to reconcile the two the SAME way, so this is one file rather than a
-- raycast copy-pasted into each service.
--
-- TWO RULES, both learned from things that went wrong:
--
--   1. PROBE FROM NEAR THE PLANNED SURFACE, NOT FROM THE CEILING. A ray cast down from roof height
--      can start inside the roof rock (the roof is irregular relief, not a flat lid), and it can
--      catch a shelf or an overhang thirty studs above the floor. Starting a short way above where
--      the ground was planned finds THIS spot's ground and nothing else.
--   2. ONLY TERRAIN COUNTS AS GROUND. The include filter removes the entire collision-neutral
--      dressing layer — CaveKit formations, dripstones, other pickups, other
--      deposits — so an object can never come to rest on top of scenery, or on top of the object
--      that spawned a moment before it.
--
-- Water is ignored deliberately: placement rules already keep these objects out of pools, and where
-- a ray does clip a pool edge the meaningful surface is the rock under it, not the surface film.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)

local SurfaceProbe = {}

export type RoomGroundSurface = {
	center: Vector3,
	groundField: GroundGeometry.Field,
}

export type ResolveResult = {
	position: Vector3,
	relocated: boolean,
	emergency: boolean,
}

local params: RaycastParams? = nil

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

local function sampleGround(plannedY: number, x: number, z: number): number?
	local probe = Config.Floors.geometry.placementProbe
	local origin = Vector3.new(x, plannedY + probe.upStuds, z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(probe.upStuds + probe.downStuds), 0), raycastParams())
	if hit == nil then
		return nil
	end
	return hit.Position.Y
end

-- Resolve a floor-sitting footprint. The centre is authoritative: if it sees no Terrain, this point
-- is not usable. Peripheral samples only raise the seat to clear local voxel humps; a missed sample
-- is ignored instead of silently deleting the whole spawn, and a result far above the centre is a
-- wall/shelf rather than this patch of floor.
function SurfaceProbe.tryGroundY(plannedY: number, x: number, z: number, sampleRadius: number): number?
	local radius = math.max(0, sampleRadius)
	local centre = sampleGround(plannedY, x, z)
	if centre == nil then
		return nil
	end
	if radius <= 0 then
		return centre
	end
	local offsets = {
		Vector2.new(-radius, -radius),
		Vector2.new(-radius, radius),
		Vector2.new(radius, -radius),
		Vector2.new(radius, radius),
		Vector2.new(-radius, 0),
		Vector2.new(radius, 0),
		Vector2.new(0, -radius),
		Vector2.new(0, radius),
	}
	local highest = centre
	local maximumDelta = Config.Floors.geometry.placementProbe.maxPeripheralDeltaStuds
	for _, offset in offsets do
		local sampled = sampleGround(plannedY, x + offset.X, z + offset.Y)
		if sampled ~= nil and math.abs(sampled - centre) <= maximumDelta then
			highest = math.max(highest, sampled)
		end
	end
	return highest
end

local function resolveOffset(surface: RoomGroundSurface, offset: Vector3, sampleRadius: number): Vector3?
	-- The built-Terrain ray intentionally ignores water, so reject the matching analytic pool before
	-- probing. This applies to fallback points too; moving an item inward must never move it underwater.
	for _, pool in surface.groundField.pools do
		local dx = offset.X - pool.x
		local dz = offset.Z - pool.z
		local dryRadius = pool.radius + sampleRadius
		if dx * dx + dz * dz < dryRadius * dryRadius then
			return nil
		end
	end
	local x = surface.center.X + offset.X
	local z = surface.center.Z + offset.Z
	local plannedY = surface.center.Y + GroundGeometry.offset(surface.groundField, offset.X, offset.Z)
	local builtY = SurfaceProbe.tryGroundY(plannedY, x, z, sampleRadius)
	if builtY == nil then
		return nil
	end
	return Vector3.new(x, builtY, z)
end

-- Resolve a deterministic room-local placement onto built Terrain. A failed preferred point moves
-- inward along its original bearing, then checks distinct slots in the guaranteed navigation hub.
-- The final emergency position is lifted above the analytic centre rather than ever being buried;
-- callers expose that exceptional repair through telemetry.
function SurfaceProbe.resolveRoomPosition(
	surface: RoomGroundSurface,
	preferredOffset: Vector3,
	sampleRadius: number,
	fallbackSlot: number
): ResolveResult
	local preferred = resolveOffset(surface, preferredOffset, sampleRadius)
	if preferred ~= nil then
		return { position = preferred, relocated = false, emergency = false }
	end

	local probe = Config.Floors.geometry.placementProbe
	for _, fraction in probe.fallbackFractions do
		local resolved = resolveOffset(surface, preferredOffset * fraction, sampleRadius)
		if resolved ~= nil then
			return { position = resolved, relocated = true, emergency = false }
		end
	end

	local ringSamples = math.max(1, math.floor(probe.fallbackRingSamples))
	local firstSlot = (math.max(1, math.floor(fallbackSlot)) - 1) % ringSamples
	for step = 0, ringSamples - 1 do
		local angle = (firstSlot + step) * math.pi * 2 / ringSamples
		local offset = Vector3.new(
			math.cos(angle) * probe.fallbackRingRadiusStuds,
			0,
			math.sin(angle) * probe.fallbackRingRadiusStuds
		)
		local resolved = resolveOffset(surface, offset, sampleRadius)
		if resolved ~= nil then
			return { position = resolved, relocated = true, emergency = false }
		end
	end

	local centre = resolveOffset(surface, Vector3.zero, sampleRadius)
	if centre ~= nil then
		return { position = centre, relocated = true, emergency = false }
	end

	-- LAST RESORT: the room's own navigation hub, seated on the ANALYTIC floor rather than lifted into
	-- the air above it. The hub is open ground in every footprint by construction and the height field
	-- is flat there (the centre pad masks all relief to zero), so `GroundGeometry.offset` at the centre
	-- is the floor — the same number the planner validated against.
	--
	-- It used to return `surface.center + emergencyLiftStuds` instead. That is where "pickups hovering
	-- in the middle of the room" came from: a probe that found no Terrain — which happens whenever the
	-- ray starts inside a voxel hump rather than because the spot is bad — escalated a benign miss all
	-- the way to a deliberate levitation. Trusting the analytic field is both the safer failure (the
	-- builder writes Terrain from this exact function, so the two agree to within a voxel) and the
	-- honest one: an object at the wrong height by a voxel reads as geology, one floating six studs up
	-- reads as a bug. `emergency` is still reported so telemetry can see the probe gave up.
	return {
		position = surface.center + Vector3.new(0, GroundGeometry.offset(surface.groundField, 0, 0), 0),
		relocated = true,
		emergency = true,
	}
end

-- Resolve a placement that WANTS to stay off the middle of the room.
--
-- `resolveRoomPosition` above escalates toward the room's navigation hub, which is exactly right for
-- something that only has to exist somewhere reachable. It is exactly wrong for a pickup: an item is
-- found by sweeping a candle along the geology, so the repair for "this shelf is voxel rock" should
-- be ANOTHER SHELF, not the centre of the floor.
--
-- So this tries every bearing at the planned radius first, then works inward one ring at a time and
-- never past `minimumRadiusStuds`, and only then hands the problem to the general ladder — which
-- still guarantees a result, so an item that genuinely has nowhere peripheral to go is misplaced
-- rather than lost under the map.
export type PeripheralRing = {
	samples: number,
	rings: number,
	minimumRadiusStuds: number,
}

function SurfaceProbe.resolvePeripheralPosition(
	surface: RoomGroundSurface,
	preferredOffset: Vector3,
	sampleRadius: number,
	fallbackSlot: number,
	ring: PeripheralRing
): ResolveResult
	local preferred = resolveOffset(surface, preferredOffset, sampleRadius)
	if preferred ~= nil then
		return { position = preferred, relocated = false, emergency = false }
	end

	local plannedRadius = Vector3.new(preferredOffset.X, 0, preferredOffset.Z).Magnitude
	local innerRadius = math.min(plannedRadius, math.max(0, ring.minimumRadiusStuds))
	local rings = math.max(1, math.floor(ring.rings))
	local samples = math.max(1, math.floor(ring.samples))
	if plannedRadius > 0.01 then
		-- Start the sweep at the bearing that was actually planned, then walk around from there, so
		-- the repair stays as close to the authored intent as the built Terrain allows. The slot index
		-- rotates the starting direction so two pickups repaired in the same room do not converge.
		local plannedAngle = math.atan2(preferredOffset.Z, preferredOffset.X)
		local slot = math.max(1, math.floor(fallbackSlot)) - 1
		for index = 0, rings - 1 do
			local radius = if rings == 1
				then plannedRadius
				else plannedRadius + (innerRadius - plannedRadius) * (index / (rings - 1))
			for step = 1, samples do
				-- Alternate outward from the planned bearing (+1, -1, +2, -2, ...) rather than sweeping
				-- one way around, so the nearest acceptable shelf wins regardless of which side it is on.
				local half = math.ceil(step / 2)
				local direction = if step % 2 == 0 then -1 else 1
				local angle = plannedAngle + (direction * half + slot) * math.pi * 2 / samples
				local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local resolved = resolveOffset(surface, offset, sampleRadius)
				if resolved ~= nil then
					return { position = resolved, relocated = true, emergency = false }
				end
			end
		end
	end

	return SurfaceProbe.resolveRoomPosition(surface, preferredOffset, sampleRadius, fallbackSlot)
end

-- Seat a built model on a surface and turn it to face `faceTowards`.
--
-- The lift is measured from the model's real VISIBLE PARTS, not from its pivot: a builder is free to
-- put its primary part wherever the gameplay query wants it (a deposit's root is the rock's centre,
-- a pickup's root is an invisible anchor), and neither of those is the bottom of the silhouette. The
-- visible object is what has to rest on the ground.
--
-- `bottomOffset` is where the silhouette's underside ends up relative to `surfaceY`: positive lifts
-- it clear of the ground, negative sinks it in (a boulder shouldered into the floor reads as
-- geology; a boulder balanced on top of it reads as a prop).
function SurfaceProbe.seat(model: Model, surfacePosition: Vector3, faceTowards: Vector3, bottomOffset: number): Vector3
	local function orient(at: Vector3): CFrame
		local target = Vector3.new(faceTowards.X, at.Y, faceTowards.Z)
		-- A model placed exactly on the point it is told to face has no facing to compute; leave it
		-- unrotated rather than handing CFrame.lookAt a zero-length direction.
		if (target - at).Magnitude < 1e-3 then
			return CFrame.new(at)
		end
		return CFrame.lookAt(at, target)
	end

	local position = surfacePosition
	model:PivotTo(orient(position))
	-- Fully transparent roots are interaction anchors, not silhouette. Computing the lower extent from
	-- visible parts prevents an arbitrary root size/position from changing how deeply the art sits.
	local bottomY = math.huge
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local frame = descendant.CFrame
			local size = descendant.Size
			local verticalHalfExtent = (
				math.abs(frame.RightVector.Y) * size.X
				+ math.abs(frame.UpVector.Y) * size.Y
				+ math.abs(frame.LookVector.Y) * size.Z
			) / 2
			bottomY = math.min(bottomY, frame.Position.Y - verticalHalfExtent)
		end
	end
	if bottomY == math.huge then
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		bottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
	end
	local lift = (surfacePosition.Y + bottomOffset) - bottomY
	if lift ~= 0 then
		position += Vector3.new(0, lift, 0)
		model:PivotTo(orient(position))
	end
	return position
end

return SurfaceProbe

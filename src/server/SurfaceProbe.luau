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
local SurfaceRules = require(ReplicatedStorage.Shared.Logic.SurfaceRules)

local SurfaceProbe = {}

-- Roblox writes Terrain on a fixed 4-stud voxel grid, so this is the largest the built floor can
-- disagree with the analytic field it was written from. It is the safety margin the emergency
-- fallback lifts by, not a tunable.
local VOXEL_STUDS = 4

export type RoomGroundSurface = {
	center: Vector3,
	groundField: GroundGeometry.Field,
}

export type ResolveResult = {
	position: Vector3,
	normal: Vector3,
	relocated: boolean,
	emergency: boolean,
	-- No stage of the ladder found real Terrain, so `position` is a manufactured guess rather than a
	-- measured surface. The ladder still returns one — a caller that would rather place an object badly
	-- than not at all keeps working unchanged — but "I could not find the ground" is now something a
	-- caller can READ and refuse, instead of a fact that only ever reached telemetry.
	failed: boolean,
}

type GroundSample = {
	position: Vector3,
	normal: Vector3,
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

local function sampleGround(plannedY: number, x: number, z: number): GroundSample?
	local probe = Config.Floors.geometry.placementProbe
	local origin = Vector3.new(x, plannedY + probe.upStuds, z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(probe.upStuds + probe.downStuds), 0), raycastParams())
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

-- Resolve a floor-sitting footprint. The centre is authoritative: it is both the required hit and
-- the final seat height. Peripheral samples only validate that the footprint is still on this patch
-- of floor. They must never lift the model to the highest nearby voxel, because doing that leaves
-- its centre floating above the surface it visibly occupies.
function SurfaceProbe.tryGroundY(plannedY: number, x: number, z: number, sampleRadius: number): number?
	local radius = math.max(0, sampleRadius)
	local centre = sampleGround(plannedY, x, z)
	if centre == nil then
		return nil
	end
	if radius <= 0 then
		return centre.position.Y
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
	local peripheral: { number } = {}
	local maximumDelta = Config.Floors.geometry.placementProbe.maxPeripheralDeltaStuds
	for _, offset in offsets do
		local sampled = sampleGround(plannedY, x + offset.X, z + offset.Y)
		if sampled ~= nil then
			table.insert(peripheral, sampled.position.Y)
		end
	end
	return SurfaceRules.footprintSeatY(centre.position.Y, peripheral, maximumDelta)
end

local function tryGroundSurface(plannedY: number, x: number, z: number, sampleRadius: number): GroundSample?
	local seatY = SurfaceProbe.tryGroundY(plannedY, x, z, sampleRadius)
	if seatY == nil then
		return nil
	end
	-- Retain the actual centre normal after the same centre and footprint have been validated above.
	-- Height and normal therefore describe one built-Terrain surface, not two placement decisions.
	local centre = sampleGround(plannedY, x, z)
	if centre == nil then
		return nil
	end
	return {
		position = Vector3.new(x, seatY, z),
		normal = centre.normal,
	}
end

-- Does this footprint clear every analytic pool in the room? The built-Terrain ray intentionally
-- ignores water, so nothing here can tell a pool from the rock under it — the analytic field has to
-- be asked instead, and it has to be asked in every place a position is chosen. Moving an item inward
-- must never move it underwater, and neither must the emergency seat that skips the probe entirely.
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
	return tryGroundSurface(plannedY, x, z, sampleRadius)
end

local function resolveResult(sample: GroundSample, relocated: boolean, emergency: boolean): ResolveResult
	return {
		position = sample.position,
		normal = sample.normal,
		relocated = relocated,
		emergency = emergency,
		-- Every path through this helper measured a real upward-facing Terrain hit, whatever ladder rung
		-- produced it. Only the manufactured last resort sets `failed`.
		failed = false,
	}
end

-- WHERE IN THE HUB A GIVEN SLOT SITS — and the hub is a DISC, not a point, which is the whole of why
-- this function exists.
--
-- `GroundGeometry` masks all relief to zero inside `padRadius`, so every point within that disc is
-- the same flat, open, analytically-known floor. The escalation ladder below used to throw that away
-- and aim its last three stages at the exact centre, ignoring `fallbackSlot` entirely — and that cost
-- a real bug. The Stone Warden's rubble pile and its wax tray are two separate placements resolved
-- against one room; the planner keeps them 18 studs apart and can never put them together. But both
-- ran out of ladder, both terminal answers were literally `surface.center`, and the wax spawned
-- inside the Warden.
--
-- So "distinct slot" stopped meaning anything at precisely the point where two objects are most
-- likely to meet: the ring stage above rotates by slot, then every stage after it converged. Every
-- caller that passes a slot — a mining seam's placement index, a loot spawn's index, the Warden's
-- two fixtures — is asking for exactly the guarantee this restores.
--
-- Slot 1 keeps the centre, so a room with one escalating placement lands where it always did. Later
-- slots take a deterministic seat on a ring sized to hold the whole footprint inside the flat pad.
-- Beyond `fallbackRingSamples + 1` distinct slots the seats wrap and can coincide again; that needs
-- ten placements in ONE room to each exhaust the entire ladder, and the result is then no worse than
-- what every slot got before.
--
-- The seat is a room-local offset, NOT a finished position: the caller still probes it like any other
-- candidate, and only falls through to the emergency stages if that probe fails too.
local function hubSeat(field: GroundGeometry.Field, fallbackSlot: number, sampleRadius: number): Vector3
	local seats = math.max(1, math.floor(Config.Floors.geometry.placementProbe.fallbackRingSamples))
	-- Inside the pad and no further: past `padRadius` the field starts blending real relief back in,
	-- and the flatness this seat is chosen for is exactly what stops being true there.
	local radius = math.max(0, field.padRadius - sampleRadius)
	local slot = math.max(1, math.floor(fallbackSlot))

	local function seatAt(index: number): Vector3
		local angle = (index % seats) * math.pi * 2 / seats
		return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	end

	-- Prefer a DRY seat. This feeds the two emergency stages, which are the only placements in this
	-- file that skip `resolveOffset` and so the only ones that can land somewhere its pool guard would
	-- have rejected — and the emergency raycast ignores water, so a seat over a pool comes back seated
	-- on the bed, underwater. Each slot starts at its own seat and walks the ring from there, so
	-- avoiding water costs nothing in distinctness until the whole hub is flooded.
	if slot == 1 and isDryOffset(field, Vector3.zero, sampleRadius) then
		return Vector3.zero
	end
	local first = slot - 2
	for step = 0, seats - 1 do
		local offset = seatAt(first + step)
		if isDryOffset(field, offset, sampleRadius) then
			return offset
		end
	end
	-- Every seat is under water, so there is no dry answer to pick and the only thing left to preserve
	-- is that two slots still differ. Hand back this slot's own seat.
	return if slot == 1 then Vector3.zero else seatAt(first)
end

-- Resolve a deterministic room-local placement onto built Terrain. A failed preferred point moves
-- inward along its original bearing, then checks distinct slots in the guaranteed navigation hub.
-- The final emergency position is lifted above the analytic hub seat rather than ever being buried;
-- callers expose that exceptional repair through telemetry.
function SurfaceProbe.resolveRoomPosition(
	surface: RoomGroundSurface,
	preferredOffset: Vector3,
	sampleRadius: number,
	fallbackSlot: number
): ResolveResult
	local preferred = resolveOffset(surface, preferredOffset, sampleRadius)
	if preferred ~= nil then
		return resolveResult(preferred, false, false)
	end

	local probe = Config.Floors.geometry.placementProbe
	for _, fraction in probe.fallbackFractions do
		local resolved = resolveOffset(surface, preferredOffset * fraction, sampleRadius)
		if resolved ~= nil then
			return resolveResult(resolved, true, false)
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
			return resolveResult(resolved, true, false)
		end
	end

	local hubOffset = hubSeat(surface.groundField, fallbackSlot, sampleRadius)
	local centre = resolveOffset(surface, hubOffset, sampleRadius)
	if centre ~= nil then
		return resolveResult(centre, true, false)
	end

	-- LAST RESORT: the room's own navigation hub. The hub is open ground in every footprint by
	-- construction and the height field is flat there (the centre pad masks all relief to zero), so
	-- `GroundGeometry.offset` anywhere inside it is the analytic floor.
	--
	-- BUT THE ANALYTIC FLOOR IS NOT A SAFE PLACE TO PUT AN OBJECT, and this is what buried pickups.
	-- The two earlier answers were both wrong in opposite directions: `surface.center +
	-- emergencyLiftStuds` levitated things in mid-room, and seating flush on the analytic field sank
	-- them. Terrain is voxelized from that field, so the built floor can stand a voxel ABOVE what the
	-- field says — and an item is barely a stud tall, so "off by a voxel" is not a height error that
	-- reads as geology, it is the item gone: under the floor, invisible, with its prompt inside rock.
	--
	-- So probe once more, properly. Every sample so far started `upStuds` above a PLANNED height, which
	-- is exactly the ray that fails when the real ground has risen over that start point. The hub is
	-- open air for the room's whole height, so a ray dropped from INSIDE that open column crosses the
	-- real floor and nothing else.
	--
	-- "INSIDE THAT OPEN COLUMN" IS THE ENTIRE POINT, and getting it wrong made this stage a bug rather
	-- than a repair. It used to start at `ceilingMaxHeight` (46) above the floor — the global maximum a
	-- room may be built to, not the height of THIS one. Rooms are built anywhere from `ceilingMinHeight`
	-- up to that, with `roof.rockThickness` of solid rock above the underside, so the origin was never
	-- in the open column it assumed:
	--
	--   * A room shorter than `46 - rockThickness` put the origin ABOVE the room's rock slab entirely.
	--     The slab's top face is flat, solid and upward-facing, so the ray hit THAT, passed the slope
	--     check, and seated the object on top of the cave roof — tens of studs up, inside the rock.
	--   * A taller room put the origin INSIDE that slab, where a Terrain raycast reports nothing, so it
	--     fell through to the manufactured seat below.
	--
	-- There was no room height at which it did what it claimed.
	--
	-- The band that IS open air in every room ever built is `roof.minimumClearance`: the roof field is
	-- constrained to stay at least that far above the floor everywhere, whatever the room's nominal
	-- height and whatever relief is under it. Half of it clears the voxel disagreement this stage exists
	-- to defeat while staying well under the lowest roof, so the origin is in open air by construction
	-- rather than by assumption — which is the property the old number quietly lacked.
	--
	-- Reaching less far up than the stages above is deliberate and costs nothing: what makes this stage
	-- succeed where the hub probe just failed is that it asks for a bare centre hit, with none of that
	-- probe's footprint-flatness or pool constraints — not that it looks from higher.
	local hubX = surface.center.X + hubOffset.X
	local hubZ = surface.center.Z + hubOffset.Z
	local analyticY = surface.center.Y + GroundGeometry.offset(surface.groundField, hubOffset.X, hubOffset.Z)
	local dropFrom = math.max(VOXEL_STUDS, Config.Floors.roof.minimumClearance / 2)
	local fromCeiling = Workspace:Raycast(
		Vector3.new(hubX, analyticY + dropFrom, hubZ),
		Vector3.new(0, -(dropFrom + probe.downStuds), 0),
		raycastParams()
	)
	if fromCeiling ~= nil and SurfaceRules.isUpwardFacing(fromCeiling.Normal, probe.maxUpwardSlopeDegrees) then
		return {
			position = Vector3.new(hubX, fromCeiling.Position.Y, hubZ),
			normal = fromCeiling.Normal.Unit,
			relocated = true,
			emergency = true,
			-- Still a measured Terrain surface, just one reached by the exceptional route.
			failed = false,
		}
	end

	-- Even that found nothing, so there is no Terrain answer to be had here and the analytic field is
	-- all that is left. Clear it by one voxel: the builder writes Terrain on a 4-stud grid from this
	-- same field, so a voxel is the whole of the disagreement between them. Erring UP by that much
	-- leaves an object resting at worst a voxel proud of the floor, which reads as a rock it is sitting
	-- on. Erring down by the same amount loses it entirely, and those two costs are not comparable.
	return {
		position = Vector3.new(hubX, analyticY + VOXEL_STUDS, hubZ),
		normal = Vector3.yAxis,
		relocated = true,
		emergency = true,
		-- NOTHING HERE WAS MEASURED. Reaching this line means no ray in the whole ladder found Terrain
		-- under this room, which in a built floor means the room is not where the caller thinks it is.
		-- The position is a deliberate one-voxel float, and a caller that would rather skip the spawn
		-- than hang an object in mid-air can now tell that apart from an ordinary relocation.
		failed = true,
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
		return resolveResult(preferred, false, false)
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
					return resolveResult(resolved, true, false)
				end
			end
		end
	end

	return SurfaceProbe.resolveRoomPosition(surface, preferredOffset, sampleRadius, fallbackSlot)
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

	local function orient(at: Vector3): CFrame
		local toward = faceTowards - at
		local tangent = toward - normal * toward:Dot(normal)
		if tangent.Magnitude < 1e-3 then
			local reference = if math.abs(normal:Dot(Vector3.zAxis)) < 0.95 then Vector3.zAxis else Vector3.xAxis
			tangent = reference - normal * reference:Dot(normal)
		end
		return CFrame.lookAt(at, at + tangent.Unit, normal)
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
		position += normal * lift
		model:PivotTo(orient(position))
	end
	return position
end

-- HOW FAR IS THIS MODEL ACTUALLY OFF THE GROUND? Positive floats, negative is buried, nil means there
-- is no Terrain under it at all.
--
-- Everything above this line reasons about where an object SHOULD go. This measures where one ENDED
-- UP, from its own visible silhouette, and it does not care which service placed it or which rung of
-- which ladder chose the spot. That independence is the point: every floating-object bug so far has
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
	local origin = Vector3.new(sumX / count, lowestY + probe.upStuds, sumZ / count)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(probe.upStuds + probe.downStuds), 0), raycastParams())
	if hit == nil then
		return nil
	end
	return lowestY - hit.Position.Y
end

return SurfaceProbe

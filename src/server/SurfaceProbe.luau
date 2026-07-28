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
--   2. ONLY COLLIDABLE GEOMETRY COUNTS AS GROUND. `RespectCanCollide` filters out the entire
--      collision-neutral dressing layer — CaveKit formations, dripstones, other pickups, other
--      deposits — so an object can never come to rest on top of scenery, or on top of the object
--      that spawned a moment before it.
--
-- Water is ignored deliberately: placement rules already keep these objects out of pools, and where
-- a ray does clip a pool edge the meaningful surface is the rock under it, not the surface film.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local SurfaceProbe = {}

local params: RaycastParams? = nil

local function raycastParams(): RaycastParams
	local existing = params
	if existing ~= nil then
		return existing
	end
	local created = RaycastParams.new()
	created.FilterType = Enum.RaycastFilterType.Exclude
	created.FilterDescendantsInstances = {}
	created.IgnoreWater = true
	-- THE important line. Everything decorative in this cave is non-collidable, and none of it is
	-- ground.
	created.RespectCanCollide = true
	params = created
	return created
end

-- The Y a thing placed at (x, z) should consider "the floor". `plannedY` is the analytic field's
-- answer and is returned unchanged when the probe finds nothing, so a placement is never silently
-- teleported somewhere unrelated because a raycast missed.
function SurfaceProbe.groundY(plannedY: number, x: number, z: number): number
	local probe = Config.Floors.geometry.placementProbe
	local origin = Vector3.new(x, plannedY + probe.upStuds, z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(probe.upStuds + probe.downStuds), 0), raycastParams())
	if hit == nil then
		return plannedY
	end
	return hit.Position.Y
end

-- Seat a built model on a surface and turn it to face `faceTowards`.
--
-- The lift is measured from the model's real BOUNDING BOX, not from its pivot: a builder is free to
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
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local bottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
	local lift = (surfacePosition.Y + bottomOffset) - bottomY
	if lift ~= 0 then
		position += Vector3.new(0, lift, 0)
		model:PivotTo(orient(position))
	end
	return position
end

return SurfaceProbe

--!strict
-- Shared "is this surface floor-like" check. Any raycast that wants to know whether it landed on
-- something an object can rest on — as opposed to a wall, or the underside of an overhang/ceiling —
-- goes through here, so the slope math and its edge cases (zero-length normal, angle wrap) exist
-- exactly once.

local SurfaceRules = {}

-- A vertical normal is flat ground; normals beyond the configured slope (walls, and anything
-- pointing downward like the underside of a shelf or overhang) are rejected.
function SurfaceRules.isUpwardFacing(normal: Vector3, maxSlopeDegrees: number): boolean
	if normal.Magnitude <= 0 then
		return false
	end
	local maximum = math.clamp(maxSlopeDegrees, 0, 90)
	return normal.Unit.Y >= math.cos(math.rad(maximum))
end

-- The centre ray is the point the model is actually seated on. Peripheral rays validate that the
-- footprint still belongs to the same patch of floor; they must never raise the whole model to a
-- nearby voxel hump, which leaves its centre visibly floating above the ground.
function SurfaceRules.footprintSeatY(centreY: number, peripheralY: { number }, maxDeltaStuds: number): number?
	local maximum = math.max(0, maxDeltaStuds)
	for _, sampleY in peripheralY do
		if math.abs(sampleY - centreY) > maximum then
			return nil
		end
	end
	return centreY
end

return SurfaceRules

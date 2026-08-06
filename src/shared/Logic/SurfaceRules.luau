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

return SurfaceRules

--!strict
-- Shared "is this surface floor-like" check. Any raycast that wants to know whether it landed on
-- something an object can rest on — as opposed to a wall, or the underside of an overhang/ceiling —
-- goes through here, so the slope math and its edge cases (zero-length normal, angle wrap) exist
-- exactly once.

local SurfaceRules = {}

export type FootprintSample = {
	offset: Vector2,
	y: number,
}

-- A vertical normal is flat ground; normals beyond the configured slope (walls, and anything
-- pointing downward like the underside of a shelf or overhang) are rejected.
function SurfaceRules.isUpwardFacing(normal: Vector3, maxSlopeDegrees: number): boolean
	if normal.Magnitude <= 0 then
		return false
	end
	local maximum = math.clamp(maxSlopeDegrees, 0, 90)
	return normal.Unit.Y >= math.cos(math.rad(maximum))
end

-- Keep a downward floor ray's origin inside the one air band every legal room guarantees. Half the
-- minimum floor-to-roof clearance is high enough to clear voxelized floor error and cannot cross the
-- matching roof error. The configured value remains a cap for shallower probes.
function SurfaceRules.openBandProbeLift(requestedStuds: number, minimumClearanceStuds: number): number
	local requested = math.max(0, requestedStuds)
	local openBandMidpoint = math.max(0, minimumClearanceStuds / 2)
	return math.min(requested, openBandMidpoint)
end

-- Static planner-owned content may only probe a place that has the game's complete authored
-- headroom. Near the wall/roof join the roof field deliberately stops forcing that clearance, so a
-- globally safe midpoint is not automatically safe there. Refuse such a shelf during planning and,
-- at runtime, derive the origin from this exact local floor-to-roof gap.
function SurfaceRules.plannedProbeLift(
	requestedStuds: number,
	localClearanceStuds: number,
	minimumClearanceStuds: number
): number?
	local minimum = math.max(0, minimumClearanceStuds)
	if localClearanceStuds + 1e-6 < minimum then
		return nil
	end
	return SurfaceRules.openBandProbeLift(requestedStuds, localClearanceStuds)
end

-- A floor footprint belongs to ONE local tangent plane. Comparing every peripheral hit directly to
-- the centre height mistakes an ordinary incline for a cliff: the wider the object, the flatter the
-- old test accidentally required its ground to be. Project each sample onto the centre hit's tangent
-- plane instead. The remaining difference is real curvature, a voxel lip, or another surface.
--
-- `expectedSamples` is explicit because a missing wall-side ray is evidence that the footprint is
-- not fully supported. Silently validating only the rays that happened to hit is how placements at a
-- room edge were accepted with half their model in rock.
function SurfaceRules.footprintSeatY(
	centreY: number,
	centreNormal: Vector3,
	peripheral: { FootprintSample },
	expectedSamples: number,
	maxResidualStuds: number
): number?
	if #peripheral ~= math.max(0, math.floor(expectedSamples)) then
		return nil
	end
	if centreNormal.Magnitude <= 0 then
		return nil
	end
	local normal = centreNormal.Unit
	if normal.Y <= 1e-4 then
		return nil
	end

	local maximum = math.max(0, maxResidualStuds)
	for _, sample in peripheral do
		-- n dot (sample - centre) = 0, solved for the tangent plane's Y at this X/Z.
		local tangentY = centreY - (normal.X * sample.offset.X + normal.Z * sample.offset.Y) / normal.Y
		if math.abs(sample.y - tangentY) > maximum then
			return nil
		end
	end
	return centreY
end

return SurfaceRules

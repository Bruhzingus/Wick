--!strict
-- Pure timing and footprint rules for the one-way between-floor elevator.

local DescentElevatorRules = {}

export type Timeline = {
	landsAt: number,
	pushesAt: number,
	returnsAt: number,
	holdsUntil: number,
	parksAt: number,
}

-- `returnsAt` IS THE EARLIEST THE GATE MAY SHUT, NOT WHEN IT DOES. The caller holds it open past that
-- for as long as anybody is still standing on the deck: a gate that closes on a clock closes through
-- whoever was still walking out of it, which is the one thing this fixture must never do.
--
-- `holdsUntil` is the end of that patience. An arrival cannot wait forever — a rider who is AFK, stuck
-- on geometry or fighting the push would otherwise strand the cage at the bottom and lock the floor's
-- only way down for everybody else — so at this deadline the caller ejects whoever is left and shuts
-- the gate anyway. It is a backstop for a rider who CANNOT leave, not a budget for one who is leaving.
function DescentElevatorRules.timeline(
	startedAt: number,
	rideSeconds: number,
	exitGraceSeconds: number,
	pushSeconds: number,
	returnSeconds: number,
	maxHoldSeconds: number
): Timeline
	local landsAt = startedAt + math.max(rideSeconds, 0)
	local pushesAt = landsAt + math.max(exitGraceSeconds, 0)
	local returnsAt = pushesAt + math.max(pushSeconds, 0)
	return {
		landsAt = landsAt,
		pushesAt = pushesAt,
		returnsAt = returnsAt,
		holdsUntil = returnsAt + math.max(maxHoldSeconds, 0),
		-- The optimistic estimate, for an empty deck. `holdsUntil` can push the real park later, so the
		-- caller rewrites this from the moment the gate actually shuts.
		parksAt = returnsAt + math.max(returnSeconds, 0),
	}
end

-- THE DESCENT CURVE ITSELF, so the one client that draws it and the one server that has to reason
-- about where the cage is at a given instant read it from the same place. A winch eases off its brake,
-- runs, and settles.
function DescentElevatorRules.rideEase(progress: number): number
	local t = math.clamp(progress, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The exact inverse of `rideEase` on [0, 1]: given a fraction of the distance travelled, how much of
-- the ride's time has run. Smoothstep is monotonic across that range, so this is a closed form rather
-- than a search.
function DescentElevatorRules.rideEaseInverse(travelled: number): number
	local y = math.clamp(travelled, 0, 1)
	return 0.5 - math.sin(math.asin(1 - 2 * y) / 3)
end

-- WHEN THE MOUTH MAY BE COVERED, and never one frame before. The cage parks with its deck level with
-- the room floor, so at the instant of departure it is still standing in the hole the hatch covers:
-- throwing the hatch shut then lays a slab through the cage and drags every rider down through it.
-- `clearanceStuds` is how far the cage must fall for its highest point to pass under the closed
-- hatch, and this converts that distance into the time the eased ride takes to cover it.
function DescentElevatorRules.hatchClosesAt(
	startedAt: number,
	rideSeconds: number,
	clearanceStuds: number,
	rideDistance: number
): number
	local duration = math.max(rideSeconds, 0)
	if clearanceStuds <= 0 then
		return startedAt
	end
	if rideDistance <= 0 then
		-- The cage has nowhere to fall, so it never clears. Cover the mouth only once it has landed.
		return startedAt + duration
	end
	local fraction = math.min(clearanceStuds / rideDistance, 1)
	return startedAt + duration * DescentElevatorRules.rideEaseInverse(fraction)
end

-- The same instant on the way back up, where the cage rises into a mouth the hatch is still covering.
-- The return leg runs the curve backwards, so the cage is `clearanceStuds` below the mouth once the
-- ride has all but that fraction of its distance left to travel.
function DescentElevatorRules.hatchOpensAt(
	startedAt: number,
	returnSeconds: number,
	clearanceStuds: number,
	rideDistance: number
): number
	local duration = math.max(returnSeconds, 0)
	if clearanceStuds <= 0 or rideDistance <= 0 then
		return startedAt
	end
	local fraction = math.min(clearanceStuds / rideDistance, 1)
	return startedAt + duration * DescentElevatorRules.rideEaseInverse(1 - fraction)
end

function DescentElevatorRules.isOnDeck(
	cagePivot: CFrame,
	position: Vector3,
	cageWidth: number,
	cageDepth: number,
	verticalTolerance: number
): boolean
	local localPosition = cagePivot:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= math.max(cageWidth, 0) / 2
		and math.abs(localPosition.Z) <= math.max(cageDepth, 0) / 2
		and math.abs(localPosition.Y) <= math.max(verticalTolerance, 0)
end

function DescentElevatorRules.exitDirection(cagePivot: CFrame): Vector3
	local look = cagePivot.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0 then flat.Unit else Vector3.new(0, 0, -1)
end

function DescentElevatorRules.exitPosition(cagePivot: CFrame, lateralOffset: number, forwardStuds: number): Vector3
	local right = cagePivot.RightVector
	local flatRight = Vector3.new(right.X, 0, right.Z)
	local side = if flatRight.Magnitude > 0 then flatRight.Unit else Vector3.new(1, 0, 0)
	return cagePivot.Position
		+ side * lateralOffset
		+ DescentElevatorRules.exitDirection(cagePivot) * math.max(forwardStuds, 0)
end

return DescentElevatorRules

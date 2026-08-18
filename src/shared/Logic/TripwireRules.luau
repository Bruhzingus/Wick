--!strict
-- Pure tripwire rules: whether a step crossed the wire, what that costs in seconds, and what burns it.
--
-- WHY THE CROSSING IS A SEGMENT TEST AND NOT A DISTANCE CHECK. A running player covers 16 studs a
-- second and the server ticks at a fraction of that, so between two consecutive samples they can be a
-- stud in front of the wire and then a stud past it, having never once been NEAR it. A radius check
-- misses exactly the player the trap is built for — the one sprinting through a doorway — and catches
-- the cautious one who edged up to the strand and stopped. So the test is the segment the player
-- actually travelled against the segment the wire actually occupies, and the fast runner is the one
-- who cannot slip through.
--
-- THE HEIGHT TEST IS THE HOP, and it is checked at the same time rather than separately: a wire is
-- cleared by being above it as you cross it, which is what jumping over a rope means.
--
-- Everything here is a pure function of numbers so `Tests/TripwireRulesTests` can prove the two
-- promises the encounter makes — that a hop always clears, and that a faster player is always down
-- for at least as long as a slower one — without a floor, a body or an engine.

local TripwireConfig = require(script.Parent.Parent.Config.Tripwire)
local VineRules = require(script.Parent.VineRules)

local TripwireRules = {}

-- Signed area of the triangle abc, doubled. Positive means c is left of the line a->b. The whole
-- segment test is four of these.
local function cross(ax: number, az: number, bx: number, bz: number, cx: number, cz: number): number
	return (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
end

-- Do the XZ segments `a1->a2` and `b1->b2` cross? Touching counts: a player who stops with their
-- centre exactly on the strand has walked into it.
--
-- COLLINEAR OVERLAP IS DELIBERATELY NOT A CROSSING. A player walking exactly ALONG a wire — down the
-- length of it, inside the doorway — has not run into it, and treating that as a trip would fire the
-- trap on somebody moving parallel to the strand they can see.
function TripwireRules.segmentsCross(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3): boolean
	local d1 = cross(b1.X, b1.Z, b2.X, b2.Z, a1.X, a1.Z)
	local d2 = cross(b1.X, b1.Z, b2.X, b2.Z, a2.X, a2.Z)
	local d3 = cross(a1.X, a1.Z, a2.X, a2.Z, b1.X, b1.Z)
	local d4 = cross(a1.X, a1.Z, a2.X, a2.Z, b2.X, b2.Z)
	if ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0)) then
		return true
	end
	-- One endpoint sitting exactly on the other segment. Only counted when the segments are not
	-- parallel, so travel along the wire is excluded (see above).
	local parallel = math.abs(d3) < 1e-6 and math.abs(d4) < 1e-6
	if parallel then
		return false
	end
	local function onSegment(px: number, pz: number, qx: number, qz: number, rx: number, rz: number): boolean
		return math.min(px, qx) - 1e-6 <= rx
			and rx <= math.max(px, qx) + 1e-6
			and math.min(pz, qz) - 1e-6 <= rz
			and rz <= math.max(pz, qz) + 1e-6
	end
	if math.abs(d1) < 1e-6 and onSegment(b1.X, b1.Z, b2.X, b2.Z, a1.X, a1.Z) then
		return true
	end
	if math.abs(d2) < 1e-6 and onSegment(b1.X, b1.Z, b2.X, b2.Z, a2.X, a2.Z) then
		return true
	end
	if math.abs(d3) < 1e-6 and onSegment(a1.X, a1.Z, a2.X, a2.Z, b1.X, b1.Z) then
		return true
	end
	if math.abs(d4) < 1e-6 and onSegment(a1.X, a1.Z, a2.X, a2.Z, b2.X, b2.Z) then
		return true
	end
	return false
end

-- HOW LONG YOU ARE DOWN, from how fast you hit it. Linear between the two speeds, clamped at both
-- ends, so the relationship a player can feel — go faster, fall harder — holds everywhere in the band
-- rather than only at the extremes.
function TripwireRules.stunSeconds(speed: number): number
	local trip = TripwireConfig.trip
	local floorSpeed = math.max(trip.minimumTripSpeed, 0)
	local ceilingSpeed = math.max(trip.fullStunSpeed, floorSpeed + 1e-6)
	local fraction = math.clamp((speed - floorSpeed) / (ceilingSpeed - floorSpeed), 0, 1)
	return trip.minStunSeconds + (trip.maxStunSeconds - trip.minStunSeconds) * fraction
end

export type TripQuery = {
	-- Where the player's FEET were and are. Both ends of the step, because the crossing is a segment.
	previousFoot: Vector3,
	currentFoot: Vector3,
	-- The wire's two anchor points, at wire height.
	anchorA: Vector3,
	anchorB: Vector3,
	-- Measured horizontal speed (server/CharacterService.horizontalSpeed), never a client claim.
	speed: number,
	-- Whether the engine says this body has nothing under its feet. A jump is an airborne body, and
	-- this is the authoritative read the game already uses for landing noises.
	airborne: boolean,
}

-- DOES THIS STEP TRIP THE WIRE? Three independent ways to not be caught, in the order a player would
-- describe them: you were not moving fast enough to run into anything, your feet were over it, or you
-- never crossed it.
function TripwireRules.trips(query: TripQuery): boolean
	local trip = TripwireConfig.trip
	if query.speed < trip.minimumTripSpeed then
		return false
	end
	-- OVER IT. The height is taken from the lower of the two samples: a player already descending from
	-- a hop has cleared the wire if their feet were above it for the crossing, and taking the lower
	-- sample is what makes a landing ON the wire still count as landing on it.
	local wireY = math.max(query.anchorA.Y, query.anchorB.Y)
	local footY = math.min(query.previousFoot.Y, query.currentFoot.Y)
	if query.airborne and footY > wireY + trip.hopClearanceStuds then
		return false
	end
	return TripwireRules.segmentsCross(query.previousFoot, query.currentFoot, query.anchorA, query.anchorB)
end

-- IS THIS FLAME BURNING THE STRAND RIGHT NOW? Deliberately delegated rather than re-derived: a vine
-- curtain and a tripwire are the same growth answering to the same dial, and a player who has learned
-- what clears one has learned what clears the other. Only the EXPOSURE differs (Config/Tripwire.burn).
function TripwireRules.burns(
	isLit: boolean,
	isCupping: boolean,
	burnRate: number,
	isFlaring: boolean,
	maxBurnRate: number?
): boolean
	return VineRules.burnsVines(isLit, isCupping, burnRate, isFlaring, maxBurnRate)
end

-- Is this player close enough to the strand for their light to be working on it? Flat distance: a
-- doorway is a doorway whatever height the floor is at either side of it.
function TripwireRules.withinBurnRange(playerPosition: Vector3, wireCenter: Vector3): boolean
	local delta = playerPosition - wireCenter
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= TripwireConfig.burn.radiusStuds
end

-- The strand's sag, sampled along its span. `t` runs 0..1 between the anchors and the result is how
-- far BELOW the straight line the strand hangs there — zero at both ends, deepest in the middle.
-- Shared by the builder that draws the wire and by nothing else today; it is here rather than in the
-- service so the drawn shape and any future collision against it cannot drift apart.
function TripwireRules.sagAt(t: number, spanStuds: number): number
	local clamped = math.clamp(t, 0, 1)
	return math.sin(clamped * math.pi) * spanStuds * TripwireConfig.geometry.sagFraction
end

return TripwireRules

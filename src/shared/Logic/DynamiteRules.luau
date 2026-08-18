--!strict
-- Pure: everything dynamite decides, with no Instances and no services anywhere near it.
--
-- Four separable questions live here, and keeping them in one file is deliberate — they are the whole
-- item, and a reader who wants to know what dynamite does should be able to read it in one sitting:
--
--   1. THE BAG. How many sticks a player may hold, and what taking or spending one leaves behind.
--   2. THE SCHEDULE. Which floors the cave puts a stick or a crate on, as a deterministic walk rather
--      than a per-floor coin flip.
--   3. THE BLAST. What distance from the centre is worth, to a candle and to a body.
--   4. THE DOOR. Whether a stick that came to rest somewhere is close enough to break one.
--
-- Nothing here reads the clock, rolls a die, or touches a player. `server/DynamiteService` owns all
-- three of those and calls into this for every answer.

local Types = require(script.Parent.Parent.Types)
local DynamiteConfig = require(script.Parent.Parent.Config.Dynamite)

local DynamiteRules = {}

export type Supply = {
	sticks: number,
	crates: number,
	-- Total charges this floor should hand out. `sticks + crates * crateCharges`, resolved here so a
	-- caller never has to know a crate is worth more than one.
	charges: number,
}

export type Denial = "Disabled" | "Dead" | "NotLit" | "Empty" | "InvalidTarget" | "AlreadyPlaced" | "AlreadyLit"

--------------------------------------------------------------------------------
-- 1. The bag
--------------------------------------------------------------------------------

local function sanitizeCount(count: number?): number
	local value = count or 0
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

function DynamiteRules.carried(state: Types.PlayerRunState): number
	return sanitizeCount(state.dynamiteCharges)
end

-- What the bag looks like after finding `amount` sticks, and how many of them actually fitted. The
-- overflow is REPORTED rather than silently dropped, so the pickup message can tell a full player that
-- a crate they just opened was mostly wasted — which is the moment the carry cap is supposed to teach.
function DynamiteRules.grant(carried: number, amount: number): (number, number)
	local cap = math.max(0, math.floor(DynamiteConfig.supply.maxCarried))
	local current = sanitizeCount(carried)
	local wanted = math.max(0, math.floor(amount))
	local next_ = math.min(cap, current + wanted)
	return next_, next_ - current
end

function DynamiteRules.spend(carried: number): number?
	local current = sanitizeCount(carried)
	if current <= 0 then
		return nil
	end
	return current - 1
end

-- May this player arm a stick right now? Deliberately NOT a copy of `ToolRules.validate`: dynamite has
-- no cooldown, no wax price and no sacrifice that can remove it, so the only questions left are
-- whether the candle is in a state to act and whether there is a stick in the bag.
--
-- IT REQUIRES A LIT FLAME. Not for balance — you light the fuse FROM your own flame, and a snuffed
-- candle has nothing to light it with. This is the same reason mining requires a lit flame.
function DynamiteRules.validate(state: Types.PlayerRunState): (boolean, Denial?)
	if not DynamiteConfig.enabled then
		return false, "Disabled"
	end
	if not state.alive or state.finished or state.snuffedAt ~= nil then
		return false, "Dead"
	end
	if not state.isLit then
		return false, "NotLit"
	end
	if DynamiteRules.carried(state) <= 0 then
		return false, "Empty"
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- 2. The schedule
--------------------------------------------------------------------------------

-- Fold a salt into a seed. Keeps the stick stream and the crate stream from being the same sequence
-- read at two speeds, which would put every crate on a stick floor.
local function saltedSeed(runSeed: number, salt: number): number
	local base = math.abs(math.floor(if runSeed == runSeed then runSeed else 0)) % 2_147_483_647
	return (base * 31 + salt * 7919) % 2_147_483_647
end

-- Does the "every min..max floors" schedule land exactly on `globalDepth`?
--
-- WHY A WALK AND NOT A PER-FLOOR CHANCE. A 50% roll per floor has the right average and the wrong
-- shape: it produces five-floor droughts often enough that a player cannot form the expectation the
-- item depends on. Walking the gaps from a run seed gives a real "every one to three floors" — the
-- player never knows WHICH floor, but the cave keeps its side of the bargain.
--
-- Pure and stateless: floors are planned independently and out of order, so this must be answerable
-- for floor 9 without floor 8 ever having been planned. Cost is O(depth / minGap), which is why the
-- iteration cap exists at all — an expedition has no floor cap.
local function scheduleLandsOn(
	runSeed: number,
	globalDepth: number,
	salt: number,
	firstDepth: number,
	minGap: number,
	maxGap: number
): boolean
	local low = math.max(1, math.floor(minGap))
	local high = math.max(low, math.floor(maxGap))
	local start = math.max(1, math.floor(firstDepth))
	local target = math.floor(globalDepth)
	if target < start then
		return false
	end
	local rng = Random.new(saltedSeed(runSeed, salt))
	local depth = start
	local iterations = 0
	local cap = math.max(1, math.floor(DynamiteConfig.supply.scheduleIterationCap))
	while depth < target do
		iterations += 1
		if iterations > cap then
			return false
		end
		depth += rng:NextInteger(low, high)
	end
	return depth == target
end

-- What this floor hands out. Both streams are independent, so a floor can carry a stick and a crate;
-- that is rare, intended, and the best floor in a long run.
function DynamiteRules.supplyForDepth(runSeed: number, globalDepth: number): Supply
	if not DynamiteConfig.enabled then
		return { sticks = 0, crates = 0, charges = 0 }
	end
	local supply = DynamiteConfig.supply
	local sticks = if scheduleLandsOn(
			runSeed,
			globalDepth,
			1,
			supply.stickFirstDepth,
			supply.stickMinGap,
			supply.stickMaxGap
		)
		then 1
		else 0
	local crates = if scheduleLandsOn(
			runSeed,
			globalDepth,
			2,
			supply.crateFirstDepth,
			supply.crateMinGap,
			supply.crateMaxGap
		)
		then 1
		else 0
	return {
		sticks = sticks,
		crates = crates,
		charges = sticks + crates * math.max(1, math.floor(supply.crateCharges)),
	}
end

--------------------------------------------------------------------------------
-- 3. The blast
--------------------------------------------------------------------------------

-- Linear falloff to nothing at the edge, matching `MiningRules.blastWaxCost` exactly. The two
-- explosions in this game must not fall off differently: a player learns one distance instinct and it
-- has to be correct for both.
local function falloff(distance: number): number
	local radius = math.max(DynamiteConfig.blast.radius, 0.0001)
	return math.clamp(1 - math.max(0, distance) / radius, 0, 1)
end

function DynamiteRules.blastFalloff(distance: number): number
	return falloff(distance)
end

-- Wax removed from a candle at this distance. Below the configured floor it returns zero rather than a
-- rounding smear, so a player at the far edge is not told they were hurt when they were not.
function DynamiteRules.blastWaxCost(distance: number): number
	local cost = DynamiteConfig.blast.playerWaxCost * falloff(distance)
	if cost < DynamiteConfig.blast.minimumWaxCost then
		return 0
	end
	return cost
end

-- Blast damage dealt to a BODY at this distance. Point blank is exactly 1.0, which is what makes
-- `BlastProfile.hitPoints` readable as "sticks at point blank" wherever it appears.
function DynamiteRules.blastDamage(distance: number): number
	return falloff(distance)
end

function DynamiteRules.profileFor(def: Types.ThreatDef?): Types.BlastProfile
	local profile = if def ~= nil then def.blast else nil
	if profile ~= nil then
		return profile
	end
	return DynamiteConfig.threat.default
end

-- Does `accumulated + incoming` finish this body off? Damage accumulates and never decays, so a
-- creature that survived one stick is cheaper to remove with the next.
function DynamiteRules.isLethal(accumulated: number, incoming: number, profile: Types.BlastProfile): boolean
	local hitPoints = math.max(profile.hitPoints, 0.0001)
	return math.max(0, accumulated) + math.max(0, incoming) >= hitPoints
end

--------------------------------------------------------------------------------
-- 4. The throw
--------------------------------------------------------------------------------

-- A REAL THROW, not a fixed-distance placement.
--
-- What this replaces: the old solver flattened the aim to horizontal and always resolved to exactly
-- `range` studs, so a stick thrown at the ceiling and a stick thrown at the floor landed in the same
-- spot. Pitch did nothing, and the one input a player naturally reaches for did not exist.
--
-- The model is ordinary projectile motion with one authored constant: `range` is the distance a throw
-- covers at the IDEAL 45-degree launch, which for a projectile landing at its launch height is
--
--     R = v^2 * sin(2*theta) / g,   maximal at theta = 45 where sin(2*theta) = 1
--
-- so the launch speed that produces the authored range is `v = sqrt(R * g)` and nothing else in the
-- throw needs a tuning value of its own. Everything a player expects then falls out for free rather
-- than being special-cased: 45 degrees goes furthest, flat goes shorter, straight up lands on your own
-- head, and aiming down drops it at your feet. The stick is never *aimed at a point* — it is thrown,
-- and where it lands is a consequence.
function DynamiteRules.launchSpeed(): number
	local throwConfig = DynamiteConfig.throw
	return math.sqrt(math.max(throwConfig.range, 0) * math.max(throwConfig.gravity, 0.0001))
end

-- The launch velocity for an aim direction. Returns nil for a degenerate direction rather than
-- guessing one: a zero-length vector is a malformed request, and a client is the only thing that can
-- send one.
--
-- NORMALISED HERE, which is also the whole of the server's trust check on the value. A client that
-- sends a 900-stud vector gets the same throw as one that sends a unit vector, because only the
-- direction survives.
function DynamiteRules.throwVelocity(direction: Vector3): Vector3?
	local magnitude = direction.Magnitude
	if magnitude ~= magnitude or magnitude <= 1e-4 or magnitude == math.huge then
		return nil
	end
	return direction / magnitude * DynamiteRules.launchSpeed()
end

-- Where the stick is `elapsed` seconds after leaving the hand. Plain ballistics, no drag: drag would
-- cost a tuning value nobody could feel and would break the clean `sqrt(R * g)` relationship above.
function DynamiteRules.ballisticPoint(origin: Vector3, velocity: Vector3, elapsed: number): Vector3
	local t = math.max(elapsed, 0)
	return origin + velocity * t - Vector3.yAxis * (0.5 * DynamiteConfig.throw.gravity * t * t)
end

-- Seconds between simulation samples. The caller walks the arc in these steps and raycasts between
-- consecutive points, so this is the resolution at which a wall can stop a throw.
function DynamiteRules.flightStepSeconds(): number
	local throwConfig = DynamiteConfig.throw
	return math.max(throwConfig.maxFlightSeconds, 0.0001) / math.max(math.floor(throwConfig.simulationSteps), 1)
end

--------------------------------------------------------------------------------
-- 5. The door
--------------------------------------------------------------------------------

-- A stick that came to rest this far from a door's face breaks it. Sockets are the clean answer and
-- exist for players who plan; this exists for players who improvise, and it is generous on purpose.
function DynamiteRules.breaksDoor(distance: number): boolean
	return math.max(0, distance) <= math.max(0, DynamiteConfig.door.thrownBreakRadius)
end

-- Closest distance from `point` to the segment `a`->`b`.
--
-- Needed because the arc is walked in fixed TIME steps: at launch speed one step covers several studs,
-- so a charge pocket can sit between two consecutive samples. Testing only the samples would miss a
-- throw that visibly passed straight through the marker; testing the segment cannot.
function DynamiteRules.distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local travel = b - a
	local lengthSquared = travel:Dot(travel)
	if lengthSquared <= 1e-8 then
		return (point - a).Magnitude
	end
	local alpha = math.clamp((point - a):Dot(travel) / lengthSquared, 0, 1)
	return (point - (a + travel * alpha)).Magnitude
end

-- Did a thrown stick's flight pass close enough to the charge pocket to seat in it? This is the
-- "stick a bomb on the door" catch: aim at the marker, throw, and the stick seats itself instead of
-- bouncing off the rock.
--
-- Deliberately a SPHERE AROUND THE SOCKET tested along the flight path rather than a check on the
-- final resting place. A stick thrown at a vertical face does not come to rest on it — it hits and
-- falls to the floor — so testing only the landing point would mean a dead-centre throw at the marker
-- never counted, which is exactly the shot the marker is asking for.
function DynamiteRules.catchesSocket(distance: number): boolean
	return math.max(0, distance) <= math.max(0, DynamiteConfig.door.socketCatchRadius)
end

-- 0..1 through a fuse. Reaching 1 is the detonation, in whichever clock the caller is holding.
function DynamiteRules.fuseProgress(elapsed: number, fuseSeconds: number): number
	local total = math.max(fuseSeconds, 0.0001)
	return math.clamp(math.max(0, elapsed) / total, 0, 1)
end

function DynamiteRules.fuseSecondsFor(kind: Types.LiveDynamiteKind): number
	return if kind == "Socketed" then DynamiteConfig.fuse.socketedSeconds else DynamiteConfig.fuse.thrownSeconds
end

return DynamiteRules

--!strict
-- Pure unstable-dripstone math. Generation, server authority, and client presentation all use
-- these functions so warning timing, fall motion, hit footprints, and light suppression agree.

local HazardsConfig = require(script.Parent.Parent.Config.Hazards)

local DripstoneRules = {}

type Variant = typeof(HazardsConfig.unstableDripstone.variants[1])
export type ImpactOutcome = "Damage" | "Snuff"

function DripstoneRules.variantById(variantId: string): Variant?
	for _, variant in HazardsConfig.unstableDripstone.variants do
		if variant.id == variantId then
			return variant
		end
	end
	return nil
end

-- Conservative anchor-to-tip extent of the CaveKit silhouette. The procedural tip and skirt
-- extend beyond `length`, so gameplay must never land using the nominal spire height alone.
function DripstoneRules.visualLength(variant: Variant): number
	return variant.length + variant.radius * HazardsConfig.unstableDripstone.visualLengthRadiusFactor
end

-- How high this formation's TIP hangs above the room floor, given the roof it is anchored to. This
-- is the number the readability rule is actually about: a player inspects the thing that is going to
-- fall on them, not the rock it is attached to.
function DripstoneRules.tipHeight(roofHeight: number, variant: Variant): number
	return roofHeight - DripstoneRules.visualLength(variant)
end

-- Is a formation of this variant, hanging from this roof, close enough to read?
function DripstoneRules.isReadableTip(roofHeight: number, variant: Variant): boolean
	return DripstoneRules.tipHeight(roofHeight, variant) <= HazardsConfig.unstableDripstone.maxEligibleTipHeight
end

-- The highest roof ANY authored variant can still bring a readable tip down from. Used to decide
-- whether a room is worth considering at all, before a variant has been rolled — so a tall chamber is
-- only excluded when nothing in the whole variant pool could reach into the readable band.
function DripstoneRules.maxReachableRoofHeight(): number
	local longest = 0
	for _, variant in HazardsConfig.unstableDripstone.variants do
		longest = math.max(longest, DripstoneRules.visualLength(variant))
	end
	return HazardsConfig.unstableDripstone.maxEligibleTipHeight + longest
end

function DripstoneRules.targetCount(depth: number): number
	local config = HazardsConfig.unstableDripstone
	local clampedDepth = math.max(1, math.floor(depth))
	local expected: number
	if clampedDepth <= 3 then
		expected = config.earlyLinearBase + config.earlyLinearStep * (clampedDepth - 1)
	elseif clampedDepth <= 6 then
		expected = config.midExponentialBase * config.midExponentialGrowth ^ (clampedDepth - 4)
	else
		expected = config.deepExponentialBase * config.deepExponentialGrowth ^ (clampedDepth - 6)
	end
	return math.max(0, math.floor(expected + 0.5))
end

function DripstoneRules.fallDuration(fallDistance: number): number
	local config = HazardsConfig.unstableDripstone
	local duration = math.sqrt(2 * math.max(0, fallDistance) / math.max(config.fallAcceleration, 0.001))
	return math.clamp(duration, config.minFallSeconds, config.maxFallSeconds)
end

-- Distance travelled after elapsed seconds under the configured analytic acceleration.
function DripstoneRules.fallOffset(elapsed: number, fallDistance: number): number
	local duration = DripstoneRules.fallDuration(fallDistance)
	if duration <= 0 then
		return math.max(0, fallDistance)
	end
	local progress = math.clamp(elapsed / duration, 0, 1)
	-- Quadratic ease is the normalized constant-acceleration trajectory and lands exactly.
	return math.max(0, fallDistance) * progress * progress
end

function DripstoneRules.insideDisc(point: Vector3, center: Vector3, radius: number): boolean
	local dx = point.X - center.X
	local dz = point.Z - center.Z
	return dx * dx + dz * dz <= radius * radius
end

-- A sufficiently depleted candle is extinguished outright. Otherwise the caller applies the
-- configured variant's max-wax damage; this function deliberately does not mutate state.
function DripstoneRules.impactOutcome(currentWax: number, maxWax: number): ImpactOutcome
	local threshold = HazardsConfig.unstableDripstone.snuffBelowWaxFraction
	if maxWax > 0 and currentWax / maxWax < threshold then
		return "Snuff"
	end
	return "Damage"
end

-- The first visible fall teaches its physical warning without requiring the player to be hit.
function DripstoneRules.shouldShowFallTutorial(
	alreadySeen: boolean,
	depth: number,
	maxDepth: number,
	playerPosition: Vector3,
	impactPosition: Vector3,
	presentationRadius: number
): boolean
	return not alreadySeen
		and depth <= maxDepth
		and DripstoneRules.insideDisc(playerPosition, impactPosition, presentationRadius)
end

function DripstoneRules.lightMultiplier(now: number, suppressedUntil: number, multiplier: number): number
	if now < suppressedUntil then
		return math.clamp(multiplier, 0, 1)
	end
	return 1
end

return DripstoneRules

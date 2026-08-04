--!strict
-- Pure unstable-dripstone math. Generation, server authority, and client presentation all use
-- these functions so warning timing, fall motion, hit footprints, and light suppression agree.

local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
-- One-directional: CaveFamilyRules reads Config/Hazards as data and never calls back into here, so
-- asking it which formations a family can roll costs no cycle.
local CaveFamilyRules = require(script.Parent.CaveFamilyRules)

local DripstoneRules = {}

type Variant = typeof(HazardsConfig.unstableDripstone.variants[1])
type CaveFamilyProfile = CaveFamilyRules.CaveFamilyProfile
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

-- The highest roof a variant this family can actually ROLL will still bring a readable tip down from.
-- Used to decide whether a room is worth considering at all, before a variant has been picked — so a
-- tall chamber is only excluded when nothing the family could draw would reach into the readable band.
--
-- WHY IT TAKES A FAMILY. This walks the pool to find the longest reach, and a family may weight a
-- variant to zero (Config/CaveFamilies.hazardEcology). Counting a formation the family will never roll
-- would admit tall rooms that then burn every placement attempt and come away empty — the room would
-- have qualified on the strength of a spire that family does not hang. Passing no profile keeps the
-- old whole-pool answer, which is what a caller with no family in hand should get.
function DripstoneRules.maxReachableRoofHeight(profile: CaveFamilyProfile?): number
	local longest = 0
	for _, variant in HazardsConfig.unstableDripstone.variants do
		local weight = if profile ~= nil
			then CaveFamilyRules.dripstoneVariantWeightMultiplier(profile, variant.id) * math.max(0, variant.weight)
			else math.max(0, variant.weight)
		if weight > 0 then
			longest = math.max(longest, DripstoneRules.visualLength(variant))
		end
	end
	return HazardsConfig.unstableDripstone.maxEligibleTipHeight + longest
end

-- The family's own weighted pick from the shared variant list, from ONE uniform roll in [0, 1). Pure
-- and deterministic in that roll, so the planner's seeded stream fully determines the result.
--
-- Returns nil only when a family has refused every formation, which `CaveFamilyRules.validate`
-- already rejects at the config — so a live caller always gets a variant back.
function DripstoneRules.selectVariant(profile: CaveFamilyProfile, roll: number): Variant?
	local variants = HazardsConfig.unstableDripstone.variants
	local total = 0
	for _, variant in variants do
		total += math.max(0, variant.weight) * CaveFamilyRules.dripstoneVariantWeightMultiplier(profile, variant.id)
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(if roll == roll then roll else 0, 0, 0.9999999) * total
	local cumulative = 0
	for _, variant in variants do
		cumulative += math.max(0, variant.weight) * CaveFamilyRules.dripstoneVariantWeightMultiplier(
			profile,
			variant.id
		)
		if target < cumulative then
			return variant
		end
	end
	-- Float drift on the last step only. Walk back to the last row the family can actually roll rather
	-- than handing back whatever happens to sit at the end of the list.
	for index = #variants, 1, -1 do
		local variant = variants[index]
		if math.max(0, variant.weight) * CaveFamilyRules.dripstoneVariantWeightMultiplier(profile, variant.id) > 0 then
			return variant
		end
	end
	return nil
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

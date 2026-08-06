--!strict
-- Pure ore resolution: which TIER of ore a seam in this cave family, at this depth, is cut from.
--
-- Deliberately separate from Logic/MiningRules, which owns how a seam is WORKED. A deposit has both
-- a row (its interaction: Standard, Twin, Deep, Dim, Bright) and a tier (its material). They are
-- independent axes and neither reads the other.
--
-- THE RESOLVER MUST OUTLIVE ITS CONTENT. Adding a fourth ore tier later must be a row in
-- Config/Ore.tiers plus a band in a family's `ore.availability` — nothing in this module, in the
-- planner, or in any cave logic may need to change for it. That is why availability is a scanned
-- list of weighted bands rather than a hand-written "if depth >= 40 then" ladder.

local OreConfig = require(script.Parent.Parent.Config.Ore)
local MiningConfig = require(script.Parent.Parent.Config.Mining)
local CaveFamilyRules = require(script.Parent.CaveFamilyRules)

local OreRules = {}

export type OreTier = OreConfig.OreTier
export type TierWeight = { tier: number, weight: number }
export type CaveFamilyProfile = CaveFamilyRules.CaveFamilyProfile

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function OreRules.tierById(tier: number?): OreTier?
	if typeof(tier) ~= "number" or not isFiniteNumber(tier) then
		return nil
	end
	local whole = math.floor(tier)
	for _, row in OreConfig.tiers do
		if row.tier == whole then
			return row
		end
	end
	return nil
end

-- Is this a tier the content tables actually describe? A family may only reference tiers that exist;
-- Logic/CaveFamilyRules.validate does not check that (it cannot see this config), so the
-- cross-config check lives in the ore test suite instead.
function OreRules.isKnownTier(tier: number?): boolean
	return OreRules.tierById(tier) ~= nil
end

function OreRules.nativeTier(profile: CaveFamilyProfile): number
	return profile.ore.nativeTier
end

-- The weighted tier list in force at this depth. Bands are stored deepest-first, so the first band
-- whose `minDepth` this floor reaches is the one that applies — a single forward scan, and a depth
-- below every band falls back to the family's native tier rather than to nothing.
function OreRules.availabilityAt(profile: CaveFamilyProfile, globalDepth: number): { TierWeight }
	local depth = if isFiniteNumber(globalDepth) then math.floor(globalDepth) else 1
	for _, band in profile.ore.availability do
		if depth >= band.minDepth then
			return band.tiers
		end
	end
	return { { tier = profile.ore.nativeTier, weight = 1 } }
end

-- Which tier THIS seam is, from one uniform roll in [0, 1) so a floor stays a pure function of its
-- seed. Unknown or zero-weight configurations fall back to the family's native tier: a seam always
-- has a material.
function OreRules.selectTier(profile: CaveFamilyProfile, globalDepth: number, roll: number): number
	local available = OreRules.availabilityAt(profile, globalDepth)
	local total = 0
	for _, entry in available do
		if entry.weight > 0 then
			total += entry.weight
		end
	end
	if total <= 0 then
		return profile.ore.nativeTier
	end

	local target = math.clamp(if roll == roll then roll else 0, 0, 0.9999999) * total
	local cumulative = 0
	for _, entry in available do
		if entry.weight <= 0 then
			continue
		end
		cumulative += entry.weight
		if target < cumulative then
			return entry.tier
		end
	end
	return available[#available].tier
end

-- The share of seams at this depth that come out as each tier, as a map tier -> probability. Used by
-- tests and by diagnostics; never by generation, which rolls `selectTier` per deposit.
function OreRules.tierProbabilities(profile: CaveFamilyProfile, globalDepth: number): { [number]: number }
	local available = OreRules.availabilityAt(profile, globalDepth)
	local total = 0
	for _, entry in available do
		if entry.weight > 0 then
			total += entry.weight
		end
	end
	local shares: { [number]: number } = {}
	if total <= 0 then
		shares[profile.ore.nativeTier] = 1
		return shares
	end
	for _, entry in available do
		if entry.weight > 0 then
			shares[entry.tier] = (shares[entry.tier] or 0) + entry.weight / total
		end
	end
	return shares
end

export type DepositTargetRange = { minimum: number, maximum: number }

-- The cave-family brief's intended seam-count envelope for this depth, identical in every family.
-- Read only by tests and documentation today: the live count is still Logic/MiningRules.targetCount.
-- See the long note in Config/Ore.depositTargets for exactly how the two differ and why adopting
-- this one is a mining/economy task rather than a cave-family one.
function OreRules.depositTargetRange(globalDepth: number): DepositTargetRange
	local depth = if isFiniteNumber(globalDepth) then math.max(1, math.floor(globalDepth)) else 1
	local bands = OreConfig.depositTargets
	if #bands == 0 then
		return { minimum = 0, maximum = 0 }
	end
	for _, band in bands do
		if depth <= band.maxDepth then
			return { minimum = band.minimum, maximum = band.maximum }
		end
	end
	local last = bands[#bands]
	return { minimum = last.minimum, maximum = last.maximum }
end

-- The absolute ceiling the planner will ever place, whatever the curves say. Stated here so a test
-- can compare the brief's envelope against the shipped clamp without reaching into Config/Mining.
function OreRules.maxDepositsPerFloor(): number
	return math.max(0, math.floor(MiningConfig.placement.maxPerFloor))
end

return OreRules

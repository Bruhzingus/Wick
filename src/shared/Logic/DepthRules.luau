--!strict
-- Pure: the one authoritative depth model. An expedition has a `startDepth` (where the tier drops
-- you) and a `localFloor` (how many floors of THIS expedition you have entered); every difficulty,
-- content and reward curve scales from the single derived `globalDepth`.
--
--   globalDepth = startDepth + localFloor - 1
--
-- Nothing here touches Roblox Instances or services. Every number comes from Config/Depth or from
-- the hand-authored per-floor tables it extends; no service may re-derive a depth curve of its own.

local DepthConfig = require(script.Parent.Parent.Config.Depth)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local BrazierConfig = require(script.Parent.Parent.Config.Brazier)

local DepthRules = {}

-- Park-Miller field, used only for deriving stable per-floor seeds. All intermediates stay below
-- 2^53 so the fold is exact rather than float-rounded.
local SEED_MODULUS = 2147483647
local SEED_MULTIPLIER = 48271

local function isFiniteNumber(value: number): boolean
	-- Rejects NaN (value ~= value) and both infinities.
	return value == value and value > -math.huge and value < math.huge
end

-- A usable floor ordinal: finite, whole, and at least 1. Fractional floors are rejected rather than
-- rounded, because rounding would let two different requests collide on one derived seed.
function DepthRules.isValidFloorNumber(value: number): boolean
	return isFiniteNumber(value) and math.floor(value) == value and value >= DepthConfig.minDepth
end

-- Every positive whole floor is supported. Content curves cap their own magnitudes, and the server
-- constructs only the next floor, so depth itself needs no gameplay ceiling.
function DepthRules.isSupportedDepth(globalDepth: number): boolean
	return DepthRules.isValidFloorNumber(globalDepth)
end

-- Fails loudly. Invalid input can never silently produce floor-1 data.
function DepthRules.assertSupportedDepth(globalDepth: number, context: string?)
	if not DepthRules.isSupportedDepth(globalDepth) then
		error(
			string.format(
				"%s: global depth %s must be a whole number at or above %d",
				context or "DepthRules",
				tostring(globalDepth),
				DepthConfig.minDepth
			),
			2
		)
	end
end

-- THE canonical formula. Errors on invalid input instead of guessing.
function DepthRules.getGlobalDepth(startDepth: number, localFloor: number): number
	if not DepthRules.isValidFloorNumber(startDepth) then
		error("DepthRules.getGlobalDepth: invalid startDepth " .. tostring(startDepth), 2)
	end
	if not DepthRules.isValidFloorNumber(localFloor) then
		error("DepthRules.getGlobalDepth: invalid localFloor " .. tostring(localFloor), 2)
	end
	return startDepth + localFloor - 1
end

-- Validate a finite planning batch. Live expeditions do not call this for progression; they plan
-- one next floor on demand.
function DepthRules.planningBatchCount(startDepth: number, requestedCount: number): number
	if not DepthRules.isSupportedDepth(startDepth) or not DepthRules.isValidFloorNumber(requestedCount) then
		return 0
	end
	return math.floor(requestedCount)
end

-- Internal difficulty band. Never shown to players; systems request values, not band branches.
function DepthRules.getDepthBand(globalDepth: number): string
	DepthRules.assertSupportedDepth(globalDepth, "DepthRules.getDepthBand")
	for _, band in DepthConfig.bands do
		if globalDepth <= band.maxDepth then
			return band.id
		end
	end
	-- Depths beyond the authored labels remain in the final band.
	return DepthConfig.bands[#DepthConfig.bands].id
end

-- Shared shape for the "authored tables own depths 1..authoredDepth, this extends past them" curves.
local function depthsPastAuthored(globalDepth: number): number
	return math.max(0, globalDepth - DepthConfig.authoredDepth)
end

local function linearExtension(globalDepth: number, curve: DepthConfig.ExtensionCurve): number
	local scaled = 1 + math.max(0, curve.perDepth) * depthsPastAuthored(globalDepth)
	return math.clamp(scaled, 1, math.max(curve.maximum, 1))
end

-- Multiplier applied on top of Config/Floors.threatBudgetPerFloor. Exactly 1 across the authored
-- range, so current expeditions are unchanged.
function DepthRules.getThreatBudgetMultiplier(globalDepth: number): number
	DepthRules.assertSupportedDepth(globalDepth, "DepthRules.getThreatBudgetMultiplier")
	return linearExtension(globalDepth, DepthConfig.threatBudget)
end

-- Multiplier applied on top of the dripstone target count. Planner safety caps still bind above it.
function DepthRules.getHazardBudgetMultiplier(globalDepth: number): number
	DepthRules.assertSupportedDepth(globalDepth, "DepthRules.getHazardBudgetMultiplier")
	return linearExtension(globalDepth, DepthConfig.hazardBudget)
end

-- Rooms to assemble. Inside the authored table this IS the authored value; past it the table's last
-- row grows by a configured step up to a hard ceiling.
function DepthRules.getRoomCountTarget(globalDepth: number): number
	DepthRules.assertSupportedDepth(globalDepth, "DepthRules.getRoomCountTarget")
	local authored = FloorsConfig.roomsPerFloor
	local ceiling = math.max(DepthConfig.maxRoomsPerFloor, 1)
	if #authored == 0 then
		return 1
	end
	if globalDepth <= #authored then
		return math.clamp(math.floor(authored[globalDepth]), 1, ceiling)
	end
	local last = authored[#authored]
	local extended = last + math.max(0, DepthConfig.roomCountStepPerDepth) * (globalDepth - #authored)
	return math.clamp(math.floor(extended + 0.5), 1, ceiling)
end

-- Brazier depth multiplier. Inside the authored table this IS the authored value; past it it grows
-- geometrically to a configured cap, so payout never runs away.
function DepthRules.getRewardDepthMultiplier(globalDepth: number): number
	DepthRules.assertSupportedDepth(globalDepth, "DepthRules.getRewardDepthMultiplier")
	local authored = BrazierConfig.depthMultipliers
	if #authored == 0 then
		return 1
	end
	if globalDepth <= #authored then
		return authored[globalDepth]
	end
	local growth = math.max(DepthConfig.rewardGrowthPerDepth, 1)
	local extended = authored[#authored] * growth ^ (globalDepth - #authored)
	return math.clamp(
		extended,
		authored[#authored],
		math.max(DepthConfig.maxRewardDepthMultiplier, authored[#authored])
	)
end

local function fold(state: number, value: number): number
	local mixed = (state + math.floor(value) % SEED_MODULUS) % SEED_MODULUS
	if mixed <= 0 then
		mixed += SEED_MODULUS - 1
	end
	return (mixed * SEED_MULTIPLIER) % SEED_MODULUS
end

-- Stable per-floor generation seed. A floor is reproducible from (run seed, tier, global depth)
-- alone — it never depends on how many floors were planned before it.
function DepthRules.getFloorSeed(runSeed: number, tierId: number, globalDepth: number): number
	DepthRules.assertSupportedDepth(globalDepth, "DepthRules.getFloorSeed")
	local base = math.abs(math.floor(if isFiniteNumber(runSeed) then runSeed else 0)) % SEED_MODULUS
	local safeTier = math.abs(math.floor(if isFiniteNumber(tierId) then tierId else 0)) % SEED_MODULUS
	return fold(fold(fold(base + 1, safeTier * 7919), globalDepth * 104729), globalDepth)
end

return DepthRules

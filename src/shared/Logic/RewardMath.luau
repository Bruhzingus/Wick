--!strict
-- Pure: the brazier reward formula (DESIGN §12). Exposed as a breakdown, not just a total,
-- because the game deliberately shows players the arithmetic before they commit.

local BrazierConfig = require(script.Parent.Parent.Config.Brazier)
local DepthRules = require(script.Parent.DepthRules)

export type RewardBreakdown = {
	waxDelivered: number,
	depthMultiplier: number,
	groupMultiplier: number, -- 1 + bonus x additional players
	tierMultiplier: number,
	total: number, -- payout currency, rounded down
}

local RewardMath = {}

-- `globalDepth` is the canonical difficulty depth (Logic/DepthRules), not this expedition's floor
-- ordinal. Paying out is not generating content, so a depth outside the supported range is clamped
-- into it rather than refused — a player standing at a brazier must always be able to cash out.
function RewardMath.compute(
	waxDelivered: number,
	globalDepth: number,
	additionalPlayers: number,
	tierMultiplier: number?
): RewardBreakdown
	local safeDepth = math.clamp(math.floor(globalDepth), 1, DepthRules.prototypeCeiling())
	local depthMultiplier = DepthRules.getRewardDepthMultiplier(safeDepth)
	local groupMultiplier = 1 + BrazierConfig.groupBonusPerPlayer * math.max(additionalPlayers, 0)
	local appliedTierMultiplier = math.max(tierMultiplier or 1, 0)
	local total = math.floor(
		waxDelivered * depthMultiplier * groupMultiplier * appliedTierMultiplier * BrazierConfig.rewardPerWaxUnit
	)
	return {
		waxDelivered = waxDelivered,
		depthMultiplier = depthMultiplier,
		groupMultiplier = groupMultiplier,
		tierMultiplier = appliedTierMultiplier,
		total = total,
	}
end

return RewardMath

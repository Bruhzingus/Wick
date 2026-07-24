--!strict
-- Pure: the brazier reward formula (DESIGN §12). Exposed as a breakdown, not just a total,
-- because the game deliberately shows players the arithmetic before they commit.

local BrazierConfig = require(script.Parent.Parent.Config.Brazier)

export type RewardBreakdown = {
	waxDelivered: number,
	depthMultiplier: number,
	groupMultiplier: number, -- 1 + bonus x additional players
	tierMultiplier: number,
	total: number, -- payout currency, rounded down
}

local RewardMath = {}

function RewardMath.compute(
	waxDelivered: number,
	depth: number,
	additionalPlayers: number,
	tierMultiplier: number?
): RewardBreakdown
	local index = math.clamp(depth, 1, #BrazierConfig.depthMultipliers)
	local depthMultiplier = BrazierConfig.depthMultipliers[index]
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

--!strict

local Harness = require(script.Parent.Harness)
local RewardMath = require(script.Parent.Parent.Logic.RewardMath)
local BrazierConfig = require(script.Parent.Parent.Config.Brazier)
local DepthConfig = require(script.Parent.Parent.Config.Depth)
local DepthRules = require(script.Parent.Parent.Logic.DepthRules)

local suite: Harness.Suite = {
	name = "RewardMath",
	tests = {
		Harness.test("reward breakdown exposes the exact visible formula", function()
			local wax = 0.537
			local depth = math.min(3, #BrazierConfig.depthMultipliers)
			local additionalPlayers = 2
			local result = RewardMath.compute(wax, depth, additionalPlayers)
			local depthMultiplier = BrazierConfig.depthMultipliers[depth]
			local groupMultiplier = 1 + BrazierConfig.groupBonusPerPlayer * additionalPlayers
			local expected = math.floor(wax * depthMultiplier * groupMultiplier * BrazierConfig.rewardPerWaxUnit)

			Harness.near(result.waxDelivered, wax)
			Harness.near(result.depthMultiplier, depthMultiplier)
			Harness.near(result.groupMultiplier, groupMultiplier)
			Harness.equal(result.total, expected)
		end),

		Harness.test("out-of-range depths still pay out, inside the configured bounds", function()
			-- Below the curve pays the shallowest row; above the technical ceiling pays the deepest
			-- supported depth. A player standing at a brazier can always cash out.
			local shallow = RewardMath.compute(1, 0, 0)
			local deep = RewardMath.compute(1, DepthRules.prototypeCeiling() + 100, 0)
			local ceiling = RewardMath.compute(1, DepthRules.prototypeCeiling(), 0)
			Harness.near(shallow.depthMultiplier, BrazierConfig.depthMultipliers[1])
			Harness.near(deep.depthMultiplier, ceiling.depthMultiplier)
			Harness.expect(
				deep.depthMultiplier >= BrazierConfig.depthMultipliers[#BrazierConfig.depthMultipliers],
				"depth past the authored table must never pay less than the deepest authored row"
			)
			Harness.expect(
				deep.depthMultiplier <= DepthConfig.maxRewardDepthMultiplier,
				"reward multiplier escaped its cap"
			)
		end),

		Harness.test("authored depths keep their exact authored multiplier", function()
			for depth, authored in BrazierConfig.depthMultipliers do
				Harness.near(RewardMath.compute(1, depth, 0).depthMultiplier, authored, 1e-9, "depth " .. depth)
			end
		end),

		Harness.test("negative party counts cannot reduce a payout", function()
			local result = RewardMath.compute(1, 1, -4)
			Harness.near(result.groupMultiplier, 1)
			Harness.equal(result.total, math.floor(BrazierConfig.depthMultipliers[1] * BrazierConfig.rewardPerWaxUnit))
		end),

		Harness.test("each additional player adds the configured multiplier without splitting the pot", function()
			local wax = 0.5
			local solo = RewardMath.compute(wax, 1, 0)
			for additionalPlayers = 1, 3 do
				local grouped = RewardMath.compute(wax, 1, additionalPlayers)
				Harness.near(grouped.groupMultiplier, 1 + BrazierConfig.groupBonusPerPlayer * additionalPlayers)
				Harness.expect(grouped.total >= solo.total, "group presence must never shrink an individual payout")
			end
		end),
	},
}

return suite

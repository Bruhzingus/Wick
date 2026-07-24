--!strict

local Harness = require(script.Parent.Harness)
local RewardMath = require(script.Parent.Parent.Logic.RewardMath)
local BrazierConfig = require(script.Parent.Parent.Config.Brazier)

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

		Harness.test("depth clamps to the configured reward curve", function()
			local shallow = RewardMath.compute(1, 0, 0)
			local deep = RewardMath.compute(1, #BrazierConfig.depthMultipliers + 100, 0)
			Harness.near(shallow.depthMultiplier, BrazierConfig.depthMultipliers[1])
			Harness.near(deep.depthMultiplier, BrazierConfig.depthMultipliers[#BrazierConfig.depthMultipliers])
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

--!strict

local Harness = require(script.Parent.Harness)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local DripstoneRules = require(script.Parent.Parent.Logic.DripstoneRules)

local suite: Harness.Suite = {
	name = "DripstoneRules",
	tests = {
		Harness.test("target counts follow the intended floor-one-through-ten curve", function()
			local expected = { 1, 2, 2, 4, 5, 7, 8, 10, 12, 15 }
			for depth, count in expected do
				Harness.equal(
					DripstoneRules.targetCount(depth),
					count,
					string.format("unexpected target at floor %d", depth)
				)
			end
		end),

		Harness.test("deep-floor target scaling never decreases", function()
			local previous = DripstoneRules.targetCount(6)
			for depth = 7, 30 do
				local current = DripstoneRules.targetCount(depth)
				Harness.expect(current >= previous, string.format("target decreased at floor %d", depth))
				previous = current
			end
			Harness.expect(
				DripstoneRules.targetCount(10) > DripstoneRules.targetCount(7),
				"deep scaling must materially increase the target"
			)
		end),

		Harness.test("fall timing is clamped and analytic motion lands exactly", function()
			local config = HazardsConfig.unstableDripstone
			for _, variant in config.variants do
				local visualLength = DripstoneRules.visualLength(variant)
				Harness.expect(visualLength > variant.length, "procedural tip extent must exceed nominal spire length")
			end
			Harness.near(DripstoneRules.fallDuration(0), config.minFallSeconds)

			local middleDuration = (config.minFallSeconds + config.maxFallSeconds) / 2
			local middleDistance = 0.5 * config.fallAcceleration * middleDuration * middleDuration
			Harness.near(DripstoneRules.fallDuration(middleDistance), middleDuration)

			local farDistance = 0.5 * config.fallAcceleration * (config.maxFallSeconds * 2) ^ 2
			Harness.near(DripstoneRules.fallDuration(farDistance), config.maxFallSeconds)

			local duration = DripstoneRules.fallDuration(middleDistance)
			Harness.near(DripstoneRules.fallOffset(-1, middleDistance), 0)
			Harness.near(DripstoneRules.fallOffset(0, middleDistance), 0)
			Harness.near(DripstoneRules.fallOffset(duration / 2, middleDistance), middleDistance * 0.25)
			Harness.near(DripstoneRules.fallOffset(duration, middleDistance), middleDistance)
			Harness.near(DripstoneRules.fallOffset(duration + 10, middleDistance), middleDistance)
		end),

		Harness.test("impact discs include their boundary and ignore vertical distance", function()
			local center = Vector3.new(4, 20, -3)
			Harness.expect(DripstoneRules.insideDisc(center, center, 3))
			Harness.expect(DripstoneRules.insideDisc(Vector3.new(7, -100, -3), center, 3))
			Harness.expect(DripstoneRules.insideDisc(Vector3.new(4, 500, 0), center, 3))
			Harness.expect(not DripstoneRules.insideDisc(Vector3.new(7.001, 20, -3), center, 3))
		end),

		Harness.test("light suppression expires at the authoritative deadline", function()
			Harness.near(DripstoneRules.lightMultiplier(9.999, 10, 0.42), 0.42)
			Harness.near(DripstoneRules.lightMultiplier(10, 10, 0.42), 1)
			Harness.near(DripstoneRules.lightMultiplier(11, 10, 0.42), 1)
			Harness.near(DripstoneRules.lightMultiplier(0, 1, -0.2), 0)
			Harness.near(DripstoneRules.lightMultiplier(0, 1, 1.2), 1)
		end),
	},
}

return suite

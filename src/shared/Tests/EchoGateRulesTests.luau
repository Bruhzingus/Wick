--!strict

local Harness = require(script.Parent.Harness)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)
local EchoGateRules = require(script.Parent.Parent.Logic.EchoGateRules)

local suite: Harness.Suite = {
	name = "EchoGateRules",
	tests = {
		Harness.test("planning requires the owned node and minimum depth", function()
			local minimum = LampConfig.generation.echoLock.minDepth
			Harness.equal(EchoGateRules.canPlan({}, minimum), false)
			Harness.equal(EchoGateRules.canPlan({ ["lamp.echo_lock"] = true }, minimum - 1), false)
			Harness.equal(
				EchoGateRules.canPlan({ ["lamp.echo_lock"] = true }, minimum),
				LampConfig.enabled and LampConfig.generation.enabled
			)
		end),

		Harness.test("entry, objectives, and the Warden room are protected", function()
			Harness.equal(EchoGateRules.roomIsEligible(1, 1, 2, 3, 4), false)
			Harness.equal(EchoGateRules.roomIsEligible(2, 1, 2, 3, 4), false)
			Harness.equal(EchoGateRules.roomIsEligible(3, 1, 2, 3, 4), false)
			Harness.equal(EchoGateRules.roomIsEligible(4, 1, 2, 3, 4), false)
			Harness.equal(EchoGateRules.roomIsEligible(5, 1, 2, 3, 4), true)
			Harness.equal(EchoGateRules.roomIsEligible(4, 1, 2, 3, nil), true)
		end),

		Harness.test("a ring opens only inside the configured radius", function()
			local radius = LampConfig.generation.echoLock.ringRadius
			Harness.expect(radius > 0, "the Echo Lock needs a positive interaction radius")
			local origin = Vector3.zero
			Harness.equal(EchoGateRules.withinRingRange(origin, Vector3.new(radius, 0, 0)), true)
			Harness.equal(EchoGateRules.withinRingRange(origin, Vector3.new(radius + 0.01, 0, 0)), false)
			Harness.equal(
				EchoGateRules.withinRingRange(origin, Vector3.new(0, radius + 0.01, 0)),
				false,
				"range is spatial, not a floor-wide horizontal cylinder"
			)
		end),
	},
}

return suite

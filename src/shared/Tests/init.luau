--!strict
-- Pure-rule suite registry. Requiring this module does not run tests; the Studio-only server
-- runner calls run so production servers pay no test execution cost.

local Harness = require(script.Harness)

export type Summary = Harness.Summary

local suites: { Harness.Suite } = {
	require(script.BrightnessMapTests),
	require(script.CandleGeometryTests),
	require(script.FloorPlannerTests),
	require(script.HazardRulesTests),
	require(script.LightFieldTests),
	require(script.LootRulesTests),
	require(script.RewardMathTests),
	require(script.RoomNavigationTests),
	require(script.SacrificeRulesTests),
	require(script.ThreatBrainTests),
	require(script.TokenBucketTests),
	require(script.ToolRulesTests),
	require(script.WaxDrainTests),
}

local Tests = {}

function Tests.run(): (boolean, Summary)
	return Harness.run(suites)
end

return Tests

--!strict
-- Pure-rule suite registry. Requiring this module does not run tests; the Studio-only server
-- runner calls run so production servers pay no test execution cost.

local Harness = require(script.Harness)

export type Summary = Harness.Summary

local suites: { Harness.Suite } = {
	require(script.AshamedLurkerRulesTests),
	require(script.AudioConfigTests),
	require(script.BrightnessMapTests),
	require(script.CandleGeometryTests),
	require(script.CargoRulesTests),
	require(script.CaveFamilyRulesTests),
	require(script.CaveTiersTests),
	require(script.ContractRulesTests),
	require(script.CooldownRulesTests),
	require(script.DepthRulesTests),
	require(script.ExtractionValueTests),
	require(script.DripstoneRulesTests),
	require(script.EchoGateRulesTests),
	require(script.EntrySpawnRulesTests),
	require(script.FlameFlickerTests),
	require(script.FloorPlannerTests),
	require(script.HazardRulesTests),
	require(script.LampRulesTests),
	require(script.LightFieldTests),
	require(script.LootRulesTests),
	require(script.MiningRulesTests),
	require(script.MossFireRulesTests),
	require(script.OreRulesTests),
	require(script.PlacementReservationsTests),
	require(script.RoomFootprintTests),
	require(script.RoomNavigationTests),
	require(script.SacrificeRulesTests),
	require(script.SoundFieldTests),
	require(script.SpectatorRulesTests),
	require(script.ThreatBrainTests),
	require(script.TokenBucketTests),
	require(script.ToolRulesTests),
	require(script.VineRulesTests),
	require(script.WaxAccountingTests),
	require(script.WaxDrainTests),
	require(script.WaxPacingTests),
}

local Tests = {}

function Tests.run(): (boolean, Summary)
	return Harness.run(suites)
end

return Tests

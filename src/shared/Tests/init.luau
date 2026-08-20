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
	require(script.CameraMotionTests),
	require(script.CandleModifiersTests),
	require(script.CargoRulesTests),
	require(script.CaveFamilyRulesTests),
	require(script.CaveTiersTests),
	require(script.ContractRulesTests),
	require(script.CooldownRulesTests),
	require(script.DeadCandleRulesTests),
	require(script.DescentElevatorRulesTests),
	require(script.DepthRulesTests),
	require(script.DevTestRoomRulesTests),
	require(script.ExtractionValueTests),
	require(script.DripstoneRulesTests),
	require(script.DynamiteRulesTests),
	require(script.EnemySpawnRulesTests),
	require(script.EntrySpawnRulesTests),
	require(script.FlameFlickerTests),
	require(script.FloorPlannerTests),
	require(script.FloorStackingTests),
	require(script.FloorRetentionRulesTests),
	require(script.GroundGeometryTests),
	require(script.HazardRulesTests),
	require(script.LampRulesTests),
	require(script.LightFieldTests),
	require(script.LobbyParkourTests),
	require(script.LootRulesTests),
	require(script.MineRelicRulesTests),
	require(script.MiningRulesTests),
	require(script.MossFireRulesTests),
	require(script.OreRulesTests),
	require(script.PartyInterfaceTests),
	require(script.PartyRulesTests),
	require(script.PartyVoteTests),
	require(script.PlacementReservationsTests),
	require(script.RoomFootprintTests),
	require(script.RoomNavigationTests),
	require(script.SacrificeRulesTests),
	require(script.SoundFieldTests),
	require(script.SpectatorRulesTests),
	require(script.StoneWardenConfigTests),
	require(script.SurfaceRulesTests),
	require(script.ThreatAnimationConfigTests),
	require(script.ThreatBrainTests),
	require(script.ThreatRulesTests),
	require(script.TokenBucketTests),
	require(script.ToolRulesTests),
	require(script.UnlittiusRulesTests),
	require(script.TouchLayoutRulesTests),
	require(script.TripwireRulesTests),
	require(script.VineRulesTests),
	require(script.WallLampRulesTests),
	require(script.WaxAccountingTests),
	require(script.WaxDrainTests),
	require(script.WaxPacingTests),
}

local Tests = {}

function Tests.run(): (boolean, Summary)
	return Harness.run(suites)
end

return Tests

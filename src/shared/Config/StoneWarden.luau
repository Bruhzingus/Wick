--!strict
-- Stone Warden encounter tuning. The planner owns whether and where the encounter exists;
-- server runtime only realizes the planned room fixtures and behaviour.

export type StoneWardenConfig = {
	enabled: boolean,
	minGlobalDepth: number,
	spawnChancePerEligibleFloor: number,
	roomModuleId: string,
	roomCeilingHeight: number,
	pileOffset: Vector3,
	relicOffset: Vector3,
	counterDripstoneOffset: Vector3,
	counterDripstoneVariantId: string,
	encounterClearance: number,
	fixtureFootprint: number,
	bowlSize: Vector3,
	relicSize: Vector3,
	relicSurfaceClearance: number,
	relicColor: Color3,
	relicLightRange: number,
	relicLightBrightness: number,
	walkSpeed: number,
	emergenceSeconds: number,
	pathRefreshSeconds: number,
	stationaryPauseSeconds: number,
}

local StoneWarden: StoneWardenConfig = {
	enabled = true,
	minGlobalDepth = 4,
	-- Rare enough to remain an event, common enough to be exercised during ordinary playtests.
	spawnChancePerEligibleFloor = 0.45,
	roomModuleId = "WardenDen",
	roomCeilingHeight = 28,
	pileOffset = Vector3.new(8, 0, 4),
	relicOffset = Vector3.new(-10, 0, -6),
	counterDripstoneOffset = Vector3.new(8, 0, -8),
	counterDripstoneVariantId = "Hammer",
	encounterClearance = 9,
	-- The relic is a guaranteed encounter trigger, not incidental dressing. Its pad uses the same
	-- built-Terrain resolver as loot and deposits, and the larger silhouette remains readable in the
	-- room without turning into a second light source for threat logic.
	fixtureFootprint = 4,
	bowlSize = Vector3.new(4, 1, 4),
	relicSize = Vector3.new(1.6, 1.6, 1.6),
	relicSurfaceClearance = 0.12,
	relicColor = Color3.fromRGB(200, 220, 255),
	relicLightRange = 18,
	relicLightBrightness = 2.4,
	walkSpeed = 8,
	emergenceSeconds = 4,
	pathRefreshSeconds = 0.3,
	stationaryPauseSeconds = 3,
}

return StoneWarden

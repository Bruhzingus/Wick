--!strict
-- Drip trail tuning (DESIGN §8). Involuntary: you ARE the trail. Navigation upside, exposure downside.

export type DripTrailConfig = {
	emitIntervalStuds: number,
	pointLifetimeSeconds: number,
	maxPointsPerPlayer: number,
	dripPartSize: number,
	dripFlattening: number,
	dripSizeJitter: number,
	dripAspectJitter: number,
	dripPositionJitter: number,
	dripColor: Color3,
}

local DripTrail: DripTrailConfig = {
	-- Studs travelled between drips. Lower = denser trail: better route memory, worse exposure.
	emitIntervalStuds = 8,
	-- Seconds a physical wax drop remains before disappearing.
	pointLifetimeSeconds = 35,
	-- Cap per player (oldest culled first). Bounds both scene cost and how far back you can be tracked.
	maxPointsPerPlayer = 24,
	-- Tiny floor-hugging wax discs: visual breadcrumbs only, never balls, Neon, or light sources.
	dripPartSize = 0.18,
	dripFlattening = 0.16,
	dripSizeJitter = 0.22,
	dripAspectJitter = 0.18,
	dripPositionJitter = 0.14,
	dripColor = Color3.fromRGB(112, 88, 62),
}

return DripTrail

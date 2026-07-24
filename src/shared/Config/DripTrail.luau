--!strict
-- Drip trail tuning (DESIGN §8). Involuntary: you ARE the trail. Navigation upside, exposure downside.

export type DripTrailConfig = {
	emitIntervalStuds: number,
	pointLifetimeSeconds: number,
	maxPointsPerPlayer: number,
	pointIntensity: number,
	pointRange: number,
	dripPartSize: number,
}

local DripTrail: DripTrailConfig = {
	-- Studs travelled between drips. Lower = denser trail: better route memory, worse exposure.
	emitIntervalStuds = 6,
	-- Seconds a drip glows before fading out. Higher = longer-lived evidence of your route.
	pointLifetimeSeconds = 45,
	-- Cap per player (oldest culled first). Bounds both scene cost and how far back you can be tracked.
	maxPointsPerPlayer = 40,
	-- Light-field intensity of one drip. Keep tiny: the drawn should barely care, hunters follow
	-- the points geometrically regardless. Higher = the trail itself lures the drawn = harder.
	pointIntensity = 0.05,
	-- Studs one drip's faint light reaches.
	pointRange = 4,
	-- Visual size (studs) of the drip blob.
	dripPartSize = 0.4,
}

return DripTrail

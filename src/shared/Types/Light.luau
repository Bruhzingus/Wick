--!strict
-- Light-field types. Threat perception is driven entirely by a list of light sources;
-- every tool works by adding, removing, or scaling entries in this list (see Types/Tool).

export type LightSourceKind = "Flame" | "Flare" | "Decoy" | "Drip"

-- One contributor to the light field. Pure data consumed by Logic/LightField.
export type LightSource = {
	kind: LightSourceKind,
	position: Vector3,
	intensity: number, -- strength at the source; falls off linearly to zero at range
	range: number, -- studs at which the contribution reaches zero
	attractsDrawn: boolean, -- false for cold-wax sources: they illuminate but the drawn ignore them
	ownerId: number?, -- PlayerId for player-origin sources
}

-- One drip-trail breadcrumb (DESIGN §8). Dark-hunters can path along these geometrically;
-- they also enter the light field as tiny Drip sources.
export type TrailPoint = {
	position: Vector3,
	ownerId: number,
	createdAt: number, -- os.clock() at emission
}

return {}

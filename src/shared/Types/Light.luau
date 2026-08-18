--!strict
-- Light-field types. Threat perception is driven entirely by a list of light sources;
-- every tool works by adding, removing, or scaling entries in this list (see Types/Tool).

-- "Lamp" is a cave wall lamp a player lit by hand (Config/WallLamp). It is the only kind in this
-- list that nobody owns, never moves and never goes out — which is exactly why it needed its own
-- kind rather than borrowing "Flame": a fixed, ownerless, permanent light is a different thing for a
-- threat to reason about than a flame walking around with a player attached to it.
export type LightSourceKind = "Flame" | "Flare" | "Decoy" | "Remains" | "Lamp"

-- One contributor to the light field. Pure data consumed by Logic/LightField.
export type LightSource = {
	kind: LightSourceKind,
	position: Vector3,
	intensity: number, -- strength at the source; falls off linearly to zero at range
	range: number, -- studs at which the contribution reaches zero
	attractsDrawn: boolean, -- false for cold-wax sources: they illuminate but the drawn ignore them
	repelsDarkHunters: boolean, -- whether hunters perceive this light when judging illuminated space
	forcesDarkHunterRetreat: boolean, -- true only for panic light such as FLARE; ordinary dial light never drives them off
	ownerId: number?, -- PlayerId for player-origin sources
}

-- One non-glowing drip-trail breadcrumb (DESIGN §8). Dark-hunters path along these geometrically;
-- they never enter the light field and never attract the Drawn.
export type TrailPoint = {
	position: Vector3,
	ownerId: number,
	createdAt: number, -- os.clock() at emission
}

return {}

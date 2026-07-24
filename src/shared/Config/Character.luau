--!strict
-- Candle body geometry. The model IS the health bar (DESIGN §3): height tracks remaining wax,
-- and that height is authoritative — the water lethality rule compares against it directly.
-- Proportions read as a stumpy candle: wide body, melted rim, short wick, small flame.

export type CharacterConfig = {
	heightAtFullWax: number,
	heightAtZeroWax: number,
	bodyRadius: number,
	rimHeight: number,
	rimRadiusMultiplier: number,
	wickHeight: number,
	flameHeight: number,
	cameraLift: number,
	hipHeight: number,
}

local Character: CharacterConfig = {
	-- Body height (studs) at wax = 1.0. Taller = water must rise higher to be lethal = easier.
	heightAtFullWax = 4,
	-- Body height (studs) near burnout — the body shrinks linearly toward this, so water that was
	-- once wadeable becomes lethal late in a run. Lower = harder late-game.
	heightAtZeroWax = 0.8,
	-- Cylinder radius (studs). Visual and collision width; wider = stumpier.
	bodyRadius = 1.4,
	-- The melted lip at the top of the body (visual).
	rimHeight = 0.3,
	rimRadiusMultiplier = 1.12,
	-- Dark wick between body top and flame (visual; the flame sits on top of it).
	wickHeight = 0.45,
	-- Flame size (studs); the flame part is slightly elongated from this base dimension.
	flameHeight = 0.9,
	-- How far the first-person eye sits ABOVE the body top. Keeps your own flame and cap out of
	-- the view; looking down still shows the shrinking body.
	cameraLift = 0.8,
	-- How high the physics root floats above ground. Purely mechanical; leave unless movement misbehaves.
	hipHeight = 0.5,
}

return Character

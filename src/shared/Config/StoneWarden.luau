--!strict
-- Stone Warden encounter tuning. The planner owns whether and where the encounter exists;
-- server runtime only realizes the planned room fixtures and behaviour.

export type StoneWardenConfig = {
	enabled: boolean,
	minGlobalDepth: number,
	spawnChancePerEligibleFloor: number,
	roomModuleId: string,
	roomCeilingHeight: number,
	-- Distances from the DEN'S WALL and its centre, not fixed room-local points. The planner picks a
	-- doorless side once the room's doorways are final and turns these into the three offsets.
	layout: {
		wallSetback: number,
		relicStandoff: number,
		counterLateral: number,
		counterStandoff: number,
	},
	emergence: {
		wallDepth: number,
		rise: number,
	},
	relicWakeRadius: number,
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
	-- THE ENCOUNTER IS BUILT AGAINST A WALL, and it used to be built around the room centre: a heap of
	-- rock standing in open floor with the relic it was supposedly guarding twenty studs behind it.
	-- Nothing about that read as a guard, and a player's first contact with the encounter was usually
	-- walking into the heap. Now the dormant body is an outcrop in one doorless wall of the den and the
	-- relic stands out in the open floor in front of it, lit, where you see what you are about to take
	-- and what is behind it before you take it. `Logic/FloorPlanner` turns these into room offsets.
	layout = {
		-- Pile centre, in from the cell boundary. The wall's inner face is `wallThickness` inside that,
		-- so the dormant mass (built up to ~4.4 studs deep in StoneWardenModel) ends up fused with the
		-- wall rather than floating in front of it or poking through into the next room.
		wallSetback = 5,
		-- Relic, out from the room centre toward that wall: far enough off the navigation hub to keep
		-- the crossing clear, close enough that the outcrop behind it is in the same view.
		relicStandoff = 9,
		-- The Heavy Crown, off to one side of the walk between them, so a player who takes the relic
		-- and runs has a hazard to lead the thing under rather than a straight line to the door.
		counterLateral = 14,
		counterStandoff = 6,
	},
	-- How the body leaves the wall. It steps FORWARD out of the rock over `emergenceSeconds` rather
	-- than rising out of the floor, so `wallDepth` is how far back inside the stone it starts.
	emergence = {
		wallDepth = 4.5,
		rise = 2.5,
	},
	-- Waking is proximity, not a touch. The relic is a small ball on a solid plinth, and a player
	-- standing at the plinth reading it never overlaps the ball itself — which is how an encounter
	-- whose whole trigger is "touch the relic" ended up being woken by bumping into the Warden.
	relicWakeRadius = 7,
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

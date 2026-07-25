--!strict
-- Session-local remains tuning. Storage disappears with the expedition server; global/cross-server
-- remains stay deferred.

export type RemainsConfig = {
	minimumWax: number,
	maxStoredPerFloor: number,
	ownerMayCollect: boolean,
	pickupRange: number,
	pickupHoldSeconds: number,
	visualDiameter: number,
	visualThickness: number,
	placementInset: number,
	groundProbeHeightAbove: number,
	groundProbeDepth: number,
	lightIntensity: number,
	lightRange: number,
	color: Color3,
}

local Remains: RemainsConfig = {
	minimumWax = 0.005,
	maxStoredPerFloor = 12,
	ownerMayCollect = false,
	pickupRange = 9,
	pickupHoldSeconds = 0.5,
	visualDiameter = 2.2,
	visualThickness = 0.25,
	-- Fraction of half a room kept clear of walls when remapping an old death position.
	placementInset = 0.7,
	-- Bounded ground-probe ray: starts this far above the flat-room fallback height and searches
	-- downward this far, so a remains pool always settles on the real undulating floor.
	groundProbeHeightAbove = 40,
	groundProbeDepth = 120,
	lightIntensity = 0.45,
	lightRange = 12,
	color = Color3.fromRGB(255, 145, 64),
}

return Remains

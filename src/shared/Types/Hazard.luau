--!strict
-- Hazard-domain types (DESIGN §9). Environmental threats: no AI, cheap difficulty.
-- Water is the only static zone hazard. Dripstone is a stateful environmental hazard with a
-- focused placement/runtime route; it deliberately does not use HazardPlacement's zone fields.
-- A creature that extinguishes rather than drains is still a creature: it is a Threats row carrying
-- contactEffect = "Snuff" or a sustainedContact profile, never a hazard.

-- Hazard kinds. Closed union.
export type HazardId = "Water" | "Dripstone"
-- Only these hazards use RoomModuleDef.allowedHazards and HazardPlacement's static zone shape.
export type StaticHazardId = "Water"

-- Static hazard definition. One FLAT record with optional fields (no tagged unions) because each
-- hazard uses a different subset; the comment on each field says which hazard it applies to.
export type HazardDef = {
	id: HazardId,
	displayName: string,
	degradePerSecond: number?, -- Water: wax lost per second while wading
	lethalAtHeightFraction: number?, -- Water: fraction of CURRENT model height at which the surface kills
}

-- Water wading assessment, computed purely from heights (Logic/HazardRules).
export type WaterAssessment = "None" | "Wading" | "Lethal"

return {}

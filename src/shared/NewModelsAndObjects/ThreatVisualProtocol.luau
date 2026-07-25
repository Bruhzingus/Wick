--!strict
-- Shared names for the lightweight server proxy -> client creature-visual contract.
-- Gameplay state never travels through this contract; these attributes are presentation only.

local ThreatVisualProtocol = {
	attributes = {
		kind = "WickVisualKind",
		mode = "WickThreatMode",
		targetPosition = "WickThreatTargetPosition",
		illumination = "WickThreatIllumination",
		moving = "WickThreatMoving",
	},
	kinds = {
		crawler = "Crawler",
		moth = "Moth",
		ceilingFly = "CeilingFly",
	},
}

return table.freeze(ThreatVisualProtocol)

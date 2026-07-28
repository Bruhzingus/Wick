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
		-- Monotonic counter, not a boolean: one increment is one attack beat. A counter survives a
		-- pulse landing inside a single replication frame, which a flag toggled on and off does not.
		attack = "WickThreatAttack",
		-- Written before `attack` so the client can add a close-mixed sting only for the player the
		-- authoritative contact resolver actually hit.
		attackVictim = "WickThreatAttackVictim",
	},
	kinds = {
		crawler = "Crawler",
		moth = "Moth",
		ceilingFly = "CeilingFly",
	},
}

return table.freeze(ThreatVisualProtocol)

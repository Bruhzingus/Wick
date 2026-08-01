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
		-- WHICH CAVE FAMILY'S DRESSING this body wears, and how strongly to tint it
		-- (Config/CaveFamilies.presentation). PRESENTATION ONLY, and unusually strictly so: the same
		-- AI, collision, speed, damage, perception and states run behind every variant, and the
		-- silhouette category is identical. A Moss Lurker is a Lurker with damp growth on it.
		--
		-- WHAT A VARIANT MAY NEVER TOUCH: the crimson dark-hunter eyes, the yellow Drawn eyes, and the
		-- readability of moth wings. Those three are how a player identifies what is coming at them in
		-- the dark, and a variant that dimmed or recoloured them would be making the game harder
		-- through presentation — which is exactly the thing a cosmetic layer is not allowed to do.
		-- The tint strength is deliberately capped low in config for the same reason: a threat must
		-- never be camouflaged against the rock it is standing on.
		familyVariant = "WickThreatFamilyVariant",
		familyTint = "WickThreatFamilyTint",
	},
	kinds = {
		crawler = "Crawler",
		moth = "Moth",
		ceilingFly = "CeilingFly",
	},
}

return table.freeze(ThreatVisualProtocol)

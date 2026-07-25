--!strict
-- Replicated presentation contract for one-shot unstable dripstone models. The server changes only
-- state/timestamps; clients reconstruct wobble and analytic falling from the same shared rules.

local DripstoneVisualProtocol = {
	tag = "WickUnstableDripstone",
	states = {
		dormant = "Dormant",
		warning = "Warning",
		falling = "Falling",
		spent = "Spent",
	},
	attributes = {
		state = "WickDripstoneState",
		stateStartedAt = "WickDripstoneStateStartedAt",
		restCFrame = "WickDripstoneRestCFrame",
		impactPosition = "WickDripstoneImpactPosition",
		fallDistance = "WickDripstoneFallDistance",
		variantId = "WickDripstoneVariantId",
		visualSeed = "WickDripstoneVisualSeed",
		depth = "WickDripstoneDepth",
	},
}

return table.freeze(DripstoneVisualProtocol)

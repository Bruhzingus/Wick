--!strict
-- ============================ STUB ============================
-- Cave-tier access (DESIGN §14, primary progression axis). Real version reads unlocks from persistence
-- and a tuned tier table. Replace this one file. Currently every tier is unlocked for everyone.
-- =============================================================

local Types = require(script.Parent.Parent.Types)

export type CaveTier = {
	id: number,
	displayName: string,
	minWaxReward: number,
}

export type CaveTiersInterface = {
	list: () -> { CaveTier },
	isUnlocked: (playerId: Types.PlayerId, tierId: number) -> boolean,
}

local TIERS: { CaveTier } = {
	{ id = 1, displayName = "The Shallows", minWaxReward = 0 },
	{ id = 2, displayName = "The Deep", minWaxReward = 0 },
}

local CaveTiers: CaveTiersInterface = {
	list = function()
		return TIERS
	end,
	isUnlocked = function(_playerId, _tierId)
		return true -- STUB: everything unlocked
	end,
}

return CaveTiers

--!strict
-- Wax-type burn profiles (DESIGN §15). "Standard" is the neutral start; the rest are in-run loot.
-- NOTE: pickups are not yet placed in floors (see IMPLEMENTATION-NOTES.md); the profiles are live
-- in the drain/light math, so placing loot later is purely additive.

local Types = require(script.Parent.Parent.Types)

local WaxTypes: { [Types.WaxTypeId]: Types.WaxTypeDef } = {
	Standard = {
		id = "Standard",
		displayName = "Standard Wax",
		-- The neutral baseline every candle starts with. All multipliers 1 by definition.
		drainMultiplier = 1.0,
		brightnessMultiplier = 1.0,
		attractsDrawn = true,
	},
	Beeswax = {
		id = "Beeswax",
		displayName = "Beeswax",
		-- Slow, dim, efficient. <1 drain = lasts longer (easier survival, less light).
		drainMultiplier = 0.8,
		brightnessMultiplier = 0.85,
		attractsDrawn = true,
	},
	Tallow = {
		id = "Tallow",
		displayName = "Tallow",
		-- Fast, bright, hungry. >1 drain = shorter run, more light (higher risk/reward).
		drainMultiplier = 1.3,
		brightnessMultiplier = 1.3,
		attractsDrawn = true,
	},
	ColdWax = {
		id = "ColdWax",
		displayName = "Cold Wax",
		-- Rare. Burns without attracting the drawn — removes half the threat taxonomy while held.
		-- Applies to ALL your light: flame, flares, decoys, drips (your wax is cold everywhere).
		drainMultiplier = 1.0,
		brightnessMultiplier = 0.9,
		attractsDrawn = false,
	},
}

return WaxTypes

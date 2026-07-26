--!strict
-- Durable-access tiers. These rows are the complete tuning surface for where an expedition starts,
-- how long it runs, its difficulty/payout scaling, and unlock thresholds; Interfaces/CaveTiers owns
-- only evaluation. Difficulty comes from the global depth these rows produce (Logic/DepthRules),
-- never from the tier id itself.

export type CaveTier = {
	id: number,
	displayName: string,
	requiredCurrency: number,
	-- Absolute global depth this tier's expedition BEGINS at (Logic/DepthRules). Every tier starts at
	-- 1 today, preserving current player-facing behaviour; turning tiers into deeper starting points
	-- is a later task, and this field is where that change lands.
	startDepth: number,
	maxFloors: number,
	threatBudgetMultiplier: number,
	rewardMultiplier: number,
	dripstoneMultiplier: number,
	waxDrainMultiplier: number,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
}

local CaveTiers: { CaveTier } = {
	{
		id = 1,
		displayName = "The Shallows",
		requiredCurrency = 0,
		startDepth = 1,
		maxFloors = 6,
		-- This keeps early one-threat floors intact but reduces later two-threat floors to one,
		-- making the introductory expedition genuinely sparse.
		threatBudgetMultiplier = 0.6,
		rewardMultiplier = 1,
		-- Baseline falling-dripstone rate (DripstoneRules.targetCount is unscaled at this tier).
		dripstoneMultiplier = 1,
		-- Baseline wax economy: every candle's effective burn rate is unscaled at this tier.
		waxDrainMultiplier = 1,
		-- Matches the default project Atmosphere: the lightest, least oppressive shade of cave.
		atmosphereColor = Color3.new(0.62, 0.66, 0.74),
		atmosphereDecay = Color3.new(0.22, 0.24, 0.3),
	},
	{
		id = 2,
		displayName = "The Descent",
		requiredCurrency = 1500,
		startDepth = 1,
		maxFloors = 8,
		-- Slightly more threats than the original neutral 1.0 budget.
		threatBudgetMultiplier = 1.1,
		rewardMultiplier = 1.15,
		-- Slightly more falling dripstones than The Shallows.
		dripstoneMultiplier = 1.2,
		-- Slightly faster effective burn rate: every candle drains a little quicker at this depth.
		waxDrainMultiplier = 1.08,
		-- A visibly darker, cooler shade of cave than The Shallows.
		atmosphereColor = Color3.new(0.5, 0.53, 0.59),
		atmosphereDecay = Color3.new(0.18, 0.19, 0.24),
	},
	{
		id = 3,
		displayName = "The Deep",
		requiredCurrency = 6000,
		startDepth = 1,
		maxFloors = 10,
		-- Slightly more threats than the original 1.2 budget.
		threatBudgetMultiplier = 1.35,
		rewardMultiplier = 1.5,
		-- Noticeably more falling dripstones than The Descent.
		dripstoneMultiplier = 1.45,
		-- Fastest effective burn rate: wax is precious this deep.
		waxDrainMultiplier = 1.18,
		-- The darkest shade of cave: same hue as the other tiers, driven toward black.
		atmosphereColor = Color3.new(0.37, 0.4, 0.44),
		atmosphereDecay = Color3.new(0.13, 0.14, 0.18),
	},
}

return CaveTiers

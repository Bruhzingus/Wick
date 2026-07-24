--!strict
-- Durable-access tiers. These rows are the complete tuning surface for unlock thresholds,
-- expedition length/difficulty, and payout scaling; Interfaces/CaveTiers owns only evaluation.

export type CaveTier = {
	id: number,
	displayName: string,
	requiredCurrency: number,
	maxFloors: number,
	threatBudgetMultiplier: number,
	rewardMultiplier: number,
}

local CaveTiers: { CaveTier } = {
	{
		id = 1,
		displayName = "The Shallows",
		requiredCurrency = 0,
		maxFloors = 6,
		-- This keeps early one-threat floors intact but reduces later two-threat floors to one,
		-- making the introductory expedition genuinely sparse.
		threatBudgetMultiplier = 0.6,
		rewardMultiplier = 1,
	},
	{
		id = 2,
		displayName = "The Descent",
		requiredCurrency = 1500,
		maxFloors = 8,
		threatBudgetMultiplier = 1,
		rewardMultiplier = 1.15,
	},
	{
		id = 3,
		displayName = "The Deep",
		requiredCurrency = 6000,
		maxFloors = 10,
		threatBudgetMultiplier = 1.2,
		rewardMultiplier = 1.5,
	},
}

return CaveTiers

--!strict
-- The canonical depth model's tuning surface. `globalDepth` is the one difficulty number every
-- system scales from; a cave tier contributes where an expedition STARTS while the run may continue
-- indefinitely. Everything here extends the authored per-floor
-- tables in Config/Floors, Config/Loot, Config/Brazier and Config/Threats still own depths 1..10.
-- These values describe what happens BEYOND them. Depth is intentionally uncapped: bounded content
-- curves and on-demand floor construction keep arbitrarily deep expeditions safe.

export type DepthBand = {
	id: string,
	maxDepth: number, -- inclusive upper bound; depths beyond the final row use the final band
}

export type ExtensionCurve = {
	perDepth: number, -- added per global depth past `authoredDepth`
	maximum: number, -- hard cap; scaling can never exceed this
}

export type DepthConfig = {
	minDepth: number,
	authoredDepth: number,
	bands: { DepthBand },
	threatBudget: ExtensionCurve,
	hazardBudget: ExtensionCurve,
	roomCountStepPerDepth: number,
	maxRoomsPerFloor: number,
	rewardGrowthPerDepth: number,
	maxRewardDepthMultiplier: number,
}

local Depth: DepthConfig = {
	-- Shallowest legal global depth. Depth 0 and below are invalid input, never clamped silently.
	minDepth = 1,
	-- The deepest global depth the hand-authored per-floor tables actually cover. At or above depth 1
	-- and at or below this, every curve below is neutral (multiplier 1 / authored room count), so the
	-- current game is bit-for-bit unchanged. Raise this only when those tables are extended by hand.
	authoredDepth = 10,
	-- Internal difficulty bands later systems can request. Names are internal; nothing shows them.
	bands = {
		{ id = "Introduction", maxDepth = 3 },
		{ id = "Standard", maxDepth = 6 },
		{ id = "Dangerous", maxDepth = 10 },
		{ id = "Expert", maxDepth = 15 },
		{ id = "Extreme", maxDepth = 20 },
	},
	-- Extra threat budget past the authored tables. Linear and capped — deliberately gentle, because
	-- DESIGN's difficulty comes from threat combinations and room complexity, not from a bigger number.
	threatBudget = {
		perDepth = 0.06,
		maximum = 1.6,
	},
	-- Extra hazard (falling-dripstone) density past the authored tables. The planner's own per-room
	-- and hazardous-room-fraction caps still bind, so this can raise pressure but never safety.
	hazardBudget = {
		perDepth = 0.05,
		maximum = 1.5,
	},
	-- Rooms added per global depth past the authored `roomsPerFloor` table.
	roomCountStepPerDepth = 0.5,
	-- Absolute per-floor room ceiling. This bounds each on-demand construction step.
	maxRoomsPerFloor = 16,
	-- Geometric growth of the brazier depth multiplier past the authored `depthMultipliers` table.
	rewardGrowthPerDepth = 1.25,
	-- Payout ceiling for the prototype; keeps deep runs valuable without unbounded exponential growth.
	maxRewardDepthMultiplier = 60,
}

return Depth

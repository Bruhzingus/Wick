--!strict
-- The canonical depth model's tuning surface. `globalDepth` is the one difficulty number every
-- system scales from; a cave tier contributes only where an expedition STARTS and how many floors
-- it runs. Everything here is prototype scaffolding for longer expeditions — the authored per-floor
-- tables in Config/Floors, Config/Loot, Config/Brazier and Config/Threats still own depths 1..10.
-- These values describe what happens BEYOND them, plus the technical ceiling that keeps the
-- prototype honest.

export type DepthBand = {
	id: string,
	maxDepth: number, -- inclusive upper bound; bands must be listed shallowest-first and cover the ceiling
}

export type ExtensionCurve = {
	perDepth: number, -- added per global depth past `authoredDepth`
	maximum: number, -- hard cap; scaling can never exceed this
}

export type DevelopmentConfig = {
	enabled: boolean,
	floorsPerRun: number,
}

export type DepthConfig = {
	minDepth: number,
	prototypeCeiling: number,
	authoredDepth: number,
	bands: { DepthBand },
	threatBudget: ExtensionCurve,
	hazardBudget: ExtensionCurve,
	roomCountStepPerDepth: number,
	maxRoomsPerFloor: number,
	rewardGrowthPerDepth: number,
	maxRewardDepthMultiplier: number,
	development: DevelopmentConfig,
}

local Depth: DepthConfig = {
	-- Shallowest legal global depth. Depth 0 and below are invalid input, never clamped silently.
	minDepth = 1,
	-- Temporary technical ceiling for the prototype, NOT a design statement. Requesting a depth past
	-- this is an error: the planner refuses rather than quietly generating shallow-floor content.
	prototypeCeiling = 20,
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
	-- Absolute room ceiling. Floors are built eagerly at run start, so this bounds build cost too.
	maxRoomsPerFloor = 16,
	-- Geometric growth of the brazier depth multiplier past the authored `depthMultipliers` table.
	rewardGrowthPerDepth = 1.25,
	-- Payout ceiling for the prototype; keeps deep runs valuable without unbounded exponential growth.
	maxRewardDepthMultiplier = 60,
	-- DEVELOPMENT ONLY. When enabled, a run ignores its tier's `maxFloors` and descends to
	-- `floorsPerRun` (still clamped to `prototypeCeiling`). Never ship this enabled.
	development = {
		enabled = false,
		floorsPerRun = 20,
	},
}

return Depth

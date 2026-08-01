--!strict
-- ORE TIERS — what the rock a seam is cut from is made of, independent of how a seam is worked.
--
-- Config/Mining owns the INTERACTION (how many strikes, what window, how loud). This file owns the
-- MATERIAL: which tier of ore a cave family's rock is, and how many seams a floor of any family
-- wants. The two are deliberately separate axes — a Twin Seam of Tier 1 and a Twin Seam of Tier 3
-- are worked identically and are worth different amounts.
--
-- NOTHING HERE IS A MINING CHANGE. No permanent ore currency, no new strike rule, no new
-- interaction. Logic/OreRules is a pure resolver, and the only consumer today is the floor planner
-- recording which tier a planned deposit sits in. What a tier is WORTH is left to a later task and
-- is deliberately not stated as an economy number here.

export type OreTier = {
	tier: number,
	displayName: string,
	-- The family whose native rock this is, for documentation and diagnostics only. Availability is
	-- decided by Config/CaveFamilies.ore, never by reading this back.
	nativeToFamily: string?,
}

export type DepositTargetBand = {
	maxDepth: number, -- inclusive; depths past the final row use the final row
	minimum: number,
	maximum: number,
}

export type OreConfig = {
	-- Launch ships tiers 1-3. A fourth tier is added by appending a row HERE and naming it in a
	-- family's `ore.availability` band — Logic/OreRules resolves whatever it is given and no cave
	-- logic changes. There is deliberately no Tier 4 row at launch.
	tiers: { OreTier },
	-- HOW MANY SEAMS A FLOOR WANTS, by global depth, and identical in every family. Depth increases
	-- ore availability by putting MORE deposits in the ground; a harder cave is better because its
	-- native ore is more valuable, never because it automatically contains more of it.
	--
	-- This is a TARGET RANGE, not a guarantee. The planner places at most one deposit per room and
	-- only in rooms that pass every safety rule; a floor that cannot satisfy them carries fewer. The
	-- count drops, the rules never relax.
	--
	-- NOT YET THE LIVE CURVE, and deliberately so. The count a floor actually rolls is still
	-- Logic/MiningRules.targetCount against the authored weight bands in Config/Mining — the curve
	-- every income figure in TUNING.md was measured on (expected 0.65 / 1.10 / 1.40 / 1.85 / 2.45 per
	-- band). This table is the cave-family brief's intended envelope and it DIVERGES from that curve
	-- at both ends: the brief guarantees a seam on floor 1 where the shipped curve rolls none 35% of
	-- the time, and asks for up to four at depth 20 where Config/Mining caps at three. Adopting it is
	-- a mining/economy task with its own income re-derivation, not a cave-family change, so the
	-- envelope is recorded here and read only by Logic/OreRules.depositTargetRange until then.
	depositTargets: { DepositTargetBand },
}

local Ore: OreConfig = {
	tiers = {
		{ tier = 1, displayName = "Pale Wax", nativeToFamily = "STONE" },
		{ tier = 2, displayName = "Green Wax", nativeToFamily = "MOSS" },
		{ tier = 3, displayName = "Cold Wax", nativeToFamily = "ICE" },
	},
	depositTargets = {
		{ maxDepth = 4, minimum = 1, maximum = 1 },
		{ maxDepth = 9, minimum = 1, maximum = 2 },
		{ maxDepth = 14, minimum = 2, maximum = 2 },
		{ maxDepth = 19, minimum = 2, maximum = 3 },
		{ maxDepth = math.huge, minimum = 3, maximum = 4 },
	},
}

return Ore

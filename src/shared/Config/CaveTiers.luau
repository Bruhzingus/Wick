--!strict
-- Cave tiers — DERIVED, not authored. Every value in this table is projected from a row in
-- Config/CaveFamilies, which is the one authoritative description of what a cave is.
--
-- WHY THIS FILE STILL EXISTS. The lobby, the elevators, the shop, the party, the remote payloads and
-- every save written before the cave-family redesign all speak a numeric tier id. Rewriting all of
-- them to speak "STONE"/"MOSS"/"ICE" would be a wire-format and persistence change spread across a
-- dozen systems for no gameplay benefit, so the numeric id stays as the ADDRESS of a cave while the
-- family id is its IDENTITY. `Interfaces/CaveTiers` translates between them in exactly one place,
-- and profile ownership is persisted by family id (`Interfaces/Persistence.ownedCaveFamilies`).
--
-- THE MIGRATION IS A RENAME, NOT A GRANT, and this projection is what makes that true:
--
--     tier 1  The Shallows -> STONE  Stone Caves
--     tier 2  The Descent  -> MOSS   Moss Caves
--     tier 3  The Deep     -> ICE    Ice Caves
--
-- Anyone who owned The Descent owns Moss; anyone who owned The Deep owns Ice; nobody gains or loses
-- access, and no currency moves.
--
-- DO NOT ADD A FIELD HERE. If a cave needs to describe something new, it belongs on the family
-- profile; this table only projects what the pre-family systems already read. `startDepth` is the
-- clearest example of why: all three families begin at global depth 1 and always will, so the field
-- is projected as a constant rather than kept as a knob somebody could turn.

local CaveFamiliesConfig = require(script.Parent.CaveFamilies)

export type CaveTier = {
	id: number,
	displayName: string,
	-- The family this row projects. Read by anything that needs the real profile — never re-derived
	-- from the numeric id anywhere else.
	familyId: CaveFamiliesConfig.CaveFamilyId,
	-- Currency taken from EVERY party member at the moment of descent. Zero means the cave is free
	-- and always will be. Non-refundable once the run starts: this is the risk.
	entryFee: number,
	-- One-off price for never paying this cave's fee again. Zero means there is nothing to buy.
	permanentUnlockPrice: number,
	-- Absolute global depth this expedition BEGINS at. Always 1: a family is not a deeper starting
	-- point, it is a different cave that scales differently from its own floor 1.
	startDepth: number,
	-- The family's BASE threat/hazard multipliers. The per-band growth on top of these is resolved by
	-- Logic/CaveFamilyRules and is deliberately NOT projected here — a caller holding only a tier row
	-- must not be able to compute a difficulty number, because it would be missing half the formula.
	threatBudgetMultiplier: number,
	payoutPermille: number,
	dripstoneMultiplier: number,
	waxDrainMultiplier: number,
	-- NOTE: this projection deliberately carries no atmosphere. It used to mirror the family's colour
	-- and decay, back when those two were the whole of a cave's air and the run orchestrator read them
	-- from here. The air is now five properties resolved by `Logic/CaveFamilyRules.atmosphere` from the
	-- family id, so mirroring a subset of it through the legacy tier row would be two values that could
	-- silently disagree with the three beside them.
}

local function project(family: CaveFamiliesConfig.CaveFamilyProfile): CaveTier
	return {
		id = family.legacyTierId,
		displayName = family.displayName,
		familyId = family.id,
		entryFee = family.entryFee,
		permanentUnlockPrice = family.unlockCost,
		startDepth = 1,
		threatBudgetMultiplier = family.baseThreatMultiplier,
		payoutPermille = family.payoutPermille,
		dripstoneMultiplier = family.baseHazardMultiplier,
		waxDrainMultiplier = family.waxDrainMultiplier,
	}
end

local CaveTiers: { CaveTier } = {}
for _, family in CaveFamiliesConfig.families do
	table.insert(CaveTiers, project(family))
end
-- Ascending tier id, so every party ballot and the shop's cave list stay in the order the player
-- learned them in whatever order the family rows happen to be written.
table.sort(CaveTiers, function(a: CaveTier, b: CaveTier): boolean
	return a.id < b.id
end)

return CaveTiers

--!strict
-- The DERIVED numeric tier table (Config/CaveTiers), which exists only so the lobby, shop, party and
-- elevator layers can keep addressing caves by ordinal. What a cave IS lives in Config/CaveFamilies
-- and is tested by CaveFamilyRulesTests; this suite tests the projection itself.
--
-- These are deliberately structural rather than a transcription of the current numbers. Pinning
-- `payoutPermille = 2500` here would mean every legitimate tuning pass failed the suite until somebody
-- updated a second file, which teaches people to edit tests until they go green. What is pinned
-- instead is the shape the rows must keep whatever the numbers become.

local Harness = require(script.Parent.Harness)
local CaveTierConfig = require(script.Parent.Parent.Config.CaveTiers)
local CaveFamiliesConfig = require(script.Parent.Parent.Config.CaveFamilies)

local suite: Harness.Suite = {
	name = "CaveTiers",
	tests = {
		Harness.test("every family projects exactly one tier row, in ascending id order", function()
			-- The projection has to be a bijection or ownership stops being translatable between the
			-- numeric address a shop card uses and the stable id a save records.
			Harness.equal(#CaveTierConfig, #CaveFamiliesConfig.families)
			local seenIds: { [number]: boolean } = {}
			local seenFamilies: { [string]: boolean } = {}
			local previousId = -math.huge
			for _, tier in CaveTierConfig do
				Harness.isNil(seenIds[tier.id], "two rows share tier id " .. tostring(tier.id))
				Harness.isNil(seenFamilies[tier.familyId], "two rows project family " .. tier.familyId)
				seenIds[tier.id] = true
				seenFamilies[tier.familyId] = true
				Harness.expect(tier.id > previousId, "the lobby's cave order must be stable and ascending")
				previousId = tier.id
			end
			for _, family in CaveFamiliesConfig.families do
				Harness.expect(seenFamilies[family.id] == true, family.id .. " has no tier row to be addressed by")
			end
		end),

		Harness.test("a projected row carries a usable identity and whole currency values", function()
			for _, tier in CaveTierConfig do
				Harness.expect(typeof(tier.displayName) == "string" and #tier.displayName > 0, "missing display name")
				Harness.expect(typeof(tier.familyId) == "string" and #tier.familyId > 0, "missing family id")
				-- Currency never touches floating point (Config/Extraction), so every price and the
				-- payout scalar must be whole at every tier.
				for _, field in { "entryFee", "permanentUnlockPrice", "payoutPermille" } do
					local value = (tier :: any)[field]
					Harness.expect(
						typeof(value) == "number" and value == value and value % 1 == 0 and value >= 0,
						string.format("%s: %s must be a whole, non-negative number", tier.displayName, field)
					)
				end
				Harness.expect(tier.payoutPermille >= 1000, tier.displayName .. " must never pay below the baseline")
			end
		end),

		Harness.test("every tier starts at the surface", function()
			-- A family is a DIFFERENT cave, not a deeper starting point. The field is projected as a
			-- constant rather than kept as a knob, and this pins that decision.
			for _, tier in CaveTierConfig do
				Harness.equal(tier.startDepth, 1, tier.displayName .. " must start at the surface")
			end
		end),

		Harness.test("there is always a cave a broke player can walk into", function()
			-- The floor under the whole economy: a bad streak in a paid cave must never lock somebody out
			-- of the game entirely (Interfaces/CaveTiers.isFree).
			local free = 0
			for _, tier in CaveTierConfig do
				if tier.entryFee <= 0 then
					free += 1
					Harness.equal(
						tier.permanentUnlockPrice,
						0,
						tier.displayName .. " is free, so it must not also be for sale"
					)
				end
			end
			Harness.expect(free >= 1, "at least one cave must be free forever")
		end),

		Harness.test("a paid cave costs more to own outright than to enter once", function()
			-- Owning a cave is a long-term goal, not the obvious thing to do with a first windfall. If
			-- the unlock ever fell below a single admission, paying the toll would be strictly wrong.
			for _, tier in CaveTierConfig do
				if tier.entryFee > 0 then
					Harness.expect(
						tier.permanentUnlockPrice > tier.entryFee,
						tier.displayName .. " must cost more to own than to enter once"
					)
				end
			end
		end),

		Harness.test("a harder cave pays better, so risk is never taken for nothing", function()
			-- Sorted by base threat budget, payout must not decrease. This is the model's whole promise:
			-- a family moves difficulty and reward together, and never one without the other.
			local sorted = table.clone(CaveTierConfig)
			table.sort(sorted, function(a, b)
				return a.threatBudgetMultiplier < b.threatBudgetMultiplier
			end)
			for index = 2, #sorted do
				Harness.expect(
					sorted[index].payoutPermille >= sorted[index - 1].payoutPermille,
					string.format(
						"%s is more dangerous than %s but does not pay more",
						sorted[index].displayName,
						sorted[index - 1].displayName
					)
				)
			end
		end),

		Harness.test("the projection never leaks a difficulty number a caller could act on", function()
			-- A tier row carries the family's BASE multipliers so pre-family callers keep working, and
			-- deliberately not the per-band growth on top of them: a caller holding only this row must
			-- not be able to compute a difficulty, because it would be missing half the formula.
			-- Resolution lives in Logic/CaveFamilyRules and nowhere else.
			for _, tier in CaveTierConfig do
				Harness.isNil((tier :: any).threatBandMultipliers, "band growth must not leak into the projection")
				Harness.isNil((tier :: any).hazardBandMultipliers, "band growth must not leak into the projection")
				Harness.isNil((tier :: any).roomShapeWeights, "generation data must not leak into the projection")
				Harness.isNil((tier :: any).ore, "ore data must not leak into the projection")
				Harness.isNil((tier :: any).topology, "topology must not leak into the projection")
			end
		end),
	},
}

return suite

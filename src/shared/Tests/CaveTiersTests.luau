--!strict
-- PHASE 10. The cave-tier rows, and the guarantees that keep a tier a DIAL rather than a second
-- content system.
--
-- These are deliberately structural rather than a transcription of the current numbers. Pinning
-- `payoutPermille = 2500` here would mean every legitimate tuning pass failed the suite until somebody
-- updated a second file, which teaches people to edit tests until they go green. What is pinned
-- instead is the shape the rows must keep whatever the numbers become.

local Harness = require(script.Parent.Harness)
local CaveTierConfig = require(script.Parent.Parent.Config.CaveTiers)

local suite: Harness.Suite = {
	name = "CaveTiers",
	tests = {
		Harness.test("every tier carries a usable biome id", function()
			-- The Phase 10 stub. A tier missing this field is a tier a future biome lookup would index
			-- with nil and silently skip, which is the exact failure a stub exists to prevent.
			for _, tier in CaveTierConfig do
				Harness.expect(
					typeof(tier.biomeId) == "string" and #tier.biomeId > 0,
					string.format("tier %d (%s) has no usable biomeId", tier.id, tier.displayName)
				)
			end
		end),

		Harness.test("the biome field is still a no-op placeholder shared by every tier", function()
			-- WHY THIS TEST EXISTS: while all three tiers hold the same value, any consumer added later
			-- branches identically for every cave, which is what makes the field provably invisible to
			-- players. The moment one tier differs, that guarantee is gone and real biome content has
			-- started shipping.
			--
			-- "multiple biomes" is on the NEVER list in DESIGN.md §16 and GAME-BRIEF.md §19, and
			-- ART-BIBLE.md §12 calls the caves "never a themed biome" — so this failing is not
			-- necessarily a bug, but it must never happen by accident. If you are here because you
			-- deliberately themed a tier, amend those three documents and then delete this test.
			local first: string? = nil
			for _, tier in CaveTierConfig do
				if first == nil then
					first = tier.biomeId
				else
					Harness.equal(
						tier.biomeId,
						first,
						"a tier was themed without the authority documents being amended (see the comment above)"
					)
				end
			end
		end),

		Harness.test("tier ids are unique, and every tier starts at the surface", function()
			-- Converting tiers into deeper starting points was proposed and explicitly rejected: all
			-- tiers begin at depth 1 and difficulty comes from the multipliers alone. `startDepth` stays
			-- in the row as the place that change would land if it is ever revisited, so this pins the
			-- decision rather than the field's existence.
			local seen: { [number]: boolean } = {}
			for _, tier in CaveTierConfig do
				Harness.expect(not seen[tier.id], "duplicate tier id " .. tostring(tier.id))
				seen[tier.id] = true
				Harness.equal(tier.startDepth, 1, tier.displayName .. " must start at the surface")
			end
		end),

		Harness.test("there is always a cave a broke player can walk into", function()
			-- The floor under the whole economy: a bad streak in a paid cave must never lock somebody out
			-- of the game entirely (Config/CaveTiers, Interfaces/CaveTiers.isFree).
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
				-- Currency never touches floating point (Config/Extraction), so both prices and the
				-- payout scalar must be whole numbers at every tier.
				for _, field in { "entryFee", "permanentUnlockPrice", "payoutPermille" } do
					local value = (tier :: any)[field]
					Harness.equal(value % 1, 0, string.format("%s.%s must be a whole number", tier.displayName, field))
				end
			end
		end),

		Harness.test("a harder cave pays better, so risk is never taken for nothing", function()
			-- Sorted by threat budget, payout must not decrease. This is the tier model's whole promise:
			-- the dial moves difficulty and reward together, and nothing else.
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
	},
}

return suite

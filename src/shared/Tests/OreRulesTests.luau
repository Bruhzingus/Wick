--!strict
-- Ore tiers: which material a seam in a given cave family at a given depth is cut from.
--
-- The point of this suite is that the RESOLVER outlives its content. Launch ships three tiers; a
-- fourth must be a config row and nothing else. The synthetic profile below is how that is proven
-- without shipping a Tier 4 nobody has authored yet.

local Harness = require(script.Parent.Harness)
local OreRules = require(script.Parent.Parent.Logic.OreRules)
local OreConfig = require(script.Parent.Parent.Config.Ore)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)
local MiningRules = require(script.Parent.Parent.Logic.MiningRules)

local function familyById(id: string)
	local profile = CaveFamilyRules.byId(id)
	assert(profile ~= nil, "test fixture requires family " .. id)
	return profile
end

-- The exact share of seams that come out as `tier` at this depth, from the resolver's own weights.
local function shareOf(profile: any, depth: number, tier: number): number
	return OreRules.tierProbabilities(profile, depth)[tier] or 0
end

-- Sampled rather than computed, so this exercises `selectTier`'s actual roll mapping rather than
-- re-reading the weights it was derived from.
local function sampledShare(profile: any, depth: number, tier: number, samples: number): number
	local hits = 0
	for index = 0, samples - 1 do
		if OreRules.selectTier(profile, depth, index / samples) == tier then
			hits += 1
		end
	end
	return hits / samples
end

local suite: Harness.Suite = {
	name = "OreRules",
	tests = {
		Harness.test("every tier a family references is a tier the content tables describe", function()
			-- Logic/CaveFamilyRules.validate cannot check this: it cannot see Config/Ore. The
			-- cross-config check therefore lives here, where both are in scope.
			for _, profile in CaveFamilyRules.list() do
				Harness.expect(
					OreRules.isKnownTier(profile.ore.nativeTier),
					profile.id .. " is native to a tier that does not exist"
				)
				for _, band in profile.ore.availability do
					for _, entry in band.tiers do
						Harness.expect(
							OreRules.isKnownTier(entry.tier),
							profile.id .. " offers tier " .. entry.tier .. ", which does not exist"
						)
					end
				end
			end
		end),

		Harness.test("launch ships exactly three tiers and no unauthored fourth", function()
			Harness.equal(#OreConfig.tiers, 3, "a fourth tier must be a deliberate content addition")
			for tier = 1, 3 do
				Harness.expect(OreRules.isKnownTier(tier), "tier " .. tier .. " must exist at launch")
			end
			Harness.expect(not OreRules.isKnownTier(4), "there is deliberately no Tier 4 yet")
			Harness.isNil(OreRules.tierById(nil))
			Harness.isNil(OreRules.tierById(0 / 0))
		end),

		Harness.test("each family's native tier is the only thing it carries at depth 1", function()
			for _, expected in { { id = "STONE", tier = 1 }, { id = "MOSS", tier = 2 }, { id = "ICE", tier = 3 } } do
				local profile = familyById(expected.id)
				Harness.equal(OreRules.nativeTier(profile), expected.tier)
				Harness.equal(shareOf(profile, 1, expected.tier), 1, expected.id .. " floor 1 must be pure native ore")
				-- And the roll agrees with the weights it came from, at every extreme.
				for _, roll in { 0, 0.5, 0.999999 } do
					Harness.equal(OreRules.selectTier(profile, 1, roll), expected.tier)
				end
			end
		end),

		Harness.test("Stone reaches Tier 2 at floor 20 and Tier 3 at floor 40", function()
			local stone = familyById("STONE")
			Harness.equal(shareOf(stone, 19, 2), 0, "Tier 2 must not appear before floor 20")
			Harness.near(shareOf(stone, 20, 1), 0.85, 1e-9)
			Harness.near(shareOf(stone, 20, 2), 0.15, 1e-9)
			Harness.equal(shareOf(stone, 20, 3), 0, "Tier 3 must not appear before floor 40")

			Harness.near(shareOf(stone, 40, 1), 0.65, 1e-9)
			Harness.near(shareOf(stone, 40, 2), 0.25, 1e-9)
			Harness.near(shareOf(stone, 40, 3), 0.10, 1e-9)
			-- The bands hold past their own row rather than falling off the end.
			Harness.near(shareOf(stone, 4_000, 3), 0.10, 1e-9)
		end),

		Harness.test("Moss reaches Tier 3 at floor 20 and Ice is Tier 3 throughout", function()
			local moss = familyById("MOSS")
			Harness.equal(shareOf(moss, 19, 3), 0, "Moss must not reach Tier 3 before floor 20")
			Harness.near(shareOf(moss, 20, 2), 0.85, 1e-9)
			Harness.near(shareOf(moss, 20, 3), 0.15, 1e-9)
			Harness.equal(shareOf(moss, 20, 1), 0, "Moss never carries Stone's ore")

			local ice = familyById("ICE")
			for _, depth in { 1, 20, 40, 500 } do
				Harness.equal(shareOf(ice, depth, 3), 1, "Ice is Tier 3 at every depth")
			end
		end),

		Harness.test("the rarity split a family advertises is the split its rolls produce", function()
			local stone = familyById("STONE")
			-- 85/15 at the first unlock, 65/25/10 once two advanced tiers are available.
			Harness.near(sampledShare(stone, 20, 1, 10_000), 0.85, 0.002)
			Harness.near(sampledShare(stone, 20, 2, 10_000), 0.15, 0.002)
			Harness.near(sampledShare(stone, 40, 1, 10_000), 0.65, 0.002)
			Harness.near(sampledShare(stone, 40, 2, 10_000), 0.25, 0.002)
			Harness.near(sampledShare(stone, 40, 3, 10_000), 0.10, 0.002)
		end),

		Harness.test("a family's native tier is always the most common thing in it", function()
			for _, profile in CaveFamilyRules.list() do
				for _, depth in { 1, 20, 40, 120 } do
					local shares = OreRules.tierProbabilities(profile, depth)
					local nativeShare = shares[profile.ore.nativeTier] or 0
					for tier, share in shares do
						if tier ~= profile.ore.nativeTier then
							Harness.expect(
								nativeShare > share,
								string.format("%s stopped being native to its own ore at depth %d", profile.id, depth)
							)
						end
					end
				end
			end
		end),

		Harness.test("a fourth tier needs a config row and no cave logic at all", function()
			-- THE forward-compatibility test. This synthetic profile names a tier the shipped content
			-- tables do not describe; the resolver must handle it purely as data. If this ever requires
			-- a change in OreRules, the resolver has stopped outliving its content.
			local future = {
				id = "FUTURE",
				ore = {
					nativeTier = 4,
					availability = {
						{ minDepth = 30, tiers = { { tier = 4, weight = 70 }, { tier = 5, weight = 30 } } },
						{ minDepth = 1, tiers = { { tier = 4, weight = 100 } } },
					},
				},
			}
			Harness.equal(OreRules.nativeTier(future :: any), 4)
			Harness.equal(OreRules.selectTier(future :: any, 1, 0.5), 4)
			Harness.equal(OreRules.selectTier(future :: any, 30, 0.1), 4)
			Harness.equal(OreRules.selectTier(future :: any, 30, 0.9), 5)
			Harness.near(shareOf(future :: any, 30, 5), 0.3, 1e-9)
		end),

		Harness.test("a hostile roll or a broken band still yields the native tier", function()
			local stone = familyById("STONE")
			for _, roll in { -5, 5, 0 / 0, math.huge, -math.huge } do
				Harness.expect(
					OreRules.isKnownTier(OreRules.selectTier(stone, 40, roll)),
					"hostile roll: " .. tostring(roll)
				)
			end
			-- Zero-weight and empty bands fall back rather than returning nil.
			local broken = {
				ore = { nativeTier = 2, availability = { { minDepth = 1, tiers = { { tier = 3, weight = 0 } } } } },
			}
			Harness.equal(OreRules.selectTier(broken :: any, 5, 0.5), 2)
			-- A depth below every band also falls back to the native tier.
			local gapped =
				{ ore = { nativeTier = 1, availability = { { minDepth = 50, tiers = { { tier = 2, weight = 1 } } } } } }
			Harness.equal(OreRules.selectTier(gapped :: any, 5, 0.5), 1)
		end),

		Harness.test("the deposit-count envelope is finite, ordered, and identical for every family", function()
			-- The envelope is shared by every family on purpose: depth increases ore availability by
			-- putting MORE seams in the ground, and a harder cave is better because its native ore is
			-- worth more — never because it automatically contains more of it.
			local previousMinimum, previousMaximum = 0, 0
			for _, depth in { 1, 4, 5, 9, 10, 14, 15, 19, 20, 60 } do
				local range = OreRules.depositTargetRange(depth)
				for _, value in { range.minimum, range.maximum } do
					Harness.expect(value == value, "deposit target must not be NaN at depth " .. depth)
					Harness.expect(value < math.huge, "deposit target must be finite at depth " .. depth)
					Harness.expect(value >= 0, "deposit target must be non-negative at depth " .. depth)
				end
				Harness.expect(range.maximum >= range.minimum, "an inverted band at depth " .. depth)
				Harness.expect(range.minimum >= previousMinimum, "the envelope floor must not fall with depth")
				Harness.expect(range.maximum >= previousMaximum, "the envelope ceiling must not fall with depth")
				previousMinimum, previousMaximum = range.minimum, range.maximum
			end
			-- Hostile depths resolve rather than erroring.
			for _, depth in { 0, -3, 0 / 0 } do
				Harness.expect(OreRules.depositTargetRange(depth).maximum >= 0, "hostile depth: " .. tostring(depth))
			end
		end),

		Harness.test("the shipped seam count and the brief's envelope are both recorded and differ", function()
			-- A deliberate, documented divergence (see Config/Ore.depositTargets). This test exists so
			-- that whoever closes it later has to come here and delete an assertion that says the two
			-- disagree, rather than discovering the gap by reading a balance spreadsheet.
			local shallow = OreRules.depositTargetRange(1)
			Harness.equal(shallow.minimum, 1, "the brief guarantees a seam on floor 1")
			Harness.equal(MiningRules.targetCount(1, 0), 0, "the shipped curve still rolls a seamless floor 1")
			Harness.expect(
				OreRules.depositTargetRange(20).maximum > OreRules.maxDepositsPerFloor(),
				"the brief's deep ceiling still exceeds the shipped per-floor clamp"
			)
		end),
	},
}

return suite

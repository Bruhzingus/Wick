--!strict
-- Cold tests for the wick-pack spawn budget and the variant mapping. No Instances, no services.

local Harness = require(script.Parent.Harness)
local EnemySpawnRules = require(script.Parent.Parent.Logic.EnemySpawnRules)
local EnemyVariantRules = require(script.Parent.Parent.Logic.EnemyVariantRules)

-- Walks a deep range of depths with many seeds. The budget is a dice roll, so the properties worth
-- pinning are the INVARIANTS it may never violate at any depth or seed, not one sampled outcome.
local function forEveryRoll(callback: (depth: number, budget: EnemySpawnRules.Budget) -> ())
	for depth = 1, 24 do
		for seed = 1, 60 do
			callback(depth, EnemySpawnRules.budgetForDepth(depth, Random.new(depth * 1000 + seed)))
		end
	end
end

local suite: Harness.Suite = {
	name = "EnemySpawnRules",
	tests = {
		--------------------------------------------------------------------------------
		-- The pairing rules, which are the reason this module exists at all
		--------------------------------------------------------------------------------

		Harness.test("never more than one Gnawer on a floor, at any depth or seed", function()
			-- ENCOUNTERS.md: two straight-line charges in one space is unreadable, because a player
			-- cannot track two commit directions at once. This is a hard cap, not a tendency.
			forEveryRoll(function(depth, budget)
				Harness.expect(budget.gnawers <= 1, string.format("depth %d rolled %d gnawers", depth, budget.gnawers))
			end)
		end),

		Harness.test("never more than one Longarm, and never more than two broods", function()
			forEveryRoll(function(depth, budget)
				Harness.expect(
					budget.longarms <= 1,
					string.format("depth %d rolled %d longarms", depth, budget.longarms)
				)
				Harness.expect(budget.broods <= 2, string.format("depth %d rolled %d broods", depth, budget.broods))
			end)
		end),

		Harness.test("no counts are ever negative or fractional", function()
			forEveryRoll(function(_depth, budget)
				for _, count in { budget.broods, budget.gnawers, budget.longarms } do
					Harness.expect(count >= 0, "negative count")
					Harness.equal(count % 1, 0, "fractional count")
				end
			end)
		end),

		--------------------------------------------------------------------------------
		-- Depth gating
		--------------------------------------------------------------------------------

		Harness.test("the tutorial floor carries nothing at all", function()
			-- Floor 1 is where a player learns the light. Nothing from this pack may be there to
			-- muddy that lesson, exactly as the dynamite schedule leaves floor 1 clear.
			for seed = 1, 200 do
				local budget = EnemySpawnRules.budgetForDepth(1, Random.new(seed))
				Harness.equal(budget.broods, 0, "a brood spawned on floor 1")
				Harness.equal(budget.gnawers, 0, "a gnawer spawned on floor 1")
				Harness.equal(budget.longarms, 0, "a longarm spawned on floor 1")
			end
		end),

		Harness.test("no tier-3 body appears above its minimum depth, whatever the curve says", function()
			local minimum = EnemySpawnRules.tierThreeMinimumDepth()
			for depth = 1, minimum - 1 do
				for seed = 1, 200 do
					local budget = EnemySpawnRules.budgetForDepth(depth, Random.new(seed))
					Harness.equal(budget.gnawers, 0, string.format("gnawer at depth %d", depth))
					Harness.equal(budget.longarms, 0, string.format("longarm at depth %d", depth))
				end
			end
		end),

		Harness.test("grubs do appear in the shallows, and tier 3 does eventually appear", function()
			-- The gating above is only meaningful if the curves are not accidentally flat zero.
			local sawBrood = false
			for seed = 1, 400 do
				if EnemySpawnRules.budgetForDepth(3, Random.new(seed)).broods > 0 then
					sawBrood = true
					break
				end
			end
			Harness.expect(sawBrood, "no brood ever rolled on a shallow floor")

			local sawGnawer, sawLongarm = false, false
			for seed = 1, 400 do
				local budget = EnemySpawnRules.budgetForDepth(10, Random.new(seed))
				sawGnawer = sawGnawer or budget.gnawers > 0
				sawLongarm = sawLongarm or budget.longarms > 0
			end
			Harness.expect(sawGnawer, "no gnawer ever rolled deep")
			Harness.expect(sawLongarm, "no longarm ever rolled deep")
		end),

		Harness.test("the same seed and depth always produce the same budget", function()
			-- A floor is rebuilt from its seed on rejoin and in tests; a roster that re-rolled would
			-- mean the cave changed under a returning player.
			for depth = 1, 14 do
				local first = EnemySpawnRules.budgetForDepth(depth, Random.new(depth * 77))
				local second = EnemySpawnRules.budgetForDepth(depth, Random.new(depth * 77))
				Harness.equal(first.broods, second.broods)
				Harness.equal(first.gnawers, second.gnawers)
				Harness.equal(first.longarms, second.longarms)
			end
		end),

		Harness.test("a non-finite depth is treated as the first floor rather than erroring", function()
			local budget = EnemySpawnRules.budgetForDepth(0 / 0, Random.new(1))
			Harness.equal(budget.gnawers, 0)
			Harness.equal(budget.longarms, 0)
		end),

		--------------------------------------------------------------------------------
		-- Room-size gates
		--------------------------------------------------------------------------------

		Harness.test("a Gnawer's room needs real width to be dodgeable", function()
			-- A charge with nowhere to sidestep is not an encounter. ENCOUNTERS.md asks for at least
			-- 20 studs perpendicular to the likely charge line.
			Harness.expect(EnemySpawnRules.minimumGnawerRoomWidth() >= 20, "gnawer rooms may not be corridors")
		end),

		Harness.test("Gnawer and Longarm together demand a genuinely large chamber", function()
			Harness.expect(
				not EnemySpawnRules.allowsGnawerWithLongarm(24),
				"the pair must be refused in a corridor-width room"
			)
			Harness.expect(EnemySpawnRules.allowsGnawerWithLongarm(60), "the pair must be allowed in a full room")
		end),

		--------------------------------------------------------------------------------
		-- Variants
		--------------------------------------------------------------------------------

		Harness.test("every cave family maps to a dressing, and an unknown one never errors", function()
			Harness.equal(EnemyVariantRules.variantForFamily("STONE"), "regular")
			Harness.equal(EnemyVariantRules.variantForFamily("MOSS"), "moss")
			Harness.equal(EnemyVariantRules.variantForFamily("ICE"), "ice")
			-- A new cave family is authored content and must never be able to stop a floor spawning
			-- creatures; the failure mode of the alternative is a dead floor.
			Harness.equal(EnemyVariantRules.variantForFamily("SOMETHING_NEW"), "regular")
			Harness.equal(EnemyVariantRules.variantForFamily(nil), "regular")
		end),

		Harness.test("variant multipliers invert the way the pack documents", function()
			-- VARIANTS.md: moss is the tank biome, ice is the glass cannon. If these ever stop
			-- inverting, the reason to change approach per cave is gone.
			local moss = EnemyVariantRules.variantStats("moss")
			local ice = EnemyVariantRules.variantStats("ice")
			Harness.expect(moss.health > 1 and moss.speed < 1, "moss must be tankier and slower")
			Harness.expect(ice.health < 1 and ice.speed > 1, "ice must be frailer and faster")
		end),

		Harness.test("an elder is tougher, slower and larger than a regular body", function()
			Harness.expect(
				EnemyVariantRules.healthMultiplier("regular", true)
					> EnemyVariantRules.healthMultiplier("regular", false),
				"elders must be tougher"
			)
			Harness.expect(
				EnemyVariantRules.speedMultiplier("regular", true) < EnemyVariantRules.speedMultiplier("regular", false),
				"elders must be slower"
			)
			Harness.expect(EnemyVariantRules.scaleMultiplier(true) > 1, "an elder must be a silhouette change")
			Harness.equal(EnemyVariantRules.scaleMultiplier(false), 1)
		end),

		Harness.test("variant and elder multipliers compound rather than replace", function()
			-- A moss elder must be tougher than either a moss body or a regular elder.
			local mossElder = EnemyVariantRules.healthMultiplier("moss", true)
			Harness.expect(mossElder > EnemyVariantRules.healthMultiplier("moss", false), "elder must add to moss")
			Harness.expect(mossElder > EnemyVariantRules.healthMultiplier("regular", true), "moss must add to elder")
		end),

		-- THE PIN. `Logic/EnemyVariantRules` keeps its own copy of the pack's two stat tables so it can
		-- stay cold-loadable (EnemyKit calls game:GetService at load, which would drag an engine
		-- dependency into every pure module that ever reads a variant). This is the test that makes the
		-- copy safe: retune the pack and forget this file, and the suite goes red here rather than
		-- shipping a creature whose speed disagrees with its own health.
		--
		-- It requires the pack, so it is the ONE test in this suite that needs a Roblox environment.
		Harness.test("the local copy of the pack's variant stats has not drifted", function()
			local EnemyKit = require(script.Parent.Parent.Enemies.EnemyKit)
			for _, variant in { "regular", "moss", "ice" } do
				local mine = EnemyVariantRules.variantStats(variant :: any)
				local theirs = (EnemyKit.VariantStats :: any)[variant]
				Harness.expect(theirs ~= nil, "pack lost variant " .. variant)
				Harness.near(mine.health, theirs.health, 1e-9, variant .. " health drifted from the pack")
				Harness.near(mine.speed, theirs.speed, 1e-9, variant .. " speed drifted from the pack")
				Harness.near(mine.fireDamage, theirs.fireDamage, 1e-9, variant .. " fireDamage drifted from the pack")
			end
			local elder = EnemyVariantRules.elderStats()
			Harness.near(elder.health, EnemyKit.ElderStats.health, 1e-9, "elder health drifted from the pack")
			Harness.near(elder.speed, EnemyKit.ElderStats.speed, 1e-9, "elder speed drifted from the pack")
			Harness.near(elder.scale, EnemyKit.ElderStats.scale, 1e-9, "elder scale drifted from the pack")
		end),

		-- REGRESSION: `body.speed * speedMultiplier(variant, elder)` DOUBLE-APPLIES THE VARIANT TERM.
		--
		-- WaxGrub.new / StoneGnawer.new / Longarm.new each bake `stats.speed` into `self.speed` at
		-- construction. A behavior layer that then multiplies `body.speed` by the FULL
		-- `speedMultiplier(variant, elder)` — which also contains `stats.speed` — squares the variant
		-- term: this actually shipped for one work session (ice ran at 1.5625x instead of 1.25x, moss
		-- at 0.64x instead of 0.8x) before being caught by inspection rather than by a test. This pins
		-- the correct relationship so it cannot happen again silently:
		--   body.speed(variant) * elderSpeedMultiplier(elder)  ==  base * variantFactor * elderFactor
		-- applying the variant factor exactly once, however elderSpeedMultiplier is combined with an
		-- already-scaled body.speed.
		Harness.test(
			"elderSpeedMultiplier composes with a pack-scaled body.speed without squaring the variant term",
			function()
				local VARIANT_FACTOR = { regular = 1.0, moss = 0.8, ice = 1.25 }
				local ELDER_FACTOR = { [true] = 0.9, [false] = 1 }
				local BASE_SPEED = 10 -- an arbitrary stand-in for Config.<X>.speed; only ratios matter here
				for _, variant in { "regular", "moss", "ice" } do
					for _, elder in { false, true } do
						-- Exactly what WaxGrubBehavior.new / StoneGnawerBehavior.new / LongarmBehavior.new
						-- now compute: the pack's own construction, then the elder-only top-up.
						local bodySpeed = BASE_SPEED * VARIANT_FACTOR[variant]
						local finalSpeed = bodySpeed * EnemyVariantRules.elderSpeedMultiplier(elder)
						local intended = BASE_SPEED * VARIANT_FACTOR[variant] * ELDER_FACTOR[elder]
						Harness.near(
							finalSpeed,
							intended,
							1e-9,
							string.format(
								"%s elder=%s: variant factor applied more than once",
								variant,
								tostring(elder)
							)
						)
						-- The bug this catches: multiplying body.speed by the FULL multiplier instead.
						-- Assert that path actually DIFFERS from the intended value whenever the variant
						-- factor is not 1, so this test cannot pass merely because both sides happen to
						-- agree by coincidence at the regular/non-elder identity case.
						if VARIANT_FACTOR[variant] ~= 1 then
							local buggy = bodySpeed * EnemyVariantRules.speedMultiplier(variant :: any, elder)
							Harness.expect(
								math.abs(buggy - intended) > 1e-6,
								"the regression case must actually diverge from the fix, or this test proves nothing"
							)
						end
					end
				end
			end
		),
	},
}

return suite

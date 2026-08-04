--!strict

local Harness = require(script.Parent.Harness)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local DripstoneRules = require(script.Parent.Parent.Logic.DripstoneRules)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)

local suite: Harness.Suite = {
	name = "DripstoneRules",
	tests = {
		Harness.test("target counts follow the three authored curve segments", function()
			-- Derived from the config rather than transcribed, so a retune of the growth constants does
			-- not mean editing two files — what is pinned is that the shipped function IS the documented
			-- piecewise curve, not what today's numbers happen to be.
			local config = HazardsConfig.unstableDripstone
			for depth = 1, 3 do
				Harness.equal(
					DripstoneRules.targetCount(depth),
					math.floor(config.earlyLinearBase + config.earlyLinearStep * (depth - 1) + 0.5),
					string.format("floor %d must follow the shallow linear segment", depth)
				)
			end
			for depth = 4, 6 do
				Harness.equal(
					DripstoneRules.targetCount(depth),
					math.floor(config.midExponentialBase * config.midExponentialGrowth ^ (depth - 4) + 0.5),
					string.format("floor %d must follow the mid exponential segment", depth)
				)
			end
			for depth = 7, 20 do
				Harness.equal(
					DripstoneRules.targetCount(depth),
					math.floor(config.deepExponentialBase * config.deepExponentialGrowth ^ (depth - 6) + 0.5),
					string.format("floor %d must follow the deep exponential segment", depth)
				)
			end
		end),

		Harness.test("the shallow floors stay teachable while the deep ones accelerate", function()
			-- WHY THIS SHAPE. Floors 1-3 are where a player learns to read the dust, the tremor and the
			-- warning, and they cannot learn that in a room raining rock — so the shallow end stays low
			-- and nearly flat. Everything past that is what "deeper is more dangerous" is made of, and
			-- the deep segment has to pull away hard enough that floor 16 is a different proposition
			-- from floor 8 rather than the same one with a few more.
			Harness.expect(DripstoneRules.targetCount(1) <= 1, "floor 1 must not open with a hazard field")
			Harness.expect(DripstoneRules.targetCount(3) <= 3, "the teaching floors stay sparse")

			local shallowStep = DripstoneRules.targetCount(3) - DripstoneRules.targetCount(1)
			local deepStep = DripstoneRules.targetCount(10) - DripstoneRules.targetCount(8)
			Harness.expect(deepStep > shallowStep, "the curve must accelerate rather than run linear")

			Harness.expect(
				DripstoneRules.targetCount(16) >= DripstoneRules.targetCount(8) * 2,
				"floor 16 must ask for materially more than floor 8"
			)
			Harness.expect(
				DripstoneRules.targetCount(8) > DripstoneRules.targetCount(4),
				"the mid floors must out-carry the teaching floors"
			)
		end),

		Harness.test("readability is measured at the tip, and some variant can reach any rolled roof", function()
			local config = HazardsConfig.unstableDripstone
			local reach = DripstoneRules.maxReachableRoofHeight()
			-- The pool must contain something long enough to serve a near-maximum ceiling, or the game's
			-- tallest rooms are permanently hazard-free and the family that rolls them loses its
			-- signature pressure.
			Harness.expect(
				reach >= FloorsConfig.geometry.ceilingMaxHeight * 0.9,
				"no authored variant can reach the ceilings the generator actually rolls"
			)
			-- And the rule really is about the tip: a long variant is readable from a roof that refuses
			-- a short one.
			local shortest, longest = nil, nil
			for _, variant in config.variants do
				if shortest == nil or DripstoneRules.visualLength(variant) < DripstoneRules.visualLength(shortest) then
					shortest = variant
				end
				if longest == nil or DripstoneRules.visualLength(variant) > DripstoneRules.visualLength(longest) then
					longest = variant
				end
			end
			local tallRoof = config.maxEligibleTipHeight + DripstoneRules.visualLength(longest :: any) - 0.5
			Harness.expect(DripstoneRules.isReadableTip(tallRoof, longest :: any), "the long variant must serve it")
			Harness.expect(
				not DripstoneRules.isReadableTip(tallRoof, shortest :: any),
				"the short variant must still be refused there"
			)
			-- The bound is a real edge rather than a soft preference: a hair inside passes, a hair
			-- outside does not. Tested a hair either side rather than exactly on it, because exact float
			-- equality on a computed boundary is not a guarantee anything should depend on.
			local exactRoof = config.maxEligibleTipHeight + DripstoneRules.visualLength(shortest :: any)
			Harness.expect(
				DripstoneRules.isReadableTip(exactRoof - 0.01, shortest :: any),
				"a hair inside the boundary must be readable"
			)
			Harness.expect(
				not DripstoneRules.isReadableTip(exactRoof + 0.01, shortest :: any),
				"a hair above the boundary is refused"
			)
			Harness.near(DripstoneRules.tipHeight(exactRoof, shortest :: any), config.maxEligibleTipHeight, 1e-6)
		end),

		Harness.test("deep-floor target scaling never decreases", function()
			local previous = DripstoneRules.targetCount(6)
			for depth = 7, 30 do
				local current = DripstoneRules.targetCount(depth)
				Harness.expect(current >= previous, string.format("target decreased at floor %d", depth))
				previous = current
			end
			Harness.expect(
				DripstoneRules.targetCount(10) > DripstoneRules.targetCount(7),
				"deep scaling must materially increase the target"
			)
		end),

		Harness.test("fall timing is clamped and analytic motion lands exactly", function()
			local config = HazardsConfig.unstableDripstone
			for _, variant in config.variants do
				local visualLength = DripstoneRules.visualLength(variant)
				Harness.expect(visualLength > variant.length, "procedural tip extent must exceed nominal spire length")
			end
			Harness.near(DripstoneRules.fallDuration(0), config.minFallSeconds)

			local middleDuration = (config.minFallSeconds + config.maxFallSeconds) / 2
			local middleDistance = 0.5 * config.fallAcceleration * middleDuration * middleDuration
			Harness.near(DripstoneRules.fallDuration(middleDistance), middleDuration)

			local farDistance = 0.5 * config.fallAcceleration * (config.maxFallSeconds * 2) ^ 2
			Harness.near(DripstoneRules.fallDuration(farDistance), config.maxFallSeconds)

			local duration = DripstoneRules.fallDuration(middleDistance)
			Harness.near(DripstoneRules.fallOffset(-1, middleDistance), 0)
			Harness.near(DripstoneRules.fallOffset(0, middleDistance), 0)
			Harness.near(DripstoneRules.fallOffset(duration / 2, middleDistance), middleDistance * 0.25)
			Harness.near(DripstoneRules.fallOffset(duration, middleDistance), middleDistance)
			Harness.near(DripstoneRules.fallOffset(duration + 10, middleDistance), middleDistance)
		end),

		Harness.test("impact discs include their boundary and ignore vertical distance", function()
			local center = Vector3.new(4, 20, -3)
			Harness.expect(DripstoneRules.insideDisc(center, center, 3))
			Harness.expect(DripstoneRules.insideDisc(Vector3.new(7, -100, -3), center, 3))
			Harness.expect(DripstoneRules.insideDisc(Vector3.new(4, 500, 0), center, 3))
			Harness.expect(not DripstoneRules.insideDisc(Vector3.new(7.001, 20, -3), center, 3))
		end),

		Harness.test("a dripstone snuffs only a candle already below the configured threshold", function()
			local threshold = HazardsConfig.unstableDripstone.snuffBelowWaxFraction
			Harness.equal(DripstoneRules.impactOutcome(threshold - 0.001, 1), "Snuff")
			Harness.equal(DripstoneRules.impactOutcome(threshold, 1), "Damage")
			Harness.equal(DripstoneRules.impactOutcome(0.8, 0), "Damage")
		end),

		Harness.test("dripstone variants scale up to the hammer's half-wax strike", function()
			-- Indexed by ID rather than by position now that families weight the pool and new rows have
			-- been appended: a positional assertion would have started testing a different formation the
			-- moment anything was added, which is exactly the kind of test that teaches people to edit
			-- tests instead of thinking.
			local function variant(id: string)
				local found = DripstoneRules.variantById(id)
				assert(found ~= nil, "test fixture requires the " .. id .. " variant")
				return found
			end
			Harness.expect(variant("Needle").waxLossFraction < variant("Fork").waxLossFraction)
			Harness.expect(variant("Fork").waxLossFraction < variant("Hammer").waxLossFraction)
			Harness.near(variant("Hammer").waxLossFraction, 0.5)
		end),

		Harness.test("every formation stays readable, including the two family-signature rows", function()
			-- THE RULE THAT DOES NOT BEND. A formation may warn for less time, commit from further out,
			-- hit harder or cost more; it may never be something a player cannot react to. Checked as a
			-- travel budget rather than as a warning threshold, because what actually matters is whether
			-- you can leave the disc that is going to hit you.
			--
			-- Worst case is standing dead centre under it at Cup-slowed speed, which is the slowest a
			-- player can ever be while still moving.
			local SLOWEST_MOVEMENT = 8
			for _, variant in HazardsConfig.unstableDripstone.variants do
				local timeToClear = variant.impactRadius / SLOWEST_MOVEMENT
				Harness.expect(
					variant.warningSeconds > timeToClear,
					string.format(
						"%s cannot be escaped from its own centre (%.2fs of warning, %.2fs to clear)",
						variant.id,
						variant.warningSeconds,
						timeToClear
					)
				)
				-- A trigger disc smaller than the impact disc would mean ground that hurts you without
				-- ever having committed, which is an invisible hazard however long it warns for.
				Harness.expect(
					variant.triggerRadius >= variant.impactRadius,
					variant.id .. " can hit ground it never claimed"
				)
			end
		end),

		Harness.test("each family's reach counts only the formations it can actually roll", function()
			-- `maxReachableRoofHeight` decides whether a tall room is worth considering at all. Counting
			-- a variant the family will never draw would admit rooms that then burn every placement
			-- attempt and come away empty — the room would have qualified on the strength of a spire
			-- that family does not hang.
			for _, profile in CaveFamilyRules.list() do
				local familyReach = DripstoneRules.maxReachableRoofHeight(profile)
				Harness.expect(
					familyReach <= DripstoneRules.maxReachableRoofHeight(),
					profile.id .. " reaches further than the whole authored pool"
				)
				Harness.expect(
					familyReach >= FloorsConfig.geometry.ceilingMaxHeight * 0.9,
					profile.id .. " cannot reach the ceilings its own generator rolls"
				)
			end
		end),

		Harness.test("variant selection is deterministic and never returns a refused row", function()
			local ice = CaveFamilyRules.byId("ICE")
			local stone = CaveFamilyRules.byId("STONE")
			assert(ice ~= nil and stone ~= nil, "test fixture requires the shipped families")

			for _, roll in { 0, 0.25, 0.5, 0.75, 0.999999 } do
				local first = DripstoneRules.selectVariant(ice :: any, roll)
				local second = DripstoneRules.selectVariant(ice :: any, roll)
				Harness.expect(first ~= nil, "a live family must always yield a variant")
				Harness.equal((first :: any).id, (second :: any).id, "selection must be pure in its roll")
			end

			-- Hostile rolls still land on a real row rather than nil or a zero-weighted one.
			for _, roll in { -1, 2, 0 / 0 } do
				local picked = DripstoneRules.selectVariant(stone :: any, roll)
				Harness.expect(picked ~= nil, "a hostile roll must still produce a formation")
				Harness.expect(
					CaveFamilyRules.dripstoneVariantWeightMultiplier(stone :: any, (picked :: any).id) > 0,
					"selection returned a formation this family refuses"
				)
			end

			-- Sweeping the whole roll space must never surface a row the family weighted to zero.
			for step = 0, 200 do
				local picked = DripstoneRules.selectVariant(stone :: any, step / 200)
				if picked ~= nil then
					Harness.expect(
						(picked :: any).id ~= "Lance" and (picked :: any).id ~= "Mass",
						"Stone rolled a formation only another family hangs"
					)
				end
			end
		end),

		Harness.test("the first nearby fall teaches before a player is hit", function()
			local center = Vector3.new(3, 0, -8)
			Harness.expect(DripstoneRules.shouldShowFallTutorial(false, 3, 3, center, center, 36))
			Harness.expect(not DripstoneRules.shouldShowFallTutorial(true, 1, 3, center, center, 36))
			Harness.expect(not DripstoneRules.shouldShowFallTutorial(false, 4, 3, center, center, 36))
			Harness.expect(not DripstoneRules.shouldShowFallTutorial(false, 1, 3, Vector3.new(40, 0, -8), center, 36))
		end),

		Harness.test("light suppression expires at the authoritative deadline", function()
			Harness.near(DripstoneRules.lightMultiplier(9.999, 10, 0.42), 0.42)
			Harness.near(DripstoneRules.lightMultiplier(10, 10, 0.42), 1)
			Harness.near(DripstoneRules.lightMultiplier(11, 10, 0.42), 1)
			Harness.near(DripstoneRules.lightMultiplier(0, 1, -0.2), 0)
			Harness.near(DripstoneRules.lightMultiplier(0, 1, 1.2), 1)
		end),
	},
}

return suite

--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local CandleModifiers = require(script.Parent.Parent.Logic.CandleModifiers)
local Config = require(script.Parent.Parent.Config.CandleModifiers)
local LightConfig = require(script.Parent.Parent.Config.Light)

local MAX_WAX = 1.3

local function ctx(burnRate: number, isLit: boolean?): CandleModifiers.StepContext
	return {
		isLit = if isLit == nil then true else isLit,
		burnRate = burnRate,
		minBurnRate = LightConfig.minBurnRate,
		maxBurnRate = LightConfig.maxBurnRate,
		maxWax = MAX_WAX,
	}
end

-- Run `seconds` of ticks at a fixed dial and report the total wax melted plus the final state.
local function simulate(
	state: Types.CandleModifierState,
	seconds: number,
	burnRate: number,
	step: number
): (Types.CandleModifierState, number)
	local total = 0
	local current = state
	local elapsed = 0
	while elapsed < seconds - 1e-9 do
		local effects
		current, effects = CandleModifiers.step(current, step, ctx(burnRate))
		total += effects.waxGain
		elapsed += step
	end
	return current, total
end

local suite: Harness.Suite = {
	name = "CandleModifiers",
	tests = {
		Harness.test("a fresh candle is exactly neutral", function()
			local profile = CandleModifiers.profile(CandleModifiers.newState(), false)
			Harness.near(profile.drainMultiplier, 1)
			Harness.near(profile.brightnessMultiplier, 1)
			Harness.equal(profile.attractsDrawn, true)
		end),

		-- The whole point of a soft knee: every extra stack is still worth taking, but the first ones
		-- are worth the most, and the total is bounded however many a run finds.
		Harness.test("stacking bonuses are monotonic, knee-limited and capped", function()
			local cases = {
				{ read = CandleModifiers.lifeWaxDrainReduction, tuning = Config.lifeWax, name = "LifeWax" },
				{ read = CandleModifiers.brightWaxBrightnessBonus, tuning = Config.brightWax, name = "BrightWax" },
			}
			for _, case in cases do
				Harness.near(case.read(0), 0, nil, case.name .. " must be zero at no stacks")
				local previous = 0
				for stacks = 1, 400 do
					local value = case.read(stacks)
					Harness.expect(value >= previous - 1e-12, case.name .. " must never go down with a stack")
					Harness.expect(value <= case.tuning.maximum + 1e-12, case.name .. " must respect its ceiling")
					previous = value
				end
				Harness.near(case.read(400), case.tuning.maximum, 1e-9, case.name .. " must reach its ceiling")

				-- Below the knee a stack is worth face value; above it, strictly less.
				local belowKnee = math.max(1, math.floor(case.tuning.diminishingAbove / case.tuning.perStack) - 1)
				Harness.near(case.read(belowKnee), belowKnee * case.tuning.perStack, 1e-9)
				local farAbove = math.ceil(case.tuning.diminishingAbove / case.tuning.perStack) + 5
				Harness.expect(
					case.read(farAbove) < farAbove * case.tuning.perStack,
					case.name .. " must diminish past its knee"
				)
			end
		end),

		Harness.test("LifeWax cuts drain and BrightWax adds light, each only on its own side", function()
			local state = CandleModifiers.newState()
			state.lifeWax = 5
			state.brightWax = 4
			local profile = CandleModifiers.profile(state, false)
			Harness.near(profile.drainMultiplier, 1 - CandleModifiers.lifeWaxDrainReduction(5))
			Harness.near(profile.brightnessMultiplier, 1 + CandleModifiers.brightWaxBrightnessBonus(4))
			Harness.expect(profile.drainMultiplier < 1, "LifeWax must reduce drain")
			Harness.expect(profile.brightnessMultiplier > 1, "BrightWax must add light")
		end),

		-- THE CUP RULE, stated as a test because it is the one interaction the item brief called out:
		-- cupping has to land on the SAME darkness it always did, so a wick bundle cannot ride through
		-- a cupped hand. BrightWax is the candle's own wax and does ride through.
		Harness.test("cupping suppresses the wick bundle and only the wick bundle", function()
			local state = CandleModifiers.newState()
			state.brightWax = 3
			state.wicks = { wicks = 3, remaining = 120 }

			local open = CandleModifiers.profile(state, false)
			local cupped = CandleModifiers.profile(state, true)
			Harness.near(open.brightnessMultiplier - cupped.brightnessMultiplier, Config.extraWicks.brightnessBonus)

			local wicklessOpen = CandleModifiers.profile({
				lifeWax = state.lifeWax,
				brightWax = state.brightWax,
				frozen = state.frozen,
				wicks = { wicks = 0, remaining = 0 },
				sleeve = state.sleeve,
			}, false)
			Harness.near(
				cupped.brightnessMultiplier,
				wicklessOpen.brightnessMultiplier,
				1e-9,
				"a cupped candle with wicks must read exactly as the same candle without them"
			)
		end),

		Harness.test("an expired bundle stops contributing light", function()
			local state = CandleModifiers.newState()
			state.wicks = { wicks = 2, remaining = 0.02 }
			local stepped, effects = CandleModifiers.step(state, 0.5, ctx(LightConfig.maxBurnRate))
			Harness.equal(effects.wicksExpired, true)
			Harness.equal(stepped.wicks.remaining, 0)
			Harness.near(CandleModifiers.profile(stepped, false).brightnessMultiplier, 1)
		end),

		-- "3 to 5 minutes depending on your flame profile", asserted end to end rather than trusted to
		-- the two tuning constants that produce it.
		Harness.test("a wick bundle lasts between three and five minutes at every dial", function()
			for wicks = Config.extraWicks.minimumWicks, Config.extraWicks.maximumWicks do
				for _, burnRate in { LightConfig.minBurnRate, 0.5, LightConfig.maxBurnRate } do
					local state = CandleModifiers.newState()
					state.wicks = { wicks = wicks, remaining = CandleModifiers.wickSecondsFor(wicks) }
					local lasted = 0
					local step = 0.25
					while state.wicks.remaining > 0 and lasted < 1200 do
						local effects
						state, effects = CandleModifiers.step(state, step, ctx(burnRate))
						lasted += step
						if effects.wicksExpired then
							break
						end
					end
					local label = ("%d wicks at dial %.2f lasted %.0fs"):format(wicks, burnRate, lasted)
					Harness.expect(lasted >= 175, label .. " — below the three-minute floor")
					Harness.expect(lasted <= 305, label .. " — above the five-minute ceiling")
				end
			end
		end),

		Harness.test("a wick bundle only burns while the candle is lit", function()
			local state = CandleModifiers.newState()
			state.wicks = { wicks = 3, remaining = 100 }
			local stepped = CandleModifiers.step(state, 30, {
				isLit = false,
				burnRate = LightConfig.maxBurnRate,
				minBurnRate = LightConfig.minBurnRate,
				maxBurnRate = LightConfig.maxBurnRate,
				maxWax = MAX_WAX,
			})
			Harness.near(stepped.wicks.remaining, 100)
		end),

		-- FROZEN WAX pays out ONLY at the top of the dial. That condition is the item.
		Harness.test("frozen wax melts at maximum brightness and nowhere else", function()
			local banked = CandleModifiers.applyPickup(CandleModifiers.newState(), "FrozenWax", MAX_WAX, 0)
			local state = banked :: Types.CandleModifierState
			Harness.near(state.frozen.reserve, MAX_WAX * Config.frozenWax.reservePerPickup)

			local _, idleGain = simulate(state, 120, 0.5, 0.5)
			Harness.near(idleGain, 0, 1e-12, "a mid-dial candle must never melt frozen wax")

			local _, unlitGain = CandleModifiers.step(state, 120, {
				isLit = false,
				burnRate = LightConfig.maxBurnRate,
				minBurnRate = LightConfig.minBurnRate,
				maxBurnRate = LightConfig.maxBurnRate,
				maxWax = MAX_WAX,
			})
			Harness.near(unlitGain.waxGain, 0, 1e-12, "a snuffed candle must never melt frozen wax")

			-- Exactly one melt per configured interval, at exactly the configured size.
			local afterOne, oneGain = simulate(state, Config.frozenWax.meltSeconds, LightConfig.maxBurnRate, 0.5)
			Harness.near(oneGain, MAX_WAX * Config.frozenWax.meltFraction, 1e-9)
			Harness.near(afterOne.frozen.reserve, state.frozen.reserve - oneGain, 1e-9)
		end),

		Harness.test("frozen wax pays out its whole reserve and then reports itself gone", function()
			local banked = CandleModifiers.applyPickup(CandleModifiers.newState(), "FrozenWax", MAX_WAX, 0)
			local state = banked :: Types.CandleModifierState
			local reserve = state.frozen.reserve

			local total = 0
			local depletedAt = -1
			local elapsed = 0
			while elapsed < 600 do
				local effects
				state, effects = CandleModifiers.step(state, 0.5, ctx(LightConfig.maxBurnRate))
				total += effects.waxGain
				elapsed += 0.5
				if effects.frozenDepleted then
					depletedAt = elapsed
					break
				end
			end

			Harness.near(total, reserve, 1e-9, "the whole reserve must reach the meter, no more and no less")
			Harness.near(state.frozen.reserve, 0)
			-- 5% of a candle at 0.25% per ten seconds is twenty melts: about 200 seconds at maximum.
			Harness.expect(depletedAt > 0, "the block must eventually report itself consumed")
			Harness.near(depletedAt, 200, 1.0)
		end),

		-- DELIBERATELY UNCAPPED. Frozen Wax is temporary: every unit is spent the moment it is earned,
		-- and only by holding the dial at maximum. A ceiling here would only punish a player for
		-- finding a third block, so blocks stack cleanly and the MELT RATE is the only limiter.
		Harness.test("frozen wax blocks stack without a ceiling", function()
			local state = CandleModifiers.newState()
			for blocks = 1, 10 do
				state = CandleModifiers.applyPickup(state, "FrozenWax", MAX_WAX, 0) :: Types.CandleModifierState
				Harness.near(
					state.frozen.reserve,
					MAX_WAX * Config.frozenWax.reservePerPickup * blocks,
					1e-9,
					("%d blocks must bank %d x 5%% of the candle"):format(blocks, blocks)
				)
			end
			-- Ten blocks is fifty percent of a candle, and paying it back takes over half an hour of
			-- maximum brightness — the rate, not a cap, is what keeps it from being a second wax meter.
			local perSecondAtMax = (MAX_WAX * Config.frozenWax.meltFraction) / Config.frozenWax.meltSeconds
			Harness.expect(
				state.frozen.reserve / perSecondAtMax > 1800,
				"a large reserve must still cost real time at maximum brightness to recover"
			)
		end),

		Harness.test("wick count rolls across its whole authored range", function()
			local seen: { [number]: boolean } = {}
			for index = 0, 100 do
				local wicks = CandleModifiers.rollWickCount(index / 100)
				Harness.expect(
					wicks >= Config.extraWicks.minimumWicks and wicks <= Config.extraWicks.maximumWicks,
					"a rolled wick count must stay inside its authored range"
				)
				seen[wicks] = true
			end
			for wicks = Config.extraWicks.minimumWicks, Config.extraWicks.maximumWicks do
				Harness.expect(seen[wicks] == true, ("%d wicks must be reachable"):format(wicks))
			end
		end),

		-- THE SLEEVE'S HEADLINE PROMISE: 40% off, five hits.
		Harness.test("a fresh sleeve takes its configured cut for its configured number of hits", function()
			local state =
				CandleModifiers.applyPickup(CandleModifiers.newState(), "CandleSleeve", MAX_WAX, 0) :: Types.CandleModifierState
			Harness.near(state.sleeve.charges, Config.sleeve.charges)

			local absorbed = 0
			local broke = false
			for _ = 1, Config.sleeve.charges do
				local surviving, updated, ended = CandleModifiers.absorb(
					state,
					"DamageThreat",
					{ kind = "Hit", seconds = Config.sleeve.referenceHitSeconds }
				)
				Harness.near(surviving, 1 - Config.sleeve.damageReduction)
				state = updated
				absorbed += 1
				broke = ended
			end
			Harness.equal(absorbed, Config.sleeve.charges)
			Harness.equal(broke, true, "the fifth reference hit must be the one that tears it")

			local afterBreak = CandleModifiers.absorb(state, "DamageThreat", nil)
			Harness.near(afterBreak, 1, nil, "a torn sleeve must stop protecting")
		end),

		-- "Adjusting for enemies that hit fast": a swarm must not shred five charges in a second.
		Harness.test("a fast attacker spends a fraction of a charge per swing", function()
			local fast = CandleModifiers.chargeCostFor({ kind = "Hit", seconds = 0.3 })
			local slow = CandleModifiers.chargeCostFor({ kind = "Hit", seconds = 3 })
			Harness.expect(fast < 1, "a fast swing must cost less than a whole charge")
			Harness.expect(fast >= Config.sleeve.minimumChargeCost, "no cadence may make protection free")
			Harness.near(slow, 1, nil, "a slow swing must never cost more than one charge")

			-- The real promise: a sleeve survives more SWINGS from a fast attacker than a slow one,
			-- while lasting a comparable number of SECONDS against both.
			local function swingsSurvived(cadence: number): number
				local state =
					CandleModifiers.applyPickup(CandleModifiers.newState(), "CandleSleeve", MAX_WAX, 0) :: Types.CandleModifierState
				local swings = 0
				while state.sleeve.charges > 0 and swings < 500 do
					local _, updated =
						CandleModifiers.absorb(state, "DamageThreat", { kind = "Hit", seconds = cadence })
					state = updated
					swings += 1
				end
				return swings
			end
			local fastSwings = swingsSurvived(0.3)
			local slowSwings = swingsSurvived(2.4)
			Harness.expect(
				fastSwings > slowSwings,
				"a sleeve must survive more swings from a fast attacker than from a slow one"
			)
			Harness.equal(slowSwings, Config.sleeve.charges)
		end),

		Harness.test("a continuous drain spends the sleeve by the second, not by the tick", function()
			local state =
				CandleModifiers.applyPickup(CandleModifiers.newState(), "CandleSleeve", MAX_WAX, 0) :: Types.CandleModifierState
			local dt = 1 / 20
			local seconds = 0
			while state.sleeve.charges > 0 and seconds < 60 do
				local _, updated =
					CandleModifiers.absorb(state, "EnvironmentalFire", { kind = "Continuous", seconds = dt })
				state = updated
				seconds += dt
			end
			-- Five charges at a 1.2 s reference is six seconds of standing in it — NOT five ticks.
			Harness.near(seconds, Config.sleeve.charges * Config.sleeve.referenceHitSeconds, 0.2)
		end),

		Harness.test("the sleeve protects exactly the configured damage sources", function()
			local state =
				CandleModifiers.applyPickup(CandleModifiers.newState(), "CandleSleeve", MAX_WAX, 0) :: Types.CandleModifierState
			local everySource: { Types.WaxSource } = {
				"PassiveBurn",
				"MovementWalk",
				"MovementRun",
				"ToolFlare",
				"ToolDecoy",
				"ToolCup",
				"ToolOther",
				"DamageThreat",
				"DamageWater",
				"DamageDripstone",
				"ReviveCost",
				"Extraction",
				"DeathLoss",
				"EnvironmentalFire",
				"SeamBlast",
				"Other",
			}
			for _, source in everySource do
				local surviving = CandleModifiers.absorb(state, source, nil)
				if Config.sleeve.protects[source] then
					Harness.near(surviving, 1 - Config.sleeve.damageReduction, nil, source .. " should be softened")
				else
					Harness.near(surviving, 1, nil, source .. " must pass through a sleeve untouched")
				end
			end
			-- Water in particular: the water rule is absolute and a sleeve must never look like an answer to it.
			Harness.equal(Config.sleeve.protects.DamageWater ~= true, true)
		end),

		Harness.test("a candle with no sleeve is never charged for one", function()
			local bare = CandleModifiers.newState()
			local surviving, updated, broke = CandleModifiers.absorb(bare, "DamageThreat", nil)
			Harness.near(surviving, 1)
			Harness.equal(broke, false)
			Harness.equal(updated.sleeve.charges, 0)
		end),
	},
}

return suite

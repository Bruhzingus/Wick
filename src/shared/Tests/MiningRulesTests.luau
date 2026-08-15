--!strict

local Harness = require(script.Parent.Harness)
local MiningRules = require(script.Parent.Parent.Logic.MiningRules)
local MiningConfig = require(script.Parent.Parent.Config.Mining)
local WaxConfig = require(script.Parent.Parent.Config.Wax)

local deposit = MiningConfig.deposit
local timing = MiningConfig.timing
-- The row every seam falls back to, and the one the historical tests below were written against.
local STANDARD = MiningRules.resolveRow("Standard")
-- The one row that cannot be worked out. Resolved by id rather than by the flag so that the tests
-- fail loudly if it is ever removed, instead of quietly asserting nothing.
local EXPLOSIVE = MiningRules.resolveRow("Explosive")

-- Seconds into a swing at which the marker sits exactly on a given sweep phase, AT A TIER. Both
-- durations scale with the ladder, so "how long until the marker is there" is only answerable once
-- you say which rung the stance is on.
local function elapsedAtPhase(phase: number, tier: number?): number
	return MiningRules.effectiveWindupSeconds(tier) + phase * MiningRules.effectiveSweepSeconds(tier)
end

-- The historical fixture, pinned to tier 1. Every rule below that does not name a tier is exercising
-- something other than the ladder — payout, depletion, the wandering band — and tier 1 is the honest
-- default for those, because it is the tier every stance actually opens at.
local PERFECT = elapsedAtPhase(timing.perfectCenter % 1, 1)

-- How many rungs the ladder tests walk. The ladder itself has no top, so "every tier" is not a loop
-- anybody can write; going a few past the rung where the sweep floor bites is what proves it keeps
-- ANSWERING for tiers nobody authored, rather than proving it keeps changing.
local TIERS_EXERCISED = MiningRules.saturationTier() + 3

local function baseRequest(): MiningRules.StrikeRequest
	return {
		alive = true,
		finished = false,
		snuffed = false,
		isLit = true,
		isCupping = false,
		playerDepth = 3,
		depositDepth = 3,
		depositDepleted = false,
		distance = 1,
		hasLineOfSight = true,
		now = 100,
		nextStrikeAt = 0,
		hasOpenSwing = false,
	}
end

local suite: Harness.Suite = {
	name = "MiningRules",
	tests = {
		Harness.test("a Standard seam's clean strikes deplete it, and no fewer", function()
			local progress = 0
			for strike = 1, STANDARD.cleanStrikes - 1 do
				local outcome = MiningRules.resolveStrike(progress, PERFECT)
				Harness.equal(outcome.accuracy, "Perfect", "the configured centre must score Perfect")
				Harness.equal(outcome.depleted, false, "a deposit must not break on strike " .. strike)
				progress = outcome.progress
			end
			local final = MiningRules.resolveStrike(progress, PERFECT)
			Harness.equal(final.depleted, true, "the configured clean-strike count must break the seam")
		end),

		Harness.test("fumbling costs strikes — the ring is the whole skill lever", function()
			-- A miss must advance the seam (grinding is allowed) but strictly less than a clean hit,
			-- or the timing window would be decoration.
			-- Checked against EVERY row, not just Standard: the bands are proportions of a clean strike now,
			-- so a row with a different length must still order them the same way.
			for _, row in MiningConfig.rows do
				local miss = MiningRules.progressForAccuracy("Miss", row)
				local good = MiningRules.progressForAccuracy("Good", row)
				local perfect = MiningRules.progressForAccuracy("Perfect", row)
				Harness.expect(miss > 0, row.id .. ": a miss must still chip the seam")
				Harness.expect(
					miss < good and good < perfect,
					row.id .. ": the three bands must be strictly ordered, or accuracy buys nothing"
				)
				Harness.expect(
					math.ceil(1 / miss) > row.cleanStrikes,
					row.id .. ": missing every swing must take more swings than hitting every one"
				)
			end
		end),

		Harness.test("every row is a real, readable trade against the Standard seam", function()
			-- The pay rate is now stated directly as `gramsPerStrike`, so a row that beats Standard has to
			-- pay for it with exposure a player can see (a burn requirement, a longer stance, a second
			-- miner, a rock that might go off) rather than with a bigger number alone.
			local baseline = STANDARD.gramsPerStrike
			for _, row in MiningConfig.rows do
				Harness.expect(row.cleanStrikes >= 1 and row.cleanStrikes % 1 == 0, row.id .. " needs whole strikes")
				Harness.expect(
					row.gramsPerStrike >= 1 and row.gramsPerStrike % 1 == 0,
					row.id .. " needs a whole number of grams per strike"
				)
				Harness.expect(row.maxPaidMiners >= 1, row.id .. " must pay at least one miner")
				Harness.expect(row.minDepth >= 1, row.id .. " needs a legal minimum depth")
				Harness.expect(
					row.minBurnFraction >= 0 and row.maxBurnFraction <= 1 and row.minBurnFraction <= row.maxBurnFraction,
					row.id .. " needs a valid burn window"
				)

				if row.gramsPerStrike > baseline then
					Harness.expect(
						row.minBurnFraction > 0
							or row.maxBurnFraction < 1
							or row.minDepth > STANDARD.minDepth
							or row.neverDepletes,
						row.id .. " out-earns Standard per strike but risks nothing extra for it"
					)
				end
				-- A CO-OPERATIVE ROW'S RATE MUST BE DIVIDED BY THE NUMBER OF PEOPLE IT PAYS, not merely
				-- capped at the baseline. Every miner in a stance is paid for every strike ANYBODY lands,
				-- so `gramsPerStrike x maxPaidMiners` is what one swing of real work actually costs the
				-- economy — and if that product exceeds the Standard rate, a pair out-earns a solo miner
				-- per swing of effort and the row has stopped being a co-operation bonus.
				--
				-- This caught a real regression: converting Twin from the old lump sum left it at the full
				-- 50g, which paid a solo miner Standard's rate for double the time (it is supposed to be
				-- half) and turned one shared rock into 600g instead of 300g. A `<= baseline` check passed
				-- it happily. This one does not.
				if row.maxPaidMiners > 1 then
					Harness.expect(
						row.gramsPerStrike * row.maxPaidMiners <= baseline,
						string.format(
							"%s pays %d miners %dg each per strike (%dg of work), beating the Standard rate of"
								.. " %dg — that is double-dipping",
							row.id,
							row.maxPaidMiners,
							row.gramsPerStrike,
							row.gramsPerStrike * row.maxPaidMiners,
							baseline
						)
					)
				end
			end
		end),

		Harness.test("a landed swing pays its row, and a fumble pays nothing at all", function()
			-- The rule per-swing payment exists to create: reading the rail IS the income. A Miss still
			-- chips the rock and is still the loudest thing mining does; it simply pays zero.
			for _, row in MiningConfig.rows do
				Harness.equal(MiningRules.gramsForAccuracy("Perfect", row), row.gramsPerStrike, row.id .. ": perfect")
				Harness.equal(
					MiningRules.gramsForAccuracy("Good", row),
					math.floor(row.gramsPerStrike * timing.goodFractionOfPerfect),
					row.id .. ": good"
				)
				Harness.equal(MiningRules.gramsForAccuracy("Miss", row), 0, row.id .. ": a fumble must pay nothing")
				-- Whole grams only, at every band: there is no sub-gram anything in this economy.
				for _, accuracy in { "Perfect", "Good", "Miss" } do
					local grams = MiningRules.gramsForAccuracy(accuracy :: any, row)
					Harness.equal(grams % 1, 0, row.id .. ": fractional grams from a " .. accuracy)
					Harness.expect(grams >= 0, row.id .. ": negative grams from a " .. accuracy)
				end
				-- A Good strike must be worth strictly less than a Perfect one, or the rail's tightest band
				-- buys nothing at all.
				Harness.expect(
					MiningRules.gramsForAccuracy("Good", row) < MiningRules.gramsForAccuracy("Perfect", row),
					row.id .. ": Good must pay less than Perfect"
				)
			end
			-- `resolveStrike` must report the same number, since that is the one the server banks.
			Harness.equal(MiningRules.resolveStrike(0, PERFECT).grams, STANDARD.gramsPerStrike)
		end),

		Harness.test("a row's clean-strike count is exactly what breaks it", function()
			-- Per-row progress is derived (1 / cleanStrikes), so this catches a rounding error that would
			-- make a nine-strike seam take ten.
			for _, row in MiningConfig.rows do
				if row.neverDepletes then
					continue
				end
				local progress = 0
				for strike = 1, row.cleanStrikes - 1 do
					local outcome = MiningRules.resolveStrike(progress, PERFECT, nil, row)
					Harness.equal(
						outcome.depleted,
						false,
						string.format("%s must not break on clean strike %d of %d", row.id, strike, row.cleanStrikes)
					)
					progress = outcome.progress
				end
				Harness.equal(
					MiningRules.resolveStrike(progress, PERFECT, nil, row).depleted,
					true,
					row.id .. " must break on exactly its configured clean-strike count"
				)
				Harness.equal(MiningRules.cleanStrikesRemaining(0, row), row.cleanStrikes)
			end
		end),

		Harness.test("a never-depleting row cannot be worked out, however long it is struck", function()
			-- The Explosive Seam's defining property, and the one thing that could quietly break it: if
			-- `resolveStrike` ever let progress cross the line, the rock would break instead of exploding
			-- and the whole row would silently become a very ordinary seam.
			for _, row in MiningConfig.rows do
				if not row.neverDepletes then
					continue
				end
				local progress = 0
				for strike = 1, row.cleanStrikes * 20 do
					local outcome = MiningRules.resolveStrike(progress, PERFECT, nil, row)
					Harness.equal(
						outcome.depleted,
						false,
						string.format("%s broke on strike %d — it must never break", row.id, strike)
					)
					Harness.expect(outcome.grams > 0, row.id .. " must keep paying for as long as it is worked")
					progress = outcome.progress
				end
				Harness.expect(progress <= 1, row.id .. ": progress must stay inside its bar")
				-- And the readout must refuse to promise a count it cannot honour.
				Harness.equal(
					MiningRules.cleanStrikesRemaining(progress, row),
					-1,
					row.id .. ": a seam with no end must not report a number of swings"
				)
			end
		end),

		Harness.test("the clean-strikes readout never lies, at any progress, on any row", function()
			-- THE bug this pins. Progress accumulates as `n` copies of `1 / n`, which does not reach 1 in
			-- binary floating point for most n — six sixths land on 0.9999999999999999. Without a
			-- tolerance, a six-strike Twin Seam took SEVEN swings and the readout promised two more clean
			-- strikes when one would break it. The player counts their swings; the game has to agree.
			for _, row in MiningConfig.rows do
				if row.neverDepletes then
					continue
				end
				local progress = 0
				for strike = 1, row.cleanStrikes do
					Harness.equal(
						MiningRules.cleanStrikesRemaining(progress, row),
						row.cleanStrikes - (strike - 1),
						string.format("%s: before strike %d of %d", row.id, strike, row.cleanStrikes)
					)
					progress = MiningRules.resolveStrike(progress, PERFECT, nil, row).progress
				end
				Harness.equal(MiningRules.cleanStrikesRemaining(progress, row), 0, row.id .. ": broken means zero")
				Harness.equal(progress, 1, row.id .. ": a broken seam must read as exactly full")
			end
		end),

		Harness.test("a bright-only row refuses a dim candle and accepts a flare", function()
			local bright: MiningRules.DepositRow? = nil
			for _, row in MiningConfig.rows do
				if row.minBurnFraction > 0 then
					bright = row
					break
				end
			end
			if bright == nil then
				return
			end
			local row = bright :: MiningRules.DepositRow
			local required = MiningRules.requiredBurnRate(row)
			Harness.expect(required > 0, row.id .. " must require a real burn rate")

			local dim = baseRequest()
			dim.row = row
			dim.burnRate = required - 0.01
			Harness.equal(select(2, MiningRules.canBeginStrike(dim)), "TooDim")
			-- And it must keep refusing mid-stance, or a player could open at full burn and finish dark.
			Harness.equal(select(2, MiningRules.canResolveStrike(dim)), "TooDim")

			local bright2 = baseRequest()
			bright2.row = row
			bright2.burnRate = required
			Harness.equal(MiningRules.canBeginStrike(bright2), true, "exactly the required burn must qualify")

			-- A Flare always qualifies as the fast alternative.
			local flaring = baseRequest()
			flaring.row = row
			flaring.burnRate = 0
			flaring.isFlaring = true
			Harness.equal(MiningRules.canBeginStrike(flaring), true, "a live flare must always qualify")

			local cappedMaximum = required * 0.8
			local capped = baseRequest()
			capped.row = row
			capped.minimumBurnRate = 0
			capped.maximumBurnRate = cappedMaximum
			capped.burnRate = MiningRules.requiredBurnRate(row, 0, cappedMaximum)
			Harness.equal(
				MiningRules.canBeginStrike(capped),
				true,
				"a capped candle at its reachable bright threshold must still work the seam"
			)

			-- A missing reading fails CLOSED: one lost swing beats handing out an unearned row.
			local unknown = baseRequest()
			unknown.row = row
			unknown.burnRate = nil
			Harness.equal(select(2, MiningRules.canBeginStrike(unknown)), "TooDim")
			local nan = baseRequest()
			nan.row = row
			nan.burnRate = 0 / 0
			Harness.equal(select(2, MiningRules.canBeginStrike(nan)), "TooDim")
		end),

		Harness.test("a dim-only row accepts a low flame and refuses heat or a flare", function()
			local row = MiningRules.rowById("Dim")
			Harness.expect(row ~= nil, "the Dim Seam row must exist")
			if row == nil then
				return
			end
			local maximum = MiningRules.maximumBurnRate(row)
			Harness.expect(maximum > 0, "Dim Seam must leave a playable lit window")
			Harness.expect(maximum < MiningRules.maximumBurnRate(STANDARD), "Dim Seam must cap the dial")

			local low = baseRequest()
			low.row = row
			low.burnRate = maximum
			Harness.equal(MiningRules.canBeginStrike(low), true, "the authored ceiling must qualify")

			local hot = baseRequest()
			hot.row = row
			hot.burnRate = maximum + 0.01
			Harness.equal(select(2, MiningRules.canBeginStrike(hot)), "TooBright")
			Harness.equal(select(2, MiningRules.canResolveStrike(hot)), "TooBright")

			local flaring = baseRequest()
			flaring.row = row
			flaring.burnRate = 0
			flaring.isFlaring = true
			Harness.equal(select(2, MiningRules.canBeginStrike(flaring)), "TooBright")

			local unknown = baseRequest()
			unknown.row = row
			unknown.burnRate = nil
			Harness.equal(select(2, MiningRules.canBeginStrike(unknown)), "TooBright")
		end),

		Harness.test("row selection respects depth, unlocks, and the rollback flag", function()
			local nothingOwned: { [string]: boolean } = {}
			-- With nothing unlocked, only the always-available row can ever be chosen, at any depth and
			-- for any roll — including hostile ones.
			for depth = 1, 20 do
				for _, roll in { 0, 0.5, 0.999999, -1, 2, 0 / 0 } do
					Harness.equal(
						MiningRules.selectRow(depth, nothingOwned, roll).unlockNode,
						nil,
						"an unowned row must never be selected"
					)
				end
			end

			-- A gated row must never appear above its own minimum depth, even fully unlocked.
			local allOwned: { [string]: boolean } = {}
			for _, row in MiningConfig.rows do
				if row.unlockNode ~= nil then
					allOwned[row.unlockNode] = true
				end
			end
			for _, row in MiningConfig.rows do
				if row.minDepth <= 1 then
					continue
				end
				for depth = 1, row.minDepth - 1 do
					for _, roll in { 0, 0.25, 0.5, 0.75, 0.999999 } do
						Harness.expect(
							MiningRules.selectRow(depth, allOwned, roll).id ~= row.id,
							string.format("%s must not appear at depth %d", row.id, depth)
						)
					end
				end
			end
		end),

		Harness.test("an unknown or absent row degrades to Standard rather than breaking a run", function()
			-- A floor built before a config change, or a save restored across one, must stay minable.
			Harness.equal(MiningRules.resolveRow(nil).id, STANDARD.id)
			Harness.equal(MiningRules.resolveRow("").id, STANDARD.id)
			Harness.equal(MiningRules.resolveRow("NoSuchRow").id, STANDARD.id)
			Harness.equal(MiningRules.rowById("NoSuchRow"), nil)
		end),

		Harness.test("a fumble is the loud one, and a break is louder still", function()
			Harness.equal(MiningRules.noiseKindFor("Perfect", false), "MineStrikeClean")
			Harness.equal(MiningRules.noiseKindFor("Good", false), "MineStrikeClean")
			Harness.equal(
				MiningRules.noiseKindFor("Miss", false),
				"MineStrikeFumble",
				"a fumbled swing must announce itself differently — skill has to buy safety"
			)
			-- Depletion overrides the band: breaking the seam is one loud event however it landed.
			Harness.equal(MiningRules.noiseKindFor("Miss", true), "MineBreak")
			Harness.equal(MiningRules.noiseKindFor("Perfect", true), "MineBreak")
		end),

		Harness.test("releasing during the wind-up is a miss, not a free retry", function()
			-- Asserted at every tier, because the wind-up is one of the two durations the ladder scales:
			-- a tier that moved the sweep without moving its lead-in would put the marker in motion
			-- before the rail said it was live.
			for tier = 1, TIERS_EXERCISED do
				local windup = MiningRules.effectiveWindupSeconds(tier)
				Harness.isNil(
					MiningRules.sweepPhase(0, tier),
					"tier " .. tier .. ": the sweep must not be live before the wind-up ends"
				)
				Harness.isNil(MiningRules.sweepPhase(windup - 0.001, tier))
				Harness.equal(MiningRules.accuracyForElapsed(0, nil, tier), "Miss")
				Harness.expect(
					MiningRules.sweepPhase(windup, tier) ~= nil,
					"tier " .. tier .. ": the sweep must be live the instant the wind-up ends"
				)
			end
			-- And the boundary genuinely MOVES with the tier, or the scaling is decorative: an elapsed
			-- that is still wind-up at the bottom of the ladder is a live sweep at the top.
			local slowWindup = MiningRules.effectiveWindupSeconds(1)
			Harness.isNil(MiningRules.sweepPhase(slowWindup - 0.001, 1))
			Harness.expect(
				MiningRules.sweepPhase(slowWindup - 0.001, TIERS_EXERCISED) ~= nil,
				"a climbed wind-up must be strictly shorter than the bottom rung's"
			)
		end),

		Harness.test("the tier ladder is exactly the authored escalation", function()
			-- A TRIPWIRE ON THE TUNING, NOT ON THE CODE. These are the numbers the ladder was designed
			-- and signed off against; changing one is allowed and changing it silently is not.
			Harness.near(timing.tiers.widthMultiplier, 1, 1e-9, "the band must not resize with the tier")
			Harness.near(timing.tiers.baseSpeedMultiplier, 1.2, 1e-9, "where a fresh stance opens")
			Harness.near(timing.tiers.speedRatioPerTier, 0.775, 1e-9, "what one Perfect is worth")
			Harness.near(timing.tiers.minSweepSeconds, 0.6, 1e-9, "the 30 fps frame-quantization floor")

			-- ...and what that formula actually produces in the player's hands, which is the thing the
			-- design is stated in and the thing Config/Mining's own comment promises. Milliseconds, because
			-- a fraction of a sweep means nothing when the sweep length is also moving. The last entry is
			-- the floor, repeated to show it is genuinely reached rather than merely approached.
			local sweeps = { 1.38, 1.0695, 0.8288625, 0.6423684, 0.6, 0.6 }
			for tier, expectedSweep in sweeps do
				Harness.near(
					MiningRules.effectiveSweepSeconds(tier),
					expectedSweep,
					1e-4,
					string.format("tier %d's sweep must be %.3f s", tier, expectedSweep)
				)
				Harness.near(
					MiningRules.effectivePerfectHalfWidth(tier) * MiningRules.effectiveSweepSeconds(tier),
					expectedSweep * timing.perfectHalfWidth,
					1e-6,
					string.format("tier %d's Perfect aperture", tier)
				)
			end

			-- THE FLOOR IS A HARDWARE LIMIT, and this is the assertion that says so. A click is sampled
			-- once per rendered frame, so at 30 fps it lands in a 33 ms bucket; the tightest rung has to
			-- stay wide enough to be landable through that, or the top of the ladder is a dice roll on a
			-- phone. Stated against the frame time directly so lowering `minSweepSeconds` for feel fails
			-- here with the reason attached rather than shipping quietly.
			local frameSeconds = 1 / 30
			local tightestHalfWidth = MiningRules.effectivePerfectHalfWidth(1)
				* MiningRules.effectiveSweepSeconds(TIERS_EXERCISED)
			Harness.expect(
				tightestHalfWidth * 2 >= frameSeconds * 1.5,
				string.format(
					"the fastest rung's Perfect window is %.0f ms, under 1.5 frames at 30 fps — a mobile"
						.. " player cannot aim inside their own input quantization",
					tightestHalfWidth * 2000
				)
			)
			-- ...and the Good shoulder has to stay comfortably clear of it, so a phone player who misses
			-- Perfect at the top drops ONE rung instead of being fumbled off the ladder by their hardware.
			Harness.expect(
				MiningRules.effectiveGoodHalfWidth(1) * MiningRules.effectiveSweepSeconds(TIERS_EXERCISED)
					>= frameSeconds * 2,
				"the fastest rung's Good shoulder must absorb at least two frames of input quantization"
			)
		end),

		Harness.test("the ladder has no top rung, it only runs out of room to accelerate", function()
			-- THE property the streak mechanic rests on. A capped ladder makes the escalation something a
			-- player FINISHES, which turns "how long can you hold a run" into a short intro to a fixed
			-- difficulty — the exact thing this replaced.
			local saturation = MiningRules.saturationTier()
			Harness.expect(saturation > 1, "a ladder that saturates on its first rung never escalates")

			-- Below saturation every rung is strictly faster than the one under it.
			for tier = 2, saturation - 1 do
				Harness.expect(
					MiningRules.effectiveSweepSeconds(tier) < MiningRules.effectiveSweepSeconds(tier - 1),
					"tier " .. tier .. " must sweep strictly faster than the rung below"
				)
			end
			-- At and past it the rail has hit the floor and stops changing — but it still ANSWERS, for any
			-- tier at all, which is what makes the climb unbounded rather than clamped.
			Harness.near(
				MiningRules.effectiveSweepSeconds(saturation),
				timing.tiers.minSweepSeconds,
				1e-9,
				"the saturation rung must sit exactly on the floor"
			)
			for _, tier in { saturation + 1, saturation + 5, saturation + 50, 1e6 } do
				Harness.near(
					MiningRules.effectiveSweepSeconds(tier),
					timing.tiers.minSweepSeconds,
					1e-9,
					"tier " .. tier .. " must still resolve, and must resolve to the floor"
				)
			end
			-- The rung below saturation must NOT be on the floor, or the reported saturation point is a
			-- rung late and the config comment is lying about where the ladder stops moving.
			Harness.expect(
				MiningRules.effectiveSweepSeconds(saturation - 1) > timing.tiers.minSweepSeconds + 1e-9,
				"saturation must name the FIRST rung on the floor"
			)
		end),

		Harness.test("no rung is ever more forgiving than the one below, and none is a wall", function()
			local previousAperture = math.huge
			local previousSweep = math.huge
			local previousWidth = math.huge
			for tier = 1, TIERS_EXERCISED do
				local perfect = MiningRules.effectivePerfectHalfWidth(tier)
				local good = MiningRules.effectiveGoodHalfWidth(tier)
				local sweep = MiningRules.effectiveSweepSeconds(tier)
				local windup = MiningRules.effectiveWindupSeconds(tier)

				Harness.expect(perfect > 0 and good > 0, "tier " .. tier .. " must leave a hittable window")
				Harness.expect(sweep > 0 and windup > 0, "tier " .. tier .. " must have a real sweep and wind-up")
				-- THE thing that keeps the ladder a slope rather than a cliff: overreaching at the top of it
				-- has to land Good and cost one rung, never fumble and cost the whole climb.
				Harness.expect(good > perfect, "tier " .. tier .. " must keep a Good shoulder around its core")
				Harness.expect(
					good < 0.5,
					"tier " .. tier .. "'s Good band must not swallow the ring — half a sweep is everything"
				)

				-- The rail never gets SLOWER on a promotion, and THE TARGET NEVER CHANGES SIZE. The second
				-- half of that is the design decision, not a side effect: escalation is carried entirely
				-- by the marker's speed, so the thing the player is aiming at is the same object on screen
				-- at every rung. A tier that resized the band would be the game shrinking the target
				-- without telling anybody. (Strict acceleration is asserted up to saturation by its own
				-- test; past the floor the correct behaviour is to hold, not to keep shrinking.)
				Harness.expect(sweep <= previousSweep, "tier " .. tier .. " must not sweep slower than the rung below")
				if tier > 1 then
					Harness.near(
						perfect,
						previousWidth,
						1e-12,
						"tier " .. tier .. " resized the Perfect band — only the sweep speed may change"
					)
				end
				-- And in absolute time — the only unit the player experiences — no rung is ever more
				-- forgiving than the one below it.
				local aperture = perfect * sweep
				Harness.expect(
					aperture <= previousAperture,
					"tier " .. tier .. " must not be a wider window in real time than the rung below it"
				)
				previousAperture = aperture
				previousSweep = sweep
				previousWidth = perfect
			end
			-- Stated once more against the config directly, so the property survives someone reaching for
			-- `widthMultiplier` as a difficulty dial: both bands are ONE size for the whole ladder.
			for tier = 1, TIERS_EXERCISED do
				Harness.near(
					MiningRules.effectivePerfectHalfWidth(tier),
					timing.perfectHalfWidth,
					1e-12,
					"tier " .. tier .. " must play at the authored Perfect width"
				)
				Harness.near(
					MiningRules.effectiveGoodHalfWidth(tier),
					timing.goodHalfWidth,
					1e-12,
					"tier " .. tier .. " must play at the authored Good width"
				)
			end
			-- The wind-up scales with the sweep rather than staying put, or it would become an ever-larger
			-- share of the beat and eat the read it exists to announce. Asserted as a constant RATIO, so
			-- it holds on the floored rungs as well as the accelerating ones.
			local authoredShare = deposit.swingWindupSeconds / timing.sweepSeconds
			for tier = 1, TIERS_EXERCISED do
				Harness.near(
					MiningRules.effectiveWindupSeconds(tier) / MiningRules.effectiveSweepSeconds(tier),
					authoredShare,
					1e-9,
					"tier " .. tier .. ": the wind-up must stay the same share of the beat"
				)
			end
		end),

		Harness.test("the ladder is climbed one rung at a time and lost all at once", function()
			-- A Perfect promotes exactly one rung, and there is nothing above to stop at. Walked well past
			-- the saturation point, because the TIER keeps climbing even once the sweep cannot.
			for tier = 1, TIERS_EXERCISED + 20 do
				Harness.equal(MiningRules.nextTier(tier, "Perfect"), tier + 1, "a Perfect must advance exactly one")
			end
			-- A Good drops exactly one and floors, which is what settles a player at the fastest rail they
			-- can actually hold instead of yo-yoing them to the bottom for one overreach.
			for tier = 2, TIERS_EXERCISED + 20 do
				Harness.equal(MiningRules.nextTier(tier, "Good"), tier - 1, "a Good must drop exactly one")
			end
			Harness.equal(MiningRules.nextTier(1, "Good"), 1, "the bottom rung must not fall through the floor")
			-- A Miss erases the whole climb, from anywhere. This is what keeps the fumble the real penalty
			-- here exactly as it is everywhere else in the strike rules.
			for _, tier in { 1, 2, 5, 40, 5000 } do
				Harness.equal(MiningRules.nextTier(tier, "Miss"), 1, "a Miss must reset the ladder from tier " .. tier)
			end
			-- A caller with no tier yet is a fresh stance, and a fresh stance is tier 1.
			Harness.equal(MiningRules.nextTier(nil, "Perfect"), 2)
			Harness.equal(MiningRules.nextTier(nil, "Good"), 1)
			Harness.equal(MiningRules.nextTier(nil, "Miss"), 1)
			-- Hostile input cannot fall below the bottom or produce a fractional rung. There is
			-- deliberately no upper bound to violate.
			for _, hostile in { -50, 0, 0 / 0, math.huge, -math.huge } do
				local promoted = MiningRules.nextTier(hostile, "Perfect")
				Harness.expect(
					promoted >= 1 and promoted < math.huge and promoted % 1 == 0,
					"a hostile tier produced " .. tostring(promoted)
				)
			end
			-- A LONG STREAK IS AN ORDINARY NUMBER, not an overflow. The Explosive Seam has no strike limit,
			-- so a lucky run really can climb for as long as the fuse holds.
			local tier = 1
			for _ = 1, 500 do
				tier = MiningRules.nextTier(tier, "Perfect")
			end
			Harness.equal(tier, 501, "a 500-Perfect run must simply be tier 501")
			Harness.near(
				MiningRules.effectiveSweepSeconds(tier),
				timing.tiers.minSweepSeconds,
				1e-9,
				"...and must still resolve to a playable rail"
			)
		end),

		Harness.test("an unresolvable tier reads as the tier every stance opens at", function()
			-- Tier travels over the wire to draw the client's rail, so a missing, stale or malformed value
			-- must degrade to the bottom of the ladder rather than handing anybody a window that does not
			-- exist. nil is tier 1 by DESIGN and not by leniency: a stance that has never been told a tier
			-- has never landed a strike.
			Harness.equal(MiningRules.clampTier(nil), 1)
			Harness.equal(MiningRules.clampTier(0 / 0), 1)
			Harness.equal(MiningRules.clampTier(0), 1)
			Harness.equal(MiningRules.clampTier(-50), 1)
			Harness.equal(MiningRules.clampTier(-math.huge), 1)
			Harness.equal(MiningRules.clampTier(1.9), 1, "a fractional tier must floor rather than round up")
			-- A high tier is NOT clamped down, because there is no top rung to clamp it to — it is a real
			-- streak and it resolves to the floored rail on its own.
			Harness.equal(MiningRules.clampTier(40), 40, "a long streak must not be capped away")
			Harness.equal(
				MiningRules.clampTier(math.huge),
				1,
				"an infinite tier is corruption, not a streak, and must read as a fresh stance"
			)

			-- And every derived value stays a usable number for all of it, so a bad tier can never divide
			-- a live sweep by zero or paint a band of infinite width. `nil` is checked first and on its
			-- own, because a nil inside an array literal would silently truncate the list it is in.
			local function assertUsable(tier: number?)
				local derived = {
					MiningRules.effectivePerfectHalfWidth(tier),
					MiningRules.effectiveGoodHalfWidth(tier),
					MiningRules.effectiveSweepSeconds(tier),
					MiningRules.effectiveWindupSeconds(tier),
				}
				for _, value in derived do
					Harness.expect(
						value == value and value > 0 and value < math.huge,
						string.format("tier %s produced an unusable %s", tostring(tier), tostring(value))
					)
				end
			end
			assertUsable(nil)
			for _, hostile in { 0 / 0, -1, 0, math.huge, -math.huge, 1e300 } do
				assertUsable(hostile)
			end
		end),

		Harness.test("a climbing tier changes only how hard a Perfect is, never what one pays", function()
			-- THE separation the whole feature rests on. If the ladder could touch grams or progress it
			-- would be a difficulty setting on the economy, and every number in Config/Mining would have to
			-- be re-derived against a skill distribution. It cannot: tier reaches the accuracy and stops.
			for _, row in MiningConfig.rows do
				for tier = 1, TIERS_EXERCISED do
					local onBand = elapsedAtPhase(timing.perfectCenter % 1, tier)
					local outcome = MiningRules.resolveStrike(0, onBand, nil, row, tier)
					Harness.equal(
						outcome.accuracy,
						"Perfect",
						string.format("%s: the band's own centre must score Perfect at tier %d", row.id, tier)
					)
					Harness.equal(
						outcome.grams,
						MiningRules.gramsForAccuracy("Perfect", row),
						string.format("%s: tier %d changed what a Perfect pays", row.id, tier)
					)
					Harness.near(
						outcome.progress,
						MiningRules.resolveStrike(0, elapsedAtPhase(timing.perfectCenter % 1, 1), nil, row, 1).progress,
						1e-12,
						string.format("%s: tier %d changed how much rock a Perfect removes", row.id, tier)
					)
				end
			end
		end),

		Harness.test("a plausible shared click timestamp removes network delay from scoring", function()
			-- Put the click exactly at the Perfect centre, then let it arrive late enough that scoring
			-- raw arrival would have moved outside the Perfect band.
			local networkDelay = MiningRules.effectivePerfectHalfWidth(1) * MiningRules.effectiveSweepSeconds(1) * 2
			Harness.expect(
				networkDelay <= timing.maxInputRewindSeconds,
				"the configured rewind must cover a useful portion of an honest network trip"
			)

			local sweepStart = 400
			local clickedAt = sweepStart + PERFECT
			local arrivalClock = clickedAt + networkDelay
			local sharedClockAtArrival = 1_000
			local scoreClock =
				MiningRules.resolveInputClock(arrivalClock, sharedClockAtArrival, sharedClockAtArrival - networkDelay)

			Harness.equal(
				MiningRules.accuracyForElapsed(arrivalClock - sweepStart) == "Perfect",
				false,
				"this fixture must expose the arrival-time latency penalty"
			)
			Harness.near(scoreClock, clickedAt)
			Harness.equal(MiningRules.accuracyForElapsed(scoreClock - sweepStart), "Perfect")
		end),

		Harness.test("reported click time is bounded and invalid samples fail back to arrival", function()
			local arrivalClock = 500
			local sharedClockAtArrival = 2_000
			local rewind = timing.maxInputRewindSeconds
			local future = timing.inputFutureToleranceSeconds
			local outside = math.max(rewind, future, 1) * 0.01

			-- Inclusive boundaries are legitimate clock samples.
			Harness.near(
				MiningRules.resolveInputClock(arrivalClock, sharedClockAtArrival, sharedClockAtArrival - rewind),
				arrivalClock - rewind
			)
			Harness.near(
				MiningRules.resolveInputClock(arrivalClock, sharedClockAtArrival, sharedClockAtArrival + future),
				arrivalClock + future
			)

			-- Hostile/stale values do not get pinned to a useful scoring edge; they lose the rewind.
			Harness.equal(
				MiningRules.resolveInputClock(
					arrivalClock,
					sharedClockAtArrival,
					sharedClockAtArrival - rewind - outside
				),
				arrivalClock
			)
			Harness.equal(
				MiningRules.resolveInputClock(
					arrivalClock,
					sharedClockAtArrival,
					sharedClockAtArrival + future + outside
				),
				arrivalClock
			)
			Harness.equal(MiningRules.resolveInputClock(arrivalClock, sharedClockAtArrival, nil), arrivalClock)
			Harness.equal(MiningRules.resolveInputClock(arrivalClock, sharedClockAtArrival, 0 / 0), arrivalClock)
			Harness.equal(MiningRules.resolveInputClock(arrivalClock, sharedClockAtArrival, math.huge), arrivalClock)
			Harness.equal(MiningRules.resolveInputClock(arrivalClock, 0 / 0, sharedClockAtArrival), arrivalClock)
		end),

		Harness.test("the target band wraps around the ring rather than falling off its end", function()
			-- Phase is circular, so a band centred anywhere must score identically approached from
			-- either side. Probing symmetric offsets around the centre catches a linear distance.
			-- Checked on every rung, since the ladder resizes both bands and a wrap bug would only show
			-- at whichever width happened to straddle the seam.
			for tier = 1, TIERS_EXERCISED do
				local center = timing.perfectCenter % 1
				local perfect = MiningRules.effectivePerfectHalfWidth(tier)
				for _, offset in { perfect * 0.5, perfect * 0.9 } do
					Harness.equal(MiningRules.accuracyForPhase((center + offset) % 1, nil, tier), "Perfect")
					Harness.equal(MiningRules.accuracyForPhase((center - offset + 1) % 1, nil, tier), "Perfect")
				end
				local outside = MiningRules.effectiveGoodHalfWidth(tier) + 0.02
				Harness.equal(MiningRules.accuracyForPhase((center + outside) % 1, nil, tier), "Miss")
				Harness.equal(MiningRules.accuracyForPhase((center - outside + 1) % 1, nil, tier), "Miss")
			end
		end),

		Harness.test("the sweep repeats, so patience never changes what a release is worth", function()
			-- Waiting a full extra lap must score exactly the same. Otherwise holding the button
			-- longer would be a strategy rather than a timing test.
			for tier = 1, TIERS_EXERCISED do
				local onBand = elapsedAtPhase(timing.perfectCenter % 1, tier)
				local lap = MiningRules.effectiveSweepSeconds(tier)
				Harness.equal(
					MiningRules.accuracyForElapsed(onBand + lap, nil, tier),
					MiningRules.accuracyForElapsed(onBand, nil, tier),
					"tier " .. tier .. ": one extra lap must be worth exactly the same"
				)
				Harness.equal(
					MiningRules.accuracyForElapsed(onBand + lap * 3, nil, tier),
					"Perfect",
					"tier " .. tier .. ": the band must still be hittable several laps in"
				)
			end
		end),

		Harness.test("progress is clamped, so no swing can overfill a seam", function()
			local outcome = MiningRules.resolveStrike(0.99, PERFECT)
			Harness.equal(outcome.progress, 1, "progress must never exceed a full deposit")
			Harness.equal(outcome.depleted, true)
		end),

		Harness.test("every state that should refuse a swing does", function()
			Harness.equal(MiningRules.canBeginStrike(baseRequest()), true, "a healthy lit player at the seam may swing")

			local dead = baseRequest()
			dead.alive = false
			local allowed, denial = MiningRules.canBeginStrike(dead)
			Harness.equal(allowed, false)
			Harness.equal(denial, "Dead")

			local snuffed = baseRequest()
			snuffed.snuffed = true
			Harness.equal(select(2, MiningRules.canBeginStrike(snuffed)), "Dead")

			local finished = baseRequest()
			finished.finished = true
			Harness.equal(select(2, MiningRules.canBeginStrike(finished)), "Dead")

			local unlit = baseRequest()
			unlit.isLit = false
			Harness.equal(
				select(2, MiningRules.canBeginStrike(unlit)),
				"NotLit",
				"mining unlit would remove the exposure the whole mechanic is made of"
			)

			local cupped = baseRequest()
			cupped.isCupping = true
			Harness.equal(
				select(2, MiningRules.canBeginStrike(cupped)),
				"Covered",
				"cupping must not be a way to mine without being seen"
			)

			local wrongFloor = baseRequest()
			wrongFloor.playerDepth = 2
			Harness.equal(select(2, MiningRules.canBeginStrike(wrongFloor)), "WrongFloor")

			local far = baseRequest()
			far.distance = deposit.interactionRange + 0.01
			Harness.equal(select(2, MiningRules.canBeginStrike(far)), "OutOfRange")

			local obstructed = baseRequest()
			obstructed.hasLineOfSight = false
			Harness.equal(
				select(2, MiningRules.canBeginStrike(obstructed)),
				"Obstructed",
				"a seam behind cave geometry must not open a stance"
			)

			local spent = baseRequest()
			spent.depositDepleted = true
			Harness.equal(
				select(2, MiningRules.canBeginStrike(spent)),
				"Depleted",
				"a broken seam must refuse every further swing — this is the no-duplicate-reward guard"
			)

			local cooling = baseRequest()
			cooling.nextStrikeAt = cooling.now + 0.1
			Harness.equal(select(2, MiningRules.canBeginStrike(cooling)), "Cooldown")

			local busy = baseRequest()
			busy.hasOpenSwing = true
			Harness.equal(
				select(2, MiningRules.canBeginStrike(busy)),
				"AlreadySwinging",
				"one open swing per player — a second begin is a duplicate, not a queue"
			)
		end),

		Harness.test("a swing legal at the press can still be refused at the release", function()
			-- The world moves during the second a swing is open, which is exactly what makes walking
			-- away a real cancel rather than a delayed payout.
			local walkedOff = baseRequest()
			walkedOff.distance = deposit.interactionRange + 5
			Harness.equal(select(2, MiningRules.canResolveStrike(walkedOff)), "OutOfRange")

			local obstructed = baseRequest()
			obstructed.hasLineOfSight = false
			Harness.equal(
				select(2, MiningRules.canResolveStrike(obstructed)),
				"Obstructed",
				"moving an obstruction into the sightline must cancel an open stance"
			)

			local died = baseRequest()
			died.alive = false
			Harness.equal(select(2, MiningRules.canResolveStrike(died)), "Dead")

			local descended = baseRequest()
			descended.playerDepth = 4
			Harness.equal(select(2, MiningRules.canResolveStrike(descended)), "WrongFloor")

			-- Two players on one seam: whoever lands second finds it already broken.
			local beaten = baseRequest()
			beaten.depositDepleted = true
			Harness.equal(select(2, MiningRules.canResolveStrike(beaten)), "Depleted")

			-- Cooldown is deliberately NOT re-checked on release: it gates starting swings, and a
			-- swing already in flight must resolve on its own timing.
			local cooling = baseRequest()
			cooling.nextStrikeAt = cooling.now + 5
			Harness.equal(MiningRules.canResolveStrike(cooling), true)
		end),

		Harness.test("an idle stance releases itself instead of holding its commitment open", function()
			Harness.equal(MiningRules.swingHasTimedOut(0), false)
			Harness.equal(MiningRules.swingHasTimedOut(deposit.swingTimeoutSeconds), true)
			-- Measured against the SLOWEST tier, which is the binding case: tier 1 is now the longest
			-- sweep in the game, and a timeout that only cleared the top of the ladder would release a
			-- player mid-read on the very first swing of every stance.
			Harness.expect(
				deposit.swingTimeoutSeconds > MiningRules.effectiveSweepSeconds(1),
				"the timeout must leave room for at least one full sweep, or honest reads would be cut off"
			)
		end),

		Harness.test("the stance is a lock, and the lock has to cost something", function()
			-- Working a seam plants you: the stance is the commitment, and the exit is a movement key
			-- (client/MiningController polls for one and disengages on the frame it is pressed) rather
			-- than a slow walk away. A player must never be able to mine and reposition at once.
			Harness.equal(
				deposit.movementSpeedMultiplier,
				0,
				"engaging a seam must plant the player — mining while moving is not a commitment"
			)
			Harness.expect(
				deposit.strikeCooldownSeconds > 0,
				"strikes must be separable in time, or a locked stance becomes a click-spam"
			)
			-- The animation and the rhythm share one beat: the pick has to be back up and still before
			-- the next sweep can be struck, or the player is reading a ring while the tool is still in
			-- the rock.
			local pickaxe = MiningConfig.pickaxe
			Harness.expect(
				pickaxe.anticipationSeconds
						+ pickaxe.swingSeconds
						+ pickaxe.impactSeconds
						+ pickaxe.reboundSeconds
						+ pickaxe.recoverSeconds
					<= deposit.strikeCooldownSeconds,
				"the full strike animation must finish inside the strike cooldown"
			)
			-- THE PRIME only ever SHORTENS that animation — it is the anticipation beat pre-paid during
			-- the sweep — so the bound above still holds for a primed strike by construction. What has to
			-- be checked is the dial itself: a fraction at or below zero would leave the pick frozen at
			-- READY and delete the wind-up, and one above 1 would mean the arm is still cocking as the
			-- marker leaves the far end of the rail, so the slow motion would never resolve into a swing.
			Harness.expect(
				pickaxe.primeSweepFraction > 0 and pickaxe.primeSweepFraction <= 1,
				"the pickaxe prime must complete inside one pass of the rail"
			)
			Harness.expect(
				pickaxe.primeSweepFraction >= timing.perfectCenter - timing.bandWander,
				"the pick must be near full cock by the earliest a band can sit, or an early strike swings"
					.. " from a half-raised arm"
			)
			Harness.expect(
				pickaxe.primeSteadiness >= 0 and pickaxe.primeSteadiness <= 1,
				"the prime's idle damping is a fraction of the existing bob, not a multiplier on it"
			)
		end),

		Harness.test("the band wanders deterministically, inside the ring, and never sits still", function()
			-- Same inputs, same answer, on every machine that evaluates it: the server scores against
			-- this and the client draws it.
			Harness.near(MiningRules.bandCenter(7, 3), MiningRules.bandCenter(7, 3))
			for depositId = 1, 12 do
				for strikeIndex = 0, 8 do
					local center = MiningRules.bandCenter(depositId, strikeIndex)
					Harness.expect(
						center >= 0 and center < 1,
						"a band centre outside 0..1 would put the target off the ring"
					)
				end
			end
			-- It has to actually MOVE, or the sweeping ring is a metronome.
			local distinct = 0
			local seen: { [string]: boolean } = {}
			for strikeIndex = 0, 8 do
				local key = string.format("%.4f", MiningRules.bandCenter(4, strikeIndex))
				if not seen[key] then
					seen[key] = true
					distinct += 1
				end
			end
			Harness.expect(distinct > 4, "consecutive strikes must not reuse the same target position")
			Harness.expect(
				timing.bandWander > 0 and timing.bandWander <= 0.4,
				"wander must exist, and must stay small enough that the band is still findable"
			)
		end),

		Harness.test("a strike is scored against the band it was told to aim at", function()
			local center = MiningRules.bandCenter(9, 2)
			local onBand = elapsedAtPhase(center, 1)
			Harness.equal(MiningRules.resolveStrike(0, onBand, center).accuracy, "Perfect")
			-- The same instant, judged against a band on the other side of the ring, is a miss. This is
			-- the whole reason the centre travels with the payload rather than being assumed.
			local opposite = (center + 0.5) % 1
			Harness.equal(MiningRules.resolveStrike(0, onBand, opposite).accuracy, "Miss")
		end),

		Harness.test("a floor never wants more seams than the absolute ceiling allows", function()
			-- The ceiling is a safety clamp on a mistyped weight row, not a balance lever. Every band
			-- must respect it at every roll, including the degenerate ends of the range.
			local ceiling = MiningConfig.placement.maxPerFloor
			for depth = 1, 20 do
				for _, roll in { 0, 0.25, 0.5, 0.75, 0.999999, -1, 2 } do
					local count = MiningRules.targetCount(depth, roll)
					Harness.expect(
						count >= 0 and count <= ceiling and count % 1 == 0,
						string.format("depth %d roll %s produced %s", depth, tostring(roll), tostring(count))
					)
				end
			end
		end),

		Harness.test("the terrain probe covers the largest jittered seam core", function()
			local visual = MiningConfig.visual
			local widestCore = visual.rockSize.X * visual.shape.sizeJitterMax
			Harness.expect(
				visual.surfaceProbeRadius >= widestCore / 2,
				"a deposit can extend beyond the terrain samples and be swallowed by a nearby hump"
			)
			Harness.expect(visual.surfaceEmbed + visual.surfaceEmbedJitter < 0.25, "visible ore is buried too deeply")
		end),

		Harness.test("seam counts rise with depth rather than sitting flat", function()
			-- THE reason the flat 65%-of-one rule was replaced: descending has to change how much there
			-- is to work, not only what a unit is worth. Compared as expected value over the band's own
			-- weights, so this pins the shape of the curve and not one lucky roll.
			local function expected(depth: number): number
				local samples, total = 400, 0
				for index = 0, samples - 1 do
					total += MiningRules.targetCount(depth, index / samples)
				end
				return total / samples
			end

			local shallow, mid, postSix, deep = expected(2), expected(6), expected(7), expected(12)
			Harness.expect(shallow < 1, "a shallow floor must usually carry one seam or none")
			Harness.expect(mid > shallow, "a mid floor must out-carry a shallow one")
			Harness.near(postSix, 2.35, 1e-6, "floors 7-9 must carry the approved 27% seam-density increase")
			Harness.near(deep, 3.15, 1e-6, "floors 10+ must carry the approved 29% seam-density increase")
			Harness.expect(postSix > mid, "floors past six must out-carry the mid-depth band")
			Harness.expect(deep > postSix, "the deepest band must out-carry floors 7-9")
			Harness.expect(deep >= 3, "past the authored table a floor should reliably carry three or four")
		end),

		Harness.test("depths past the final weight row reuse it rather than falling off the table", function()
			-- Expeditions are uncapped (Config/Depth), so there is always a row to read.
			local last = MiningRules.targetCount(10, 0.5)
			for depth = 11, 40 do
				Harness.equal(
					MiningRules.targetCount(depth, 0.5),
					last,
					"depth " .. depth .. " must reuse the final row"
				)
			end
		end),

		Harness.test("depth gating matches the configured minimum", function()
			for depth = 1, MiningConfig.placement.minDepth - 1 do
				Harness.equal(MiningRules.targetCount(depth, 0), 0, "no deposit may be budgeted at depth " .. depth)
			end
			Harness.equal(MiningRules.isEligibleDepth(MiningConfig.placement.minDepth), true)
		end),

		Harness.test("the clean-strike readout never promises more precision than exists", function()
			Harness.equal(MiningRules.cleanStrikesRemaining(0), STANDARD.cleanStrikes)
			Harness.equal(MiningRules.cleanStrikesRemaining(1), 0)
			Harness.expect(
				MiningRules.cleanStrikesRemaining(0.5) < STANDARD.cleanStrikes,
				"a half-worked seam must read as closer to breaking"
			)
		end),

		Harness.test("the prime curve is flat, then climbs, then is certain", function()
			local explosive = MiningConfig.explosive
			local previous = -1
			for strike = 1, 40 do
				local chance = MiningRules.primeChance(EXPLOSIVE, strike)
				Harness.expect(chance >= 0 and chance <= 1, "strike " .. strike .. " produced an impossible chance")
				Harness.expect(chance >= previous, "the chance must never fall as a seam is worked further")
				previous = chance
			end
			-- The opening swings sit at the flat base: starting an explosive seam has to be a reasonable
			-- thing to do, or nobody ever makes the decision the row exists to offer.
			for strike = 1, explosive.primeChanceRampStrikes do
				Harness.near(MiningRules.primeChance(EXPLOSIVE, strike), explosive.primeChanceBase)
			end
			-- ...and it is never free. A first swing that could not possibly go off would make counting
			-- swings a safe strategy.
			Harness.expect(explosive.primeChanceBase > 0, "the first swing must carry real risk")
			-- The ramp reaches certainty, so no amount of counting buys a safe extra strike.
			Harness.equal(MiningRules.primeChance(EXPLOSIVE, 12), 1)
		end),

		Harness.test(
			"an explosive seam is statistically likely to go off between the fourth and eighth swing",
			function()
				-- THE row's authored claim, asserted rather than believed (Config/Mining.explosive). Walking the
				-- survival probability forward gives the exact distribution of "which swing sets it off"; the
				-- bulk of that mass has to sit in 4-8, or the seam is either a freeroll or a coin flip.
				local survival = 1
				local within = 0
				local early = 0
				local expectedStrike = 0
				for strike = 1, 40 do
					local chance = MiningRules.primeChance(EXPLOSIVE, strike)
					local primesHere = survival * chance
					expectedStrike += primesHere * strike
					if strike <= 3 then
						early += primesHere
					elseif strike <= 8 then
						within += primesHere
					end
					survival -= primesHere
				end
				Harness.expect(
					within >= 0.85,
					string.format("only %.1f%% of seams prime between swings 4 and 8", within * 100)
				)
				Harness.expect(
					early <= 0.12,
					string.format("%.1f%% of seams prime in the first three swings", early * 100)
				)
				Harness.near(survival, 0, 1e-6, "every seam must eventually prime")
				Harness.expect(
					expectedStrike > 4 and expectedStrike < 6,
					string.format("the mean prime lands on swing %.2f, outside the authored 4-6 window", expectedStrike)
				)
			end
		),

		Harness.test("an endless row must pay under the Standard rate, or skimming it is a free lunch", function()
			-- THE property that makes the Explosive Seam a gamble instead of a bonus. Its first three
			-- swings are nearly safe (3% each), so if they were worth more than an ordinary seam a player
			-- could chip every explosive rock three times, walk away, and out-earn mining normally at
			-- almost no risk. Paying UNDER the Standard rate puts the break-even past the flat opening —
			-- every gram of profit sits on the far side of the ramp.
			--
			-- This is not hypothetical: the row shipped at 55g in review, where three swings returned 160g
			-- against a Standard seam's 150g at 8.7% risk. That is the bug this test exists to catch.
			for _, row in MiningConfig.rows do
				if not row.neverDepletes then
					continue
				end
				Harness.expect(
					row.gramsPerStrike < STANDARD.gramsPerStrike,
					row.id .. " pays at or above the Standard rate, which makes skimming its safe swings free money"
				)
				local safeSwings = MiningConfig.explosive.primeChanceRampStrikes
				local standardSeam = STANDARD.cleanStrikes * STANDARD.gramsPerStrike
				Harness.expect(
					safeSwings * row.gramsPerStrike < standardSeam,
					string.format(
						"%s: %d near-free swings return %dg against a Standard seam's %dg — walking away"
							.. " early must be strictly worse than never starting",
						row.id,
						safeSwings,
						safeSwings * row.gramsPerStrike,
						standardSeam
					)
				)
				-- ...and the break-even must land ON the ramp rather than past it, or the row is a trap
				-- nobody should ever take.
				local breakEven = math.ceil(standardSeam / row.gramsPerStrike)
				Harness.expect(
					breakEven == safeSwings + 1,
					string.format(
						"%s breaks even on swing %d but the odds start climbing on swing %d — the payoff and"
							.. " the danger must arrive together",
						row.id,
						breakEven,
						safeSwings + 1
					)
				)
			end
		end),

		Harness.test("only an explosive row can prime, and only on a roll under its own chance", function()
			for _, row in MiningConfig.rows do
				if row.neverDepletes then
					continue
				end
				Harness.equal(MiningRules.primeChance(row, 50), 0, row.id .. " must never prime")
				Harness.equal(MiningRules.rollPrimes(row, 50, 0), false, row.id .. " must never prime")
			end
			-- A roll of exactly the chance does NOT prime (strictly less than), so a chance of zero cannot
			-- fire however the roll is produced.
			local chance = MiningRules.primeChance(EXPLOSIVE, 5)
			Harness.equal(MiningRules.rollPrimes(EXPLOSIVE, 5, chance), false)
			Harness.equal(MiningRules.rollPrimes(EXPLOSIVE, 5, chance - 1e-9), true)
			Harness.equal(MiningRules.rollPrimes(EXPLOSIVE, 5, 0 / 0), false, "a broken roll must not detonate a seam")
			Harness.equal(MiningRules.primeChance(EXPLOSIVE, 0), 0, "there is no strike zero")
			Harness.equal(MiningRules.primeChance(nil, 5), 0, "an unknown row must not prime")
		end),

		Harness.test("the fuse and the blast both resolve monotonically from their own inputs", function()
			local explosive = MiningConfig.explosive
			Harness.near(MiningRules.fuseProgress(0), 0)
			Harness.near(MiningRules.fuseProgress(explosive.fuseSeconds), 1)
			Harness.near(MiningRules.fuseProgress(explosive.fuseSeconds * 2), 1, 1e-9, "the fuse must clamp")
			Harness.near(MiningRules.fuseProgress(-5), 0, 1e-9, "a negative elapsed must not skip the fuse")

			-- The blast costs most at the centre and nothing at the edge, so backing away is always worth
			-- something rather than being a threshold the player cannot read.
			Harness.near(MiningRules.blastWaxCost(0), explosive.blastWaxCost)
			Harness.equal(MiningRules.blastWaxCost(explosive.blastRadius), 0)
			Harness.equal(MiningRules.blastWaxCost(explosive.blastRadius * 3), 0)
			Harness.expect(
				MiningRules.blastWaxCost(explosive.blastRadius * 0.5) < MiningRules.blastWaxCost(0),
				"distance must reduce the cost"
			)
			-- Survivable from full at point-blank range: the seam kills by what it brings, not by the blast.
			Harness.expect(
				explosive.blastWaxCost < WaxConfig.startingWax,
				"a direct hit must never be lethal on its own"
			)
		end),
	},
}

return suite

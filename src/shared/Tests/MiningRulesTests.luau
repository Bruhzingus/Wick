--!strict

local Harness = require(script.Parent.Harness)
local MiningRules = require(script.Parent.Parent.Logic.MiningRules)
local MiningConfig = require(script.Parent.Parent.Config.Mining)

local deposit = MiningConfig.deposit
local timing = MiningConfig.timing

-- Seconds into a swing at which the marker sits exactly on a given sweep phase.
local function elapsedAtPhase(phase: number): number
	return deposit.swingWindupSeconds + phase * timing.sweepSeconds
end

local PERFECT = elapsedAtPhase(timing.perfectCenter % 1)

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
		now = 100,
		nextStrikeAt = 0,
		hasOpenSwing = false,
	}
end

local suite: Harness.Suite = {
	name = "MiningRules",
	tests = {
		Harness.test("three clean strikes deplete a deposit, and no fewer", function()
			local progress = 0
			for strike = 1, deposit.cleanStrikesToDeplete - 1 do
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
			Harness.expect(timing.missProgress > 0, "a miss must still chip the seam")
			Harness.expect(
				timing.missProgress < timing.goodProgress and timing.goodProgress < timing.perfectProgress,
				"the three bands must be strictly ordered, or accuracy buys nothing"
			)
			local missOnly = math.ceil(1 / timing.missProgress)
			Harness.expect(
				missOnly > deposit.cleanStrikesToDeplete,
				"missing every swing must take more swings than hitting every one"
			)
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
			Harness.isNil(MiningRules.sweepPhase(0), "the sweep must not be live before the wind-up ends")
			Harness.isNil(MiningRules.sweepPhase(deposit.swingWindupSeconds - 0.001))
			Harness.equal(MiningRules.accuracyForElapsed(0), "Miss")
			Harness.expect(
				MiningRules.sweepPhase(deposit.swingWindupSeconds) ~= nil,
				"the sweep must be live the instant the wind-up ends"
			)
		end),

		Harness.test("the target band wraps around the ring rather than falling off its end", function()
			-- Phase is circular, so a band centred anywhere must score identically approached from
			-- either side. Probing symmetric offsets around the centre catches a linear distance.
			local center = timing.perfectCenter % 1
			for _, offset in { timing.perfectHalfWidth * 0.5, timing.perfectHalfWidth * 0.9 } do
				Harness.equal(MiningRules.accuracyForPhase((center + offset) % 1), "Perfect")
				Harness.equal(MiningRules.accuracyForPhase((center - offset + 1) % 1), "Perfect")
			end
			local outside = timing.goodHalfWidth + 0.02
			Harness.equal(MiningRules.accuracyForPhase((center + outside) % 1), "Miss")
			Harness.equal(MiningRules.accuracyForPhase((center - outside + 1) % 1), "Miss")
		end),

		Harness.test("the sweep repeats, so patience never changes what a release is worth", function()
			-- Waiting a full extra lap must score exactly the same. Otherwise holding the button
			-- longer would be a strategy rather than a timing test.
			Harness.equal(
				MiningRules.accuracyForElapsed(PERFECT + timing.sweepSeconds),
				MiningRules.accuracyForElapsed(PERFECT)
			)
			Harness.equal(
				MiningRules.accuracyForElapsed(PERFECT + timing.sweepSeconds * 3),
				"Perfect",
				"the band must still be hittable several laps in"
			)
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
			Harness.expect(
				deposit.swingTimeoutSeconds > timing.sweepSeconds,
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
			local onBand = deposit.swingWindupSeconds + center * timing.sweepSeconds
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

			local shallow, mid, deep = expected(2), expected(6), expected(12)
			Harness.expect(shallow < 1, "a shallow floor must usually carry one seam or none")
			Harness.expect(mid > shallow, "a mid floor must out-carry a shallow one")
			Harness.expect(deep > mid, "a deep floor must out-carry a mid one")
			Harness.expect(deep >= 2, "past the authored table a floor should reliably carry two or three")
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
			Harness.equal(MiningRules.cleanStrikesRemaining(0), deposit.cleanStrikesToDeplete)
			Harness.equal(MiningRules.cleanStrikesRemaining(1), 0)
			Harness.expect(
				MiningRules.cleanStrikesRemaining(0.5) < deposit.cleanStrikesToDeplete,
				"a half-worked seam must read as closer to breaking"
			)
		end),
	},
}

return suite

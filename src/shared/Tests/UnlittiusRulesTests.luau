--!strict
-- The Unlittius encounter's decisions (Logic/UnlittiusRules, Logic/BossRotation, DESIGN §9b).
--
-- WHY THIS SUITE EXISTS AND WHAT IT IS AIMED AT. A boss is the part of a project that historically
-- cannot be checked without standing in the room: timing, geometry and randomness braided into
-- instance manipulation. Every rule this file exercises was deliberately written as a pure function
-- for that reason, so the assertions below are about the FIGHT rather than about arithmetic —
-- "a player who steps out of a marked circle takes nothing" is a property, and it is testable here
-- because the placement of that circle is a function rather than a side effect.
--
-- The fairness properties are the ones that must never regress: the eight candles are the only score,
-- a candle counts once, a dead player cannot light one, telegraphs never shorten, and a beat that has
-- already fired is never rewound by a recoil.

local Harness = require(script.Parent.Harness)
local UnlittiusRules = require(script.Parent.Parent.Logic.UnlittiusRules)
local UnlittiusFloorPlan = require(script.Parent.Parent.Logic.UnlittiusFloorPlan)
local BossFloorPlan = require(script.Parent.Parent.Logic.BossFloorPlan)
local BossRotation = require(script.Parent.Parent.Logic.BossRotation)
local RoomFootprint = require(script.Parent.Parent.Logic.RoomFootprint)
local UnlittiusConfig = require(script.Parent.Parent.Config.Unlittius)
local GrubQueenConfig = require(script.Parent.Parent.Config.GrubQueen)

local CANDLES = UnlittiusConfig.encounter.candleCount

local function baseCandleRequest(): UnlittiusRules.CandleRequest
	return {
		candleLit = false,
		candleDepth = 4,
		alive = true,
		finished = false,
		isLit = true,
		isCupping = false,
		playerDepth = 4,
		distance = 3,
	}
end

local function context(overrides: { [string]: any }): UnlittiusRules.ActionContext
	local resolved: UnlittiusRules.ActionContext = {
		meleeCandidate = false,
		meleeReady = false,
		summonEligible = true,
		candlesLit = 0,
		recent = {},
		roll = 0.5,
	}
	for key, value in overrides do
		(resolved :: any)[key] = value
	end
	return resolved
end

local suite: Harness.Suite = {
	name = "UnlittiusRules",
	tests = {
		----------------------------------------------------------------------------------
		-- PROGRESSION
		----------------------------------------------------------------------------------
		Harness.test("eight candles is the whole health bar, and it only ever goes down", function()
			Harness.near(UnlittiusRules.power(0), 1, 1e-9, "he starts at full power")
			Harness.near(UnlittiusRules.power(CANDLES), 0, 1e-9, "the last candle takes all of it")
			local previous = math.huge
			for lit = 0, CANDLES do
				local power = UnlittiusRules.power(lit)
				Harness.expect(power < previous, "power must fall on every candle, never plateau")
				Harness.expect(power >= 0 and power <= 1, "power stays inside 0..1")
				previous = power
			end
			-- A count that somehow overshoots must clamp rather than go negative: `candleLit` takes a
			-- total from the encounter, and a total is exactly the kind of number that can arrive wrong.
			Harness.near(UnlittiusRules.power(CANDLES + 4), 0, 1e-9, "an overshoot clamps to nothing")
			Harness.near(UnlittiusRules.power(-3), 1, 1e-9, "a negative count clamps to full")
		end),

		Harness.test("the rune dims every candle but is never dark before the banish", function()
			local previous = math.huge
			for lit = 0, CANDLES - 1 do
				local brightness = UnlittiusRules.runeBrightness(lit)
				Harness.expect(brightness < previous, "each candle must be a visible dim step")
				Harness.expect(brightness > 0, "a boss who has already gone dark at seven has nothing left to take")
				previous = brightness
			end
			Harness.near(UnlittiusRules.runeBrightness(0), UnlittiusConfig.body.runeBrightnessFull, 1e-9)
			Harness.near(UnlittiusRules.runeBrightness(CANDLES - 1), UnlittiusConfig.body.runeBrightnessLast, 1e-9)
		end),

		Harness.test("the supernatural layer collapses late rather than fading evenly", function()
			-- SOUND_DESIGN.md's mix progression: ~60% at four candles, ~20% at seven. A straight line
			-- would put four candles at 50% and seven at 12.5%, which reads as the fight being over
			-- earlier than it is — the curve has to stay loud while he is winning.
			local atFour = UnlittiusRules.supernaturalGain(4)
			local atSeven = UnlittiusRules.supernaturalGain(7)
			Harness.expect(atFour > 0.2 and atFour < 0.3, "four candles must still sound like a fight")
			Harness.expect(atSeven > 0 and atSeven < 0.05, "seven candles is nearly silence")
			Harness.near(UnlittiusRules.supernaturalGain(CANDLES), 0, 1e-9, "the banish resolves it to zero")
		end),

		Harness.test("only the eighth candle completes the encounter", function()
			for lit = 0, CANDLES - 1 do
				Harness.expect(not UnlittiusRules.isComplete(lit), lit .. " candles must not finish him")
			end
			Harness.expect(UnlittiusRules.isComplete(CANDLES), "eight candles banishes him")
			Harness.expect(UnlittiusRules.isComplete(CANDLES + 1), "an overshoot still counts as complete")
		end),

		Harness.test("a chamber that seated fewer candles is still winnable", function()
			-- THE RUN-ENDING BUG THIS EXISTS TO PREVENT. If a candle post cannot be seated on the Terrain
			-- that was actually carved, the encounter builds seven — and his floor gates the descent
			-- ladder. An encounter that still demanded eight would lock the party on that floor forever,
			-- with no counterplay and nothing to route around. So the target is what was BUILT.
			Harness.expect(UnlittiusRules.isComplete(7, 7), "seven of seven finishes a seven-candle chamber")
			Harness.expect(not UnlittiusRules.isComplete(6, 7), "six of seven does not")
			Harness.expect(UnlittiusRules.isComplete(1, 1), "even a one-candle chamber can be finished")
			-- And the dim curve divides by the same number, so the last candle in a short chamber still
			-- takes him all the way down rather than leaving him lit at the end of his own encounter.
			Harness.near(UnlittiusRules.power(7, 7), 0, 1e-9, "the last candle of seven is still total")
			Harness.near(UnlittiusRules.runeBrightness(6, 7), UnlittiusConfig.body.runeBrightnessLast, 1e-9)
			Harness.near(UnlittiusRules.supernaturalGain(7, 7), 0, 1e-9)
			-- A nil target keeps the configured behaviour, so every ordinary chamber is unaffected.
			Harness.equal(UnlittiusRules.isComplete(CANDLES), UnlittiusRules.isComplete(CANDLES, CANDLES))
		end),

		----------------------------------------------------------------------------------
		-- HIS VOICE
		----------------------------------------------------------------------------------
		Harness.test("every utterance is heard before any of them repeats", function()
			-- THE PROPERTY THE OWNER ASKED FOR, stated exactly: enough lines that they are not
			-- constantly repeated. A shuffled bag guarantees it; a per-play roll only approximates it.
			local lines = UnlittiusConfig.voice.lineCount
			Harness.expect(lines >= 8, "a muttering boss needs a real pool, not three lines")
			local rng = Random.new(1234)
			local bag = UnlittiusRules.shuffledVoiceBag(rng, nil)
			Harness.equal(#bag, lines, "a bag holds every line exactly once")
			local seen: { [number]: boolean } = {}
			for _, line in bag do
				Harness.expect(line >= 1 and line <= lines, "line " .. line .. " is outside the pool")
				Harness.expect(not seen[line], "line " .. line .. " appeared twice in one bag")
				seen[line] = true
			end
			for line = 1, lines do
				Harness.expect(seen[line] == true, "line " .. line .. " was never in the bag")
			end
		end),

		Harness.test("a fresh bag never opens on the line the last one closed with", function()
			-- The one case a per-bag shuffle can still produce a back-to-back repeat: the tail of one bag
			-- and the head of the next. Swept over many seeds because it is a rare collision by nature.
			local lines = UnlittiusConfig.voice.lineCount
			for seed = 1, 400 do
				local rng = Random.new(seed)
				local previous = (seed % lines) + 1
				local bag = UnlittiusRules.shuffledVoiceBag(rng, previous)
				Harness.expect(
					bag[1] ~= previous,
					string.format("seed %d opened a new bag on line %d, which just played", seed, previous)
				)
				Harness.equal(#bag, lines, "the anti-repeat swap must not lose or duplicate a line")
				local seen: { [number]: boolean } = {}
				for _, line in bag do
					Harness.expect(not seen[line], "the anti-repeat swap duplicated line " .. line)
					seen[line] = true
				end
			end
		end),

		Harness.test("he mutters between attacks and never over them", function()
			local voice = UnlittiusConfig.voice
			-- Only while idle, and only once he has been quiet for a moment.
			Harness.expect(UnlittiusRules.canSpeak("Idle", voice.quietAfterActionSeconds), "idle and settled: speak")
			Harness.expect(
				not UnlittiusRules.canSpeak("Idle", voice.quietAfterActionSeconds - 0.1),
				"he does not speak the instant an action ends"
			)
			for _, action in { "Dripstone", "BoulderBurst", "SummonGnawers", "Melee", "Recoil" } do
				Harness.expect(not UnlittiusRules.canSpeak(action, 99), action .. " must not be talked over")
			end
			-- HE NEVER MUTTERS DURING THE BANISH. The two utterances that DO play there are scripted
			-- beats on the banish's own clock, not ambient muttering that could wander into his death.
			Harness.expect(not UnlittiusRules.canSpeak("Banish", 99), "no ambient muttering during the banish")

			-- The cadence is a range, not a metronome.
			Harness.near(UnlittiusRules.nextVoiceDelay(0), voice.minIntervalSeconds, 1e-9)
			Harness.near(UnlittiusRules.nextVoiceDelay(1), voice.maxIntervalSeconds, 1e-9)
			Harness.expect(voice.maxIntervalSeconds > voice.minIntervalSeconds, "the interval must vary")
			Harness.expect(voice.minIntervalSeconds > 5, "muttering every few seconds is chatter, not menace")
		end),

		Harness.test("his last two words land inside his own death, in order", function()
			-- THE ICONIC BEAT, pinned so a retune of the banish cannot silently push either utterance
			-- past the moment the stone closes — which would either lose the line entirely or leave it
			-- playing over a chamber that has already gone quiet.
			local banish = UnlittiusConfig.banish
			Harness.expect(banish.cryAt > 0, "the cry follows the unbind rather than opening on it")
			Harness.expect(
				banish.cryAt < banish.riseSeconds,
				"the cry belongs to the moment he comes apart, not to the lift"
			)
			Harness.expect(banish.lastWordAt > banish.cryAt, "the last word comes after the cry")
			Harness.expect(
				banish.lastWordAt < banish.reliefSwapAt,
				"the last word must start before the stone closes, or it is never heard"
			)
			-- CUT OFF, NOT RESOLVED. The gap between the last word and the seal is deliberately shorter
			-- than the cue is allowed to run, so the seal lands on top of it.
			Harness.expect(
				banish.reliefSwapAt - banish.lastWordAt < 1.2,
				"the seal must interrupt the last word rather than politely wait for it"
			)
			Harness.expect(banish.reliefSwapAt < banish.completeAt, "and the silence follows the seal")
			-- Both beats sit inside the sequence they belong to.
			for _, beat in { banish.cryAt, banish.lastWordAt } do
				Harness.expect(UnlittiusRules.beatReached(beat, beat), "a banish beat must fire exactly on time")
				Harness.expect(beat < banish.completeAt, "and inside the banish")
			end
		end),

		Harness.test("his voice sinks and quietens as the candles take him", function()
			local voice = UnlittiusConfig.voice
			Harness.near(UnlittiusRules.voiceGain(0), voice.gainAtFullPower, 1e-9)
			Harness.near(UnlittiusRules.voicePitch(0), voice.pitchAtFullPower, 1e-9)
			Harness.near(UnlittiusRules.voiceGain(CANDLES), voice.gainAtLastCandle, 1e-9)
			Harness.near(UnlittiusRules.voicePitch(CANDLES), voice.pitchAtLastCandle, 1e-9)
			local previousGain, previousPitch = math.huge, math.huge
			for lit = 0, CANDLES do
				local gain = UnlittiusRules.voiceGain(lit)
				local pitch = UnlittiusRules.voicePitch(lit)
				Harness.expect(gain <= previousGain, "his voice must never get louder as he is put out")
				Harness.expect(pitch <= previousPitch, "or higher")
				Harness.expect(gain > 0, "he is never completely inaudible before the banish")
				previousGain, previousPitch = gain, pitch
			end
			-- It follows the short chamber's target too, so a seven-candle room still ends him at his
			-- lowest rather than leaving him talking at full voice on the last candle.
			Harness.near(UnlittiusRules.voicePitch(7, 7), voice.pitchAtLastCandle, 1e-9)
		end),

		----------------------------------------------------------------------------------
		-- THE DIRECTOR
		----------------------------------------------------------------------------------
		Harness.test("downtime shortens as candles are lit, and telegraphs never do", function()
			local early = UnlittiusRules.downtimeSeconds(0, 1)
			local mid = UnlittiusRules.downtimeSeconds(4, 1)
			local late = UnlittiusRules.downtimeSeconds(7, 1)
			Harness.expect(early > mid and mid > late, "the fight gets faster between actions, not inside them")
			for _, lit in { 0, 2, 3, 5, 6, 7 } do
				local shortest = UnlittiusRules.downtimeSeconds(lit, 0)
				local longest = UnlittiusRules.downtimeSeconds(lit, 1)
				Harness.expect(shortest <= longest, "the band must not be inverted at " .. lit .. " candles")
				Harness.expect(shortest > 0, "he never chains two actions with no gap at all")
			end
			-- THE FAIRNESS INVARIANT. Every telegraph is a fixed number in `Config.Unlittius.timings`
			-- and nothing in this module can scale one — this asserts the shape of that contract rather
			-- than a value, so a future "difficulty" pass cannot quietly make the tells shorter.
			Harness.equal(UnlittiusConfig.timings.dripstoneSnapAt, 1.62, "the dripstone telegraph is fixed")
			Harness.equal(UnlittiusConfig.timings.meleeHit1At, 0.56, "the first rake's windup is fixed")
			Harness.expect(
				UnlittiusConfig.dripstone.telegraphSeconds < UnlittiusConfig.timings.dripstoneSnapAt,
				"the floor marker must be up before the snap that drops the stone"
			)
		end),

		Harness.test("a player standing under him is raked rather than rolled for", function()
			local action = UnlittiusRules.chooseAction(context({ meleeCandidate = true, meleeReady = true, roll = 0 }))
			Harness.equal(action, "Melee", "melee is a condition, never a weight")
			-- ...but only when it is off cooldown. Otherwise he answers with something else rather than
			-- standing still, which is what keeps hugging the dais from switching the fight off.
			local onCooldown =
				UnlittiusRules.chooseAction(context({ meleeCandidate = true, meleeReady = false, roll = 0 }))
			Harness.expect(onCooldown ~= "Melee", "a rake on cooldown must not be selected")
		end),

		Harness.test("the summon is skipped when it is capped and the roll is honest without it", function()
			-- With the summon ineligible, its weight must not silently redistribute onto one option: the
			-- remaining two keep their relative odds, which is the property that makes the weights mean
			-- what they say.
			local dripstoneHits, boulderHits = 0, 0
			for step = 0, 999 do
				local action = UnlittiusRules.chooseAction(context({ summonEligible = false, roll = step / 1000 }))
				Harness.expect(action ~= "SummonGnawers", "a capped summon must never be chosen")
				if action == "Dripstone" then
					dripstoneHits += 1
				elseif action == "BoulderBurst" then
					boulderHits += 1
				end
			end
			local weights = UnlittiusConfig.director.weights
			local expected = weights.Dripstone / (weights.Dripstone + weights.BoulderBurst)
			Harness.near(dripstoneHits / 1000, expected, 0.02, "dripstone keeps its share of the two-way roll")
			Harness.expect(boulderHits > 0, "the boulder must remain reachable")
		end),

		Harness.test("he will not take the same major attack a third time running", function()
			local limit = UnlittiusConfig.director.repeatLimit
			local recent: { UnlittiusRules.ActionId } = {}
			for _ = 1, limit do
				table.insert(recent, "Dripstone")
			end
			Harness.expect(
				UnlittiusRules.isRepeatExhausted(recent, "Dripstone"),
				"two dripstones in a row exhausts the third"
			)
			Harness.expect(not UnlittiusRules.isRepeatExhausted(recent, "BoulderBurst"), "other options are untouched")
			for step = 0, 99 do
				local action = UnlittiusRules.chooseAction(context({ recent = recent, roll = step / 100 }))
				Harness.expect(action ~= "Dripstone", "an exhausted option must be off the table entirely")
			end
			-- One in a row is not two.
			Harness.expect(
				not UnlittiusRules.isRepeatExhausted({ "Dripstone" }, "Dripstone"),
				"a single repeat is still allowed"
			)
		end),

		Harness.test("the scheduler always returns an attack, however constrained", function()
			-- A boss who stops scheduling is a boss the party can ignore while they walk the ring, so
			-- there is no context in which the director may answer with nothing. The worst real case is
			-- the arena-control option exhausted AND the summon capped, which still leaves the boulder.
			local exhausted: { UnlittiusRules.ActionId } = { "Dripstone", "Dripstone", "Dripstone" }
			local valid = { Dripstone = true, BoulderBurst = true, SummonGnawers = true, Melee = true }
			for _, roll in { 0, 0.25, 0.5, 0.75, 0.999999, 1, 1.5, -1 } do
				for _, capped in { true, false } do
					for _, recent in { {}, exhausted } do
						local action = UnlittiusRules.chooseAction(context({
							recent = recent,
							summonEligible = not capped,
							roll = roll,
						}))
						Harness.expect(valid[action] == true, "the director returned a non-action at roll " .. roll)
					end
				end
			end
			-- With the arena-control option spent and the summon capped, the boulder is what is left.
			Harness.equal(
				UnlittiusRules.chooseAction(context({ recent = exhausted, summonEligible = false, roll = 0.99 })),
				"BoulderBurst",
				"the one remaining eligible attack must be the one chosen"
			)
			-- An out-of-range roll must clamp rather than fall off the end of the weight walk.
			Harness.expect(
				valid[UnlittiusRules.chooseAction(context({ roll = 42 }))] == true,
				"a roll past 1 must clamp into the table rather than index past it"
			)
		end),

		----------------------------------------------------------------------------------
		-- SCALING
		----------------------------------------------------------------------------------
		Harness.test("volleys and summons scale with the party and never past their caps", function()
			Harness.equal(UnlittiusRules.dripstoneZoneCount(1), UnlittiusConfig.dripstone.zonesSolo)
			Harness.equal(UnlittiusRules.dripstoneZoneCount(2), UnlittiusConfig.dripstone.zonesDuo)
			Harness.equal(UnlittiusRules.dripstoneZoneCount(4), UnlittiusConfig.dripstone.zonesParty)
			Harness.expect(
				UnlittiusRules.dripstoneZoneCount(1) <= UnlittiusRules.dripstoneZoneCount(4),
				"a bigger party never gets fewer zones"
			)

			local cap = UnlittiusConfig.summon.activeCap
			Harness.equal(UnlittiusRules.summonCount(4, cap), 0, "a full cap summons nothing")
			Harness.equal(UnlittiusRules.summonCount(4, cap + 3), 0, "an over-full cap never goes negative")
			Harness.expect(UnlittiusRules.summonCount(1, 0) >= 1, "a solo player still gets summoned company")
			for live = 0, cap do
				local wanted = UnlittiusRules.summonCount(4, live)
				Harness.expect(live + wanted <= cap, "a summon must never push past the active cap")
			end
		end),

		Harness.test("the summon is gated by both its cap and its cooldown", function()
			Harness.expect(UnlittiusRules.summonEligible(0, 100, 50), "off cooldown and under cap is eligible")
			Harness.expect(not UnlittiusRules.summonEligible(0, 40, 50), "still on cooldown is not")
			Harness.expect(
				not UnlittiusRules.summonEligible(UnlittiusConfig.summon.activeCap, 100, 50),
				"at the cap is not, however long it has been"
			)
		end),

		----------------------------------------------------------------------------------
		-- GEOMETRY
		----------------------------------------------------------------------------------
		Harness.test("the claw only reaches what is in front of him", function()
			local origin = Vector3.new(0, 0, 0)
			local facing = Vector3.new(0, 0, -1)
			local arc = UnlittiusConfig.melee.arcDot
			Harness.expect(UnlittiusRules.insideArc(origin, facing, Vector3.new(0, 0, -10), arc), "dead ahead")
			Harness.expect(
				not UnlittiusRules.insideArc(origin, facing, Vector3.new(0, 0, 10), arc),
				"directly behind him is safe — the rake is a front arc and getting round him is the counter"
			)
			-- HEIGHT MUST NOT MATTER. He hovers six studs up; a reach measured as a diagonal would
			-- shrink and grow with how high he happens to be bobbing.
			Harness.expect(
				UnlittiusRules.insideArc(origin, facing, Vector3.new(0, -6.4, -10), arc),
				"a player on the floor below him is still in front of him"
			)
			Harness.near(UnlittiusRules.flatDistance(Vector3.new(3, 40, 4), Vector3.zero), 5, 1e-6, "distance is flat")
		end),

		Harness.test("a boulder leads a running target but never a launched one", function()
			local position = Vector3.new(0, 0, 0)
			local walking = UnlittiusRules.leadTarget(position, Vector3.new(8, 0, 0))
			Harness.near(walking.X, 8 * UnlittiusConfig.boulder.predictionSeconds, 1e-6, "a walker is led honestly")
			-- CLAMPED, so a player being flung by a blast is not answered with a shot into the far wall.
			local launched = UnlittiusRules.leadTarget(position, Vector3.new(400, 0, 0))
			Harness.near(
				launched.X,
				UnlittiusConfig.boulder.predictionMaxSpeed * UnlittiusConfig.boulder.predictionSeconds,
				1e-6,
				"absurd velocity is clamped to the prediction ceiling"
			)
			-- VERTICAL VELOCITY IS IGNORED: a jumping player is not led into the ceiling.
			local jumping = UnlittiusRules.leadTarget(position, Vector3.new(0, 60, 0))
			Harness.near(jumping.Y, 0, 1e-6, "a jump does not move the aim point upward")
		end),

		Harness.test("a boulder's direction is taken from its own spawn point", function()
			-- THE PROPERTY THAT KEEPS A CONJURED STONE OUT OF HIS OWN TORSO: the direction is computed
			-- from the shoulder attachment it materialises at, never from his root.
			local shoulder = Vector3.new(-3.4, 1.1, -2.4)
			local target = Vector3.new(-3.4, 1.1, -30)
			local direction = UnlittiusRules.boulderDirection(shoulder, target)
			Harness.near(direction.Magnitude, 1, 1e-6, "always a unit vector")
			Harness.near(direction.X, 0, 1e-6, "a straight-ahead shot from the left shoulder stays left")
			-- A degenerate aim (target exactly on the spawn point) must not produce a NaN direction that
			-- would send the projectile stepper into an infinite loop.
			local degenerate = UnlittiusRules.boulderDirection(shoulder, shoulder)
			Harness.near(degenerate.Magnitude, 1, 1e-6, "a degenerate aim still yields a real direction")
		end),

		Harness.test("a conjured boulder never crosses his own body, from any angle", function()
			-- THE PACKAGE'S HARDEST REQUIREMENT ON THIS ATTACK, and the bug it explicitly calls out from
			-- the previous implementation. Swept over every target bearing rather than spot-checked,
			-- because the failure is angular: it only happens when the firing shoulder is on the far side
			-- of the target, which is exactly what a fixed left-then-right pattern guarantees for half
			-- the circle.
			local boulder = UnlittiusConfig.boulder
			local bodyRadius = 3.2
			local center = Vector3.new(12, 0, -30)
			for facingStep = 0, 7 do
				local facingAngle = facingStep / 8 * math.pi * 2
				local forward = Vector3.new(math.sin(facingAngle), 0, math.cos(facingAngle))
				local right = Vector3.new(-forward.Z, 0, forward.X)
				for targetStep = 0, 71 do
					local targetAngle = targetStep / 72 * math.pi * 2
					-- Swept from the minimum engagement range outward. Closer than that he does not fire
					-- this attack at all (`UnlittiusRules.boulderTargets`), because the geometry there is
					-- unwinnable from either shoulder — which the test below pins separately.
					for _, range in { boulder.minimumEngagementRange, 18, 30, 45 } do
						local target = center
							+ Vector3.new(math.cos(targetAngle) * range, 2.2, math.sin(targetAngle) * range)
						local side = UnlittiusRules.boulderSide(center, forward, target)
						Harness.expect(side == 1 or side == -1, "the side must resolve to one shoulder or the other")
						local spawn = center
							+ right * (side * boulder.spawnOutboard)
							+ forward * boulder.spawnForward
							+ Vector3.new(0, boulder.spawnHeight, 0)
						-- The chosen shoulder must clear him. This is the property the behaviour relies on
						-- before it falls back to the other side.
						local direction = UnlittiusRules.boulderDirection(spawn, target)
						local clears =
							UnlittiusRules.boulderPathClears(spawn, direction, center, bodyRadius, boulder.maxDistance)
						-- If the near shoulder somehow does not clear, the far one is what the behaviour
						-- uses — so at least one of the two must always work, or the attack has no safe
						-- origin at all and the whole guarantee is empty.
						if not clears then
							local otherSpawn = center
								+ right * (-side * boulder.spawnOutboard)
								+ forward * boulder.spawnForward
								+ Vector3.new(0, boulder.spawnHeight, 0)
							Harness.expect(
								UnlittiusRules.boulderPathClears(
									otherSpawn,
									UnlittiusRules.boulderDirection(otherSpawn, target),
									center,
									bodyRadius,
									boulder.maxDistance
								),
								string.format(
									"neither shoulder clears his torso at facing %d, bearing %d, range %d",
									facingStep,
									targetStep,
									range
								)
							)
						end
					end
				end
			end
			-- The spawn attachments themselves must sit outside the body they are attached to, or none of
			-- the above can hold: a muzzle inside the torso starts every shot already clipping.
			Harness.expect(
				boulder.spawnOutboard > bodyRadius,
				"the shoulder attachments must be outboard of his own clearance radius"
			)
		end),

		Harness.test("the burst looks past anybody standing on top of him", function()
			local minimum = UnlittiusConfig.boulder.minimumEngagementRange
			-- Two players, one hugging him: the stones go to the one at a workable range, both of them.
			local targets = UnlittiusRules.boulderTargets({
				{ id = 11, distance = 4 },
				{ id = 22, distance = minimum + 10 },
			})
			Harness.equal(#targets, 2, "a burst is always exactly two stones")
			Harness.equal(targets[1], 22, "the point-blank player is skipped")
			Harness.equal(targets[2], 22)
			-- Two at workable ranges: one each, nearest first.
			local split = UnlittiusRules.boulderTargets({
				{ id = 33, distance = minimum + 20 },
				{ id = 44, distance = minimum + 2 },
			})
			Harness.equal(split[1], 44, "the nearer eligible player takes the first stone")
			Harness.equal(split[2], 33, "and the second goes to somebody else")
			-- Solo: both at the one player.
			local solo = UnlittiusRules.boulderTargets({ { id = 55, distance = minimum + 5 } })
			Harness.equal(solo[1], 55)
			Harness.equal(solo[2], 55)
			-- EVERYBODY too close: it still fires, at the furthest of them. An attack that silently did
			-- nothing would be a worse failure than an ugly shot.
			local crowded = UnlittiusRules.boulderTargets({
				{ id = 66, distance = 3 },
				{ id = 77, distance = 9 },
			})
			Harness.equal(#crowded, 2, "the burst still happens")
			Harness.equal(crowded[1], 77, "aimed at the least bad geometry available")
			-- An empty room fires nothing rather than erroring.
			Harness.equal(#UnlittiusRules.boulderTargets({}), 0)
			-- The minimum has to be outside his melee trigger, or the two attacks fight over the same
			-- band and a player in it can be answered by neither.
			Harness.expect(
				minimum >= UnlittiusConfig.melee.triggerRadius,
				"the rake must own the range the boulder refuses"
			)
		end),

		Harness.test("the near shoulder is the one that fires", function()
			local center = Vector3.zero
			local forward = Vector3.new(0, 0, -1)
			local right = Vector3.new(-forward.Z, 0, forward.X)
			-- A target off his right fires from the right shoulder, and vice versa. This is the whole
			-- mechanism: it makes the flight path diverge from his body instead of crossing it.
			Harness.equal(UnlittiusRules.boulderSide(center, forward, center + right * 10 + forward * 10), 1)
			Harness.equal(UnlittiusRules.boulderSide(center, forward, center - right * 10 + forward * 10), -1)
			-- Behind him, too: the near shoulder is still the one that has to swing least.
			Harness.equal(UnlittiusRules.boulderSide(center, forward, center + right * 10 - forward * 10), 1)
			-- Degenerate inputs resolve rather than erroring — a target exactly on him, or no facing.
			Harness.expect(UnlittiusRules.boulderSide(center, forward, center) ~= nil)
			Harness.expect(UnlittiusRules.boulderSide(center, Vector3.zero, center + right * 5) ~= nil)
		end),

		----------------------------------------------------------------------------------
		-- MOVEMENT
		----------------------------------------------------------------------------------
		Harness.test("he levitates slower than a player walks, in every mode", function()
			-- The invariant that keeps him from being a chase. If either of these ever exceeds a walk,
			-- the encounter stops being "hold the shrine" and becomes a pursuit the design forbids.
			local movement = UnlittiusConfig.movement
			Harness.expect(movement.driftSpeed > 0, "he does move")
			Harness.expect(movement.repositionSpeed > movement.driftSpeed, "hunting an angle has some urgency")
			Harness.expect(movement.repositionSpeed < 8, "he must never outpace a walking player")
			Harness.equal(UnlittiusRules.driftSpeed("Reposition"), movement.repositionSpeed)
			Harness.equal(UnlittiusRules.driftSpeed("Withdraw"), movement.driftSpeed)
			Harness.equal(UnlittiusRules.driftSpeed("Recenter"), movement.driftSpeed)
			Harness.equal(UnlittiusRules.driftSpeed("Hold"), 0, "with nothing to answer he holds station")
		end),

		Harness.test("he holds the shrine and never approaches anybody", function()
			-- THE HEADLINE RULE. There is no distance at which he decides to come to you: the intent set
			-- has no "approach" in it, and this sweeps the whole range band to prove no input produces
			-- movement toward a player who is simply far away.
			local movement = UnlittiusConfig.movement
			for distance = movement.minimumRange, 120, 3 do
				local intent = UnlittiusRules.driftIntent({
					nearestDistance = distance,
					hasLineOfSight = true,
					distanceFromHome = 0,
				})
				Harness.equal(
					intent,
					"Hold",
					string.format("he must not move for a visible player %d studs away", distance)
				)
			end
			-- An empty room holds too.
			Harness.equal(
				UnlittiusRules.driftIntent({ nearestDistance = nil, hasLineOfSight = true, distanceFromHome = 0 }),
				"Hold"
			)
		end),

		Harness.test("cover costs him an angle, not the fight", function()
			-- The ONE thing that makes him move toward a decision rather than away from one: a player
			-- behind a pillar. He sidesteps until he can see them again.
			local blocked = UnlittiusRules.driftIntent({
				nearestDistance = 30,
				hasLineOfSight = false,
				distanceFromHome = 0,
			})
			Harness.equal(blocked, "Reposition", "a broken line of sight is what moves him")

			local origin = Vector3.new(0, 6, 0)
			local home = Vector3.zero
			local target = Vector3.new(0, 0, -20)
			local sidestep = UnlittiusRules.driftDirection("Reposition", origin, target, home, 1)
			Harness.near(sidestep.Magnitude, 1, 1e-6)
			-- STRICTLY PERPENDICULAR: he changes the angle without changing the range, so how far away
			-- the player stands remains the player's decision even while he works around their cover.
			local toTarget = (target - origin)
			local forward = Vector3.new(toTarget.X, 0, toTarget.Z).Unit
			Harness.near(sidestep:Dot(forward), 0, 1e-6, "repositioning must not close or open the range")
			local other = UnlittiusRules.driftDirection("Reposition", origin, target, home, -1)
			Harness.expect(sidestep:Dot(other) < -0.99, "the two sidestep signs must be exact opposites")
			Harness.near(sidestep.Y, 0, 1e-9, "he never drifts vertically; hover owns his height")
		end),

		Harness.test("he backs off anybody crowding him, toward his own shrine", function()
			local movement = UnlittiusConfig.movement
			Harness.equal(
				UnlittiusRules.driftIntent({
					nearestDistance = movement.minimumRange - 1,
					hasLineOfSight = true,
					distanceFromHome = 0,
				}),
				"Withdraw",
				"too close: make room for a volley"
			)
			-- Withdrawing must be biased homeward, or a player standing between him and the dais would
			-- walk him to the end of his leash and strand him there for the rest of the fight.
			local origin = Vector3.new(0, 6, -6)
			local home = Vector3.zero
			local target = Vector3.new(0, 0, -10)
			local away = UnlittiusRules.driftDirection("Withdraw", origin, target, home, 1)
			Harness.near(away.Magnitude, 1, 1e-6)
			Harness.expect(away.Z > 0, "he backs away from them")
			local homeward = (home - origin)
			Harness.expect(
				away:Dot(Vector3.new(homeward.X, 0, homeward.Z).Unit) > 0,
				"and the retreat carries him back toward the dais rather than out to the leash"
			)
		end),

		Harness.test("the shrine pulls him back before anything else does", function()
			local movement = UnlittiusConfig.movement
			-- RECENTER OUTRANKS EVERYTHING. Even with a player crowding him and cover in the way, a boss
			-- at the end of his leash goes home first — that is what "bound to the dais" means.
			Harness.equal(
				UnlittiusRules.driftIntent({
					nearestDistance = 1,
					hasLineOfSight = false,
					distanceFromHome = movement.homeRadius + 1,
				}),
				"Recenter"
			)
			local origin = Vector3.new(20, 6, 0)
			local home = Vector3.zero
			local back = UnlittiusRules.driftDirection("Recenter", origin, nil, home, 1)
			Harness.near(back.Magnitude, 1, 1e-6)
			Harness.expect(back.X < -0.99, "he goes straight home")
			-- Recentering works with nobody in the room at all, which is when it matters most.
			Harness.expect(
				UnlittiusRules.driftDirection("Recenter", origin, nil, home, -1).X < -0.99,
				"the sidestep sign must not affect going home"
			)
		end),

		Harness.test("velocity is eased, never assigned, so he cannot snap between positions", function()
			local movement = UnlittiusConfig.movement
			local desired = Vector3.new(movement.repositionSpeed, 0, 0)
			local velocity = Vector3.zero
			local dt = 1 / 60
			-- From a standstill he must take real time to reach speed: the whole read of a heavy floating
			-- body is in this ramp.
			local steps = 0
			while (velocity - desired).Magnitude > 0.05 and steps < 600 do
				velocity = UnlittiusRules.stepVelocity(velocity, desired, dt)
				steps += 1
			end
			local seconds = steps * dt
			Harness.expect(seconds > 1.5, "reaching full speed instantly would read as a teleporting prop")
			Harness.expect(seconds < 6, "and taking six seconds would read as broken")
			-- One step can never move him further than the acceleration allows.
			local single = UnlittiusRules.stepVelocity(Vector3.zero, desired, dt)
			Harness.expect(
				single.Magnitude <= movement.acceleration * dt + 1e-6,
				"a single step must respect the acceleration limit"
			)
			-- Stopping is brisker than starting, and lands exactly on zero rather than oscillating.
			local stopping = Vector3.new(movement.repositionSpeed, 0, 0)
			local stopSteps = 0
			while stopping.Magnitude > 1e-3 and stopSteps < 600 do
				stopping = UnlittiusRules.stepVelocity(stopping, Vector3.zero, dt)
				stopSteps += 1
			end
			Harness.expect(stopSteps < steps, "he stops quicker than he starts")
			Harness.expect(stopping.Magnitude <= 1e-3, "and comes to a real stop rather than creeping")
		end),

		Harness.test("he can never drift off his shrine, or out of a room smaller than the leash", function()
			local movement = UnlittiusConfig.movement
			local center = Vector3.new(40, 12, -80)
			local radius = 32
			-- TWO LIMITS, TIGHTER WINS. The leash is the real bound in any normal chamber; the wall is the
			-- backstop for a room narrower than the leash assumes.
			local limit = math.min(movement.homeRadius, radius - movement.wallMargin)
			Harness.equal(limit, movement.homeRadius, "in an ordinary chamber the leash is what binds him")
			-- Inside is left exactly alone: the clamp must not nudge a boss who is already legal.
			local inside = center + Vector3.new(3, 0, -4)
			local kept, corrected = UnlittiusRules.clampToChamber(inside, center, radius)
			Harness.expect(not corrected, "an in-bounds position is not corrected")
			Harness.vectorNear(kept, inside, 1e-9)
			-- Outside is pulled back to the limit, keeping its height.
			local outside = center + Vector3.new(200, 0, 0)
			local clamped, wasCorrected = UnlittiusRules.clampToChamber(outside, center, radius)
			Harness.expect(wasCorrected, "an out-of-bounds position must be corrected")
			Harness.near(UnlittiusRules.flatDistance(clamped, center), limit, 1e-6, "clamped onto the limit ring")
			Harness.near(clamped.Y, outside.Y, 1e-9, "the clamp is horizontal; it must not drop him")
			-- Swept: no bearing may escape.
			for step = 0, 35 do
				local angle = step / 36 * math.pi * 2
				local far = center + Vector3.new(math.cos(angle) * 500, 0, math.sin(angle) * 500)
				local result = UnlittiusRules.clampToChamber(far, center, radius)
				Harness.expect(
					UnlittiusRules.flatDistance(result, center) <= limit + 1e-6,
					"escaped the chamber at bearing " .. step
				)
			end
			-- He keeps a real margin off the wall, so a boulder can never be fired from inside rock.
			Harness.expect(movement.wallMargin > UnlittiusConfig.boulder.spawnOutboard, "his muzzles stay in the room")
			-- A TINY ROOM STILL BINDS HIM. If a chamber is narrower than the leash, the wall wins.
			local tight = 16
			local tightLimit = tight - movement.wallMargin
			local squeezed = UnlittiusRules.clampToChamber(center + Vector3.new(100, 0, 0), center, tight)
			Harness.near(
				UnlittiusRules.flatDistance(squeezed, center),
				tightLimit,
				1e-6,
				"a room narrower than the leash must clamp to the wall instead"
			)
		end),

		Harness.test("two minutes of hunting an angle never takes him off his shrine", function()
			-- Integrated rather than reasoned about. A player who keeps breaking line of sight makes him
			-- sidestep continuously in one direction and then the other; the failure mode being pinned is
			-- that a perpendicular slide, repeated for minutes, slowly walks him off the dais and out to
			-- the wall. The leash plus the recenter intent must beat that.
			local center = Vector3.zero
			local radius = 28
			local leash = UnlittiusConfig.movement.homeRadius
			local position = center + Vector3.new(3, 0, 3)
			local velocity = Vector3.zero
			local dt = 1 / 30
			local target = Vector3.new(0, 0, 26)
			local recentered = 0
			for step = 1, 3600 do
				-- Cover comes and goes as they move behind pillars; the sign flips as he loses the angle
				-- on one side and picks it up on the other.
				local blocked = (step // 90) % 3 ~= 0
				local intent = UnlittiusRules.driftIntent({
					nearestDistance = UnlittiusRules.flatDistance(position, target),
					hasLineOfSight = not blocked,
					distanceFromHome = UnlittiusRules.flatDistance(position, center),
				})
				if intent == "Recenter" then
					recentered += 1
				end
				local sign = if (step // 105) % 2 == 0 then 1 else -1
				local direction = UnlittiusRules.driftDirection(intent, position, target, center, sign)
				velocity = UnlittiusRules.stepVelocity(velocity, direction * UnlittiusRules.driftSpeed(intent), dt)
				position += velocity * dt
				local clamped, corrected = UnlittiusRules.clampToChamber(position, center, radius)
				position = clamped
				if corrected then
					velocity = Vector3.zero
				end
				Harness.expect(
					UnlittiusRules.flatDistance(position, center) <= leash + 1e-6,
					string.format(
						"drifted %.1f studs off the shrine on step %d",
						UnlittiusRules.flatDistance(position, center),
						step
					)
				)
			end
			-- And the leash was actually exercised rather than the test passing because he never moved.
			Harness.expect(recentered > 0, "the shrine should have had to pull him back at least once")
		end),

		Harness.test("dripstone zones are spread, bounded, and never centred on a standing player", function()
			local center = Vector3.zero
			local targets = { Vector3.new(10, 0, 0), Vector3.new(-8, 0, 6) }
			local rolls = {}
			for index = 1, 24 do
				rolls[index] = (index * 0.137) % 1
			end
			local zones = UnlittiusRules.dripstoneZones(targets, 6, rolls, center, 26)
			Harness.expect(#zones > 0, "a volley must actually place zones")
			Harness.expect(#zones <= 6, "never more than asked for")
			for index, zone in zones do
				-- INSIDE THE CHAMBER. A marker outside the room is damage nobody can be standing in and
				-- makes the volley read as smaller than it is.
				Harness.expect(
					UnlittiusRules.flatDistance(zone, center) <= 26 + 1e-6,
					"zone " .. index .. " landed outside the chamber"
				)
				-- OFFSET FROM THE PLAYER, not on them: this is the difference between a demand to move
				-- and a tax on standing still.
				for _, target in targets do
					Harness.expect(
						UnlittiusRules.flatDistance(zone, target) >= UnlittiusConfig.dripstone.aimSpreadMin - 1e-6,
						"zone " .. index .. " was dropped on somebody's head"
					)
				end
				-- SEPARATED, so a volley can never wall a player in.
				for other = index + 1, #zones do
					Harness.expect(
						UnlittiusRules.flatDistance(zone, zones[other])
							>= UnlittiusConfig.dripstone.minimumZoneSeparation - 1e-6,
						"zones " .. index .. " and " .. other .. " overlap"
					)
				end
			end
			-- Deterministic given the same rolls, which is what makes the placement testable at all.
			local repeated = UnlittiusRules.dripstoneZones(targets, 6, rolls, center, 26)
			Harness.equal(#repeated, #zones, "the same rolls must place the same volley")
			for index, zone in zones do
				Harness.vectorNear(repeated[index], zone, 1e-9, "zone " .. index .. " is not deterministic")
			end
			-- Nobody to aim at is not an error; it is an empty volley.
			Harness.equal(#UnlittiusRules.dripstoneZones({}, 6, rolls, center, 26), 0, "no targets, no stones")
		end),

		Harness.test("the shrine is eight evenly spaced candles that fit inside the chamber", function()
			local offsets = UnlittiusRules.candleOffsets()
			Harness.equal(#offsets, CANDLES, "there are exactly eight candles and the count is structural")
			local radius = UnlittiusConfig.encounter.candleRingRadius
			for index, offset in offsets do
				Harness.near(offset.Magnitude, radius, 1e-6, "candle " .. index .. " is off the ring")
				Harness.near(offset.Y, 0, 1e-9, "the ring is flat; the encounter seats each one on real ground")
				-- OUTSIDE THE DAIS. Standing at a candle must mean standing in the open, not on his plinth.
				Harness.expect(
					offset.Magnitude > UnlittiusConfig.encounter.daisRadius,
					"candle " .. index .. " is inside the dais"
				)
				-- INSIDE THE CHAMBER, with room to walk around the outside of the ring.
				Harness.expect(
					offset.Magnitude < UnlittiusFloorPlan.chamberRadius(),
					"candle " .. index .. " is outside the authored chamber"
				)
			end
			-- Evenly spaced: every neighbouring pair is the same distance apart.
			local firstGap = (offsets[2] - offsets[1]).Magnitude
			for index = 2, #offsets do
				local nextOffset = offsets[(index % #offsets) + 1]
				Harness.near((nextOffset - offsets[index]).Magnitude, firstGap, 1e-5, "the ring is not even")
			end
			-- Rotated off his facing, so the first candle a player reaches is never the one in his rake.
			Harness.expect(math.abs(offsets[1].Z) > 1e-3, "the ring must be rotated off the boss's own axis")
		end),

		Harness.test("summoned Gnawers surface away from the dais and away from each other", function()
			local center = Vector3.new(20, 5, -10)
			local first = UnlittiusRules.summonPoint(center, 1, 2, 0.2)
			local second = UnlittiusRules.summonPoint(center, 2, 2, 0.2)
			for _, point in { first, second } do
				local distance = UnlittiusRules.flatDistance(point, center)
				Harness.expect(
					distance >= UnlittiusConfig.summon.spawnRadiusMin - 1e-6
						and distance <= UnlittiusConfig.summon.spawnRadiusMax + 1e-6,
					"a summon must arrive inside its authored ring"
				)
				Harness.expect(distance > UnlittiusConfig.encounter.daisRadius, "nothing surfaces on the dais itself")
			end
			Harness.expect(
				UnlittiusRules.flatDistance(first, second) > 1,
				"two summoned at once must not arrive in the same place"
			)
		end),

		----------------------------------------------------------------------------------
		-- CANDLES
		----------------------------------------------------------------------------------
		Harness.test("you light his shrine off your own flame or not at all", function()
			local allowed, refusal = UnlittiusRules.canLightCandle(baseCandleRequest())
			Harness.expect(allowed, "an alive, lit, close player may light a dead candle")
			Harness.isNil(refusal, "an accepted light carries no refusal")

			local function refuse(mutate: (UnlittiusRules.CandleRequest) -> ()): UnlittiusRules.CandleRefusal?
				local request = baseCandleRequest()
				mutate(request)
				local ok, why = UnlittiusRules.canLightCandle(request)
				Harness.expect(not ok, "this request should have been refused")
				return why
			end

			-- THE ORDER IS DELIBERATE and copied from the wall lamp: the candle's own state first, then
			-- the player's, then geometry — so a dead player at a lit candle is told the candle is lit,
			-- because that is the reason nothing would have happened anyway.
			Harness.equal(
				refuse(function(request)
					request.candleLit = true
					request.alive = false
				end),
				"alreadyLit",
				"an already-lit candle answers first, whatever else is wrong"
			)
			Harness.equal(
				refuse(function(request)
					request.alive = false
				end),
				"notAlive"
			)
			Harness.equal(
				refuse(function(request)
					request.finished = true
				end),
				"finished"
			)
			Harness.equal(
				refuse(function(request)
					request.playerDepth = 9
				end),
				"wrongFloor"
			)
			-- THE ONE THAT MAKES THE ENCOUNTER A FIGHT: a party that has gone dark cannot rush the last
			-- candle. The resource you spend to win is the resource you need to survive.
			Harness.equal(
				refuse(function(request)
					request.isLit = false
				end),
				"notLit"
			)
			Harness.equal(
				refuse(function(request)
					request.isCupping = true
				end),
				"cupping"
			)
			Harness.equal(
				refuse(function(request)
					request.distance = UnlittiusRules.candleServerRange() + 0.1
				end),
				"tooFar"
			)
		end),

		Harness.test("the server accepts a little further than the prompt shows", function()
			local range = UnlittiusRules.candleServerRange()
			Harness.expect(
				range > UnlittiusConfig.encounter.candlePromptRange,
				"a player who took one step during their own round trip is not a cheat"
			)
			Harness.near(
				range,
				UnlittiusConfig.encounter.candlePromptRange + UnlittiusConfig.encounter.candlePositionToleranceStuds,
				1e-9
			)
			local request = baseCandleRequest()
			request.distance = range
			Harness.expect(UnlittiusRules.canLightCandle(request), "exactly at the server range is accepted")
		end),

		----------------------------------------------------------------------------------
		-- INTERRUPTION
		----------------------------------------------------------------------------------
		Harness.test("a candle interrupts a windup but never rewinds a hit that already landed", function()
			local timings = UnlittiusConfig.timings
			Harness.expect(UnlittiusRules.canInterruptFor("Idle", 0), "idle always yields to a recoil")
			-- BEFORE the authoritative beat: the rest of the action can be abandoned safely.
			Harness.expect(UnlittiusRules.canInterruptFor("Dripstone", timings.dripstoneSnapAt - 0.1))
			Harness.expect(UnlittiusRules.canInterruptFor("BoulderBurst", timings.boulderConjureAt - 0.01))
			Harness.expect(UnlittiusRules.canInterruptFor("SummonGnawers", timings.summonSpawnAt - 0.1))
			Harness.expect(UnlittiusRules.canInterruptFor("Melee", timings.meleeHit1At - 0.1))
			-- AFTER it: the stone is falling, the boulder is in the air, the rake landed. The recoil
			-- still plays — the behaviour always starts it — but nothing that happened is undone, and
			-- this is the function that records which of those two worlds we are in.
			Harness.expect(not UnlittiusRules.canInterruptFor("Dripstone", timings.dripstoneSnapAt))
			Harness.expect(not UnlittiusRules.canInterruptFor("BoulderBurst", timings.boulderFire1At))
			Harness.expect(not UnlittiusRules.canInterruptFor("Melee", timings.meleeHit2At))
			-- THE TWO THAT MUST NEVER BE INTERRUPTED. A second recoil stacking on the first is two
			-- full-body animations at once; interrupting a banish is an encounter that cannot end.
			Harness.expect(not UnlittiusRules.canInterruptFor("Recoil", 0), "recoils must not stack")
			Harness.expect(not UnlittiusRules.canInterruptFor("Banish", 0), "the banish is never interrupted")
			Harness.expect(not UnlittiusRules.canInterruptFor("Banish", 99), "not even later")
		end),

		Harness.test("every authoritative beat sits inside its own animation", function()
			-- A beat authored past the end of its action would never fire, which is an attack that
			-- silently stops dealing damage — the exact failure a timeline this hand-tuned invites.
			local timings = UnlittiusConfig.timings
			for _, row in
				{
					{ "dripstone snap", timings.dripstoneSnapAt, timings.dripstoneLength },
					{ "boulder conjure", timings.boulderConjureAt, timings.boulderLength },
					{ "boulder shot 1", timings.boulderFire1At, timings.boulderLength },
					{ "boulder shot 2", timings.boulderFire2At, timings.boulderLength },
					{ "summon spawn", timings.summonSpawnAt, timings.summonLength },
					{ "rake 1", timings.meleeHit1At, timings.meleeLength },
					{ "rake 2", timings.meleeHit2At, timings.meleeLength },
					{ "recoil impact", timings.recoilImpactAt, timings.recoilLength },
				}
			do
				Harness.expect(row[2] > 0, row[1] .. " must not fire on frame zero")
				Harness.expect(row[2] < row[3], row[1] .. " fires after its own animation has ended")
				Harness.expect(UnlittiusRules.beatReached(row[2], row[2]), row[1] .. " must fire exactly on time")
				Harness.expect(not UnlittiusRules.beatReached(row[2] - 0.001, row[2]), row[1] .. " must not fire early")
			end
			Harness.expect(timings.boulderFire2At > timings.boulderFire1At, "the second stone follows the first")
			Harness.near(
				timings.boulderFire2At - timings.boulderFire1At,
				UnlittiusConfig.boulder.shotSpacing,
				1e-9,
				"the authored shot spacing and the animation's own beats must agree"
			)
			Harness.expect(timings.meleeHit2At > timings.meleeHit1At, "the second rake follows the first")
		end),

		----------------------------------------------------------------------------------
		-- DAMAGE SCALE
		----------------------------------------------------------------------------------
		Harness.test("every hit is a fraction of a candle, and none of them is a one-shot", function()
			-- There are no hit points in this game. Each of these is a share of the player's maximum
			-- wax, and the whole table has to stay under the Queen's bite (0.8) — she is the biggest
			-- single hit in the game by design and he must not quietly take that title.
			local biggest = GrubQueenConfig.biteDamage
			for name, damage in
				{
					dripstone = UnlittiusConfig.dripstone.damage,
					boulder = UnlittiusConfig.boulder.damage,
					rake = UnlittiusConfig.melee.damagePerSwipe,
				}
			do
				Harness.expect(damage > 0 and damage < 1, name .. " must be a fraction of a candle")
				Harness.expect(damage < biggest, name .. " must not out-hit the Grub Queen's bite")
			end
			-- BOTH RAKES TOGETHER still leave a full candle standing: being caught under him twice is
			-- the most expensive mistake in the room and is deliberately survivable from full.
			Harness.expect(
				UnlittiusConfig.melee.damagePerSwipe * 2 < 1,
				"a full double rake must not empty a full candle"
			)
		end),

		----------------------------------------------------------------------------------
		-- THE ROTATION
		----------------------------------------------------------------------------------
		Harness.test("the two bosses alternate every ten floors, starting with her", function()
			Harness.equal(BossRotation.bossAt(10), "GrubQueen", "she is first, at floor ten")
			Harness.equal(BossRotation.bossAt(20), "Unlittius", "he is ten floors after her")
			Harness.equal(BossRotation.bossAt(30), "GrubQueen")
			Harness.equal(BossRotation.bossAt(40), "Unlittius")
			-- Deep floors follow the same parity: floor 10n is hers when n is odd and his when n is even.
			Harness.equal(BossRotation.bossAt(150), "GrubQueen", "floor 150 is the fifteenth turn, so hers")
			Harness.equal(BossRotation.bossAt(160), "Unlittius", "and 160 is the sixteenth, so his")
			-- Nothing before the first one, and nothing between them.
			for depth = 1, 9 do
				Harness.isNil(BossRotation.bossAt(depth), "floor " .. depth .. " is too shallow for a boss")
			end
			for depth = 11, 19 do
				Harness.isNil(BossRotation.bossAt(depth), "floor " .. depth .. " sits between boss floors")
			end
			Harness.expect(BossRotation.isBossDepth(20), "floor 20 is a boss floor")
			Harness.expect(not BossRotation.isBossDepth(25), "floor 25 is not")
			-- A fractional or malformed depth must resolve rather than error: floors are planned from
			-- arithmetic that has been wrong before.
			Harness.isNil(BossRotation.bossAt(0 / 0), "NaN is not a boss floor")
			Harness.isNil(BossRotation.bossAt(-40), "a negative depth is not a boss floor")
			Harness.equal(BossRotation.bossAt(20.6), "Unlittius", "a fractional depth floors to its own floor")
		end),

		Harness.test("the rotation is a promise across floors, not a per-floor roll", function()
			-- Planned independently and out of order, so the same depth must answer the same way every
			-- time it is asked, from any order of asking.
			local forward: { [number]: string } = {}
			for depth = 1, 120 do
				local bossId = BossRotation.bossAt(depth)
				if bossId ~= nil then
					forward[depth] = bossId
				end
			end
			for depth = 120, 1, -1 do
				local bossId = BossRotation.bossAt(depth)
				Harness.equal(bossId, forward[depth], "floor " .. depth .. " answered differently in reverse")
			end
			-- Exactly twelve boss floors in the first 120, alternating evenly.
			local queens, unlits = 0, 0
			for _, bossId in forward do
				if bossId == "GrubQueen" then
					queens += 1
				else
					unlits += 1
				end
			end
			Harness.equal(queens, 6, "six Queen floors in the first hundred and twenty")
			Harness.equal(unlits, 6, "and six shrines")
		end),

		Harness.test("the next boss floor can be looked up without re-deriving the schedule", function()
			local depth, bossId = BossRotation.nextBossDepth(1)
			Harness.equal(depth, 10)
			Harness.equal(bossId, "GrubQueen")
			depth, bossId = BossRotation.nextBossDepth(11)
			Harness.equal(depth, 20)
			Harness.equal(bossId, "Unlittius")
			depth, bossId = BossRotation.nextBossDepth(20)
			Harness.equal(depth, 20, "standing on a boss floor answers with that floor")
			Harness.equal(bossId, "Unlittius")
		end),

		----------------------------------------------------------------------------------
		-- THE FLOOR
		----------------------------------------------------------------------------------
		Harness.test("the shrine fits the room the floor builder actually carves", function()
			-- THE INTEGRATION CHECK. The candle ring, the dais and the boss are all placed from
			-- `Config/Unlittius` in encounter space, but the room they land in is carved by the ordinary
			-- floor builder from a `RoomFootprint`. Nothing enforces that those two agree — so this does.
			local half = RoomFootprint.maximumHalfExtent()
			local laneHalfWidth = RoomFootprint.requiredLaneWidth() / 2
			local ringRadius = UnlittiusConfig.encounter.candleRingRadius
			-- The fixture's own footprint, so "the candle fits" means the whole plinth fits.
			local plinthHalfWidth = 1.1

			-- INSIDE THE CARVED ROOM, with the plinth accounted for. A candle against the wall is a
			-- candle half-buried in rock.
			Harness.expect(
				ringRadius + plinthHalfWidth < half - 2,
				string.format("candle ring %.1f + plinth must clear the %.1f-stud room half-extent", ringRadius, half)
			)
			-- OUTSIDE THE DAIS, so standing at one is standing in the open.
			Harness.expect(
				ringRadius > UnlittiusConfig.encounter.daisRadius + plinthHalfWidth,
				"candles clear the dais"
			)

			-- NO CANDLE MAY BLOCK A DOORWAY. The chamber has openings on all four sides, and their lanes
			-- run along the cardinal axes. Eight candles at 45-degree spacing cannot avoid the lanes
			-- entirely, so what matters is that each one leaves a walkable gap beside it rather than
			-- standing in the middle of a doorway.
			local offsets = UnlittiusRules.candleOffsets()
			local worstClearance = math.huge
			for index, offset in offsets do
				-- Distance from each cardinal centreline.
				local fromXAxis = math.abs(offset.Z)
				local fromZAxis = math.abs(offset.X)
				local nearestLane = math.min(fromXAxis, fromZAxis)
				worstClearance = math.min(worstClearance, nearestLane)
				-- Never ON a centreline: a candle dead in a doorway's throat is the failure this ring's
				-- 22.5-degree rotation exists to prevent.
				Harness.expect(
					nearestLane > plinthHalfWidth * 2,
					string.format("candle %d sits on a doorway centreline (%.2f studs off)", index, nearestLane)
				)
				-- And the lane it intrudes into keeps a walkable margin on the far side.
				local remaining = laneHalfWidth + nearestLane - plinthHalfWidth
				Harness.expect(
					remaining >= 8,
					string.format("candle %d leaves only %.1f studs of lane", index, remaining)
				)
			end
			-- The ring is rotated to the best possible bearing for eight candles: any offset other than
			-- 22.5 degrees puts one of them nearer a centreline than this.
			Harness.near(
				worstClearance,
				ringRadius * math.sin(math.rad(22.5)),
				0.01,
				"the ring rotation is no longer the one that maximises doorway clearance"
			)

			-- THE DAIS may sit across the middle of the lanes — that is the navigation hub and it is
			-- always open air — but it must be a STEP rather than a wall, or it becomes the obstruction
			-- the footprint rules exist to prevent.
			Harness.expect(
				UnlittiusConfig.encounter.daisRadius < half,
				"the dais must fit inside the room it is built in"
			)

			-- HIS OWN DRIFT must stay inside the carved room too, with the wall margin applied.
			local chamberRadius = UnlittiusFloorPlan.chamberRadius()
			Harness.expect(chamberRadius <= half, "the drift bound must not exceed the carved room")
			Harness.expect(
				UnlittiusConfig.movement.homeRadius > UnlittiusConfig.encounter.daisRadius,
				"his leash must reach past his own dais or he cannot move at all"
			)
			Harness.expect(
				UnlittiusConfig.movement.homeRadius < ringRadius,
				"and it must stop short of the candle ring: he holds the middle, the party holds the ring"
			)
		end),

		Harness.test("both boss floors are buildable: reciprocal doorways and valid indices", function()
			-- THE "DOES IT ACTUALLY SPAWN" TEST, and it covers BOTH bosses because they go through the
			-- same builder. A hand-authored plan gets none of the planner's validation: nothing checks
			-- that a doorway on one room has a matching opening on its neighbour, that a room index
			-- points at a room that exists, or that two rooms do not sit on the same cell. Every one of
			-- those produces a floor that carves without erroring and is then broken to walk — a doorway
			-- into solid rock, a brazier in a room nobody can reach, a descent that cannot be found.
			local opposite = { N = "S", S = "N", E = "W", W = "E" }
			local step = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }

			local function auditPlan(label: string, plan: any)
				local byCell: { [string]: number } = {}
				for index, room in plan.rooms do
					local key = room.gridX .. ":" .. room.gridZ
					Harness.expect(
						byCell[key] == nil,
						string.format("%s rooms %d and %s share cell %s", label, index, tostring(byCell[key]), key)
					)
					byCell[key] = index
					Harness.expect(room.ceilingHeight > 0, label .. " room " .. index .. " has no ceiling")
					Harness.expect(room.footprint ~= nil, label .. " room " .. index .. " has no footprint")
				end

				-- EVERY DOORWAY MUST OPEN ONTO A ROOM THAT OPENS BACK.
				local connections = 0
				for index, room in plan.rooms do
					for _, direction in room.doorways do
						local delta = step[direction]
						Harness.expect(delta ~= nil, label .. " has an unknown doorway direction " .. direction)
						local neighbourKey = (room.gridX + delta[1]) .. ":" .. (room.gridZ + delta[2])
						local neighbourIndex = byCell[neighbourKey]
						Harness.expect(
							neighbourIndex ~= nil,
							string.format(
								"%s room %d has a %s doorway into solid rock (no room at %s)",
								label,
								index,
								direction,
								neighbourKey
							)
						)
						local neighbour = plan.rooms[neighbourIndex]
						local reciprocal = false
						for _, back in neighbour.doorways do
							if back == opposite[direction] then
								reciprocal = true
							end
						end
						Harness.expect(
							reciprocal,
							string.format(
								"%s room %d opens %s onto room %d, which does not open back",
								label,
								index,
								direction,
								neighbourIndex
							)
						)
						connections += 1
					end
				end
				-- Every connection was counted from both ends, so the total must be even and the floor
				-- must actually be connected rather than a pile of sealed rooms.
				Harness.expect(connections % 2 == 0, label .. " has an odd number of doorway ends")
				Harness.expect(connections / 2 >= #plan.rooms - 1, label .. " is not connected enough to walk")

				-- EVERY NAMED ROOM INDEX POINTS AT A REAL ROOM.
				for name, index in
					{
						entry = plan.entryRoomIndex,
						basin = plan.basinRoomIndex,
						brazier = plan.brazierRoomIndex,
					}
				do
					Harness.expect(
						index ~= nil and plan.rooms[index] ~= nil,
						string.format("%s %s room index %s does not exist", label, name, tostring(index))
					)
				end

				-- REACHABLE FROM THE ENTRY. Walked as a graph rather than assumed from the shape.
				local reached: { [number]: boolean } = { [plan.entryRoomIndex] = true }
				local queue = { plan.entryRoomIndex }
				local cursor = 1
				while cursor <= #queue do
					local index = queue[cursor]
					cursor += 1
					local room = plan.rooms[index]
					for _, direction in room.doorways do
						local delta = step[direction]
						local neighbourIndex = byCell[(room.gridX + delta[1]) .. ":" .. (room.gridZ + delta[2])]
						if neighbourIndex ~= nil and not reached[neighbourIndex] then
							reached[neighbourIndex] = true
							table.insert(queue, neighbourIndex)
						end
					end
				end
				for index in plan.rooms do
					Harness.expect(
						reached[index] == true,
						label .. " room " .. index .. " is unreachable from the entry"
					)
				end

				-- Every placement points at a room that exists.
				for _, list in { plan.lootSpawns, plan.dripstones, plan.deposits } do
					for _, placement in list do
						Harness.expect(
							plan.rooms[placement.roomIndex] ~= nil,
							label
								.. " places content in room "
								.. tostring(placement.roomIndex)
								.. ", which does not exist"
						)
					end
				end
				Harness.expect(plan.bossEncounter == true, label .. " must be flagged as a boss floor")
			end

			auditPlan("the Grub Queen's floor", BossFloorPlan.plan(10, 3, "STONE", Vector3.zero))
			auditPlan("Unlittius' floor", UnlittiusFloorPlan.plan(20, 4, "STONE", Vector3.zero))
		end),

		Harness.test("the two boss floors are different shapes, not the same skeleton twice", function()
			-- A player meets these two five floors apart on the rotation. If both are a centre with four
			-- arms, the second one reads as the first one redressed — which is the specific mistake this
			-- test exists to prevent coming back.
			local hers = BossFloorPlan.plan(10, 1, "STONE", Vector3.zero)
			local his = UnlittiusFloorPlan.plan(20, 1, "STONE", Vector3.zero)

			local function doorwayCounts(plan: any): { number }
				local counts = {}
				for _, room in plan.rooms do
					table.insert(counts, #room.doorways)
				end
				table.sort(counts)
				return counts
			end
			local hersCounts = doorwayCounts(hers)
			local hisCounts = doorwayCounts(his)
			-- HERS IS A HUB: one room with four doorways and four dead ends hanging off it.
			Harness.equal(hersCounts[#hersCounts], 4, "her floor is a hub with a four-doorway centre")
			-- HIS IS A PROCESSION: no room has four doorways, and two rooms are through-routes rather
			-- than dead ends, so the party walks the arc instead of returning to a hub every time.
			Harness.expect(hisCounts[#hisCounts] < 4, "his floor must not be another four-arm hub")
			local hisThroughRooms = 0
			for _, count in hisCounts do
				if count >= 2 then
					hisThroughRooms += 1
				end
			end
			Harness.expect(hisThroughRooms >= 3, "his floor needs a route with rooms you pass through")

			-- And their entries do not sit in the same relationship to the boss chamber: hers opens
			-- straight onto the centre, his is a corner you walk up from.
			local herEntry = hers.rooms[hers.entryRoomIndex]
			local herCentre = hers.rooms[BossFloorPlan.CENTER_ROOM]
			local hisEntry = his.rooms[his.entryRoomIndex]
			local hisShrine = his.rooms[UnlittiusFloorPlan.CENTER_ROOM]
			local herGap = math.abs(herEntry.gridX - herCentre.gridX) + math.abs(herEntry.gridZ - herCentre.gridZ)
			local hisGap = math.abs(hisEntry.gridX - hisShrine.gridX) + math.abs(hisEntry.gridZ - hisShrine.gridZ)
			Harness.equal(herGap, 1, "her entry opens directly onto her chamber")
			Harness.expect(hisGap > 1, "his entry must be a walk away from the shrine, not a door onto it")
		end),

		Harness.test("his floor is a ring with the way down behind him and no dynamite on it", function()
			local plan = UnlittiusFloorPlan.plan(20, 3, "STONE", Vector3.zero)
			Harness.equal(plan.globalDepth, 20)
			Harness.equal(plan.depth, 3, "the local floor index is preserved")
			Harness.expect(plan.bossEncounter == true, "downstream systems key their doorway minimums off this")
			Harness.equal(#plan.rooms, 5, "five rooms in a plus")
			Harness.equal(plan.entryRoomIndex, UnlittiusFloorPlan.ENTRY_ROOM)
			Harness.equal(plan.basinRoomIndex, UnlittiusFloorPlan.DESCENT_ROOM)
			-- THE BRAZIER STAYS IN THE ENTRY. Banishing him is required to go DOWN, never to leave the
			-- cave — a party out of light must be able to see the way out and choose it.
			Harness.equal(plan.brazierRoomIndex, UnlittiusFloorPlan.ENTRY_ROOM, "extraction must remain possible")
			-- NO ROSTER. His summons are the floor's creatures.
			Harness.equal(#plan.threatSpawns, 0, "no wandering roster in a chamber already at capacity")
			Harness.equal(#plan.enemySpawns, 0)
			-- NO AUTHORED DRIPSTONE IN THE CHAMBER: he pulls the ceiling down himself with a marked
			-- telegraph, and a room that also dropped rock unprompted would teach players to distrust it.
			for _, dripstone in plan.dripstones do
				Harness.expect(
					dripstone.roomIndex ~= UnlittiusFloorPlan.CENTER_ROOM,
					"the chamber's ceiling belongs to his attack alone"
				)
			end
			Harness.expect(#plan.dripstones > 0, "the galleries still carry real falling stone")
			-- WAX ON BOTH FLANKS AND NOT A STICK OF DYNAMITE: nothing can hurt him, so a dynamite wing
			-- would be a room full of an answer to a question this fight never asks.
			local wax, west, east = 0, 0, 0
			for _, loot in plan.lootSpawns do
				Harness.expect(loot.lootId == "LifeWax", "his floor supplies light and nothing else")
				wax += 1
				if loot.roomIndex == UnlittiusFloorPlan.WEST_ROOM then
					west += 1
				elseif loot.roomIndex == UnlittiusFloorPlan.EAST_ROOM then
					east += 1
				end
			end
			Harness.expect(wax >= 4, "the fight drains wax and has to be able to be topped up")
			Harness.expect(west > 0 and east > 0, "both galleries carry supply, so the lap runs either way")
			Harness.expect(#plan.deposits > 0, "one sealed cache: the only reason to stand still")
			Harness.expect(
				UnlittiusFloorPlan.chamberRadius() > UnlittiusConfig.encounter.candleRingRadius,
				"the chamber has to be wider than the candle ring it holds"
			)
			-- Tall enough to hold him, hover him, and swallow him.
			Harness.expect(
				UnlittiusFloorPlan.CENTER_CEILING > UnlittiusConfig.body.hoverHeight + UnlittiusConfig.body.targetHeight,
				"the chamber must clear his hood before the banish even starts"
			)
		end),
	},
}

return suite

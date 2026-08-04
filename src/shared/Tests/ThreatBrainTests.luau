--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local ThreatBrain = require(script.Parent.Parent.Logic.ThreatBrain)
local LightConfig = require(script.Parent.Parent.Config.Light)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)

local function definitionFor(category: Types.ThreatCategory): Types.ThreatDef
	local selected: Types.ThreatDef? = nil
	for _, def in ThreatsConfig.definitions do
		-- These tests exercise the generic category behavior. Dictionary order is undefined, and
		-- selecting the category's territorial ambush row would test that profile instead.
		-- THE PLAIN ROSTER ROW for this category: no territory, no interception, no roof-strike. These
		-- tests are about the shared brain, so they must not silently start running against whichever
		-- specialised creature happens to sort first — adding the Calver alone would otherwise have
		-- swapped every dark-hunter assertion onto a row that never approaches anybody.
		if
			def.category == category
			and def.ambush == nil
			and def.ceilingStrike == nil
			and def.intercept == nil
			and (selected == nil or def.id < selected.id)
		then
			selected = def
		end
	end
	if selected ~= nil then
		return selected
	end
	error("missing threat definition for " .. category)
end

local function stateFor(def: Types.ThreatDef): Types.ThreatState
	return {
		id = def.id,
		category = def.category,
		position = Vector3.zero,
		homePosition = Vector3.zero,
		mode = "Wander",
		targetPosition = nil,
		targetPlayerId = nil,
		nextThinkAt = 0,
		retreatUntil = 0,
		investigateUntil = 0,
		investigateLoudness = 0,
		interceptUntil = 0,
		interceptPosition = nil,
		strikeReadyAt = 0,
	}
end

-- The lowest-id row that actually has ears, chosen the same deterministic way as definitionFor so
-- these tests never depend on dictionary order.
local function hearingDefinition(): Types.ThreatDef
	local selected: Types.ThreatDef? = nil
	for _, def in ThreatsConfig.definitions do
		if
			def.hearing ~= nil
			and def.ambush == nil
			and def.ceilingStrike == nil
			and def.intercept == nil
			and (selected == nil or def.id < selected.id)
		then
			selected = def
		end
	end
	if selected ~= nil then
		return selected
	end
	error("no threat definition has a hearing profile")
end

-- A noise at `position` guaranteed to clear `profile`'s curiosity threshold on its own, so a test
-- about the DECISION never quietly becomes a test about the tuning. Loudness is set from the
-- threshold itself rather than from a Config row for the same reason.
local function loudEnough(position: Vector3, profile: Types.HearingProfile, now: number): { Types.NoiseEvent }
	return {
		{
			kind = "TestNoise",
			position = position,
			loudness = (profile.curiosityThreshold / math.max(profile.sensitivity, 0.001)) * 4,
			radius = profile.hearingRadius * 4,
			decaySeconds = 10,
			createdAt = now,
			ownerId = nil,
		},
	}
end

local function light(
	position: Vector3,
	intensity: number,
	range: number,
	attractsDrawn: boolean,
	ownerId: number?
): Types.LightSource
	return {
		kind = "Flame",
		position = position,
		intensity = intensity,
		range = range,
		attractsDrawn = attractsDrawn,
		repelsDarkHunters = true,
		forcesDarkHunterRetreat = false,
		ownerId = ownerId,
	}
end

local function flare(position: Vector3, intensity: number, range: number, ownerId: number?): Types.LightSource
	local source = light(position, intensity, range, true, ownerId)
	source.kind = "Flare"
	source.forcesDarkHunterRetreat = true
	return source
end

local suite: Harness.Suite = {
	name = "ThreatBrain",
	tests = {
		-- The light field's `attractsDrawn` filter, checked directly. No item in the shipped pool
		-- produces a cold source any more, but the filter is the mechanism a future one would use and
		-- the Drawn must keep honouring it.
		Harness.test("drawn seek an eligible light source and ignore one they cannot perceive", function()
			local def = definitionFor("Drawn")
			local state = stateFor(def)
			local cold = light(Vector3.new(1, 0, 0), 100, def.detectionRadius, false, 10)
			local warm = light(Vector3.new(2, 4, 0), 1, def.detectionRadius, true, 20)
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = { cold, warm },
				trail = {},
				noises = {},
				now = 5,
				rng = Random.new(1),
			})

			Harness.equal(result.mode, "Seek")
			Harness.equal(result.targetPlayerId, warm.ownerId)
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(warm.position.X, 0, warm.position.Z))
			Harness.near(result.nextThinkAt, 5 + ThreatsConfig.behavior.repathIntervalSeconds)
		end),

		Harness.test("dark-hunters flee when Flare crosses the repel threshold", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local sensitivity = math.abs(def.lightResponse)
			local intensity = ThreatsConfig.behavior.repelLightThreshold / sensitivity + 1
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = { flare(state.position, intensity, def.detectionRadius, 1) },
				trail = {},
				noises = {},
				now = 0,
				rng = Random.new(2),
			})

			Harness.equal(result.mode, "Flee")
			Harness.vectorNear(result.targetPosition :: Vector3, state.position + Vector3.xAxis * def.detectionRadius)
			Harness.isNil(result.targetPlayerId)
			Harness.near(
				result.retreatUntil,
				def.detectionRadius / def.speed + ThreatsConfig.behavior.darkHunterBlindSeconds
			)
		end),

		Harness.test("ordinary maximum light affects hunters but never forces retreat", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = { light(state.position, 100, def.detectionRadius, true, 1) },
				trail = {},
				noises = {},
				now = 0,
				rng = Random.new(14),
			})

			Harness.expect(result.mode ~= "Flee", "the brightness dial must not replace Flare counterplay")
		end),

		Harness.test("Flare-blind retreat persists after the source moves away", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local sensitivity = math.abs(def.lightResponse)
			local first = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = {
					flare(
						state.position,
						ThreatsConfig.behavior.repelLightThreshold / sensitivity + 1,
						def.detectionRadius,
						1
					),
				},
				trail = {},
				noises = {},
				now = 10,
				rng = Random.new(12),
			})
			local dimPlayer: ThreatBrain.PlayerSnapshot = {
				playerId = 1,
				position = Vector3.new(2, 0, 0),
				lightLevel = 0,
				repelsAmbusher = false,
				targetable = true,
			}
			local stillRetreating = ThreatBrain.think({
				def = def,
				state = first,
				players = { dimPlayer },
				sources = {},
				trail = {},
				noises = {},
				now = 11,
				rng = Random.new(12),
			})

			Harness.equal(stillRetreating.mode, "Flee")
			Harness.isNil(stillRetreating.targetPlayerId)
			Harness.near(stillRetreating.retreatUntil, first.retreatUntil)

			local estimatedArrival = 10 + def.detectionRadius / def.speed
			local stillBlinded = ThreatBrain.think({
				def = def,
				state = first,
				players = { dimPlayer },
				sources = {},
				trail = {},
				noises = {},
				now = estimatedArrival + ThreatsConfig.behavior.darkHunterBlindSeconds - 0.01,
				rng = Random.new(12),
			})
			Harness.equal(stillBlinded.mode, "Flee")

			local blindnessEnded = ThreatBrain.think({
				def = def,
				state = first,
				players = { dimPlayer },
				sources = {},
				trail = {},
				noises = {},
				now = first.retreatUntil,
				rng = Random.new(12),
			})
			Harness.equal(blindnessEnded.mode, "Seek")
			Harness.equal(blindnessEnded.targetPlayerId, dimPlayer.playerId)
		end),

		Harness.test("dark-hunters hold a configured gap from medium-light players", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local sensitivity = math.abs(def.lightResponse)
			local player: ThreatBrain.PlayerSnapshot = {
				playerId = 8,
				position = Vector3.new(5, 4, 0),
				lookDirection = Vector3.new(-1, 0, 0),
				lightLevel = (ThreatsConfig.behavior.huntLightThreshold + ThreatsConfig.behavior.repelLightThreshold)
					/ 2
					/ sensitivity,
				repelsAmbusher = false,
				targetable = true,
			}
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = { player },
				sources = {},
				trail = {},
				noises = {},
				now = 0,
				rng = Random.new(13),
			})

			Harness.equal(result.mode, "Stalk")
			Harness.equal(result.targetPlayerId, player.playerId)
			Harness.vectorNear(
				result.targetPosition :: Vector3,
				Vector3.new(5 - ThreatsConfig.behavior.darkHunterKeepDistance, 0, 0)
			)
		end),

		Harness.test("the baseline crawler attacks at the minimum ordinary dial light", function()
			local def = ThreatsConfig.definitions.DarkCrawler
			local state = stateFor(def)
			local player: ThreatBrain.PlayerSnapshot = {
				playerId = 18,
				position = Vector3.new(5, 0, 0),
				lookDirection = Vector3.new(-1, 0, 0),
				lightLevel = LightConfig.minIntensity,
				repelsAmbusher = false,
				targetable = true,
			}
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = { player },
				sources = {},
				trail = {},
				noises = {},
				now = 0,
				rng = Random.new(31),
			})

			Harness.equal(result.mode, "Seek", "minimum dial light must no longer be safe without Cup")
			Harness.equal(result.targetPlayerId, player.playerId)
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(5, 0, 0))
		end),

		Harness.test("an unwatched crawler sneaks through the middle light band", function()
			local def = ThreatsConfig.definitions.DarkCrawler
			local state = stateFor(def)
			local player: ThreatBrain.PlayerSnapshot = {
				playerId = 19,
				position = Vector3.new(5, 0, 0),
				-- Hunter is behind the player at -X; +X faces directly away from it.
				lookDirection = Vector3.new(1, 0, 0),
				lightLevel = (
					ThreatsConfig.behavior.huntLightThreshold
					+ ThreatsConfig.behavior.darkHunterSneakLightThreshold
				) / 2,
				repelsAmbusher = false,
				targetable = true,
			}
			local sneaking = ThreatBrain.think({
				def = def,
				state = state,
				players = { player },
				sources = {},
				trail = {},
				noises = {},
				now = 0,
				rng = Random.new(32),
			})

			Harness.equal(sneaking.mode, "Stalk")
			Harness.vectorNear(
				sneaking.targetPosition :: Vector3,
				Vector3.new(5, 0, 0),
				1e-6,
				"an unwatched crawler should close all the way to contact at stalk speed"
			)

			player.lookDirection = Vector3.new(-1, 0, 0)
			local watched = ThreatBrain.think({
				def = def,
				state = state,
				players = { player },
				sources = {},
				trail = {},
				noises = {},
				now = 1,
				rng = Random.new(32),
			})
			Harness.equal(watched.mode, "Stalk")
			Harness.vectorNear(
				watched.targetPosition :: Vector3,
				Vector3.new(5 - ThreatsConfig.behavior.darkHunterKeepDistance, 0, 0),
				1e-6,
				"turning toward it should restore the keep-distance ring"
			)
		end),

		Harness.test("dark-hunters choose the nearest targetable dim player", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local players: { ThreatBrain.PlayerSnapshot } = {
				{
					playerId = 1,
					position = Vector3.new(2, 5, 0),
					lightLevel = 0,
					repelsAmbusher = false,
					targetable = false,
				},
				{
					playerId = 2,
					position = Vector3.new(6, 5, 0),
					lightLevel = 0,
					repelsAmbusher = false,
					targetable = true,
				},
				{
					playerId = 3,
					position = Vector3.new(4, 5, 0),
					lightLevel = 0,
					repelsAmbusher = false,
					targetable = true,
				},
			}
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = players,
				sources = {},
				trail = {},
				noises = {},
				now = 0,
				rng = Random.new(3),
			})

			Harness.equal(result.mode, "Seek")
			Harness.equal(result.targetPlayerId, 3)
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(4, 0, 0))
		end),

		Harness.test("dark-hunters follow the freshest trail point in range when prey is absent", function()
			local def = definitionFor("DarkHunter")
			local state = stateFor(def)
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = {},
				trail = {
					{ position = Vector3.new(2, 8, 0), ownerId = 1, createdAt = 10 },
					{ position = Vector3.new(3, 8, 0), ownerId = 1, createdAt = 20 },
					{
						position = Vector3.new(def.detectionRadius + 1, 0, 0),
						ownerId = 1,
						createdAt = 30,
					},
				},
				noises = {},
				now = 0,
				rng = Random.new(4),
			})

			Harness.equal(result.mode, "Seek")
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(3, 0, 0))
			Harness.isNil(result.targetPlayerId)
		end),

		Harness.test("step uses mode speed and never overshoots a target", function()
			local def = definitionFor("Drawn")
			local state = stateFor(def)
			state.mode = "Seek"
			state.targetPosition = Vector3.new(1, 0, 0)
			Harness.vectorNear(ThreatBrain.step(state, def, 10), state.targetPosition)

			state.mode = "Wander"
			state.targetPosition = Vector3.new(100, 0, 0)
			local dt = 0.25
			local stepped = ThreatBrain.step(state, def, dt)
			Harness.near(
				(stepped - state.position).Magnitude,
				def.speed * ThreatsConfig.behavior.wanderSpeedFraction * dt
			)

			state.mode = "Stalk"
			state.targetPosition = Vector3.new(100, 0, 0)
			stepped = ThreatBrain.step(state, def, dt)
			Harness.near(
				(stepped - state.position).Magnitude,
				def.speed * ThreatsConfig.behavior.stalkSpeedFraction * dt
			)

			state.targetPosition = nil
			Harness.vectorNear(ThreatBrain.step(state, def, dt), state.position)
		end),

		Harness.test("ambushers engage exposed prey and retreat from a repelling light or teammate", function()
			local def = ThreatsConfig.definitions.VoidFly
			local state = stateFor(def)
			local victim: ThreatBrain.PlayerSnapshot = {
				playerId = 11,
				position = Vector3.new(3, 0, 0),
				lightLevel = 0.2,
				repelsAmbusher = false,
				targetable = true,
			}
			local engaged = ThreatBrain.think({
				def = def,
				state = state,
				players = { victim },
				sources = {},
				trail = {},
				noises = {},
				now = 10,
				rng = Random.new(9),
			})
			Harness.equal(engaged.mode, "Seek")
			Harness.equal(engaged.targetPlayerId, victim.playerId)

			victim.repelsAmbusher = true
			local repelled = ThreatBrain.think({
				def = def,
				state = engaged,
				players = { victim },
				sources = {},
				trail = {},
				noises = {},
				now = 11,
				rng = Random.new(9),
			})
			Harness.equal(repelled.mode, "Flee")
			Harness.isNil(repelled.targetPlayerId)
			Harness.expect(repelled.retreatUntil > 11)

			victim.repelsAmbusher = false
			local teammate: ThreatBrain.PlayerSnapshot = {
				playerId = 12,
				position = victim.position + Vector3.new(2, 0, 0),
				lightLevel = 0.2,
				repelsAmbusher = false,
				targetable = true,
			}
			engaged.retreatUntil = 0
			local grouped = ThreatBrain.think({
				def = def,
				state = engaged,
				players = { victim, teammate },
				sources = {},
				trail = {},
				noises = {},
				now = 12,
				rng = Random.new(9),
			})
			Harness.equal(grouped.mode, "Flee")
		end),

		Harness.test("a heard noise pulls a hunter to the PLACE, never to the player", function()
			local def = hearingDefinition()
			local hearing = def.hearing :: Types.HearingProfile
			local state = stateFor(def)
			local seam = Vector3.new(12, 0, 0)
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = {},
				trail = {},
				noises = loudEnough(seam, hearing, 0),
				now = 0,
				rng = Random.new(21),
			})

			Harness.equal(result.mode, "Investigate")
			Harness.vectorNear(result.targetPosition :: Vector3, Vector3.new(seam.X, 0, seam.Z), 1e-3)
			Harness.isNil(
				result.targetPlayerId,
				"hearing must never acquire a player — being heard costs you a location, not your life"
			)
			Harness.expect(result.investigateUntil > 0, "committing to a noise must record its own deadline")
		end),

		Harness.test("real prey interrupts curiosity rather than queueing behind it", function()
			local def = hearingDefinition()
			local hearing = def.hearing :: Types.HearingProfile
			local state = stateFor(def)
			local noises = loudEnough(Vector3.new(12, 0, 0), hearing, 0)
			local dim: ThreatBrain.PlayerSnapshot = {
				playerId = 7,
				position = Vector3.new(-4, 0, 0),
				lightLevel = 0,
				repelsAmbusher = false,
				targetable = true,
			}
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = { dim },
				sources = {},
				trail = {},
				noises = noises,
				now = 0,
				rng = Random.new(22),
			})

			Harness.equal(result.mode, "Seek", "a sensed candle must outrank a sound")
			Harness.equal(result.targetPlayerId, dim.playerId)
			Harness.equal(result.investigateUntil, 0, "any other decision must forget the noise entirely")
			Harness.equal(result.investigateLoudness, 0)
		end),

		Harness.test("a noise outranks a cold drip trail", function()
			-- This ordering is the entire reason mining is dangerous: a working pick draws a hunter
			-- to the seam rather than along the path the player walked in on.
			local def = hearingDefinition()
			local hearing = def.hearing :: Types.HearingProfile
			local state = stateFor(def)
			local result = ThreatBrain.think({
				def = def,
				state = state,
				players = {},
				sources = {},
				trail = { { position = Vector3.new(0, 0, 5), ownerId = 1, createdAt = 0 } },
				noises = loudEnough(Vector3.new(12, 0, 0), hearing, 0),
				now = 0,
				rng = Random.new(23),
			})
			Harness.equal(result.mode, "Investigate")
		end),

		Harness.test("curiosity lapses on its own instead of becoming a permanent hunt", function()
			local def = hearingDefinition()
			local committed = stateFor(def)
			committed.mode = "Investigate"
			committed.targetPosition = Vector3.new(40, 0, 0)
			committed.investigateUntil = 5
			committed.investigateLoudness = 99

			-- Still committed, cave silent: it keeps walking to where the sound was.
			local walking = ThreatBrain.think({
				def = def,
				state = committed,
				players = {},
				sources = {},
				trail = {},
				noises = {},
				now = 4,
				rng = Random.new(24),
			})
			Harness.equal(walking.mode, "Investigate")

			-- Deadline passed: it gives up and drifts. Nothing keeps it there.
			local lapsed = ThreatBrain.think({
				def = def,
				state = committed,
				players = {},
				sources = {},
				trail = {},
				noises = {},
				now = 6,
				rng = Random.new(24),
			})
			Harness.equal(lapsed.mode, "Wander")
			Harness.equal(lapsed.investigateUntil, 0)
		end),

		Harness.test("deaf rows ignore the sound field entirely", function()
			-- Every Drawn row is deaf, so a noisy action must not pull both families at once.
			local def = definitionFor("Drawn")
			Harness.isNil(def.hearing, "this test is meaningless if the chosen Drawn row can hear")
			local hearing = (hearingDefinition().hearing :: any) :: Types.HearingProfile
			local result = ThreatBrain.think({
				def = def,
				state = stateFor(def),
				players = {},
				sources = {},
				trail = {},
				noises = loudEnough(Vector3.new(8, 0, 0), hearing, 0),
				now = 0,
				rng = Random.new(25),
			})
			Harness.expect(result.mode ~= "Investigate", "a deaf row must never investigate")
		end),

		Harness.test("investigating is a walk, not a charge", function()
			local def = hearingDefinition()
			local hearing = def.hearing :: Types.HearingProfile
			Harness.expect(
				hearing.investigateSpeedFraction < 1,
				"a lured threat must stay visibly slower than a hunt, so abandoning the seam stays possible"
			)
			local state = stateFor(def)
			state.mode = "Investigate"
			state.targetPosition = Vector3.new(1000, 0, 0)
			local stepped = ThreatBrain.step(state, def, 1)
			Harness.near(
				stepped.X,
				def.speed * hearing.investigateSpeedFraction,
				1e-6,
				"investigate speed must come from the row's own profile"
			)
		end),

		Harness.test("staged contact requires every configured hit before snuffing", function()
			local hits = 0
			for _ = 1, 3 do
				local shouldSnuff: boolean
				hits, shouldSnuff = ThreatBrain.advanceContactHits(hits, 4)
				Harness.equal(shouldSnuff, false)
			end
			local finalHits, shouldSnuff = ThreatBrain.advanceContactHits(hits, 4)
			Harness.equal(finalHits, 4)
			Harness.equal(shouldSnuff, true)
		end),

		Harness.test("sustained contact snuffs only after the clock runs, and a real break resets it", function()
			local profile: Types.SustainedContactProfile = { secondsToSnuff = 3, graceSeconds = 0.75 }
			-- Held: contact seen every tick, so the clock carries and reaches the threshold.
			local elapsed, snuffed = 0, false
			local now = 0
			for _ = 1, 5 do
				elapsed, snuffed = ThreatBrain.advanceContactSeconds(elapsed, now, now + 0.5, 0.5, profile)
				now += 0.5
			end
			Harness.equal(snuffed, false, "2.5 s of contact must not reach a 3 s threshold")
			elapsed, snuffed = ThreatBrain.advanceContactSeconds(elapsed, now, now + 0.5, 0.5, profile)
			Harness.equal(snuffed, true, "the sixth half-second crosses it")

			-- ESCAPED: a gap longer than the grace window starts from nothing, however long the player
			-- had already been held. This is the counterplay — walk, dim, decoy — actually paying off.
			local afterEscape, escapedSnuff = ThreatBrain.advanceContactSeconds(2.9, 0, 5, 0.5, profile)
			Harness.near(afterEscape, 0.5, 1e-6, "a real break must discard the accumulated time")
			Harness.equal(escapedSnuff, false)

			-- A LAPSE INSIDE THE GRACE WINDOW IS NOT AN ESCAPE. Contact is a radius test against a
			-- flying body, so the radius is crossed constantly while a moth sits on one player; if that
			-- reset the clock the mechanic could never fire against somebody standing still.
			local afterFlicker, flickerSnuff = ThreatBrain.advanceContactSeconds(2.9, 0, 0.5, 0.5, profile)
			Harness.near(afterFlicker, 3.4, 1e-6, "a wingbeat's worth of separation must carry the clock")
			Harness.equal(flickerSnuff, true)

			-- A row whose clock is off at this depth accumulates and simply never resolves, so no
			-- caller needs to special-case a shallow floor.
			local shallow: Types.SustainedContactProfile = { secondsToSnuff = 0, graceSeconds = 0.75 }
			local _, shallowSnuff = ThreatBrain.advanceContactSeconds(999, 0, 0.5, 0.5, shallow)
			Harness.equal(shallowSnuff, false, "secondsToSnuff = 0 must mean it cannot happen here")
		end),

		Harness.test("an intercepting row heads where a player is going, and commits to it", function()
			-- THE FAIRNESS GUARANTEE, tested directly: once a prediction is made it is HONOURED for the
			-- authored window and cannot be re-aimed. That is what makes doubling back beat this
			-- creature, and a difficulty curve is explicitly not allowed to erode it.
			local def = ThreatsConfig.definitions.Knotwalker
			Harness.expect(def ~= nil and def.intercept ~= nil, "test fixture requires an intercepting row")
			local profile = def.intercept :: Types.InterceptProfile

			local state = stateFor(def)
			state.position = Vector3.new(0, 0, 0)
			local walkingEast = {
				playerId = 1,
				position = Vector3.new(10, 0, 0),
				lookDirection = Vector3.new(1, 0, 0),
				lightLevel = 0,
				repelsAmbusher = false,
				targetable = true,
			}

			local first = ThreatBrain.think({
				def = def,
				state = state,
				players = { walkingEast },
				sources = {},
				trail = {},
				noises = {},
				now = 100,
				rng = Random.new(1),
			})
			local predicted = first.targetPosition
			Harness.expect(predicted ~= nil, "an intercepting row must produce a target")
			-- It aims PAST the player along their heading, not at them.
			Harness.expect(
				(predicted :: Vector3).X > walkingEast.position.X,
				"interception must aim ahead of the player, not at them"
			)
			Harness.expect(first.interceptUntil > 100, "a prediction must record its commitment window")

			-- The player now doubles back. The creature must keep walking to the ground it already
			-- committed to rather than re-aiming — this is the branch a player's counterplay rests on.
			local doubledBack = {
				playerId = 1,
				position = Vector3.new(12, 0, 0),
				lookDirection = Vector3.new(-1, 0, 0),
				lightLevel = 0,
				repelsAmbusher = false,
				targetable = true,
			}
			local second = ThreatBrain.think({
				def = def,
				state = first,
				players = { doubledBack },
				sources = {},
				trail = {},
				noises = {},
				now = 100 + profile.commitmentSeconds * 0.5,
				rng = Random.new(1),
			})
			Harness.equal(second.targetPosition, predicted, "a live commitment must not be re-aimed")

			-- Past the window it may predict again, and now follows the new heading.
			local third = ThreatBrain.think({
				def = def,
				state = second,
				players = { doubledBack },
				sources = {},
				trail = {},
				noises = {},
				now = 100 + profile.commitmentSeconds + 1,
				rng = Random.new(1),
			})
			Harness.expect(
				(third.targetPosition :: Vector3).X < (predicted :: Vector3).X,
				"an expired commitment must follow the player's new heading"
			)
		end),

		Harness.test("an intercepting row without a heading still hunts normally", function()
			-- A player milling in a room produces no prediction at all. The creature must fall back to
			-- an ordinary chase rather than going inert, or standing still would defeat it completely.
			local def = ThreatsConfig.definitions.Knotwalker
			local state = stateFor(def)
			state.position = Vector3.zero
			local next_ = ThreatBrain.think({
				def = def,
				state = state,
				players = {
					{
						playerId = 1,
						position = Vector3.new(9, 0, 0),
						lookDirection = nil,
						lightLevel = 0,
						repelsAmbusher = false,
						targetable = true,
					},
				},
				sources = {},
				trail = {},
				noises = {},
				now = 5,
				rng = Random.new(1),
			})
			Harness.equal(next_.mode, "Seek", "it must still commit to the player")
			Harness.equal(next_.targetPlayerId, 1)
			Harness.near((next_.targetPosition :: Vector3).X, 9, 1e-6, "with no heading it walks at the player")
		end),

		Harness.test("a ceiling striker watches from its patch and never approaches", function()
			-- THE WHOLE CREATURE, in one assertion: it takes a target and its target position stays on
			-- its own territory. "Seek" here means "watching somebody below", never "closing".
			local def = ThreatsConfig.definitions.Calver
			Harness.expect(def ~= nil and def.ceilingStrike ~= nil, "test fixture requires a roof-bound row")
			local state = stateFor(def)
			state.position = Vector3.new(0, 0, 0)
			state.homePosition = Vector3.new(0, 0, 0)

			local below = {
				playerId = 7,
				position = Vector3.new(4, 0, 0),
				lookDirection = Vector3.new(0, 0, 1),
				lightLevel = 0,
				repelsAmbusher = false,
				targetable = true,
			}
			local next_ = ThreatBrain.think({
				def = def,
				state = state,
				players = { below },
				sources = {},
				trail = {},
				noises = {},
				now = 10,
				rng = Random.new(1),
			})
			Harness.equal(next_.mode, "Seek", "a candle beneath it is something it can act on")
			Harness.equal(next_.targetPlayerId, 7)
			Harness.equal(next_.targetPosition, state.homePosition, "a striker must never move toward a player")

			-- A flare drives it off its patch like any other dark-hunter: the counter to a creature that
			-- weaponises the ceiling is the same tool that answers everything else in the dark.
			local flared = ThreatBrain.think({
				def = def,
				state = state,
				players = {
					{
						playerId = 7,
						position = Vector3.new(4, 0, 0),
						lookDirection = Vector3.new(0, 0, 1),
						lightLevel = 1,
						repelsAmbusher = true,
						targetable = true,
					},
				},
				sources = {},
				trail = {},
				noises = {},
				now = 10,
				rng = Random.new(1),
			})
			Harness.equal(flared.mode, "Flee", "panic light must drive a striker off its patch")
			Harness.expect(flared.retreatUntil > 10, "being driven off must hold for a real window")
		end),
	},
}

return suite

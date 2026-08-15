--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local SoundField = require(script.Parent.Parent.Logic.SoundField)
local SoundConfig = require(script.Parent.Parent.Config.Sound)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local ThreatRules = require(script.Parent.Parent.Logic.ThreatRules)

local function noise(kind: string, position: Vector3, createdAt: number): Types.NoiseEvent
	local event = SoundField.eventFor(kind, position, createdAt, nil)
	assert(event ~= nil, "Config/Sound must define the emitter row " .. kind)
	return event
end

-- A crawler's ears are a function of the floor it stands on, so a test about hearing has to say WHICH
-- crawler. Floor 1 is the one the mining loop is balanced against and the one these thresholds are a
-- contract for; the deep profile is asserted separately below.
local function crawlerHearingAt(depth: number): Types.HearingProfile
	local def = ThreatRules.atDepth(ThreatsConfig.definitions.DarkCrawler, depth)
	return def.hearing :: Types.HearingProfile
end

local shallowHearing = crawlerHearingAt(1)

local suite: Harness.Suite = {
	name = "SoundField",
	tests = {
		Harness.test("a noise falls off with distance and dies at its radius", function()
			local event = noise("MineStrikeClean", Vector3.zero, 0)
			local atSource = SoundField.contributionOf(event, Vector3.zero, 0)
			Harness.near(atSource, event.loudness, 1e-6, "a fresh noise is full strength at its source")
			Harness.expect(
				SoundField.contributionOf(event, Vector3.new(event.radius / 2, 0, 0), 0) < atSource,
				"loudness must fall off with distance"
			)
			Harness.equal(
				SoundField.contributionOf(event, Vector3.new(event.radius, 0, 0), 0),
				0,
				"a noise must be silent at its own radius, not merely faint"
			)
			Harness.equal(SoundField.contributionOf(event, Vector3.new(event.radius * 3, 0, 0), 0), 0)
		end),

		Harness.test("a noise decays to nothing and then expires", function()
			local event = noise("MineStrikeClean", Vector3.zero, 0)
			Harness.equal(SoundField.isExpired(event, 0), false)
			Harness.near(SoundField.remainingFraction(event, event.decaySeconds / 2), 0.5, 1e-6)
			Harness.equal(
				SoundField.isExpired(event, event.decaySeconds),
				true,
				"a fully decayed noise must be droppable, or the field grows without bound"
			)
			Harness.equal(SoundField.contributionOf(event, Vector3.zero, event.decaySeconds), 0)
		end),

		Harness.test("ONE clean strike does not bring a shallow crawler; repeated strikes do", function()
			-- This is the whole "repeated hits lure them" design, and it is not special-cased
			-- anywhere: it is only what happens when decaying events are added together.
			local at = Vector3.new(6, 0, 0)
			local single = { noise("MineStrikeClean", Vector3.zero, 0) }
			Harness.isNil(
				SoundField.audibleFor(at, single, 0, shallowHearing),
				"a single clean swing must not be worth investigating"
			)

			local repeated = {
				noise("MineStrikeClean", Vector3.zero, 0),
				noise("MineStrikeClean", Vector3.zero, 0.5),
				noise("MineStrikeClean", Vector3.zero, 1),
			}
			local heard = SoundField.audibleFor(at, repeated, 1, shallowHearing)
			Harness.expect(heard ~= nil, "three overlapping strikes must cross the curiosity threshold")
		end),

		Harness.test("a fumble crosses the threshold faster than a clean strike", function()
			local at = Vector3.new(6, 0, 0)
			local cleanPair = {
				noise("MineStrikeClean", Vector3.zero, 0),
				noise("MineStrikeClean", Vector3.zero, 0.5),
			}
			local fumblePair = {
				noise("MineStrikeFumble", Vector3.zero, 0),
				noise("MineStrikeFumble", Vector3.zero, 0.5),
			}
			local cleanLoudness = SoundField.loudnessAt(at, cleanPair, 0.5)
			local fumbleLoudness = SoundField.loudnessAt(at, fumblePair, 0.5)
			Harness.expect(
				fumbleLoudness > cleanLoudness,
				"fumbling must be audibly worse than hitting the window, or accuracy buys nothing"
			)
		end),

		Harness.test("hearing radius gates before falloff — quiet and far is out of earshot", function()
			local deaf: Types.HearingProfile = {
				sensitivity = 10,
				curiosityThreshold = 0.01,
				-- Tiny ears: the noise is enormously loud but simply cannot be heard from here.
				hearingRadius = 2,
				investigateSeconds = 5,
				investigateSpeedFraction = 0.5,
			}
			local events = { noise("MineBreak", Vector3.new(20, 0, 0), 0) }
			Harness.isNil(SoundField.audibleFor(Vector3.zero, events, 0, deaf))
			-- The same listener with real ears hears it immediately.
			local keen: Types.HearingProfile = {
				sensitivity = 10,
				curiosityThreshold = 0.01,
				hearingRadius = 100,
				investigateSeconds = 5,
				investigateSpeedFraction = 0.5,
			}
			Harness.expect(SoundField.audibleFor(Vector3.zero, events, 0, keen) ~= nil)
		end),

		Harness.test("what is heard is a PLACE — the weighted centre of the noise", function()
			-- Two equally loud strikes either side: the listener is drawn between them, never to a
			-- player. Nothing in the field can express "where the player is now".
			local events = {
				noise("MineBreak", Vector3.new(-10, 0, 0), 0),
				noise("MineBreak", Vector3.new(10, 0, 0), 0),
			}
			local heard = SoundField.audibleFor(Vector3.new(0, 0, 30), events, 0, shallowHearing)
			Harness.expect(heard ~= nil, "two breaks nearby must be heard")
			Harness.vectorNear(
				(heard :: SoundField.Audible).position,
				Vector3.zero,
				1e-3,
				"equal noises either side must resolve to the point between them"
			)
		end),

		Harness.test("a deaf profile hears nothing however loud the cave gets", function()
			local silent: Types.HearingProfile = {
				sensitivity = 0,
				curiosityThreshold = 0,
				hearingRadius = 1000,
				investigateSeconds = 5,
				investigateSpeedFraction = 0.5,
			}
			local events = { noise("DripstoneImpact", Vector3.zero, 0) }
			Harness.isNil(
				SoundField.audibleFor(Vector3.zero, events, 0, silent),
				"zero sensitivity must be genuinely deaf, not merely quiet"
			)
		end),

		Harness.test("only dark-hunters have ears — the Drawn stay pure moth logic", function()
			-- If a Drawn row ever gains hearing, a noisy action would pull both families at once and
			-- the light/dark read that the entire threat design rests on would blur.
			for id, def in ThreatsConfig.definitions do
				if def.category == "Drawn" then
					Harness.isNil(def.hearing, id .. " is Drawn and must not hear")
				end
			end
			Harness.expect(
				ThreatsConfig.definitions.DarkCrawler.hearing ~= nil,
				"at least one dark-hunter must listen, or the sound field does nothing"
			)
		end),

		Harness.test("a crawler's ears open with depth, and the shallow contract still holds", function()
			-- The depth ramp used to be composition: three crawler rows with different ears and
			-- staggered spawn tables, so the deep floors drew the keen one more often. Now it is one
			-- row's own curve, and this is what that curve has to mean.
			local deep = crawlerHearingAt(10)
			Harness.expect(deep.sensitivity > shallowHearing.sensitivity, "a deep crawler must hear more keenly")
			Harness.expect(
				deep.curiosityThreshold < shallowHearing.curiosityThreshold,
				"a deep crawler must be quicker to come and look"
			)
			Harness.expect(deep.hearingRadius > shallowHearing.hearingRadius, "a deep crawler must hear further")

			-- THE SHALLOW CONTRACT IS THE ONE THAT MATTERS FOR TEACHING, and the ramp must not have
			-- quietly rewritten it: floor 1 is still the profile a first mining loop is safe against.
			local at = Vector3.new(6, 0, 0)
			local single = { noise("MineStrikeClean", Vector3.zero, 0) }
			Harness.isNil(
				SoundField.audibleFor(at, single, 0, shallowHearing),
				"one swing on floor 1 must stay safe however the deep end is tuned"
			)
			-- The curve is clamped, not extrapolated: past the last authored floor a crawler holds the
			-- deepest ears rather than growing new ones forever.
			local past = crawlerHearingAt(40)
			Harness.equal(past.sensitivity, deep.sensitivity, "sensitivity must clamp at the deepest authored floor")
			Harness.equal(past.hearingRadius, deep.hearingRadius, "hearing radius must clamp too")
		end),

		Harness.test("mining is louder than the ambient noise floor it stands against", function()
			-- Default running must never out-shout working a seam, or the loudest thing a player does
			-- would be the thing they do constantly and mining would carry no signal.
			Harness.expect(
				SoundConfig.emitters.MineStrikeClean.loudness > SoundConfig.emitters.Sprint.loudness,
				"a pick strike must be louder than a footfall"
			)
			Harness.expect(
				SoundConfig.emitters.MineBreak.loudness > SoundConfig.emitters.MineStrikeFumble.loudness,
				"breaking the seam must be the loudest moment of mining"
			)
			Harness.expect(
				SoundConfig.emitters.Sprint.loudness < shallowHearing.curiosityThreshold,
				"a single footfall must never be worth investigating on its own"
			)
		end),

		Harness.test("one landing rouses the thing above your head and nothing else", function()
			-- WHAT JUMPING COSTS, stated as a contract. A landing is the only movement noise loud
			-- enough to matter on its own, and it matters to exactly one creature: the one hanging
			-- over the player. Walking stays silent to the whole cave either way — nothing emits it.
			local landing = noise("Landing", Vector3.zero, 0)
			local flyHearing = ThreatsConfig.definitions.VoidFly.hearing :: Types.HearingProfile
			Harness.expect(
				SoundField.audibleFor(Vector3.new(0, 0, 3), { landing }, 0, flyHearing) ~= nil,
				"a fly directly above a landing must notice it"
			)
			Harness.isNil(
				SoundField.audibleFor(Vector3.new(0, 0, 3), { landing }, 0, shallowHearing),
				"one hop must not be worth a shallow crawler's attention"
			)
			Harness.expect(
				SoundConfig.emitters.Landing.loudness < SoundConfig.emitters.MineStrikeFumble.loudness,
				"landing must stay under the noise mining makes, or jumping becomes the loudest act in the game"
			)
			Harness.expect(
				SoundConfig.emitters.Landing.decaySeconds <= SoundConfig.emitters.MineStrikeClean.decaySeconds,
				"a landing is a moment, not a place: it must fade at least as fast as a pick strike"
			)
		end),
	},
}

return suite

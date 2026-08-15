--!strict

local Harness = require(script.Parent.Harness)
local Threats = require(script.Parent.Parent.Config.Threats)
local Protocol = require(script.Parent.Parent.NewModelsAndObjects.ThreatVisualProtocol)
local ThreatVisualRules = require(script.Parent.Parent.NewModelsAndObjects.ThreatVisualRules)

type Timing = {
	anticipationSeconds: number,
	strikeSeconds: number,
	recoverySeconds: number,
	impactFraction: number,
}

local function totalSeconds(motion: Timing): number
	return motion.anticipationSeconds + motion.strikeSeconds + motion.recoverySeconds
end

local function impactSeconds(motion: Timing): number
	return motion.anticipationSeconds + motion.strikeSeconds * motion.impactFraction
end

local suite: Harness.Suite = {
	name = "ThreatAnimationConfig",
	tests = {
		Harness.test("every rendered strike kind owns valid phased motion and two audio beats", function()
			local procedural = Threats.visuals.procedural
			local motionByKind = procedural.attackMotion :: { [string]: Timing }
			for _, kind in Protocol.kinds do
				local motion = motionByKind[kind]
				Harness.expect(motion ~= nil, kind .. " has a strike but no motion row")
				Harness.expect(motion.anticipationSeconds > 0, kind .. " has no anticipation")
				Harness.expect(motion.strikeSeconds > 0, kind .. " has no strike phase")
				Harness.expect(motion.recoverySeconds > 0, kind .. " has no recovery")
				Harness.expect(
					motion.impactFraction > 0 and motion.impactFraction <= 1,
					kind .. " impact must occur inside its strike phase"
				)
				Harness.expect(
					impactSeconds(motion) < totalSeconds(motion),
					kind .. " must retain visible recovery after impact"
				)
				Harness.expect(
					procedural.attackAudio.lungeCueNames[kind] ~= nil,
					kind .. " has motion but no commit cue"
				)
				Harness.expect(
					procedural.attackAudio.impactCueNames[kind] ~= nil,
					kind .. " has motion but no impact cue"
				)
			end
		end),

		Harness.test("continuous-contact actions settle before another cosmetic pulse", function()
			local procedural = Threats.visuals.procedural
			local motionByKind = procedural.attackMotion :: { [string]: Timing }
			for _, kind in { "Crawler", "Moth", "Listener", "Knotwalker" } do
				Harness.expect(
					totalSeconds(motionByKind[kind]) <= procedural.attackPulseIntervalSeconds,
					kind .. " action overlaps the next confirmed-contact presentation pulse"
				)
			end
			local voidFlyAttack =
				assert(Threats.definitions.VoidFly.contactAttack, "VoidFly lost its staged contact cadence")
			Harness.expect(
				totalSeconds(motionByKind.CeilingFly) <= voidFlyAttack.cooldownSeconds,
				"CeilingFly action overlaps VoidFly's next confirmed bite"
			)
		end),

		Harness.test("Calver impact is caused by and paced against its own ceiling strike", function()
			local motion = Threats.visuals.procedural.attackMotion.Calver
			local ceilingStrike = assert(Threats.definitions.Calver.ceilingStrike, "Calver lost its ceiling strike")
			Harness.near(
				impactSeconds(motion),
				ceilingStrike.windUpSeconds,
				1e-6,
				"Calver's hammer must arrive when the server begins the separate dripstone warning"
			)
			Harness.expect(
				totalSeconds(motion) < ceilingStrike.cooldownSeconds,
				"Calver's long recovery overlaps its next authoritative ceiling-strike opportunity"
			)
			Harness.expect(
				Protocol.actions.ceilingStrike ~= "",
				"Calver's timestamped pre-effect intent lost its stable action id"
			)
		end),

		Harness.test("asymmetric and held motion ranges remain ordered", function()
			local motion = Threats.visuals.procedural.attackMotion
			Harness.expect(
				motion.Knotwalker.idleResetMinSeconds < motion.Knotwalker.idleResetMaxSeconds,
				"Knotwalker joint-reset interval is inverted"
			)
			Harness.expect(motion.Knotwalker.idleResetSeconds > 0, "Knotwalker joint reset has no duration")
			Harness.expect(
				motion.Knotwalker.leadHandFraction > 0 and motion.Knotwalker.leadHandFraction < 1,
				"Knotwalker's leading hand must remain subtly ahead rather than fully desynchronised"
			)
			Harness.expect(
				motion.Listener.earLeadFraction > 0 and motion.Listener.earLeadFraction < 1,
				"Listener ears must lead the skull inside the anticipation"
			)
			Harness.expect(
				motion.Calver.impactHoldSeconds < motion.Calver.recoverySeconds,
				"Calver's post-impact hold must leave time to settle back into the roof"
			)
			Harness.expect(
				motion.CeilingFly.clingTransitionSeconds > 0,
				"CeilingFly roof-cling transition must have a positive duration"
			)
		end),

		Harness.test("a launched VoidFly does not re-cling during a patrol pause", function()
			local airborne = ThreatVisualRules.ceilingFlyAirborne(false, "Wander", false)
			Harness.expect(not airborne, "an unstarted stationary fly should retain its initial ceiling grip")

			airborne = ThreatVisualRules.ceilingFlyAirborne(airborne, "Wander", true)
			Harness.expect(airborne, "horizontal patrol movement should launch the fly")

			airborne = ThreatVisualRules.ceilingFlyAirborne(airborne, "Wander", false)
			Harness.expect(airborne, "a one-frame patrol pause must not make the fly backflip into a grip")
		end),
	},
}

return suite

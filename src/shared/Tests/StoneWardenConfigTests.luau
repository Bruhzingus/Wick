--!strict

local Harness = require(script.Parent.Harness)
local CaveFamilies = require(script.Parent.Parent.Config.CaveFamilies)
local Floors = require(script.Parent.Parent.Config.Floors)
local Hazards = require(script.Parent.Parent.Config.Hazards)
local StoneWarden = require(script.Parent.Parent.Config.StoneWarden)

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local suite: Harness.Suite = {
	name = "StoneWardenConfig",
	tests = {
		Harness.test("every procedural motion value is finite", function()
			for name, value in StoneWarden.motion do
				Harness.expect(isFinite(value), "StoneWarden.motion." .. name .. " must be finite")
			end
		end),

		Harness.test("motion clocks and smoothing windows are positive", function()
			local motion = StoneWarden.motion
			for _, entry in
				{
					{ name = "maxDeltaSeconds", value = motion.maxDeltaSeconds },
					{ name = "gaitCycleSeconds", value = motion.gaitCycleSeconds },
					{ name = "gaitReferenceSpeed", value = motion.gaitReferenceSpeed },
					{ name = "minimumGaitCadenceScale", value = motion.minimumGaitCadenceScale },
					{ name = "maximumGaitCadenceScale", value = motion.maximumGaitCadenceScale },
					{ name = "gaitBlendSeconds", value = motion.gaitBlendSeconds },
					{ name = "headLagSeconds", value = motion.headLagSeconds },
					{ name = "stunSettleSeconds", value = motion.stunSettleSeconds },
					{ name = "resumeGatherSeconds", value = motion.resumeGatherSeconds },
					{ name = "nearBraceBlendSeconds", value = motion.nearBraceBlendSeconds },
					{ name = "contactFollowThroughSeconds", value = motion.contactFollowThroughSeconds },
					{ name = "contactRepeatCooldownSeconds", value = motion.contactRepeatCooldownSeconds },
				}
			do
				Harness.expect(entry.value > 0, "StoneWarden.motion." .. entry.name .. " must be positive")
			end
			Harness.equal(
				motion.gaitReferenceSpeed,
				StoneWarden.walkSpeed,
				"the visible stomp cadence must be calibrated to the authoritative walk speed"
			)
		end),

		Harness.test("phase fractions remain normalized and non-degenerate", function()
			local motion = StoneWarden.motion
			Harness.expect(
				motion.emergenceUnsealFraction > 0 and motion.emergenceUnsealFraction < 1,
				"shoulders must unseal before authoritative emergence finishes"
			)
			Harness.expect(
				motion.armPhaseLagFraction >= 0 and motion.armPhaseLagFraction < 0.5,
				"arm delay must remain inside one half of the two-beat gait"
			)
			Harness.expect(
				motion.contactPeakFraction > 0 and motion.contactPeakFraction < 1,
				"confirmed-contact follow-through needs both drive and recovery"
			)
			Harness.expect(
				motion.minimumGaitCadenceScale <= motion.maximumGaitCadenceScale,
				"the gait cadence scale band cannot be inverted"
			)
			Harness.expect(
				motion.contactGaitSuppression >= 0 and motion.contactGaitSuppression <= 1,
				"confirmed contact may reduce the visible gait but cannot reverse it"
			)
		end),

		Harness.test("presentation magnitudes are bounded and cannot add a gameplay window", function()
			local motion = StoneWarden.motion
			for _, entry in
				{
					{ name = "bodyBobStuds", value = motion.bodyBobStuds },
					{ name = "hipRollDegrees", value = motion.hipRollDegrees },
					{ name = "legSwingDegrees", value = motion.legSwingDegrees },
					{ name = "kneeLiftDegrees", value = motion.kneeLiftDegrees },
					{ name = "armSwingDegrees", value = motion.armSwingDegrees },
					{ name = "headLagDegrees", value = motion.headLagDegrees },
					{ name = "emergenceCrouchStuds", value = motion.emergenceCrouchStuds },
					{ name = "emergenceShoulderDegrees", value = motion.emergenceShoulderDegrees },
					{ name = "stunSagStuds", value = motion.stunSagStuds },
					{ name = "stunPitchDegrees", value = motion.stunPitchDegrees },
					{ name = "resumeGatherStuds", value = motion.resumeGatherStuds },
					{ name = "nearBraceDistance", value = motion.nearBraceDistance },
					{ name = "nearBracePitchDegrees", value = motion.nearBracePitchDegrees },
					{ name = "nearBraceForwardStuds", value = motion.nearBraceForwardStuds },
					{ name = "nearBraceShoulderDegrees", value = motion.nearBraceShoulderDegrees },
					{ name = "contactDriveStuds", value = motion.contactDriveStuds },
					{ name = "contactPitchDegrees", value = motion.contactPitchDegrees },
					{ name = "contactShoulderDegrees", value = motion.contactShoulderDegrees },
				}
			do
				Harness.expect(entry.value >= 0, "StoneWarden.motion." .. entry.name .. " cannot be negative")
			end
			Harness.expect(
				motion.resumeGatherSeconds < Hazards.unstableDripstone.wardenStunSeconds,
				"resume gathering must fit inside the existing authoritative dripstone stun"
			)
			Harness.expect(
				motion.contactFollowThroughSeconds < Hazards.unstableDripstone.wardenStunSeconds,
				"post-contact presentation must stay a short visual echo, not resemble a new stun or attack phase"
			)
		end),

		-- THE TEST THIS WHOLE SEAM EXISTS FOR. The Warden stands twelve studs tall and the generator
		-- cuts openings as small as eight, so before it could fold, a low arch did not slow the pursuit
		-- down — it ended it, and a player who found one could ignore the encounter entirely.
		--
		-- Both halves of the fix are checked, because either one alone leaves it stuck: the body has to
		-- physically clear the tightest opening Config/Floors can produce, AND the pathfinding agent has
		-- to be small enough that a route through that opening exists to walk in the first place.
		Harness.test("a folded Warden fits the tightest opening the generator can cut", function()
			local squeeze = StoneWarden.squeeze
			local geometry = Floors.geometry
			Harness.expect(
				squeeze.squeezedHeight < geometry.doorwayMinHeight,
				"the folded body must clear the shortest doorway the generator can roll"
			)
			Harness.expect(
				squeeze.squeezedWidth < geometry.doorwayMinWidth,
				"the folded body must pass the narrowest doorway the generator can roll"
			)
			-- PathfindingService refuses to route an agent through anything shorter than the agent, so
			-- an agent taller than the folded body would make those doorways invisible to the plan even
			-- though the body can walk through them.
			Harness.expect(
				squeeze.agentHeight <= squeeze.squeezedHeight,
				"the pathfinding agent must not be taller than the body it plans for"
			)
			Harness.expect(
				squeeze.agentRadius * 2 <= squeeze.squeezedWidth,
				"the pathfinding agent must not be wider than the body it plans for"
			)
			Harness.expect(
				squeeze.standingHeight > squeeze.squeezedHeight and squeeze.standingWidth > squeeze.squeezedWidth,
				"folding must actually make the body smaller"
			)
			-- A fold that cost nothing would be a free pass through every opening on the floor. A fold
			-- that stopped it would be the bug this replaced, wearing a different name.
			Harness.expect(
				squeeze.walkSpeedMultiplier > 0 and squeeze.walkSpeedMultiplier < 1,
				"folding must cost time and must never cost the pursuit"
			)
			Harness.expect(#squeeze.probeDistances > 0, "the body has to look somewhere before it folds")
		end),

		Harness.test("the wake's beats stay ordered inside the emergence they are fractions of", function()
			local stages = StoneWarden.emergenceStages
			local ordered = { stages.tremorFraction, stages.breachFraction, stages.riseFraction, stages.roarFraction }
			local previous = 0
			for index, fraction in ordered do
				Harness.expect(
					fraction > previous and fraction < 1,
					"emergence beat " .. index .. " must fall after the one before it and inside the animation"
				)
				previous = fraction
			end
			for _, id in { "tremor", "breach", "rise", "roar" } do
				local shake = stages.beatShake[id]
				Harness.expect(shake ~= nil, "beat " .. id .. " has no authored floor movement")
				Harness.expect(shake.seconds > 0 and shake.frequency > 0, id .. " needs a real shake window")
			end
		end),

		-- Floors stack 96 studs apart (Config/Floors.geometry.floorGap), and none of the presentation
		-- below is filtered by depth — it does not have to be, as long as it cannot reach that far. A
		-- retune that pushed one of these past the gap would have players feeling a Warden walking on a
		-- floor they have never been to, which reads as a bug in the darkness rather than as a threat.
		Harness.test("no Warden presentation reaches the floor above or below it", function()
			local presence = StoneWarden.presence
			for _, entry in
				{
					{ name = "presence.rumbleRadius", value = presence.rumbleRadius },
					{ name = "presence.stepAudioRadius", value = presence.stepAudioRadius },
					{ name = "presence.stepPresentationRadius", value = presence.stepPresentationRadius },
					{ name = "presence.loopRadius", value = presence.loopRadius },
					{ name = "collapsePresentationRadius", value = StoneWarden.collapsePresentationRadius },
				}
			do
				Harness.expect(
					entry.value > 0 and entry.value < Floors.geometry.floorGap,
					"StoneWarden." .. entry.name .. " must stay inside one floor"
				)
			end
			Harness.expect(#presence.tag > 0, "clients need a tag to find the body by")
		end),

		Harness.test("every cave lights its own Warden", function()
			for _, family in CaveFamilies.families do
				local accent = StoneWarden.accents[family.id]
				Harness.expect(accent ~= nil, family.id .. " has no Warden accent")
				-- The eyes are the one light on the body. ART-BIBLE §4 binds the CAVE to darkness, and a
				-- creature carrying a lamp would quietly repeal that: a Warden must resolve out of the
				-- dark a moment before it reaches you and must never show you the room it is in.
				Harness.expect(
					accent.eyeLightRange > 0 and accent.eyeLightRange <= StoneWarden.presence.rumbleRadius / 4,
					family.id .. " Warden's eyes must be visible without lighting the cave"
				)
				Harness.expect(accent.eyeLightBrightness > 0, family.id .. " Warden must have eyes at all")
				Harness.expect(accent.coreSeamCount >= 0, family.id .. " Warden cannot have negative seams")
			end
			Harness.expect(StoneWarden.defaultAccent ~= nil, "an unknown family must still get a lit Warden")
		end),
	},
}

return suite

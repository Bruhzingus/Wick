--!strict

local Harness = require(script.Parent.Harness)
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
	},
}

return suite

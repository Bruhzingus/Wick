-- StoneWardenAnimator.lua
-- Presentation-only Motor6D posing for one server-owned Warden rig. It never moves the authoritative
-- root, changes Humanoid movement, chooses a target, decides contact, or changes a stun deadline.
--
-- THE SQUEEZE IS THE ONE PLACE THAT CONTRACT NEEDS RESTATING. Folding the body through a tight
-- opening genuinely does require the authoritative root to change size, and this file still does not
-- do it — StoneWardenSqueeze owns the root and hands the resulting 0..1 blend down through
-- `setSqueeze`. Everything here only draws the body in the shape the root is already in. The one
-- number that crosses that line is `SqueezeRootLift`, which is read from the same config the root is
-- resized from so the soles stay on the floor while the root's centre drops.

local RunService = game:GetService("RunService")

local StoneWardenAnimator = {}
StoneWardenAnimator.__index = StoneWardenAnimator

local TAU = math.pi * 2

local function clamp01(value)
	return math.clamp(value, 0, 1)
end

local function smoothstep(value)
	local x = clamp01(value)
	return x * x * (3 - 2 * x)
end

local function easeOutCubic(value)
	local x = 1 - clamp01(value)
	return 1 - x * x * x
end

-- Normalized position inside one stage of the wake. Stages are authored as fractions of the whole
-- emergence (Config/StoneWarden.emergenceStages) so retiming `emergenceSeconds` retimes all of them
-- together and none can run past the end.
local function stage(progress, from, to)
	if to <= from then
		return if progress >= to then 1 else 0
	end
	return clamp01((progress - from) / (to - from))
end

-- Rises to 1 at the middle of a stage and falls back. Used for beats that PEAK rather than arrive —
-- the arm that punches out of the wall, and the bellow at full height.
local function bell(value)
	return math.sin(clamp01(value) * math.pi)
end

local function damp(current, target, seconds, dt)
	if seconds <= 0 then
		return target
	end
	return current + (target - current) * (1 - math.exp(-dt / seconds))
end

local function pose(joint, transform)
	joint.motor.C0 = joint.baseC0 * transform
end

local function yawOf(cframe)
	local look = cframe.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function shortestAngle(from, to)
	return math.atan2(math.sin(to - from), math.cos(to - from))
end

local function horizontalSpeed(root)
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

function StoneWardenAnimator.new(rig, motion, emergenceSeconds, stages, squeeze)
	local self = setmetatable({}, StoneWardenAnimator)
	self.Rig = rig
	self.Motion = motion
	self.EmergenceSeconds = emergenceSeconds
	self.Stages = stages
	-- The root's centre drops by half the height it loses when it folds, because the Humanoid keeps the
	-- bottom of the root on the ground. Cancelling that is what keeps the soles planted while the body
	-- crouches instead of sinking the whole rig two studs into the cave — and it is derived from the
	-- root's REAL size every frame rather than from this file's own blend, because the two ramps do not
	-- share a window on purpose (the pose leads the hitbox going in, and trails it coming out). Inferring
	-- the lift from the pose blend instead would make the body dip and recover on every unfold.
	self.SqueezeStandingHeight = squeeze.standingHeight
	self.Mode = "DORMANT"
	self.EmergenceStartedAt = 0
	self.NearTargetDistance = nil
	self.StunnedUntil = 0
	self.ContactStartedAt = -math.huge
	self.GaitPhase = 0
	self.GaitBlend = 0
	self.BraceBlend = 0
	self.StunBlend = 0
	self.GatherBlend = 0
	self.SqueezeTarget = 0
	self.SqueezeBlend = 0
	self.HeadYaw = 0
	self.LastRootYaw = yawOf(rig.root.CFrame)
	self.LastStepSign = 0
	self.OnFootPlant = nil
	self.Destroyed = false

	self.HeartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if rig.model.Parent == nil then
			self:destroy()
			return
		end
		self:step(dt)
	end)
	self.AncestryConnection = rig.model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:destroy()
		end
	end)

	return self
end

function StoneWardenAnimator:beginEmergence(startedAt)
	self.Mode = "EMERGING"
	self.EmergenceStartedAt = startedAt
end

function StoneWardenAnimator:setActive()
	self.Mode = "ACTIVE"
end

function StoneWardenAnimator:setNearTarget(distance)
	self.NearTargetDistance = distance
end

function StoneWardenAnimator:setStunnedUntil(deadline)
	if deadline > self.StunnedUntil then
		self.StunnedUntil = deadline
	end
end

-- 0 standing, 1 fully folded. Owned by StoneWardenSqueeze, which is also what resized the root this
-- pose has to match; this file never decides to fold.
function StoneWardenAnimator:setSqueeze(amount)
	self.SqueezeTarget = clamp01(amount or 0)
end

-- Called only from the existing confirmed Touched path. The authoritative death has already been
-- selected by that path; this timer can only draw the stone mass continuing through the contact.
function StoneWardenAnimator:signalContact()
	self.ContactStartedAt = tick()
end

-- One sole landing. Fired from the gait phase rather than from a physics touch, so it is exactly in
-- sync with the leg a player is watching, and it stays presentation: the behaviour turns it into a
-- broadcast footfall, and nothing downstream of it can hurt anybody.
function StoneWardenAnimator:_emitFootPlant(side, strength)
	local callback = self.OnFootPlant
	if callback == nil then
		return
	end
	local leg = if side == "Left" then self.Rig.legs.left else self.Rig.legs.right
	local foot = leg.foot
	if foot == nil or foot.Parent == nil then
		return
	end
	local ok, err = pcall(callback, side, foot.Position, strength)
	if not ok then
		warn("[WICK WARDEN] footfall presentation failed: " .. tostring(err))
	end
end

function StoneWardenAnimator:step(rawDt)
	if self.Destroyed then
		return
	end

	local motion = self.Motion
	local dt = math.min(math.max(rawDt, 0), motion.maxDeltaSeconds)
	local now = tick()
	local active = self.Mode == "ACTIVE"
	local stunned = active and now < self.StunnedUntil

	local speed = if active and not stunned then horizontalSpeed(self.Rig.root) else 0
	local gaitTarget = clamp01(speed / motion.gaitReferenceSpeed)
	self.GaitBlend = damp(self.GaitBlend, gaitTarget, motion.gaitBlendSeconds, dt)
	if self.GaitBlend > 0.001 then
		local cadence = math.clamp(
			speed / motion.gaitReferenceSpeed,
			motion.minimumGaitCadenceScale,
			motion.maximumGaitCadenceScale
		)
		self.GaitPhase = (self.GaitPhase + TAU * dt * cadence / motion.gaitCycleSeconds) % TAU
	end

	local braceTarget = 0
	if active and not stunned and self.NearTargetDistance ~= nil then
		braceTarget = clamp01(1 - self.NearTargetDistance / motion.nearBraceDistance)
	end
	self.BraceBlend = damp(self.BraceBlend, braceTarget, motion.nearBraceBlendSeconds, dt)

	local stunTarget = if stunned then 1 else 0
	self.StunBlend = damp(self.StunBlend, stunTarget, motion.stunSettleSeconds, dt)
	local gatherTarget = 0
	if stunned then
		local remaining = self.StunnedUntil - now
		if remaining < motion.resumeGatherSeconds then
			gatherTarget = smoothstep(1 - remaining / motion.resumeGatherSeconds)
		end
	end
	-- Smoothing also makes an extended stun fold the gathering pose back under the rubble instead of
	-- snapping when a second formation lands during the final fraction of the first stun.
	self.GatherBlend = damp(self.GatherBlend, gatherTarget, motion.stunSettleSeconds, dt)

	-- A stunned or emerging body is never also folded: both of those own the whole silhouette, and a
	-- Warden buried under a crown must not keep tucking its shoulders as though it were still walking.
	local squeezeTarget = if active and not stunned then self.SqueezeTarget else 0
	self.SqueezeBlend = damp(self.SqueezeBlend, squeezeTarget, motion.squeezeBlendSeconds, dt)
	local squeeze = self.SqueezeBlend

	local rootYaw = yawOf(self.Rig.root.CFrame)
	local rootTurn = shortestAngle(self.LastRootYaw, rootYaw)
	self.LastRootYaw = rootYaw
	self.HeadYaw =
		math.clamp(self.HeadYaw - rootTurn, -math.rad(motion.headLagDegrees), math.rad(motion.headLagDegrees))
	self.HeadYaw = damp(self.HeadYaw, 0, motion.headLagSeconds, dt)

	-- THE WAKE, IN FOUR BEATS instead of one linear slide. What this replaced eased a crouch out over
	-- four seconds while the body translated forward, which read as an object being moved rather than
	-- as a thing standing up. Now: it strains against the seal, an arm breaks out and takes the floor,
	-- the body climbs up over that arm, and it reaches full height a beat before it settles.
	local emergenceSeal = 0
	local emergenceCrouch = 0
	local emergenceBreach = 0
	local emergenceDuck = 0
	local emergenceRoar = 0
	local emergenceSettle = 0
	if self.Mode == "EMERGING" then
		local stages = self.Stages
		local progress = clamp01((now - self.EmergenceStartedAt) / self.EmergenceSeconds)
		emergenceSeal = 1 - smoothstep(progress / motion.emergenceUnsealFraction)
		emergenceCrouch = 1 - smoothstep(stage(progress, stages.tremorFraction, stages.riseFraction))
		emergenceBreach = bell(stage(progress, stages.tremorFraction, stages.riseFraction))
		emergenceDuck = 1 - smoothstep(stage(progress, stages.breachFraction, stages.roarFraction))
		emergenceRoar = bell(stage(progress, stages.riseFraction, 1))
		-- The overshoot on the last of the rise. Full height arrives as a slam that drops back rather
		-- than as a curve that stops, which is the difference between a body and a lift.
		local settleAt = stage(progress, stages.roarFraction, 1)
		emergenceSettle = bell(settleAt) * (1 - settleAt * 0.4)
	elseif self.Mode == "DORMANT" then
		emergenceSeal = 1
		emergenceCrouch = 1
		emergenceDuck = 1
	end

	local contact = 0
	local contactAge = now - self.ContactStartedAt
	if active and contactAge >= 0 and contactAge < motion.contactFollowThroughSeconds then
		local progress = contactAge / motion.contactFollowThroughSeconds
		if progress <= motion.contactPeakFraction then
			contact = easeOutCubic(progress / motion.contactPeakFraction)
		else
			contact = 1 - smoothstep((progress - motion.contactPeakFraction) / (1 - motion.contactPeakFraction))
		end
	end

	local gait = self.GaitBlend * (1 - self.StunBlend) * (1 - contact * motion.contactGaitSuppression)
	local leftStep = math.sin(self.GaitPhase)
	local rightStep = -leftStep

	-- FOOTFALLS. A sole is planted while its own step term is negative, so a plant is that term
	-- crossing zero downward. Gated on a real gait so a body creeping at the edge of its blend cannot
	-- machine-gun the cue, and skipped entirely on the first frame after a stop.
	if active and gait > 0.18 then
		local sign = if leftStep >= 0 then 1 else -1
		if self.LastStepSign ~= 0 and sign ~= self.LastStepSign then
			local strength = clamp01(gait) * (1 - squeeze * 0.35)
			self:_emitFootPlant(if sign < 0 then "Left" else "Right", strength)
		end
		self.LastStepSign = sign
	else
		self.LastStepSign = 0
	end

	local twoBeat = 0.5 + 0.5 * math.cos(self.GaitPhase * 2)
	local bodyBob = -motion.bodyBobStuds * twoBeat * gait
	local hipRoll = math.rad(motion.hipRollDegrees) * leftStep * gait
	local bracePitch = math.rad(motion.nearBracePitchDegrees) * self.BraceBlend
	local contactPitch = math.rad(motion.contactPitchDegrees) * contact
	local stunPitch = math.rad(motion.stunPitchDegrees) * self.StunBlend
	local squeezePitch = math.rad(motion.squeezePitchDegrees) * squeeze
	local squeezeTurn = math.rad(motion.squeezeTurnDegrees) * squeeze
	-- Stone does not fit through a hole, it grinds through one. Without this the fold reads as a
	-- smaller Warden walking through comfortably.
	local strain = math.sin(now * motion.squeezeStrainFrequency) * math.rad(motion.squeezeStrainDegrees) * squeeze
	-- A standing body is never completely still. Well under the gait, and multiplied out as soon as
	-- it starts walking so it can never fight the stride.
	local idle = (1 - self.GaitBlend) * (1 - self.StunBlend) * (if active then 1 else 0)
	local idleBreath = math.sin(now * TAU / motion.idleBreathSeconds) * motion.idleBreathStuds * idle
	local idleSway = math.sin(now * TAU / (motion.idleBreathSeconds * 1.7)) * math.rad(motion.idleSwayDegrees) * idle

	local bodyForward = motion.nearBraceForwardStuds * self.BraceBlend + motion.contactDriveStuds * contact
	local bodyHeight = bodyBob
		+ idleBreath
		- motion.emergenceCrouchStuds * emergenceCrouch
		- motion.stunSagStuds * self.StunBlend
		+ motion.resumeGatherStuds * self.GatherBlend
		- motion.emergenceSettleStuds * emergenceSettle
		+ (self.SqueezeStandingHeight - self.Rig.root.Size.Y) / 2
		- motion.squeezeCrouchStuds * squeeze

	pose(
		self.Rig.spine.body,
		CFrame.new(0, bodyHeight, -bodyForward)
			* CFrame.Angles(bracePitch + contactPitch + stunPitch + squeezePitch + strain, 0, hipRoll + idleSway)
	)
	pose(self.Rig.spine.pelvis, CFrame.Angles(0, 0, hipRoll * 0.32))
	pose(
		self.Rig.spine.waist,
		CFrame.Angles(
			(bracePitch + contactPitch) * 0.26 - stunPitch * 0.18 + squeezePitch * 0.4,
			squeezeTurn * 0.45,
			-hipRoll * 0.42
		)
	)
	pose(
		self.Rig.spine.chest,
		CFrame.Angles(
			(bracePitch + contactPitch) * 0.34
				+ stunPitch * 0.12
				+ squeezePitch * 0.5
				- math.rad(motion.emergenceRoarPitchDegrees) * emergenceRoar,
			squeezeTurn * 0.55,
			-hipRoll * 0.24 - strain * 0.6
		)
	)
	pose(
		self.Rig.spine.head,
		CFrame.Angles(
			-(bracePitch + contactPitch) * 0.22
				+ stunPitch * 0.2
				+ math.rad(motion.squeezeHeadDuckDegrees) * squeeze
				+ math.rad(motion.emergenceHeadDuckDegrees) * emergenceDuck
				- math.rad(motion.emergenceRoarPitchDegrees) * emergenceRoar * 1.4,
			self.HeadYaw - squeezeTurn * 0.3,
			-hipRoll * 0.18
		)
	)

	local lag = motion.armPhaseLagFraction * TAU
	local armLeft = -math.sin(self.GaitPhase - lag) * gait
	local armRight = math.sin(self.GaitPhase - lag) * gait
	local shoulderReach = math.rad(motion.nearBraceShoulderDegrees) * self.BraceBlend
		+ math.rad(motion.contactShoulderDegrees) * contact
	-- Sealed against the wall while dormant, then thrown wide on the bellow. Both ride the same axis
	-- the fold tucks along, so the three can never argue about where an arm is.
	local sealedShoulder = math.rad(motion.emergenceShoulderDegrees) * emergenceSeal
		+ math.rad(motion.squeezeShoulderDegrees) * squeeze
		- math.rad(motion.emergenceRoarShoulderDegrees) * emergenceRoar
	local armTuck = math.rad(motion.squeezeArmTuckDegrees) * squeeze
		+ math.rad(motion.emergenceBreachShoulderDegrees) * emergenceBreach
	local elbowFold = math.rad(motion.squeezeElbowDegrees) * squeeze
		- math.rad(motion.emergenceBreachElbowDegrees) * emergenceBreach
	local function poseArm(arm, side, swing)
		pose(
			arm.shoulder,
			CFrame.Angles(math.rad(motion.armSwingDegrees) * swing + shoulderReach + armTuck, 0, side * sealedShoulder)
		)
		pose(arm.elbow, CFrame.Angles(-shoulderReach * 0.34 - math.abs(swing) * gait * 0.08 - elbowFold, 0, 0))
		pose(arm.wrist, CFrame.Angles(shoulderReach * 0.16 + elbowFold * 0.2, 0, -side * hipRoll * 0.2))
	end
	poseArm(self.Rig.arms.left, -1, armLeft)
	poseArm(self.Rig.arms.right, 1, armRight)

	local legSwing = math.rad(motion.legSwingDegrees)
	local kneeLift = math.rad(motion.kneeLiftDegrees)
	local stunBend = stunPitch * 0.38 * (1 - self.GatherBlend)
	-- Folded, the legs carry the crouch: thigh forward, calf back, and the ankle taking whatever is
	-- left over so the sole stays flat on the cave instead of rolling onto its toe.
	local hipCrouch = math.rad(motion.squeezeHipDegrees) * squeeze
	local kneeCrouch = math.rad(motion.squeezeKneeDegrees) * squeeze
	local function poseLeg(leg, step)
		local lift = math.max(0, step) * gait
		local swing = legSwing * step * gait
		pose(leg.hip, CFrame.Angles(swing + stunBend + hipCrouch, 0, 0))
		pose(leg.knee, CFrame.Angles(-kneeLift * lift - math.abs(swing) * 0.3 - stunBend * 0.7 - kneeCrouch, 0, 0))
		pose(leg.ankle, CFrame.Angles(-swing * 0.48 + kneeLift * lift * 0.32 + (kneeCrouch - hipCrouch), 0, 0))
	end
	poseLeg(self.Rig.legs.left, leftStep)
	poseLeg(self.Rig.legs.right, rightStep)
end

function StoneWardenAnimator:destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.OnFootPlant = nil
	if self.HeartbeatConnection ~= nil then
		self.HeartbeatConnection:Disconnect()
		self.HeartbeatConnection = nil
	end
	if self.AncestryConnection ~= nil then
		self.AncestryConnection:Disconnect()
		self.AncestryConnection = nil
	end
end

return StoneWardenAnimator

-- StoneWardenAnimator.lua
-- Presentation-only Motor6D posing for one server-owned Warden rig. It never moves the authoritative
-- root, changes Humanoid movement, chooses a target, decides contact, or changes a stun deadline.

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

function StoneWardenAnimator.new(rig, motion, emergenceSeconds)
	local self = setmetatable({}, StoneWardenAnimator)
	self.Rig = rig
	self.Motion = motion
	self.EmergenceSeconds = emergenceSeconds
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
	self.HeadYaw = 0
	self.LastRootYaw = yawOf(rig.root.CFrame)
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

-- Called only from the existing confirmed Touched path. The authoritative death has already been
-- selected by that path; this timer can only draw the stone mass continuing through the contact.
function StoneWardenAnimator:signalContact()
	self.ContactStartedAt = tick()
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

	local rootYaw = yawOf(self.Rig.root.CFrame)
	local rootTurn = shortestAngle(self.LastRootYaw, rootYaw)
	self.LastRootYaw = rootYaw
	self.HeadYaw =
		math.clamp(self.HeadYaw - rootTurn, -math.rad(motion.headLagDegrees), math.rad(motion.headLagDegrees))
	self.HeadYaw = damp(self.HeadYaw, 0, motion.headLagSeconds, dt)

	local emergenceSeal = 0
	local emergenceCrouch = 0
	if self.Mode == "EMERGING" then
		local progress = clamp01((now - self.EmergenceStartedAt) / self.EmergenceSeconds)
		emergenceSeal = 1 - smoothstep(progress / motion.emergenceUnsealFraction)
		emergenceCrouch = 1 - smoothstep(progress)
	elseif self.Mode == "DORMANT" then
		emergenceSeal = 1
		emergenceCrouch = 1
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
	local twoBeat = 0.5 + 0.5 * math.cos(self.GaitPhase * 2)
	local bodyBob = -motion.bodyBobStuds * twoBeat * gait
	local hipRoll = math.rad(motion.hipRollDegrees) * leftStep * gait
	local bracePitch = math.rad(motion.nearBracePitchDegrees) * self.BraceBlend
	local contactPitch = math.rad(motion.contactPitchDegrees) * contact
	local stunPitch = math.rad(motion.stunPitchDegrees) * self.StunBlend
	local bodyForward = motion.nearBraceForwardStuds * self.BraceBlend + motion.contactDriveStuds * contact
	local bodyHeight = bodyBob
		- motion.emergenceCrouchStuds * emergenceCrouch
		- motion.stunSagStuds * self.StunBlend
		+ motion.resumeGatherStuds * self.GatherBlend

	pose(
		self.Rig.spine.body,
		CFrame.new(0, bodyHeight, -bodyForward) * CFrame.Angles(bracePitch + contactPitch + stunPitch, 0, hipRoll)
	)
	pose(self.Rig.spine.pelvis, CFrame.Angles(0, 0, hipRoll * 0.32))
	pose(self.Rig.spine.waist, CFrame.Angles((bracePitch + contactPitch) * 0.26 - stunPitch * 0.18, 0, -hipRoll * 0.42))
	pose(self.Rig.spine.chest, CFrame.Angles((bracePitch + contactPitch) * 0.34 + stunPitch * 0.12, 0, -hipRoll * 0.24))
	pose(
		self.Rig.spine.head,
		CFrame.Angles(-(bracePitch + contactPitch) * 0.22 + stunPitch * 0.2, self.HeadYaw, -hipRoll * 0.18)
	)

	local lag = motion.armPhaseLagFraction * TAU
	local armLeft = -math.sin(self.GaitPhase - lag) * gait
	local armRight = math.sin(self.GaitPhase - lag) * gait
	local shoulderReach = math.rad(motion.nearBraceShoulderDegrees) * self.BraceBlend
		+ math.rad(motion.contactShoulderDegrees) * contact
	local sealedShoulder = math.rad(motion.emergenceShoulderDegrees) * emergenceSeal
	local function poseArm(arm, side, swing)
		pose(
			arm.shoulder,
			CFrame.Angles(math.rad(motion.armSwingDegrees) * swing + shoulderReach, 0, side * sealedShoulder)
		)
		pose(arm.elbow, CFrame.Angles(-shoulderReach * 0.34 - math.abs(swing) * gait * 0.08, 0, 0))
		pose(arm.wrist, CFrame.Angles(shoulderReach * 0.16, 0, -side * hipRoll * 0.2))
	end
	poseArm(self.Rig.arms.left, -1, armLeft)
	poseArm(self.Rig.arms.right, 1, armRight)

	local legSwing = math.rad(motion.legSwingDegrees)
	local kneeLift = math.rad(motion.kneeLiftDegrees)
	local stunBend = stunPitch * 0.38 * (1 - self.GatherBlend)
	local function poseLeg(leg, step)
		local lift = math.max(0, step) * gait
		local swing = legSwing * step * gait
		pose(leg.hip, CFrame.Angles(swing + stunBend, 0, 0))
		pose(leg.knee, CFrame.Angles(-kneeLift * lift - math.abs(swing) * 0.3 - stunBend * 0.7, 0, 0))
		pose(leg.ankle, CFrame.Angles(-swing * 0.48 + kneeLift * lift * 0.32, 0, 0))
	end
	poseLeg(self.Rig.legs.left, leftStep)
	poseLeg(self.Rig.legs.right, rightStep)
end

function StoneWardenAnimator:destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
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

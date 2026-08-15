--!strict
-- KNOTWALKER — Moss's signature dark-hunter. Built to be somewhere before you are.
-- Place at: ReplicatedStorage/Creatures/Knotwalker
--
-- THE SILHOUETTE IS THE MECHANIC, same as everything else on this roster. Moss generates more loops,
-- more optional branches and far more TwinLobe rooms than the other caves, and the way through a
-- TwinLobe is its neck. So this creature is built for necks: extremely narrow across the shoulders,
-- extremely long in the forelimbs, with a small high head on a thin neck of its own. It does not
-- barge through a gap, it THREADS one — arms first, shoulders turned, body following.
--
-- READ IT AGAINST THE CRAWLER, because that is what a player will do. The crawler is long-legged and
-- short-bodied: a person wrongly assembled. This is the opposite build — short-legged, long-armed,
-- and narrow enough that head-on it nearly disappears. Both carry the crimson angled eye slits, so a
-- player knows instantly that it is a hunter and just as instantly that it is not the other one.
--
-- THE HANDS ARE THE WARNING. Its forelimbs are longer than its whole torso and it carries them raised
-- and forward, reaching. When it is committed to a prediction the reach extends and the fingers
-- spread; when it has lost you they fold in. A player who catches the reach at the edge of their light
-- has been told, before anything else, which way it thinks they are going.
--
-- Nothing here collides, queries or touches. Wax, contact, perception and AI are the server's.

local CollectionService = game:GetService("CollectionService")
local PartKit = require(script.Parent.PartKit)
local CreatureDressing = require(script.Parent.CreatureDressing)
local Threats = require(script.Parent.Parent.Config.Threats)

local Knotwalker = {}
Knotwalker.__index = Knotwalker

local SKIN_DARK = Color3.fromRGB(10, 11, 12)
local SKIN_PALE = Color3.fromRGB(26, 26, 27)
local SKIN_MATERIAL = Enum.Material.Slate
local BONE_MATERIAL = Enum.Material.Concrete
local BONE = Color3.fromRGB(44, 41, 36)
local LIT_TARGET = Color3.fromRGB(72, 70, 64)
local LIT_MIX = 0.42

local EYE_IDLE = Color3.fromRGB(128, 16, 10)
local EYE_LOCKED = Color3.fromRGB(255, 46, 30)
local EYE_ANGLE = 20

-- Proportions. 5.4 studs to the crown, but only 0.52 across the shoulders — narrower than a candle.
-- The arms alone are 3.1, longer than the torso and head together.
local LEG_UPPER, LEG_LOWER = 1.15, 1.2
local ARM_UPPER, ARM_LOWER = 1.5, 1.6
local HAND_LEN = 0.42
local FINGER_LEN = 0.56
local LIMB_D = 0.2
local SHOULDER_SPAN = 0.52

local GAIT_REFERENCE_SPEED = 7
local GAIT_MAX_MEASURED_SPEED = 22

type Skinned = { part: BasePart, base: Color3, lit: Color3 }
type Arm = { upper: PartKit.Joint, lower: PartKit.Joint, fingers: { PartKit.Joint }, side: number }
type Leg = { upper: PartKit.Joint, lower: PartKit.Joint, side: number }

export type Walker = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		bodyJoint: PartKit.Joint,
		hitbox: BasePart,
		arms: { Arm },
		legs: { Leg },
		skin: { Skinned },
		dressAnchors: { CreatureDressing.Anchor },
		eyes: { BasePart },
		halos: { BasePart },
		spine: { PartKit.Joint },
		headJoint: PartKit.Joint,
		t: number,
		lit: number,
		lastPaintedIllumination: number?,
		aware: number,
		moving: boolean,
		focus: Vector3?,
		speed: number,
		lastPos: Vector3?,
		headYaw: number,
		reach: number,
		gaitPhase: number,
		pendingFootfall: number?,
		attackT: number,
		attackLanded: boolean,
		pendingImpact: boolean,
		strike: number,
		rng: Random,
		nextIdleResetAt: number,
		idleResetT: number,
		idleResetSide: number,
		attackSide: number,
	},
	{} :: typeof({ __index = Knotwalker })
))

local function skinColor(tone: number): Color3
	return SKIN_DARK:Lerp(SKIN_PALE, math.clamp(tone, 0, 1))
end

local function track(skin: { Skinned }, part: BasePart, base: Color3): BasePart
	table.insert(skin, { part = part, base = base, lit = base:Lerp(LIT_TARGET, LIT_MIX) })
	return part
end

local function blob(
	model: Model,
	skin: { Skinned },
	name: string,
	size: Vector3,
	tone: number,
	castShadow: boolean?
): BasePart
	local color = skinColor(tone)
	return track(
		skin,
		PartKit.ellipsoid(model, {
			name = name,
			size = size,
			color = color,
			material = SKIN_MATERIAL,
			castShadow = castShadow,
		}),
		color
	)
end

local function tube(model: Model, skin: { Skinned }, name: string, len: number, dia: number, tone: number): BasePart
	local color = skinColor(tone)
	return track(skin, PartKit.tube(model, name, len, dia, color, SKIN_MATERIAL, false), color)
end

local function refreshEyes(self: Walker)
	local heat = math.max(self.aware, self.strike)
	local color = PartKit.lerpColor(EYE_IDLE, EYE_LOCKED, 0.25 + heat * 0.75)
	local wash = self.lit * 0.5
	for _, eye in self.eyes do
		eye.Color = color
		eye.Transparency = wash
	end
	for _, halo in self.halos do
		halo.Color = color
		halo.Transparency = math.clamp(0.64 + self.lit * 0.32 - heat * 0.26, 0, 1)
	end
end

local function buildLeg(
	model: Model,
	skin: { Skinned },
	anchors: { CreatureDressing.Anchor },
	pelvis: BasePart,
	side: number
): Leg
	local upper = tube(model, skin, "Thigh", LEG_UPPER, LIMB_D * 1.15, 0.24)
	local jointUpper = PartKit.joint(
		pelvis,
		upper,
		CFrame.new(side * 0.17, -0.1, 0) * CFrame.Angles(math.rad(-86), 0, math.rad(side * 4)),
		PartKit.tubePivot(LEG_UPPER)
	)

	local lower = tube(model, skin, "Shin", LEG_LOWER, LIMB_D * 0.95, 0.16)
	local jointLower = PartKit.joint(
		upper,
		lower,
		PartKit.tubeTip(LEG_UPPER) * CFrame.Angles(math.rad(-12), 0, 0),
		PartKit.tubePivot(LEG_LOWER)
	)

	local foot = blob(model, skin, "Foot", Vector3.new(0.18, 0.1, 0.5), 0.1, false)
	PartKit.joint(
		lower,
		foot,
		PartKit.tubeTip(LEG_LOWER) * CFrame.Angles(math.rad(92), 0, 0),
		CFrame.new(0, 0.03, 0.16)
	)

	table.insert(anchors, { part = upper, normal = Vector3.new(0, side, 0), scale = 0.7, upward = false })
	table.insert(anchors, { part = foot, normal = Vector3.yAxis, scale = 0.5, upward = true })

	return { upper = jointUpper, lower = jointLower, side = side }
end

-- THE ARM. Two long segments, a narrow hand, and three fingers that are themselves nearly as long as
-- the hand — the reach a player reads before anything else on this body.
local function buildArm(
	model: Model,
	skin: { Skinned },
	anchors: { CreatureDressing.Anchor },
	chest: BasePart,
	side: number
): Arm
	local upper = tube(model, skin, "Upper", ARM_UPPER, LIMB_D, 0.28)
	local jointUpper = PartKit.joint(
		chest,
		upper,
		CFrame.new(side * SHOULDER_SPAN / 2, 0.2, 0)
			* CFrame.Angles(0, math.rad(side * 10), 0)
			-- Carried forward and slightly raised rather than hanging: this creature is always reaching.
			* CFrame.Angles(math.rad(-56), 0, math.rad(side * 8)),
		PartKit.tubePivot(ARM_UPPER)
	)

	local lower = tube(model, skin, "Forearm", ARM_LOWER, LIMB_D * 0.85, 0.2)
	local jointLower = PartKit.joint(
		upper,
		lower,
		PartKit.tubeTip(ARM_UPPER) * CFrame.Angles(math.rad(-26), 0, 0),
		PartKit.tubePivot(ARM_LOWER)
	)

	local hand = blob(model, skin, "Hand", Vector3.new(0.15, 0.08, HAND_LEN), 0.12, false)
	PartKit.joint(lower, hand, PartKit.tubeTip(ARM_LOWER), CFrame.new(0, 0, HAND_LEN / 2))

	local fingers: { PartKit.Joint } = {}
	for i = 1, 3 do
		local finger = tube(model, skin, "Finger", FINGER_LEN, 0.042, 0.07)
		table.insert(
			fingers,
			PartKit.joint(
				hand,
				finger,
				CFrame.new((i - 2) * 0.055, 0, -HAND_LEN / 2) * CFrame.Angles(math.rad(6), math.rad((i - 2) * 14), 0),
				PartKit.tubePivot(FINGER_LEN)
			)
		)
	end

	-- Both arm segments are offered, and both allow a hanging strand. In Moss this is exactly where a
	-- player sees the growth move: the arms travel further per stride than anything else here.
	table.insert(
		anchors,
		{ part = upper, normal = Vector3.new(0, side, 0), scale = 0.8, upward = true, allowStrand = true }
	)
	table.insert(
		anchors,
		{ part = lower, normal = Vector3.new(0, side, 0), scale = 0.7, upward = false, allowStrand = true }
	)

	return { upper = jointUpper, lower = jointLower, fingers = fingers, side = side }
end

function Knotwalker.build(parent: Instance): Walker
	local model = Instance.new("Model")
	model.Name = "Knotwalker"
	local skin: { Skinned } = {}
	local anchors: { CreatureDressing.Anchor } = {}

	-- Keep the proxy-following root separate from the visible pelvis. Whole-body reach and recovery
	-- then stay cosmetic and cannot feed back into the measured gait speed.
	local root = PartKit.part(model, {
		name = "PresentationRoot",
		size = Vector3.new(0.1, 0.1, 0.1),
		transparency = 1,
		castShadow = false,
	})
	local pelvis = blob(model, skin, "Pelvis", Vector3.new(0.42, 0.42, 0.34), 0.3)
	local bodyJoint = PartKit.joint(root, pelvis, CFrame.new())

	-- A spine of three narrow segments. Narrow is the whole design: seen head-on this body is a line.
	local spine: { PartKit.Joint } = {}
	local previous: BasePart = pelvis
	local chest: BasePart = pelvis
	for _, segment in
		{
			{ name = "Waist", w = 0.4, h = 0.56, d = 0.3, at = 0.4 },
			{ name = "Chest", w = SHOULDER_SPAN, h = 0.78, d = 0.34, at = 0.6 },
		}
	do
		local part = blob(model, skin, segment.name, Vector3.new(segment.w, segment.h, segment.d), 0.36)
		table.insert(
			spine,
			PartKit.joint(
				previous,
				part,
				CFrame.new(0, segment.at - segment.h / 2, 0),
				CFrame.new(0, -segment.h / 2, 0)
			)
		)
		previous = part
		if segment.name == "Chest" then
			chest = part
		end
	end

	-- Collarbones swept FORWARD rather than out, which is what lets the shoulders fold through a gap.
	for _, side in { -1, 1 } do
		local clavicle = PartKit.tube(model, "Clavicle", 0.34, 0.055, BONE, BONE_MATERIAL, false)
		PartKit.joint(
			chest,
			clavicle,
			CFrame.new(side * 0.16, 0.26, -0.1) * CFrame.Angles(0, math.rad(side * 34), math.rad(side * -8))
		)
		track(skin, clavicle, BONE)
	end

	local neck = tube(model, skin, "Neck", 0.5, 0.14, 0.2)
	PartKit.joint(chest, neck, CFrame.new(0, 0.38, 0) * CFrame.Angles(math.rad(-84), 0, 0), PartKit.tubePivot(0.5))

	-- A small head, held high. Small because everything a player needs from it is the two slits.
	local skull = blob(model, skin, "Skull", Vector3.new(0.3, 0.44, 0.4), 0.42)
	local headJoint = PartKit.joint(neck, skull, PartKit.tubeTip(0.5) * CFrame.Angles(math.rad(84), 0, 0))

	local eyes: { BasePart } = {}
	local halos: { BasePart } = {}
	for _, side in { -1, 1 } do
		local halo = PartKit.neon(model, {
			name = "Halo",
			size = Vector3.new(0.2, 0.09, 0.07),
			color = EYE_IDLE,
			transparency = 0.68,
		})
		PartKit.joint(
			skull,
			halo,
			CFrame.new(side * 0.09, 0.05, -0.17) * CFrame.Angles(0, 0, math.rad(side * EYE_ANGLE))
		)
		table.insert(halos, halo)

		local slit = PartKit.neon(model, {
			name = "Eye",
			size = Vector3.new(0.17, 0.05, 0.045),
			color = EYE_IDLE,
		})
		PartKit.joint(
			skull,
			slit,
			CFrame.new(side * 0.09, 0.05, -0.2) * CFrame.Angles(0, 0, math.rad(side * EYE_ANGLE))
		)
		table.insert(eyes, slit)
	end

	local legs: { Leg } = {}
	local arms: { Arm } = {}
	for _, side in { -1, 1 } do
		table.insert(legs, buildLeg(model, skin, anchors, pelvis, side))
	end
	for _, side in { -1, 1 } do
		table.insert(arms, buildArm(model, skin, anchors, chest, side))
	end

	table.insert(anchors, { part = chest, normal = Vector3.new(0, 0.5, -1).Unit, scale = 0.85, upward = true })
	table.insert(anchors, { part = pelvis, normal = Vector3.yAxis, scale = 0.8, upward = true })

	local hitbox = PartKit.hitbox(model, pelvis, Vector3.new(1, 5.2, 1), CFrame.new(0, 1.1, 0))

	PartKit.finalise(model, root, true)
	CollectionService:AddTag(model, "Creature")
	CollectionService:AddTag(model, "DarkHunter")
	model:SetAttribute("FleesLight", true)
	model.Parent = parent

	local rng = Random.new()
	local idleMotion = Threats.visuals.procedural.attackMotion.Knotwalker
	local self = setmetatable({
		model = model,
		root = root,
		bodyJoint = bodyJoint,
		hitbox = hitbox,
		arms = arms,
		legs = legs,
		skin = skin,
		dressAnchors = anchors,
		eyes = eyes,
		halos = halos,
		spine = spine,
		headJoint = headJoint,
		t = 0,
		lit = 0,
		lastPaintedIllumination = nil,
		aware = 0,
		moving = false,
		focus = nil,
		speed = 0,
		lastPos = nil,
		headYaw = 0,
		reach = 0,
		gaitPhase = 0,
		pendingFootfall = nil,
		attackT = -1,
		attackLanded = true,
		pendingImpact = false,
		strike = 0,
		rng = rng,
		nextIdleResetAt = rng:NextNumber(idleMotion.idleResetMinSeconds, idleMotion.idleResetMaxSeconds),
		idleResetT = -1,
		idleResetSide = -1,
		attackSide = -1,
	}, Knotwalker)

	refreshEyes(self)
	return self
end

function Knotwalker.setIllumination(self: Walker, lit01: number)
	self.lit = math.clamp(lit01, 0, 1)
	if self.lastPaintedIllumination ~= self.lit then
		self.lastPaintedIllumination = self.lit
		for _, s in self.skin do
			s.part.Color = s.base:Lerp(s.lit, self.lit)
		end
	end
	refreshEyes(self)
end

function Knotwalker.setAware(self: Walker, aware01: number)
	self.aware = math.clamp(aware01, 0, 1)
	refreshEyes(self)
end

function Knotwalker.setMoving(self: Walker, moving: boolean)
	self.moving = moving
end

function Knotwalker.lookAt(self: Walker, worldPosition: Vector3?)
	self.focus = worldPosition
end

function Knotwalker.strike(self: Walker)
	if self.attackT >= 0 then
		return
	end
	self.attackSide = -self.attackSide
	self.idleResetT = -1
	self.nextIdleResetAt = self.t
		+ self.rng:NextNumber(
			Threats.visuals.procedural.attackMotion.Knotwalker.idleResetMinSeconds,
			Threats.visuals.procedural.attackMotion.Knotwalker.idleResetMaxSeconds
		)
	self.attackT = 0
	self.attackLanded = false
	self.pendingImpact = false
end

function Knotwalker.consumeImpact(self: Walker): boolean
	if self.pendingImpact then
		self.pendingImpact = false
		return true
	end
	return false
end

function Knotwalker.consumeFootfall(self: Walker): number?
	local weight = self.pendingFootfall
	self.pendingFootfall = nil
	return weight
end

function Knotwalker.applyFamilyTint(self: Walker, color: Color3, strength: number)
	local blend = math.clamp(strength, 0, 1)
	if blend <= 0 then
		return
	end
	for _, s in self.skin do
		s.base = s.base:Lerp(color, blend)
		s.lit = s.lit:Lerp(color, blend)
	end
	self.lastPaintedIllumination = nil
	Knotwalker.setIllumination(self, self.lit)
end

function Knotwalker.applyFamilyDressing(self: Walker, dressing: CreatureDressing.Dressing, seed: number)
	CreatureDressing.apply(dressing, self.dressAnchors, seed)
	local parts: { BasePart } = {}
	for _, s in self.skin do
		table.insert(parts, s.part)
	end
	CreatureDressing.applySkinMaterial(dressing, parts)
end

local function smoothstep(value: number): number
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end

function Knotwalker.step(self: Walker, dt: number)
	self.t += dt

	local position = self.root.Position
	local last = self.lastPos
	if last ~= nil and dt > 0 then
		self.speed = math.min((position - last).Magnitude / dt, GAIT_MAX_MEASURED_SPEED)
	end
	self.lastPos = position

	local motion = Threats.visuals.procedural.attackMotion.Knotwalker
	local anticipationProgress = 0
	local strikeRaw = 0
	local strikeProgress = 0
	local recoveryRaw = 0
	local recoveryProgress = 0
	local actionWeight = 0
	local bodyY = 0
	local bodyZ = 0
	local bodyPitch = 0
	if self.attackT >= 0 then
		self.attackT += dt
		local anticipationEnd = motion.anticipationSeconds
		local strikeEnd = anticipationEnd + motion.strikeSeconds
		local total = strikeEnd + motion.recoverySeconds
		local time = math.min(self.attackT, total)
		if time < anticipationEnd then
			anticipationProgress = smoothstep(time / anticipationEnd)
			actionWeight = anticipationProgress
			bodyY = motion.torsoRiseStuds * anticipationProgress
			bodyZ = motion.torsoReachStuds * 0.2 * anticipationProgress
			bodyPitch = math.rad(-motion.shoulderCollapseDegrees * 0.22 * anticipationProgress)
		elseif time < strikeEnd then
			strikeRaw = (time - anticipationEnd) / motion.strikeSeconds
			strikeProgress = smoothstep(strikeRaw)
			actionWeight = 1
			bodyY = motion.torsoRiseStuds * (1 - strikeProgress * 0.55)
			bodyZ = motion.torsoReachStuds * (0.2 - 1.2 * strikeProgress)
			bodyPitch = math.rad(motion.shoulderCollapseDegrees * 0.55 * strikeProgress)
		else
			recoveryRaw = (time - strikeEnd) / motion.recoverySeconds
			recoveryProgress = smoothstep(recoveryRaw)
			actionWeight = 1 - recoveryProgress
			bodyY = motion.torsoRiseStuds * 0.45 * (1 - recoveryProgress)
			bodyZ = -motion.torsoReachStuds * (1 - recoveryProgress)
			bodyPitch = math.rad(
				motion.shoulderCollapseDegrees * 0.55 * (1 - recoveryProgress)
					- motion.shoulderCollapseDegrees * 0.35 * math.sin(recoveryRaw * math.pi)
			)
		end

		local impactAt = anticipationEnd + motion.strikeSeconds * motion.impactFraction
		if not self.attackLanded and self.attackT >= impactAt then
			self.attackLanded = true
			self.pendingImpact = true
		end
		if self.attackT >= total then
			self.attackT = -1
			self.strike = 0
		else
			self.strike = actionWeight
		end
		refreshEyes(self)
	end
	PartKit.pose(
		self.bodyJoint,
		CFrame.new(0, bodyY, bodyZ) * CFrame.Angles(bodyPitch, math.rad(self.attackSide * 5 * actionWeight), 0)
	)

	-- A slow, one-sided joint reset breaks the perpetual mirrored idle without reading as another
	-- attack. It only starts between actions and its entire interval/envelope lives in config.
	if self.attackT < 0 and self.idleResetT < 0 and self.t >= self.nextIdleResetAt then
		self.idleResetT = 0
		self.idleResetSide = if self.rng:NextInteger(0, 1) == 0 then -1 else 1
	end
	local resetWeight = 0
	if self.idleResetT >= 0 then
		self.idleResetT += dt
		local progress = math.clamp(self.idleResetT / motion.idleResetSeconds, 0, 1)
		resetWeight = math.sin(progress * math.pi)
		if progress >= 1 then
			self.idleResetT = -1
			self.nextIdleResetAt = self.t + self.rng:NextNumber(motion.idleResetMinSeconds, motion.idleResetMaxSeconds)
		end
	end

	-- THE REACH. Arms extend and fingers spread as it commits; both fold in when it has nothing. This
	-- is the body language a player is meant to read the interception off — and it deliberately leads
	-- the movement, so the reach appears before the creature has finished arriving.
	local targetReach = 0.12 + self.aware * 0.88
	self.reach += (targetReach - self.reach) * math.min(1, dt * 2.8)

	local focus = self.focus
	local targetYaw = 0
	if focus ~= nil then
		local flat = Vector3.new(focus.X - position.X, 0, focus.Z - position.Z)
		if flat.Magnitude > 0.05 then
			local forward = self.root.CFrame.LookVector
			targetYaw =
				math.clamp(math.atan2(flat.Unit:Cross(forward).Y, -flat.Unit:Dot(forward)), -math.rad(64), math.rad(64))
		end
	else
		targetYaw = math.sin(self.t * 0.55) * math.rad(20)
	end
	self.headYaw += (targetYaw - self.headYaw) * math.min(1, dt * 5)
	PartKit.pose(self.headJoint, CFrame.Angles(math.rad(-6), self.headYaw, 0))

	-- A narrow body sways rather than bobs. The lean rides the gait so it reads as weight shifting
	-- through the hips instead of the whole model rocking.
	local cadence = 2.4 + math.clamp(self.speed / GAIT_REFERENCE_SPEED, 0, 2.2) * 3.2
	local baseStride = if self.moving then math.clamp(self.speed / GAIT_REFERENCE_SPEED, 0.25, 1.3) else 0.1
	local stride = baseStride * (1 - motion.plantedGaitSuppression * actionWeight)
	local previousPhase = self.gaitPhase
	self.gaitPhase += dt * cadence
	local sway = math.sin(self.gaitPhase) * 0.06 * stride
	for index, joint in self.spine do
		local actionBend = bodyPitch * (if index == 1 then 0.34 else 0.52)
		PartKit.pose(joint, CFrame.Angles(math.rad(4 - index * 2) + actionBend, 0, sway * (index == 1 and 1 or 0.6)))
	end

	for _, leg in self.legs do
		local phase = self.gaitPhase + (if leg.side < 0 then 0 else math.pi)
		local swing = math.sin(phase) * stride * 0.5
		PartKit.pose(leg.upper, CFrame.Angles(swing, 0, 0))
		PartKit.pose(leg.lower, CFrame.Angles(-math.abs(swing) * 0.75, 0, 0))
	end
	if self.moving then
		local crossed = math.floor((previousPhase + math.pi / 2) / math.pi)
			~= math.floor((self.gaitPhase + math.pi / 2) / math.pi)
		if crossed then
			self.pendingFootfall = math.clamp(stride, 0, 1)
		end
	end

	for _, arm in self.arms do
		local phase = self.gaitPhase + (if arm.side < 0 then math.pi else 0)
		local walkSwing = math.sin(phase) * stride * 0.26
		local armStrike = strikeProgress
		if arm.side ~= self.attackSide and strikeRaw > 0 then
			-- One hand reaches first; the second follows by a small fraction of the strike rather
			-- than mirroring it on the same frame.
			armStrike = smoothstep((strikeRaw - motion.leadHandFraction) / (1 - motion.leadHandFraction))
		end
		local attackPitch = math.rad(motion.armDrawDegrees) * anticipationProgress
		if strikeRaw > 0 then
			attackPitch = math.rad(motion.armDrawDegrees)
				+ math.rad(-motion.armReachDegrees - motion.armDrawDegrees) * armStrike
		elseif recoveryRaw > 0 then
			attackPitch = math.rad(-motion.armReachDegrees) * (1 - recoveryProgress)
				+ math.rad(motion.handDragDegrees * arm.side * self.attackSide) * math.sin(recoveryRaw * math.pi)
		end
		local reset = if arm.side == self.idleResetSide then math.rad(motion.idleResetDegrees) * resetWeight else 0
		local reachPose = self.reach * 0.34
		local collapse = math.rad(motion.shoulderCollapseDegrees) * math.sin(recoveryRaw * math.pi)
		PartKit.pose(
			arm.upper,
			CFrame.Angles(walkSwing - reachPose + attackPitch + reset, 0, arm.side * collapse * 0.35)
		)
		PartKit.pose(arm.lower, CFrame.Angles(-0.5 + reachPose * 0.7 - attackPitch * 0.58 - reset * 0.7, 0, 0))
		local spread = self.reach * 0.5 + actionWeight * (0.35 + armStrike * 0.28)
		for fingerIndex, finger in arm.fingers do
			local fingerLag = if fingerIndex == 2 then 0.88 else 1
			PartKit.pose(finger, CFrame.Angles(-spread * 0.6 * fingerLag, math.rad((fingerIndex - 2) * 12) * spread, 0))
		end
	end
end

function Knotwalker.destroy(self: Walker)
	self.model:Destroy()
end

return Knotwalker

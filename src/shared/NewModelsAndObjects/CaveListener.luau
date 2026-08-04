--!strict
-- CAVE LISTENER — Stone's signature dark-hunter. A thing built entirely around hearing.
-- Place at: ReplicatedStorage/Creatures/CaveListener
--
-- THE SILHOUETTE IS THE MECHANIC. Everything else on the roster is built around a head that looks at
-- you; this one has no eyes at all in the usual place. It carries an enormous flattened skull low and
-- forward, almost dragging, with two broad membranous ear fans spread off the sides of it — and it
-- moves on four limbs whose hips sit high above the shoulders, so the whole body slopes down into the
-- listening end. At a distance you read a wedge nosing along the floor, not a person.
--
-- THE CATEGORY TELL IS PRESERVED, JUST RELOCATED. A player judges a threat by its eyes: crimson,
-- narrow, angled means dark-hunter. This creature has that exact tell — same colour, same ~20 degree
-- angle, same faint glow, same brightening as it closes — running along the JAW LINE of the flattened
-- skull instead of sitting in a brow. So it is unmistakably a hunter at range and unmistakably not a
-- crawler, which is precisely the pair of facts the player needs.
--
-- THE EARS DO THE TALKING. The fans are hinged and they MOVE: slack and folded while it is drifting,
-- swept forward and taut the moment it has heard something. That is the animation carrying the state
-- a player most needs — "it is coming to look at a noise" versus "it has not noticed anything" — and
-- it is readable long before the crimson is.
--
-- Nothing here collides, queries or touches. Wax, contact, perception and AI are the server's.

local CollectionService = game:GetService("CollectionService")
local PartKit = require(script.Parent.PartKit)
local CreatureDressing = require(script.Parent.CreatureDressing)

local CaveListener = {}
CaveListener.__index = CaveListener

-- Near-black, never pure black: falloff has to resolve an edge instead of a hole. Matched to the
-- crawler's ramp so the two read as the same kind of thing made differently.
local SKIN_DARK = Color3.fromRGB(11, 11, 14)
local SKIN_PALE = Color3.fromRGB(29, 27, 28)
local SKIN_MATERIAL = Enum.Material.Slate
local BONE_MATERIAL = Enum.Material.Concrete
local BONE = Color3.fromRGB(40, 37, 33)
-- The ear membrane. Lighter than the body and slightly translucent so a flame behind one shows the
-- ribbing through it — the one place on this creature light passes through rather than dying.
local MEMBRANE = Color3.fromRGB(34, 31, 32)
local LIT_TARGET = Color3.fromRGB(74, 69, 63)
local LIT_MIX = 0.44

-- Identical to the crawler's, deliberately: crimson at rest, hotter as it closes.
local EYE_IDLE = Color3.fromRGB(128, 16, 10)
local EYE_LOCKED = Color3.fromRGB(255, 46, 30)
local EYE_ANGLE = 20

-- Proportions. Total height at the hip is 3.1 — lower than a crawler's 6.0 at the crown, which is the
-- point: this thing does not tower, it creeps.
local HIP_HEIGHT = 3.1
local SHOULDER_HEIGHT = 2.35
local BODY_LEN = 2.5
local FORE_UPPER, FORE_LOWER = 1.05, 1.15
local HIND_UPPER, HIND_LOWER = 1.35, 1.4
local LIMB_D = 0.3

local EAR_LEN = 1.25
local EAR_RIBS = 4

local GAIT_REFERENCE_SPEED = 8
local GAIT_MAX_MEASURED_SPEED = 24

type Skinned = { part: BasePart, base: Color3, lit: Color3 }
type Limb = { upper: PartKit.Joint, lower: PartKit.Joint, side: number, front: boolean }

export type Listener = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		hitbox: BasePart,
		limbs: { Limb },
		skin: { Skinned },
		dressAnchors: { CreatureDressing.Anchor },
		eyes: { BasePart },
		halos: { BasePart },
		ears: { PartKit.Joint },
		neck: PartKit.Joint,
		skullJoint: PartKit.Joint,
		t: number,
		lit: number,
		aware: number,
		moving: boolean,
		focus: Vector3?,
		speed: number,
		lastPos: Vector3?,
		headYaw: number,
		scanPhase: number,
		earSpread: number,
		gaitPhase: number,
		pendingFootfall: number?,
		attackT: number,
		attackLanded: boolean,
		pendingImpact: boolean,
		strike: number,
	},
	{} :: typeof({ __index = CaveListener })
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

local function refreshEyes(self: Listener)
	local heat = math.max(self.aware, self.strike)
	local color = PartKit.lerpColor(EYE_IDLE, EYE_LOCKED, 0.25 + heat * 0.75)
	local wash = self.lit * 0.5
	for _, eye in self.eyes do
		eye.Color = color
		eye.Transparency = wash
	end
	for _, halo in self.halos do
		halo.Color = color
		halo.Transparency = math.clamp(0.66 + self.lit * 0.3 - heat * 0.24, 0, 1)
	end
end

-- One limb: upper segment, lower segment, and a splayed foot. The fore pair are shorter and set
-- wider than the hind pair, which is what tips the whole body forward and down.
local function buildLimb(
	model: Model,
	skin: { Skinned },
	anchors: { CreatureDressing.Anchor },
	host: BasePart,
	side: number,
	front: boolean
): Limb
	local upperLen = if front then FORE_UPPER else HIND_UPPER
	local lowerLen = if front then FORE_LOWER else HIND_LOWER
	local lateral = if front then 0.46 else 0.38
	local along = if front then -BODY_LEN * 0.34 else BODY_LEN * 0.36

	local upper = tube(model, skin, "Upper", upperLen, LIMB_D, 0.26)
	local jointUpper = PartKit.joint(
		host,
		upper,
		CFrame.new(side * lateral, -0.12, along)
			* CFrame.Angles(0, math.rad(side * 8), 0)
			-- Splayed outward rather than tucked under: a low creature stands on a wide base.
			* CFrame.Angles(math.rad(-72), 0, math.rad(side * 16)),
		PartKit.tubePivot(upperLen)
	)

	local lower = tube(model, skin, "Lower", lowerLen, LIMB_D * 0.82, 0.18)
	local jointLower = PartKit.joint(
		upper,
		lower,
		PartKit.tubeTip(upperLen) * CFrame.Angles(math.rad(-38), 0, 0),
		PartKit.tubePivot(lowerLen)
	)

	local foot = blob(model, skin, "Foot", Vector3.new(0.34, 0.13, 0.5), 0.1, false)
	PartKit.joint(lower, foot, PartKit.tubeTip(lowerLen) * CFrame.Angles(math.rad(70), 0, 0), CFrame.new(0, 0.03, 0.16))

	-- Limbs collect on their outer faces; only the foot's upper surface is somewhere frost settles.
	table.insert(anchors, { part = upper, normal = Vector3.new(0, side, 0), scale = 0.8, upward = false })
	table.insert(anchors, { part = foot, normal = Vector3.yAxis, scale = 0.55, upward = true })

	return { upper = jointUpper, lower = jointLower, side = side, front = front }
end

-- The ear fan: a hinged spine with ribs fanning off it and a membrane stretched between. Built along
-- the head's local X so a single joint rotation sweeps the whole fan forward.
local function buildEar(model: Model, skin: { Skinned }, skull: BasePart, side: number): PartKit.Joint
	local spine = tube(model, skin, "EarSpine", EAR_LEN, 0.09, 0.2)
	local hinge = PartKit.joint(
		skull,
		spine,
		CFrame.new(side * 0.3, 0.14, 0.08) * CFrame.Angles(0, math.rad(side * 52), math.rad(side * -18)),
		PartKit.tubePivot(EAR_LEN)
	)

	for rib = 1, EAR_RIBS do
		local along = EAR_LEN * (rib / (EAR_RIBS + 1)) - EAR_LEN / 2
		local span = 0.62 * (1 - math.abs(rib - (EAR_RIBS + 1) / 2) / EAR_RIBS)
		local membrane = PartKit.ellipsoid(model, {
			name = "EarMembrane",
			size = Vector3.new(0.05, span * 1.6, span * 1.5),
			color = MEMBRANE,
			material = Enum.Material.Fabric,
			transparency = 0.28,
			castShadow = false,
		})
		PartKit.joint(spine, membrane, CFrame.new(along, 0, 0))
		track(skin, membrane, MEMBRANE)
	end

	return hinge
end

function CaveListener.build(parent: Instance): Listener
	local model = Instance.new("Model")
	model.Name = "CaveListener"
	local skin: { Skinned } = {}
	local anchors: { CreatureDressing.Anchor } = {}

	-- The hip block is the root: it is the highest point of the body and the thing the whole slope
	-- hangs off, so anchoring here keeps the creature's height honest whatever the head is doing.
	local hips = blob(model, skin, "Hips", Vector3.new(0.86, 0.7, 0.92), 0.3)

	local spine = blob(model, skin, "Spine", Vector3.new(0.78, 0.62, BODY_LEN * 0.7), 0.34)
	PartKit.joint(hips, spine, CFrame.new(0, -0.16, -BODY_LEN * 0.34) * CFrame.Angles(math.rad(-11), 0, 0))

	-- A visible ridge of vertebrae down the slope. Free surface interest at the exact angle a candle
	-- sweeping the body catches first.
	for i = 1, 5 do
		local bead = PartKit.ellipsoid(model, {
			name = "Vertebra",
			size = Vector3.new(0.13, 0.16, 0.13),
			color = BONE,
			material = BONE_MATERIAL,
			castShadow = false,
		})
		PartKit.joint(spine, bead, CFrame.new(0, 0.3 - i * 0.012, BODY_LEN * 0.28 - (i - 1) * (BODY_LEN * 0.16)))
		track(skin, bead, BONE)
	end

	local shoulders = blob(model, skin, "Shoulders", Vector3.new(0.94, 0.6, 0.8), 0.38)
	PartKit.joint(spine, shoulders, CFrame.new(0, -(HIP_HEIGHT - SHOULDER_HEIGHT) * 0.5, -BODY_LEN * 0.44))

	local neckSeg = tube(model, skin, "Neck", 0.6, 0.34, 0.22)
	local neck = PartKit.joint(
		shoulders,
		neckSeg,
		CFrame.new(0, -0.1, -0.44) * CFrame.Angles(math.rad(-96), 0, 0),
		PartKit.tubePivot(0.6)
	)

	-- THE SKULL. Wide, flat and long — a spade rather than a head. Nothing on its top surface, because
	-- the ears own that silhouette and a brow would compete with them.
	local skull = blob(model, skin, "Skull", Vector3.new(1.05, 0.34, 1.15), 0.4)
	local skullJoint = PartKit.joint(neckSeg, skull, PartKit.tubeTip(0.6) * CFrame.Angles(math.rad(84), 0, 0))

	local ears: { PartKit.Joint } = {}
	local eyes: { BasePart } = {}
	local halos: { BasePart } = {}
	for _, side in { -1, 1 } do
		table.insert(ears, buildEar(model, skin, skull, side))

		-- THE CATEGORY TELL, on the jaw line. Angled at the same ~20 degrees as every other
		-- dark-hunter's, so the shape a player has learned to fear is the shape they see here.
		local halo = PartKit.neon(model, {
			name = "Halo",
			size = Vector3.new(0.34, 0.1, 0.08),
			color = EYE_IDLE,
			transparency = 0.7,
		})
		PartKit.joint(
			skull,
			halo,
			CFrame.new(side * 0.34, -0.1, -0.4) * CFrame.Angles(0, 0, math.rad(side * EYE_ANGLE))
		)
		table.insert(halos, halo)

		local slit = PartKit.neon(model, {
			name = "Eye",
			size = Vector3.new(0.28, 0.055, 0.05),
			color = EYE_IDLE,
		})
		PartKit.joint(
			skull,
			slit,
			CFrame.new(side * 0.34, -0.1, -0.43) * CFrame.Angles(0, 0, math.rad(side * EYE_ANGLE))
		)
		table.insert(eyes, slit)
	end

	-- A low, wide mouth along the underside. Never opens far: this creature listens, it does not roar.
	local jaw = blob(model, skin, "Jaw", Vector3.new(0.9, 0.2, 0.95), 0.24, false)
	PartKit.joint(skull, jaw, CFrame.new(0, -0.2, 0.04))

	local limbs: { Limb } = {}
	for _, side in { -1, 1 } do
		table.insert(limbs, buildLimb(model, skin, anchors, shoulders, side, true))
	end
	for _, side in { -1, 1 } do
		table.insert(limbs, buildLimb(model, skin, anchors, hips, side, false))
	end

	-- The back is the only torso surface offered: the skull and its ears are refused in every family.
	table.insert(anchors, { part = hips, normal = Vector3.yAxis, scale = 1.05, upward = true, allowStrand = true })
	table.insert(anchors, { part = spine, normal = Vector3.yAxis, scale = 1, upward = true, allowStrand = false })
	table.insert(anchors, { part = shoulders, normal = Vector3.yAxis, scale = 0.95, upward = true, allowStrand = true })

	local hitbox = PartKit.hitbox(model, hips, Vector3.new(1.5, 3.2, 3.6), CFrame.new(0, -0.4, -0.6))

	PartKit.finalise(model, hips, true)
	CollectionService:AddTag(model, "Creature")
	CollectionService:AddTag(model, "DarkHunter")
	model:SetAttribute("FleesLight", true)
	model:SetAttribute("HuntsByHearing", true)
	model.Parent = parent

	local self = setmetatable({
		model = model,
		root = hips,
		hitbox = hitbox,
		limbs = limbs,
		skin = skin,
		dressAnchors = anchors,
		eyes = eyes,
		halos = halos,
		ears = ears,
		neck = neck,
		skullJoint = skullJoint,
		t = 0,
		lit = 0,
		aware = 0,
		moving = false,
		focus = nil,
		speed = 0,
		lastPos = nil,
		headYaw = 0,
		scanPhase = 0,
		earSpread = 0,
		gaitPhase = 0,
		pendingFootfall = nil,
		attackT = -1,
		attackLanded = true,
		pendingImpact = false,
		strike = 0,
	}, CaveListener)

	refreshEyes(self)
	return self
end

function CaveListener.setIllumination(self: Listener, lit01: number)
	self.lit = math.clamp(lit01, 0, 1)
	for _, s in self.skin do
		s.part.Color = s.base:Lerp(s.lit, self.lit)
	end
	refreshEyes(self)
end

function CaveListener.setAware(self: Listener, aware01: number)
	self.aware = math.clamp(aware01, 0, 1)
	refreshEyes(self)
end

function CaveListener.setMoving(self: Listener, moving: boolean)
	self.moving = moving
end

function CaveListener.lookAt(self: Listener, worldPosition: Vector3?)
	self.focus = worldPosition
end

function CaveListener.strike(self: Listener)
	self.attackT = 0
	self.attackLanded = false
end

function CaveListener.consumeImpact(self: Listener): boolean
	if self.pendingImpact then
		self.pendingImpact = false
		return true
	end
	return false
end

function CaveListener.consumeFootfall(self: Listener): number?
	local weight = self.pendingFootfall
	self.pendingFootfall = nil
	return weight
end

function CaveListener.applyFamilyTint(self: Listener, color: Color3, strength: number)
	local blend = math.clamp(strength, 0, 1)
	if blend <= 0 then
		return
	end
	for _, s in self.skin do
		s.base = s.base:Lerp(color, blend)
		s.lit = s.lit:Lerp(color, blend)
	end
	CaveListener.setIllumination(self, self.lit)
end

function CaveListener.applyFamilyDressing(self: Listener, dressing: CreatureDressing.Dressing, seed: number)
	CreatureDressing.apply(dressing, self.dressAnchors, seed)
	local parts: { BasePart } = {}
	for _, s in self.skin do
		-- The ear membranes keep Fabric whatever the family's rock is: they are the one surface on this
		-- body a flame passes through, and turning them to stone would cost the creature its read.
		if s.part.Name ~= "EarMembrane" then
			table.insert(parts, s.part)
		end
	end
	CreatureDressing.applySkinMaterial(dressing, parts)
end

function CaveListener.step(self: Listener, dt: number)
	self.t += dt

	local position = self.root.Position
	local last = self.lastPos
	if last ~= nil and dt > 0 then
		local measured = (position - last).Magnitude / dt
		self.speed = math.min(measured, GAIT_MAX_MEASURED_SPEED)
	end
	self.lastPos = position

	-- THE EARS. Slack and folded back while nothing has its attention; swept forward and taut as
	-- awareness rises. This is the readable state change on this body, and it is deliberately much
	-- larger and slower than the eye brightening so it carries at a distance the crimson does not.
	local targetSpread = 0.15 + self.aware * 0.85
	self.earSpread += (targetSpread - self.earSpread) * math.min(1, dt * 3.4)
	for index, ear in self.ears do
		local side = if index == 1 then -1 else 1
		-- A slow independent quiver per side, so the two fans never look mechanically linked.
		local quiver = math.sin(self.t * (2.6 + index * 0.4)) * 0.05 * (1 - self.aware * 0.5)
		PartKit.pose(
			ear,
			CFrame.Angles(0, math.rad(side * -46 * self.earSpread), math.rad(side * (14 * self.earSpread + quiver)))
		)
	end

	-- THE SCAN. With nothing to chase it sweeps the head across the ground in front of it; with a
	-- focus it holds that direction instead. A listening creature that stared straight ahead forever
	-- would read as broken rather than as blind.
	local focus = self.focus
	local targetYaw: number
	if focus ~= nil then
		local toFocus = focus - position
		local flat = Vector3.new(toFocus.X, 0, toFocus.Z)
		if flat.Magnitude > 0.05 then
			local forward = self.root.CFrame.LookVector
			targetYaw =
				math.clamp(math.atan2(flat.Unit:Cross(forward).Y, -flat.Unit:Dot(forward)), -math.rad(58), math.rad(58))
		else
			targetYaw = 0
		end
	else
		self.scanPhase += dt * (0.5 + self.aware * 0.8)
		targetYaw = math.sin(self.scanPhase) * math.rad(34)
	end
	self.headYaw += (targetYaw - self.headYaw) * math.min(1, dt * 4)
	PartKit.pose(self.skullJoint, CFrame.Angles(0, self.headYaw, 0))
	-- The neck dips as the body settles and lifts as it rouses: the head is lowest when it is calm,
	-- which is the opposite of every other creature here and reads as listening TO THE GROUND.
	PartKit.pose(self.neck, CFrame.Angles(math.rad(-8 + self.aware * 13), self.headYaw * 0.3, 0))

	-- THE GAIT. Four limbs on two diagonals. Cadence follows measured ground speed, so a creeping
	-- body's legs actually creep and a committed one's actually run.
	local cadence = 2.1 + math.clamp(self.speed / GAIT_REFERENCE_SPEED, 0, 2.4) * 3.6
	local stride = if self.moving then math.clamp(self.speed / GAIT_REFERENCE_SPEED, 0.25, 1.35) else 0.12
	local previousPhase = self.gaitPhase
	self.gaitPhase += dt * cadence
	for index, limb in self.limbs do
		-- Diagonal pairs: fore-left with hind-right.
		local diagonal = if (limb.front and limb.side < 0) or (not limb.front and limb.side > 0) then 0 else math.pi
		local phase = self.gaitPhase + diagonal
		local swing = math.sin(phase) * stride * 0.42
		local lift = math.max(0, math.cos(phase)) * stride * 0.3
		PartKit.pose(limb.upper, CFrame.Angles(swing, 0, 0))
		PartKit.pose(limb.lower, CFrame.Angles(-math.abs(swing) * 0.6 - lift, 0, 0))

		-- A foot plant is the frame this limb's phase crosses the bottom of its arc. Reported rather
		-- than played here: the controller owns audio, this body owns when.
		if index == 1 and self.moving then
			local crossed = math.floor((previousPhase + math.pi / 2) / math.pi)
				~= math.floor((self.gaitPhase + math.pi / 2) / math.pi)
			if crossed then
				self.pendingFootfall = math.clamp(stride, 0, 1)
			end
		end
	end

	-- THE STRIKE. A short forward lunge of the whole head — the spade slams down. Its impact frame is
	-- latched once so the sound of the blow lands with the blow.
	if self.attackT >= 0 then
		self.attackT += dt
		local duration = 0.72
		local progress = math.clamp(self.attackT / duration, 0, 1)
		-- Windup back, then a fast drive forward, then recovery.
		local envelope = if progress < 0.32
			then -math.sin(progress / 0.32 * math.pi * 0.5) * 0.4
			else math.sin((progress - 0.32) / 0.68 * math.pi) * 1.15
		self.strike = math.clamp(math.abs(envelope), 0, 1)
		PartKit.pose(self.neck, CFrame.Angles(math.rad(-8 + self.aware * 13) + envelope * 0.8, self.headYaw * 0.3, 0))
		if not self.attackLanded and progress >= 0.46 then
			self.attackLanded = true
			self.pendingImpact = true
		end
		if progress >= 1 then
			self.attackT = -1
			self.strike = 0
		end
		refreshEyes(self)
	end
end

function CaveListener.destroy(self: Listener)
	self.model:Destroy()
end

return CaveListener

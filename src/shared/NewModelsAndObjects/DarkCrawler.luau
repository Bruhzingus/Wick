--!strict
-- DarkCrawler — the dark-hunter. A human-sized figure that is almost, but not, a person.
-- Place at: ReplicatedStorage/Creatures/DarkCrawler
--
-- Proportions are the tell. 6.0 studs total: 3.6 of leg from hip to floor, 2.4 of
-- torso and head above it. A 60/40 split against a human's roughly 50/50 reads as
-- long-legged and short-bodied — recognisably a person, wrongly assembled.
--
-- Everything is round. Limbs are cylinders capped with spheres of matching
-- diameter at every joint, so a chain reads as one smooth capsule rather than a
-- stack of boxes, and carry a muscle mass so they are not broom handles. Torso,
-- skull, jaw, hands and feet are ellipsoids via PartKit.ellipsoid — a Ball part
-- is always a perfect sphere however you size it. No hard edges except the teeth.
--
-- Skin is ONE colour ramp and ONE material. Tone is a per-role constant, so a
-- limb shades along its length and the left side always matches the right.
--
-- Limb chains hang off PartKit.tubeTip. See the note there: chaining a tube at
-- -length/2 folds the next segment back up over its parent.
--
-- Part count: 86 with DETAIL on, 67 with it off.

local CollectionService = game:GetService("CollectionService")
local PartKit = require(script.Parent.PartKit)

local DarkCrawler = {}
DarkCrawler.__index = DarkCrawler

-- Near-black, never pure black: falloff has to resolve an edge instead of a hole.
local SKIN_DARK = Color3.fromRGB(10, 10, 13)
local SKIN_PALE = Color3.fromRGB(27, 25, 26)
local SKIN_MATERIAL = Enum.Material.Slate
local BONE_MATERIAL = Enum.Material.Concrete
local LIT_TARGET = Color3.fromRGB(78, 72, 65)
local LIT_MIX = 0.46

-- Tone: 0 is the deepest skin, 1 the palest. Extremities run dark and the mass
-- nearest a light runs pale, which is how a body reads at the edge of a flame.
local TONE = {
	pelvis = 0.34,
	waist = 0.30,
	chest = 0.44,
	yoke = 0.38,
	neck = 0.24,
	skull = 0.48,
	brow = 0.32,
	jaw = 0.40,
	thigh = 0.26,
	shin = 0.17,
	foot = 0.10,
	upper = 0.30,
	fore = 0.21,
	hand = 0.12,
	digit = 0.07,
}

local PRESSURE = Color3.fromRGB(38, 35, 31)
local SOCKET = Color3.fromRGB(3, 3, 4)
local TOOTH = Color3.fromRGB(132, 126, 112)
local EYE_IDLE = Color3.fromRGB(128, 16, 10)
local EYE_LOCKED = Color3.fromRGB(255, 46, 30)

local SHADOW_DETAIL = true
local DETAIL = true

-- 60% legs. Thigh + shin + ankle = 3.60.
local THIGH, SHIN = 1.78, 1.62
local THIGH_D, SHIN_D = 0.32, 0.24
local UPPER, FORE, HAND = 1.30, 1.32, 0.30
local UPPER_D, FORE_D = 0.26, 0.205

-- 40% torso and head. Pelvis centre 3.72, crown 5.98.
local SPINE_PLAN = {
	{ name = "Waist", w = 0.50, h = 0.60, d = 0.38, at = 0.44, tone = TONE.waist },
	{ name = "Chest", w = 0.92, h = 0.80, d = 0.54, at = 0.56, tone = TONE.chest },
	{ name = "Neck", w = 0.22, h = 0.34, d = 0.22, at = 0.52, tone = TONE.neck },
}

local SOUNDS = { skitter = "", hiss = "" }

local FLINCH = 0.35
local HEAD_YAW_LIMIT = math.rad(74)
local HEAD_PITCH_LIMIT = math.rad(32)

-- Stride follows measured ground speed rather than a fixed cadence, so the feet
-- stop scrubbing when the body is barely moving and the legs do not moonwalk
-- when it sprints. The cap ignores the teleport on the frame a body is built.
local GAIT_REFERENCE_SPEED = 9
local GAIT_MAX_MEASURED_SPEED = 26

-- Attack: one shot, three beats. Coil pulls everything back and opens the jaw,
-- strike whips it through, recover eases out. Contact lands on the strike.
local ATTACK_COIL = 0.20
local ATTACK_STRIKE = 0.14
local ATTACK_RECOVER = 0.52
local ATTACK_TOTAL = ATTACK_COIL + ATTACK_STRIKE + ATTACK_RECOVER

export type Skinned = { part: BasePart, base: Color3, lit: Color3 }
export type Limb = { a: PartKit.Joint, b: PartKit.Joint, c: PartKit.Joint, side: number }

export type Crawler = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		hitbox: BasePart,
		legs: { Limb },
		arms: { Limb },
		spine: { PartKit.Joint },
		skin: { Skinned },
		eyes: { BasePart },
		halos: { BasePart },
		headJoint: PartKit.Joint,
		jaw: PartKit.Joint,
		skitter: Sound?,
		hiss: Sound?,
		t: number,
		gaitSpeed: number,
		lit: number,
		aware: number,
		wasLit: boolean,
		moving: boolean,
		focus: Vector3?,
		headYaw: number,
		headPitch: number,
		jawOpen: number,
		lastYaw: number,
		yawRate: number,
		idleAt: number,
		idleYaw: number,
		speed: number,
		lastPos: Vector3?,
		attackT: number,
		attackKind: string,
		attackSide: number,
		strike: number,
		strikeShown: number,
		-- AUDIO EVENTS THE ANIMATION PRODUCES, each consumed exactly once by whoever is driving this
		-- body. They are derived from the gait and attack envelopes rather than from a timer, so a
		-- footstep can only ever fire on the frame a foot actually reaches the ground and a strike
		-- sound can only ever fire on the frame the arm actually arrives. A stalking crawler moving
		-- its legs slowly is quiet because its legs ARE slow, not because something separately
		-- decided it should be.
		gaitPhase: number,
		pendingFootfall: number?,
		attackLanded: boolean,
		pendingImpact: boolean,
	},
	DarkCrawler
))

local function skinColor(tone: number): Color3
	return SKIN_DARK:Lerp(SKIN_PALE, math.clamp(tone, 0, 1))
end

local function track(skin: { Skinned }, p: BasePart, base: Color3): BasePart
	table.insert(skin, { part = p, base = base, lit = base:Lerp(LIT_TARGET, LIT_MIX) })
	return p
end

-- Round mass: torso segment, skull, jaw, hand, foot, muscle belly.
local function blob(
	model: Model,
	skin: { Skinned },
	name: string,
	size: Vector3,
	tone: number,
	shadow: boolean?
): BasePart
	local c = skinColor(tone)
	return track(
		skin,
		PartKit.ellipsoid(model, {
			name = name,
			size = size,
			color = c,
			material = SKIN_MATERIAL,
			castShadow = if shadow ~= nil then shadow else true,
		}),
		c
	)
end

local function tube(
	model: Model,
	skin: { Skinned },
	name: string,
	len: number,
	dia: number,
	tone: number,
	shadow: boolean?
): BasePart
	local c = skinColor(tone)
	return track(skin, PartKit.tube(model, name, len, dia, c, SKIN_MATERIAL, shadow), c)
end

-- Joint sphere, sized to the limb it caps. This is what removes the seams.
-- `pale` is for a bone pressing through: knee, ankle, elbow, wrist.
local function knuckle(
	model: Model,
	skin: { Skinned },
	host: BasePart,
	at: CFrame,
	dia: number,
	tone: number,
	pale: boolean?
): BasePart
	local c = if pale then PRESSURE else skinColor(tone)
	local p = PartKit.part(model, {
		name = "Joint",
		size = Vector3.one * dia,
		shape = Enum.PartType.Ball,
		color = c,
		material = if pale then BONE_MATERIAL else SKIN_MATERIAL,
		castShadow = false,
	})
	PartKit.joint(host, p, at)
	return track(skin, p, c)
end

local function boneRod(model: Model, skin: { Skinned }, name: string, len: number, dia: number): BasePart
	local p = PartKit.tube(model, name, len, dia, PRESSURE, BONE_MATERIAL, false)
	return track(skin, p, PRESSURE)
end

-- Depth of an ellipsoid torso segment's surface at height y, sunk by `inset`.
-- Bone detail placed here is half-buried in the skin instead of floating off it
-- at the ends of the segment, where an ellipsoid has curved away.
local function shellDepth(halfHeight: number, halfDepth: number, y: number, inset: number): number
	local t = math.clamp(y / halfHeight, -1, 1)
	return halfDepth * math.sqrt(1 - t * t) - inset
end

local function refreshEyes(self: Crawler)
	local heat = math.max(self.aware, self.strike)
	local c = PartKit.lerpColor(EYE_IDLE, EYE_LOCKED, 0.25 + heat * 0.75)
	local wash = self.lit * 0.5
	for _, e in self.eyes do
		e.Color = c
		e.Transparency = wash
	end
	for _, h in self.halos do
		h.Color = c
		h.Transparency = math.clamp(0.62 + self.lit * 0.32 - heat * 0.26, 0, 1)
	end
	self.strikeShown = self.strike
end

local function buildLeg(model: Model, skin: { Skinned }, pelvis: BasePart, side: number): Limb
	local hipAt = CFrame.new(side * 0.26, -0.10, 0)
	knuckle(model, skin, pelvis, hipAt, THIGH_D * 1.18, TONE.pelvis)

	local thigh = tube(model, skin, "Thigh", THIGH, THIGH_D, TONE.thigh, SHADOW_DETAIL)
	local jt = PartKit.joint(
		pelvis,
		thigh,
		hipAt * CFrame.Angles(0, math.rad(side * 3), 0) * CFrame.Angles(math.rad(-88), 0, 0),
		PartKit.tubePivot(THIGH)
	)

	if DETAIL then
		-- Quadriceps belly. A bare cylinder is a broom handle; this gives the thigh
		-- a mass up top that tapers away toward the knee.
		local quad =
			blob(model, skin, "Quad", Vector3.new(THIGH_D * 1.30, THIGH_D * 1.26, THIGH * 0.66), TONE.thigh, false)
		PartKit.joint(thigh, quad, CFrame.new(-THIGH * 0.12, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
	end

	local shin = tube(model, skin, "Shin", SHIN, SHIN_D, TONE.shin, SHADOW_DETAIL)
	local js =
		PartKit.joint(thigh, shin, PartKit.tubeTip(THIGH) * CFrame.Angles(math.rad(-7), 0, 0), PartKit.tubePivot(SHIN))
	-- Knee caps the thigh/shin seam, so it takes the thigh's diameter.
	knuckle(model, skin, shin, CFrame.new(-SHIN / 2, 0, 0), THIGH_D * 1.02, TONE.thigh)

	if DETAIL then
		local calf = blob(model, skin, "Calf", Vector3.new(SHIN_D * 1.24, SHIN_D * 1.34, SHIN * 0.54), TONE.shin, false)
		PartKit.joint(shin, calf, CFrame.new(-SHIN * 0.16, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
		knuckle(model, skin, shin, CFrame.new(SHIN / 2, 0, 0), SHIN_D * 1.16, TONE.shin, true)
	end

	local foot = blob(model, skin, "Foot", Vector3.new(0.26, 0.15, 0.66), TONE.foot, SHADOW_DETAIL)
	local jf =
		PartKit.joint(shin, foot, PartKit.tubeTip(SHIN) * CFrame.Angles(math.rad(95), 0, 0), CFrame.new(0, 0.04, 0.21))

	for i = 1, 3 do
		local toe = tube(model, skin, "Toe", 0.20, 0.066, TONE.digit, false)
		PartKit.joint(
			foot,
			toe,
			CFrame.new((i - 2) * 0.075, -0.012, -0.29) * CFrame.Angles(math.rad(-9), math.rad((i - 2) * 9), 0),
			PartKit.tubePivot(0.20)
		)
	end

	return { a = jt, b = js, c = jf, side = side }
end

local function buildArm(model: Model, skin: { Skinned }, chest: BasePart, side: number): Limb
	local shoulderAt = CFrame.new(side * 0.44, 0.24, 0)
	if DETAIL then
		local delt = blob(model, skin, "Deltoid", Vector3.new(0.34, 0.32, 0.32), TONE.chest, false)
		PartKit.joint(chest, delt, CFrame.new(side * 0.44, 0.26, 0))
	end

	local upper = tube(model, skin, "Upper", UPPER, UPPER_D, TONE.upper, SHADOW_DETAIL)
	local ju = PartKit.joint(
		chest,
		upper,
		shoulderAt * CFrame.Angles(0, math.rad(side * 6), 0) * CFrame.Angles(math.rad(-84), 0, 0),
		PartKit.tubePivot(UPPER)
	)

	if DETAIL then
		local bicep =
			blob(model, skin, "Bicep", Vector3.new(UPPER_D * 1.22, UPPER_D * 1.20, UPPER * 0.56), TONE.upper, false)
		PartKit.joint(upper, bicep, CFrame.new(-UPPER * 0.14, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
	end

	local fore = tube(model, skin, "Forearm", FORE, FORE_D, TONE.fore, SHADOW_DETAIL)
	local jf =
		PartKit.joint(upper, fore, PartKit.tubeTip(UPPER) * CFrame.Angles(math.rad(8), 0, 0), PartKit.tubePivot(FORE))
	knuckle(model, skin, fore, CFrame.new(-FORE / 2, 0, 0), UPPER_D * 1.04, TONE.upper)

	if DETAIL then
		knuckle(model, skin, fore, CFrame.new(FORE / 2, 0, 0), FORE_D * 1.14, TONE.fore, true)
	end

	local hand = blob(model, skin, "Hand", Vector3.new(0.21, 0.09, HAND), TONE.hand, false)
	local jh =
		PartKit.joint(fore, hand, PartKit.tubeTip(FORE) * CFrame.Angles(math.rad(6), 0, 0), CFrame.new(0, 0, HAND / 2))

	for i = 1, 3 do
		local len = 0.42 - math.abs(i - 2) * 0.07
		local fing = tube(model, skin, "Finger", len, 0.048, TONE.digit, false)
		PartKit.joint(
			hand,
			fing,
			CFrame.new((i - 2) * 0.066, 0, -HAND / 2) * CFrame.Angles(math.rad(10), math.rad((i - 2) * 12), 0),
			PartKit.tubePivot(len)
		)
	end
	local thumb = tube(model, skin, "Thumb", 0.26, 0.05, TONE.digit, false)
	PartKit.joint(
		hand,
		thumb,
		CFrame.new(side * 0.09, 0, -0.03) * CFrame.Angles(math.rad(24), math.rad(side * 52), 0),
		PartKit.tubePivot(0.26)
	)

	return { a = ju, b = jf, c = jh, side = side }
end

function DarkCrawler.build(parent: Instance): Crawler
	local model = Instance.new("Model")
	model.Name = "DarkCrawler"
	local skin: { Skinned } = {}

	local pelvis = blob(model, skin, "Pelvis", Vector3.new(0.72, 0.52, 0.46), TONE.pelvis)

	if DETAIL then
		for _, s in { -1, 1 } do
			local crest = PartKit.ellipsoid(model, {
				name = "HipCrest",
				size = Vector3.new(0.14, 0.26, 0.32),
				color = PRESSURE,
				material = BONE_MATERIAL,
				castShadow = false,
			})
			PartKit.joint(pelvis, crest, CFrame.new(s * 0.30, 0.13, 0) * CFrame.Angles(0, 0, math.rad(s * 14)))
			track(skin, crest, PRESSURE)
		end
	end

	-- Spine segments hinge at their own base, not their centre, so a hunch bends
	-- the torso instead of opening a gap at every seam.
	local spine: { PartKit.Joint } = {}
	local prev: BasePart = pelvis
	local waist: BasePart = pelvis
	local chest: BasePart = pelvis
	for _, s in SPINE_PLAN do
		local seg = blob(model, skin, s.name, Vector3.new(s.w, s.h, s.d), s.tone)
		table.insert(spine, PartKit.joint(prev, seg, CFrame.new(0, s.at - s.h / 2, 0), CFrame.new(0, -s.h / 2, 0)))
		prev = seg
		if s.name == "Waist" then
			waist = seg
		elseif s.name == "Chest" then
			chest = seg
		end
	end

	local chestHalfHeight = SPINE_PLAN[2].h / 2
	local chestHalfDepth = SPINE_PLAN[2].d / 2
	local waistHalfHeight = SPINE_PLAN[1].h / 2
	local waistHalfDepth = SPINE_PLAN[1].d / 2

	-- Shoulder yoke. Without it a 0.22 neck steps straight out of a 0.92 chest.
	local yoke = blob(model, skin, "Yoke", Vector3.new(0.66, 0.30, 0.40), TONE.yoke)
	PartKit.joint(chest, yoke, CFrame.new(0, 0.34, 0.04))

	-- Ribs as thin rods rather than slabs. Rounder, and they catch a rim of
	-- light along their length instead of flashing a flat face. Each runs across
	-- the chest (the rod lies along the joint's X) and rides the chest surface,
	-- so a rib is a ridge under skin rather than a bar hanging in front of it.
	for i = 1, 4 do
		local y = 0.25 - (i - 1) * 0.17
		local rib = boneRod(model, skin, "Rib" .. i, 0.80 - (i - 1) * 0.085, 0.068)
		PartKit.joint(chest, rib, CFrame.new(0, y, -shellDepth(chestHalfHeight, chestHalfDepth, y, 0.012)))
	end
	for _, s in { -1, 1 } do
		local cl = boneRod(model, skin, "Clavicle", 0.42, 0.07)
		PartKit.joint(chest, cl, CFrame.new(s * 0.23, 0.34, -0.17) * CFrame.Angles(0, 0, math.rad(s * -12)))
	end

	if DETAIL then
		for i = 1, 3 do
			local y = 0.20 - (i - 1) * 0.19
			local v = PartKit.part(model, {
				name = "VertW" .. i,
				size = Vector3.one * 0.10,
				shape = Enum.PartType.Ball,
				color = PRESSURE,
				material = BONE_MATERIAL,
				castShadow = false,
			})
			PartKit.joint(waist, v, CFrame.new(0, y, shellDepth(waistHalfHeight, waistHalfDepth, y, 0.03)))
			track(skin, v, PRESSURE)
		end
		for i = 1, 4 do
			local y = 0.28 - (i - 1) * 0.18
			local v = PartKit.part(model, {
				name = "VertC" .. i,
				size = Vector3.one * 0.11,
				shape = Enum.PartType.Ball,
				color = PRESSURE,
				material = BONE_MATERIAL,
				castShadow = false,
			})
			PartKit.joint(chest, v, CFrame.new(0, y, shellDepth(chestHalfHeight, chestHalfDepth, y, 0.03)))
			track(skin, v, PRESSURE)
		end
	end

	local skull = blob(model, skin, "Skull", Vector3.new(0.46, 0.72, 0.58), TONE.skull)
	local headJoint = PartKit.joint(prev, skull, CFrame.new(0, 0.38, -0.02))

	local brow = blob(model, skin, "Brow", Vector3.new(0.46, 0.15, 0.26), TONE.brow, true)
	PartKit.joint(skull, brow, CFrame.new(0, 0.12, -0.20) * CFrame.Angles(math.rad(18), 0, 0))

	local nasal = PartKit.ellipsoid(model, {
		name = "Nasal",
		size = Vector3.new(0.12, 0.17, 0.13),
		color = SOCKET,
		material = Enum.Material.SmoothPlastic,
		castShadow = false,
	})
	PartKit.joint(skull, nasal, CFrame.new(0, -0.13, -0.25))

	-- Eyes sit deep in a socket with a wide dim halo behind them. The halo is what
	-- makes them read as burning rather than as two red dots.
	local eyes: { BasePart } = {}
	local halos: { BasePart } = {}
	for _, s in { -1, 1 } do
		local sock = PartKit.ellipsoid(model, {
			name = "Socket",
			size = Vector3.new(0.30, 0.32, 0.28),
			color = SOCKET,
			material = Enum.Material.SmoothPlastic,
			castShadow = false,
		})
		PartKit.joint(skull, sock, CFrame.new(s * 0.135, 0.005, -0.17))

		local halo = PartKit.neon(model, {
			name = "Halo",
			size = Vector3.one * 0.25,
			shape = Enum.PartType.Ball,
			color = EYE_IDLE,
			transparency = 0.68,
		})
		PartKit.joint(skull, halo, CFrame.new(s * 0.135, 0.005, -0.235))
		table.insert(halos, halo)

		local e = PartKit.neon(model, {
			name = "Eye",
			size = Vector3.one * 0.145,
			shape = Enum.PartType.Ball,
			color = EYE_IDLE,
		})
		PartKit.joint(skull, e, CFrame.new(s * 0.135, 0.005, -0.26))
		table.insert(eyes, e)

		local cheek = PartKit.ellipsoid(model, {
			name = "Cheek",
			size = Vector3.new(0.12, 0.28, 0.17),
			color = PRESSURE,
			material = BONE_MATERIAL,
			castShadow = false,
		})
		PartKit.joint(
			skull,
			cheek,
			CFrame.new(s * 0.20, -0.15, -0.12) * CFrame.Angles(0, math.rad(s * 18), math.rad(s * 10))
		)
		track(skin, cheek, PRESSURE)
	end

	local upperJaw = blob(model, skin, "UpperJaw", Vector3.new(0.36, 0.18, 0.33), TONE.jaw, true)
	PartKit.joint(skull, upperJaw, CFrame.new(0, -0.26, -0.14))

	-- The jaw hinges behind the cheek like a jaw, not about its own middle.
	local lowerJaw = blob(model, skin, "LowerJaw", Vector3.new(0.33, 0.21, 0.36), TONE.jaw, true)
	local jaw = PartKit.joint(skull, lowerJaw, CFrame.new(0, -0.24, 0.08), CFrame.new(0, 0.07, 0.13))

	for i = 1, 5 do
		local x = (i - 3) * 0.066
		for _, row in { { host = upperJaw, y = -0.07, dir = -88 }, { host = lowerJaw, y = 0.09, dir = 88 } } do
			local t = PartKit.tube(model, "Tooth", 0.13, 0.036, TOOTH, Enum.Material.Glass, false)
			t.Reflectance = 0.16
			PartKit.joint(
				row.host,
				t,
				CFrame.new(x, row.y, -0.06) * CFrame.Angles(math.rad(row.dir), 0, 0),
				PartKit.tubePivot(0.13)
			)
		end
	end

	local legs: { Limb } = {}
	local arms: { Limb } = {}
	for _, sd in { -1, 1 } do
		table.insert(legs, buildLeg(model, skin, pelvis, sd))
	end
	for _, sd in { -1, 1 } do
		table.insert(arms, buildArm(model, skin, chest, sd))
	end

	local hitbox = PartKit.hitbox(model, pelvis, Vector3.new(1.3, 5.9, 1.1), CFrame.new(0, 1.1, 0))

	PartKit.finalise(model, pelvis, true)
	CollectionService:AddTag(model, "Creature")
	CollectionService:AddTag(model, "DarkHunter")
	model:SetAttribute("FleesLight", true)
	model.Parent = parent

	local skitter: Sound? = nil
	local hiss: Sound? = nil
	if SOUNDS.skitter ~= "" then
		skitter = PartKit.emitter(
			pelvis,
			SOUNDS.skitter,
			{ name = "Skitter", looped = true, volume = 0.45, minDistance = 6, maxDistance = 55 }
		).sound
	end
	if SOUNDS.hiss ~= "" then
		hiss =
			PartKit.emitter(pelvis, SOUNDS.hiss, { name = "Hiss", volume = 0.7, minDistance = 10, maxDistance = 80 }).sound
	end

	local self = setmetatable({
		model = model,
		root = pelvis,
		hitbox = hitbox,
		legs = legs,
		arms = arms,
		spine = spine,
		skin = skin,
		eyes = eyes,
		halos = halos,
		headJoint = headJoint,
		jaw = jaw,
		skitter = skitter,
		hiss = hiss,
		t = 0,
		gaitSpeed = 3.8,
		lit = 0,
		aware = 0,
		wasLit = false,
		moving = false,
		focus = nil,
		headYaw = 0,
		headPitch = 0,
		jawOpen = 0,
		lastYaw = 0,
		yawRate = 0,
		idleAt = 3,
		idleYaw = 0,
		speed = 0,
		lastPos = nil,
		attackT = -1,
		attackKind = "Lunge",
		attackSide = 1,
		strike = 0,
		strikeShown = 0,
		gaitPhase = 0,
		pendingFootfall = nil,
		attackLanded = true,
		pendingImpact = false,
	}, DarkCrawler)

	refreshEyes(self)
	return self
end

function DarkCrawler.setIllumination(self: Crawler, lit01: number)
	local lit = math.clamp(lit01, 0, 1)
	self.lit = lit
	for _, s in self.skin do
		s.part.Color = s.base:Lerp(s.lit, lit)
	end
	refreshEyes(self)

	if lit > FLINCH and not self.wasLit then
		self.wasLit = true
		if self.hiss then
			self.hiss:Play()
		end
	elseif lit <= FLINCH * 0.6 then
		self.wasLit = false
	end
end

-- Cave-family dressing. Blends this body's SKIN toward the family's hue and nothing else: the eye
-- parts and their halos live in `self.eyes` rather than `self.skin`, so the crimson dark-hunter eyes
-- that tell a player what is coming at them are structurally untouchable from here.
--
-- Applied to the tracked base AND lit colours together, because `setIllumination` rewrites every skin
-- part from those two every frame — tinting the parts directly would be erased on the next tick.
function DarkCrawler.applyFamilyTint(self: Crawler, color: Color3, strength: number)
	local blend = math.clamp(strength, 0, 1)
	if blend <= 0 then
		return
	end
	for _, s in self.skin do
		s.base = s.base:Lerp(color, blend)
		s.lit = s.lit:Lerp(color, blend)
	end
	DarkCrawler.setIllumination(self, self.lit)
end

function DarkCrawler.setAware(self: Crawler, aware01: number)
	self.aware = math.clamp(aware01, 0, 1)
	refreshEyes(self)
end

function DarkCrawler.lookAt(self: Crawler, worldPosition: Vector3?)
	self.focus = worldPosition
end

function DarkCrawler.setMoving(self: Crawler, moving: boolean)
	self.moving = moving
	if self.skitter then
		if moving and self.lit < 0.9 then
			if not self.skitter.IsPlaying then
				self.skitter:Play()
			end
		else
			self.skitter:Stop()
		end
	end
end

-- Begin one attack. "Swipe" is a single arm arcing across the body; "Lunge" is
-- both arms and a bite. Alternates by default so repeat hits never look looped.
-- A call during a wind-up is ignored rather than snapping the pose back to zero.
function DarkCrawler.strike(self: Crawler, kind: string?)
	if self.attackT >= 0 and self.attackT < ATTACK_COIL + ATTACK_STRIKE then
		return
	end
	self.attackT = 0
	self.attackKind = kind or (if self.attackKind == "Swipe" then "Lunge" else "Swipe")
	self.attackSide = -self.attackSide
	self.attackLanded = false
	if self.hiss and self.lit < 0.9 then
		self.hiss:Play()
	end
end

function DarkCrawler.isAttacking(self: Crawler): boolean
	return self.attackT >= 0
end

-- One foot reaching the ground, consumed. Returns how much weight went into it (0..1, the gait's own
-- `active` term) or nil if no foot has landed since the last call. Weight is the whole point: it
-- folds in speed, whether the body is moving at all, whether a candle is on it, and whether it is
-- mid-swing — so the same call describes a silent creep and a full charge without a caller having to
-- know the difference.
function DarkCrawler.consumeFootfall(self: Crawler): number?
	local weight = self.pendingFootfall
	self.pendingFootfall = nil
	return weight
end

-- The frame an attack actually arrives — the end of the wind-up, not the start of it. Consumed once
-- per swing, so the sound of a blow landing lands with the blow.
function DarkCrawler.consumeImpact(self: Crawler): boolean
	local landed = self.pendingImpact
	self.pendingImpact = false
	return landed
end

-- coil rises through the wind-up and is spent by the end of the strike; thrust
-- takes over for the strike itself and decays across the recovery.
local function attackEnvelopes(elapsed: number): (number, number)
	if elapsed < ATTACK_COIL then
		local u = elapsed / ATTACK_COIL
		return u * u * (3 - 2 * u), 0
	elseif elapsed < ATTACK_COIL + ATTACK_STRIKE then
		local u = (elapsed - ATTACK_COIL) / ATTACK_STRIKE
		return 1 - u, u * u
	end
	local u = math.clamp((elapsed - ATTACK_COIL - ATTACK_STRIKE) / ATTACK_RECOVER, 0, 1)
	local fall = 1 - u
	return 0, fall * fall
end

function DarkCrawler.step(self: Crawler, dt: number)
	local coil, thrust = 0, 0
	if self.attackT >= 0 then
		self.attackT += dt
		-- The wind-up is over: the arm is now travelling. Latched rather than compared per frame so a
		-- long frame that skips straight past the coil still reports exactly one impact.
		if not self.attackLanded and self.attackT >= ATTACK_COIL then
			self.attackLanded = true
			self.pendingImpact = true
		end
		if self.attackT >= ATTACK_TOTAL then
			self.attackT = -1
		else
			coil, thrust = attackEnvelopes(self.attackT)
		end
	end
	local attack = math.max(coil, thrust)
	self.strike = attack

	-- Ground speed drives both stride length and cadence.
	local pos = self.root.Position
	local previous = self.lastPos
	self.lastPos = pos
	if previous ~= nil and dt > 0 then
		local measured = Vector3.new(pos.X - previous.X, 0, pos.Z - previous.Z).Magnitude / dt
		if measured <= GAIT_MAX_MEASURED_SPEED then
			self.speed += (measured - self.speed) * math.min(dt * 7, 1)
		end
	end

	local drive = if self.moving then math.clamp(self.speed / GAIT_REFERENCE_SPEED, 0.3, 1.5) else 0.16
	local active = (1 - self.lit) * drive * (1 - attack * 0.65)
	self.t += dt * self.gaitSpeed * active

	-- The two legs run half a cycle apart and each one's lift is `max(sin(phase), 0)`, so a foot
	-- reaches the ground every time the gait crosses a multiple of pi. Reading the plant off the same
	-- number that poses the leg is what keeps a footstep and the leg it belongs to in sync at any
	-- speed, including through the slow-down an attack forces on the gait.
	local gaitPhase = self.t / math.pi
	if math.floor(gaitPhase) > math.floor(self.gaitPhase) then
		self.pendingFootfall = math.clamp(active, 0, 1)
	end
	self.gaitPhase = gaitPhase

	local _, yaw = self.root.CFrame:ToOrientation()
	local dYaw = yaw - self.lastYaw
	if dYaw > math.pi then
		dYaw -= math.pi * 2
	elseif dYaw < -math.pi then
		dYaw += math.pi * 2
	end
	self.lastYaw = yaw
	local rate = if dt > 0 then dYaw / dt else 0
	self.yawRate += (rate - self.yawRate) * math.min(dt * 6, 1)

	local hunch = self.lit
	local guard = hunch * math.rad(52)
	local swipe = if self.attackKind == "Swipe" then 1 else 0
	local lunge = 1 - swipe

	-- Long legs want a long slow stride. Knee folds backward only. The attack
	-- crouches on the coil and drives the hips through on the strike.
	local crouchHip = coil * math.rad(15) - thrust * math.rad(9)
	local crouchKnee = -coil * math.rad(30) + thrust * math.rad(16)
	local crouchAnkle = coil * math.rad(14) - thrust * math.rad(8)
	for i, leg in self.legs do
		local p = self.t + (if i == 1 then 0 else math.pi)
		local lift = math.max(math.sin(p), 0)
		local sweep = -math.cos(p)
		PartKit.pose(leg.a, CFrame.Angles(math.rad(sweep * 22 * active) + hunch * math.rad(14) + crouchHip, 0, 0))
		PartKit.pose(leg.b, CFrame.Angles(math.rad(-lift * 50 * active) - hunch * math.rad(26) + crouchKnee, 0, 0))
		PartKit.pose(
			leg.c,
			CFrame.Angles(math.rad(lift * 28 * active - sweep * 10 * active) + hunch * math.rad(12) + crouchAnkle, 0, 0)
		)
	end

	for i, arm in self.arms do
		local phase = if i == 1 then 1 else -1
		local swing = math.sin(self.t) * phase
		local lead = if arm.side == self.attackSide then 1 else 0

		-- Shoulder: pitch swings the arm fore/aft, the middle term abducts it out
		-- to the side. A swipe throws the leading arm wide and drags it across.
		local pitch = -coil * math.rad(52 * lunge + 34 * swipe * lead + 18 * swipe * (1 - lead))
			+ thrust * math.rad(74 * lunge + 30 * swipe * lead + 12 * swipe * (1 - lead))
		local abduct = -arm.side
			* (
				coil * (math.rad(20) * lunge + math.rad(66) * swipe * lead)
				- thrust * (math.rad(8) * lunge + math.rad(78) * swipe * lead)
			)
		PartKit.pose(
			arm.a,
			CFrame.Angles(math.rad(swing * 20 * active) + guard * 0.55 + pitch, abduct, math.rad(phase * hunch * -18))
		)
		-- Elbow cocks hard on the coil and snaps almost straight on the strike.
		PartKit.pose(
			arm.b,
			CFrame.Angles(
				math.rad(math.abs(swing) * 16 * active)
					+ guard * 1.5
					+ coil * math.rad(64 + 14 * lead)
					- thrust * math.rad(34),
				0,
				0
			)
		)
		PartKit.pose(
			arm.c,
			CFrame.Angles(math.rad(swing * 8 * active) - coil * math.rad(22) + thrust * math.rad(30), 0, 0)
		)
	end

	local sway = math.clamp(-self.yawRate * 0.14, -0.4, 0.4)
	local bob = math.sin(self.t * 2) * 0.035 * active
	local attackPitch = -coil * math.rad(11) + thrust * math.rad(27)
	local attackTwist = swipe * self.attackSide * (coil * math.rad(16) - thrust * math.rad(28))
	for i, j in self.spine do
		local w = i / #self.spine
		PartKit.pose(
			j,
			CFrame.Angles(
				bob * w - hunch * math.rad(13) * w + attackPitch * w,
				sway * w + attackTwist * w,
				sway * w * 0.3
			)
		)
	end

	-- Jaw hangs open on the coil and snaps shut through the strike: a bite.
	local goalJaw = 0.10 + self.aware * 0.72 + self.lit * 0.35
	if self.aware > 0.5 then
		goalJaw += math.sin(self.t * 14) * 0.06 * self.aware
	end
	goalJaw = math.max(goalJaw, coil * 1.3)
	self.jawOpen += (goalJaw - self.jawOpen) * math.min(dt * (8 + attack * 30), 1)
	PartKit.pose(self.jaw, CFrame.Angles(-self.jawOpen * math.rad(46), 0, 0))

	local goalYaw, goalPitch = 0, 0
	if self.focus then
		local rel = self.root.CFrame:PointToObjectSpace(self.focus)
		goalYaw = math.clamp(math.atan2(-rel.X, -rel.Z), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
		local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
		-- Positive head pitch tips the face up, so a target below has to read negative.
		goalPitch = math.clamp(math.atan2(rel.Y - 1.6, flat), -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT)
	else
		if self.t > self.idleAt then
			self.idleAt = self.t + 2 + math.random() * 4
			self.idleYaw = (math.random() - 0.5) * HEAD_YAW_LIMIT * 1.5
		end
		goalYaw = self.idleYaw
	end

	local trackRate = math.min(dt * (2.4 + self.aware * 8), 1)
	self.headYaw += (goalYaw - self.headYaw) * trackRate
	self.headPitch += (goalPitch - self.headPitch) * trackRate
	PartKit.pose(
		self.headJoint,
		CFrame.Angles(
			self.headPitch + hunch * math.rad(20) + coil * math.rad(15) - thrust * math.rad(24),
			self.headYaw - attackTwist * 0.6,
			self.headYaw * -0.2
		)
	)

	if math.abs(self.strike - self.strikeShown) > 0.04 then
		refreshEyes(self)
	end
end

function DarkCrawler.moveTo(self: Crawler, position: Vector3, dt: number, speed: number)
	local cur = self.root.Position
	local delta = position - cur
	if delta.Magnitude < 0.05 then
		self:setMoving(false)
		return
	end
	self:setMoving(true)
	local goal = cur + delta.Unit * math.min(speed * dt, delta.Magnitude)
	self.root.CFrame = CFrame.lookAt(goal, goal + delta.Unit)
end

function DarkCrawler.destroy(self: Crawler)
	self.model:Destroy()
end

return DarkCrawler

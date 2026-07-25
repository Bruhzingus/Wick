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
-- stack of boxes. Torso, skull and jaw are ellipsoids. No hard edges anywhere
-- except the teeth.
--
-- Part count: 84 with DETAIL on, 62 with it off.

local CollectionService = game:GetService("CollectionService")
local PartKit = require(script.Parent.PartKit)

local DarkCrawler = {}
DarkCrawler.__index = DarkCrawler

local SKIN = {
	Color3.fromRGB(14, 14, 17),
	Color3.fromRGB(20, 18, 16),
	Color3.fromRGB(10, 11, 15),
	Color3.fromRGB(23, 21, 19),
}
local SKIN_MAT = {
	Enum.Material.Slate,
	Enum.Material.Basalt,
	Enum.Material.Concrete,
	Enum.Material.Pebble,
}
local PRESSURE = Color3.fromRGB(38, 35, 31)
local LIT_TARGET = Color3.fromRGB(78, 72, 65)
local LIT_MIX = 0.46

local SOCKET = Color3.fromRGB(3, 3, 4)
local TOOTH = Color3.fromRGB(132, 126, 112)
local MARK = Color3.fromRGB(96, 128, 150)
local EYE_IDLE = Color3.fromRGB(128, 16, 10)
local EYE_LOCKED = Color3.fromRGB(255, 46, 30)

local SHADOW_DETAIL = true
local DETAIL = true

-- 60% legs. Thigh + shin + ankle = 3.60.
local THIGH, SHIN = 1.78, 1.62
local THIGH_D, SHIN_D = 0.28, 0.205
local UPPER, FORE, HAND = 1.30, 1.32, 0.28
local UPPER_D, FORE_D = 0.225, 0.175

-- 40% torso and head. Pelvis centre 3.72, crown 5.98.
local SPINE_PLAN = {
	{ name = "Waist", w = 0.50, h = 0.60, d = 0.38, at = 0.44 },
	{ name = "Chest", w = 0.92, h = 0.80, d = 0.54, at = 0.56 },
	{ name = "Neck", w = 0.22, h = 0.34, d = 0.22, at = 0.52 },
}

local SOUNDS = { skitter = "", hiss = "" }

local FLINCH = 0.35
local HEAD_YAW_LIMIT = math.rad(74)
local HEAD_PITCH_LIMIT = math.rad(32)

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
		marks: { BasePart },
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
	},
	DarkCrawler
))

local nextSkin = 0
local function track(skin: { Skinned }, p: BasePart, base: Color3): BasePart
	table.insert(skin, { part = p, base = base, lit = base:Lerp(LIT_TARGET, LIT_MIX) })
	return p
end

local function pickSkin(): (Color3, Enum.Material)
	nextSkin += 1
	return SKIN[(nextSkin - 1) % #SKIN + 1], SKIN_MAT[(nextSkin - 1) % #SKIN_MAT + 1]
end

local function blob(model: Model, skin: { Skinned }, name: string, size: Vector3, shadow: boolean?): BasePart
	local c, m = pickSkin()
	return track(
		skin,
		PartKit.part(model, {
			name = name,
			size = size,
			shape = Enum.PartType.Ball,
			color = c,
			material = m,
			castShadow = if shadow ~= nil then shadow else true,
		}),
		c
	)
end

local function tube(model: Model, skin: { Skinned }, name: string, len: number, dia: number, shadow: boolean?): BasePart
	local c, m = pickSkin()
	return track(skin, PartKit.tube(model, name, len, dia, c, m, shadow), c)
end

-- Joint sphere, sized to the limb it caps. This is what removes the seams.
local function knuckle(
	model: Model,
	skin: { Skinned },
	host: BasePart,
	at: CFrame,
	dia: number,
	pale: boolean?
): BasePart
	local c: Color3, m: Enum.Material
	if pale then
		c, m = PRESSURE, Enum.Material.Concrete
	else
		c, m = pickSkin()
	end
	local p = PartKit.part(model, {
		name = "Joint",
		size = Vector3.one * dia,
		shape = Enum.PartType.Ball,
		color = c,
		material = m,
		castShadow = false,
	})
	PartKit.joint(host, p, at)
	return track(skin, p, c)
end

local function refreshEyes(self: Crawler)
	local c = PartKit.lerpColor(EYE_IDLE, EYE_LOCKED, 0.25 + self.aware * 0.75)
	local wash = self.lit * 0.5
	for _, e in self.eyes do
		e.Color = c
		e.Transparency = wash
	end
	for _, h in self.halos do
		h.Color = c
		h.Transparency = 0.62 + self.lit * 0.32 - self.aware * 0.16
	end
end

local function buildLeg(model: Model, skin: { Skinned }, pelvis: BasePart, side: number): Limb
	knuckle(model, skin, pelvis, CFrame.new(side * 0.24, -0.12, 0), THIGH_D * 1.12)

	local thigh = tube(model, skin, "Thigh", THIGH, THIGH_D, SHADOW_DETAIL)
	local jt = PartKit.joint(
		pelvis,
		thigh,
		CFrame.new(side * 0.24, -0.12, 0) * CFrame.Angles(0, math.rad(side * 3), 0) * CFrame.Angles(math.rad(-88), 0, 0),
		PartKit.tubePivot(THIGH)
	)

	local shin = tube(model, skin, "Shin", SHIN, SHIN_D, SHADOW_DETAIL)
	local js = PartKit.joint(
		thigh,
		shin,
		CFrame.new(-THIGH / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-7), 0, 0),
		PartKit.tubePivot(SHIN)
	)
	knuckle(model, skin, shin, CFrame.new(SHIN / 2, 0, 0), THIGH_D * 1.02, DETAIL)

	if DETAIL then
		knuckle(model, skin, shin, CFrame.new(-SHIN / 2, 0, 0), SHIN_D * 1.16, true)
	end

	-- Sole. The one place a flat plane is right.
	local footC, footM = pickSkin()
	local foot = track(
		skin,
		PartKit.part(model, {
			name = "Foot",
			size = Vector3.new(0.24, 0.13, 0.62),
			shape = Enum.PartType.Ball,
			color = footC,
			material = footM,
			castShadow = SHADOW_DETAIL,
		}),
		footC
	)
	local jf = PartKit.joint(
		shin,
		foot,
		CFrame.new(-SHIN / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(95), 0, 0),
		CFrame.new(0, 0.04, 0.21)
	)

	for i = 1, 3 do
		local toe = tube(model, skin, "Toe", 0.19, 0.062, false)
		PartKit.joint(
			foot,
			toe,
			CFrame.new((i - 2) * 0.07, -0.012, -0.30) * CFrame.Angles(math.rad(88), 0, 0),
			PartKit.tubePivot(0.19)
		)
	end

	return { a = jt, b = js, c = jf, side = side }
end

local function buildArm(model: Model, skin: { Skinned }, chest: BasePart, side: number): Limb
	if DETAIL then
		local delt = blob(model, skin, "Deltoid", Vector3.new(0.30, 0.28, 0.27), false)
		PartKit.joint(chest, delt, CFrame.new(side * 0.44, 0.26, 0))
	end

	local upper = tube(model, skin, "Upper", UPPER, UPPER_D, SHADOW_DETAIL)
	local ju = PartKit.joint(
		chest,
		upper,
		CFrame.new(side * 0.44, 0.24, 0) * CFrame.Angles(0, math.rad(side * 6), 0) * CFrame.Angles(math.rad(-84), 0, 0),
		PartKit.tubePivot(UPPER)
	)

	local fore = tube(model, skin, "Forearm", FORE, FORE_D, SHADOW_DETAIL)
	local jf = PartKit.joint(
		upper,
		fore,
		CFrame.new(-UPPER / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(8), 0, 0),
		PartKit.tubePivot(FORE)
	)
	knuckle(model, skin, fore, CFrame.new(FORE / 2, 0, 0), UPPER_D * 1.04, DETAIL)

	if DETAIL then
		knuckle(model, skin, fore, CFrame.new(-FORE / 2, 0, 0), FORE_D * 1.14)
	end

	local handC, handM = pickSkin()
	local hand = track(
		skin,
		PartKit.part(model, {
			name = "Hand",
			size = Vector3.new(0.19, 0.075, HAND),
			shape = Enum.PartType.Ball,
			color = handC,
			material = handM,
			castShadow = false,
		}),
		handC
	)
	local jh = PartKit.joint(
		fore,
		hand,
		CFrame.new(-FORE / 2, 0, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(6), 0, 0),
		CFrame.new(0, 0, HAND / 2)
	)

	for i = 1, 3 do
		local len = 0.40 - math.abs(i - 2) * 0.07
		local fing = tube(model, skin, "Finger", len, 0.044, false)
		PartKit.joint(
			hand,
			fing,
			CFrame.new((i - 2) * 0.062, 0, -HAND / 2) * CFrame.Angles(math.rad(10), math.rad((i - 2) * 12), 0),
			PartKit.tubePivot(len)
		)
	end
	local thumb = tube(model, skin, "Thumb", 0.25, 0.046, false)
	PartKit.joint(
		hand,
		thumb,
		CFrame.new(side * 0.09, 0, -0.03) * CFrame.Angles(math.rad(24), math.rad(side * 52), 0),
		PartKit.tubePivot(0.25)
	)

	return { a = ju, b = jf, c = jh, side = side }
end

function DarkCrawler.build(parent: Instance): Crawler
	local model = Instance.new("Model")
	model.Name = "DarkCrawler"
	local skin: { Skinned } = {}

	local pelvis = blob(model, skin, "Pelvis", Vector3.new(0.72, 0.52, 0.46))

	if DETAIL then
		for _, s in { -1, 1 } do
			local crest = PartKit.part(model, {
				name = "HipCrest",
				size = Vector3.new(0.12, 0.24, 0.30),
				shape = Enum.PartType.Ball,
				color = PRESSURE,
				material = Enum.Material.Concrete,
				castShadow = false,
			})
			PartKit.joint(pelvis, crest, CFrame.new(s * 0.29, 0.13, 0) * CFrame.Angles(0, 0, math.rad(s * 14)))
			track(skin, crest, PRESSURE)
		end
	end

	local spine: { PartKit.Joint } = {}
	local prev: BasePart = pelvis
	local waist: BasePart = pelvis
	local chest: BasePart = pelvis
	for _, s in SPINE_PLAN do
		local seg = blob(model, skin, s.name, Vector3.new(s.w, s.h, s.d))
		table.insert(spine, PartKit.joint(prev, seg, CFrame.new(0, s.at, 0)))
		prev = seg
		if s.name == "Waist" then
			waist = seg
		elseif s.name == "Chest" then
			chest = seg
		end
	end

	-- Ribs as thin rods rather than slabs. Rounder, and they catch a rim of
	-- light along their length instead of flashing a flat face.
	for i = 1, 4 do
		local w = 0.80 - (i - 1) * 0.085
		local rib = PartKit.tube(model, "Rib" .. i, w, 0.068, PRESSURE, Enum.Material.Concrete, false)
		PartKit.joint(
			chest,
			rib,
			CFrame.new(0, 0.25 - (i - 1) * 0.17, -0.24) * CFrame.Angles(math.rad(-8 + i * 3), 0, 0),
			PartKit.tubePivot(w) * CFrame.new(0, 0, -w / 2)
		)
		track(skin, rib, PRESSURE)
	end
	for _, s in { -1, 1 } do
		local cl = PartKit.tube(model, "Clavicle", 0.42, 0.07, PRESSURE, Enum.Material.Concrete, false)
		PartKit.joint(
			chest,
			cl,
			CFrame.new(s * 0.22, 0.34, -0.14) * CFrame.Angles(0, 0, math.rad(s * -12)),
			PartKit.tubePivot(0.42) * CFrame.new(0, 0, -0.21)
		)
		track(skin, cl, PRESSURE)
	end

	if DETAIL then
		for i = 1, 3 do
			local v = PartKit.part(model, {
				name = "VertW" .. i,
				size = Vector3.one * 0.10,
				shape = Enum.PartType.Ball,
				color = PRESSURE,
				material = Enum.Material.Concrete,
				castShadow = false,
			})
			PartKit.joint(waist, v, CFrame.new(0, 0.20 - (i - 1) * 0.19, 0.18))
			track(skin, v, PRESSURE)
		end
		for i = 1, 4 do
			local v = PartKit.part(model, {
				name = "VertC" .. i,
				size = Vector3.one * 0.11,
				shape = Enum.PartType.Ball,
				color = PRESSURE,
				material = Enum.Material.Concrete,
				castShadow = false,
			})
			PartKit.joint(chest, v, CFrame.new(0, 0.28 - (i - 1) * 0.18, 0.26))
			track(skin, v, PRESSURE)
		end
	end

	local skull = blob(model, skin, "Skull", Vector3.new(0.46, 0.72, 0.58))
	local headJoint = PartKit.joint(prev, skull, CFrame.new(0, 0.38, -0.02))

	-- Brow as a flattened ellipsoid. Same overhang, no corners.
	local brow = blob(model, skin, "Brow", Vector3.new(0.46, 0.14, 0.26), true)
	PartKit.joint(skull, brow, CFrame.new(0, 0.12, -0.20) * CFrame.Angles(math.rad(18), 0, 0))

	local nasal = PartKit.part(model, {
		name = "Nasal",
		size = Vector3.new(0.12, 0.16, 0.12),
		shape = Enum.PartType.Ball,
		color = SOCKET,
		material = Enum.Material.SmoothPlastic,
		castShadow = false,
	})
	PartKit.joint(skull, nasal, CFrame.new(0, -0.13, -0.25))

	-- Eyes: nearly twice the old diameter, with a wide dim halo behind them.
	-- The halo is what makes them read as burning rather than as two red dots.
	local eyes: { BasePart } = {}
	local halos: { BasePart } = {}
	for _, s in { -1, 1 } do
		local sock = PartKit.part(model, {
			name = "Socket",
			size = Vector3.new(0.29, 0.30, 0.27),
			shape = Enum.PartType.Ball,
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

		local cheek = PartKit.part(model, {
			name = "Cheek",
			size = Vector3.new(0.11, 0.28, 0.16),
			shape = Enum.PartType.Ball,
			color = PRESSURE,
			material = Enum.Material.Concrete,
			castShadow = false,
		})
		PartKit.joint(
			skull,
			cheek,
			CFrame.new(s * 0.20, -0.15, -0.12) * CFrame.Angles(0, math.rad(s * 18), math.rad(s * 10))
		)
		track(skin, cheek, PRESSURE)
	end

	local upperJaw = blob(model, skin, "UpperJaw", Vector3.new(0.36, 0.17, 0.32), true)
	PartKit.joint(skull, upperJaw, CFrame.new(0, -0.26, -0.14))

	local lowerJaw = blob(model, skin, "LowerJaw", Vector3.new(0.33, 0.20, 0.35), true)
	local jaw = PartKit.joint(skull, lowerJaw, CFrame.new(0, -0.31, -0.05))

	for i = 1, 5 do
		local x = (i - 3) * 0.066
		for _, row in { { host = upperJaw, y = -0.07, dir = 88 }, { host = lowerJaw, y = 0.09, dir = -88 } } do
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

	local marks: { BasePart } = {}
	local markHosts = { waist, chest, skull }
	local markY = { 0.02, 0.16, -0.10 }
	for i = 1, 3 do
		local m = PartKit.neon(model, {
			name = "Mark" .. i,
			size = Vector3.one * (0.08 - (i - 1) * 0.013),
			shape = Enum.PartType.Ball,
			color = MARK,
		})
		PartKit.joint(markHosts[i], m, CFrame.new(0, markY[i], 0.24))
		table.insert(marks, m)
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
		marks = marks,
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
	for _, m in self.marks do
		m.Transparency = 0.55 + lit * 0.45
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

function DarkCrawler.step(self: Crawler, dt: number)
	local active = (1 - self.lit) * (if self.moving then 1 else 0.18)
	self.t += dt * self.gaitSpeed * active

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

	-- Long legs want a long slow stride. Knee folds backward only.
	for i, leg in self.legs do
		local p = self.t + (if i == 1 then 0 else math.pi)
		local lift = math.max(math.sin(p), 0)
		local sweep = -math.cos(p)
		PartKit.pose(leg.a, CFrame.Angles(math.rad(sweep * 22 * active) + hunch * math.rad(14), 0, 0))
		PartKit.pose(leg.b, CFrame.Angles(math.rad(-lift * 50 * active) - hunch * math.rad(26), 0, 0))
		PartKit.pose(
			leg.c,
			CFrame.Angles(math.rad(lift * 28 * active - sweep * 10 * active) + hunch * math.rad(12), 0, 0)
		)
	end

	for i, arm in self.arms do
		local sd = if i == 1 then 1 else -1
		local swing = math.sin(self.t) * sd
		PartKit.pose(arm.a, CFrame.Angles(math.rad(swing * 20 * active) - guard, 0, math.rad(sd * hunch * -18)))
		PartKit.pose(arm.b, CFrame.Angles(math.rad(math.abs(swing) * 16 * active) + guard * 1.5, 0, 0))
		PartKit.pose(arm.c, CFrame.Angles(math.rad(swing * 8 * active), 0, 0))
	end

	local sway = math.clamp(-self.yawRate * 0.14, -0.4, 0.4)
	local bob = math.sin(self.t * 2) * 0.035 * active
	for i, j in self.spine do
		local w = i / #self.spine
		PartKit.pose(j, CFrame.Angles(bob * w - hunch * math.rad(13) * w, sway * w, sway * w * 0.3))
	end

	local goalJaw = 0.10 + self.aware * 0.72 + self.lit * 0.35
	if self.aware > 0.5 then
		goalJaw += math.sin(self.t * 14) * 0.06 * self.aware
	end
	self.jawOpen += (goalJaw - self.jawOpen) * math.min(dt * 8, 1)
	PartKit.pose(self.jaw, CFrame.Angles(self.jawOpen * math.rad(46), 0, 0))

	local goalYaw, goalPitch = 0, 0
	if self.focus then
		local rel = self.root.CFrame:PointToObjectSpace(self.focus)
		goalYaw = math.clamp(math.atan2(-rel.X, -rel.Z), -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
		local flat = math.sqrt(rel.X * rel.X + rel.Z * rel.Z)
		goalPitch = math.clamp(-math.atan2(rel.Y - 1.6, flat), -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT)
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
		CFrame.Angles(self.headPitch + hunch * math.rad(20), self.headYaw, self.headYaw * -0.2)
	)
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

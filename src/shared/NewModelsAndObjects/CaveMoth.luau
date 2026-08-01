--!strict
-- CaveMoth — the drawn. A single large moth that wants your flame.
-- Place at: ReplicatedStorage/Creatures/CaveMoth
--
-- Wingspan ~4.4 studs, body ~2.2. Close to player-height across the wings, which
-- makes one of them a real encounter rather than ambience.
--
-- Visibility design: it is always heading toward light, so it is lit by whatever
-- it is hunting. The wings are translucent and warm — your own flame glows through
-- them as it closes, and at contact range it occludes what you can see. That
-- dimming is the threat made visual. Small pale fangs under the head, visible only
-- once it is close enough that seeing them does not help you.
--
-- Part count: 45. Wing shadows optional and worth it — a single moth throwing a
-- 4-stud flickering shadow across a candlelit wall is the best frame in the pack.

local CollectionService = game:GetService("CollectionService")
local PartKit = require(script.Parent.PartKit)

local CaveMoth = {}
CaveMoth.__index = CaveMoth

local BODY = Color3.fromRGB(72, 63, 53)
local BODY_LIT = Color3.fromRGB(104, 92, 76)
local FORE_C = Color3.fromRGB(142, 124, 100)
local HIND_C = Color3.fromRGB(116, 100, 80)
local RUFF = Color3.fromRGB(88, 77, 63)
local FANG = Color3.fromRGB(196, 188, 168)
local FANG_TIP = Color3.fromRGB(224, 218, 200)
-- Faint warm yellow, not the dark-hunter's crimson — a moth's eyes are a small found light, not a
-- warning. They brighten specifically with attraction (pressure), not with ambient illumination.
local EYE = Color3.fromRGB(255, 214, 120)
local EYE_ATTRACTED = Color3.fromRGB(255, 236, 168)
local EYE_TRANSPARENCY_CALM = 0.72
local EYE_TRANSPARENCY_ATTRACTED = 0.1
local HALO_TRANSPARENCY_CALM = 0.92
local HALO_TRANSPARENCY_ATTRACTED = 0.55

local BODY_LEN = 2.2
local FORE_SIZE = Vector3.new(2.05, 0.11, 1.55)
local HIND_SIZE = Vector3.new(1.42, 0.10, 1.15)

local FLUTTER_HZ = 6.5
local HIND_LAG = 0.7
local BANK_STRENGTH = 11
local BANK_MAX = math.rad(58)

local WING_SHADOWS = true

local SOUNDS = { wingbeat = "", shriek = "" }

export type Moth = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		hitbox: BasePart,
		shell: { BasePart },
		abdomen: { PartKit.Joint },
		wings: { PartKit.Joint },
		fangs: { PartKit.Joint },
		eyes: { BasePart },
		halos: { BasePart },
		antennae: { PartKit.Joint },
		wingbeat: Sound?,
		shriek: Sound?,
		target: BasePart?,
		t: number,
		lit: number,
		pressure: number,
		orbit: number,
		speed: number,
		bank: number,
		heading: Vector3,
		seed: number,
		-- One feeding lunge. `attackT` is elapsed seconds into the envelope or -1 when idle; `flash`
		-- is the eye brightening that rides it. `pendingImpact` is the frame the fangs actually close,
		-- consumed once by whoever drives this body so the sound of the bite lands with the bite.
		attackT: number,
		attackLanded: boolean,
		pendingImpact: boolean,
		flash: number,
	},
	CaveMoth
))

-- A moth's lunge is shorter and lighter than a crawler's: it is a feeding stab, not a blow. The
-- fangs gape through the coil, close through the strike, and the wings carry the recovery.
local ATTACK_COIL = 0.13
local ATTACK_STRIKE = 0.09
local ATTACK_RECOVER = 0.30
local ATTACK_TOTAL = ATTACK_COIL + ATTACK_STRIKE + ATTACK_RECOVER

-- coil rises through the wind-up and is spent by the end of the stab; thrust owns the stab itself
-- and decays across the recovery. Same shape as the crawler's, so the two bodies read as one
-- vocabulary of attack rather than two unrelated animations.
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

local function wing(
	model: Model,
	thorax: BasePart,
	size: Vector3,
	color: Color3,
	s: number,
	z: number,
	name: string
): PartKit.Joint
	local w = PartKit.part(model, {
		name = name,
		size = size,
		color = color,
		material = Enum.Material.Fabric,
		transparency = 0.34,
		castShadow = WING_SHADOWS,
	})
	return PartKit.joint(thorax, w, CFrame.new(s * 0.28, 0.11, z), CFrame.new(-s * size.X / 2, 0, 0))
end

-- Eyes brighten mostly with attraction (pressure — how hard it's currently being pulled toward a
-- flame) and only a little with ambient illumination, so a moth calmly drifting in the dark still
-- shows a faint yellow glint, and one actively closing in lights up clearly before it arrives.
local function refreshEyes(self: Moth)
	-- A lunge lights the eyes regardless of how attracted the body was a moment ago, so the thing
	-- that just bit you is unmistakably the thing that just bit you.
	local glow = math.clamp(self.pressure * 0.85 + self.lit * 0.15 + self.flash, 0, 1)
	local color = PartKit.lerpColor(EYE, EYE_ATTRACTED, math.clamp(self.pressure + self.flash, 0, 1))
	for _, e in self.eyes do
		e.Color = color
		e.Transparency = EYE_TRANSPARENCY_CALM - glow * (EYE_TRANSPARENCY_CALM - EYE_TRANSPARENCY_ATTRACTED)
	end
	for _, h in self.halos do
		h.Color = color
		h.Transparency = HALO_TRANSPARENCY_CALM - glow * (HALO_TRANSPARENCY_CALM - HALO_TRANSPARENCY_ATTRACTED)
	end
end

function CaveMoth.build(parent: Instance): Moth
	local model = Instance.new("Model")
	model.Name = "CaveMoth"

	local thorax = PartKit.part(model, {
		name = "Thorax",
		size = Vector3.new(0.86, 0.80, BODY_LEN),
		shape = Enum.PartType.Cylinder,
		color = BODY,
		material = Enum.Material.Fabric,
		castShadow = WING_SHADOWS,
	})
	thorax.CFrame = CFrame.Angles(0, math.rad(90), 0)

	local shell: { BasePart } = { thorax }
	local abdomen: { PartKit.Joint } = {}
	local prev: BasePart = thorax
	local reach = BODY_LEN / 2 + 0.34
	for i, spec in { { w = 0.74, h = 0.70, d = 0.92 }, { w = 0.54, h = 0.52, d = 0.70 } } do
		local seg = PartKit.part(model, {
			name = "Abdomen" .. i,
			size = Vector3.new(spec.w, spec.h, spec.d),
			shape = Enum.PartType.Ball,
			color = BODY,
			material = Enum.Material.Fabric,
			castShadow = false,
		})
		table.insert(abdomen, PartKit.joint(prev, seg, CFrame.new(0, -0.04, reach)))
		table.insert(shell, seg)
		prev = seg
		reach = 0.62
	end

	-- Ruff: a thick collar of scales between thorax and head. This is what
	-- separates the head from the body — without it a moth reads as one tube.
	local ruff = PartKit.part(model, {
		name = "Ruff",
		size = Vector3.new(1.02, 0.94, 0.40),
		shape = Enum.PartType.Ball,
		color = RUFF,
		material = Enum.Material.Fabric,
	})
	PartKit.joint(thorax, ruff, CFrame.new(0, 0.04, -BODY_LEN / 2 - 0.10))
	table.insert(shell, ruff)

	local head = PartKit.part(model, {
		name = "Head",
		size = Vector3.new(0.80, 0.74, 0.72),
		shape = Enum.PartType.Ball,
		color = BODY,
		material = Enum.Material.Fabric,
	})
	PartKit.joint(thorax, head, CFrame.new(0, 0.02, -BODY_LEN / 2 - 0.48))
	table.insert(shell, head)

	-- Compound eyes: large, wrapped around the sides, the way a real moth's are. A soft halo behind
	-- each eye is what sells "a small found light" rather than "two flat dots" — the same trick as
	-- the dark-hunter's eye halo, but warm yellow and driven by attraction, not menace.
	local eyes: { BasePart } = {}
	local halos: { BasePart } = {}
	for _, s in { -1, 1 } do
		local halo = PartKit.neon(model, {
			name = "EyeHalo",
			size = Vector3.new(0.30, 0.32, 0.30),
			shape = Enum.PartType.Ball,
			color = EYE,
			transparency = HALO_TRANSPARENCY_CALM,
		})
		PartKit.joint(head, halo, CFrame.new(s * 0.26, 0.05, -0.06))
		table.insert(halos, halo)

		local e = PartKit.neon(model, {
			name = "Eye",
			size = Vector3.new(0.38, 0.42, 0.40),
			shape = Enum.PartType.Ball,
			color = EYE,
			transparency = EYE_TRANSPARENCY_CALM,
		})
		PartKit.joint(head, e, CFrame.new(s * 0.26, 0.05, -0.10))
		table.insert(eyes, e)
	end

	-- Small, but shaped like fangs: three tapering segments, each curling a
	-- little further in than the last. A straight peg reads as a pin; a curve
	-- that narrows to a point reads as something meant for holding on.
	local FANG_SEG = {
		{ len = 0.17, dia = 0.085, curl = 0, color = FANG },
		{ len = 0.13, dia = 0.058, curl = 22, color = FANG },
		{ len = 0.10, dia = 0.032, curl = 30, color = FANG_TIP },
	}
	local fangs: { PartKit.Joint } = {}
	for _, s in { -1, 1 } do
		local host: BasePart = head
		local root: PartKit.Joint? = nil
		for i, spec in FANG_SEG do
			local f = PartKit.tube(model, "Fang" .. i, spec.len, spec.dia, spec.color, Enum.Material.Glass, false)
			f.Reflectance = 0.22
			local at: CFrame
			if i == 1 then
				at = CFrame.new(s * 0.13, -0.26, -0.24) * CFrame.Angles(math.rad(44), math.rad(s * 16), 0)
			else
				at = CFrame.new(-FANG_SEG[i - 1].len / 2, 0, 0)
					* CFrame.Angles(0, math.rad(90), 0)
					* CFrame.Angles(math.rad(spec.curl), math.rad(s * 7), 0)
			end
			local j = PartKit.joint(host, f, at, PartKit.tubePivot(spec.len))
			if i == 1 then
				root = j
			end
			host = f
		end
		table.insert(fangs, root :: PartKit.Joint)
	end

	local wings: { PartKit.Joint } = {
		wing(model, thorax, FORE_SIZE, FORE_C, -1, -0.22, "ForewingL"),
		wing(model, thorax, FORE_SIZE, FORE_C, 1, -0.22, "ForewingR"),
		wing(model, thorax, HIND_SIZE, HIND_C, -1, 0.56, "HindwingL"),
		wing(model, thorax, HIND_SIZE, HIND_C, 1, 0.56, "HindwingR"),
	}

	-- Feathered antennae. The barbs are the single most moth-identifying thing
	-- on the model — more than the wings, which any large insect could have.
	local antennae: { PartKit.Joint } = {}
	for _, s in { -1, 1 } do
		local shaft1 = PartKit.tube(model, "Antenna", 0.46, 0.062, BODY, Enum.Material.Fabric, false)
		local j1 = PartKit.joint(
			head,
			shaft1,
			CFrame.new(s * 0.19, 0.24, -0.26) * CFrame.Angles(math.rad(-30), math.rad(s * 24), 0),
			PartKit.tubePivot(0.46)
		)
		table.insert(antennae, j1)

		local shaft2 = PartKit.tube(model, "AntennaTip", 0.38, 0.044, BODY, Enum.Material.Fabric, false)
		PartKit.joint(
			shaft1,
			shaft2,
			CFrame.new(-0.23, 0, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-16), 0, 0),
			PartKit.tubePivot(0.38)
		)

		for i = 1, 3 do
			local along = 0.23 - (i - 1) * 0.15
			for _, bs in { -1, 1 } do
				local barb =
					PartKit.tube(model, "Barb", 0.15 - (i - 1) * 0.025, 0.026, BODY, Enum.Material.Fabric, false)
				PartKit.joint(
					shaft1,
					barb,
					CFrame.new(along, 0, 0)
						* CFrame.Angles(0, math.rad(90), 0)
						* CFrame.Angles(math.rad(64), math.rad(bs * 52), 0),
					PartKit.tubePivot(0.15 - (i - 1) * 0.025)
				)
			end
		end
	end

	local hitbox = PartKit.hitbox(model, thorax, Vector3.new(1.6, 1.4, 3.4), CFrame.new(0, 0, 0.2))

	PartKit.finalise(model, thorax, true)
	CollectionService:AddTag(model, "Creature")
	CollectionService:AddTag(model, "Drawn")
	model:SetAttribute("SeeksLight", true)
	model.Parent = parent

	local wingbeat: Sound? = nil
	local shriek: Sound? = nil
	if SOUNDS.wingbeat ~= "" then
		wingbeat = PartKit.emitter(thorax, SOUNDS.wingbeat, {
			name = "Wingbeat",
			looped = true,
			volume = 0.4,
			minDistance = 8,
			maxDistance = 70,
		}).sound
		wingbeat:Play()
	end
	if SOUNDS.shriek ~= "" then
		shriek = PartKit.emitter(thorax, SOUNDS.shriek, {
			name = "Shriek",
			volume = 0.8,
			minDistance = 12,
			maxDistance = 95,
		}).sound
	end

	local self = setmetatable({
		model = model,
		root = thorax,
		hitbox = hitbox,
		shell = shell,
		abdomen = abdomen,
		wings = wings,
		fangs = fangs,
		eyes = eyes,
		halos = halos,
		antennae = antennae,
		wingbeat = wingbeat,
		shriek = shriek,
		target = nil,
		t = 0,
		lit = 0,
		pressure = 0,
		orbit = 11,
		speed = 6,
		bank = 0,
		heading = Vector3.new(0, 0, -1),
		seed = math.random() * 1000,
		attackT = -1,
		attackLanded = true,
		pendingImpact = false,
		flash = 0,
	}, CaveMoth)

	refreshEyes(self)
	return self
end

-- Begin one feeding lunge. A call during a wind-up is ignored rather than snapping the pose back to
-- zero, so repeated contact reads as a body still working rather than a stutter.
function CaveMoth.strike(self: Moth)
	if self.attackT >= 0 and self.attackT < ATTACK_COIL + ATTACK_STRIKE then
		return
	end
	self.attackT = 0
	self.attackLanded = false
	if self.shriek then
		self.shriek:Play()
	end
end

-- The frame the fangs close, consumed once per lunge.
function CaveMoth.consumeImpact(self: Moth): boolean
	local landed = self.pendingImpact
	self.pendingImpact = false
	return landed
end

function CaveMoth.setTarget(self: Moth, target: BasePart?)
	self.target = target
end

-- Cosmetic pressure only. WICK's server-owned ThreatService decides movement and wax loss.
-- `brightness01` here is really "how strongly is it currently drawn in" (derived from its AI mode
-- — Seek is the highest), not ambient light on the body; see `setIllumination` for that.
function CaveMoth.setPressure(self: Moth, brightness01: number)
	local b = math.clamp(brightness01, 0, 1)
	local wasCalm = self.pressure < 0.55
	self.pressure = b
	self.orbit = 11 - b * 8.5
	self.speed = 5 + b * 11
	if self.wingbeat then
		self.wingbeat.Volume = 0.16 + b * 0.5
		self.wingbeat.PlaybackSpeed = 0.85 + b * 0.45
	end
	if b >= 0.55 and wasCalm and self.shriek then
		self.shriek:Play()
	end
	refreshEyes(self)
end

function CaveMoth.setIllumination(self: Moth, lit01: number)
	self.lit = math.clamp(lit01, 0, 1)
	local c = PartKit.lerpColor(BODY, BODY_LIT, self.lit)
	for _, p in self.shell do
		p.Color = c
	end
	refreshEyes(self)
end

function CaveMoth.step(self: Moth, dt: number)
	self.t += dt

	local coil, thrust = 0, 0
	if self.attackT >= 0 then
		self.attackT += dt
		-- Latched rather than compared per frame, so a long frame that skips the whole wind-up still
		-- reports exactly one bite.
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
	local flash = math.max(coil, thrust) * 0.75
	if math.abs(flash - self.flash) > 0.02 then
		self.flash = flash
		refreshEyes(self)
	end

	local p = self.t * FLUTTER_HZ
	local fore = math.sin(p)
	local hind = math.sin(p - HIND_LAG)

	-- The wings do the lunging. A moth has no shoulders to throw, so the coil pulls both pairs back
	-- and up into a held beat and the stab releases them forward — the same read a real moth gives
	-- when it commits to a landing.
	local beat = 1 + coil * 0.35 + thrust * 0.9
	local sweep = coil * 0.5 - thrust * 0.62
	PartKit.pose(self.wings[1], CFrame.Angles(0, -sweep, -fore * 1.1 * beat))
	PartKit.pose(self.wings[2], CFrame.Angles(0, sweep, fore * 1.1 * beat))
	PartKit.pose(self.wings[3], CFrame.Angles(0, -sweep * 0.7, -hind * 0.84 * beat))
	PartKit.pose(self.wings[4], CFrame.Angles(0, sweep * 0.7, hind * 0.84 * beat))

	-- The abdomen tucks under on the stab, which is what turns a hovering body into a striking one.
	local curl = math.sin(p * 0.5) * 0.09 + thrust * 0.42
	for i, j in self.abdomen do
		PartKit.pose(j, CFrame.Angles(curl * i * 0.6, 0, 0))
	end

	-- Fangs work faster the closer it gets. Antennae sweep on a slower rhythm. On a lunge the fangs
	-- gape wide through the wind-up and close through the stab, overriding the idle chew.
	local chew = math.sin(self.t * (2 + self.pressure * 9)) * (0.10 + self.pressure * 0.30)
	local gape = coil * 1.15 - thrust * 0.55
	for i, j in self.fangs do
		PartKit.pose(j, CFrame.Angles(0, (if i == 1 then -1 else 1) * (chew + gape), 0))
	end
	-- Antennae lay flat back the instant it commits: nothing about the body stays casual.
	local pin = coil * 0.55 + thrust * 0.3
	for i, j in self.antennae do
		local s = if i == 1 then -1 else 1
		PartKit.pose(
			j,
			CFrame.Angles(math.sin(self.t * 1.3 + i) * 0.14 - pin, s * (math.sin(self.t * 0.9) * 0.18 + pin * 0.5), 0)
		)
	end

	if not self.target then
		return
	end

	-- Orbits the flame on a wandering radius, tightening as it brightens. Two
	-- out-of-phase sines per axis so it never settles into a visible cycle.
	local centre = self.target.Position
	local s = self.seed
	local a = self.t * (0.55 + self.pressure * 0.7) + s
	local drift = Vector3.new(
		math.sin(a * 1.7) + math.sin(a * 0.53) * 0.6,
		math.sin(a * 2.3 + s) * 0.35 + math.sin(a * 0.31) * 0.7,
		math.cos(a * 1.3) + math.cos(a * 0.61) * 0.6
	)

	local goal = centre + drift * self.orbit
	local cur = self.root.Position
	local next_ = cur:Lerp(goal, math.min(dt * self.speed * 0.25, 1))

	local heading = goal - cur
	if heading.Magnitude < 0.01 then
		heading = self.heading
	else
		heading = heading.Unit
	end

	local turn = self.heading:Cross(heading).Y
	local goalBank = math.clamp(-turn * BANK_STRENGTH, -BANK_MAX, BANK_MAX)
	self.bank += (goalBank - self.bank) * math.min(dt * 5, 1)
	self.heading = heading

	self.root.CFrame = CFrame.lookAt(next_, next_ + heading) * CFrame.Angles(0, 0, self.bank)
end

function CaveMoth.destroy(self: Moth)
	if self.wingbeat then
		self.wingbeat:Stop()
	end
	self.model:Destroy()
end

return CaveMoth

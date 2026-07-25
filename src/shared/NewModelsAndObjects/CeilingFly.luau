--!strict
-- CeilingFly — hangs inverted, waits, drops on your head, and holds on.
-- Place at: ReplicatedStorage/Creatures/CeilingFly
--
-- Visibility design: the eyes are amber neon tuned close to candle colour. At
-- range they read as a distant flame — possibly a teammate, possibly a fixture.
-- That misread is the whole creature. They brighten as it wakes, which is the
-- only warning you get, and by then you are already underneath it.
--
-- Once latched it is a wax problem, not a combat problem: it rides your head,
-- drains, and the only answer is to burn brighter than is comfortable. Burning
-- it off costs you the thing it is stealing.
--
-- Part count: 47. Body shadows on — it is stationary, so the cost is paid once,
-- and the shadow it throws down a corridor is worth every microsecond.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local PartKit = require(script.Parent.PartKit)

local CeilingFly = {}
CeilingFly.__index = CeilingFly

-- Considerably darker than the crawler. It should be a hole in the ceiling
-- with two embers in it.
local CHITIN = Color3.fromRGB(11, 10, 10)
local CHITIN_LIT = Color3.fromRGB(34, 30, 27)
local CHITIN_BURN = Color3.fromRGB(168, 62, 18)
local BARB = Color3.fromRGB(28, 24, 21)
local TOOTH = Color3.fromRGB(96, 88, 76)
local EYE_DORMANT = Color3.fromRGB(112, 58, 14)
local EYE_ALERT = Color3.fromRGB(238, 138, 32)
local WING = Color3.fromRGB(78, 72, 64)

local COXA, FEMUR, TARSUS = 1.0, 1.45, 0.95

local ABDOMEN_PLAN = {
	{ w = 1.42, h = 1.30, d = 1.55, at = CFrame.new(0, -0.55, 1.5) },
	{ w = 1.10, h = 1.02, d = 1.25, at = CFrame.new(0, -0.10, 1.25) },
}

local LEG_PLAN = { { yaw = 42, z = -0.55 }, { yaw = 88, z = 0.15 }, { yaw = 138, z = 0.8 } }

local SOUNDS = { shift = "", launch = "", buzz = "", feed = "", screech = "" }

export type Leg = {
	coxa: PartKit.Joint,
	femur: PartKit.Joint,
	tarsus: PartKit.Joint,
	side: number,
	seed: number,
}

export type Fly = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		hitbox: BasePart,
		legs: { Leg },
		wings: { PartKit.Joint },
		mandibles: { PartKit.Joint },
		stinger: PartKit.Joint,
		eyes: { BasePart },
		shell: { BasePart },
		abdomen: { PartKit.Joint },
		shift: Sound?,
		launch: Sound?,
		buzz: Sound?,
		feed: Sound?,
		screech: Sound?,
		weld: WeldConstraint?,
		t: number,
		state: string,
		twitchAt: number,
		alert: number,
		lit: number,
		burn: number,
	},
	CeilingFly
))

local function buildLeg(model: Model, thorax: BasePart, plan: { yaw: number, z: number }, side: number): Leg
	local yaw = math.rad(plan.yaw * side)

	local coxa = PartKit.segment(model, "Coxa", COXA, 0.20, CHITIN)
	local cj = PartKit.joint(
		thorax,
		coxa,
		CFrame.new(side * 0.6, 0.25, plan.z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-72), 0, 0),
		PartKit.segmentPivot(COXA)
	)

	local femur = PartKit.segment(model, "Femur", FEMUR, 0.15, CHITIN)
	local fj = PartKit.joint(
		coxa,
		femur,
		CFrame.new(0, 0, -COXA / 2) * CFrame.Angles(math.rad(-34), 0, 0),
		PartKit.segmentPivot(FEMUR)
	)

	-- Backward-facing spur. Legs that are only smooth cylinders read as furniture.
	local spur = PartKit.segment(model, "Spur", 0.42, 0.075, BARB)
	spur.CastShadow = false
	PartKit.joint(
		femur,
		spur,
		CFrame.new(0, 0.07, 0.1) * CFrame.Angles(math.rad(-142), 0, 0),
		PartKit.segmentPivot(0.42)
	)

	local tarsus = PartKit.segment(model, "Tarsus", TARSUS, 0.10, CHITIN)
	local tj = PartKit.joint(
		femur,
		tarsus,
		CFrame.new(0, 0, -FEMUR / 2) * CFrame.Angles(math.rad(-58), 0, 0),
		PartKit.segmentPivot(TARSUS)
	)

	-- Hooked claws. These are what make "burn it off" the only option.
	for _, ds in { -1, 1 } do
		local hook = PartKit.segment(model, "Hook", 0.34, 0.062, TOOTH)
		hook.Material = Enum.Material.Glass
		hook.Reflectance = 0.18
		hook.CastShadow = false
		PartKit.joint(
			tarsus,
			hook,
			CFrame.new(0, 0, -TARSUS / 2) * CFrame.Angles(math.rad(58), math.rad(ds * 22), 0),
			PartKit.segmentPivot(0.34)
		)
	end

	return { coxa = cj, femur = fj, tarsus = tj, side = side, seed = math.random() * 100 }
end

function CeilingFly.build(parent: Instance): Fly
	local model = Instance.new("Model")
	model.Name = "CeilingFly"

	local thorax = PartKit.part(model, {
		name = "Thorax",
		size = Vector3.new(1.55, 0.95, 1.85),
		shape = Enum.PartType.Ball,
		color = CHITIN,
		material = Enum.Material.Slate,
	})

	local shell: { BasePart } = { thorax }
	local abdomenJoints: { PartKit.Joint } = {}
	local prev: BasePart = thorax
	for i, spec in ABDOMEN_PLAN do
		local seg = PartKit.part(model, {
			name = "Abdomen" .. i,
			size = Vector3.new(spec.w, spec.h, spec.d),
			shape = Enum.PartType.Ball,
			color = CHITIN,
			material = if i == 1 then Enum.Material.Slate else Enum.Material.Pebble,
		})
		table.insert(abdomenJoints, PartKit.joint(prev, seg, spec.at))
		table.insert(shell, seg)
		prev = seg
	end

	-- Ovipositor spike off the tail. Never used mechanically; it is there so the
	-- silhouette has a point on it.
	local stinger = PartKit.joint(
		prev,
		(function()
			local s = PartKit.segment(model, "Stinger", 1.15, 0.13, TOOTH)
			s.Material = Enum.Material.Glass
			s.Reflectance = 0.2
			return s
		end)(),
		CFrame.new(0, -0.1, 0.62) * CFrame.Angles(math.rad(196), 0, 0),
		PartKit.segmentPivot(1.15)
	)

	local head = PartKit.part(model, {
		name = "Head",
		size = Vector3.new(0.95, 0.75, 0.8),
		shape = Enum.PartType.Ball,
		color = CHITIN,
		material = Enum.Material.Slate,
	})
	PartKit.joint(thorax, head, CFrame.new(0, -0.12, -1.15))
	table.insert(shell, head)

	local eyes: { BasePart } = {}
	for _, s in { -1, 1 } do
		local e = PartKit.neon(model, {
			name = "Eye",
			size = Vector3.new(0.62, 0.66, 0.6),
			shape = Enum.PartType.Ball,
			color = EYE_DORMANT,
			transparency = 0.25,
		})
		PartKit.joint(head, e, CFrame.new(s * 0.32, 0.06, -0.18))
		table.insert(eyes, e)
	end

	-- Outer mandibles plus an inner pair that works out of phase. Two pairs
	-- chewing against each other is the difference between a mouth and a face.
	local mandibles: { PartKit.Joint } = {}
	for _, s in { -1, 1 } do
		local m = PartKit.segment(model, "Mandible", 0.92, 0.13, TOOTH)
		m.Material = Enum.Material.Glass
		m.Reflectance = 0.22
		table.insert(
			mandibles,
			PartKit.joint(
				head,
				m,
				CFrame.new(s * 0.26, -0.24, -0.30) * CFrame.Angles(math.rad(26), math.rad(s * 26), 0),
				PartKit.segmentPivot(0.92)
			)
		)
	end
	for _, s in { -1, 1 } do
		local m = PartKit.segment(model, "InnerFang", 0.62, 0.085, TOOTH)
		m.Material = Enum.Material.Glass
		m.Reflectance = 0.22
		m.CastShadow = false
		table.insert(
			mandibles,
			PartKit.joint(
				head,
				m,
				CFrame.new(s * 0.12, -0.30, -0.26) * CFrame.Angles(math.rad(44), math.rad(s * 12), 0),
				PartKit.segmentPivot(0.62)
			)
		)
	end

	local wings: { PartKit.Joint } = {}
	for _, s in { -1, 1 } do
		local w = PartKit.part(model, {
			name = "Wing",
			size = Vector3.new(0.68, 0.07, 2.5),
			color = WING,
			material = Enum.Material.Fabric,
			transparency = 0.5,
			castShadow = false,
		})
		table.insert(
			wings,
			PartKit.joint(
				thorax,
				w,
				CFrame.new(s * 0.22, 0.42, 0.5) * CFrame.Angles(0, math.rad(s * 8), 0),
				CFrame.new(0, 0, -1.0)
			)
		)
	end

	local legs: { Leg } = {}
	for _, plan in LEG_PLAN do
		table.insert(legs, buildLeg(model, thorax, plan, -1))
		table.insert(legs, buildLeg(model, thorax, plan, 1))
	end

	local hitbox = PartKit.hitbox(model, thorax, Vector3.new(2.6, 2.6, 4.6), CFrame.new(0, -0.3, 0.7))

	PartKit.finalise(model, thorax, true)
	CollectionService:AddTag(model, "Creature")
	CollectionService:AddTag(model, "Ambusher")
	model:SetAttribute("Dormant", true)
	model:SetAttribute("Latched", false)
	model.Parent = parent

	local function mk(id: string, name: string, looped: boolean, vol: number, minD: number, maxD: number): Sound?
		if id == "" then
			return nil
		end
		return PartKit.emitter(thorax, id, {
			name = name,
			looped = looped,
			volume = vol,
			minDistance = minD,
			maxDistance = maxD,
		}).sound
	end

	return setmetatable({
		model = model,
		root = thorax,
		hitbox = hitbox,
		legs = legs,
		wings = wings,
		mandibles = mandibles,
		stinger = stinger,
		eyes = eyes,
		shell = shell,
		abdomen = abdomenJoints,
		shift = mk(SOUNDS.shift, "Shift", false, 0.55, 6, 45),
		launch = mk(SOUNDS.launch, "Launch", false, 0.9, 12, 100),
		buzz = mk(SOUNDS.buzz, "Buzz", true, 0.6, 10, 80),
		feed = mk(SOUNDS.feed, "Feed", true, 0.75, 4, 40),
		screech = mk(SOUNDS.screech, "Screech", false, 1, 14, 110),
		weld = nil,
		t = 0,
		state = "gripped",
		twitchAt = 2 + math.random() * 5,
		alert = 0,
		lit = 0,
		burn = 0,
	}, CeilingFly)
end

function CeilingFly.attach(self: Fly, ceilingPoint: Vector3, facing: Vector3?)
	local look = facing or Vector3.new(0, 0, -1)
	local p = ceilingPoint - Vector3.new(0, 0.5, 0)
	self.root.CFrame = CFrame.lookAt(p, p + look) * CFrame.Angles(math.rad(180), 0, 0)
	self.root.Anchored = true
	self.state = "gripped"
end

function CeilingFly.setIllumination(self: Fly, lit01: number)
	self.lit = math.clamp(lit01, 0, 1)
	local base = PartKit.lerpColor(CHITIN, CHITIN_LIT, self.lit)
	local c = PartKit.lerpColor(base, CHITIN_BURN, self.burn * 0.75)
	for _, p in self.shell do
		p.Color = c
	end
end

function CeilingFly.setAlert(self: Fly, alert01: number)
	self.alert = math.clamp(alert01, 0, 1)
	local c = PartKit.lerpColor(EYE_DORMANT, EYE_ALERT, self.alert)
	for _, e in self.eyes do
		e.Color = c
		e.Transparency = 0.3 - self.alert * 0.3
	end
	self.model:SetAttribute("Dormant", self.alert < 0.5)
end

-- Presentation-only flight state used by WICK's client visual adapter. The server proxy owns the
-- actual position and movement; this method only selects the correct local wing/leg animation.
function CeilingFly.setFlying(self: Fly, flying: boolean)
	if self.state == "dead" or self.state == "latched" then
		return
	end
	local nextState = if flying then "flying" else "gripped"
	if self.state == nextState then
		return
	end
	self.state = nextState
	self.root.Anchored = true
	self.root.AssemblyLinearVelocity = Vector3.zero
	if flying then
		if self.launch then
			self.launch:Play()
		end
		if self.buzz and not self.buzz.IsPlaying then
			self.buzz:Play()
		end
	elseif self.buzz then
		self.buzz:Stop()
	end
end

-- Latch onto a player's head. Welds, starts draining, and stays until burned off.
function CeilingFly.latchTo(self: Fly, targetPart: BasePart)
	if self.state == "latched" or self.state == "dead" then
		return
	end
	self.state = "latched"
	self.burn = 0
	self:setAlert(1)

	self.root.Anchored = false
	self.root.CFrame = targetPart.CFrame * CFrame.new(0, 1.1, 0) * CFrame.Angles(math.rad(180), 0, 0)

	local w = Instance.new("WeldConstraint")
	w.Part0 = targetPart
	w.Part1 = self.root
	w.Parent = self.root
	self.weld = w

	self.hitbox.CanQuery = false
	self.model:SetAttribute("Latched", true)

	if self.buzz then
		self.buzz:Stop()
	end
	if self.feed then
		self.feed:Play()
	end
	if self.screech then
		self.screech:Play()
	end
end

-- 0..1. Drive from how bright the victim is burning. At 1 it lets go and dies.
function CeilingFly.setBurn(self: Fly, burn01: number)
	if self.state ~= "latched" then
		return
	end
	self.burn = math.clamp(burn01, 0, 1)
	self:setIllumination(self.lit)
	if self.burn >= 1 then
		self:snuff()
	end
end

function CeilingFly.step(self: Fly, dt: number)
	self.t += dt

	if self.state == "latched" then
		-- Thrashing scales with burn. It fights hardest right before it lets go.
		local rate = 16 + self.burn * 26
		local amp = 0.16 + self.burn * 0.5
		local th = math.sin(self.t * rate) * amp
		local ch = math.sin(self.t * 22) * 0.5

		for i, j in self.mandibles do
			local s = if i % 2 == 1 then -1 else 1
			local inner = if i > 2 then -1 else 1
			PartKit.pose(j, CFrame.Angles(0, s * inner * ch * 0.6, 0))
		end
		for _, leg in self.legs do
			PartKit.pose(leg.coxa, CFrame.Angles(math.rad(-14) + th * leg.side * 0.4, 0, 0))
			PartKit.pose(leg.femur, CFrame.Angles(math.rad(20) - th * 0.5, 0, 0))
			PartKit.pose(leg.tarsus, CFrame.Angles(math.rad(-26), 0, 0))
		end
		for i, w in self.wings do
			local s = if i == 1 then -1 else 1
			PartKit.pose(w, CFrame.Angles(0, 0, s * math.sin(self.t * 30) * (0.3 + self.burn * 0.9)))
		end
		for i, j in self.abdomen do
			PartKit.pose(j, CFrame.Angles(th * 0.5 * i, 0, 0))
		end
		PartKit.pose(self.stinger, CFrame.Angles(th * 0.8, 0, 0))
		return
	end

	if self.state == "gripped" then
		local twitching = self.t > self.twitchAt and self.t < self.twitchAt + 0.35
		if twitching and self.shift and not self.shift.IsPlaying then
			self.shift:Play()
		end
		if self.t > self.twitchAt + 0.35 then
			self.twitchAt = self.t + 2.5 + math.random() * 6
		end

		for _, leg in self.legs do
			local n = math.sin(self.t * 0.7 + leg.seed) * 0.012
			local tw = if twitching then math.sin((self.t - self.twitchAt) * 42) * 0.09 else 0
			PartKit.pose(leg.coxa, CFrame.Angles(n + tw * leg.side, 0, 0))
			PartKit.pose(leg.femur, CFrame.Angles(n * 1.4 - tw, 0, 0))
			PartKit.pose(leg.tarsus, CFrame.Angles(-n, 0, 0))
		end

		-- Mandibles work slowly while it waits and faster as it decides.
		local chew = math.sin(self.t * (1.4 + self.alert * 9)) * (0.06 + self.alert * 0.42)
		for i, j in self.mandibles do
			local s = if i % 2 == 1 then -1 else 1
			local inner = if i > 2 then -1 else 1
			PartKit.pose(j, CFrame.Angles(0, s * inner * chew, 0))
		end

		for i, w in self.wings do
			local s = if i == 1 then -1 else 1
			PartKit.pose(w, CFrame.Angles(0, s * self.alert * math.rad(24), 0))
		end

		local rate = 1.1 + self.alert * 3.4
		local depth = 0.055 - self.alert * 0.03
		local breath = math.sin(self.t * rate) * depth
		for i, j in self.abdomen do
			PartKit.pose(j, CFrame.new(0, breath * i * 0.5, breath * i) * CFrame.Angles(breath * 0.4, 0, 0))
		end
		PartKit.pose(self.stinger, CFrame.Angles(breath * 1.2 - self.alert * math.rad(18), 0, 0))
		return
	end

	local flap = math.sin(self.t * 38)
	for i, w in self.wings do
		local s = if i == 1 then -1 else 1
		PartKit.pose(w, CFrame.Angles(0, 0, s * flap * 1.15))
	end
	for _, leg in self.legs do
		PartKit.pose(leg.coxa, CFrame.Angles(math.rad(34), 0, 0))
		PartKit.pose(leg.femur, CFrame.Angles(math.rad(22), 0, 0))
		PartKit.pose(leg.tarsus, CFrame.Angles(math.rad(-16), 0, 0))
	end
	local snap = math.sin(self.t * 26) * 0.55
	for i, j in self.mandibles do
		local s = if i % 2 == 1 then -1 else 1
		local inner = if i > 2 then -1 else 1
		PartKit.pose(j, CFrame.Angles(0, s * inner * snap, 0))
	end
end

function CeilingFly.drop(self: Fly)
	if self.state ~= "gripped" then
		return
	end
	self.state = "flying"
	self:setAlert(1)
	self.root.CFrame = self.root.CFrame * CFrame.Angles(math.rad(180), 0, 0)
	self.root.Anchored = false
	self.root.AssemblyLinearVelocity = Vector3.new(0, -18, 0)

	if self.launch then
		self.launch:Play()
	end
	if self.buzz then
		self.buzz:Play()
	end
end

function CeilingFly.snuff(self: Fly)
	if self.state == "dead" then
		return
	end
	self.state = "dead"
	self:setAlert(0)
	for _, e in self.eyes do
		e.Transparency = 1
	end
	if self.buzz then
		self.buzz:Stop()
	end
	if self.feed then
		self.feed:Stop()
	end
	if self.weld then
		self.weld:Destroy()
		self.weld = nil
	end
	self.model:SetAttribute("Latched", false)
	self.root.Anchored = false
	self.hitbox.CanQuery = false
	Debris:AddItem(self.model, 6)
end

function CeilingFly.destroy(self: Fly)
	if self.buzz then
		self.buzz:Stop()
	end
	if self.feed then
		self.feed:Stop()
	end
	self.model:Destroy()
end

return CeilingFly

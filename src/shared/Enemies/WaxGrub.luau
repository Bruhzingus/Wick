--!strict
-- WaxGrub — tier 1 swarm scavenger.
-- Place at: ReplicatedStorage/Enemies/WaxGrub
--
-- The player cannot attack, so this is not a fight. It is a nuisance with two
-- outs: stomp on it, or flare. Both are cheap, which is the point — the grub
-- exists to make the player spend something small, often, and to make broods
-- feel like a decision rather than an obstacle.
--
-- Attack is deliberately fast (0.42s total, down from 0.8s). A slow lunge from
-- something this small reads as harmless.

local EnemyKit = require(script.Parent.EnemyKit)
local E = EnemyKit.Ease

local WaxGrub = {}
WaxGrub.__index = WaxGrub

WaxGrub.Config = {
	health = 12,
	speed = 6,
	fleeSpeed = 11,
	-- See Config/WaxGrub.luau header for the derivation; kept numerically in sync with that file,
	-- which is what integration actually reads at runtime.
	drainPerSecond = 0.05,
	-- Above this brightness it will not approach. A flare trivially clears a brood.
	flareThreshold = 0.72,
	-- Stomping scares rather than kills: the player has no attack, and a grub
	-- that dies to a footstep makes the brood meaningless.
	stompFleeSeconds = 4.5,
	attackRange = 3.2,
	senseRange = 14,
}

local SOUNDS = { idle = "", lunge = "", drink = "", flee = "", death = "" }

local rad = math.rad

-- ============================================================
-- ANIMATION
-- ============================================================
local TRACKS = {}

-- Extended, not curled. Segment joints carry no baked rotation now, so the body
-- lies straight and the sinuous motion comes entirely from these tracks. The
-- previous version compounded 18 degrees of yaw per joint down a chained
-- skeleton, which spiralled the tail through 270 degrees and made it read as
-- permanently coiled.
TRACKS.idle = EnemyKit.track({
	{ t = 0.0, pose = { neck = { 0, rad(4), 0 }, head = { rad(2), rad(-5), 0 }, s1 = { 0, rad(5), 0 }, s2 = { 0, rad(-4), 0 }, s3 = { 0, rad(4), 0 }, s4 = { 0, rad(-3), 0 }, s5 = { 0, rad(3), 0 }, mandL = { 0, rad(-10), 0 }, mandR = { 0, rad(10), 0 } }, ease = "inOutQuad" },
	{ t = 1.5, pose = { neck = { 0, rad(-4), 0 }, head = { rad(-1), rad(6), 0 }, s1 = { 0, rad(-5), 0 }, s2 = { 0, rad(4), 0 }, s3 = { 0, rad(-4), 0 }, s4 = { 0, rad(3), 0 }, s5 = { 0, rad(-3), 0 }, mandL = { 0, rad(-20), 0 }, mandR = { 0, rad(20), 0 } }, ease = "inOutQuad" },
	{ t = 3.0, pose = { neck = { 0, rad(4), 0 }, head = { rad(2), rad(-5), 0 }, s1 = { 0, rad(5), 0 }, s2 = { 0, rad(-4), 0 }, s3 = { 0, rad(4), 0 }, s4 = { 0, rad(-3), 0 }, s5 = { 0, rad(3), 0 }, mandL = { 0, rad(-10), 0 }, mandR = { 0, rad(10), 0 } }, ease = "inOutQuad" },
}, true)

-- A travelling wave running head to tail. Each segment lags the one in front by
-- a fixed phase, which is what makes it crawl rather than wag.
TRACKS.move = EnemyKit.track({
	{ t = 0.00, pose = { neck = { rad(-4), rad(5), 0 }, head = { rad(-3), rad(4), 0 }, s1 = { rad(-7), rad(12), 0 }, s2 = { rad(4), rad(-9), 0 }, s3 = { rad(-5), rad(10), 0 }, s4 = { rad(3), rad(-8), 0 }, s5 = { rad(-3), rad(7), 0 } }, ease = "inOutQuad" },
	{ t = 0.24, pose = { neck = { rad(4), rad(-5), 0 }, head = { rad(3), rad(-4), 0 }, s1 = { rad(6), rad(-11), 0 }, s2 = { rad(-6), rad(11), 0 }, s3 = { rad(4), rad(-9), 0 }, s4 = { rad(-4), rad(8), 0 }, s5 = { rad(3), rad(-7), 0 } }, ease = "inOutQuad" },
	{ t = 0.48, pose = { neck = { rad(-4), rad(5), 0 }, head = { rad(-3), rad(4), 0 }, s1 = { rad(-7), rad(12), 0 }, s2 = { rad(4), rad(-9), 0 }, s3 = { rad(-5), rad(10), 0 }, s4 = { rad(3), rad(-8), 0 }, s5 = { rad(-3), rad(7), 0 } }, ease = "inOutQuad" },
}, true)

-- BITES WITH ITS HEAD. The neck rears back and up, then whips down and forward
-- while the mandibles snap shut. The body braces slightly backward against the
-- strike instead of driving it — the previous version animated the trunk, so
-- the whole thing read as a tail whip.
TRACKS.attack = EnemyKit.track({
	{ t = 0.00, pose = { neck = { 0, 0, 0 }, head = { 0, 0, 0 }, s1 = { 0, 0, 0 }, s2 = { 0, 0, 0 }, mandL = { 0, rad(-12), 0 }, mandR = { 0, rad(12), 0 } } },
	-- anticipation: rear back, jaws wide
	{ t = 0.13, pose = { neck = { rad(-38), 0, 0 }, head = { rad(-22), 0, 0 }, s1 = { rad(-10), 0, 0 }, s2 = { rad(-5), 0, 0 }, mandL = { 0, rad(-56), 0 }, mandR = { 0, rad(56), 0 } }, ease = "outQuad" },
	-- strike: whip down and forward, jaws snap shut on the same frame
	{ t = 0.23, pose = { neck = { rad(46), 0, 0 }, head = { rad(34), 0, 0 }, s1 = { rad(8), 0, 0 }, s2 = { rad(4), 0, 0 }, mandL = { 0, rad(2), 0 }, mandR = { 0, rad(-2), 0 } }, ease = "outBack" },
	{ t = 0.44, pose = { neck = { 0, 0, 0 }, head = { 0, 0, 0 }, s1 = { 0, 0, 0 }, s2 = { 0, 0, 0 }, mandL = { 0, rad(-12), 0 }, mandR = { 0, rad(12), 0 } }, ease = "outCubic" },
})

-- CHEWING. Head dipped down over the wax drop, mandibles opening and closing in a steady rhythm
-- rather than the attack's single snap. Looped and slower than the idle mouth-flutter so it reads
-- as committed feeding, not resting.
TRACKS.eat = EnemyKit.track({
	{ t = 0.00, pose = { neck = { rad(22), 0, 0 }, head = { rad(16), 0, 0 }, s1 = { rad(3), 0, 0 }, mandL = { 0, rad(-10), 0 }, mandR = { 0, rad(10), 0 } }, ease = "inOutQuad" },
	{ t = 0.22, pose = { neck = { rad(26), 0, 0 }, head = { rad(19), 0, 0 }, s1 = { rad(4), 0, 0 }, mandL = { 0, rad(-34), 0 }, mandR = { 0, rad(34), 0 } }, ease = "outQuad" },
	{ t = 0.44, pose = { neck = { rad(22), 0, 0 }, head = { rad(16), 0, 0 }, s1 = { rad(3), 0, 0 }, mandL = { 0, rad(-8), 0 }, mandR = { 0, rad(8), 0 } }, ease = "inQuad" },
	{ t = 0.66, pose = { neck = { rad(26), 0, 0 }, head = { rad(19), 0, 0 }, s1 = { rad(4), 0, 0 }, mandL = { 0, rad(-34), 0 }, mandR = { 0, rad(34), 0 } }, ease = "outQuad" },
	{ t = 0.88, pose = { neck = { rad(22), 0, 0 }, head = { rad(16), 0, 0 }, s1 = { rad(3), 0, 0 }, mandL = { 0, rad(-10), 0 }, mandR = { 0, rad(10), 0 } }, ease = "inQuad" },
}, true)

-- Rears the head away, then reverses. Still extended — a scared worm backs off
-- in a line, it does not ball up.
TRACKS.flee = EnemyKit.track({
	{ t = 0.00, pose = { neck = { 0, 0, 0 }, head = { 0, 0, 0 } } },
	{ t = 0.13, pose = { neck = { rad(-50), 0, 0 }, head = { rad(-34), 0, 0 }, s1 = { rad(-14), 0, 0 }, mandL = { 0, rad(-50), 0 }, mandR = { 0, rad(50), 0 } }, ease = "outBack" },
	{ t = 0.34, pose = { neck = { rad(-18), rad(20), 0 }, head = { rad(-12), rad(-16), 0 }, s1 = { rad(-6), rad(-20), 0 }, s2 = { rad(-3), rad(17), 0 }, s3 = { 0, rad(-14), 0 } }, ease = "outQuad" },
	{ t = 0.56, pose = { neck = { rad(-18), rad(-20), 0 }, head = { rad(-12), rad(16), 0 }, s1 = { rad(-6), rad(20), 0 }, s2 = { rad(-3), rad(-17), 0 }, s3 = { 0, rad(14), 0 } }, ease = "inOutQuad" },
	{ t = 0.78, pose = { neck = { rad(-18), rad(20), 0 }, head = { rad(-12), rad(-16), 0 }, s1 = { rad(-6), rad(-20), 0 }, s2 = { rad(-3), rad(17), 0 }, s3 = { 0, rad(-14), 0 } }, ease = "inOutQuad" },
}, true)

TRACKS.hurt = EnemyKit.track({
	{ t = 0.00, pose = { neck = { 0, 0, 0 }, head = { 0, 0, 0 }, s1 = { 0, 0, 0 } } },
	{ t = 0.07, pose = { neck = { rad(24), rad(-22), 0 }, head = { rad(16), rad(18), 0 }, s1 = { rad(-16), rad(20), 0 }, s2 = { rad(12), rad(-17), 0 }, s3 = { rad(-8), rad(14), 0 }, mandL = { 0, rad(-44), 0 }, mandR = { 0, rad(44), 0 } }, ease = "outQuart" },
	{ t = 0.32, pose = { neck = { 0, 0, 0 }, head = { 0, 0, 0 }, s1 = { 0, 0, 0 }, s2 = { 0, 0, 0 }, s3 = { 0, 0, 0 }, mandL = { 0, rad(-12), 0 }, mandR = { 0, rad(12), 0 } }, ease = "outElastic" },
})

-- Four beats: flinch, slacken, curl, settle. It only curls at death, which is
-- what makes the pose mean something.
TRACKS.death = EnemyKit.track({
	{ t = 0.00, pose = { neck = { 0, 0, 0 }, head = { 0, 0, 0 }, s1 = { 0, 0, 0 }, s2 = { 0, 0, 0 }, s3 = { 0, 0, 0 }, s4 = { 0, 0, 0 }, s5 = { 0, 0, 0 } } },
	{ t = 0.11, pose = { neck = { rad(-34), 0, 0 }, head = { rad(-24), 0, 0 }, mandL = { 0, rad(-52), 0 }, mandR = { 0, rad(52), 0 } }, ease = "outQuart" },
	{ t = 0.30, pose = { neck = { rad(10), 0, 0 }, head = { rad(14), 0, 0 }, s1 = { rad(6), rad(6), 0 }, s2 = { rad(5), rad(5), 0 } }, ease = "inQuad" },
	{ t = 0.72, pose = { neck = { rad(30), rad(14), 0 }, head = { rad(26), rad(10), 0 }, s1 = { rad(40), rad(30), 0 }, s2 = { rad(36), rad(26), 0 }, s3 = { rad(32), rad(22), 0 }, s4 = { rad(26), rad(18), 0 }, s5 = { rad(20), rad(13), 0 } }, ease = "inCubic" },
	{ t = 1.05, pose = { neck = { rad(38), rad(19), 0 }, head = { rad(34), rad(14), 0 }, s1 = { rad(52), rad(38), 0 }, s2 = { rad(47), rad(33), 0 }, s3 = { rad(42), rad(28), 0 }, s4 = { rad(35), rad(23), 0 }, s5 = { rad(27), rad(17), 0 }, mandL = { 0, rad(-8), 0 }, mandR = { 0, rad(8), 0 } }, ease = "outCubic" },
	{ t = 1.45, pose = { neck = { rad(36), rad(18), 0 }, s1 = { rad(49), rad(36), 0 }, s2 = { rad(45), rad(31), 0 }, s3 = { rad(40), rad(26), 0 }, s4 = { rad(33), rad(21), 0 }, s5 = { rad(26), rad(16), 0 } }, ease = "outQuad" },
})

-- ============================================================
-- BUILD
-- ============================================================
function WaxGrub.build(variant: EnemyKit.Variant, seed: number?): (Model, any)
	local b = EnemyKit.begin("WaxGrub", variant, seed)
	local joints: { [string]: EnemyKit.Joint } = {}

	local root = EnemyKit.block(b, "Body0", Vector3.new(0.62, 0.45, 0.44), "chit")
	local prev = root
	local segParts = { root }

	-- NO baked rotation on these joints. Compounding a per-segment yaw down a
	-- chained skeleton spirals the tail; the body must lie straight at rest and
	-- get all of its curve from the animation tracks.
	for i = 1, 5 do
		local s = 0.62 - i * 0.055
		local seg = EnemyKit.block(b, "Body" .. i, Vector3.new(s, s * 0.72, 0.44), "chit", true)
		joints["s" .. i] = EnemyKit.joint(prev, seg, CFrame.new(0, 0, 0.42))
		if i <= 3 then
			local sac = EnemyKit.blob(b, "Sac", Vector3.new(s * 0.46, s * 0.32, 0.30), "wax", false)
			EnemyKit.joint(seg, sac, CFrame.new(0, s * 0.30, 0))
		end
		EnemyKit.anchor(b, seg, CFrame.new(0, s * 0.3, 0), 0.26)
		prev = seg
		table.insert(segParts, seg)
	end

	-- Neck exists so the head can strike. Without a second joint in front of the
	-- root there is nothing to swing, and an attack animated on the trunk reads
	-- as a tail whip.
	local neck = EnemyKit.block(b, "Neck", Vector3.new(0.52, 0.40, 0.30), "chit")
	joints.neck = EnemyKit.joint(root, neck, CFrame.new(0, 0, -0.36), CFrame.new(0, 0, 0.15))

	local head = EnemyKit.block(b, "Head", Vector3.new(0.58, 0.44, 0.46), "chit")
	joints.head = EnemyKit.joint(neck, head, CFrame.new(0, 0, -0.15), CFrame.new(0, 0, 0.23))

	-- Teeth. The strike lands with these, so they need to be visible before it
	-- happens — a bite from something with no visible mouth reads as a shove.
	for i = 0, 2 do
		local x = (i - 1) * 0.115
		local tu = EnemyKit.block(b, "ToothUpper", Vector3.new(0.055, 0.17, 0.055), "tooth", false)
		EnemyKit.joint(head, tu, CFrame.new(x, -0.02, -0.24) * CFrame.Angles(math.rad(18), 0, 0))
	end
	local jawPlate = EnemyKit.block(b, "Jaw", Vector3.new(0.40, 0.12, 0.30), "chit", false)
	EnemyKit.joint(head, jawPlate, CFrame.new(0, -0.20, -0.12))
	for i = 0, 1 do
		local x = (i - 0.5) * 0.16
		local tl = EnemyKit.block(b, "ToothLower", Vector3.new(0.05, 0.14, 0.05), "tooth", false)
		EnemyKit.joint(jawPlate, tl, CFrame.new(x, 0.10, -0.10) * CFrame.Angles(math.rad(-20), 0, 0))
	end

	-- Mandibles: longer and hooked inward so the snap has a clear silhouette.
	for _, side in { -1, 1 } do
		local m = EnemyKit.block(b, "Mandible", Vector3.new(0.10, 0.10, 0.46), "pale", false)
		local j = EnemyKit.joint(head, m, CFrame.new(side * 0.20, -0.05, -0.22) * CFrame.Angles(math.rad(10), math.rad(side * 22), 0), CFrame.new(0, 0, 0.23))
		joints[if side < 0 then "mandL" else "mandR"] = j
		local tip = EnemyKit.block(b, "MandibleTip", Vector3.new(0.07, 0.07, 0.24), "tooth", false)
		EnemyKit.joint(m, tip, CFrame.new(0, 0, -0.23) * CFrame.Angles(0, math.rad(side * -34), 0), CFrame.new(0, 0, 0.12))
		local e = EnemyKit.neon(b, "Eye", Vector3.one * 0.09, "eye")
		EnemyKit.joint(head, e, CFrame.new(side * 0.18, 0.13, -0.18))
	end

	-- Legs are cosmetic and never carry a pose key.
	for i = 1, 3 do
		for _, side in { -1, 1 } do
			local host = segParts[i + 1]
			local a = EnemyKit.block(b, "Leg", Vector3.new(0.075, 0.075, 0.30), "chit", false)
			local ja = EnemyKit.joint(host, a, CFrame.new(side * 0.24, -0.14, 0) * CFrame.Angles(0, math.rad(side * 70), 0) * CFrame.Angles(math.rad(-50), 0, 0), CFrame.new(0, 0, 0.15))
			joints[("leg%d%s"):format(i, if side < 0 then "L" else "R")] = ja
			local c = EnemyKit.block(b, "Foot", Vector3.new(0.055, 0.055, 0.26), "chit", false)
			EnemyKit.joint(a, c, CFrame.new(0, 0, -0.15) * CFrame.Angles(math.rad(58), 0, 0), CFrame.new(0, 0, 0.13))
		end
	end

	EnemyKit.hitbox(b, root, Vector3.new(1.0, 0.9, 3.2), CFrame.new(0, 0, 0.8))
	EnemyKit.collider(b, root, Vector3.new(0.8, 0.7, 2.4), CFrame.new(0, 0, 0.8))

	local model = EnemyKit.finish(b, root, "WaxGrub", 1)
	return model, { root = root, joints = joints, head = head, segs = segParts }
end

-- ============================================================
-- CONTROLLER
-- ============================================================
export type Grub = typeof(setmetatable({} :: any, WaxGrub))

function WaxGrub.new(cframe: CFrame, variant: EnemyKit.Variant?, seed: number?): Grub
	local v = variant or "regular"
	local model, rig = WaxGrub.build(v, seed)
	model:PivotTo(cframe)

	local stats = EnemyKit.VariantStats[v]
	local elder = model:GetAttribute("Elder")
	local hp = WaxGrub.Config.health * stats.health * (if elder then EnemyKit.ElderStats.health else 1)

	local self = setmetatable({
		model = model,
		root = rig.root,
		joints = rig.joints,
		hitbox = model:FindFirstChild("Hitbox"),
		variant = v,
		health = hp,
		maxHealth = hp,
		speed = WaxGrub.Config.speed * stats.speed,
		state = "idle",
		t = 0,
		stateT = 0,
		fleeUntil = 0,
		latched = nil,
		sounds = {
			idle = EnemyKit.emitter(rig.root, SOUNDS.idle, "Idle", true, 0.35, 4, 30),
			lunge = EnemyKit.emitter(rig.root, SOUNDS.lunge, "Lunge", false, 0.55, 4, 34),
			drink = EnemyKit.emitter(rig.root, SOUNDS.drink, "Drink", true, 0.6, 2, 8),
			flee = EnemyKit.emitter(rig.root, SOUNDS.flee, "Flee", false, 0.5, 4, 30),
			death = EnemyKit.emitter(rig.root, SOUNDS.death, "Death", false, 0.6, 4, 30),
		},
	}, WaxGrub)

	-- Per-instance pitch, set once and never changed. A brood must sound like
	-- many individuals, not one sound played many times.
	if self.sounds.idle then
		self.sounds.idle.PlaybackSpeed = 0.9 + math.random() * 0.24
		self.sounds.idle:Play()
	end
	return self
end

function WaxGrub.setState(self: Grub, state: string)
	if self.state == state or self.state == "death" then
		return
	end
	self.state = state
	self.stateT = 0
	self.model:SetAttribute("State", state)
	if state == "attack" and self.sounds.lunge then
		self.sounds.lunge:Play()
	elseif state == "flee" and self.sounds.flee then
		self.sounds.flee:Play()
	elseif state == "death" then
		if self.sounds.idle then
			self.sounds.idle:Stop()
		end
		if self.sounds.drink then
			self.sounds.drink:Stop()
		end
		if self.sounds.death then
			self.sounds.death:Play()
		end
	end
end

-- Called by whatever detects a player footfall landing on this grub. It is
-- scared away, not killed: the player has no attack, and a grub that dies to a
-- footstep makes the whole brood meaningless.
function WaxGrub.stomp(self: Grub)
	if self.state == "death" then
		return
	end
	self:unlatch()
	self.fleeUntil = self.t + WaxGrub.Config.stompFleeSeconds
	self:setState("flee")
end

-- A FOOT THAT LANDED ON IT BUT DID NOT SHAKE IT LOOSE. The same flinch `damage` plays, and
-- deliberately no health spent and no unlatch: a latched grub takes several stomps (see
-- Config/WaxGrub.shakeStompsMin/Max) and the host calls this for every one of them except the last,
-- which calls `stomp`. Restarts the track even when it is already flinching, so two landings in
-- quick succession read as two hits rather than as one that never ended.
function WaxGrub.flinch(self: Grub)
	if self.state == "death" then
		return
	end
	if self.state == "hurt" then
		self.stateT = 0
		return
	end
	self:setState("hurt")
end

-- Drive from the player's brightness each frame.
function WaxGrub.setIllumination(self: Grub, brightness: number)
	if self.state == "death" then
		return
	end
	if brightness >= WaxGrub.Config.flareThreshold and self.state ~= "flee" then
		self:unlatch()
		self.fleeUntil = self.t + 2.5
		self:setState("flee")
	end
end

-- THE COLLIDER IS TURNED OFF WHILE LATCHED, and this is not cosmetic.
--
-- A latched grub is carried at the player's feet by whatever drives it (server/EnemySystem/
-- WaxGrubBehavior re-seats it under the root every tick, in the air as well as on the ground), so a
-- collidable body under the boots is a floor that follows you: the Humanoid never reports
-- `FloorMaterial = Air`, which means the player can jump off the grub again in mid-air — forever, up
-- to the ceiling — and, worse, the landing that the host reads as a STOMP is a transition into
-- grounded that never happens. The one counter to this creature was silently disabled by its own
-- hitbox. Nothing needs the collider while latched: the body is anchored and posed by CFrame.
local function setColliding(self: Grub, colliding: boolean)
	local collider = self.model:FindFirstChild("Collider")
	if collider ~= nil and collider:IsA("BasePart") then
		collider.CanCollide = colliding
	end
end

function WaxGrub.latchTo(self: Grub, target: BasePart)
	if self.state == "death" or self.state == "flee" then
		return
	end
	self.latched = target
	setColliding(self, false)
	self.model:SetAttribute("Latched", true)
	self.model:SetAttribute("WaxDrainPerSecond", WaxGrub.Config.drainPerSecond)
	if self.sounds.drink then
		self.sounds.drink:Play()
	end
end

function WaxGrub.unlatch(self: Grub)
	if not self.latched then
		return
	end
	self.latched = nil
	setColliding(self, true)
	self.model:SetAttribute("Latched", false)
	self.model:SetAttribute("WaxDrainPerSecond", 0)
	if self.sounds.drink then
		self.sounds.drink:Stop()
	end
end

function WaxGrub.damage(self: Grub, amount: number)
	if self.state == "death" then
		return
	end
	self.health -= amount
	if self.health <= 0 then
		self:unlatch()
		self:setState("death")
	else
		self:setState("hurt")
	end
end

function WaxGrub.step(self: Grub, dt: number)
	self.t += dt
	self.stateT += dt

	if self.state == "flee" and self.t >= self.fleeUntil then
		self:setState("idle")
	end
	if self.state == "hurt" and self.stateT > 0.30 then
		self:setState("idle")
	end
	if self.state == "attack" and self.stateT > 0.44 then
		self:setState("idle")
	end

	local track = TRACKS[self.state] or TRACKS.idle
	EnemyKit.evaluate(self.joints, track, self.stateT)

	-- Cosmetic leg cycle, layered on top rather than keyed.
	if self.state ~= "death" then
		local rate = if self.state == "flee" then 15 elseif self.state == "move" then 9 else 2.4
		-- EAT is stationary, same as idle: legs should hold still under it, not wave through the
		-- "active" amplitude every other non-idle state uses.
		local amp = if self.state == "idle" or self.state == "eat" then 0.12 else 0.42
		for i = 1, 3 do
			for _, s in { "L", "R" } do
				local j = self.joints[("leg%d%s"):format(i, s)]
				if j then
					local ph = self.t * rate + i * 1.7 + (if s == "R" then math.pi else 0)
					EnemyKit.pose(j, math.sin(ph) * amp, 0, 0)
				end
			end
		end
	end
end

function WaxGrub.destroy(self: Grub)
	self.model:Destroy()
end

return WaxGrub

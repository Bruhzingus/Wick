--!strict
-- CALVER — Ice's signature dark-hunter. The creature that brings the ceiling down.
-- Place at: ReplicatedStorage/Creatures/Calver
--
-- IT NEVER COMES DOWN AND IT NEVER TOUCHES YOU. Every other creature in the game closes distance;
-- this one has no interest in you at all. It clings to the roof of Ice's tall vaults, and when a
-- candle passes underneath it hammers the rock — setting off an unstable formation that was already
-- hanging there, that the player could have inspected from across the room, and that still gives its
-- own full warning when it goes. It changes WHEN the ceiling fails, never WHETHER.
--
-- SO THE BODY IS BUILT AROUND ITS ARMS. Six limbs: four splayed grippers holding it flat against the
-- rock, and two heavy forelimbs folded up over its own back that exist only to swing down into the
-- ceiling. Those two are thicker than anything else on the creature, and they are what a player who
-- looks up actually sees — a shape with hammers on it.
--
-- THE WIND-UP IS THE WHOLE CONTRACT. `windUpSeconds` in Config/Threats is the player's warning that
-- something above them is about to act, and this body spends every frame of it visibly cocking: the
-- forelimbs draw back and up, the grip limbs brace, and the crimson brightens. It is meant to be
-- unmistakable, because the reaction it asks for — get out from under, not away from the creature —
-- is the opposite of the reflex every other threat has trained.
--
-- EYES FACE DOWN. It looks at the floor beneath it, so its crimson slits are on the underside of the
-- head where a player standing below can actually see them. Same colour, same angle, same brightening
-- as everything else on the roster.
--
-- Nothing here collides, queries or touches. Wax, contact, perception and AI are the server's.

local CollectionService = game:GetService("CollectionService")
local PartKit = require(script.Parent.PartKit)
local CreatureDressing = require(script.Parent.CreatureDressing)
local Threats = require(script.Parent.Parent.Config.Threats)

local Calver = {}
Calver.__index = Calver

local CHITIN_DARK = Color3.fromRGB(12, 12, 15)
local CHITIN_PALE = Color3.fromRGB(30, 30, 33)
local CHITIN_MATERIAL = Enum.Material.Slate
local PLATE_MATERIAL = Enum.Material.Pebble
local CLAW = Color3.fromRGB(58, 56, 52)
local LIT_TARGET = Color3.fromRGB(70, 72, 78)
local LIT_MIX = 0.4

local EYE_IDLE = Color3.fromRGB(128, 16, 10)
local EYE_LOCKED = Color3.fromRGB(255, 46, 30)
local EYE_ANGLE = 20

-- Proportions. Wide and flat: 2.3 across, 0.6 deep. It is a plate with limbs, not a body.
local CARAPACE_W, CARAPACE_H, CARAPACE_L = 2.3, 0.6, 2.6
local GRIP_UPPER, GRIP_LOWER = 0.85, 0.95
local HAMMER_UPPER, HAMMER_LOWER = 1.1, 1.15
local GRIP_D = 0.19

type Skinned = { part: BasePart, base: Color3, lit: Color3 }
type Grip = { upper: PartKit.Joint, lower: PartKit.Joint, side: number, front: boolean }
type Hammer = { upper: PartKit.Joint, lower: PartKit.Joint, side: number }

export type Fly = typeof(setmetatable(
	{} :: {
		model: Model,
		root: BasePart,
		bodyJoint: PartKit.Joint,
		hitbox: BasePart,
		grips: { Grip },
		hammers: { Hammer },
		skin: { Skinned },
		dressAnchors: { CreatureDressing.Anchor },
		eyes: { BasePart },
		halos: { BasePart },
		headJoint: PartKit.Joint,
		t: number,
		lit: number,
		lastPaintedIllumination: number?,
		aware: number,
		moving: boolean,
		focus: Vector3?,
		headYaw: number,
		brace: number,
		attackT: number,
		attackLanded: boolean,
		pendingImpact: boolean,
		strike: number,
	},
	{} :: typeof({ __index = Calver })
))

local function chitinColor(tone: number): Color3
	return CHITIN_DARK:Lerp(CHITIN_PALE, math.clamp(tone, 0, 1))
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
	material: Enum.Material?
): BasePart
	local color = chitinColor(tone)
	return track(
		skin,
		PartKit.ellipsoid(model, {
			name = name,
			size = size,
			color = color,
			material = material or CHITIN_MATERIAL,
			castShadow = false,
		}),
		color
	)
end

local function tube(model: Model, skin: { Skinned }, name: string, len: number, dia: number, tone: number): BasePart
	local color = chitinColor(tone)
	return track(skin, PartKit.tube(model, name, len, dia, color, CHITIN_MATERIAL, false), color)
end

local function refreshEyes(self: Fly)
	local heat = math.max(self.aware, self.strike)
	local color = PartKit.lerpColor(EYE_IDLE, EYE_LOCKED, 0.25 + heat * 0.75)
	local wash = self.lit * 0.5
	for _, eye in self.eyes do
		eye.Color = color
		eye.Transparency = wash
	end
	for _, halo in self.halos do
		halo.Color = color
		halo.Transparency = math.clamp(0.62 + self.lit * 0.32 - heat * 0.3, 0, 1)
	end
end

-- A grip limb: splayed out and UP, ending in a hooked claw. Four of these hold the body flat.
local function buildGrip(
	model: Model,
	skin: { Skinned },
	anchors: { CreatureDressing.Anchor },
	carapace: BasePart,
	side: number,
	front: boolean
): Grip
	local along = if front then -CARAPACE_L * 0.3 else CARAPACE_L * 0.3
	local upper = tube(model, skin, "GripUpper", GRIP_UPPER, GRIP_D, 0.22)
	local jointUpper = PartKit.joint(
		carapace,
		upper,
		CFrame.new(side * CARAPACE_W * 0.36, 0.08, along)
			* CFrame.Angles(0, math.rad(side * (if front then 34 else -34)), 0)
			-- Reaching UPWARD into the rock, not downward at the floor.
			* CFrame.Angles(math.rad(-118), 0, math.rad(side * 22)),
		PartKit.tubePivot(GRIP_UPPER)
	)

	local lower = tube(model, skin, "GripLower", GRIP_LOWER, GRIP_D * 0.8, 0.15)
	local jointLower = PartKit.joint(
		upper,
		lower,
		PartKit.tubeTip(GRIP_UPPER) * CFrame.Angles(math.rad(52), 0, 0),
		PartKit.tubePivot(GRIP_LOWER)
	)

	local claw = PartKit.tube(model, "Claw", 0.3, 0.07, CLAW, Enum.Material.Concrete, false)
	PartKit.joint(lower, claw, PartKit.tubeTip(GRIP_LOWER) * CFrame.Angles(math.rad(34), 0, 0), PartKit.tubePivot(0.3))
	track(skin, claw, CLAW)

	table.insert(anchors, { part = upper, normal = Vector3.new(0, side, 0), scale = 0.45, upward = false })

	return { upper = jointUpper, lower = jointLower, side = side, front = front }
end

-- A hammer limb. Thicker than the grips at every segment and ending in a blunt mass rather than a
-- claw, because what it does is blunt.
local function buildHammer(
	model: Model,
	skin: { Skinned },
	anchors: { CreatureDressing.Anchor },
	carapace: BasePart,
	side: number
): Hammer
	local upper = tube(model, skin, "HammerUpper", HAMMER_UPPER, GRIP_D * 1.7, 0.3)
	local jointUpper = PartKit.joint(
		carapace,
		upper,
		CFrame.new(side * CARAPACE_W * 0.2, 0.16, -CARAPACE_L * 0.42)
			* CFrame.Angles(0, math.rad(side * 12), 0)
			-- Folded up and back over its own carapace at rest: cocked, permanently.
			* CFrame.Angles(math.rad(-146), 0, math.rad(side * 10)),
		PartKit.tubePivot(HAMMER_UPPER)
	)

	local lower = tube(model, skin, "HammerLower", HAMMER_LOWER, GRIP_D * 1.45, 0.24)
	local jointLower = PartKit.joint(
		upper,
		lower,
		PartKit.tubeTip(HAMMER_UPPER) * CFrame.Angles(math.rad(96), 0, 0),
		PartKit.tubePivot(HAMMER_LOWER)
	)

	local head = blob(model, skin, "HammerHead", Vector3.new(0.44, 0.4, 0.5), 0.34, PLATE_MATERIAL)
	PartKit.joint(lower, head, PartKit.tubeTip(HAMMER_LOWER), CFrame.new(0, 0, 0.1))

	-- The hammers carry the family dressing most visibly, because they are what moves.
	table.insert(
		anchors,
		{ part = upper, normal = Vector3.new(0, side, 0), scale = 0.7, upward = true, allowStrand = true }
	)
	table.insert(anchors, { part = head, normal = Vector3.yAxis, scale = 0.6, upward = true })

	return { upper = jointUpper, lower = jointLower, side = side }
end

function Calver.build(parent: Instance): Fly
	local model = Instance.new("Model")
	model.Name = "Calver"
	local skin: { Skinned } = {}
	local anchors: { CreatureDressing.Anchor } = {}

	-- The proxy follows the roof; the visible plate hangs from this private motor so bracing and
	-- recoil never move the authoritative presentation root or guess at ceiling geometry locally.
	local root = PartKit.part(model, {
		name = "PresentationRoot",
		size = Vector3.new(0.1, 0.1, 0.1),
		transparency = 1,
		castShadow = false,
	})
	local carapace = blob(model, skin, "Carapace", Vector3.new(CARAPACE_W, CARAPACE_H, CARAPACE_L), 0.32)
	local bodyJoint = PartKit.joint(root, carapace, CFrame.new())

	-- Overlapping back plates, running along the length. They break up what would otherwise be one
	-- flat oval and give a candle sweeping the roof something to catch on.
	for i = 1, 4 do
		local width = CARAPACE_W * (0.92 - (i - 1) * 0.13)
		local plate =
			blob(model, skin, "Plate" .. i, Vector3.new(width, CARAPACE_H * 0.5, CARAPACE_L * 0.3), 0.4, PLATE_MATERIAL)
		PartKit.joint(carapace, plate, CFrame.new(0, 0.16, CARAPACE_L * 0.3 - (i - 1) * (CARAPACE_L * 0.2)))
		table.insert(anchors, { part = plate, normal = Vector3.yAxis, scale = 0.55, upward = true })
	end

	-- The head hangs BELOW the carapace's leading edge, tilted to look at the floor.
	local head = blob(model, skin, "Head", Vector3.new(0.68, 0.4, 0.6), 0.38)
	local headJoint =
		PartKit.joint(carapace, head, CFrame.new(0, -0.18, -CARAPACE_L * 0.48) * CFrame.Angles(math.rad(28), 0, 0))

	local eyes: { BasePart } = {}
	local halos: { BasePart } = {}
	for _, side in { -1, 1 } do
		local halo = PartKit.neon(model, {
			name = "Halo",
			size = Vector3.new(0.26, 0.1, 0.08),
			color = EYE_IDLE,
			transparency = 0.66,
		})
		PartKit.joint(
			head,
			halo,
			CFrame.new(side * 0.19, -0.13, -0.16) * CFrame.Angles(0, 0, math.rad(side * EYE_ANGLE))
		)
		table.insert(halos, halo)

		local slit = PartKit.neon(model, {
			name = "Eye",
			size = Vector3.new(0.21, 0.055, 0.05),
			color = EYE_IDLE,
		})
		PartKit.joint(
			head,
			slit,
			CFrame.new(side * 0.19, -0.15, -0.18) * CFrame.Angles(0, 0, math.rad(side * EYE_ANGLE))
		)
		table.insert(eyes, slit)
	end

	local grips: { Grip } = {}
	local hammers: { Hammer } = {}
	for _, side in { -1, 1 } do
		table.insert(grips, buildGrip(model, skin, anchors, carapace, side, true))
		table.insert(grips, buildGrip(model, skin, anchors, carapace, side, false))
	end
	for _, side in { -1, 1 } do
		table.insert(hammers, buildHammer(model, skin, anchors, carapace, side))
	end

	local hitbox = PartKit.hitbox(model, carapace, Vector3.new(2.6, 1.4, 3), CFrame.new())

	PartKit.finalise(model, root, true)
	CollectionService:AddTag(model, "Creature")
	CollectionService:AddTag(model, "DarkHunter")
	model:SetAttribute("FleesLight", true)
	model:SetAttribute("CeilingBound", true)
	model.Parent = parent

	local self = setmetatable({
		model = model,
		root = root,
		bodyJoint = bodyJoint,
		hitbox = hitbox,
		grips = grips,
		hammers = hammers,
		skin = skin,
		dressAnchors = anchors,
		eyes = eyes,
		halos = halos,
		headJoint = headJoint,
		t = 0,
		lit = 0,
		lastPaintedIllumination = nil,
		aware = 0,
		moving = false,
		focus = nil,
		headYaw = 0,
		brace = 0,
		attackT = -1,
		attackLanded = true,
		pendingImpact = false,
		strike = 0,
	}, Calver)

	refreshEyes(self)
	return self
end

function Calver.setIllumination(self: Fly, lit01: number)
	self.lit = math.clamp(lit01, 0, 1)
	if self.lastPaintedIllumination ~= self.lit then
		self.lastPaintedIllumination = self.lit
		for _, s in self.skin do
			s.part.Color = s.base:Lerp(s.lit, self.lit)
		end
	end
	refreshEyes(self)
end

function Calver.setAware(self: Fly, aware01: number)
	self.aware = math.clamp(aware01, 0, 1)
	refreshEyes(self)
end

-- A roof-bound creature is never "moving" in the sense the gait systems mean. Accepted and ignored
-- so this body satisfies the same interface as the walkers and the controller needs no special case.
function Calver.setMoving(self: Fly, moving: boolean)
	self.moving = moving
end

function Calver.lookAt(self: Fly, worldPosition: Vector3?)
	self.focus = worldPosition
end

function Calver.strike(self: Fly, elapsed: number?)
	if self.attackT >= 0 then
		return
	end
	-- Timestamped visual intent may arrive after frame zero. Starting at the replicated age keeps
	-- the hammer contact aligned with the server's separate dripstone trigger on every client.
	self.attackT = math.max(0, elapsed or 0)
	self.attackLanded = false
	self.pendingImpact = false
end

function Calver.consumeImpact(self: Fly): boolean
	if self.pendingImpact then
		self.pendingImpact = false
		return true
	end
	return false
end

function Calver.applyFamilyTint(self: Fly, color: Color3, strength: number)
	local blend = math.clamp(strength, 0, 1)
	if blend <= 0 then
		return
	end
	for _, s in self.skin do
		s.base = s.base:Lerp(color, blend)
		s.lit = s.lit:Lerp(color, blend)
	end
	self.lastPaintedIllumination = nil
	Calver.setIllumination(self, self.lit)
end

function Calver.applyFamilyDressing(self: Fly, dressing: CreatureDressing.Dressing, seed: number)
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

function Calver.step(self: Fly, dt: number)
	self.t += dt
	local motion = Threats.visuals.procedural.attackMotion.Calver
	local raise = 0
	local hammer = 0
	local action = 0
	local actionBrace = 0
	local scrape = 0
	if self.attackT >= 0 then
		self.attackT += dt
		local anticipationEnd = motion.anticipationSeconds
		local strikeEnd = anticipationEnd + motion.strikeSeconds
		local total = strikeEnd + motion.recoverySeconds
		local time = math.min(self.attackT, total)
		if time < anticipationEnd then
			raise = smoothstep(time / anticipationEnd)
			action = raise
			actionBrace = raise
		elseif time < strikeEnd then
			local phase = smoothstep((time - anticipationEnd) / motion.strikeSeconds)
			raise = 1 - phase
			hammer = phase
			action = 1
			actionBrace = 1
		else
			local recoveryTime = time - strikeEnd
			if recoveryTime <= motion.impactHoldSeconds then
				hammer = 1
				action = 1
				actionBrace = 1
			else
				local settleTime = motion.recoverySeconds - motion.impactHoldSeconds
				local raw = (recoveryTime - motion.impactHoldSeconds) / settleTime
				local settle = smoothstep(raw)
				hammer = 1 - settle
				action = 1 - settle
				actionBrace = 1 - settle
				scrape = math.rad(motion.settleScrapeDegrees) * math.sin(raw * math.pi * 2) * (1 - settle)
			end
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
			self.strike = action
		end
		refreshEyes(self)
	end
	PartKit.pose(
		self.bodyJoint,
		CFrame.new(0, motion.bodyBraceStuds * actionBrace - motion.roofRecoilStuds * hammer, 0)
			* CFrame.Angles(scrape * 0.22, 0, scrape * 0.4)
	)

	-- THE BRACE. Grip limbs pull the body tighter to the rock as it rouses, which is both the honest
	-- physics of what it is about to do and the earliest visible sign that it has noticed anything.
	local targetBrace = math.max(self.aware, actionBrace)
	self.brace += (targetBrace - self.brace) * math.min(1, dt * 3)

	-- Looking DOWN and slightly toward whatever it has: the eyes are on the underside, so this is the
	-- pose that puts the crimson where a player beneath it can see it.
	local focus = self.focus
	local targetYaw = 0
	if focus ~= nil then
		local position = self.root.Position
		local flat = Vector3.new(focus.X - position.X, 0, focus.Z - position.Z)
		if flat.Magnitude > 0.05 then
			local forward = self.root.CFrame.LookVector
			targetYaw =
				math.clamp(math.atan2(flat.Unit:Cross(forward).Y, -flat.Unit:Dot(forward)), -math.rad(50), math.rad(50))
		end
	else
		targetYaw = math.sin(self.t * 0.4) * math.rad(16)
	end
	self.headYaw += (targetYaw - self.headYaw) * math.min(1, dt * 3.5)
	PartKit.pose(
		self.headJoint,
		CFrame.Angles(
			math.rad(self.brace * 8 + motion.headFocusPitchDegrees * actionBrace) - scrape * 0.25,
			self.headYaw,
			0
		)
	)

	-- Idle grip shuffle. Tiny, slow and out of phase per limb, so a stationary creature is still alive
	-- without ever reading as though it is about to move somewhere.
	for index, grip in self.grips do
		local shuffle = math.sin(self.t * (0.7 + index * 0.13)) * 0.03 * (1 - self.brace * 0.6)
		local impactBrace = math.rad(motion.elbowFoldDegrees) * actionBrace * 0.28
		PartKit.pose(grip.upper, CFrame.Angles(shuffle - self.brace * 0.18 - impactBrace, 0, 0))
		PartKit.pose(grip.lower, CFrame.Angles(self.brace * 0.26 - shuffle * 0.5 + impactBrace * 1.25, 0, 0))
	end

	-- THE STRIKE. A long, obvious wind-up back and up, then both hammers drive into the rock together.
	-- Deliberately slower and larger than any other attack animation in the game: this one is not
	-- trying to catch anybody, it is trying to be seen in time.
	for _, hammerLimb in self.hammers do
		local idle = math.sin(self.t * 0.9 + hammerLimb.side) * 0.02
		local upper = -math.rad(motion.forelimbRaiseDegrees) * raise
			+ math.rad(motion.forelimbHammerDegrees) * hammer
			+ idle
			- self.brace * 0.12
		PartKit.pose(hammerLimb.upper, CFrame.Angles(upper + scrape * hammerLimb.side * 0.35, 0, 0))
		PartKit.pose(
			hammerLimb.lower,
			CFrame.Angles(
				math.rad(motion.elbowFoldDegrees) * raise
					- math.rad(motion.elbowFoldDegrees) * 0.72 * hammer
					- scrape * hammerLimb.side,
				0,
				0
			)
		)
	end
end

function Calver.destroy(self: Fly)
	self.model:Destroy()
end

return Calver

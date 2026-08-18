--!strict
-- EnemyKit — builders, keyframe animation, and the variant system.
-- Place at: ReplicatedStorage/Enemies/EnemyKit
--
-- WHY KEYFRAMES AND NOT PROCEDURAL SINE
-- The previous pass drove every joint from trig. That reads acceptably on a
-- creature with four joints and turns to noise on one with thirty, because sine
-- functions have no strong poses — they are always mid-transition. Animation
-- reads well when it holds a clear silhouette, moves fast between silhouettes,
-- and settles. That is what a keyframe track gives you and what a sum of sines
-- structurally cannot.
--
-- Death and attack were the worst offenders for the same reason. A death is
-- four beats — react, lose support, fall, settle — and blending one continuous
-- curve across all of them makes it read as deflating rather than dying.

local CollectionService = game:GetService("CollectionService")

local EnemyKit = {}

-- ============================================================
-- EASING
-- Linear motion reads as mechanical. Everything here should accelerate or
-- decelerate. outBack gives an overshoot-and-settle that sells weight; inQuart
-- gives the accelerating collapse a falling body needs.
-- ============================================================
local Ease = {}
EnemyKit.Ease = Ease

function Ease.linear(t: number): number
	return t
end
function Ease.inQuad(t: number): number
	return t * t
end
function Ease.outQuad(t: number): number
	return 1 - (1 - t) * (1 - t)
end
function Ease.inOutQuad(t: number): number
	return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
end
function Ease.inCubic(t: number): number
	return t * t * t
end
function Ease.outCubic(t: number): number
	return 1 - (1 - t) ^ 3
end
function Ease.inOutCubic(t: number): number
	return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2
end
function Ease.inQuart(t: number): number
	return t * t * t * t
end
function Ease.outQuart(t: number): number
	return 1 - (1 - t) ^ 4
end
-- Overshoot then settle. The single most useful curve for making a strike land.
function Ease.outBack(t: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
function Ease.inBack(t: number): number
	local c1, c3 = 1.70158, 2.70158
	return c3 * t * t * t - c1 * t * t
end
-- For a body hitting the floor and not staying still.
function Ease.outBounce(t: number): number
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	end
	t -= 2.625 / d1
	return n1 * t * t + 0.984375
end
function Ease.outElastic(t: number): number
	if t == 0 or t == 1 then
		return t
	end
	return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

-- ============================================================
-- JOINTS
-- ============================================================
export type Joint = { motor: Motor6D, base: CFrame }

-- Every joint made during a build lands here so `finish` can rescale its REST POSE alongside the
-- geometry. It has to be collected rather than walked out of the model at the end, because `base` is
-- a Lua-side copy of the offset that the animation tracks rebuild `motor.C0` from every frame — a
-- rescale that only touches the Motor6D is thrown away by the first animated frame.
--
-- ONE SLOT IS ENOUGH. A build is a single synchronous `X.build()` call that only creates instances
-- and never yields, so `begin` opens this and `finish` closes it with nothing able to interleave.
local activeJoints: { Joint }? = nil

function EnemyKit.joint(part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame?): Joint
	local m = Instance.new("Motor6D")
	m.Name = part1.Name .. "Joint"
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1 or CFrame.new()
	m.Parent = part0
	local j: Joint = { motor = m, base = c0 }
	if activeJoints ~= nil then
		table.insert(activeJoints, j)
	end
	return j
end

function EnemyKit.pose(j: Joint?, rx: number, ry: number, rz: number)
	if not j then
		return
	end
	j.motor.C0 = j.base * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end

function EnemyKit.poseOffset(j: Joint?, offset: CFrame)
	if not j then
		return
	end
	j.motor.C0 = j.base * offset
end

-- ============================================================
-- KEYFRAME TRACKS
-- A pose maps joint names to {rx, ry, rz} in radians. A track is a list of
-- poses at times, each with the easing used to arrive at it. Joints absent from
-- a key hold their previous value, so you only author what moves.
-- ============================================================
export type Pose = { [string]: { number } }
export type Key = { t: number, pose: Pose, ease: string? }
export type Track = { keys: { Key }, length: number, loop: boolean }

function EnemyKit.track(keys: { Key }, loop: boolean?): Track
	local len = 0
	for _, k in keys do
		if k.t > len then
			len = k.t
		end
	end
	return { keys = keys, length = len, loop = loop or false }
end

local ZERO = { 0, 0, 0 }

-- Walks backward from the current key to find the last one that specified this
-- joint, so partial keys work.
local function lastValue(keys: { Key }, upto: number, name: string): { number }
	for i = upto, 1, -1 do
		local v = keys[i].pose[name]
		if v then
			return v
		end
	end
	return ZERO
end

function EnemyKit.evaluate(joints: { [string]: Joint }, track: Track, time: number)
	local t = time
	if track.loop and track.length > 0 then
		t = t % track.length
	else
		t = math.clamp(t, 0, track.length)
	end

	local keys = track.keys
	local iA, iB = 1, 1
	for i = 1, #keys do
		if keys[i].t <= t then
			iA = i
			iB = math.min(i + 1, #keys)
		end
	end

	local a, b = keys[iA], keys[iB]
	local span = b.t - a.t
	local raw = if span > 0 then (t - a.t) / span else 1
	local easeFn = (Ease :: any)[b.ease or "inOutCubic"] or Ease.inOutCubic
	local k = easeFn(math.clamp(raw, 0, 1))

	for name, joint in joints do
		local va = a.pose[name] or lastValue(keys, iA, name)
		local vb = b.pose[name] or va
		EnemyKit.pose(
			joint,
			va[1] + (vb[1] - va[1]) * k,
			va[2] + (vb[2] - va[2]) * k,
			va[3] + (vb[3] - va[3]) * k
		)
	end
end

-- Additive breathing/idle noise layered on top of a track, so nothing is ever
-- perfectly still. Apply after evaluate().
function EnemyKit.breathe(j: Joint?, time: number, rate: number, amount: number, phase: number?)
	if not j then
		return
	end
	local s = math.sin(time * rate + (phase or 0)) * amount
	j.motor.C0 = j.motor.C0 * CFrame.Angles(s, s * 0.4, 0)
end


-- ============================================================
-- PALETTES AND VARIANTS
--
-- Variety comes from three stacked layers, not one:
--   1. Per-instance colour jitter, so no two spawns are identical even in the
--      same biome.
--   2. A decoration ROLL per anchor rather than a fixed count, so placement
--      differs every spawn.
--   3. A rare "elder" roll that changes silhouette, not just texture.
-- Repeating the exact same decoration set on every spawn is what makes a
-- variant read as a palette swap instead of a different creature.
-- ============================================================
export type Variant = "regular" | "moss" | "ice"
export type Role = "rock" | "chit" | "soft" | "pale" | "tooth" | "sac" | "wax"

local PALETTE: { [string]: any } = {
	regular = {
		rock = { Color3.fromRGB(128, 109, 82), Color3.fromRGB(112, 94, 69), Color3.fromRGB(141, 120, 90), Color3.fromRGB(99, 83, 61) },
		chit = { Color3.fromRGB(74, 65, 56), Color3.fromRGB(61, 53, 45), Color3.fromRGB(87, 76, 64), Color3.fromRGB(51, 44, 38) },
		soft = Color3.fromRGB(107, 90, 68),
		pale = Color3.fromRGB(176, 160, 132),
		tooth = Color3.fromRGB(200, 189, 164),
		sac = Color3.fromRGB(216, 160, 82),
		wax = Color3.fromRGB(226, 190, 124),
		eye = Color3.fromRGB(216, 56, 32),
		glow = Color3.fromRGB(255, 138, 60),
	},
	moss = {
		rock = { Color3.fromRGB(95, 107, 74), Color3.fromRGB(81, 92, 63), Color3.fromRGB(107, 122, 82), Color3.fromRGB(66, 74, 51) },
		chit = { Color3.fromRGB(58, 66, 52), Color3.fromRGB(48, 54, 42), Color3.fromRGB(71, 80, 60), Color3.fromRGB(39, 44, 34) },
		soft = Color3.fromRGB(74, 87, 64),
		pale = Color3.fromRGB(138, 152, 120),
		tooth = Color3.fromRGB(184, 192, 160),
		sac = Color3.fromRGB(168, 196, 106),
		wax = Color3.fromRGB(196, 214, 140),
		eye = Color3.fromRGB(200, 208, 64),
		glow = Color3.fromRGB(159, 216, 92),
	},
	ice = {
		rock = { Color3.fromRGB(133, 149, 160), Color3.fromRGB(116, 131, 142), Color3.fromRGB(150, 167, 179), Color3.fromRGB(95, 108, 118) },
		chit = { Color3.fromRGB(99, 112, 123), Color3.fromRGB(84, 95, 105), Color3.fromRGB(116, 130, 142), Color3.fromRGB(69, 78, 87) },
		soft = Color3.fromRGB(124, 138, 149),
		pale = Color3.fromRGB(196, 212, 222),
		tooth = Color3.fromRGB(228, 242, 250),
		sac = Color3.fromRGB(214, 240, 255),
		wax = Color3.fromRGB(224, 244, 255),
		eye = Color3.fromRGB(96, 216, 240),
		glow = Color3.fromRGB(191, 232, 255),
	},
}

local MATERIAL: { [string]: { Enum.Material } } = {
	rock = { Enum.Material.Sandstone, Enum.Material.Slate, Enum.Material.Concrete },
	chit = { Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.Concrete },
	soft = { Enum.Material.Concrete, Enum.Material.Sandstone },
	pale = { Enum.Material.Concrete },
	tooth = { Enum.Material.Glass },
	sac = { Enum.Material.Glass },
	wax = { Enum.Material.Glass },
}

export type Build = {
	model: Model,
	variant: Variant,
	rng: Random,
	elder: boolean,
	anchors: { { host: BasePart, at: CFrame, scale: number } },
	joints: { Joint },
	scale: number,
	_i: number,
}

-- `scale` is the body's FINISHED size relative to the numbers written in its build function, applied
-- once in `finish`. It exists because a pack module's geometry is authored in whatever units that
-- creature was drawn at, which is not necessarily the scale its own gameplay numbers assume — the
-- Longarm is the standing example (see its BODY_SCALE). Writing it here rather than editing a
-- hundred hand-tuned dimensions keeps the anatomy and the animation poses exactly as authored.
function EnemyKit.begin(name: string, variant: Variant, seed: number?, scale: number?): Build
	local model = Instance.new("Model")
	model.Name = name
	local s = seed or math.random(1, 2 ^ 30)
	local rng = Random.new(s)
	model:SetAttribute("Seed", s)
	-- Elder: 1 in 12. Bigger, darker, heavily overgrown. A silhouette change
	-- rather than a tint, so players notice it across a room.
	local elder = rng:NextNumber() < 0.085
	model:SetAttribute("Elder", elder)
	local joints: { Joint } = {}
	activeJoints = joints
	return {
		model = model,
		variant = variant,
		rng = rng,
		elder = elder,
		anchors = {},
		joints = joints,
		scale = scale or 1,
		_i = 0,
	}
end

local function jitter(c: Color3, rng: Random): Color3
	local d = (rng:NextNumber() - 0.5) * 0.09
	return Color3.new(math.clamp(c.R + d, 0, 1), math.clamp(c.G + d, 0, 1), math.clamp(c.B + d, 0, 1))
end

function EnemyKit.color(b: Build, role: Role, index: number?): Color3
	local p = PALETTE[b.variant]
	local c: Color3
	if role == "rock" or role == "chit" then
		c = p[role][((index or b._i) % 4) + 1]
	else
		c = p[role]
	end
	if b.elder then
		c = c:Lerp(Color3.new(0, 0, 0), 0.28)
	end
	return jitter(c, b.rng)
end

function EnemyKit.emissive(b: Build, which: "eye" | "glow"): Color3
	return PALETTE[b.variant][which]
end

local function dress(b: Build, p: BasePart, role: Role, shadow: boolean?)
	b._i += 1
	p.Color = EnemyKit.color(b, role)
	local mats = MATERIAL[role]
	p.Material = mats[(b._i % #mats) + 1]
	if role == "tooth" then
		p.Reflectance = 0.18
	elseif role == "sac" or role == "wax" then
		p.Reflectance = 0.06
		p.Transparency = 0.28
	end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = b.model
end

function EnemyKit.block(b: Build, name: string, size: Vector3, role: Role, shadow: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	dress(b, p, role, shadow)
	return p
end

function EnemyKit.blob(b: Build, name: string, size: Vector3, role: Role, shadow: boolean?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = size
	dress(b, p, role, shadow)
	return p
end

function EnemyKit.wedge(b: Build, name: string, size: Vector3, role: Role, shadow: boolean?): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	dress(b, p, role, shadow)
	return p
end

function EnemyKit.neon(b: Build, name: string, size: Vector3, which: "eye" | "glow", transparency: number?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = size
	p.Color = EnemyKit.emissive(b, which)
	p.Material = Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = b.model
	return p
end

-- Register a surface where variant decoration may grow. Backs and joints only,
-- never faces: dressing over an eye or a mouth destroys the silhouette the
-- model was designed around.
function EnemyKit.anchor(b: Build, host: BasePart, at: CFrame, scale: number)
	table.insert(b.anchors, { host = host, at = at, scale = scale })
end

-- Rolls decoration per anchor rather than placing a fixed count, so two spawns
-- of the same enemy in the same biome are visibly different objects.
function EnemyKit.applyVariant(b: Build)
	if b.variant == "regular" and not b.elder then
		return
	end
	local rng = b.rng
	local density = if b.elder then 1.9 else 1.0

	for _, a in b.anchors do
		if b.variant == "regular" then
			-- Elder in a regular cave still gets growth, just sparse.
			if rng:NextNumber() > 0.45 then
				continue
			end
		end
		local roll = rng:NextNumber() * density
		local count = if roll < 0.35 then 1 elseif roll < 0.8 then 2 elseif roll < 1.4 then 3 else 4
		for _ = 1, count do
			local s = a.scale * (0.45 + rng:NextNumber() * 0.85)
			local spin = CFrame.new(
				(rng:NextNumber() - 0.5) * a.scale,
				0,
				(rng:NextNumber() - 0.5) * a.scale
			) * CFrame.Angles(
				math.rad((rng:NextNumber() - 0.5) * 44),
				rng:NextNumber() * 6.28,
				math.rad((rng:NextNumber() - 0.5) * 44)
			)

			local p: BasePart
			local kind = rng:NextNumber()
			if b.variant == "ice" then
				if kind < 0.68 then
					p = Instance.new("WedgePart")
					p.Size = Vector3.new(s * 0.45, s * 1.9, s * 0.45)
					p.Color = Color3.fromRGB(216, 238, 252)
					p.Material = Enum.Material.Glacier
					p.Transparency = 0.16
					p.Reflectance = 0.14
					p.Name = "Shard"
				else
					-- flat frost patch, breaks up the shard repetition
					p = Instance.new("Part")
					p.Size = Vector3.new(s * 2.2, s * 0.12, s * 2.0)
					p.Color = Color3.fromRGB(232, 246, 255)
					p.Material = Enum.Material.Glacier
					p.Transparency = 0.3
					p.Name = "Frost"
				end
			else
				if kind < 0.6 then
					p = Instance.new("Part")
					p.Size = Vector3.new(s * 1.5, s * 0.34, s * 1.5)
					p.Color = Color3.fromRGB(126, 163, 78)
					p.Material = Enum.Material.Grass
					p.Name = "Moss"
				elseif kind < 0.86 then
					-- hanging strand, gives moss a vertical element
					p = Instance.new("Part")
					p.Size = Vector3.new(s * 0.16, s * 2.4, s * 0.16)
					p.Color = Color3.fromRGB(104, 138, 66)
					p.Material = Enum.Material.Grass
					p.Name = "Strand"
					spin = spin * CFrame.new(0, -s * 1.2, 0)
				else
					-- cap, rare
					p = Instance.new("Part")
					p.Shape = Enum.PartType.Ball
					p.Size = Vector3.new(s * 1.1, s * 0.5, s * 1.1)
					p.Color = Color3.fromRGB(178, 176, 128)
					p.Material = Enum.Material.Concrete
					p.Name = "Cap"
				end
			end
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = b.model
			EnemyKit.joint(a.host, p, a.at * spin)
		end
	end
end

EnemyKit.VariantStats = {
	regular = { health = 1.0, speed = 1.0, fireDamage = 1.0 },
	moss = { health = 1.35, speed = 0.8, fireDamage = 0.75 },
	ice = { health = 0.7, speed = 1.25, fireDamage = 1.6 },
}
EnemyKit.ElderStats = { health = 2.2, speed = 0.9, scale = 1.18 }

-- ============================================================
-- FINALISE
-- Visual parts never collide and never answer queries. One Hitbox part carries
-- detection; a few invisible primitives carry physics. Limb geometry eating a
-- raycast is the most common cause of "why did that not register".
-- ============================================================
function EnemyKit.hitbox(b: Build, root: BasePart, size: Vector3, offset: CFrame?): BasePart
	local h = Instance.new("Part")
	h.Name = "Hitbox"
	h.Size = size
	h.Transparency = 1
	h.CanCollide = false
	h.CanQuery = true
	h.CanTouch = true
	h.CastShadow = false
	h.Massless = true
	h.Parent = b.model
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = h
	w.C0 = offset or CFrame.new()
	w.Parent = h
	return h
end

function EnemyKit.collider(b: Build, root: BasePart, size: Vector3, offset: CFrame)
	local c = Instance.new("Part")
	c.Name = "Collider"
	c.Size = size
	c.Transparency = 1
	c.CanCollide = true
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.Massless = true
	c.Parent = b.model
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = c
	w.C0 = offset
	w.Parent = c
end

-- PLACE THE WHOLE RIG IN ITS REST POSE, IN THE BUILD FRAME. A HOST ADDITION, and the fix for every
-- pack creature standing in the floor.
--
-- Nothing in this file ever writes a part's CFrame: every part is created at the world origin and
-- `EnemyKit.joint` only creates the Motor6D that will eventually put it somewhere. The engine
-- resolves that chain when the assembly is simulated — which is at best the physics step AFTER the
-- model is parented into the world, and the constructors are long finished by then. So for the whole
-- of the spawn frame the built creature is not a creature: it is every part stacked inside the root,
-- and ANY MEASUREMENT TAKEN OF IT IS A MEASUREMENT OF THE ROOT BLOCK.
--
-- Three things measure exactly then, and all three were being lied to:
--   * `EnemyMover.measureRideHeight` — how far the root sits above the body's lowest point. Read off
--     the stack it returns half the tallest part instead of the standing height, so the spawn lift is
--     a stud or more short and `Humanoid.HipHeight` comes out near zero. The Humanoid then holds the
--     root's underside on the rock with the legs below it inside the floor, and every `reseat`
--     correction is undone by the controller on the next step. THIS IS THE CREATURE-IN-THE-GROUND BUG.
--   * `WaxGrubBehavior.seat` — the same number for the CFrame-driven grub.
--   * `EnemyService.auditSeating` — the independent check that was supposed to CATCH all of this. It
--     walks per-part CFrames, so on a collapsed rig it measures the root's own box, finds it sitting
--     perfectly on the ground, and never warns. That is why every report of this has come from
--     somebody looking at a screenshot.
--
-- The walk below is the engine's own rule (`Part1 = Part0 * C0 * C1⁻¹`) applied breadth-first from the
-- root, so it produces exactly the pose the joint solver would have produced, one frame earlier and
-- without needing the model to be in the world. Welds are included because the Hitbox and Collider
-- hang off root that way. It runs once per body, at build.
local function settle(model: Model, root: BasePart)
	local byPart0: { [BasePart]: { JointInstance } } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("Weld") then
			local part0 = descendant.Part0
			if part0 ~= nil and descendant.Part1 ~= nil then
				local list = byPart0[part0]
				if list == nil then
					byPart0[part0] = { descendant }
				else
					table.insert(list, descendant)
				end
			end
		end
	end

	-- Breadth-first from the root, marking as we go: a part is placed by the FIRST joint that reaches
	-- it, and a rig that somehow closed a loop would otherwise walk itself forever.
	local placed: { [BasePart]: boolean } = { [root] = true }
	local queue: { BasePart } = { root }
	local index = 1
	while index <= #queue do
		local part = queue[index]
		index += 1
		local joints = byPart0[part]
		if joints ~= nil then
			for _, joint in joints do
				local child = joint.Part1 :: BasePart
				if not placed[child] then
					placed[child] = true
					child.CFrame = part.CFrame * joint.C0 * joint.C1:Inverse()
					table.insert(queue, child)
				end
			end
		end
	end
end

-- How much air to leave under the collidable box. Not zero: the box would then scrape every lump in
-- a voxel floor while the body walks normally, and the physics engine answers a penetrating box by
-- shoving it upward, which is a creature that judders across the room. A sixth of a stud is under the
-- resolution of the terrain and still turns a lost-footing drop into nothing.
local COLLIDER_FOOT_CLEARANCE = 0.15

-- FIT THE COLLIDABLE BOX TO THE BODY THAT WAS ACTUALLY BUILT, so it reaches the ground the creature
-- is standing on. A HOST ADDITION, and the fix for a body that sinks to its belly the instant
-- anything interrupts it.
--
-- The pack authors one invisible `Collider` per creature around the TORSO, which is the correct shape
-- for the pack's own assumption that the host drives these bodies by CFrame. This game drives three of
-- them with a Humanoid instead, and a Humanoid body is held above the floor by its controller alone —
-- so the collider is the only thing that catches the body when the controller lets go (a teleport, a
-- Freefall transition, a stagger). Measured on the settled rigs, the authored boxes end far short of
-- the feet: 1.31 studs of air under the Stone Gnawer, 5.68 under the Longarm. That gap IS the fall:
-- lose the floor for one frame and the body drops until the box lands, which buries the legs and puts
-- the root too low for the controller to stand up again until whatever it was doing ends. It is also
-- why the drop always ENDS with the creature popping back up — the controller recovers the moment it
-- can, and nothing was ever broken except the height.
--
-- Only the BOTTOM moves. The top, the width and the depth are the author's decisions about what this
-- creature's mass occupies; where its feet are is a measurement, and only a measurement can know it.
local function fitCollider(model: Model, root: BasePart)
	-- The VISIBLE silhouette: the feet a player can see, not the invisible volumes. The Hitbox and the
	-- colliders are transparent by construction, so this is the art and only the art.
	local lowest = math.huge
	local colliders: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		if part.Name == "Collider" then
			table.insert(colliders, part)
		end
		if part.Transparency < 1 then
			local frame, size = part.CFrame, part.Size
			local halfHeight = (
				math.abs(frame.RightVector.Y) * size.X
				+ math.abs(frame.UpVector.Y) * size.Y
				+ math.abs(frame.LookVector.Y) * size.Z
			) / 2
			lowest = math.min(lowest, frame.Position.Y - halfHeight)
		end
	end
	if lowest == math.huge then
		return
	end

	-- EVERY collider, not the first one found: the Grub Queen is two boxes down one long body, and
	-- fitting only the thorax would leave her abdomen hanging over the floor by itself.
	for _, collider in colliders do
		-- A rotated box cannot be extended along world Y by changing one component of its size. None of
		-- the pack's colliders are rotated; if one ever is, leave it as authored rather than deform it.
		if math.abs(collider.CFrame.UpVector.Y - 1) > 0.01 then
			continue
		end
		local weld: Weld? = nil
		for _, child in collider:GetChildren() do
			if child:IsA("Weld") and child.Part1 == collider then
				weld = child
				break
			end
		end
		if weld == nil then
			continue
		end

		local top = collider.CFrame.Position.Y + collider.Size.Y * 0.5
		local desiredBottom = lowest + COLLIDER_FOOT_CLEARANCE
		local height = top - desiredBottom
		-- Already reaching (the grub is nearly there on its own) — leave it alone rather than shrink a
		-- box an author deliberately made deeper than the art.
		if height <= collider.Size.Y then
			continue
		end

		collider.Size = Vector3.new(collider.Size.X, height, collider.Size.Z)
		-- THE WELD IS WHAT HOLDS IT THERE, so the offset has to move with the box: writing only the
		-- part's CFrame lasts until the joint solver puts it back at the old offset on the next step.
		-- Everything is still built axis-aligned at the origin here (constructors pivot the finished
		-- model), so root space and world Y are the same axis.
		local centre = desiredBottom + height * 0.5
		local offset = weld.C0.Position
		weld.C0 = CFrame.new(offset.X, centre - root.CFrame.Position.Y, offset.Z) * (weld.C0 - offset)
		collider.CFrame = root.CFrame * weld.C0 * weld.C1:Inverse()
	end
end

-- Offsets scale, rotations do not. Splitting the CFrame is the whole of it.
local function scaleOffset(cf: CFrame, s: number): CFrame
	return CFrame.new(cf.Position * s) * (cf - cf.Position)
end

-- Grow (or shrink) a finished rig about its root. Sizes, joint offsets and the Lua-side rest poses
-- all move together; miss any one of the three and the body comes apart.
local function rescale(b: Build, s: number)
	for _, d in b.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size = d.Size * s
		end
	end
	-- BOTH SIDES OF EVERY JOINT, and Welds as well as Motor6Ds. C1 places the pivot inside the CHILD
	-- part — every limb in the pack uses it to hinge at an end rather than a centre — and the Hitbox
	-- and Collider hang off the root on plain Welds, so a pass that only scaled Motor6D.C0 would leave
	-- limbs telescoping out of their sockets and the detection volume sitting at the old offset.
	for _, d in b.model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Weld") then
			d.C0 = scaleOffset(d.C0, s)
			d.C1 = scaleOffset(d.C1, s)
		end
	end
	-- The rest pose the animation rebuilds `motor.C0` from every frame (`pose`: `base * angles`).
	-- Without this the rig is correct exactly until the first `evaluate` and then snaps back.
	for _, j in b.joints do
		j.base = scaleOffset(j.base, s)
	end
end

function EnemyKit.finish(b: Build, root: BasePart, id: string, tier: number): Model
	EnemyKit.applyVariant(b)
	b.model.PrimaryPart = root
	root.Anchored = false
	for _, d in b.model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
		end
	end
	-- The body's own scale and the elder bonus are one multiplication, applied after `applyVariant` so
	-- that decoration grown onto the rig scales with the surface it grew on.
	local s = b.scale * (if b.elder then EnemyKit.ElderStats.scale else 1)
	if s ~= 1 then
		rescale(b, s)
	end
	b.model:SetAttribute("BodyScale", s)
	activeJoints = nil
	-- AFTER the scale pass above, which rescales both the parts and the joint offsets: settling first
	-- would pose the rig and then move every joint out from under it.
	settle(b.model, root)
	-- AFTER `settle`, which is what makes the feet measurable in the first place.
	fitCollider(b.model, root)
	CollectionService:AddTag(b.model, "Enemy")
	CollectionService:AddTag(b.model, id)
	b.model:SetAttribute("EnemyId", id)
	b.model:SetAttribute("Variant", b.variant)
	b.model:SetAttribute("Tier", tier)
	b.model:SetAttribute("State", "idle")
	return b.model
end

-- 3D sound rig. Distances assume sight reaches ~20 studs, so hearing must
-- reach 60+ or threats arrive with no telegraph at all.
function EnemyKit.emitter(host: BasePart, assetId: string, name: string, looped: boolean, volume: number, minD: number, maxD: number): Sound?
	if assetId == "" then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = name .. "Point"
	a.Parent = host
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = assetId
	s.Looped = looped
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = minD
	s.RollOffMaxDistance = maxD
	s.Parent = a
	return s
end

return EnemyKit

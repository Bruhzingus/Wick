--!strict
-- GrubQueen — floor boss. Appears every 10-15 floors.
-- Place at: ReplicatedStorage/Enemies/GrubQueen
--
-- SHE IS A GRUB, NOT A ROCK. The previous version was a mound of stone with
-- vents in it, which read as terrain rather than as a creature and gave the
-- Wax Grubs no visual parent. She is now an enormously engorged version of the
-- grub the player has been stepping on all game: same segmentation, same
-- mandibles, same wax sacs, forty times the mass.
--
-- THE FIGHT, in a game with no player attack:
--   * She drags herself toward you and cannot be damaged conventionally.
--   * She continuously births Wax Grubs.
--   * Two Longarms are chained to her and patrol as bodyguards.
--   * The player circles the chamber gathering wax to stay alive and dynamite
--     to kill her, while being slowly worn down.
--   * Only dynamite damages her. Everything else is survival.
--
-- The design intent is a resource race under pressure, not a damage race. The
-- Longarms are the pressure, the grubs are the attrition, and the wax pickups
-- are the timer you can extend.
--
-- SHE MOVES NOW, AND THE POINT IS THAT SHE IS SLOW. The pack shipped her fully
-- immobile, which made her a wall with a timer: once the player found a corner
-- her head was not pointed at, the encounter had nothing left to say. She now
-- crawls at 1.8 studs a second against a player who walks at 8 and runs at 16 —
-- she cannot catch anybody, ever, and is not meant to. What she takes away is
-- the corner. She is a slow tide across a room you have to keep working in.
--
-- AND SHE BITES ANYTHING THAT COMES TO HER. Her mandibles reach seven studs and
-- she takes most of a candle with them (Config/GrubQueen.biteDamage), which is
-- the biggest single hit in the game. Two things make that fair: it is
-- telegraphed by a slow rear-back, and it only lands in the arc in FRONT of
-- her. She turns at 24 degrees a second, so getting behind her works and staying
-- there is the actual skill the fight asks for.

local EnemyKit = require(script.Parent.EnemyKit)

local GrubQueen = {}
GrubQueen.__index = GrubQueen

GrubQueen.Config = {
	-- Only dynamite hurts her. Sized so a run yields roughly 5-7 charges.
	health = 6,
	dynamiteDamage = 1,
	broodInterval = 7.5,
	broodCount = 2,
	-- Kept in step with `Config/GrubQueen.maxLiveGrubs`, which is the copy the brain reads.
	maxLiveGrubs = 10,
	-- Enslaved bodyguards. Spawned by the encounter, not by her.
	guardCount = 2,
	callInterval = 26,
	segmentCount = 9,
	-- HOW SHE MOVES. Studs per second and degrees per second, and both are deliberately hopeless as
	-- a pursuit: 1.8 against a walk of 8, and a turn that takes fifteen seconds to come about. She is
	-- denial of ground, not a chase. The integration reads Config/GrubQueen's copies of these.
	crawlSpeed = 1.8,
	turnDegreesPerSecond = 24,
	-- THE BITE, in track time. `contact` is when the mandibles actually shut, and it is late on
	-- purpose: everything before it is the rear-back the player is being given to read.
	biteWindupSeconds = 0.52,
	biteContactSeconds = 0.72,
	biteSeconds = 1.45,
}

local SOUNDS = { churn = "", birth = "", call = "", hurt = "", death = "" }
local rad = math.rad

-- ============================================================
-- ANIMATION
-- A peristaltic wave travels tail-to-head. Segment i lags segment i-1, which is
-- what makes a fat immobile thing read as alive rather than as scenery.
-- ============================================================
local T = {}

local function wave(offsetPhase: number, amp: number, headAmp: number, yawBias: number?)
	local pose: any = {}
	-- `yawBias` multiplies the SIDEWAYS half of the wave. At rest she undulates mostly vertically —
	-- a fat thing breathing — and at 1 that is what this returns. Crawling passes a big one, because a
	-- legless body does not pull itself along by rippling up and down: it throws its length side to
	-- side and drags itself off the curve, and the pitch component is only there to stop the wiggle
	-- reading as flat.
	local yaw = yawBias or 1
	for i = 1, GrubQueen.Config.segmentCount do
		local ph = offsetPhase - i * 0.55
		pose["s" .. i] = { rad(math.sin(ph) * amp), rad(math.cos(ph * 0.7) * amp * 0.6 * yaw), 0 }
	end
	pose.head = { rad(math.sin(offsetPhase + 0.6) * headAmp), rad(math.cos(offsetPhase * 0.5) * headAmp), 0 }
	return pose
end

T.idle = EnemyKit.track({
	{ t = 0.0, pose = wave(0.0, 4.5, 3), ease = "inOutQuad" },
	{ t = 1.6, pose = wave(1.6, 4.5, 3), ease = "inOutQuad" },
	{ t = 3.2, pose = wave(3.2, 4.5, 3), ease = "inOutQuad" },
	{ t = 4.8, pose = wave(4.8, 4.5, 3), ease = "inOutQuad" },
	{ t = 6.4, pose = wave(6.28, 4.5, 3), ease = "inOutQuad" },
}, true)

-- CRAWLING, AND IT IS A WIGGLE. A legless body of this mass does not pull itself along by rippling
-- up and down — it throws its whole length side to side and drags itself off the curve, the way a
-- maggot or a snake does. So the crawl runs the same wave as the idle with the SIDEWAYS component
-- tripled and the amplitude roughly doubled: the tail sweeps a wide arc behind her, the head leads
-- it, and the vertical component is left small so the wiggle is unmistakably horizontal.
--
-- IT IS STILL THE SAME WAVE FUNCTION ON PURPOSE. A player watching her from across the chamber has
-- to be able to tell she is coming, and the tell is the RATE and the WIDTH of a motion they have
-- already been watching her make at rest — not a second animation, which would read as a different
-- creature rather than as the same one bearing down.
T.crawl = EnemyKit.track({
	{ t = 0.0, pose = wave(0.0, 9.5, 7, 3.2), ease = "inOutQuad" },
	{ t = 0.9, pose = wave(1.6, 9.5, 7, 3.2), ease = "inOutQuad" },
	{ t = 1.8, pose = wave(3.2, 9.5, 7, 3.2), ease = "inOutQuad" },
	{ t = 2.7, pose = wave(4.8, 9.5, 7, 3.2), ease = "inOutQuad" },
	{ t = 3.6, pose = wave(6.28, 9.5, 7, 3.2), ease = "inOutQuad" },
}, true)

-- THE BITE. Rear, hang, then everything comes down at once.
--
-- THE HANG IS THE FAIRNESS. She lifts her head over half a second and holds it there before anything
-- lands, which on a creature this size is a shape visible from across the room — and the contact test
-- is taken at the moment the mandibles shut, not when the animation started, so backing out of the
-- arc during the rear WORKS. A hit that was decided at the windup would make the telegraph a lie.
--
-- NOTHING BEHIND THE NECK MOVES, AND THAT IS NOT A STYLE CHOICE. `s1`..`s9` are the ABDOMEN, and they
-- are a chain: a rotation at `s1` compounds through all nine joints, so the -26 degrees this track
-- used to put there swung the ovipositor thirteen studs while the head barely travelled. Measured,
-- not guessed — and it is why the attack read as "she raises her tail at you" rather than as a bite.
-- The head, the neck and the mandibles are the entire animation now, and they are the only parts that
-- have any business in one.
-- The abdomen is named at zero and left there for the whole bite, which is what the animation system
-- would do with it anyway (a joint no keyframe mentions reads as zero) — stated explicitly because it
-- is the right pose rather than an accident: she braces her length straight and drives off it. It also
-- means the wiggle she was crawling with stops dead the instant she commits, which is the tell.
T.bite = EnemyKit.track({
	{
		t = 0.00,
		pose = {
			head = { 0, 0, 0 },
			neck = { 0, 0, 0 },
			mandL = { 0, rad(-14), 0 },
			mandR = { 0, rad(14), 0 },
			s1 = { 0, 0, 0 },
			s2 = { 0, 0, 0 },
			s3 = { 0, 0, 0 },
			s4 = { 0, 0, 0 },
			s5 = { 0, 0, 0 },
			s6 = { 0, 0, 0 },
			s7 = { 0, 0, 0 },
			s8 = { 0, 0, 0 },
			s9 = { 0, 0, 0 },
		},
	},
	-- rear: the head climbs and the mandibles open to their widest. Bigger than it was, because it is
	-- now carrying the whole telegraph on its own rather than borrowing the abdomen's travel.
	{
		t = 0.52,
		pose = {
			head = { rad(-72), 0, 0 },
			neck = { rad(-52), 0, 0 },
			mandL = { 0, rad(-84), 0 },
			mandR = { 0, rad(84), 0 },
		},
		ease = "outCubic",
	},
	-- the hang, barely moving. This is the frame the player is supposed to read.
	{
		t = 0.62,
		pose = {
			head = { rad(-76), 0, 0 },
			neck = { rad(-55), 0, 0 },
			mandL = { 0, rad(-88), 0 },
			mandR = { 0, rad(88), 0 },
		},
		ease = "inOutQuad",
	},
	-- DOWN. Head and neck drive forward and the mandibles shut on whatever is in front of them.
	{
		t = 0.72,
		pose = {
			head = { rad(52), 0, 0 },
			neck = { rad(38), 0, 0 },
			mandL = { 0, rad(-2), 0 },
			mandR = { 0, rad(2), 0 },
		},
		ease = "inQuart",
	},
	-- worry it, the way anything with mandibles does
	{
		t = 0.96,
		pose = {
			head = { rad(42), rad(-14), 0 },
			neck = { rad(30), rad(-8), 0 },
			mandL = { 0, rad(-22), 0 },
			mandR = { 0, rad(22), 0 },
		},
		ease = "outQuad",
	},
	{
		t = 1.16,
		pose = {
			head = { rad(44), rad(14), 0 },
			neck = { rad(32), rad(8), 0 },
			mandL = { 0, rad(-6), 0 },
			mandR = { 0, rad(6), 0 },
		},
		ease = "inOutQuad",
	},
	{
		t = 1.45,
		pose = { head = { 0, 0, 0 }, neck = { 0, 0, 0 }, mandL = { 0, rad(-14), 0 }, mandR = { 0, rad(14), 0 } },
		ease = "inOutCubic",
	},
})

-- A contraction runs the length of her, the ovipositor flares, a grub drops.
T.birth = EnemyKit.track({
	{
		t = 0.00,
		pose = { s7 = { 0, 0, 0 }, s8 = { 0, 0, 0 }, s9 = { 0, 0, 0 }, ovi = { 0, 0, 0 }, head = { 0, 0, 0 } },
	},
	{
		t = 0.35,
		pose = {
			s5 = { rad(-9), 0, 0 },
			s6 = { rad(-12), 0, 0 },
			s7 = { rad(-16), 0, 0 },
			s8 = { rad(-20), 0, 0 },
			s9 = { rad(-24), 0, 0 },
			ovi = { rad(-16), 0, 0 },
			head = { rad(6), 0, 0 },
		},
		ease = "inQuad",
	},
	{
		t = 0.62,
		pose = { s7 = { rad(18), 0, 0 }, s8 = { rad(24), 0, 0 }, s9 = { rad(30), 0, 0 }, ovi = { rad(44), 0, 0 } },
		ease = "outQuart",
	},
	{
		t = 1.10,
		pose = {
			s5 = { 0, 0, 0 },
			s6 = { 0, 0, 0 },
			s7 = { 0, 0, 0 },
			s8 = { 0, 0, 0 },
			s9 = { 0, 0, 0 },
			ovi = { 0, 0, 0 },
			head = { 0, 0, 0 },
		},
		ease = "outCubic",
	},
})

-- Head end rears, mandibles spread. This is the summon and it should be the
-- loudest thing in the chamber.
T.call = EnemyKit.track({
	{
		t = 0.00,
		pose = {
			head = { 0, 0, 0 },
			neck = { 0, 0, 0 },
			mandL = { 0, rad(-14), 0 },
			mandR = { 0, rad(14), 0 },
			s1 = { 0, 0, 0 },
			s2 = { 0, 0, 0 },
		},
	},
	{
		t = 0.28,
		pose = {
			head = { rad(18), 0, 0 },
			neck = { rad(12), 0, 0 },
			s1 = { rad(10), 0, 0 },
			mandL = { 0, rad(-4), 0 },
			mandR = { 0, rad(4), 0 },
		},
		ease = "inQuad",
	},
	{
		t = 0.62,
		pose = {
			head = { rad(-46), 0, 0 },
			neck = { rad(-34), 0, 0 },
			s1 = { rad(-22), 0, 0 },
			s2 = { rad(-14), 0, 0 },
			mandL = { 0, rad(-66), 0 },
			mandR = { 0, rad(66), 0 },
		},
		ease = "outBack",
	},
	{
		t = 1.60,
		pose = { head = { rad(-40), rad(8), 0 }, mandL = { 0, rad(-58), 0 }, mandR = { 0, rad(58), 0 } },
		ease = "inOutQuad",
	},
	{
		t = 2.40,
		pose = {
			head = { 0, 0, 0 },
			neck = { 0, 0, 0 },
			s1 = { 0, 0, 0 },
			s2 = { 0, 0, 0 },
			mandL = { 0, rad(-14), 0 },
			mandR = { 0, rad(14), 0 },
		},
		ease = "inOutCubic",
	},
})

T.hurt = EnemyKit.track({
	{ t = 0.00, pose = { head = { 0, 0, 0 } } },
	{
		t = 0.10,
		pose = {
			head = { rad(-28), rad(12), 0 },
			neck = { rad(-18), 0, 0 },
			s1 = { rad(-14), rad(-10), 0 },
			s2 = { rad(12), rad(9), 0 },
			s3 = { rad(-10), rad(-8), 0 },
			s4 = { rad(9), rad(7), 0 },
			mandL = { 0, rad(-56), 0 },
			mandR = { 0, rad(56), 0 },
		},
		ease = "outQuart",
	},
	{
		t = 0.70,
		pose = {
			head = { 0, 0, 0 },
			neck = { 0, 0, 0 },
			s1 = { 0, 0, 0 },
			s2 = { 0, 0, 0 },
			s3 = { 0, 0, 0 },
			s4 = { 0, 0, 0 },
			mandL = { 0, rad(-14), 0 },
			mandR = { 0, rad(14), 0 },
		},
		ease = "outElastic",
	},
})

-- Long. She is enormous and should take her time. Rear collapses first, the
-- wave runs forward, the head goes down last.
T.death = EnemyKit.track({
	{ t = 0.00, pose = { head = { 0, 0, 0 } } },
	{
		t = 0.30,
		pose = {
			head = { rad(-52), 0, 0 },
			neck = { rad(-38), 0, 0 },
			s1 = { rad(-26), 0, 0 },
			s2 = { rad(-18), 0, 0 },
			mandL = { 0, rad(-74), 0 },
			mandR = { 0, rad(74), 0 },
			ovi = { rad(-30), 0, 0 },
		},
		ease = "outQuart",
	},
	{
		t = 1.00,
		pose = {
			s9 = { rad(34), rad(20), 0 },
			s8 = { rad(30), rad(17), 0 },
			s7 = { rad(26), rad(14), 0 },
			s6 = { rad(20), rad(11), 0 },
			ovi = { rad(50), 0, 0 },
		},
		ease = "inQuart",
	},
	{
		t = 1.70,
		pose = {
			s5 = { rad(24), rad(-14), 0 },
			s4 = { rad(28), rad(-17), 0 },
			s3 = { rad(32), rad(-20), 0 },
			s2 = { rad(30), rad(-16), 0 },
			s1 = { rad(26), rad(-12), 0 },
		},
		ease = "inCubic",
	},
	{
		t = 2.30,
		pose = {
			head = { rad(44), rad(18), 0 },
			neck = { rad(38), rad(12), 0 },
			mandL = { 0, rad(-20), 0 },
			mandR = { 0, rad(20), 0 },
		},
		ease = "outBounce",
	},
	{
		t = 3.60,
		pose = {
			head = { rad(41), rad(16), 0 },
			neck = { rad(36), rad(11), 0 },
			mandL = { 0, rad(-6), 0 },
			mandR = { 0, rad(6), 0 },
		},
		ease = "outCubic",
	},
})

-- ============================================================
-- BUILD
-- ============================================================
function GrubQueen.build(variant: EnemyKit.Variant, seed: number?): (Model, any)
	local b = EnemyKit.begin("GrubQueen", variant, seed)
	local J: { [string]: EnemyKit.Joint } = {}
	local N = GrubQueen.Config.segmentCount

	-- Thorax is the root; the abdomen swells behind it and tapers at the tail.
	local root = EnemyKit.block(b, "Thorax", Vector3.new(3.4, 2.6, 2.6), "chit")

	local prev = root
	local segs = {}
	local sacs = {}
	for i = 1, N do
		-- Peak girth around segment 4: engorged, not a uniform tube.
		local swell = 1 - ((i - 4) / 5.4) ^ 2 * 0.62
		local w = 3.6 * swell
		local h = 2.9 * swell
		local seg = EnemyKit.block(b, "Seg" .. i, Vector3.new(w, h, 1.7), "chit")
		-- No baked yaw: these joints are chained, so any constant rotation compounds
		-- down the body and bends her into a comma. Curve comes from the tracks.
		J["s" .. i] = EnemyKit.joint(prev, seg, CFrame.new(0, -0.05, 1.62))
		table.insert(segs, seg)

		-- Brood sacs, brightest where she is fattest. These are the targeting
		-- read for dynamite and the only bright thing on her.
		if i >= 2 and i <= 7 then
			for _, side in { -1, 1 } do
				local sac =
					EnemyKit.blob(b, "BroodSac", Vector3.new(0.9 * swell, 1.15 * swell, 0.9 * swell), "wax", false)
				EnemyKit.joint(seg, sac, CFrame.new(side * w * 0.46, -0.2, 0))
				table.insert(sacs, sac)
			end
			local glow = EnemyKit.neon(b, "SacGlow", Vector3.new(0.5, 0.7, 0.5), "glow", 0.55)
			EnemyKit.joint(seg, glow, CFrame.new(0, -h * 0.42, 0))
		end
		-- Stubby vestigial legs. She has not walked in a long time.
		if i <= 6 then
			for _, side in { -1, 1 } do
				local leg = EnemyKit.block(b, "Vestigial", Vector3.new(0.26, 0.26, 0.9), "chit", false)
				EnemyKit.joint(
					seg,
					leg,
					CFrame.new(side * w * 0.42, -h * 0.36, 0)
						* CFrame.Angles(0, rad(side * 74), 0)
						* CFrame.Angles(rad(-40), 0, 0),
					CFrame.new(0, 0, 0.45)
				)
			end
		end
		EnemyKit.anchor(b, seg, CFrame.new(0, h * 0.42, 0), 0.55)
		prev = seg
	end

	-- Ovipositor. Where the grubs come out.
	local ovi = EnemyKit.block(b, "Ovipositor", Vector3.new(1.5, 1.3, 1.9), "soft")
	J.ovi = EnemyKit.joint(prev, ovi, CFrame.new(0, -0.15, 1.35), CFrame.new(0, 0, -0.6))
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		local lip = EnemyKit.block(b, "Lip", Vector3.new(0.34, 0.72, 0.5), "soft", false)
		EnemyKit.joint(
			ovi,
			lip,
			CFrame.new(math.cos(a) * 0.5, math.sin(a) * 0.42, -0.7) * CFrame.Angles(rad(-24), 0, -a)
		)
	end
	local vent = EnemyKit.neon(b, "Vent", Vector3.new(0.8, 0.7, 0.4), "glow", 0.35)
	EnemyKit.joint(ovi, vent, CFrame.new(0, 0, -0.7))

	-- Head end. Recognisably the same creature as the Wax Grub, scaled up.
	local neck = EnemyKit.block(b, "Neck", Vector3.new(2.4, 1.9, 1.3), "chit")
	J.neck = EnemyKit.joint(root, neck, CFrame.new(0, 0.1, -1.7), CFrame.new(0, 0, 0.55))
	local head = EnemyKit.block(b, "Head", Vector3.new(2.5, 1.8, 1.8), "chit")
	J.head = EnemyKit.joint(neck, head, CFrame.new(0, 0.05, -1.0), CFrame.new(0, 0, 0.7))
	EnemyKit.anchor(b, head, CFrame.new(0, 0.8, 0.3), 0.42)

	for _, side in { -1, 1 } do
		local m = EnemyKit.block(b, "Mandible", Vector3.new(0.34, 0.34, 1.7), "pale")
		J[if side < 0 then "mandL" else "mandR"] = EnemyKit.joint(
			head,
			m,
			CFrame.new(side * 0.75, -0.35, -0.85) * CFrame.Angles(rad(12), rad(side * 16), 0),
			CFrame.new(0, 0, 0.85)
		)
		for e = 0, 2 do
			local eye = EnemyKit.neon(b, "Eye", Vector3.one * (0.30 - e * 0.06), "eye")
			EnemyKit.joint(head, eye, CFrame.new(side * (0.42 + e * 0.26), 0.42 - e * 0.1, -0.82))
		end
	end

	EnemyKit.hitbox(b, root, Vector3.new(5.0, 4.0, 16.0), CFrame.new(0, 0, 5.0))
	EnemyKit.collider(b, root, Vector3.new(4.2, 3.2, 6.0), CFrame.new(0, 0, 2.0))
	EnemyKit.collider(b, root, Vector3.new(3.4, 2.8, 6.0), CFrame.new(0, 0, 8.5))

	local model = EnemyKit.finish(b, root, "GrubQueen", 5)
	return model, { root = root, joints = J, segs = segs, sacs = sacs, ovi = ovi, vent = vent }
end

-- ============================================================
-- CONTROLLER
-- ============================================================
export type Queen = typeof(setmetatable({} :: any, GrubQueen))

function GrubQueen.new(cframe: CFrame, variant: EnemyKit.Variant?, seed: number?): Queen
	local v = variant or "regular"
	local model, rig = GrubQueen.build(v, seed)
	model:PivotTo(cframe)
	-- ANCHORED AND STILL MOBILE, which is not a contradiction: she is driven by CFrame, exactly like
	-- the Wax Grub, and for the same reason written out at length in WaxGrubBehavior. A body of this
	-- mass handed to the physics solver would be shoved around by her own brood, would need a Humanoid
	-- and a navmesh agent nothing this shape fits, and would fight every voxel seam in the chamber.
	-- Anchoring the ROOT and writing its CFrame gives movement without any of that.
	--
	-- HER SEGMENTS STAY UNANCHORED regardless. The peristaltic wave down the Motor6D chain is her
	-- whole presence; anchoring the segments freezes those joints and collapses her into a stack of
	-- parts at the origin.
	rig.root.Anchored = true

	return setmetatable({
		model = model,
		root = rig.root,
		joints = rig.joints,
		vent = rig.vent,
		hitbox = model:FindFirstChild("Hitbox"),
		variant = v,
		health = GrubQueen.Config.health,
		maxHealth = GrubQueen.Config.health,
		state = "idle",
		t = 0,
		stateT = 0,
		nextBrood = GrubQueen.Config.broodInterval,
		nextCall = GrubQueen.Config.callInterval,
		liveGrubs = 0,
		onBirth = nil :: ((CFrame) -> ())?,
		onCall = nil :: (() -> ())?,
		onDeath = nil :: (() -> ())?,
		sounds = {
			churn = EnemyKit.emitter(rig.root, SOUNDS.churn, "Churn", true, 0.7, 20, 160),
			birth = EnemyKit.emitter(rig.ovi, SOUNDS.birth, "Birth", false, 0.8, 6, 55),
			call = EnemyKit.emitter(rig.root, SOUNDS.call, "Call", false, 1, 25, 170),
			hurt = EnemyKit.emitter(rig.root, SOUNDS.hurt, "Hurt", false, 0.9, 12, 90),
			death = EnemyKit.emitter(rig.root, SOUNDS.death, "Death", false, 1, 25, 170),
		},
	}, GrubQueen)
end

function GrubQueen.setState(self: Queen, state: string)
	if self.state == state or self.state == "death" then
		return
	end
	self.state = state
	self.stateT = 0
	self.model:SetAttribute("State", state)
	if state == "birth" and self.sounds.birth then
		self.sounds.birth:Play()
	elseif (state == "call" or state == "bite") and self.sounds.call then
		-- The pack ships no bite sample, so this bare emitter falls back to her voice; the integration
		-- layer plays a separate QueenBite cue on the same transition.
		self.sounds.call:Play()
	elseif state == "hurt" and self.sounds.hurt then
		self.sounds.hurt:Play()
	elseif state == "death" then
		if self.sounds.churn then
			self.sounds.churn:Stop()
		end
		if self.sounds.death then
			self.sounds.death:Play()
		end
	end
end

function GrubQueen.start(self: Queen)
	if self.sounds.churn then
		self.sounds.churn:Play()
	end
end

-- Only dynamite. Anything else is ignored, which is the whole encounter design
-- in one function.
function GrubQueen.applyDynamite(self: Queen, charges: number?)
	if self.state == "death" then
		return
	end
	self.health -= (charges or 1) * GrubQueen.Config.dynamiteDamage
	self.model:SetAttribute("Health", self.health)
	if self.health <= 0 then
		self:setState("death")
		if self.onDeath then
			self.onDeath()
		end
	else
		self:setState("hurt")
	end
end

function GrubQueen.grubDied(self: Queen)
	self.liveGrubs = math.max(0, self.liveGrubs - 1)
end

-- BEGIN A BITE. Accepted out of either travelling state and refused from every other one: she will
-- not interrupt a birth, a call, a flinch or another bite to take one, which is what keeps her from
-- chain-biting somebody pinned against her head. The controller owns the cooldown and the contact
-- test; this owns the pose.
--
-- IT HAS TO ACCEPT FROM `crawl`, NOT JUST `idle`. She is crawling at whoever she is about to bite
-- right up until the moment they are in range, so a version of this that demanded a settled idle
-- refused every bite she would ever have reason to take — which is exactly what it did.
function GrubQueen.bite(self: Queen): boolean
	if not self:isTravelling() then
		return false
	end
	self:setState("bite")
	return true
end

-- Whether she is free to crawl this frame. She stops dead to lay, to summon, and when hit — a body
-- that kept sliding forward through its own birth animation would read as being on rails.
function GrubQueen.isTravelling(self: Queen): boolean
	return self.state == "idle" or self.state == "crawl"
end

-- Where a newborn grub should appear. Slightly in front of the ovipositor so it
-- does not spawn inside her collider.
function GrubQueen.birthPoint(self: Queen): CFrame
	local ovi = self.model:FindFirstChild("Ovipositor") :: BasePart?
	if not ovi then
		return self.root.CFrame * CFrame.new(0, 0, 12)
	end
	return ovi.CFrame * CFrame.new(0, -0.5, -2.2)
end

function GrubQueen.step(self: Queen, dt: number)
	self.t += dt
	self.stateT += dt

	if self.state == "birth" and self.stateT > 1.10 then
		self:setState("idle")
	elseif self.state == "call" and self.stateT > 2.40 then
		self:setState("idle")
	elseif self.state == "hurt" and self.stateT > 0.70 then
		self:setState("idle")
	elseif self.state == "bite" and self.stateT >= GrubQueen.Config.biteSeconds then
		self:setState("idle")
	end

	-- BIRTHS AND CALLS FIRE WHILE SHE IS CRAWLING TOO. Gating them on `idle` alone was correct when
	-- idle was the only state she was ever in; now that she travels, it would mean a Queen that never
	-- stopped following anybody also never laid a grub — the encounter's whole clock, switched off by
	-- a player who kept walking. She still STOPS to do either: the birth and call states are not
	-- travelling states, so the crawl resumes after them.
	if self:isTravelling() then
		if self.t >= self.nextBrood and self.liveGrubs < GrubQueen.Config.maxLiveGrubs then
			self.nextBrood = self.t + GrubQueen.Config.broodInterval
			self:setState("birth")
			if self.onBirth then
				for _ = 1, GrubQueen.Config.broodCount do
					self.onBirth(self:birthPoint())
					self.liveGrubs += 1
				end
			end
		elseif self.t >= self.nextCall then
			self.nextCall = self.t + GrubQueen.Config.callInterval
			self:setState("call")
			if self.onCall then
				self.onCall()
			end
		end
	end

	local track = T[self.state] or T.idle
	EnemyKit.evaluate(self.joints, track, self.stateT)

	-- Vent brightens as a birth approaches. This is the player's only timing
	-- information for when the next brood arrives.
	if self.vent and self.state ~= "death" then
		local til = math.clamp(1 - (self.nextBrood - self.t) / GrubQueen.Config.broodInterval, 0, 1)
		self.vent.Transparency = 0.6 - til * 0.5
	elseif self.vent then
		self.vent.Transparency = 1
	end
end

function GrubQueen.destroy(self: Queen)
	self.model:Destroy()
end

return GrubQueen

--!strict
-- Unlittius — the cave deity. The second floor boss (DESIGN §9b), appearing every 20 floors,
-- alternating with the Grub Queen.
-- Place at: ReplicatedStorage/Enemies/Unlittius
--
-- HE IS ARCHITECTURE THAT WOKE UP. Every other body in this pack is an animal; this one is a shrine
-- carving held a few feet off its own broken pedestal by something that has not let go of it in a very
-- long time. That reading is the whole design, and three things carry it:
--
--   * HE HAS NO LEGS AND NO WALK CYCLE, and there is deliberately no code anywhere that could give
--     him one. He hovers over his dais and is rooted there in gameplay terms; the only translation he
--     is ever allowed is a stud and a half of melee lunge and the banish rise.
--   * HIS MASS LAGS. Nothing on this body arrives at once — the base stones move least, the torso
--     follows, the head arrives last, and the claws overshoot. That lag is authored into every track
--     below rather than produced by a spring, because a spring has no strong poses.
--   * HE ENDS AS ARCHITECTURE AGAIN. The eighth candle does not kill him. It pulls him into the
--     ceiling and leaves him there as a relief, which is why `Unlittius.relief` exists in this file
--     beside the live rig: the two are one design and must be built from the same numbers.
--
-- THE FIGHT, in a game with no player attack: eight dead shrine candles ring his dais, the party
-- lights them off their own flames, and each one permanently dims him. There is no health here and no
-- `damage()` function, exactly as the Grub Queen exposes `applyDynamite` and nothing else — the
-- encounter's only verb is `candleLit`.
--
-- GEOMETRY IS CENTRALISED IN `P`, AT THE TOP, and every part below is placed from it. The handoff
-- package asks for exactly this and the reason is the arm revision: the limbs were shortened by ~13%
-- late in the design, and a body whose proportions live in a hundred literals scattered through a
-- builder cannot absorb a change like that without becoming a different creature.

local EnemyKit = require(script.Parent.EnemyKit)
local UnlittiusConfig = require(script.Parent.Parent.Config.Unlittius)

local Unlittius = {}
Unlittius.__index = Unlittius

local rad = math.rad

-- ============================================================
-- PROPORTIONS
--
-- Studs, in the rig's own frame: the root sits at y = 0 at chest-block height, +Y is up, and he faces
-- -Z (the pack's convention — `root.CFrame.LookVector`). Widths are the master spec's; the vertical
-- chain is stretched slightly against the reference viewer so the finished silhouette lands inside the
-- spec's 11-12.5 stud band without widening him past its 4.4-4.8 stud shoulders.
-- ============================================================
local P = {
	-- Vertical chain, each measured from its parent's origin.
	torsoY = 0.34,
	neckY = 1.75,
	headY = 0.80,
	crownY = 0.60,
	pelvisY = -1.18,

	-- Torso. Broad at the chest, narrowing hard into the waist.
	torsoSize = Vector3.new(3.84, 2.84, 2.16),
	ribCount = 6,
	ribTopY = 1.08,
	ribStepY = 0.42,
	ribWidth = 3.76,
	ribWidthStep = 0.24,
	ribSize = Vector3.new(3.76, 0.52, 1.68),
	shoulderMassOffset = Vector3.new(1.50, 0.52, -0.02),
	shoulderMassSize = Vector3.new(1.16, 1.80, 1.72),
	flankSize = Vector3.new(0.80, 1.28, 1.40),

	-- The chest cavity and the rune inside it. The rune is the brightest thing on him and the only
	-- part of the body a player is ever asked to read at a glance.
	cavitySize = Vector3.new(2.96, 2.68, 0.68),
	cavityOffset = Vector3.new(0, 0.30, -1.02),
	runeSize = Vector3.new(1.00, 1.40, 0.56),
	runeOffset = Vector3.new(0, 0.30, -1.26),
	runeBarCount = 4,

	-- The floating base: three compact major stones and a short taper. Not a tornado.
	baseStones = {
		{ offset = Vector3.new(0.00, -1.90, 0.00), size = Vector3.new(2.84, 1.16, 2.16), yaw = 10 },
		{ offset = Vector3.new(-0.20, -2.70, 0.04), size = Vector3.new(2.00, 0.88, 1.60), yaw = -20 },
		{ offset = Vector3.new(0.16, -3.42, -0.04), size = Vector3.new(1.44, 0.86, 1.16), yaw = 24 },
	},
	pelvisSize = Vector3.new(2.68, 1.20, 1.84),

	-- Shoulders and arms. THE SHORTENED REVISION: upper arm 1.92, forearm 1.86, and the talons left
	-- at full size on purpose, so the hand reads as the threat rather than the reach.
	shoulderOffset = Vector3.new(1.66, 0.80, -0.02),
	shoulderSize = Vector3.new(1.50, 1.44, 1.80),
	shoulderCapSize = Vector3.new(1.24, 1.00, 1.44),
	shoulderSpikeCount = 3,
	upperArmY = -0.46,
	upperArmX = 0.24,
	upperArmLength = 1.92,
	upperArmSize = Vector3.new(0.76, 0.88, 2.04),
	upperArmRestPitch = -66,
	forearmLength = 1.86,
	forearmSize = Vector3.new(0.76, 0.88, 2.04),
	forearmRestPitch = 18,
	cuffSize = Vector3.new(0.92, 0.72, 0.50),
	handRestPitch = 12,

	-- The claws. Three primary talons plus one opposing thumb, each a thick stone root, a narrow dark
	-- middle and a blade tip. Tips are separated and curve down and inward.
	palmSize = Vector3.new(1.32, 0.84, 1.44),
	knuckleSize = Vector3.new(1.12, 0.60, 1.08),
	talonSpread = { -0.46, 0, 0.46 },
	talonRootSize = Vector3.new(0.32, 0.32, 0.86),
	talonMidSize = Vector3.new(0.24, 0.24, 0.94),
	talonTipSize = Vector3.new(0.20, 0.78, 0.18),
	talonReach = 2.08,
	thumbRootSize = Vector3.new(0.34, 0.34, 0.78),
	thumbMidSize = Vector3.new(0.24, 0.24, 0.78),

	-- Head and hood.
	skullSize = Vector3.new(1.44, 1.48, 1.32),
	faceVoidSize = Vector3.new(2.24, 2.44, 0.36),
	faceVoidOffset = Vector3.new(0, -0.18, -0.70),
	eyeSize = Vector3.new(0.36, 0.48, 0.24),
	eyeOffset = Vector3.new(0.31, 0.04, -0.84),
	chinStoneCount = 5,
	cheekFinSize = Vector3.new(0.60, 2.44, 0.68),
	brimSize = Vector3.new(2.84, 0.48, 2.76),
	-- The hood is a STACK of five tapering faceted blocks, not a cone: the spec asks for carved,
	-- layered and old, and a smooth cone reads as cloth.
	hoodLayers = 5,
	hoodBaseWidth = 2.44,
	hoodHeight = 3.60,
	hoodTipSize = Vector3.new(0.68, 0.90, 0.60),

	-- The cape. Broad continuous slabs with a torn hem — never narrow strips.
	capeOffset = Vector3.new(0, 1.00, 1.02),
	mantleSize = Vector3.new(3.34, 0.44, 1.04),
	capePanelWidth = 1.30,
	capePanelLength = 4.20,
	capePanelThickness = 0.30,
	capeTagCount = 4,

	-- Orbiting fragments.
	orbitStoneSize = Vector3.new(0.56, 0.44, 0.52),
}

-- THE AUTHORED SILHOUETTE HEIGHT, derived from `P` rather than measured or guessed: from the bottom
-- of the lowest major base stone to the tip of the hood. `build` divides the configured target height
-- by this to get one uniform scale, so retuning any number above keeps the finished body the size the
-- encounter was balanced around.
local LOWEST_BASE_Y = P.baseStones[3].offset.Y - P.baseStones[3].size.Y / 2
local CROWN_Y = P.torsoY + P.neckY + P.headY + P.crownY
local HOOD_TIP_Y = CROWN_Y + P.brimSize.Y / 2 + P.hoodHeight + P.hoodTipSize.Y * 0.9
local AUTHORED_HEIGHT = HOOD_TIP_Y - LOWEST_BASE_Y

Unlittius.Config = {
	-- Mirrors of the encounter timings the tracks below are authored against. `Config/Unlittius` is
	-- the source of truth and the behaviour reads it; these exist so the animation can be inspected on
	-- its own, exactly as `GrubQueen.Config` mirrors hers.
	idleSeconds = 6.0,
	dripstoneSeconds = 2.6,
	boulderSeconds = 2.45,
	summonSeconds = 3.05,
	meleeSeconds = 1.55,
	recoilSeconds = 1.7,
	banishSeconds = 3.4,
	authoredHeight = AUTHORED_HEIGHT,
}

-- ============================================================
-- ANIMATION
--
-- Every value is a DELTA on the rest pose (`EnemyKit.pose` composes `base * angles`), so the resting
-- hang of the arms is geometry and the tracks only ever say how far from it something moved.
--
-- THE ARM CONVENTION, because it is the one thing in this file that is easy to get backwards and
-- expensive to notice: a limb points along its own -Z, and POSITIVE `rx` RAISES it. The upper arms
-- rest at -66 degrees (hanging down and slightly forward, per the spec's resting pose), so +66 is a
-- horizontal reach, +150 is overhead, and a negative delta drives the arm down and behind him. Every
-- raise below is therefore a large positive number, and the first pass of this file had them all
-- inverted — the "arms rise" telegraph pointed his claws at the floor behind his own cape.
--
-- THE ORDER OF ARRIVAL IS THE WHOLE STYLE. Read any track below as a column and the same rule holds:
-- the base stones barely move, the torso commits, the arms lead, and the head lands last. Reversing
-- that on any single key is what makes a heavy thing look light.
--
-- `clawL`/`clawR` drive the whole talon cluster as one channel: NEGATIVE spreads the talons open,
-- positive curls them shut. They open on every windup and shut on every contact.
-- ============================================================
local T = {}

-- IDLE. Gravity pulling on something magic is barely holding up. The head scans, the shoulders sag
-- and recover, the claws flex once per cycle, and nothing is ever symmetrical.
T.idle = EnemyKit.track({
	{ t = 0.00, pose = { torso = { rad(2), rad(-1), 0 }, neck = { 0, rad(4), 0 }, head = { rad(-3), rad(-10), rad(1) }, crown = { rad(2), 0, 0 }, shL = { 0, 0, rad(-2) }, shR = { 0, 0, rad(2) }, upL = { rad(2), 0, rad(-3) }, upR = { rad(1), 0, rad(2) }, foL = { rad(-2), 0, 0 }, foR = { rad(-1), 0, 0 }, hdL = { rad(3), rad(-4), 0 }, hdR = { rad(2), rad(4), 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 }, cape = { rad(-1), 0, 0 }, pelvis = { rad(-1), rad(2), 0 } } },
	{ t = 1.60, pose = { torso = { rad(3), rad(1), rad(-1) }, neck = { rad(1), rad(1), 0 }, head = { rad(-1), rad(-4), 0 }, shL = { rad(-2), 0, rad(-4) }, shR = { rad(-1), 0, rad(3) }, upL = { rad(5), rad(-2), rad(-4) }, upR = { rad(4), rad(2), rad(3) }, foL = { rad(3), 0, rad(2) }, foR = { rad(2), 0, rad(-2) }, hdL = { rad(6), rad(-7), rad(3) }, hdR = { rad(5), rad(6), rad(-3) }, clawL = { rad(-6), 0, 0 }, clawR = { rad(-4), 0, 0 }, cape = { rad(-2), rad(1), 0 }, pelvis = { rad(1), rad(-1), 0 } }, ease = "inOutQuad" },
	{ t = 3.00, pose = { torso = { rad(1), rad(2), rad(1) }, neck = { rad(-1), rad(-3), 0 }, head = { rad(-4), rad(12), rad(-1) }, crown = { rad(1), rad(2), 0 }, shL = { rad(1), 0, rad(-1) }, shR = { rad(2), 0, rad(1) }, upL = { rad(1), rad(1), rad(-2) }, upR = { rad(2), rad(-1), rad(1) }, foL = { rad(-1), 0, rad(-1) }, foR = { rad(-2), 0, rad(1) }, hdL = { rad(2), rad(-2), rad(-2) }, hdR = { rad(3), rad(2), rad(2) }, clawL = { rad(2), 0, 0 }, clawR = { rad(3), 0, 0 }, cape = { rad(-1), rad(-1), 0 }, pelvis = { rad(-1), rad(1), 0 } }, ease = "inOutQuad" },
	{ t = 4.50, pose = { torso = { rad(2), 0, 0 }, neck = { rad(1), rad(2), 0 }, head = { rad(-2), rad(6), rad(2) }, shL = { rad(-1), 0, rad(-3) }, shR = { rad(-2), 0, rad(2) }, upL = { rad(4), rad(-1), rad(-3) }, upR = { rad(5), rad(1), rad(2) }, foL = { rad(2), 0, rad(1) }, foR = { rad(3), 0, rad(-1) }, hdL = { rad(4), rad(-5), rad(1) }, hdR = { rad(6), rad(4), rad(-1) }, clawL = { rad(-3), 0, 0 }, clawR = { rad(-5), 0, 0 }, cape = { rad(-2), 0, 0 }, pelvis = { rad(1), rad(1), 0 } }, ease = "inOutQuad" },
	{ t = 6.00, pose = { torso = { rad(2), rad(-1), 0 }, neck = { 0, rad(4), 0 }, head = { rad(-3), rad(-10), rad(1) }, crown = { rad(2), 0, 0 }, shL = { 0, 0, rad(-2) }, shR = { 0, 0, rad(2) }, upL = { rad(2), 0, rad(-3) }, upR = { rad(1), 0, rad(2) }, foL = { rad(-2), 0, 0 }, foR = { rad(-1), 0, 0 }, hdL = { rad(3), rad(-4), 0 }, hdR = { rad(2), rad(4), 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 }, cape = { rad(-1), 0, 0 }, pelvis = { rad(-1), rad(2), 0 } }, ease = "inOutQuad" },
}, true)

-- DRIPSTONE (2.60s). He pulls the cave ceiling down. The arms come up over nine tenths of a second
-- and hold overhead while the floor markers are already lit, then everything drives down at once at
-- 1.62 — the exact instant the server resolves the impacts, so the snap and the damage are one event.
T.dripstone = EnemyKit.track({
	{ t = 0.00, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 }, cape = { 0, 0, 0 } } },
	-- the rise: arms lead to horizontal, the torso leans back under them, the head follows late
	{ t = 0.55, pose = { torso = { rad(-7), 0, 0 }, neck = { rad(-3), 0, 0 }, head = { rad(2), rad(-3), 0 }, shL = { rad(-8), 0, rad(-10) }, shR = { rad(-8), 0, rad(10) }, upL = { rad(78), rad(-10), rad(-14) }, upR = { rad(78), rad(10), rad(14) }, foL = { rad(26), 0, rad(-8) }, foR = { rad(26), 0, rad(8) }, hdL = { rad(10), 0, 0 }, hdR = { rad(10), 0, 0 }, clawL = { rad(-16), 0, 0 }, clawR = { rad(-16), 0, 0 }, cape = { rad(4), 0, 0 } }, ease = "outCubic" },
	-- overhead, both talons open at the ceiling
	{ t = 0.90, pose = { torso = { rad(-11), 0, 0 }, neck = { rad(-6), 0, 0 }, head = { rad(-8), 0, 0 }, shL = { rad(-14), 0, rad(-14) }, shR = { rad(-14), 0, rad(14) }, upL = { rad(146), rad(-14), rad(-20) }, upR = { rad(146), rad(14), rad(20) }, foL = { rad(38), 0, rad(-10) }, foR = { rad(38), 0, rad(10) }, hdL = { rad(24), rad(6), 0 }, hdR = { rad(24), rad(-6), 0 }, clawL = { rad(-30), 0, 0 }, clawR = { rad(-30), 0, 0 }, cape = { rad(6), 0, 0 } }, ease = "outQuart" },
	-- THE MICRO-HOLD. This frame is the whole telegraph, and the markers are already on the floor.
	{ t = 1.45, pose = { torso = { rad(-12), 0, 0 }, head = { rad(-11), 0, 0 }, upL = { rad(152), rad(-14), rad(-21) }, upR = { rad(152), rad(14), rad(21) }, foL = { rad(41), 0, rad(-10) }, foR = { rad(41), 0, rad(10) }, clawL = { rad(-34), 0, 0 }, clawR = { rad(-34), 0, 0 } }, ease = "inOutQuad" },
	-- DOWN. The conductor's snap: the hands drive to chest height and overshoot the torso, which has
	-- not caught up yet.
	{ t = 1.62, pose = { torso = { rad(14), 0, 0 }, neck = { rad(8), 0, 0 }, head = { rad(6), 0, 0 }, shL = { rad(8), 0, rad(6) }, shR = { rad(8), 0, rad(-6) }, upL = { rad(34), rad(4), rad(8) }, upR = { rad(34), rad(-4), rad(-8) }, foL = { rad(-4), 0, rad(4) }, foR = { rad(-4), 0, rad(-4) }, hdL = { rad(20), 0, 0 }, hdR = { rad(20), 0, 0 }, clawL = { rad(22), 0, 0 }, clawR = { rad(22), 0, 0 }, cape = { rad(-8), 0, 0 } }, ease = "inQuart" },
	-- the body arrives after the hands did
	{ t = 1.86, pose = { torso = { rad(8), 0, 0 }, neck = { rad(3), 0, 0 }, head = { rad(12), rad(3), 0 }, upL = { rad(22), rad(2), rad(5) }, upR = { rad(22), rad(-2), rad(-5) }, foL = { rad(2), 0, 0 }, foR = { rad(2), 0, 0 }, cape = { rad(-4), 0, 0 } }, ease = "outQuad" },
	{ t = 2.60, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 }, cape = { 0, 0, 0 } }, ease = "inOutCubic" },
})

-- BOULDER BURST (2.45s). HE NEVER TOUCHES THEM. The arms open to chest height and conduct; the stones
-- assemble outboard of each shoulder on their own and leave on his gesture at 0.92 and 1.16. Anything
-- here that read as a grab or a throw would be the wrong creature entirely.
T.boulder = EnemyKit.track({
	{ t = 0.00, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 } } },
	-- open: elbows out, both palms turning up and outward under where each stone is forming
	{ t = 0.55, pose = { torso = { rad(-3), 0, 0 }, neck = { rad(-2), 0, 0 }, head = { rad(-4), 0, 0 }, shL = { rad(-6), 0, rad(-16) }, shR = { rad(-6), 0, rad(16) }, upL = { rad(72), rad(-24), rad(-26) }, upR = { rad(72), rad(24), rad(26) }, foL = { rad(20), rad(-10), rad(-12) }, foR = { rad(20), rad(10), rad(12) }, hdL = { rad(-16), rad(-16), rad(-18) }, hdR = { rad(-16), rad(16), rad(18) }, clawL = { rad(-22), 0, 0 }, clawR = { rad(-22), 0, 0 } }, ease = "outCubic" },
	-- ready: the stones are full size, and both hands turn to face where they are going
	{ t = 0.86, pose = { torso = { rad(-1), 0, 0 }, head = { rad(-2), 0, 0 }, shL = { rad(-4), 0, rad(-12) }, shR = { rad(-4), 0, rad(12) }, upL = { rad(78), rad(-14), rad(-20) }, upR = { rad(78), rad(14), rad(20) }, foL = { rad(12), rad(-4), rad(-6) }, foR = { rad(12), rad(4), rad(6) }, hdL = { rad(-24), rad(-6), rad(-8) }, hdR = { rad(-24), rad(6), rad(8) } }, ease = "inOutQuad" },
	-- SHOT ONE, from the left. One hand drives forward; the other still holds its stone.
	{ t = 0.92, pose = { torso = { rad(4), rad(-5), 0 }, upL = { rad(88), rad(8), rad(-8) }, foL = { rad(2), rad(4), 0 }, hdL = { rad(-6), rad(6), 0 }, clawL = { rad(16), 0, 0 } }, ease = "outQuart" },
	-- SHOT TWO, 0.24s later, from the right.
	{ t = 1.16, pose = { torso = { rad(4), rad(5), 0 }, upR = { rad(88), rad(-8), rad(8) }, foR = { rad(2), rad(-4), 0 }, hdR = { rad(-6), rad(-6), 0 }, clawR = { rad(16), 0, 0 } }, ease = "outQuart" },
	{ t = 1.65, pose = { torso = { rad(2), 0, 0 }, head = { rad(3), rad(-4), 0 }, upL = { rad(38), 0, rad(-6) }, upR = { rad(38), 0, rad(6) }, foL = { rad(6), 0, 0 }, foR = { rad(6), 0, 0 }, hdL = { rad(-6), 0, 0 }, hdR = { rad(-6), 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 } }, ease = "outQuad" },
	{ t = 2.45, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 } }, ease = "inOutCubic" },
})

-- SUMMON GNAWERS (3.05s). A RITUAL, NOT A SWING. Both arms lift past horizontal, the shoulders open,
-- the palms and talons rotate to face the ceiling, the head tilts back — and then he HOLDS, which is
-- the part that makes it read as summoning rather than as another attack. They arrive during the hold.
T.summon = EnemyKit.track({
	{ t = 0.00, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, crown = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 }, cape = { 0, 0, 0 } } },
	{ t = 0.70, pose = { torso = { rad(-4), 0, 0 }, neck = { rad(-4), 0, 0 }, head = { rad(-8), 0, 0 }, shL = { rad(-8), 0, rad(-18) }, shR = { rad(-8), 0, rad(18) }, upL = { rad(96), rad(-22), rad(-30) }, upR = { rad(96), rad(22), rad(30) }, foL = { rad(32), rad(-8), rad(-14) }, foR = { rad(32), rad(8), rad(14) }, hdL = { rad(-34), rad(-10), rad(-10) }, hdR = { rad(-34), rad(10), rad(10) }, clawL = { rad(-30), 0, 0 }, clawR = { rad(-30), 0, 0 }, cape = { rad(3), 0, 0 } }, ease = "outCubic" },
	-- open: head all the way back, palms to the ceiling, talons spread
	{ t = 1.30, pose = { torso = { rad(-9), 0, 0 }, neck = { rad(-14), 0, 0 }, head = { rad(-26), 0, 0 }, crown = { rad(-6), 0, 0 }, shL = { rad(-14), 0, rad(-26) }, shR = { rad(-14), 0, rad(26) }, upL = { rad(148), rad(-32), rad(-42) }, upR = { rad(148), rad(32), rad(42) }, foL = { rad(54), rad(-14), rad(-20) }, foR = { rad(54), rad(14), rad(20) }, hdL = { rad(-72), rad(-14), rad(-14) }, hdR = { rad(-72), rad(14), rad(14) }, clawL = { rad(-52), 0, 0 }, clawR = { rad(-52), 0, 0 }, cape = { rad(6), 0, 0 } }, ease = "outQuart" },
	-- THE HOLD. Almost nothing moves for most of a second; the Gnawers break the floor at 1.42.
	{ t = 2.15, pose = { torso = { rad(-9), rad(1), 0 }, head = { rad(-27), rad(2), 0 }, upL = { rad(151), rad(-32), rad(-43) }, upR = { rad(151), rad(32), rad(43) }, clawL = { rad(-56), 0, 0 }, clawR = { rad(-56), 0, 0 } }, ease = "inOutQuad" },
	{ t = 3.05, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, crown = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 }, cape = { 0, 0, 0 } }, ease = "inOutCubic" },
})

-- MELEE DOUBLE RAKE (1.55s). Short pullback, then two crossing rakes 0.26s apart, swept LOW — his
-- chest floats six studs over the dais, so a rake at his own chest height passes cleanly over the
-- head of the player it is supposed to punish. These keep the arms near their resting hang and turn
-- the cross into yaw, which puts the talons through the band a standing body actually occupies
-- (measured: claw tips 1.5-3.5 studs above the dais at both contact frames).
--
-- The torso twists into each one and the claws overshoot; the ROOT moves barely a stud (the
-- behaviour owns that) and he never leaves the dais.
T.melee = EnemyKit.track({
	{ t = 0.00, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 } } },
	-- pull back and out, claws visibly open. The whole warning, and it is short on purpose.
	{ t = 0.28, pose = { torso = { rad(-7), 0, 0 }, neck = { rad(-2), 0, 0 }, head = { rad(-6), 0, 0 }, shL = { rad(-4), 0, rad(-14) }, shR = { rad(-4), 0, rad(14) }, upL = { rad(6), rad(-38), rad(-20) }, upR = { rad(6), rad(38), rad(20) }, foL = { rad(10), rad(-14), 0 }, foR = { rad(10), rad(14), 0 }, hdL = { rad(-8), rad(-14), 0 }, hdR = { rad(-8), rad(14), 0 }, clawL = { rad(-46), 0, 0 }, clawR = { rad(-46), 0, 0 } }, ease = "outCubic" },
	-- LEFT RAKE crosses the body, low and hard. Contact is at 0.56 and the server resolves it there.
	{ t = 0.56, pose = { torso = { rad(8), rad(24), 0 }, neck = { rad(2), rad(8), 0 }, head = { rad(6), rad(16), 0 }, shL = { rad(4), 0, rad(12) }, upL = { rad(4), rad(56), rad(62) }, foL = { rad(0), rad(30), rad(10) }, hdL = { rad(-4), rad(34), rad(14) }, clawL = { rad(20), 0, 0 } }, ease = "inQuart" },
	-- RIGHT RAKE crosses back through it at 0.82, while the left arm is still recovering.
	{ t = 0.82, pose = { torso = { rad(8), rad(-24), 0 }, neck = { rad(2), rad(-8), 0 }, head = { rad(6), rad(-16), 0 }, shR = { rad(4), 0, rad(-12) }, upL = { rad(2), rad(24), rad(30) }, foL = { rad(0), rad(12), rad(6) }, upR = { rad(4), rad(-56), rad(-62) }, foR = { rad(0), rad(-30), rad(-10) }, hdR = { rad(-4), rad(-34), rad(-14) }, clawR = { rad(20), 0, 0 } }, ease = "inQuart" },
	-- overshoot and settle
	{ t = 0.96, pose = { torso = { rad(4), rad(-13), 0 }, head = { rad(3), rad(-7), 0 }, upR = { rad(3), rad(-30), rad(-34) }, clawL = { rad(4), 0, 0 }, clawR = { rad(6), 0, 0 } }, ease = "outQuad" },
	{ t = 1.55, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 } }, ease = "inOutCubic" },
})

-- CANDLE RECOIL (1.70s). THE MOST IMPORTANT ANIMATION IN THE ENCOUNTER, because it is the only
-- feedback a boss with no health bar can give that he is losing. It lands like a wound: a hard snap
-- away inside a tenth of a second, both arms up across the chest rune to shield it, and an unstable
-- recovery that is still moving when it stops.
T.recoil = EnemyKit.track({
	{ t = 0.00, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, crown = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, cape = { 0, 0, 0 }, pelvis = { 0, 0, 0 } } },
	-- the hit
	{ t = 0.13, pose = { torso = { rad(-18), rad(-9), rad(4) }, neck = { rad(-12), rad(-6), 0 }, head = { rad(-24), rad(-18), rad(6) }, crown = { rad(-8), 0, 0 }, shL = { rad(-16), 0, rad(-16) }, shR = { rad(-14), 0, rad(14) }, upL = { rad(34), rad(10), rad(-18) }, upR = { rad(32), rad(-10), rad(16) }, foL = { rad(48), rad(14), rad(-8) }, foR = { rad(46), rad(-14), rad(8) }, hdL = { rad(10), rad(-8), 0 }, hdR = { rad(8), rad(8), 0 }, cape = { rad(8), 0, 0 }, pelvis = { rad(6), rad(-4), 0 } }, ease = "outQuart" },
	-- shielding: forearms folded in across the rune, head turned away from the light
	{ t = 0.55, pose = { torso = { rad(-11), rad(-5), rad(2) }, head = { rad(-16), rad(-22), rad(4) }, upL = { rad(42), rad(16), rad(-12) }, upR = { rad(40), rad(-16), rad(10) }, foL = { rad(70), rad(20), 0 }, foR = { rad(68), rad(-20), 0 }, hdL = { rad(14), rad(14), 0 }, hdR = { rad(12), rad(-14), 0 } }, ease = "inOutQuad" },
	{ t = 0.90, pose = { torso = { rad(-8), rad(3), 0 }, head = { rad(-10), rad(10), 0 }, upL = { rad(26), rad(6), rad(-8) }, upR = { rad(24), rad(-6), rad(6) }, foL = { rad(44), rad(10), 0 }, foR = { rad(42), rad(-10), 0 } }, ease = "inOutQuad" },
	-- unstable return: he does not settle cleanly, and the cape is still moving when he stops
	{ t = 1.28, pose = { torso = { rad(3), rad(-2), 0 }, head = { rad(4), rad(-6), 0 }, upL = { rad(6), 0, rad(-2) }, upR = { rad(5), 0, rad(2) }, foL = { rad(10), 0, 0 }, foR = { rad(9), 0, 0 }, cape = { rad(-4), 0, 0 } }, ease = "outBack" },
	{ t = 1.70, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, crown = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, cape = { 0, 0, 0 }, pelvis = { 0, 0, 0 } }, ease = "outElastic" },
})

-- BANISH (3.40s). He is not killed. The rune goes unstable, the arms spread wide, something takes
-- hold of him from above, and he is pressed flat into the rock. The ROOT's rise and its roll onto the
-- ceiling plane are driven by the behaviour (they are movement, not pose); this is the body's answer
-- to it — arms opening into the flat relief pose they will be frozen in for the rest of the run.
T.banish = EnemyKit.track({
	{ t = 0.00, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { 0, 0, 0 }, crown = { 0, 0, 0 }, shL = { 0, 0, 0 }, shR = { 0, 0, 0 }, upL = { 0, 0, 0 }, upR = { 0, 0, 0 }, foL = { 0, 0, 0 }, foR = { 0, 0, 0 }, hdL = { 0, 0, 0 }, hdR = { 0, 0, 0 }, clawL = { 0, 0, 0 }, clawR = { 0, 0, 0 }, cape = { 0, 0, 0 }, pelvis = { 0, 0, 0 } } },
	-- unbind: a convulsion outward, head thrown back
	{ t = 0.45, pose = { torso = { rad(-14), 0, 0 }, neck = { rad(-10), 0, 0 }, head = { rad(-22), 0, 0 }, crown = { rad(-6), 0, 0 }, shL = { rad(-16), 0, rad(-24) }, shR = { rad(-16), 0, rad(24) }, upL = { rad(52), rad(-26), rad(-38) }, upR = { rad(52), rad(26), rad(38) }, foL = { rad(28), rad(-12), rad(-14) }, foR = { rad(28), rad(12), rad(14) }, hdL = { rad(-16), rad(-14), 0 }, hdR = { rad(-16), rad(14), 0 }, clawL = { rad(-40), 0, 0 }, clawR = { rad(-40), 0, 0 }, cape = { rad(10), 0, 0 }, pelvis = { rad(8), 0, 0 } }, ease = "outQuart" },
	-- the pull: the limbs trail as he is dragged upward
	{ t = 1.25, pose = { torso = { rad(-6), 0, 0 }, neck = { rad(-4), 0, 0 }, head = { rad(-12), 0, 0 }, shL = { rad(-8), 0, rad(-30) }, shR = { rad(-8), 0, rad(30) }, upL = { rad(58), rad(-34), rad(-50) }, upR = { rad(58), rad(34), rad(50) }, foL = { rad(22), rad(-16), rad(-20) }, foR = { rad(22), rad(16), rad(20) }, hdL = { rad(-8), rad(-18), 0 }, hdR = { rad(-8), rad(18), 0 }, clawL = { rad(-30), 0, 0 }, clawR = { rad(-30), 0, 0 }, cape = { rad(16), 0, 0 }, pelvis = { rad(4), 0, 0 } }, ease = "inOutQuad" },
	-- THE RELIEF POSE. Arms wide and flat, claws spread, head straight: the shape he is carved in.
	{ t = 2.30, pose = { torso = { 0, 0, 0 }, neck = { 0, 0, 0 }, head = { rad(-2), 0, 0 }, crown = { 0, 0, 0 }, shL = { 0, 0, rad(-38) }, shR = { 0, 0, rad(38) }, upL = { rad(66), rad(-38), rad(-62) }, upR = { rad(66), rad(38), rad(62) }, foL = { rad(14), rad(-10), rad(-22) }, foR = { rad(14), rad(10), rad(22) }, hdL = { 0, rad(-14), rad(-8) }, hdR = { 0, rad(14), rad(8) }, clawL = { rad(-18), 0, 0 }, clawR = { rad(-18), 0, 0 }, cape = { rad(4), 0, 0 }, pelvis = { 0, 0, 0 } }, ease = "inOutCubic" },
	-- pressed in. Nothing moves after this: the last fifth of a second is the stone closing over him.
	{ t = 3.20, pose = { shL = { 0, 0, rad(-40) }, shR = { 0, 0, rad(40) }, upL = { rad(68), rad(-40), rad(-64) }, upR = { rad(68), rad(40), rad(64) }, clawL = { rad(-20), 0, 0 }, clawR = { rad(-20), 0, 0 }, cape = { rad(2), 0, 0 } }, ease = "outQuad" },
	{ t = 3.40, pose = { head = { rad(-2), 0, 0 } }, ease = "linear" },
})
Unlittius.tracks = T

-- ============================================================
-- BUILD
-- ============================================================

-- Push a part's colour toward black. The palette gives this pack four stone tints per variant and no
-- true cavity colour; the recessed face, the chest hollow and the joint cuffs all need one, and
-- darkening the variant's own stone keeps a moss or ice Unlittius tinted rather than turning every
-- cavity the same brown-black in all three caves.
local function darken(part: BasePart, amount: number): BasePart
	part.Color = part.Color:Lerp(Color3.new(0, 0, 0), amount)
	return part
end

-- The violet. Every emissive piece on him is made here so a retune of `Config/Unlittius.body` moves
-- all of them together — eyes, chest rune, forearm seams, cape talismans and the hairline cracks.
local function runeSurface(part: BasePart, brightness: number): BasePart
	local body = UnlittiusConfig.body
	part.Color = body.runeColor:Lerp(Color3.new(1, 1, 1), 0.18 * brightness)
	part.Material = Enum.Material.Neon
	part.CastShadow = false
	return part
end

local function attachment(host: BasePart, name: string, offset: CFrame): Attachment
	local created = Instance.new("Attachment")
	created.Name = name
	created.CFrame = offset
	created.Parent = host
	return created
end

-- ONE HAND. A compact palm, three hooked talons and one opposing thumb — never four parallel sticks
-- and never a knuckle. Each talon is three pieces: a thick stone root, a narrow dark middle, and a
-- blade tip that hooks down and inward, which is what makes the silhouette readable in near-black.
local function buildHand(b: EnemyKit.Build, hand: BasePart, side: number): EnemyKit.Joint
	local palm = EnemyKit.block(b, "Palm", P.palmSize, "rock")
	EnemyKit.joint(hand, palm, CFrame.new(0, 0.02, -0.34) * CFrame.Angles(rad(10), rad(side * 5), rad(side * 5)))
	local cuff = darken(EnemyKit.block(b, "PalmCuff", P.knuckleSize, "chit"), 0.35)
	EnemyKit.joint(hand, cuff, CFrame.new(0, -0.02, -0.62) * CFrame.Angles(rad(18), 0, 0))

	-- ONE JOINT FOR THE WHOLE SET OF TALONS, driven by the `clawL`/`clawR` track channel. Four
	-- independent finger joints would be four more channels in every pose for a flex the player reads
	-- as one motion; the talons open and close together, like a trap rather than a hand.
	local spreadRoot = EnemyKit.block(b, "ClawRoot", Vector3.new(0.9, 0.5, 0.5), "chit")
	spreadRoot.Transparency = 1
	local clawJoint = EnemyKit.joint(hand, spreadRoot, CFrame.new(0, -0.06, -0.62))

	for index, x in P.talonSpread do
		local extend = if index == 2 then 0.16 else 0
		local root = EnemyKit.block(b, "Talon", P.talonRootSize, "rock")
		EnemyKit.joint(
			spreadRoot,
			root,
			CFrame.new(x * 0.86, -0.10, -0.44) * CFrame.Angles(rad(16), rad(side * -x * 6), rad(-x * 8))
		)
		local mid = darken(EnemyKit.block(b, "TalonMid", P.talonMidSize, "chit"), 0.4)
		EnemyKit.joint(
			root,
			mid,
			CFrame.new(x * 0.10, -0.30, -0.72) * CFrame.Angles(rad(28), 0, rad(-x * 6))
		)
		local tip = EnemyKit.wedge(b, "TalonTip", P.talonTipSize, "rock")
		EnemyKit.joint(
			mid,
			tip,
			CFrame.new(0, -0.34, -0.52 - extend)
				* CFrame.Angles(rad(116), rad(side * (8 + index * 4)), rad((index - 2) * 10))
		)
	end

	-- The thumb, opposing and hooked back under the palm.
	local thumbRoot = EnemyKit.block(b, "ThumbTalon", P.thumbRootSize, "rock")
	EnemyKit.joint(
		spreadRoot,
		thumbRoot,
		CFrame.new(side * 0.56, 0.04, -0.34) * CFrame.Angles(rad(10), rad(side * -28), rad(side * -14))
	)
	local thumbMid = darken(EnemyKit.block(b, "ThumbMid", P.thumbMidSize, "chit"), 0.4)
	EnemyKit.joint(thumbRoot, thumbMid, CFrame.new(side * 0.16, -0.30, -0.58) * CFrame.Angles(rad(30), 0, 0))
	local thumbTip = EnemyKit.wedge(b, "ThumbTip", P.talonTipSize, "rock")
	EnemyKit.joint(thumbMid, thumbTip, CFrame.new(0, -0.30, -0.44) * CFrame.Angles(rad(112), 0, rad(side * 24)))

	return clawJoint
end

-- The hood: five tapering faceted layers, a crooked cap band and a broken tip. Rotated off-axis in
-- alternating directions so no two layers line up, which is what sells "carved and old" instead of
-- "extruded cone".
local function buildHood(b: EnemyKit.Build, crown: BasePart)
	local brim = EnemyKit.block(b, "HoodBrim", P.brimSize, "rock")
	EnemyKit.joint(crown, brim, CFrame.new(0, P.brimSize.Y * 0.5, 0.05) * CFrame.Angles(0, rad(18), 0))

	local layerHeight = P.hoodHeight / P.hoodLayers
	local previous = brim
	local baseY = P.brimSize.Y * 0.5
	for index = 1, P.hoodLayers do
		local shrink = 1 - (index - 1) / P.hoodLayers * 0.82
		local size = Vector3.new(P.hoodBaseWidth * shrink, layerHeight * 1.06, P.hoodBaseWidth * 0.92 * shrink)
		local layer = EnemyKit.block(b, "HoodLayer" .. index, size, "rock", true)
		if index % 2 == 0 then
			darken(layer, 0.16)
		end
		EnemyKit.joint(
			crown,
			layer,
			CFrame.new(
				math.sin(index * 1.7) * 0.06,
				baseY + (index - 0.5) * layerHeight,
				0.08 + index * 0.015
			) * CFrame.Angles(rad((index % 2) * 2 - 1), rad(18 + index * 7), rad(math.sin(index * 2.3) * 3))
		)
		previous = layer
	end
	local _ = previous

	-- The broken top. Crooked, and the one asymmetry on him that a player will notice.
	local tip = EnemyKit.wedge(b, "HoodTip", P.hoodTipSize, "rock")
	EnemyKit.joint(
		crown,
		tip,
		CFrame.new(0.08, baseY + P.hoodHeight + P.hoodTipSize.Y * 0.4, 0.05)
			* CFrame.Angles(rad(-8), rad(12), rad(7))
	)
	local band = darken(EnemyKit.block(b, "HoodBand", Vector3.new(2.96, 0.40, 2.68), "chit"), 0.3)
	EnemyKit.joint(crown, band, CFrame.new(0, baseY + 0.62, 0.02) * CFrame.Angles(0, rad(18), rad(-3)))

	-- Temple fins on the brim, one per side.
	for _, side in { -1, 1 } do
		local fin = EnemyKit.wedge(b, "TempleFin", Vector3.new(0.48, 1.40, 0.56), "chit")
		darken(fin, 0.25)
		EnemyKit.joint(
			crown,
			fin,
			CFrame.new(side * 1.20, baseY + 0.26, 0.03) * CFrame.Angles(rad(92), rad(side * 8), rad(side * 12))
		)
	end
end

-- The cape: broad overlapping slabs with an irregular hem, hung off a mantle that anchors the whole
-- silhouette. FIVE PANELS AND NOT MORE — the spec is explicit that narrow strips are the failure mode,
-- and every panel here is wider than it is thick by a factor of four.
local function buildCape(b: EnemyKit.Build, capeRoot: BasePart): { EnemyKit.Joint }
	local mantle = darken(EnemyKit.block(b, "CapeMantle", P.mantleSize, "chit"), 0.2)
	EnemyKit.joint(capeRoot, mantle, CFrame.new(0, 0.22, 0.06))
	for _, side in { -1, 1 } do
		local pauldron = EnemyKit.block(b, "CapeShoulder", Vector3.new(1.56, 0.96, 1.20), "rock")
		EnemyKit.joint(
			capeRoot,
			pauldron,
			CFrame.new(side * 1.22, 0.10, 0.04) * CFrame.Angles(rad(7), rad(side * 15), rad(side * 8))
		)
	end

	local panels: { EnemyKit.Joint } = {}
	local count = math.max(math.floor(UnlittiusConfig.body.capePanelCount), 1)
	for index = 1, count do
		-- Asymmetric lengths, longest at the centre: a hem that is level reads as fabric that was cut.
		local fromCentre = math.abs(index - (count + 1) / 2)
		local length = P.capePanelLength * (1 - fromCentre * 0.14)
		local x = (index - (count + 1) / 2) * (P.capePanelWidth * 0.86)
		local panel = darken(
			EnemyKit.block(
				b,
				"CapePanel" .. index,
				Vector3.new(P.capePanelWidth, length, P.capePanelThickness),
				"chit"
			),
			0.28
		)
		local joint = EnemyKit.joint(
			capeRoot,
			panel,
			CFrame.new(x, 0.06, 0.16 + fromCentre * 0.06)
				* CFrame.Angles(rad(-4 - fromCentre * 3), rad(x * 4), rad(-x * 5)),
			-- Hung from the TOP EDGE, so the panel swings from the mantle rather than about its middle.
			CFrame.new(0, length * 0.5, 0)
		)
		table.insert(panels, joint)

		-- The torn hem: a wedge bitten out of the bottom of each panel, angled differently per panel.
		local tear = darken(EnemyKit.wedge(b, "CapeTear", Vector3.new(P.capePanelWidth * 0.9, 0.9, 0.24), "chit"), 0.34)
		EnemyKit.joint(
			panel,
			tear,
			CFrame.new(math.sin(index * 2.1) * 0.2, -length * 0.5 - 0.28, 0.02)
				* CFrame.Angles(rad(178), 0, rad((index - 3) * 9))
		)
	end

	-- A few talismans, attached flat to the cape rather than hanging like noodles.
	for index = 1, P.capeTagCount do
		local x = (index - (P.capeTagCount + 1) / 2) * 0.92
		local tag = EnemyKit.block(b, "CapeTalisman", Vector3.new(0.42, 0.90, 0.16), "rock")
		EnemyKit.joint(
			capeRoot,
			tag,
			CFrame.new(x, -1.30 - math.abs(x) * 0.24, 0.02) * CFrame.Angles(0, 0, rad((index - 2.5) * 5))
		)
		local mark = runeSurface(EnemyKit.block(b, "TalismanMark", Vector3.new(0.08, 0.30, 0.08), "chit"), 0.6)
		EnemyKit.joint(tag, mark, CFrame.new(0, 0, -0.10))
	end
	return panels
end

export type Rig = {
	root: BasePart,
	joints: { [string]: EnemyKit.Joint },
	orbitJoints: { EnemyKit.Joint },
	orbitStones: { BasePart },
	capePanels: { EnemyKit.Joint },
	rune: BasePart,
	runeLight: PointLight,
	eyes: { BasePart },
	emissive: { BasePart },
	attachments: { [string]: Attachment },
	torso: BasePart,
	head: BasePart,
}

function Unlittius.build(variant: EnemyKit.Variant, seed: number?): (Model, Rig)
	local scale = UnlittiusConfig.body.targetHeight / AUTHORED_HEIGHT
	local b = EnemyKit.begin("Unlittius", variant, seed, scale)
	local J: { [string]: EnemyKit.Joint } = {}
	local emissive: { BasePart } = {}
	local eyes: { BasePart } = {}

	-- THE ROOT IS INVISIBLE AND IS NOT A BODY PART. Every other creature in the pack roots on its
	-- torso; this one cannot, because his torso is going to rotate ninety degrees during the banish
	-- while the position the encounter tracks him by must not. The root is his hover point over the
	-- dais, and the body hangs off it.
	local root = EnemyKit.block(b, "Core", Vector3.new(1.6, 1.6, 1.2), "chit")
	root.Transparency = 1
	root.CastShadow = false

	-- ---------- floating base ----------
	local pelvis = EnemyKit.block(b, "PelvisStone", P.pelvisSize, "rock")
	J.pelvis = EnemyKit.joint(root, pelvis, CFrame.new(0, P.pelvisY, 0) * CFrame.Angles(0, rad(9), 0))
	for index, stone in P.baseStones do
		local part = EnemyKit.block(b, "FloatStone_" .. string.char(64 + index), stone.size, "rock")
		J["base" .. index] = EnemyKit.joint(
			root,
			part,
			CFrame.new(stone.offset)
				* CFrame.Angles(rad(if index % 2 == 0 then 8 else -6), rad(stone.yaw), rad((index - 2) * 4))
		)
		EnemyKit.anchor(b, part, CFrame.new(0, stone.size.Y * 0.4, 0), 0.4)
	end

	-- Loose fragments. Held on real joints so they can be driven in an orbit each frame rather than
	-- being welded scenery — the spec asks for them to RISE during the dripstone and the summon, and
	-- something welded cannot.
	local orbitJoints: { EnemyKit.Joint } = {}
	local orbitStones: { BasePart } = {}
	for index = 1, UnlittiusConfig.body.orbitStoneCount do
		local stone = EnemyKit.block(
			b,
			"OrbitStone_" .. index,
			P.orbitStoneSize * (0.8 + (index % 3) * 0.22),
			"rock",
			false
		)
		local joint = EnemyKit.joint(root, stone, CFrame.new(0, -2.0, 0))
		table.insert(orbitJoints, joint)
		table.insert(orbitStones, stone)
	end

	-- ---------- torso ----------
	local torso = EnemyKit.block(b, "Torso", P.torsoSize, "chit")
	darken(torso, 0.2)
	J.torso = EnemyKit.joint(root, torso, CFrame.new(0, P.torsoY, 0.08) * CFrame.Angles(rad(1), 0, 0))
	EnemyKit.anchor(b, torso, CFrame.new(0, P.torsoSize.Y * 0.4, 0.9), 0.55)

	-- Layered rib plates. Each one is narrower and tipped a little further than the last, so the chest
	-- reads as armour that was carved in courses rather than as a barrel.
	for index = 0, P.ribCount - 1 do
		local width = P.ribWidth - index * P.ribWidthStep
		local rib = EnemyKit.block(b, "RibPlate", Vector3.new(width, P.ribSize.Y, P.ribSize.Z), "rock")
		EnemyKit.joint(
			torso,
			rib,
			CFrame.new(0, P.ribTopY - index * P.ribStepY, -0.12 - index * 0.05)
				* CFrame.Angles(rad(-10 + index * 3), rad((if index % 2 == 0 then 1 else -1) * 7), 0)
		)
	end
	for _, side in { -1, 1 } do
		local mass = EnemyKit.block(b, "ShoulderMass", P.shoulderMassSize, "rock")
		EnemyKit.joint(
			torso,
			mass,
			CFrame.new(side * P.shoulderMassOffset.X, P.shoulderMassOffset.Y, P.shoulderMassOffset.Z)
				* CFrame.Angles(rad(10), rad(side * 18), rad(side * 12))
		)
		local flank = darken(EnemyKit.block(b, "Flank", P.flankSize, "chit"), 0.25)
		EnemyKit.joint(
			torso,
			flank,
			CFrame.new(side * 1.30, -0.42, 0.08) * CFrame.Angles(rad(-5), rad(side * 12), rad(side * 8))
		)
	end

	-- THE CHEST CAVITY AND THE UNLIT HEART. The rune is the brightest thing on him by a wide margin,
	-- recessed into a hollow so it throws its own shadow and so it is still legible when it has been
	-- dimmed to a tenth of its power by seven candles.
	local cavity = darken(EnemyKit.block(b, "ChestCavity", P.cavitySize, "chit"), 0.65)
	EnemyKit.joint(torso, cavity, CFrame.new(P.cavityOffset))
	local rune = runeSurface(EnemyKit.block(b, "ChestRune", P.runeSize, "chit"), 1)
	EnemyKit.joint(torso, rune, CFrame.new(P.runeOffset) * CFrame.Angles(0, 0, rad(45)))
	table.insert(emissive, rune)
	local runeLight = Instance.new("PointLight")
	runeLight.Name = "RuneLight"
	runeLight.Color = UnlittiusConfig.body.runeColor
	runeLight.Range = UnlittiusConfig.body.runeLightRange
	runeLight.Brightness = UnlittiusConfig.body.runeLightBrightness
	runeLight.Shadows = false
	runeLight.Parent = rune
	for index = 1, P.runeBarCount do
		local bar = runeSurface(
			EnemyKit.block(b, "RuneBar", Vector3.new(0.11, 0.64 + index * 0.08, 0.09), "chit"),
			0.7
		)
		EnemyKit.joint(
			torso,
			bar,
			CFrame.new((index - 2.5) * 0.34, -0.50 + math.sin(index) * 0.08, -1.20)
				* CFrame.Angles(0, 0, rad((index - 2.5) * 14))
		)
		table.insert(emissive, bar)
	end

	-- ---------- cape ----------
	local capeRoot = EnemyKit.block(b, "CapeRoot", Vector3.new(1.2, 0.5, 0.5), "chit")
	capeRoot.Transparency = 1
	J.cape = EnemyKit.joint(torso, capeRoot, CFrame.new(P.capeOffset) * CFrame.Angles(rad(3), 0, 0))
	local capePanels = buildCape(b, capeRoot)

	-- ---------- shoulders and arms ----------
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local shoulder = EnemyKit.block(b, "Shoulder_" .. tag, P.shoulderSize, "rock")
		J["sh" .. tag] = EnemyKit.joint(
			torso,
			shoulder,
			CFrame.new(side * P.shoulderOffset.X, P.shoulderOffset.Y, P.shoulderOffset.Z)
		)
		local cap = EnemyKit.block(b, "ShoulderCap", P.shoulderCapSize, "rock")
		EnemyKit.joint(
			shoulder,
			cap,
			CFrame.new(side * 0.40, 0.16, -0.06) * CFrame.Angles(rad(-8), rad(side * 18), rad(side * 10))
		)
		-- Dripstone-like spikes, so the shoulders read as part of the cave rather than as pauldrons.
		for k = 0, P.shoulderSpikeCount - 1 do
			local spike = EnemyKit.wedge(b, "ShoulderSpike", Vector3.new(0.56, 2.10 - k * 0.30, 0.62), "rock")
			EnemyKit.joint(
				shoulder,
				spike,
				CFrame.new(side * (0.12 + k * 0.26), 0.60 + k * 0.08, 0.04 + k * 0.14)
					* CFrame.Angles(rad(-18), rad(side * (18 + k * 18)), rad(side * 9))
			)
		end
		EnemyKit.anchor(b, shoulder, CFrame.new(0, P.shoulderSize.Y * 0.4, 0.3), 0.45)

		-- THE SHORTENED ARM. Upper arm and forearm hinge at their TOP END (the `c1` offset), so the
		-- limb rotates about the joint rather than about its own centre — which is the difference
		-- between an arm and a propeller.
		local upper = EnemyKit.block(b, "UpperArm_" .. tag, P.upperArmSize, "rock")
		J["up" .. tag] = EnemyKit.joint(
			shoulder,
			upper,
			CFrame.new(side * P.upperArmX, P.upperArmY, -0.02)
				* CFrame.Angles(rad(P.upperArmRestPitch), rad(side * -7), rad(side * 5)),
			CFrame.new(0, 0, P.upperArmSize.Z * 0.5 - 0.06)
		)
		local elbow = darken(EnemyKit.block(b, "ElbowCuff", P.cuffSize, "chit"), 0.4)
		EnemyKit.joint(upper, elbow, CFrame.new(0, 0.02, -P.upperArmLength * 0.96) * CFrame.Angles(0, rad(side * 10), 0))

		local forearm = EnemyKit.block(b, "Forearm_" .. tag, P.forearmSize, "rock")
		J["fo" .. tag] = EnemyKit.joint(
			upper,
			forearm,
			CFrame.new(0, -0.08, -P.upperArmLength)
				* CFrame.Angles(rad(P.forearmRestPitch), rad(side * 6), rad(side * -3)),
			CFrame.new(0, 0, P.forearmSize.Z * 0.5 - 0.06)
		)
		local wrist = darken(EnemyKit.block(b, "WristBlock", Vector3.new(1.02, 0.78, 0.52), "chit"), 0.4)
		EnemyKit.joint(forearm, wrist, CFrame.new(0, 0, -P.forearmLength * 0.98) * CFrame.Angles(0, rad(side * -8), 0))
		local seam = runeSurface(EnemyKit.block(b, "ForearmSeam", Vector3.new(0.10, 0.10, 1.30), "chit"), 0.5)
		EnemyKit.joint(forearm, seam, CFrame.new(side * 0.26, 0.02, -0.70))
		table.insert(emissive, seam)

		local hand = EnemyKit.block(b, "Hand_" .. tag, Vector3.new(0.9, 0.6, 0.6), "chit")
		hand.Transparency = 1
		J["hd" .. tag] = EnemyKit.joint(
			forearm,
			hand,
			CFrame.new(0, 0.02, -P.forearmLength) * CFrame.Angles(rad(P.handRestPitch), rad(side * -10), rad(side * -10))
		)
		J["claw" .. tag] = buildHand(b, hand, side)
	end

	-- ---------- head ----------
	local neck = darken(EnemyKit.block(b, "Neck", Vector3.new(0.90, 0.76, 0.88), "chit"), 0.35)
	J.neck = EnemyKit.joint(torso, neck, CFrame.new(0, P.neckY, 0))
	local head = darken(EnemyKit.block(b, "Head", P.skullSize, "chit"), 0.3)
	J.head = EnemyKit.joint(neck, head, CFrame.new(0, P.headY, -0.04))

	-- THE FACE IS A HOLE. No mouth, no skull, no expression — a recessed black plate with two small
	-- violet eyes in it, which is the entire reason he is frightening rather than monstrous.
	local void = darken(EnemyKit.block(b, "FaceVoid", P.faceVoidSize, "chit"), 0.88)
	void.Reflectance = 0
	EnemyKit.joint(head, void, CFrame.new(P.faceVoidOffset))
	for _, side in { -1, 1 } do
		local eye = runeSurface(EnemyKit.block(b, "Eye", P.eyeSize, "chit"), 1)
		EnemyKit.joint(head, eye, CFrame.new(side * P.eyeOffset.X, P.eyeOffset.Y, P.eyeOffset.Z))
		table.insert(eyes, eye)
		table.insert(emissive, eye)
		-- Cheek armour and a temple fin per side: the head has to be wide enough to carry the hood.
		local cheek = EnemyKit.block(b, "CheekPlate", Vector3.new(0.84, 1.60, 1.12), "rock")
		EnemyKit.joint(head, cheek, CFrame.new(side * 0.60, -0.18, -0.02) * CFrame.Angles(0, rad(side * 18), rad(side * 8)))
		local fin = EnemyKit.wedge(b, "HeadFin", P.cheekFinSize, "rock")
		EnemyKit.joint(head, fin, CFrame.new(side * 0.72, 0.30, 0.22) * CFrame.Angles(rad(-28), rad(side * 30), rad(side * 10)))
	end
	-- Hanging stones under the void, which give the face a ragged beard-like edge in silhouette.
	for index = 1, P.chinStoneCount do
		local x = (index - (P.chinStoneCount + 1) / 2) * 0.22
		local chin = darken(
			EnemyKit.wedge(b, "ChinStone", Vector3.new(0.32, 1.20 - 0.14 * math.abs(index - 3), 0.30), "chit"),
			0.5
		)
		EnemyKit.joint(head, chin, CFrame.new(x, -0.79, -0.64) * CFrame.Angles(rad(180), 0, rad((index - 3) * 5)))
	end

	local crown = EnemyKit.block(b, "Crown", Vector3.new(1.0, 0.4, 1.0), "chit")
	crown.Transparency = 1
	J.crown = EnemyKit.joint(head, crown, CFrame.new(0, P.crownY, 0.08))
	buildHood(b, crown)
	EnemyKit.anchor(b, head, CFrame.new(0, 0.7, 0.5), 0.4)

	-- ---------- attachments ----------
	-- Named exactly as the handoff package's rig blueprint names them, because these are the contract
	-- between the body and everything that fires from it: the two boulder origins are what guarantee a
	-- conjured stone can never appear inside his torso, and the melee traces are what the server
	-- sweeps at each rake's contact frame.
	local attachments: { [string]: Attachment } = {}
	attachments.ChestFX = attachment(rune, "ChestFX", CFrame.new(0, 0, -0.4))
	attachments.HeadFX = attachment(head, "HeadFX", CFrame.new(0, 0.2, -0.9))
	attachments.AudioEmitter = attachment(torso, "AudioEmitter", CFrame.new(0, 0.4, 0))
	attachments.CeilingAnchor = attachment(root, "CeilingAnchor", CFrame.new(0, 0, 0))
	local boulder = UnlittiusConfig.boulder
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		attachments["BoulderSpawn_" .. tag] = attachment(
			root,
			"BoulderSpawn_" .. tag,
			CFrame.new(side * boulder.spawnOutboard, boulder.spawnHeight, -boulder.spawnForward)
		)
		local handPart = b.model:FindFirstChild("Hand_" .. tag) :: BasePart
		attachments["MeleeTrace_" .. tag] = attachment(handPart, "MeleeTrace_" .. tag, CFrame.new(0, -0.4, -1.4))
	end

	-- ---------- volumes ----------
	-- ONE query volume around the body a player can actually reach, and one collidable box that keeps
	-- them from walking through him. Both are sized to the FLOATING body, which starts well above the
	-- dais — nothing here should touch the floor, because he does not.
	EnemyKit.hitbox(b, root, Vector3.new(4.6, 9.0, 3.6), CFrame.new(0, 1.0, 0))
	EnemyKit.collider(b, root, Vector3.new(3.6, 6.4, 2.8), CFrame.new(0, 0.2, 0))

	local model = EnemyKit.finish(b, root, "Unlittius", 6)
	return model,
		{
			root = root,
			joints = J,
			orbitJoints = orbitJoints,
			orbitStones = orbitStones,
			capePanels = capePanels,
			rune = rune,
			runeLight = runeLight,
			eyes = eyes,
			emissive = emissive,
			attachments = attachments,
			torso = torso,
			head = head,
		}
end

-- THE CEILING RELIEF. A separate, anchored, purpose-built asset rather than the live rig left rotated
-- inside the rock forever — which is what the package recommends and what the fight needs: the relief
-- outlives the encounter, and an animated Motor6D chain hanging in a ceiling for the rest of a run is
-- a body the engine keeps solving for no reason.
--
-- It is built from the same `P` as the live body so the swap has nothing to line up: the same hood,
-- the same shoulders, the same claws, pressed flat and stripped of everything that would not survive
-- being carved — the cape, the floating base, the orbit stones and every emissive piece.
function Unlittius.relief(variant: EnemyKit.Variant, seed: number?): Model
	local scale = UnlittiusConfig.body.targetHeight / AUTHORED_HEIGHT
	local b = EnemyKit.begin("UnlittiusRelief", variant, seed, scale)

	local slab = EnemyKit.block(b, "ReliefSlab", Vector3.new(9.6, 1.0, 8.4), "rock")
	darken(slab, 0.12)

	-- Torso and hood, flattened along the ceiling's normal. IT IS BUILT ALREADY FACE-DOWN: every
	-- feature hangs below the slab on -Y and everything is squashed on Y, so the caller places it at
	-- the ceiling with a yaw and nothing else. Building it upright and rotating it at placement time
	-- was the obvious alternative and the worse one — the pitch would have to be exactly right or the
	-- relief reads as a statue glued to the roof rather than as a carving pressed into it.
	local torso = darken(EnemyKit.block(b, "ReliefTorso", Vector3.new(3.7, 0.9, 2.9), "chit"), 0.18)
	EnemyKit.joint(slab, torso, CFrame.new(0, -0.55, 0.4))
	for index = 0, 4 do
		local rib = EnemyKit.block(b, "ReliefRib", Vector3.new(3.5 - index * 0.3, 0.34, 0.7), "rock")
		EnemyKit.joint(torso, rib, CFrame.new(0, -0.30, 0.9 - index * 0.44) * CFrame.Angles(rad(index * 2), 0, 0))
	end
	local heart = darken(EnemyKit.block(b, "ReliefHeart", Vector3.new(0.9, 0.30, 1.2), "chit"), 0.7)
	EnemyKit.joint(torso, heart, CFrame.new(0, -0.5, 0.2) * CFrame.Angles(0, rad(45), 0))

	local head = darken(EnemyKit.block(b, "ReliefHead", Vector3.new(1.5, 0.8, 1.4), "chit"), 0.3)
	EnemyKit.joint(slab, head, CFrame.new(0, -0.5, -1.9))
	local face = darken(EnemyKit.block(b, "ReliefFace", Vector3.new(2.2, 0.34, 2.3), "chit"), 0.88)
	EnemyKit.joint(head, face, CFrame.new(0, -0.5, 0))
	local layerDepth = 0.62
	for index = 1, P.hoodLayers do
		local shrink = 1 - (index - 1) / P.hoodLayers * 0.82
		local layer = EnemyKit.block(
			b,
			"ReliefHood" .. index,
			Vector3.new(P.hoodBaseWidth * shrink, layerDepth * (1 - index * 0.1), P.hoodHeight / P.hoodLayers * 1.1),
			"rock"
		)
		if index % 2 == 0 then
			darken(layer, 0.16)
		end
		EnemyKit.joint(
			head,
			layer,
			CFrame.new(0, -0.20 - index * 0.05, -0.9 - (index - 0.5) * (P.hoodHeight / P.hoodLayers))
				* CFrame.Angles(0, rad(18 + index * 7), 0)
		)
	end

	-- Arms spread wide and flat, claws splayed: the pose the banish track ends in.
	for _, side in { -1, 1 } do
		local shoulder = EnemyKit.block(b, "ReliefShoulder", Vector3.new(1.7, 0.8, 1.7), "rock")
		EnemyKit.joint(slab, shoulder, CFrame.new(side * 1.9, -0.5, -0.5) * CFrame.Angles(0, rad(side * 12), 0))
		local upper = EnemyKit.block(b, "ReliefUpperArm", Vector3.new(P.upperArmLength * 1.05, 0.66, 0.8), "rock")
		EnemyKit.joint(shoulder, upper, CFrame.new(side * P.upperArmLength * 0.62, -0.24, 0.32) * CFrame.Angles(0, rad(side * -14), 0))
		local forearm = EnemyKit.block(b, "ReliefForearm", Vector3.new(P.forearmLength * 1.05, 0.62, 0.76), "rock")
		EnemyKit.joint(upper, forearm, CFrame.new(side * P.forearmLength * 0.92, -0.10, 0.52) * CFrame.Angles(0, rad(side * -10), 0))
		for index = 1, 3 do
			local talon = EnemyKit.wedge(b, "ReliefTalon", Vector3.new(1.5, 0.44, 0.34), "rock")
			EnemyKit.joint(
				forearm,
				talon,
				CFrame.new(side * (P.forearmLength * 0.7 + 0.5), -0.12, (index - 2) * 0.66)
					* CFrame.Angles(0, rad(side * (-90 + (index - 2) * 16)), rad(90))
			)
		end
	end

	-- The seam around the perimeter: four thin courses of chipped stone that make the relief look
	-- pressed INTO the ceiling rather than stuck onto it.
	for index = 0, 3 do
		local along = index % 2 == 0
		local seam = darken(
			EnemyKit.block(
				b,
				"ReliefSeam",
				if along then Vector3.new(9.8, 0.5, 0.42) else Vector3.new(0.42, 0.5, 8.6),
				"chit"
			),
			0.45
		)
		local sign = if index < 2 then 1 else -1
		EnemyKit.joint(
			slab,
			seam,
			if along then CFrame.new(0, -0.2, sign * 4.3) else CFrame.new(sign * 4.9, -0.2, 0)
		)
	end

	local model = EnemyKit.finish(b, slab, "UnlittiusRelief", 6)
	-- Scenery from the moment it exists: anchored, non-colliding, and never stepped by anything.
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	return model
end

-- ============================================================
-- CONTROLLER
-- ============================================================
export type Body = typeof(setmetatable({} :: any, Unlittius))

local STATE_TRACK: { [string]: string } = {
	Idle = "idle",
	Dripstone = "dripstone",
	BoulderBurst = "boulder",
	SummonGnawers = "summon",
	Melee = "melee",
	Recoil = "recoil",
	Banish = "banish",
}

function Unlittius.new(cframe: CFrame, variant: EnemyKit.Variant?, seed: number?): Body
	local resolved = variant or "regular"
	local model, rig = Unlittius.build(resolved, seed)
	model:PivotTo(cframe)

	-- ANCHORED AT THE ROOT, LIKE EVERY OTHER CFRAME-DRIVEN BODY IN THIS PACK, and for one extra reason
	-- of his own: he FLOATS. Handing a levitating stack of stone to the physics solver means either a
	-- BodyPosition fighting gravity every frame or a body that falls on its own dais. His height is a
	-- number the encounter owns, not a force balance.
	rig.root.Anchored = true

	return setmetatable({
		model = model,
		root = rig.root,
		rig = rig,
		joints = rig.joints,
		variant = resolved,
		state = "Idle",
		t = 0,
		stateT = 0,
		-- Where the root rests, before hover. Written once at spawn and again only by the banish.
		anchorCFrame = cframe,
		candlesLit = 0,
		power = 1,
		-- DERIVED FROM THE BUILD SEED, not from `math.random`. The hover is only a bob, but this module
		-- is handed a seed precisely so that the same floor replays the same creature — and a body whose
		-- idle phase came from unseeded global randomness would be a different boss every time a seed was
		-- re-run, which is exactly the kind of drift that makes a "deterministic" floor untestable.
		hoverPhase = ((model:GetAttribute("Seed") :: number?) or 1) % 6.283,
		-- 0..1, how far the loose stones have lifted out of their orbit. Raised during the dripstone
		-- and the summon, which the spec asks for and which is the cheapest possible way to make the
		-- room itself look like it is answering him.
		orbitLift = 0,
		banishProgress = 0,
		-- His current travel, in studs per second, written by the behaviour every frame. Drives the lean
		-- and the cape trail; the movement itself is applied through `moveBy`.
		travelVelocity = Vector3.zero,
	}, Unlittius)
end

function Unlittius.setState(self: Body, state: string)
	if self.state == state or self.state == "Banish" then
		return
	end
	self.state = state
	self.stateT = 0
	self.model:SetAttribute("State", state)
end

-- HOW MUCH OF HIM IS LEFT. Applied to every emissive part, the rune light and the eyes at once, and
-- it never goes back up: the dim is permanent per candle, which is the encounter's whole promise.
function Unlittius.setPower(self: Body, candlesLit: number, brightness: number)
	self.candlesLit = candlesLit
	self.power = math.clamp(brightness, 0, 1)
	local color = UnlittiusConfig.body.runeColor
	for _, part in self.rig.emissive do
		part.Color = color:Lerp(Color3.new(0, 0, 0), 1 - self.power * 0.9)
		part.Transparency = (1 - self.power) * 0.55
	end
	self.rig.runeLight.Brightness = UnlittiusConfig.body.runeLightBrightness * self.power
	self.rig.runeLight.Range = UnlittiusConfig.body.runeLightRange * (0.45 + 0.55 * self.power)
	self.model:SetAttribute("Power", self.power)
	self.model:SetAttribute("CandlesLit", candlesLit)
end

-- Where a boulder is conjured, in world space. Read off the real attachment rather than computed from
-- the root, so the origin moves with whatever the arms are doing and can never end up inside him.
function Unlittius.boulderOrigin(self: Body, side: number): CFrame
	local tag = if side < 0 then "L" else "R"
	local point = self.rig.attachments["BoulderSpawn_" .. tag]
	if point == nil then
		return self.root.CFrame * CFrame.new(side * 3.4, 1.1, -2.4)
	end
	return point.WorldCFrame
end

function Unlittius.meleeTrace(self: Body, side: number): CFrame
	local tag = if side < 0 then "L" else "R"
	local point = self.rig.attachments["MeleeTrace_" .. tag]
	if point == nil then
		return self.root.CFrame
	end
	return point.WorldCFrame
end

function Unlittius.chestPosition(self: Body): Vector3
	return self.rig.rune.Position
end

-- Face a point without moving. He turns to watch whoever he is about to answer, and the turn is slow
-- enough that getting behind him is a real answer to the rake — the same contract the Grub Queen's
-- twenty-four degrees a second makes.
function Unlittius.faceToward(self: Body, target: Vector3, dt: number, degreesPerSecond: number)
	local origin = self.anchorCFrame.Position
	local offset = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	if offset.Magnitude < 0.5 then
		return
	end
	local desired = math.atan2(offset.Unit.X, offset.Unit.Z)
	local facing = self.anchorCFrame.LookVector
	local current = math.atan2(facing.X, facing.Z)
	local difference = (desired - current + math.pi) % (2 * math.pi) - math.pi
	local step = math.rad(degreesPerSecond) * dt
	local yaw = current + math.clamp(difference, -step, step)
	self.anchorCFrame = CFrame.new(origin) * CFrame.Angles(0, yaw, 0)
end

-- MOVE HIM. The behaviour owns WHERE (it reads the room and the players); this owns the fact that his
-- position is a property of the anchor rather than of the root, so the hover, the lean and the banish
-- all keep composing on top of it instead of fighting it.
--
-- HE IS NEVER ASSIGNED A POSITION, ONLY OFFSET BY A VELOCITY. That is the whole difference between a
-- levitating body and a prop being teleported around a room, and it is why `velocity` is eased by
-- `UnlittiusRules.stepVelocity` before it ever reaches here.
function Unlittius.moveBy(self: Body, delta: Vector3)
	if delta.Magnitude < 1e-5 then
		return
	end
	local base = self.anchorCFrame
	self.anchorCFrame = CFrame.new(base.Position + delta) * (base - base.Position)
end

function Unlittius.setPosition(self: Body, position: Vector3)
	local base = self.anchorCFrame
	self.anchorCFrame = CFrame.new(position) * (base - base.Position)
end

-- How hard he is leaning into his own travel, 0..1 of `Config.Unlittius.movement.leanDegrees`, and in
-- which direction. Written by the behaviour each frame and applied in `step` as an additive pose on
-- the torso and the cape — additive rather than keyframed because it has to survive every track,
-- including the ones that hold a pose perfectly still.
function Unlittius.setTravel(self: Body, velocity: Vector3)
	self.travelVelocity = velocity
end

-- THE BANISH IS A ROOT MOVE, not a pose, so it lives here rather than in the track: he is pulled up,
-- rolled onto his back against the ceiling plane, and pressed in. `progress` is 0..1 across
-- `Config.Unlittius.banish.completeAt`, and `rise` is how far above his dais the ceiling is.
function Unlittius.applyBanish(self: Body, progress: number, rise: number)
	local banish = UnlittiusConfig.banish
	local length = math.max(banish.completeAt, 0.001)
	local elapsed = math.clamp(progress, 0, 1) * length

	-- The lift starts slowly and then takes him: nothing about this should look like flying.
	local liftStart = banish.unbindSeconds
	local liftSpan = math.max(banish.alignSeconds - liftStart, 0.001)
	local lift = math.clamp((elapsed - liftStart) / liftSpan, 0, 1)
	local eased = lift * lift * (3 - 2 * lift)

	-- The roll onto the ceiling plane runs slightly behind the lift, so he arrives face-down rather
	-- than arriving and then rotating — which would read as a prop being placed.
	local rollStart = banish.unbindSeconds + 0.1
	local rollSpan = math.max(banish.alignSeconds - rollStart, 0.001)
	local roll = math.clamp((elapsed - rollStart) / rollSpan, 0, 1)
	local rollEased = roll * roll * (3 - 2 * roll)

	-- The last press into the rock, after the roll has finished.
	local embed = math.clamp((elapsed - banish.alignSeconds) / math.max(banish.reliefSwapAt - banish.alignSeconds, 0.001), 0, 1)

	self.banishProgress = math.clamp(progress, 0, 1)
	local base = self.anchorCFrame
	local height = rise * eased + embed * banish.ceilingInset
	self.root.CFrame = CFrame.new(base.Position + Vector3.new(0, height, 0))
		* (base - base.Position)
		* CFrame.Angles(-math.pi * 0.5 * rollEased, 0, 0)
end

function Unlittius.step(self: Body, dt: number)
	self.t += dt
	self.stateT += dt

	local trackName = STATE_TRACK[self.state] or "idle"
	local track = T[trackName]
	EnemyKit.evaluate(self.joints, track, self.stateT)

	-- HOVER. Applied to the root AFTER the pose, and deliberately not part of any track: it must keep
	-- running through every state, including the ones a track holds perfectly still, or he lands.
	-- Suppressed during the banish, which owns the root outright.
	if self.state ~= "Banish" then
		local body = UnlittiusConfig.body
		local bob = math.sin(self.t * body.hoverFrequency * math.pi * 2 + self.hoverPhase) * body.hoverAmplitude
		-- A second, slower wave a third the size, so the hover never resolves into a clean sine — the
		-- one thing that would make a levitating body read as a prop on a lift.
		bob += math.sin(self.t * body.hoverFrequency * 0.61 + self.hoverPhase * 1.7) * body.hoverAmplitude * 0.34
		self.root.CFrame = self.anchorCFrame * CFrame.new(0, bob, 0)
	end

	-- THE ORBIT. Driven per-frame rather than keyframed, because it is continuous, and lifted during
	-- the two attacks that pull on the room. The stones counter-rotate against each other so the
	-- cluster never reads as one rigid wheel.
	local lifted = if self.state == "Dripstone" or self.state == "SummonGnawers" then 1 else 0
	self.orbitLift += (lifted - self.orbitLift) * math.min(dt * 2.4, 1)
	local body = UnlittiusConfig.body
	for index, joint in self.rig.orbitJoints do
		local direction = if index % 2 == 0 then -1 else 1
		local angle = self.t * body.orbitSpeed * direction + index * (math.pi * 2 / #self.rig.orbitJoints)
		local radius = body.orbitRadius * (0.82 + (index % 3) * 0.12)
		local height = -2.05 - (index % 3) * 0.30 + self.orbitLift * (1.6 + (index % 2) * 0.5)
		EnemyKit.poseOffset(
			joint,
			CFrame.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
				* CFrame.Angles(self.t * 0.55 + index, self.t * 0.42, self.t * 0.28 + index)
		)
	end

	-- LEANING INTO THE DRIFT. Applied on top of whatever the track just posed, because it has to
	-- survive every state including the ones that hold the torso perfectly still — a boss who stopped
	-- leaning the moment he started an attack would visibly snap upright mid-glide.
	--
	-- THE LEAN IS IN HIS OWN FRAME, so travelling forward tips him forward and drifting sideways rolls
	-- him: the same body reading two different kinds of movement, which is most of what makes the
	-- levitation look intentional rather than like a sliding prop.
	local travel = self.travelVelocity
	local leanAmount = 0
	if travel.Magnitude > 0.05 then
		local movement = UnlittiusConfig.movement
		local fraction = math.clamp(travel.Magnitude / math.max(movement.advanceSpeed, 0.001), 0, 1)
		leanAmount = math.rad(movement.leanDegrees) * fraction
		local facing = self.anchorCFrame.LookVector
		local right = Vector3.new(-facing.Z, 0, facing.X)
		local forwardShare = Vector3.new(facing.X, 0, facing.Z).Unit:Dot(travel.Unit)
		local lateralShare = right.Unit:Dot(travel.Unit)
		local torso = self.joints.torso
		if torso ~= nil then
			torso.motor.C0 = torso.motor.C0
				* CFrame.Angles(leanAmount * forwardShare, 0, -leanAmount * lateralShare * 1.3)
		end
		-- The base stones lag the torso rather than leading it: the mass at the bottom is the last
		-- thing to agree that he is going anywhere.
		for index = 1, #P.baseStones do
			local joint = self.joints["base" .. index]
			if joint ~= nil then
				local lag = 0.35 + index * 0.12
				EnemyKit.poseOffset(
					joint,
					CFrame.Angles(-leanAmount * forwardShare * lag, 0, leanAmount * lateralShare * lag)
				)
			end
		end
	end

	-- CAPE LAG. The panels trail whatever the torso just did, outer panels more than inner ones. Two
	-- degrees of it at rest, which is all a stone-heavy cape should ever have — and a little more when
	-- he is actually travelling, because a cape that ignored the drift would read as painted on.
	local sway = math.sin(self.t * 0.8 + self.hoverPhase) * 0.02
	local trail = leanAmount * 0.9
	for index, joint in self.rig.capePanels do
		local fromCentre = math.abs(index - (#self.rig.capePanels + 1) / 2)
		EnemyKit.poseOffset(
			joint,
			CFrame.Angles(sway * (1 + fromCentre * 0.6) - trail * (0.6 + fromCentre * 0.25), 0, sway * fromCentre * 0.5)
		)
	end

	-- The rune breathes while he is awake and flickers hard in the frame after a candle lands.
	if self.state ~= "Banish" then
		local pulse = 0.5 + 0.5 * math.sin(self.t * 1.7)
		local flare = if self.state == "Recoil" and self.stateT < 0.22 then 1 else 0
		self.rig.runeLight.Brightness = UnlittiusConfig.body.runeLightBrightness
			* self.power
			* (0.75 + pulse * 0.25 + flare * 2.2)
	end
end

function Unlittius.destroy(self: Body)
	self.model:Destroy()
end

return Unlittius

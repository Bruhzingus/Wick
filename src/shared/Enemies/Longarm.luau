--!strict
-- Longarm — tier 3 stalker. The reveal is the whole design.
-- Place at: ReplicatedStorage/Enemies/Longarm
--
-- IT HAS ONE SET OF LIMBS. The arms hang directly alongside the legs, slightly
-- outboard and slightly behind, running the full length of them and ending in a
-- hand that rests on the ground like a second foot. At a glance it is a tall
-- biped standing on two thick limbs. Then it strikes and half of each limb
-- peels away to nine studs of reach.
--
-- The safe distance the player learned from every other enemy is wrong here,
-- and they only find out once.
--
-- The player cannot attack, so the counters are entirely positional and
-- resource-based:
--   * FLARE is the only thing that scares it. Nothing else works.
--   * DECOY CANDLES pull it away — it grabs and destroys them, which buys time.
--   * At maximum reach it only damages. Closer, it grabs, jumpscares, and
--     drops you, then ignores you for a few seconds. That grace window is what
--     stops a grab being a death sentence in a game with no combat.
--
-- Slow, quiet, no idle vocalisation. It is the one enemy that gives you nothing
-- to hear until it is already committed.

local EnemyKit = require(script.Parent.EnemyKit)

local Longarm = {}
Longarm.__index = Longarm

Longarm.Config = {
	health = 80,
	speed = 4.5,
	fleeSpeed = 9,
	-- REACH BANDS, AND BOTH ARE MEASURED OFF THE BUILT ARM rather than chosen. Taken flat (XZ) from
	-- the pelvis — which is the point the brain measures a player against — to the fingertip:
	--
	--   reachMax  9.0 — the arm at full extension, elbow straight, at the height the strike lands
	--                   (2.5 studs below the pelvis, which is player chest height). Measured 9.01.
	--                   THIS IS THE SLASH BAND'S OUTER EDGE and the entire point of the creature: a
	--                   player who learned safe distance from anything else on the roster is inside it.
	--   reachGrab 6.0 — where the elbow can still FOLD around something rather than just touch it. At
	--                   90 degrees of elbow the hand is 6.99 out and at 120 it is 4.72, so a hand that
	--                   closes at about 100 sits right about here.
	--
	-- Both scale with the body: at BODY_SCALE 2.5 the arm measures 8.4 studs of limb, and these are
	-- what that limb can actually touch. Re-measure them if the scale ever changes.
	reachMax = 9.0,
	reachGrab = 6.0,
	-- Fractions of this game's `Config.Wax.maxWax` (1.3), not the pack's original raw units — see
	-- Config/Longarm.luau header. Kept numerically in sync with that file, which is what integration
	-- actually reads at runtime.
	grazeDamage = 0.22,
	grabDamage = 0.55,
	-- After a grab it drops you and loses interest. Without this, a no-combat
	-- game turns a single grab into an unrecoverable chain.
	ignoreSeconds = 6.0,
	holdSeconds = 1.4,
	flareThreshold = 0.78,
	fleeSeconds = 5.0,
	revealSeconds = 0.55,
	extendSeconds = 0.45,
	-- The slash is a whip across the outer band and it commits the body for longer than the thrust
	-- does: the arm has to travel the full arc and follow through past where it hit.
	slashSeconds = 0.62,
	decoyInterest = 26,
	-- How long the body spends folding down and standing back up. Both are travelled through while
	-- still walking — see the STOOPING block below.
	foldSeconds = 0.42,
	riseSeconds = 0.72,
}

-- WHAT THE BODY MEASURES WHILE STOOPED, in AUTHORED studs — multiply by the model's `BodyScale`
-- attribute, which already carries BODY_SCALE and the elder bonus, to get the real thing.
--
-- BOTH NUMBERS ARE MEASURED FROM THE BUILT RIG RATHER THAN ESTIMATED: the model is constructed
-- outside the engine, `T.stoop` is evaluated across its whole cycle, and the worst frame of the cycle
-- is taken. Authored studs rather than a fraction of the standing height because the fraction would
-- have to be taken against something — extents that include the oversized Hitbox, or a rest pose the
-- creature is never actually in — and every one of those choices is off by enough to matter when the
-- question is "does it fit through an 8-stud hole".
--
--   height — what the opening has to clear. 2.86 authored is 7.14 at BODY_SCALE 2.5, against a
--            standing 11.79 and a `doorwayMinHeight` of 8. That margin is the whole design.
--   ride   — where the pelvis sits, which the Humanoid has to be told (EnemyMover.setRideHeight) or
--            the creature folds with its feet hanging in the air. Taken from the TOP of the gait
--            cycle so the feet never sink into the rock; at the bottom of the cycle they lift a
--            fraction of a stud instead, which is the harmless direction to be wrong in.
--   stand  — the standing silhouette, for the same reason: `Model:GetExtentsSize()` answers 13.9 at
--            BODY_SCALE 2.5 because the Hitbox is deliberately taller than the head, and a creature
--            that believed it was 13.9 studs tall would fold under roof features it fits beneath.
Longarm.Stance = {
	standHeight = 4.72,
	stoopHeight = 2.86,
	stoopRide = 1.74,
}

local SOUNDS = { creep = "", reveal = "", snap = "", grab = "", scream = "", flee = "", death = "" }
local rad = math.rad

-- THE ANATOMY BELOW IS AUTHORED FAR SMALLER THAN THIS CREATURE'S OWN NUMBERS ASSUME, and this is the
-- correction. Every dimension in `build` is left exactly as drawn — the proportions are right, the
-- scale was not — and `EnemyKit.finish` grows the finished rig, joint offsets, hitbox, collider and
-- rest poses together.
--
-- The authored body stands 4.7 studs, barely taller than the player, while `reachMax` is 9 and a
-- fully extended arm measures 3.36 (upper 1.62 plus fore 1.74). A creature whose whole design is
-- "the reach is longer than you thought" cannot have a reach nearly three times longer than the limb
-- the player watches do it — a grab landing six studs past the visible hand reads as a bug, not as a
-- reveal. At 2.5x the arm measures 8.4 against a 9-stud reach and the body stands ~11.8, which is
-- what "the tallest thing on the roster" (Config/Longarm) was always meant to mean.
--
-- IT IS NOW TALLER THAN THE CAVE'S DOORWAYS, WHICH ROLL 8 TO 13 STUDS (Config/Floors). That is what
-- `T.stoop` and STOOP_HEIGHT below exist for: it folds down to get through, the way anything this
-- shape would have to, and LongarmBehavior probes the rock overhead to decide when.
local BODY_SCALE = 2.5

-- ============================================================
-- ANIMATION
-- Folded poses keep shoulder pitch near -20 and elbow near +150, which tucks
-- the forearm back along the upper arm and against the ribs. That is what makes
-- the limb read as a leg rather than an arm.
-- ============================================================
local T = {}

-- Arm base joints carry NO rotation, so this table is the entire rest pose.
-- Previously the fold was baked into the joint AND re-applied by the track,
-- which double-folded the arm and pushed it out where it read as a wing.
--
-- -80 degrees of shoulder pitch drops the arm almost straight down, parallel to
-- the leg it sits beside. A nearly-straight elbow keeps it that way for its full
-- length, so the two limbs read as one.
local FOLD = {
	shoulderL = { rad(-80), 0, rad(-5) },
	shoulderR = { rad(-80), 0, rad(5) },
	elbowL = { rad(-4), 0, 0 },
	elbowR = { rad(-4), 0, 0 },
	wristL = { rad(14), 0, 0 },
	wristR = { rad(14), 0, 0 },
}

T.idle = EnemyKit.track({
	{ t = 0.0, pose = { shoulderL = FOLD.shoulderL, shoulderR = FOLD.shoulderR, elbowL = FOLD.elbowL, elbowR = FOLD.elbowR, wristL = FOLD.wristL, wristR = FOLD.wristR, chest = { rad(14), 0, 0 }, neck = { rad(10), 0, 0 }, head = { rad(6), rad(-10), 0 }, hipL = { rad(-4), 0, 0 }, hipR = { rad(4), 0, 0 } }, ease = "inOutQuad" },
	{ t = 2.2, pose = { chest = { rad(16), rad(4), 0 }, neck = { rad(8), rad(6), 0 }, head = { rad(4), rad(14), 0 } }, ease = "inOutQuad" },
	{ t = 4.4, pose = { chest = { rad(14), 0, 0 }, neck = { rad(10), 0, 0 }, head = { rad(6), rad(-10), 0 } }, ease = "inOutQuad" },
}, true)

-- Creeping. Slow, low, arms still folded. Deliberately quiet in motion.
T.move = EnemyKit.track({
	{ t = 0.0, pose = { shoulderL = FOLD.shoulderL, shoulderR = FOLD.shoulderR, elbowL = FOLD.elbowL, elbowR = FOLD.elbowR, chest = { rad(20), rad(3), 0 }, neck = { rad(12), 0, 0 }, head = { rad(4), rad(-6), 0 }, hipL = { rad(24), 0, 0 }, hipR = { rad(-24), 0, 0 }, kneeL = { rad(-30), 0, 0 }, kneeR = { rad(-6), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.7, pose = { chest = { rad(20), rad(-3), 0 }, head = { rad(4), rad(6), 0 }, hipL = { rad(-24), 0, 0 }, hipR = { rad(24), 0, 0 }, kneeL = { rad(-6), 0, 0 }, kneeR = { rad(-30), 0, 0 } }, ease = "inOutQuad" },
	{ t = 1.4, pose = { chest = { rad(20), rad(3), 0 }, head = { rad(4), rad(-6), 0 }, hipL = { rad(24), 0, 0 }, hipR = { rad(-24), 0, 0 }, kneeL = { rad(-30), 0, 0 }, kneeR = { rad(-6), 0, 0 } }, ease = "inOutQuad" },
}, true)

-- ============================================================
-- STOOPING. The doorway problem, and the only reason this creature can use the cave at all.
--
-- At full size it stands 11.8 studs and the cave's openings roll 8 to 13 (Config/Floors), so for the
-- tightest of them it has to fold to about 7.1 — measured, not estimated; see STOOP below.
--
-- IT DOES NOT CROUCH LIKE SOMETHING HIDING, IT FOLDS LIKE SOMETHING TOO BIG FOR THE ROOM. The hips
-- break past horizontal, the knees buckle out to the sides, the spine goes flat, and the arms — which
-- hang full-length alongside the legs and are longer than the legs are — have to tuck: shoulders
-- rolled back and elbows shut so the forearm packs against the upper arm. Untucked they would be the
-- tallest thing on the body once it folded, which is exactly what the measurements said.
--
-- IT KEEPS WALKING THROUGHOUT. A stoop that stopped to fold, moved, then stopped to unfold would pin
-- the creature in the doorway it is clearing, and on the one enemy that can grab you that is the
-- difference between a stalker and a roadblock. So `fold` and `rise` are transitions the body travels
-- through, and `stoop` is a gait rather than a pose.
-- ============================================================

-- The folded pose every stoop keyframe is a variation on. Written once because `fold` has to end
-- exactly where `stoop` begins and `rise` has to begin exactly where `stoop` ends — three tracks
-- disagreeing about the folded pose by a few degrees is a visible pop at every doorway.
local STOOP = {
	chest = { rad(88), rad(3), 0 },
	neck = { rad(-10), 0, 0 },
	head = { rad(-10), rad(-8), 0 },
	shoulderL = { rad(-150), 0, rad(-16) },
	shoulderR = { rad(-150), 0, rad(16) },
	elbowL = { rad(110), 0, 0 },
	elbowR = { rad(110), 0, 0 },
	wristL = { rad(-30), 0, 0 },
	wristR = { rad(-30), 0, 0 },
	hipL = { rad(94), 0, rad(-8) },
	hipR = { rad(78), 0, rad(8) },
	kneeL = { rad(-114), 0, 0 },
	kneeR = { rad(-98), 0, 0 },
}

-- FOLDING DOWN. Fast — this happens at a doorway the player may be running for, and a slow fold is a
-- creature that gives up the chase. The head goes last and lowest: the silhouette collapsing from the
-- top down is what sells the height it is losing.
T.fold = EnemyKit.track({
	{ t = 0.00, pose = { shoulderL = FOLD.shoulderL, shoulderR = FOLD.shoulderR, elbowL = FOLD.elbowL, elbowR = FOLD.elbowR, wristL = FOLD.wristL, wristR = FOLD.wristR, chest = { rad(20), rad(3), 0 }, neck = { rad(12), 0, 0 }, head = { rad(4), rad(-6), 0 }, hipL = { rad(24), 0, 0 }, hipR = { rad(-24), 0, 0 }, kneeL = { rad(-30), 0, 0 }, kneeR = { rad(-6), 0, 0 } } },
	-- shoulders roll back and the elbows shut first, or the arms are still full-length when the body
	-- comes down on top of them
	{ t = 0.16, pose = { shoulderL = { rad(-120), 0, rad(-16) }, shoulderR = { rad(-120), 0, rad(16) }, elbowL = { rad(78), 0, 0 }, elbowR = { rad(78), 0, 0 }, wristL = { rad(-20), 0, 0 }, wristR = { rad(-20), 0, 0 }, chest = { rad(48), rad(3), 0 }, neck = { rad(4), 0, 0 }, head = { rad(-2), rad(-6), 0 }, hipL = { rad(52), 0, rad(-8) }, hipR = { rad(40), 0, rad(8) }, kneeL = { rad(-66), 0, 0 }, kneeR = { rad(-56), 0, 0 } }, ease = "outQuad" },
	{ t = 0.42, pose = STOOP, ease = "inOutCubic" },
})

-- THE STOOPED GAIT. The same slow stride as `move` — hips alternating, knees compensating — run
-- through a body that is folded in half. The pelvis rides a little up and down across the cycle;
-- STOOP_HEIGHT_RATIO below is measured from its WORST frame, not its average.
T.stoop = EnemyKit.track({
	{ t = 0.0, pose = STOOP, ease = "inOutQuad" },
	{ t = 0.8, pose = { chest = { rad(88), rad(-3), 0 }, head = { rad(-10), rad(8), 0 }, hipL = { rad(78), 0, rad(-8) }, hipR = { rad(94), 0, rad(8) }, kneeL = { rad(-98), 0, 0 }, kneeR = { rad(-114), 0, 0 } }, ease = "inOutQuad" },
	{ t = 1.6, pose = STOOP, ease = "inOutQuad" },
}, true)

-- COMING BACK UP, and deliberately slower than the fold with an overshoot at the top. A thing this
-- size unfolding into a room it now fits in is the second-best silhouette moment it has, and the only
-- one the player gets to watch from safety.
T.rise = EnemyKit.track({
	{ t = 0.00, pose = STOOP },
	{ t = 0.30, pose = { chest = { rad(34), rad(2), 0 }, neck = { rad(6), 0, 0 }, head = { rad(0), rad(-4), 0 }, shoulderL = { rad(-108), 0, rad(-12) }, shoulderR = { rad(-108), 0, rad(12) }, elbowL = { rad(56), 0, 0 }, elbowR = { rad(56), 0, 0 }, hipL = { rad(30), 0, rad(-4) }, hipR = { rad(22), 0, rad(4) }, kneeL = { rad(-44), 0, 0 }, kneeR = { rad(-36), 0, 0 } }, ease = "outQuad" },
	{ t = 0.54, pose = { chest = { rad(6), 0, 0 }, neck = { rad(14), 0, 0 }, head = { rad(10), 0, 0 }, shoulderL = FOLD.shoulderL, shoulderR = FOLD.shoulderR, elbowL = FOLD.elbowL, elbowR = FOLD.elbowR, wristL = FOLD.wristL, wristR = FOLD.wristR, hipL = { rad(-6), 0, 0 }, hipR = { rad(2), 0, 0 }, kneeL = { rad(-8), 0, 0 }, kneeR = { rad(-4), 0, 0 } }, ease = "outBack" },
	{ t = 0.72, pose = { chest = { rad(14), 0, 0 }, neck = { rad(10), 0, 0 }, head = { rad(6), rad(-10), 0 }, hipL = { rad(-4), 0, 0 }, hipR = { rad(4), 0, 0 }, kneeL = { 0, 0, 0 }, kneeR = { 0, 0, 0 } }, ease = "outCubic" },
})

-- THE REVEAL. Body rises, shoulders roll back, arms unfold. Biggest silhouette
-- change in the game and it must be legible from across a room.
-- THE REVEAL. Half of each limb detaches and rises. Biggest silhouette change
-- in the game and it must be legible from twenty studs.
T.reveal = EnemyKit.track({
	{ t = 0.00, pose = { shoulderL = FOLD.shoulderL, shoulderR = FOLD.shoulderR, elbowL = FOLD.elbowL, elbowR = FOLD.elbowR, wristL = FOLD.wristL, wristR = FOLD.wristR, chest = { rad(14), 0, 0 }, neck = { rad(10), 0, 0 }, head = { rad(6), 0, 0 }, jaw = { 0, 0, 0 } } },
	-- shoulders roll outward first, so the limbs visibly split before they lift
	{ t = 0.18, pose = { chest = { rad(22), 0, 0 }, neck = { rad(16), 0, 0 }, head = { rad(12), 0, 0 }, shoulderL = { rad(-76), rad(-10), rad(-26) }, shoulderR = { rad(-76), rad(10), rad(26) } }, ease = "outQuad" },
	{ t = 0.40, pose = { chest = { rad(-20), 0, 0 }, neck = { rad(-14), 0, 0 }, head = { rad(-18), 0, 0 }, jaw = { rad(-40), 0, 0 }, shoulderL = { rad(-32), rad(-22), rad(-30) }, shoulderR = { rad(-32), rad(22), rad(30) }, elbowL = { rad(52), 0, 0 }, elbowR = { rad(52), 0, 0 }, wristL = { rad(-10), 0, 0 }, wristR = { rad(-10), 0, 0 }, hipL = { rad(-10), 0, 0 }, hipR = { rad(-10), 0, 0 } }, ease = "outBack" },
	{ t = 0.58, pose = { chest = { rad(-13), 0, 0 }, neck = { rad(-9), 0, 0 }, head = { rad(-12), 0, 0 }, shoulderL = { rad(-38), rad(-18), rad(-24) }, shoulderR = { rad(-38), rad(18), rad(24) }, elbowL = { rad(44), 0, 0 }, elbowR = { rad(44), 0, 0 } }, ease = "outCubic" },
	{ t = 1.60, pose = {}, ease = "linear" },
}, true)

-- ============================================================
-- TWO ATTACKS, AND THE DISTANCE PICKS WHICH. They are separate animations because they are separate
-- answers to "how did that go", and a player has to be able to tell them apart on sight:
--
--   SLASH — the outer band, `reachGrab` to `reachMax` (6.0 to 9.0 studs). A horizontal whip across
--           the body at full extension. It costs wax and nothing else, and the arc is wide and
--           readable so that surviving one TEACHES the reach: it happens at a distance the player
--           believed was safe, and they get to watch the arm cover it.
--   STRIKE — inside `reachGrab`. A straight thrust, elbow shutting on contact, into `hold`. The
--           silhouette is the opposite of the slash: nothing crosses the body, everything goes
--           forward, and it ends with the player in the hand.
--
-- Both begin from the revealed rest pose so either can follow a reveal without a pop.
-- ============================================================

-- THE SLASH. It winds ACROSS the body first — the one frame of warning — and then comes back through
-- at full extension with the elbow straight, because a bent arm at this distance would not reach. The
-- follow-through carries past the target rather than stopping on it: a whip that halts where it hit
-- reads as a poke.
T.slash = EnemyKit.track({
	{ t = 0.00, pose = { shoulderL = { rad(-38), rad(-18), rad(-24) }, shoulderR = { rad(-38), rad(18), rad(24) }, elbowL = { rad(44), 0, 0 }, elbowR = { rad(44), 0, 0 }, wristL = { rad(-10), 0, 0 }, wristR = { rad(-10), 0, 0 }, chest = { rad(-13), 0, 0 }, head = { rad(-12), 0, 0 } } },
	-- wind across: the arm gathers on the far side of the body, shoulders and head turning with it
	{ t = 0.14, pose = { shoulderR = { rad(-30), rad(-52), rad(14) }, elbowR = { rad(30), 0, 0 }, wristR = { rad(-4), 0, 0 }, chest = { rad(-6), rad(-28), 0 }, neck = { rad(-6), rad(-10), 0 }, head = { rad(-8), rad(-20), 0 }, jaw = { rad(-18), 0, 0 } }, ease = "outQuad" },
	-- THROUGH. Elbow straight, arm level, sweeping the whole outer band in one frame.
	{ t = 0.30, pose = { shoulderR = { rad(-16), rad(44), rad(-8) }, elbowR = { rad(-2), 0, 0 }, wristR = { rad(-14), 0, 0 }, chest = { rad(-16), rad(30), 0 }, neck = { rad(-8), rad(12), 0 }, head = { rad(-14), rad(26), 0 }, jaw = { rad(-44), 0, 0 }, hipL = { rad(-8), 0, 0 }, hipR = { rad(8), 0, 0 } }, ease = "outQuart" },
	-- follow-through, and the body has to catch up with the arm
	{ t = 0.46, pose = { shoulderR = { rad(-22), rad(64), rad(-16) }, elbowR = { rad(12), 0, 0 }, chest = { rad(-10), rad(42), 0 }, neck = { rad(-4), rad(16), 0 }, head = { rad(-6), rad(34), 0 }, jaw = { rad(-24), 0, 0 } }, ease = "outCubic" },
	-- LANDS ON THE IDLE POSE, not on the revealed one. `slashSeconds` hands the body straight to `idle`
	-- and that track opens on the folded disguise, so anything else here is a frame where the arms jump
	-- from wherever the swing left them down to the legs. Ending the arc by re-folding also says the
	-- right thing: it took its swing and went back to being a tall shape in the dark.
	{ t = 0.62, pose = { shoulderL = FOLD.shoulderL, shoulderR = FOLD.shoulderR, elbowL = FOLD.elbowL, elbowR = FOLD.elbowR, wristL = FOLD.wristL, wristR = FOLD.wristR, chest = { rad(14), 0, 0 }, neck = { rad(10), 0, 0 }, head = { rad(6), rad(-10), 0 }, jaw = { 0, 0, 0 }, hipL = { rad(-4), 0, 0 }, hipR = { rad(4), 0, 0 } }, ease = "inOutCubic" },
	{ t = 1.30, pose = {}, ease = "linear" },
}, true)

-- THE THRUST, which is the grab. The right arm snaps to full extension: shoulder near horizontal,
-- elbow straight. All 8.4 studs of limb (3.36 authored, x BODY_SCALE) pointing at the player in one
-- frame, and the hand closes at the end of it.
T.strike = EnemyKit.track({
	{ t = 0.00, pose = { shoulderL = { rad(-38), rad(-18), rad(-24) }, shoulderR = { rad(-38), rad(18), rad(24) }, elbowL = { rad(44), 0, 0 }, elbowR = { rad(44), 0, 0 }, wristL = { rad(-10), 0, 0 }, wristR = { rad(-10), 0, 0 }, chest = { rad(-13), 0, 0 }, head = { rad(-12), 0, 0 } } },
	-- coil back, the only frame of warning
	{ t = 0.13, pose = { shoulderR = { rad(-58), rad(34), rad(30) }, elbowR = { rad(76), 0, 0 }, chest = { rad(-4), rad(-16), 0 }, head = { rad(-6), rad(-12), 0 }, jaw = { rad(-16), 0, 0 } }, ease = "outQuad" },
	{ t = 0.31, pose = { shoulderR = { rad(-4), rad(-4), rad(-2) }, elbowR = { rad(-2), 0, 0 }, wristR = { rad(-6), 0, 0 }, chest = { rad(-20), rad(10), 0 }, head = { rad(-20), rad(6), 0 }, jaw = { rad(-46), 0, 0 } }, ease = "outQuart" },
	{ t = 0.46, pose = { shoulderR = { rad(-8), 0, 0 }, elbowR = { rad(2), 0, 0 } }, ease = "outElastic" },
	{ t = 1.30, pose = {}, ease = "linear" },
}, true)

T.hold = EnemyKit.track({
	{ t = 0.00, pose = { shoulderR = { rad(-8), 0, 0 }, elbowR = { rad(2), 0, 0 }, jaw = { rad(-46), 0, 0 }, head = { rad(-20), 0, 0 }, shoulderL = { rad(-38), rad(-18), rad(-24) }, elbowL = { rad(44), 0, 0 }, chest = { rad(-13), 0, 0 } } },
	{ t = 0.32, pose = { shoulderR = { rad(-34), rad(4), 0 }, elbowR = { rad(66), 0, 0 }, chest = { rad(-6), 0, 0 }, head = { rad(-6), 0, 0 }, jaw = { rad(-72), 0, 0 } }, ease = "inQuart" },
	{ t = 0.72, pose = { shoulderR = { rad(-40), rad(8), 0 }, elbowR = { rad(76), 0, 0 }, head = { rad(2), rad(-8), 0 }, jaw = { rad(-30), 0, 0 } }, ease = "outQuad" },
	{ t = 1.06, pose = { head = { rad(-4), rad(8), 0 }, jaw = { rad(-76), 0, 0 } }, ease = "outQuart" },
	{ t = 1.40, pose = { shoulderR = { rad(-52), 0, 0 }, elbowR = { rad(88), 0, 0 }, jaw = { rad(-20), 0, 0 }, head = { rad(6), 0, 0 } }, ease = "inOutCubic" },
}, true)

-- Only a flare does this. Arms come up over the head, then it folds and reverses.
T.flee = EnemyKit.track({
	{ t = 0.00, pose = { chest = { rad(-13), 0, 0 }, head = { rad(-12), 0, 0 } } },
	{ t = 0.15, pose = { shoulderL = { rad(-146), rad(-14), rad(24) }, shoulderR = { rad(-146), rad(14), rad(-24) }, elbowL = { rad(92), 0, 0 }, elbowR = { rad(92), 0, 0 }, chest = { rad(30), 0, 0 }, neck = { rad(26), 0, 0 }, head = { rad(34), 0, 0 }, jaw = { rad(-30), 0, 0 } }, ease = "outQuart" },
	{ t = 0.52, pose = { chest = { rad(34), rad(14), 0 }, head = { rad(30), rad(-10), 0 }, hipL = { rad(-30), 0, 0 }, hipR = { rad(30), 0, 0 }, kneeL = { rad(-16), 0, 0 }, kneeR = { rad(-40), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.88, pose = { chest = { rad(34), rad(-14), 0 }, head = { rad(30), rad(10), 0 }, hipL = { rad(30), 0, 0 }, hipR = { rad(-30), 0, 0 }, kneeL = { rad(-40), 0, 0 }, kneeR = { rad(-16), 0, 0 } }, ease = "inOutQuad" },
	{ t = 1.24, pose = { chest = { rad(34), rad(14), 0 }, head = { rad(30), rad(-10), 0 }, hipL = { rad(-30), 0, 0 }, hipR = { rad(30), 0, 0 }, kneeL = { rad(-16), 0, 0 }, kneeR = { rad(-40), 0, 0 } }, ease = "inOutQuad" },
}, true)

T.hurt = EnemyKit.track({
	{ t = 0.00, pose = { chest = { rad(-14), 0, 0 } } },
	{ t = 0.08, pose = { chest = { rad(12), rad(14), 0 }, neck = { rad(-8), 0, 0 }, head = { rad(16), rad(-10), 0 }, jaw = { rad(-34), 0, 0 }, shoulderL = { rad(-40), rad(-20), rad(30) }, shoulderR = { rad(-40), rad(20), rad(-30) } }, ease = "outQuart" },
	{ t = 0.42, pose = { chest = { rad(-14), 0, 0 }, neck = { rad(-10), 0, 0 }, head = { rad(-12), 0, 0 }, jaw = { 0, 0, 0 } }, ease = "outElastic" },
})

-- Folds inward first, then the legs give. A tall thing collapsing vertically.
-- Folds inward, then the legs give. A tall thing collapsing vertically.
T.death = EnemyKit.track({
	{ t = 0.00, pose = { shoulderL = FOLD.shoulderL, shoulderR = FOLD.shoulderR, elbowL = FOLD.elbowL, elbowR = FOLD.elbowR, chest = { rad(-13), 0, 0 }, head = { rad(-12), 0, 0 } } },
	{ t = 0.17, pose = { chest = { rad(-34), 0, 0 }, neck = { rad(-26), 0, 0 }, head = { rad(-30), 0, 0 }, jaw = { rad(-56), 0, 0 }, shoulderL = { rad(-108), rad(-26), rad(-30) }, shoulderR = { rad(-108), rad(26), rad(30) }, elbowL = { rad(30), 0, 0 }, elbowR = { rad(30), 0, 0 } }, ease = "outQuart" },
	{ t = 0.58, pose = { chest = { rad(48), 0, rad(10) }, neck = { rad(40), 0, 0 }, head = { rad(46), rad(12), 0 }, shoulderL = { rad(-18), rad(-30), rad(-42) }, shoulderR = { rad(-18), rad(30), rad(42) }, elbowL = { rad(96), 0, 0 }, elbowR = { rad(96), 0, 0 }, hipL = { rad(70), 0, 0 }, hipR = { rad(64), 0, 0 }, kneeL = { rad(-96), 0, 0 }, kneeR = { rad(-90), 0, 0 } }, ease = "inQuart" },
	{ t = 0.90, pose = { chest = { rad(62), 0, rad(16) }, neck = { rad(56), 0, 0 }, head = { rad(60), rad(18), 0 }, jaw = { rad(-24), 0, 0 } }, ease = "outBounce" },
	{ t = 1.75, pose = { chest = { rad(60), 0, rad(15) }, head = { rad(58), rad(16), 0 }, jaw = { rad(-8), 0, 0 }, shoulderL = { rad(-14), rad(-26), rad(-38) }, shoulderR = { rad(-14), rad(26), rad(38) } }, ease = "outCubic" },
})

-- ============================================================
-- BUILD
-- ============================================================
function Longarm.build(variant: EnemyKit.Variant, seed: number?): (Model, any)
	local b = EnemyKit.begin("Longarm", variant, seed, BODY_SCALE)
	local J: { [string]: EnemyKit.Joint } = {}

	local pel = EnemyKit.block(b, "Pelvis", Vector3.new(0.62, 0.46, 0.44), "soft")

	local chest = EnemyKit.block(b, "Chest", Vector3.new(0.82, 0.72, 0.50), "soft")
	J.chest = EnemyKit.joint(pel, chest, CFrame.new(0, 0.68, -0.02))
	for i = 0, 2 do
		local rib = EnemyKit.block(b, "Rib", Vector3.new(0.62 - i * 0.07, 0.07, 0.09), "pale", false)
		EnemyKit.joint(chest, rib, CFrame.new(0, 0.20 - i * 0.18, -0.26) * CFrame.Angles(rad(-4 + i * 4), 0, 0))
	end
	EnemyKit.anchor(b, chest, CFrame.new(0, 0.30, 0.20), 0.30)

	local neck = EnemyKit.block(b, "Neck", Vector3.new(0.20, 0.32, 0.20), "soft")
	J.neck = EnemyKit.joint(chest, neck, CFrame.new(0, 0.46, 0))

	local head = EnemyKit.block(b, "Head", Vector3.new(0.38, 0.46, 0.46), "soft")
	J.head = EnemyKit.joint(neck, head, CFrame.new(0, 0.30, -0.02))
	local brow = EnemyKit.block(b, "Brow", Vector3.new(0.36, 0.10, 0.16), "soft", false)
	EnemyKit.joint(head, brow, CFrame.new(0, 0.16, -0.20) * CFrame.Angles(rad(18), 0, 0))
	EnemyKit.anchor(b, head, CFrame.new(0, 0.22, 0.16), 0.22)

	local jaw = EnemyKit.block(b, "Jaw", Vector3.new(0.30, 0.18, 0.34), "soft")
	J.jaw = EnemyKit.joint(head, jaw, CFrame.new(0, -0.21, -0.06), CFrame.new(0, 0.06, -0.10))
	for i = 0, 3 do
		local x = (i - 1.5) * 0.07
		local tu = EnemyKit.block(b, "Tooth", Vector3.new(0.04, 0.12, 0.04), "tooth", false)
		EnemyKit.joint(jaw, tu, CFrame.new(x, 0.10, -0.16))
		local td = EnemyKit.block(b, "Tooth", Vector3.new(0.04, 0.12, 0.04), "tooth", false)
		EnemyKit.joint(head, td, CFrame.new(x, -0.20, -0.18))
	end
	-- Eyes are deep-set and dim. It should be hard to tell it is looking at you.
	for _, side in { -1, 1 } do
		local sock = EnemyKit.blob(b, "Socket", Vector3.new(0.19, 0.20, 0.17), "chit", false)
		EnemyKit.joint(head, sock, CFrame.new(side * 0.11, 0.03, -0.17))
		local e = EnemyKit.neon(b, "Eye", Vector3.one * 0.075, "eye", 0.25)
		EnemyKit.joint(head, e, CFrame.new(side * 0.11, 0.03, -0.22))
	end

	-- Arms sit just outboard of and slightly behind the legs, at x 0.26 against
	-- the leg's 0.20, running their full length. Base joints carry position
	-- only; the rest pose is FOLD in the animation tracks.
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local upper = EnemyKit.block(b, "Upper", Vector3.new(0.17, 0.17, 1.62), "chit")
		J["shoulder" .. tag] = EnemyKit.joint(chest, upper, CFrame.new(side * 0.26, 0.10, 0.16) * CFrame.Angles(0, rad(side * 4), 0), CFrame.new(0, 0, 0.81))
		local fore = EnemyKit.block(b, "Fore", Vector3.new(0.13, 0.13, 1.74), "chit")
		J["elbow" .. tag] = EnemyKit.joint(upper, fore, CFrame.new(0, 0, -0.81), CFrame.new(0, 0, 0.87))
		local hand = EnemyKit.block(b, "Hand", Vector3.new(0.20, 0.08, 0.30), "chit", false)
		J["wrist" .. tag] = EnemyKit.joint(fore, hand, CFrame.new(0, 0, -0.87), CFrame.new(0, 0, 0.15))
		for f = 0, 3 do
			local len = 0.46 - math.abs(f - 1.5) * 0.06
			local fin = EnemyKit.block(b, "Finger", Vector3.new(0.042, 0.042, len), "chit", false)
			EnemyKit.joint(hand, fin, CFrame.new((f - 1.5) * 0.06, 0, -0.15) * CFrame.Angles(rad(8), rad((f - 1.5) * 9), 0), CFrame.new(0, 0, len / 2))
		end
		EnemyKit.anchor(b, upper, CFrame.new(0, 0.08, 0.4), 0.20)
	end

	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local thigh = EnemyKit.block(b, "Thigh", Vector3.new(0.20, 0.20, 1.24), "chit")
		J["hip" .. tag] = EnemyKit.joint(pel, thigh, CFrame.new(side * 0.20, -0.20, 0) * CFrame.Angles(0, rad(side * 4), 0) * CFrame.Angles(rad(-84), 0, 0), CFrame.new(0, 0, 0.62))
		local shin = EnemyKit.block(b, "Shin", Vector3.new(0.155, 0.155, 1.22), "chit")
		J["knee" .. tag] = EnemyKit.joint(thigh, shin, CFrame.new(0, 0, -0.62) * CFrame.Angles(rad(-6), 0, 0), CFrame.new(0, 0, 0.61))
		local foot = EnemyKit.block(b, "Foot", Vector3.new(0.24, 0.13, 0.56), "chit", false)
		EnemyKit.joint(shin, foot, CFrame.new(0, 0, -0.61) * CFrame.Angles(rad(92), 0, 0), CFrame.new(0, 0.05, 0.20))
	end

	-- Authored dimensions like everything above: `finish` multiplies both volumes AND their weld
	-- offsets by BODY_SCALE, so detection and physics grow with the silhouette rather than staying a
	-- third-size box in the middle of it.
	EnemyKit.hitbox(b, pel, Vector3.new(1.2, 3.4, 1.1), CFrame.new(0, 1.1, 0))
	EnemyKit.collider(b, pel, Vector3.new(1.0, 2.8, 0.9), CFrame.new(0, 0.9, 0))

	local model = EnemyKit.finish(b, pel, "Longarm", 3)
	return model, { root = pel, joints = J, chest = chest, head = head }
end

-- ============================================================
-- CONTROLLER
-- ============================================================
export type Long = typeof(setmetatable({} :: any, Longarm))

function Longarm.new(cframe: CFrame, variant: EnemyKit.Variant?, seed: number?): Long
	local v = variant or "regular"
	local model, rig = Longarm.build(v, seed)
	model:PivotTo(cframe)

	local stats = EnemyKit.VariantStats[v]
	local elder = model:GetAttribute("Elder")
	local hp = Longarm.Config.health * stats.health * (if elder then EnemyKit.ElderStats.health else 1)

	return setmetatable({
		model = model,
		root = rig.root,
		joints = rig.joints,
		hitbox = model:FindFirstChild("Hitbox"),
		variant = v,
		health = hp,
		maxHealth = hp,
		speed = Longarm.Config.speed * stats.speed,
		state = "idle",
		t = 0,
		stateT = 0,
		ignoreUntil = 0,
		fleeUntil = 0,
		victim = nil,
		decoy = nil,
		sounds = {
			creep = EnemyKit.emitter(rig.root, SOUNDS.creep, "Creep", true, 0.22, 4, 26),
			reveal = EnemyKit.emitter(rig.root, SOUNDS.reveal, "Reveal", false, 0.8, 10, 60),
			snap = EnemyKit.emitter(rig.root, SOUNDS.snap, "Snap", false, 1, 12, 70),
			grab = EnemyKit.emitter(rig.root, SOUNDS.grab, "Grab", false, 0.9, 6, 40),
			scream = EnemyKit.emitter(rig.root, SOUNDS.scream, "Scream", false, 1, 14, 90),
			flee = EnemyKit.emitter(rig.root, SOUNDS.flee, "Flee", false, 0.7, 10, 60),
			death = EnemyKit.emitter(rig.root, SOUNDS.death, "Death", false, 0.85, 10, 70),
		},
	}, Longarm)
end

function Longarm.setState(self: Long, state: string)
	if self.state == state or self.state == "death" then
		return
	end
	self.state = state
	self.stateT = 0
	self.model:SetAttribute("State", state)

	if self.sounds.creep then
		-- Folding, stooping and rising are all locomotion: the body is travelling through every one of
		-- them, so the creep runs through them exactly as it does through `move`.
		if state == "move" or state == "fold" or state == "stoop" or state == "rise" then
			self.sounds.creep:Play()
		else
			self.sounds.creep:Stop()
		end
	end
	if state == "reveal" and self.sounds.reveal then
		self.sounds.reveal:Play()
	elseif (state == "strike" or state == "slash") and self.sounds.snap then
		-- Both attacks extend the arm and both crack; the integration layer gives them separate cues
		-- (LongarmSnap and LongarmSlash), and this bare emitter has only the one.
		self.sounds.snap:Play()
	elseif state == "hold" then
		if self.sounds.grab then
			self.sounds.grab:Play()
		end
		if self.sounds.scream then
			self.sounds.scream:Play()
		end
	elseif state == "flee" and self.sounds.flee then
		self.sounds.flee:Play()
	elseif state == "death" then
		if self.sounds.creep then
			self.sounds.creep:Stop()
		end
		if self.sounds.death then
			self.sounds.death:Play()
		end
	end
end

-- The only thing that scares it. Nothing else works, by design.
function Longarm.setIllumination(self: Long, brightness: number)
	if self.state == "death" then
		return
	end
	if brightness >= Longarm.Config.flareThreshold then
		self:release()
		self.fleeUntil = self.t + Longarm.Config.fleeSeconds
		self:setState("flee")
	end
end

-- Decoy candles pull it away. It grabs and destroys them, which buys the party
-- a window — the only proactive tool the player has against it.
function Longarm.setDecoy(self: Long, decoyPart: BasePart?)
	if self.state == "flee" or self.state == "death" then
		return
	end
	self.decoy = decoyPart
end

function Longarm.consumeDecoy(self: Long)
	if self.decoy then
		self.decoy:Destroy()
		self.decoy = nil
	end
	self.ignoreUntil = self.t + Longarm.Config.ignoreSeconds * 0.5
end

-- DISTANCE DECIDES WHICH ATTACK, and the animation is chosen here rather than by the caller: the
-- outer band gets the slash and the inner band gets the thrust, so the pose the player sees always
-- matches the thing that just happened to them. `distance` is measured FLAT — see the note on
-- `nearestPlayer` in LongarmBehavior — because these bands are arm lengths, and a creature whose
-- pelvis is seven studs up would otherwise lose more than a stud of its reach to the height
-- difference alone.
function Longarm.attackAt(self: Long, distance: number): string
	if self.state ~= "reveal" and self.state ~= "idle" and self.state ~= "move" then
		return "none"
	end
	if distance > Longarm.Config.reachMax then
		return "none"
	end
	if distance <= Longarm.Config.reachGrab then
		self:setState("strike")
		return "grab"
	end
	self:setState("slash")
	return "graze"
end

function Longarm.grab(self: Long, victim: Model)
	self.victim = victim
	self:setState("hold")
	self.model:SetAttribute("HoldingVictim", true)
end

function Longarm.release(self: Long)
	if not self.victim then
		return
	end
	self.victim = nil
	self.model:SetAttribute("HoldingVictim", false)
	self.ignoreUntil = self.t + Longarm.Config.ignoreSeconds
	self:setState("idle")
end

function Longarm.isIgnoring(self: Long): boolean
	return self.t < self.ignoreUntil
end

-- Folded, folding, or on its way back up — i.e. anywhere in the stoop, and therefore not standing at
-- its full height. The controller drives the stoop but the body owns which states are part of it.
function Longarm.isStooping(self: Long): boolean
	return self.state == "fold" or self.state == "stoop" or self.state == "rise"
end

function Longarm.damage(self: Long, amount: number)
	if self.state == "death" then
		return
	end
	self.health -= amount
	if self.health <= 0 then
		self:release()
		self:setState("death")
	elseif self.state ~= "hold" and self.state ~= "strike" then
		self:setState("hurt")
	end
end

function Longarm.step(self: Long, dt: number)
	self.t += dt
	self.stateT += dt

	if self.state == "reveal" and self.stateT >= Longarm.Config.revealSeconds then
		-- Held revealed; the controller decides whether to strike.
	elseif self.state == "strike" and self.stateT >= Longarm.Config.extendSeconds and not self.victim then
		self:setState("idle")
	elseif self.state == "slash" and self.stateT >= Longarm.Config.slashSeconds then
		-- A slash never holds anything, so unlike the thrust there is no victim to wait on: the arc
		-- finishes, the arm comes back to the revealed rest, and the creature is choosing again.
		self:setState("idle")
	elseif self.state == "hold" and self.stateT >= Longarm.Config.holdSeconds then
		self:release()
	elseif self.state == "flee" and self.t >= self.fleeUntil then
		self:setState("idle")
	elseif self.state == "hurt" and self.stateT > 0.42 then
		self:setState("idle")
	elseif self.state == "fold" and self.stateT >= Longarm.Config.foldSeconds then
		-- Folded. From here it is a walking silhouette barely half its own height, and it holds that
		-- until the controller — which is the only thing that can see the rock overhead — says otherwise.
		self:setState("stoop")
	elseif self.state == "rise" and self.stateT >= Longarm.Config.riseSeconds then
		self:setState("move")
	end

	local track = T[self.state] or T.idle
	EnemyKit.evaluate(self.joints, track, self.stateT)

	if self.state ~= "death" then
		EnemyKit.breathe(self.joints.chest, self.t, 0.9, 0.018)
	end
end

function Longarm.destroy(self: Long)
	self.model:Destroy()
end

return Longarm

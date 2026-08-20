--!strict
-- StoneGnawer — tier 3 blind charger. Lethal Company dog structurally.
-- Place at: ReplicatedStorage/Enemies/StoneGnawer
--
-- EYELESS BY DESIGN. It hunts by sound, so giving it eyes would tell players
-- the wrong thing about how to beat it. The sensory frills where eyes would be
-- are the read: they flare when it is listening.
--
-- The player cannot attack, so this is not a fight — the entire encounter is
-- "hear it eating, do not make noise, and if it charges, move sideways". It
-- charges in a straight line and cannot turn, which is the whole counter.
--
-- Three audio cues carry it and all three must exist:
--   1. EAT loop, audible from ~45 studs. This is how you know the room is bad.
--   2. LISTEN chirp when it stops eating. This is your last quiet moment.
--   3. CHARGE_WARN, 1.1s, foreleg scrape. This is the dodge cue.

local EnemyKit = require(script.Parent.EnemyKit)

local StoneGnawer = {}
StoneGnawer.__index = StoneGnawer

StoneGnawer.Config = {
	health = 140,
	walkSpeed = 6,
	chargeSpeed = 26,
	-- Fraction of this game's `Config.Wax.maxWax` (1.3), not the pack's original raw units — see
	-- Config/StoneGnawer.luau header. Kept numerically in sync with that file, which is what
	-- integration actually reads at runtime.
	chargeDamage = 0.75,
	-- It cannot turn once committed. Sidestep distance the player needs.
	chargeLockSeconds = 1.6,
	staggerSeconds = 2.0,
	-- Noise radii. Standing still is genuinely invisible to it.
	hearSprint = 42,
	hearWalk = 16,
	-- HOW LONG IT MAY SPEND TURNING BEFORE THE WIND-UP STARTS, at most: the host ends the aim as soon
	-- as the body is actually pointed at the target (StoneGnawerBehavior), and this is only the ceiling
	-- for a creature that cannot get there — cornered, or turning through 180 degrees. Without a
	-- ceiling a Gnawer that could never quite line up would aim forever and never charge at all.
	aimMaxSeconds = 1.15,
	warnSeconds = 1.1,
	-- How fast it may swing its aim during the wind-up. 150 deg/s comfortably tracks a walking player
	-- and loses to a committed lateral sprint, so "keep moving sideways" stays the counter to the
	-- telegraph and "sidestep the lane" stays the counter to the charge itself.
	warnTurnDegreesPerSecond = 150,
}

local SOUNDS = { eat = "", listen = "", warn = "", charge = "", impact = "", death = "" }
local rad = math.rad

-- HALF AGAIN THE AUTHORED SIZE. Owner decision: at its drawn dimensions this reads as a large dog in
-- a cave built for a creature that outweighs you, and the encounter is supposed to be something you
-- get out of the way of rather than something you could shoulder past. Applied in `finish`, which
-- multiplies part volumes, joint offsets, rest poses AND the hitbox/collider welds together — so the
-- anatomy and every animation below stay exactly as authored and only the finished body changes.
--
-- NOTHING DOWNSTREAM NEEDS A MATCHING EDIT, by design: the brain's charge reach and body radius are
-- measured off the built model (StoneGnawerBehavior.new), and so are the Humanoid's ride height and
-- agent size (EnemyMover.attach). Its gameplay numbers — speed, hearing, damage — are deliberately
-- not size-derived and do not move with this.
local BODY_SCALE = 1.5

-- ============================================================
-- ANIMATION
-- ============================================================
local T = {}

-- Head down, jaw grinding. Rhythmic and audible — this is the state players
-- should learn to hear from another room.
T.eat = EnemyKit.track({
	{ t = 0.0, pose = { neck = { rad(34), 0, 0 }, head = { rad(14), rad(4), 0 }, jaw = { rad(-6), 0, 0 }, frillL = { 0, rad(-6), rad(10) }, frillR = { 0, rad(6), rad(-10) }, spine = { rad(4), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.34, pose = { neck = { rad(40), rad(-3), 0 }, head = { rad(18), rad(-3), 0 }, jaw = { rad(-30), 0, 0 } }, ease = "outQuad" },
	{ t = 0.58, pose = { neck = { rad(36), rad(2), 0 }, head = { rad(15), rad(3), 0 }, jaw = { rad(-4), 0, 0 } }, ease = "inQuad" },
	{ t = 0.92, pose = { neck = { rad(40), rad(3), 0 }, head = { rad(18), rad(2), 0 }, jaw = { rad(-26), 0, 0 } }, ease = "outQuad" },
	{ t = 1.20, pose = { neck = { rad(34), 0, 0 }, head = { rad(14), rad(4), 0 }, jaw = { rad(-6), 0, 0 } }, ease = "inQuad" },
}, true)

-- Head snaps up, frills flare, body freezes. The stillness is the tell.
T.listen = EnemyKit.track({
	{ t = 0.00, pose = { neck = { rad(34), 0, 0 }, head = { rad(14), 0, 0 }, jaw = { rad(-6), 0, 0 } } },
	{ t = 0.16, pose = { neck = { rad(-16), 0, 0 }, head = { rad(-8), 0, 0 }, jaw = { 0, 0, 0 }, frillL = { 0, rad(-30), rad(38) }, frillR = { 0, rad(30), rad(-38) }, spine = { rad(-4), 0, 0 } }, ease = "outQuart" },
	{ t = 1.10, pose = { neck = { rad(-14), rad(26), 0 }, head = { rad(-6), rad(16), 0 } }, ease = "inOutCubic" },
	{ t = 2.10, pose = { neck = { rad(-14), rad(-26), 0 }, head = { rad(-6), rad(-16), 0 } }, ease = "inOutCubic" },
	{ t = 3.00, pose = { neck = { rad(-16), 0, 0 }, head = { rad(-8), 0, 0 } }, ease = "inOutCubic" },
}, true)

T.move = EnemyKit.track({
	{ t = 0.00, pose = { spine = { rad(2), rad(3), 0 }, neck = { rad(6), rad(4), 0 }, head = { rad(3), rad(-3), 0 }, legFL = { rad(20), 0, 0 }, legFR = { rad(-20), 0, 0 }, legBL = { rad(-18), 0, 0 }, legBR = { rad(18), 0, 0 }, kneeFL = { rad(-26), 0, 0 }, kneeFR = { rad(6), 0, 0 }, kneeBL = { rad(6), 0, 0 }, kneeBR = { rad(-24), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.30, pose = { spine = { rad(-2), rad(-3), 0 }, neck = { rad(6), rad(-4), 0 }, head = { rad(3), rad(3), 0 }, legFL = { rad(-20), 0, 0 }, legFR = { rad(20), 0, 0 }, legBL = { rad(18), 0, 0 }, legBR = { rad(-18), 0, 0 }, kneeFL = { rad(6), 0, 0 }, kneeFR = { rad(-26), 0, 0 }, kneeBL = { rad(-24), 0, 0 }, kneeBR = { rad(6), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.60, pose = { spine = { rad(2), rad(3), 0 }, neck = { rad(6), rad(4), 0 }, head = { rad(3), rad(-3), 0 }, legFL = { rad(20), 0, 0 }, legFR = { rad(-20), 0, 0 }, legBL = { rad(-18), 0, 0 }, legBR = { rad(18), 0, 0 }, kneeFL = { rad(-26), 0, 0 }, kneeFR = { rad(6), 0, 0 }, kneeBL = { rad(6), 0, 0 }, kneeBR = { rad(-24), 0, 0 } }, ease = "inOutQuad" },
}, true)

-- HUNTING. The walk cycle carrying a listening head, and that combination is the whole read: this is
-- the creature travelling to something it heard from another room rather than grazing its way around
-- its own.
--
-- IT IS DELIBERATELY THE `move` GAIT AND THE `listen` HEAD, not a third silhouette. A player has
-- already learned that head-down-and-chewing is safe and head-up-with-frills-flared is not; a hunting
-- Gnawer is the second of those, walking. Inventing a new posture would throw away the vocabulary the
-- eat and listen states spent the whole run teaching.
--
-- The head sweeps side to side across the cycle at half the speed of the legs, so the two rhythms do
-- not lock — it should look like it is casting for the sound again, not marching to a known point.
T.hunt = EnemyKit.track({
	{ t = 0.00, pose = { spine = { rad(-2), rad(3), 0 }, neck = { rad(-14), rad(-18), 0 }, head = { rad(-6), rad(-12), 0 }, jaw = { 0, 0, 0 }, frillL = { 0, rad(-24), rad(30) }, frillR = { 0, rad(24), rad(-30) }, legFL = { rad(20), 0, 0 }, legFR = { rad(-20), 0, 0 }, legBL = { rad(-18), 0, 0 }, legBR = { rad(18), 0, 0 }, kneeFL = { rad(-26), 0, 0 }, kneeFR = { rad(6), 0, 0 }, kneeBL = { rad(6), 0, 0 }, kneeBR = { rad(-24), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.30, pose = { spine = { rad(-2), rad(-3), 0 }, neck = { rad(-15), rad(-4), 0 }, head = { rad(-6), rad(-2), 0 }, legFL = { rad(-20), 0, 0 }, legFR = { rad(20), 0, 0 }, legBL = { rad(18), 0, 0 }, legBR = { rad(-18), 0, 0 }, kneeFL = { rad(6), 0, 0 }, kneeFR = { rad(-26), 0, 0 }, kneeBL = { rad(-24), 0, 0 }, kneeBR = { rad(6), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.60, pose = { spine = { rad(-2), rad(3), 0 }, neck = { rad(-14), rad(14), 0 }, head = { rad(-6), rad(10), 0 }, legFL = { rad(20), 0, 0 }, legFR = { rad(-20), 0, 0 }, legBL = { rad(-18), 0, 0 }, legBR = { rad(18), 0, 0 }, kneeFL = { rad(-26), 0, 0 }, kneeFR = { rad(6), 0, 0 }, kneeBL = { rad(6), 0, 0 }, kneeBR = { rad(-24), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.90, pose = { spine = { rad(-2), rad(-3), 0 }, neck = { rad(-15), rad(20), 0 }, head = { rad(-6), rad(14), 0 }, legFL = { rad(-20), 0, 0 }, legFR = { rad(20), 0, 0 }, legBL = { rad(18), 0, 0 }, legBR = { rad(-18), 0, 0 }, kneeFL = { rad(6), 0, 0 }, kneeFR = { rad(-26), 0, 0 }, kneeBL = { rad(-24), 0, 0 }, kneeBR = { rad(6), 0, 0 } }, ease = "inOutQuad" },
	{ t = 1.20, pose = { spine = { rad(-2), rad(3), 0 }, neck = { rad(-14), rad(-18), 0 }, head = { rad(-6), rad(-12), 0 }, legFL = { rad(20), 0, 0 }, legFR = { rad(-20), 0, 0 }, legBL = { rad(-18), 0, 0 }, legBR = { rad(18), 0, 0 }, kneeFL = { rad(-26), 0, 0 }, kneeFR = { rad(6), 0, 0 }, kneeBL = { rad(6), 0, 0 }, kneeBR = { rad(-24), 0, 0 } }, ease = "inOutQuad" },
}, true)

-- AIMING. The beat before the warning: it has decided on a target and is bringing its whole body
-- round to face it, and it does not start the wind-up until it has.
--
-- THIS EXISTS BECAUSE THE TURN USED TO HAPPEN INSIDE THE WARNING. `beginCharge` set `warn` in the
-- same call that set the heading, so the 1.1 seconds of telegraph were spent rotating — and a body
-- this size does not rotate in 1.1 seconds. A player behind it saw the creature stand, do its plant
-- and scrape while still pointed the wrong way, snap round, and leave. The dodge cue was therefore
-- aimed at nobody for most of its length, which is the opposite of what a telegraph is for.
--
-- The order is now: turn (this), warn (plant and coil, pointed at you the whole time), charge.
--
-- IT IS A SHUFFLE, NOT A POSE. Small alternating foreleg steps with the head locked forward, so the
-- creature reads as pivoting rather than sliding — the Humanoid is doing the actual rotation
-- (server/EnemySystem/EnemyMover.setFacing) and this is what makes that rotation look driven.
T.aim = EnemyKit.track({
	{ t = 0.00, pose = { spine = { rad(-4), rad(3), 0 }, neck = { rad(-18), 0, 0 }, head = { rad(-10), 0, 0 }, jaw = { 0, 0, 0 }, frillL = { 0, rad(-32), rad(40) }, frillR = { 0, rad(32), rad(-40) }, legFL = { rad(14), 0, 0 }, legFR = { rad(-10), 0, 0 }, legBL = { rad(-8), 0, 0 }, legBR = { rad(12), 0, 0 }, kneeFL = { rad(-16), 0, 0 }, kneeFR = { rad(8), 0, 0 } }, ease = "outQuad" },
	{ t = 0.26, pose = { spine = { rad(-5), rad(-3), 0 }, neck = { rad(-19), 0, 0 }, legFL = { rad(-12), 0, 0 }, legFR = { rad(16), 0, 0 }, legBL = { rad(10), 0, 0 }, legBR = { rad(-8), 0, 0 }, kneeFL = { rad(8), 0, 0 }, kneeFR = { rad(-18), 0, 0 } }, ease = "inOutQuad" },
	{ t = 0.52, pose = { spine = { rad(-4), rad(3), 0 }, neck = { rad(-18), 0, 0 }, legFL = { rad(14), 0, 0 }, legFR = { rad(-10), 0, 0 }, legBL = { rad(-8), 0, 0 }, legBR = { rad(12), 0, 0 }, kneeFL = { rad(-16), 0, 0 }, kneeFR = { rad(8), 0, 0 } }, ease = "inOutQuad" },
}, true)

-- Plant, coil, scrape. Long and unmistakable — this is the only warning and
-- must survive Bluetooth latency, so nothing under 450ms.
--
-- IT NO LONGER TURNS DURING THIS. `T.aim` above brings the body round first; by the time this track
-- starts the creature is already pointed at whoever it is about to run down, so all 1.1 seconds of
-- the dodge cue are aimed at them.
T.warn = EnemyKit.track({
	{ t = 0.00, pose = { spine = { 0, 0, 0 }, neck = { rad(-16), 0, 0 }, head = { rad(-8), 0, 0 }, jaw = { 0, 0, 0 } } },
	{ t = 0.30, pose = { spine = { rad(-8), 0, 0 }, neck = { rad(-26), 0, 0 }, head = { rad(-14), 0, 0 }, frillL = { 0, rad(-34), rad(44) }, frillR = { 0, rad(34), rad(-44) }, legFL = { rad(-34), 0, 0 }, kneeFL = { rad(46), 0, 0 } }, ease = "outCubic" },
	{ t = 0.68, pose = { spine = { rad(-10), 0, 0 }, neck = { rad(-20), 0, 0 }, legFL = { rad(26), 0, 0 }, kneeFL = { rad(-14), 0, 0 }, jaw = { rad(-34), 0, 0 } }, ease = "inQuart" },
	{ t = 0.90, pose = { spine = { rad(-12), 0, 0 }, legFL = { rad(-30), 0, 0 }, kneeFL = { rad(40), 0, 0 } }, ease = "outQuad" },
	{ t = 1.10, pose = { spine = { rad(-14), 0, 0 }, neck = { rad(10), 0, 0 }, head = { rad(16), 0, 0 }, jaw = { rad(-40), 0, 0 }, legFL = { rad(-38), 0, 0 } }, ease = "inQuad" },
})

-- A BOUND, NOT A TROT. The old cycle moved the legs in diagonal pairs with the spine bobbing eight
-- degrees — a gait, and gaits read as travel. This one is four beats of a rotary gallop: gather,
-- suspension, forelegs SLAM, hindquarters drive. Both forelegs strike together and the spine flexes
-- through 38 degrees between coiled and extended, which is what makes a body read as thrown at
-- something rather than carried toward it.
--
-- THE SILHOUETTE HAS TO SURVIVE THE DARK. This is the only creature you are meant to react to with no
-- time to look at it, in a game lit by one candle, so the read is carried by the biggest shapes on the
-- body: the whole trunk pitching and rolling, the head driving low and forward, and the jaw held open
-- for the entire cycle rather than flapping. Detail work on the frills and tail would be invisible at
-- the distance this matters from — they are pinned back and whipping, and that is all they do.
--
-- SWINGING THE LEGS HARDER CANNOT SINK THE BODY. Each leg is a pendulum from its hip, so a larger
-- angle lifts the foot rather than dropping it; the rest pose stays the lowest the feet ever go, which
-- is the pose `EnemyMover` measured the ride height from.
T.charge = EnemyKit.track({
	-- GATHER. Coiled under itself, hind legs planted forward, head low and driving.
	{ t = 0.00, pose = { spine = { rad(-18), 0, rad(4) }, neck = { rad(22), 0, 0 }, head = { rad(26), 0, 0 }, jaw = { rad(-46), 0, 0 }, tail = { rad(-14), rad(18), 0 }, frillL = { 0, rad(-34), rad(46) }, frillR = { 0, rad(34), rad(-46) }, legFL = { rad(-30), 0, 0 }, legFR = { rad(-34), 0, 0 }, legBL = { rad(44), 0, 0 }, legBR = { rad(40), 0, 0 }, kneeFL = { rad(52), 0, 0 }, kneeFR = { rad(56), 0, 0 }, kneeBL = { rad(-40), 0, 0 }, kneeBR = { rad(-36), 0, 0 } }, ease = "inQuad" },
	-- SUSPENSION. Everything thrown open — forelegs reaching, hind legs trailing, trunk extended.
	{ t = 0.08, pose = { spine = { rad(16), 0, rad(-3) }, neck = { rad(10), 0, 0 }, head = { rad(14), 0, 0 }, tail = { rad(-22), rad(-16), 0 }, legFL = { rad(-58), 0, 0 }, legFR = { rad(-54), 0, 0 }, legBL = { rad(-46), 0, 0 }, legBR = { rad(-42), 0, 0 }, kneeFL = { rad(8), 0, 0 }, kneeFR = { rad(12), 0, 0 }, kneeBL = { rad(6), 0, 0 }, kneeBR = { rad(10), 0, 0 } }, ease = "outQuart" },
	-- FORELEG STRIKE. Both front feet hit at once and the whole front end jolts down over them.
	{ t = 0.15, pose = { spine = { rad(20), 0, rad(7) }, neck = { rad(26), 0, 0 }, head = { rad(32), 0, 0 }, jaw = { rad(-22), 0, 0 }, tail = { rad(6), rad(20), 0 }, legFL = { rad(50), 0, 0 }, legFR = { rad(46), 0, 0 }, legBL = { rad(-34), 0, 0 }, legBR = { rad(-30), 0, 0 }, kneeFL = { rad(-58), 0, 0 }, kneeFR = { rad(-54), 0, 0 }, kneeBL = { rad(10), 0, 0 }, kneeBR = { rad(14), 0, 0 } }, ease = "outQuart" },
	-- DRIVE. Hind legs swing under and shove, jaw opens again for the next bound.
	{ t = 0.22, pose = { spine = { rad(-6), 0, rad(-7) }, neck = { rad(18), 0, 0 }, head = { rad(22), 0, 0 }, jaw = { rad(-48), 0, 0 }, tail = { rad(-4), rad(-22), 0 }, legFL = { rad(20), 0, 0 }, legFR = { rad(24), 0, 0 }, legBL = { rad(52), 0, 0 }, legBR = { rad(48), 0, 0 }, kneeFL = { rad(-20), 0, 0 }, kneeFR = { rad(-24), 0, 0 }, kneeBL = { rad(-52), 0, 0 }, kneeBR = { rad(-48), 0, 0 } }, ease = "inQuart" },
	{ t = 0.30, pose = { spine = { rad(-18), 0, rad(4) }, neck = { rad(22), 0, 0 }, head = { rad(26), 0, 0 }, jaw = { rad(-46), 0, 0 }, tail = { rad(-14), rad(18), 0 }, legFL = { rad(-30), 0, 0 }, legFR = { rad(-34), 0, 0 }, legBL = { rad(44), 0, 0 }, legBR = { rad(40), 0, 0 }, kneeFL = { rad(52), 0, 0 }, kneeFR = { rad(56), 0, 0 }, kneeBL = { rad(-40), 0, 0 }, kneeBR = { rad(-36), 0, 0 } }, ease = "inQuad" },
}, true)

-- It hit a wall. Recoil, shake it off, recover. This is the player's window.
T.stagger = EnemyKit.track({
	{ t = 0.00, pose = { spine = { rad(8), 0, 0 }, neck = { rad(16), 0, 0 }, head = { rad(20), 0, 0 } } },
	{ t = 0.12, pose = { spine = { rad(-22), 0, rad(10) }, neck = { rad(34), 0, 0 }, head = { rad(30), 0, 0 }, jaw = { rad(-44), 0, 0 }, legFL = { rad(-44), 0, 0 }, legFR = { rad(-40), 0, 0 }, kneeFL = { rad(52), 0, 0 }, kneeFR = { rad(48), 0, 0 } }, ease = "outQuart" },
	{ t = 0.60, pose = { spine = { rad(6), 0, rad(-6) }, neck = { rad(20), rad(18), 0 }, head = { rad(12), rad(-14), 0 } }, ease = "inOutCubic" },
	{ t = 1.10, pose = { spine = { rad(2), 0, rad(6) }, neck = { rad(14), rad(-18), 0 }, head = { rad(8), rad(14), 0 } }, ease = "inOutCubic" },
	{ t = 2.00, pose = { spine = { 0, 0, 0 }, neck = { rad(-16), 0, 0 }, head = { rad(-8), 0, 0 }, jaw = { 0, 0, 0 }, legFL = { 0, 0, 0 }, legFR = { 0, 0, 0 }, kneeFL = { 0, 0, 0 }, kneeFR = { 0, 0, 0 } }, ease = "outCubic" },
})

T.hurt = EnemyKit.track({
	{ t = 0.00, pose = { spine = { 0, 0, 0 }, neck = { rad(-16), 0, 0 } } },
	{ t = 0.08, pose = { spine = { rad(-10), rad(8), rad(6) }, neck = { rad(-4), rad(-10), 0 }, head = { rad(8), 0, 0 }, jaw = { rad(-30), 0, 0 } }, ease = "outQuart" },
	{ t = 0.40, pose = { spine = { 0, 0, 0 }, neck = { rad(-16), 0, 0 }, head = { rad(-8), 0, 0 }, jaw = { 0, 0, 0 } }, ease = "outElastic" },
})

-- Forelegs buckle first, then the head slams, then it settles. Weight comes
-- from the front collapsing before the back.
T.death = EnemyKit.track({
	{ t = 0.00, pose = { spine = { 0, 0, 0 }, neck = { rad(-16), 0, 0 }, head = { rad(-8), 0, 0 } } },
	{ t = 0.14, pose = { spine = { rad(-14), 0, 0 }, neck = { rad(-38), 0, 0 }, head = { rad(-24), 0, 0 }, jaw = { rad(-46), 0, 0 }, frillL = { 0, rad(-40), rad(50) }, frillR = { 0, rad(40), rad(-50) } }, ease = "outQuart" },
	{ t = 0.52, pose = { spine = { rad(26), 0, rad(8) }, neck = { rad(30), rad(10), 0 }, head = { rad(26), 0, 0 }, legFL = { rad(64), 0, 0 }, legFR = { rad(58), 0, 0 }, kneeFL = { rad(-72), 0, 0 }, kneeFR = { rad(-68), 0, 0 } }, ease = "inQuart" },
	{ t = 0.78, pose = { spine = { rad(34), 0, rad(14) }, neck = { rad(48), rad(14), 0 }, head = { rad(40), rad(6), 0 }, legBL = { rad(52), 0, 0 }, legBR = { rad(46), 0, 0 }, kneeBL = { rad(-60), 0, 0 }, kneeBR = { rad(-56), 0, 0 }, jaw = { rad(-20), 0, 0 } }, ease = "outBounce" },
	{ t = 1.60, pose = { spine = { rad(32), 0, rad(13) }, neck = { rad(45), rad(12), 0 }, head = { rad(38), rad(5), 0 }, jaw = { rad(-8), 0, 0 }, frillL = { 0, rad(-6), rad(8) }, frillR = { 0, rad(6), rad(-8) } }, ease = "outCubic" },
})

-- ============================================================
-- BUILD
-- ============================================================
function StoneGnawer.build(variant: EnemyKit.Variant, seed: number?): (Model, any)
	local b = EnemyKit.begin("StoneGnawer", variant, seed, BODY_SCALE)
	local J: { [string]: EnemyKit.Joint } = {}

	local root = EnemyKit.block(b, "Body", Vector3.new(1.30, 1.02, 2.30), "soft")

	local spine = EnemyKit.block(b, "Spine", Vector3.new(1.16, 0.86, 1.20), "soft")
	J.spine = EnemyKit.joint(root, spine, CFrame.new(0, 0.06, -0.62))

	for i = 0, 4 do
		local w = 1.32 - math.abs(i - 1.6) * 0.13
		local host = if i < 2 then spine else root
		local z = if i < 2 then -0.34 + i * 0.5 else -0.86 + i * 0.46
		local plate = EnemyKit.block(b, "Plate" .. i, Vector3.new(w, 0.40, 0.56), "rock")
		EnemyKit.joint(host, plate, CFrame.new(0, 0.48, z) * CFrame.Angles(rad(-8 + i * 4), rad(i * 15 - 24), 0))
		local ridge = EnemyKit.wedge(b, "Ridge", Vector3.new(w * 0.72, 0.40, 0.46), "rock", false)
		EnemyKit.joint(plate, ridge, CFrame.new(0, 0.30, 0) * CFrame.Angles(0, rad(12), 0))
		EnemyKit.anchor(b, plate, CFrame.new(0, 0.34, 0), 0.42)
	end

	local neck = EnemyKit.block(b, "Neck", Vector3.new(0.88, 0.72, 0.86), "soft")
	J.neck = EnemyKit.joint(spine, neck, CFrame.new(0, -0.06, -0.72), CFrame.new(0, 0, -0.30))

	local head = EnemyKit.block(b, "Head", Vector3.new(1.00, 0.60, 0.86), "soft")
	J.head = EnemyKit.joint(neck, head, CFrame.new(0, -0.06, -0.62), CFrame.new(0, 0, -0.30))
	local skull = EnemyKit.block(b, "Skull", Vector3.new(0.94, 0.24, 0.66), "rock")
	EnemyKit.joint(head, skull, CFrame.new(0, 0.28, -0.10) * CFrame.Angles(rad(-9), 0, 0))
	EnemyKit.anchor(b, head, CFrame.new(0, 0.40, -0.2), 0.32)

	local jaw = EnemyKit.block(b, "Jaw", Vector3.new(0.80, 0.24, 0.80), "soft")
	J.jaw = EnemyKit.joint(head, jaw, CFrame.new(0, -0.24, -0.10), CFrame.new(0, 0.06, -0.30))

	for i = 0, 3 do
		local x = (i - 1.5) * 0.19
		local tu = EnemyKit.block(b, "Tooth", Vector3.new(0.10, 0.20, 0.10), "tooth", false)
		EnemyKit.joint(jaw, tu, CFrame.new(x, 0.14, -0.28))
		local td = EnemyKit.block(b, "Tooth", Vector3.new(0.10, 0.20, 0.10), "tooth", false)
		EnemyKit.joint(head, td, CFrame.new(x, -0.24, -0.34))
	end

	-- Sensory frills where eyes would be. They flare when it listens, which is
	-- the entire visual channel for a mechanic that is otherwise audio-only.
	for _, side in { -1, 1 } do
		local f = EnemyKit.wedge(b, "Frill", Vector3.new(0.14, 0.56, 0.52), "pale", false)
		J[if side < 0 then "frillL" else "frillR"] = EnemyKit.joint(head, f, CFrame.new(side * 0.42, 0.18, -0.06) * CFrame.Angles(0, rad(side * 16), rad(side * 12)))
	end

	local plan = { { key = "FL", x = -1, z = -0.72 }, { key = "FR", x = 1, z = -0.72 }, { key = "BL", x = -1, z = 0.78 }, { key = "BR", x = 1, z = 0.78 } }
	for _, p in plan do
		local upper = EnemyKit.block(b, "Leg", Vector3.new(0.34, 0.34, 0.68), "soft")
		J["leg" .. p.key] = EnemyKit.joint(root, upper, CFrame.new(p.x * 0.56, -0.44, p.z) * CFrame.Angles(0, rad(p.x * 4), 0) * CFrame.Angles(rad(-84), 0, 0), CFrame.new(0, 0, 0.34))
		local lower = EnemyKit.block(b, "Shin", Vector3.new(0.28, 0.28, 0.62), "soft")
		J["knee" .. p.key] = EnemyKit.joint(upper, lower, CFrame.new(0, 0, -0.34) * CFrame.Angles(rad(p.z < 0 and 14 or -12), 0, 0), CFrame.new(0, 0, 0.31))
		local foot = EnemyKit.block(b, "Foot", Vector3.new(0.30, 0.20, 0.44), "soft", false)
		EnemyKit.joint(lower, foot, CFrame.new(0, 0, -0.31) * CFrame.Angles(rad(p.z < 0 and 76 or 74), 0, 0), CFrame.new(0, 0.04, 0.16))
	end

	local tail = EnemyKit.block(b, "Tail", Vector3.new(0.44, 0.40, 0.84), "soft")
	J.tail = EnemyKit.joint(root, tail, CFrame.new(0, 0.10, 1.18), CFrame.new(0, 0, -0.42))

	EnemyKit.hitbox(b, root, Vector3.new(1.8, 2.2, 4.2), CFrame.new(0, 0.4, -0.3))
	EnemyKit.collider(b, root, Vector3.new(1.5, 1.6, 3.2), CFrame.new(0, 0.1, 0))

	local model = EnemyKit.finish(b, root, "StoneGnawer", 3)
	return model, { root = root, joints = J }
end

-- ============================================================
-- CONTROLLER
-- ============================================================
export type Gnawer = typeof(setmetatable({} :: any, StoneGnawer))

function StoneGnawer.new(cframe: CFrame, variant: EnemyKit.Variant?, seed: number?): Gnawer
	local v = variant or "regular"
	local model, rig = StoneGnawer.build(v, seed)
	model:PivotTo(cframe)

	local stats = EnemyKit.VariantStats[v]
	local elder = model:GetAttribute("Elder")
	local hp = StoneGnawer.Config.health * stats.health * (if elder then EnemyKit.ElderStats.health else 1)

	local self = setmetatable({
		model = model,
		root = rig.root,
		joints = rig.joints,
		hitbox = model:FindFirstChild("Hitbox"),
		variant = v,
		health = hp,
		maxHealth = hp,
		speed = StoneGnawer.Config.walkSpeed * stats.speed,
		state = "eat",
		t = 0,
		stateT = 0,
		chargeDir = Vector3.zero,
		sounds = {
			eat = EnemyKit.emitter(rig.root, SOUNDS.eat, "Eat", true, 0.55, 8, 45),
			listen = EnemyKit.emitter(rig.root, SOUNDS.listen, "Listen", false, 0.6, 8, 50),
			warn = EnemyKit.emitter(rig.root, SOUNDS.warn, "Warn", false, 0.9, 10, 70),
			charge = EnemyKit.emitter(rig.root, SOUNDS.charge, "Charge", true, 0.85, 10, 70),
			impact = EnemyKit.emitter(rig.root, SOUNDS.impact, "Impact", false, 1, 14, 110),
			death = EnemyKit.emitter(rig.root, SOUNDS.death, "Death", false, 0.9, 12, 80),
		},
	}, StoneGnawer)

	if self.sounds.eat then
		self.sounds.eat:Play()
	end
	return self
end

function StoneGnawer.setState(self: Gnawer, state: string)
	if self.state == state or self.state == "death" then
		return
	end
	local prev = self.state
	self.state = state
	self.stateT = 0
	self.model:SetAttribute("State", state)

	if self.sounds.eat then
		if state == "eat" then
			self.sounds.eat:Play()
		else
			self.sounds.eat:Stop()
		end
	end
	if self.sounds.charge then
		if state == "charge" then
			self.sounds.charge:Play()
		else
			self.sounds.charge:Stop()
		end
	end
	if state == "listen" and prev == "eat" and self.sounds.listen then
		self.sounds.listen:Play()
	elseif state == "warn" and self.sounds.warn then
		self.sounds.warn:Play()
	elseif state == "stagger" and self.sounds.impact then
		self.sounds.impact:Play()
	elseif state == "death" then
		if self.sounds.death then
			self.sounds.death:Play()
		end
	end
end

-- Feed a noise event: 0 = silent, 1 = sprinting. Standing still is invisible.
-- `move` COUNTS AS A CALM STATE, and must. The host drives this creature between grazing spots by
-- setting `move` (server/EnemySystem/StoneGnawerBehavior.stepIdleMovement); the pack alone never
-- entered it, which is why this guard originally listed only the two states that existed. Leaving
-- `move` out makes a Gnawer completely deaf for the several seconds it spends walking, so a player
-- could sprint past a repositioning one and never be noticed — the opposite of the whole creature.
-- `warn` IS ALSO LISTENING, and that is what makes the wind-up a real threat. It does not act on what
-- it hears — the state machine is already committed to charging — it only keeps updating `target`, so
-- the aim it locks at launch is the freshest one it has. See `step` for the re-aim itself.
-- `hunt` IS ALSO A CALM STATE, and leaving it out would be the same bug `move` had. The host walks
-- this creature across the floor toward a vibration it felt from another room
-- (server/EnemySystem/StoneGnawerBehavior), and a Gnawer that went deaf for that whole walk could be
-- sprinted past by anybody standing between it and where it was going — while it was actively
-- hunting. It is the state in which it should be listening HARDEST.
function StoneGnawer.hearNoise(self: Gnawer, loudness: number, from: Vector3)
	local d = (from - self.root.Position).Magnitude
	local radius = StoneGnawer.Config.hearWalk + (StoneGnawer.Config.hearSprint - StoneGnawer.Config.hearWalk) * loudness
	if loudness > 0.05 and d <= radius then
		self:hearAt(from)
	end
end

-- THE SAME REACTION, FOR A NOISE THE HOST HAS ALREADY DECIDED IS AUDIBLE. Everything above the split
-- is the pack's own generic reach; everything below it is what hearing something actually does.
--
-- THE SPLIT EXISTS BECAUSE SOME NOISES HAVE THEIR OWN REACH, and `hearNoise` cannot express them: its
-- radius tops out at `hearSprint` no matter what it is handed, so a caller that had already decided
-- "this creature hears falling stone from seventy studs" had its decision silently overruled by a
-- forty-two stud cap. That is not a tuning disagreement — it made a per-kind reach impossible to
-- write. The host owns those (Config/StoneGnawer.hearLanding, .hearDripstone) because the reach of a
-- shared cave event is a property of this game's sound field, not of the pack.
--
-- WHAT IT STILL DOES NOT BYPASS is any of the state logic: a `warn` still only re-aims, a calm
-- creature still stands up and listens first, and the half-second of `listen` before a charge is
-- still there. This is a louder ear, not a shortcut to the charge.
function StoneGnawer.hearAt(self: Gnawer, from: Vector3)
	if
		self.state ~= "eat"
		and self.state ~= "move"
		and self.state ~= "hunt"
		and self.state ~= "listen"
		and self.state ~= "aim"
		and self.state ~= "warn"
	then
		return
	end
	self.target = from
	if self.state == "warn" or self.state == "aim" then
		-- Tracking only. Committing here would restart the wind-up on every footstep — and during `aim`
		-- it is what lets the turn follow a player who is still moving while the body comes round.
		return
	end
	if self.state == "eat" or self.state == "move" or self.state == "hunt" then
		-- Something audible is HERE, which outranks whatever it was walking across the floor toward.
		-- The host sees the state change and drops the hunt (StoneGnawerBehavior.stepHunt).
		self:setState("listen")
	elseif self.stateT > 0.6 then
		-- TURN FIRST. This used to go straight to `beginCharge`, which meant the wind-up and the turn
		-- happened together and the telegraph spent most of its length pointed somewhere else.
		self:beginAim(from)
	end
end

-- TURN TOWARD SOMETHING, WITHOUT COMMITTING TO IT YET. The body plants, faces the noise and holds
-- there; the host does the actual rotating (it owns the Humanoid) and calls `beginCharge` the moment
-- the body is genuinely pointed at the target, or `aimMaxSeconds` expires and this commits anyway.
--
-- `target` KEEPS UPDATING THROUGHOUT, exactly as it does during the wind-up: a player who moves while
-- the creature is coming round is followed. What they cannot do is make it start over — only a
-- transition out of `aim` does that.
function StoneGnawer.beginAim(self: Gnawer, at: Vector3)
	if self.state == "charge" or self.state == "warn" or self.state == "aim" or self.state == "death" then
		return
	end
	local flat = Vector3.new(at.X - self.root.Position.X, 0, at.Z - self.root.Position.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	self.chargeDir = flat.Unit
	self.target = at
	self:setState("aim")
end

-- Locks a direction and commits. It cannot turn after this — that is the counter.
function StoneGnawer.beginCharge(self: Gnawer, at: Vector3)
	if self.state == "charge" or self.state == "warn" or self.state == "death" then
		return
	end
	local flat = Vector3.new(at.X - self.root.Position.X, 0, at.Z - self.root.Position.Z)
	if flat.Magnitude < 0.1 then
		return
	end
	self.chargeDir = flat.Unit
	-- THE FACING IS NOT WRITTEN WHEN A HUMANOID OWNS THIS BODY, and that exception is load-bearing.
	--
	-- This module assumes the host drives the creature by CFrame (the pack builds no Humanoid), and
	-- under that assumption snapping the root round is free. This game gives it a Humanoid instead, and
	-- a direct CFrame write on the root of an unanchored Humanoid assembly is a TELEPORT: the
	-- controller loses the floor it was holding the body above, the body enters Freefall and drops
	-- until its collider lands, and `Humanoid:Move` has no traction while it is falling. That is a
	-- Gnawer that sinks into the ground at the start of every charge, stands there unable to travel,
	-- and pops back up the moment the charge times out and the controller recovers.
	--
	-- The host turns it through the Humanoid instead (server/EnemySystem/EnemyMover.setFacing), which
	-- is the same commitment expressed to the thing actually in charge of the body.
	if self.model:FindFirstChildOfClass("Humanoid") == nil then
		self.root.CFrame = CFrame.lookAt(self.root.Position, self.root.Position + self.chargeDir)
	end
	self:setState("warn")
end

function StoneGnawer.onChargeCollide(self: Gnawer)
	if self.state ~= "charge" then
		return
	end
	self:setState("stagger")
end

function StoneGnawer.damage(self: Gnawer, amount: number)
	if self.state == "death" then
		return
	end
	self.health -= amount
	if self.health <= 0 then
		self:setState("death")
	elseif self.state ~= "charge" and self.state ~= "warn" then
		self:setState("hurt")
	end
end

function StoneGnawer.step(self: Gnawer, dt: number)
	self.t += dt
	self.stateT += dt

	-- TRACK THROUGH THE WIND-UP, LOCK AT LAUNCH. `beginCharge` used to fix the heading the instant the
	-- warn began, so the whole 1.1s telegraph aimed at wherever the player HAD been. Anyone who kept
	-- moving after triggering it was already clear before the charge started, which made the wind-up the
	-- moment to dodge and the charge itself a formality.
	--
	-- Re-aiming every frame moves the decision to where it belongs: the creature turns to follow the
	-- most recent thing it heard for as long as it is winding up (`hearNoise` keeps feeding `target`
	-- while in `warn`), and the heading is frozen only by the transition below. So the dodge is a
	-- sidestep as it launches, and the counter is still that it cannot steer once committed.
	--
	-- This runs BEFORE the timeout so the very last frame of the wind-up re-aims and then commits on the
	-- same tick — no stale frame between the final aim and the launch.
	-- THE TRACKING IS RATE-LIMITED, which is what keeps the encounter winnable. An instant re-aim would
	-- follow a player round in a circle perfectly and the charge could never be beaten by movement at
	-- all — only by breaking line of travel at the exact frame of launch. Capping the turn means running
	-- laterally, hard, genuinely out-turns it, and it also keeps the AIM and the BODY together: the
	-- Humanoid turns at its own rate (EnemyMover.hold), so a heading that snapped would leave the
	-- creature charging sideways out of a body still facing where it started.
	-- AIM TRACKS WITHOUT A RATE LIMIT, unlike the wind-up below. During `aim` the body itself is what
	-- is turning and the Humanoid is already the limiter, so capping the heading as well would fight
	-- it: the creature would arrive facing a stale direction and then have to turn again inside its
	-- own telegraph, which is the exact bug the aim phase exists to remove.
	if self.state == "aim" then
		local target = self.target
		if target ~= nil then
			local flat = Vector3.new(target.X - self.root.Position.X, 0, target.Z - self.root.Position.Z)
			if flat.Magnitude >= 0.1 then
				self.chargeDir = flat.Unit
			end
		end
	end

	if self.state == "warn" then
		local target = self.target
		if target ~= nil then
			local flat = Vector3.new(target.X - self.root.Position.X, 0, target.Z - self.root.Position.Z)
			if flat.Magnitude >= 0.1 then
				local desired = flat.Unit
				local current = self.chargeDir
				if current.Magnitude < 0.1 then
					self.chargeDir = desired
				else
					local dot = math.clamp(current:Dot(desired), -1, 1)
					local crossY = current.Z * desired.X - current.X * desired.Z
					local maxStep = math.rad(StoneGnawer.Config.warnTurnDegreesPerSecond) * dt
					local signed = math.clamp(-math.atan2(crossY, dot), -maxStep, maxStep)
					local c, s = math.cos(signed), math.sin(signed)
					self.chargeDir =
						Vector3.new(current.X * c - current.Z * s, 0, current.X * s + current.Z * c).Unit
				end
			end
		end
	end

	-- THE AIM TIMES OUT INTO THE WIND-UP. Normally the host ends it earlier, the moment the body is
	-- actually pointed at the target; this is the floor under a creature that cannot get there.
	if self.state == "aim" and self.stateT >= StoneGnawer.Config.aimMaxSeconds then
		self:setState("warn")
	elseif self.state == "warn" and self.stateT >= StoneGnawer.Config.warnSeconds then
		self:setState("charge")
	elseif self.state == "charge" and self.stateT >= StoneGnawer.Config.chargeLockSeconds then
		self:setState("listen")
	elseif self.state == "stagger" and self.stateT >= StoneGnawer.Config.staggerSeconds then
		self:setState("listen")
	elseif self.state == "hurt" and self.stateT > 0.40 then
		self:setState("listen")
	end

	local track = T[self.state] or T.eat
	EnemyKit.evaluate(self.joints, track, self.stateT)

	if self.state ~= "death" then
		EnemyKit.breathe(self.joints.tail, self.t, 1.4, 0.06)
	end
end

-- Returns the world velocity the mover should apply this frame. Charge is a
-- straight line with no steering; everything else defers to pathfinding.
function StoneGnawer.desiredVelocity(self: Gnawer): Vector3?
	if self.state == "charge" then
		return self.chargeDir * StoneGnawer.Config.chargeSpeed
	end
	return nil
end

function StoneGnawer.destroy(self: Gnawer)
	self.model:Destroy()
end

return StoneGnawer

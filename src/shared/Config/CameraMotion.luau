--!strict
-- The camera's own locomotion motion, and the global policy every other camera effect obeys.
--
-- WHAT LIVES HERE AND WHAT DOES NOT. This file owns the motion the CAMERA generates by itself --
-- walking, running, landing -- plus the ceiling and the reduced-motion scales that apply to all
-- camera movement in the game. It deliberately does NOT own the shake numbers for the dripstone, the
-- blast, the Warden or the Lurker: a creature's shake is part of that creature's presentation and
-- belongs beside the rest of it, the same way its audio and its silhouette do. Those systems author
-- their own studs and degrees and hand them to `client/CameraMotionController`, which is where the
-- policy below is applied to them.
--
-- RESTRAINT IS THE DESIGN CONSTRAINT, not a tuning preference. DESIGN section 5 requires sprint
-- presentation to sit "at the edge of conscious notice", and the same bar applies to the walk cycle:
-- this exists so the body reads as a body, not so the screen has something happening on it.

local CameraMotion = require(script.Parent.Parent.Logic.CameraMotion)

export type CameraMotionConfig = {
	enabled: boolean,
	defaultLevel: CameraMotion.Level,
	levelOrder: { CameraMotion.Level },
	levelLabels: { [string]: string },
	scales: { [string]: CameraMotion.Scales },
	headBob: CameraMotion.HeadBobConfig,
	landing: CameraMotion.LandingConfig,
	limits: CameraMotion.Limits,
	postureLimits: CameraMotion.Limits,
	maximumShakes: number,
}

local Config: CameraMotionConfig = {
	enabled = true,

	-- WHAT A NEW PLAYER GETS. Full, because the effects below are authored to be comfortable rather
	-- than to be survived, and a setting that most players have to find and change before the game is
	-- pleasant is a badly tuned default rather than an accessibility feature.
	defaultLevel = "Full",
	-- The order the settings row cycles through. It wraps, so the control can never strand a player.
	levelOrder = { "Full", "Reduced", "Off" },
	levelLabels = {
		Full = "FULL",
		Reduced = "REDUCED",
		Off = "OFF",
	},

	-- The four channels, and how much of each survives at each level. Split into four rather than one
	-- master dial because they are uncomfortable for different reasons and carry different amounts of
	-- information -- a player who cannot take a blast shake may still want the walk cycle, and a
	-- knockdown has to stay legible even when everything else is off.
	scales = {
		Full = { bob = 1, shake = 1, posture = 1, viewKick = 1 },
		-- Everything still happens; nothing is loud. This is the setting for a player who noticed the
		-- camera moving and would rather it did not, which is a far more common complaint than motion
		-- sickness and is not served by an on/off switch.
		Reduced = { bob = 0.35, shake = 0.45, posture = 0.7, viewKick = 0.5 },
		-- `viewKick = 0` pins the field of view: an FOV that changes under you is the single most
		-- reliably nauseating thing a first-person camera does, and the sprint still reads through the
		-- vignette, the streaks, the flame lean and the footstep cadence, none of which move the view.
		--
		-- `posture` survives at a third rather than going to zero. It is the channel a tripwire
		-- knockdown and a landing dip use, and those are not decoration -- pitching toward the floor is
		-- how the game says "you are down" from a viewpoint that has no third-person body to show it
		-- with. They are also slow, single, deliberate movements rather than oscillation, which is what
		-- actually makes a camera hard to tolerate.
		Off = { bob = 0, shake = 0, posture = 0.35, viewKick = 0 },
	},

	headBob = {
		-- Below this the body counts as standing still. Matches `Feel.footsteps.minimumSpeed`, so the
		-- cadence you see and the cadence you hear start and stop on the same frame.
		minimumSpeed = 1.5,
		-- Speed (studs/s) at which the bob is at its authored amplitude. Well under the 8-stud walk, so
		-- ordinary walking is fully bobbed and only the first moment of stepping off is eased.
		fullBobSpeed = 5,
		-- STRIDES PER SECOND, not steps. A stride is two steps, and the vertical drop happens once per
		-- step -- so these are half the footfall rate. `Feel.footsteps` places a step every 0.52 s at a
		-- walk and every 0.33 s at a run; 0.96 Hz and 1.52 Hz are those rates halved, which is what puts
		-- the camera's low point on the same frame as the footstep sample instead of beating against it.
		walk = {
			frequencyHz = 0.96,
			-- How far the eye drops at each footfall (studs). The eye sits around 4 studs up, so this is
			-- under two percent of eye height: felt, not watched.
			verticalStuds = 0.075,
			-- Side to side over a full stride. Kept well under the vertical, because lateral sway is the
			-- component that reads as drunk when it is overdone.
			lateralStuds = 0.045,
			-- Roll into the sway. The smallest of the three and the one that does most of the work: a
			-- camera that banks fractionally with its own footfalls stops reading as a floating point.
			rollDegrees = 0.32,
			-- Nose-down as weight lands, a quarter cycle behind the drop.
			pitchDegrees = 0.14,
		},
		-- Running is the same cycle, faster and heavier. Roughly double the amplitude of the walk, which
		-- is where the difference becomes something a player feels in their hands rather than notices.
		run = {
			frequencyHz = 1.52,
			verticalStuds = 0.15,
			lateralStuds = 0.085,
			rollDegrees = 0.7,
			pitchDegrees = 0.3,
		},
		-- Seconds for the bob to fade fully in or out. Short enough to feel connected to the input,
		-- long enough that tapping a direction key does not snap the camera.
		easeSeconds = 0.16,
		-- Faster fade for leaving the ground. Feet off the rock means no walk cycle, and holding it a
		-- moment longer than the jump would be the camera lying about what the body is doing.
		airEaseSeconds = 0.09,
	},

	landing = {
		-- Fall speed (studs/s) below which a landing produces nothing. `Movement.hopPower` is 30, so an
		-- ordinary hop off flat ground returns at about 30 and lands silent by design: the hop is
		-- terrain recovery (DESIGN section 5) and players use it constantly on uneven rock. Only a real
		-- drop is worth a dip.
		minimumFallSpeed = 36,
		-- Fall speed at which the dip is at full authored size.
		fullFallSpeed = 90,
		-- How far the eye sinks at a full-strength landing (studs), and how far it noses down with it.
		dipStuds = 0.36,
		pitchDegrees = 2.1,
		-- Down and back up. Long enough to read as absorbing the drop, short enough that control never
		-- feels taken away.
		durationSeconds = 0.32,
	},

	-- THE CEILING ON EVERYTHING ADDED TOGETHER, applied after the per-channel scales. A blast landing
	-- during a Warden's approach is a legitimate moment and neither effect should be dropped -- but
	-- their sum has to stay inside something a player can still aim and read the cave through.
	--
	-- Generous relative to any single effect: the largest authored shake in the game is 0.2 studs, so
	-- this is roughly four of them at once before anything is held back.
	limits = {
		studs = 0.75,
		degrees = 7,
	},

	-- POSTURE IS BOUNDED SEPARATELY, and much further out. A tripwire knockdown moves the eye 2.2
	-- studs and pitches it 78 degrees; that is not four shakes stacking up by accident, it is one
	-- authored pose saying "you are face down on the rock". Sharing the budget above would clip it to a
	-- stumble. This bound exists only so that no bug in a posture source can throw the view somewhere
	-- unrecoverable, which is why it sits well outside anything the game actually asks for.
	postureLimits = {
		studs = 4,
		degrees = 100,
	},

	-- How many decaying impacts may be live at once. The oldest is dropped when a new one arrives past
	-- this, which is the right end to drop from: the oldest is also the most decayed, so losing it is
	-- the least visible thing that can be lost. The ceiling above already bounds how large the sum can
	-- get; this bounds how much work the frame does to compute it during a boss floor where a slam, its
	-- boulders and a Warden's footfalls can all be resolving at once.
	maximumShakes = 12,
}

return Config

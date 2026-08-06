--!strict
-- The Ashamed Lurker: a deep-floor doorway creature that lunges for the wax of anyone who RUNS
-- through the half of an arch its long arm crosses, and retreats in shame when a player standing in
-- the open half holds its gaze. Pure data; Logic/AshamedLurkerRules owns the rules, FloorPlanner
-- picks the arches, FloorBuilder places the proxy, and server/AshamedLurkerService owns state.
--
-- TWO INVARIANTS, both enforced by the rules and the planner, not here:
--   1. Only ONE half of a doorway is ever trapped. The opposite lane always keeps at least
--      `minSafeLaneWidth` studs of clear floor, so an arch it occupies is never impassable —
--      the open lane is always an answer, and Cup-slowed movement can cross the trapped lane.
--   2. It is never fought. A grab costs wax; a held stare drives it off. Nothing kills it.

export type AshamedLurkerConfig = {
	enabled: boolean,
	minDepth: number,
	maxPerFloorByDepth: { number },
	chancePerEligibleDoorway: number,
	sitesPerLurker: number,
	placement: {
		minDoorWidth: number,
		maxDoorWidth: number,
		minDoorHeight: number,
		maxDoorHeight: number,
		edgeInset: number,
		restArmReach: number,
		minSafeLaneWidth: number,
	},
	face: {
		heightFraction: number,
		lateralInset: number,
		forwardOffset: number,
	},
	trigger: {
		sampleHz: number,
		reach: number,
		minSpeedFraction: number,
		minAbsoluteSpeed: number,
		laneDepth: number,
		laneCenterY: number,
		laneHeight: number,
		grabLateralPadding: number,
		grabDepthPadding: number,
		grabCheckDelaySeconds: number,
		recoverySeconds: number,
		rearmSeconds: number,
		waxLossFraction: number,
	},
	gaze: {
		sampleHz: number,
		dotThreshold: number,
		holdSeconds: number,
		maxDistance: number,
		requiredDialFraction: number,
		losEndpointInset: number,
		maxCameraOffsetStuds: number,
		sampleTimeoutSeconds: number,
		decayPerSecond: number,
	},
	ashamedSeconds: number,
	hiddenSeconds: number,
	presentation: {
		cullDistance: number,
		cullHysteresis: number,
		maxAnimationDeltaSeconds: number,
		breathAudibleDistance: number,
		breathMinIntervalSeconds: number,
		breathMaxIntervalSeconds: number,
		grabPresentationRadius: number,
		grabShakeSeconds: number,
		grabShakeStuds: number,
		grabShakeDegrees: number,
		grabShakeFrequency: number,
		grabDimSeconds: number,
		grabDimBrightness: number,
		grabDimContrast: number,
		grabDimTint: Color3,
	},
	motion: {
		dormant: {
			breathRadiansPerSecond: number,
			chestBobStuds: number,
			hubBobStuds: number,
			chestPitchDegrees: number,
			neckPitchDegrees: number,
			jawRestDegrees: number,
			jawBreathDegrees: number,
			shoulderBreathDegrees: number,
			wallShoulderBreathDegrees: number,
			twitchPrimaryRadiansPerSecond: number,
			twitchSecondaryRadiansPerSecond: number,
			twitchSecondaryWeight: number,
			headTwitchYawDegrees: number,
			headTwitchPitchDegrees: number,
			fingerRadiansPerSecond: number,
			fingerPhaseStepRadians: number,
			fingerCurlDegrees: number,
		},
		triggered: {
			safeLaneMarginStuds: number,
			bodyLeadFraction: number,
			armLeadFraction: number,
			headLeadFraction: number,
			bodyRecoveryStartFraction: number,
			headRecoveryStartFraction: number,
			armRecoveryStartFraction: number,
			idleBlend: number,
			hubDropStuds: number,
			hubRollDegrees: number,
			chestPitchDegrees: number,
			chestYawDegrees: number,
			neckPitchDegrees: number,
			headPitchDegrees: number,
			headYawDegrees: number,
			jawOpenDegrees: number,
			armShoulderPitchDegrees: number,
			armShoulderYawDegrees: number,
			armShoulderRollDegrees: number,
			armElbowPitchDegrees: number,
			armWristYawDegrees: number,
			fingerCurlDegrees: number,
			wallShoulderPitchDegrees: number,
			wallShoulderRollDegrees: number,
			wallElbowPitchDegrees: number,
			wallWristYawDegrees: number,
			recoverySagStuds: number,
			recoveryChestTwistDegrees: number,
			recoveryShoulderHangDegrees: number,
		},
		ashamed: {
			fissureDartEndFraction: number,
			coverStartFraction: number,
			coverEndFraction: number,
			retreatStartFraction: number,
			retreatEndFraction: number,
			fadeStartFraction: number,
			fadeEndFraction: number,
			idleBlend: number,
			fissureDartRadiansPerSecond: number,
			fissureDartStuds: number,
			armShoulderPitchDegrees: number,
			armShoulderYawDegrees: number,
			armShoulderRollDegrees: number,
			armElbowPitchDegrees: number,
			armWristYawDegrees: number,
			fingerCurlDegrees: number,
			wallShoulderPitchDegrees: number,
			wallShoulderYawDegrees: number,
			wallShoulderRollDegrees: number,
			wallElbowPitchDegrees: number,
			wallWristYawDegrees: number,
			headPitchDegrees: number,
			headYawDegrees: number,
			jawCloseDegrees: number,
			chestPitchDegrees: number,
			chestYawDegrees: number,
			retreatSideStuds: number,
			retreatUpStuds: number,
			retreatThroughStuds: number,
			retreatPitchDegrees: number,
		},
	},
	visual: {
		skin: Color3,
		skinPale: Color3,
		bone: Color3,
		boneDark: Color3,
		void: Color3,
		rock: Color3,
		rockLight: Color3,
	},
}

local AshamedLurker: AshamedLurkerConfig = {
	enabled = true,
	-- First GLOBAL depth an arch may host one. Floors 1-3 teach doorways without a reason to fear one.
	minDepth = 4,
	-- Maximum per floor, indexed by global depth (clamped to the last entry). The real count is
	-- usually lower: an arch also has to pass the size/lane rules below and win its own roll, so
	-- "0 or 1" is the common outcome and two is a deep-floor event.
	maxPerFloorByDepth = { 0, 0, 0, 1, 1, 1, 2, 2, 2, 2 },
	-- Chance an eligible arch is taken while the floor still wants one. Qualifying arches are already
	-- scarce (most openings are the wrong size, and protected rooms are excluded), so this lands at
	-- roughly half of deep floors carrying one and two being a genuine rarity. A player must never
	-- learn to expect one on every floor.
	chancePerEligibleDoorway = 0.7,
	-- How many arches one creature reserves: where it starts, plus the arches it relocates to after
	-- being shamed off. Sites are never shared, so a floor with only one qualifying arch simply means
	-- the creature comes back to the same one — it is hidden for `hiddenSeconds` either way.
	sitesPerLurker = 3,
	placement = {
		-- Nominal doorway width is measured before Terrain intrudes: the cave floor rolls up into the
		-- opening and the arch's own rock eats into its edges, so a "12-stud" door plays much tighter
		-- than it measures. 16 is the narrowest opening that still reads and walks as a real room
		-- mouth once that is accounted for. A cramped arch never hosts one, so the creature can never
		-- be met in a doorway a player is forced to squeeze through. It is also the narrowest width
		-- that can hold `trigger.reach` (7) plus `edgeInset` (0.7) plus the full `minSafeLaneWidth`
		-- guarantee (8.4) — below this the three numbers cannot all be honoured at once.
		minDoorWidth = 17,
		maxDoorWidth = 28,
		-- Short arches hide the head; the ceiling cap (Floors.geometry.doorwayMaxHeight) is 13.
		minDoorHeight = 9.5,
		maxDoorHeight = 13,
		-- How far the body sits in from the springer, so it never intersects the wall it clings to.
		edgeInset = 0.7,
		-- VISUAL ONLY: how far the draped arm extends while dormant. The volume that actually catches
		-- a runner is `trigger.reach` — the creature lunges well past where its arm rests, which is
		-- what makes the attack land without the resting silhouette blocking the arch.
		restArmReach = 3.5,
		-- Clear floor the opposite lane must keep: three candles (3 * 2.8 = 8.4) walking abreast.
		-- Measured against `trigger.reach`, not the resting arm, so the guarantee covers the lunge.
		minSafeLaneWidth = 8.4,
	},
	-- Where the face sits, relative to the doorway root (its floor centre). The server derives the
	-- gaze target from this and the client's model builder puts the head there; they must agree.
	face = {
		heightFraction = 0.52,
		lateralInset = 1.35,
		-- Kept in the plane of the opening so the face reads from BOTH approaches.
		forwardOffset = 0,
	},
	trigger = {
		sampleHz = 20,
		-- THE attack range: a FIXED distance in from the trapped springer that the creature can snatch
		-- across when it commits, independent of how wide the arch is. It does not scale with the
		-- opening, so a big arch is proportionally far less covered (7 of 16 studs at the narrowest
		-- allowed door, 7 of 28 at the widest) while the lunge still reaches far enough past the
		-- resting arm to actually catch someone on the trapped lane rather than only someone who stops
		-- at the body. Capped by the trap half in the rules, so it never crosses the centre.
		reach = 7,
		-- Fraction of Config/Movement.runSpeed that counts as "running through". 0.7 * 16 = 11.2 sits
		-- clearly above Cup-slowed movement (8) and below the 16-stud default run, so the trapped lane
		-- trips during ordinary movement.
		minSpeedFraction = 0.7,
		-- Floor under the fraction, so a sacrifice or effect that lowers run speed cannot make the
		-- creature harmless. Still above Cup-slowed movement.
		minAbsoluteSpeed = 10,
		-- Lane depth through the opening (studs along the doorway normal). Wide enough that a default
		-- runner at 16 studs/s is sampled several times crossing it rather than tunnelling through.
		laneDepth = 4.5,
		-- Vertical band, measured from the doorway's floor. Generous: Terrain rolls up into the
		-- opening and a candle's tracked position is its base, not its middle.
		laneCenterY = 2.5,
		laneHeight = 10,
		-- The grab volume checked at the impact frame is the trip lane grown by this much. Depth is
		-- padded hard: a default runner covers ~2 studs during the wind-up, so without it the grab would
		-- resolve behind an already-departed runner. Escaping is meant to be LATERAL — leaving the
		-- trapped lane — not simply being fast.
		grabLateralPadding = 0.8,
		grabDepthPadding = 2.5,
		-- Wind-up before the hand closes. This is the whole reaction window.
		grabCheckDelaySeconds = 0.12,
		-- How long it stays extended after a lunge before it settles back.
		recoverySeconds = 0.9,
		-- Minimum gap between lunges, so one runner cannot be hit twice by one pass.
		rearmSeconds = 0.5,
		-- Wax taken by a connecting grab, as a fraction of the candle's maximum. Level with the
		-- lightest dripstone impact: a real wound, not a run-ender.
		waxLossFraction = 0.2,
	},
	gaze = {
		sampleHz = 12,
		-- cos of the cone the face must sit inside. 0.86 is roughly 31 degrees: still deliberate, but
		-- forgiving enough that "I am clearly looking at it" reliably reads as looking at it.
		dotThreshold = 0.86,
		-- Half a second of being seen is enough. It is not a staring contest; it is caught.
		holdSeconds = 0.5,
		-- It has to be able to tell it is being looked AT, which means you are close.
		maxDistance = 12,
		-- How far up the ORDINARY dial (Light.minBurnRate .. maxBurnRate) the flame must be before it
		-- can be seen well enough to shame. 0.5 is the middle of the slider the player actually drags.
		-- Creeping past it in the dark is a real option; it just costs you the brightness to do it.
		requiredDialFraction = 0.5,
		-- The line-of-sight ray stops this far short of the face. The head is embedded in the arch, so
		-- the rock immediately behind and around it is not an occluder — only walls and bends along
		-- the rest of the path are. Without this, its own doorway blocks every stare.
		losEndpointInset = 1.5,
		-- The server cannot see a client's camera, so it validates the reported one against the
		-- authoritative body position instead.
		maxCameraOffsetStuds = 8,
		-- A sample older than this is stale and stops counting.
		sampleTimeoutSeconds = 0.35,
		-- Progress decays this many seconds of hold per second of looking away, so a flicked glance
		-- across it is not banked.
		decayPerSecond = 2.4,
	},
	-- Cover-face-and-retreat animation before it is gone.
	ashamedSeconds = 1.3,
	-- How long a shamed creature stays away before it settles into a DIFFERENT arch on the same
	-- floor. Clearing an arch buys a route, never permanent safety.
	hiddenSeconds = 50,
	presentation = {
		cullDistance = 110,
		cullHysteresis = 12,
		maxAnimationDeltaSeconds = 0.1,
		breathAudibleDistance = 26,
		breathMinIntervalSeconds = 3.5,
		breathMaxIntervalSeconds = 8,
		-- A connecting grab is meant to land as a scare, so the shake carries into the room rather
		-- than only hitting the victim.
		grabPresentationRadius = 60,
		grabShakeSeconds = 0.65,
		grabShakeStuds = 0.9,
		grabShakeDegrees = 3.2,
		grabShakeFrequency = 30,
		grabDimSeconds = 1.1,
		grabDimBrightness = -0.28,
		grabDimContrast = 0.2,
		grabDimTint = Color3.fromRGB(255, 214, 206),
	},
	-- Procedural pose tuning only. Gameplay timing remains in `trigger`, `gaze`, and
	-- `ashamedSeconds`; the builder derives its phases from those authorities rather than carrying a
	-- second animation clock that could disagree with the grab or relocation state machine.
	motion = {
		dormant = {
			breathRadiansPerSecond = 1.15,
			chestBobStuds = 0.014,
			hubBobStuds = 0.007,
			chestPitchDegrees = 2,
			neckPitchDegrees = 1,
			jawRestDegrees = 4,
			jawBreathDegrees = 4,
			shoulderBreathDegrees = 1.2,
			wallShoulderBreathDegrees = 0.7,
			twitchPrimaryRadiansPerSecond = 0.63,
			twitchSecondaryRadiansPerSecond = 1.9,
			twitchSecondaryWeight = 0.24,
			headTwitchYawDegrees = 3.2,
			headTwitchPitchDegrees = 1.6,
			fingerRadiansPerSecond = 1.4,
			fingerPhaseStepRadians = 1,
			fingerCurlDegrees = 2.9,
		},
		triggered = {
			-- The animated silhouette keeps this much local-X room before the doorway centre line. The
			-- actual gameplay grab volume may touch the centre line, but neither one crosses it.
			safeLaneMarginStuds = 1,
			-- Torso/shoulder commit first, the reaching arm follows, and the face arrives last. All
			-- three still equal one at `grabCheckDelaySeconds`, the authoritative impact instant.
			bodyLeadFraction = 0,
			armLeadFraction = 0.22,
			headLeadFraction = 0.5,
			-- Recovery is deliberately staggered: mass comes back first, the skull follows, and the
			-- hand hangs in the lane for a short readable beat before dragging home.
			bodyRecoveryStartFraction = 0.04,
			headRecoveryStartFraction = 0.12,
			armRecoveryStartFraction = 0.2,
			idleBlend = 0.28,
			hubDropStuds = 0.35,
			hubRollDegrees = 10,
			chestPitchDegrees = -18,
			chestYawDegrees = -16,
			neckPitchDegrees = 12,
			headPitchDegrees = -14,
			headYawDegrees = 20,
			jawOpenDegrees = 30,
			-- Most of the reach comes from the bounded hub translation. Keeping the shoulder's local-Z
			-- sweep small protects the open half while pitch gives the arm a large silhouette change.
			armShoulderPitchDegrees = -32,
			armShoulderYawDegrees = 8,
			armShoulderRollDegrees = -6,
			armElbowPitchDegrees = -36,
			armWristYawDegrees = 38,
			fingerCurlDegrees = -46,
			wallShoulderPitchDegrees = 12,
			wallShoulderRollDegrees = 8,
			wallElbowPitchDegrees = 10,
			wallWristYawDegrees = -10,
			recoverySagStuds = 0.16,
			recoveryChestTwistDegrees = 10,
			recoveryShoulderHangDegrees = 18,
		},
		ashamed = {
			fissureDartEndFraction = 0.26,
			coverStartFraction = 0.12,
			coverEndFraction = 0.48,
			retreatStartFraction = 0.48,
			retreatEndFraction = 1,
			fadeStartFraction = 0.72,
			fadeEndFraction = 1,
			idleBlend = 0.16,
			fissureDartRadiansPerSecond = 34,
			fissureDartStuds = 0.05,
			armShoulderPitchDegrees = -18,
			armShoulderYawDegrees = -12,
			armShoulderRollDegrees = 96,
			armElbowPitchDegrees = -72,
			armWristYawDegrees = -24,
			fingerCurlDegrees = -34,
			wallShoulderPitchDegrees = -14,
			wallShoulderYawDegrees = 10,
			wallShoulderRollDegrees = -84,
			wallElbowPitchDegrees = -66,
			wallWristYawDegrees = 22,
			headPitchDegrees = 26,
			headYawDegrees = -34,
			jawCloseDegrees = -6,
			chestPitchDegrees = 22,
			chestYawDegrees = 18,
			retreatSideStuds = 1.1,
			retreatUpStuds = 1.9,
			retreatThroughStuds = 1.3,
			retreatPitchDegrees = -24,
		},
	},
	-- Ash-grey starved flesh with pale bone. Only the back plates and the wall socket imitate stone;
	-- the face fissure is non-emissive black negative space, never a glowing eye.
	visual = {
		skin = Color3.fromRGB(46, 40, 43),
		skinPale = Color3.fromRGB(63, 55, 57),
		bone = Color3.fromRGB(118, 108, 95),
		boneDark = Color3.fromRGB(82, 74, 67),
		void = Color3.fromRGB(7, 6, 8),
		-- Matched to FloorBuilder's wall/rock slate so the socket and back plates genuinely disappear
		-- into the springer until a flame is close enough to resolve the body in front of them.
		rock = Color3.fromRGB(52, 56, 66),
		rockLight = Color3.fromRGB(62, 66, 78),
	},
}

return AshamedLurker

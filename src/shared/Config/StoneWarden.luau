--!strict
-- Stone Warden encounter tuning. The planner owns whether and where the encounter exists;
-- server runtime only realizes the planned room fixtures and behaviour.

export type CollapseDripstoneLayout = {
	lateral: number,
	standoff: number,
	variantId: string,
}

-- WHAT ONE CAVE'S WARDEN IS LIT BY. Kept here rather than in Config/CaveFamilies.presentation because
-- everything a family owns there describes the CAVE — its rock, its air, its growth — and is held to
-- ART-BIBLE §4's darkness bound by CaveFamilyRules.validate for exactly that reason. These two colours
-- describe a CREATURE carrying its own small light, which is a thing the roster already does (the
-- Drawn's warm halo, the dark-hunter's crimson slits) and which that bound would wrongly forbid.
--
-- The light is deliberately tiny. `eyeLightRange` is short enough that two embers resolve out of the
-- dark a moment before the mass behind them does, and never enough to show a player the room.
export type WardenAccent = {
	eyeColor: Color3,
	eyeLightBrightness: number,
	eyeLightRange: number,
	coreColor: Color3,
	-- 0 leaves the body bare rock. Above zero cuts glowing seams into the chest and shoulders.
	coreSeamCount: number,
}

export type WardenSqueezeConfig = {
	enabled: boolean,
	-- The authoritative root's two shapes. `standing` is the body that has always been the gameplay
	-- hitbox; `squeezed` is the same body folded down small enough to physically clear the tightest
	-- opening Config/Floors can cut (doorwayMinHeight 8, doorwayMinWidth 8).
	standingHeight: number,
	standingWidth: number,
	squeezedHeight: number,
	squeezedWidth: number,
	-- Free space the body wants ahead of it before it will walk on standing. Anything less and it
	-- folds. Height clearance is measured from the ground the Warden is standing on.
	heightClearance: number,
	widthClearance: number,
	probeDistances: { number },
	probeSeconds: number,
	-- Held folded this long after the probe comes back clear, so it does not pop upright halfway
	-- through an arch it is still physically inside.
	releaseGraceSeconds: number,
	enterSeconds: number,
	exitSeconds: number,
	-- The cost of folding. A squeezing Warden is slower, which is the only thing this whole system
	-- takes away from it — before it, a tight doorway stopped the pursuit outright.
	walkSpeedMultiplier: number,
	-- Pathfinding agent. Sized to the SQUEEZED body: a Warden that can fold has to be allowed to
	-- plan through the openings it can fold through, or the animation would never be reached.
	agentRadius: number,
	agentHeight: number,
	-- Presentation. Grit shed off the shoulders while stone is dragging against stone.
	dustRate: number,
	grindCueSeconds: number,
}

-- THE WAKE, BEAT BY BEAT. Fractions of Config/StoneWarden.emergenceSeconds, in order, so retiming the
-- emergence retimes every beat with it and none of them can drift past the end of the animation.
export type WardenShakeSpec = {
	seconds: number,
	studs: number,
	degrees: number,
	frequency: number,
}

export type WardenEmergenceStages = {
	-- The wall shivers and sheds dust; nothing has moved yet.
	tremorFraction: number,
	-- One arm breaks the seal and takes the floor.
	breachFraction: number,
	-- Head clears the rock and the eyes light.
	riseFraction: number,
	-- Full height, and the bellow.
	roarFraction: number,
	dustRate: number,
	burstParticles: number,
	-- What the floor does under the player at each beat, keyed by the beat's id. The wake escalates:
	-- a long low shiver, a hard short crack as the arm comes out, the rise, and then the bellow — which
	-- is the largest camera event this encounter ever produces.
	beatShake: { [string]: WardenShakeSpec },
}

export type WardenPresenceConfig = {
	-- Gameplay-facing tag, distinct from Config/Diagnostics.wardenTag: that one exists so a developer
	-- overlay can count bodies and may be removed with the overlay. Clients read THIS one every frame
	-- to place the tremor, so it is part of the encounter rather than part of the tooling.
	tag: string,
	-- Ground shake. `radius` is where the floor starts moving at all; the falloff is quadratic, so the
	-- last few studs carry most of it.
	rumbleRadius: number,
	rumbleStuds: number,
	rumbleDegrees: number,
	rumbleFrequency: number,
	-- Multiplies the sustained bed while the body is actually walking, against standing still.
	rumbleMovingBonus: number,
	-- One footfall. Shorter and much harder than the bed it lands on top of.
	stepShakeSeconds: number,
	stepShakeStuds: number,
	stepShakeDegrees: number,
	stepShakeFrequency: number,
	stepAudioRadius: number,
	stepPresentationRadius: number,
	-- The low bed that plays off the body itself whenever one is near enough to matter.
	loopRadius: number,
	loopCueName: string,
}

export type StoneWardenMotionConfig = {
	maxDeltaSeconds: number,
	gaitCycleSeconds: number,
	gaitReferenceSpeed: number,
	minimumGaitCadenceScale: number,
	maximumGaitCadenceScale: number,
	gaitBlendSeconds: number,
	bodyBobStuds: number,
	hipRollDegrees: number,
	legSwingDegrees: number,
	kneeLiftDegrees: number,
	armSwingDegrees: number,
	armPhaseLagFraction: number,
	headLagSeconds: number,
	headLagDegrees: number,
	emergenceUnsealFraction: number,
	emergenceCrouchStuds: number,
	emergenceShoulderDegrees: number,
	stunSettleSeconds: number,
	stunSagStuds: number,
	stunPitchDegrees: number,
	resumeGatherSeconds: number,
	resumeGatherStuds: number,
	nearBraceDistance: number,
	nearBraceBlendSeconds: number,
	nearBracePitchDegrees: number,
	nearBraceForwardStuds: number,
	nearBraceShoulderDegrees: number,
	contactFollowThroughSeconds: number,
	contactRepeatCooldownSeconds: number,
	contactPeakFraction: number,
	contactGaitSuppression: number,
	contactDriveStuds: number,
	contactPitchDegrees: number,
	contactShoulderDegrees: number,
	-- FOLDING THROUGH A GAP. Every one of these is a pose, never a rule: the authoritative root is
	-- resized by server/StoneWardenSystem/StoneWardenSqueeze and these only draw the body doing it.
	-- `squeezeRootLiftStuds` is the one that is not free — it cancels the drop the smaller root takes
	-- so the soles stay on the floor, and is derived from the two root heights in `squeeze` below.
	squeezeBlendSeconds: number,
	squeezeCrouchStuds: number,
	squeezePitchDegrees: number,
	squeezeTurnDegrees: number,
	squeezeShoulderDegrees: number,
	squeezeArmTuckDegrees: number,
	squeezeElbowDegrees: number,
	squeezeHeadDuckDegrees: number,
	squeezeHipDegrees: number,
	squeezeKneeDegrees: number,
	squeezeStrainDegrees: number,
	squeezeStrainFrequency: number,
	-- A standing Warden is never completely still. Slow, and far below the gait, so it reads as mass
	-- settling rather than as a second animation.
	idleBreathSeconds: number,
	idleBreathStuds: number,
	idleSwayDegrees: number,
	-- The wake. The arm that breaks the seal reaches this far before the body follows it out.
	emergenceBreachShoulderDegrees: number,
	emergenceBreachElbowDegrees: number,
	emergenceHeadDuckDegrees: number,
	emergenceRoarPitchDegrees: number,
	emergenceRoarShoulderDegrees: number,
	emergenceRoarSeconds: number,
	-- Overshoot on the last of the rise, so full height arrives as a slam rather than as a stop.
	emergenceSettleStuds: number,
	emergenceSettleSeconds: number,
}

export type StoneWardenConfig = {
	enabled: boolean,
	minGlobalDepth: number,
	spawnChancePerEligibleFloor: number,
	roomModuleId: string,
	roomCeilingHeight: number,
	layout: {
		wallSetback: number,
		waxStandoff: number,
		counterLateral: number,
		counterStandoff: number,
		collapseDripstones: { CollapseDripstoneLayout },
	},
	emergence: {
		wallDepth: number,
		rise: number,
	},
	counterDripstoneVariantId: string,
	encounterClearance: number,
	fixtureFootprint: number,
	traySize: Vector3,
	waxPieceOffsets: { Vector3 },
	waxPieceSize: Vector3,
	waxSurfaceClearance: number,
	waxColor: Color3,
	pickupRange: number,
	pickupHoldSeconds: number,
	pickupValidationSlack: number,
	pickupActionText: string,
	pickupObjectText: string,
	collapseTriggerRadius: number,
	collapsePresentationRadius: number,
	collapseShakeSeconds: number,
	collapseShakeFrequency: number,
	collapseShakeStuds: number,
	collapseShakeDegrees: number,
	presentationEmitterLifetime: number,
	walkSpeed: number,
	emergenceSeconds: number,
	pathRefreshSeconds: number,
	stationaryPauseSeconds: number,
	motion: StoneWardenMotionConfig,
	squeeze: WardenSqueezeConfig,
	emergenceStages: WardenEmergenceStages,
	presence: WardenPresenceConfig,
	-- Keyed by Config/CaveFamilies id. An absent or unknown family falls through to `defaultAccent`,
	-- which is Stone's — the same fallback rule the rock palette already uses.
	accents: { [string]: WardenAccent },
	defaultAccent: WardenAccent,
}

local StoneWarden: StoneWardenConfig = {
	enabled = true,
	minGlobalDepth = 4,
	spawnChancePerEligibleFloor = 0.45,
	roomModuleId = "WardenDen",
	roomCeilingHeight = 28,
	-- One doorless wall anchors the dormant body, the guarded wax, the reusable counter crown, and
	-- three extra formations that commit when all wax has been taken. The counter is kept separate so
	-- the opening collapse never spends the player's only way to stun the Warden.
	layout = {
		wallSetback = 5,
		waxStandoff = 9,
		counterLateral = 14,
		counterStandoff = 6,
		collapseDripstones = {
			{ lateral = -11, standoff = 10, variantId = "Needle" },
			{ lateral = 0, standoff = -7, variantId = "Fork" },
			{ lateral = 11, standoff = -1, variantId = "Needle" },
		},
	},
	emergence = {
		wallDepth = 4.5,
		rise = 2.5,
	},
	counterDripstoneVariantId = "Hammer",
	encounterClearance = 9,
	-- Three non-glowing pieces sit on one low stone tray in the open floor in front of the wall.
	-- Each has its own server-owned prompt; the third collection commits the encounter.
	fixtureFootprint = 5,
	traySize = Vector3.new(4.8, 0.5, 3.8),
	waxPieceOffsets = {
		Vector3.new(-1.25, 0, -0.35),
		Vector3.new(0.05, 0, 0.45),
		Vector3.new(1.3, 0, -0.2),
	},
	waxPieceSize = Vector3.new(0.9, 0.62, 0.72),
	waxSurfaceClearance = 0.08,
	waxColor = Color3.fromRGB(219, 184, 116),
	pickupRange = 7,
	pickupHoldSeconds = 0.2,
	pickupValidationSlack = 2,
	pickupActionText = "Take Wax",
	pickupObjectText = "Warden Wax",
	-- The collapse is presentation plus ordinary server-owned dripstone warnings/falls. It never
	-- shortens a formation's reaction window and never replaces the Heavy Crown counter.
	collapseTriggerRadius = 1.5,
	collapsePresentationRadius = 48,
	collapseShakeSeconds = 0.9,
	collapseShakeFrequency = 13,
	collapseShakeStuds = 0.13,
	collapseShakeDegrees = 1.4,
	presentationEmitterLifetime = 3,
	-- Fifteen percent above the previous 8-stud pursuit speed.
	walkSpeed = 9.2,
	emergenceSeconds = 4,
	pathRefreshSeconds = 0.3,
	stationaryPauseSeconds = 3,
	-- Presentation only. The invisible HumanoidRootPart remains the authoritative movement, collision,
	-- touch-kill, and pathfinding body; these values pose the Motor6D stone rig around it.
	motion = {
		maxDeltaSeconds = 1 / 20,
		gaitCycleSeconds = 1.18,
		gaitReferenceSpeed = 9.2,
		minimumGaitCadenceScale = 0.32,
		maximumGaitCadenceScale = 1.15,
		gaitBlendSeconds = 0.24,
		bodyBobStuds = 0.22,
		hipRollDegrees = 4.5,
		legSwingDegrees = 11,
		kneeLiftDegrees = 8,
		armSwingDegrees = 15,
		armPhaseLagFraction = 0.08,
		headLagSeconds = 0.32,
		headLagDegrees = 12,
		-- Shoulders finish breaking their wall-seal before the authoritative root finishes clearing it.
		emergenceUnsealFraction = 0.72,
		emergenceCrouchStuds = 1.05,
		emergenceShoulderDegrees = 34,
		stunSettleSeconds = 0.42,
		stunSagStuds = 1.1,
		stunPitchDegrees = 13,
		-- This gather is drawn inside the existing dripstone stun window; it never extends that window.
		resumeGatherSeconds = 0.8,
		resumeGatherStuds = 0.28,
		nearBraceDistance = 9,
		nearBraceBlendSeconds = 0.2,
		nearBracePitchDegrees = 8,
		nearBraceForwardStuds = 0.24,
		nearBraceShoulderDegrees = 18,
		-- Contact is already fatal when this begins. This is follow-through, never a dodge wind-up.
		contactFollowThroughSeconds = 0.7,
		-- Normally the first contact ends the victim's run. Developer-room invulnerability deliberately
		-- keeps that candle alive, so repeated physics touches still need one bounded presentation beat.
		contactRepeatCooldownSeconds = 0.7,
		contactPeakFraction = 0.3,
		contactGaitSuppression = 0.82,
		contactDriveStuds = 0.5,
		contactPitchDegrees = 15,
		contactShoulderDegrees = 30,
		-- Folded: down onto bent knees, hunched hard forward, shoulders rolled in and turned so the
		-- widest part of the body goes through an opening edge-on, head tucked under the brow. The
		-- strain wobble is what keeps it from looking like a smaller Warden — stone does not fit
		-- through a hole, it grinds through one.
		squeezeBlendSeconds = 0.26,
		squeezeCrouchStuds = 1.75,
		squeezePitchDegrees = 26,
		squeezeTurnDegrees = 17,
		squeezeShoulderDegrees = 40,
		squeezeArmTuckDegrees = 34,
		squeezeElbowDegrees = 62,
		squeezeHeadDuckDegrees = 22,
		squeezeHipDegrees = 24,
		squeezeKneeDegrees = 44,
		squeezeStrainDegrees = 1.9,
		squeezeStrainFrequency = 7.5,
		idleBreathSeconds = 4.4,
		idleBreathStuds = 0.11,
		idleSwayDegrees = 1.1,
		emergenceBreachShoulderDegrees = 58,
		emergenceBreachElbowDegrees = 44,
		emergenceHeadDuckDegrees = 30,
		emergenceRoarPitchDegrees = 14,
		emergenceRoarShoulderDegrees = 26,
		emergenceRoarSeconds = 0.75,
		emergenceSettleStuds = 0.55,
		emergenceSettleSeconds = 0.5,
	},
	-- IT HAS TO GET THROUGH THE DOOR.
	--
	-- Config/Floors.geometry rolls every doorway between 8 and 13 studs tall, and the Warden's
	-- authoritative root is 12 studs of it. So most of the openings on a floor were physically too
	-- small for the body, AND the pursuit asked PathfindingService for a 12-stud agent, which refuses
	-- to plan through any of them. A Warden that lost line of sight through a low arch simply stopped
	-- being a threat — it stood on the far side of a hole it could see the player through.
	--
	-- Folding fixes both halves. The root shrinks to something that clears the tightest opening the
	-- generator can cut, the agent is sized to the FOLDED body so a plan through that opening exists
	-- at all, and the animator draws the body forcing itself through. The cost is `walkSpeedMultiplier`
	-- while folded, which is the only thing this system takes off the Warden.
	squeeze = {
		enabled = true,
		standingHeight = 12,
		standingWidth = 6,
		-- 0.8 studs under the shortest opening the generator can cut, so the tightest crevice on the
		-- worst-rolled floor is still passable rather than merely usually passable.
		squeezedHeight = 7.2,
		squeezedWidth = 3.4,
		-- Measured from the ground the Warden is standing on. Slightly over the standing height so it
		-- commits to folding a beat BEFORE its head would hit, rather than after.
		heightClearance = 0.85,
		widthClearance = 0.9,
		-- One sample at the body, one at the mouth of the opening it is walking at, one past it.
		probeDistances = { 2.5, 7, 12 },
		probeSeconds = 0.12,
		releaseGraceSeconds = 0.65,
		enterSeconds = 0.4,
		exitSeconds = 0.55,
		walkSpeedMultiplier = 0.82,
		-- Exactly the folded body's half-width and full height. Larger and the plan would route it
		-- through gaps it cannot fit; smaller and it would plan through gaps it can fit but the probe
		-- would never fold it for, and it would walk into the rock beside the opening.
		agentRadius = 1.7,
		agentHeight = 7.2,
		dustRate = 34,
		grindCueSeconds = 0.85,
	},
	emergenceStages = {
		tremorFraction = 0.18,
		breachFraction = 0.42,
		riseFraction = 0.72,
		roarFraction = 0.88,
		dustRate = 55,
		burstParticles = 90,
		beatShake = {
			tremor = { seconds = 1.15, studs = 0.06, degrees = 0.5, frequency = 15 },
			breach = { seconds = 0.55, studs = 0.22, degrees = 1.6, frequency = 19 },
			rise = { seconds = 0.7, studs = 0.16, degrees = 1.2, frequency = 14 },
			roar = { seconds = 1.5, studs = 0.34, degrees = 2.4, frequency = 11 },
		},
	},
	presence = {
		tag = "WickWarden",
		-- Roughly two rooms' worth of warning. The falloff is quadratic, so at half this distance the
		-- floor is only a quarter as loud — the tremor tells you it is CLOSER, not merely present.
		rumbleRadius = 62,
		rumbleStuds = 0.085,
		rumbleDegrees = 0.5,
		rumbleFrequency = 9,
		rumbleMovingBonus = 0.85,
		stepShakeSeconds = 0.34,
		stepShakeStuds = 0.2,
		stepShakeDegrees = 1.1,
		stepShakeFrequency = 21,
		stepAudioRadius = 70,
		stepPresentationRadius = 78,
		loopRadius = 58,
		loopCueName = "WardenPresence",
	},
	-- Three caves, three lights inside the same rock. Stone is a banked ember, Moss is the cold
	-- bioluminescence its cave is already full of, Ice is the deep blue of pressure in old glacier.
	accents = {
		STONE = {
			eyeColor = Color3.fromRGB(255, 138, 58),
			eyeLightBrightness = 0.55,
			eyeLightRange = 11,
			coreColor = Color3.fromRGB(168, 66, 22),
			coreSeamCount = 6,
		},
		MOSS = {
			eyeColor = Color3.fromRGB(150, 255, 150),
			eyeLightBrightness = 0.5,
			eyeLightRange = 10,
			coreColor = Color3.fromRGB(74, 158, 84),
			coreSeamCount = 7,
		},
		ICE = {
			eyeColor = Color3.fromRGB(146, 226, 255),
			eyeLightBrightness = 0.6,
			eyeLightRange = 12,
			coreColor = Color3.fromRGB(58, 126, 190),
			coreSeamCount = 5,
		},
	},
	defaultAccent = {
		eyeColor = Color3.fromRGB(255, 138, 58),
		eyeLightBrightness = 0.55,
		eyeLightRange = 11,
		coreColor = Color3.fromRGB(168, 66, 22),
		coreSeamCount = 6,
	},
}

return StoneWarden

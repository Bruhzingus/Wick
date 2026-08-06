--!strict
-- Client-only feel and readability tuning. None of these values affect authoritative game rules:
-- they control warnings, cosmetic flame motion, debug visibility, and the shared input legend.

local Types = require(script.Parent.Parent.Types)

export type ToolControl = {
	toolId: Types.ToolId,
	keyCode: Enum.KeyCode,
	keyLabel: string,
	touchPosition: UDim2,
	audioCue: string,
}

export type AmbientSurface = "Wall" | "Ceiling" | "Ground"

export type AmbientSoundEvent = {
	id: string,
	cueName: string,
	weight: number,
	surface: AmbientSurface,
	allowWater: boolean?,
	minDistance: number,
	maxDistance: number,
	burstsMin: number,
	burstsMax: number,
	burstGapMinSeconds: number,
	burstGapMaxSeconds: number,
	pitchMin: number,
	pitchMax: number,
	durationSeconds: number,
}

export type FeelConfig = {
	lowWax: {
		enabled: boolean,
		threshold: number,
		urgentThreshold: number,
		pulseFrequencyHz: number,
		normalColor: Color3,
		snuffedColor: Color3,
		warningColor: Color3,
		urgentColor: Color3,
		minColorBlend: number,
		maxColorBlend: number,
	},
	waxBarFlame: {
		flickerHz: number,
		swayHz: number,
		sizeBase: number,
		sizeHeatScale: number,
		sizeFlickerBase: number,
		sizeFlickerScale: number,
		leanDegrees: number,
		leanInnerMultiplier: number,
		swayInnerPositionScale: number,
		swayCorePositionScale: number,
		flickerCorePositionScale: number,
		hotShiftScale: number,
		lowActiveOuterBlend: number,
		haloBase: number,
		haloHeatScale: number,
		haloFlickerScale: number,
		haloOuterOffset: number,
		haloOuterMin: number,
		haloOuterMax: number,
		haloInnerMin: number,
		haloInnerMax: number,
		smokeDurationSeconds: number,
		smokeTransparencyBase: number,
		smokeTransparencyScale: number,
		smokeNoiseFrequencyHz: number,
		smokeNoisePositionScale: number,
		smokePositionDropScale: number,
	},
	sprintFeedback: {
		enabled: boolean,
		activeAttribute: string,
		normalFov: number,
		sprintFov: number,
		transitionSeconds: number,
		movementThreshold: number,
		acceptedSpeedMargin: number,
		vignetteColor: Color3,
		vignetteWidthScale: number,
		vignetteMaxOpacity: number,
		vignettePulseOpacity: number,
		vignettePulseFrequencyHz: number,
		heatShimmerPixels: number,
		heatFrequencyHz: number,
		cameraSwayStuds: number,
		cameraBobStuds: number,
		cameraRollDegrees: number,
		cameraFrequencyHz: number,
		streakColor: Color3,
		streakCountPerSide: number,
		streakWidthPixels: number,
		streakLengthScale: number,
		streakInsetScale: number,
		streakMaxOpacity: number,
		streakTravelScale: number,
		streakAngleDegrees: number,
	},
	basinVision: {
		edgeColor: Color3,
		edgeWidthScale: number,
	},
	waterWarning: {
		enabled: boolean,
		tintColor: Color3,
		brightness: number,
		contrast: number,
	},
	dialSnap: {
		enabled: boolean,
		trackColor: Color3,
		flashColor: Color3,
		flashSeconds: number,
	},
	dialInput: {
		sendIntervalSeconds: number,
		serverReconcileDelaySeconds: number,
	},
	threatWarning: {
		enabled: boolean,
		collectionTag: string,
		radius: number,
		scanIntervalSeconds: number,
	},
	-- YOUR OWN FOOTSTEPS. Paced from measured ground speed rather than a fixed timer, so a step lands
	-- when a step would land and a body that has stopped is silent.
	footsteps: {
		enabled: boolean,
		-- Studs/sec below which the body counts as standing still. Above the tiny drift a grounded
		-- character reports while doing nothing, so idling never ticks.
		minimumSpeed: number,
		-- Seconds between footfalls at walk and at run. Interpolated by measured speed, so Cup-slowed
		-- movement is genuinely slower underfoot and a sprint is genuinely faster — the cadence is a
		-- readable signal about your own state, not decoration.
		walkIntervalSeconds: number,
		runIntervalSeconds: number,
		-- Random +/- fraction applied to each interval. Repeated identical footfalls turn into a
		-- metronome faster than any other sound in a game, and a metronome is the opposite of dread.
		intervalJitter: number,
		-- Playback level at walk and at run. Both stay well under the creature-audio layer: your own
		-- steps must never mask the thing you are straining to hear.
		quietVolume: number,
		loudVolume: number,
		-- How far down to probe for what you are standing on, and how deep the water has to be before
		-- the wading cue takes over from the family's own surface.
		surfaceProbeDistance: number,
		waterDepthThreshold: number,
	},
	ambientRockfall: {
		enabled: boolean,
		wallSearchAttempts: number,
		wallSearchMinDistance: number,
		wallSearchMaxDistance: number,
		wallNormalMaxY: number,
		wallInset: number,
		groundProbeHeight: number,
		groundProbeDistance: number,
		groundNormalMinY: number,
		rockMinSize: number,
		rockMaxSize: number,
		fallMinHeight: number,
		fallMaxHeight: number,
		fallSeconds: number,
		rollMinDistance: number,
		rollMaxDistance: number,
		rollSeconds: number,
		lingerSeconds: number,
	},
	ambientWaterDrip: {
		enabled: boolean,
		sourceSearchAttempts: number,
		sourceMinDistance: number,
		sourceMaxDistance: number,
		ceilingSearchHeight: number,
		ceilingNormalMaxY: number,
		sourceInset: number,
		emitterLifetimeSeconds: number,
	},
	ambientCave: {
		enabled: boolean,
		initialDelayMinSeconds: number,
		initialDelayMaxSeconds: number,
		refractoryMinSeconds: number,
		refractoryMaxSeconds: number,
		meanSilenceSeconds: number,
		maxSilenceSeconds: number,
		retryDelaySeconds: number,
		silentWeight: number,
		rockfallWeight: number,
		waterDripWeight: number,
		recentFamilyCount: number,
		focusQuietSeconds: number,
		emitterSearchAttempts: number,
		maxForwardDot: number,
		wallNormalMaxY: number,
		ceilingNormalMaxY: number,
		groundNormalMinY: number,
		sourceInset: number,
		ceilingProbeDistance: number,
		groundProbeHeight: number,
		groundProbeDistance: number,
		emitterSize: number,
		emitterLifetimeSeconds: number,
		soundEvents: { AmbientSoundEvent },
	},
	tutorialHints: {
		enabled: boolean,
		maxDepth: number,
		displaySeconds: number,
		fadeSeconds: number,
		serverCooldownSeconds: number,
		repeatCooldownSeconds: number,
		minimumGapSeconds: number,
		displayOrder: number,
		position: UDim2,
		size: UDim2,
		maxTextSize: number,
		messages: { [string]: string },
	},
	itemHints: {
		enabled: boolean,
		messages: { [string]: string },
	},
	deathHints: {
		enabled: boolean,
		messages: { [string]: string },
	},
	debug: {
		showThreatLabels: boolean,
		showDeathDebug: boolean,
	},
	controls: {
		signalBellKey: Enum.KeyCode,
		spectatorFollowKey: Enum.KeyCode,
		spectatorFollowKeyLabel: string,
		tools: { ToolControl },
	},
	hotbar: {
		enabled: boolean,
		displayOrder: number,
		desktopPosition: UDim2,
		desktopSize: UDim2,
		touchPosition: UDim2,
		touchSize: UDim2,
		backgroundColor: Color3,
		backgroundTransparency: number,
		chipColor: Color3,
		chipTransparency: number,
		activeChipColor: Color3,
		activeStrokeColor: Color3,
		acceptedColor: Color3,
		deniedColor: Color3,
		keyColor: Color3,
		textColor: Color3,
		strokeColor: Color3,
		strokeTransparency: number,
		cooldownTrackColor: Color3,
		cooldownTrackTransparency: number,
		cooldownFillColor: Color3,
		cooldownFillTransparency: number,
		cooldownTextColor: Color3,
		cooldownTextStrokeTransparency: number,
		cooldownBarHeightScale: number,
		cooldownLabelPosition: UDim2,
		cooldownLabelSize: UDim2,
		touchCooldownTrackPosition: UDim2,
		touchCooldownTrackSize: UDim2,
		touchCooldownLabelPosition: UDim2,
		touchCooldownLabelSize: UDim2,
		cooldownMinimumDisplaySeconds: number,
		cooldownDisplayStepSeconds: number,
		cooldownSecondsFormat: string,
		pulseSeconds: number,
		pulseScale: number,
		deniedFlashSeconds: number,
		denialTextSeconds: number,
		denialFallbackText: string,
		denialMessages: { [string]: string },
		cornerRadiusPixels: number,
		rowGapPixels: number,
		chipGapPixels: number,
		minTextSize: number,
		maxTextSize: number,
		desktopHeader: string,
		touchHeader: string,
		freeChargeFormat: string,
		activeDisplayFormat: string,
		flareDisplayName: string,
		uncupDisplayName: string,
	},
}

local Feel: FeelConfig = {
	lowWax = {
		enabled = true,
		-- Absolute wax fraction at which the melt line begins pulsing.
		threshold = 0.25,
		urgentThreshold = 0.1,
		pulseFrequencyHz = 1.6,
		normalColor = Color3.fromRGB(235, 225, 200),
		snuffedColor = Color3.fromRGB(120, 115, 105),
		warningColor = Color3.fromRGB(255, 154, 72),
		urgentColor = Color3.fromRGB(255, 72, 48),
		minColorBlend = 0.25,
		maxColorBlend = 0.85,
	},
	-- The wax-bar HUD's cosmetic 2D flame icon. Independent from the 3D candle's
	-- FlameFlicker/CandleLightController signal (a local UI icon, never server-synced), but every
	-- constant it uses still belongs here rather than inline in WaxBar.luau.
	waxBarFlame = {
		flickerHz = 8.5,
		swayHz = 2.1,
		sizeBase = 0.7,
		sizeHeatScale = 0.55,
		sizeFlickerBase = 0.93,
		sizeFlickerScale = 0.14,
		leanDegrees = 6,
		leanInnerMultiplier = 1.15,
		swayInnerPositionScale = 0.05,
		swayCorePositionScale = 0.06,
		flickerCorePositionScale = 0.03,
		hotShiftScale = 0.5,
		lowActiveOuterBlend = 0.4,
		haloBase = 0.62,
		haloHeatScale = 0.24,
		haloFlickerScale = 0.08,
		haloOuterOffset = 0.18,
		haloOuterMin = 0.2,
		haloOuterMax = 0.95,
		haloInnerMin = 0.1,
		haloInnerMax = 0.9,
		smokeDurationSeconds = 1.4,
		smokeTransparencyBase = 0.55,
		smokeTransparencyScale = 0.45,
		smokeNoiseFrequencyHz = 1.5,
		smokeNoisePositionScale = 0.08,
		smokePositionDropScale = 0.5,
	},
	sprintFeedback = {
		enabled = true,
		-- Restrained first-person urgency: the candle strains rather than receiving a power boost.
		activeAttribute = "WickSprintActive",
		normalFov = 74,
		sprintFov = 85,
		transitionSeconds = 0.4,
		movementThreshold = 0.1,
		-- Require the replicated server-owned WalkSpeed to exceed the slow-movement threshold before
		-- rendering the default run strain.
		acceptedSpeedMargin = 0.5,
		vignetteColor = Color3.fromRGB(8, 5, 4),
		vignetteWidthScale = 0.17,
		vignetteMaxOpacity = 0.16,
		vignettePulseOpacity = 0.025,
		vignettePulseFrequencyHz = 2.2,
		heatShimmerPixels = 2,
		heatFrequencyHz = 5.5,
		cameraSwayStuds = 0.018,
		cameraBobStuds = 0.022,
		cameraRollDegrees = 0.22,
		cameraFrequencyHz = 5.8,
		streakColor = Color3.fromRGB(138, 100, 70),
		streakCountPerSide = 4,
		streakWidthPixels = 2,
		streakLengthScale = 0.075,
		streakInsetScale = 0.045,
		streakMaxOpacity = 0.055,
		streakTravelScale = 0.025,
		streakAngleDegrees = 7,
	},
	basinVision = {
		edgeColor = Color3.fromRGB(2, 2, 4),
		edgeWidthScale = 0.24,
	},
	waterWarning = {
		enabled = true,
		tintColor = Color3.fromRGB(185, 215, 235),
		brightness = -0.035,
		contrast = 0.05,
	},
	dialSnap = {
		enabled = true,
		trackColor = Color3.fromRGB(30, 28, 32),
		flashColor = Color3.fromRGB(255, 180, 80),
		flashSeconds = 0.12,
	},
	dialInput = {
		-- Keep sustained drag traffic below Security.SetBurnRate (8/s), leaving room for release.
		sendIntervalSeconds = 0.15,
		-- Do not let an in-flight StateSync overwrite a just-sent scroll/drag value.
		serverReconcileDelaySeconds = 0.35,
	},
	threatWarning = {
		enabled = true,
		collectionTag = "WickThreat",
		radius = 30,
		scanIntervalSeconds = 0.25,
	},
	-- Rare, client-only cave movement. It has no hitbox or gameplay consequence: a small piece of
	-- the existing slate dressing drops from a real nearby wall, rolls along the sampled floor, and
	-- vanishes once the sound has settled.
	footsteps = {
		enabled = true,
		minimumSpeed = 1.5,
		-- Config/Movement: walk is 8 studs/s and run is 16. A step every 0.52 s at a walk and every
		-- 0.33 s at a run is roughly a human stride at those speeds — fast enough to feel like moving,
		-- slow enough that it never becomes a texture.
		walkIntervalSeconds = 0.52,
		runIntervalSeconds = 0.33,
		intervalJitter = 0.14,
		-- Deliberately quiet. This layer exists to give the player a body, not to fill the mix: it sits
		-- under the creature locomotion a player is straining to hear, because the moment your own feet
		-- mask an approaching crawler the audio has started working against the game.
		-- Both endpoints are 30% below the prior band, preserving the walk-to-run weight read.
		quietVolume = 0.238,
		loudVolume = 0.595,
		surfaceProbeDistance = 8,
		-- Ankle-deep. Below this you are on a damp shore and still hear the cave's own floor; at or above
		-- it you are wading, and wading is costing you wax.
		waterDepthThreshold = 0.35,
	},
	ambientRockfall = {
		enabled = true,
		wallSearchAttempts = 7,
		wallSearchMinDistance = 10,
		wallSearchMaxDistance = 44,
		wallNormalMaxY = 0.35,
		wallInset = 0.45,
		groundProbeHeight = 9.5,
		groundProbeDistance = 22,
		groundNormalMinY = 0.45,
		rockMinSize = 0.6,
		rockMaxSize = 1.1,
		fallMinHeight = 3.2,
		fallMaxHeight = 5.8,
		fallSeconds = 0.28,
		rollMinDistance = 2.5,
		rollMaxDistance = 5.5,
		rollSeconds = 1.35,
		lingerSeconds = 0.45,
	},
	ambientWaterDrip = {
		enabled = true,
		sourceSearchAttempts = 6,
		sourceMinDistance = 8,
		sourceMaxDistance = 26,
		ceilingSearchHeight = 34,
		ceilingNormalMaxY = -0.45,
		sourceInset = 0.15,
		emitterLifetimeSeconds = 2,
	},
	-- One director owns ALL harmless cave punctuation: the existing loose rock and water drip plus
	-- eight shared natural sound families and two family-exclusive voices. A refractory floor followed
	-- by an exponential wait creates quiet valleys and occasional loose clusters without settling into
	-- a recognizable metronome. The lower-gain ambience bus lets this clock speak more often without
	-- filling the mix.
	-- `silentWeight` is an authored non-event: sometimes the director spends its turn on silence.
	ambientCave = {
		enabled = true,
		initialDelayMinSeconds = 28,
		initialDelayMaxSeconds = 56,
		refractoryMinSeconds = 22,
		refractoryMaxSeconds = 32,
		meanSilenceSeconds = 48,
		maxSilenceSeconds = 150,
		retryDelaySeconds = 12,
		silentWeight = 18,
		rockfallWeight = 7,
		waterDripWeight = 10,
		recentFamilyCount = 2,
		-- Focus-bus cues are threats, hazards, tools, and mining. Ambience gives those sounds a clean
		-- window instead of landing a harmless groan on top of information the player must trust.
		focusQuietSeconds = 11,
		emitterSearchAttempts = 9,
		-- Do not always put a scare directly behind the camera, but keep it out of the central aim
		-- cone where a sound-only event would feel disconnected from an empty visible wall.
		maxForwardDot = 0.78,
		wallNormalMaxY = 0.42,
		ceilingNormalMaxY = -0.42,
		groundNormalMinY = 0.46,
		sourceInset = 0.22,
		ceilingProbeDistance = 40,
		groundProbeHeight = 12,
		groundProbeDistance = 28,
		emitterSize = 0.05,
		emitterLifetimeSeconds = 14,
		soundEvents = {
			{
				id = "StrataStrain",
				cueName = "CaveStrataStrain",
				weight = 9,
				surface = "Wall",
				minDistance = 24,
				maxDistance = 52,
				burstsMin = 1,
				burstsMax = 1,
				burstGapMinSeconds = 0,
				burstGapMaxSeconds = 0,
				pitchMin = 0.94,
				pitchMax = 1.04,
				durationSeconds = 4.4,
			},
			{
				id = "FissureBreath",
				cueName = "CaveFissureBreath",
				weight = 18,
				surface = "Wall",
				minDistance = 18,
				maxDistance = 46,
				burstsMin = 1,
				burstsMax = 1,
				burstGapMinSeconds = 0,
				burstGapMaxSeconds = 0,
				pitchMin = 0.96,
				pitchMax = 1.04,
				durationSeconds = 6.5,
			},
			{
				id = "CalciteTicks",
				cueName = "CaveCalciteTick",
				weight = 20,
				surface = "Ceiling",
				minDistance = 14,
				maxDistance = 38,
				burstsMin = 1,
				burstsMax = 3,
				burstGapMinSeconds = 0.42,
				burstGapMaxSeconds = 1.35,
				pitchMin = 0.9,
				pitchMax = 1.1,
				durationSeconds = 4.8,
			},
			{
				id = "HiddenWaterPulse",
				cueName = "CaveHiddenWater",
				weight = 15,
				surface = "Ground",
				-- This is the only family allowed to anchor to a Terrain water surface. Gravel and
				-- falling stone must always resolve against solid cave geometry.
				allowWater = true,
				minDistance = 22,
				maxDistance = 55,
				burstsMin = 1,
				burstsMax = 1,
				burstGapMinSeconds = 0,
				burstGapMaxSeconds = 0,
				pitchMin = 0.96,
				pitchMax = 1.04,
				durationSeconds = 5.5,
			},
			{
				id = "GravelCreep",
				cueName = "CaveGravelCreep",
				weight = 24,
				surface = "Ground",
				minDistance = 12,
				maxDistance = 34,
				burstsMin = 1,
				burstsMax = 1,
				burstGapMinSeconds = 0,
				burstGapMaxSeconds = 0,
				pitchMin = 0.96,
				pitchMax = 1.06,
				durationSeconds = 3,
			},
			{
				-- Farther than the visible loose-rock presentation, so it gives depth without impersonating
				-- a falling hazard.
				id = "DistantSettle",
				cueName = "CaveDistantSettle",
				weight = 12,
				surface = "Wall",
				minDistance = 30,
				maxDistance = 64,
				burstsMin = 1,
				burstsMax = 2,
				burstGapMinSeconds = 0.6,
				burstGapMaxSeconds = 1.6,
				pitchMin = 0.94,
				pitchMax = 1.08,
				durationSeconds = 3.2,
			},
			{
				-- A small current through a side wall. FissureBreath still owns the broad pressure movement
				-- of a whole cavern.
				id = "ColdDraft",
				cueName = "CaveColdDraft",
				weight = 11,
				surface = "Wall",
				minDistance = 16,
				maxDistance = 48,
				burstsMin = 1,
				burstsMax = 1,
				burstGapMinSeconds = 0,
				burstGapMaxSeconds = 0,
				pitchMin = 0.94,
				pitchMax = 1.06,
				durationSeconds = 5.8,
			},
			{
				-- Several small roof drops from a real ceiling, with no water hazard or noise event.
				id = "DripCluster",
				cueName = "CaveDripCluster",
				weight = 14,
				surface = "Ceiling",
				minDistance = 8,
				maxDistance = 30,
				burstsMin = 2,
				burstsMax = 4,
				burstGapMinSeconds = 0.46,
				burstGapMaxSeconds = 1.25,
				pitchMin = 0.92,
				pitchMax = 1.08,
				durationSeconds = 5.2,
			},
			-- THE TWO FAMILY-EXCLUSIVE EVENTS. Every row in this list is authored family-agnostically —
			-- the WEIGHT below is what a cave would roll if every family treated it the same — and
			-- Config/CaveFamilies.ambience is what actually decides. These two are weighted to zero in
			-- two of the three families, which is how a cave gets a sound the others simply never make.
			--
			-- A NEW ROW HERE IS NOT OPTIONAL FOR THE FAMILIES. Logic/CaveFamilyRules.validate requires
			-- every family to answer for every id in this list, so adding an event without weighting it
			-- fails the suite rather than quietly appearing in all three caves at full rate.
			{
				-- MOSS. Water running down a wall a few studs off, close enough to place by ear. Ranged
				-- deliberately tight and multi-burst: it is meant to be a thing happening beside you in a
				-- wet cave, not another distant pulse.
				id = "SeepRun",
				cueName = "CaveSeepRun",
				weight = 12,
				surface = "Wall",
				minDistance = 8,
				maxDistance = 26,
				burstsMin = 1,
				burstsMax = 2,
				burstGapMinSeconds = 1.1,
				burstGapMaxSeconds = 2.4,
				pitchMin = 0.96,
				pitchMax = 1.08,
				durationSeconds = 6,
			},
			{
				-- ICE. The only CEILING-surfaced event in the list, and the reason it is worth its own
				-- row rather than a reweighted strata strain: in the family whose signature pressure hangs
				-- overhead, the cave's own voice should come from where the danger is. Long-ranged to
				-- match Ice's open halls, single-burst because a groan is one continuous thing.
				id = "GlacierGroan",
				cueName = "CaveGlacierGroan",
				weight = 12,
				surface = "Ceiling",
				minDistance = 20,
				maxDistance = 58,
				burstsMin = 1,
				burstsMax = 1,
				burstGapMinSeconds = 0,
				burstGapMaxSeconds = 0,
				pitchMin = 0.92,
				pitchMax = 1.02,
				durationSeconds = 7.5,
			},
		},
	},
	tutorialHints = {
		enabled = true,
		maxDepth = 3,
		displaySeconds = 5,
		fadeSeconds = 0.35,
		-- Server cap prevents continuous-contact threats from generating remote traffic every tick.
		serverCooldownSeconds = 3,
		repeatCooldownSeconds = 12,
		minimumGapSeconds = 2.5,
		displayOrder = 9,
		position = UDim2.fromScale(0.5, 0.79),
		size = UDim2.fromScale(0.72, 0.07),
		maxTextSize = 22,
		messages = {
			-- KEYED BY THREAT ID, one line per creature. These used to be seven near-identical lines
			-- for three bodies, which is how it became obvious the roster was carrying rows the player
			-- was never shown: the text itself had already collapsed them into "a DarkCrawler" and "a
			-- cave moth" because there was nothing else honest to call them.
			DarkCrawler = "A DarkCrawler is draining your wax. Use FLARE to blind it and drive it off!",
			-- Says both halves of what a moth does, because contact now costs wax AND, past the early
			-- floors, eventually takes the flame if you never break away (Config/Threats.Moth). Names
			-- CUP explicitly rather than the vague "lower your light": every other row here names the
			-- actual tool (FLARE, DECOY), and the raised dial floor (Config/Light.minBrightness) means
			-- the ordinary dial alone no longer reads as dark enough to lose a moth's interest.
			Moth = "A cave moth is feeding on your flame. CUP your flame or DECOY it away before it smothers you!",
			VoidFly = "A VoidFly is diving at you. Burn it off with FLARE or stay close to a teammate!",
			-- THE THREE SIGNATURE CREATURES, one per cave. Each line names the counterplay that is
			-- SPECIFIC to that creature, because in all three cases the reflex a player has already built
			-- is the wrong one: you cannot out-brighten the Listener, you cannot outrun the Knotwalker by
			-- going the way you were going, and there is nothing to do about the Calver itself at all.
			-- Says MINING specifically, not "stop moving". Walking is silent to the cave: Config/Sound's
			-- emitter list is mining, falling stone and the signal bell, and nothing else. An earlier
			-- draft of this line told players to stop moving, which would have had them standing still
			-- waiting out a creature that could not hear them in the first place.
			Listener = "A Cave Listener hunts by sound, not light. Stop mining and let it lose you; brightness will not help!",
			Knotwalker = "A Knotwalker is cutting ahead of you. Turn back or take another route; it commits to the way you were going!",
			Calver = "A Calver is striking the ceiling. Get out from under the falling ice, not away from the creature!",
			Water = "Water is dissolving your wax. Climb back onto dry ground!",
			Dripstone = "Falling stone. Look for a fractured black collar and falling dust, then leave its ground before it drops!",
			-- NOT reached through this table's own `sendTutorialHint` gate (AshamedLurkerService fires it
			-- directly): the Lurker never appears before floor 4, past `maxDepth` below, so it could never
			-- earn a slot in the depth-capped path anyway. Fired once ever per player instead, the same
			-- shape as `itemHints`.
			AshamedLurker = "Something unseen grabbed you and took your wax. Don't linger near quiet archways — look away the moment you feel watched.",
		},
	},
	-- FIRST-PICKUP HINTS, keyed by `Config/Loot` id. Shown once per player, EVER — the server records
	-- the sighting on the profile (`Interfaces/Persistence.claimFirstSighting`), so a returning player
	-- is never re-taught something they already know.
	--
	-- WHY THESE ARE NOT `tutorialHints` ROWS. Tutorial hints are capped at `maxDepth` because they
	-- teach the pressures of the first three floors, and a player still meeting those on floor 20 is
	-- not being taught, they are being nagged. An item hint is the opposite shape: it fires the first
	-- time a specific thing is picked up, which for a Candle Sleeve cannot happen before floor 5 and
	-- on Stone cannot happen before floor 15. Sharing the depth cap would have made the rarest item in
	-- the game the only one that could never explain itself.
	--
	-- Each line says what the item DOES and, where it matters, the condition attached to it. The short
	-- numeric readout LootService already sends ("Life Wax: burn rate down 3% (2 held)") is a
	-- different message in a different place; this is the one that explains the mechanic.
	itemHints = {
		enabled = true,
		messages = {
			LifeWax = "LIFE WAX. Your candle burns 3% slower. It stacks, and it lasts the whole run.",
			BrightWax = "BRIGHT WAX. 5% more light for the whole run. It stacks. So does what sees you.",
			ExtraWicks = "EXTRA WICKS. 25% brighter for a few minutes, and it costs no extra wax. Cupping still hides you completely.",
			FrozenWax = "FROZEN WAX. It only melts back into your candle while you burn at MAXIMUM brightness. Push the dial or carry it for nothing.",
			CandleSleeve = "CANDLE SLEEVE. Cardboard around your candle: 40% less damage for the next five hits, then it tears.",
			FlareCharge = "PREPARED FLARE. One free flare. It costs no wax when you use it.",
			DecoyCharge = "PREPARED DECOY. One free decoy. It costs no wax when you use it.",
			Match = "MATCH. Alone, you can relight yourself once after being snuffed. It does nothing if a teammate is alive.",
		},
	},
	-- SHOWN ON THE RESULTS SCREEN AFTER A DEATH, keyed by `DeathService`'s `sourceId` (falling back to
	-- the raw `deathCause` — "BurnOut" — when no single actor caused it). Deliberately separate copy
	-- from `tutorialHints`/`itemHints` above: those teach in the moment, in second person, present
	-- tense ("CUP your flame"); these are retrospective ("next time, ..."), written to be read once,
	-- after the fact, by a player who just lost the run to exactly this. No `enabled` toggle needed
	-- beyond the shared one below — unlike the in-run hints this never repeats or nags, so there is
	-- nothing here that ongoing play could need to suppress.
	deathHints = {
		enabled = true,
		messages = {
			DarkCrawler = "A DarkCrawler took your flame. Next time, back off and hit it with FLARE the instant it starts draining you — don't let it stay close.",
			Moth = "A cave moth smothered your flame. Next time, CUP your flame or DECOY it away the moment it lands on you.",
			VoidFly = "A VoidFly took your flame. Next time, burn at max brightness or stay near a teammate under a dark ceiling patch.",
			Listener = "A Cave Listener took your flame. Next time, stop mining the instant you hear it — it hunts by sound, and more light will not save you.",
			Knotwalker = "A Knotwalker took your flame. Next time, turn back the moment you spot one — it commits to the path you were already on, so change yours.",
			Calver = "A Calver took your flame. Next time, run out from under the falling ice, not away from the creature striking the ceiling.",
			Water = "Water reached your flame. Next time, watch the surface level and stay on dry ground — it kills the instant it reaches your flame's height.",
			Dripstone = "Falling stone took your flame. Next time, watch for a fractured black collar and dust, then clear its ground before it drops.",
			MossFire = "Burning moss took your flame. Next time, back away from a lit cluster instead of pushing through the heat.",
			StoneWarden = "The Warden woke and crushed you. Next time, leave its wax alone, or grab a piece and retreat immediately — it stuns easily but kills instantly once it's up.",
			AshamedLurker = "Something in the dark grabbed you and took your flame. Next time, don't linger near quiet archways, and look away the moment you feel watched.",
			-- Fallback for a plain starvation death with no external actor (ran the dial too hot, too far
			-- from safe ground). Keyed by `deathCause` itself since there is no `sourceId` to look up.
			BurnOut = "Your candle ran dry. Next time, watch your wax meter and dial down before a long stretch without safe ground.",
		},
	},
	debug = {
		-- Keep false for horror/readability playtests. This is intentionally config-gated for grey-box debugging.
		showThreatLabels = false,
		-- When true, the results screen appends the raw death diagnostics (wax/burn/movement) as a
		-- small dim line. Off by default so the shipped end screen reads clean.
		showDeathDebug = false,
	},
	controls = {
		-- The Signal Bell (Config/LampNetwork.bell). Not a tool row: it has no hotbar slot, no cooldown
		-- marker and no threat interaction, so it lives beside the tool list rather than inside it.
		signalBellKey = Enum.KeyCode.Four,
		-- The ghost's only control (Config/Spectator, server/SpectatorService). It lives here beside the
		-- bell rather than in the tool list for the same reason: a spectator has no hotbar slot, no
		-- cooldown marker and no effect on the cave. Deliberately a key the living never use, so nobody
		-- learns a binding that changes meaning when they die.
		spectatorFollowKey = Enum.KeyCode.F,
		spectatorFollowKeyLabel = "F",
		tools = {
			{
				toolId = "Flare",
				keyCode = Enum.KeyCode.One,
				keyLabel = "1",
				touchPosition = UDim2.new(0, 62, 1, -142),
				audioCue = "ToolFlare",
			},
			{
				toolId = "Decoy",
				keyCode = Enum.KeyCode.Two,
				keyLabel = "2",
				touchPosition = UDim2.new(0, 132, 1, -142),
				audioCue = "ToolDecoy",
			},
			{
				toolId = "Cup",
				keyCode = Enum.KeyCode.Three,
				keyLabel = "3",
				touchPosition = UDim2.new(0, 62, 1, -72),
				audioCue = "ToolCup",
			},
		},
	},
	hotbar = {
		enabled = true,
		displayOrder = 8,
		desktopPosition = UDim2.fromScale(0.5, 0.93),
		desktopSize = UDim2.fromScale(0.68, 0.105),
		-- Touch action buttons live along the bottom edges; this compact legend stays above them.
		touchPosition = UDim2.fromScale(0.5, 0.22),
		touchSize = UDim2.fromScale(0.88, 0.12),
		backgroundColor = Color3.fromRGB(12, 11, 14),
		backgroundTransparency = 0.2,
		chipColor = Color3.fromRGB(35, 32, 38),
		chipTransparency = 0.12,
		activeChipColor = Color3.fromRGB(73, 48, 31),
		activeStrokeColor = Color3.fromRGB(255, 154, 66),
		acceptedColor = Color3.fromRGB(112, 67, 35),
		deniedColor = Color3.fromRGB(112, 39, 32),
		keyColor = Color3.fromRGB(255, 180, 80),
		textColor = Color3.fromRGB(232, 226, 215),
		strokeColor = Color3.fromRGB(92, 77, 62),
		strokeTransparency = 0.35,
		cooldownTrackColor = Color3.fromRGB(8, 7, 9),
		cooldownTrackTransparency = 0.08,
		cooldownFillColor = Color3.fromRGB(255, 145, 54),
		cooldownFillTransparency = 0.05,
		cooldownTextColor = Color3.fromRGB(255, 235, 202),
		cooldownTextStrokeTransparency = 0.35,
		cooldownBarHeightScale = 0.2,
		-- The chip timer occupies the desktop key column. The larger touch readout sits directly
		-- above the native action button's mirrored cooldown bar.
		cooldownLabelPosition = UDim2.fromScale(0.03, 0.08),
		cooldownLabelSize = UDim2.fromScale(0.25, 0.64),
		touchCooldownTrackPosition = UDim2.fromScale(0.5, 0.9),
		touchCooldownTrackSize = UDim2.fromScale(0.72, 0.14),
		touchCooldownLabelPosition = UDim2.fromScale(0.15, 0.54),
		touchCooldownLabelSize = UDim2.fromScale(0.7, 0.24),
		-- Keep the bar visible until the authoritative deadline. Displayed tenths round upward so
		-- the HUD never claims an action is ready while a positive remainder still exists.
		cooldownMinimumDisplaySeconds = 0,
		cooldownDisplayStepSeconds = 0.1,
		cooldownSecondsFormat = "%.1fs",
		pulseSeconds = 0.15,
		pulseScale = 1.09,
		deniedFlashSeconds = 0.2,
		denialTextSeconds = 1.1,
		denialFallbackText = "NOT READY",
		denialMessages = {
			Sacrificed = "ABILITY SACRIFICED",
			Cooldown = "WAIT",
			NotLit = "LIGHT YOUR FLAME",
			NotEnoughWax = "NOT ENOUGH WAX",
			Dead = "UNAVAILABLE",
			Unavailable = "UNAVAILABLE",
			InvalidTarget = "AIM AT OPEN GROUND",
		},
		cornerRadiusPixels = 5,
		rowGapPixels = 4,
		chipGapPixels = 5,
		-- The on-screen control legend is read at a glance, mid-run, in the dark. A 9px floor meant a
		-- chip whose label did not fit simply shrank until it was unreadable rather than admitting it
		-- was too narrow; 14 matches the game's shared type floor (client/UITheme.textSize.micro).
		minTextSize = 14,
		maxTextSize = 20,
		desktopHeader = "CONTROLS  ·  WHEEL / RIGHT SLIDER = BRIGHTNESS",
		touchHeader = "TOUCH CONTROLS  ·  RIGHT SLIDER = BRIGHTNESS",
		freeChargeFormat = "%s · %d FREE",
		activeDisplayFormat = "● %s",
		flareDisplayName = "FLARING",
		uncupDisplayName = "UNCUP",
	},
}

return Feel

--!strict
-- Environmental hazard tuning (DESIGN §9). Cheap difficulty: no AI, no models.
-- The candle model's height mapping lives in Config/Character (the water rule reads it there).

local Types = require(script.Parent.Parent.Types)

export type DripstoneVariant = {
	id: string,
	displayName: string,
	weight: number,
	length: number,
	radius: number,
	prongCount: number,
	leanDegrees: number,
	taper: number,
	crownScale: number,
	warningSeconds: number,
	triggerRadius: number,
	impactRadius: number,
	waxLossFraction: number,
}

export type UnstableDripstoneConfig = {
	maxEligibleCeilingHeight: number,
	earlyLinearBase: number,
	earlyLinearStep: number,
	midExponentialBase: number,
	midExponentialGrowth: number,
	deepExponentialBase: number,
	deepExponentialGrowth: number,
	maxHazardousRoomFraction: number,
	maxPerRoomEarly: number,
	maxPerRoomMid: number,
	maxPerRoomDeep: number,
	maxUnstableToHarmlessRatio: number,
	placementAttempts: number,
	minCenterOffset: number,
	maxCenterOffset: number,
	doorwaySafetyPadding: number,
	minFormationSpacing: number,
	visualLengthRadiusFactor: number,
	minimumFallDistance: number,
	impactEmbedDepth: number,
	decorationEgressPadding: number,
	fallAcceleration: number,
	minFallSeconds: number,
	maxFallSeconds: number,
	lightSuppressionMultiplier: number,
	lightSuppressionSeconds: number,
	snuffBelowWaxFraction: number,
	wardenStunSeconds: number,
	presentationCullDistance: number,
	impactPresentationRadius: number,
	impactShakeStuds: number,
	impactShakeDegrees: number,
	impactShakeSeconds: number,
	impactDimBrightness: number,
	impactDimSeconds: number,
	flameFlickerSeconds: number,
	flameFlickerFrequencyHz: number,
	flameFlickerMinMultiplier: number,
	warningDustRate: number,
	warningDustBurst: number,
	fallingDustRate: number,
	fallingDustBurst: number,
	warningAudioFreshSeconds: number,
	dormantDustMinSeconds: number,
	dormantDustMaxSeconds: number,
	dormantDustBurstMin: number,
	dormantDustBurstMax: number,
	dormantTremorDegrees: number,
	warningWobbleStartDegrees: number,
	warningWobbleEndDegrees: number,
	warningFinalStillFraction: number,
	warningVibrationStuds: number,
	warningFrequencyStart: number,
	warningFrequencyIncrease: number,
	impactDustBurst: number,
	impactDebrisCount: number,
	impactDebrisLifetime: number,
	impactGradeContrast: number,
	impactGradeSaturation: number,
	impactShakeFrequency: number,
	modelPivotColor: Color3,
	modelCrownColor: Color3,
	modelFractureColor: Color3,
	modelDustColorStart: Color3,
	modelDustColorEnd: Color3,
	modelCrownPieces: number,
	modelFracturePieces: number,
	modelProngSpacing: number,
	modelSecondaryProngRadiusScale: number,
	modelProngHeightJitter: number,
	variants: { DripstoneVariant },
}

export type HazardsConfig = {
	definitions: { [Types.HazardId]: Types.HazardDef },
	unstableDripstone: UnstableDripstoneConfig,
	waterPool: {
		minSize: number,
		maxSize: number,
		aspectJitter: number,
		basinSearchStep: number,
		basinCandidateLimit: number,
		minimumFreeboard: number,
		visualThickness: number,
		shoreMossPatches: number,
		shoreMossRingPadding: number,
	},
	animation: {
		waterBobHeight: number,
		waterBobSpeed: number,
		waterTransparencyPulse: number,
		waterSheenTravelSpeed: number,
		waterSheenCrossSpeed: number,
		waterSheenCrossAmount: number,
	},
}

local Hazards: HazardsConfig = {
	definitions = {
		Water = {
			id = "Water",
			displayName = "Water",
			-- Wax lost per second while wading (feet below the surface). Higher = harder.
			degradePerSecond = 0.2,
			-- Instantly lethal when the water surface reaches this fraction of the CURRENT model height.
			-- The model shrinks as wax burns (Config/Character), so safe water becomes lethal later in
			-- the same run — the interaction emerges from these numbers. Lower = shallower kills = harder.
			lethalAtHeightFraction = 1.0,
		},
		Dripstone = {
			id = "Dripstone",
			displayName = "Unstable Dripstone",
		},
	},
	-- A rare, one-shot ceiling hazard. Detection and impact are deterministic; light changes only
	-- how early a player can read the fractured collar and dust. Counts rise with depth but are
	-- always safety-capped so most rooms and most ceiling formations remain harmless.
	unstableDripstone = {
		-- Nominal roof height above the room floor. Taller caverns never receive unstable formations:
		-- even a full-brightness candle should be able to inspect every dangerous ceiling.
		maxEligibleCeilingHeight = 34,
		-- Expected-count curve:
		-- F1-F3 = round(1 + .5 * (depth - 1)); F4-F6 = round(4 * 1.3^(depth - 4));
		-- F7+ = round(7 * 1.2^(depth - 6)). Placement safety caps may reduce the result.
		earlyLinearBase = 1,
		earlyLinearStep = 0.5,
		midExponentialBase = 4,
		midExponentialGrowth = 1.3,
		deepExponentialBase = 7,
		deepExponentialGrowth = 1.2,
		maxHazardousRoomFraction = 0.5,
		maxPerRoomEarly = 1,
		maxPerRoomMid = 2,
		maxPerRoomDeep = 3,
		maxUnstableToHarmlessRatio = 0.4,
		placementAttempts = 64,
		minCenterOffset = 11,
		maxCenterOffset = 25,
		doorwaySafetyPadding = 8,
		minFormationSpacing = 12,
		-- CaveKit's broken tip extends below the nominal spire height. Planning and landing use this
		-- conservative visual extent, then reserve a real drop beneath it.
		visualLengthRadiusFactor = 2.4,
		minimumFallDistance = 4.5,
		impactEmbedDepth = 0.2,
		decorationEgressPadding = 4,
		-- Analytic fall: anchored presentation, never network-owned physics or Touched damage.
		fallAcceleration = 180,
		minFallSeconds = 0.28,
		maxFallSeconds = 0.62,
		-- Partial snuff leaves the flame alive and the dial cost unchanged, but both rendered output
		-- and threat perception use this same multiplier for the same authoritative duration.
		lightSuppressionMultiplier = 0.42,
		lightSuppressionSeconds = 2,
		-- A candle already this depleted is snuffed by an impact instead of taking ordinary damage.
		snuffBelowWaxFraction = 0.3,
		-- A Stone Warden crossing the trigger disc sets the formation off exactly like a player does,
		-- and a crown landing on it buries the golem for this long: it stops walking and cannot kill
		-- while it digs itself back out. The main reason to lead one under a fractured ceiling.
		wardenStunSeconds = 15,
		presentationCullDistance = 90,
		impactPresentationRadius = 36,
		impactShakeStuds = 0.1,
		impactShakeDegrees = 1.25,
		impactShakeSeconds = 0.42,
		impactDimBrightness = -0.12,
		impactDimSeconds = 0.62,
		flameFlickerSeconds = 0.95,
		flameFlickerFrequencyHz = 22,
		flameFlickerMinMultiplier = 0.22,
		warningDustRate = 12,
		warningDustBurst = 4,
		fallingDustRate = 7,
		fallingDustBurst = 7,
		warningAudioFreshSeconds = 0.6,
		dormantDustMinSeconds = 4,
		dormantDustMaxSeconds = 9,
		dormantDustBurstMin = 1,
		dormantDustBurstMax = 3,
		dormantTremorDegrees = 0.28,
		warningWobbleStartDegrees = 0.3,
		warningWobbleEndDegrees = 2.2,
		warningFinalStillFraction = 0.06,
		warningVibrationStuds = 0.035,
		warningFrequencyStart = 8,
		warningFrequencyIncrease = 13,
		impactDustBurst = 28,
		impactDebrisCount = 10,
		impactDebrisLifetime = 2.2,
		impactGradeContrast = 0.08,
		impactGradeSaturation = -0.18,
		impactShakeFrequency = 41,
		modelPivotColor = Color3.fromRGB(38, 40, 47),
		modelCrownColor = Color3.fromRGB(49, 51, 59),
		modelFractureColor = Color3.fromRGB(17, 18, 22),
		modelDustColorStart = Color3.fromRGB(82, 78, 72),
		modelDustColorEnd = Color3.fromRGB(40, 40, 43),
		modelCrownPieces = 3,
		modelFracturePieces = 3,
		modelProngSpacing = 0.72,
		modelSecondaryProngRadiusScale = 0.66,
		modelProngHeightJitter = 0.035,
		-- All variants share one behavior and warning language. Shape, readable weight, warning time,
		-- footprint, and wax cost are data so new silhouettes do not require service branches.
		variants = {
			{
				id = "Needle",
				displayName = "Fractured Needle",
				weight = 4,
				length = 7.4,
				radius = 0.85,
				prongCount = 1,
				leanDegrees = 5,
				taper = 1.28,
				crownScale = 2.55,
				warningSeconds = 1.65,
				triggerRadius = 5,
				impactRadius = 3.25,
				waxLossFraction = 0.2,
			},
			{
				id = "Fork",
				displayName = "Split Fork",
				weight = 3,
				length = 6.4,
				radius = 1.15,
				prongCount = 2,
				leanDegrees = 6,
				taper = 1.28,
				crownScale = 2.55,
				warningSeconds = 1.8,
				triggerRadius = 5.25,
				impactRadius = 3.6,
				waxLossFraction = 0.35,
			},
			{
				id = "Hammer",
				displayName = "Heavy Crown",
				weight = 2,
				length = 5.4,
				radius = 1.55,
				prongCount = 3,
				leanDegrees = 7,
				taper = 0.95,
				crownScale = 3.3,
				warningSeconds = 2,
				triggerRadius = 5.5,
				impactRadius = 4,
				waxLossFraction = 0.5,
			},
		},
	},
	-- Water settles into the room's OWN natural recesses (see FloorPlanner.planWaterPool) rather than
	-- into a bowl punched through flat ground. The cave floor already rolls by several studs, so the
	-- planner samples that height field, puts the pool in its lowest valid dip, and only ever
	-- deepens what is already there. The surrounding rock stays walkable and the pool never spans a
	-- room, so nothing here can block a route.
	waterPool = {
		-- Pool DIAMETER range (studs). The cave floor is smooth Terrain written at 4-stud voxels, so a
		-- pool narrower than a few voxels smooths back into the surrounding rock and never becomes
		-- visible or wadeable. This is the real lower bound on "small" — below ~5 voxels it vanishes.
		minSize = 20,
		maxSize = 32,
		-- Per-axis stretch applied to that diameter so pools are not perfect circles. Kept small:
		-- the bed is radial, so a strongly elliptical plane would overhang its own floor.
		aspectJitter = 0.12,
		-- Recess search grid (studs). Matched to the Terrain voxel size so a chosen dip is never a
		-- sub-voxel pinprick the builder cannot actually resolve.
		basinSearchStep = 4,
		-- How many of the deepest candidate dips to try before giving up and using the room centre.
		basinCandidateLimit = 48,
		-- The waterline is pinned to the pool bed, not to the room's base plane, so wading depth is
		-- exactly the module's declared depth wherever the recess happens to sit. This is the minimum
		-- gap kept between that waterline and the room's flat base plane, which is what guarantees
		-- the central plaza and every doorway lane stay dry.
		minimumFreeboard = 0.5,
		visualThickness = 0.16,
		-- Damp-shore dressing: moss patches ringed around the waterline (see Config/Floors.caveMoss).
		shoreMossPatches = 14,
		shoreMossRingPadding = 5,
	},
	animation = {
		waterBobHeight = 0.06,
		waterBobSpeed = 1.1,
		waterTransparencyPulse = 0.05,
		waterSheenTravelSpeed = 0.12,
		waterSheenCrossSpeed = 0.45,
		waterSheenCrossAmount = 0.2,
	},
}

return Hazards

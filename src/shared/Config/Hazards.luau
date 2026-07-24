--!strict
-- Environmental hazard tuning (DESIGN §9). Cheap difficulty: no AI, no models.
-- The candle model's height mapping lives in Config/Character (the water rule reads it there).

local Types = require(script.Parent.Parent.Types)

export type HazardsConfig = {
	definitions: { [Types.HazardId]: Types.HazardDef },
	draftZone: {
		length: number,
		width: number,
		height: number,
		maxCenterOffset: number,
	},
	draftVisual: {
		enabled: boolean,
		hazeColor: Color3,
		hazeTransparency: number,
		markerColor: Color3,
		markerTransparency: number,
		markerWidth: number,
		markerDepth: number,
		lightBrightness: number,
		lightRange: number,
	},
	waterPool: {
		minSize: number,
		maxSize: number,
		maxCenterOffset: number,
		surfaceOffset: number,
		visualThickness: number,
		escapeStepMaxRise: number,
		escapeRun: number,
		rimRocks: number,
		rimRockMinSize: number,
		rimRockMaxSize: number,
	},
	animation: {
		waterBobHeight: number,
		waterBobSpeed: number,
		waterTransparencyPulse: number,
		waterSheenTravelSpeed: number,
		waterSheenCrossSpeed: number,
		waterSheenCrossAmount: number,
		draftPulseSpeed: number,
		draftTransparencyPulse: number,
		windParticleRate: number,
		windParticleMinSpeed: number,
		windParticleMaxSpeed: number,
	},
}

local Hazards: HazardsConfig = {
	definitions = {
		Draft = {
			id = "Draft",
			displayName = "Draft",
			-- Extra wax drained per second while exposed and not cupping. Higher = harder. Countered by CUP.
			guttering = 0.03,
			-- Continuous uncupped, lit exposure (seconds) after which the draft fully snuffs the flame
			-- (the revivable death state). Lower = harder; this is what gives CUP its teeth.
			snuffAfterSeconds = 4,
		},
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
	},
	-- Avoidable interior wind pockets. FloorPlanner records their exact orientation and offset.
	draftZone = {
		length = 22,
		width = 8,
		height = 9,
		maxCenterOffset = 9,
	},
	-- Readability-only wind-pocket treatment. It intentionally looks cold and unnatural before the
	-- player enters the mechanical zone; no value here changes draft exposure or damage.
	draftVisual = {
		enabled = true,
		hazeColor = Color3.fromRGB(125, 180, 235),
		hazeTransparency = 0.72,
		markerColor = Color3.fromRGB(170, 220, 255),
		markerTransparency = 0.16,
		markerWidth = 0.28,
		markerDepth = 0.16,
		lightBrightness = 0.65,
		lightRange = 12,
	},
	-- Water is a recessed local pool, never a room-wide plane. Its surrounding rock remains
	-- walkable and submerged steps provide an escape route even from the deepest prototype pool.
	waterPool = {
		minSize = 10,
		maxSize = 18,
		maxCenterOffset = 9,
		surfaceOffset = 0.08,
		visualThickness = 0.16,
		escapeStepMaxRise = 0.5,
		escapeRun = 6,
		rimRocks = 10,
		rimRockMinSize = 0.8,
		rimRockMaxSize = 2.2,
	},
	animation = {
		waterBobHeight = 0.06,
		waterBobSpeed = 1.1,
		waterTransparencyPulse = 0.05,
		waterSheenTravelSpeed = 0.12,
		waterSheenCrossSpeed = 0.45,
		waterSheenCrossAmount = 0.2,
		draftPulseSpeed = 1.8,
		draftTransparencyPulse = 0.08,
		windParticleRate = 18,
		windParticleMinSpeed = 7,
		windParticleMaxSpeed = 11,
	},
}

return Hazards

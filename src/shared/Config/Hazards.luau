--!strict
-- Environmental hazard tuning (DESIGN §9). Cheap difficulty: no AI, no models.
-- The candle model's height mapping lives in Config/Character (the water rule reads it there).

local Types = require(script.Parent.Parent.Types)

export type HazardsConfig = {
	definitions: { [Types.HazardId]: Types.HazardDef },
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
}

return Hazards

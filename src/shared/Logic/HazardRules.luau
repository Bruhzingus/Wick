--!strict
-- Pure: hazard rules. The water rule is THE mechanic (spec): a real height comparison between
-- the water surface and the shrinking body — never a scripted trigger.

local Types = require(script.Parent.Parent.Types)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)

local HazardRules = {}

-- Where does this water surface sit against this candle right now?
-- baseY = world Y of the candle's base; height = CURRENT (wax-scaled) body height.
function HazardRules.waterAssessment(surfaceY: number, baseY: number, height: number): Types.WaterAssessment
	local water = HazardsConfig.definitions.Water
	local lethalFraction = water.lethalAtHeightFraction :: number -- Water rows always define this
	if surfaceY >= baseY + height * lethalFraction then
		return "Lethal"
	end
	if surfaceY > baseY then
		return "Wading"
	end
	return "None"
end

-- Does draft exposure count toward snuffing the flame right now? (CUP is full immunity.)
function HazardRules.draftThreatens(isLit: boolean, isCupping: boolean): boolean
	return isLit and not isCupping
end

-- Continuous threatened-seconds after which a draft snuffs the flame.
function HazardRules.draftSnuffSeconds(): number
	local draft = HazardsConfig.definitions.Draft
	return draft.snuffAfterSeconds :: number -- Draft rows always define this
end

return HazardRules

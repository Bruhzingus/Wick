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

return HazardRules

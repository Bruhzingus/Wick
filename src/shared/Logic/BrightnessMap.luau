--!strict
-- Pure: burn rate -> light numbers (PointLight Range/Brightness and light-field intensity).
-- The one place the dial's output curve lives; server visuals and threat perception both read it.

local Types = require(script.Parent.Parent.Types)
local LightConfig = require(script.Parent.Parent.Config.Light)

export type LightParams = {
	range: number,
	brightness: number,
	intensity: number, -- light-field strength for threat perception
}

local BrightnessMap = {}

-- `candle` is the LIVE profile from Logic/CandleModifiers.profile (which has already decided what a
-- cupped flame's modifiers are worth). lightMultiplier: 1 normally; Cup's lightMultiplier while
-- cupping.
function BrightnessMap.paramsFor(
	burnRate: Types.BurnRate,
	candle: Types.CandleProfile,
	lightMultiplier: number
): LightParams
	local span = LightConfig.maxBurnRate - LightConfig.minBurnRate
	local t = if span > 0 then math.clamp((burnRate - LightConfig.minBurnRate) / span, 0, 1) else 0
	local curved = t ^ LightConfig.falloffExponent
	local scale = candle.brightnessMultiplier * lightMultiplier

	return {
		range = (LightConfig.minRange + (LightConfig.maxRange - LightConfig.minRange) * curved) * scale,
		brightness = (LightConfig.minBrightness + (LightConfig.maxBrightness - LightConfig.minBrightness) * curved)
			* scale,
		-- Intensity uses the same curve so what threats perceive always tracks what players see.
		intensity = (LightConfig.minIntensity + (LightConfig.maxIntensity - LightConfig.minIntensity) * curved) * scale,
	}
end

return BrightnessMap

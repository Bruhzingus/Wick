--!strict
-- Pure clearing rule for Ice's barred doorway barricades.

local IciclesConfig = require(script.Parent.Parent.Config.Icicles)
local LightConfig = require(script.Parent.Parent.Config.Light)

local IcicleRules = {}

function IcicleRules.meltSeconds(
	isLit: boolean,
	isCupping: boolean,
	burnRate: number,
	isFlaring: boolean,
	maxBurnRate: number?
): number?
	if not isLit or isCupping then
		return nil
	end
	if isFlaring then
		return IciclesConfig.flareMeltSeconds
	end
	local ceiling = if maxBurnRate ~= nil and maxBurnRate == maxBurnRate
		then math.clamp(maxBurnRate, LightConfig.minBurnRate, LightConfig.maxBurnRate)
		else LightConfig.maxBurnRate
	if burnRate >= ceiling * IciclesConfig.requiredBurnRateFraction then
		return IciclesConfig.maxBrightnessMeltSeconds
	end
	return nil
end

return IcicleRules

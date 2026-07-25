--!strict
-- Replicated presentation contract for candle lighting. The server publishes authoritative
-- targets as attributes; every client renders and interpolates its own PointLights.

local LightVisualProtocol = {
	tag = "WickCandleLight",
	attributes = {
		ownerUserId = "WickLightOwnerUserId",
		enabled = "WickLightEnabled",
		range = "WickLightRange",
		brightness = "WickLightBrightness",
		impactFlickerUntil = "WickLightImpactFlickerUntil",
	},
}

return table.freeze(LightVisualProtocol)

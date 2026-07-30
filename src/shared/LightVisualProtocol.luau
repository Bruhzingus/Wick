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
		-- OPTIONAL, and absent on every living candle. A Color3 that replaces the configured flame colour
		-- for this emitter and opts it out of the warm combustion flicker. It exists for the one light in
		-- the game that is not a burning wick: a ghost's cold remnant (Config/Spectator), which would
		-- otherwise cast warm candlelight out of a blue flame. Unset means "an ordinary candle", so
		-- Config/Light.rendering stays the single answer for all of them.
		color = "WickLightColor",
	},
}

return table.freeze(LightVisualProtocol)

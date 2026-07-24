--!strict
-- Light output tuning: how the brightness dial (burn rate) maps to the candle's light (DESIGN §4).
-- Pure data. Logic/BrightnessMap turns these into numbers; a server adapter sets the PointLight.

local Types = require(script.Parent.Parent.Types)

export type DialConfig = {
	scrollStep: number,
	snapPoints: { number },
	snapRadius: number,
}

export type LightConfig = {
	minBurnRate: Types.BurnRate,
	maxBurnRate: Types.BurnRate,
	minRange: number,
	maxRange: number,
	minBrightness: number,
	maxBrightness: number,
	falloffExponent: number,
	dial: DialConfig,
}

local Light: LightConfig = {
	-- Lowest the dial can go while still lit (0 would be snuffed). Higher floor = easier to see.
	minBurnRate = 0.05,
	-- Highest the dial can go, before a Basin MaxBrightness cap. Higher = can see more, but burns faster.
	maxBurnRate = 1.0,
	-- PointLight.Range (studs) at minBurnRate. Larger = see more in the dark = easier.
	minRange = 6,
	-- PointLight.Range (studs) at maxBurnRate. Larger = easier to see, but reaching it costs wax.
	maxRange = 40,
	-- PointLight.Brightness at minBurnRate.
	minBrightness = 0.5,
	-- PointLight.Brightness at maxBurnRate.
	maxBrightness = 4,
	-- Shape of the burnRate -> range/brightness curve (t ^ exponent). >1 = stays dim until you push the dial high.
	falloffExponent = 1.0,
	-- Input feel of the dial itself (client-side; server still clamps the result).
	dial = {
		-- Burn-rate change per scroll-wheel notch. Smaller = finer control.
		scrollStep = 0.05,
		-- Dial values the slider gently snaps to. Skill expression lives between them.
		snapPoints = { 0.25, 0.5, 0.75 },
		-- How close (in burn rate) the thumb must be to a snap point to stick.
		snapRadius = 0.02,
	},
}

return Light

--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local BrightnessMap = require(script.Parent.Parent.Logic.BrightnessMap)
local LightConfig = require(script.Parent.Parent.Config.Light)
local CandleModifiers = require(script.Parent.Parent.Logic.CandleModifiers)

local suite: Harness.Suite = {
	name = "BrightnessMap",
	tests = {
		Harness.test("dial endpoints and out-of-range inputs clamp to config", function()
			local standard = CandleModifiers.neutralProfile()
			local low = BrightnessMap.paramsFor(LightConfig.minBurnRate, standard, 1)
			Harness.near(low.range, LightConfig.minRange)
			Harness.near(low.brightness, LightConfig.minBrightness)
			Harness.near(low.intensity, LightConfig.minIntensity)

			local high = BrightnessMap.paramsFor(LightConfig.maxBurnRate, standard, 1)
			Harness.near(high.range, LightConfig.maxRange)
			Harness.near(high.brightness, LightConfig.maxBrightness)
			Harness.near(high.intensity, LightConfig.maxIntensity * standard.brightnessMultiplier)

			local below = BrightnessMap.paramsFor(LightConfig.minBurnRate - 10, standard, 1)
			local above = BrightnessMap.paramsFor(LightConfig.maxBurnRate + 10, standard, 1)
			Harness.near(below.range, low.range)
			Harness.near(above.range, high.range)
		end),

		Harness.test("the configured curve drives all three light outputs", function()
			local standard = CandleModifiers.neutralProfile()
			local t = 0.37
			local burnRate = LightConfig.minBurnRate + (LightConfig.maxBurnRate - LightConfig.minBurnRate) * t
			local curved = t ^ LightConfig.falloffExponent
			local params = BrightnessMap.paramsFor(burnRate, standard, 1)

			Harness.near(params.range, LightConfig.minRange + (LightConfig.maxRange - LightConfig.minRange) * curved)
			Harness.near(
				params.brightness,
				LightConfig.minBrightness + (LightConfig.maxBrightness - LightConfig.minBrightness) * curved
			)
			Harness.near(
				params.intensity,
				LightConfig.minIntensity + (LightConfig.maxIntensity - LightConfig.minIntensity) * curved
			)
		end),

		Harness.test("candle modifiers and Cup multiply perceived and visible light together", function()
			-- A real modified candle rather than a hand-written profile: whatever a BrightWax stack is
			-- retuned to be worth, it must still reach range, brightness AND what threats perceive by
			-- exactly the same factor. Light you can see that threats cannot is the one thing the
			-- brightness pipeline may never produce.
			local candle: Types.CandleProfile = {
				drainMultiplier = 1,
				brightnessMultiplier = 1 + CandleModifiers.brightWaxBrightnessBonus(3),
				attractsDrawn = true,
			}
			local lightMultiplier = 0.2
			local scale = candle.brightnessMultiplier * lightMultiplier
			local params = BrightnessMap.paramsFor(LightConfig.maxBurnRate, candle, lightMultiplier)

			Harness.expect(candle.brightnessMultiplier > 1, "three BrightWax stacks must add light")
			Harness.near(params.range, LightConfig.maxRange * scale)
			Harness.near(params.brightness, LightConfig.maxBrightness * scale)
			Harness.near(params.intensity, LightConfig.maxIntensity * scale)
		end),

		Harness.test("higher in-range dial values never produce less light", function()
			local candle = CandleModifiers.neutralProfile()
			local previous = BrightnessMap.paramsFor(LightConfig.minBurnRate, candle, 1)
			for index = 1, 20 do
				local t = index / 20
				local burnRate = LightConfig.minBurnRate + (LightConfig.maxBurnRate - LightConfig.minBurnRate) * t
				local current = BrightnessMap.paramsFor(burnRate, candle, 1)
				Harness.expect(current.range >= previous.range, "range curve must be monotonic")
				Harness.expect(current.brightness >= previous.brightness, "brightness curve must be monotonic")
				Harness.expect(current.intensity >= previous.intensity, "intensity curve must be monotonic")
				previous = current
			end
		end),

		Harness.test("local rendering keeps stable illumination dominant", function()
			local rendering = LightConfig.rendering
			local shadow = rendering.localShadowBrightnessFraction
			local bounce = rendering.localBounceBrightnessFraction
			local stableFill = 1 - shadow - bounce

			Harness.expect(shadow > 0, "the local candle should retain visible shadow detail")
			Harness.expect(stableFill > shadow, "engine shadow-map changes must not dominate illumination")
			Harness.expect(stableFill >= 0, "light layer fractions must not exceed the output budget")
			Harness.expect(
				rendering.positionSettleDistance > 0
					and rendering.positionSettleDistance < rendering.positionSnapDistance,
				"idle settle must remain positive and below the teleport threshold"
			)
		end),
	},
}

return suite

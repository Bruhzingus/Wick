--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local LightField = require(script.Parent.Parent.Logic.LightField)
local BrightnessMap = require(script.Parent.Parent.Logic.BrightnessMap)
local LightConfig = require(script.Parent.Parent.Config.Light)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)
local WaxTypes = require(script.Parent.Parent.Config.WaxTypes)

local function source(
	position: Vector3,
	intensity: number,
	range: number,
	attractsDrawn: boolean,
	ownerId: number?,
	repelsDarkHunters: boolean?,
	forcesDarkHunterRetreat: boolean?
): Types.LightSource
	return {
		kind = "Flame",
		position = position,
		intensity = intensity,
		range = range,
		attractsDrawn = attractsDrawn,
		repelsDarkHunters = repelsDarkHunters ~= false,
		forcesDarkHunterRetreat = forcesDarkHunterRetreat == true,
		ownerId = ownerId,
	}
end

local suite: Harness.Suite = {
	name = "LightField",
	tests = {
		Harness.test("one source falls off linearly and reaches zero at range", function()
			local light = source(Vector3.zero, 2, 10, true, 1)
			local cases = {
				{ position = Vector3.zero, expected = 2 },
				{ position = Vector3.new(5, 0, 0), expected = 1 },
				{ position = Vector3.new(10, 0, 0), expected = 0 },
				{ position = Vector3.new(20, 0, 0), expected = 0 },
			}
			for _, case in cases do
				Harness.near(LightField.contributionOf(light, case.position), case.expected)
			end

			local invalidRange = source(Vector3.zero, 2, 0, true, 1)
			Harness.near(LightField.contributionOf(invalidRange, Vector3.zero), 0)
		end),

		Harness.test("total intensity is the sum of every contribution", function()
			local sources: { Types.LightSource } = {
				source(Vector3.zero, 1, 10, true, 1),
				source(Vector3.new(5, 0, 0), 2, 10, true, 2),
				source(Vector3.new(100, 0, 0), 100, 1, true, 3),
			}
			Harness.near(LightField.intensityAt(Vector3.zero, sources), 1 + 2 * 0.5)
		end),

		Harness.test("strongest source is judged by local contribution, not raw intensity", function()
			local close = source(Vector3.new(1, 0, 0), 1, 10, true, 11)
			local far = source(Vector3.new(8, 0, 0), 3, 10, true, 22)
			local best = LightField.strongestSourceNear(Vector3.zero, { close, far }, 20, false)
			Harness.equal(best, close)
		end),

		Harness.test("drawn filtering ignores cold light and respects detection radius", function()
			local cold = source(Vector3.new(1, 0, 0), 100, 100, false, 11)
			local warm = source(Vector3.new(2, 0, 0), 1, 10, true, 22)
			local outside = source(Vector3.new(20, 0, 0), 100, 100, true, 33)

			local drawnBest = LightField.strongestSourceNear(Vector3.zero, { cold, warm, outside }, 10, true)
			Harness.equal(drawnBest, warm)

			local anyBest = LightField.strongestSourceNear(Vector3.zero, { cold, warm, outside }, 10, false)
			Harness.equal(anyBest, cold)

			local none = LightField.strongestSourceNear(Vector3.zero, { outside }, 10, false)
			Harness.isNil(none)

			local decoy = source(Vector3.new(3, 0, 0), 2, 10, true, nil, false)
			decoy.kind = "Decoy"
			local darkHunterSources = LightField.sourcesForDarkHunters({ warm, decoy })
			Harness.equal(#darkHunterSources, 1)
			Harness.equal(darkHunterSources[1], warm)
		end),

		Harness.test("only explicit panic light can force a hunter retreat", function()
			local ordinary = source(Vector3.zero, 100, 100, true, 1, true, false)
			local flare = source(Vector3.new(2, 0, 0), 3, 60, true, 1, true, true)
			flare.kind = "Flare"

			Harness.isNil(LightField.strongestRetreatSourceAt(Vector3.zero, { ordinary }))
			Harness.equal(LightField.strongestRetreatSourceAt(Vector3.zero, { ordinary, flare }), flare)
		end),

		Harness.test("nearby open flames still illuminate a cupped player", function()
			local cupMultiplier = ToolsConfig.Cup.lightMultiplier :: number
			local cuppedParams = BrightnessMap.paramsFor(LightConfig.maxBurnRate, WaxTypes.Standard, cupMultiplier)
			local openParams = BrightnessMap.paramsFor(LightConfig.maxBurnRate, WaxTypes.Standard, 1)
			local cupped = source(Vector3.zero, cuppedParams.intensity, cuppedParams.range, true, 1, true, false)
			local teammate = source(Vector3.new(3, 0, 0), openParams.intensity, openParams.range, true, 2, true, false)
			local otherCupped =
				source(Vector3.new(0.5, 0, 0), cuppedParams.intensity, cuppedParams.range, true, 2, true, false)
			local illuminationRequirement = 0
			for _, def in ThreatsConfig.definitions do
				if def.category == "DarkHunter" and def.ambush == nil then
					illuminationRequirement = math.max(
						illuminationRequirement,
						ThreatsConfig.behavior.huntLightThreshold / math.abs(def.lightResponse)
					)
				end
			end
			Harness.expect(
				LightField.intensityAt(Vector3.zero, { cupped, teammate }) > illuminationRequirement,
				"a nearby uncovered teammate must make the cupped player read as illuminated"
			)
			Harness.expect(
				LightField.intensityAt(Vector3.zero, { cupped, otherCupped })
					< ThreatsConfig.behavior.huntLightThreshold,
				"two cupped flames should remain effectively dark"
			)
		end),
	},
}

return suite

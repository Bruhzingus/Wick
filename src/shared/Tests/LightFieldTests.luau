--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local LightField = require(script.Parent.Parent.Logic.LightField)

local function source(
	position: Vector3,
	intensity: number,
	range: number,
	attractsDrawn: boolean,
	ownerId: number?,
	repelsDarkHunters: boolean?
): Types.LightSource
	return {
		kind = "Flame",
		position = position,
		intensity = intensity,
		range = range,
		attractsDrawn = attractsDrawn,
		repelsDarkHunters = repelsDarkHunters ~= false,
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
	},
}

return suite

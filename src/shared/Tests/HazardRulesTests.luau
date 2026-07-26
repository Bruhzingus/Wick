--!strict

local Harness = require(script.Parent.Harness)
local CandleGeometry = require(script.Parent.Parent.Logic.CandleGeometry)
local HazardRules = require(script.Parent.Parent.Logic.HazardRules)
local HazardsConfig = require(script.Parent.Parent.Config.Hazards)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)

local suite: Harness.Suite = {
	name = "HazardRules",
	tests = {
		Harness.test("water boundaries follow base and current-height comparisons", function()
			local lethalFraction = HazardsConfig.definitions.Water.lethalAtHeightFraction :: number
			local baseY = 10
			local height = 4
			local lethalY = baseY + height * lethalFraction

			Harness.equal(HazardRules.waterAssessment(baseY, baseY, height), "None")
			Harness.equal(HazardRules.waterAssessment(baseY + 0.01, baseY, height), "Wading")
			Harness.equal(HazardRules.waterAssessment(lethalY - 0.01, baseY, height), "Wading")
			Harness.equal(HazardRules.waterAssessment(lethalY, baseY, height), "Lethal")
			Harness.equal(HazardRules.waterAssessment(lethalY + 1, baseY, height), "Lethal")
		end),

		Harness.test("shrinking can turn the same configured water into a lethal route", function()
			local waterDepth: number? = nil
			for _, room in FloorsConfig.roomModules do
				if room.waterDepth ~= nil then
					waterDepth = room.waterDepth
					break
				end
			end
			Harness.expect(waterDepth ~= nil, "at least one room module must exercise the water rule")
			local surfaceY = waterDepth :: number
			local fullHeight = CandleGeometry.heightForWax(1)
			local emptyHeight = CandleGeometry.heightForWax(0)

			Harness.equal(HazardRules.waterAssessment(surfaceY, 0, fullHeight), "Wading")
			Harness.equal(HazardRules.waterAssessment(surfaceY, 0, emptyHeight), "Lethal")
		end),
	},
}

return suite

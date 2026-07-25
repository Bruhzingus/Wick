--!strict

local Harness = require(script.Parent.Harness)
local CandleGeometry = require(script.Parent.Parent.Logic.CandleGeometry)
local CharacterConfig = require(script.Parent.Parent.Config.Character)
local WaxConfig = require(script.Parent.Parent.Config.Wax)

local suite: Harness.Suite = {
	name = "CandleGeometry",
	tests = {
		Harness.test("wax maps linearly onto configured body-height endpoints", function()
			Harness.near(CandleGeometry.heightForWax(0), CharacterConfig.heightAtZeroWax)
			Harness.near(CandleGeometry.heightForWax(WaxConfig.maxWax), CharacterConfig.heightAtFullWax)

			local fraction = 0.37
			local wax = WaxConfig.maxWax * fraction
			local expected = CharacterConfig.heightAtZeroWax
				+ (CharacterConfig.heightAtFullWax - CharacterConfig.heightAtZeroWax) * fraction
			Harness.near(CandleGeometry.heightForWax(wax), expected)
		end),

		Harness.test("out-of-range wax cannot create impossible geometry", function()
			Harness.near(CandleGeometry.heightForWax(-10), CharacterConfig.heightAtZeroWax)
			Harness.near(CandleGeometry.heightForWax(10), CharacterConfig.heightAtFullWax)
		end),

		Harness.test("flame reference heights share the body top as their origin", function()
			local baseY = -12
			local height = CandleGeometry.heightForWax(0.5)
			Harness.near(CandleGeometry.flameBaseY(baseY, height), baseY + height)
			Harness.near(
				CandleGeometry.flameCenterY(baseY, height),
				baseY + height + CharacterConfig.wickHeight + CharacterConfig.flameHeight / 2
			)
		end),

		Harness.test("body height is monotonic with remaining absolute wax", function()
			local previous = CandleGeometry.heightForWax(0)
			for index = 1, 20 do
				local current = CandleGeometry.heightForWax(WaxConfig.maxWax * index / 20)
				Harness.expect(current >= previous, "more wax must never make a shorter candle")
				previous = current
			end
		end),
	},
}

return suite

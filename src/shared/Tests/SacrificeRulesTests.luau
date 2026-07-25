--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local SacrificeRules = require(script.Parent.Parent.Logic.SacrificeRules)
local BasinConfig = require(script.Parent.Parent.Config.Basin)
local LightConfig = require(script.Parent.Parent.Config.Light)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)

local function offerSignature(offers: { Types.ResolvedOffer }): string
	local pieces: { string } = {}
	for _, offer in offers do
		table.insert(pieces, string.format("%s:%s:%.12g", offer.def.id, tostring(offer.toolId), offer.waxGranted))
	end
	return table.concat(pieces, "|")
end

local suite: Harness.Suite = {
	name = "SacrificeRules",
	tests = {
		Harness.test("default modifiers preserve every starting ability", function()
			local modifiers = SacrificeRules.defaultModifiers()
			Harness.near(modifiers.maxBurnRate, LightConfig.maxBurnRate)
			Harness.equal(modifiers.canSlide, true)
			Harness.near(modifiers.dodgeDistanceMultiplier, 1)
			Harness.equal(modifiers.hasDripTrail, true)
			Harness.equal(modifiers.canRelight, true)
			Harness.equal(modifiers.canBeRelit, true)
			Harness.isNil(next(modifiers.lostTools))
		end),

		Harness.test("grants worsen with depth and the next-Basin penalty divides once", function()
			local def = BasinConfig.pool[1]
			local depth = 4
			local expected = def.waxGranted * BasinConfig.depthPenaltyPerFloor ^ (depth - 1)
			Harness.near(SacrificeRules.grantFor(def, depth, 1), expected)
			Harness.near(SacrificeRules.grantFor(def, depth, 2), expected / 2)
			Harness.near(SacrificeRules.grantFor(def, depth, 0), expected)
		end),

		Harness.test("seeded offers are stable, distinct, applicable, and fully resolved", function()
			local first = SacrificeRules.rollOffers(SacrificeRules.defaultModifiers(), {}, 3, 1, Random.new(8_675_309))
			local second = SacrificeRules.rollOffers(SacrificeRules.defaultModifiers(), {}, 3, 1, Random.new(8_675_309))
			Harness.equal(#first, math.min(BasinConfig.offersPerVisit, #BasinConfig.pool))
			Harness.equal(offerSignature(first), offerSignature(second))

			local seen: { [string]: boolean } = {}
			for _, offer in first do
				Harness.expect(not seen[offer.def.id], "offer roll must be without replacement")
				seen[offer.def.id] = true
				if offer.def.target == "Tool" then
					Harness.expect(offer.toolId ~= nil, "tool sacrifice must name the concrete lost tool")
				else
					Harness.isNil(offer.toolId)
				end
				Harness.near(offer.waxGranted, SacrificeRules.grantFor(offer.def, 3, 1))
			end
		end),

		Harness.test("inapplicable and previously taken sacrifices are removed before rolling", function()
			local modifiers = SacrificeRules.defaultModifiers()
			for toolId in ToolsConfig do
				modifiers.lostTools[toolId] = true
			end
			modifiers.canSlide = false
			modifiers.dodgeDistanceMultiplier = 0.5
			modifiers.hasDripTrail = false
			modifiers.canRelight = false
			modifiers.canBeRelit = false

			local taken: { [string]: boolean } = {}
			for _, def in BasinConfig.pool do
				if def.target == "MaxBrightness" or def.target == "NextBasinPriceDoubled" then
					taken[def.id] = true
				end
			end

			local offers = SacrificeRules.rollOffers(modifiers, taken, 1, 1, Random.new(7))
			Harness.equal(#offers, 0)
		end),

		Harness.test("every configured target applies immutably through the generic dispatch", function()
			for _, def in BasinConfig.pool do
				local original = SacrificeRules.defaultModifiers()
				local toolId: Types.ToolId? = if def.target == "Tool" then "Flare" else nil
				local result = SacrificeRules.apply(original, {
					def = def,
					toolId = toolId,
					waxGranted = def.waxGranted,
				})

				Harness.expect(result.modifiers ~= original, "apply must return a copied modifier record")
				Harness.near(original.maxBurnRate, LightConfig.maxBurnRate, nil, "input max brightness mutated")
				Harness.equal(original.canSlide, true, "input slide flag mutated")
				Harness.isNil(original.lostTools.Flare, "input lost-tools table mutated")
				Harness.equal(
					result.doublesNextPrice,
					def.target == "NextBasinPriceDoubled",
					"wrong next-price result for " .. def.id
				)

				if def.target == "MaxBrightness" then
					Harness.near(
						result.modifiers.maxBurnRate,
						LightConfig.maxBurnRate * BasinConfig.effects.maxBurnRateCapMultiplier
					)
				elseif def.target == "Slide" then
					Harness.equal(result.modifiers.canSlide, false)
				elseif def.target == "Dodge" then
					Harness.near(result.modifiers.dodgeDistanceMultiplier, BasinConfig.effects.dodgeShortenMultiplier)
				elseif def.target == "DripTrail" then
					Harness.equal(result.modifiers.hasDripTrail, false)
				elseif def.target == "Relight" then
					Harness.equal(result.modifiers.canRelight, false)
				elseif def.target == "BeRelit" then
					Harness.equal(result.modifiers.canBeRelit, false)
				elseif def.target == "Tool" then
					Harness.equal(result.modifiers.lostTools.Flare, true)
				end
			end
		end),
	},
}

return suite

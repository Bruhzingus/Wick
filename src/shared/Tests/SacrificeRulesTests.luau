--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local SacrificeRules = require(script.Parent.Parent.Logic.SacrificeRules)
local BasinConfig = require(script.Parent.Parent.Config.Basin)
local LightConfig = require(script.Parent.Parent.Config.Light)

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
			Harness.near(modifiers.minBurnRate, LightConfig.minBurnRate)
			Harness.near(modifiers.moveSpeedMultiplier, 1)
			Harness.near(modifiers.cupSpeedMultiplier, 1)
			Harness.equal(modifiers.hasDripTrail, true)
			Harness.equal(modifiers.canRelight, true)
			Harness.equal(modifiers.canBeRelit, true)
			Harness.equal(modifiers.canHearThreats, true)
			Harness.near(modifiers.maxWaxMultiplier, 1)
			Harness.near(modifiers.waxDrainMultiplier, 1)
			Harness.near(modifiers.toolCooldownMultiplier, 1)
			Harness.near(modifiers.flareDurationMultiplier, 1)
			Harness.near(modifiers.decoyDurationMultiplier, 1)
			Harness.near(modifiers.relightCostMultiplier, 1)
			Harness.near(modifiers.peripheralDarkness, 0)
			Harness.near(modifiers.sightBrightness, 0)
			Harness.near(modifiers.sightSaturation, 0)
			Harness.isNil(next(modifiers.lostTools))
		end),

		Harness.test("every pool row names a target the dispatch table can actually apply", function()
			local modifiers = SacrificeRules.defaultModifiers()
			local seenIds: { [string]: boolean } = {}
			for _, def in BasinConfig.pool do
				Harness.expect(not seenIds[def.id], "duplicate sacrifice id " .. def.id)
				seenIds[def.id] = true
				Harness.expect(def.weight > 0, def.id .. " must be rollable")
				Harness.expect(
					def.waxGranted >= BasinConfig.minimumGrant and def.waxGranted <= BasinConfig.maximumGrant,
					def.id .. " must stay inside the Basin grant band"
				)
				local toolId: Types.ToolId? = if def.target == "Tool" then "Flare" else nil
				local result = SacrificeRules.apply(modifiers, {
					def = def,
					toolId = toolId,
					waxGranted = def.waxGranted,
				})
				Harness.expect(result.modifiers ~= nil, "no handler for target " .. def.target)
			end
		end),

		Harness.test("a capped dial can never end up above its own ceiling or below its own floor", function()
			local capped = SacrificeRules.defaultModifiers()
			for _, def in BasinConfig.pool do
				if def.target == "MaxBrightness" or def.target == "DialFloor" then
					capped =
						SacrificeRules.apply(capped, { def = def, toolId = nil, waxGranted = def.waxGranted }).modifiers
				end
			end
			Harness.expect(capped.minBurnRate <= capped.maxBurnRate, "dial collapsed to an empty range")
			Harness.expect(
				capped.maxBurnRate < LightConfig.maxBurnRate,
				"a brightness cap must actually lower the ceiling"
			)
		end),

		Harness.test("grants stay flat with depth and inside the configured band", function()
			local def = BasinConfig.pool[1]
			local expected = math.clamp(def.waxGranted, BasinConfig.minimumGrant, BasinConfig.maximumGrant)
			Harness.near(SacrificeRules.grantFor(def, 1, 1), expected)
			Harness.near(SacrificeRules.grantFor(def, 100, 1), expected)
			Harness.near(
				SacrificeRules.grantFor(def, 100, 2),
				math.clamp(def.waxGranted / 2, BasinConfig.minimumGrant, BasinConfig.maximumGrant)
			)
			Harness.near(SacrificeRules.grantFor(def, 4, 0), expected)
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
			-- A player who has already taken every authored row gets no offers at all.
			local modifiers = SacrificeRules.defaultModifiers()
			local taken: { [string]: boolean } = {}
			for _, def in BasinConfig.pool do
				taken[def.id] = true
			end

			local offers = SacrificeRules.rollOffers(modifiers, taken, 1, 1, Random.new(7))
			Harness.equal(#offers, 0)
		end),

		Harness.test("progressive rows unlock in order", function()
			local first = SacrificeRules.rollOffers(SacrificeRules.defaultModifiers(), {}, 1, 1, Random.new(19))
			for _, offer in first do
				Harness.isNil(offer.def.requiresSacrificeId, "a later sacrifice stage appeared before its prerequisite")
			end
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
				elseif def.target == "DripTrail" then
					Harness.equal(result.modifiers.hasDripTrail, false)
				elseif def.target == "Relight" then
					Harness.equal(result.modifiers.canRelight, false)
				elseif def.target == "BeRelit" then
					Harness.equal(result.modifiers.canBeRelit, false)
				elseif def.target == "MoveSpeed" then
					Harness.near(result.modifiers.moveSpeedMultiplier, BasinConfig.effects.moveSpeedMultiplier)
				elseif def.target == "CupSpeed" then
					Harness.near(result.modifiers.cupSpeedMultiplier, BasinConfig.effects.cupSpeedMultiplier)
				elseif def.target == "DialFloor" then
					Harness.expect(
						result.modifiers.minBurnRate > LightConfig.minBurnRate,
						"the dial floor must actually rise"
					)
				elseif def.target == "Hearing" then
					Harness.equal(result.modifiers.canHearThreats, false)
				elseif def.target == "WaxCapacity" then
					Harness.near(result.modifiers.maxWaxMultiplier, BasinConfig.effects.maxWaxMultiplier)
				elseif def.target == "BurnEfficiency" then
					Harness.near(result.modifiers.waxDrainMultiplier, BasinConfig.effects.waxDrainMultiplier)
				elseif def.target == "ToolSpeed" then
					Harness.near(result.modifiers.toolCooldownMultiplier, BasinConfig.effects.toolCooldownMultiplier)
				elseif def.target == "FlareDuration" then
					Harness.near(result.modifiers.flareDurationMultiplier, BasinConfig.effects.flareDurationMultiplier)
				elseif def.target == "DecoyDuration" then
					Harness.near(result.modifiers.decoyDurationMultiplier, BasinConfig.effects.decoyDurationMultiplier)
				elseif def.target == "RelightCost" then
					Harness.near(result.modifiers.relightCostMultiplier, BasinConfig.effects.relightCostMultiplier)
				elseif def.target == "PeripheralDarkness" then
					Harness.near(result.modifiers.peripheralDarkness, BasinConfig.effects.peripheralDarknessOpacity)
				elseif def.target == "SightBrightness" then
					Harness.near(result.modifiers.sightBrightness, BasinConfig.effects.sightBrightness)
				elseif def.target == "SightSaturation" then
					Harness.near(result.modifiers.sightSaturation, BasinConfig.effects.sightSaturation)
				elseif def.target == "Tool" then
					Harness.equal(result.modifiers.lostTools.Flare, true)
				end
			end
		end),
	},
}

return suite

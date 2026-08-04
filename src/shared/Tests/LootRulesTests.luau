--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local LootRules = require(script.Parent.Parent.Logic.LootRules)
local CandleModifiers = require(script.Parent.Parent.Logic.CandleModifiers)
local LootConfig = require(script.Parent.Parent.Config.Loot)
local CandleConfig = require(script.Parent.Parent.Config.CandleModifiers)
local FeelConfig = require(script.Parent.Parent.Config.Feel)

local MAX_WAX = 1.3

local function context(candle: Types.CandleModifierState?, charges: { [Types.ToolId]: number }?, roll: number?)
	return {
		candle = candle or CandleModifiers.newState(),
		freeToolCharges = charges or {},
		matchCharges = 1,
		maxWax = MAX_WAX,
		roll = roll or 0,
	}
end

local suite: Harness.Suite = {
	name = "LootRules",
	tests = {
		Harness.test("every configured modifier pickup changes the candle without touching charges", function()
			for _, def in LootConfig.definitions do
				if def.kind ~= "CandleModifier" then
					continue
				end
				local charges: { [Types.ToolId]: number } = { Flare = 2 }
				local result = LootRules.apply(context(nil, charges), def)
				Harness.expect(result ~= nil, def.id .. " should be applicable")
				local applied = result :: LootRules.AppliedLoot
				Harness.expect(applied.outcome ~= nil, def.id .. " should report what it granted")
				Harness.equal((applied.outcome :: CandleModifiers.PickupOutcome).modifierId, def.modifierId)
				Harness.equal(applied.freeToolCharges.Flare, 2)
				Harness.equal(applied.matchCharges, 1)
				Harness.equal(charges.Flare, 2)
				Harness.expect(applied.freeToolCharges ~= charges, "loot application must clone the charge table")
			end
		end),

		-- THE INVARIANT THAT REPLACED "SWAPS BURN PROFILE": a modifier ADDS. Picking one up may never
		-- take away a stack, a reserve, or a sleeve the run already earned.
		Harness.test("collecting a modifier never removes something already collected", function()
			local carried: Types.CandleModifierState = {
				lifeWax = 3,
				brightWax = 2,
				frozen = { reserve = 0.04, atMaxSeconds = 4 },
				wicks = { wicks = 2, remaining = 120 },
				sleeve = { charges = 3.5 },
			}
			for _, def in LootConfig.definitions do
				if def.kind ~= "CandleModifier" then
					continue
				end
				local result = LootRules.apply(context(carried), def)
				local applied = (result :: LootRules.AppliedLoot).candle
				Harness.expect(applied.lifeWax >= carried.lifeWax, def.id .. " must not drop LifeWax stacks")
				Harness.expect(applied.brightWax >= carried.brightWax, def.id .. " must not drop BrightWax stacks")
				Harness.expect(applied.frozen.reserve >= carried.frozen.reserve, def.id .. " must not drop reserve")
				Harness.expect(applied.wicks.remaining >= carried.wicks.remaining, def.id .. " must not cut wick life")
				Harness.expect(applied.sleeve.charges >= carried.sleeve.charges, def.id .. " must not scuff a sleeve")
			end
		end),

		Harness.test("every configured charge pickup adds floored uses to its named tool", function()
			for _, def in LootConfig.definitions do
				if def.kind ~= "ToolCharge" then
					continue
				end
				local toolId = def.toolId :: Types.ToolId
				local charges: { [Types.ToolId]: number } = { [toolId] = 2 }
				local carried: Types.CandleModifierState = CandleModifiers.newState()
				carried.lifeWax = 4
				local result = LootRules.apply(context(carried, charges), def)
				Harness.expect(result ~= nil, def.id .. " should be applicable")
				local applied = result :: LootRules.AppliedLoot
				-- A tool charge is not a candle modifier and must leave the candle exactly alone.
				Harness.equal(applied.candle.lifeWax, 4)
				Harness.isNil(applied.outcome)
				Harness.equal(applied.freeToolCharges[toolId], 2 + math.floor(def.freeCharges :: number))
				Harness.equal(applied.matchCharges, 1)
				Harness.equal(charges[toolId], 2, "input charges must remain unchanged")
			end
		end),

		Harness.test("malformed content rows fail closed", function()
			local missingModifier: Types.LootDef = {
				id = "MissingModifier",
				displayName = "Missing Modifier",
				kind = "CandleModifier",
				spawnWeightByDepth = { 1 },
				color = Color3.new(),
			}
			Harness.isNil(LootRules.apply(context(), missingModifier))

			local missingCharge: Types.LootDef = {
				id = "MissingCharge",
				displayName = "Missing Charge",
				kind = "ToolCharge",
				spawnWeightByDepth = { 1 },
				toolId = "Flare",
				freeCharges = 0,
				color = Color3.new(),
			}
			Harness.isNil(LootRules.apply(context(), missingCharge))
		end),

		Harness.test("a configured Match adds only its self-relight charge", function()
			local match = LootConfig.definitions.Match
			local result = LootRules.apply(context(nil, { Flare = 2 }), match)
			Harness.expect(result ~= nil, "Match should be applicable")
			local applied = result :: LootRules.AppliedLoot
			Harness.equal(applied.candle.lifeWax, 0)
			Harness.equal(applied.freeToolCharges.Flare, 2)
			Harness.equal(applied.matchCharges, 1 + math.floor(match.matchCharges :: number))
		end),

		-- THE CANDLE SLEEVE'S RARITY IS A GATE, NOT A DICE ROLL. If this ever passes at a shallow depth
		-- the item has silently become an ordinary common, whatever its weight says.
		Harness.test("family depth gates decide availability before any weight is consulted", function()
			local sleeve = LootConfig.definitions.CandleSleeve
			local gates = sleeve.minDepthByFamily
			Harness.expect(gates ~= nil, "the Candle Sleeve must carry a family depth gate")
			for familyId, minimum in gates :: { [string]: number } do
				Harness.equal(
					LootRules.isAvailable(sleeve, familyId, minimum - 1),
					false,
					familyId .. " must refuse the sleeve one floor above its gate"
				)
				Harness.equal(
					LootRules.isAvailable(sleeve, familyId, minimum),
					true,
					familyId .. " must allow the sleeve at its gate"
				)
			end
			Harness.equal(
				LootRules.isAvailable(sleeve, "NOT_A_FAMILY", 999),
				false,
				"a gated row must never appear in a family it does not name"
			)
			-- Every ungated row stays available everywhere, so adding a gate is always a deliberate act.
			for _, def in LootConfig.definitions do
				if def.minDepthByFamily == nil then
					Harness.equal(LootRules.isAvailable(def, "STONE", 1), true, def.id .. " should be ungated")
				end
			end
		end),

		-- Every pickup explains itself the first time it is collected. Asserted both ways so the pool
		-- and its teaching text cannot drift apart: a new loot row that ships without a hint is silent
		-- forever, and a hint keyed to a row that no longer exists can never fire.
		Harness.test("every loot row has a first-pickup hint, and every hint has a row", function()
			local hints = FeelConfig.itemHints.messages
			for _, def in LootConfig.definitions do
				local message = hints[def.id]
				Harness.expect(message ~= nil, def.id .. " has no first-pickup hint")
				Harness.expect((message :: string):len() > 0, def.id .. " has an empty first-pickup hint")
			end
			for hintId in hints do
				Harness.expect(
					LootConfig.definitions[hintId] ~= nil,
					hintId .. " is a first-pickup hint for a loot row that does not exist"
				)
			end
		end),

		-- The design ceiling from the item brief, asserted rather than trusted to a comment: no single
		-- stacking pickup is worth more than 5%.
		Harness.test("no stacking modifier is worth more than five percent per pickup", function()
			Harness.expect(CandleConfig.lifeWax.perStack <= 0.05, "one LifeWax pickup must not exceed a 5% change")
			Harness.expect(CandleConfig.brightWax.perStack <= 0.05, "one BrightWax pickup must not exceed a 5% change")
		end),
	},
}

return suite

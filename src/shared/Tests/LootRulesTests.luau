--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local LootRules = require(script.Parent.Parent.Logic.LootRules)
local LootConfig = require(script.Parent.Parent.Config.Loot)

local suite: Harness.Suite = {
	name = "LootRules",
	tests = {
		Harness.test("every configured wax cache swaps profile without mutating charges", function()
			for _, def in LootConfig.definitions do
				if def.kind ~= "WaxType" then
					continue
				end
				local charges: { [Types.ToolId]: number } = { Flare = 2 }
				local result = LootRules.apply("Standard", charges, def)
				Harness.expect(result ~= nil, def.id .. " should be applicable")
				local applied = result :: LootRules.AppliedLoot
				Harness.equal(applied.waxTypeId, def.waxTypeId :: Types.WaxTypeId)
				Harness.equal(applied.freeToolCharges.Flare, 2)
				Harness.equal(charges.Flare, 2)
				Harness.expect(applied.freeToolCharges ~= charges, "loot application must clone the charge table")
			end
		end),

		Harness.test("every configured charge pickup adds floored uses to its named tool", function()
			for _, def in LootConfig.definitions do
				if def.kind ~= "ToolCharge" then
					continue
				end
				local toolId = def.toolId :: Types.ToolId
				local charges: { [Types.ToolId]: number } = { [toolId] = 2 }
				local result = LootRules.apply("Beeswax", charges, def)
				Harness.expect(result ~= nil, def.id .. " should be applicable")
				local applied = result :: LootRules.AppliedLoot
				Harness.equal(applied.waxTypeId, "Beeswax")
				Harness.equal(applied.freeToolCharges[toolId], 2 + math.floor(def.freeCharges :: number))
				Harness.equal(charges[toolId], 2, "input charges must remain unchanged")
			end
		end),

		Harness.test("malformed content rows fail closed", function()
			local missingWaxType: Types.LootDef = {
				id = "MissingWax",
				displayName = "Missing Wax",
				kind = "WaxType",
				spawnWeightByDepth = { 1 },
				color = Color3.new(),
			}
			Harness.isNil(LootRules.apply("Standard", {}, missingWaxType))

			local missingCharge: Types.LootDef = {
				id = "MissingCharge",
				displayName = "Missing Charge",
				kind = "ToolCharge",
				spawnWeightByDepth = { 1 },
				toolId = "Flare",
				freeCharges = 0,
				color = Color3.new(),
			}
			Harness.isNil(LootRules.apply("Standard", {}, missingCharge))
		end),
	},
}

return suite

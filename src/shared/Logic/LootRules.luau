--!strict
-- Pure in-run loot effects. The service owns pickup Instances and authority; this module maps
-- a data row to the next wax profile / free-charge table without touching Roblox Instances.

local Types = require(script.Parent.Parent.Types)

local LootRules = {}

export type AppliedLoot = {
	waxTypeId: Types.WaxTypeId,
	freeToolCharges: { [Types.ToolId]: number },
}

function LootRules.apply(
	currentWaxTypeId: Types.WaxTypeId,
	currentCharges: { [Types.ToolId]: number },
	def: Types.LootDef
): AppliedLoot?
	local nextCharges = table.clone(currentCharges)

	if def.kind == "WaxType" then
		local waxTypeId = def.waxTypeId
		if waxTypeId == nil then
			return nil
		end
		return {
			waxTypeId = waxTypeId,
			freeToolCharges = nextCharges,
		}
	end

	local toolId = def.toolId
	local freeCharges = def.freeCharges
	if toolId == nil or freeCharges == nil then
		return nil
	end
	local wholeCharges = math.floor(freeCharges)
	if wholeCharges <= 0 then
		return nil
	end
	nextCharges[toolId] = (nextCharges[toolId] or 0) + wholeCharges
	return {
		waxTypeId = currentWaxTypeId,
		freeToolCharges = nextCharges,
	}
end

return LootRules

--!strict
-- Pure in-run loot effects. The service owns pickup Instances and authority; this module maps
-- a data row to the next wax profile / free-charge table without touching Roblox Instances.

local Types = require(script.Parent.Parent.Types)

local LootRules = {}

export type AppliedLoot = {
	waxTypeId: Types.WaxTypeId,
	freeToolCharges: { [Types.ToolId]: number },
	matchCharges: number,
}

function LootRules.apply(
	currentWaxTypeId: Types.WaxTypeId,
	currentCharges: { [Types.ToolId]: number },
	currentMatchCharges: number,
	def: Types.LootDef
): AppliedLoot?
	local nextCharges = table.clone(currentCharges)
	local nextMatchCharges = math.max(0, math.floor(currentMatchCharges))

	if def.kind == "WaxType" then
		local waxTypeId = def.waxTypeId
		if waxTypeId == nil then
			return nil
		end
		return {
			waxTypeId = waxTypeId,
			freeToolCharges = nextCharges,
			matchCharges = nextMatchCharges,
		}
	end

	if def.kind == "SelfRelight" then
		local matchCharges = def.matchCharges
		if matchCharges == nil then
			return nil
		end
		local wholeCharges = math.floor(matchCharges)
		if wholeCharges <= 0 then
			return nil
		end
		return {
			waxTypeId = currentWaxTypeId,
			freeToolCharges = nextCharges,
			matchCharges = nextMatchCharges + wholeCharges,
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
		matchCharges = nextMatchCharges,
	}
end

return LootRules

--!strict
-- Pure in-run loot effects. The service owns pickup Instances and authority; this module maps
-- a data row to the next candle-modifier / free-charge table without touching Roblox Instances.

local Types = require(script.Parent.Parent.Types)
local CandleModifiers = require(script.Parent.CandleModifiers)
local DynamiteRules = require(script.Parent.DynamiteRules)

local LootRules = {}

-- What the collecting player already has, plus the two run facts a modifier row may need. `roll` is
-- a 0..1 value the caller supplies for rows with a rolled magnitude (Extra Wicks' wick count), so
-- the randomness lives with the service that owns the Random and this module stays deterministic.
export type CollectContext = {
	candle: Types.CandleModifierState,
	freeToolCharges: { [Types.ToolId]: number },
	matchCharges: number,
	dynamiteCharges: number,
	maxWax: Types.WaxAmount,
	roll: number,
}

export type AppliedLoot = {
	candle: Types.CandleModifierState,
	freeToolCharges: { [Types.ToolId]: number },
	matchCharges: number,
	dynamiteCharges: number,
	-- Present only for a modifier pickup: what the player actually got, for the collection message.
	outcome: CandleModifiers.PickupOutcome?,
	-- "Dynamite" rows only: how many sticks actually FITTED in the bag. Reported so the collection
	-- message can be honest about a crate that hit the carry cap, rather than claiming three when the
	-- player only got one. Nil for every other kind.
	dynamiteTaken: number?,
}

function LootRules.apply(ctx: CollectContext, def: Types.LootDef): AppliedLoot?
	local nextCharges = table.clone(ctx.freeToolCharges)
	local nextMatchCharges = math.max(0, math.floor(ctx.matchCharges))
	local nextDynamite = math.max(0, math.floor(ctx.dynamiteCharges))

	if def.kind == "CandleModifier" then
		local candle, outcome = CandleModifiers.applyPickup(ctx.candle, def.modifierId, ctx.maxWax, ctx.roll)
		if candle == nil or outcome == nil then
			return nil
		end
		return {
			candle = candle,
			freeToolCharges = nextCharges,
			matchCharges = nextMatchCharges,
			dynamiteCharges = nextDynamite,
			outcome = outcome,
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
			candle = ctx.candle,
			freeToolCharges = nextCharges,
			matchCharges = nextMatchCharges + wholeCharges,
			dynamiteCharges = nextDynamite,
		}
	end

	-- DYNAMITE. The carry cap lives in `DynamiteRules.grant`, and a cache that would overflow it is
	-- REFUSED rather than partially taken: leaving a crate on the floor with two sticks still in it is
	-- a better state than silently binning them, because the player can come back for it.
	if def.kind == "Dynamite" then
		local charges = def.dynamiteCharges
		if charges == nil then
			return nil
		end
		local wholeCharges = math.floor(charges)
		if wholeCharges <= 0 then
			return nil
		end
		local granted, taken = DynamiteRules.grant(nextDynamite, wholeCharges)
		if taken <= 0 then
			return nil
		end
		return {
			candle = ctx.candle,
			freeToolCharges = nextCharges,
			matchCharges = nextMatchCharges,
			dynamiteCharges = granted,
			dynamiteTaken = taken,
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
		candle = ctx.candle,
		freeToolCharges = nextCharges,
		matchCharges = nextMatchCharges,
		dynamiteCharges = nextDynamite,
	}
end

-- Is this row allowed to appear at all in this cave, at this depth? A row with no gate is available
-- everywhere from depth 1; a row that names families is refused in any family it does not name.
-- Shared by the planner and by the tests that assert the planner obeyed it.
function LootRules.isAvailable(def: Types.LootDef, familyId: string, depth: number): boolean
	local gates = def.minDepthByFamily
	if gates == nil then
		return true
	end
	local minimum = gates[familyId]
	if minimum == nil then
		return false
	end
	return depth >= minimum
end

return LootRules

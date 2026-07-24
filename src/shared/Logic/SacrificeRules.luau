--!strict
-- Pure: Basin sacrifice rules — what can be offered, what a sacrifice pays at depth, and what
-- accepting one does to a player's modifiers. Adding a sacrifice with an existing target is a
-- Config row; a genuinely new target adds one handler entry to the dispatch table below.

local Types = require(script.Parent.Parent.Types)
local BasinConfig = require(script.Parent.Parent.Config.Basin)
local LightConfig = require(script.Parent.Parent.Config.Light)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)

local SacrificeRules = {}

function SacrificeRules.defaultModifiers(): Types.SacrificeModifiers
	return {
		maxBurnRate = LightConfig.maxBurnRate,
		canSlide = true,
		dodgeDistanceMultiplier = 1,
		hasDripTrail = true,
		canRelight = true,
		canBeRelit = true,
		lostTools = {},
	}
end

local function ownedTools(modifiers: Types.SacrificeModifiers): { Types.ToolId }
	local owned: { Types.ToolId } = {}
	for id in ToolsConfig do
		if not modifiers.lostTools[id] then
			table.insert(owned, id)
		end
	end
	table.sort(owned) -- deterministic order so rng picks are seed-stable
	return owned
end

-- Can this pool entry still be offered to this player?
local function applicable(
	def: Types.SacrificeDef,
	modifiers: Types.SacrificeModifiers,
	takenIds: { [string]: boolean }
): boolean
	if takenIds[def.id] then
		return false
	end
	if def.target == "Slide" then
		return modifiers.canSlide
	elseif def.target == "Dodge" then
		return modifiers.dodgeDistanceMultiplier >= 1
	elseif def.target == "DripTrail" then
		return modifiers.hasDripTrail
	elseif def.target == "Relight" then
		return modifiers.canRelight
	elseif def.target == "BeRelit" then
		return modifiers.canBeRelit
	elseif def.target == "Tool" then
		return #ownedTools(modifiers) > 0
	end
	return true
end

-- Wax actually paid for a sacrifice at this depth for this player (DESIGN §10: rate worsens with depth).
function SacrificeRules.grantFor(def: Types.SacrificeDef, depth: number, nextBasinPenalty: number): number
	local scaled = def.waxGranted * BasinConfig.depthPenaltyPerFloor ^ (depth - 1)
	return scaled / math.max(nextBasinPenalty, 1)
end

-- Roll this visit's private offers: weighted, without replacement, only what still applies.
function SacrificeRules.rollOffers(
	modifiers: Types.SacrificeModifiers,
	takenIds: { [string]: boolean },
	depth: number,
	nextBasinPenalty: number,
	rng: Random
): { Types.ResolvedOffer }
	local candidates: { Types.SacrificeDef } = {}
	for _, def in BasinConfig.pool do
		if applicable(def, modifiers, takenIds) then
			table.insert(candidates, def)
		end
	end

	local offers: { Types.ResolvedOffer } = {}
	for _ = 1, math.min(BasinConfig.offersPerVisit, #candidates) do
		local totalWeight = 0
		for _, def in candidates do
			totalWeight += def.weight
		end
		local roll = rng:NextNumber() * totalWeight
		local pickedIndex = #candidates
		for index, def in candidates do
			roll -= def.weight
			if roll <= 0 then
				pickedIndex = index
				break
			end
		end
		local def = table.remove(candidates, pickedIndex) :: Types.SacrificeDef
		local toolId: Types.ToolId? = nil
		if def.target == "Tool" then
			local owned = ownedTools(modifiers)
			toolId = owned[rng:NextInteger(1, #owned)]
		end
		table.insert(offers, {
			def = def,
			toolId = toolId,
			waxGranted = SacrificeRules.grantFor(def, depth, nextBasinPenalty),
		})
	end
	return offers
end

export type ApplyResult = {
	modifiers: Types.SacrificeModifiers,
	doublesNextPrice: boolean,
}

-- Handler per target. Each takes and returns modifiers (copies — never mutates the input).
local handlers: { [Types.SacrificeTarget]: (Types.SacrificeModifiers, Types.ToolId?) -> (Types.SacrificeModifiers, boolean) } =
	{}

local function clone(modifiers: Types.SacrificeModifiers): Types.SacrificeModifiers
	local lostTools = table.clone(modifiers.lostTools)
	return {
		maxBurnRate = modifiers.maxBurnRate,
		canSlide = modifiers.canSlide,
		dodgeDistanceMultiplier = modifiers.dodgeDistanceMultiplier,
		hasDripTrail = modifiers.hasDripTrail,
		canRelight = modifiers.canRelight,
		canBeRelit = modifiers.canBeRelit,
		lostTools = lostTools,
	}
end

handlers.MaxBrightness = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.maxBurnRate = modifiers.maxBurnRate * BasinConfig.effects.maxBurnRateCapMultiplier
	return next_, false
end

handlers.Slide = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.canSlide = false
	return next_, false
end

handlers.Dodge = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.dodgeDistanceMultiplier = modifiers.dodgeDistanceMultiplier * BasinConfig.effects.dodgeShortenMultiplier
	return next_, false
end

handlers.DripTrail = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.hasDripTrail = false
	return next_, false
end

handlers.Relight = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.canRelight = false
	return next_, false
end

handlers.BeRelit = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.canBeRelit = false
	return next_, false
end

handlers.Tool = function(modifiers, toolId)
	local next_ = clone(modifiers)
	if toolId ~= nil then
		next_.lostTools[toolId] = true
	end
	return next_, false
end

handlers.NextBasinPriceDoubled = function(modifiers, _toolId)
	return clone(modifiers), true
end

function SacrificeRules.apply(modifiers: Types.SacrificeModifiers, offer: Types.ResolvedOffer): ApplyResult
	local handler = handlers[offer.def.target]
	local next_, doubles = handler(modifiers, offer.toolId)
	return { modifiers = next_, doublesNextPrice = doubles }
end

return SacrificeRules

--!strict
-- Pure: Basin sacrifice rules — what can be offered, what a sacrifice pays, and what
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
		minBurnRate = LightConfig.minBurnRate,
		moveSpeedMultiplier = 1,
		cupSpeedMultiplier = 1,
		hasDripTrail = true,
		canRelight = true,
		canBeRelit = true,
		canHearThreats = true,
		maxWaxMultiplier = 1,
		waxDrainMultiplier = 1,
		toolCooldownMultiplier = 1,
		flareDurationMultiplier = 1,
		decoyDurationMultiplier = 1,
		relightCostMultiplier = 1,
		peripheralDarkness = 0,
		sightBrightness = 0,
		sightSaturation = 0,
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

-- Can this pool entry still be offered to this player? The Basin never asks for something it has
-- already taken, so every target that removes or worsens a specific ability checks that ability's
-- live value rather than trusting the taken-id set alone.
local function applicable(
	def: Types.SacrificeDef,
	modifiers: Types.SacrificeModifiers,
	takenIds: { [string]: boolean }
): boolean
	if takenIds[def.id] then
		return false
	end
	if def.requiresSacrificeId ~= nil and not takenIds[def.requiresSacrificeId] then
		return false
	end
	if def.target == "CupSpeed" then
		-- Pointless to sell once CUP itself is gone.
		return not modifiers.lostTools.Cup
	elseif def.target == "DripTrail" then
		return modifiers.hasDripTrail
	elseif def.target == "Relight" then
		return modifiers.canRelight
	elseif def.target == "BeRelit" then
		return modifiers.canBeRelit
	elseif def.target == "Hearing" then
		return modifiers.canHearThreats
	elseif def.target == "ToolSpeed" then
		return #ownedTools(modifiers) > 0
	elseif def.target == "FlareDuration" then
		return not modifiers.lostTools.Flare
	elseif def.target == "DecoyDuration" then
		return not modifiers.lostTools.Decoy
	elseif def.target == "RelightCost" then
		return modifiers.canRelight
	elseif def.target == "Tool" then
		return #ownedTools(modifiers) > 0
	end
	return true
end

-- The permanent sacrifice is the scaling cost, so depth never reduces the grant.
function SacrificeRules.grantFor(def: Types.SacrificeDef, _depth: number, nextBasinPenalty: number): number
	local penalized = def.waxGranted / math.max(nextBasinPenalty, 1)
	return math.clamp(penalized, BasinConfig.minimumGrant, BasinConfig.maximumGrant)
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
		minBurnRate = modifiers.minBurnRate,
		moveSpeedMultiplier = modifiers.moveSpeedMultiplier,
		cupSpeedMultiplier = modifiers.cupSpeedMultiplier,
		hasDripTrail = modifiers.hasDripTrail,
		canRelight = modifiers.canRelight,
		canBeRelit = modifiers.canBeRelit,
		canHearThreats = modifiers.canHearThreats,
		maxWaxMultiplier = modifiers.maxWaxMultiplier,
		waxDrainMultiplier = modifiers.waxDrainMultiplier,
		toolCooldownMultiplier = modifiers.toolCooldownMultiplier,
		flareDurationMultiplier = modifiers.flareDurationMultiplier,
		decoyDurationMultiplier = modifiers.decoyDurationMultiplier,
		relightCostMultiplier = modifiers.relightCostMultiplier,
		peripheralDarkness = modifiers.peripheralDarkness,
		sightBrightness = modifiers.sightBrightness,
		sightSaturation = modifiers.sightSaturation,
		lostTools = lostTools,
	}
end

handlers.MaxBrightness = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.maxBurnRate = modifiers.maxBurnRate * BasinConfig.effects.maxBurnRateCapMultiplier
	-- A ceiling can never fall below the floor; the dial would have nowhere to sit.
	next_.maxBurnRate = math.max(next_.maxBurnRate, next_.minBurnRate)
	return next_, false
end

handlers.DialFloor = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	local span = LightConfig.maxBurnRate - LightConfig.minBurnRate
	local raised = modifiers.minBurnRate + span * BasinConfig.effects.dialFloorRaiseFraction
	next_.minBurnRate = math.min(math.max(modifiers.minBurnRate, raised), modifiers.maxBurnRate)
	return next_, false
end

handlers.MoveSpeed = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.moveSpeedMultiplier = modifiers.moveSpeedMultiplier * BasinConfig.effects.moveSpeedMultiplier
	return next_, false
end

handlers.CupSpeed = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.cupSpeedMultiplier = modifiers.cupSpeedMultiplier * BasinConfig.effects.cupSpeedMultiplier
	return next_, false
end

handlers.Hearing = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.canHearThreats = false
	return next_, false
end

handlers.WaxCapacity = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.maxWaxMultiplier = modifiers.maxWaxMultiplier * BasinConfig.effects.maxWaxMultiplier
	return next_, false
end

handlers.BurnEfficiency = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.waxDrainMultiplier = modifiers.waxDrainMultiplier * BasinConfig.effects.waxDrainMultiplier
	return next_, false
end

handlers.ToolSpeed = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.toolCooldownMultiplier = modifiers.toolCooldownMultiplier * BasinConfig.effects.toolCooldownMultiplier
	return next_, false
end

handlers.FlareDuration = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.flareDurationMultiplier = modifiers.flareDurationMultiplier * BasinConfig.effects.flareDurationMultiplier
	return next_, false
end

handlers.DecoyDuration = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.decoyDurationMultiplier = modifiers.decoyDurationMultiplier * BasinConfig.effects.decoyDurationMultiplier
	return next_, false
end

handlers.RelightCost = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.relightCostMultiplier = modifiers.relightCostMultiplier * BasinConfig.effects.relightCostMultiplier
	return next_, false
end

handlers.PeripheralDarkness = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.peripheralDarkness =
		math.clamp(modifiers.peripheralDarkness + BasinConfig.effects.peripheralDarknessOpacity, 0, 1)
	return next_, false
end

handlers.SightBrightness = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.sightBrightness = math.clamp(modifiers.sightBrightness + BasinConfig.effects.sightBrightness, -1, 1)
	return next_, false
end

handlers.SightSaturation = function(modifiers, _toolId)
	local next_ = clone(modifiers)
	next_.sightSaturation = math.clamp(modifiers.sightSaturation + BasinConfig.effects.sightSaturation, -1, 1)
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

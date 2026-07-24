--!strict
-- Cave access progression. Unlocks are derived from the persisted currency earned at braziers.
-- Tier selection is consumed by the lobby/run flow; the tier rows remain data, not branches.

local Types = require(script.Parent.Parent.Types)
local CaveTierConfig = require(script.Parent.Parent.Config.CaveTiers)
local Persistence = require(script.Parent.Persistence)

export type CaveTier = CaveTierConfig.CaveTier

export type CaveTiersInterface = {
	list: () -> { CaveTier },
	get: (tierId: number) -> CaveTier?,
	isUnlocked: (playerId: Types.PlayerId, tierId: number) -> boolean,
	refreshUnlocks: (playerId: Types.PlayerId) -> number,
}

local TIERS: { CaveTier } = CaveTierConfig

local function getTier(tierId: number): CaveTier?
	for _, tier in TIERS do
		if tier.id == tierId then
			return tier
		end
	end
	return nil
end

local CaveTiers: CaveTiersInterface = {
	list = function()
		return TIERS
	end,

	get = getTier,

	isUnlocked = function(playerId, tierId)
		local tier = getTier(tierId)
		if tier == nil then
			return false
		end
		return tierId <= Persistence.get(playerId).unlockedCaveTier
	end,

	refreshUnlocks = function(playerId)
		local profile = Persistence.get(playerId)
		local unlocked = profile.unlockedCaveTier
		for _, tier in TIERS do
			if profile.currency >= tier.requiredCurrency then
				unlocked = math.max(unlocked, tier.id)
			end
		end
		if unlocked ~= profile.unlockedCaveTier then
			profile.unlockedCaveTier = unlocked
			Persistence.save(playerId, profile)
		end
		return unlocked
	end,
}

return CaveTiers

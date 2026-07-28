--!strict
-- Cave access. Tier rows remain data (Config/CaveTiers); this module owns only evaluation and the
-- two things a player can actually do about access — pay to descend once, or buy the cave outright.
--
-- PHASE 8 REPLACED A DERIVED THRESHOLD WITH A PURCHASE. Access used to be a function of lifetime
-- currency: cross 1500 and The Descent was yours forever, whether or not you meant to spend anything.
-- That made the deep caves free precisely when a player stopped needing help, and it meant the
-- currency number could never be spent on anything without also revoking access.
--
-- Now there are exactly two ways in:
--   * PAY THE FEE, every descent, per player. The money is gone when you step into the elevator, and
--     it does not come back if the run goes badly. This is the normal way to play.
--   * OWN THE CAVE, once, for roughly fifteen descents' worth. A long-term goal, not a shortcut.
--
-- Every currency movement in here runs through `Persistence.applyTransaction` with a caller-supplied
-- id, so a retried purchase charges once and a retried refund credits once.

local Types = require(script.Parent.Parent.Types)
local CaveTierConfig = require(script.Parent.Parent.Config.CaveTiers)
local Persistence = require(script.Parent.Persistence)

export type CaveTier = CaveTierConfig.CaveTier

export type PurchaseResult = {
	ok: boolean,
	balance: number,
	failure: string?,
}

export type CaveTiersInterface = {
	list: () -> { CaveTier },
	get: (tierId: number) -> CaveTier?,
	isFree: (tierId: number) -> boolean,
	owns: (playerId: Types.PlayerId, tierId: number) -> boolean,
	-- May this player descend into this tier at all — free, owned, or affordable right now?
	canAfford: (playerId: Types.PlayerId, tierId: number) -> boolean,
	entryFeeFor: (playerId: Types.PlayerId, tierId: number) -> number,
	chargeEntry: (playerId: Types.PlayerId, tierId: number, transactionId: string) -> PurchaseResult,
	refundEntry: (playerId: Types.PlayerId, tierId: number, transactionId: string) -> PurchaseResult,
	purchasePermanent: (playerId: Types.PlayerId, tierId: number, transactionId: string) -> PurchaseResult,
	ownedTiers: (playerId: Types.PlayerId) -> { number },
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

local function isFree(tierId: number): boolean
	local tier = getTier(tierId)
	return tier ~= nil and tier.entryFee <= 0
end

local function owns(playerId: Types.PlayerId, tierId: number): boolean
	return table.find(Persistence.get(playerId).ownedCaveTiers, tierId) ~= nil
end

-- What this descent actually costs this player, right now. Zero for a free cave and zero for one they
-- already own — the single place that "owning it means never paying again" is expressed, so no caller
-- has to remember to check ownership before charging.
local function entryFeeFor(playerId: Types.PlayerId, tierId: number): number
	local tier = getTier(tierId)
	if tier == nil then
		return 0
	end
	if tier.entryFee <= 0 or owns(playerId, tierId) then
		return 0
	end
	return math.max(0, math.floor(tier.entryFee))
end

local CaveTiers: CaveTiersInterface = {
	list = function()
		return TIERS
	end,

	get = getTier,
	isFree = isFree,
	owns = owns,
	entryFeeFor = entryFeeFor,

	ownedTiers = function(playerId)
		return Persistence.get(playerId).ownedCaveTiers
	end,

	canAfford = function(playerId, tierId)
		local tier = getTier(tierId)
		if tier == nil then
			return false
		end
		local fee = entryFeeFor(playerId, tierId)
		if fee <= 0 then
			return true
		end
		return Persistence.get(playerId).currency >= fee
	end,

	-- Take the fee. Called once per player at the moment a descent is committed, never speculatively:
	-- an expedition that fails to launch must refund (see `refundEntry`), and the cleanest way to keep
	-- that honest is for the charge to happen as late as possible.
	chargeEntry = function(playerId, tierId, transactionId)
		local fee = entryFeeFor(playerId, tierId)
		if fee <= 0 then
			return { ok = true, balance = Persistence.get(playerId).currency }
		end
		local result = Persistence.applyTransaction(playerId, transactionId, -fee)
		return { ok = result.ok, balance = result.balance, failure = result.failure }
	end,

	-- Give it back. Used only when an expedition never actually happened — a failed teleport, a party
	-- that dissolved before the run began. Deliberately a SEPARATE transaction id from the charge
	-- (the caller composes it), so that a refund cannot be mistaken for a replay of the charge and
	-- silently skipped.
	refundEntry = function(playerId, tierId, transactionId)
		local tier = getTier(tierId)
		if tier == nil or tier.entryFee <= 0 then
			return { ok = true, balance = Persistence.get(playerId).currency }
		end
		local result = Persistence.applyTransaction(playerId, transactionId, math.max(0, math.floor(tier.entryFee)))
		return { ok = result.ok, balance = result.balance, failure = result.failure }
	end,

	-- Buy the cave outright. Charges first and records ownership only if the charge actually landed,
	-- so a failed or refused payment can never grant access.
	purchasePermanent = function(playerId, tierId, transactionId)
		local tier = getTier(tierId)
		if tier == nil then
			return { ok = false, balance = Persistence.get(playerId).currency, failure = "UnknownTier" }
		end
		if tier.permanentUnlockPrice <= 0 then
			return { ok = false, balance = Persistence.get(playerId).currency, failure = "NotForSale" }
		end
		if owns(playerId, tierId) then
			return { ok = false, balance = Persistence.get(playerId).currency, failure = "AlreadyOwned" }
		end

		local price = math.max(0, math.floor(tier.permanentUnlockPrice))
		local result = Persistence.applyTransaction(playerId, transactionId, -price)
		if not result.ok then
			return { ok = false, balance = result.balance, failure = result.failure }
		end
		-- The charge is committed. Record ownership immediately and unconditionally: if this write
		-- were to be skipped the player would have paid for nothing, so there is no branch here.
		local profile = Persistence.get(playerId)
		if table.find(profile.ownedCaveTiers, tierId) == nil then
			table.insert(profile.ownedCaveTiers, tierId)
			Persistence.save(playerId, profile)
		end
		return { ok = true, balance = result.balance }
	end,
}

return CaveTiers

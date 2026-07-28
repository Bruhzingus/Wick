--!strict
-- The Lamp Network's persistence boundary. Node and contract rows are data (Config/LampNetwork) and
-- every rule about them is pure (Logic/LampRules); this module owns only the two things that need a
-- live profile — moving currency, and recording what a player bought or agreed to.
--
-- MODELLED ON Interfaces/CaveTiers, with one deliberate divergence. A cave tier is granted by
-- reading a profile, mutating the copy, and saving it back, which is safe today only because nothing
-- yields between those three calls — a property of the current call sites rather than of the code. A
-- lamp node is granted by `Persistence.grantLampNode`, which mutates the live session directly and
-- never yields, so the charge and the grant sit in one indivisible block. See `purchaseNode`.
--
-- NOTHING IN HERE DECIDES A PRICE FROM ANYTHING A CLIENT SENT. Callers pass a node id and a
-- transaction id; every cost, prerequisite and eligibility test is re-derived from config and the
-- live profile at the moment of the call.

local Types = require(script.Parent.Parent.Types)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)
local LampRules = require(script.Parent.Parent.Logic.LampRules)
local Persistence = require(script.Parent.Persistence)

export type LampNode = LampConfig.LampNode
export type LampContract = LampConfig.LampContract

export type PurchaseResult = {
	ok: boolean,
	balance: number,
	failure: string?,
	-- The specific unmet prerequisite, when `failure` is "MissingPrerequisite". Lets the caller name
	-- the node a player has to go and buy instead of saying "you can't do that".
	missingNode: string?,
}

export type ContractResult = {
	ok: boolean,
	failure: string?,
}

export type LampNetworkInterface = {
	isEnabled: () -> boolean,
	list: () -> { LampNode },
	get: (nodeId: string) -> LampNode?,
	owns: (playerId: Types.PlayerId, nodeId: string) -> boolean,
	ownedNodes: (playerId: Types.PlayerId) -> { string },
	missingPrerequisite: (playerId: Types.PlayerId, nodeId: string) -> string?,
	canPurchase: (playerId: Types.PlayerId, nodeId: string) -> PurchaseResult,
	purchaseNode: (playerId: Types.PlayerId, nodeId: string, transactionId: string) -> PurchaseResult,
	availableContracts: (playerId: Types.PlayerId, partySize: number) -> { LampContract },
	getContract: (contractId: string) -> LampContract?,
	acceptContract: (playerId: Types.PlayerId, contractId: string, partySize: number) -> ContractResult,
	acceptWager: (playerId: Types.PlayerId, targetDepth: number) -> ContractResult,
	-- Clears whatever bet is pending. Called when a run resolves and when a party dissolves before one
	-- ever started, so an unused contract is never silently spent.
	clearPending: (playerId: Types.PlayerId) -> (),
	-- The payout scalar this player's pending bet contributes, in permille. Never below the neutral
	-- rate, so a caller can multiply unconditionally.
	pendingPermille: (playerId: Types.PlayerId, reachedDepth: number) -> number,
	minimumWagerTarget: (playerId: Types.PlayerId) -> number,
}

local function owns(playerId: Types.PlayerId, nodeId: string): boolean
	return LampRules.ownsNode(Persistence.get(playerId).ownedLampNodes, nodeId)
end

-- Everything that must be true before a single unit of currency moves. Shared by `canPurchase` (which
-- only asks) and `purchaseNode` (which then acts), so the two can never disagree about eligibility.
-- Contains no yields: `purchaseNode` relies on that.
local function validate(playerId: Types.PlayerId, nodeId: string): PurchaseResult?
	local profile = Persistence.get(playerId)
	local balance = profile.currency
	if not LampRules.isEnabled() then
		return { ok = false, balance = balance, failure = "Disabled" }
	end
	if LampRules.getNode(nodeId) == nil then
		return { ok = false, balance = balance, failure = "UnknownNode" }
	end
	if LampRules.ownsNode(profile.ownedLampNodes, nodeId) then
		return { ok = false, balance = balance, failure = "AlreadyOwned" }
	end
	local missing = LampRules.missingPrerequisite(profile.ownedLampNodes, nodeId)
	if missing ~= nil then
		return { ok = false, balance = balance, failure = "MissingPrerequisite", missingNode = missing }
	end
	-- A purchase must never land while the profile is still loading: the charge would go into a
	-- fallback cache that is about to be discarded, and the player would have bought nothing.
	if not Persistence.isLoaded(playerId) then
		return { ok = false, balance = balance, failure = "ProfileNotLoaded" }
	end
	return nil
end

local LampNetwork: LampNetworkInterface

LampNetwork = {
	isEnabled = LampRules.isEnabled,
	list = LampRules.nodes,
	get = LampRules.getNode,
	getContract = LampRules.getContract,
	owns = owns,

	ownedNodes = function(playerId)
		return Persistence.get(playerId).ownedLampNodes
	end,

	missingPrerequisite = function(playerId, nodeId)
		return LampRules.missingPrerequisite(Persistence.get(playerId).ownedLampNodes, nodeId)
	end,

	-- Asks without acting. Used by the prompt handler to produce a specific refusal before anything is
	-- attempted, and by tests to assert the gate independently of the transaction.
	canPurchase = function(playerId, nodeId)
		local failure = validate(playerId, nodeId)
		if failure ~= nil then
			return failure
		end
		local balance = Persistence.get(playerId).currency
		if balance < LampRules.costOf(nodeId) then
			return { ok = false, balance = balance, failure = "InsufficientFunds" }
		end
		return { ok = true, balance = balance }
	end,

	-- BUY A NODE. The whole atomicity contract lives in this function, in this order:
	--
	--   1. Validate with no yields.
	--   2. Charge through `applyTransaction`, which is itself yield-free and replay-guarded.
	--   3. On failure, grant nothing. Nothing was charged.
	--   4. On success, grant IMMEDIATELY, in the same yield-free block.
	--
	-- THE PROPERTY THAT MAKES A REFUND FEATURE UNNECESSARY: `transactionId` is derived from
	-- (player, node) by the caller rather than generated, so every attempt at the same purchase
	-- produces the same id. If an earlier attempt charged but never reached the grant, the retry sees
	-- a duplicate, charges nothing a second time, and completes the grant. The retry path is the
	-- repair path, and the only two reachable end states are "charged and owned" or "neither".
	--
	-- Note that a duplicate is deliberately NOT an early return — `applyTransaction` reports it as
	-- `ok = true` and execution falls straight through to the grant below.
	purchaseNode = function(playerId, nodeId, transactionId)
		local failure = validate(playerId, nodeId)
		if failure ~= nil then
			return failure
		end
		local charge = Persistence.applyTransaction(playerId, transactionId, -LampRules.costOf(nodeId))
		if not charge.ok then
			return { ok = false, balance = charge.balance, failure = charge.failure }
		end

		-- The charge is committed. There is no branch here and there must never be one: a grant that
		-- could be skipped is a player who paid for nothing.
		if not Persistence.grantLampNode(playerId, nodeId) then
			-- Only reachable if the session died between the charge and this line. Loud, because it is
			-- the one state this design exists to make impossible — and recoverable, because the next
			-- attempt replays the same transaction id and grants without charging again.
			warn(
				string.format(
					"[WICK] LampNetwork: charged user %d for %s but could not record it;"
						.. " retrying the purchase will grant it without charging again.",
					playerId,
					nodeId
				)
			)
			return { ok = false, balance = charge.balance, failure = "GrantFailed" }
		end
		return { ok = true, balance = charge.balance }
	end,

	-----------------------------------------------------------------------------------------------
	-- Contracts and wagers. One bet per run, ever — accepting either clears the other.
	-----------------------------------------------------------------------------------------------

	availableContracts = function(playerId, partySize)
		return LampRules.availableContracts(Persistence.get(playerId).ownedLampNodes, partySize)
	end,

	acceptContract = function(playerId, contractId, partySize)
		if not LampRules.contractsEnabled() then
			return { ok = false, failure = "Disabled" }
		end
		local contract = LampRules.getContract(contractId)
		if contract == nil then
			return { ok = false, failure = "UnknownContract" }
		end
		if not owns(playerId, contract.unlockNode) then
			return { ok = false, failure = "Locked" }
		end
		if partySize < contract.minPartySize then
			return { ok = false, failure = "PartyTooSmall" }
		end
		if not Persistence.isLoaded(playerId) then
			return { ok = false, failure = "ProfileNotLoaded" }
		end

		local profile = Persistence.get(playerId)
		profile.activeContractId = contract.id
		-- One bet per run. Taking a contract abandons any wager, and vice versa.
		profile.activeWagerDepth = nil
		Persistence.save(playerId, profile)
		return { ok = true }
	end,

	minimumWagerTarget = function(playerId)
		return LampRules.minimumWagerTarget(Persistence.get(playerId).deepestFloor)
	end,

	acceptWager = function(playerId, targetDepth)
		if not LampRules.wagerEnabled() then
			return { ok = false, failure = "Disabled" }
		end
		if not owns(playerId, LampConfig.wager.unlockNode) then
			return { ok = false, failure = "Locked" }
		end
		if typeof(targetDepth) ~= "number" or targetDepth ~= targetDepth or targetDepth % 1 ~= 0 then
			return { ok = false, failure = "InvalidTarget" }
		end
		if not Persistence.isLoaded(playerId) then
			return { ok = false, failure = "ProfileNotLoaded" }
		end
		if targetDepth < LampNetwork.minimumWagerTarget(playerId) then
			return { ok = false, failure = "TargetTooShallow" }
		end

		local profile = Persistence.get(playerId)
		profile.activeWagerDepth = math.floor(targetDepth)
		profile.activeContractId = nil
		Persistence.save(playerId, profile)
		return { ok = true }
	end,

	clearPending = function(playerId)
		if not Persistence.isLoaded(playerId) then
			return
		end
		local profile = Persistence.get(playerId)
		if profile.activeContractId == nil and profile.activeWagerDepth == nil then
			return
		end
		profile.activeContractId = nil
		profile.activeWagerDepth = nil
		Persistence.save(playerId, profile)
	end,

	pendingPermille = function(playerId, reachedDepth)
		local profile = Persistence.get(playerId)
		return LampRules.resolvePermille(profile.activeContractId, profile.activeWagerDepth, reachedDepth)
	end,
}

return LampNetwork

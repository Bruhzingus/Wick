--!strict
-- Pure Lamp Network rules: what a node costs, what it needs first, which contracts a given set of
-- owned nodes may sign, and what a pending bet is worth. Config rows are data
-- (Config/LampNetwork); this file is the only place they are interpreted.
--
-- NOTHING HERE TOUCHES A PROFILE, A PLAYER, OR A ROBLOX SERVICE. Every function takes the owned-node
-- list as an argument rather than looking one up, which is what lets the whole progression gate be
-- tested cold against hand-written sets — including the ones a real profile could never produce, like
-- owning a leaf without its trunk. Interfaces/LampNetwork is the thin adapter that reads a profile
-- and calls in here; it holds the currency movement and nothing else.
--
-- THE PAYOUT SCALARS ARE PERMILLE INTEGERS and never become floats at any point, for the same reason
-- every other number in the economy is an integer (Config/Extraction): currency is persisted, and a
-- persisted float is a future argument about whether someone has 349.99999 or 350.

local LampConfig = require(script.Parent.Parent.Config.LampNetwork)

local LampRules = {}

export type LampNode = LampConfig.LampNode
export type LampContract = LampConfig.LampContract

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function LampRules.isEnabled(): boolean
	return LampConfig.enabled
end

function LampRules.contractsEnabled(): boolean
	return LampConfig.enabled and LampConfig.contracts.enabled
end

function LampRules.wagerEnabled(): boolean
	return LampConfig.enabled and LampConfig.wager.enabled
end

function LampRules.nodes(): { LampNode }
	return LampConfig.nodes
end

function LampRules.contracts(): { LampContract }
	return LampConfig.contracts.rows
end

function LampRules.getNode(nodeId: string): LampNode?
	if typeof(nodeId) ~= "string" then
		return nil
	end
	for _, node in LampConfig.nodes do
		if node.id == nodeId then
			return node
		end
	end
	return nil
end

function LampRules.getContract(contractId: string): LampContract?
	if typeof(contractId) ~= "string" then
		return nil
	end
	for _, contract in LampConfig.contracts.rows do
		if contract.id == contractId then
			return contract
		end
	end
	return nil
end

-- What a node costs, as a whole non-negative number. A mistyped or negative config cost resolves to
-- zero rather than to a charge nobody can explain.
function LampRules.costOf(nodeId: string): number
	local node = LampRules.getNode(nodeId)
	if node == nil or not isFiniteNumber(node.cost) then
		return 0
	end
	return math.max(0, math.floor(node.cost))
end

function LampRules.ownsNode(owned: { string }, nodeId: string): boolean
	return table.find(owned, nodeId) ~= nil
end

-- Which requirement this owned-set has not met for `nodeId`, or nil for none.
--
-- Returns the first unmet hard requirement, and for the any-of gate the CHEAPEST unowned candidate —
-- so the message a player ends up reading points at the shortest road in rather than at whichever
-- row happened to be written first.
function LampRules.missingPrerequisite(owned: { string }, nodeId: string): string?
	local node = LampRules.getNode(nodeId)
	if node == nil then
		return nil
	end
	for _, required in node.requires do
		if not LampRules.ownsNode(owned, required) then
			return required
		end
	end
	if node.requiresAnyCount <= 0 then
		return nil
	end

	local satisfied = 0
	local cheapest: LampNode? = nil
	for _, candidateId in node.requiresAny do
		if LampRules.ownsNode(owned, candidateId) then
			satisfied += 1
			continue
		end
		local candidate = LampRules.getNode(candidateId)
		if candidate ~= nil and (cheapest == nil or candidate.cost < (cheapest :: LampNode).cost) then
			cheapest = candidate
		end
	end
	if satisfied >= node.requiresAnyCount then
		return nil
	end
	return if cheapest ~= nil then (cheapest :: LampNode).id else node.requiresAny[1]
end

-- Every contract this owned-set may sign at this party size. Order follows the config, so the board
-- always lists the standing rows before the hard ones.
function LampRules.availableContracts(owned: { string }, partySize: number): { LampContract }
	local rows: { LampContract } = {}
	if not LampRules.contractsEnabled() then
		return rows
	end
	for _, contract in LampConfig.contracts.rows do
		if LampRules.ownsNode(owned, contract.unlockNode) and partySize >= contract.minPartySize then
			table.insert(rows, contract)
		end
	end
	return rows
end

-- The shallowest depth a player with this record may wager on: strictly deeper than they have ever
-- actually been, and never shallower than the configured floor.
--
-- THIS ONE RULE IS WHAT MAKES THE WAGER A BET. Without it a player names the depth they were going to
-- reach anyway and collects a multiplier for doing nothing differently. With it the target is a
-- personal record attempt by construction, and the difficulty self-scales forever without anybody
-- retuning a number.
function LampRules.minimumWagerTarget(deepestFloor: number): number
	local reached = if isFiniteNumber(deepestFloor) and deepestFloor > 0 then math.floor(deepestFloor) else 0
	return math.max(LampConfig.wager.minimumTarget, reached + 1)
end

-- What a wager on `targetDepth` pays if it lands, in permille. Anything invalid or too shallow pays
-- the neutral rate rather than erroring, so a corrupted target is worth nothing extra instead of
-- being worth something surprising.
function LampRules.wagerPermilleFor(targetDepth: number): number
	local wager = LampConfig.wager
	if not isFiniteNumber(targetDepth) or targetDepth % 1 ~= 0 or targetDepth < wager.minimumTarget then
		return wager.basePermille
	end
	local scaled = wager.basePermille + wager.permillePerDepth * (targetDepth - (wager.minimumTarget - 1))
	return math.clamp(math.floor(scaled), wager.basePermille, wager.maximumPermille)
end

-- What a pending bet contributes to a payout, in permille. Always at or above the neutral rate, so a
-- caller can multiply unconditionally and never has to branch on "did they have one".
--
-- A CONTRACT THAT WAS ACCEPTED ALWAYS PAYS ITS RATE HERE. Whether its rule was actually kept is the
-- run's business, and a broken rule is reported by the caller passing `nil` rather than by this
-- function trying to guess what happened in the cave. A wager pays only if `reachedDepth` got there.
--
-- A contract and a wager are mutually exclusive upstream; if both somehow arrive, the contract wins
-- and the wager is ignored, so no combination of stale profile fields can ever stack two scalars.
function LampRules.resolvePermille(contractId: string?, wagerDepth: number?, reachedDepth: number): number
	local base = LampConfig.wager.basePermille
	if not LampConfig.enabled then
		return base
	end

	if contractId ~= nil and LampConfig.contracts.enabled then
		local contract = LampRules.getContract(contractId)
		if contract ~= nil and isFiniteNumber(contract.payoutPermille) then
			return math.max(base, math.floor(contract.payoutPermille))
		end
	end

	if wagerDepth ~= nil and LampConfig.wager.enabled then
		if isFiniteNumber(wagerDepth) and isFiniteNumber(reachedDepth) and reachedDepth >= wagerDepth then
			return LampRules.wagerPermilleFor(wagerDepth)
		end
	end
	return base
end

return LampRules

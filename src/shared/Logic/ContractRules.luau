--!strict
-- Pure: what a signed Lamp Network contract does to a run. Contract rows and their effects are data
-- (Config/LampNetwork); this module is the only place that data is interpreted.
--
-- THE ONE INVARIANT, and every function here exists to hold it: A CONTRACT CAN ONLY EVER MAKE A RUN
-- WORSE. Tools are removed and never granted, wax multipliers are clamped to at most 1 so a mistyped
-- 1.5 cannot hand somebody a bigger candle, and the two void conditions can only take a payout away.
-- A contract that made a run easier would be the pure-power upgrade the whole track forbids, and it
-- would be paying the player extra for the privilege.
--
-- NOTHING HERE TOUCHES A PLAYER, A PROFILE, OR A ROBLOX SERVICE. Callers pass the contract id and the
-- facts about the run; this returns what should change. That is what lets every rule be tested cold
-- against hand-written state, including combinations a real run could not produce.

local LampConfig = require(script.Parent.Parent.Config.LampNetwork)

local ContractRules = {}

export type Effect = LampConfig.LampContractEffect

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- A multiplier a contract is allowed to apply: finite, above zero, and never above 1.
--
-- The upper clamp is the load-bearing half. A contract row is the only place in this codebase where a
-- designer writes a number that scales a candle, and the difference between 0.6 and 1.6 is one
-- keystroke — so the type system's job is done here rather than trusted to review.
local function safeMultiplier(value: number): number
	if not isFiniteNumber(value) or value <= 0 then
		return 1
	end
	return math.min(value, 1)
end

-- The neutral effect: a run under no contract at all. Returned for an unknown id, a rolled-back
-- contract layer, and a voided contract, so every caller can apply the result unconditionally instead
-- of branching on "did they have one".
local NEUTRAL: Effect = {
	lostTools = {},
	startingWaxMultiplier = 1,
	maxWaxMultiplier = 1,
	sealsBasin = false,
	minimumPayingDepth = 0,
	tetherStuds = 0,
	tetherGraceSeconds = 0,
	voidsOnPartyDeath = false,
}

function ContractRules.neutral(): Effect
	return NEUTRAL
end

-- What this contract does, sanitised. `nil`, an unknown id, and a rolled-back layer all resolve to
-- neutral rather than erroring — a run must always be playable, whatever state the config is in.
function ContractRules.effectFor(contractId: string?): Effect
	if contractId == nil or not LampConfig.enabled or not LampConfig.contracts.enabled then
		return NEUTRAL
	end
	for _, contract in LampConfig.contracts.rows do
		if contract.id == contractId then
			local raw = contract.effect
			return {
				lostTools = raw.lostTools,
				startingWaxMultiplier = safeMultiplier(raw.startingWaxMultiplier),
				maxWaxMultiplier = safeMultiplier(raw.maxWaxMultiplier),
				sealsBasin = raw.sealsBasin == true,
				-- A negative or fractional depth would silently disqualify every unit ever mined, which
				-- reads in game as "the contract paid nothing and nobody can say why".
				minimumPayingDepth = if isFiniteNumber(raw.minimumPayingDepth) and raw.minimumPayingDepth > 0
					then math.floor(raw.minimumPayingDepth)
					else 0,
				tetherStuds = if isFiniteNumber(raw.tetherStuds) and raw.tetherStuds > 0 then raw.tetherStuds else 0,
				tetherGraceSeconds = if isFiniteNumber(raw.tetherGraceSeconds) and raw.tetherGraceSeconds > 0
					then raw.tetherGraceSeconds
					else 0,
				voidsOnPartyDeath = raw.voidsOnPartyDeath == true,
			}
		end
	end
	return NEUTRAL
end

-- The wax a candle is lit with, and the tank it is lit into. Returned together because they are one
-- decision: `startingWax` is clamped to `maxWax`, so a contract that shrinks the tank below the
-- normal start does not produce a candle that begins above its own maximum.
function ContractRules.waxFor(effect: Effect, baseStartingWax: number, baseMaxWax: number): (number, number)
	local maxWax = baseMaxWax * effect.maxWaxMultiplier
	local startingWax = math.min(baseStartingWax * effect.startingWaxMultiplier, maxWax)
	return startingWax, maxWax
end

-- Tools this contract takes away, as the set shape `SacrificeModifiers.lostTools` already uses. Merged
-- into whatever the Basin has taken rather than replacing it, so a contract and a sacrifice that both
-- remove a tool agree instead of one erasing the other.
function ContractRules.applyLostTools(effect: Effect, lostTools: { [string]: boolean })
	for _, toolId in effect.lostTools do
		lostTools[toolId] = true
	end
end

-- Has this contract's tether been broken for longer than its grace period?
--
-- `separatedFor` is how many continuous seconds this player has been further than `tetherStuds` from
-- their nearest living teammate — measured and accumulated by the caller, because distance is a fact
-- about the world and this module never touches one.
--
-- A contract with no tether is never broken by this, whatever is passed in.
function ContractRules.tetherIsBroken(effect: Effect, separatedFor: number): boolean
	if effect.tetherStuds <= 0 then
		return false
	end
	return isFiniteNumber(separatedFor) and separatedFor > effect.tetherGraceSeconds
end

-- Does a unit mined at this depth pay under this contract?
--
-- Above the contract's minimum it is worth exactly zero — not reduced, not discounted. That is what
-- makes The Long Descent a bet on reaching a depth rather than a general penalty: shallow units do not
-- become slightly worse, they become nothing, so the only way the contract pays is to get deep enough
-- that most of the bag came from below the line.
function ContractRules.depthPays(effect: Effect, originDepth: number): boolean
	if effect.minimumPayingDepth <= 0 then
		return true
	end
	return isFiniteNumber(originDepth) and originDepth >= effect.minimumPayingDepth
end

return ContractRules

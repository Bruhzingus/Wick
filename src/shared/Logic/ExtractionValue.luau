--!strict
-- PHASE 8, pure: what a bag of Raw Wax is worth. This module is the ONLY place in the game that
-- turns cargo into currency, and it does it without ever touching a Roblox service, a player, or a
-- profile — so the whole economy can be tested cold and simulated offline.
--
-- THE INVARIANT THIS FILE EXISTS TO GUARANTEE: every value it returns is a NON-NEGATIVE, FINITE
-- INTEGER, for every input, including hostile ones. Not "rounded to an integer" — never fractional
-- at any intermediate step. Currency is persisted, and a persisted float is a future argument about
-- whether a player has 349.99999 or 350.
--
-- HOW THE INTEGER GUARANTEE IS ACTUALLY HELD:
--
--   * Per-unit values are authored as whole currency in Config/Extraction. There is no "base value
--     times a depth multiplier" step, because that step is where the fractions would come from.
--   * The two scaling factors (cave payout, party bonus) are PERMILLE INTEGERS, applied as
--     `floor(subtotal * permille / 1000)`. `subtotal * permille` is an exact integer product well
--     below 2^53 given the caps below, so the division is the only rounding in the system and it is
--     an explicit, single, downward one.
--   * Scaling is applied ONCE to the summed subtotal, never per-stack. Per-stack rounding would let
--     a player raise their own payout by splitting one seam's units across more stacks.
--
-- WHY ORIGIN DEPTH AND NOT EXTRACTION DEPTH: a unit is priced by the floor it was mined out of. This
-- is the single decision that makes "farm the safe floors, then sprint to the bottom and cash in"
-- worth exactly what running to the bottom alone is worth. There is deliberately NO bonus for
-- carrying cargo deeper than you found it — such a bonus would reward precisely the shallow-farm
-- strategy it is meant to discourage, because the cheapest units to acquire would gain the most from
-- being walked down.

local Types = require(script.Parent.Parent.Types)
local ExtractionConfig = require(script.Parent.Parent.Config.Extraction)
local DepthRules = require(script.Parent.DepthRules)

local ExtractionValue = {}

-- One extraction, fully explained. The game shows players its arithmetic before they commit
-- (Config/Brazier), so the breakdown is the return value and the total is merely part of it.
export type ValueBreakdown = {
	units: number, -- how many units were priced
	baseValue: number, -- summed origin-depth value, before any scaling
	cavePayoutPermille: number,
	-- The Lamp Network contract or wager this run was signed under (Config/LampNetwork). 1000 when
	-- there was none, when the bet was missed, or when the whole track is rolled back.
	contractPermille: number,
	partyBonusPermille: number, -- 1000 when no bonus applies
	total: number, -- what the profile is actually credited
	capped: boolean, -- true if maxSinglePayout bound the result
}

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- A whole number at or above zero. Fractional, negative, NaN and infinite inputs all fail rather
-- than being coerced into something plausible — a payout computed from a repaired number is a payout
-- nobody can explain afterwards.
local function isNonNegativeInteger(value: number): boolean
	return isFiniteNumber(value) and value >= 0 and value % 1 == 0
end

-- WHAT ONE UNIT MINED AT `originDepth` IS WORTH, in whole currency.
--
-- Inside the authored table this IS the authored value. Past it the curve keeps compounding at
-- `extensionGrowthPermille`, computed by repeated integer multiply-then-divide so that an
-- extrapolated value is exactly as integral as an authored one, and clamped at `maxValuePerUnit`.
-- The loop terminates on the cap rather than on the depth, so an absurd depth costs a bounded number
-- of iterations instead of hanging the server.
--
-- Returns 0 for any depth the game does not actually support, which is what makes a corrupted or
-- client-influenced origin depth worth nothing rather than worth something surprising.
function ExtractionValue.valuePerUnit(originDepth: number): number
	if not DepthRules.isSupportedDepth(originDepth) then
		return 0
	end
	local authored = ExtractionConfig.valuePerUnitByDepth
	if #authored == 0 then
		return 0
	end
	local cap = math.max(0, math.floor(ExtractionConfig.maxValuePerUnit))
	if originDepth <= #authored then
		return math.clamp(math.floor(authored[originDepth]), 0, cap)
	end

	local growth = math.max(1000, math.floor(ExtractionConfig.extensionGrowthPermille))
	local value = math.clamp(math.floor(authored[#authored]), 0, cap)
	for _ = #authored + 1, originDepth do
		if value >= cap then
			return cap
		end
		-- Integer multiply, then integer divide. Never `value * 1.33`.
		value = math.min(math.floor(value * growth / 1000), cap)
	end
	return value
end

-- Sum a cargo's stacks at their own origin depths. Stacks with an unsupported origin depth or a
-- non-integer unit count contribute nothing at all rather than being repaired — the ONE field a
-- payout is derived from must never be guessed at.
--
-- The unit count is clamped to the configured cargo ceiling before pricing, so even a cargo table
-- that was corrupted past the cap cannot price more units than the game can legitimately hold.
-- `minimumPayingDepth` is The Long Descent's rule (Config/LampNetwork): units mined ABOVE that depth
-- are worth exactly zero, not merely discounted. They are still COUNTED as units — the player really
-- did carry them out, the results card should say so, and quietly deleting them from the tally would
-- make the readout disagree with the bag. Zero means every depth pays, which is every ordinary run.
function ExtractionValue.baseValue(cargo: Types.RawWaxCargo, minimumPayingDepth: number?): (number, number)
	local floorDepth = if minimumPayingDepth ~= nil
			and isFiniteNumber(minimumPayingDepth)
			and minimumPayingDepth > 0
		then math.floor(minimumPayingDepth)
		else 0
	local maxUnits = math.max(0, math.floor(ExtractionConfig.maxCargoUnits))
	local units = 0
	local value = 0
	for _, stack in cargo.stacks do
		if not isNonNegativeInteger(stack.units) or stack.units <= 0 then
			continue
		end
		-- An unsupported or corrupted origin depth is skipped ENTIRELY — not counted, not priced. That
		-- is the pre-existing guard and it must stay: a unit whose provenance is unreadable is not a
		-- unit anybody can audit.
		local perUnit = ExtractionValue.valuePerUnit(stack.originDepth)
		if perUnit <= 0 then
			continue
		end
		-- A unit the CONTRACT disqualifies is a different case, and is deliberately handled the other
		-- way round: it is counted and priced at zero. The player really did carry it out, so the tally
		-- on the results card has to say so — deleting it would make the readout disagree with the bag
		-- they were holding, and "why does it say 4 units when I mined 10" is a bug report, not a rule
		-- anyone would infer.
		if floorDepth > 0 and stack.originDepth < floorDepth then
			perUnit = 0
		end
		local counted = math.min(stack.units, math.max(0, maxUnits - units))
		if counted <= 0 then
			break
		end
		units += counted
		value += counted * perUnit
	end
	return value, units
end

-- Apply a permille scalar to an integer subtotal. The single rounding step in the whole economy,
-- and it always rounds DOWN — a player can never gain currency from a rounding decision.
local function scale(value: number, permille: number): number
	if not isNonNegativeInteger(value) or value <= 0 then
		return 0
	end
	local safePermille = if isFiniteNumber(permille) then math.max(0, math.floor(permille)) else 0
	return math.floor(value * safePermille / 1000)
end

ExtractionValue.scale = scale

-- Whether this player may earn the "everyone came back" bonus from a party of this size. Solo runs
-- never do, a death cancels it globally, and choosing an early lobby return forfeits it individually.
function ExtractionValue.partyBonusApplies(partySize: number, anyoneDied: boolean, extractedEarly: boolean?): boolean
	if anyoneDied or extractedEarly == true then
		return false
	end
	if not isNonNegativeInteger(partySize) then
		return false
	end
	return partySize >= math.max(2, math.floor(ExtractionConfig.partyBonusMinimumMembers))
end

-- THE PAYOUT. Everything above, composed once, in the only order that is safe:
--
--   sum origin-depth values  ->  scale by (cave x contract)  ->  scale by the party bonus  ->  clamp
--
-- Scaling the summed subtotal (rather than each stack) is what stops a player from raising their own
-- payout by fragmenting cargo across more stacks: with per-stack rounding, N stacks means N chances
-- to round, and here there is exactly one.
--
-- WHY THE CONTRACT COMPOSES INTO THE CAVE SCALAR RATHER THAN BECOMING A THIRD STEP. Both answer the
-- same question — what is a unit from this run worth — so they are multiplied into ONE permille by
-- integer multiply-then-divide and applied through the existing single floor. A third `scale` call
-- would have added a third downward rounding, quietly costing a player currency for having signed a
-- contract at all. Composing also means a run with no contract is bit-for-bit what it was before the
-- Lamp Network existed: `cave x 1000 / 1000` is exactly `cave`.
--
-- The party bonus stays its own step because it is its own credit — settled retroactively once the
-- last member is out (see `partyBonusDelta` and ExtractionService), not at the brazier.
--
-- `withPartyBonus` is passed in rather than derived, because whether the party all got out is a fact
-- about the run that this pure module has no business knowing. ExtractionService decides it. The same
-- is true of `contractPermille`: whether a contract's RULE was actually kept is the run's business,
-- and a broken contract arrives here as nil rather than as this module guessing.
function ExtractionValue.compute(
	cargo: Types.RawWaxCargo,
	cavePayoutPermille: number,
	withPartyBonus: boolean,
	contractPermille: number?,
	minimumPayingDepth: number?
): ValueBreakdown
	local baseValue, units = ExtractionValue.baseValue(cargo, minimumPayingDepth)
	local safeCavePermille = if isFiniteNumber(cavePayoutPermille)
		then math.max(0, math.floor(cavePayoutPermille))
		else 0
	-- Never below neutral. A contract can only ever pay MORE for a harder run; a scalar under 1000
	-- arriving here would be a bug that silently docked somebody's earnings.
	local safeContractPermille = if contractPermille ~= nil and isFiniteNumber(contractPermille)
		then math.max(1000, math.floor(contractPermille))
		else 1000
	local partyPermille = if withPartyBonus
		then math.max(1000, math.floor(ExtractionConfig.partyBonusPermille))
		else 1000

	-- An exact integer product, far below 2^53 given the caps in Config/Extraction, so composing the
	-- two scalars introduces no rounding of its own.
	local runPermille = math.floor(safeCavePermille * safeContractPermille / 1000)
	local total = scale(baseValue, runPermille)
	if withPartyBonus then
		total = scale(total, partyPermille)
	end

	local ceiling = math.max(0, math.floor(ExtractionConfig.maxSinglePayout))
	local capped = total > ceiling
	if capped then
		total = ceiling
	end

	return {
		units = units,
		baseValue = baseValue,
		cavePayoutPermille = safeCavePermille,
		contractPermille = safeContractPermille,
		partyBonusPermille = partyPermille,
		total = total,
		capped = capped,
	}
end

-- The retroactive half of the party bonus. The base payout was already credited when the player
-- walked out; this is the DIFFERENCE the bonus adds, credited separately once the last member is
-- safely out (see ExtractionService).
--
-- Computed as `withBonus - withoutBonus` from the same inputs rather than as a fresh percentage, so
-- the two credits provably sum to exactly what a single bonused extraction would have paid. There is
-- no arrangement of rounding in which a player earns more by being paid in two pieces.
--
-- `contractPermille` must be the SAME value the base extraction was paid at, or the two credits stop
-- summing to a single bonused extraction — which is the one property this function exists to hold.
function ExtractionValue.partyBonusDelta(
	cargo: Types.RawWaxCargo,
	cavePayoutPermille: number,
	contractPermille: number?,
	minimumPayingDepth: number?
): number
	local withBonus =
		ExtractionValue.compute(cargo, cavePayoutPermille, true, contractPermille, minimumPayingDepth).total
	local without =
		ExtractionValue.compute(cargo, cavePayoutPermille, false, contractPermille, minimumPayingDepth).total
	return math.max(0, withBonus - without)
end

return ExtractionValue

--!strict
-- Pure: every authoritative wax mutation, plus the per-run accounting that explains it. The rule
-- the whole module exists to enforce is simple — a spend can only ever REMOVE wax and a grant can
-- only ever ADD it, whatever amount or reason is passed in — so a mislabelled or hostile call can
-- never mint wax. `WaxDrain.apply` still owns the clamp; this wraps it with attribution.
--
-- Wax remains the only resource (ARCHITECTURE invariant). A ledger is internal bookkeeping: it is
-- never shown on the meter, never replicated as a second meter, and never persisted.

local Types = require(script.Parent.Parent.Types)
local WaxDrain = require(script.Parent.WaxDrain)

local WaxAccounting = {}

-- The closed accounting vocabulary. Anything not in this set is recorded as "Other" rather than
-- creating a new category at runtime.
local SOURCES: { [string]: boolean } = {
	PassiveBurn = true,
	MovementWalk = true,
	MovementRun = true,
	ToolFlare = true,
	ToolDecoy = true,
	ToolCup = true,
	ToolOther = true,
	DamageThreat = true,
	DamageWater = true,
	DamageDripstone = true,
	ReviveCost = true,
	Extraction = true,
	DeathLoss = true,
	BasinGain = true,
	FoundWaxGain = true,
	-- Wax shards that flew off a seam on a perfect strike and stuck to the player (Config/Mining).
	-- Its own category rather than folded into FoundWaxGain, because "wax I dug out of the wall" and
	-- "wax I scavenged off a corpse" answer different questions about how a run stayed alive.
	MiningShardGain = true,
	-- Wax spent ringing the Signal Bell (Config/LampNetwork.bell). Its own category so the run summary
	-- can say what being findable cost, rather than hiding it inside tool spend — the bell is not a
	-- tool and its cost answers a different question about the run.
	SignalBellCost = true,
	-- Standing in the heat of burning vegetation (Config/MossFire). THE centralized reason for
	-- every environmental fire in the game: fire costs Living Wax and adds no second meter, and it
	-- gets its own category so the run summary can say what the fire cost rather than smearing it
	-- across "Other".
	EnvironmentalFire = true,
	Other = true,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function WaxAccounting.isSource(reason: string): boolean
	return SOURCES[reason] == true
end

-- Never trusts the caller's string. An unknown reason is bookkeeping noise, not an error the run
-- should die on, so it lands in "Other" where the summary makes it visible.
function WaxAccounting.normalizeSource(reason: string?): Types.WaxSource
	if reason ~= nil and SOURCES[reason] then
		return reason :: Types.WaxSource
	end
	return "Other"
end

function WaxAccounting.newLedger(startingWax: number, startDepth: number, startedAt: number): Types.WaxLedger
	return {
		startingWax = if isFinite(startingWax) then math.max(0, startingWax) else 0,
		startedAt = startedAt,
		startDepth = startDepth,
		deepestGlobalDepth = startDepth,
		totalLost = 0,
		totalGained = 0,
		lostBySource = {},
		gainedBySource = {},
	}
end

function WaxAccounting.noteDepth(ledger: Types.WaxLedger, globalDepth: number)
	if isFinite(globalDepth) and globalDepth > ledger.deepestGlobalDepth then
		ledger.deepestGlobalDepth = globalDepth
	end
end

local function record(ledger: Types.WaxLedger, source: Types.WaxSource, delta: number)
	if delta < 0 then
		local lost = -delta
		ledger.totalLost += lost
		ledger.lostBySource[source] = (ledger.lostBySource[source] or 0) + lost
	elseif delta > 0 then
		ledger.totalGained += delta
		ledger.gainedBySource[source] = (ledger.gainedBySource[source] or 0) + delta
	end
end

-- Remove wax. `amount` is treated as a magnitude: a negative or non-finite amount removes nothing
-- rather than granting. Returns the new wax state, whether this emptied the candle, and how much
-- was actually removed (which is less than `amount` when the candle bottomed out).
function WaxAccounting.spend(
	wax: Types.WaxState,
	ledger: Types.WaxLedger?,
	amount: number,
	reason: string?
): (Types.WaxState, boolean, number)
	local requested = if isFinite(amount) then math.max(0, amount) else 0
	local newWax, emptied = WaxDrain.apply(wax, requested)
	local applied = wax.current - newWax.current
	if ledger ~= nil and applied ~= 0 then
		record(ledger, WaxAccounting.normalizeSource(reason), -applied)
	end
	return newWax, emptied, applied
end

-- Add wax, never above capacity. A negative or non-finite amount adds nothing rather than draining.
-- If capacity was lowered underneath a full candle (the Basin's "shrink your reserve" sacrifice),
-- the clamp removes the overflow and records it as a LOSS against the same source, which is exactly
-- who took it — the ledger still reconciles.
function WaxAccounting.grant(
	wax: Types.WaxState,
	ledger: Types.WaxLedger?,
	amount: number,
	reason: string?
): (Types.WaxState, number)
	local requested = if isFinite(amount) then math.max(0, amount) else 0
	local current = math.clamp(wax.current + requested, 0, wax.max)
	local applied = current - wax.current
	if ledger ~= nil and applied ~= 0 then
		record(ledger, WaxAccounting.normalizeSource(reason), applied)
	end
	return { current = current, max = wax.max }, applied
end

-- Deliberately empty the candle (extraction, terminal death) and attribute the whole remainder.
function WaxAccounting.drainToEmpty(
	wax: Types.WaxState,
	ledger: Types.WaxLedger?,
	reason: string?
): (Types.WaxState, number)
	local newWax, _, applied = WaxAccounting.spend(wax, ledger, wax.current, reason)
	return newWax, applied
end

function WaxAccounting.summarize(
	ledger: Types.WaxLedger,
	endingWax: number,
	endedAt: number,
	outcome: Types.WaxRunOutcome
): Types.WaxRunSummary
	local ending = if isFinite(endingWax) then math.max(0, endingWax) else 0
	return {
		startingWax = ledger.startingWax,
		endingWax = ending,
		totalLost = ledger.totalLost,
		totalGained = ledger.totalGained,
		lostBySource = table.clone(ledger.lostBySource),
		gainedBySource = table.clone(ledger.gainedBySource),
		startDepth = ledger.startDepth,
		deepestGlobalDepth = ledger.deepestGlobalDepth,
		outcome = outcome,
		durationSeconds = math.max(0, endedAt - ledger.startedAt),
		reconciliationError = ledger.startingWax + ledger.totalGained - ledger.totalLost - ending,
	}
end

return WaxAccounting

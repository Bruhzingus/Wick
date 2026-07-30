--!strict
-- Pure mining rules: who may swing, where a swing landed in the timing sweep, what that swing is
-- worth, and how loud it was. Server, client and tests all read these, so the timing rail the
-- player sees and the accuracy the server awards are the same function evaluated against the same
-- bounded clock sample — never two implementations that can disagree.
--
-- NOTHING HERE TOUCHES A THREAT. A swing produces progress and a noise kind. Whether anything comes
-- to look is entirely the sound field's business (Logic/SoundField), which is why the pickaxe can
-- never become a weapon by accident: there is no code path from a strike to a threat's health,
-- because threats have no health.

local Types = require(script.Parent.Parent.Types)
local MiningConfig = require(script.Parent.Parent.Config.Mining)
local LightConfig = require(script.Parent.Parent.Config.Light)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)

local MiningRules = {}

export type DepositRow = MiningConfig.DepositRow

--------------------------------------------------------------------------------
-- Deposit rows
--------------------------------------------------------------------------------

-- The row every seam falls back to. Deliberately resolved by lookup rather than by index, so
-- reordering the config table cannot silently change what an un-rowed deposit becomes.
local FALLBACK_ROW_ID = "Standard"

function MiningRules.rowById(rowId: string?): DepositRow?
	if typeof(rowId) ~= "string" then
		return nil
	end
	for _, row in MiningConfig.rows do
		if row.id == rowId then
			return row
		end
	end
	return nil
end

-- The row a deposit actually behaves as. Anything unknown, absent, or belonging to a rolled-back
-- layer resolves to Standard rather than erroring — a floor built before a config change, or a save
-- restored across one, must still be minable.
function MiningRules.resolveRow(rowId: string?): DepositRow
	local row = MiningRules.rowById(rowId)
	if row ~= nil and (row.unlockNode == nil or LampConfig.depositRows.enabled) then
		return row
	end
	local fallback = MiningRules.rowById(FALLBACK_ROW_ID)
	-- A config with no Standard row is a broken config, but a seam still has to be workable rather
	-- than crash a live run, so synthesise the historical values.
	if fallback == nil then
		return {
			id = FALLBACK_ROW_ID,
			displayName = "Raw Wax",
			weight = 1,
			minDepth = 1,
			cleanStrikes = 3,
			units = 2,
			maxPaidMiners = 1,
			minBurnFraction = 0,
			unlockNode = nil,
		}
	end
	return fallback
end

-- Which rows may appear on a floor at this depth, given the node ids the party between them owns.
--
-- `unlockedNodes` is the UNION of every member's owned nodes: a floor is shared, so one friend's
-- purchase has to put seams in the ground for everybody or the row would be invisible to the person
-- who bought it whenever they were not the leader.
function MiningRules.rowsAvailable(depth: number, unlockedNodes: { [string]: boolean }): { DepositRow }
	local available: { DepositRow } = {}
	for _, row in MiningConfig.rows do
		if depth < row.minDepth then
			continue
		end
		if row.unlockNode ~= nil then
			if not LampConfig.depositRows.enabled or not unlockedNodes[row.unlockNode] then
				continue
			end
		end
		if row.weight > 0 then
			table.insert(available, row)
		end
	end
	return available
end

-- Which row THIS deposit is, chosen from one uniform roll in [0, 1) so the whole floor stays a pure
-- function of its seed. Falls back to Standard when nothing is eligible, which keeps a floor minable
-- no matter what the unlock set looks like.
function MiningRules.selectRow(depth: number, unlockedNodes: { [string]: boolean }, roll: number): DepositRow
	local available = MiningRules.rowsAvailable(depth, unlockedNodes)
	if #available == 0 then
		return MiningRules.resolveRow(FALLBACK_ROW_ID)
	end

	local total = 0
	for _, row in available do
		total += row.weight
	end
	if total <= 0 then
		return available[1]
	end

	local target = math.clamp(if roll == roll then roll else 0, 0, 0.9999999) * total
	local cumulative = 0
	for _, row in available do
		cumulative += row.weight
		if target < cumulative then
			return row
		end
	end
	return available[#available]
end

-- The burn rate a candle must be holding to work this row, in absolute dial units. Zero for every
-- row that does not care.
--
-- Derived from the game's maximum rather than the player's own, so a Basin brightness cap genuinely
-- locks a candle out of a Bright Seam instead of merely lowering the bar it has to clear.
function MiningRules.requiredBurnRate(row: DepositRow): number
	if row.minBurnFraction <= 0 then
		return 0
	end
	return LightConfig.maxBurnRate * math.clamp(row.minBurnFraction, 0, 1)
end

export type Denial =
	"Dead" -- burned out, snuffed, or already finished
	| "NotLit" -- you cannot work a seam in the dark
	| "Covered" -- ...nor with the flame cupped down to an ember
	| "WrongFloor" -- the deposit is on another floor of the expedition
	| "OutOfRange"
	| "Obstructed" -- cave geometry blocks the player from the seam
	| "Depleted" -- someone already broke it, possibly on this same frame
	| "Cooldown" -- too soon after the previous swing
	| "AlreadySwinging" -- a swing of yours is already open
	| "NoSwing" -- a release/cancel with nothing open
	| "Disabled"
	| "TooDim" -- this row only gives at the top of the dial (Bright Seam)

-- Is this floor allowed to carry a deposit at all?
function MiningRules.isEligibleDepth(depth: number): boolean
	return MiningConfig.enabled and depth >= MiningConfig.placement.minDepth
end

-- The weight row governing this depth. Depths past the final row use the final row, so an uncapped
-- expedition always has a rule rather than falling off the end of the table.
local function weightsForDepth(depth: number): { number }?
	local bands = MiningConfig.placement.depositCounts
	if #bands == 0 then
		return nil
	end
	for _, band in bands do
		if depth <= band.maxDepth then
			return band.weights
		end
	end
	return bands[#bands].weights
end

-- How many deposits this floor WANTS, given its own placement roll. Zero to three, weighted by depth
-- (Config/Mining.placement.depositCounts) so a shallow floor usually carries one seam or none and a
-- deep floor usually carries two or three.
--
-- `roll` is one uniform number in [0, 1) supplied by the planner's seeded RNG, mapped onto the band's
-- cumulative weights. One roll rather than one per possible seam, so the count stays a single
-- deterministic function of the floor seed and a test can pin it exactly.
--
-- This is a TARGET, never a guarantee. The planner places at most one deposit per room and only in
-- rooms that pass every safety rule (off-route, dry footprint, clear of hazards and threat spawns,
-- never behind a vine); a floor that cannot satisfy them places fewer. The count drops, the rules
-- never relax.
function MiningRules.targetCount(depth: number, roll: number): number
	if not MiningRules.isEligibleDepth(depth) then
		return 0
	end
	local weights = weightsForDepth(depth)
	if weights == nil then
		return 0
	end

	local total = 0
	for _, weight in weights do
		if weight > 0 then
			total += weight
		end
	end
	if total <= 0 then
		return 0
	end

	-- A roll outside [0, 1) would otherwise fall through the loop and silently return the last row's
	-- count; clamping keeps a bad caller cheap rather than surprising.
	local target = math.clamp(roll, 0, 0.9999999) * total
	local cumulative = 0
	local ceiling = math.max(0, math.floor(MiningConfig.placement.maxPerFloor))
	for index, weight in weights do
		if weight <= 0 then
			continue
		end
		cumulative += weight
		if target < cumulative then
			return math.min(index - 1, ceiling)
		end
	end
	return math.min(#weights - 1, ceiling)
end

-- Where the marker sits in its sweep, 0..1, `elapsed` seconds after the swing began. The wind-up is
-- dead time before the sweep starts, so the sweep and the animation agree about when the rail is
-- live. Returns nil during the wind-up: there is no phase to release into yet.
function MiningRules.sweepPhase(elapsed: number): number?
	local deposit = MiningConfig.deposit
	local sweepSeconds = MiningConfig.timing.sweepSeconds
	if sweepSeconds <= 0 or elapsed < deposit.swingWindupSeconds then
		return nil
	end
	return ((elapsed - deposit.swingWindupSeconds) % sweepSeconds) / sweepSeconds
end

-- Circular distance between two sweep phases, so the target band works identically wherever it sits
-- in the cycle and a release just past the wrap point is not mistakenly scored as a whole lap away.
local function phaseDistance(a: number, b: number): number
	local raw = math.abs(a - b)
	return math.min(raw, 1 - raw)
end

-- Where the target band sits for one strike of one deposit. Deterministic from (seed, strike index)
-- and nothing else, so the server can score a strike and the client can draw the band it was scored
-- against without either of them inventing a number.
--
-- WHY IT MOVES AT ALL: the stance keeps the rail sweeping continuously, and a band that never moved
-- would reduce mining to clicking on a metronome. Moving it one read at a time is what keeps a
-- strike a decision rather than a tempo.
function MiningRules.bandCenter(seed: number, strikeIndex: number): number
	local timing = MiningConfig.timing
	local base = timing.perfectCenter % 1
	local wander = math.clamp(timing.bandWander, 0, 0.5)
	if wander <= 0 then
		return base
	end
	-- Integer hash rather than Random: pure, allocation-free, and identical on every machine that
	-- evaluates it.
	local hashed = (math.abs(math.floor(seed)) * 73856093 + math.abs(math.floor(strikeIndex)) * 19349663) % 65536
	return (base + (hashed / 65536 - 0.5) * 2 * wander) % 1
end

-- How well a strike at this phase landed. `center` defaults to the configured band for callers that
-- do not run a wandering band (the rail's own colouring, tests).
function MiningRules.accuracyForPhase(phase: number, center: number?): Types.StrikeAccuracy
	local timing = MiningConfig.timing
	local distance = phaseDistance(phase, (center or timing.perfectCenter) % 1)
	if distance <= timing.perfectHalfWidth then
		return "Perfect"
	elseif distance <= timing.goodHalfWidth then
		return "Good"
	end
	return "Miss"
end

-- How well a strike `elapsed` seconds into the current sweep landed. Striking during the wind-up is
-- a miss, not a free retry: a twitchy click still costs you the swing.
function MiningRules.accuracyForElapsed(elapsed: number, center: number?): Types.StrikeAccuracy
	local phase = MiningRules.sweepPhase(elapsed)
	if phase == nil then
		return "Miss"
	end
	return MiningRules.accuracyForPhase(phase, center)
end

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

-- Convert a client's shared-clock click sample into the server's private monotonic clock.
--
-- The server still owns the sweep start, cooldown, validation and arrival time. This helper only
-- removes a plausible one-way network delay from SCORING so a player is judged where they clicked,
-- not where their packet arrived. A missing, non-finite, stale, or implausibly future report falls
-- back to arrival instead of being clamped to an exploitable window edge.
function MiningRules.resolveInputClock(
	arrivalClock: number,
	sharedClockAtArrival: number,
	reportedSharedClock: number?
): number
	if reportedSharedClock == nil or not isFinite(sharedClockAtArrival) or not isFinite(reportedSharedClock) then
		return arrivalClock
	end

	local offset = reportedSharedClock - sharedClockAtArrival
	if not isFinite(offset) then
		return arrivalClock
	end

	local timing = MiningConfig.timing
	local maxRewind = math.max(0, timing.maxInputRewindSeconds)
	local futureTolerance = math.max(0, timing.inputFutureToleranceSeconds)
	if offset < -maxRewind or offset > futureTolerance then
		return arrivalClock
	end
	return arrivalClock + offset
end

-- What one swing is worth, as a fraction of THIS row's deposit. A clean strike is `1 / cleanStrikes`
-- and the two lesser bands are fixed proportions of it, so a nine-strike Deep Seam forgives a fumble
-- by exactly the same share as a three-strike Standard one.
function MiningRules.progressForAccuracy(accuracy: Types.StrikeAccuracy, row: DepositRow?): number
	local timing = MiningConfig.timing
	local resolved = row or MiningRules.resolveRow(FALLBACK_ROW_ID)
	local strikes = math.max(1, math.floor(resolved.cleanStrikes))
	local perfect = 1 / strikes
	if accuracy == "Perfect" then
		return perfect
	elseif accuracy == "Good" then
		return perfect * math.clamp(timing.goodFractionOfPerfect, 0, 1)
	end
	return perfect * math.clamp(timing.missFractionOfPerfect, 0, 1)
end

-- Which Config/Sound row this swing announces itself with. A break is the loudest thing mining
-- does; a fumble is louder than a clean bite, which is the player's only lever on exposure.
function MiningRules.noiseKindFor(accuracy: Types.StrikeAccuracy, depleted: boolean): Types.NoiseKind
	if depleted then
		return "MineBreak"
	end
	return if accuracy == "Miss" then "MineStrikeFumble" else "MineStrikeClean"
end

-- THE resolution. Takes the deposit's current progress and how far into the current sweep the
-- strike landed; returns what it was worth. The server is the only caller that keeps the result.
function MiningRules.resolveStrike(
	progress: number,
	elapsed: number,
	center: number?,
	row: DepositRow?
): Types.StrikeOutcome
	local accuracy = MiningRules.accuracyForElapsed(elapsed, center)
	local nextProgress = math.clamp(progress + MiningRules.progressForAccuracy(accuracy, row), 0, 1)

	-- CLOSE ENOUGH IS BROKEN. `n` accumulations of `1 / n` do not reach 1 in binary floating point for
	-- most n — six sixths sum to 0.9999999999999999 — so a strict `>= 1` would have made a six-strike
	-- Twin Seam take seven and a nine-strike Deep Seam take ten. The player would have counted their
	-- swings, been told "0 clean left", and watched the rock refuse to break.
	--
	-- The tolerance is safe by a wide margin rather than by luck: the SMALLEST progress any single swing
	-- can add is a miss on the longest row (0.3 / 9 = 0.033), four orders of magnitude above this. No
	-- combination of swings can cross the line early.
	local depleted = nextProgress >= 1 - 1e-6
	return {
		accuracy = accuracy,
		-- Snapped to exactly 1 once broken, so the seam's replicated progress and its depleted flag can
		-- never disagree about whether it is finished.
		progress = if depleted then 1 else nextProgress,
		depleted = depleted,
		noiseKind = MiningRules.noiseKindFor(accuracy, depleted),
	}
end

-- Clean swings still needed, for a display that never implies more precision than the server has.
--
-- Carries the same floating-point tolerance as `resolveStrike`, and for the same reason: at five
-- sixths of a Twin Seam, `(1 - 0.8333) / 0.1667` evaluates to 1.0000000000000002 and a bare `ceil`
-- would promise TWO more clean strikes when one would break it. The readout and the rock have to
-- agree, or the number on screen is the game lying about its own state.
function MiningRules.cleanStrikesRemaining(progress: number, row: DepositRow?): number
	local perStrike = MiningRules.progressForAccuracy("Perfect", row)
	if perStrike <= 0 then
		return 0
	end
	local remaining = (1 - progress) / perStrike
	return math.max(0, math.ceil(remaining - 1e-6))
end

export type StrikeRequest = {
	alive: boolean,
	finished: boolean,
	snuffed: boolean,
	isLit: boolean,
	isCupping: boolean,
	playerDepth: number,
	depositDepth: number,
	depositDepleted: boolean,
	distance: number,
	hasLineOfSight: boolean,
	now: number,
	nextStrikeAt: number, -- os.clock() this player's cooldown clears
	hasOpenSwing: boolean,
	-- The row this seam is, and the burn this candle is actually holding. Both optional so a caller
	-- that predates rows still validates exactly as it did.
	row: DepositRow?,
	burnRate: number?,
	isFlaring: boolean?,
}

-- Is this candle burning hard enough for this row? True for every row that does not ask.
--
-- A live Flare always qualifies: it pushes light far past anything the dial can reach, so refusing it
-- would make the tool useless at exactly the moment it is most obviously the right answer. It is also
-- the only way a Basin-capped candle can ever work a Bright Seam, which keeps the sacrifice a real
-- cost with a real, expensive workaround rather than a permanent lockout.
local function burnIsSufficient(request: StrikeRequest): boolean
	local row = request.row
	if row == nil then
		return true
	end
	local required = MiningRules.requiredBurnRate(row)
	if required <= 0 then
		return true
	end
	if request.isFlaring == true then
		return true
	end
	local burn = request.burnRate
	-- A missing burn reading is treated as too dim rather than as sufficient: failing closed costs a
	-- player one swing, failing open hands them a row they never met the condition for.
	if burn == nil or burn ~= burn then
		return false
	end
	return burn >= required
end

-- Everything that must be true to ENGAGE a seam — to enter the locked working stance. The server
-- calls this and nothing else decides; the client calls the same function only to grey out its own
-- prompt. `hasOpenSwing` here means "already engaged": you cannot take two stances at once.
function MiningRules.canBeginStrike(request: StrikeRequest): (boolean, Denial?)
	local deposit = MiningConfig.deposit
	if not MiningConfig.enabled then
		return false, "Disabled"
	end
	if not request.alive or request.finished or request.snuffed then
		return false, "Dead"
	end
	if deposit.requiresLit and not request.isLit then
		return false, "NotLit"
	end
	if deposit.requiresUncoveredFlame and request.isCupping then
		return false, "Covered"
	end
	if request.playerDepth ~= request.depositDepth then
		return false, "WrongFloor"
	end
	if request.depositDepleted then
		return false, "Depleted"
	end
	if request.distance > deposit.interactionRange then
		return false, "OutOfRange"
	end
	if deposit.requiresLineOfSight and not request.hasLineOfSight then
		return false, "Obstructed"
	end
	if request.hasOpenSwing then
		return false, "AlreadySwinging"
	end
	if request.now < request.nextStrikeAt then
		return false, "Cooldown"
	end
	-- Checked LAST of the refusals, so a player who is also out of range or cupped hears the reason
	-- they can act on first. A Bright Seam refusing a dim candle is the row working, not an error.
	if not burnIsSufficient(request) then
		return false, "TooDim"
	end
	return true, nil
end

-- Everything that must STILL be true for an engaged player to land a strike — re-checked on every
-- strike AND every tick the stance is held. Deliberately a second check rather than a repeat of the
-- first: the world moves while someone stands at a rock. Being pushed out of range, cupping the
-- flame, being snuffed, descending, or somebody else breaking the seam all end the stance instead of
-- paying it out.
function MiningRules.canResolveStrike(request: StrikeRequest): (boolean, Denial?)
	local deposit = MiningConfig.deposit
	if not request.alive or request.finished or request.snuffed then
		return false, "Dead"
	end
	if deposit.requiresLit and not request.isLit then
		return false, "NotLit"
	end
	if deposit.requiresUncoveredFlame and request.isCupping then
		return false, "Covered"
	end
	if request.playerDepth ~= request.depositDepth then
		return false, "WrongFloor"
	end
	if request.depositDepleted then
		return false, "Depleted"
	end
	if request.distance > deposit.interactionRange then
		return false, "OutOfRange"
	end
	if deposit.requiresLineOfSight and not request.hasLineOfSight then
		return false, "Obstructed"
	end
	-- Re-checked on every strike, not only at engagement: letting the dial fall mid-seam has to end the
	-- stance, or a player could open a Bright Seam at full burn and then finish it in the dark.
	if not burnIsSufficient(request) then
		return false, "TooDim"
	end
	return true, nil
end

-- Has an engaged player gone quiet long enough to release the stance for them? Prevents a client
-- that stopped responding from leaving someone rooted to a rock forever.
function MiningRules.swingHasTimedOut(elapsed: number): boolean
	return elapsed >= MiningConfig.deposit.swingTimeoutSeconds
end

return MiningRules

--!strict
-- Pure mining rules: who may swing, where a swing landed in the timing sweep, what that swing is
-- worth, and how loud it was. Server, client and tests all read these, so the timing rail the
-- player sees and the accuracy the server awards are the same function evaluated against the same
-- bounded clock sample — never two implementations that can disagree.
--
-- NOTHING HERE TOUCHES A THREAT. A swing produces progress, a gram count and a noise kind. Whether
-- anything comes to look is entirely the sound field's business (Logic/SoundField) — or, for the one
-- seam that detonates, ThreatService's — which is why the pickaxe can never become a weapon by
-- accident: there is no code path from a strike to a threat's health, because threats have no health.
--
-- WHAT A SWING IS WORTH IS DECIDED HERE, in whole Raw Wax grams, because payment is now per swing
-- rather than per break (`gramsForAccuracy`). The explosive seam's prime curve lives here too, for the
-- same reason everything else does: it is arithmetic the server must own and a test must be able to
-- pin, and putting it in the service would make the one number the row is balanced on unassertable.

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
			gramsPerStrike = 50,
			neverDepletes = false,
			maxPaidMiners = 1,
			minBurnFraction = 0,
			maxBurnFraction = 1,
			unlockNode = nil,
		}
	end
	return fallback
end

-- Is this a seam that can never be worked out? Read through a helper rather than off the field, so a
-- row authored before the flag existed — or one restored from a rolled-back config — reads as an
-- ordinary breakable seam instead of becoming an accidental infinite deposit.
function MiningRules.neverDepletes(row: DepositRow?): boolean
	return row ~= nil and row.neverDepletes == true
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
-- Fractions resolve across the candle's CURRENT reachable dial range. Basin penalties change the
-- light produced at each end, but never make an authored mining window impossible to reach.
function MiningRules.requiredBurnRate(row: DepositRow, minBurnRate: number?, maxBurnRate: number?): number
	if row.minBurnFraction <= 0 then
		return 0
	end
	local floor = if minBurnRate ~= nil and minBurnRate == minBurnRate
		then math.clamp(minBurnRate, LightConfig.minBurnRate, LightConfig.maxBurnRate)
		else LightConfig.minBurnRate
	local ceiling = if maxBurnRate ~= nil and maxBurnRate == maxBurnRate
		then math.clamp(maxBurnRate, floor, LightConfig.maxBurnRate)
		else LightConfig.maxBurnRate
	return floor + (ceiling - floor) * math.clamp(row.minBurnFraction, 0, 1)
end

-- The hottest this row may be worked. The neutral value is the game's maximum dial rate; a Flare
-- exceeds it conceptually and is handled by the shared window check below.
function MiningRules.maximumBurnRate(row: DepositRow, minBurnRate: number?, maxBurnRate: number?): number
	local floor = if minBurnRate ~= nil and minBurnRate == minBurnRate
		then math.clamp(minBurnRate, LightConfig.minBurnRate, LightConfig.maxBurnRate)
		else LightConfig.minBurnRate
	local ceiling = if maxBurnRate ~= nil and maxBurnRate == maxBurnRate
		then math.clamp(maxBurnRate, floor, LightConfig.maxBurnRate)
		else LightConfig.maxBurnRate
	return floor + (ceiling - floor) * math.clamp(row.maxBurnFraction, 0, 1)
end

export type Denial =
	"Dead" -- burned out, snuffed, or already finished
	| "NotLit" -- you cannot work a seam in the dark
	| "Covered" -- ...nor with the flame cupped down to an ember
	| "WrongFloor" -- the deposit is on another floor of the expedition
	| "OutOfRange"
	| "Obstructed" -- cave geometry blocks the player from the seam
	| "Depleted" -- someone already broke it, possibly on this same frame
	| "Primed" -- an explosive seam has gone off; the only correct action left is to leave
	| "Cooldown" -- too soon after the previous swing
	| "AlreadySwinging" -- a swing of yours is already open
	| "NoSwing" -- a release/cancel with nothing open
	| "Disabled"
	| "TooDim" -- this row needs more uncovered flame (Bright Seam)
	| "TooBright" -- this row needs a restrained uncovered flame (Dim Seam)

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

-- How many deposits this floor WANTS, given its own placement roll. Zero to four, weighted by depth
-- (Config/Mining.placement.depositCounts) so a shallow floor usually carries one seam or none and a
-- deep floor usually carries two or three, with a rare fourth seam past floor ten.
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

--------------------------------------------------------------------------------
-- The tier ladder
--------------------------------------------------------------------------------

-- THE STREAK. A stance opens at the slowest, most forgiving tier and climbs on Perfect strikes; the
-- tier it is at governs how fast the marker sweeps and how wide the two scoring bands are. Everything
-- below is pure and reads only `Config/Mining.timing.tiers`, so the rail the player watches, the
-- window the server scores against, and the tests all derive the same numbers from the same table.
--
-- TIER IS PER-STANCE MOMENTUM, NOT ROCK STATE. It lives in MiningService's Session beside the sweep
-- clock, so two miners at one Twin Seam climb independently and every fresh engage starts at 1. It is
-- deliberately NOT in Types.DepositState: a seam does not remember how well the last person did.
--
-- NOTHING HERE TOUCHES PAYOUT. A tier changes how hard a Perfect is to land and never what one is
-- worth — grams and progress are decided by the row and the accuracy alone, exactly as before.

-- Any caller's idea of a tier, resolved to a real rung. nil is tier 1 rather than an error, and that
-- is the correct reading rather than a lenient one: a caller that has never been told a tier is a
-- fresh stance, and a fresh stance IS tier 1.
--
-- THERE IS NO UPPER CLAMP, because there is no top rung. Only the floor and the non-finite cases are
-- defended; an absurdly large tier is harmless because the speed it resolves to saturates.
function MiningRules.clampTier(tier: number?): number
	if tier == nil or tier ~= tier or tier == math.huge or tier == -math.huge then
		return 1
	end
	return math.max(1, math.floor(tier))
end

-- The DURATION scale this rung plays at: `base * ratio ^ (tier - 1)`, bounded below so the sweep can
-- never fall under `minSweepSeconds`.
--
-- THE BOUND IS THE FRAME CLOCK, NOT A DIFFICULTY CEILING. Input is sampled once per rendered frame, so
-- a Perfect window thinner than a couple of frames stops being a test of timing and becomes a coin
-- toss — see the derivation in Config/Mining.timing.tiers. The ladder still climbs past that rung; it
-- simply has nothing left to give, which is a far better failure mode than an aperture nobody can hit.
local function tierSpeedMultiplier(tier: number?): number
	local timing = MiningConfig.timing
	local tiers = timing.tiers
	-- A ratio at or above 1 would never escalate and one at or below 0 would flip sign every rung;
	-- both are broken configs, and both are cheaper to clamp than to crash a live stance over.
	local ratio = math.clamp(tiers.speedRatioPerTier, 0.01, 1)
	local raw = tiers.baseSpeedMultiplier * ratio ^ (MiningRules.clampTier(tier) - 1)
	if timing.sweepSeconds <= 0 then
		return raw
	end
	return math.max(raw, math.max(0, tiers.minSweepSeconds) / timing.sweepSeconds)
end

-- The first rung whose sweep has already hit the floor, and therefore the highest tier at which
-- anything about the rail still changes. The tier NUMBER keeps climbing past it — this is the honest
-- answer to "how fast does this actually get", not a cap, and nothing enforces it.
function MiningRules.saturationTier(): number
	local timing = MiningConfig.timing
	local tiers = timing.tiers
	local ratio = math.clamp(tiers.speedRatioPerTier, 0.01, 1)
	local floorMultiplier = if timing.sweepSeconds > 0
		then math.max(0, tiers.minSweepSeconds) / timing.sweepSeconds
		else 0
	-- A ladder that never descends to the floor, or starts already on it, saturates immediately.
	if ratio >= 1 or floorMultiplier <= 0 or tiers.baseSpeedMultiplier <= floorMultiplier then
		return 1
	end
	return 1 + math.ceil(math.log(floorMultiplier / tiers.baseSpeedMultiplier) / math.log(ratio))
end

-- The two scoring half-widths this tier actually plays at, as fractions of one sweep. Every read of
-- the band widths goes through these, so there stays exactly one place a width is decided.
--
-- THE TIER IS ACCEPTED AND IGNORED, deliberately. `widthMultiplier` is one value for the whole ladder
-- — the target does not change size, by design — but the argument stays in the signature because the
-- width is a real dial, every caller already threads a tier, and the HUD is already built to rebuild
-- its geometry when one changes. Making it per-rung again is a config edit, not a refactor.
function MiningRules.effectivePerfectHalfWidth(_tier: number?): number
	return MiningConfig.timing.perfectHalfWidth * MiningConfig.timing.tiers.widthMultiplier
end

function MiningRules.effectiveGoodHalfWidth(_tier: number?): number
	return MiningConfig.timing.goodHalfWidth * MiningConfig.timing.tiers.widthMultiplier
end

-- How long this tier's sweep and its lead-in take, in seconds. Both scale by the same factor on
-- purpose: a wind-up that stayed fixed while the sweep accelerated would become a larger and larger
-- share of the beat, and the rail's "here it comes" moment would swallow the read it exists to set up.
function MiningRules.effectiveSweepSeconds(tier: number?): number
	return MiningConfig.timing.sweepSeconds * tierSpeedMultiplier(tier)
end

function MiningRules.effectiveWindupSeconds(tier: number?): number
	return MiningConfig.deposit.swingWindupSeconds * tierSpeedMultiplier(tier)
end

-- WHERE THE NEXT STRIKE SITS ON THE LADDER, given how this one landed. A Perfect climbs one rung, with
-- nothing above it to stop at; a Good drops exactly one; a Miss falls all the way back.
--
-- THE ASYMMETRY IS THE MECHANIC. Climbing is one rung at a time so getting high is a RUN of Perfects
-- rather than a lucky swing, and a Good — the ordinary outcome of overreaching — costs one rung rather
-- than the streak, so the ladder settles a player at the fastest rail they can actually hold instead
-- of yo-yoing them to the bottom. A Miss is the only thing that erases the whole climb, which keeps
-- the fumble the real penalty here exactly as it is everywhere else in this file.
function MiningRules.nextTier(currentTier: number?, accuracy: Types.StrikeAccuracy): number
	if accuracy == "Miss" then
		return 1
	end
	local current = MiningRules.clampTier(currentTier)
	if accuracy == "Perfect" then
		return current + 1
	end
	return math.max(current - 1, 1)
end

-- Where the marker sits in its sweep, 0..1, `elapsed` seconds after the swing began. The wind-up is
-- dead time before the sweep starts, so the sweep and the animation agree about when the rail is
-- live. Returns nil during the wind-up: there is no phase to release into yet.
--
-- Both durations come from the TIER, so a stance that has climbed reads a faster rail from the same
-- elapsed clock. `tier` is optional and nil means 1 — the tier a stance opens at.
function MiningRules.sweepPhase(elapsed: number, tier: number?): number?
	local windupSeconds = MiningRules.effectiveWindupSeconds(tier)
	local sweepSeconds = MiningRules.effectiveSweepSeconds(tier)
	if sweepSeconds <= 0 or elapsed < windupSeconds then
		return nil
	end
	return ((elapsed - windupSeconds) % sweepSeconds) / sweepSeconds
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
-- do not run a wandering band (the rail's own colouring, tests); `tier` defaults to the tier a fresh
-- stance opens at, and decides how wide the two bands are.
function MiningRules.accuracyForPhase(phase: number, center: number?, tier: number?): Types.StrikeAccuracy
	local timing = MiningConfig.timing
	local distance = phaseDistance(phase, (center or timing.perfectCenter) % 1)
	if distance <= MiningRules.effectivePerfectHalfWidth(tier) then
		return "Perfect"
	elseif distance <= MiningRules.effectiveGoodHalfWidth(tier) then
		return "Good"
	end
	return "Miss"
end

-- How well a strike `elapsed` seconds into the current sweep landed. Striking during the wind-up is
-- a miss, not a free retry: a twitchy click still costs you the swing.
--
-- The tier reaches BOTH halves of this — it sets how long the wind-up and sweep are, and how wide the
-- bands the resulting phase is measured against are — which is why it has to be passed here rather
-- than applied to the answer afterwards.
function MiningRules.accuracyForElapsed(elapsed: number, center: number?, tier: number?): Types.StrikeAccuracy
	local phase = MiningRules.sweepPhase(elapsed, tier)
	if phase == nil then
		return "Miss"
	end
	return MiningRules.accuracyForPhase(phase, center, tier)
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

-- WHAT ONE SWING PUTS IN THE BAG, in whole Raw Wax grams.
--
-- A clean strike pays the row's full rate; a Good strike pays `goodFractionOfPerfect` of it, floored;
-- a Miss pays nothing whatsoever.
--
-- THE SAME FRACTION SCALES THE PROGRESS (`progressForAccuracy`), and that is not a coincidence — it is
-- what makes Good and Perfect pay the identical amount for the identical amount of rock removed. A
-- seam worked entirely in Good strikes is worth exactly what one worked entirely in Perfect strikes is
-- worth; it simply takes longer and makes more noise doing it. The MISS is the only band that removes
-- rock without releasing wax, which is what makes it the real penalty rather than merely the slow one.
-- Config/Mining carries the measured cost by skill.
--
-- FLOORED, NEVER ROUNDED, and never below zero. Every amount in this economy is a whole gram
-- (Logic/CargoRules), so a fractional yield has to resolve here rather than downstream, and it
-- resolves in the direction that cannot mint anything.
function MiningRules.gramsForAccuracy(accuracy: Types.StrikeAccuracy, row: DepositRow?): number
	if accuracy == "Miss" then
		return 0
	end
	local resolved = row or MiningRules.resolveRow(FALLBACK_ROW_ID)
	local perStrike = resolved.gramsPerStrike
	if typeof(perStrike) ~= "number" or perStrike ~= perStrike or perStrike <= 0 then
		return 0
	end
	if accuracy == "Perfect" then
		return math.max(0, math.floor(perStrike))
	end
	local fraction = math.clamp(MiningConfig.timing.goodFractionOfPerfect, 0, 1)
	return math.max(0, math.floor(perStrike * fraction))
end

--------------------------------------------------------------------------------
-- The explosive seam
--------------------------------------------------------------------------------

-- THE ODDS THAT STRIKE `strikeCount` IS THE ONE THAT SETS AN EXPLOSIVE SEAM OFF. `strikeCount` is
-- one-based and counts the strike being resolved, so the first swing at a fresh seam asks for 1.
--
-- Flat for the opening `primeChanceRampStrikes` swings and then climbing linearly to certainty. The
-- authored distribution this produces — and why it is shaped this way — is derived in full in
-- Config/Mining.explosive; this function is only the formula, and it is pure so that the derivation
-- can be asserted rather than believed (Tests/MiningRulesTests).
--
-- Zero for every row that is not explosive, so a caller that forgets to check the row cannot
-- accidentally prime a Standard seam.
function MiningRules.primeChance(row: DepositRow?, strikeCount: number): number
	if not MiningRules.neverDepletes(row) then
		return 0
	end
	if strikeCount ~= strikeCount or strikeCount < 1 then
		return 0
	end
	local explosive = MiningConfig.explosive
	local ramp = math.max(0, math.floor(explosive.primeChanceRampStrikes))
	local over = math.max(0, math.floor(strikeCount) - ramp)
	return math.clamp(explosive.primeChanceBase + explosive.primeChancePerStrike * over, 0, 1)
end

-- Did this strike prime the seam? `roll` is a uniform sample in [0, 1) supplied by the caller, so the
-- decision itself stays pure and the randomness stays server-owned (MiningService). Strictly `<`, so
-- a chance of exactly 0 can never fire however the roll is generated.
function MiningRules.rollPrimes(row: DepositRow?, strikeCount: number, roll: number): boolean
	local chance = MiningRules.primeChance(row, strikeCount)
	if chance <= 0 or roll ~= roll then
		return false
	end
	return roll < chance
end

-- How far into its fuse a primed seam is, 0 at the crackle and 1 at the blast. Drives the client's
-- presentation and the server's detonation check from ONE function, so what the player hears and what
-- the cave does can never be a frame apart on which one happened first.
function MiningRules.fuseProgress(elapsed: number): number
	local fuse = MiningConfig.explosive.fuseSeconds
	if fuse <= 0 then
		return 1
	end
	return math.clamp(elapsed / fuse, 0, 1)
end

-- How much Living Wax a candle `distance` studs from the blast loses. Linear from the full cost at
-- the centre to nothing at the edge, so "get further away" is always worth something rather than
-- being a binary the player cannot read. Zero outside the radius.
function MiningRules.blastWaxCost(distance: number): number
	local explosive = MiningConfig.explosive
	local radius = explosive.blastRadius
	if radius <= 0 or distance ~= distance or distance >= radius then
		return 0
	end
	return math.max(0, explosive.blastWaxCost * (1 - math.max(0, distance) / radius))
end

-- THE resolution. Takes the deposit's current progress and how far into the current sweep the
-- strike landed; returns what it was worth. The server is the only caller that keeps the result.
--
-- `tier` reaches the ACCURACY and stops there. What that accuracy is then worth — progress, grams,
-- noise — is the row's business and the accuracy's, so climbing the ladder changes only how hard the
-- Perfect was to earn and never how much it pays. It is the whole reason the streak can be tuned
-- without re-deriving a single number in the economy.
function MiningRules.resolveStrike(
	progress: number,
	elapsed: number,
	center: number?,
	row: DepositRow?,
	tier: number?
): Types.StrikeOutcome
	local accuracy = MiningRules.accuracyForElapsed(elapsed, center, tier)
	local nextProgress = math.clamp(progress + MiningRules.progressForAccuracy(accuracy, row), 0, 1)

	-- CLOSE ENOUGH IS BROKEN. `n` accumulations of `1 / n` do not reach 1 in binary floating point for
	-- most n — six sixths sum to 0.9999999999999999 — so a strict `>= 1` would have made a six-strike
	-- Twin Seam take seven and a nine-strike Deep Seam take ten. The player would have counted their
	-- swings, been told "0 clean left", and watched the rock refuse to break.
	--
	-- The tolerance is safe by a wide margin rather than by luck: the SMALLEST progress any single swing
	-- can add is a miss on the longest row (0.3 / 9 = 0.033), four orders of magnitude above this. No
	-- combination of swings can cross the line early.
	--
	-- A ROW THAT NEVER DEPLETES SIMPLY NEVER CROSSES IT. Progress still accumulates and is still drawn
	-- — an explosive seam visibly opens up as it is worked — but it saturates at the top and the seam
	-- stays workable. This is the ONE place the flag is honoured, so the rest of the system continues
	-- to reason about exactly one kind of seam.
	local depleted = nextProgress >= 1 - 1e-6 and not MiningRules.neverDepletes(row)
	return {
		accuracy = accuracy,
		-- Snapped to exactly 1 once broken, so the seam's replicated progress and its depleted flag can
		-- never disagree about whether it is finished.
		progress = if depleted then 1 else nextProgress,
		depleted = depleted,
		grams = MiningRules.gramsForAccuracy(accuracy, row),
		noiseKind = MiningRules.noiseKindFor(accuracy, depleted),
	}
end

-- Clean swings still needed, for a display that never implies more precision than the server has.
--
-- Carries the same floating-point tolerance as `resolveStrike`, and for the same reason: at five
-- sixths of a Twin Seam, `(1 - 0.8333) / 0.1667` evaluates to 1.0000000000000002 and a bare `ceil`
-- would promise TWO more clean strikes when one would break it. The readout and the rock have to
-- agree, or the number on screen is the game lying about its own state.
--
-- A NEVER-DEPLETING ROW ANSWERS -1 rather than a number of swings, because there is no honest number
-- to give: the seam does not end. Callers present that as "no end in sight" and never as a count, and
-- returning a sentinel rather than 0 keeps it from reading as "one more and it breaks".
function MiningRules.cleanStrikesRemaining(progress: number, row: DepositRow?): number
	if MiningRules.neverDepletes(row) then
		return -1
	end
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
	-- An explosive seam whose fuse is already running. Optional so a caller that predates the row
	-- validates exactly as it did; absent reads as "not primed", which is true of every other seam.
	depositPrimed: boolean?,
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
	minimumBurnRate: number?,
	maximumBurnRate: number?,
}

-- Which side of this row's authored burn window the candle falls on. A Flare clears a minimum-only
-- Bright Seam, but is intentionally above a Dim Seam's ceiling. Missing readings fail closed.
local function burnDenial(request: StrikeRequest): Denial?
	local row = request.row
	if row == nil then
		return nil
	end
	local required = MiningRules.requiredBurnRate(row, request.minimumBurnRate, request.maximumBurnRate)
	local maximum = MiningRules.maximumBurnRate(row, request.minimumBurnRate, request.maximumBurnRate)
	if request.isFlaring == true then
		return if row.maxBurnFraction < 1 then "TooBright" else nil
	end
	local burn = request.burnRate
	if burn == nil or burn ~= burn then
		return if required > 0 then "TooDim" elseif row.maxBurnFraction < 1 then "TooBright" else nil
	end
	if burn < required then
		return "TooDim"
	elseif burn > maximum then
		return "TooBright"
	end
	return nil
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
	-- A lit fuse ends the stance for everyone at the rock, and it is checked here — beside depletion —
	-- rather than in the service, so the client greys its own prompt out on exactly the same rule the
	-- server enforces. There is no "one more swing" while the seam is counting down.
	if request.depositPrimed == true then
		return false, "Primed"
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
	local burnFailure = burnDenial(request)
	if burnFailure ~= nil then
		return false, burnFailure
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
	-- A lit fuse ends the stance for everyone at the rock, and it is checked here — beside depletion —
	-- rather than in the service, so the client greys its own prompt out on exactly the same rule the
	-- server enforces. There is no "one more swing" while the seam is counting down.
	if request.depositPrimed == true then
		return false, "Primed"
	end
	if request.distance > deposit.interactionRange then
		return false, "OutOfRange"
	end
	if deposit.requiresLineOfSight and not request.hasLineOfSight then
		return false, "Obstructed"
	end
	-- Re-checked on every strike, not only at engagement: letting the dial fall mid-seam has to end the
	-- stance, or a player could open a Bright Seam at full burn and then finish it in the dark.
	local burnFailure = burnDenial(request)
	if burnFailure ~= nil then
		return false, burnFailure
	end
	return true, nil
end

-- Has an engaged player gone quiet long enough to release the stance for them? Prevents a client
-- that stopped responding from leaving someone rooted to a rock forever.
function MiningRules.swingHasTimedOut(elapsed: number): boolean
	return elapsed >= MiningConfig.deposit.swingTimeoutSeconds
end

return MiningRules

--!strict
-- Pure mining rules: who may swing, where a swing landed in the timing sweep, what that swing is
-- worth, and how loud it was. Server, client and tests all read these, so the timing ring the
-- player sees and the accuracy the server awards are the same function evaluated against the same
-- server timestamp — never two implementations that can disagree.
--
-- NOTHING HERE TOUCHES A THREAT. A swing produces progress and a noise kind. Whether anything comes
-- to look is entirely the sound field's business (Logic/SoundField), which is why the pickaxe can
-- never become a weapon by accident: there is no code path from a strike to a threat's health,
-- because threats have no health.

local Types = require(script.Parent.Parent.Types)
local MiningConfig = require(script.Parent.Parent.Config.Mining)

local MiningRules = {}

export type Denial =
	"Dead" -- burned out, snuffed, or already finished
	| "NotLit" -- you cannot work a seam in the dark
	| "Covered" -- ...nor with the flame cupped down to an ember
	| "WrongFloor" -- the deposit is on another floor of the expedition
	| "OutOfRange"
	| "Depleted" -- someone already broke it, possibly on this same frame
	| "Cooldown" -- too soon after the previous swing
	| "AlreadySwinging" -- a swing of yours is already open
	| "NoSwing" -- a release/cancel with nothing open
	| "Disabled"

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
-- dead time before the sweep starts, so the sweep and the animation agree about when the ring is
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
-- WHY IT MOVES AT ALL: the stance keeps the ring sweeping continuously, and a band that never moved
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
-- do not run a wandering band (the ring's own colouring, tests).
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

function MiningRules.progressForAccuracy(accuracy: Types.StrikeAccuracy): number
	local timing = MiningConfig.timing
	if accuracy == "Perfect" then
		return timing.perfectProgress
	elseif accuracy == "Good" then
		return timing.goodProgress
	end
	return timing.missProgress
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
function MiningRules.resolveStrike(progress: number, elapsed: number, center: number?): Types.StrikeOutcome
	local accuracy = MiningRules.accuracyForElapsed(elapsed, center)
	local nextProgress = math.clamp(progress + MiningRules.progressForAccuracy(accuracy), 0, 1)
	local depleted = nextProgress >= 1
	return {
		accuracy = accuracy,
		progress = nextProgress,
		depleted = depleted,
		noiseKind = MiningRules.noiseKindFor(accuracy, depleted),
	}
end

-- Clean swings still needed, for a display that never implies more precision than the server has.
function MiningRules.cleanStrikesRemaining(progress: number): number
	local perStrike = MiningConfig.timing.perfectProgress
	if perStrike <= 0 then
		return 0
	end
	return math.max(0, math.ceil((1 - progress) / perStrike))
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
	now: number,
	nextStrikeAt: number, -- os.clock() this player's cooldown clears
	hasOpenSwing: boolean,
}

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
	if request.hasOpenSwing then
		return false, "AlreadySwinging"
	end
	if request.now < request.nextStrikeAt then
		return false, "Cooldown"
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
	return true, nil
end

-- Has an engaged player gone quiet long enough to release the stance for them? Prevents a client
-- that stopped responding from leaving someone rooted to a rock forever.
function MiningRules.swingHasTimedOut(elapsed: number): boolean
	return elapsed >= MiningConfig.deposit.swingTimeoutSeconds
end

return MiningRules

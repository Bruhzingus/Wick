--!strict
-- Pure: how many wick-pack bodies a floor carries, and which.
--
-- WHY THIS IS NOT PART OF THE THREAT BUDGET. The existing roster is drawn from one weighted pool per
-- room module, which is the right shape for six interchangeable creatures that all read light and all
-- run on the same brain. These four are not interchangeable — ENCOUNTERS.md is explicit that some
-- pairings are good and some are unreadable — so they are budgeted per SPECIES against depth instead
-- of drawn from a shared bag, and the pairing rules are enforceable because each count is decided
-- separately and can see the others.
--
-- THE PAIRING RULES, straight from docs/wick-enemies/ENCOUNTERS.md, and the reason this file exists
-- rather than three independent rolls:
--   * Never two Gnawers on a floor. Two straight-line charges in one space is unreadable — a player
--     cannot track two commit directions at once.
--   * Gnawer + Longarm is workable in a large chamber and miserable in a corridor, so at most one
--     of each and never before the depth where rooms are reliably large.
--   * Grubs alone are a breather, and that is a legitimate floor.
--
-- Everything here is a pure function of depth and an RNG, so a floor seed reproduces its roster and a
-- cold test can pin the curve without building a cave.

local EnemySpawnRules = {}

export type Budget = {
	broods: number,
	gnawers: number,
	longarms: number,
}

-- Sampled the way every other depth curve in this game is (Config's own convention): index by floor,
-- clamp at both ends, never interpolate. An authored table IS the curve.
local function valueAtDepth(values: { number }, depth: number, fallback: number): number
	if #values == 0 then
		return fallback
	end
	local index = math.clamp(math.floor(depth), 1, #values)
	local value = values[index]
	if value == nil or value ~= value then
		return fallback
	end
	return value
end

-- CHANCE PER FLOOR, per species, by depth.
--
-- The grub is tier 1 and shows up almost immediately: it is the creature that teaches a player that
-- something in this cave wants their wax, and it is survivable on the floor where they learn it.
-- Floor 1 is left clear deliberately, exactly as the dynamite schedule leaves it clear — the first
-- room a player ever walks into should teach the light, and nothing else.
local BROOD_CHANCE = { 0, 0.35, 0.45, 0.5, 0.55, 0.6, 0.6, 0.65, 0.65, 0.7 }
-- A second brood is rolled only if the first landed, so two is genuinely uncommon rather than half of
-- all grub floors. ENCOUNTERS.md: never more than two broods in a room, and this keeps them apart.
local SECOND_BROOD_CHANCE = { 0, 0, 0.12, 0.16, 0.2, 0.24, 0.26, 0.28, 0.3, 0.32 }

-- Both tier 3, and both held off the shallow floors entirely. A Gnawer needs a room with twenty studs
-- of clear width to be dodgeable and a Longarm needs the player to already have learned what safe
-- distance means from something else — neither is true of the tutorial band.
local GNAWER_CHANCE = { 0, 0, 0, 0, 0.18, 0.24, 0.3, 0.34, 0.38, 0.42 }
local LONGARM_CHANCE = { 0, 0, 0, 0, 0.16, 0.22, 0.28, 0.32, 0.36, 0.4 }

-- Below this depth neither tier-3 body may appear at all, whatever the curve says. A hard floor under
-- the curves so retuning a table cannot accidentally put a Longarm on floor two.
local TIER_THREE_MIN_DEPTH = 5

function EnemySpawnRules.budgetForDepth(depth: number, rng: Random): Budget
	local resolved = if depth == depth then math.max(1, math.floor(depth)) else 1

	local broods = 0
	if rng:NextNumber() < valueAtDepth(BROOD_CHANCE, resolved, 0) then
		broods = 1
		if rng:NextNumber() < valueAtDepth(SECOND_BROOD_CHANCE, resolved, 0) then
			broods = 2
		end
	end

	local gnawers = 0
	local longarms = 0
	if resolved >= TIER_THREE_MIN_DEPTH then
		-- AT MOST ONE GNAWER, ALWAYS. Not a roll that happens to usually produce one — a hard cap, so
		-- no retune of the curve can ever put two unreadable charge lines in one space.
		if rng:NextNumber() < valueAtDepth(GNAWER_CHANCE, resolved, 0) then
			gnawers = 1
		end
		if rng:NextNumber() < valueAtDepth(LONGARM_CHANCE, resolved, 0) then
			longarms = 1
		end
	end

	return { broods = broods, gnawers = gnawers, longarms = longarms }
end

-- Whether these two may share a floor at all. Kept as its own question rather than folded into the
-- budget because the answer depends on the floor's geometry, which the planner knows and this does
-- not: "workable in a large chamber, miserable in a corridor".
function EnemySpawnRules.allowsGnawerWithLongarm(largestRoomWidth: number): boolean
	return largestRoomWidth >= 40
end

-- The clear width a Gnawer's room needs perpendicular to its likely charge line. Below this there is
-- nowhere to dodge, and a charge with no dodge is not an encounter.
function EnemySpawnRules.minimumGnawerRoomWidth(): number
	return 20
end

function EnemySpawnRules.tierThreeMinimumDepth(): number
	return TIER_THREE_MIN_DEPTH
end

return EnemySpawnRules

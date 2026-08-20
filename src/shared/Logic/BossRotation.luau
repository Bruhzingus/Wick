--!strict
-- WHICH BOSS OWNS WHICH FLOOR. The one place in the game that answers "is this a boss floor, and
-- whose?" (DESIGN §9a, §9b).
--
-- THE CADENCE CHANGED WHEN THERE WERE TWO OF THEM, and it is worth writing down why. The Grub Queen
-- alone was walked from the run seed at a random 10-15 floor interval, which was the right shape for
-- one boss: an interval a player cannot count down to, with a guarantee that two never land back to
-- back. With a second boss the interesting property is no longer surprise, it is ALTERNATION — a run
-- that reaches floor 40 should have met her twice and him twice, in that order, and a player who has
-- learned one fight should be able to expect the other. A random interval cannot promise that; it can
-- only promise an average, and an average that occasionally hands somebody the same boss three times
-- is a rotation nobody experiences as one.
--
-- So: a boss floor every ten, and they take turns.
--
--   floor 10  Grub Queen        floor 40  Unlittius
--   floor 20  Unlittius         floor 50  Grub Queen
--   floor 30  Grub Queen        floor 60  Unlittius
--
-- OWNER DECISION, recorded here rather than inferred: "every 10 levels, starting 10 levels after the
-- Grub Queen, alternating with her."
--
-- IT TAKES NO SEED AND ROLLS NOTHING. That is the point — the schedule is a promise across floors
-- rather than a per-floor outcome, and floors are planned independently and out of order, so anything
-- derived from a per-floor stream would be free to disagree with itself. `Config.GrubQueen`'s own
-- `minIntervalFloors`/`maxIntervalFloors` are no longer the cadence; they are kept as her documented
-- design range and this file is the authority.

local GrubQueenConfig = require(script.Parent.Parent.Config.GrubQueen)
local UnlittiusConfig = require(script.Parent.Parent.Config.Unlittius)

local BossRotation = {}

export type BossId = "GrubQueen" | "Unlittius"

-- Floors between boss floors, and the depth the first one lands on. One number for both, because
-- "every ten, starting at ten" is one decision rather than two.
BossRotation.INTERVAL_FLOORS = 10

-- The rotation, in the order they are met. Adding a third boss is a row here and nothing else.
local ORDER: { BossId } = { "GrubQueen", "Unlittius" }

BossRotation.ORDER = ORDER

-- Whether an encounter is switched on at all. Both bosses can be disabled from their own config
-- without this file learning about either of them: a boss nobody can finish would be a floor a party
-- cannot descend from.
local function enabled(bossId: BossId): boolean
	if bossId == "GrubQueen" then
		return GrubQueenConfig.health > 0
	end
	return UnlittiusConfig.encounter.candleCount > 0
end

-- WHOSE FLOOR IS THIS? Returns nil on every ordinary floor, which is almost all of them.
function BossRotation.bossAt(globalDepth: number): BossId?
	if globalDepth ~= globalDepth or globalDepth < BossRotation.INTERVAL_FLOORS then
		return nil
	end
	local depth = math.floor(globalDepth)
	if depth % BossRotation.INTERVAL_FLOORS ~= 0 then
		return nil
	end
	local turn = depth // BossRotation.INTERVAL_FLOORS
	local bossId = ORDER[(turn - 1) % #ORDER + 1]
	if not enabled(bossId) then
		return nil
	end
	return bossId
end

function BossRotation.isBossDepth(globalDepth: number): boolean
	return BossRotation.bossAt(globalDepth) ~= nil
end

-- The next depth at or after `fromDepth` that carries a boss, and who. Used by nothing in the fight
-- itself — it exists so a tester, a telemetry query or a future "what is coming" readout never has to
-- re-derive the schedule and get it subtly wrong.
function BossRotation.nextBossDepth(fromDepth: number): (number?, BossId?)
	local depth = math.max(math.floor(fromDepth), 1)
	for candidate = depth, depth + BossRotation.INTERVAL_FLOORS * #ORDER do
		local bossId = BossRotation.bossAt(candidate)
		if bossId ~= nil then
			return candidate, bossId
		end
	end
	return nil, nil
end

return BossRotation

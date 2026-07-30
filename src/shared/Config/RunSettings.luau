--!strict
-- Run-level tuning: pacing, party size, tick rates, and expedition entry.
-- The form a burned-out player takes now lives in `Config/Spectator` (the ghost candle), which owns
-- its body, its almost-nothing light, following, and the ghost-only trail.

export type RunConfig = {
	targetRunLengthSeconds: number,
	partyCap: number,
	soloAllowed: boolean,
	tickRate: number,
	stateReplicationHz: number,
	startCountdownSeconds: number,
	restartDelaySeconds: number,
	entrySpawnRadius: number,
	entrySpawnClearance: number,
}

local Run: RunConfig = {
	-- Target length of a full descent (seconds). Longer = more sustained tension — watch for tedium (DESIGN §20).
	targetRunLengthSeconds = 1200,
	-- Maximum players per run (DESIGN §21: cap 4; ARCHITECTURE invariant). Party size shifts difficulty balance.
	partyCap = 4,
	-- Whether a single player can start a run alone.
	soloAllowed = true,
	-- Authoritative wax ticks per second. Higher = smoother drain, more server work. Mechanical, not feel.
	tickRate = 10,
	-- State broadcasts to clients per second (wax bar / body sync cadence). Mechanical, not feel.
	stateReplicationHz = 10,
	-- Seconds after the lobby/arrival handoff accepts an expedition before the descent starts.
	startCountdownSeconds = 5,
	-- Results remain available long enough to choose replay or return to tier selection.
	restartDelaySeconds = 60,
	-- Runner one uses the room centre; additional runners use stable, separated slots on this
	-- radius. It must fit inside the entry room's guaranteed-clear central footprint.
	entrySpawnRadius = 5,
	-- Empty horizontal space required between two candle colliders at an entry spawn.
	entrySpawnClearance = 0.5,
}

return Run

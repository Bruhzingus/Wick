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
	floorLookahead: number,
	floorRetentionBehind: number,
	floorRetirementCheckSeconds: number,
	maxFloorRetirementsPerCheck: number,
	retainEntryFloor: boolean,
	entrySpawnRadius: number,
	entrySpawnClearance: number,
	floorRecoveryDrop: number,
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
	-- HOW MANY FLOORS ARE KEPT READY, counting the one a runner is standing on. Three means the floor
	-- below and the one below that are already carved by the time anybody reaches a descent pad.
	--
	-- ONLY THE FIRST OF THEM IS EVER BUILT SYNCHRONOUSLY. A floor is the single most expensive thing
	-- this server does, and the descent is gated on it: every floor built before the party spawns is
	-- time the loading screen spends on an empty screen. So the run builds floor one, puts bodies in
	-- it, and lets the rest of the lookahead fill in on later frames — one floor per frame, never a
	-- stack of them at once. A runner who somehow outruns the queue is not stranded: the descent check
	-- builds the floor beneath them on demand before it moves anyone.
	floorLookahead = 3,
	-- Floors strictly farther behind the shallowest connected runner/ghost than this margin are
	-- retired. Party splits and a spectator who deliberately remains behind therefore keep their
	-- ground intact; ordinary groups bound history to this trailing window plus the retained entry.
	floorRetentionBehind = 2,
	-- Terrain removal is deliberately amortized instead of landing on a descent/build frame in a
	-- burst. One exact floor every half-second is fast enough to catch up with play and cheap enough
	-- to avoid a visible server hitch.
	floorRetirementCheckSeconds = 0.5,
	maxFloorRetirementsPerCheck = 1,
	-- Same-server late party arrivals currently enter through floor one. Keeping that single floor is
	-- a constant memory cost and preserves the existing admission/rejoin contract.
	retainEntryFloor = true,
	-- Runner one uses the room centre; additional runners use stable, separated slots on this
	-- radius. It must fit inside the entry room's guaranteed-clear central footprint.
	entrySpawnRadius = 5,
	-- Empty horizontal space required between two candle colliders at an entry spawn.
	entrySpawnClearance = 0.5,
	-- How far below its own floor's base plane a candle has to be before the expedition treats it as
	-- having left the world and puts it back at the entry. Comfortably below the deepest legitimate
	-- ground (a Deep Sump's bed is two studs) and comfortably above the next floor down, which begins
	-- a full `Config.Floors.geometry.floorGap` (96) lower — so nothing real ever sits in this band.
	floorRecoveryDrop = 32,
}

return Run

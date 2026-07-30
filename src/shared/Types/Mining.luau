--!strict
-- Mining-domain types. One generic Raw Wax deposit, struck with a contextual pickaxe. There is still
-- no inventory, no crafting, and no deposit rarity — a seam is a seam, and the only thing that varies
-- is how deep you were standing when you broke it.
--
-- PHASE 8: mining is now the game's only source of income. What a seam yields is still a flat integer
-- count of units; what those units are WORTH is decided entirely by origin depth, in
-- Logic/ExtractionValue, and is only ever realised by walking them out through a brazier.

-- How well one swing landed against the deposit's timing sweep. Closed union — the three bands are
-- the mechanic, not content that grows by config.
export type StrikeAccuracy = "Perfect" | "Good" | "Miss"

-- What one swing did. Returned by the pure rules; the server applies it and owns the result.
export type StrikeOutcome = {
	accuracy: StrikeAccuracy,
	progress: number, -- deposit progress AFTER this swing, 0..1
	depleted: boolean,
	noiseKind: string, -- Config/Sound row this swing announces itself with
}

-- Live server-owned state of one placed deposit. Not replicated as a table; the server publishes
-- only the quantized attributes in MiningVisualProtocol.
export type DepositState = {
	id: number, -- stable per-run identity; the deduplication key every cargo grant is checked against
	depth: number, -- floor ordinal this deposit belongs to
	position: Vector3,
	progress: number, -- 0..1; the server is the only writer
	strikes: number, -- swings resolved so far, for telemetry and the sequence guard
	depleted: boolean,
	-- Which Config/Mining row this seam behaves as. Decides its strike count, its yield, how many
	-- miners one break may pay, and whether it demands a bright flame (Logic/MiningRules).
	rowId: string,
}

-- PHASE 8 cargo (Config/Extraction). One player's Raw Wax, grouped by the GLOBAL depth it came out
-- of. Integer units only — there is no fractional Raw Wax anywhere, so no accounting here can turn
-- into a floating-point argument. Origin depth is not a label: it is the field the payout curve
-- prices, which is why it is stamped at the moment of the break and never rewritten afterwards.
export type RawWaxStack = {
	originDepth: number, -- global depth of the deposit these units were broken out of
	units: number, -- positive integer
}

-- Run-scoped and never convertible to wax. Only the VALUE of an extracted bag ever reaches a profile;
-- the bag itself dies with the run. `total` is maintained alongside `stacks` so no reader has to
-- re-sum (and so a mismatch between the two is a testable invariant).
export type RawWaxCargo = {
	stacks: { RawWaxStack }, -- ascending by originDepth; at most one stack per depth
	total: number,
}

-- Everything one player's run knows about its own cargo. Lives on PlayerRunState beside the bag
-- itself. The unit counters exist so a finished run can be reconciled to zero:
--   acquired == lost + dropped + extracted + still carried.
-- A non-zero reconciliation means units appeared or vanished outside CargoRules, which is the only
-- bug in this system that could mint currency.
export type RawWaxRun = {
	cargo: RawWaxCargo,
	unitsAcquired: number, -- granted by breaks, over the whole run
	unitsLost: number, -- shattered outright (the destroyed half of a death, a lapsed disconnect)
	unitsDropped: number, -- left in the world for someone else to recover
	unitsExtracted: number, -- carried out through a brazier and paid for
	extractionDepth: number?, -- global depth the cargo was extracted at, nil if it never was
	-- THE IDEMPOTENCY LATCH. Extraction can pay out exactly once per run; a second commit — from a
	-- duplicated remote, a replayed transition, or a re-entrant call — finds this true and pays zero.
	extracted: boolean,
	-- The transaction identifier the profile credit was recorded under. Persisted alongside the
	-- currency so that a retried write can tell "this already landed" from "this never landed",
	-- which is the difference between a safe retry and duplicated money.
	extractionId: string?,
	currencyCredited: number, -- what the base extraction actually paid
	partyBonusCredited: number, -- what the retroactive "everyone got out" bonus later added
	-- Every unit this run ever acquired, grouped by origin depth and NEVER cleared. Clearing the bag
	-- is what destroys that detail, and the origin-depth distribution is what the balance pass turns
	-- on — so it accumulates separately from what the player is still carrying.
	acquiredByDepth: RawWaxCargo,
}

return {}

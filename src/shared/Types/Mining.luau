--!strict
-- Mining-domain types. Row-driven Raw Wax deposits are struck with a contextual pickaxe; rows vary
-- clean-strike count, per-swing yield, helper payout, and brightness gate without adding inventory or
-- crafting.
--
-- PHASE 8: mining is now the game's only source of income. What a swing yields is a flat integer count
-- of GRAMS; what those grams are WORTH is decided entirely by origin depth, in
-- Logic/ExtractionValue, and is only ever realised by walking them out through a brazier.
--
-- WHY GRAMS AND NOT UNITS: payment moved from the break to the swing, and a swing is a fraction of a
-- seam. Expressing that fraction as "0.67 units" would have put a float into the one accounting system
-- in the game that must never hold one, so the unit got smaller instead (one old unit is 100g) and
-- every amount stayed a whole number. Config/Extraction carries the full reasoning.

-- How well one swing landed against the deposit's timing sweep. Closed union — the three bands are
-- the mechanic, not content that grows by config.
export type StrikeAccuracy = "Perfect" | "Good" | "Miss"

-- What one swing did. Returned by the pure rules; the server applies it and owns the result.
export type StrikeOutcome = {
	accuracy: StrikeAccuracy,
	progress: number, -- deposit progress AFTER this swing, 0..1
	depleted: boolean,
	-- Raw Wax grams this swing earned the striker. Zero for a Miss: a fumble still chips the rock and
	-- still makes noise, and pays nothing at all.
	grams: number,
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
	-- Which Config/Mining row this seam behaves as. Decides its strike count, its per-swing yield, how
	-- many miners one strike may pay, and whether it demands a bright flame (Logic/MiningRules).
	rowId: string,
	-- EXPLOSIVE SEAMS ONLY (Config/Mining.explosive), nil on every other row. `primedAt` is the
	-- os.clock() the fuse started; the blast lands `fuseSeconds` later. Its presence IS the "this seam
	-- is counting down" flag, so there is no second boolean that could disagree with it.
	primedAt: number?,
}

-- PHASE 8 cargo (Config/Extraction). One player's Raw Wax, grouped by the GLOBAL depth it came out
-- of. Integer grams only — there is no fractional Raw Wax anywhere, so no accounting here can turn
-- into a floating-point argument. Origin depth is not a label: it is the field the payout curve
-- prices, which is why it is stamped at the moment of the swing and never rewritten afterwards.
export type RawWaxStack = {
	originDepth: number, -- global depth of the deposit these grams came out of
	grams: number, -- positive integer
}

-- Run-scoped and never convertible to wax. Only the VALUE of an extracted bag ever reaches a profile;
-- the bag itself dies with the run. `total` is maintained alongside `stacks` so no reader has to
-- re-sum (and so a mismatch between the two is a testable invariant).
export type RawWaxCargo = {
	stacks: { RawWaxStack }, -- ascending by originDepth; at most one stack per depth
	total: number, -- grams
}

-- Everything one player's run knows about its own cargo. Lives on PlayerRunState beside the bag
-- itself. The gram counters exist so a finished run can be reconciled to zero:
--   acquired == lost + dropped + extracted + still carried.
-- A non-zero reconciliation means grams appeared or vanished outside CargoRules, which is the only
-- bug in this system that could mint currency.
export type RawWaxRun = {
	cargo: RawWaxCargo,
	gramsAcquired: number, -- granted by swings, over the whole run
	gramsLost: number, -- shattered outright (the destroyed half of a death, a lapsed disconnect)
	gramsDropped: number, -- left in the world for someone else to recover
	gramsExtracted: number, -- carried out through a brazier and paid for
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
	-- Every gram this run ever acquired, grouped by origin depth and NEVER cleared. Clearing the bag
	-- is what destroys that detail, and the origin-depth distribution is what the balance pass turns
	-- on — so it accumulates separately from what the player is still carrying.
	acquiredByDepth: RawWaxCargo,
}

return {}

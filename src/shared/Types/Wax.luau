--!strict
-- Wax-domain types. Wax is the ONLY resource: health, light, fuel, and timer at once (DESIGN §3).

-- Wax expressed in candle units. Config.Wax.maxWax is the full-capacity presentation reference.
export type WaxAmount = number

-- Live wax meter for a candle. Server-authoritative (ARCHITECTURE).
export type WaxState = {
	current: WaxAmount, -- the live value; hits 0 -> BurnOut
	max: WaxAmount, -- current ceiling; a future sacrifice may lower this
}

-- The brightness dial, 0..1 (DESIGN §4). Higher = brighter and faster drain. 0 = snuffed.
export type BurnRate = number

-- Wax-type loot ids (DESIGN section 14). Closed union — a small, named pool.
-- "Standard" is the neutral starting profile (all multipliers 1); the other three are in-run loot.
export type WaxTypeId = "Standard" | "Beeswax" | "Tallow" | "ColdWax"

-- Why wax moved. Closed union: every authoritative mutation names exactly one of these, so a run
-- can be explained after the fact ("what actually killed this candle?"). Internal accounting only —
-- this is not a second resource and never reaches the player's meter. Clients never supply one.
export type WaxSource =
	"PassiveBurn"
	| "MovementWalk"
	| "MovementRun"
	| "ToolFlare"
	| "ToolDecoy"
	| "ToolCup"
	| "ToolOther"
	| "DamageThreat"
	| "DamageWater"
	| "DamageDripstone"
	| "ReviveCost"
	| "Extraction"
	| "DeathLoss"
	| "BasinGain"
	| "FoundWaxGain"
	| "MiningShardGain"
	| "Other"

-- Running per-player accounting for one expedition. Lives in PlayerRunState; server-only in
-- practice, and never persisted (DESIGN/roadmap: no run telemetry in ProfileStore yet).
export type WaxLedger = {
	startingWax: WaxAmount,
	startedAt: number, -- os.clock() when the run began
	startDepth: number,
	deepestGlobalDepth: number,
	totalLost: WaxAmount,
	totalGained: WaxAmount,
	lostBySource: { [WaxSource]: WaxAmount },
	gainedBySource: { [WaxSource]: WaxAmount },
}

-- How a run ended, for the development-only run summary.
export type WaxRunOutcome = "Extraction" | "BurnOut" | "Snuff" | "Disconnect" | "Unresolved"

export type WaxRunSummary = {
	startingWax: WaxAmount,
	endingWax: WaxAmount,
	totalLost: WaxAmount,
	totalGained: WaxAmount,
	lostBySource: { [WaxSource]: WaxAmount },
	gainedBySource: { [WaxSource]: WaxAmount },
	startDepth: number,
	deepestGlobalDepth: number,
	outcome: WaxRunOutcome,
	durationSeconds: number,
	-- startingWax + totalGained - totalLost - endingWax. Zero when the ledger is complete; a
	-- non-zero value means some mutation bypassed the authoritative path.
	reconciliationError: number,
}

-- Static burn profile for a wax type. Pure data (see Config/WaxTypes).
export type WaxTypeDef = {
	id: WaxTypeId,
	displayName: string,
	drainMultiplier: number, -- scales all drain; higher = hungrier
	brightnessMultiplier: number, -- scales light per unit burn; higher = brighter
	attractsDrawn: boolean, -- cold wax burns without pulling the drawn
}

return {}

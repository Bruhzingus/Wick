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

-- In-run candle modifiers (DESIGN section 14). Closed union — a small, named pool of roguelike
-- upgrades a run accumulates. Every one of them ADDS to the candle you already have; none of them
-- replaces its burn profile, and none is worth more than a few percent on its own.
export type CandleModifierId = "FrozenWax" | "ExtraWicks" | "LifeWax" | "BrightWax" | "CandleSleeve"

-- FROZEN WAX. A banked reserve of wax that only melts while the dial is pinned at maximum, paying
-- a little of the brightness back. `atMaxSeconds` accumulates ACROSS bursts rather than resetting
-- the moment the dial drops, so short breaks in a bright push are not silently punished.
export type FrozenWaxState = {
	reserve: WaxAmount, -- wax units still frozen; the item is gone when this reaches 0
	atMaxSeconds: number, -- seconds burned at maximum since the last melt
}

-- EXTRA WICKS. A temporary multi-wick flame: more light for the same wax. `remaining` is in real
-- seconds and is spent faster the harder the flame is being pushed.
export type ExtraWicksState = {
	wicks: number, -- 1..3, rolled on pickup; presentation plus how long the bundle lasts
	remaining: number, -- seconds of wick left; 0 = no bundle
}

-- CANDLE SLEEVE. A cardboard shield measured in FRACTIONAL hit charges, so a fast attacker spends
-- proportionally less of it per swing than a slow one (Logic/CandleModifiers.absorb).
export type CandleSleeveState = {
	charges: number,
}

-- Everything one run has collected. Run-scoped: built fresh by PlayerState and never persisted.
export type CandleModifierState = {
	lifeWax: number, -- stacks; each shaves a little off the burn drain
	brightWax: number, -- stacks; each adds a little light
	frozen: FrozenWaxState,
	wicks: ExtraWicksState,
	sleeve: CandleSleeveState,
}

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
	| "SeamBlast"
	-- A stick of dynamite (Config/Dynamite). Kept apart from `SeamBlast` even though the two do the
	-- same arithmetic, because the run summary's whole job is answering "what killed this candle?" and
	-- "the cave exploded near me" and "I threw an explosive at my own feet" are different answers.
	| "DynamiteBlast"
	| "EnvironmentalFire"
	| "FrozenWaxGain"
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

-- The LIVE burn profile of one candle. DERIVED, not authored: Logic/CandleModifiers.profile builds
-- it from the run's CandleModifierState every tick, so there is no such thing as a "wax type" a
-- pickup swaps you into — only the candle you started with plus what this run has added to it.
export type CandleProfile = {
	drainMultiplier: number, -- scales the burn component of drain; lower = a longer candle
	brightnessMultiplier: number, -- scales light per unit burn; higher = brighter
	attractsDrawn: boolean, -- whether this flame pulls the Drawn (true for every ordinary candle)
}

return {}

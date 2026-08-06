--!strict
-- Wax economy tuning. Wax is health + light + fuel + timer (DESIGN §3). Draining faster = harder.

local Types = require(script.Parent.Parent.Types)

export type WaxConfig = {
	startingWax: Types.WaxAmount,
	maxWax: Types.WaxAmount,
	initialBurnRate: Types.BurnRate,
	idleDrainPerSecond: number,
	burnDrainPerSecond: number,
	burnDrainExponent: number,
	movementCostMultiplier: number,
}

local Wax: WaxConfig = {
	-- Wax a fresh candle starts with. Capacity is 30% above the original 1.0-unit candle.
	startingWax = 1.3,
	-- Absolute wax ceiling. Rendering normalizes against this value, so capacity does not alter size.
	maxWax = 1.3,
	-- Dial setting a fresh candle spawns with. Purely a starting point; the player moves it immediately.
	initialBurnRate = 0.35,
	-- Every candle starts NEUTRAL: no burn profile to swap into, no starting modifier. What a candle
	-- becomes is what the run adds to it (Config/CandleModifiers, Logic/CandleModifiers).
	-- Wax lost per second just from being lit, before brightness. Higher = harder: shorter runs.
	-- Phase 2 (wax pacing correction): was 0.0005. Measured against the real FloorPlanner/
	-- RoomNavigation room graph, the OLD idle+brightness+movement drain cost ~1.95 wax (150% of the
	-- 1.3-wax candle) just to WALK the shortest path to depth 12 at a modest dial — passive drain was
	-- the deterministic cause of nearly every run ending at the same depth, not threats or mistakes.
	-- See TUNING.md "the wax pacing budget model" for the full derivation.
	-- Burn-rate pass: +15% on top of the Phase 2 value (0.00025) so the candle burns down faster.
	idleDrainPerSecond = 0.0002875,
	-- Wax-drain coefficient at burnRate = 1, on top of idle. The ordinary dial is capped below 1;
	-- repeated Flare activations pay their separate immediate cost.
	-- Phase 2: was 0.0045, cut to roughly the same ~40-46% fraction across the whole 0.18-0.78 dial
	-- range as the idle cut above, so the dial's relative shape (how much brighter costs) is
	-- unchanged; only the absolute unavoidable cost of being lit at all is reduced.
	-- Burn-rate pass: +15% on top of the Phase 2 value (0.0018).
	burnDrainPerSecond = 0.00207,
	-- Curve on burn drain: drain = burnDrainPerSecond * burnRate ^ exponent.
	-- >1 makes bright settings disproportionately expensive. Higher = harder when burning bright.
	burnDrainExponent = 1.5,
	-- Global scalar on ALL movement wax costs from Config/Movement, per-second and per-action
	-- (DESIGN §5 says small). Higher = harder.
	-- Phase 2: was 0.6. Cut so movement keeps roughly the same ~31-33% share of total unavoidable
	-- direct-route cost it had before (movement was never the dominant term; passive burn was), while
	-- the absolute total drops with the passive-burn cut above.
	movementCostMultiplier = 0.25,
}

return Wax

--!strict
-- Wax economy tuning. Wax is health + light + fuel + timer (DESIGN §3). Draining faster = harder.

local Types = require(script.Parent.Parent.Types)

export type WaxConfig = {
	startingWax: Types.WaxAmount,
	maxWax: Types.WaxAmount,
	initialBurnRate: Types.BurnRate,
	startingWaxTypeId: Types.WaxTypeId,
	idleDrainPerSecond: number,
	burnDrainPerSecond: number,
	burnDrainExponent: number,
	movementCostMultiplier: number,
}

local Wax: WaxConfig = {
	-- Wax a fresh candle starts a run with (0..1). Lower = harder: less to spend on everything.
	startingWax = 1.0,
	-- Absolute wax ceiling (0..1). A Basin sacrifice can lower a player's live max below this. Lower = harder.
	maxWax = 1.0,
	-- Dial setting a fresh candle spawns with. Purely a starting point; the player moves it immediately.
	initialBurnRate = 0.4,
	-- Burn profile a fresh candle starts with ("Standard" = neutral multipliers).
	startingWaxTypeId = "Standard",
	-- Wax lost per second just from being lit, before brightness. Higher = harder: shorter runs.
	idleDrainPerSecond = 0.002,
	-- Wax lost per second at full brightness (burnRate = 1), on top of idle. Higher = harder.
	burnDrainPerSecond = 0.02,
	-- Curve on burn drain: drain = burnDrainPerSecond * burnRate ^ exponent.
	-- >1 makes bright settings disproportionately expensive. Higher = harder when burning bright.
	burnDrainExponent = 1.5,
	-- Global scalar on ALL movement wax costs from Config/Movement, per-second and per-action
	-- (DESIGN §5 says small). Higher = harder.
	movementCostMultiplier = 1.0,
}

return Wax

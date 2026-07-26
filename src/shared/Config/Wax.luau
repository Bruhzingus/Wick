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
	-- Wax a fresh candle starts with. Capacity is 30% above the original 1.0-unit candle.
	startingWax = 1.3,
	-- Absolute wax ceiling. Rendering normalizes against this value, so capacity does not alter size.
	maxWax = 1.3,
	-- Dial setting a fresh candle spawns with. Purely a starting point; the player moves it immediately.
	initialBurnRate = 0.35,
	-- Burn profile a fresh candle starts with ("Standard" = neutral multipliers).
	startingWaxTypeId = "Standard",
	-- Wax lost per second just from being lit, before brightness. Higher = harder: shorter runs.
	idleDrainPerSecond = 0.0005,
	-- Wax-drain coefficient at burnRate = 1, on top of idle. The ordinary dial is capped below 1;
	-- repeated Flare activations pay their separate immediate cost.
	burnDrainPerSecond = 0.0045,
	-- Curve on burn drain: drain = burnDrainPerSecond * burnRate ^ exponent.
	-- >1 makes bright settings disproportionately expensive. Higher = harder when burning bright.
	burnDrainExponent = 1.5,
	-- Global scalar on ALL movement wax costs from Config/Movement, per-second and per-action
	-- (DESIGN §5 says small). Higher = harder.
	movementCostMultiplier = 0.6,
}

return Wax

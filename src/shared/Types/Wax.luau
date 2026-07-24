--!strict
-- Wax-domain types. Wax is the ONLY resource: health, light, fuel, and timer at once (DESIGN §3).

-- Wax expressed as a fraction of a full candle, 0..1. Used for costs, amounts, and the live meter.
export type WaxAmount = number

-- Live wax meter for a candle. Server-authoritative (ARCHITECTURE).
export type WaxState = {
	current: WaxAmount, -- the live value, 0..1; hits 0 -> BurnOut
	max: WaxAmount, -- current ceiling, 0..1; a Basin sacrifice can permanently lower this
}

-- The brightness dial, 0..1 (DESIGN §4). Higher = brighter and faster drain. 0 = snuffed.
export type BurnRate = number

-- Wax-type loot ids (DESIGN section 14). Closed union — a small, named pool.
-- "Standard" is the neutral starting profile (all multipliers 1); the other three are in-run loot.
export type WaxTypeId = "Standard" | "Beeswax" | "Tallow" | "ColdWax"

-- Static burn profile for a wax type. Pure data (see Config/WaxTypes).
export type WaxTypeDef = {
	id: WaxTypeId,
	displayName: string,
	drainMultiplier: number, -- scales all drain; higher = hungrier
	brightnessMultiplier: number, -- scales light per unit burn; higher = brighter
	attractsDrawn: boolean, -- cold wax burns without pulling the drawn
}

return {}

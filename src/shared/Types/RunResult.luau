--!strict
-- Outcome types for a completed or failed run (DESIGN §7, §12).

local Player = require(script.Parent.Player)

-- Why a candle died. Two mechanically distinct states (DESIGN §7). Closed union.
export type DeathCause = "BurnOut" | "Snuffed"

-- The result of one player's run, computed server-side when they light a brazier or die.
export type RunResult = {
	playerId: Player.PlayerId,
	survived: boolean, -- true if they lit a brazier; false if they died first
	deathCause: DeathCause?, -- set only when survived == false
	depthReached: number, -- deepest floor entered
	waxDelivered: number, -- wax units poured into the brazier (0 on death)
	reward: number, -- final payout after depth multiplier + group bonus (Config/Brazier)
}

return {}

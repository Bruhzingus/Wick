--!strict
-- Death / revival tuning (DESIGN §7, §13). Two death states: Snuffed (revivable) and BurnOut (not).

local Types = require(script.Parent.Parent.Types)

export type DeathConfig = {
	relightWaxCost: Types.WaxAmount,
	snuffStateDuration: number,
	relightRange: number,
	relightHoldSeconds: number,
	selfRelightDelaySeconds: number,
	remainsWaxFraction: number,
}

local Death: DeathConfig = {
	-- Wax the REVIVER spends to relight a snuffed teammate (DESIGN §7: paid by reviver, must be significant).
	-- Higher = harder.
	relightWaxCost = 0.15,
	-- Seconds a snuffed player can wait before rescue becomes impossible. Shorter = harder.
	snuffStateDuration = 20,
	-- Studs from which a teammate can trigger the relight prompt.
	relightRange = 8,
	-- Seconds the relight prompt must be held. Giving someone your life shouldn't be a mis-tap.
	relightHoldSeconds = 1,
	-- Seconds after a VOLUNTARY snuff before you can relight yourself. Higher = snuffing is a
	-- bigger commitment = harder. (World-snuffed players can never self-relight.)
	selfRelightDelaySeconds = 1.5,
	-- Fraction of remaining wax that pools as recoverable Remains on burnout (DESIGN §13).
	-- Consumed by the Remains interface (stubbed in v1). Higher = softer failure.
	remainsWaxFraction = 0.5,
}

return Death

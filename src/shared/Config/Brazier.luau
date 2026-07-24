--!strict
-- Brazier / reward tuning (DESIGN §12).
-- Reward = waxDelivered * depthMultipliers[depth] * (1 + groupBonusPerPlayer * additionalPlayers) * rewardPerWaxUnit.
-- Expose the numbers: legible tension beats mysterious tension. The preview shows this arithmetic live.

export type BrazierConfig = {
	depthMultipliers: { number },
	groupBonusPerPlayer: number,
	rewardPerWaxUnit: number,
	promptRange: number,
	groupRadius: number,
	commitHoldSeconds: number,
	previewUpdateSeconds: number,
}

local Brazier: BrazierConfig = {
	-- Depth multiplier by floor (index = floor number). DESIGN §12 examples: floor2 ~1.5, floor4 ~3, floor6 ~5.
	-- Steeper curve = stronger pull to push deeper = higher risk/reward.
	depthMultipliers = { 1.0, 1.5, 2.2, 3.0, 4.0, 5.0, 6.5, 8.0 },
	-- Bonus per ADDITIONAL player at the same brazier (DESIGN §12: 0.25). A multiplier, not a split pot —
	-- nobody's share shrinks when someone else arrives. Higher = more reason to wait for the party.
	groupBonusPerPlayer = 0.25,
	-- Scalar from delivered wax (0..1) to payout currency. Higher = more generous economy.
	rewardPerWaxUnit = 1000,
	-- Studs at which the commit prompt and live preview appear.
	promptRange = 10,
	-- Studs within which another alive, unfinished player counts toward the group bonus at commit.
	groupRadius = 12,
	-- Seconds the commit prompt must be held. Guards against accidentally ending your run.
	commitHoldSeconds = 1,
	-- Seconds between preview refreshes for players standing at the brazier.
	previewUpdateSeconds = 0.25,
}

return Brazier

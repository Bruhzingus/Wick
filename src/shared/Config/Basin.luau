--!strict
-- Basin tuning (DESIGN §10). Between-floor sacrifice for wax. v1: a static weighted-random pool,
-- offers PRIVATE to each player. Contextual "only offer what the player uses" targeting is DEFERRED.

local Types = require(script.Parent.Parent.Types)

export type BasinEffectsConfig = {
	maxBurnRateCapMultiplier: number,
	dodgeShortenMultiplier: number,
}

export type BasinConfig = {
	baseWaxGranted: Types.WaxAmount,
	depthPenaltyPerFloor: number,
	offersPerVisit: number,
	effects: BasinEffectsConfig,
	pool: { Types.SacrificeDef },
}

local Basin: BasinConfig = {
	-- Baseline wax granted for a sacrifice before depth scaling (0..1). Lower = harder.
	baseWaxGranted = 0.25,
	-- The exchange rate worsens with depth (DESIGN §10 rule 1): granted wax is multiplied by
	-- depthPenaltyPerFloor ^ (depth - 1). <1 means deeper floors pay LESS for the same loss = harder.
	depthPenaltyPerFloor = 0.85,
	-- Distinct offers shown per visit. Fewer = less choice = harder.
	offersPerVisit = 3,
	-- Magnitudes of sacrifice effects that are reductions rather than removals.
	effects = {
		-- MaxBrightness sacrifice: new dial ceiling = current ceiling x this. Lower = harsher.
		maxBurnRateCapMultiplier = 0.6,
		-- Dodge sacrifice: dodge distance x this. Lower = harsher.
		dodgeShortenMultiplier = 0.5,
	},
	-- Weighted-random pool (DESIGN §10). weight = relative likelihood; waxGranted overrides the base
	-- for that entry (before depth scaling).
	pool = {
		{
			id = "CapMaxBrightness",
			displayName = "Cap your brightness",
			target = "MaxBrightness",
			waxGranted = 0.25,
			weight = 1,
		},
		{ id = "LoseSlide", displayName = "Lose your slide", target = "Slide", waxGranted = 0.25, weight = 1 },
		{ id = "ShortenDodge", displayName = "Shorten your dodge", target = "Dodge", waxGranted = 0.20, weight = 1 },
		{
			id = "LoseDripTrail",
			displayName = "Lose your drip trail",
			target = "DripTrail",
			waxGranted = 0.15,
			weight = 1,
		},
		{ id = "LoseRelight", displayName = "Never relight others", target = "Relight", waxGranted = 0.30, weight = 1 },
		{ id = "LoseBeRelit", displayName = "Never be relit", target = "BeRelit", waxGranted = 0.30, weight = 1 },
		{ id = "LoseTool", displayName = "Lose a tool", target = "Tool", waxGranted = 0.30, weight = 1 },
		{
			id = "DoubleNextPrice",
			displayName = "Double the next price",
			target = "NextBasinPriceDoubled",
			waxGranted = 0.35,
			weight = 1,
		},
	},
}

return Basin

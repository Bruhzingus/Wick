--!strict
-- Basin tuning (DESIGN §10). Between-floor sacrifice for wax. v1: a static weighted-random pool,
-- offers PRIVATE to each player. Contextual "only offer what the player uses" targeting is DEFERRED.

local Types = require(script.Parent.Parent.Types)

export type BasinEffectsConfig = {
	maxBurnRateCapMultiplier: number,
	dialFloorRaiseFraction: number,
	moveSpeedMultiplier: number,
	cupSpeedMultiplier: number,
	maxWaxMultiplier: number,
	waxDrainMultiplier: number,
	toolCooldownMultiplier: number,
	peripheralDarknessOpacity: number,
	sightBrightness: number,
	sightSaturation: number,
}

export type BasinConfig = {
	minimumGrant: number,
	maximumGrant: number,
	offersPerVisit: number,
	promptHoldSeconds: number,
	positionToleranceStuds: number,
	effects: BasinEffectsConfig,
	pool: { Types.SacrificeDef },
}

local Basin: BasinConfig = {
	-- The permanent sacrifice is the scaling cost. Grants never decay with depth and every displayed
	-- result, including a doubled-next-price penalty, stays inside this band.
	minimumGrant = 0.20,
	maximumGrant = 0.35,
	-- Distinct offers shown per visit. Fewer = less choice = harder.
	offersPerVisit = 3,
	-- Commitment time on the "Offer yourself" prompt.
	promptHoldSeconds = 0.5,
	-- Slack added to the room's quarter-cell radius when re-validating a player is still at the
	-- Basin position server-side (matches the trust-boundary margins Config/Security owns).
	positionToleranceStuds = 2,
	-- Magnitudes of sacrifice effects that are reductions rather than removals. Every one of these
	-- compounds if a target is ever offered twice (it is not today: one row per id, taken once).
	effects = {
		-- MaxBrightness sacrifice: new dial ceiling = current ceiling x this. Lower = harsher.
		-- Also what puts burnable vines out of reach, so keep it well under Config/Vines'
		-- requiredBurnRateFraction.
		maxBurnRateCapMultiplier = 0.6,
		-- DialFloor sacrifice: the dial can no longer be closed all the way down. The new floor sits
		-- this far up the min..max span, so you are permanently more visible to the Drawn.
		dialFloorRaiseFraction = 0.45,
		-- MoveSpeed sacrifice: walk and run speed x this. Lower = harsher.
		moveSpeedMultiplier = 0.78,
		-- CupSpeed sacrifice: compounds with Config/Tools.Cup.speedMultiplier, so cupping while
		-- moving becomes close to standing still. Lower = harsher.
		cupSpeedMultiplier = 0.55,
		-- WaxCapacity sacrifice: max wax x this. The candle also stands shorter for the same wax
		-- fraction, so water turns lethal sooner. Lower = harsher.
		maxWaxMultiplier = 0.82,
		-- BurnEfficiency sacrifice: every drain component x this. Higher = harsher.
		waxDrainMultiplier = 1.2,
		-- ToolSpeed sacrifice: every tool cooldown x this. Higher = harsher.
		toolCooldownMultiplier = 1.8,
		-- Mild, client-visible perception costs. These never change authoritative threat perception.
		peripheralDarknessOpacity = 0.22,
		sightBrightness = -0.055,
		sightSaturation = -0.24,
	},
	-- Weighted-random pool (DESIGN §10). weight = relative likelihood; waxGranted is the flat grant
	-- for that entry before an optional next-price penalty. Grants reflect how much the loss actually
	-- costs a run: a permanent, always-on loss (light, capacity, burn rate) pays more than losing a
	-- situational move.
	--
	-- Only three of these are offered per visit, so a deep pool is what keeps a long descent from
	-- becoming the same four decisions every time.
	pool = {
		-- Light. The most expensive things to give up, and the ones that gate content: a capped dial
		-- can no longer burn vines open (Config/Vines), which is why vines are never the only route.
		{
			id = "CapMaxBrightness",
			displayName = "Cap your brightness",
			target = "MaxBrightness",
			waxGranted = 0.30,
			weight = 1,
		},
		{
			id = "RaiseDialFloor",
			displayName = "Never burn low again",
			target = "DialFloor",
			waxGranted = 0.28,
			weight = 1,
		},

		-- Movement.
		{ id = "SlowStep", displayName = "Slow your step", target = "MoveSpeed", waxGranted = 0.30, weight = 1 },
		{
			id = "FumbleTheCup",
			displayName = "Fumble the cup",
			target = "CupSpeed",
			waxGranted = 0.20,
			weight = 1,
		},

		-- Senses and party ties.
		{
			id = "LoseHearing",
			displayName = "Go deaf to the dark",
			target = "Hearing",
			waxGranted = 0.26,
			weight = 1,
		},
		{
			id = "LoseDripTrail",
			displayName = "Lose your drip trail",
			target = "DripTrail",
			waxGranted = 0.20,
			weight = 1,
		},
		{ id = "LoseRelight", displayName = "Never relight others", target = "Relight", waxGranted = 0.30, weight = 1 },
		{ id = "LoseBeRelit", displayName = "Never be relit", target = "BeRelit", waxGranted = 0.30, weight = 1 },

		-- The candle itself.
		{
			id = "ShrinkReserve",
			displayName = "Shrink your reserve",
			target = "WaxCapacity",
			waxGranted = 0.32,
			weight = 1,
		},
		{ id = "BurnHotter", displayName = "Burn hotter", target = "BurnEfficiency", waxGranted = 0.30, weight = 1 },
		{ id = "SlowYourHands", displayName = "Slow your hands", target = "ToolSpeed", waxGranted = 0.24, weight = 1 },
		{ id = "LoseTool", displayName = "Lose a tool", target = "Tool", waxGranted = 0.30, weight = 1 },

		-- Smaller perception costs: permanent and noticeable, but not binary ability removals.
		{
			id = "DarkenPeriphery",
			displayName = "Darken the edges of your sight",
			target = "PeripheralDarkness",
			waxGranted = 0.24,
			weight = 1,
		},
		{
			id = "DimSight",
			displayName = "Dim your sight",
			target = "SightBrightness",
			waxGranted = 0.23,
			weight = 1,
		},
		{
			id = "DrainColor",
			displayName = "Let the cave drain its color",
			target = "SightSaturation",
			waxGranted = 0.22,
			weight = 1,
		},

		-- The gamble.
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

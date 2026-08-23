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
	flareDurationMultiplier: number,
	decoyDurationMultiplier: number,
	relightCostMultiplier: number,
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
	-- WHAT A BOSS FLOOR'S BASIN PAYS, as a multiplier on every offer's `waxGranted`.
	--
	-- A boss floor gives out no wax of any kind on the ground any more — hers carries dynamite and two
	-- decoys, his carries decoys and sticks, and neither carries a seam. The Basin is therefore the
	-- only fuel on the floor, and it is standing in the one room the fight is not in. Paying thirty per
	-- cent over the ordinary rate is what makes walking to it worth the trip out of a fight that has
	-- already cost a candle, rather than a formality on the way to the ladder.
	bossFloorGrantMultiplier: number,
}

local Basin: BasinConfig = {
	-- The permanent sacrifice is the scaling cost. Grants never decay with depth and every displayed
	-- result, including a doubled-next-price penalty, stays inside this band.
	minimumGrant = 0.20,
	maximumGrant = 0.35,
	-- Distinct offers shown per visit. Fewer = less choice = harder.
	offersPerVisit = 4,
	-- Commitment time on the "Offer yourself" prompt.
	promptHoldSeconds = 0.5,
	-- Slack added to the room's quarter-cell radius when re-validating a player is still at the
	-- Basin position server-side (matches the trust-boundary margins Config/Security owns).
	positionToleranceStuds = 2,
	-- Per-stage magnitudes for progressive sacrifices. Staged rows intentionally compound.
	effects = {
		-- MaxBrightness sacrifice: new dial ceiling = current ceiling x this. Lower = harsher.
		-- Doorway keys resolve against this effective ceiling, so lowering it never removes access.
		maxBurnRateCapMultiplier = 0.86,
		-- DialFloor sacrifice: the dial can no longer be closed all the way down. The new floor sits
		-- this far up the min..max span, so you are permanently more visible to the Drawn.
		dialFloorRaiseFraction = 0.12,
		-- MoveSpeed sacrifice: walk and run speed x this. Lower = harsher.
		moveSpeedMultiplier = 0.9,
		-- CupSpeed sacrifice: compounds with Config/Tools.Cup.speedMultiplier, so cupping while
		-- moving becomes close to standing still. Lower = harsher.
		cupSpeedMultiplier = 0.8,
		-- WaxCapacity sacrifice: max wax x this. The candle also stands shorter for the same wax
		-- fraction, so water turns lethal sooner. Lower = harsher.
		maxWaxMultiplier = 0.9,
		-- BurnEfficiency sacrifice: every drain component x this. Higher = harsher.
		waxDrainMultiplier = 1.1,
		-- ToolSpeed sacrifice: every tool cooldown x this. Higher = harsher.
		toolCooldownMultiplier = 1.25,
		-- Tool-specific degradations preserve each tool while changing how it must be used.
		flareDurationMultiplier = 0.82,
		decoyDurationMultiplier = 0.82,
		relightCostMultiplier = 1.3,
		-- Mild, client-visible perception costs. These never change authoritative threat perception.
		peripheralDarknessOpacity = 0.08,
		sightBrightness = -0.025,
		sightSaturation = -0.1,
	},
	-- Weighted-random pool (DESIGN §10). weight = relative likelihood; waxGranted is the flat grant
	-- for that entry before an optional next-price penalty. Grants reflect how much the loss actually
	-- costs a run: a permanent, always-on loss (light, capacity, burn rate) pays more than losing a
	-- situational move.
	--
	-- Only four of these are offered per visit, so a deep pool is what keeps a long descent from
	-- becoming the same four decisions every time.
	bossFloorGrantMultiplier = 1.3,
	pool = {
		-- Progressive losses. Later stages do not enter the roll until the prior stage was taken.
		{
			id = "DimFlame1",
			displayName = "Dim the flame I",
			description = "Your maximum dial setting becomes 14% lower for the rest of this run.",
			target = "MaxBrightness",
			waxGranted = 0.26,
			weight = 1,
		},
		{
			id = "DimFlame2",
			displayName = "Dim the flame II",
			description = "Your remaining maximum brightness is reduced by another 14%.",
			target = "MaxBrightness",
			waxGranted = 0.29,
			weight = 1,
			requiresSacrificeId = "DimFlame1",
		},
		{
			id = "DimFlame3",
			displayName = "Dim the flame III",
			description = "Your remaining maximum brightness is reduced by another 14%; full-brightness barriers may require a Flare or detour.",
			target = "MaxBrightness",
			waxGranted = 0.33,
			weight = 1,
			requiresSacrificeId = "DimFlame2",
		},
		{
			id = "RestlessFlame1",
			displayName = "Restless flame I",
			description = "The bottom of your brightness dial rises by 12% of its full range. You cannot burn as dimly.",
			target = "DialFloor",
			waxGranted = 0.23,
			weight = 1,
		},
		{
			id = "RestlessFlame2",
			displayName = "Restless flame II",
			description = "The bottom of your dial rises by another 12%, making hiding from the Drawn harder.",
			target = "DialFloor",
			waxGranted = 0.27,
			weight = 1,
			requiresSacrificeId = "RestlessFlame1",
		},
		{
			id = "HeavyStep1",
			displayName = "Heavy step I",
			description = "Walking and running are 10% slower for the rest of this run.",
			target = "MoveSpeed",
			waxGranted = 0.24,
			weight = 1,
		},
		{
			id = "HeavyStep2",
			displayName = "Heavy step II",
			description = "Walking and running lose another 10% of their remaining speed.",
			target = "MoveSpeed",
			waxGranted = 0.28,
			weight = 1,
			requiresSacrificeId = "HeavyStep1",
		},
		{
			id = "HeavyStep3",
			displayName = "Heavy step III",
			description = "Walking and running lose another 10% of their remaining speed.",
			target = "MoveSpeed",
			waxGranted = 0.32,
			weight = 1,
			requiresSacrificeId = "HeavyStep2",
		},
		{
			id = "SmallReserve1",
			displayName = "Small reserve I",
			description = "Maximum wax is reduced by 10%. Current wax is clamped to the new maximum before this grant.",
			target = "WaxCapacity",
			waxGranted = 0.27,
			weight = 1,
		},
		{
			id = "SmallReserve2",
			displayName = "Small reserve II",
			description = "Maximum wax is reduced by another 10%, making deep water lethal sooner.",
			target = "WaxCapacity",
			waxGranted = 0.31,
			weight = 1,
			requiresSacrificeId = "SmallReserve1",
		},
		{
			id = "HungryFlame1",
			displayName = "Hungry flame I",
			description = "Every source of wax drain costs 10% more for the rest of this run.",
			target = "BurnEfficiency",
			waxGranted = 0.27,
			weight = 1,
		},
		{
			id = "HungryFlame2",
			displayName = "Hungry flame II",
			description = "Every source of wax drain costs another 10% more.",
			target = "BurnEfficiency",
			waxGranted = 0.31,
			weight = 1,
			requiresSacrificeId = "HungryFlame1",
		},
		{
			id = "ClumsyHands1",
			displayName = "Clumsy hands I",
			description = "All tool cooldowns become 25% longer.",
			target = "ToolSpeed",
			waxGranted = 0.23,
			weight = 1,
		},
		{
			id = "ClumsyHands2",
			displayName = "Clumsy hands II",
			description = "All tool cooldowns become another 25% longer.",
			target = "ToolSpeed",
			waxGranted = 0.27,
			weight = 1,
			requiresSacrificeId = "ClumsyHands1",
		},
		{
			id = "BriefFlare1",
			displayName = "Brief Flare I",
			description = "Each Flare's blinding light and protection last 18% less time.",
			target = "FlareDuration",
			waxGranted = 0.23,
			weight = 1,
		},
		{
			id = "BriefFlare2",
			displayName = "Brief Flare II",
			description = "Each Flare lasts another 18% less time than it does now.",
			target = "FlareDuration",
			waxGranted = 0.27,
			weight = 1,
			requiresSacrificeId = "BriefFlare1",
		},
		{
			id = "FrailDecoy1",
			displayName = "Frail Decoy I",
			description = "Every Decoy burns out 18% sooner.",
			target = "DecoyDuration",
			waxGranted = 0.22,
			weight = 1,
		},
		{
			id = "FrailDecoy2",
			displayName = "Frail Decoy II",
			description = "Every Decoy burns out another 18% sooner than it does now.",
			target = "DecoyDuration",
			waxGranted = 0.26,
			weight = 1,
			requiresSacrificeId = "FrailDecoy1",
		},
		{
			id = "CostlyMercy1",
			displayName = "Costly mercy I",
			description = "Relighting a teammate costs you 30% more wax.",
			target = "RelightCost",
			waxGranted = 0.22,
			weight = 1,
		},
		{
			id = "CostlyMercy2",
			displayName = "Costly mercy II",
			description = "Relighting a teammate costs another 30% more wax than it does now.",
			target = "RelightCost",
			waxGranted = 0.26,
			weight = 1,
			requiresSacrificeId = "CostlyMercy1",
		},
		{
			id = "DarkEdges1",
			displayName = "Dark edges I",
			description = "A permanent dark ring covers 8% more of your peripheral view.",
			target = "PeripheralDarkness",
			waxGranted = 0.21,
			weight = 1,
		},
		{
			id = "DarkEdges2",
			displayName = "Dark edges II",
			description = "The permanent darkness at the edge of your view thickens by another 8%.",
			target = "PeripheralDarkness",
			waxGranted = 0.24,
			weight = 1,
			requiresSacrificeId = "DarkEdges1",
		},
		{
			id = "DimSight1",
			displayName = "Dim sight I",
			description = "Your entire view becomes permanently 2.5% darker. This does not change what threats perceive.",
			target = "SightBrightness",
			waxGranted = 0.21,
			weight = 1,
		},
		{
			id = "DimSight2",
			displayName = "Dim sight II",
			description = "Your entire view becomes another 2.5% darker.",
			target = "SightBrightness",
			waxGranted = 0.24,
			weight = 1,
			requiresSacrificeId = "DimSight1",
		},
		{
			id = "PaleSight1",
			displayName = "Pale sight I",
			description = "Your view permanently loses 10% of its color. Gameplay lighting is unchanged.",
			target = "SightSaturation",
			waxGranted = 0.20,
			weight = 1,
		},
		{
			id = "PaleSight2",
			displayName = "Pale sight II",
			description = "Your view loses another 10% of its color.",
			target = "SightSaturation",
			waxGranted = 0.23,
			weight = 1,
			requiresSacrificeId = "PaleSight1",
		},
		{
			id = "DoubleNextPrice",
			displayName = "Burden the next Basin",
			description = "This grant is normal, but the next Basin grant is halved (never below +0.20 wax).",
			target = "NextBasinPriceDoubled",
			waxGranted = 0.35,
			weight = 0.35,
		},
	},
}

return Basin

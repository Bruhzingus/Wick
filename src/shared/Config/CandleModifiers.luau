--!strict
-- ROGUELIKE CANDLE MODIFIERS (DESIGN section 14). The in-run item pool, and the one place its
-- numbers live. Logic/CandleModifiers owns every rule that reads them.
--
-- THE DESIGN RULE THAT SHAPES EVERY NUMBER BELOW: a modifier ADDS to the candle you already have.
-- It never swaps you into a different burn profile, and no single pickup is worth more than 5% of
-- anything. That ceiling is deliberate — an item that changes a run by a fifth turns the run into
-- a search for that item, whereas twenty items worth 3% each turn it into a run you shaped. The
-- interesting decision is which stacks to chase and how far, not which cache to pray for.
--
-- WHY DIMINISHING RETURNS AND NOT HARD STACK CAPS. A hard cap makes the twelfth LifeWax worthless
-- and the eleventh mandatory, which is a cliff a player has to memorize. A soft knee keeps every
-- extra stack worth picking up while making the first ones matter most, so "do I detour for this"
-- stays a live question at every point in the run instead of flipping to "no" forever.

local Types = require(script.Parent.Parent.Types)

export type StackingBonusConfig = {
	perStack: number, -- nominal contribution of one stack
	diminishingAbove: number, -- nominal total past which contributions are scaled down
	diminishedFactor: number, -- how much of `perStack` still lands above the knee
	maximum: number, -- absolute ceiling; reached only by an extreme stack count
}

export type FrozenWaxConfig = {
	reservePerPickup: number, -- fraction of MAX wax banked by one pickup; deliberately uncapped
	meltSeconds: number, -- seconds at maximum brightness between melts
	meltFraction: number, -- fraction of MAX wax returned by one melt
	maxBurnRateFraction: number, -- fraction of the effective dial ceiling that counts as "at max"
}

export type ExtraWicksConfig = {
	minimumWicks: number,
	maximumWicks: number,
	brightnessBonus: number, -- light added while the bundle is lit; costs no extra wax
	secondsByWickCount: { number }, -- nominal life, indexed by rolled wick count
	stretchAtMinBurn: number, -- >1: a dim flame makes a bundle last longer
	stretchAtMaxBurn: number, -- <1: a hard-pushed flame eats it faster
}

export type CandleSleeveConfig = {
	damageReduction: number, -- fraction of an incoming hit the sleeve eats
	charges: number, -- reference-cadence hits a fresh sleeve survives
	referenceHitSeconds: number, -- the attack cadence one whole charge is defined against
	minimumChargeCost: number, -- floor on a single discrete hit, however fast the attacker swings
	protects: { [Types.WaxSource]: boolean },
}

export type CandleModifiersConfig = {
	lifeWax: StackingBonusConfig,
	brightWax: StackingBonusConfig,
	frozenWax: FrozenWaxConfig,
	extraWicks: ExtraWicksConfig,
	sleeve: CandleSleeveConfig,
}

local CandleModifiers: CandleModifiersConfig = {
	-- LIFE WAX — the survivability stack. 3% off the burn component per pickup, which at the shipped
	-- pacing is worth roughly one extra room per stack rather than one extra floor: small enough that
	-- nobody plans a run around one, large enough that six of them are visibly a different candle.
	lifeWax = {
		perStack = 0.03,
		-- Half your burn rate is already an enormous swing. Past it each stack lands at about a third
		-- of face value, so 17 pickups buy 50% and it takes 31 to approach the ceiling.
		diminishingAbove = 0.50,
		diminishedFactor = 0.35,
		maximum = 0.65,
	},
	-- BRIGHT WAX — the greed stack. The full 5% ceiling, because light is the thing you are actually
	-- trading against: every point of it is also seen by the Drawn (Logic/BrightnessMap scales
	-- perceived intensity by exactly the same number it scales the visible flame by).
	brightWax = {
		perStack = 0.05,
		-- The knee is tighter than LifeWax's on purpose. Brightness is two-sided, so a stack that ran
		-- away with itself would make a build that both sees everything and is seen by everything.
		diminishingAbove = 0.30,
		diminishedFactor = 0.30,
		maximum = 0.45,
	},
	-- FROZEN WAX — wax you can only spend by burning bright. It is not a heal; it is a reason to
	-- commit to the dial you were already scared of.
	frozenWax = {
		-- One block is 5% of a full candle: twenty melts at ten seconds each, so a little over three
		-- minutes of maximum brightness pays the whole thing back.
		--
		-- THERE IS NO CEILING ON THE RESERVE, and that is the point. The stacking pair are capped
		-- because they are permanent — an uncapped LifeWax would eventually make a candle that does not
		-- burn. Frozen Wax is the opposite kind of item: every unit of it is spent the moment it is
		-- earned, and it can only be earned by holding the dial at maximum, which is the most dangerous
		-- and most expensive thing a player can do. A cap here would only ever punish someone for
		-- finding a third block, and the rate limit — 0.25% per ten seconds AT MAXIMUM, and nowhere
		-- else — already decides what a reserve is worth. Carrying more just means burning bright for
		-- longer to get it back.
		reservePerPickup = 0.05,
		meltSeconds = 10,
		meltFraction = 0.0025,
		-- "At max" is generous by a rounding error so a dial resting on its own ceiling always counts,
		-- and so a MaxBrightness sacrifice does not quietly make the item unusable.
		maxBurnRateFraction = 0.98,
	},
	-- EXTRA WICKS — the only light in the game that is free. Its cost is that it ends.
	extraWicks = {
		minimumWicks = 1,
		maximumWicks = 3,
		brightnessBonus = 0.25,
		-- Nominal life per rolled wick count, before the flame-profile stretch below. The two together
		-- span roughly 3 to 5 minutes: 195 * 0.93 = 181 s at the worst, 290 * 1.03 = 299 s at the best.
		secondsByWickCount = { 195, 245, 290 },
		stretchAtMinBurn = 1.03,
		stretchAtMaxBurn = 0.93,
	},
	-- CANDLE SLEEVE — the only defensive item in the game, and deliberately a consumable one. It is
	-- cardboard: it buys a mistake back, it does not make you safe.
	sleeve = {
		damageReduction = 0.40,
		charges = 5,
		-- A charge is defined against a roughly-once-per-second attacker. Everything faster spends a
		-- FRACTION of a charge per swing (Logic/CandleModifiers.absorb), so a swarm that hits four
		-- times a second cannot shred a sleeve in a second and a quarter — it still gets about five
		-- reference-seconds of protection, which is what "five hits" is actually promising.
		referenceHitSeconds = 1.2,
		-- ...but not free either. However fast a discrete attacker swings, each swing costs at least
		-- this much, so no attack cadence turns the sleeve into permanent armour.
		minimumChargeCost = 0.2,
		-- Enemies and environmental impacts. Water is NOT here: the water rule is absolute (a surface
		-- above your flame height kills, it does not damage), and a cardboard tube would be the first
		-- thing that rule destroyed anyway.
		protects = {
			DamageThreat = true,
			DamageDripstone = true,
			EnvironmentalFire = true,
			-- An explosive seam going up (Config/Mining.explosive) is an environmental impact like a
			-- falling crown: a discrete hit, from the world, that a tube of cardboard can plausibly take
			-- some of. Its absence here would have been the only inconsistency in the set.
			SeamBlast = true,
			-- And a stick of dynamite (Config/Dynamite), for exactly the same reason: a discrete
			-- impact a tube of cardboard can plausibly take some of. That it was the player's OWN
			-- explosive changes nothing — the sleeve does not ask whose mistake it was.
			DynamiteBlast = true,
		},
	},
}

return CandleModifiers

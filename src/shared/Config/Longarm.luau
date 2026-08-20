--!strict
-- Longarm tuning, ported from shared/Enemies/Longarm.luau. Tier 3 stalker: one set
-- of limbs until it strikes. Flare is the only thing that scares it — `flareThreshold` (0.78) sits
-- above anything ambient candle brightness reaches, so feeding it continuous
-- `setIllumination(brightness)` as the pack module already expects is correct as-is; this is not
-- the same deviation WaxGrub needed (see Config/WaxGrub.luau header) because ordinary light never
-- crosses this threshold in practice, only a flare does.
--
-- `grazeDamage` AND `grabDamage` ARE WAX-DRAIN AMOUNTS, routed through WaxService.drainExternal
-- like every other threat's contact — see Config/StoneGnawer.luau header for why.
--
-- BOTH ARE FRACTIONS OF `Config.Wax.maxWax` (1.3), NOT THE PACK'S ORIGINAL RAW UNITS. The vendored
-- pack shipped `grazeDamage = 18, grabDamage = 34` — numbers from whatever scale it was authored
-- against, not this game's. Every other threat and hazard here deals damage as a small fraction of
-- the 1.3 pool (Config/Threats' contact hits run 0.012-0.07; even Hazards' rarest, most-telegraphed
-- falling spire only takes `waxLossFraction = 0.55`), so the untouched pack values were 14x-26x the
-- entire candle — an unconditional, unavoidable burnout on ANY graze or grab regardless of current
-- wax, sleeve absorption included (0.40 reduction leaves grabDamage at ~20, still ~15x max). That
-- directly contradicted the design intent stated below: a graze that "costs wax without taking the
-- run" cannot end the run outright, and the grab's ignoreSeconds window only means anything if a
-- single grab is normally survivable.
--
-- THE 6-SECOND IGNORE WINDOW AFTER A GRAB IS NOT OPTIONAL. In a game with no player attack, a grab
-- that can immediately re-grab is unrecoverable. Do not shorten `ignoreSeconds`.

local Types = require(script.Parent.Parent.Types)

export type LongarmConfig = {
	health: number,
	speed: number,
	fleeSpeed: number,
	reachMax: number,
	reachGrab: number,
	grazeDamage: number,
	grabDamage: number,
	ignoreSeconds: number,
	holdSeconds: number,
	flareThreshold: number,
	fleeSeconds: number,
	revealSeconds: number,
	extendSeconds: number,
	decoyInterest: number,
	-- One point-blank stick removes it. It is the tallest thing on the roster but not the toughest —
	-- what makes a Longarm dangerous is that you never heard it coming, and a player who did hear it
	-- coming and spent their rarest consumable on it has earned the kill outright.
	blast: Types.BlastProfile,
}

local Longarm: LongarmConfig = {
	health = 80,
	speed = 4.5,
	fleeSpeed = 9,
	-- MEASURED OFF THE BUILT ARM, not chosen — see the same two rows in shared/Enemies/Longarm for the
	-- measurements. Flat (XZ) from the pelvis to the fingertip: 9.01 with the elbow straight, and 6.99
	-- with it at ninety degrees, which is the furthest the hand can still CLOSE rather than just touch.
	--
	-- THE TWO BANDS ARE TWO DIFFERENT ATTACKS. Outside `reachGrab` it slashes: a wide horizontal whip
	-- that costs `grazeDamage` and teaches the reach. Inside it, it thrusts and grabs. Both animations
	-- live in the pack module; the band boundary is here because it is a tuning decision.
	-- 11.5 is the SLASH band and 6.0 is the GRAB band; see the same two rows in shared/Enemies/Longarm
	-- for how each was arrived at. The slash reaches 2.5 studs past the fingertip on purpose and the
	-- creature is only allowed to use it under the near-miss rule in LongarmBehavior.
	reachMax = 11.5,
	reachGrab = 6.0,
	-- ~17% of max: a real cost, not a wipe. Calibrated against Hazards.luau's 0.2-0.55 fraction range.
	grazeDamage = 0.22,
	-- ~42% of max: the scariest single hit on the roster short of the Gnawer's charge, but survivable
	-- from anything above half a candle — which is what makes the post-grab ignore window meaningful.
	grabDamage = 0.55,
	ignoreSeconds = 6.0,
	holdSeconds = 1.4,
	flareThreshold = 0.78,
	fleeSeconds = 5.0,
	revealSeconds = 0.55,
	extendSeconds = 0.45,
	decoyInterest = 26,
	blast = { hitPoints = 1, staggerSeconds = 6 },
}

return Longarm

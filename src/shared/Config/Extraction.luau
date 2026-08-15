--!strict
-- PHASE 8 — THE FINAL EXTRACTION ECONOMY. Raw Wax stops being an experiment's test score and becomes
-- the one persistent currency in the game. Every number that decides what a run is worth lives here.
--
-- THE ONE-SENTENCE MODEL: you mine Raw Wax out of seams by the GRAM, each gram remembers the depth it
-- came from, and it is worth nothing at all until you walk it out through a brazier.
--
-- WHAT CHANGED FROM PHASE 7A, and why each change is here rather than spread across services:
--
--   * LIVING WAX NO LONGER PAYS. The old brazier formula credited currency for the wax still in your
--     candle when you cashed out, which meant the optimal play was to burn as little as possible and
--     never stop to mine. Wax is now purely what keeps you alive; Raw Wax is the only thing that
--     makes you money. One resource for survival, one for reward, and they are in direct tension:
--     every second you spend mining is wax you are burning to do it.
--   * ORIGIN DEPTH IS THE PRICE. A gram is priced by the floor it came OUT of, not by where you were
--     standing when you cashed it in. Carrying shallow wax deep adds nothing, so "farm the safe
--     floors then run down" earns exactly what running down alone would have.
--   * CAVES CHARGE ADMISSION. The Shallows is free forever. The deeper caves take a fee from every
--     party member at the moment of descent, which is lost with the run if it goes badly.
--
-- THE GRAM PASS replaced the old "unit" with a GRAM, and the reason is entirely about what mining now
-- pays for. Yield used to arrive as a lump sum when a seam broke, so one seam was a whole number of
-- units and nothing finer than a seam ever had to be expressed. Payment is now per SWING
-- (Config/Mining.rows.gramsPerStrike), and a swing is worth a fraction of a seam — which in the old
-- vocabulary would have been "0.67 units", i.e. exactly the fractional currency this file exists to
-- forbid. Choosing a smaller unit rather than a fractional one keeps every amount in the economy a
-- whole number for the same reason it always was. One old unit is 100g, so nothing about the SHAPE of
-- the economy is implied by the rename; what actually changed is stated in the two tuning notes below.
--
-- EVERY NUMBER IN THIS FILE IS AN INTEGER, and that is deliberate rather than incidental. Payouts are
-- currency, currency is persisted, and a persisted float is an argument waiting to happen about
-- whether 349.99999 is 350. Depth multipliers are expressed as PERMILLE of one currency per gram, and
-- the two scaling factors (cave payout, party bonus) are PERMILLE integers applied as
-- `floor(value * permille / 1000)`. No payout anywhere in the system is ever computed in floating
-- point, so no payout can ever disagree with itself. Logic/ExtractionValue sums the exact integer
-- products `grams x permille` across the whole bag and divides ONCE, so per-gram pricing did not buy
-- the economy a second rounding step.

export type ExtractionConfig = {
	maxCargoGrams: number,
	valuePerGramPermilleByDepth: { number },
	extensionGrowthPermille: number,
	maxValuePerGramPermille: number,
	maxSinglePayout: number,
	partyBonusPermille: number,
	partyBonusMinimumMembers: number,
	deathDropPermille: number,
	disconnectGraceSeconds: number,
	currencyName: string,
	gramsPerKilogram: number,
}

local Extraction: ExtractionConfig = {
	-- Hard ceiling on one player's carried grams. A floor carries at most four seams and the richest
	-- row pays 450g, so even a thirty-floor expedition physically produces well under 50kg — this sits
	-- far above that on purpose, so reaching it is a bug signal (a grant that fired twice) rather than
	-- a balance lever anyone tunes.
	maxCargoGrams = 100000,

	-- THE VALUE CURVE. Index = the global depth a gram was mined at; value = THOUSANDTHS of one
	-- currency per gram. 90 means "a floor-1 gram is worth 0.09", which is the same 9 currency per
	-- 100g the old table expressed as whole currency per unit.
	--
	-- Permille rather than whole currency because a gram is a hundredth of the old unit: authored as
	-- integers-per-gram the whole shallow half of the curve would collapse onto the same value. The
	-- integer guarantee is unaffected — see the header: the products are summed exactly and divided
	-- once, so this is a finer scale rather than a floating-point one.
	--
	-- The shape is gentle through the first few floors and then compounds at roughly 25% per floor,
	-- accelerating past floor 8. A floor-1 gram is worth 0.09; a floor-8 gram 0.36; a floor-15 gram
	-- 1.80. That gap is what makes the descent the whole game — no amount of safe shallow mining adds
	-- up to one good deep seam.
	--
	-- TWO REDUCTIONS ARE BAKED INTO THESE NUMBERS, and they are separate decisions:
	--
	--   1. THE GENERAL RATE IS DOWN 10%. Neutral conversion of the old per-unit table would have been
	--      `oldValue x 10` (10/unit -> 100 permille/gram). Every entry here is 0.9 of that, so the whole
	--      curve pays a tenth less at every depth than the pre-gram economy did at the same depth.
	--   2. DEPTH COMPOUNDS MORE SLOWLY. The old depth multipliers were 1.0 / 1.1 / 1.4 / 1.8 / 2.3 /
	--      2.8 / 3.5 / 4.3 / 5.4 / 6.8 / 8.7 / 11.2 / 14.6 / 19.2 / 25.4. They are now 1.0 / 1.1 / 1.4 /
	--      1.75 / 2.2 / 2.65 / 3.3 / 4.0 / 4.95 / 6.15 / 7.7 / 9.7 / 12.3 / 15.6 / 20.0 — untouched
	--      through floor 3, a couple of percent off in the middle, and 21% off at floor 15. The descent
	--      is still overwhelmingly where the money is; it is simply no longer worth quite so much more
	--      than the floor above it, which is the point of the change.
	--
	-- Note that the seam itself also yields less mass than the old lump sum did (150g against the old
	-- 2 units = 200g equivalent), so the per-seam income drop is larger than this table alone implies.
	-- Config/Mining owns that half; TUNING.md carries the combined arithmetic.
	valuePerGramPermilleByDepth = {
		90, -- 1   1.0x   the free cave's opening floor
		99, -- 2   1.1x
		126, -- 3   1.4x
		158, -- 4   1.75x
		198, -- 5   2.2x   an average player's realistic turnaround point
		239, -- 6   2.65x
		297, -- 7   3.3x
		360, -- 8   4.0x   where a paid cave starts genuinely profiting
		446, -- 9   4.95x  the ramp steepens from here
		554, -- 10  6.15x
		693, -- 11  7.7x
		873, -- 12  9.7x
		1107, -- 13  12.3x
		1404, -- 14  15.6x
		1800, -- 15  20.0x
	},
	-- Past the authored table the curve keeps compounding at this rate, computed as integer
	-- multiply-then-divide so the extension is exactly as float-free as the table above it. Cut from
	-- 1330 in the same pass that flattened the authored tail: an uncapped expedition should still be
	-- worth pushing, just not at a third more per floor forever.
	extensionGrowthPermille = 1280,
	-- Absolute ceiling on what one gram can ever be worth, reached around floor 29. Depth itself has
	-- no cap in this game (floors are built on demand, forever), so the VALUE curve must have one or
	-- a sufficiently patient player produces an unbounded number. Cut from the old 5000-per-unit
	-- equivalent (50000) by the same 10% as the authored table.
	maxValuePerGramPermille = 45000,
	-- Belt-and-braces ceiling on a single extraction payout, after depth, cave and party scaling.
	-- Nothing legitimate approaches it; it exists so that no combination of multipliers can ever
	-- return a number that a profile write has to think about.
	maxSinglePayout = 1000000,

	-- THE PARTY BONUS: everybody who went down comes back up. Paid retroactively to every member once
	-- the last of them is out, as a separate credit from the base extraction (see ExtractionService) —
	-- which is why it can be a clean 1.5x rather than something the results card has to predict.
	--
	-- A DEATH cancels it for the entire party, including members who already cashed out. A DISCONNECT
	-- does not: connections drop for reasons that are not decisions, and punishing the survivors for
	-- someone else's router is not tension, it is noise. The obvious objection — "then people will
	-- pull the cable instead of dying" — does not survive contact with the rules, because a
	-- disconnect still destroys that player's own cargo and their own fee.
	-- A resolved survivor who deliberately returns to the main lobby before the party finishes gives
	-- up only their own pending bonus. Their base payout stays banked and the remaining party keeps
	-- its eligibility.
	partyBonusPermille = 1500,
	-- Solo runs never earn it. A party of one that "all got out" is just a player who survived, and
	-- paying a teamwork bonus for it would make the bonus meaningless everywhere else.
	partyBonusMinimumMembers = 2,

	-- TERMINAL DEATH: half of what you were carrying lands on your candle remains for your party to
	-- salvage, and half shatters and is gone from the world entirely.
	--
	-- Why not all of it: if a death loses the party nothing, then dying is a fast-travel option and
	-- the run has no teeth. Why not none of it: cargo that vanishes with its owner makes a body
	-- worthless to walk toward, and the most interesting thirty seconds in this game is deciding
	-- whether to go and get what your friend was carrying.
	deathDropPermille = 500,

	-- DISCONNECT: your bag drops where you stood, visible immediately, but LOCKED TO YOU for this
	-- long. Come back inside the window and it is yours, untouched. Let it lapse and it unlocks for
	-- whoever is still down there.
	--
	-- This shape is load-bearing for anti-duplication: at no instant does the cargo exist in two
	-- places. It is either in the locked pile or in someone's bag, and the transition between those
	-- states is a single claim. Nothing is ever taken back from a player who already picked it up,
	-- because "return it to the owner" and "credit it to the finder" cannot both be true.
	disconnectGraceSeconds = 120,

	-- What the player sees this called. One currency, one name, everywhere.
	currencyName = "Raw Wax",
	-- Where a carried mass stops being read in grams and starts being read in kilograms
	-- (Logic/CargoRules.formatGrams). Presentation only: no rule, payout or stored amount is ever
	-- expressed in anything but whole grams, so this cannot round anybody's cargo.
	gramsPerKilogram = 1000,
}

return Extraction

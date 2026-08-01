--!strict
-- PHASE 8 — THE FINAL EXTRACTION ECONOMY. Raw Wax stops being an experiment's test score and becomes
-- the one persistent currency in the game. Every number that decides what a run is worth lives here.
--
-- THE ONE-SENTENCE MODEL: you mine Raw Wax out of seams, each unit remembers the depth it came from,
-- and it is worth nothing at all until you walk it out through a brazier.
--
-- WHAT CHANGED FROM PHASE 7A, and why each change is here rather than spread across services:
--
--   * LIVING WAX NO LONGER PAYS. The old brazier formula credited currency for the wax still in your
--     candle when you cashed out, which meant the optimal play was to burn as little as possible and
--     never stop to mine. Wax is now purely what keeps you alive; Raw Wax is the only thing that
--     makes you money. One resource for survival, one for reward, and they are in direct tension:
--     every second you spend mining is wax you are burning to do it.
--   * ORIGIN DEPTH IS THE PRICE. A unit is priced by the floor it came OUT of, not by where you were
--     standing when you cashed it in. Carrying shallow wax deep adds nothing, so "farm the safe
--     floors then run down" earns exactly what running down alone would have.
--   * CAVES CHARGE ADMISSION. The Shallows is free forever. The deeper caves take a fee from every
--     party member at the moment of descent, which is lost with the run if it goes badly.
--
-- EVERY NUMBER IN THIS FILE IS AN INTEGER, and that is deliberate rather than incidental. Payouts are
-- currency, currency is persisted, and a persisted float is an argument waiting to happen about
-- whether 349.99999 is 350. Depth multipliers are expressed as whole currency-per-unit values, and
-- the two scaling factors (cave payout, party bonus) are PERMILLE integers applied as
-- `floor(value * permille / 1000)`. No payout anywhere in the system is ever computed in floating
-- point, so no payout can ever disagree with itself.

export type ExtractionConfig = {
	unitsPerDeposit: number,
	maxCargoUnits: number,
	valuePerUnitByDepth: { number },
	extensionGrowthPermille: number,
	maxValuePerUnit: number,
	maxSinglePayout: number,
	partyBonusPermille: number,
	partyBonusMinimumMembers: number,
	deathDropPermille: number,
	disconnectGraceSeconds: number,
	currencyName: string,
}

local Extraction: ExtractionConfig = {
	-- What one broken seam yields. A flat integer count at every depth: depth changes what a unit is
	-- WORTH, never how many one seam gives you. Keeping the per-seam yield flat is what stops a deep
	-- floor from also being the floor where a single seam takes six extra swings.
	--
	-- CUT FROM 3 TO 2 WHEN FLOORS GAINED MULTIPLE SEAMS (Config/Mining.placement.depositCounts). Depth
	-- now changes how many seams a floor carries — 0.65 expected on floors 1-3 rising to 3.15 past
	-- floor 10 — so leaving this at 3 would have roughly tripled deep income on top of a value curve
	-- that already compounds. At 2 the two documented anchors both survive: a 5-floor Shallows run
	-- pays ~149 against the ~152 TUNING measured, and a 5-floor Deep run nets ~-327 against the
	-- documented -316. Shallow floors now yield FEWER units than before and deep floors more, so the
	-- deposit curve reinforces the descent instead of sitting flat against it. LAMP-NETWORK.md §6.
	-- The later deep-density pass leaves this per-seam payout unchanged: 2.35 expected seams on
	-- floors 7-9 and 3.15 on floors 10+, while floors 1-6 retain their existing economy.
	unitsPerDeposit = 2,
	-- Hard ceiling on one player's carried units. A floor carries at most four seams, so even a
	-- thirty-floor expedition physically produces well under two hundred units — this sits far above
	-- that on purpose, so reaching it is a bug signal (a grant that fired twice) rather than a balance
	-- lever anyone tunes.
	-- The deep-density pass can now roll four seams, which remains far below this guard.
	maxCargoUnits = 999,

	-- THE VALUE CURVE. Index = the global depth a unit was mined at; value = whole currency per unit.
	--
	-- Floor 1 is 10 rather than 1 so the authored shape (1x, 1.1x, 1.4x, 1.8x, 2.3x, 2.8x, 3.5x,
	-- 4.3x ...) lands on exact integers at every step. That is the entire reason for the base of ten:
	-- it buys the whole curve in integer arithmetic without a single rounding decision.
	--
	-- The shape is gentle through the first few floors and then compounds at roughly 25-30% per floor,
	-- accelerating past floor 8. A floor-1 unit is worth 10; a floor-8 unit is worth 43; a floor-15
	-- unit is worth 254. That gap is what makes the descent the whole game — no amount of safe
	-- shallow mining adds up to one good deep seam.
	valuePerUnitByDepth = {
		10, -- 1   1.0x   the free cave's opening floor
		11, -- 2   1.1x
		14, -- 3   1.4x
		18, -- 4   1.8x
		23, -- 5   2.3x   an average player's realistic turnaround point
		28, -- 6   2.8x
		35, -- 7   3.5x
		43, -- 8   4.3x   where a paid cave starts genuinely profiting
		54, -- 9   5.4x   the ramp steepens from here
		68, -- 10  6.8x
		87, -- 11  8.7x
		112, -- 12  11.2x
		146, -- 13  14.6x
		192, -- 14  19.2x
		254, -- 15  25.4x
	},
	-- Past the authored table the curve keeps compounding at this rate (1.33x per floor), computed as
	-- integer multiply-then-divide so the extension is exactly as float-free as the table above it.
	extensionGrowthPermille = 1330,
	-- Absolute ceiling on what one unit can ever be worth, reached around floor 26. Depth itself has
	-- no cap in this game (floors are built on demand, forever), so the VALUE curve must have one or
	-- a sufficiently patient player produces an unbounded number.
	maxValuePerUnit = 5000,
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
}

return Extraction

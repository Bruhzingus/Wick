--!strict
-- The mining presentation boundary. The server builds and owns the deposit model and writes these
-- attributes; the client reads them to draw the prompt, the seam's wear, and the timing rail. It is
-- the same contract shape the dripstone and lurker use: the server publishes state, never motion.
--
-- The client is never told the accuracy windows through here — it computes them from
-- Logic/MiningRules against the sweep timestamp below, which is the same function the server scores
-- with. The strike request may echo the shared clock sampled at input; MiningRules accepts it only
-- inside a strict rewind window and otherwise scores authoritative arrival.

local MiningVisualProtocol = {}

-- Tag on every built deposit model. The client watches this collection.
MiningVisualProtocol.depositTag = "WickWaxDeposit"

-- Attributes on the deposit's root part.
MiningVisualProtocol.attributes = {
	-- Floor ordinal this deposit belongs to. Clients ignore deposits on other floors.
	depth = "WickDepositDepth",
	-- Server-owned progress, 0..1. The ONLY progress value that exists; clients render it and
	-- never advance it.
	progress = "WickDepositProgress",
	-- Set once when the seam breaks, so a late-joining client renders it spent rather than fresh.
	depleted = "WickDepositDepleted",
	-- Which Config/Mining row this seam is. The client needs it to name the seam on its prompt and to
	-- count the clean strikes left, because both differ per row — a rail that promised three swings on
	-- a nine-swing Deep Seam would be the readout lying to the player.
	rowId = "WickDepositRowId",
	-- The shared-clock instant an explosive seam's fuse was lit, or 0. Written once, when the seam
	-- primes, so a client that joins or renders late starts the crackle at the right point in the three
	-- seconds rather than from the top. The BLAST itself is a separate authoritative event — this
	-- attribute is only the countdown, and nothing client-side ever decides that it finished.
	primedAt = "WickDepositPrimedAt",
}

-- `MineState` payload kinds (Net/Remotes). Fired to the striker for responsive viewmodel/HUD
-- presentation. Accepted world contact is separately broadcast as `RunEvent("mineImpact")`, while
-- hunter hearing remains server-owned through NoiseService.
-- Every sweep payload carries the same three numbers: when the current pass started (in
-- `Workspace:GetServerTimeNow()` space), where its target band sits, and which strike of this stance
-- it belongs to. The client derives the whole rail from them and reports no phase or accuracy.
export type MineStateKind =
	-- payload: { startedAt: number, bandCenter: number, strikeIndex: number, progress: number,
	--            deposit: BasePart } — the stance is now locked.
	"engaged"
	-- payload: the same sweep fields for the NEXT pass, plus
	-- { deposit: BasePart, accuracy: string, depleted: boolean, shardWax: number, rawWaxGranted: number,
	--   rawWaxCarried: number } for the strike that just landed. Deposit remains explicit because local
	-- release may already clear the stance.
	--
	-- CARGO ARRIVES ON EVERY STRIKE, not only on the break, because that is when it is earned now
	-- (Config/Mining). `rawWaxGranted` is whole Raw Wax grams and is zero for a fumble.
	| "strikeResolved"
	-- payload: { deposit, rawWaxGranted, rawWaxCarried, sharedWith }. A CO-OPERATIVE ROW'S HELPER was
	-- paid for a swing somebody else landed (Config/Mining.rows.maxPaidMiners). Deliberately not a
	-- `strikeResolved`: this player did not swing, so nothing about their own rail or stance changed —
	-- the only thing that moved is their cargo, and it must move with a visible cause on the same frame.
	| "sharedStrike"
	| "disengaged" -- payload: { reason: string } — the stance is over, whoever ended it
	-- payload: { deposit, minedThisRun, globalDepth, rawWaxCarried, accuracy, shardWax, sharedWith? }.
	-- The seam is worked out. `sharedWith` is present only for a co-operative row's helper. `accuracy`
	-- and `shardWax` duplicate the accepted break's physical result because this private event can race
	-- the public `mineImpact` stream; either route must claim identical break presentation. Clients
	-- reject all deposit-bearing kinds when the root is gone or belongs to a different current depth.
	--
	-- IT NO LONGER CARRIES A PAYOUT. Breaking a seam is the end of an income stream rather than the
	-- moment of it, so there is nothing to announce here that `strikeResolved` did not already say.
	| "depleted"

return MiningVisualProtocol

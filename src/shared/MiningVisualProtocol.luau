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
	-- payload: the same sweep fields for the NEXT pass, plus { accuracy: string, depleted: boolean }
	-- for the strike that just landed.
	| "strikeResolved"
	| "disengaged" -- payload: { reason: string } — the stance is over, whoever ended it
	-- payload: { minedThisRun, globalDepth, rawWaxGranted, rawWaxCarried, paidMiners?, sharedWith? }.
	-- `sharedWith` is present only for a co-operative row's helper: somebody else landed the breaking
	-- strike and this player was paid for standing there when it went.
	| "depleted"

return MiningVisualProtocol

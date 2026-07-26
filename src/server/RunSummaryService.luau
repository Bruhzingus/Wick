--!strict
-- Development-only run accounting readout: at the moment a player's expedition resolves, turn their
-- per-run wax ledger into one structured server log line answering "why did this run end?".
--
-- Deliberately narrow for now (IMPLEMENTATION-ROADMAP): it writes to the existing Telemetry log,
-- adds no UI, changes no gameplay value, and persists nothing — detailed run telemetry does not go
-- into ProfileStore yet. Each player's run is summarized at most once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local PlayerState = require(script.Parent.PlayerState)
local Telemetry = require(script.Parent.Telemetry)

local RunSummaryService = {}

local emitted: { [Types.PlayerId]: boolean } = {}

local function formatSources(bySource: { [Types.WaxSource]: number }): string
	local keys: { string } = {}
	for source in bySource do
		table.insert(keys, source)
	end
	table.sort(keys)
	local parts: { string } = {}
	for _, source in keys do
		table.insert(parts, string.format("%s:%.2f", source, bySource[source :: Types.WaxSource]))
	end
	if #parts == 0 then
		return "none"
	end
	return table.concat(parts, ",")
end

-- Build the summary without emitting it. Exposed so a future results payload can reuse the same
-- server-computed numbers instead of recomputing them somewhere else.
function RunSummaryService.build(playerId: Types.PlayerId, outcome: Types.WaxRunOutcome): Types.WaxRunSummary?
	local state = PlayerState.get(playerId)
	if state == nil then
		return nil
	end
	WaxAccounting.noteDepth(state.waxLedger, PlayerState.globalDepth(state))
	return WaxAccounting.summarize(state.waxLedger, state.wax.current, os.clock(), outcome)
end

function RunSummaryService.emit(playerId: Types.PlayerId, outcome: Types.WaxRunOutcome)
	if emitted[playerId] then
		return
	end
	local summary = RunSummaryService.build(playerId, outcome)
	if summary == nil then
		return
	end
	emitted[playerId] = true
	Telemetry.event("run_wax_summary", playerId, {
		outcome = summary.outcome,
		startDepth = summary.startDepth,
		deepestGlobalDepth = summary.deepestGlobalDepth,
		durationSeconds = string.format("%.1f", summary.durationSeconds),
		startingWax = string.format("%.2f", summary.startingWax),
		endingWax = string.format("%.2f", summary.endingWax),
		totalLost = string.format("%.2f", summary.totalLost),
		totalGained = string.format("%.2f", summary.totalGained),
		lost = formatSources(summary.lostBySource),
		gained = formatSources(summary.gainedBySource),
		-- Non-zero means some code path changed wax without going through the accounting API.
		reconciliationError = string.format("%.4f", summary.reconciliationError),
	})
end

function RunSummaryService.clear(playerId: Types.PlayerId)
	emitted[playerId] = nil
end

function RunSummaryService.reset()
	table.clear(emitted)
end

return RunSummaryService

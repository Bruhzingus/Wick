--!strict
-- ============================ STUB ============================
-- Player remains / wax pools (DESIGN §13). Real version syncs pools across runs (a dead player's wax
-- appears in strangers' runs as light + a recoverable resource). Replace this one file.
-- Currently no remains exist and deposits are dropped.
-- =============================================================

local Types = require(script.Parent.Parent.Types)

export type Remains = {
	playerId: Types.PlayerId,
	position: Vector3,
	wax: Types.WaxAmount,
}

export type RemainsInterface = {
	listForFloor: (depth: number) -> { Remains },
	deposit: (remains: Remains) -> (),
}

local Remains: RemainsInterface = {
	listForFloor = function(_depth)
		return {} -- STUB: no remains
	end,
	deposit = function(_remains)
		-- STUB: dropped
	end,
}

return Remains

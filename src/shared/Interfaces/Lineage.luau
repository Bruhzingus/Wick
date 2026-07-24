--!strict
-- ============================ STUB ============================
-- Lineage carryover between candles (DESIGN §14). Real version persists a small token from the last run
-- and lights the next candle from it. Replace this one file. Currently always generation 1, no inheritance.
-- =============================================================

local Types = require(script.Parent.Parent.Types)

export type Lineage = {
	generation: number,
	inheritedTrait: string?,
}

export type LineageInterface = {
	get: (playerId: Types.PlayerId) -> Lineage,
}

local Lineage: LineageInterface = {
	get = function(_playerId)
		return { generation = 1, inheritedTrait = nil } -- STUB
	end,
}

return Lineage

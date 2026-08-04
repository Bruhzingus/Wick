--!strict
-- In-run loot adds a roguelike modifier to the candle you already have, or grants a free use of an
-- existing tool. It never adds a second resource or a parallel tool path.

local Wax = require(script.Parent.Wax)
local Tool = require(script.Parent.Tool)

export type LootId = string
export type LootKind = "CandleModifier" | "ToolCharge" | "SelfRelight"

-- Static content row consumed by FloorPlanner and LootService. Optional fields are selected by
-- `kind`; adding a pickup with an existing kind is a config-only change.
export type LootDef = {
	id: LootId,
	displayName: string,
	kind: LootKind,
	spawnWeightByDepth: { number },
	-- Lowest GLOBAL depth this row may appear at, per cave family id ("STONE"/"MOSS"/"ICE"). Absent
	-- means "available from depth 1 in every family"; a family missing from a present table means the
	-- row never spawns there at all. This is how a rare deep-cave item is gated by cave rather than by
	-- weight alone — a weight of 0.001 is still a weight, a depth gate is a promise.
	minDepthByFamily: { [string]: number }?,
	modifierId: Wax.CandleModifierId?,
	toolId: Tool.ToolId?,
	freeCharges: number?,
	matchCharges: number?,
	color: Color3,
}

return {}

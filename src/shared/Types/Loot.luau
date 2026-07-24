--!strict
-- In-run loot changes a candle's burn profile or grants a free use of an existing tool.
-- It never adds a second resource or a parallel tool path.

local Wax = require(script.Parent.Wax)
local Tool = require(script.Parent.Tool)

export type LootId = string
export type LootKind = "WaxType" | "ToolCharge"

-- Static content row consumed by FloorPlanner and LootService. Optional fields are selected by
-- `kind`; adding a pickup with an existing kind is a config-only change.
export type LootDef = {
	id: LootId,
	displayName: string,
	kind: LootKind,
	spawnWeightByDepth: { number },
	waxTypeId: Wax.WaxTypeId?,
	toolId: Tool.ToolId?,
	freeCharges: number?,
	color: Color3,
}

return {}

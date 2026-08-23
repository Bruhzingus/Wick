--!strict
-- In-run loot adds a roguelike modifier to the candle you already have, or grants a free use of an
-- existing tool. It never adds a second resource or a parallel tool path.

local Wax = require(script.Parent.Wax)
local Tool = require(script.Parent.Tool)
local Dynamite = require(script.Parent.Dynamite)

export type LootId = string
-- "Dynamite" grants sticks of the found consumable (Config/Dynamite). It is its own kind rather than a
-- `ToolCharge` because a tool charge is a free activation of a tool the player already permanently
-- owns, and dynamite is an object they do not own until they find it.
-- "RawWax" grants EXTRACTION CARGO rather than anything to do with the candle — the same grams a
-- mining seam pays, banked the same way, priced on the way out by the same curve. It is its own kind
-- because every other row here modifies the thing in your hand, and this one modifies the bag.
export type LootKind = "CandleModifier" | "ToolCharge" | "SelfRelight" | "Dynamite" | "RawWax"

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
	-- "Dynamite" rows only: how many sticks this cache is worth. One for a loose stick, several for a
	-- crate. The two rows differ in nothing else, which is what keeps a crate a quantity rather than a
	-- second item with its own rules.
	dynamiteCharges: number?,
	-- "Dynamite" rows only: which silhouette to build (Shared/NewModelsAndObjects/Dynamite).
	dynamiteStyle: Dynamite.DynamiteStyle?,
	-- "RawWax" rows only: what this pile is worth, IN SEAMS rather than in grams.
	--
	-- EXPRESSED IN NODES ON PURPOSE. A gram figure would have to be re-derived by hand every time the
	-- mining economy moved, and it moved by half once already (`Config/Mining` rows: "the rate halved,
	-- deliberately"). A node is one ordinary Standard seam worked clean — `cleanStrikes` of
	-- `gramsPerStrike` — so a row that says "two to five nodes" keeps meaning the same thing to a
	-- player whatever those two numbers become.
	rawWaxNodesMin: number?,
	rawWaxNodesMax: number?,
	color: Color3,
}

return {}

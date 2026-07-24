--!strict
-- In-run loot content and pickup tuning (DESIGN section 14). Wax pickups replace the active
-- burn profile; charge pickups grant free activations through the existing ToolService path.

local Types = require(script.Parent.Parent.Types)

export type LootConfig = {
	spawnsPerFloor: { number },
	spawnOffsetRadius: number,
	pickupRange: number,
	pickupHoldSeconds: number,
	visualSize: number,
	definitions: { [Types.LootId]: Types.LootDef },
}

local Loot: LootConfig = {
	-- Small, dependable decision density without turning exploration into a loot sweep.
	spawnsPerFloor = { 1, 1, 2, 2, 2, 2, 3, 3, 3, 3 },
	-- Planner-authored horizontal offset from a room centre (studs).
	spawnOffsetRadius = 10,
	pickupRange = 8,
	pickupHoldSeconds = 0.25,
	visualSize = 1.1,
	definitions = {
		BeeswaxCache = {
			id = "BeeswaxCache",
			displayName = "Beeswax",
			kind = "WaxType",
			spawnWeightByDepth = { 7, 7, 6, 6, 5, 5, 4, 4, 3, 3 },
			waxTypeId = "Beeswax",
			color = Color3.fromRGB(235, 174, 62),
		},
		TallowCache = {
			id = "TallowCache",
			displayName = "Tallow",
			kind = "WaxType",
			spawnWeightByDepth = { 5, 5, 6, 6, 6, 5, 5, 4, 4, 4 },
			waxTypeId = "Tallow",
			color = Color3.fromRGB(244, 224, 184),
		},
		ColdWaxCache = {
			id = "ColdWaxCache",
			displayName = "Cold Wax",
			kind = "WaxType",
			spawnWeightByDepth = { 0, 0, 0, 1, 1, 2, 2, 3, 4, 5 },
			waxTypeId = "ColdWax",
			color = Color3.fromRGB(122, 212, 255),
		},
		FlareCharge = {
			id = "FlareCharge",
			displayName = "Prepared Flare",
			kind = "ToolCharge",
			spawnWeightByDepth = { 4, 4, 4, 4, 3, 3, 3, 3, 3, 3 },
			toolId = "Flare",
			freeCharges = 1,
			color = Color3.fromRGB(255, 112, 47),
		},
		CastCharge = {
			id = "CastCharge",
			displayName = "Prepared Decoy",
			kind = "ToolCharge",
			spawnWeightByDepth = { 3, 3, 4, 4, 4, 4, 4, 4, 4, 4 },
			toolId = "Cast",
			freeCharges = 1,
			color = Color3.fromRGB(255, 186, 92),
		},
	},
}

return Loot

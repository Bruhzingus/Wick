--!strict
-- In-run loot content and pickup tuning (DESIGN section 14). Modifier pickups add a roguelike
-- upgrade to the candle you already have (Config/CandleModifiers); charge pickups grant free
-- activations through the existing ToolService path. Neither adds a second resource.

local Types = require(script.Parent.Parent.Types)

-- Inclusive band of pickups a floor may plan, rolled once per floor. A band rather than a fixed
-- count so "how much did this floor give me" is a real variable between runs.
export type SpawnBand = {
	minimum: number,
	maximum: number,
}

export type LootConfig = {
	spawnsPerFloor: { SpawnBand },
	wallInsetMin: number,
	wallInsetMax: number,
	wallLateralRange: number,
	placementAttempts: number,
	placementFootprint: number,
	minimumCenterDistance: number,
	fallbackRings: number,
	fallbackRingSamples: number,
	pickupRange: number,
	pickupHoldSeconds: number,
	visualSize: number,
	surfaceClearance: number,
	promptHeight: number,
	definitions: { [Types.LootId]: Types.LootDef },
}

local Loot: LootConfig = {
	-- HOW MANY PICKUPS A FLOOR CARRIES, indexed by global depth (the last row covers everything
	-- deeper). Rolled inclusively per floor.
	--
	-- These bands are roughly HALF the flat 2/3/4-per-floor counts they replace. The old schedule
	-- guaranteed loot on every floor, which made the pool background noise: you did not decide to go
	-- and find an item, you walked past three. A shallow floor now averages one pickup and can
	-- honestly have none, so a cache is worth crossing a room for, and the count climbs with depth so
	-- a long run still accumulates a real build.
	spawnsPerFloor = {
		{ minimum = 0, maximum = 2 },
		{ minimum = 0, maximum = 2 },
		{ minimum = 0, maximum = 2 },
		{ minimum = 0, maximum = 2 },
		{ minimum = 1, maximum = 2 },
		{ minimum = 1, maximum = 2 },
		{ minimum = 1, maximum = 2 },
		{ minimum = 1, maximum = 3 },
		{ minimum = 1, maximum = 3 },
		{ minimum = 1, maximum = 3 },
		{ minimum = 1, maximum = 3 },
		{ minimum = 2, maximum = 4 },
	},
	-- Loot belongs in peripheral shelves and wall pockets, not in the room-centre walking line.
	-- Inset for the same reason as Config/Mining.placement: a pickup's probe-widened footprint is
	-- contained only within about 24 studs of the room centre, and the old 6..13 range rolled it out
	-- to 26, so the outermost rolls were refused or walked back and the survivors sat in the eroded
	-- side-wall band. 8..15 keeps every roll inside the boundary on the first try.
	wallInsetMin = 8,
	wallInsetMax = 15,
	wallLateralRange = 24,
	placementAttempts = 18,
	placementFootprint = 3.4,
	-- HOW CLOSE TO THE ROOM'S CENTRE A PICKUP MAY EVER BE PLANNED. The half-cell is 32 studs, so this
	-- reserves the middle of every room — the walking line, the sightline, the fighting space — and
	-- keeps pickups against the geology where a candle sweep finds them.
	--
	-- This exists because of the shape of the old failure. When every wall pocket was rejected, the
	-- planner walked its last corner straight inward and then returned the room ORIGIN, and the
	-- surface probe's own repair ladder ended at the room origin too. Both gave up toward the same
	-- point, so the harder a room was to place in, the more certain it was to put its item in the
	-- exact middle. The ring sweep below replaces that: a failed pocket now tries every other bearing
	-- at the same distance from the centre before it gives up any ground at all.
	minimumCenterDistance = 14,
	-- Rings the deterministic sweep walks between the outer wall band and `minimumCenterDistance`,
	-- and bearings tried per ring. 4 x 12 is 48 candidate shelves, which in practice resolves every
	-- shaped room without ever reaching the room hub.
	fallbackRings = 4,
	fallbackRingSamples = 12,
	pickupRange = 8,
	pickupHoldSeconds = 0.25,
	visualSize = 1.15,
	-- Minimum clearance beneath the VISIBLE model after it is aligned to the highest nearby Terrain
	-- sample. A third of a stud clears smooth-Terrain interpolation without reading as a hover.
	surfaceClearance = 0.35,
	promptHeight = 1.45,
	definitions = {
		-- THE STACKING PAIR. Common, small, and the two ends of the same question: do you want the
		-- candle to last longer, or to see further with it?
		LifeWax = {
			id = "LifeWax",
			displayName = "Life Wax",
			kind = "CandleModifier",
			-- The most common row in the pool. Survivability is the stack a new player finds first.
			spawnWeightByDepth = { 8, 8, 8, 7, 7, 7, 6, 6, 6, 6 },
			modifierId = "LifeWax",
			color = Color3.fromRGB(226, 205, 152),
		},
		BrightWax = {
			id = "BrightWax",
			displayName = "Bright Wax",
			kind = "CandleModifier",
			spawnWeightByDepth = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 },
			modifierId = "BrightWax",
			color = Color3.fromRGB(250, 242, 222),
		},
		ExtraWicks = {
			id = "ExtraWicks",
			displayName = "Extra Wicks",
			kind = "CandleModifier",
			spawnWeightByDepth = { 4, 4, 5, 5, 5, 5, 5, 5, 5, 5 },
			modifierId = "ExtraWicks",
			color = Color3.fromRGB(214, 176, 108),
		},
		-- Absent from the first two floors: it is only worth anything to a player who has already
		-- learned to push the dial, and the first two floors are where they learn not to.
		FrozenWax = {
			id = "FrozenWax",
			displayName = "Frozen Wax",
			kind = "CandleModifier",
			spawnWeightByDepth = { 0, 0, 2, 3, 4, 4, 5, 5, 6, 6 },
			modifierId = "FrozenWax",
			color = Color3.fromRGB(176, 219, 246),
		},
		-- THE RARE ONE. Its rarity is a depth gate first and a weight second: it cannot appear at all
		-- until a cave is genuinely deep, and each family reaches "deep" at a different floor because
		-- each family's difficulty curve does (Config/CaveFamilies). Ice is the steepest curve in the
		-- game, so its floor 5 has earned what Stone's floor 15 has.
		--
		-- The single-entry weight table is deliberate: the gate decides WHETHER, so the weight only
		-- has to decide how often, and 1.5 against a pool of ~33 is the lowest share of any row.
		CandleSleeve = {
			id = "CandleSleeve",
			displayName = "Candle Sleeve",
			kind = "CandleModifier",
			spawnWeightByDepth = { 1.5 },
			minDepthByFamily = {
				STONE = 15,
				MOSS = 10,
				ICE = 5,
			},
			modifierId = "CandleSleeve",
			color = Color3.fromRGB(168, 132, 88),
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
		DecoyCharge = {
			id = "DecoyCharge",
			displayName = "Prepared Decoy",
			kind = "ToolCharge",
			spawnWeightByDepth = { 3, 3, 4, 4, 4, 4, 4, 4, 4, 4 },
			toolId = "Decoy",
			freeCharges = 1,
			color = Color3.fromRGB(255, 186, 92),
		},
		Match = {
			id = "Match",
			displayName = "Match",
			kind = "SelfRelight",
			spawnWeightByDepth = { 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 },
			matchCharges = 1,
			color = Color3.fromRGB(214, 126, 62),
		},
	},
}

return Loot

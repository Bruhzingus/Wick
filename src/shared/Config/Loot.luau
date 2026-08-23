--!strict
-- In-run loot content and pickup tuning (DESIGN section 14). Modifier pickups add a roguelike
-- upgrade to the candle you already have (Config/CandleModifiers); charge pickups grant free
-- activations through the existing ToolService path. Neither adds a second resource.

local Types = require(script.Parent.Parent.Types)
local Dynamite = require(script.Parent.Dynamite)

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
	-- How far from the kill a boss's reward piles are laid out, as a ring radius. Wide enough that they
	-- are separate objects with separate prompts, tight enough to read as one drop.
	bossDropSpread: number,
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
	bossDropSpread = 5.5,
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
	-- Tiny separation from the exact centre-sampled Terrain surface to prevent z-fighting without
	-- making the pickup read as hovering.
	surfaceClearance = 0.05,
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
		-- DYNAMITE (Config/Dynamite). These two rows carry a weight of ZERO and that is not a mistake:
		-- dynamite is never drawn from the ordinary weighted pool. `Logic/FloorPlanner` emits it from
		-- its own deterministic schedule (a stick every 1-3 floors, a crate every 10-20) straight into
		-- `lootSpawns`, exactly the way the Dead Candle emits its own pickups.
		--
		-- WHY IT IS NOT IN THE POOL. Every other row here is a small permanent improvement, and the
		-- pool's job is to decide which of them a floor happens to offer. Dynamite is a single
		-- consumable object whose whole design depends on the cave supplying it at a KNOWN rate — a
		-- weight would have made it a lottery, and a player cannot plan around a lottery. The rows still
		-- live here because everything downstream (placement, surface probing, the prompt, the pickup
		-- message, the first-sighting hint) is the ordinary loot path and should stay that way.
		DynamiteStick = {
			id = "DynamiteStick",
			displayName = "Dynamite",
			kind = "Dynamite",
			spawnWeightByDepth = { 0 },
			dynamiteCharges = 1,
			dynamiteStyle = "Stick",
			color = Color3.fromRGB(139, 46, 38),
		},
		DynamiteCrate = {
			id = "DynamiteCrate",
			displayName = "Crate of Dynamite",
			kind = "Dynamite",
			spawnWeightByDepth = { 0 },
			-- Reads its count from the config rather than repeating it, so "how many sticks is a crate"
			-- stays one number in one file.
			dynamiteCharges = Dynamite.supply.crateCharges,
			dynamiteStyle = "Crate",
			color = Color3.fromRGB(88, 66, 43),
		},
		-- WHAT A BOSS IS WORTH, and the only row in this table that pays extraction cargo instead of
		-- changing the candle.
		--
		-- IT IS NEVER ROLLED. `spawnWeightByDepth = { 0 }` keeps it out of the ordinary pool entirely —
		-- like the two dynamite rows above it, this is a thing an authored encounter DROPS, not a thing
		-- a floor can happen to contain. `server/BossEncounterService` and `UnlittiusEncounterService`
		-- place one per living player where the boss died.
		--
		-- TWO TO FIVE NODES, rolled per pile, where a node is one ordinary Standard seam worked clean
		-- (Config/Mining: 4 strikes x 25g = 100g). So a boss pays somewhere between two and five seams'
		-- worth of grams to each person who was alive to see it die — a real payday against a floor that
		-- now carries no seams at all, and still priced on the way out by the same curve as every gram
		-- that came out of a wall.
		BossWax = {
			id = "BossWax",
			displayName = "Wax of the Slain",
			kind = "RawWax",
			spawnWeightByDepth = { 0 },
			rawWaxNodesMin = 2,
			rawWaxNodesMax = 5,
			color = Color3.fromRGB(236, 214, 150),
		},
	},
}

return Loot

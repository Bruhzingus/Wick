--!strict
-- MOSS FLAMMABLE VEGETATION — the one thing in the game your own flame can set alight.
--
-- A tagged cluster of dry growth in an ordinary Moss room. Hold an uncovered flame against it, or
-- throw a burning Decoy into it, or pop a Flare beside it, and it catches; the fire runs along that
-- cluster's own connected growth and burns out. While it burns it is a real light source in the
-- shared light field and a real heat source that costs Living Wax.
--
-- WHAT IT IS FOR. Three legitimate uses, all of them trades rather than upgrades:
--   * clear an optional vegetation obstruction out of a route you wanted;
--   * buy temporary visibility without spending your own dial;
--   * reveal part of a room you could not otherwise read.
-- Against: it draws every Drawn threat in earshot, it costs wax to stand near, it is a light you do
-- not control, and it makes a room dangerous for as long as it lasts.
--
-- FIVE HARD RULES, and every number below is subordinate to them:
--
--   1. UNCOMMON. Most Moss rooms have nothing to burn. Fire is an event, not a mechanic you plan
--      around, and the per-room chances here are deliberately low even at depth.
--   2. NOTHING ELSE BURNS. Only explicitly tagged clusters are flammable. Wet cave walls do not
--      burn, ordinary damp moss does not burn, and flammability is NEVER inferred from a colour or a
--      material at runtime — a future dressing pass that happens to pick a dry-looking green must
--      not accidentally become fuel.
--   3. NEVER LOAD-BEARING. A cluster is never placed on the guaranteed route, in the entry, Basin or
--      completion room, or across a doorway lane, a spawn clearance, or a required item or threat
--      footprint. No obstruction it forms is mandatory: another valid route always exists.
--   4. NOT A FLARE. Burning vegetation is ordinary environmental light. It attracts Drawn normally
--      and affects ordinary dark-hunter hunt/stalk logic normally, and it can never force the
--      panic-light retreat that only a real Flare causes.
--   5. NO SECOND RESOURCE. Heat costs Living Wax and nothing else. There is no burn meter, no
--      temperature, no new bar.
--
-- The fire changes the CURRENT generated floor only. It creates no persistent world state.

export type IgnitionIntensity = "Low" | "Medium" | "High"

export type VegetationKind = {
	id: string,
	displayName: string,
	-- Relative weight among the kinds a cluster may draw its nodes from.
	weight: number,
	-- Quick-burning strands carry fire across a cluster much faster and die much sooner. Everything
	-- else smoulders along at the ordinary rate.
	quick: boolean,
	burnSecondsMin: number,
	burnSecondsMax: number,
}

export type MossFireConfig = {
	enabled: boolean,
	-- Chance an ELIGIBLE room carries a cluster, by global depth. Rows are scanned in order and
	-- depths past the final row use the final row.
	chanceByDepth: { { maxDepth: number, chance: number } },
	placement: {
		-- Hard cap, and the reason the whole feature stays legible: one cluster per room, always.
		maxClustersPerRoom: number,
		-- Hard cap per FLOOR on clusters that may be alight at once. Bounds the particle, light and
		-- audio cost of a floor whatever a player does to it.
		maxActiveClustersPerFloor: number,
		minDepth: number,
		nodesMin: number,
		nodesMax: number,
		-- How far apart a cluster's own nodes sit, and how far the whole cluster reaches.
		nodeSpacingMin: number,
		nodeSpacingMax: number,
		clusterRadius: number,
		placementAttempts: number,
		-- Distance a cluster keeps from the room centre, so it hugs the room's growth rather than
		-- sitting on the navigation hub.
		minCenterOffset: number,
		maxCenterOffset: number,
		-- Clearance from every planned gameplay footprint (spawns, seams, hazards, fixtures).
		gameplayClearance: number,
		-- Chance a placed cluster also forms a collidable obstruction that burning clears. Safe by
		-- construction: a cluster is already never on a route, in a lane, or on the hub.
		obstructionChance: number,
	},
	ignition: {
		-- Seconds of continuous exposure to each burn intensity before a cluster catches. Interpolated
		-- continuously from the flame's current burn rate, so these are the anchors of a curve rather
		-- than three discrete cases.
		lowExposureSeconds: number,
		mediumExposureSeconds: number,
		highExposureSeconds: number,
		-- Burn-rate fractions of the game maximum that count as low and high. Below low contributes
		-- nothing at all.
		lowBurnFraction: number,
		highBurnFraction: number,
		-- How close a source has to be.
		range: number,
		-- Ignition progress lost per second once every source has left range. A player who nearly lit
		-- something and walked away has not armed a trap for whoever comes next.
		decayPerSecond: number,
		-- A Flare is a burst of panic light; against dry growth it is simply instant.
		flareIgnitesImmediately: boolean,
		-- A burning Decoy contributes as a fixed intensity rather than reading a dial it does not have.
		decoyIntensity: IgnitionIntensity,
	},
	spread: {
		-- Seconds between spread attempts along ordinary growth, and along a quick-burning strand.
		normalIntervalSeconds: number,
		quickIntervalSeconds: number,
	},
	light: {
		-- Ordinary environmental light. Comparable to a mid-dial candle, and deliberately not more:
		-- a fire that outshone a Flare would become the answer to every dark room.
		intensity: number,
		range: number,
		-- Rises as the cluster catches and falls as it dies, so a fire reads as a thing with a life.
		riseSeconds: number,
		fadeSeconds: number,
	},
	heat: {
		-- Wax per second, by distance from a burning node. Living Wax and nothing else.
		nearRadius: number,
		nearWaxPerSecond: number,
		farRadius: number,
		farWaxPerSecond: number,
		-- The most any ONE cluster may cost per second however many of its nodes are alight. Without
		-- this, standing in the middle of a big cluster would be an instant death rather than a bad
		-- decision.
		clusterCapPerSecond: number,
	},
	visual: {
		nodeSizeMin: number,
		nodeSizeMax: number,
		strandPalette: { Color3 },
		strandMaterial: Enum.Material,
		emberPalette: { Color3 },
		obstructionThickness: number,
		obstructionHeight: number,
	},
	kinds: { VegetationKind },
}

local MossFire: MossFireConfig = {
	enabled = true,
	-- UNCOMMON, and only slowly less so. At depth 16 four rooms in five still have nothing to burn.
	chanceByDepth = {
		{ maxDepth = 5, chance = 0.10 },
		{ maxDepth = 10, chance = 0.13 },
		{ maxDepth = 15, chance = 0.16 },
		{ maxDepth = math.huge, chance = 0.20 },
	},
	placement = {
		maxClustersPerRoom = 1,
		-- Four at once on one floor is already an unusual amount of light and noise; the cap exists so
		-- a player who systematically torches everything cannot turn a floor into a bonfire.
		maxActiveClustersPerFloor = 4,
		minDepth = 1,
		nodesMin = 4,
		nodesMax = 7,
		nodeSpacingMin = 2.5,
		nodeSpacingMax = 5,
		clusterRadius = 9,
		placementAttempts = 20,
		minCenterOffset = 16,
		maxCenterOffset = 26,
		gameplayClearance = 6,
		obstructionChance = 0.45,
	},
	ignition = {
		lowExposureSeconds = 2.5,
		mediumExposureSeconds = 1.5,
		highExposureSeconds = 0.75,
		-- Below a third of maximum burn the flame is not hot enough to do anything at all, which is
		-- what makes a cupped or guttering candle safe to carry past dry growth.
		lowBurnFraction = 0.33,
		highBurnFraction = 0.95,
		range = 6,
		-- Roughly half the rate progress accrues at, so backing off loses ground without erasing a
		-- deliberate attempt the instant a player steps sideways.
		decayPerSecond = 0.25,
		flareIgnitesImmediately = true,
		decoyIntensity = "Medium",
	},
	spread = {
		normalIntervalSeconds = 0.75,
		quickIntervalSeconds = 0.25,
	},
	light = {
		intensity = 1.15,
		range = 26,
		riseSeconds = 1.2,
		fadeSeconds = 2.5,
	},
	heat = {
		nearRadius = 4,
		nearWaxPerSecond = 0.020,
		farRadius = 8,
		farWaxPerSecond = 0.008,
		clusterCapPerSecond = 0.025,
	},
	visual = {
		nodeSizeMin = 1.6,
		nodeSizeMax = 3.4,
		-- Dry, red-starved browns and olives. Visibly DEAD growth beside the living moss on the walls,
		-- because a player has to be able to tell what will burn before they hold a flame to it.
		strandPalette = {
			Color3.fromRGB(74, 62, 34),
			Color3.fromRGB(63, 55, 30),
			Color3.fromRGB(85, 74, 42),
			Color3.fromRGB(58, 50, 28),
		},
		strandMaterial = Enum.Material.Grass,
		emberPalette = {
			Color3.fromRGB(255, 140, 40),
			Color3.fromRGB(255, 96, 24),
			Color3.fromRGB(196, 60, 18),
		},
		obstructionThickness = 2.2,
		obstructionHeight = 6,
	},
	kinds = {
		{
			id = "DryMossMat",
			displayName = "Dry Moss Mat",
			weight = 3,
			quick = false,
			burnSecondsMin = 6,
			burnSecondsMax = 10,
		},
		{
			id = "DryRootBundle",
			displayName = "Dry Root Bundle",
			weight = 2.4,
			quick = false,
			burnSecondsMin = 7,
			burnSecondsMax = 10,
		},
		{
			id = "DryFungusCluster",
			displayName = "Dry Fungus Cluster",
			weight = 1.6,
			quick = false,
			burnSecondsMin = 6,
			burnSecondsMax = 9,
		},
		{
			-- The one kind that carries fire across a whole cluster in a couple of seconds. Fewer of
			-- them, and they die fast: a strand is what makes a cluster go up at once instead of
			-- creeping, which is the difference between a decision and a wait.
			id = "QuickStrand",
			displayName = "Quick-Burning Strand",
			weight = 1,
			quick = true,
			burnSecondsMin = 3,
			burnSecondsMax = 5,
		},
	},
}

return MossFire

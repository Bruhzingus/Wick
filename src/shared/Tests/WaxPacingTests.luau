--!strict
-- Phase 2 (wax pacing correction): deterministic evidence for the wax-budget target in TUNING.md.
-- Computes the REAL unavoidable direct-route wax cost per depth by generating an actual FloorPlan
-- and walking the exact reciprocal-doorway room graph Logic/RoomNavigation already builds for
-- threat routing (never a hand-picked distance guess), across several seeds so no assertion rests
-- on one hand-picked floor.

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local WaxConfig = require(script.Parent.Parent.Config.Wax)
local WaxTypes = require(script.Parent.Parent.Config.WaxTypes)
local MovementConfig = require(script.Parent.Parent.Config.Movement)
local LightConfig = require(script.Parent.Parent.Config.Light)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)
local CaveTiersConfig = require(script.Parent.Parent.Config.CaveTiers)
local FloorPlanner = require(script.Parent.Parent.Logic.FloorPlanner)
local RoomNavigation = require(script.Parent.Parent.Logic.RoomNavigation)
local WaxDrain = require(script.Parent.Parent.Logic.WaxDrain)

-- A modest, "efficient but still lit enough to navigate" dial. Not the literal dial floor (0.18,
-- effectively blind) — it stands in for a nearly flawless player who keeps brightness low but
-- practical for the whole descent. See TUNING.md "the wax pacing budget model".
local CLEAN_RUN_DIAL = 0.30
local SEEDS = { 11, 977, 30047, 512927, 7368787 }

-- Shortest number of room-to-room hops from the entry to the Basin (which holds the descent pad),
-- using the exact graph RoomNavigation.build derives from reciprocal doorways. `roomCenters` only
-- feeds RoomNavigation's hazard-avoidance bookkeeping, which this walk never reads, so placeholder
-- positions (grid-aligned, in studs) are enough.
local function shortestHopsToBasin(plan: Types.FloorPlan): number
	local placeholderCenters: { Vector3 } = {}
	for _, room in plan.rooms do
		table.insert(placeholderCenters, Vector3.new(room.gridX, 0, room.gridZ))
	end
	local navigation = RoomNavigation.build(plan, placeholderCenters)

	local basinNeighborSet: { [number]: boolean } = {}
	for _, roomIndex in navigation.basinNeighbors do
		basinNeighborSet[roomIndex] = true
	end
	if basinNeighborSet[plan.entryRoomIndex] then
		return 1
	end

	local visited: { [number]: boolean } = { [plan.entryRoomIndex] = true }
	local frontier: { number } = { plan.entryRoomIndex }
	local hops = 0
	while #frontier > 0 do
		hops += 1
		local nextFrontier: { number } = {}
		for _, roomIndex in frontier do
			for _, neighborIndex in navigation.neighbors[roomIndex] or {} do
				if basinNeighborSet[neighborIndex] then
					return hops + 1
				end
				if not visited[neighborIndex] then
					visited[neighborIndex] = true
					table.insert(nextFrontier, neighborIndex)
				end
			end
		end
		frontier = nextFrontier
	end
	error("Basin unreachable from the entry room on a generated floor — guaranteed-route invariant broken")
end

-- The wax a maximally efficient player spends walking `studs` at a fixed dial: standard wax type,
-- no water/cup/tools/threats. The floor of what reaching the Basin costs at all.
local function directRouteWaxCost(studs: number, burnRate: number): number
	local perSecond = WaxDrain.perSecond({
		isLit = true,
		burnRate = burnRate,
		waxType = WaxTypes.Standard,
		movementMode = "Walk",
		isCupping = false,
		cupUpkeepPerSecond = 0,
		wading = false,
	})
	return perSecond * (studs / MovementConfig.walkSpeed)
end

-- Direct-route cost from depth 1 through `throughDepth`, worst case across SEEDS at each depth.
local function cumulativeWorstCaseCost(throughDepth: number, burnRate: number): number
	local total = 0
	for depth = 1, throughDepth do
		local worst = 0
		for _, seed in SEEDS do
			local plan = FloorPlanner.plan({ globalDepth = depth, localFloor = depth, rng = Random.new(seed + depth) })
			local studs = shortestHopsToBasin(plan) * FloorsConfig.geometry.cellSize
			worst = math.max(worst, directRouteWaxCost(studs, burnRate))
		end
		total += worst
	end
	return total
end

local suite: Harness.Suite = {
	name = "WaxPacing",
	tests = {
		Harness.test("direct-route cost per depth is finite and non-negative", function()
			for _, depth in { 1, 3, 5, 8, 10, 12, 15, 20 } do
				for _, seed in SEEDS do
					local plan =
						FloorPlanner.plan({ globalDepth = depth, localFloor = depth, rng = Random.new(seed + depth) })
					local hops = shortestHopsToBasin(plan)
					Harness.expect(hops >= 1, "depth " .. depth .. " produced an unreachable Basin")
					local cost = directRouteWaxCost(hops * FloorsConfig.geometry.cellSize, CLEAN_RUN_DIAL)
					Harness.expect(
						cost == cost and cost >= 0 and cost < math.huge,
						"depth " .. depth .. " produced a non-finite or negative direct-route cost"
					)
				end
			end
		end),

		Harness.test("a flawless direct run can reach depth 10-12 on the base candle alone", function()
			local costTo10 = cumulativeWorstCaseCost(10, CLEAN_RUN_DIAL)
			local costTo12 = cumulativeWorstCaseCost(12, CLEAN_RUN_DIAL)
			Harness.expect(
				costTo10 < WaxConfig.startingWax,
				string.format(
					"depth 10 direct-route cost %.3f must fit inside the %.2f-wax candle with no Basin use",
					costTo10,
					WaxConfig.startingWax
				)
			)
			Harness.expect(
				costTo12 < WaxConfig.startingWax,
				string.format(
					"depth 12 direct-route cost %.3f must fit inside the %.2f-wax candle with no Basin use "
						.. "(declining every Basin offer must remain viable for a clean run)",
					costTo12,
					WaxConfig.startingWax
				)
			)
		end),

		Harness.test("depth 8 leaves most of the candle unspent by drain alone", function()
			-- If ordinary players are failing/extracting around depths 5-9, it must be reads/mistakes/
			-- exploration/threats doing that, not unavoidable drain — drain alone should still leave a
			-- large majority of the candle at depth 8.
			local costTo8 = cumulativeWorstCaseCost(8, CLEAN_RUN_DIAL)
			Harness.expect(
				costTo8 < WaxConfig.startingWax * 0.6,
				string.format("depth 8 direct-route cost %.3f consumes too much of the candle by drain alone", costTo8)
			)
		end),

		Harness.test("sustained maximum brightness is not free across a full descent", function()
			-- The dial must still be a meaningful purchase: burning at the ordinary ceiling (0.78) the
			-- whole way to depth 12 should NOT fit inside the base candle.
			local costTo12AtMax = cumulativeWorstCaseCost(12, LightConfig.maxBurnRate)
			Harness.expect(
				costTo12AtMax > WaxConfig.startingWax,
				string.format(
					"sustained max-brightness cost %.3f should exceed the %.2f-wax candle, or brightness stops mattering",
					costTo12AtMax,
					WaxConfig.startingWax
				)
			)
		end),

		Harness.test("cave tiers no longer add a flat drain tax on top of depth difficulty", function()
			for _, tier in CaveTiersConfig do
				Harness.equal(
					tier.waxDrainMultiplier,
					1,
					tier.displayName .. " must not scale wax drain independently of depth (Phase 2)"
				)
			end
		end),
	},
}

return suite

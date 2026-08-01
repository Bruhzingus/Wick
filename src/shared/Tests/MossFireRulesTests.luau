--!strict
-- Moss flammable vegetation: what may light it, how fire moves through it, and what it costs.
--
-- The ignition tests are written as "how long does this take" rather than "what rate does this
-- return", because seconds-to-ignite is what the design states and what a player experiences. A rate
-- assertion would pass a curve that felt completely wrong.

local Harness = require(script.Parent.Harness)
local MossFireRules = require(script.Parent.Parent.Logic.MossFireRules)
local MossFireConfig = require(script.Parent.Parent.Config.MossFire)
local LightConfig = require(script.Parent.Parent.Config.Light)
local WaxAccounting = require(script.Parent.Parent.Logic.WaxAccounting)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)

local MAX_BURN = LightConfig.maxBurnRate

-- Seconds of continuous exposure at this burn rate before a cluster catches. Simulated in small
-- steps through the real `stepIgnition`, so this measures the shipped path rather than 1/rate.
local function secondsToIgnite(burnRate: number, isCupping: boolean?): number
	local progress = 0
	local elapsed = 0
	local step = 1 / 240
	while progress < 1 and elapsed < 60 do
		local rate = MossFireRules.flameProgressPerSecond(true, isCupping == true, burnRate)
		progress = MossFireRules.stepIgnition(progress, step, rate, false)
		elapsed += step
	end
	return elapsed
end

local suite: Harness.Suite = {
	name = "MossFireRules",
	tests = {
		Harness.test("only Moss grows anything that burns", function()
			Harness.expect(MossFireRules.isEligibleFamily("MOSS"), "Moss must carry flammable vegetation")
			Harness.expect(not MossFireRules.isEligibleFamily("STONE"), "Stone is bare wet rock")
			Harness.expect(not MossFireRules.isEligibleFamily("ICE"), "nothing grows in Ice")
			-- An unknown family resolves to the free one, which does not burn — so a bad id can never
			-- accidentally make a cave flammable.
			Harness.expect(not MossFireRules.isEligibleFamily("NOPE"), "an unknown family must not burn")
			Harness.expect(not MossFireRules.isEligibleFamily(nil), "an absent family must not burn")
			-- And the config flag is the ONLY thing that decides it.
			for _, profile in CaveFamilyRules.list() do
				Harness.equal(
					MossFireRules.isEligibleFamily(profile.id),
					profile.environment.flammableVegetation,
					profile.id .. " eligibility must follow its own config flag"
				)
			end
		end),

		Harness.test("vegetation stays uncommon at every depth and never certain", function()
			local previous = 0
			for _, depth in { 1, 5, 6, 10, 11, 15, 16, 40, 400 } do
				local chance = MossFireRules.chanceForDepth(depth)
				Harness.expect(chance > 0, "an eligible room must have some chance at depth " .. depth)
				Harness.expect(chance <= 0.25, "vegetation must stay uncommon at depth " .. depth)
				Harness.expect(chance >= previous, "the chance must not fall with depth")
				previous = chance
			end
			-- Hostile depths resolve rather than erroring.
			for _, depth in { 0, -4, 0 / 0 } do
				Harness.expect(MossFireRules.chanceForDepth(depth) >= 0, "hostile depth " .. tostring(depth))
			end
		end),

		--------------------------------------------------------------------------------
		-- Ignition
		--------------------------------------------------------------------------------

		Harness.test("low, medium and high exposure ignite at their authored times", function()
			local ignition = MossFireConfig.ignition
			local low = MAX_BURN * ignition.lowBurnFraction
			local high = MAX_BURN * ignition.highBurnFraction
			local medium = (low + high) / 2
			Harness.near(secondsToIgnite(low), ignition.lowExposureSeconds, 0.05, "low burn")
			Harness.near(secondsToIgnite(medium), ignition.mediumExposureSeconds, 0.05, "medium burn")
			Harness.near(secondsToIgnite(high), ignition.highExposureSeconds, 0.05, "high burn")
			-- CONTINUOUS, not three cases: a dial held a little higher must do a little more.
			local previous = math.huge
			for step = 0, 20 do
				local burn = low + (high - low) * (step / 20)
				local seconds = secondsToIgnite(burn)
				Harness.expect(seconds <= previous + 1e-6, "holding the dial higher must never ignite slower")
				previous = seconds
			end
		end),

		Harness.test("a cupped flame and an unlit candle contribute exactly zero", function()
			-- CUP is a near-dark ember whatever the dial underneath it reads, and SNUFF is the absence
			-- of a flame. Neither is "slow"; both are nothing.
			Harness.equal(MossFireRules.flameProgressPerSecond(true, true, MAX_BURN), 0, "cupped at full burn")
			Harness.equal(MossFireRules.flameProgressPerSecond(false, false, MAX_BURN), 0, "unlit at full burn")
			Harness.expect(not MossFireRules.flameIgnites(true, true, MAX_BURN), "cupping must never ignite")
			Harness.expect(not MossFireRules.flameIgnites(false, false, MAX_BURN), "an unlit candle must never ignite")

			-- And a flame below the low threshold is genuinely safe to carry past dry growth.
			local belowThreshold = MAX_BURN * MossFireConfig.ignition.lowBurnFraction * 0.9
			Harness.equal(MossFireRules.flameProgressPerSecond(true, false, belowThreshold), 0, "below threshold")

			-- Held forever, a cupped flame still never gets there.
			local progress = 0
			for _ = 1, 6_000 do
				progress = MossFireRules.stepIgnition(
					progress,
					1 / 60,
					MossFireRules.flameProgressPerSecond(true, true, MAX_BURN),
					false
				)
			end
			Harness.equal(progress, 0, "a hundred seconds of cupped flame must light nothing")
		end),

		Harness.test("a Flare ignites immediately, from nothing", function()
			Harness.equal(MossFireRules.stepIgnition(0, 0, 0, true), 1, "a Flare needs no accumulated exposure")
			Harness.expect(MossFireRules.hasCaught(MossFireRules.stepIgnition(0, 1 / 60, 0, true)), "flare catches")
		end),

		Harness.test("a burning Decoy contributes at its authored intensity", function()
			local decoyRate = MossFireRules.decoyProgressPerSecond()
			Harness.expect(decoyRate > 0, "a burning Decoy must be able to light dry growth")
			Harness.near(
				decoyRate,
				MossFireRules.intensityProgressPerSecond(MossFireConfig.ignition.decoyIntensity),
				1e-9
			)
			-- Medium by default, so a Decoy sits between a low flame and a high one rather than
			-- outperforming a fully open candle.
			local low = MossFireRules.intensityProgressPerSecond("Low")
			local high = MossFireRules.intensityProgressPerSecond("High")
			Harness.expect(decoyRate >= low and decoyRate <= high, "a Decoy must sit inside the authored band")
		end),

		Harness.test("ignition progress decays once every source leaves", function()
			-- A player who nearly lit something and walked away has not armed a trap for whoever comes
			-- through next.
			-- A third of a second at full burn: real progress, well short of the ~0.75s it takes to
			-- catch, which is exactly the state a player who thought better of it leaves behind.
			local progress =
				MossFireRules.stepIgnition(0, 0.3, MossFireRules.flameProgressPerSecond(true, false, MAX_BURN), false)
			Harness.expect(progress > 0 and progress < 1, "fixture must be partly lit")
			local decayed = MossFireRules.stepIgnition(progress, 0.2, 0, false)
			Harness.expect(decayed < progress, "progress must decay with no source in range")
			-- All the way back to nothing, and never below it.
			local settled = decayed
			for _ = 1, 200 do
				settled = MossFireRules.stepIgnition(settled, 1 / 10, 0, false)
			end
			Harness.equal(settled, 0, "progress must settle at zero, not go negative")
		end),

		Harness.test("progress is clamped and survives hostile inputs", function()
			Harness.equal(MossFireRules.stepIgnition(5, 1, 10, false), 1, "progress must never exceed 1")
			Harness.equal(MossFireRules.stepIgnition(-5, 1, 0, false), 0, "progress must never go below 0")
			Harness.equal(MossFireRules.stepIgnition(0 / 0, 1, 0, false), 0, "NaN progress resets rather than spreads")
			Harness.equal(MossFireRules.stepIgnition(0.5, -10, 0, false), 0.5, "a negative step changes nothing")
			Harness.equal(MossFireRules.stepIgnition(0.5, 0 / 0, 1, false), 0.5, "a NaN step changes nothing")
		end),

		--------------------------------------------------------------------------------
		-- Spread
		--------------------------------------------------------------------------------

		Harness.test("fire only ever moves along connected nodes", function()
			-- Two clusters' worth of nodes with no edge between them. Fire started in one must never
			-- reach the other however long it runs — which is the same property that stops it reaching
			-- a wet wall or unrelated dressing.
			local edges = { { a = 1, b = 2 }, { a = 2, b = 3 }, { a = 4, b = 5 } }
			Harness.equal(#MossFireRules.neighbours(edges, 1), 1)
			Harness.equal(#MossFireRules.neighbours(edges, 2), 2)
			Harness.equal(#MossFireRules.neighbours(edges, 5), 1)
			Harness.equal(#MossFireRules.neighbours(edges, 99), 0, "an unknown node has no neighbours")

			-- Walked here rather than through the module's own connectivity helper.
			local burning: { [number]: boolean } = { [1] = true }
			for _ = 1, 20 do
				for index in table.clone(burning) do
					for _, neighbour in MossFireRules.neighbours(edges, index) do
						burning[neighbour] = true
					end
				end
			end
			Harness.expect(burning[3] == true, "fire must reach the far end of its own growth")
			Harness.isNil(burning[4], "fire must never jump to disconnected growth")
			Harness.isNil(burning[5], "fire must never jump to disconnected growth")
		end),

		Harness.test("a planned cluster graph is one connected piece", function()
			Harness.expect(MossFireRules.isConnectedGraph(1, {}), "a single node is trivially connected")
			Harness.expect(
				MossFireRules.isConnectedGraph(3, { { a = 1, b = 2 }, { a = 2, b = 3 } }),
				"a chain is connected"
			)
			Harness.expect(
				not MossFireRules.isConnectedGraph(5, { { a = 1, b = 2 }, { a = 2, b = 3 }, { a = 4, b = 5 } }),
				"two components are not one cluster"
			)
			Harness.expect(not MossFireRules.isConnectedGraph(0, {}), "an empty cluster is not a cluster")
			Harness.expect(not MossFireRules.isConnectedGraph(2, {}), "unlinked nodes are not connected")
		end),

		Harness.test("quick-burning strands carry fire faster and die sooner", function()
			local quick: MossFireRules.VegetationKind? = nil
			local ordinary: MossFireRules.VegetationKind? = nil
			for _, kind in MossFireConfig.kinds do
				if kind.quick and quick == nil then
					quick = kind
				elseif not kind.quick and ordinary == nil then
					ordinary = kind
				end
			end
			Harness.expect(quick ~= nil and ordinary ~= nil, "the config must ship both kinds")
			local quickKind = quick :: MossFireRules.VegetationKind
			local ordinaryKind = ordinary :: MossFireRules.VegetationKind

			Harness.expect(
				MossFireRules.spreadInterval(quickKind) < MossFireRules.spreadInterval(ordinaryKind),
				"a strand must carry fire faster than ordinary growth"
			)
			Harness.expect(
				MossFireRules.burnSeconds(quickKind, 1) < MossFireRules.burnSeconds(ordinaryKind, 0),
				"a strand must burn out before ordinary growth does"
			)
			-- Burn duration spans its authored band and never leaves it.
			for _, roll in { -1, 0, 0.5, 1, 2, 0 / 0 } do
				local seconds = MossFireRules.burnSeconds(ordinaryKind, roll)
				Harness.expect(
					seconds >= ordinaryKind.burnSecondsMin and seconds <= ordinaryKind.burnSecondsMax,
					"burn duration left its band for roll " .. tostring(roll)
				)
			end
		end),

		Harness.test("an unknown vegetation kind resolves to ordinary growth, never to a strand", function()
			-- A floor built before a config change must still be burnable, and an unrecognised node
			-- must not become the fastest thing in the room.
			for _, id in { nil, "", "NotAKind", "42" } do
				local kind = MossFireRules.resolveKind(id :: any)
				Harness.expect(not kind.quick, "an unknown kind must never resolve to a quick strand")
			end
			Harness.isNil(MossFireRules.kindById("NotAKind"))
			Harness.isNil(MossFireRules.kindById(nil))
			-- Selection is a pure function of its roll and always returns a real kind.
			for _, roll in { -1, 0, 0.5, 0.999999, 2, 0 / 0 } do
				local kind = MossFireRules.selectKind(roll)
				Harness.expect(MossFireRules.kindById(kind.id) ~= nil, "selectKind returned an unknown kind")
			end
		end),

		--------------------------------------------------------------------------------
		-- Light and heat
		--------------------------------------------------------------------------------

		Harness.test("fire light rises, holds and fades, and is never a Flare", function()
			local duration = 10
			Harness.equal(MossFireRules.lightFraction(0, duration), 0, "a fire starts dark")
			Harness.expect(MossFireRules.lightFraction(duration / 2, duration) > 0.9, "it holds through its life")
			Harness.equal(MossFireRules.lightFraction(duration, duration), 0, "and it goes out")
			Harness.equal(MossFireRules.lightFraction(5, 0), 0, "a zero-length burn emits nothing")

			-- Ordinary environmental light: comfortably below a Flare's burst, so a fire can never
			-- become a better Flare than the Flare.
			local peak = MossFireRules.lightIntensity(1)
			Harness.expect(peak > 0, "a burning cluster must actually light the room")
			Harness.expect(
				peak < (require(script.Parent.Parent.Config.Tools).Flare.burstIntensity :: number),
				"burning vegetation must never outshine a Flare"
			)
			Harness.equal(MossFireRules.lightIntensity(0), 0)
			Harness.equal(MossFireRules.lightRange(0), 0)
		end),

		Harness.test("heat costs wax by distance, and one cluster is capped", function()
			local heat = MossFireConfig.heat
			Harness.equal(MossFireRules.heatPerSecond(0), heat.nearWaxPerSecond, "at the fire")
			Harness.equal(MossFireRules.heatPerSecond(heat.nearRadius), heat.nearWaxPerSecond, "at the near edge")
			Harness.equal(MossFireRules.heatPerSecond(heat.nearRadius + 0.01), heat.farWaxPerSecond, "just outside")
			Harness.equal(MossFireRules.heatPerSecond(heat.farRadius), heat.farWaxPerSecond, "at the far edge")
			Harness.equal(MossFireRules.heatPerSecond(heat.farRadius + 0.01), 0, "outside the fire costs nothing")
			Harness.equal(MossFireRules.heatPerSecond(-1), 0, "a nonsense distance costs nothing")
			Harness.equal(MossFireRules.heatPerSecond(0 / 0), 0, "a NaN distance costs nothing")

			-- Standing in the middle of a big cluster is a bad decision, not an instant death.
			local hugging = { 0, 0, 0, 0, 0, 0, 0, 0 }
			Harness.equal(
				MossFireRules.clusterHeatPerSecond(hugging),
				heat.clusterCapPerSecond,
				"one cluster must never exceed its cap"
			)
			Harness.equal(MossFireRules.clusterHeatPerSecond({}), 0, "a cluster with nothing alight costs nothing")
			Harness.expect(
				heat.clusterCapPerSecond < require(script.Parent.Parent.Config.Wax).startingWax,
				"a full second in a fire must not be a whole candle"
			)
		end),

		Harness.test("environmental fire spends wax under one centralized, recognised reason", function()
			-- If this reason were not in the accounting vocabulary it would silently land in "Other",
			-- and the run summary could never say what the fire cost.
			local reason = MossFireRules.waxReason()
			Harness.expect(WaxAccounting.isSource(reason), "the fire's wax reason must be a real accounting source")
			Harness.equal(WaxAccounting.normalizeSource(reason), reason, "it must not normalize away")
			Harness.equal(reason, "EnvironmentalFire", "the reason is a stable, centralized string")
		end),

		--------------------------------------------------------------------------------
		-- Limits
		--------------------------------------------------------------------------------

		Harness.test("the per-room and per-floor caps are real, whole, and small", function()
			Harness.equal(MossFireRules.maxPerRoom(), 1, "one cluster per room, always")
			local floorCap = MossFireRules.maxActivePerFloor()
			Harness.expect(floorCap >= 1, "at least one fire must be possible")
			Harness.expect(floorCap <= 8, "a floor must never become a bonfire")
			Harness.equal(floorCap % 1, 0, "the cap must be a whole number of fires")
		end),
	},
}

return suite

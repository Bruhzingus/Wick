--!strict

local Harness = require(script.Parent.Harness)
local WaxDrain = require(script.Parent.Parent.Logic.WaxDrain)
local WaxConfig = require(script.Parent.Parent.Config.Wax)
local WaxTypes = require(script.Parent.Parent.Config.WaxTypes)
local MovementConfig = require(script.Parent.Parent.Config.Movement)

local standard = WaxTypes.Standard
local baseBurn = WaxConfig.idleDrainPerSecond
	+ WaxConfig.burnDrainPerSecond * WaxConfig.initialBurnRate ^ WaxConfig.burnDrainExponent

local suite: Harness.Suite = {
	name = "WaxDrain",
	tests = {
		Harness.test("per-second drain is assembled from config inputs", function()
			local waterDegrade =
				require(script.Parent.Parent.Config.Hazards).definitions.Water.degradePerSecond :: number
			local cases: {
				{
					name: string,
					context: WaxDrain.DrainContext,
					expected: number,
				}
			} =
				{
					{
						name = "unlit idle",
						context = {
							isLit = false,
							burnRate = WaxConfig.initialBurnRate,
							waxType = standard,
							movementMode = "Idle",
							isCupping = false,
							cupUpkeepPerSecond = 0,
							wading = false,
						},
						expected = 0,
					},
					{
						name = "lit idle",
						context = {
							isLit = true,
							burnRate = WaxConfig.initialBurnRate,
							waxType = standard,
							movementMode = "Idle",
							isCupping = false,
							cupUpkeepPerSecond = 0,
							wading = false,
						},
						expected = baseBurn * standard.drainMultiplier,
					},
					{
						name = "running",
						context = {
							isLit = true,
							burnRate = WaxConfig.initialBurnRate,
							waxType = standard,
							movementMode = "Run",
							isCupping = false,
							cupUpkeepPerSecond = 0,
							wading = false,
						},
						expected = baseBurn * standard.drainMultiplier
							+ MovementConfig.runWaxPerSecond * WaxConfig.movementCostMultiplier,
					},
					{
						name = "cup upkeep",
						context = {
							isLit = true,
							burnRate = WaxConfig.initialBurnRate,
							waxType = standard,
							movementMode = "Walk",
							isCupping = true,
							cupUpkeepPerSecond = 0.123,
							wading = false,
						},
						expected = baseBurn * standard.drainMultiplier
							+ MovementConfig.walkWaxPerSecond * WaxConfig.movementCostMultiplier
							+ 0.123,
					},
					{
						name = "water degrades an unlit candle",
						context = {
							isLit = false,
							burnRate = WaxConfig.initialBurnRate,
							waxType = standard,
							movementMode = "Run",
							isCupping = false,
							cupUpkeepPerSecond = 0,
							wading = true,
						},
						expected = waterDegrade,
					},
				}

			for _, case in cases do
				Harness.near(WaxDrain.perSecond(case.context), case.expected, nil, "wrong drain for " .. case.name)
			end
		end),

		Harness.test("wax type hunger scales only the burn component", function()
			local tallow = WaxTypes.Tallow
			local context: WaxDrain.DrainContext = {
				isLit = true,
				burnRate = WaxConfig.initialBurnRate,
				waxType = tallow,
				movementMode = "Walk",
				isCupping = false,
				cupUpkeepPerSecond = 0,
				wading = false,
			}
			local expected = baseBurn * tallow.drainMultiplier
				+ MovementConfig.walkWaxPerSecond * WaxConfig.movementCostMultiplier
			Harness.near(WaxDrain.perSecond(context), expected)
		end),

		Harness.test("apply clamps to the live wax bounds and reports burnout", function()
			local reduced, reducedOut = WaxDrain.apply({ current = 0.6, max = 0.8 }, 0.2)
			Harness.near(reduced.current, 0.4)
			Harness.near(reduced.max, 0.8)
			Harness.equal(reducedOut, false)

			local empty, burnedOut = WaxDrain.apply({ current = 0.1, max = 0.8 }, 0.2)
			Harness.near(empty.current, 0)
			Harness.equal(burnedOut, true)

			local capped, cappedOut = WaxDrain.apply({ current = 0.6, max = 0.8 }, -1)
			Harness.near(capped.current, 0.8)
			Harness.equal(cappedOut, false)
		end),

		Harness.test("measured-speed thresholds classify boundary values", function()
			local walkThreshold = MovementConfig.walkSpeed * MovementConfig.drainThresholds.walkAtFractionOfWalkSpeed
			local runThreshold = MovementConfig.runSpeed * MovementConfig.drainThresholds.runAtFractionOfRunSpeed
			local epsilon = 1e-4

			Harness.equal(WaxDrain.movementModeForSpeed(0), "Idle")
			Harness.equal(WaxDrain.movementModeForSpeed(walkThreshold - epsilon), "Idle")
			Harness.equal(WaxDrain.movementModeForSpeed(walkThreshold), "Walk")
			Harness.equal(WaxDrain.movementModeForSpeed(runThreshold - epsilon), "Walk")
			Harness.equal(WaxDrain.movementModeForSpeed(runThreshold), "Run")
		end),
	},
}

return suite

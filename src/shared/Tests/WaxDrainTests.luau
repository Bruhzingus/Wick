--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local WaxDrain = require(script.Parent.Parent.Logic.WaxDrain)
local WaxConfig = require(script.Parent.Parent.Config.Wax)
local CandleModifiers = require(script.Parent.Parent.Logic.CandleModifiers)
local MovementConfig = require(script.Parent.Parent.Config.Movement)

local neutral = CandleModifiers.neutralProfile()
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
							candle = neutral,
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
							candle = neutral,
							movementMode = "Idle",
							isCupping = false,
							cupUpkeepPerSecond = 0,
							wading = false,
						},
						expected = baseBurn * neutral.drainMultiplier,
					},
					{
						name = "running",
						context = {
							isLit = true,
							burnRate = WaxConfig.initialBurnRate,
							candle = neutral,
							movementMode = "Run",
							isCupping = false,
							cupUpkeepPerSecond = 0,
							wading = false,
						},
						expected = baseBurn * neutral.drainMultiplier
							+ MovementConfig.runWaxPerSecond * WaxConfig.movementCostMultiplier,
					},
					{
						name = "cup upkeep",
						context = {
							isLit = true,
							burnRate = WaxConfig.initialBurnRate,
							candle = neutral,
							movementMode = "Walk",
							isCupping = true,
							cupUpkeepPerSecond = 0.123,
							wading = false,
						},
						expected = baseBurn * neutral.drainMultiplier
							+ MovementConfig.walkWaxPerSecond * WaxConfig.movementCostMultiplier
							+ 0.123,
					},
					{
						name = "water degrades an unlit candle",
						context = {
							isLit = false,
							burnRate = WaxConfig.initialBurnRate,
							candle = neutral,
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

		-- THE LIFEWAX BOUNDARY. A candle's own hunger scales the burn component and NOTHING else:
		-- collecting LifeWax must never make wading, walking or cupping cheaper, because those are
		-- pressures the player answers with decisions rather than with items.
		Harness.test("candle hunger scales only the burn component", function()
			local lifeWaxed: Types.CandleProfile = {
				drainMultiplier = 1 - CandleModifiers.lifeWaxDrainReduction(4),
				brightnessMultiplier = 1,
				attractsDrawn = true,
			}
			Harness.expect(lifeWaxed.drainMultiplier < 1, "four LifeWax stacks must reduce the burn drain")

			local context: WaxDrain.DrainContext = {
				isLit = true,
				burnRate = WaxConfig.initialBurnRate,
				candle = lifeWaxed,
				movementMode = "Walk",
				isCupping = true,
				cupUpkeepPerSecond = 0.2,
				wading = true,
			}
			local water = require(script.Parent.Parent.Config.Hazards).definitions.Water.degradePerSecond :: number
			local expected = baseBurn * lifeWaxed.drainMultiplier
				+ MovementConfig.walkWaxPerSecond * WaxConfig.movementCostMultiplier
				+ 0.2
				+ water
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

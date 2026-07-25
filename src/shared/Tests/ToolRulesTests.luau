--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local ToolRules = require(script.Parent.Parent.Logic.ToolRules)
local SacrificeRules = require(script.Parent.Parent.Logic.SacrificeRules)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)
local DeathConfig = require(script.Parent.Parent.Config.Death)
local LightConfig = require(script.Parent.Parent.Config.Light)
local WaxTypesConfig = require(script.Parent.Parent.Config.WaxTypes)

local NOW = 100

local function freshState(): Types.PlayerRunState
	return {
		playerId = 1,
		wax = { current = 1, max = 1 },
		burnRate = 0.5,
		waxTypeId = "Standard",
		isLit = true,
		unlitByChoice = false,
		litChangedAt = 0,
		snuffedAt = nil,
		isCupping = false,
		flareEndsAt = 0,
		lightSuppressedUntil = 0,
		lightSuppressionMultiplier = 1,
		position = Vector3.zero,
		currentHeight = 4,
		depth = 1,
		alive = true,
		finished = false,
		movementMode = "Idle",
		sprinting = false,
		slidingUntil = 0,
		lastDodgeAt = 0,
		lastSlideAt = 0,
		nextToolUse = {},
		freeToolCharges = {},
		sacrifices = {},
		modifiers = SacrificeRules.defaultModifiers(),
		nextBasinPenalty = 1,
		basinUsedAtDepth = {},
	}
end

local suite: Harness.Suite = {
	name = "ToolRules",
	tests = {
		Harness.test("terminal and involuntary-snuff states reject tool requests first", function()
			local cases = {
				{
					name = "dead",
					mutate = function(state: Types.PlayerRunState)
						state.alive = false
					end,
				},
				{
					name = "finished",
					mutate = function(state: Types.PlayerRunState)
						state.finished = true
					end,
				},
				{
					name = "snuffed",
					mutate = function(state: Types.PlayerRunState)
						state.snuffedAt = NOW
					end,
				},
			}
			for _, case in cases do
				local state = freshState()
				case.mutate(state)
				local allowed, denial = ToolRules.validate(state, ToolsConfig.Flare, NOW)
				Harness.equal(allowed, false, case.name .. " should reject")
				Harness.equal(denial, "Dead", case.name .. " should use the terminal denial")
			end
		end),

		Harness.test("sacrifices and cooldowns are enforced at their exact boundaries", function()
			local sacrificed = freshState()
			sacrificed.modifiers.lostTools.Flare = true
			local sacrificedAllowed, sacrificedDenial = ToolRules.validate(sacrificed, ToolsConfig.Flare, NOW)
			Harness.equal(sacrificedAllowed, false)
			Harness.equal(sacrificedDenial, "Sacrificed")

			local cooling = freshState()
			cooling.nextToolUse.Flare = NOW + 0.01
			local coolingAllowed, coolingDenial = ToolRules.validate(cooling, ToolsConfig.Flare, NOW)
			Harness.equal(coolingAllowed, false)
			Harness.equal(coolingDenial, "Cooldown")

			cooling.nextToolUse.Flare = NOW
			local boundaryAllowed, boundaryDenial = ToolRules.validate(cooling, ToolsConfig.Flare, NOW)
			Harness.equal(boundaryAllowed, true)
			Harness.isNil(boundaryDenial)
		end),

		Harness.test("lit requirements and voluntary self-relight rules are distinct", function()
			local unlit = freshState()
			unlit.isLit = false
			local flareAllowed, flareDenial = ToolRules.validate(unlit, ToolsConfig.Flare, NOW)
			Harness.equal(flareAllowed, false)
			Harness.equal(flareDenial, "NotLit")

			local involuntary = freshState()
			involuntary.isLit = false
			involuntary.unlitByChoice = false
			local involuntaryAllowed, involuntaryDenial = ToolRules.validate(involuntary, ToolsConfig.Snuff, NOW)
			Harness.equal(involuntaryAllowed, false)
			Harness.equal(involuntaryDenial, "CannotRelight")

			local voluntary = freshState()
			voluntary.isLit = false
			voluntary.unlitByChoice = true
			voluntary.litChangedAt = NOW - DeathConfig.selfRelightDelaySeconds + 0.01
			local earlyAllowed, earlyDenial = ToolRules.validate(voluntary, ToolsConfig.Snuff, NOW)
			Harness.equal(earlyAllowed, false)
			Harness.equal(earlyDenial, "CannotRelight")

			voluntary.litChangedAt = NOW - DeathConfig.selfRelightDelaySeconds
			local readyAllowed, readyDenial = ToolRules.validate(voluntary, ToolsConfig.Snuff, NOW)
			Harness.equal(readyAllowed, true)
			Harness.isNil(readyDenial)
		end),

		Harness.test("instant tools require strictly more wax than their cost", function()
			local state = freshState()
			state.wax.current = ToolsConfig.Cast.waxCost
			local equalAllowed, equalDenial = ToolRules.validate(state, ToolsConfig.Cast, NOW)
			Harness.equal(equalAllowed, false)
			Harness.equal(equalDenial, "NotEnoughWax")

			state.wax.current = ToolsConfig.Cast.waxCost + 1e-6
			local aboveAllowed, aboveDenial = ToolRules.validate(state, ToolsConfig.Cast, NOW)
			Harness.equal(aboveAllowed, true)
			Harness.isNil(aboveDenial)
		end),

		Harness.test("loot charges bypass payment only, not other activation rules", function()
			local state = freshState()
			state.wax.current = ToolsConfig.Flare.waxCost
			state.freeToolCharges.Flare = 1
			Harness.equal(ToolRules.hasFreeActivation(state, ToolsConfig.Flare), true)

			local chargedAllowed, chargedDenial = ToolRules.validate(state, ToolsConfig.Flare, NOW)
			Harness.equal(chargedAllowed, true)
			Harness.isNil(chargedDenial)

			state.nextToolUse.Flare = NOW + 1
			local coolingAllowed, coolingDenial = ToolRules.validate(state, ToolsConfig.Flare, NOW)
			Harness.equal(coolingAllowed, false)
			Harness.equal(coolingDenial, "Cooldown")

			Harness.equal(ToolRules.hasFreeActivation(state, ToolsConfig.Cup), false)
		end),

		Harness.test("Cast resolves horizontal range and ignores client-supplied height", function()
			local origin = Vector3.new(3, 4, 5)
			local castRange = ToolsConfig.Cast.castRange :: number
			local inRange = origin + Vector3.new(castRange / 2, 100, 0)
			Harness.vectorNear(
				ToolRules.castHorizontalPoint(origin, inRange, castRange, nil, 0, 0) or origin,
				Vector3.new(inRange.X, origin.Y, inRange.Z)
			)
			Harness.vectorNear(ToolRules.castHorizontalPoint(origin, origin, castRange, nil, 0, 0) or origin, origin)

			local direction = Vector3.new(1, 2, -3).Unit
			local far = origin + direction * castRange * 10
			local clamped = ToolRules.castHorizontalPoint(origin, far, castRange, nil, 0, 0) or origin
			Harness.near((clamped - origin).Magnitude, castRange)
			Harness.near(clamped.Y, origin.Y)
			local horizontalDirection = Vector3.new(direction.X, 0, direction.Z).Unit
			Harness.vectorNear((clamped - origin).Unit, horizontalDirection)
		end),

		Harness.test("Cast obstruction inset rejects landings that end too close", function()
			local placement = ToolsConfig.Cast.castPlacement
			if placement == nil then
				error("Cast requires placement tuning")
			end
			local origin = Vector3.new(0, 5, 0)
			local aim = Vector3.new(100, -500, 0)
			local castRange = ToolsConfig.Cast.castRange :: number

			local shortened = ToolRules.castHorizontalPoint(
				origin,
				aim,
				castRange,
				10,
				placement.obstructionInset,
				placement.minimumDistance
			)
			if shortened == nil then
				error("a clear nine-stud landing should remain legal")
			end
			Harness.vectorNear(shortened, origin + Vector3.new(10 - placement.obstructionInset, 0, 0))

			Harness.isNil(
				ToolRules.castHorizontalPoint(
					origin,
					aim,
					castRange,
					placement.obstructionInset + placement.minimumDistance - 0.01,
					placement.obstructionInset,
					placement.minimumDistance
				)
			)
			Harness.isNil(
				ToolRules.castHorizontalPoint(
					origin,
					origin,
					castRange,
					nil,
					placement.obstructionInset,
					placement.minimumDistance
				)
			)
		end),

		Harness.test("Cast accepts only upward surfaces within its configured slope", function()
			local placement = ToolsConfig.Cast.castPlacement
			if placement == nil then
				error("Cast requires placement tuning")
			end
			local maximum = placement.maxGroundSlopeDegrees
			local within = math.rad(maximum - 1)
			local beyond = math.rad(maximum + 1)
			Harness.equal(ToolRules.castSurfaceAllowed(Vector3.yAxis, maximum), true)
			Harness.equal(
				ToolRules.castSurfaceAllowed(Vector3.new(math.sin(within), math.cos(within), 0), maximum),
				true
			)
			Harness.equal(
				ToolRules.castSurfaceAllowed(Vector3.new(math.sin(beyond), math.cos(beyond), 0), maximum),
				false
			)
			Harness.equal(ToolRules.castSurfaceAllowed(Vector3.zero, maximum), false)
		end),

		Harness.test("Cast throw arc preserves endpoints and clears rolling ground at its midpoint", function()
			local placement = ToolsConfig.Cast.castPlacement
			if placement == nil then
				error("Cast requires placement tuning")
			end
			local startPoint = Vector3.new(2, 4, 6)
			local endPoint = Vector3.new(22, 4, -4)
			Harness.vectorNear(ToolRules.castArcPoint(startPoint, endPoint, placement.throwArcHeight, 0), startPoint)
			Harness.vectorNear(ToolRules.castArcPoint(startPoint, endPoint, placement.throwArcHeight, 1), endPoint)
			Harness.vectorNear(
				ToolRules.castArcPoint(startPoint, endPoint, placement.throwArcHeight, 0.5),
				startPoint:Lerp(endPoint, 0.5) + Vector3.yAxis * placement.throwArcHeight
			)
		end),

		Harness.test("Cast and Flare presentation strengths stay legible against player light", function()
			local strongestPlayerFlame = 0
			local strongestPlayerBrightness = 0
			for _, waxType in WaxTypesConfig do
				strongestPlayerFlame = math.max(strongestPlayerFlame, waxType.brightnessMultiplier)
				strongestPlayerBrightness =
					math.max(strongestPlayerBrightness, LightConfig.maxBrightness * waxType.brightnessMultiplier)
			end
			Harness.expect(
				(ToolsConfig.Cast.decoyIntensity :: number) > strongestPlayerFlame,
				"the decoy must out-pull the brightest ordinary player flame"
			)
			Harness.expect(
				(ToolsConfig.Flare.burstBrightness :: number) > strongestPlayerBrightness,
				"the rendered Flare burst must look brighter than every wax type at maximum burn"
			)
		end),
	},
}

return suite

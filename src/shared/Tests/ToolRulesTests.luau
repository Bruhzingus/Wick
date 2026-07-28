--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local ToolRules = require(script.Parent.Parent.Logic.ToolRules)
local LightField = require(script.Parent.Parent.Logic.LightField)
local SacrificeRules = require(script.Parent.Parent.Logic.SacrificeRules)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)
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
		nextToolUse = {},
		freeToolCharges = {},
		matchCharges = 0,
		isSoloRun = false,
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

		Harness.test("every tool requires a lit flame; there is no self-relight action", function()
			for toolId, def in ToolsConfig do
				Harness.equal(def.requiresLit, true, toolId .. " should require a lit flame")

				local unlit = freshState()
				unlit.isLit = false
				local allowed, denial = ToolRules.validate(unlit, def, NOW)
				Harness.equal(allowed, false, toolId .. " should reject while unlit")
				Harness.equal(denial, "NotLit", toolId .. " should use the unlit denial")
			end
		end),

		Harness.test("instant tools require strictly more wax than their cost", function()
			local state = freshState()
			state.wax.current = ToolsConfig.Decoy.waxCost
			local equalAllowed, equalDenial = ToolRules.validate(state, ToolsConfig.Decoy, NOW)
			Harness.equal(equalAllowed, false)
			Harness.equal(equalDenial, "NotEnoughWax")

			state.wax.current = ToolsConfig.Decoy.waxCost + 1e-6
			local aboveAllowed, aboveDenial = ToolRules.validate(state, ToolsConfig.Decoy, NOW)
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

		Harness.test("Decoy resolves horizontal range and ignores client-supplied height", function()
			local origin = Vector3.new(3, 4, 5)
			local throwRange = ToolsConfig.Decoy.throwRange :: number
			local inRange = origin + Vector3.new(throwRange / 2, 100, 0)
			Harness.vectorNear(
				ToolRules.throwHorizontalPoint(origin, inRange, throwRange, nil, 0, 0) or origin,
				Vector3.new(inRange.X, origin.Y, inRange.Z)
			)
			Harness.vectorNear(ToolRules.throwHorizontalPoint(origin, origin, throwRange, nil, 0, 0) or origin, origin)

			local direction = Vector3.new(1, 2, -3).Unit
			local far = origin + direction * throwRange * 10
			local clamped = ToolRules.throwHorizontalPoint(origin, far, throwRange, nil, 0, 0) or origin
			Harness.near((clamped - origin).Magnitude, throwRange)
			Harness.near(clamped.Y, origin.Y)
			local horizontalDirection = Vector3.new(direction.X, 0, direction.Z).Unit
			Harness.vectorNear((clamped - origin).Unit, horizontalDirection)
		end),

		Harness.test("Decoy obstruction inset rejects landings that end too close", function()
			local placement = ToolsConfig.Decoy.throwPlacement
			if placement == nil then
				error("Decoy requires placement tuning")
			end
			local origin = Vector3.new(0, 5, 0)
			local aim = Vector3.new(100, -500, 0)
			local throwRange = ToolsConfig.Decoy.throwRange :: number

			local shortened = ToolRules.throwHorizontalPoint(
				origin,
				aim,
				throwRange,
				10,
				placement.obstructionInset,
				placement.minimumDistance
			)
			if shortened == nil then
				error("a clear nine-stud landing should remain legal")
			end
			Harness.vectorNear(shortened, origin + Vector3.new(10 - placement.obstructionInset, 0, 0))

			Harness.isNil(
				ToolRules.throwHorizontalPoint(
					origin,
					aim,
					throwRange,
					placement.obstructionInset + placement.minimumDistance - 0.01,
					placement.obstructionInset,
					placement.minimumDistance
				)
			)
			Harness.isNil(
				ToolRules.throwHorizontalPoint(
					origin,
					origin,
					throwRange,
					nil,
					placement.obstructionInset,
					placement.minimumDistance
				)
			)
		end),

		Harness.test("Decoy accepts only upward surfaces within its configured slope", function()
			local placement = ToolsConfig.Decoy.throwPlacement
			if placement == nil then
				error("Decoy requires placement tuning")
			end
			local maximum = placement.maxGroundSlopeDegrees
			local within = math.rad(maximum - 1)
			local beyond = math.rad(maximum + 1)
			Harness.equal(ToolRules.decoySurfaceAllowed(Vector3.yAxis, maximum), true)
			Harness.equal(
				ToolRules.decoySurfaceAllowed(Vector3.new(math.sin(within), math.cos(within), 0), maximum),
				true
			)
			Harness.equal(
				ToolRules.decoySurfaceAllowed(Vector3.new(math.sin(beyond), math.cos(beyond), 0), maximum),
				false
			)
			Harness.equal(ToolRules.decoySurfaceAllowed(Vector3.zero, maximum), false)
		end),

		Harness.test("Decoy throw arc preserves endpoints and clears rolling ground at its midpoint", function()
			local placement = ToolsConfig.Decoy.throwPlacement
			if placement == nil then
				error("Decoy requires placement tuning")
			end
			local startPoint = Vector3.new(2, 4, 6)
			local endPoint = Vector3.new(22, 4, -4)
			Harness.vectorNear(ToolRules.throwArcPoint(startPoint, endPoint, placement.throwArcHeight, 0), startPoint)
			Harness.vectorNear(ToolRules.throwArcPoint(startPoint, endPoint, placement.throwArcHeight, 1), endPoint)
			Harness.vectorNear(
				ToolRules.throwArcPoint(startPoint, endPoint, placement.throwArcHeight, 0.5),
				startPoint:Lerp(endPoint, 0.5) + Vector3.yAxis * placement.throwArcHeight
			)
		end),

		Harness.test("Decoy and Flare presentation strengths stay legible against player light", function()
			local strongestPlayerFlame = 0
			local strongestPlayerBrightness = 0
			for _, waxType in WaxTypesConfig do
				strongestPlayerFlame =
					math.max(strongestPlayerFlame, LightConfig.maxIntensity * waxType.brightnessMultiplier)
				strongestPlayerBrightness =
					math.max(strongestPlayerBrightness, LightConfig.maxBrightness * waxType.brightnessMultiplier)
			end
			Harness.expect(
				(ToolsConfig.Decoy.decoyIntensity :: number) > strongestPlayerFlame,
				"the decoy must out-pull the brightest ordinary player flame"
			)
			Harness.expect(
				(ToolsConfig.Flare.burstBrightness :: number) > strongestPlayerBrightness,
				"the rendered Flare burst must look brighter than every wax type at maximum burn"
			)
		end),

		Harness.test("A decoy thrown at full range out-pulls a flame the drawn are already on", function()
			local strongestPlayerFlame = 0
			for _, waxType in WaxTypesConfig do
				strongestPlayerFlame =
					math.max(strongestPlayerFlame, LightConfig.maxIntensity * waxType.brightnessMultiplier)
			end
			-- Worst case for the tool: the moth sits on the flame (full contribution, zero distance)
			-- and the decoy lands as far away as the throw allows.
			local decoy: Types.LightSource = {
				kind = "Decoy",
				position = Vector3.new(ToolsConfig.Decoy.throwRange :: number, 0, 0),
				intensity = ToolsConfig.Decoy.decoyIntensity :: number,
				range = ToolsConfig.Decoy.decoyRange :: number,
				attractsDrawn = true,
				repelsDarkHunters = false,
				forcesDarkHunterRetreat = false,
				ownerId = nil,
			}
			Harness.expect(
				LightField.contributionOf(decoy, Vector3.zero) > strongestPlayerFlame,
				"a decoy at maximum throw distance must still divert a moth feeding on the brightest flame"
			)
		end),

		Harness.test("Flare and Cup are cooldown-free wax-paid counterplay tools", function()
			Harness.near(ToolsConfig.Flare.cooldown, 0)
			Harness.near(ToolsConfig.Cup.cooldown, 0)
			Harness.expect(ToolsConfig.Flare.waxCost > 0, "Flare must still spend wax per activation")
			Harness.expect(
				(ToolsConfig.Cup.lightMultiplier :: number) < 0.05,
				"Cup should suppress almost all emitted light"
			)
		end),
	},
}

return suite

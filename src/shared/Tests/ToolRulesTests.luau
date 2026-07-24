--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local ToolRules = require(script.Parent.Parent.Logic.ToolRules)
local SacrificeRules = require(script.Parent.Parent.Logic.SacrificeRules)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)
local DeathConfig = require(script.Parent.Parent.Config.Death)

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

		Harness.test("aim points are preserved in range and clamped on the same ray", function()
			local origin = Vector3.new(3, 4, 5)
			local castRange = ToolsConfig.Cast.castRange :: number
			local inRange = origin + Vector3.new(castRange / 2, 0, 0)
			Harness.vectorNear(ToolRules.clampAim(origin, inRange, castRange), inRange)
			Harness.vectorNear(ToolRules.clampAim(origin, origin, castRange), origin)

			local direction = Vector3.new(1, 2, -3).Unit
			local far = origin + direction * castRange * 10
			local clamped = ToolRules.clampAim(origin, far, castRange)
			Harness.near((clamped - origin).Magnitude, castRange)
			Harness.vectorNear((clamped - origin).Unit, direction)
		end),
	},
}

return suite

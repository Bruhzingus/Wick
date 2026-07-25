--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local CooldownRules = require(script.Parent.Parent.Logic.CooldownRules)
local DeathConfig = require(script.Parent.Parent.Config.Death)
local MovementConfig = require(script.Parent.Parent.Config.Movement)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)
local SacrificeRules = require(script.Parent.Parent.Logic.SacrificeRules)

local NOW = 100

local function freshState(playerId: number?): Types.PlayerRunState
	return {
		playerId = playerId or 1,
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
		lastDodgeAt = -math.huge,
		lastSlideAt = -math.huge,
		nextToolUse = {},
		freeToolCharges = {},
		sacrifices = {},
		modifiers = SacrificeRules.defaultModifiers(),
		nextBasinPenalty = 1,
		basinUsedAtDepth = {},
	}
end

local function requireStatus(status: CooldownRules.CooldownStatus?): CooldownRules.CooldownStatus
	Harness.expect(status ~= nil, "expected a cooldown status")
	return status :: CooldownRules.CooldownStatus
end

local suite: Harness.Suite = {
	name = "CooldownRules",
	tests = {
		Harness.test("snapshot covers all cooldown tools and movement actions but omits sprint", function()
			local snapshot = CooldownRules.snapshot(freshState(), NOW)
			for toolId, def in ToolsConfig do
				local status = snapshot[toolId]
				Harness.expect(status ~= nil, toolId .. " should have a cooldown projection")
				Harness.near((status :: CooldownRules.CooldownStatus).duration, def.cooldown)
				Harness.near((status :: CooldownRules.CooldownStatus).remaining, 0)
			end
			Harness.near(requireStatus(snapshot.Dodge).duration, MovementConfig.dodgeCooldown)
			Harness.near(requireStatus(snapshot.Slide).duration, MovementConfig.slideCooldown)
			Harness.near(requireStatus(snapshot.Dodge).remaining, 0, nil, "fresh Dodge should be ready")
			Harness.near(requireStatus(snapshot.Slide).remaining, 0, nil, "fresh Slide should be ready")
			Harness.isNil(snapshot.Sprint)
			Harness.isNil(CooldownRules.forAction(freshState(), "Sprint", NOW))
		end),

		Harness.test("all four tool cooldowns report exact remaining time and ready boundaries", function()
			for toolId, def in ToolsConfig do
				local state = freshState()
				state.nextToolUse[toolId] = NOW + def.cooldown

				local started = requireStatus(CooldownRules.forAction(state, toolId, NOW))
				Harness.near(started.remaining, def.cooldown, nil, toolId .. " should begin full")
				Harness.near(started.duration, def.cooldown)

				local justBefore = requireStatus(CooldownRules.forAction(state, toolId, NOW + def.cooldown - 0.01))
				Harness.near(justBefore.remaining, 0.01, nil, toolId .. " should remain cooling before boundary")

				local boundary = requireStatus(CooldownRules.forAction(state, toolId, NOW + def.cooldown))
				Harness.near(boundary.remaining, 0, nil, toolId .. " should be ready at boundary")
			end
		end),

		Harness.test("voluntary Snuff projects the effective self-relight commitment", function()
			local state = freshState()
			state.isLit = false
			state.unlitByChoice = true
			state.litChangedAt = NOW
			state.nextToolUse.Snuff = NOW + ToolsConfig.Snuff.cooldown

			local started = requireStatus(CooldownRules.forAction(state, "Snuff", NOW))
			Harness.near(started.duration, DeathConfig.selfRelightDelaySeconds)
			Harness.near(started.remaining, DeathConfig.selfRelightDelaySeconds)

			local justBefore =
				requireStatus(CooldownRules.forAction(state, "Snuff", NOW + DeathConfig.selfRelightDelaySeconds - 0.01))
			Harness.near(justBefore.remaining, 0.01)

			local boundary =
				requireStatus(CooldownRules.forAction(state, "Snuff", NOW + DeathConfig.selfRelightDelaySeconds))
			Harness.near(boundary.remaining, 0)
		end),

		Harness.test("Dodge and Slide use authoritative last-use times and exact boundaries", function()
			local state = freshState()
			state.lastDodgeAt = NOW
			state.lastSlideAt = NOW

			local dodge = requireStatus(CooldownRules.forAction(state, "Dodge", NOW))
			local slide = requireStatus(CooldownRules.forAction(state, "Slide", NOW))
			Harness.near(dodge.remaining, MovementConfig.dodgeCooldown)
			Harness.near(dodge.duration, MovementConfig.dodgeCooldown)
			Harness.near(slide.remaining, MovementConfig.slideCooldown)
			Harness.near(slide.duration, MovementConfig.slideCooldown)

			Harness.near(
				requireStatus(CooldownRules.forAction(state, "Dodge", NOW + MovementConfig.dodgeCooldown)).remaining,
				0
			)
			Harness.near(
				requireStatus(CooldownRules.forAction(state, "Slide", NOW + MovementConfig.slideCooldown)).remaining,
				0
			)
		end),

		Harness.test("snapshots are independent and never mutate player state", function()
			local first = freshState(11)
			local second = freshState(22)
			first.nextToolUse.Flare = NOW + ToolsConfig.Flare.cooldown
			second.nextToolUse.Cast = NOW + ToolsConfig.Cast.cooldown

			local firstSnapshot = CooldownRules.snapshot(first, NOW)
			local secondSnapshot = CooldownRules.snapshot(second, NOW)
			Harness.near(requireStatus(firstSnapshot.Flare).remaining, ToolsConfig.Flare.cooldown)
			Harness.near(requireStatus(firstSnapshot.Cast).remaining, 0)
			Harness.near(requireStatus(secondSnapshot.Flare).remaining, 0)
			Harness.near(requireStatus(secondSnapshot.Cast).remaining, ToolsConfig.Cast.cooldown)

			firstSnapshot.Flare.remaining = 123
			Harness.near(requireStatus(secondSnapshot.Flare).remaining, 0)
			Harness.near(first.nextToolUse.Flare :: number, NOW + ToolsConfig.Flare.cooldown)
			Harness.isNil(second.nextToolUse.Flare)
		end),
	},
}

return suite

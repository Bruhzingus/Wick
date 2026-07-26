--!strict
-- Server-authoritative one-shot unstable dripstone lifecycle. It owns trigger detection, shared
-- state/timing, variant-scaled wax loss, low-wax snuffing, and early-floor teaching. Models remain
-- anchored; clients reconstruct warning and fall motion from replicated timestamps, so solo and
-- multiplayer use identical rules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local DripstoneVisualProtocol = require(ReplicatedStorage.Shared.DripstoneVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local WaxService = require(script.Parent.WaxService)
local DeathService = require(script.Parent.DeathService)
local WardenRegistry = require(script.Parent.WardenRegistry)
local Telemetry = require(script.Parent.Telemetry)

local DripstoneService = {}

export type RuntimeInput = {
	model: Model,
	depth: number,
	impactPosition: Vector3,
	fallDistance: number,
	variantId: string,
}

type Mode = "Dormant" | "Warning" | "Falling" | "Spent"
type Runtime = RuntimeInput & {
	mode: Mode,
	stateStartedAt: number,
	deadline: number,
}

local runtimesByDepth: { [number]: { Runtime } } = {}
local dripstoneTutorialSeen: { [number]: boolean } = {}

-- The first nearby fall teaches the full physical warning language even when the player dodges
-- cleanly. This is intentionally once per runner per expedition, not a hit-only reminder.
local function sendFallTutorial(runtime: Runtime)
	local hints = Config.Feel.tutorialHints
	if not hints.enabled or runtime.depth > hints.maxDepth then
		return
	end
	for playerId, state in PlayerState.all() do
		if
			state.alive
			and not state.finished
			and state.snuffedAt == nil
			and state.depth == runtime.depth
			and DripstoneRules.shouldShowFallTutorial(
				dripstoneTutorialSeen[playerId] == true,
				runtime.depth,
				hints.maxDepth,
				state.position,
				runtime.impactPosition,
				Config.Hazards.unstableDripstone.presentationCullDistance
			)
		then
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil then
				dripstoneTutorialSeen[playerId] = true
				Remotes.get("TutorialHint"):FireClient(player, "Dripstone")
			end
		end
	end
end

local function setMode(runtime: Runtime, mode: Mode, now: number, duration: number)
	runtime.mode = mode
	runtime.stateStartedAt = now
	runtime.deadline = now + math.max(0, duration)
	if runtime.model.Parent ~= nil then
		runtime.model:SetAttribute(DripstoneVisualProtocol.attributes.stateStartedAt, workspace:GetServerTimeNow())
		-- State is written last so its change signal observes the matching timestamp.
		runtime.model:SetAttribute(DripstoneVisualProtocol.attributes.state, mode)
	end
end

local function impact(runtime: Runtime, now: number)
	local variant = DripstoneRules.variantById(runtime.variantId)
	if variant == nil then
		setMode(runtime, "Spent", now, 0)
		return
	end

	local hitPlayerIds: { number } = {}
	for playerId, state in PlayerState.all() do
		if
			state.alive
			and not state.finished
			and state.snuffedAt == nil
			and state.depth == runtime.depth
			and DripstoneRules.insideDisc(state.position, runtime.impactPosition, variant.impactRadius)
		then
			table.insert(hitPlayerIds, playerId)
			if DripstoneRules.impactOutcome(state.wax.current, state.wax.max) == "Snuff" then
				DeathService.snuff(playerId, "A falling dripstone snuffed your weakened flame.")
			else
				WaxService.drainExternal(
					playerId,
					state.wax.max * variant.waxLossFraction,
					"DamageDripstone",
					"Falling dripstone shattered your remaining wax."
				)
			end
			-- Burnout can occur above. Only a surviving flame receives the temporary partial snuff.
			local afterDamage = PlayerState.get(playerId)
			if afterDamage ~= nil and afterDamage.alive and not afterDamage.finished then
				WaxService.suppressLight(
					playerId,
					Config.Hazards.unstableDripstone.lightSuppressionMultiplier,
					Config.Hazards.unstableDripstone.lightSuppressionSeconds,
					Config.Hazards.unstableDripstone.flameFlickerSeconds
				)
			end
		end
	end

	-- The crown does not care what it lands on. A Stone Warden caught under it is buried: rooted in
	-- place and unable to kill until it digs out (Config.Hazards.unstableDripstone.wardenStunSeconds).
	local stunnedWardens = 0
	for _, entry in WardenRegistry.positionsAtDepth(runtime.depth) do
		if DripstoneRules.insideDisc(entry.position, runtime.impactPosition, variant.impactRadius) then
			entry.warden.stun(Config.Hazards.unstableDripstone.wardenStunSeconds)
			stunnedWardens += 1
		end
	end

	local restCFrame = runtime.model:GetAttribute(DripstoneVisualProtocol.attributes.restCFrame)
	if typeof(restCFrame) == "CFrame" and runtime.model.Parent ~= nil then
		runtime.model:PivotTo(CFrame.new(0, -runtime.fallDistance, 0) * restCFrame)
	end
	setMode(runtime, "Spent", now, 0)
	Remotes.get("RunEvent"):FireAllClients("dripstoneImpact", {
		position = runtime.impactPosition,
		depth = runtime.depth,
		variantId = runtime.variantId,
		hitPlayerIds = hitPlayerIds,
	})
	Telemetry.event("dripstone_impact", nil, {
		depth = runtime.depth,
		variant = runtime.variantId,
		hitPlayers = #hitPlayerIds,
		stunnedWardens = stunnedWardens,
	})
end

function DripstoneService.registerFloor(depth: number, inputs: { RuntimeInput })
	local floorRuntimes: { Runtime } = {}
	for _, input in inputs do
		table.insert(floorRuntimes, {
			model = input.model,
			depth = input.depth,
			impactPosition = input.impactPosition,
			fallDistance = input.fallDistance,
			variantId = input.variantId,
			mode = "Dormant",
			stateStartedAt = 0,
			deadline = 0,
		})
	end
	runtimesByDepth[depth] = floorRuntimes
end

function DripstoneService.tick()
	local now = os.clock()
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			if runtime.model.Parent == nil or runtime.mode == "Spent" then
				continue
			end
			local variant = DripstoneRules.variantById(runtime.variantId)
			if variant == nil then
				setMode(runtime, "Spent", now, 0)
				continue
			end

			if runtime.mode == "Dormant" then
				local triggered = false
				for _, state in PlayerState.all() do
					if
						state.alive
						and not state.finished
						and state.snuffedAt == nil
						and state.depth == runtime.depth
						and DripstoneRules.insideDisc(state.position, runtime.impactPosition, variant.triggerRadius)
					then
						triggered = true
						break
					end
				end
				-- The trigger disc is a physical one: anything heavy enough crossing it sets the
				-- formation off, so a Stone Warden walking under a fractured ceiling brings it down
				-- on itself. It is the same disc, the same warning, and the same commitment.
				if not triggered then
					for _, entry in WardenRegistry.positionsAtDepth(runtime.depth) do
						if DripstoneRules.insideDisc(entry.position, runtime.impactPosition, variant.triggerRadius) then
							triggered = true
							break
						end
					end
				end
				if triggered then
					-- The warning commits once triggered and never homes or cancels. Sprinting
					-- changes reaction time naturally; it does not secretly change this footprint.
					setMode(runtime, "Warning", now, variant.warningSeconds)
				end
			elseif runtime.mode == "Warning" and now >= runtime.deadline then
				setMode(runtime, "Falling", now, DripstoneRules.fallDuration(runtime.fallDistance))
				sendFallTutorial(runtime)
			elseif runtime.mode == "Falling" and now >= runtime.deadline then
				impact(runtime, now)
			end
		end
	end
end

function DripstoneService.reset()
	table.clear(runtimesByDepth)
	table.clear(dripstoneTutorialSeen)
end

return DripstoneService

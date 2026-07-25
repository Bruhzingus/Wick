--!strict
-- Server-authoritative one-shot unstable dripstone lifecycle. It owns trigger detection, shared
-- state/timing, wax loss, and partial snuff. Models remain anchored; clients reconstruct warning
-- and fall motion from replicated timestamps, so solo and multiplayer use identical rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local DripstoneVisualProtocol = require(ReplicatedStorage.Shared.DripstoneVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local WaxService = require(script.Parent.WaxService)
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
			WaxService.drainExternal(
				playerId,
				state.wax.max * variant.waxLossFraction,
				"Falling dripstone shattered your remaining wax."
			)
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
				for _, state in PlayerState.all() do
					if
						state.alive
						and not state.finished
						and state.snuffedAt == nil
						and state.depth == runtime.depth
						and DripstoneRules.insideDisc(state.position, runtime.impactPosition, variant.triggerRadius)
					then
						-- The warning commits once triggered and never homes or cancels. Sprinting
						-- changes reaction time naturally; it does not secretly change this footprint.
						setMode(runtime, "Warning", now, variant.warningSeconds)
						break
					end
				end
			elseif runtime.mode == "Warning" and now >= runtime.deadline then
				setMode(runtime, "Falling", now, DripstoneRules.fallDuration(runtime.fallDistance))
			elseif runtime.mode == "Falling" and now >= runtime.deadline then
				impact(runtime, now)
			end
		end
	end
end

function DripstoneService.reset()
	table.clear(runtimesByDepth)
end

return DripstoneService

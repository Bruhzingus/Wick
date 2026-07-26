--!strict
-- The authoritative tick: samples each candle, assembles its drain context, applies the pure
-- drain pipeline, enforces the water rule, updates the body, and replicates state. Wax changes
-- from other systems (threat contact) also route through here so burnout is detected in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local WaxDrain = require(ReplicatedStorage.Shared.Logic.WaxDrain)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local BrightnessMap = require(ReplicatedStorage.Shared.Logic.BrightnessMap)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local CooldownRules = require(ReplicatedStorage.Shared.Logic.CooldownRules)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local HazardService = require(script.Parent.HazardService)
local DeathService = require(script.Parent.DeathService)

local WaxService = {}

local tickAccumulator = 0
local replicationAccumulator = 0
-- Cave-tier difficulty knob: scales every component of the drain pipeline uniformly, so a deeper
-- tier's candles effectively burn faster without changing the pure per-tick math in WaxDrain.
local tierWaxDrainMultiplier = 1

local function applyLightVisual(playerId: Types.PlayerId, state: Types.PlayerRunState, now: number)
	local lightMultiplier =
		DripstoneRules.lightMultiplier(now, state.lightSuppressedUntil, state.lightSuppressionMultiplier)
	if lightMultiplier == 1 and state.lightSuppressionMultiplier ~= 1 then
		state.lightSuppressionMultiplier = 1
	end
	if state.flareEndsAt > now then
		local flare = Config.Tools.Flare
		CharacterService.applyLight(
			playerId,
			(flare.burstRange :: number) * lightMultiplier,
			(flare.burstBrightness :: number) * lightMultiplier,
			state.isLit
		)
	else
		local cupMultiplier = 1
		if state.isCupping then
			cupMultiplier = Config.Tools.Cup.lightMultiplier :: number
		end
		local params = BrightnessMap.paramsFor(state.burnRate, Config.WaxTypes[state.waxTypeId], cupMultiplier)
		CharacterService.applyLight(
			playerId,
			params.range * lightMultiplier,
			params.brightness * lightMultiplier,
			state.isLit
		)
	end
end

local function stepPlayer(playerId: Types.PlayerId, state: Types.PlayerRunState, step: number, now: number)
	local basePosition = CharacterService.basePosition(playerId)
	if basePosition == nil then
		return
	end
	state.position = basePosition
	state.movementMode = WaxDrain.movementModeForSpeed(CharacterService.horizontalSpeed(playerId))

	local exposure = HazardService.exposureFor(state.depth, state.position, state.currentHeight)

	-- THE water rule: surface vs current flame height, nothing scripted. Instant and absolute.
	if exposure.water == "Lethal" then
		DeathService.kill(playerId, "Snuffed", "Water reached your flame height.")
		return
	end

	local cupUpkeep = 0
	if state.isCupping then
		cupUpkeep = Config.Tools.Cup.waxCost
	end
	-- The same pipeline as before, taken one attributed component at a time so the run summary can
	-- say which part of the recurring pressure actually emptied the candle.
	local components = WaxDrain.breakdown({
		isLit = state.isLit,
		burnRate = state.burnRate,
		waxType = Config.WaxTypes[state.waxTypeId],
		movementMode = state.movementMode,
		isCupping = state.isCupping,
		cupUpkeepPerSecond = cupUpkeep,
		wading = exposure.water == "Wading",
	})
	local scale = tierWaxDrainMultiplier * state.modifiers.waxDrainMultiplier * step
	for _, component in components do
		local newWax = WaxAccounting.spend(state.wax, state.waxLedger, component.perSecond * scale, component.source)
		state.wax = newWax
	end
	if state.wax.current <= 0 then
		DeathService.burnOut(playerId, "Your wax was depleted by the active burn drain.")
		return
	end

	local height = CandleGeometry.heightForWax(state.wax.current)
	if math.abs(height - state.currentHeight) > 0.01 then
		state.currentHeight = height
		CharacterService.applyHeight(playerId, height)
	end
	CharacterService.applyMovementVisual(playerId, state.movementMode)

	-- Visuals: flare burst overrides the flame's own output while live.
	applyLightVisual(playerId, state, now)
end

local function replicate()
	local entries: { Remotes.StateEntry } = {}
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	for playerId, state in PlayerState.all() do
		local water: Types.WaterAssessment = "None"
		if state.alive and not state.finished then
			local exposure = HazardService.exposureFor(state.depth, state.position, state.currentHeight)
			water = exposure.water
		end
		local actionCooldowns: { [string]: Remotes.ActionCooldown } = {}
		for actionId, status in CooldownRules.snapshot(state, now) do
			actionCooldowns[actionId] = {
				endsAt = serverNow + status.remaining,
				duration = status.duration,
			}
		end
		table.insert(entries, {
			playerId = playerId,
			wax = state.wax.current,
			maxWax = state.wax.max,
			burnRate = state.burnRate,
			waxTypeId = state.waxTypeId,
			freeToolCharges = table.clone(state.freeToolCharges),
			actionCooldowns = actionCooldowns,
			isLit = state.isLit,
			isCupping = state.isCupping,
			isFlaring = state.isLit and state.flareEndsAt > now,
			height = state.currentHeight,
			depth = state.depth,
			alive = state.alive,
			finished = state.finished,
			snuffed = state.snuffedAt ~= nil,
			water = water,
			canHearThreats = state.modifiers.canHearThreats,
		})
	end
	Remotes.get("StateSync"):FireAllClients(entries)
end

function WaxService.tick(dt: number)
	local step = 1 / Config.Run.tickRate
	tickAccumulator += dt
	while tickAccumulator >= step do
		tickAccumulator -= step
		local now = os.clock()
		for playerId, state in PlayerState.all() do
			if state.alive and not state.finished then
				stepPlayer(playerId, state, step, now)
			end
		end
	end

	replicationAccumulator += dt
	local replicationStep = 1 / Config.Run.stateReplicationHz
	if replicationAccumulator >= replicationStep then
		replicationAccumulator -= replicationStep
		replicate()
	end
end

-- External wax removal (threat contact, dripstone impact). Routed here so burnout detection stays
-- in one place. `source` is chosen by the calling server system — never by anything on the wire —
-- and an unrecognized one is recorded as "Other" rather than silently vanishing.
function WaxService.drainExternal(
	playerId: Types.PlayerId,
	amount: number,
	source: Types.WaxSource,
	burnoutReason: string?
): number
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished then
		return 0
	end
	local newWax, emptied, applied = WaxAccounting.spend(state.wax, state.waxLedger, amount, source)
	state.wax = newWax
	if emptied then
		DeathService.burnOut(playerId, burnoutReason or "External damage depleted your wax.")
	end
	return applied
end

-- Merge partial-snuff effects authoritatively. Overlaps keep the dimmest multiplier and the latest
-- expiry; they never toggle isLit or enter the revivable full-snuff state.
function WaxService.suppressLight(
	playerId: Types.PlayerId,
	multiplier: number,
	duration: number,
	impactFlickerSeconds: number?
)
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished then
		return
	end
	local now = os.clock()
	local nextMultiplier = math.clamp(multiplier, 0, 1)
	if now < state.lightSuppressedUntil then
		state.lightSuppressionMultiplier = math.min(state.lightSuppressionMultiplier, nextMultiplier)
	else
		state.lightSuppressionMultiplier = nextMultiplier
	end
	state.lightSuppressedUntil = math.max(state.lightSuppressedUntil, now + math.max(0, duration))
	-- Retarget the replicated light in the same server step as threat perception. Clients still ease
	-- the transition over their short presentation window, but never wait for the next wax tick.
	applyLightVisual(playerId, state, now)
	if impactFlickerSeconds ~= nil and impactFlickerSeconds > 0 then
		CharacterService.signalLightImpact(playerId, impactFlickerSeconds)
	end
end

-- Called once per run start (RunOrchestrator), mirroring BrazierService.setCaveTier.
function WaxService.setCaveTier(tierId: number)
	local tier = Interfaces.CaveTiers.get(tierId)
	tierWaxDrainMultiplier = if tier ~= nil then tier.waxDrainMultiplier else 1
end

function WaxService.reset()
	tickAccumulator = 0
	tierWaxDrainMultiplier = 1
end

return WaxService

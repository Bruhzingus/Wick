--!strict
-- The authoritative tick: samples each candle, assembles its drain context, applies the pure
-- drain pipeline, enforces the water rule, updates the body, and replicates state. Wax changes
-- from other systems (threat contact) also route through here so burnout is detected in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local WaxDrain = require(ReplicatedStorage.Shared.Logic.WaxDrain)
local BrightnessMap = require(ReplicatedStorage.Shared.Logic.BrightnessMap)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local HazardRules = require(ReplicatedStorage.Shared.Logic.HazardRules)
local CooldownRules = require(ReplicatedStorage.Shared.Logic.CooldownRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local HazardService = require(script.Parent.HazardService)
local DeathService = require(script.Parent.DeathService)

local WaxService = {}

local tickAccumulator = 0
local replicationAccumulator = 0
local draftExposureSeconds: { [Types.PlayerId]: number } = {}

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

	-- Drafts snuff a flame held open too long; CUP is the counter.
	if exposure.inDraft and HazardRules.draftThreatens(state.isLit, state.isCupping) then
		local seconds = (draftExposureSeconds[playerId] or 0) + step
		if seconds >= HazardRules.draftSnuffSeconds() then
			draftExposureSeconds[playerId] = 0
			DeathService.snuff(playerId, "An uncovered draft snuffed your flame.")
			return
		end
		draftExposureSeconds[playerId] = seconds
	else
		draftExposureSeconds[playerId] = 0
	end

	local cupUpkeep = 0
	if state.isCupping then
		cupUpkeep = Config.Tools.Cup.waxCost
	end
	local drainPerSecond = WaxDrain.perSecond({
		isLit = state.isLit,
		burnRate = state.burnRate,
		waxType = Config.WaxTypes[state.waxTypeId],
		movementMode = state.movementMode,
		isCupping = state.isCupping,
		cupUpkeepPerSecond = cupUpkeep,
		inDraft = exposure.inDraft,
		wading = exposure.water == "Wading",
	})
	local newWax, burnedOut = WaxDrain.apply(state.wax, drainPerSecond * step)
	state.wax = newWax
	if burnedOut then
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
		local inDraft = false
		local water: Types.WaterAssessment = "None"
		if state.alive and not state.finished then
			local exposure = HazardService.exposureFor(state.depth, state.position, state.currentHeight)
			inDraft = exposure.inDraft
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
			height = state.currentHeight,
			depth = state.depth,
			alive = state.alive,
			finished = state.finished,
			snuffed = state.snuffedAt ~= nil,
			inDraft = inDraft,
			water = water,
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

-- External wax removal (threat contact). Routed here so burnout detection stays in one place.
function WaxService.drainExternal(playerId: Types.PlayerId, amount: number, reason: string?)
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished then
		return
	end
	local newWax, burnedOut = WaxDrain.apply(state.wax, amount)
	state.wax = newWax
	if burnedOut then
		DeathService.burnOut(playerId, reason or "External damage depleted your wax.")
	end
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

function WaxService.reset()
	table.clear(draftExposureSeconds)
	tickAccumulator = 0
end

return WaxService

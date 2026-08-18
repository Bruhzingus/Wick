--!strict
-- The per-player state store: the ONLY place PlayerRunState lives. Keyed by userId — no
-- singletons, no player-count assumptions (ARCHITECTURE invariant). Services read and mutate
-- entries; pure logic in shared computes what the new values should be.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local SacrificeRules = require(ReplicatedStorage.Shared.Logic.SacrificeRules)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local DepthRules = require(ReplicatedStorage.Shared.Logic.DepthRules)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local CargoRules = require(ReplicatedStorage.Shared.Logic.CargoRules)
local CandleModifiers = require(ReplicatedStorage.Shared.Logic.CandleModifiers)
local ContractRules = require(ReplicatedStorage.Shared.Logic.ContractRules)

local PlayerState = {}

local states: { [Types.PlayerId]: Types.PlayerRunState } = {}

local function freshState(
	playerId: Types.PlayerId,
	isSoloRun: boolean,
	startDepth: number,
	contractId: string?
): Types.PlayerRunState
	local now = os.clock()

	-- THE CONTRACT SHAPES THE CANDLE BEFORE IT IS EVER LIT. Applied here rather than after spawning so
	-- there is no frame in which a Short Wick candle exists at full wax — the body height that decides
	-- whether water is lethal is derived from this number (Logic/CandleGeometry), and a candle that is
	-- briefly the wrong height is a candle that can briefly wade somewhere it should drown in.
	local effect = ContractRules.effectFor(contractId)
	local startingWax, maxWax = ContractRules.waxFor(effect, Config.Wax.startingWax, Config.Wax.maxWax)
	local modifiers = SacrificeRules.defaultModifiers()
	modifiers.maxWaxMultiplier = effect.maxWaxMultiplier
	-- Rides the Basin's own tool-removal set, so `ToolRules` needs no contract-specific branch and a
	-- contract plus a sacrifice that both take a tool agree rather than overwriting each other.
	ContractRules.applyLostTools(effect, modifiers.lostTools)

	return {
		playerId = playerId,
		wax = { current = startingWax, max = maxWax },
		burnRate = Config.Wax.initialBurnRate,
		-- Every run starts on a NEUTRAL candle and builds from there. Wiped with the rest of the state,
		-- so nothing a run collected — not a LifeWax stack, not a half-melted block of Frozen Wax —
		-- survives into the next one.
		candle = CandleModifiers.newState(),
		isLit = true,
		litChangedAt = now,
		snuffedAt = nil,
		isCupping = false,
		flareEndsAt = 0,
		lightSuppressedUntil = 0,
		lightSuppressionMultiplier = 1,
		threatProtectedUntil = 0,
		position = Vector3.zero,
		currentHeight = CandleGeometry.heightForWax(startingWax),
		depth = 1,
		startDepth = startDepth,
		waxLedger = WaxAccounting.newLedger(startingWax, startDepth, now),
		alive = true,
		finished = false,
		movementMode = "Idle",
		nextToolUse = {},
		freeToolCharges = {},
		matchCharges = 0,
		-- Nothing carries over. A stick found on floor 9 of the last run is not in this candle's bag.
		dynamiteCharges = 0,
		isSoloRun = isSoloRun,
		sacrifices = {},
		modifiers = modifiers,
		nextBasinPenalty = 1,
		basinUsedAtDepth = {},
		isSwinging = false,
		isHeldByEnemy = false,
		isLightingLamp = false,
		trippedUntil = 0,
		-- Wiped with the rest of the run: the mining count is a playtest readout, never progression.
		depositsMinedThisRun = 0,
		depositsMinedAtDepths = {},
		-- PHASE 8 cargo. Fresh and empty with every run; ExtractionService is its only mutator.
		rawWax = CargoRules.newRun(),
	}
end

function PlayerState.ensure(playerId: Types.PlayerId): Types.PlayerRunState
	local existing = states[playerId]
	if existing ~= nil then
		return existing
	end
	local state = freshState(playerId, false, 1)
	states[playerId] = state
	return state
end

function PlayerState.get(playerId: Types.PlayerId): Types.PlayerRunState?
	return states[playerId]
end

-- Wipe to a fresh candle (new run). Keeps the entry so references via get() stay valid patterns.
-- `startDepth` is the absolute depth this expedition begins at; it comes from the cave tier and is
-- server-authoritative. Omitted means the surface-level start every tier uses today.
--
-- `contractId` is the Lamp Network contract this player signed, taken from the run's own snapshot
-- (ExtractionService.contractFor) rather than read live from a profile — the profile's copy was
-- already blanked at descent, and a candle must be built from what the run agreed to, not from what
-- the player has since gone and signed for their next one.
function PlayerState.reset(
	playerId: Types.PlayerId,
	isSoloRun: boolean,
	startDepth: number?,
	contractId: string?
): Types.PlayerRunState
	local start = startDepth or 1
	if not DepthRules.isSupportedDepth(start) then
		start = 1
	end
	local state = freshState(playerId, isSoloRun, start, contractId)
	states[playerId] = state
	return state
end

-- The canonical difficulty depth for a player right now. Read this, never `state.depth`, whenever
-- the question is "how deep/dangerous is this", not "which floor of this run is it".
function PlayerState.globalDepth(state: Types.PlayerRunState): number
	return DepthRules.getGlobalDepth(state.startDepth, state.depth)
end

function PlayerState.protectFromThreats(playerId: Types.PlayerId, duration: number)
	local state = states[playerId]
	if state == nil then
		return
	end
	state.threatProtectedUntil = math.max(state.threatProtectedUntil, os.clock() + math.max(duration, 0))
end

function PlayerState.isThreatProtected(playerId: Types.PlayerId, now: number?): boolean
	local state = states[playerId]
	return state ~= nil and state.threatProtectedUntil > (now or os.clock())
end

function PlayerState.clearThreatProtection(playerId: Types.PlayerId)
	local state = states[playerId]
	if state ~= nil then
		state.threatProtectedUntil = 0
	end
end

function PlayerState.remove(playerId: Types.PlayerId)
	states[playerId] = nil
end

function PlayerState.all(): { [Types.PlayerId]: Types.PlayerRunState }
	return states
end

return PlayerState

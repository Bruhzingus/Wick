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

local PlayerState = {}

local states: { [Types.PlayerId]: Types.PlayerRunState } = {}

local function freshState(playerId: Types.PlayerId, isSoloRun: boolean, startDepth: number): Types.PlayerRunState
	local now = os.clock()
	return {
		playerId = playerId,
		wax = { current = Config.Wax.startingWax, max = Config.Wax.maxWax },
		burnRate = Config.Wax.initialBurnRate,
		waxTypeId = Config.Wax.startingWaxTypeId,
		isLit = true,
		litChangedAt = now,
		snuffedAt = nil,
		isCupping = false,
		flareEndsAt = 0,
		lightSuppressedUntil = 0,
		lightSuppressionMultiplier = 1,
		position = Vector3.zero,
		currentHeight = CandleGeometry.heightForWax(Config.Wax.startingWax),
		depth = 1,
		startDepth = startDepth,
		waxLedger = WaxAccounting.newLedger(Config.Wax.startingWax, startDepth, now),
		alive = true,
		finished = false,
		movementMode = "Idle",
		sprinting = false,
		nextToolUse = {},
		freeToolCharges = {},
		matchCharges = 0,
		isSoloRun = isSoloRun,
		sacrifices = {},
		modifiers = SacrificeRules.defaultModifiers(),
		nextBasinPenalty = 1,
		basinUsedAtDepth = {},
		isSwinging = false,
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
function PlayerState.reset(playerId: Types.PlayerId, isSoloRun: boolean, startDepth: number?): Types.PlayerRunState
	local start = startDepth or 1
	if not DepthRules.isSupportedDepth(start) then
		start = 1
	end
	local state = freshState(playerId, isSoloRun, start)
	states[playerId] = state
	return state
end

-- The canonical difficulty depth for a player right now. Read this, never `state.depth`, whenever
-- the question is "how deep/dangerous is this", not "which floor of this run is it".
function PlayerState.globalDepth(state: Types.PlayerRunState): number
	return DepthRules.getGlobalDepth(state.startDepth, state.depth)
end

function PlayerState.remove(playerId: Types.PlayerId)
	states[playerId] = nil
end

function PlayerState.all(): { [Types.PlayerId]: Types.PlayerRunState }
	return states
end

return PlayerState

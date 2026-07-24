--!strict
-- The per-player state store: the ONLY place PlayerRunState lives. Keyed by userId — no
-- singletons, no player-count assumptions (ARCHITECTURE invariant). Services read and mutate
-- entries; pure logic in shared computes what the new values should be.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local SacrificeRules = require(ReplicatedStorage.Shared.Logic.SacrificeRules)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)

local PlayerState = {}

local states: { [Types.PlayerId]: Types.PlayerRunState } = {}

local function freshState(playerId: Types.PlayerId): Types.PlayerRunState
	local now = os.clock()
	return {
		playerId = playerId,
		wax = { current = Config.Wax.startingWax, max = Config.Wax.maxWax },
		burnRate = Config.Wax.initialBurnRate,
		waxTypeId = Config.Wax.startingWaxTypeId,
		isLit = true,
		unlitByChoice = false,
		litChangedAt = now,
		snuffedAt = nil,
		isCupping = false,
		flareEndsAt = 0,
		position = Vector3.zero,
		currentHeight = CandleGeometry.heightForWax(Config.Wax.startingWax),
		depth = 1,
		alive = true,
		finished = false,
		movementMode = "Idle",
		sprinting = false,
		slidingUntil = 0,
		lastDodgeAt = 0,
		lastSlideAt = 0,
		nextToolUse = {},
		sacrifices = {},
		modifiers = SacrificeRules.defaultModifiers(),
		nextBasinPenalty = 1,
		basinUsedAtDepth = {},
	}
end

function PlayerState.ensure(playerId: Types.PlayerId): Types.PlayerRunState
	local existing = states[playerId]
	if existing ~= nil then
		return existing
	end
	local state = freshState(playerId)
	states[playerId] = state
	return state
end

function PlayerState.get(playerId: Types.PlayerId): Types.PlayerRunState?
	return states[playerId]
end

-- Wipe to a fresh candle (new run). Keeps the entry so references via get() stay valid patterns.
function PlayerState.reset(playerId: Types.PlayerId): Types.PlayerRunState
	local state = freshState(playerId)
	states[playerId] = state
	return state
end

function PlayerState.remove(playerId: Types.PlayerId)
	states[playerId] = nil
end

function PlayerState.all(): { [Types.PlayerId]: Types.PlayerRunState }
	return states
end

return PlayerState

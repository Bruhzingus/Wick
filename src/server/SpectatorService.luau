--!strict
-- THE SPECTATOR SYSTEM (DESIGN §7 "you become a wisp… death doesn't mean sitting out", §21 Q8).
-- Server authority over everything a dead player is: a translucent candle that walks, a teammate it
-- follows, an almost-nothing light, and the one sense it has left — its teammates' footfalls.
--
-- WHAT A GHOST CAN DO IS DEFINED BY WHAT IT CANNOT. It has no entry in the light field
-- (server/LightSources never collects it), so no threat can see it, be drawn to it, or be repelled by
-- it. It is not a run rig (server/CharacterService keeps ghosts in their own table), so no wax ticks
-- against it, no hazard samples it, and no movement correction watches it. Every rule that refuses a
-- dead player an action already refuses it by reading `alive`, so nothing here had to be added to
-- mining, tools, the bell, the Basin or the braziers to keep a ghost out of them.
--
-- THE TWO THINGS IT DOES GET, AND WHY BOTH ARE WEAK:
--
--   * THE TRAIL. A ghost cannot light a cave it still has to navigate, so it is given the one piece of
--     information that is already true — where its teammates walked. Samples come from the server's
--     own `PlayerRunState.position` and are replicated ONLY to players who are dead, so this is not a
--     map a living client can ask for. They are marks on the floor drawn locally by each ghost's own
--     client, which means rock occludes them like anything else: a ghost reads a path, never a room.
--
--   * FOLLOWING. Not a convenience — the party leaves by a descent hole a ghost cannot use, and a
--     ghost left behind is alone on a finished floor for the rest of the run. Following pulls it onto a
--     teammate, and the anchor is always that teammate's own feet: a ghost can therefore only ever
--     appear somewhere a living player is already standing, so it can never scout ahead for the party.
--
-- It decides nothing about money, progression or the run's outcome. All of that resolved at the death
-- that created the ghost (server/DeathService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local SpectatorRules = require(ReplicatedStorage.Shared.Logic.SpectatorRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local DevTestSessionRegistry = require(script.Parent.DevTestSessionRegistry)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)

local SpectatorService = {}

-- One entry per dead player.
local ghosts: { [Types.PlayerId]: Types.SpectatorState } = {}
-- Recorded footfalls, per LIVING runner. Kept even when nobody is dead, so a player who dies at
-- minute ten immediately has a path to follow instead of a black room.
local samples: { [Types.PlayerId]: { Types.SpectatorSample } } = {}
local lastSamplePosition: { [Types.PlayerId]: Vector3 } = {}
-- Replication bookkeeping, deliberately beside the state rather than inside it: what each ghost has
-- already been told, and whether its next packet replaces everything it is drawing.
local lastSentSeq: { [Types.PlayerId]: number } = {}
local lastSentSummary: { [Types.PlayerId]: string } = {}
local pendingReset: { [Types.PlayerId]: boolean } = {}
-- Monotonic within this server. The only job is letting a ghost's client dedupe samples it has
-- already drawn and letting the server send only what is new.
local nextSeq = 0
local sendAccumulator = 0

-- A player whose footfalls are worth recording, and the only kind of player a ghost may follow: still
-- in the expedition, still connected, and actually holding a run candle down in the cave. A snuffed
-- teammate qualifies (Logic/SpectatorRules.canFollow) — a body on the floor is exactly where the party
-- is, and it is about to be either relit or dead.
--
-- THE RUN-RIG CONDITION IS LOAD-BEARING, not belt-and-braces. `PlayerRunState.position` is only ever
-- sampled for a player who has a run rig (server/WaxService), and in Studio the lobby shares this
-- server: without it, a party member still standing in the hub would be a follow candidate, and
-- following them would pull a ghost out of the cave to a stale position in a room it cannot be in.
local function isLiveRunner(playerId: Types.PlayerId, state: Types.PlayerRunState): boolean
	return not DevTestSessionRegistry.isProtected(playerId)
		and SpectatorRules.canFollow(state.alive, state.finished)
		and Players:GetPlayerByUserId(playerId) ~= nil
		and CharacterService.basePosition(playerId) ~= nil
end

local function followable(): { Types.PlayerId }
	local ids: { Types.PlayerId } = {}
	for playerId, state in PlayerState.all() do
		if isLiveRunner(playerId, state) then
			table.insert(ids, playerId)
		end
	end
	return ids
end

local function recordFootfalls(now: number)
	local trail = Config.Spectator.trail
	for playerId, state in PlayerState.all() do
		if not isLiveRunner(playerId, state) then
			continue
		end
		if not SpectatorRules.shouldSample(lastSamplePosition[playerId], state.position, trail.sampleIntervalStuds) then
			continue
		end
		local buffer = samples[playerId]
		if buffer == nil then
			buffer = {}
			samples[playerId] = buffer
		end
		nextSeq += 1
		table.insert(buffer, {
			ownerId = playerId,
			position = state.position,
			depth = state.depth,
			at = now,
			seq = nextSeq,
		})
		lastSamplePosition[playerId] = state.position
	end
end

local function pruneFootfalls(now: number)
	local trail = Config.Spectator.trail
	for playerId, buffer in samples do
		samples[playerId] = SpectatorRules.pruneSamples(buffer, now, trail.lifetimeSeconds, trail.maxSamplesPerRunner)
	end
end

local function applyLight(playerId: Types.PlayerId, ghost: Types.SpectatorState, now: number)
	local light = Config.Spectator.light
	local lit = now < ghost.lightGoesOutAt
	CharacterService.applySpectatorLight(
		playerId,
		if lit then light.range else 0,
		if lit then light.brightness else 0,
		lit
	)
end

-- Puts the ghost on its target's feet. The ONE mover in this system, and the reason a ghost can never
-- be somewhere a living player has not already been.
local function anchorTo(
	playerId: Types.PlayerId,
	ghost: Types.SpectatorState,
	target: Types.PlayerRunState,
	now: number
)
	local follow = Config.Spectator.follow
	CharacterService.teleportSpectator(playerId, SpectatorRules.anchorPosition(target.position, follow.anchorLift))
	ghost.nextAnchorAt = now + math.max(follow.reanchorCooldownSeconds, 0)
	if ghost.depth ~= target.depth then
		ghost.depth = target.depth
		-- Keep the store's own floor honest: a ghost that followed the party down IS on that floor, and
		-- the trail it is shown is filtered by exactly this number. Nothing else reads a dead player's
		-- depth — the death that created it already banked its progression (server/DeathService).
		local state = PlayerState.get(playerId)
		if state ~= nil then
			state.depth = target.depth
		end
		-- New floor, new set of marks: the client must drop everything it is drawing.
		pendingReset[playerId] = true
		lastSentSeq[playerId] = 0
		Telemetry.event("spectator_followed_floor", playerId, { depth = target.depth, targetId = target.playerId })
	end
end

local function replicateTo(playerId: Types.PlayerId)
	local ghost = ghosts[playerId]
	local player = Players:GetPlayerByUserId(playerId)
	if ghost == nil or player == nil then
		return
	end

	local reset = pendingReset[playerId] == true
	local since = if reset then 0 else lastSentSeq[playerId] or 0
	local highest = since
	local fresh: { Types.SpectatorSample } = {}
	for _, buffer in samples do
		for _, sample in buffer do
			if sample.seq > highest then
				highest = sample.seq
			end
			-- Own floor only. Floors are stacked far apart in world space, but filtering here is what
			-- makes that a rule rather than a consequence of the geometry.
			if sample.seq > since and sample.depth == ghost.depth then
				table.insert(fresh, sample)
			end
		end
	end
	table.sort(fresh, function(left, right)
		return left.seq < right.seq
	end)

	local targetId = ghost.targetId
	local targetPlayer = if targetId ~= nil then Players:GetPlayerByUserId(targetId) else nil
	local candidateCount = #followable()
	-- Idle ghosts cost nothing: with no new footfalls and no change of status there is nothing to say.
	local summary = string.format("%s|%d|%d", tostring(targetId), candidateCount, ghost.depth)
	if #fresh == 0 and not reset and lastSentSummary[playerId] == summary then
		return
	end

	local payload: Remotes.SpectatorPayload = {
		targetId = targetId,
		targetName = if targetPlayer ~= nil then targetPlayer.Name else nil,
		followable = candidateCount,
		depth = ghost.depth,
		reset = reset,
		samples = fresh,
	}
	Remotes.get("SpectatorState"):FireClient(player, payload)
	pendingReset[playerId] = nil
	lastSentSeq[playerId] = highest
	lastSentSummary[playerId] = summary
end

local function stepGhost(
	playerId: Types.PlayerId,
	ghost: Types.SpectatorState,
	candidates: { Types.PlayerId },
	now: number
)
	applyLight(playerId, ghost, now)

	local targetId = ghost.targetId
	local target = if targetId ~= nil then PlayerState.get(targetId) else nil
	if target ~= nil and targetId ~= nil and not isLiveRunner(targetId, target) then
		target = nil
	end
	if targetId ~= nil and target == nil then
		-- The teammate being followed just died or cashed out. Move to whoever is still down there,
		-- rather than silently dropping a ghost into free roam at the worst possible moment.
		ghost.targetId = SpectatorRules.nextFollowTarget(candidates, nil)
		targetId = ghost.targetId
		target = if targetId ~= nil then PlayerState.get(targetId) else nil
	end
	if target == nil or now < ghost.nextAnchorAt then
		return
	end

	local follow = Config.Spectator.follow
	local ghostPosition = CharacterService.spectatorBasePosition(playerId)
	if
		SpectatorRules.needsReanchor(ghostPosition, ghost.depth, target.position, target.depth, follow.reanchorDistance)
	then
		anchorTo(playerId, ghost, target, now)
	end
end

-- Called by DeathService the instant a run ends terminally. `position` is where the candle went out —
-- a ghost starts on its own remains, and `follow.graceSeconds` keeps it there long enough to see what
-- it left for the party.
function SpectatorService.onDeath(player: Player, position: Vector3, depth: number)
	local playerId = player.UserId
	CharacterService.spawnSpectator(player, position)
	local now = Workspace:GetServerTimeNow()
	local light = Config.Spectator.light
	local follow = Config.Spectator.follow
	local ghost: Types.SpectatorState = {
		playerId = playerId,
		targetId = nil,
		lightGoesOutAt = now + math.max(light.fadeAfterSeconds, 0),
		nextAnchorAt = now + math.max(follow.graceSeconds, 0),
		depth = depth,
	}
	if follow.autoFollowOnDeath then
		ghost.targetId = SpectatorRules.nextFollowTarget(followable(), nil)
	end
	ghosts[playerId] = ghost
	lastSentSeq[playerId] = 0
	lastSentSummary[playerId] = ""
	pendingReset[playerId] = true
	-- Their own footfalls are deliberately NOT wiped. They stop being added to the moment they stop being
	-- a live runner, and the marks already recorded are the path that leads to the body they just left —
	-- which is exactly what the rest of the party's ghosts want to see. They age out like any others.
	applyLight(playerId, ghost, now)
	Telemetry.event("spectator_began", playerId, {
		depth = depth,
		followingId = ghost.targetId,
		followable = #followable(),
	})
end

function SpectatorService.init()
	Remotes.get("SpectatorAction").OnServerEvent:Connect(function(player: Player, action: unknown)
		if not RequestGuard.allow(player, "SpectatorAction") then
			return
		end
		if type(action) ~= "string" then
			return
		end
		local ghost = ghosts[player.UserId]
		if ghost == nil then
			return
		end
		local now = Workspace:GetServerTimeNow()
		if action == "follow" then
			ghost.targetId = SpectatorRules.nextFollowTarget(followable(), ghost.targetId)
			local targetId = ghost.targetId
			local target = if targetId ~= nil then PlayerState.get(targetId) else nil
			if target ~= nil then
				-- ASKING TO FOLLOW IS ASKING TO BE TAKEN THERE. The automatic pull is a leash for getting
				-- lost; the key press is the deliberate act, so it overrides both the grace window and the
				-- distance test. The remote is rate-limited (Config/Security) and the destination is still
				-- a teammate's own feet, so there is nothing here to abuse.
				anchorTo(player.UserId, ghost, target, now)
			end
		elseif action == "release" then
			ghost.targetId = nil
		else
			return
		end
		-- Immediate feedback: the readout must change on the key press, not on the next send tick.
		replicateTo(player.UserId)
	end)
end

function SpectatorService.tick(dt: number)
	local now = Workspace:GetServerTimeNow()
	recordFootfalls(now)

	if next(ghosts) ~= nil then
		local candidates = followable()
		for playerId, ghost in ghosts do
			stepGhost(playerId, ghost, candidates, now)
		end
	end

	sendAccumulator += dt
	local step = 1 / math.max(Config.Spectator.trail.sendHz, 0.1)
	if sendAccumulator < step then
		return
	end
	sendAccumulator -= step
	pruneFootfalls(now)
	for playerId in ghosts do
		replicateTo(playerId)
	end
end

function SpectatorService.clear(playerId: Types.PlayerId)
	ghosts[playerId] = nil
	samples[playerId] = nil
	lastSamplePosition[playerId] = nil
	lastSentSeq[playerId] = nil
	lastSentSummary[playerId] = nil
	pendingReset[playerId] = nil
end

-- Run teardown. Bodies are not destroyed here: every teardown path already despawns the characters it
-- owns (RunOrchestrator's restart and lobby return both do), and destroying a body from a service that
-- does not create the replacement is how a player ends up with no character at all.
function SpectatorService.reset()
	table.clear(ghosts)
	table.clear(samples)
	table.clear(lastSamplePosition)
	table.clear(lastSentSeq)
	table.clear(lastSentSummary)
	table.clear(pendingReset)
	nextSeq = 0
	sendAccumulator = 0
end

return SpectatorService

--!strict
-- The two death states (DESIGN §7) and relighting. Snuffed: incapacitated, wax remaining,
-- revivable by a lit teammate who personally pays the cost. BurnOut / expired snuff: terminal —
-- the player becomes a ghost candle and keeps watching (server/SpectatorService owns that form).
-- Water's "instant and absolute" kill routes here as a terminal snuff.
--
-- Going out is always something the world does to you: players have no action that extinguishes
-- their own flame (Cup covers the light instead), so every state here is involuntary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local SpectatorService = require(script.Parent.SpectatorService)
local DevTestSessionRegistry = require(script.Parent.DevTestSessionRegistry)
local MovementService = require(script.Parent.MovementService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local ExtractionService = require(script.Parent.ExtractionService)
local RemainsService = require(script.Parent.RemainsService)
local RunSummaryService = require(script.Parent.RunSummaryService)
local Telemetry = require(script.Parent.Telemetry)

local DeathService = {}

local relightPrompts: { [Types.PlayerId]: ProximityPrompt } = {}
local snuffReasons: { [Types.PlayerId]: string } = {}
-- Which threat/hazard id caused the snuff, kept alongside its reason so a snuff that expires into a
-- terminal kill (`tick` below) can still tell the death-hint system what actually did this.
local snuffSourceIds: { [Types.PlayerId]: string? } = {}

local function removeRelightPrompt(playerId: Types.PlayerId)
	local prompt = relightPrompts[playerId]
	if prompt ~= nil then
		prompt:Destroy()
		relightPrompts[playerId] = nil
	end
end

local tryRelight: (Player, Types.PlayerId) -> ()
local trySelfRelight: (Player, Types.PlayerId) -> ()

-- The prompt lives on the candle's own root, so it is built here rather than inline in `snuff`:
-- a body that gets replaced underneath a still-snuffed player (RunOrchestrator's stranded-runner
-- recovery) has to be given the prompt again, or nobody can reach them.
local function attachRelightPrompt(playerId: Types.PlayerId, selfRelightAvailable: boolean)
	local root = CharacterService.rootPart(playerId)
	if root == nil then
		return
	end
	removeRelightPrompt(playerId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if selfRelightAvailable then "Use Match" else "Relight"
	prompt.ObjectText = if selfRelightAvailable then "Relight yourself" else "Snuffed candle"
	prompt.HoldDuration = Config.Death.relightHoldSeconds
	prompt.MaxActivationDistance = Config.Death.relightRange
	prompt.RequiresLineOfSight = false
	-- The prompt is shared so teammates can see it. The owner ID lets the local client hide
	-- the unusable prompt from the snuffed candle itself.
	prompt:SetAttribute("WickRelightTargetId", playerId)
	prompt:SetAttribute("WickSelfRelight", selfRelightAvailable)
	prompt.Triggered:Connect(function(reviver: Player)
		if reviver.UserId == playerId then
			trySelfRelight(reviver, playerId)
		else
			tryRelight(reviver, playerId)
		end
	end)
	prompt.Parent = root
	relightPrompts[playerId] = prompt
end

function tryRelight(reviver: Player, targetId: Types.PlayerId)
	local reviverState = PlayerState.get(reviver.UserId)
	local targetState = PlayerState.get(targetId)
	if reviverState == nil or targetState == nil then
		return
	end
	if targetState.snuffedAt == nil or not targetState.alive then
		return
	end
	if not reviverState.alive or reviverState.finished or not reviverState.isLit then
		return
	end
	if not reviverState.modifiers.canRelight then
		return
	end
	-- The reviver personally gives a piece of their life — and it can never burn them out.
	local relightCost = Config.Death.relightWaxCost * reviverState.modifiers.relightCostMultiplier
	if reviverState.wax.current <= relightCost then
		return
	end
	reviverState.wax = WaxAccounting.spend(reviverState.wax, reviverState.waxLedger, relightCost, "ReviveCost")

	targetState.snuffedAt = nil
	targetState.isLit = true
	targetState.litChangedAt = os.clock()
	snuffReasons[targetId] = nil
	snuffSourceIds[targetId] = nil
	removeRelightPrompt(targetId)
	MovementService.refresh(targetId)
end

function trySelfRelight(player: Player, targetId: Types.PlayerId)
	if player.UserId ~= targetId then
		return
	end
	local state = PlayerState.get(targetId)
	if state == nil or not state.alive or state.finished or state.snuffedAt == nil then
		return
	end
	if not state.isSoloRun or state.matchCharges <= 0 then
		return
	end
	state.matchCharges -= 1
	state.snuffedAt = nil
	state.isLit = true
	state.litChangedAt = os.clock()
	snuffReasons[targetId] = nil
	snuffSourceIds[targetId] = nil
	removeRelightPrompt(targetId)
	MovementService.refresh(targetId)
end

-- True if some other runner is still an active participant in this expedition (alive, not yet
-- finished) and could in principle reach and relight this player. Deliberately server-population-
-- independent: a full server can still leave one player functionally solo (party smaller than the
-- server, teammates already burned out/cashed out, or a late arrival not yet spawned into a run).
local function hasReachableTeammate(playerId: Types.PlayerId): boolean
	for otherId, otherState in PlayerState.all() do
		if
			otherId ~= playerId
			and not DevTestSessionRegistry.isProtected(otherId)
			and otherState.alive
			and not otherState.finished
		then
			return true
		end
	end
	return false
end

-- Involuntary snuff (snuffer-type threats, …). Revivable — unless this player sacrificed
-- being relit, in which case going out is going out for good. `sourceId` names the threat/hazard
-- that caused it (e.g. "Moth", "Dripstone") for the death-hint system (Config/Feel.deathHints);
-- nil for causes with no single attributable actor.
function DeathService.snuff(playerId: Types.PlayerId, reason: string?, sourceId: string?)
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished or state.snuffedAt ~= nil then
		return
	end
	if DevTestSessionRegistry.isProtected(playerId) then
		return
	end
	local snuffReason = reason or "Your flame was snuffed."
	if not state.modifiers.canBeRelit then
		DeathService.kill(playerId, "Snuffed", snuffReason, sourceId)
		return
	end
	local selfRelightAvailable = state.isSoloRun and state.matchCharges > 0
	if Config.Death.soloSnuffIsTerminal and not hasReachableTeammate(playerId) and not selfRelightAvailable then
		DeathService.kill(playerId, "Snuffed", snuffReason .. " There is no one to relight you.", sourceId)
		return
	end
	local now = os.clock()
	state.isLit = false
	state.litChangedAt = now
	state.snuffedAt = now
	state.isCupping = false
	state.flareEndsAt = 0
	snuffReasons[playerId] = snuffReason
	snuffSourceIds[playerId] = sourceId
	MovementService.refresh(playerId)
	CharacterService.applyLight(playerId, 0, 0, false)

	attachRelightPrompt(playerId, selfRelightAvailable)
end

-- Give a rebuilt body its relight prompt back. The only caller is RunOrchestrator's stranded-runner
-- recovery, which replaces a body the engine or the world took away; being incapacitated must not
-- also mean being unrevivable because the candle you were attached to is a different instance now.
function DeathService.rebindRelightPrompt(playerId: Types.PlayerId)
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished or state.snuffedAt == nil then
		return
	end
	attachRelightPrompt(playerId, state.isSoloRun and state.matchCharges > 0)
end

function DeathService.burnOut(playerId: Types.PlayerId, reason: string?, sourceId: string?)
	DeathService.kill(playerId, "BurnOut", reason or "Your candle ran out of wax.", sourceId)
end

-- Terminal. Deposits session remains, reports the result, and swaps the body for a ghost candle.
function DeathService.kill(playerId: Types.PlayerId, cause: Types.DeathCause, reason: string?, sourceId: string?)
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished then
		return
	end
	if DevTestSessionRegistry.isProtected(playerId) then
		return
	end
	local debug = {
		trigger = reason or (if cause == "BurnOut" then "Your candle ran out of wax." else "Your flame was snuffed."),
		waxRemaining = state.wax.current,
		maxWax = state.wax.max,
		burnRate = state.burnRate,
		movementMode = state.movementMode,
		depth = state.depth,
	}
	state.alive = false
	state.isLit = false
	state.snuffedAt = nil
	state.isCupping = false
	state.flareEndsAt = 0
	removeRelightPrompt(playerId)
	snuffReasons[playerId] = nil
	snuffSourceIds[playerId] = nil

	-- PHASE 8: half of what they were carrying lands on the body and half shatters (Config/Extraction).
	-- The recoverable half rides the SAME candle-remains record as the wax, so a teammate walking to a
	-- friend's body finds one pile with one prompt rather than two things to hoover up.
	--
	-- No owner lock: the owner is dead and this run is over for them, so there is nobody to hold it
	-- for. A SNUFF never reaches here, which is why an incapacitated player keeps their whole bag and
	-- a revive costs no cargo — being relit should not be taxed twice.
	local droppedCargo, droppedGrams, shatteredGrams = ExtractionService.splitOnDeath(playerId)
	local record = Interfaces.Remains.deposit({
		playerId = playerId,
		depth = state.depth,
		position = state.position,
		wax = state.wax.current * Config.Death.remainsWaxFraction,
		cargo = droppedCargo,
		ownerLockUntil = 0,
	})
	-- Put it in the world NOW, on the floor that is currently standing. Remains used to appear only
	-- when a floor was built, which was fine when they were a gift to a future expedition — but a
	-- party is expected to walk back for this one while the body is still warm.
	RemainsService.spawnLive(record)
	-- Whatever was left is gone with the candle; attribute it so the summary reconciles to zero.
	state.wax = WaxAccounting.drainToEmpty(state.wax, state.waxLedger, "DeathLoss")
	-- A death cancels the party's "everyone came back" bonus for every member, including those who
	-- already cashed out. Recorded before the profile write so the settle below sees it.
	ExtractionService.noteDeath(playerId)

	local profile = Interfaces.Persistence.get(playerId)
	profile.runsCompleted += 1
	-- Progression records how deep in the cave you got, which is the canonical depth.
	profile.deepestFloor = math.max(profile.deepestFloor, PlayerState.globalDepth(state))
	Interfaces.Persistence.save(playerId, profile)
	-- Dying still counts: the board ranks how deep you got, not whether you came back.
	Interfaces.Leaderboard.submit(playerId, profile.deepestFloor)
	LeaderboardService.requestRefresh()
	Telemetry.event("player_death", playerId, {
		cause = cause,
		depth = state.depth,
		globalDepth = PlayerState.globalDepth(state),
		reason = debug.trigger,
		rawWaxDropped = droppedGrams,
		rawWaxShattered = shatteredGrams,
	})
	-- Development-only accounting readout: what this run actually spent its wax on.
	RunSummaryService.emit(playerId, if cause == "BurnOut" then "BurnOut" else "Snuff")
	ExtractionService.emitRunSummary(playerId, if cause == "BurnOut" then "BurnOut" else "Snuff", debug.waxRemaining)
	-- This player's run is over. If they were the last one still down there, the survivors settle now
	-- — though a death has already cancelled the bonus, so this call pays nothing and simply closes
	-- the run out. It stays here so every resolution path ends the same way.
	ExtractionService.settlePartyBonus()

	-- THE CARD LANDS IMMEDIATELY, and nothing is staged in front of it.
	--
	-- This used to be a longer note arguing that a death should not get the extraction's five-second
	-- lamp-cascade beat. That beat no longer exists for anybody: lighting the cave is a mid-run player
	-- action now (server/WallLampService) and cashing out at the Brazier reveals its card at once, so
	-- there is no longer an asymmetry here to defend.
	--
	-- What remains true is the reason the argument landed where it did. Death already has its own
	-- beat and it is not a lighting shot: the snuff, the remains hitting the floor where they fell,
	-- and the handover to a ghost. Anything held in front of the card would be spent bodyless, since
	-- a death hands the player straight to SpectatorService below.
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		Remotes.get("RunEvent"):FireClient(player, "results", {
			survived = false,
			deathCause = cause,
			deathSourceId = sourceId,
			depthReached = state.depth,
			waxDelivered = 0,
			reward = 0,
			deathDebug = debug,
			depositsMined = state.depositsMinedThisRun,
			depositsMinedAtDepths = state.depositsMinedAtDepths,
			-- What the dark just took, and what it left behind for the others. The dropped figure is
			-- the one that matters to a player watching their own results card: it tells them their
			-- run was not entirely wasted if their party can reach the body.
			rawWax = ExtractionService.resultsPayload(playerId),
			-- Whether there is still an expedition to watch. The results card uses it to offer the
			-- spectator its dismiss button instead of pinning a dead player behind a summary while their
			-- party is still alive in the room in front of them.
			partyStillInside = hasReachableTeammate(playerId),
		})
		-- The run is over for them, so what follows is not gameplay: it is a body to watch it from
		-- (DESIGN §7). SpectatorService owns the ghost from here — this call is the whole handover.
		SpectatorService.onDeath(player, state.position, state.depth)
	end
end

-- Expire snuffed states into terminal deaths.
function DeathService.tick()
	local now = os.clock()
	for playerId, state in PlayerState.all() do
		local snuffedAt = state.snuffedAt
		if snuffedAt ~= nil and state.alive and now - snuffedAt >= Config.Death.snuffStateDuration then
			local reason = snuffReasons[playerId] or "Your flame was snuffed."
			DeathService.kill(playerId, "Snuffed", reason .. " No one relit you in time.", snuffSourceIds[playerId])
		end
	end
end

function DeathService.reset()
	for playerId in relightPrompts do
		removeRelightPrompt(playerId)
	end
	table.clear(snuffReasons)
	table.clear(snuffSourceIds)
end

return DeathService

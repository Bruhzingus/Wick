--!strict
-- Expedition state machine: lobby handoff -> countdown -> build -> descend -> all resolved ->
-- reset. Public lobby/teleport ownership lives in PartyLobbyService, not here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local FloorPlanner = require(ReplicatedStorage.Shared.Logic.FloorPlanner)
local DepthRules = require(ReplicatedStorage.Shared.Logic.DepthRules)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local EntrySpawnRules = require(ReplicatedStorage.Shared.Logic.EntrySpawnRules)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local EnvironmentSetup = require(script.Parent.EnvironmentSetup)
local FloorBuilder = require(script.Parent.FloorBuilder)
local HazardService = require(script.Parent.HazardService)
local DripstoneService = require(script.Parent.DripstoneService)
local ThreatService = require(script.Parent.ThreatService)
local BasinService = require(script.Parent.BasinService)
local BrazierService = require(script.Parent.BrazierService)
local DripTrailService = require(script.Parent.DripTrailService)
local ToolService = require(script.Parent.ToolService)
local DeathService = require(script.Parent.DeathService)
local WaxService = require(script.Parent.WaxService)
local MovementService = require(script.Parent.MovementService)
local MovementSanityService = require(script.Parent.MovementSanityService)
local LootService = require(script.Parent.LootService)
local MiningService = require(script.Parent.MiningService)
local NoiseService = require(script.Parent.NoiseService)
local ContractWatchService = require(script.Parent.ContractWatchService)
local ExtractionService = require(script.Parent.ExtractionService)
-- One-directional: PartyLobbyService reaches this module through the start callback wired in
-- init.server, never by requiring it, so this import introduces no cycle.
local PartyLobbyService = require(script.Parent.PartyLobbyService)
local RemainsService = require(script.Parent.RemainsService)
local VineService = require(script.Parent.VineService)
local AshamedLurkerService = require(script.Parent.AshamedLurkerService)
local WardenRegistry = require(script.Parent.WardenRegistry)
local StoneWardenService = require(script.Parent.StoneWardenService)
local RequestGuard = require(script.Parent.RequestGuard)
local RunSummaryService = require(script.Parent.RunSummaryService)
local Telemetry = require(script.Parent.Telemetry)

local RunOrchestrator = {}

type Phase = "Waiting" | "Countdown" | "Running" | "Restarting"
type LobbyReturnHandler = () -> ()

local phase: Phase = "Waiting"
local phaseDeadline = 0
local currentTierId = 1
-- Absolute depth the current expedition starts at. Server-authoritative and the only place a run's
-- global depth is anchored: every player's globalDepth is this plus their floor ordinal minus one.
local currentStartDepth = 1
local currentRunSeed = 0
-- Monotonic within this server's lifetime. Only job is to keep two expeditions that start in the same
-- second from deriving the same run id, and therefore the same currency transaction ids.
local runCounter = 0
local currentThreatBudgetMultiplier = 1
local currentDripstoneMultiplier = 1
-- THE UNION of every member's owned Lamp Network nodes, resolved once at descent and held for the
-- whole expedition. Read only by the floor planner, and only to decide which deposit rows may appear.
--
-- A UNION RATHER THAN THE LEADER'S OWN SET, because a floor is one shared thing: if it were the
-- leader's, a player who bought Twin Seam would stop finding them the moment somebody else pulled the
-- lever, which is indistinguishable from the purchase not working.
--
-- CAPTURED ONCE, not re-read per floor. Later floors are built on demand, and a player buying a node
-- mid-expedition must not retroactively change what the cave contains — the run has to be the cave
-- everybody descended into.
local currentUnlockedNodes: { [string]: boolean } = {}
local floors: { [number]: FloorBuilder.FloorRuntime } = {}
local floorsFolder: Folder? = nil
local queuedRunners: { [Types.PlayerId]: boolean } = {}
local runners: { [Types.PlayerId]: boolean } = {}
local runnerSlots: { [Types.PlayerId]: number } = {}
local lobbyReturnHandler: LobbyReturnHandler? = nil
local startingRunnerCount = 0

local function broadcast(kind: string, payload: { [string]: unknown })
	Remotes.get("RunEvent"):FireAllClients(kind, payload)
end

local function beginCountdown()
	phase = "Countdown"
	phaseDeadline = os.clock() + Config.Run.startCountdownSeconds
	broadcast("countdown", { seconds = Config.Run.startCountdownSeconds, tierId = currentTierId })
end

local function reserveRunnerSlot(playerId: Types.PlayerId): number?
	local existing = runnerSlots[playerId]
	if existing ~= nil then
		return existing
	end
	local occupied: { [number]: boolean } = {}
	for _, slot in runnerSlots do
		occupied[slot] = true
	end
	for slot = 1, Config.Run.partyCap do
		if not occupied[slot] then
			runnerSlots[playerId] = slot
			return slot
		end
	end
	return nil
end

local function entryForRunner(playerId: Types.PlayerId, entryCenter: Vector3): Vector3?
	local slot = reserveRunnerSlot(playerId)
	return if slot ~= nil then EntrySpawnRules.positionForSlot(entryCenter, slot) else nil
end

local function spawnRunner(player: Player, entryCenter: Vector3)
	local entry = entryForRunner(player.UserId, entryCenter)
	if entry == nil then
		return
	end
	runners[player.UserId] = true
	-- The contract comes from the run's own snapshot (taken in ExtractionService.beginRun, which has
	-- already run by the time anyone spawns), never from the live profile.
	PlayerState.reset(
		player.UserId,
		startingRunnerCount == 1,
		currentStartDepth,
		ExtractionService.contractFor(player.UserId)
	)
	-- Elevator doors open directly into the cave: CharacterService.spawn always clears any lobby
	-- candle first (see its own despawnLobby call), so the run rig replaces it cleanly.
	CharacterService.spawn(player, entry)
	MovementService.refresh(player.UserId)
	MovementSanityService.markAuthorized(player.UserId, entry)
	Remotes.get("RunEvent"):FireClient(player, "floor", {
		depth = 1,
		globalDepth = DepthRules.getGlobalDepth(currentStartDepth, 1),
		tierId = currentTierId,
	})
end

local function buildFloor(localFloor: number): FloorBuilder.FloorRuntime?
	local existing = floors[localFloor]
	if existing ~= nil then
		return existing
	end
	local folder = floorsFolder
	if folder == nil then
		return nil
	end
	local globalDepth = DepthRules.getGlobalDepth(currentStartDepth, localFloor)
	local plan = FloorPlanner.plan({
		globalDepth = globalDepth,
		localFloor = localFloor,
		rng = Random.new(DepthRules.getFloorSeed(currentRunSeed, currentTierId, globalDepth)),
		threatBudgetMultiplier = currentThreatBudgetMultiplier,
		dripstoneMultiplier = currentDripstoneMultiplier,
		unlockedNodes = currentUnlockedNodes,
	})
	local runtime = FloorBuilder.build(plan)
	runtime.model.Parent = folder
	floors[plan.depth] = runtime
	HazardService.registerFloor(plan.depth, runtime.waterRegions)
	DripstoneService.registerFloor(plan.depth, runtime.dripstones)
	VineService.registerFloor(plan.depth, runtime.vines)
	AshamedLurkerService.registerFloor(plan.depth, runtime.lurkers)
	local builtThreats = ThreatService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces)
	local builtLoot = LootService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	local builtWarden = StoneWardenService.spawnFloor(plan, runtime.roomSurfaces, runtime.model)
	MiningService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	RemainsService.spawnFloor(plan, runtime.roomCenters, runtime.model)
	BasinService.registerFloor(plan.depth, runtime.basinPosition, runtime.model)
	BrazierService.registerFloor(plan.depth, runtime.brazierPosition, runtime.model)
	Telemetry.event("floor_spawn_audit", nil, {
		depth = plan.depth,
		globalDepth = plan.globalDepth,
		plannedThreats = #plan.threatSpawns,
		builtThreats = builtThreats,
		plannedLoot = #plan.lootSpawns,
		builtLoot = builtLoot,
		plannedLurkers = #plan.lurkers,
		builtLurkers = #runtime.lurkers,
		plannedWarden = plan.warden ~= nil,
		builtWarden = builtWarden,
	})
	return runtime
end

-- ADMISSION. Every party member pays their own fee for a paid cave, once, at the moment the cave is
-- built. Owning the cave outright makes the fee zero (Interfaces/CaveTiers), so this is also the only
-- place a permanent unlock has to be honoured.
--
-- Affordability was already validated when the party readied up, so a refusal here means something
-- changed underneath us (a purchase elsewhere, a session that ended). The run still proceeds for the
-- players who did pay: kicking a party out of a cave that is already being carved would be a worse
-- outcome than one player getting a free ride, and the refusal is logged loudly enough to notice.
local function chargeAdmission(tierId: number, memberIds: { Types.PlayerId }, runId: string)
	for _, playerId in memberIds do
		local fee = Interfaces.CaveTiers.entryFeeFor(playerId, tierId)
		if fee <= 0 then
			continue
		end
		local result = Interfaces.CaveTiers.chargeEntry(playerId, tierId, string.format("%s:entry:%d", runId, playerId))
		if not result.ok then
			warn(
				string.format(
					"[WICK] Admission to tier %d could not be charged to user %d (%s); they descend unbilled.",
					tierId,
					playerId,
					tostring(result.failure)
				)
			)
		end
		Telemetry.event("cave_admission", playerId, {
			runId = runId,
			tier = tierId,
			fee = fee,
			ok = result.ok,
			balance = result.balance,
		})
	end
end

-- Record on each profile that this player is mid-run, and where. Read on join by RejoinService to
-- decide whether to send them back into the expedition they dropped from rather than leaving them in
-- a fresh public lobby with their bag lying on a floor they can no longer reach.
local function markPlayersInRun(memberIds: { Types.PlayerId }, runId: string)
	local accessCode = PartyLobbyService.reservedAccessCode()
	if accessCode == nil then
		-- A run started outside a reserved server (Studio, or a local start). There is nowhere to send
		-- a dropped player back TO, so no pointer is written — a marker without a valid access code
		-- would only ever produce failed teleports.
		return
	end
	for _, playerId in memberIds do
		local profile = Interfaces.Persistence.get(playerId)
		profile.activeRunServer = game.PrivateServerId
		profile.activeRunAccessCode = accessCode
		profile.activeRunId = runId
		profile.activeRunStartedAt = os.time()
		Interfaces.Persistence.save(playerId, profile)
	end
end

-- Clear that marker. Called for every player as the expedition resolves, so a finished run never
-- pulls a returning player back into a cave that no longer exists.
local function clearRunMarker(playerId: Types.PlayerId)
	local profile = Interfaces.Persistence.get(playerId)
	if profile.activeRunId == nil then
		return
	end
	profile.activeRunServer = nil
	profile.activeRunId = nil
	profile.activeRunStartedAt = nil
	Interfaces.Persistence.save(playerId, profile)
end

local function startRun()
	local tier = Interfaces.CaveTiers.get(currentTierId) or Interfaces.CaveTiers.list()[1]
	currentStartDepth = tier.startDepth
	if not DepthRules.isSupportedDepth(currentStartDepth) then
		Telemetry.event("run_start_rejected", nil, { tier = tier.id, startDepth = currentStartDepth })
		phase = "Waiting"
		return
	end
	currentThreatBudgetMultiplier = tier.threatBudgetMultiplier
	currentDripstoneMultiplier = tier.dripstoneMultiplier
	phase = "Running"
	BrazierService.setCaveTier(tier.id)
	WaxService.setCaveTier(tier.id)
	-- TODO (PHASE 10 HOOK 2 of 4 — `CaveTier.biomeId`, Config/CaveTiers): the one place a run learns
	-- which cave it is. Anything a biome needs chosen ONCE per expedition rather than once per floor —
	-- a skybox, a global particle emitter, an ambience bed, a per-biome sound bank — belongs at this
	-- call site, because `tier` is in scope here and nowhere downstream. Per-FLOOR flavour does not:
	-- that is hook 3 (FloorBuilder's palette) and hook 4 (Config/Floors dressing).
	--
	-- Blocked on the documentation conflict recorded at `NEUTRAL_BIOME` in Config/CaveTiers.
	EnvironmentSetup.applyCaveTier(tier.atmosphereColor, tier.atmosphereDecay)

	-- Floors are drawn as smooth Terrain (which lives outside the floor model), so clear any left
	-- over the cave before carving the new one.
	workspace.Terrain:Clear()

	local folder = Instance.new("Folder")
	folder.Name = "WickFloors"
	folder.Parent = workspace
	floorsFolder = folder
	ThreatService.setFloorsFolder(folder)

	currentRunSeed = os.time()

	-- THE RUN'S IDENTITY, and the namespace every currency transaction this expedition performs is
	-- keyed under. It must be unique per expedition on this server, because two runs sharing an id
	-- would let the second one's payout be rejected as a replay of the first's. JobId pins the server,
	-- the seed pins the expedition within it, and the counter covers the case of two runs starting in
	-- the same second.
	runCounter += 1
	local runId = string.format("%s:%d:%d", game.JobId, currentRunSeed, runCounter)
	local memberIds: { Types.PlayerId } = {}
	for playerId in queuedRunners do
		table.insert(memberIds, playerId)
	end
	table.sort(memberIds)
	-- Before the first floor is planned: which seam kinds this cave may contain.
	table.clear(currentUnlockedNodes)
	for _, playerId in memberIds do
		for _, nodeId in Interfaces.LampNetwork.ownedNodes(playerId) do
			currentUnlockedNodes[nodeId] = true
		end
	end

	ExtractionService.beginRun(runId, tier.id, memberIds)
	-- Admission is taken here, at the last possible moment before the cave exists, and never
	-- speculatively: everything that could still cancel this expedition has already happened.
	chargeAdmission(tier.id, memberIds, runId)
	markPlayersInRun(memberIds, runId)

	-- Keep the current floor and its successor ready. Each descent builds one more successor, so the
	-- expedition can continue indefinitely without eagerly constructing an arbitrary capped stack.
	buildFloor(1)
	buildFloor(2)
	startingRunnerCount = 0
	for _ in queuedRunners do
		startingRunnerCount += 1
	end
	table.clear(runners)
	local firstFloor = floors[1]
	if firstFloor ~= nil then
		for _, player in Players:GetPlayers() do
			if queuedRunners[player.UserId] then
				spawnRunner(player, firstFloor.entryPosition)
			end
		end
	end
	Telemetry.event("run_started", nil, {
		players = #Players:GetPlayers(),
		tier = currentTierId,
		startDepth = currentStartDepth,
		prebuiltFloors = 2,
		seed = currentRunSeed,
	})
end

local function teardown()
	ThreatService.reset()
	DripstoneService.reset()
	VineService.reset()
	AshamedLurkerService.reset()
	-- Wardens live inside the floor models below and notice their own teardown, but clearing the
	-- registry here keeps hazard lookups from ever seeing a floor that is already gone.
	WardenRegistry.reset()
	HazardService.reset()
	DripTrailService.reset()
	ToolService.reset()
	LootService.reset()
	MiningService.reset()
	-- Cargo, its dedup latches, the party-bonus ledger and the run id every transaction was keyed by
	-- die with the deposits that produced them. Nothing about Raw Wax survives a run boundary in any
	-- direction — and because transaction ids embed the run id, a replayed credit from a finished run
	-- cannot collide with a live one either.
	ExtractionService.reset()
	-- Candle remains deliberately outlive an expedition, but the CARGO on them must not: a haul that
	-- survived teardown would be free money deposited into the next run's floors.
	Interfaces.Remains.clearAllCargo()
	-- Deposits and their models are gone, so the noise they made must go with them: a stale event
	-- would otherwise let the next floor's threats investigate a sound from the previous one.
	NoiseService.reset()
	RemainsService.reset()
	BasinService.reset()
	ContractWatchService.reset()
	BrazierService.reset()
	DeathService.reset()
	RunSummaryService.reset()
	WaxService.reset()
	MovementSanityService.reset()
	table.clear(floors)
	table.clear(runners)
	table.clear(runnerSlots)
	table.clear(queuedRunners)
	startingRunnerCount = 0
	currentRunSeed = 0
	currentThreatBudgetMultiplier = 1
	currentDripstoneMultiplier = 1
	if floorsFolder ~= nil then
		floorsFolder:Destroy()
		floorsFolder = nil
	end
	-- The floor Terrain is not parented to the folder; clear it explicitly on teardown.
	workspace.Terrain:Clear()
	-- Nobody is mid-run any more. Clearing every marker here — rather than only on the paths that
	-- resolve a player cleanly — is what stops a crashed or abandoned expedition from pulling a
	-- returning player back into a cave that has already been demolished.
	for _, player in Players:GetPlayers() do
		clearRunMarker(player.UserId)
	end
end

local function queuePresentParty()
	table.clear(queuedRunners)
	local party = Interfaces.Party.snapshot()
	if party == nil then
		return
	end
	for _, playerId in party.members do
		if Players:GetPlayerByUserId(playerId) ~= nil then
			queuedRunners[playerId] = true
		end
	end
end

local function restartExpedition()
	teardown()
	queuePresentParty()
	if next(queuedRunners) ~= nil then
		beginCountdown()
	else
		phase = "Waiting"
	end
end

local function returnToLobby()
	for playerId in runners do
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil then
			CharacterService.despawn(player)
		end
	end
	teardown()
	phase = "Waiting"
	phaseDeadline = 0
	local callback = lobbyReturnHandler
	if callback ~= nil then
		callback()
	end
end

local function checkDescent()
	for playerId, state in PlayerState.all() do
		if not runners[playerId] or not state.alive or state.finished or state.snuffedAt ~= nil then
			continue
		end
		local runtime = floors[state.depth]
		local nextRuntime = floors[state.depth + 1]
		if runtime ~= nil and nextRuntime == nil then
			nextRuntime = buildFloor(state.depth + 1)
		end
		if runtime == nil or nextRuntime == nil then
			continue
		end
		local region = runtime.descentRegion
		local offset = state.position - region.center
		if
			math.abs(offset.X) <= region.size.X / 2
			and math.abs(offset.Y) <= region.size.Y / 2
			and math.abs(offset.Z) <= region.size.Z / 2
		then
			local entry = entryForRunner(playerId, nextRuntime.entryPosition)
			if entry == nil then
				continue
			end
			state.depth += 1
			state.position = entry
			buildFloor(state.depth + 1)
			local globalDepth = PlayerState.globalDepth(state)
			WaxAccounting.noteDepth(state.waxLedger, globalDepth)
			CharacterService.teleport(playerId, entry)
			MovementSanityService.markAuthorized(playerId, entry)
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil then
				Remotes.get("RunEvent"):FireClient(player, "floor", {
					depth = state.depth,
					globalDepth = globalDepth,
					tierId = currentTierId,
				})
			end
			Telemetry.event("floor_reached", playerId, {
				depth = state.depth,
				globalDepth = globalDepth,
				tier = currentTierId,
			})
		end
	end
end

local function runIsOver(): boolean
	for playerId in runners do
		local state = PlayerState.get(playerId)
		if state ~= nil and Players:GetPlayerByUserId(playerId) ~= nil and state.alive and not state.finished then
			return false
		end
	end
	return true
end

function RunOrchestrator.init(onLobbyReturn: LobbyReturnHandler?)
	lobbyReturnHandler = onLobbyReturn
	Remotes.get("RestartRun").OnServerEvent:Connect(function(player: Player)
		if not RequestGuard.allow(player, "RestartRun") then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil or (state.alive and not state.finished) then
			return
		end
		if (phase ~= "Running" and phase ~= "Restarting") or not runIsOver() then
			Remotes.get("RunEvent"):FireClient(player, "message", {
				text = "Restart is available when every runner has finished or died.",
			})
			return
		end
		Telemetry.event("run_restart_requested", player.UserId)
		restartExpedition()
	end)
	Remotes.get("ReturnToLobby").OnServerEvent:Connect(function(player: Player)
		if not RequestGuard.allow(player, "ReturnToLobby") then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil or (state.alive and not state.finished) then
			return
		end
		if (phase ~= "Running" and phase ~= "Restarting") or not runIsOver() then
			Remotes.get("RunEvent"):FireClient(player, "message", {
				text = "Lobby return is available when every runner has finished or died.",
			})
			return
		end
		Telemetry.event("run_lobby_return_requested", player.UserId)
		returnToLobby()
	end)
end

function RunOrchestrator.startFromLobby(tierId: number, memberIds: { Types.PlayerId })
	if phase ~= "Waiting" then
		return
	end
	local tier = Interfaces.CaveTiers.get(tierId)
	currentTierId = if tier ~= nil then tier.id else 1
	table.clear(queuedRunners)
	for _, playerId in memberIds do
		if Players:GetPlayerByUserId(playerId) ~= nil then
			queuedRunners[playerId] = true
			PlayerState.ensure(playerId)
		end
	end
	if next(queuedRunners) ~= nil then
		beginCountdown()
	end
end

function RunOrchestrator.onPlayerAdded(player: Player)
	PlayerState.ensure(player.UserId)
	if phase == "Countdown" then
		local party = Interfaces.Party.snapshot()
		if party ~= nil and table.find(party.members, player.UserId) ~= nil then
			queuedRunners[player.UserId] = true
		end
	elseif phase == "Running" then
		local party = Interfaces.Party.snapshot()
		local firstFloor = floors[1]
		if
			party ~= nil
			and table.find(party.members, player.UserId) ~= nil
			and firstFloor ~= nil
			and not runners[player.UserId]
		then
			spawnRunner(player, firstFloor.entryPosition)
		end
	end
end

-- Living Wax still on the candle at the moment a run resolves, for the experiment's summary line.
-- Zero for a player with no run state left to read.
local function waxRemainingFor(playerId: Types.PlayerId): number
	local state = PlayerState.get(playerId)
	return if state ~= nil then state.wax.current else 0
end

function RunOrchestrator.onPlayerRemoving(player: Player)
	if runners[player.UserId] then
		local leaving = PlayerState.get(player.UserId)
		-- WHETHER THIS PLAYER SHOULD BE PULLED BACK IN. A player who is still alive and still in the
		-- cave dropped out of a run they were playing, and their marker stays so RejoinService can
		-- return them to it. A player who already cashed out or already died has nothing to come back
		-- to, so their marker is cleared and rejoining puts them in a normal lobby.
		if leaving == nil or leaving.finished or not leaving.alive then
			clearRunMarker(player.UserId)
		end
		-- Leaving mid-run still resolves the run for accounting purposes.
		RunSummaryService.emit(player.UserId, "Disconnect")

		-- PHASE 8: THE BAG DROPS WHERE THEY STOOD, LOCKED TO THEM.
		--
		-- This is the shape that makes "it drops, and if you come back you get it back" safe. The pile
		-- IS the hold: the cargo is removed from the run state and placed in the world in one step, so
		-- at no instant does it exist in two places. During the grace window only its owner may claim
		-- it (Interfaces/Remains enforces the lock); after the window it unlocks for whoever is still
		-- down there. Nothing is ever taken back from a teammate who already picked it up, because
		-- "return it to the owner" and "credit it to the finder" cannot both be true.
		local state = PlayerState.get(player.UserId)
		local dropped, droppedUnits = ExtractionService.dropOnDisconnect(player.UserId)
		if droppedUnits > 0 and state ~= nil then
			local record = Interfaces.Remains.deposit({
				playerId = player.UserId,
				depth = state.depth,
				position = state.position,
				-- A disconnect leaves no candle behind — the body simply is not there any more. Only
				-- the haul drops, so this record carries cargo and no wax.
				wax = 0,
				cargo = dropped,
				ownerLockUntil = os.clock() + Config.Extraction.disconnectGraceSeconds,
			})
			-- Visible immediately, so the party sees where their teammate went down and can decide
			-- whether to wait out the lock or move on.
			RemainsService.spawnLive(record)
		end
		ExtractionService.emitRunSummary(player.UserId, "Disconnect", waxRemainingFor(player.UserId))
		-- A disconnect resolves this player WITHOUT cancelling the party bonus (Config/Extraction:
		-- connections drop for reasons that are not decisions). The survivors may still settle.
		ExtractionService.noteDisconnect(player.UserId)
		local bonuses = ExtractionService.settlePartyBonus()
		BrazierService.announceBonuses(bonuses)
	end
	RunSummaryService.clear(player.UserId)
	ExtractionService.clear(player.UserId)
	DripTrailService.clear(player.UserId)
	MiningService.clear(player.UserId)
	NoiseService.clear(player.UserId)
	CharacterService.despawn(player)
	MovementSanityService.clear(player.UserId)
	PlayerState.remove(player.UserId)
	queuedRunners[player.UserId] = nil
	runners[player.UserId] = nil
	runnerSlots[player.UserId] = nil
end

function RunOrchestrator.tick()
	local now = os.clock()
	if phase == "Countdown" and now >= phaseDeadline then
		if next(queuedRunners) ~= nil then
			startRun()
		else
			phase = "Waiting"
		end
	elseif phase == "Running" then
		checkDescent()
		if runIsOver() then
			phase = "Restarting"
			phaseDeadline = now + Config.Run.restartDelaySeconds
			broadcast("message", { text = "The caves grow quiet. Replay, or return to the lobby." })
			Telemetry.event("run_resolved", nil, { tier = currentTierId })
		end
	elseif phase == "Restarting" and now >= phaseDeadline then
		restartExpedition()
	end
end

return RunOrchestrator

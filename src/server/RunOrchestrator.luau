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
local RemainsService = require(script.Parent.RemainsService)
local VineService = require(script.Parent.VineService)
local WardenRegistry = require(script.Parent.WardenRegistry)
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
	PlayerState.reset(player.UserId, startingRunnerCount == 1, currentStartDepth)
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

local function startRun()
	local tier = Interfaces.CaveTiers.get(currentTierId) or Interfaces.CaveTiers.list()[1]
	currentStartDepth = tier.startDepth
	-- Development-only: ignore the tier's length and descend as far as the prototype ceiling allows.
	-- Never enabled in a shipped build (Config/Depth.development).
	local requestedFloors = if Config.Depth.development.enabled
		then Config.Depth.development.floorsPerRun
		else tier.maxFloors
	local floorCount = DepthRules.floorCountForRun(currentStartDepth, requestedFloors)
	if floorCount <= 0 then
		-- This tier asks to start outside the supported depth range. Refuse the expedition rather
		-- than quietly building a shallow substitute for it.
		Telemetry.event("run_start_rejected", nil, { tier = tier.id, startDepth = currentStartDepth })
		phase = "Waiting"
		return
	end
	phase = "Running"
	BrazierService.setCaveTier(tier.id)
	WaxService.setCaveTier(tier.id)
	EnvironmentSetup.applyCaveTier(tier.atmosphereColor, tier.atmosphereDecay)

	-- Floors are drawn as smooth Terrain (which lives outside the floor model), so clear any left
	-- over the cave before carving the new one.
	workspace.Terrain:Clear()

	local folder = Instance.new("Folder")
	folder.Name = "WickFloors"
	folder.Parent = workspace
	floorsFolder = folder
	ThreatService.setFloorsFolder(folder)

	local runSeed = os.time()
	local plans = FloorPlanner.planAll(
		runSeed,
		floorCount,
		tier.threatBudgetMultiplier,
		tier.dripstoneMultiplier,
		currentStartDepth,
		tier.id
	)
	for _, plan in plans do
		local runtime = FloorBuilder.build(plan)
		runtime.model.Parent = folder
		floors[plan.depth] = runtime
		HazardService.registerFloor(plan.depth, runtime.waterRegions)
		DripstoneService.registerFloor(plan.depth, runtime.dripstones)
		VineService.registerFloor(plan.depth, runtime.vines)
		ThreatService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces)
		LootService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
		RemainsService.spawnFloor(plan, runtime.roomCenters, runtime.model)
		BasinService.registerFloor(plan.depth, runtime.basinPosition, runtime.model)
		BrazierService.registerFloor(plan.depth, runtime.brazierPosition, runtime.model)
	end
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
		deepestGlobalDepth = DepthRules.getGlobalDepth(currentStartDepth, #plans),
		floors = #plans,
		seed = runSeed,
	})
end

local function teardown()
	ThreatService.reset()
	DripstoneService.reset()
	VineService.reset()
	-- Wardens live inside the floor models below and notice their own teardown, but clearing the
	-- registry here keeps hazard lookups from ever seeing a floor that is already gone.
	WardenRegistry.reset()
	HazardService.reset()
	DripTrailService.reset()
	ToolService.reset()
	LootService.reset()
	RemainsService.reset()
	BasinService.reset()
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
	if floorsFolder ~= nil then
		floorsFolder:Destroy()
		floorsFolder = nil
	end
	-- The floor Terrain is not parented to the folder; clear it explicitly on teardown.
	workspace.Terrain:Clear()
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

function RunOrchestrator.onPlayerRemoving(player: Player)
	if runners[player.UserId] then
		-- Leaving mid-run still resolves the run for accounting purposes.
		RunSummaryService.emit(player.UserId, "Disconnect")
	end
	RunSummaryService.clear(player.UserId)
	DripTrailService.clear(player.UserId)
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

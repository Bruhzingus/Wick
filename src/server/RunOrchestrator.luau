--!strict
-- Expedition state machine: lobby handoff -> countdown -> build -> descend -> all resolved ->
-- reset. Public lobby/teleport ownership lives in PartyLobbyService, not here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local FloorPlanner = require(ReplicatedStorage.Shared.Logic.FloorPlanner)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local FloorBuilder = require(script.Parent.FloorBuilder)
local HazardService = require(script.Parent.HazardService)
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
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)

local RunOrchestrator = {}

type Phase = "Waiting" | "Countdown" | "Running" | "Restarting"
type LobbyReturnHandler = () -> ()

local phase: Phase = "Waiting"
local phaseDeadline = 0
local currentTierId = 1
local floors: { [number]: FloorBuilder.FloorRuntime } = {}
local floorsFolder: Folder? = nil
local queuedRunners: { [Types.PlayerId]: boolean } = {}
local runners: { [Types.PlayerId]: boolean } = {}
local lobbyReturnHandler: LobbyReturnHandler? = nil

local function broadcast(kind: string, payload: { [string]: unknown })
	Remotes.get("RunEvent"):FireAllClients(kind, payload)
end

local function beginCountdown()
	phase = "Countdown"
	phaseDeadline = os.clock() + Config.Run.startCountdownSeconds
	broadcast("countdown", { seconds = Config.Run.startCountdownSeconds, tierId = currentTierId })
end

local function spawnRunner(player: Player, entry: Vector3)
	runners[player.UserId] = true
	PlayerState.reset(player.UserId)
	CharacterService.spawn(player, entry)
	MovementService.refresh(player.UserId)
	MovementSanityService.markAuthorized(player.UserId, entry)
	Remotes.get("RunEvent"):FireClient(player, "floor", { depth = 1, tierId = currentTierId })
end

local function startRun()
	local tier = Interfaces.CaveTiers.get(currentTierId) or Interfaces.CaveTiers.list()[1]
	phase = "Running"
	BrazierService.setCaveTier(tier.id)

	local folder = Instance.new("Folder")
	folder.Name = "WickFloors"
	folder.Parent = workspace
	floorsFolder = folder
	ThreatService.setFloorsFolder(folder)

	local plans = FloorPlanner.planAll(os.time(), tier.maxFloors, tier.threatBudgetMultiplier)
	for _, plan in plans do
		local runtime = FloorBuilder.build(plan)
		runtime.model.Parent = folder
		floors[plan.depth] = runtime
		HazardService.registerFloor(plan.depth, runtime.draftZones, runtime.waterRegions)
		ThreatService.spawnFloor(plan, runtime.roomCenters)
		LootService.spawnFloor(plan, runtime.roomCenters, runtime.model)
		RemainsService.spawnFloor(plan, runtime.roomCenters, runtime.model)
		BasinService.registerFloor(plan.depth, runtime.basinPosition, runtime.model)
		BrazierService.registerFloor(plan.depth, runtime.brazierPosition, runtime.model)
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
		floors = #plans,
	})
end

local function teardown()
	ThreatService.reset()
	HazardService.reset()
	DripTrailService.reset()
	ToolService.reset()
	LootService.reset()
	RemainsService.reset()
	BasinService.reset()
	BrazierService.reset()
	DeathService.reset()
	WaxService.reset()
	MovementSanityService.reset()
	table.clear(floors)
	table.clear(runners)
	table.clear(queuedRunners)
	if floorsFolder ~= nil then
		floorsFolder:Destroy()
		floorsFolder = nil
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
			state.depth += 1
			state.position = nextRuntime.entryPosition
			CharacterService.teleport(playerId, nextRuntime.entryPosition)
			MovementSanityService.markAuthorized(playerId, nextRuntime.entryPosition)
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil then
				Remotes.get("RunEvent"):FireClient(player, "floor", {
					depth = state.depth,
					tierId = currentTierId,
				})
			end
			Telemetry.event("floor_reached", playerId, { depth = state.depth, tier = currentTierId })
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
	DripTrailService.clear(player.UserId)
	CharacterService.despawn(player)
	MovementSanityService.clear(player.UserId)
	PlayerState.remove(player.UserId)
	queuedRunners[player.UserId] = nil
	runners[player.UserId] = nil
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

--!strict
-- The run state machine: countdown -> build floors -> descend -> everyone finished or dead ->
-- reset and go again. Owns floor runtimes and per-player descent; owns nothing that another
-- service already owns.

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

local RunOrchestrator = {}

type Phase = "Waiting" | "Countdown" | "Running" | "Restarting"

local phase: Phase = "Waiting"
local phaseDeadline = 0
local floors: { [number]: FloorBuilder.FloorRuntime } = {}
local floorsFolder: Folder? = nil
local runners: { [Types.PlayerId]: boolean } = {} -- who is in the current run's party

local function broadcast(kind: string, payload: { [string]: unknown })
	Remotes.get("RunEvent"):FireAllClients(kind, payload)
end

local function presentIds(): { Types.PlayerId }
	local ids: { Types.PlayerId } = {}
	for _, player in Players:GetPlayers() do
		table.insert(ids, player.UserId)
	end
	return ids
end

local function beginCountdown()
	phase = "Countdown"
	phaseDeadline = os.clock() + Config.Run.startCountdownSeconds
	broadcast("countdown", { seconds = Config.Run.startCountdownSeconds })
end

local function startRun()
	phase = "Running"

	local folder = Instance.new("Folder")
	folder.Name = "WickFloors"
	folder.Parent = workspace
	floorsFolder = folder

	local plans = FloorPlanner.planAll(os.time())
	for _, plan in plans do
		local runtime = FloorBuilder.build(plan)
		runtime.model.Parent = folder
		floors[plan.depth] = runtime
		HazardService.registerFloor(plan.depth, runtime.draftZones, runtime.waterRegions)
		ThreatService.spawnFloor(plan, runtime.roomCenters)
		BasinService.registerFloor(plan.depth, runtime.basinPosition, runtime.model)
		BrazierService.registerFloor(plan.depth, runtime.brazierPosition, runtime.model)
	end
	ThreatService.setFloorsFolder(folder)

	-- Party via the stub interface: everyone present, capped. Late joiners beyond cap spectate.
	local ids = presentIds()
	local party: { [Types.PlayerId]: boolean } = {}
	if #ids > 0 then
		for _, memberId in Interfaces.Party.getParty(ids[1], ids, Config.Run.partyCap).members do
			party[memberId] = true
		end
	end

	table.clear(runners)
	local entry = floors[1].entryPosition
	for _, player in Players:GetPlayers() do
		if party[player.UserId] then
			runners[player.UserId] = true
			PlayerState.reset(player.UserId)
			CharacterService.spawn(player, entry)
			MovementService.refresh(player.UserId)
			Remotes.get("RunEvent"):FireClient(player, "floor", { depth = 1 })
		else
			Remotes.get("RunEvent")
				:FireClient(player, "message", { text = "The party is full. Wait for the next descent." })
		end
	end
end

local function teardown()
	ThreatService.reset()
	HazardService.reset()
	DripTrailService.reset()
	ToolService.reset()
	BasinService.reset()
	BrazierService.reset()
	DeathService.reset()
	WaxService.reset()
	table.clear(floors)
	table.clear(runners)
	if floorsFolder ~= nil then
		floorsFolder:Destroy()
		floorsFolder = nil
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
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil then
				Remotes.get("RunEvent"):FireClient(player, "floor", { depth = state.depth })
			end
		end
	end
end

-- Over when no present runner is still alive and unfinished (covers everyone-left, too).
local function runIsOver(): boolean
	for playerId in runners do
		local state = PlayerState.get(playerId)
		if state ~= nil and Players:GetPlayerByUserId(playerId) ~= nil then
			if state.alive and not state.finished then
				return false
			end
		end
	end
	return true
end

function RunOrchestrator.onPlayerAdded(player: Player)
	PlayerState.ensure(player.UserId)
	if phase == "Waiting" then
		beginCountdown()
	elseif phase == "Running" then
		-- Mid-run joiner: spawn at floor 1 if there's party room, else spectate until restart.
		if #floors > 0 then
			local count = 0
			for _ in runners do
				count += 1
			end
			if count < Config.Run.partyCap then
				runners[player.UserId] = true
				PlayerState.reset(player.UserId)
				CharacterService.spawn(player, floors[1].entryPosition)
				MovementService.refresh(player.UserId)
				Remotes.get("RunEvent"):FireClient(player, "floor", { depth = 1 })
			else
				Remotes.get("RunEvent")
					:FireClient(player, "message", { text = "The party is full. Wait for the next descent." })
			end
		end
	end
end

function RunOrchestrator.onPlayerRemoving(player: Player)
	DripTrailService.clear(player.UserId)
	CharacterService.despawn(player)
	PlayerState.remove(player.UserId)
	runners[player.UserId] = nil
end

function RunOrchestrator.tick()
	local now = os.clock()
	if phase == "Countdown" and now >= phaseDeadline then
		if #Players:GetPlayers() > 0 then
			startRun()
		else
			phase = "Waiting"
		end
	elseif phase == "Running" then
		checkDescent()
		if runIsOver() then
			phase = "Restarting"
			phaseDeadline = now + Config.Run.restartDelaySeconds
			broadcast("message", { text = "The caves grow quiet. A new descent begins soon." })
		end
	elseif phase == "Restarting" and now >= phaseDeadline then
		teardown()
		if #Players:GetPlayers() > 0 then
			beginCountdown()
		else
			phase = "Waiting"
		end
	end
end

return RunOrchestrator

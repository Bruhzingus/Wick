--!strict
-- Server authorization and live stats for the per-player developer diagnostics overlay. This
-- service exposes observation only: it never changes wax, threats, mining, movement, or run state.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local AshamedLurkerVisualProtocol = require(ReplicatedStorage.Shared.AshamedLurkerVisualProtocol)
local MiningVisualProtocol = require(ReplicatedStorage.Shared.MiningVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local RequestGuard = require(script.Parent.RequestGuard)

local DevDiagnosticsService = {}

local enabled: { [number]: boolean } = {}
local elapsed = 0
local frames = 0

local function ordinaryThreatTag(): string
	return Config.Feel.threatWarning.collectionTag
end

local function sendState(player: Player, accepted: boolean, message: string?)
	Remotes.get("DevDiagnostics"):FireClient(player, "state", {
		enabled = enabled[player.UserId] == true,
		accepted = accepted,
		message = message or "",
	})
end

local function authorizeFromTeleport(player: Player)
	local data = player:GetJoinData().TeleportData
	if typeof(data) ~= "table" then
		return
	end
	if data.devDiagnostics == true then
		enabled[player.UserId] = true
		return
	end
	local members = data.devDiagnosticsMembers
	if typeof(members) ~= "table" then
		return
	end
	for _, rawId in members :: { unknown } do
		if rawId == player.UserId then
			enabled[player.UserId] = true
			return
		end
	end
end

function DevDiagnosticsService.init()
	Remotes.get("DevDiagnostics").OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		if typeof(action) ~= "string" or not RequestGuard.allow(player, "DevDiagnostics") then
			return
		end
		if action == "sync" then
			sendState(player, true)
			return
		end
		if action == "disable" then
			enabled[player.UserId] = nil
			sendState(player, true, "Developer diagnostics disabled.")
			return
		end
		if action ~= "unlock" then
			return
		end
		if CharacterService.lobbyBodyPosition(player.UserId) == nil then
			sendState(player, false, "Enter the code from the Landing.")
			return
		end
		if typeof(value) ~= "string" or #value > 16 or value ~= Config.Diagnostics.unlockCode then
			sendState(player, false, "Invalid developer code.")
			return
		end
		enabled[player.UserId] = true
		sendState(player, true, "Developer diagnostics enabled.")
	end)
end

function DevDiagnosticsService.onPlayerAdded(player: Player)
	authorizeFromTeleport(player)
	if enabled[player.UserId] then
		sendState(player, true, "Developer diagnostics restored.")
	end
end

function DevDiagnosticsService.clear(playerId: number)
	enabled[playerId] = nil
end

function DevDiagnosticsService.isEnabled(playerId: number): boolean
	return enabled[playerId] == true
end

function DevDiagnosticsService.enabledMembers(memberIds: { number }): { number }
	local result: { number } = {}
	for _, playerId in memberIds do
		if enabled[playerId] then
			table.insert(result, playerId)
		end
	end
	return result
end

function DevDiagnosticsService.tick(dt: number)
	elapsed += dt
	frames += 1
	if elapsed < 1 / Config.Diagnostics.statsHz then
		return
	end

	local serverFps = frames / math.max(elapsed, 0.001)
	elapsed = 0
	frames = 0
	if next(enabled) == nil then
		return
	end

	local payload = {
		serverFps = math.round(serverFps),
		serverMemoryMb = math.round(Stats:GetTotalMemoryUsageMb()),
		serverUptime = math.floor(Workspace.DistributedGameTime),
		players = #Players:GetPlayers(),
		workspaceInstances = #Workspace:GetDescendants(),
		threats = #CollectionService:GetTagged(ordinaryThreatTag()) + #CollectionService:GetTagged(
			AshamedLurkerVisualProtocol.tag
		) + #CollectionService:GetTagged(Config.Diagnostics.wardenTag),
		ore = #CollectionService:GetTagged(MiningVisualProtocol.depositTag),
		items = #CollectionService:GetTagged(Config.Diagnostics.itemTag),
		descents = #CollectionService:GetTagged(Config.Diagnostics.descentTag),
		loadingStage = tostring(Workspace:GetAttribute("WickLoadingStage") or "none"),
		reservedServer = game.PrivateServerId ~= "",
		job = string.sub(game.JobId, 1, 8),
	}
	for playerId in enabled do
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil then
			Remotes.get("DevDiagnostics"):FireClient(player, "stats", payload)
		end
	end
end

return DevDiagnosticsService

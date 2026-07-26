--!strict
-- One small public-server lobby forms a party, validates a cave tier, then teleports that party
-- into a reserved expedition server. Studio uses the same UI/state but starts locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)
local CharacterService = require(script.Parent.CharacterService)
local LobbyRoomBuilder = require(script.Parent.LobbyRoomBuilder)

local PartyLobbyService = {}

type StartHandler = (tierId: number, members: { number }) -> ()

local activeExpedition = false
local expeditionTierId = 1
local startHandler: StartHandler? = nil
local starting = false
local expeditionStarted = false
local departingParty: { [number]: boolean } = {}
local expectedExpeditionMembers: { [number]: boolean } = {}
local expeditionArrivalDeadline = 0
local arrivalTimerScheduled = false

local function playerName(playerId: number): string
	local player = Players:GetPlayerByUserId(playerId)
	return if player ~= nil then player.DisplayName else tostring(playerId)
end

local function statePayload(recipient: Player, status: string?): { [string]: unknown }
	local party = Interfaces.Party.snapshot()
	local members = {}
	local leaderId = 0
	local tierId = expeditionTierId
	if party ~= nil then
		leaderId = party.leaderId
		tierId = party.tierId
		for _, playerId in party.members do
			table.insert(members, {
				playerId = playerId,
				displayName = playerName(playerId),
				ready = party.ready[playerId] == true,
			})
		end
	end
	local profile = Interfaces.Persistence.get(recipient.UserId)
	return {
		inExpedition = expeditionStarted,
		leaderId = leaderId,
		tierId = tierId,
		tiers = Interfaces.CaveTiers.list(),
		unlockedTier = profile.unlockedCaveTier,
		currency = profile.currency,
		deepestFloor = profile.deepestFloor,
		members = members,
		status = status or "",
	}
end

local function broadcast(status: string?)
	for _, recipient in Players:GetPlayers() do
		Remotes.get("LobbyState"):FireClient(recipient, statePayload(recipient, status))
	end
end

-- One player's own status line (shop replies, personal validation messages). Routed through
-- LobbyState rather than RunEvent("message") on purpose: RunEvent's text renders into the WickText
-- ScreenGui, which LobbyController disables outside an expedition — a lobby message sent that way
-- is written into a disabled GUI and never seen.
local function sendStatusTo(player: Player, status: string)
	Remotes.get("LobbyState"):FireClient(player, statePayload(player, status))
end

local function teleportDataFor(player: Player): { [string]: unknown }?
	local joinData = player:GetJoinData()
	local data = joinData.TeleportData
	return if typeof(data) == "table" then data else nil
end

local function configureExpectedExpedition(data: { [string]: unknown }, arrivingPlayerId: number)
	if activeExpedition then
		return
	end
	activeExpedition = true
	expeditionArrivalDeadline = os.clock() + Config.Lobby.arrivalWaitSeconds
	table.clear(expectedExpeditionMembers)
	expectedExpeditionMembers[arrivingPlayerId] = true
	local expectedCount = 1

	local rawMembers = data.partyMembers
	if typeof(rawMembers) == "table" then
		for _, rawMemberId in rawMembers do
			if expectedCount >= Config.Run.partyCap then
				break
			end
			if RequestGuard.finiteNumber(rawMemberId) then
				local memberId = rawMemberId :: number
				if memberId > 0 and memberId % 1 == 0 and not expectedExpeditionMembers[memberId] then
					expectedExpeditionMembers[memberId] = true
					expectedCount += 1
				end
			end
		end
	end
end

local function startLocally(tierId: number, memberIds: { number })
	activeExpedition = true
	expeditionTierId = tierId
	expeditionStarted = true
	starting = false
	broadcast("The descent begins.")
	local callback = startHandler
	if callback ~= nil then
		callback(tierId, memberIds)
	end
end

local function partyPlayers(memberIds: { number }): { Player }
	local result: { Player } = {}
	for _, playerId in memberIds do
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil then
			table.insert(result, player)
		end
	end
	return result
end

local function attemptTeleport(tierId: number, memberIds: { number })
	if not starting then
		return
	end
	local players = partyPlayers(memberIds)
	if #players == 0 then
		starting = false
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({
		wickExpedition = true,
		tierId = tierId,
		partyMembers = memberIds,
	})

	for attempt = 1, Config.Lobby.teleportRetries do
		table.clear(departingParty)
		for _, teleportPlayer in players do
			departingParty[teleportPlayer.UserId] = true
		end
		local ok, message = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players, options)
		end)
		if ok then
			-- Leave `starting` true so repeat clicks cannot launch a second teleport while Roblox
			-- moves the party.
			broadcast("Joining the reserved expedition...")
			Telemetry.event("party_teleport", nil, { members = #players, tier = tierId })
			return
		end
		table.clear(departingParty)
		warn(string.format("[WICK] Teleport attempt %d failed: %s", attempt, tostring(message)))
		if attempt < Config.Lobby.teleportRetries then
			task.wait(Config.Lobby.teleportRetryDelaySeconds)
		end
	end
	starting = false
	broadcast("Teleport failed. Publish the experience, then try again.")
end

-- Leader-only: validates readiness/tier-unlock and launches the expedition. Exported so both the
-- `LobbyAction("start")` remote (kept for compatibility/testing) and ElevatorService's leader-only
-- descend lever call the exact same validated path — no duplicated leader/ready/unlock logic.
-- Returns true only when the expedition actually launched, so ElevatorService knows whether to play
-- the descent ride. Every rejection path (not the leader, not ready, tier locked, already starting)
-- returns false without side effects beyond the explanatory broadcast.
function PartyLobbyService.tryStart(player: Player): boolean
	if starting or activeExpedition then
		return false
	end
	local party = Interfaces.Party.snapshot()
	if party == nil or party.leaderId ~= player.UserId then
		return false
	end
	local minimumPlayers = math.max(Config.Lobby.minimumPlayers, if Config.Run.soloAllowed then 1 else 2)
	if not Interfaces.Party.allReady(minimumPlayers) then
		broadcast("Every party member must be ready.")
		return false
	end
	for _, memberId in party.members do
		if not Interfaces.CaveTiers.isUnlocked(memberId, party.tierId) then
			broadcast(playerName(memberId) .. " has not unlocked that cave tier.")
			return false
		end
	end

	starting = true
	local memberIds = table.clone(party.members)
	broadcast("Opening the descent...")
	if RunService:IsStudio() or game.PlaceId == 0 then
		startLocally(party.tierId, memberIds)
	else
		-- Let the physical car complete the same countdown-length descent before Roblox takes over
		-- for the reserved-server transfer. The destination loading screen remains until its cave
		-- body exists, so there is no second visible lobby phase after this ride.
		task.delay(Config.Run.startCountdownSeconds, attemptTeleport, party.tierId, memberIds)
	end
	return true
end

-- ElevatorService mutates party tier/readiness directly (standing in a car IS the input), so it
-- needs a way to push the resulting state to every client. Exposed rather than made public on
-- `broadcast` itself so the only thing callers can do is request a refresh, not forge a payload.
function PartyLobbyService.notifyLobbyChanged(status: string?)
	broadcast(status)
end

-- Read-only checks ElevatorService needs to decide whether its leader-only lever should be enabled,
-- without duplicating `tryStart`'s validation.
function PartyLobbyService.canStart(player: Player): boolean
	if starting or activeExpedition then
		return false
	end
	local party = Interfaces.Party.snapshot()
	if party == nil or party.leaderId ~= player.UserId then
		return false
	end
	local minimumPlayers = math.max(Config.Lobby.minimumPlayers, if Config.Run.soloAllowed then 1 else 2)
	if not Interfaces.Party.allReady(minimumPlayers) then
		return false
	end
	for _, memberId in party.members do
		if not Interfaces.CaveTiers.isUnlocked(memberId, party.tierId) then
			return false
		end
	end
	return true
end

function PartyLobbyService.init(onLocalStart: StartHandler)
	startHandler = onLocalStart
	-- LobbyRoomBuilder places the shop stall but decides nothing; answering its prompt is lobby
	-- messaging, which this service owns.
	local shopPrompt = LobbyRoomBuilder.shopPrompt()
	if shopPrompt ~= nil then
		shopPrompt.Triggered:Connect(function(player: Player)
			sendStatusTo(player, Config.LobbyRoom.shopMessage)
		end)
	end
	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		if not departingParty[player.UserId] then
			return
		end
		departingParty[player.UserId] = nil
		if next(departingParty) == nil then
			starting = false
			broadcast("Teleport failed. Ready up and try again.")
		end
	end)
	Remotes.get("LobbyAction").OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		if not RequestGuard.allow(player, "LobbyAction") or typeof(action) ~= "string" then
			return
		end
		-- A client can connect after the destination server's first broadcast. Always answer sync,
		-- including inside an active expedition, so the lobby overlay cannot get stuck on screen.
		if action == "sync" then
			broadcast()
			return
		end
		if activeExpedition then
			return
		end
		if action == "ready" and typeof(value) == "boolean" then
			Interfaces.Party.setReady(player.UserId, value)
			broadcast()
		elseif action == "tier" and RequestGuard.finiteNumber(value) then
			local tierId = value :: number
			if
				tierId % 1 == 0
				and Interfaces.CaveTiers.isUnlocked(player.UserId, tierId)
				and Interfaces.Party.setTier(player.UserId, tierId)
			then
				broadcast("Tier changed. Ready up again.")
			end
		elseif action == "start" then
			PartyLobbyService.tryStart(player)
		end
	end)
end

function PartyLobbyService.onPlayerAdded(player: Player)
	local data = teleportDataFor(player)
	local arrivingForExpedition = data ~= nil and data.wickExpedition == true
	if arrivingForExpedition and data ~= nil then
		configureExpectedExpedition(data, player.UserId)
		local rawTier = data.tierId
		if RequestGuard.finiteNumber(rawTier) then
			local tierId = rawTier :: number
			if tierId % 1 == 0 and Interfaces.CaveTiers.get(tierId) ~= nil then
				expeditionTierId = tierId
			end
		end
	end

	if not Interfaces.Party.join(player.UserId, Config.Run.partyCap) then
		Remotes.get("LobbyState"):FireClient(player, {
			inExpedition = false,
			leaderId = 0,
			tierId = 1,
			tiers = Interfaces.CaveTiers.list(),
			members = {},
			status = "This party is full. Join another server.",
		})
		return
	end
	if activeExpedition then
		Interfaces.Party.setReady(player.UserId, true)
		Interfaces.Party.adoptExpeditionTier(expeditionTierId)
	end
	-- Fresh joins get a spread lobby avatar. Reserved-expedition arrivals deliberately remain
	-- bodyless behind ReplicatedFirst's loading screen until RunOrchestrator creates the floor-one
	-- candle; spawning a lobby avatar here caused the destination hub flash between teleports.
	local party = Interfaces.Party.snapshot()
	local slot = if party ~= nil then (table.find(party.members, player.UserId) or 1) else 1
	if not arrivingForExpedition then
		CharacterService.spawnLobby(player, LobbyRoomBuilder.spawnPositionFor(slot))
	end
	broadcast()
end

function PartyLobbyService.onPlayerRemoving(player: Player)
	Interfaces.Party.leave(player.UserId)
	RequestGuard.clear(player.UserId)
	CharacterService.despawnLobby(player)
	departingParty[player.UserId] = nil
	if starting and next(departingParty) == nil then
		-- The dispatched party is gone; this public server can host a fresh lobby if Roblox
		-- routes another player here before it shuts down.
		starting = false
	end
	broadcast()
end

function PartyLobbyService.isLobbyClosed(): boolean
	return starting or activeExpedition
end

-- Reopen tier selection in the current server after a resolved expedition. Profiles were already
-- credited by BrazierService; refresh unlocks before broadcasting so newly affordable caves appear
-- immediately. Keeping the party together also makes this work in Studio and reserved servers.
function PartyLobbyService.returnToLobby()
	activeExpedition = false
	expeditionStarted = false
	starting = false
	expeditionArrivalDeadline = 0
	arrivalTimerScheduled = false
	table.clear(departingParty)
	table.clear(expectedExpeditionMembers)

	local party = Interfaces.Party.snapshot()
	if party ~= nil then
		expeditionTierId = party.tierId
		for slot, playerId in party.members do
			Interfaces.CaveTiers.refreshUnlocks(playerId)
			Interfaces.Party.setReady(playerId, false)
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil then
				-- Back in the hub itself, never wherever the cave left them: the room is static and
				-- outlives every run, so this is the same Landing a fresh joiner walks into.
				CharacterService.spawnLobby(player, LobbyRoomBuilder.spawnPositionFor(slot))
			end
		end
	end
	broadcast("Rewards banked. Choose a cave and ready up.")
end

function PartyLobbyService.beginExpeditionFromTeleport()
	if not activeExpedition or expeditionStarted then
		return
	end
	local party = Interfaces.Party.snapshot()
	local callback = startHandler
	if party == nil or callback == nil then
		return
	end

	local allArrived = true
	for expectedId in expectedExpeditionMembers do
		if table.find(party.members, expectedId) == nil then
			allArrived = false
			break
		end
	end
	if not allArrived and os.clock() < expeditionArrivalDeadline then
		broadcast("Waiting for the rest of the party...")
		if not arrivalTimerScheduled then
			arrivalTimerScheduled = true
			task.delay(math.max(expeditionArrivalDeadline - os.clock(), 0), function()
				arrivalTimerScheduled = false
				PartyLobbyService.beginExpeditionFromTeleport()
			end)
		end
		return
	end

	expeditionStarted = true
	arrivalTimerScheduled = false
	broadcast(if allArrived then "The party has arrived." else "Arrival wait ended. Beginning with this party.")
	callback(expeditionTierId, table.clone(party.members))
end

function PartyLobbyService.tierId(): number
	return expeditionTierId
end

return PartyLobbyService

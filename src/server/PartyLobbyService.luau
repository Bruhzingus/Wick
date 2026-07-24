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

local function broadcast(status: string?)
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
	for _, recipient in Players:GetPlayers() do
		local profile = Interfaces.Persistence.get(recipient.UserId)
		Remotes.get("LobbyState"):FireClient(recipient, {
			inExpedition = expeditionStarted,
			leaderId = leaderId,
			tierId = tierId,
			tiers = Interfaces.CaveTiers.list(),
			unlockedTier = profile.unlockedCaveTier,
			currency = profile.currency,
			members = members,
			status = status or "",
		})
	end
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
			task.wait(1)
		end
	end
	starting = false
	broadcast("Teleport failed. Publish the experience, then try again.")
end

local function requestStart(player: Player)
	if starting or activeExpedition then
		return
	end
	local party = Interfaces.Party.snapshot()
	if party == nil or party.leaderId ~= player.UserId then
		return
	end
	local minimumPlayers = math.max(Config.Lobby.minimumPlayers, if Config.Run.soloAllowed then 1 else 2)
	if not Interfaces.Party.allReady(minimumPlayers) then
		broadcast("Every party member must be ready.")
		return
	end
	for _, memberId in party.members do
		if not Interfaces.CaveTiers.isUnlocked(memberId, party.tierId) then
			broadcast(playerName(memberId) .. " has not unlocked that cave tier.")
			return
		end
	end

	starting = true
	local memberIds = table.clone(party.members)
	broadcast("Opening the descent...")
	if RunService:IsStudio() or game.PlaceId == 0 then
		startLocally(party.tierId, memberIds)
	else
		task.spawn(attemptTeleport, party.tierId, memberIds)
	end
end

function PartyLobbyService.init(onLocalStart: StartHandler)
	startHandler = onLocalStart
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
			requestStart(player)
		end
	end)
end

function PartyLobbyService.onPlayerAdded(player: Player)
	local data = teleportDataFor(player)
	if data ~= nil and data.wickExpedition == true then
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
		local party = Interfaces.Party.snapshot()
		if party ~= nil then
			party.tierId = expeditionTierId
		end
	end
	broadcast()
end

function PartyLobbyService.onPlayerRemoving(player: Player)
	Interfaces.Party.leave(player.UserId)
	RequestGuard.clear(player.UserId)
	departingParty[player.UserId] = nil
	if starting and next(departingParty) == nil then
		-- The dispatched party is gone; this public server can host a fresh lobby if Roblox
		-- routes another player here before it shuts down.
		starting = false
	end
	broadcast()
end

function PartyLobbyService.isExpedition(): boolean
	return activeExpedition
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

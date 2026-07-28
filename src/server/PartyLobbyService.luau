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
local ShopService = require(script.Parent.ShopService)
local LampHubService = require(script.Parent.LampHubService)

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
-- This reserved server's own reservation token, learned from the teleport data that brought the party
-- here. A server cannot ask Roblox what code it was started from, so being told on arrival is the
-- only way it can ever hand its players a pointer back to itself (see RejoinService).
local reservedAccessCode: string? = nil

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
	-- What each cave costs THIS player right now, resolved server-side. A cave they own reads as free,
	-- which is the only place a permanent unlock is visible in the UI.
	local admission: { { [string]: unknown } } = {}
	for _, tier in Interfaces.CaveTiers.list() do
		table.insert(admission, {
			tierId = tier.id,
			fee = Interfaces.CaveTiers.entryFeeFor(recipient.UserId, tier.id),
			owned = Interfaces.CaveTiers.owns(recipient.UserId, tier.id),
			affordable = Interfaces.CaveTiers.canAfford(recipient.UserId, tier.id),
			unlockPrice = tier.permanentUnlockPrice,
		})
	end
	return {
		inExpedition = expeditionStarted,
		leaderId = leaderId,
		tierId = tierId,
		tiers = Interfaces.CaveTiers.list(),
		ownedTiers = profile.ownedCaveTiers,
		admission = admission,
		currency = profile.currency,
		deepestFloor = profile.deepestFloor,
		-- LAMP NETWORK, per recipient. Ownership is per-player but hub geometry is shared, so this is
		-- what client/LampNetworkController lights its own housings from — there is no server-side lit
		-- state, because there is no single answer to "is this lamp lit" in a room holding four people.
		ownedLampNodes = profile.ownedLampNodes,
		activeContractId = profile.activeContractId,
		activeWagerDepth = profile.activeWagerDepth,
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
	-- Learned before the `activeExpedition` guard below, because a player REJOINING an already-running
	-- expedition also carries the code, and that is exactly the case where this server most needs to
	-- know it — a run whose first arrival somehow missed it would otherwise never be rejoinable again.
	local code = data.reservedAccessCode
	if typeof(code) == "string" and code ~= "" then
		reservedAccessCode = code
	end
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

	-- RESERVE EXPLICITLY, rather than letting `TeleportOptions.ShouldReserveServer` do it.
	--
	-- The two produce the same reserved server, but only this form hands back the ACCESS CODE — and
	-- the access code is the only thing in the platform that can send a dropped player back into one
	-- specific running expedition (see RejoinService). `ShouldReserveServer` keeps that code to
	-- itself, which is precisely why reconnecting into a run was impossible before this change.
	local reserved, accessCode, privateServerId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not reserved or typeof(accessCode) ~= "string" then
		starting = false
		warn(string.format("[WICK] Could not reserve an expedition server: %s", tostring(accessCode)))
		broadcast("The descent could not be opened. Try again.")
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		wickExpedition = true,
		tierId = tierId,
		partyMembers = memberIds,
		-- Carried so the destination server learns its own reservation identity. A server cannot ask
		-- Roblox for the code it was started from, so the only way it can stamp a rejoin pointer onto
		-- its players' profiles is to be told on arrival.
		reservedAccessCode = accessCode,
		reservedPrivateServerId = privateServerId,
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
		if not Interfaces.CaveTiers.canAfford(memberId, party.tierId) then
			broadcast(playerName(memberId) .. " cannot pay the toll for that cave.")
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

-- One player's own status line. Exposed so services that answer a personal action (a purchase, a
-- refused descent) can reply to just that player without broadcasting their business to the lobby,
-- and without learning how lobby messages are routed.
function PartyLobbyService.notifyPlayer(player: Player, status: string)
	sendStatusTo(player, status)
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
		if not Interfaces.CaveTiers.canAfford(memberId, party.tierId) then
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
			-- The stall lists what permanent access costs and what the player can currently afford.
			-- Buying is a separate, explicit `LobbyAction("buyCave", tierId)` handled by ShopService —
			-- walking up to a stall must never spend anybody's money.
			local offers = ShopService.offersFor(player.UserId)
			if #offers == 0 then
				sendStatusTo(player, Config.LobbyRoom.shopMessage)
				return
			end
			local lines: { string } = {}
			for _, offer in offers do
				local price = offer.price :: number
				table.insert(
					lines,
					if offer.owned == true
						then string.format("%s — owned", tostring(offer.displayName))
						else string.format("%s — %d Raw Wax to own", tostring(offer.displayName), price)
				)
			end
			sendStatusTo(player, table.concat(lines, "   |   "))
		end)
	end

	-- THE LAMP LINE. One prompt per node, the same shop-stub pattern as the stall above: the builder
	-- placed them and decided nothing, ShopService owns the money, and this owns the reply. Unlike
	-- the stall, a lamp prompt DOES buy — the 1.2s hold is the confirmation, so there is no menu and
	-- no second step.
	--
	-- Prompts stay enabled for everybody, because ProximityPrompt.Enabled is one Instance property
	-- shared by every client (see the same note in ElevatorService). A player who cannot buy this
	-- node yet is refused server-side and told exactly why.
	--
	-- EACH FIXTURE HAS TWO LIVES: a purchase point while it is dark, and a machine once it is lit.
	-- LampHubService answers the second and reports whether it did; only an unowned node falls through
	-- to a purchase. Ownership is re-read server-side on every press, so the branch can never be taken
	-- on a client's say-so.
	--
	-- No state refresh is needed on success: every reply either service makes routes back through
	-- `notifyPlayer` -> `sendStatusTo`, which rebuilds the whole payload from the profile as it stands
	-- at that moment. The toast and the newly-owned node arrive in the same message, so the housing
	-- lights on the same frame the player reads that they bought it.
	for _, fixture in LobbyRoomBuilder.lampFixtures() do
		local nodeId = fixture.nodeId
		fixture.prompt.Triggered:Connect(function(player: Player)
			if not LampHubService.use(player, nodeId) then
				ShopService.purchaseLamp(player, nodeId)
			end
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
				and Interfaces.CaveTiers.canAfford(player.UserId, tierId)
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
-- credited by ExtractionService, and affordability is now read live per broadcast rather than being
-- refreshed into a stored unlock — so a cave that this run just paid for appears the moment the
-- lobby state goes out. Keeping the party together also makes this work in Studio and reserved
-- servers.
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

-- This server's reservation token, or nil if it is a public lobby rather than an expedition server.
-- Read by RunOrchestrator when it stamps the rejoin pointer onto each runner's profile.
function PartyLobbyService.reservedAccessCode(): string?
	return reservedAccessCode
end

return PartyLobbyService

--!strict
-- A public server's four elevator parties each form their own party (Interfaces/Party), vote on a
-- cave, and are teleported into their own reserved expedition server. Studio uses the same state and
-- UI but starts locally, which is why only one party can ever actually depart there.
--
-- WHAT IS PER-PARTY AND WHAT IS PER-SERVER, because the distinction is the whole shape of this file:
--   * `startingParties` is per party. Four parties may be mid-launch at once in a live lobby, and one
--     failing must not strand the other three.
--   * `activeExpedition` / `expeditionStarted` are per SERVER, and only ever true in a reserved
--     expedition server (or a Studio local start, which stands in for one). A public lobby stays
--     open while parties leave it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local PartyInterface = require(ReplicatedStorage.Shared.Interfaces.Party)
local PartyVote = require(ReplicatedStorage.Shared.Logic.PartyVote)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)
local CharacterService = require(script.Parent.CharacterService)
local LobbyRoomBuilder = require(script.Parent.LobbyRoomBuilder)
local ShopService = require(script.Parent.ShopService)
local DevDiagnosticsService = require(script.Parent.DevDiagnosticsService)

local PartyLobbyService = {}

type Party = PartyInterface.Party

-- `countdownAlreadyServed` says the descent's wait has already been spent in front of the player.
-- True for a teleported party (their elevator car rode the whole countdown before Roblox moved them),
-- false for a Studio start, which never had a ride.
type StartHandler = (tierId: number, members: { number }, countdownAlreadyServed: boolean) -> ()

local activeExpedition = false
local expeditionTierId = 1
local startHandler: StartHandler? = nil
-- Per party, because four parties can be mid-launch at once in a live lobby.
local startingParties: { [number]: boolean } = {}
local expeditionStarted = false
local departingParty: { [number]: boolean } = {}
local restoringProfiles: { [number]: boolean } = {}
local expectedExpeditionMembers: { [number]: boolean } = {}
local expeditionArrivalDeadline = 0
local arrivalTimerScheduled = false
-- Live servers send an early extractor to a fresh public lobby. Studio cannot teleport between
-- servers, so these players use the same physical Landing locally while the expedition continues.
local localLobbyReturns: { [number]: boolean } = {}
local returningToMainLobby: { [number]: boolean } = {}
-- This reserved server's own reservation token, learned from the teleport data that brought the party
-- here. A server cannot ask Roblox what code it was started from, so being told on arrival is the
-- only way it can ever hand its players a pointer back to itself (see RejoinService).
local reservedAccessCode: string? = nil

local function playerName(playerId: number): string
	local player = Players:GetPlayerByUserId(playerId)
	return if player ~= nil then player.DisplayName else tostring(playerId)
end

-- Every party in the hub, as the client's party UI draws it: who is queuing where, how far along
-- each one is, and how its vote currently stands. Sent to everybody rather than only to your own
-- party, because seeing that party three has one person waiting is how you decide to join them.
local function partyPayloads(): { { [string]: unknown } }
	local result: { { [string]: unknown } } = {}
	for _, elevator in Config.LobbyRoom.elevators do
		local party = Interfaces.Party.get(elevator.partyId)
		local members: { { [string]: unknown } } = {}
		local tally: { [number]: number } = {}
		local phase = "Empty"
		local leaderId = 0
		local tierId = 0
		if party ~= nil then
			phase = party.phase
			leaderId = party.leaderId
			tierId = party.tierId
			tally = PartyVote.tally(party.votes, party.members)
			for _, playerId in party.members do
				table.insert(members, {
					playerId = playerId,
					displayName = playerName(playerId),
					ready = party.ready[playerId] == true,
					vote = party.votes[playerId],
				})
			end
		end
		-- Rebuilt as an array of pairs: a map keyed by number does not survive the remote boundary
		-- with its keys intact once it is sparse.
		local votes: { { [string]: unknown } } = {}
		for votedTier, count in tally do
			table.insert(votes, { tierId = votedTier, count = count })
		end
		table.insert(result, {
			partyId = elevator.partyId,
			phase = phase,
			leaderId = leaderId,
			tierId = tierId,
			members = members,
			votes = votes,
		})
	end
	return result
end

local function unseenUpdateEntries(lastSeenVersion: number): { { [string]: unknown } }
	local unseen: { { [string]: unknown } } = {}
	for _, entry in Config.LobbyRoom.updateLog do
		if entry.version > lastSeenVersion then
			table.insert(unseen, {
				version = entry.version,
				date = entry.date,
				lines = table.clone(entry.lines),
			})
		end
	end
	return unseen
end

local function latestUpdateVersion(): number
	local latest = 0
	for _, entry in Config.LobbyRoom.updateLog do
		latest = math.max(latest, entry.version)
	end
	return latest
end

local function statePayload(recipient: Player, status: string?): { [string]: unknown }
	local party = Interfaces.Party.forPlayer(recipient.UserId)
	local profile = Interfaces.Persistence.get(recipient.UserId)
	-- What each cave costs THIS player right now, resolved server-side. A cave they own reads as free,
	-- which is the only place a permanent unlock is visible in the UI.
	local admission: { { [string]: unknown } } = {}
	for _, tier in Interfaces.CaveTiers.list() do
		local partyAffordable = true
		if party ~= nil then
			for _, memberId in party.members do
				if not Interfaces.CaveTiers.canAfford(memberId, tier.id) then
					partyAffordable = false
					break
				end
			end
		end
		table.insert(admission, {
			tierId = tier.id,
			fee = Interfaces.CaveTiers.entryFeeFor(recipient.UserId, tier.id),
			owned = Interfaces.CaveTiers.owns(recipient.UserId, tier.id),
			affordable = Interfaces.CaveTiers.canAfford(recipient.UserId, tier.id),
			partyAffordable = partyAffordable,
			unlockPrice = tier.permanentUnlockPrice,
		})
	end
	return {
		inExpedition = expeditionStarted and not localLobbyReturns[recipient.UserId],
		-- Which party this player is standing in, or 0 for someone loose in the hub. The client's
		-- party panel keys its whole visibility off this: no party, no panel.
		partyId = if party ~= nil then party.partyId else 0,
		phase = if party ~= nil then party.phase else "None",
		ready = if party ~= nil then (party.ready[recipient.UserId] == true) else false,
		vote = if party ~= nil then party.votes[recipient.UserId] else nil,
		leaderId = if party ~= nil then party.leaderId else 0,
		tierId = if party ~= nil then party.tierId else 0,
		parties = partyPayloads(),
		partyCap = Config.Run.partyCap,
		tiers = Interfaces.CaveTiers.list(),
		ownedTiers = Interfaces.CaveTiers.ownedTiers(recipient.UserId),
		admission = admission,
		currency = profile.currency,
		deepestFloor = profile.deepestFloor,
		-- LAMP NETWORK, per recipient. Ownership is per-player but hub geometry is shared, so this is
		-- what client/LampNetworkController lights its own housings from.
		ownedLampNodes = profile.ownedLampNodes,
		activeContractId = profile.activeContractId,
		activeWagerDepth = profile.activeWagerDepth,
		unseenUpdates = unseenUpdateEntries(profile.lastSeenUpdateVersion),
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
-- ScreenGui, which LobbyController disables outside an expedition.
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
	-- know it.
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

local function startLocally(partyId: number, tierId: number, memberIds: { number })
	activeExpedition = true
	expeditionTierId = tierId
	expeditionStarted = true
	startingParties[partyId] = nil
	-- The party's party becomes this server's expedition party, so the run side's `snapshot()` finds
	-- it without ever learning that parties exist.
	Interfaces.Party.markExpedition(partyId)
	broadcast("The descent begins.")
	local callback = startHandler
	if callback ~= nil then
		-- No teleport in Studio means no elevator ride either, so the run still owes its countdown.
		callback(tierId, memberIds, false)
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

local function playerIds(players: { Player }): { number }
	local result: { number } = {}
	for _, player in players do
		table.insert(result, player.UserId)
	end
	return result
end

-- Reopening is the rollback for a teleport that Roblox refused after we deliberately released the
-- source sessions. Do it in parallel for a party: serial ProfileStore reads would recreate the very
-- multiplayer delay this handoff is removing.
local function restoreProfiles(players: { Player })
	local pending = 0
	for _, player in players do
		if player.Parent == Players then
			pending += 1
			task.spawn(function()
				while restoringProfiles[player.UserId] do
					task.wait()
				end
				if player.Parent ~= Players or Interfaces.Persistence.isLoaded(player.UserId) then
					pending -= 1
					return
				end
				restoringProfiles[player.UserId] = true
				local restored = Interfaces.Persistence.initPlayer(player)
				restoringProfiles[player.UserId] = nil
				if not restored and player.Parent == Players then
					player:Kick("Your profile could not be reopened after the transfer failed. Please rejoin.")
				end
				pending -= 1
			end)
		end
	end
	repeat
		task.wait()
	until pending == 0
end

-- Puts a party back to gathering after a launch that never became a run, so its party can try again
-- rather than being stuck in a frozen "Launching" car.
local function releaseParty(partyId: number, status: string)
	startingParties[partyId] = nil
	Interfaces.Party.setPhase(partyId, "Gathering")
	local party = Interfaces.Party.get(partyId)
	if party ~= nil then
		for _, memberId in party.members do
			Interfaces.Party.setReady(memberId, false)
		end
	end
	broadcast(status)
end

local function attemptTeleport(partyId: number, tierId: number, memberIds: { number })
	if not startingParties[partyId] then
		return
	end
	local players = partyPlayers(memberIds)
	if #players == 0 then
		startingParties[partyId] = nil
		return
	end

	-- RESERVE EXPLICITLY, rather than letting `TeleportOptions.ShouldReserveServer` do it.
	--
	-- The two produce the same reserved server, but only this form hands back the ACCESS CODE, and
	-- the access code is the only thing in the platform that can send a dropped player back into one
	-- specific running expedition (see RejoinService).
	local reserved, accessCode, privateServerId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not reserved or typeof(accessCode) ~= "string" then
		warn(string.format("[WICK] Could not reserve an expedition server: %s", tostring(accessCode)))
		releaseParty(partyId, "The descent could not be opened. Try again.")
		return
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({
		wickExpedition = true,
		tierId = tierId,
		partyMembers = memberIds,
		devDiagnosticsMembers = DevDiagnosticsService.enabledMembers(memberIds),
		-- Carried so the destination server learns its own reservation identity.
		reservedAccessCode = accessCode,
		reservedPrivateServerId = privateServerId,
	})

	local releaseStartedAt = os.clock()
	if not Interfaces.Persistence.releaseForTeleport(playerIds(players)) then
		restoreProfiles(players)
		releaseParty(partyId, "A player profile was not ready for transfer. Ready up and try again.")
		return
	end
	local profileReleaseMs = math.round((os.clock() - releaseStartedAt) * 1000)
	if not startingParties[partyId] or #partyPlayers(memberIds) ~= #players then
		restoreProfiles(players)
		releaseParty(partyId, "The party changed during transfer. Ready up and try again.")
		return
	end

	for attempt = 1, Config.Lobby.teleportRetries do
		for _, teleportPlayer in players do
			departingParty[teleportPlayer.UserId] = true
		end
		local ok, message = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players, options)
		end)
		if ok then
			-- Leave the party marked starting so repeat triggers cannot launch a second teleport while
			-- Roblox moves the party.
			Telemetry.event("party_teleport", nil, {
				members = #players,
				tier = tierId,
				party = partyId,
				profileReleaseMs = profileReleaseMs,
			})
			return
		end
		for _, teleportPlayer in players do
			departingParty[teleportPlayer.UserId] = nil
		end
		warn(string.format("[WICK] Teleport attempt %d failed: %s", attempt, tostring(message)))
		if attempt < Config.Lobby.teleportRetries then
			task.wait(Config.Lobby.teleportRetryDelaySeconds)
		end
	end
	restoreProfiles(players)
	releaseParty(partyId, "Teleport failed. Publish the experience, then try again.")
end

-- Launches one party's party into the cave its vote settled on. Called by ElevatorService when the
-- launch countdown expires; every rejection returns false without side effects beyond the broadcast,
-- so the caller can put the party back to gathering.
--
-- ADMISSION IS RE-CHECKED HERE even though the ballot already excluded caves the party could not
-- afford. The vote resolved seconds ago and a member may have spent that money at the shop since;
-- this is the last point before profiles are released for transfer.
function PartyLobbyService.tryLaunch(party: Party): boolean
	local partyId = party.partyId
	if startingParties[partyId] or activeExpedition then
		return false
	end
	if #party.members < math.max(Config.Lobby.minimumPlayers, if Config.Run.soloAllowed then 1 else 2) then
		return false
	end
	local tier = Interfaces.CaveTiers.get(party.tierId)
	if tier == nil then
		return false
	end
	for _, memberId in party.members do
		if not Interfaces.CaveTiers.canAfford(memberId, party.tierId) then
			broadcast(playerName(memberId) .. " cannot pay the toll for that cave.")
			return false
		end
	end

	startingParties[partyId] = true
	local memberIds = table.clone(party.members)
	local tierId = party.tierId
	broadcast("Opening the descent...")
	if RunService:IsStudio() or game.PlaceId == 0 then
		startLocally(partyId, tierId, memberIds)
	else
		-- Let the physical car complete the same countdown-length descent before Roblox takes over
		-- for the reserved-server transfer.
		task.delay(Config.Run.startCountdownSeconds, attemptTeleport, partyId, tierId, memberIds)
	end
	return true
end

-- ElevatorService mutates party membership, readiness and votes directly (the room IS the input), so
-- it needs a way to push the resulting state to every client. Exposed rather than making `broadcast`
-- public so the only thing callers can do is request a refresh, not forge a payload.
function PartyLobbyService.notifyLobbyChanged(status: string?)
	broadcast(status)
end

-- One player's own status line, for services answering a personal action.
function PartyLobbyService.notifyPlayer(player: Player, status: string)
	sendStatusTo(player, status)
end

-- A message meant for ONE party, sent to exactly that party's members.
--
-- Four parties queue in the same room and their phase messages are not each other's business: with
-- a plain broadcast, "Everyone is ready, choose a cave" from party three appears on the screen of a
-- player standing alone in party one, who is then told to choose a cave they were never offered.
-- Everyone else still gets the state refresh, just without the line.
function PartyLobbyService.notifyParty(party: Party, status: string)
	local members: { [number]: boolean } = {}
	for _, memberId in party.members do
		members[memberId] = true
	end
	for _, recipient in Players:GetPlayers() do
		Remotes.get("LobbyState")
			:FireClient(recipient, statePayload(recipient, if members[recipient.UserId] then status else nil))
	end
end

function PartyLobbyService.init(onLocalStart: StartHandler)
	startHandler = onLocalStart
	-- LobbyRoomBuilder places the shop stall but decides nothing; answering its prompt is lobby
	-- messaging, which this service owns.
	local shopPromptInstance = LobbyRoomBuilder.shopPrompt()
	if shopPromptInstance ~= nil then
		shopPromptInstance.Triggered:Connect(function(player: Player)
			ShopService.open(player)
		end)
	end
	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		if returningToMainLobby[player.UserId] then
			returningToMainLobby[player.UserId] = nil
			Remotes.get("RunEvent"):FireClient(player, "message", {
				text = "The lobby transfer failed. Press the extraction button to try again.",
			})
			return
		end
		if not departingParty[player.UserId] then
			return
		end
		task.spawn(function()
			restoreProfiles({ player })
			departingParty[player.UserId] = nil
			local party = Interfaces.Party.forPlayer(player.UserId)
			if party ~= nil then
				releaseParty(party.partyId, "Teleport failed. Ready up and try again.")
			end
		end)
	end)
	Remotes.get("LobbyAction").OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		if typeof(action) ~= "string" then
			return
		end
		-- ElevatorService owns these because both actions must also move a physical lobby body. Returning
		-- before the guard prevents one request being charged twice by the two remote listeners.
		if action == "leave" or action == "kick" then
			return
		end
		if not RequestGuard.allow(player, "LobbyAction") then
			return
		end
		-- A client can connect after the destination server's first broadcast. Always answer sync,
		-- including inside an active expedition, so the lobby overlay cannot get stuck on screen.
		if action == "sync" then
			broadcast()
			return
		end
		if action == "dismissUpdates" then
			-- The client names no version. It can only close the server-authored payload, and the server
			-- derives the persisted build from its own config so an exploiter cannot skip future notes.
			local profile = Interfaces.Persistence.get(player.UserId)
			profile.lastSeenUpdateVersion = math.max(profile.lastSeenUpdateVersion, latestUpdateVersion())
			Interfaces.Persistence.save(player.UserId, profile)
			Remotes.get("LobbyState"):FireClient(player, statePayload(player))
			return
		end
		if activeExpedition then
			return
		end
		if action == "ready" and typeof(value) == "boolean" then
			-- Membership is decided by where the player is standing, never by this remote: a client
			-- that has walked out of a car has no party for `setReady` to find.
			if Interfaces.Party.setReady(player.UserId, value :: boolean) then
				broadcast()
			else
				sendStatusTo(player, "Stand inside an elevator to ready up.")
			end
		elseif action == "vote" and RequestGuard.finiteNumber(value) then
			local tierId = value :: number
			if tierId % 1 ~= 0 or Interfaces.CaveTiers.get(tierId) == nil then
				return
			end
			-- Affordability is checked here as well as in the tally, so a client cannot register a
			-- vote for a cave it can see is locked and watch the UI show it as a live choice.
			if not Interfaces.CaveTiers.canAfford(player.UserId, tierId) then
				sendStatusTo(player, "You cannot pay that cave's admission yet.")
				return
			end
			if Interfaces.Party.setVote(player.UserId, tierId) then
				broadcast()
			end
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

	if arrivingForExpedition then
		-- A reserved server's arrivals have no party to walk into, so they are collected straight into
		-- the expedition party.
		if not Interfaces.Party.joinExpedition(player.UserId, Config.Run.partyCap) then
			Remotes.get("LobbyState"):FireClient(player, {
				inExpedition = false,
				partyId = 0,
				parties = {},
				tiers = Interfaces.CaveTiers.list(),
				status = "This expedition is full. Rejoin from the hub.",
			})
			return
		end
		if activeExpedition then
			Interfaces.Party.setReady(player.UserId, true)
			Interfaces.Party.adoptExpeditionTier(expeditionTierId)
		end
		-- Deliberately left bodyless behind ReplicatedFirst's loading screen until RunOrchestrator
		-- creates the floor-one candle; spawning a lobby avatar here caused a hub flash between
		-- teleports.
		broadcast()
		return
	end

	-- A PUBLIC LOBBY ARRIVAL JOINS NO PARTY. You become a party by walking into an elevator, which is
	-- the entire point of the party model: a player standing in the hub is nobody's teammate yet.
	CharacterService.spawnLobby(player, LobbyRoomBuilder.spawnPositionForPlayer(player.UserId))
	broadcast()
end

function PartyLobbyService.onPlayerRemoving(player: Player)
	local party = Interfaces.Party.forPlayer(player.UserId)
	local partyId = if party ~= nil then party.partyId else nil
	Interfaces.Party.leave(player.UserId)
	RequestGuard.clear(player.UserId)
	LobbyRoomBuilder.releaseSpawnSlot(player.UserId)
	CharacterService.despawnLobby(player)
	departingParty[player.UserId] = nil
	localLobbyReturns[player.UserId] = nil
	returningToMainLobby[player.UserId] = nil
	if partyId ~= nil and startingParties[partyId] then
		local remaining = Interfaces.Party.get(partyId)
		if remaining == nil then
			-- The dispatched party is gone; this party can host a fresh one.
			startingParties[partyId] = nil
		end
	end
	broadcast()
end

-- Send one resolved survivor back to the main public lobby without ending the expedition for anyone
-- else. The caller owns payout/bonus eligibility; this function owns only the server transition.
function PartyLobbyService.returnPlayerToMainLobby(player: Player)
	if returningToMainLobby[player.UserId] or localLobbyReturns[player.UserId] then
		return
	end

	if RunService:IsStudio() or game.PlaceId == 0 then
		localLobbyReturns[player.UserId] = true
		CharacterService.spawnLobby(player, LobbyRoomBuilder.spawnPositionForPlayer(player.UserId))
		sendStatusTo(player, "Extracted early. Your base rewards are banked.")
		return
	end

	returningToMainLobby[player.UserId] = true
	task.spawn(function()
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({
			wickLobbyReturn = true,
			devDiagnostics = DevDiagnosticsService.isEnabled(player.UserId),
		})
		for attempt = 1, Config.Lobby.teleportRetries do
			if player.Parent ~= Players then
				returningToMainLobby[player.UserId] = nil
				return
			end
			local ok, message = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { player }, options)
			end)
			if ok then
				return
			end
			warn(string.format("[WICK] Main-lobby return attempt %d failed: %s", attempt, tostring(message)))
			if attempt < Config.Lobby.teleportRetries then
				task.wait(Config.Lobby.teleportRetryDelaySeconds)
			end
		end
		returningToMainLobby[player.UserId] = nil
		if player.Parent == Players then
			Remotes.get("RunEvent"):FireClient(player, "message", {
				text = "The lobby transfer failed. Press the extraction button to try again.",
			})
		end
	end)
end

-- True only when THIS server is running an expedition, which stops ElevatorService driving parties in
-- a reserved server or a Studio local start. A live public lobby is never closed by one party
-- leaving it: that is the whole reason four parties exist.
function PartyLobbyService.isLobbyClosed(): boolean
	return activeExpedition
end

-- Reopen the hub after a resolved expedition. Profiles were already credited by ExtractionService,
-- and affordability is read live per broadcast, so a cave this run just paid for appears the moment
-- the lobby state goes out.
function PartyLobbyService.returnToLobby()
	activeExpedition = false
	expeditionStarted = false
	expeditionArrivalDeadline = 0
	arrivalTimerScheduled = false
	table.clear(startingParties)
	table.clear(departingParty)
	table.clear(expectedExpeditionMembers)
	table.clear(localLobbyReturns)
	table.clear(returningToMainLobby)

	local party = Interfaces.Party.expedition()
	if party ~= nil then
		expeditionTierId = party.tierId
		for _, playerId in table.clone(party.members) do
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil then
				-- Back in the hub itself, never wherever the cave left them, and back to being nobody's
				-- teammate: the returning party has to walk into a car again to queue.
				CharacterService.spawnLobby(player, LobbyRoomBuilder.spawnPositionForPlayer(player.UserId))
			end
			Interfaces.Party.leave(playerId)
		end
	end
	Interfaces.Party.clear()
	broadcast("Rewards banked. Step into the lobby elevator to queue again.")
end

function PartyLobbyService.beginExpeditionFromTeleport()
	if not activeExpedition or expeditionStarted then
		return
	end
	local party = Interfaces.Party.expedition()
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
		Telemetry.loadingStage("waiting_for_party")
		-- Logged because this wait is invisible from the outside: every player already here is sitting
		-- on a bodyless loading screen for however long the missing one takes.
		Telemetry.event("expedition_arrival_wait", nil, {
			present = #party.members,
			remainingSeconds = math.round(expeditionArrivalDeadline - os.clock()),
		})
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
	Telemetry.loadingStage("starting_expedition")
	-- The moment the destination server stops waiting on people and starts building.
	Telemetry.event("expedition_begin", nil, { members = #party.members, allArrived = allArrived })
	broadcast(if allArrived then "The party has arrived." else "Arrival wait ended. Beginning with this party.")
	-- The car in the lobby server already rode out `Config.Run.startCountdownSeconds` before the
	-- teleport was even attempted, and everything since has been server transfer the player watches a
	-- loading screen through. Starting a second countdown here bills them for the same wait twice.
	callback(expeditionTierId, table.clone(party.members), true)
end

-- This server's reservation token, or nil if it is a public lobby rather than an expedition server.
function PartyLobbyService.reservedAccessCode(): string?
	return reservedAccessCode
end

return PartyLobbyService

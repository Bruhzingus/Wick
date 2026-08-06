--!strict
-- THE HUB'S QUEUE. Each of the four elevator alcoves is an independent party car, and this file
-- owns the whole physical interaction with them: who is standing in which car, when a party's party
-- is ready, the cave vote that follows, and the descent ride that ends it.
--
-- THE PHASE MACHINE, one per party (Interfaces/Party owns the state, this file drives it):
--
--   Gathering -> players walk in and out freely; each toggles their own readiness.
--   Voting    -> reached when EVERY occupant is ready. The cave ballot opens for `voteSeconds`,
--                and closes early the moment everybody has voted.
--   Launching -> the tally resolved (Logic/PartyVote). The roster is frozen and the car leaves after
--                `launchCountdownSeconds`.
--
-- Walking out of a car is the universal undo: it drops you from the party, and if that party was
-- mid-vote the vote is torn down, because a ballot cast by a roster that no longer exists must never
-- launch anybody. Only "Launching" is one-way, and it is deliberately only a few seconds long.
--
-- WHY THE CAVE IS VOTED FOR RATHER THAN PICKED BY THE CAR YOU STAND IN. Standing somewhere used to
-- BE the tier choice, which meant a party could not gather without also committing, and readiness
-- had no separate meaning at all. Splitting the two is what lets four friends get in one car, talk,
-- and then decide.
--
-- Receives PartyLobbyService as a parameter rather than requiring it, to avoid a require cycle
-- (PartyLobbyService already requires LobbyRoomBuilder, which this file also consumes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local PartyInterface = require(ReplicatedStorage.Shared.Interfaces.Party)
local PartyVote = require(ReplicatedStorage.Shared.Logic.PartyVote)
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)
local LeverGeometry = require(ReplicatedStorage.Shared.Logic.LeverGeometry)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local LobbyRoomBuilder = require(script.Parent.LobbyRoomBuilder)
local RequestGuard = require(script.Parent.RequestGuard)

local ElevatorService = {}

type Party = PartyInterface.Party

type LobbyStartService = {
	tryLaunch: (Party) -> boolean,
	isLobbyClosed: () -> boolean,
	notifyLobbyChanged: (string?) -> (),
	notifyPlayer: (Player, string) -> (),
	notifyParty: (Party, string) -> (),
}

type Ride = {
	partyId: number,
	tierId: number,
	riders: { Types.PlayerId },
	startedAt: number,
	duration: number,
}

-- The hub's own lantern warmth when a car is committed to a descent, and cold dead iron otherwise.
local LEVER_LAMP_LIT = Color3.fromRGB(255, 188, 112)
local LEVER_LAMP_DARK = Color3.fromRGB(38, 37, 36)
-- Every car in the hub shares one width, so the lever's hinge sits at the same car-local offset in
-- all of them; computed once rather than on every reset.
local LEVER_PIVOT_OFFSET = LeverGeometry.layout(Config.LobbyRoom.elevatorCarWidth / 2).pivotOffset

local partyLobbyService: LobbyStartService? = nil
-- Keyed by party. Several parties may be riding down at once, so none of this can be a single slot.
local rides: { [number]: Ride } = {}
local rideCandleRiders: { [number]: { [Types.PlayerId]: boolean } } = {}
local carsAtRest: { [number]: boolean } = {}
local voteDeadline: { [number]: number } = {}
local launchAt: { [number]: number } = {}
-- Cached per party so the tick's board refresh only writes Instance properties when the rendered
-- content actually changed.
local lastBoardSignature: { [number]: string } = {}

local function minimumPlayers(): number
	return math.max(Config.Lobby.minimumPlayers, if Config.Run.soloAllowed then 1 else 2)
end

local function elevatorFor(partyId: number): LobbyRoomBuilder.ElevatorParts?
	for _, elevator in LobbyRoomBuilder.elevators() do
		if elevator.partyId == partyId then
			return elevator
		end
	end
	return nil
end

-- THE LEVER'S PROMPT AND ITS LAMP ARE ONE DECISION, so they are set through one call and never
-- separately. Writes nothing when nothing changed, because this runs on every lobby tick against
-- every car and these are replicated properties.
local function setLeverLive(elevator: LobbyRoomBuilder.ElevatorParts, live: boolean)
	if elevator.lever.Enabled == live then
		return
	end
	elevator.lever.Enabled = live
	local lamp = elevator.leverLamp
	lamp.Material = if live then Enum.Material.Neon else Enum.Material.Metal
	lamp.Color = if live then LEVER_LAMP_LIT else LEVER_LAMP_DARK
	local glow = lamp:FindFirstChildOfClass("PointLight")
	if glow ~= nil then
		glow.Enabled = live
	end
end

-- Horizontal-only: elevator zones don't care about vertical position. Nil-safe by design, because
-- the window where a player has no character (mid-transition, mid-LoadCharacter) must read as "in no
-- elevator", never error.
local function elevatorPartyIdAt(player: Player): number?
	local character = player.Character
	local root = if character ~= nil then character.PrimaryPart else nil
	if root == nil then
		return nil
	end
	local position = root.Position
	for _, elevator in Config.LobbyRoom.elevators do
		local target = Config.LobbyRoom.origin + elevator.offset
		local dx, dz = position.X - target.X, position.Z - target.Z
		if math.sqrt(dx * dx + dz * dz) <= Config.LobbyRoom.elevatorZoneRadius then
			return elevator.partyId
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The cave vote
--------------------------------------------------------------------------------

-- Every cave that EVERY member of this party could pay the admission for right now. A tier that one
-- member cannot afford is not a legal outcome for the party, so it is removed from the ballot rather
-- than allowed to win and then refuse to launch.
local function affordableTiers(party: Party): { number }
	local result: { number } = {}
	for _, tier in Interfaces.CaveTiers.list() do
		local affordableForAll = true
		for _, memberId in party.members do
			if not Interfaces.CaveTiers.canAfford(memberId, tier.id) then
				affordableForAll = false
				break
			end
		end
		if affordableForAll then
			table.insert(result, tier.id)
		end
	end
	return result
end

-- Resolves the ballot to a cave this party can actually descend into.
--
-- VOTES FOR AN UNAFFORDABLE CAVE ARE DROPPED, NOT HONOURED-THEN-REFUSED. If the tally could return a
-- tier somebody cannot pay for, the party would bounce back to gathering, re-ready, and deadlock on
-- the same result forever. Dropping those votes first means the answer is always launchable, and the
-- free cave is always in the affordable set, so there is always an answer at all.
local function resolveTier(party: Party): number?
	local legal = affordableTiers(party)
	if #legal == 0 then
		return nil
	end
	local ballot: PartyVote.VoteMap = {}
	for memberId, tierId in party.votes do
		if table.find(legal, tierId) ~= nil then
			ballot[memberId] = tierId
		end
	end
	return PartyVote.resolve(ballot, party.members, party.leaderId, legal[1])
end

local function everyoneVoted(party: Party): boolean
	for _, memberId in party.members do
		if party.votes[memberId] == nil then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Header boards
--------------------------------------------------------------------------------

local function rosterFor(party: Party?): string
	if party == nil or #party.members == 0 then
		return "empty"
	end
	local lines: { string } = {}
	for _, playerId in party.members do
		local player = Players:GetPlayerByUserId(playerId)
		if player == nil then
			continue
		end
		local mark = if party.ready[playerId] == true then "[x]" else "[  ]"
		local suffix = if playerId == party.leaderId then "  (lead)" else ""
		table.insert(lines, string.format("%s  %s%s", mark, player.DisplayName, suffix))
	end
	return table.concat(lines, "\n")
end

local function statusFor(party: Party?): string
	if party == nil then
		return "Step in to start a party"
	end
	local capacity = string.format("%d / %d", #party.members, Config.Run.partyCap)
	if party.phase == "Launching" then
		local tier = Interfaces.CaveTiers.get(party.tierId)
		return if tier ~= nil then ("DESCENDING  " .. string.upper(tier.displayName)) else "DESCENDING"
	end
	if party.phase == "Voting" then
		local voted = 0
		for _, memberId in party.members do
			if party.votes[memberId] ~= nil then
				voted += 1
			end
		end
		return string.format("VOTING  %d of %d have chosen a cave", voted, #party.members)
	end
	local ready = 0
	for _, memberId in party.members do
		if party.ready[memberId] then
			ready += 1
		end
	end
	return string.format("%s in the car  /  %d ready", capacity, ready)
end

-- Repaints one alcove header from its party's state. Only touches Instances when the rendered
-- content actually changed: this runs every Heartbeat against every party.
local function refreshBoard(elevator: LobbyRoomBuilder.ElevatorParts, party: Party?)
	local status = statusFor(party)
	local roster = rosterFor(party)
	local signature = status .. "|" .. roster
	if lastBoardSignature[elevator.partyId] == signature then
		return
	end
	lastBoardSignature[elevator.partyId] = signature
	elevator.headerStatus.Text = status
	elevator.headerRoster.Text = roster
end

--------------------------------------------------------------------------------
-- The descent ride
--------------------------------------------------------------------------------

-- Puts one car back at its resting pivot and reopens its gate.
local function resetCar(partyId: number)
	local elevator = elevatorFor(partyId)
	if elevator == nil then
		return
	end
	local active = rides[partyId]
	if active ~= nil then
		for _, playerId in active.riders do
			CharacterService.setLobbyBodyAnchored(playerId, false)
		end
	end
	rides[partyId] = nil

	local riders = rideCandleRiders[partyId]
	if riders ~= nil then
		for playerId in riders do
			local player = Players:GetPlayerByUserId(playerId)
			local character = if player ~= nil then player.Character else nil
			if
				player ~= nil
				and character ~= nil
				and character:GetAttribute(LobbyVisualProtocol.attributes.rideBody) == true
			then
				task.spawn(function()
					local current = player.Character
					if
						player.Parent == Players
						and current ~= nil
						and current:GetAttribute(LobbyVisualProtocol.attributes.rideBody) == true
					then
						CharacterService.spawnLobby(player, LobbyRoomBuilder.spawnPositionForPlayer(player.UserId))
					end
				end)
			end
		end
	end
	rideCandleRiders[partyId] = nil

	elevator.car:PivotTo(elevator.restPivot)
	elevator.gate.CanCollide = false
	elevator.gate.Transparency = 1
	-- `PivotTo` carries every descendant along rigidly at whatever pose it was already in, so a lever
	-- left mid-pull would otherwise ride back up still thrown. Snap the handle back to armed now, in
	-- the same instantaneous write as the rest of the reset.
	local shaft = elevator.car:FindFirstChild("LeverShaft")
	local knob = elevator.car:FindFirstChild("LeverKnob")
	if shaft ~= nil and shaft:IsA("BasePart") and knob ~= nil and knob:IsA("BasePart") then
		local shaftLocal, knobLocal = LeverGeometry.handleCFrames(LEVER_PIVOT_OFFSET, LeverGeometry.REST_ANGLE)
		shaft.CFrame = elevator.restPivot * shaftLocal
		knob.CFrame = elevator.restPivot * knobLocal
	end
	lastBoardSignature[partyId] = ""
	carsAtRest[partyId] = true
end

-- Every car back at rest. Called when the lobby reopens, so a returning party never finds the cars
-- sunk down their shafts.
function ElevatorService.resetCars()
	for _, elevator in LobbyRoomBuilder.elevators() do
		resetCar(elevator.partyId)
	end
end

-- Begins the physical ride for whoever is standing in the departing car. Riders are captured once,
-- at departure: someone who was never in the car simply watches it go.
function ElevatorService.beginDescent(partyId: number, tierId: number)
	local elevator = elevatorFor(partyId)
	if elevator == nil then
		return
	end
	local party = Interfaces.Party.get(partyId)
	local candidates: { Types.PlayerId } = {}
	if party ~= nil then
		for _, playerId in party.members do
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil and elevatorPartyIdAt(player) == partyId then
				table.insert(candidates, playerId)
			end
		end
	end

	-- The gate is closed server-side so everyone in the room sees the car seal, not just the riders.
	elevator.gate.CanCollide = true
	elevator.gate.Transparency = 0
	setLeverLive(elevator, false)

	local riders: { Types.PlayerId } = {}
	local candleRiders: { [Types.PlayerId]: boolean } = {}
	for _, playerId in candidates do
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil and CharacterService.spawnRideCandle(player) then
			table.insert(riders, playerId)
			candleRiders[playerId] = true
			CharacterService.setLobbyBodyAnchored(playerId, true)
		end
	end
	rideCandleRiders[partyId] = candleRiders

	local startedAt = Workspace:GetServerTimeNow()
	local duration = math.max(Config.Run.startCountdownSeconds, 0.1)
	carsAtRest[partyId] = false
	rides[partyId] = {
		partyId = partyId,
		tierId = tierId,
		riders = riders,
		startedAt = startedAt,
		duration = duration,
	}
	-- One timestamped curve replaces per-frame replicated CFrames. Every client renders the same
	-- analytic car/rider motion locally; the server applies only the authoritative final transform.
	Remotes.get("RunEvent"):FireAllClients("elevatorRide", {
		partyId = partyId,
		tierId = tierId,
		riderIds = table.clone(riders),
		startedAt = startedAt,
		duration = duration,
		distance = Config.LobbyRoom.rideDistance,
		restPivot = elevator.restPivot,
	})
end

local function stepRide(active: Ride)
	local elevator = elevatorFor(active.partyId)
	if elevator == nil then
		rides[active.partyId] = nil
		return
	end

	local progress = (Workspace:GetServerTimeNow() - active.startedAt) / active.duration
	if progress >= 1 then
		local finalOffset = Vector3.new(0, -Config.LobbyRoom.rideDistance, 0)
		elevator.car:PivotTo(elevator.restPivot + finalOffset)
		for _, playerId in active.riders do
			CharacterService.nudgeLobbyBody(playerId, finalOffset)
			-- Released rather than left anchored so a failed or cancelled departure can recover them.
			CharacterService.setLobbyBodyAnchored(playerId, false)
		end
		rides[active.partyId] = nil
	end
end

--------------------------------------------------------------------------------
-- Occupancy and phases
--------------------------------------------------------------------------------

-- A departed car leaves an open shaft in the hub floor, and the hub is the one place a player can be
-- stranded with no run to reset them. Anyone well below the floor is put back at the spawn pad.
local function recoverFallenBodies()
	local floorY = Config.LobbyRoom.origin.Y
	for _, player in Players:GetPlayers() do
		local position = CharacterService.lobbyBodyPosition(player.UserId)
		if position == nil or position.Y >= floorY - Config.LobbyRoom.fallRecoveryDrop then
			continue
		end
		-- Repositioned, not respawned: spawnLobby yields on LoadCharacter, and this runs inside the
		-- Heartbeat tick chain where a yield would stall every service after it.
		CharacterService.teleportLobbyBody(player.UserId, LobbyRoomBuilder.spawnPositionForPlayer(player.UserId))
	end
end

-- Standing in a car is party MEMBERSHIP now, never readiness. Joining and leaving is the only thing
-- position decides; the ready toggle is an explicit act (the in-car lever, or the client's party UI).
local function returnToLanding(player: Player, partyId: number)
	for _, elevator in Config.LobbyRoom.elevators do
		if elevator.partyId == partyId then
			CharacterService.teleportLobbyBody(
				player.UserId,
				Config.LobbyRoom.origin + elevator.offset + Config.LobbyRoom.elevatorExitOffset
			)
			return
		end
	end
	CharacterService.teleportLobbyBody(player.UserId, LobbyRoomBuilder.spawnPositionForPlayer(player.UserId))
end

local function syncOccupancy(): boolean
	local changed = false
	local service = partyLobbyService
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local partyId = elevatorPartyIdAt(player)
		local party = Interfaces.Party.forPlayer(player.UserId)
		local currentPartyId = if party ~= nil then party.partyId else nil
		if partyId == currentPartyId then
			continue
		end
		if partyId == nil then
			-- Walked out. A member of a car that has already committed keeps their seat: the ride is
			-- carrying them and their body is anchored, so their root drifting out of the zone during
			-- the descent must not drop them from the party mid-teleport.
			if party ~= nil and party.phase ~= "Launching" then
				Interfaces.Party.leave(player.UserId)
				changed = true
			end
		else
			local blockRemaining = Interfaces.Party.joinBlockRemaining(player.UserId, partyId, now)
			if blockRemaining > 0 then
				if party ~= nil and party.phase ~= "Launching" then
					Interfaces.Party.leave(player.UserId)
					changed = true
				end
				returnToLanding(player, partyId)
				if service ~= nil then
					service.notifyPlayer(
						player,
						string.format(
							"Party %d is closed to you for %d more seconds.",
							partyId,
							math.ceil(blockRemaining)
						)
					)
				end
			elseif Interfaces.Party.join(player.UserId, partyId, Config.Run.partyCap, now) then
				changed = true
			else
				-- Full and committed cars cannot hold an untracked fifth body. Put the player back in the
				-- Landing rather than retrying a refused join every Heartbeat while they stand inside it.
				if party ~= nil and party.phase ~= "Launching" then
					Interfaces.Party.leave(player.UserId)
					changed = true
				end
				returnToLanding(player, partyId)
				if service ~= nil then
					service.notifyPlayer(player, "That elevator party is full or already descending.")
				end
			end
		end
	end
	return changed
end

local function leaveFromPanel(player: Player)
	local service = partyLobbyService
	local party = Interfaces.Party.forPlayer(player.UserId)
	if service == nil or party == nil then
		return
	end
	if party.phase == "Launching" then
		service.notifyPlayer(player, "The gate is already closed.")
		return
	end
	Interfaces.Party.leave(player.UserId)
	returnToLanding(player, party.partyId)
	service.notifyLobbyChanged(nil)
end

local function kickFromPanel(player: Player, targetId: number)
	local service = partyLobbyService
	local party = Interfaces.Party.forPlayer(player.UserId)
	local target = Players:GetPlayerByUserId(targetId)
	if service == nil or party == nil or target == nil then
		return
	end

	local blockedUntil = os.clock() + Config.Lobby.kickRejoinBlockSeconds
	if not Interfaces.Party.kick(player.UserId, targetId, blockedUntil) then
		service.notifyPlayer(player, "Only the party leader can remove another rider before launch.")
		return
	end

	returnToLanding(target, party.partyId)
	service.notifyParty(party, string.format("%s removed %s from the party.", player.DisplayName, target.DisplayName))
	service.notifyPlayer(
		target,
		string.format(
			"You were removed from Party %d. Re-entry is blocked for %d seconds.",
			party.partyId,
			Config.Lobby.kickRejoinBlockSeconds
		)
	)
end

-- Advances one party through Gathering -> Voting -> Launching. Returns a status line when something
-- happened that the party should be told about.
local function stepParty(party: Party, now: number): string?
	local service = partyLobbyService
	if service == nil then
		return nil
	end
	local partyId = party.partyId

	if party.phase == "Gathering" then
		if Interfaces.Party.allReady(party, minimumPlayers()) then
			Interfaces.Party.setPhase(partyId, "Voting")
			voteDeadline[partyId] = now + Config.Lobby.voteSeconds
			return "Everyone is ready. Choose a cave."
		end
		return nil
	end

	if party.phase == "Voting" then
		local deadline = voteDeadline[partyId] or 0
		if not everyoneVoted(party) and now < deadline then
			return nil
		end
		local tierId = resolveTier(party)
		if tierId == nil then
			-- Cannot happen while the free cave stays free, and is handled rather than asserted
			-- because the alternative is a party frozen in a vote it can never close.
			Interfaces.Party.setPhase(partyId, "Gathering")
			return "No cave in reach of this party. Ready up again."
		end
		Interfaces.Party.setTier(partyId, tierId)
		Interfaces.Party.setPhase(partyId, "Launching")
		launchAt[partyId] = now + Config.Lobby.launchCountdownSeconds
		local tier = Interfaces.CaveTiers.get(tierId)
		return if tier ~= nil then (tier.displayName .. " wins the vote. Hold on.") else nil
	end

	if party.phase == "Launching" then
		if now < (launchAt[partyId] or 0) then
			return nil
		end
		launchAt[partyId] = nil
		if service.tryLaunch(party) then
			ElevatorService.beginDescent(partyId, party.tierId)
		else
			Interfaces.Party.setPhase(partyId, "Gathering")
			return "The descent could not be opened. Ready up again."
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

function ElevatorService.tick()
	local service = partyLobbyService
	if service == nil then
		return
	end

	for _, active in rides do
		stepRide(active)
	end
	if service.isLobbyClosed() then
		return
	end
	recoverFallenBodies()

	local now = os.clock()
	local changed = syncOccupancy()
	-- Phase messages are addressed to the party they happened to, never broadcast: four parties share
	-- this room and "everyone is ready" is only true for one of them. Collected rather than sent
	-- inside the loop so a party that steps twice in one tick still only produces one send.
	local messages: { { party: Party, text: string } } = {}
	for _, party in Interfaces.Party.list() do
		if party.partyId == 0 then
			-- The expedition party of a reserved server. It has no car and no vote.
			continue
		end
		local message = stepParty(party, now)
		if message ~= nil then
			table.insert(messages, { party = party, text = message })
			changed = true
		end
	end

	for _, elevator in LobbyRoomBuilder.elevators() do
		local partyId = elevator.partyId
		local party = Interfaces.Party.get(partyId)
		-- No party and no ride means this car is idle, so it belongs at the top of its shaft. Reached
		-- both on a normal lobby return and after a descent that never became a run.
		if rides[partyId] == nil and carsAtRest[partyId] == false and party == nil then
			resetCar(partyId)
		end
		-- The lever is the ready toggle, so it is live exactly while readying is a legal act.
		setLeverLive(elevator, party ~= nil and party.phase ~= "Launching")
		refreshBoard(elevator, party)
	end

	if #messages > 0 then
		-- Each of these already refreshes every client's state, so the plain refresh below is only for
		-- the case where something changed with nothing to say about it.
		for _, entry in messages do
			service.notifyParty(entry.party, entry.text)
		end
	elseif changed then
		service.notifyLobbyChanged(nil)
	end
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------

function ElevatorService.init(service: LobbyStartService)
	partyLobbyService = service
	-- PartyLobbyService owns ready/vote/sync on this remote. Leave and kick change physical elevator
	-- occupancy as well as party state, so they are handled here after their own rate-limit check.
	Remotes.get("LobbyAction").OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		if typeof(action) ~= "string" or (action ~= "leave" and action ~= "kick") then
			return
		end
		if not RequestGuard.allow(player, "LobbyAction") then
			return
		end
		if service.isLobbyClosed() then
			return
		end
		if action == "leave" then
			leaveFromPanel(player)
			return
		end
		if not RequestGuard.finiteNumber(value) then
			return
		end
		local targetId = value :: number
		if targetId <= 0 or targetId % 1 ~= 0 then
			return
		end
		kickFromPanel(player, targetId)
	end)
	for _, elevator in LobbyRoomBuilder.elevators() do
		local partyId = elevator.partyId
		carsAtRest[partyId] = true
		-- THE LEVER IS NOW THE READY TOGGLE, not the launch. There is no leader-pulls-to-go any more,
		-- because the cave is decided by a vote and the descent follows from that vote resolving. The
		-- lever survives as the diegetic way to say "I am in", beside the client party UI's button:
		-- ProximityPrompt.Enabled is one shared property, so it is enabled for the whole car and the
		-- handler below resolves who actually pulled it.
		elevator.lever.Triggered:Connect(function(player: Player)
			local party = Interfaces.Party.forPlayer(player.UserId)
			if party == nil or party.partyId ~= partyId then
				service.notifyPlayer(player, "Stand inside the car to ready up.")
				return
			end
			local nowReady = party.ready[player.UserId] ~= true
			if Interfaces.Party.setReady(player.UserId, nowReady) then
				service.notifyLobbyChanged(nil)
			end
		end)
	end
end

return ElevatorService

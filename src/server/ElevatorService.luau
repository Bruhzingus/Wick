--!strict
-- The physical lobby's entire tier-select/ready/start interaction, and the descent ride that
-- replaces the old flat loading countdown. Standing in an elevator's zone is readiness for that
-- tier; the leader's chosen elevator sets the party's tier; a leader-only lever in each car starts
-- the expedition through the exact same validated path the old 2D UI used
-- (PartyLobbyService.tryStart). When it starts, the car physically descends its shaft, carrying
-- every rider with it, for the whole start countdown — the ride IS the transition into floor 1.
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
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)
local LeverGeometry = require(ReplicatedStorage.Shared.Logic.LeverGeometry)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CharacterService = require(script.Parent.CharacterService)
local LobbyRoomBuilder = require(script.Parent.LobbyRoomBuilder)

local ElevatorService = {}

type Party = PartyInterface.Party

type LobbyStartService = {
	tryStart: (Player) -> boolean,
	canStart: (Player) -> boolean,
	isLobbyClosed: () -> boolean,
	notifyLobbyChanged: (string?) -> (),
}

type Ride = {
	tierId: number,
	riders: { Types.PlayerId },
	startedAt: number,
	duration: number,
}

-- The hub's own lantern warmth when the descent is available, and cold dead iron when it is not.
local LEVER_LAMP_LIT = Color3.fromRGB(255, 188, 112)
local LEVER_LAMP_DARK = Color3.fromRGB(38, 37, 36)
-- Every car in the hub shares one width, so the lever's hinge sits at the same car-local offset in
-- all of them; computed once rather than on every reset.
local LEVER_PIVOT_OFFSET = LeverGeometry.layout(Config.LobbyRoom.elevatorCarWidth / 2).pivotOffset

-- THE LEVER'S PROMPT AND ITS LAMP ARE ONE DECISION, so they are set through one call and never
-- separately. A dark lever that still accepts a pull, or a lit one that refuses, both read as the
-- descent being broken — and both are the kind of thing that only ever goes wrong because two lines
-- somewhere drifted apart.
--
-- Writes nothing when nothing changed, because this runs on every lobby tick against every car and
-- these are replicated properties. The prompt's own `Enabled` is the state of record: the lamp is
-- built dark to match a prompt built disabled, and only ever moves through here, so the two cannot
-- come apart without this early return being wrong.
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

local partyLobbyService: LobbyStartService? = nil
local ride: Ride? = nil
local rideCandleRiders: { [Types.PlayerId]: boolean } = {}
-- False from the moment a car departs until it is put back. Lets `tick` notice a descent that ended
-- without an expedition (failed teleport, emptied party) and bring the hub back to a usable state.
local carsAtRest = true
-- Cached so the per-tick board refresh only writes Instance properties when something changed.
local lastBoardSignature = ""

local function elevatorFor(tierId: number): LobbyRoomBuilder.ElevatorParts?
	for _, elevator in LobbyRoomBuilder.elevators() do
		if elevator.tierId == tierId then
			return elevator
		end
	end
	return nil
end

-- Horizontal-only: elevator zones don't care about vertical position. Nil-safe by design — the
-- window where a player has no character (mid-transition, mid-LoadCharacter) must read as "in no
-- elevator", never error.
local function elevatorPlayerIsStandingIn(player: Player): number?
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
			return elevator.tierId
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Header boards (the "party maker" display)
--------------------------------------------------------------------------------

local function rosterFor(occupants: { [number]: { string } }, tierId: number): string
	local names = occupants[tierId]
	return if names ~= nil and #names > 0 then table.concat(names, "\n") else "— empty —"
end

-- Repaints every alcove header from the current party state. Only touches Instances when the
-- rendered content actually changed: this runs every Heartbeat.
local function refreshBoards(party: Party?, canStart: boolean)
	local occupants: { [number]: { string } } = {}
	local lockedFor: { [number]: boolean } = {}

	if party ~= nil then
		for _, playerId in party.members do
			local player = Players:GetPlayerByUserId(playerId)
			if player == nil then
				continue
			end
			local tierId = elevatorPlayerIsStandingIn(player)
			if tierId ~= nil then
				local list = occupants[tierId]
				if list == nil then
					list = {}
					occupants[tierId] = list
				end
				local isReady = party.ready[playerId] == true
				table.insert(list, (if isReady then "● " else "○ ") .. player.DisplayName)
			end
		end
		for _, elevator in Config.LobbyRoom.elevators do
			for _, playerId in party.members do
				if not Interfaces.CaveTiers.canAfford(playerId, elevator.tierId) then
					lockedFor[elevator.tierId] = true
					break
				end
			end
		end
	end

	local signature = ""
	for _, elevator in LobbyRoomBuilder.elevators() do
		local names = occupants[elevator.tierId]
		signature ..= string.format(
			"%d:%s:%s:%s|",
			elevator.tierId,
			if lockedFor[elevator.tierId] then "L" else "u",
			if party ~= nil and party.tierId == elevator.tierId then "S" else "-",
			if names ~= nil then table.concat(names, ",") else ""
		)
	end
	signature ..= if canStart then "GO" else "--"
	if signature == lastBoardSignature then
		return
	end
	lastBoardSignature = signature

	for _, elevator in LobbyRoomBuilder.elevators() do
		if party == nil then
			elevator.headerStatus.Text = "Waiting for a party"
			elevator.headerRoster.Text = ""
			continue
		end
		if lockedFor[elevator.tierId] then
			-- "Locked" now means "somebody in this party cannot pay the toll", not "nobody has crossed
			-- a lifetime threshold". The number shown is the admission itself, because that is the
			-- thing a player has to go and earn.
			local tier = Interfaces.CaveTiers.get(elevator.tierId)
			elevator.headerStatus.Text = if tier ~= nil
				then string.format(
					"CLOSED — %d Raw Wax each to descend, or buy it outright at the shop",
					tier.entryFee
				)
				else "CLOSED"
			elevator.headerRoster.Text = rosterFor(occupants, elevator.tierId)
			continue
		end

		local status: string
		if party.tierId ~= elevator.tierId then
			status = "Step in to vote with your feet"
		elseif canStart then
			status = "READY — the leader may pull the lever"
		else
			status = "SELECTED — everyone step in to ready up"
		end
		elevator.headerStatus.Text = status
		elevator.headerRoster.Text = rosterFor(occupants, elevator.tierId)
	end
end

--------------------------------------------------------------------------------
-- The descent ride
--------------------------------------------------------------------------------

-- Puts every car back at its resting pivot and reopens its gate. Called when a ride resolves and
-- whenever the lobby reopens, so a returning party never finds the cars sunk down their shafts.
function ElevatorService.resetCars()
	local active = ride
	if active ~= nil then
		for _, playerId in active.riders do
			CharacterService.setLobbyBodyAnchored(playerId, false)
		end
	end
	ride = nil
	local party = Interfaces.Party.snapshot()
	for playerId in rideCandleRiders do
		local player = Players:GetPlayerByUserId(playerId)
		local character = if player ~= nil then player.Character else nil
		if
			player ~= nil
			and character ~= nil
			and character:GetAttribute(LobbyVisualProtocol.attributes.rideBody) == true
		then
			local slot = if party ~= nil then (table.find(party.members, playerId) or 1) else 1
			task.spawn(function()
				local current = player.Character
				if
					player.Parent == Players
					and current ~= nil
					and current:GetAttribute(LobbyVisualProtocol.attributes.rideBody) == true
				then
					CharacterService.spawnLobby(player, LobbyRoomBuilder.spawnPositionFor(slot))
				end
			end)
		end
	end
	table.clear(rideCandleRiders)
	for _, elevator in LobbyRoomBuilder.elevators() do
		elevator.car:PivotTo(elevator.restPivot)
		elevator.gate.CanCollide = false
		elevator.gate.Transparency = 1
		-- `PivotTo` carries every descendant along rigidly at whatever pose it was already in, so a
		-- lever left mid-pull (or fully thrown) would otherwise ride back up still thrown. Snap the
		-- handle back to armed now, in the same instantaneous write as the rest of the reset.
		local shaft = elevator.car:FindFirstChild("LeverShaft")
		local knob = elevator.car:FindFirstChild("LeverKnob")
		if shaft ~= nil and shaft:IsA("BasePart") and knob ~= nil and knob:IsA("BasePart") then
			local shaftLocal, knobLocal = LeverGeometry.handleCFrames(LEVER_PIVOT_OFFSET, LeverGeometry.REST_ANGLE)
			shaft.CFrame = elevator.restPivot * shaftLocal
			knob.CFrame = elevator.restPivot * knobLocal
		end
	end
	lastBoardSignature = ""
	carsAtRest = true
end

-- Begins the physical ride for whoever is standing in the departing car. Riders are captured once,
-- at departure: someone who was never in the car simply watches it go.
function ElevatorService.beginDescent(tierId: number)
	local elevator = elevatorFor(tierId)
	if elevator == nil then
		return
	end
	local party = Interfaces.Party.snapshot()
	local candidates: { Types.PlayerId } = {}
	if party ~= nil then
		for _, playerId in party.members do
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil and elevatorPlayerIsStandingIn(player) == tierId then
				table.insert(candidates, playerId)
			end
		end
	end

	-- The gate is closed server-side so everyone in the room sees the car seal, not just the riders.
	elevator.gate.CanCollide = true
	elevator.gate.Transparency = 0
	for _, other in LobbyRoomBuilder.elevators() do
		setLeverLive(other, false)
	end
	local riders: { Types.PlayerId } = {}
	table.clear(rideCandleRiders)
	for _, playerId in candidates do
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil and CharacterService.spawnRideCandle(player) then
			table.insert(riders, playerId)
			rideCandleRiders[playerId] = true
			CharacterService.setLobbyBodyAnchored(playerId, true)
		end
	end

	local startedAt = Workspace:GetServerTimeNow()
	carsAtRest = false
	ride = {
		tierId = tierId,
		riders = riders,
		startedAt = startedAt,
		duration = math.max(Config.Run.startCountdownSeconds, 0.1),
	}
	-- One timestamped curve replaces per-frame replicated CFrames. Every client renders the same
	-- analytic car/rider motion locally; the server applies only the authoritative final transform.
	Remotes.get("RunEvent"):FireAllClients("elevatorRide", {
		tierId = tierId,
		riderIds = table.clone(riders),
		startedAt = startedAt,
		duration = math.max(Config.Run.startCountdownSeconds, 0.1),
		distance = Config.LobbyRoom.rideDistance,
		restPivot = elevator.restPivot,
	})
end

local function stepRide()
	local active = ride
	if active == nil then
		return
	end
	local elevator = elevatorFor(active.tierId)
	if elevator == nil then
		ride = nil
		return
	end

	local progress = (Workspace:GetServerTimeNow() - active.startedAt) / active.duration
	if progress >= 1 then
		local finalOffset = Vector3.new(0, -Config.LobbyRoom.rideDistance, 0)
		elevator.car:PivotTo(elevator.restPivot + finalOffset)
		for _, playerId in active.riders do
			CharacterService.nudgeLobbyBody(playerId, finalOffset)
		end
		-- The car has arrived. Studio's local run replaces each rider with a candle; a live lobby now
		-- begins its reserved-server teleport. The car stays down while the lobby is closed. Riders
		-- are released rather than left anchored so a failed/cancelled departure can recover them.
		for _, playerId in active.riders do
			CharacterService.setLobbyBodyAnchored(playerId, false)
		end
		ride = nil
	end
end

--------------------------------------------------------------------------------
-- Tick
--------------------------------------------------------------------------------

-- A departed car leaves an open shaft in the hub floor, and the hub is the one place a player can
-- be stranded with no run to reset them. Anyone who ends up well below the floor is put back at the
-- spawn pad rather than falling forever.
local function recoverFallenBodies(party: Party)
	local floorY = Config.LobbyRoom.origin.Y
	for slot, playerId in party.members do
		local position = CharacterService.lobbyBodyPosition(playerId)
		if position == nil or position.Y >= floorY - Config.LobbyRoom.fallRecoveryDrop then
			continue
		end
		-- Repositioned, not respawned: spawnLobby yields on LoadCharacter, and this runs inside the
		-- Heartbeat tick chain where a yield would stall every service after it.
		CharacterService.teleportLobbyBody(playerId, LobbyRoomBuilder.spawnPositionFor(slot))
	end
end

-- Every heartbeat: advance any ride, then keep each elevator's zone mapped into Interfaces.Party
-- and each lever's availability current. Only ever calls Party.setTier/setReady when the value
-- actually needs to change — Party.setTier unconditionally resets everyone's readiness, so calling
-- it every tick while the leader merely stands still would make becoming ready impossible.
function ElevatorService.tick()
	local service = partyLobbyService
	if service == nil then
		return
	end
	if ride ~= nil then
		stepRide()
		return
	end
	if service.isLobbyClosed() then
		return
	end
	-- No ride and no expedition means the hub is open for business, so the cars belong at the top of
	-- their shafts. Reached both on a normal lobby return and after a descent that never became a run.
	if not carsAtRest then
		ElevatorService.resetCars()
	end

	local party = Interfaces.Party.snapshot()
	if party == nil then
		refreshBoards(nil, false)
		return
	end

	recoverFallenBodies(party)

	local changed = false
	local status: string? = nil
	for _, player in Players:GetPlayers() do
		if table.find(party.members, player.UserId) == nil then
			continue
		end
		local elevatorId = elevatorPlayerIsStandingIn(player)
		if player.UserId == party.leaderId and elevatorId ~= nil and party.tierId ~= elevatorId then
			-- Guard affordability here as well as at start: without this a leader stepping into a car
			-- they cannot pay for would silently wipe the whole party's readiness and leave the lever
			-- dark with no explanation.
			if Interfaces.CaveTiers.canAfford(player.UserId, elevatorId) then
				Interfaces.Party.setTier(player.UserId, elevatorId)
				local tier = Interfaces.CaveTiers.get(elevatorId)
				status = if tier ~= nil then (tier.displayName .. " selected. Ready up again.") else nil
				changed = true
			else
				local tier = Interfaces.CaveTiers.get(elevatorId)
				status = if tier ~= nil
					then string.format(
						"%s costs %d Raw Wax to descend — you cannot pay it yet. Buy it outright at the shop.",
						tier.displayName,
						tier.entryFee
					)
					else nil
			end
		end
		local shouldBeReady = elevatorId ~= nil and elevatorId == party.tierId
		if shouldBeReady ~= (party.ready[player.UserId] == true) then
			Interfaces.Party.setReady(player.UserId, shouldBeReady)
			changed = true
		end
	end

	local leader = Players:GetPlayerByUserId(party.leaderId)
	local canStart = leader ~= nil and service.canStart(leader)
	for _, elevator in LobbyRoomBuilder.elevators() do
		-- ProximityPrompt.Enabled is one instance property shared by every client, so this cannot be
		-- leader-only on its own. The Triggered handler's tryStart re-checks the leader server-side.
		setLeverLive(elevator, canStart and elevator.tierId == party.tierId)
	end

	refreshBoards(party, canStart)
	if changed or status ~= nil then
		-- ElevatorService mutates party state that the client's status readout reflects; without this
		-- the lobby would silently change tier/readiness with no feedback anywhere on screen.
		service.notifyLobbyChanged(status)
	end
end

function ElevatorService.init(service: LobbyStartService)
	partyLobbyService = service
	for _, elevator in LobbyRoomBuilder.elevators() do
		local tierId = elevator.tierId
		elevator.lever.Triggered:Connect(function(player: Player)
			-- tryStart owns the leader/ready/unlock validation and reports whether it actually
			-- launched; a non-leader who manages to trigger the shared prompt is rejected in there.
			if service.tryStart(player) then
				ElevatorService.beginDescent(tierId)
			end
		end)
	end
end

return ElevatorService

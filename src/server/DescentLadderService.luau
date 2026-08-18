--!strict
-- THE DESCENT LADDER's authority (Config/DescentLadder, FLOOR-FIXTURES-OVERHAUL): the prompt on the
-- cage, the ride's clock, every pose written to the cage and the hatch, and nothing else.
--
-- WHAT THIS FILE DOES NOT OWN, and must not learn: what a floor is, how one is carved, where a
-- runner arrives, or what `state.depth` means. Those belong to `RunOrchestrator`, which hands this
-- service two callbacks at init — one that says whether a player may set off, and one that performs
-- the move when the cage lands. The dependency runs one way only (orchestrator -> ladder), so the
-- module that owns floors can keep owning them.
--
-- THE RIDE IS SERVER-TIMED AND CLIENT-DRAWN. One timestamped curve is broadcast at departure and
-- every client reconstructs the same descent locally; the only authoritative transforms written here
-- are the cage's bottom pose when the ride ends and its return to rest afterwards. That is the exact
-- division `ElevatorService`/`ElevatorController` already use, and for the same reason: a per-frame
-- replicated CFrame judders at precisely the moment a player is looking hardest at it.
--
-- PER-CAGE, NEVER PER-PARTY. Each ride belongs to a fixture rather than to a group, so two people
-- descending different floors need no coordination at all. Two people at the SAME ladder share the
-- car: it carries `Config.DescentLadder.riderCapacity` (two), because a party crosses a floor together
-- and arrives at the ladder together. The third and any after them wait for the cage to come back up.
-- That wait is the only queueing in the system and it is a property of the fixture, not a rule.
--
-- A COMPANION IS BOARDED, NOT DRAGGED. Only somebody already standing on the deck when the winch is
-- pulled rides along, and only if the orchestrator would have let them set off on their own. Everyone
-- else on the mouth is stepped onto the collar exactly as before. Nobody is ever moved to a floor they
-- could not have reached by pulling the lever themselves.
--
-- ONE WAY, ONE FLOOR. There is no control to go back up and no connection whatsoever to
-- `ReturnToLobby`. A player who wants to leave the cave uses the Brazier and the lobby flow.
--
-- THE THRESHOLD IS TEMPORARILY ENEMY-SAFE. Threats stop targeting riders as soon as the gate closes
-- and through a short post-arrival grace. Wax drain and environmental hazards still apply: this is a
-- narrow anti-cheap-shot rule for a player the machine has pinned, not a reusable safe room.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local DescentLadder = require(ReplicatedStorage.Shared.NewModelsAndObjects.DescentLadder)
local DescentElevatorRules = require(ReplicatedStorage.Shared.Logic.DescentElevatorRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local MovementSanityService = require(script.Parent.MovementSanityService)
local Telemetry = require(script.Parent.Telemetry)

local DescentLadderService = {}

-- Answered by RunOrchestrator. `canDescend` also builds the floor below synchronously if lookahead has
-- not reached it, before this service commits or broadcasts the ride.
type DescentGuard = (playerId: Types.PlayerId, fromDepth: number) -> boolean
type DescentCompletion = (playerId: Types.PlayerId, fromDepth: number, landingPosition: Vector3) -> boolean

type Ladder = {
	depth: number,
	built: DescentLadder.BuiltLadder,
	prompt: ProximityPrompt,
	-- Server clock time the cage is available again. Covers the ride AND the winch hauling the empty
	-- cage back, because a cage at the bottom of a shaft is not a cage anybody can board.
	busyUntil: number,
}

type Ride = {
	-- Everyone the cage is carrying, in boarding order. The player who pulled the winch is first; a
	-- companion who stepped on with them follows. Never longer than `riderCapacity`.
	riderIds: { Types.PlayerId },
	-- Where each rider was put on the deck, so a refused arrival can be put back exactly where they
	-- boarded rather than stacked on the cage's centre line with whoever else was refused.
	boardedAt: { [Types.PlayerId]: Vector3 },
	depth: number,
	startedAt: number,
	endsAt: number,
	timeline: DescentElevatorRules.Timeline,
	-- When the mouth may be covered on the way down, and uncovered again on the way back up. Both are
	-- points on the ride curve rather than fixed delays, so a hatch never crosses the cage.
	hatchClosesAt: number,
	hatchOpensAt: number,
	hatchShut: boolean,
	phase: "Descending" | "Arrived" | "Pushing" | "Returning",
	disembarked: { [Types.PlayerId]: boolean },
	-- Set once the riders have been moved (or their moves refused). The cage still has its return leg
	-- to run after that, and this is what stops the completion firing twice while it does.
	resolved: boolean,
}

local ladders: { [number]: Ladder } = {} -- keyed by depth
local rides: { [number]: Ride } = {} -- keyed by depth; one cage, one ride, up to two riders
local canDescend: DescentGuard? = nil
local onArrive: DescentCompletion? = nil

local function setHatch(ladder: Ladder, closed: boolean)
	local built = ladder.built
	local poses = if closed then built.hatchClosed else built.hatchOpen
	for index, leaf in built.hatchLeaves do
		local pose = poses[index]
		if pose ~= nil then
			leaf.CFrame = pose
		end
	end
end

local function setGate(ladder: Ladder, closed: boolean)
	local built = ladder.built
	local poses = if closed then built.gateClosed else built.gateOpen
	local cagePivot = built.cage:GetPivot()
	for index, leaf in built.gateLeaves do
		local pose = poses[index]
		if pose ~= nil then
			leaf.CFrame = cagePivot * pose
		end
	end
end

-- The cage back at the mouth with its hatch folded open: the pose the fixture spends almost all of
-- its life in, and the only one a player may board from.
local function parkCage(ladder: Ladder)
	ladder.built.cage:PivotTo(ladder.built.cageRestPivot)
	setHatch(ladder, false)
	setGate(ladder, false)
	ladder.prompt.Enabled = true
	ladder.busyUntil = 0
end

local function notify(player: Player, text: string)
	Remotes.get("RunEvent"):FireClient(player, "message", { text = text })
end

-- WHERE EACH RIDER STANDS ON THE DECK. One rider takes the centre line; two are set either side of
-- it along the cage's own right vector, so the pair face the same way and neither is standing in the
-- other. Derived from the cage's rest pose rather than from world axes, so a future ladder that is
-- rotated in its room places its riders correctly without this being touched.
local function riderSlot(ladder: Ladder, index: number, total: number): Vector3
	local centre = ladder.built.riderPosition
	if total <= 1 then
		return centre
	end
	local spacing = Config.DescentLadder.riderSpacingStuds
	local across = ladder.built.cageRestPivot.RightVector
	local flat = Vector3.new(across.X, 0, across.Z)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(1, 0, 0)
	-- Evenly spread about the centre: two riders land at -spacing and +spacing.
	local offset = ((index - 1) - (total - 1) / 2) * spacing * 2
	return centre + direction * offset
end

-- SETTLE THE DECK BEFORE IT DROPS: who rides along, and who is stepped off.
--
-- The cage is a walkable platform in a room a party crosses together, so a second player standing on
-- it when somebody pulls the winch is not an edge case — with four runners it is the ordinary case.
-- It used to be answered by shoving all of them onto the collar. Now the first of them RIDES, up to
-- the cage's capacity, because "we are both going down" is what standing on the deck together means.
--
-- WHY A COMPANION IS STILL ASKED THE GUARD QUESTION. `canDescend` is the orchestrator's whole answer
-- to "may this player set off from this floor" — it re-checks their run state and it is what builds
-- the floor below when the lookahead has not reached it. A companion boarded without it would be a
-- player moved to a depth nobody ever asked permission for. It is cheap the second time: the floor
-- below was already proven by the player who pulled the lever.
--
-- ANYONE WHO CANNOT RIDE IS MOVED, NOT LEFT. Only riders enter server-owned cage control, so a player left standing
-- on the deck falls into a shaft that is about to be covered by the hatch. They would be recovered
-- eventually (`RunOrchestrator.recoverStrandedRunners` catches anyone below their floor) but recovery
-- puts them at the floor's ENTRY, which is a room-length punishment for standing in the wrong square.
-- So they take one step outward onto the collar, which is what the moment physically is. Authorised
-- like every other server-owned move so the movement sanity check does not read it as a teleport.
local function settleMouth(ladder: Ladder, riderId: Types.PlayerId, guard: DescentGuard): { Types.PlayerId }
	local config = Config.DescentLadder
	local mouthHalf = config.cageWidth / 2 + config.shaftClearance
	local stepOut = mouthHalf + 1.6
	local centre = ladder.built.riderPosition
	local companions: { Types.PlayerId } = {}
	local seats = math.max(math.floor(config.riderCapacity), 1) - 1
	for playerId, state in PlayerState.all() do
		if playerId == riderId or not state.alive or state.finished or state.depth ~= ladder.depth then
			continue
		end
		-- RUN RIGS ONLY, and that is load-bearing rather than incidental. In Studio the lobby shares
		-- this server and a player standing in the hub carries a default depth of 1, so a depth check
		-- alone would let a floor-one ride reach for somebody who is not in the cave at all.
		-- `basePosition` answers nil for a lobby body and a ghost — both are tracked apart from run
		-- rigs — which is what makes this the right question to ask.
		local position = CharacterService.basePosition(playerId)
		if position == nil then
			continue
		end
		local offset = Vector3.new(position.X - centre.X, 0, position.Z - centre.Z)
		if offset.Magnitude > mouthHalf then
			continue
		end
		if #companions < seats and state.snuffedAt == nil and guard(playerId, ladder.depth) then
			table.insert(companions, playerId)
			continue
		end
		-- Outward from the middle of the mouth, or an arbitrary but fixed direction for somebody
		-- standing exactly on the centre — anything is better than leaving them over the hole.
		local direction = if offset.Magnitude > 0.05 then offset.Unit else Vector3.new(1, 0, 0)
		local landing = centre + direction * stepOut
		CharacterService.teleport(playerId, landing)
		MovementSanityService.markAuthorized(playerId, landing)
		state.position = landing
	end
	return companions
end

local function beginRide(player: Player, ladder: Ladder)
	local playerId = player.UserId
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished or state.snuffedAt ~= nil then
		return
	end
	if state.depth ~= ladder.depth then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now < ladder.busyUntil or rides[ladder.depth] ~= nil then
		notify(player, "The cage is still below. Wait for it to come back up.")
		return
	end

	-- Validated against the body that exists NOW rather than the last periodic wax sample, exactly as
	-- the Basin's choice re-validation does: the prompt opened from the live character, and using an
	-- older position here would refuse an honest ride whenever the candle was still moving.
	local livePosition = CharacterService.basePosition(playerId)
	local config = Config.DescentLadder
	if
		livePosition == nil
		or (livePosition - ladder.built.riderPosition).Magnitude
			> config.promptRange + config.positionToleranceStuds
	then
		return
	end

	local guard = canDescend
	if guard == nil or not guard(playerId, ladder.depth) then
		notify(player, "The winch will not turn. The shaft below is not open.")
		return
	end

	-- WHO ELSE IS COMING, decided before anybody is moved. A companion is judged on where they are
	-- standing right now, and the player who pulled the winch has not been put on the deck yet — doing
	-- this after seating them would be measuring the mouth around a body that had just been teleported
	-- into the middle of it.
	local riderIds: { Types.PlayerId } = { playerId }
	for _, companionId in settleMouth(ladder, playerId, guard) do
		table.insert(riderIds, companionId)
	end
	local duration = math.max(config.rideSeconds, 0.1)
	local arrival = config.arrival
	local timeline = DescentElevatorRules.timeline(
		now,
		duration,
		arrival.exitGraceSeconds,
		arrival.pushSeconds,
		config.cageReturnSeconds,
		arrival.maxHoldSeconds
	)
	local protectionSeconds = timeline.returnsAt - now + math.max(arrival.threatGraceSeconds, 0)
	for _, boardingId in riderIds do
		PlayerState.protectFromThreats(boardingId, protectionSeconds)
	end

	-- Put the riders ON the cage. The prompt can be triggered from anywhere inside its range, and a
	-- ride that left with the player standing beside the shaft would be the same disembodied
	-- teleport this fixture exists to replace.
	local boardedAt: { [Types.PlayerId]: Vector3 } = {}
	for index, boardingId in riderIds do
		local seat = riderSlot(ladder, index, #riderIds)
		boardedAt[boardingId] = seat
		CharacterService.teleport(boardingId, seat)
		MovementSanityService.markAuthorized(boardingId, seat)
		local boardingState = PlayerState.get(boardingId)
		if boardingState ~= nil then
			boardingState.position = seat
		end
		CharacterService.setRunBodyRideControlled(boardingId, true)
	end

	ladder.prompt.Enabled = false
	setGate(ladder, true)
	-- THE HATCH IS NOT THROWN HERE. It folds shut on the server, so every client sees the mouth
	-- covered at one instant rather than each deciding for itself — the same argument ElevatorService
	-- makes for closing its gate server-side, plus one this fixture has that the lobby does not: an
	-- uncovered shaft in a walkable room is a hole a teammate falls into. What it cannot do is close
	-- NOW: the cage is still parked in the mouth at this instant, its deck level with the room floor,
	-- so a hatch shut on departure lies across the cage and the ride hauls the riders down through it.
	-- The tick throws it at `hatchClosesAt`, once the cage has fallen clear. Until then the deck itself
	-- is what caps the mouth, which is the job it already had while parked.

	ladder.busyUntil = timeline.parksAt
	rides[ladder.depth] = {
		riderIds = riderIds,
		boardedAt = boardedAt,
		depth = ladder.depth,
		startedAt = now,
		endsAt = now + duration,
		timeline = timeline,
		hatchClosesAt = DescentElevatorRules.hatchClosesAt(
			now,
			duration,
			ladder.built.hatchClearanceStuds,
			ladder.built.rideDistance
		),
		-- Rewritten from the return leg's own start; the cage is not going back up yet.
		hatchOpensAt = math.huge,
		hatchShut = false,
		phase = "Descending",
		disembarked = {},
		resolved = false,
	}

	Remotes.get("RunEvent"):FireAllClients("descentRide", {
		cage = ladder.built.cage,
		riderIds = riderIds,
		depth = ladder.depth,
		startedAt = now,
		duration = duration,
		distance = ladder.built.rideDistance,
		restPivot = ladder.built.cageRestPivot,
	})
	Telemetry.event("descent_ride_started", playerId, { depth = ladder.depth, riders = #riderIds })
end

-- Everything the cage has to put back whether the ride ended well or badly. A rider who died, left,
-- or had their body replaced mid-descent simply is not moved; the machine still resets.
local function resolveRide(ladder: Ladder, ride: Ride)
	ride.resolved = true
	ride.phase = "Arrived"
	local built = ladder.built
	-- The authoritative bottom pose. Clients rendered the descent locally against an unchanged
	-- server transform, so this is the write that makes their local view and the server agree before
	-- the cage is sent home.
	built.cage:PivotTo(built.cageBottomPivot)

	-- EACH RIDER IS RESOLVED ON THEIR OWN, and that is the whole of what sharing a cage means. They
	-- travelled together and they are asked separately: one of them dying, being snuffed or leaving
	-- during the four seconds refuses only their own arrival, and their companion still lands. The
	-- orchestrator hands each of them a distinct entry point on the floor below (`entryForRunner`),
	-- so two simultaneous arrivals never share a square.
	local completion = onArrive
	local movedCount = 0
	for index, riderId in ride.riderIds do
		local landing = riderSlot(ladder, index, #ride.riderIds) - Vector3.new(0, built.rideDistance, 0)
		local moved = completion ~= nil and completion(riderId, ride.depth, landing)
		CharacterService.setRunBodyRideControlled(riderId, false)
		if moved then
			movedCount += 1
		elseif PlayerState.get(riderId) ~= nil then
			-- The ride happened and the descent did not. Put them back where they boarded rather than
			-- leaving them standing on a cage that is about to be hauled up through them.
			local seat = ride.boardedAt[riderId] or built.riderPosition
			CharacterService.teleport(riderId, seat)
			MovementSanityService.markAuthorized(riderId, seat)
			PlayerState.clearThreatProtection(riderId)
		end
	end
	setGate(ladder, false)
	Telemetry.event("descent_ride_arrived", nil, {
		depth = ride.depth,
		riders = #ride.riderIds,
		moved = movedCount,
	})
end

local function onLowerDeck(ladder: Ladder, position: Vector3): boolean
	local config = Config.DescentLadder
	return DescentElevatorRules.isOnDeck(
		ladder.built.cageBottomPivot,
		position,
		config.cageWidth,
		config.cageDepth,
		config.arrival.deckVerticalTolerance
	)
end

local function placeOutside(ladder: Ladder, playerId: Types.PlayerId, state: Types.PlayerRunState, lateral: number)
	local config = Config.DescentLadder
	-- `cageBottomPivot` is at the deck part's centre. Raise the exit origin to the walkable top so
	-- the collision fallback cannot seat a candle fractionally inside the entry-room floor.
	local exitPivot = ladder.built.cageBottomPivot * CFrame.new(0, config.deckThickness / 2, 0)
	local exit = DescentElevatorRules.exitPosition(exitPivot, lateral, config.arrival.forcedExitStuds)
	CharacterService.teleport(playerId, exit)
	CharacterService.stopRunBody(playerId)
	MovementSanityService.markAuthorized(playerId, exit)
	state.position = exit
end

-- Returns how many riders are STILL STANDING ON THE DECK once this pass is done, which is what the
-- gate waits on. Someone placed outside during the pass is not counted: they are off by the time the
-- caller reads the number.
local function pushArrivalOccupants(ladder: Ladder, ride: Ride, pushEveryRider: boolean): number
	local direction = DescentElevatorRules.exitDirection(ladder.built.cageBottomPivot)
	local riderSet: { [Types.PlayerId]: boolean } = {}
	for _, riderId in ride.riderIds do
		riderSet[riderId] = true
	end
	local stillAboard = 0
	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished or state.depth ~= ride.depth + 1 then
			continue
		end
		local position = CharacterService.basePosition(playerId)
		if position == nil then
			continue
		end
		local isOnDeck = onLowerDeck(ladder, position)
		if riderSet[playerId] then
			if not isOnDeck then
				ride.disembarked[playerId] = true
			elseif ride.disembarked[playerId] then
				-- Crossing the threshold is one-way for this cycle. Put a rider who deliberately turns
				-- around back on the side they already chose, rather than letting client movement fight a
				-- weak velocity nudge until the gate closes.
				local localPosition = ladder.built.cageBottomPivot:PointToObjectSpace(position)
				local lateral =
					math.clamp(localPosition.X, -Config.DescentLadder.cageWidth / 2, Config.DescentLadder.cageWidth / 2)
				placeOutside(ladder, playerId, state, lateral)
			else
				-- Aboard, and has not crossed the threshold yet. The gate stays open for them, and their
				-- threat protection is topped up for as long as that lasts: the hold can outrun the fixed
				-- window granted at departure, and a rider the machine is deliberately keeping in place is
				-- exactly who must not be attacked while it does.
				stillAboard += 1
				PlayerState.protectFromThreats(playerId, Config.DescentLadder.arrival.threatGraceSeconds)
				if pushEveryRider then
					CharacterService.pushRunBody(playerId, direction, Config.DescentLadder.arrival.pushSpeed)
				end
			end
		elseif isOnDeck then
			-- The lower landing has no call control and is never a waiting room. Somebody who was not on
			-- this ride cannot enter its car from below.
			local localPosition = ladder.built.cageBottomPivot:PointToObjectSpace(position)
			local lateral =
				math.clamp(localPosition.X, -Config.DescentLadder.cageWidth / 2, Config.DescentLadder.cageWidth / 2)
			placeOutside(ladder, playerId, state, lateral)
		end
	end
	return stillAboard
end

local function forceExitAndReturn(ladder: Ladder, ride: Ride, now: number)
	local config = Config.DescentLadder
	local displaced = 0
	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished or state.depth ~= ride.depth + 1 then
			continue
		end
		local position = CharacterService.basePosition(playerId)
		if position == nil or not onLowerDeck(ladder, position) then
			continue
		end
		displaced += 1
		local riderIndex = table.find(ride.riderIds, playerId)
		local lateral = if riderIndex ~= nil
			then ((riderIndex - 1) - (#ride.riderIds - 1) / 2) * config.riderSpacingStuds * 2
			else (displaced - 1) * config.riderSpacingStuds
		placeOutside(ladder, playerId, state, lateral)
	end

	setGate(ladder, true)
	ride.phase = "Returning"
	local returnDuration = math.max(config.cageReturnSeconds, 0.1)
	ride.timeline.parksAt = now + returnDuration
	ladder.busyUntil = ride.timeline.parksAt
	-- The same crossing as the descent, run backwards: the cage rises into a mouth the hatch is still
	-- covering, so the cover is pulled before the cage reaches it rather than at the end of the leg.
	ride.hatchOpensAt = DescentElevatorRules.hatchOpensAt(
		now,
		returnDuration,
		ladder.built.hatchClearanceStuds,
		ladder.built.rideDistance
	)
	Remotes.get("RunEvent"):FireAllClients("descentReturn", {
		cage = ladder.built.cage,
		depth = ladder.depth,
		startedAt = now,
		duration = returnDuration,
		distance = ladder.built.rideDistance,
		restPivot = ladder.built.cageRestPivot,
	})
	Telemetry.event("descent_cage_returning", nil, { depth = ride.depth, forcedExits = displaced })
end

function DescentLadderService.registerFloor(depth: number, runtime: { built: DescentLadder.BuiltLadder })
	local built = runtime.built
	local config = Config.DescentLadder

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DescentLadderPrompt"
	prompt.ActionText = "Ride down"
	prompt.ObjectText = "Descent Elevator"
	prompt.HoldDuration = config.promptHoldSeconds
	prompt.MaxActivationDistance = config.promptRange
	-- Matches every other diegetic prompt in the game: the cage is a lattice of thin bars and a
	-- line-of-sight test against it fails from most of the angles a player actually approaches from.
	prompt.RequiresLineOfSight = false
	prompt.Parent = built.promptAnchor

	local ladder: Ladder = {
		depth = depth,
		built = built,
		prompt = prompt,
		busyUntil = 0,
	}
	prompt.Triggered:Connect(function(player: Player)
		beginRide(player, ladder)
	end)
	ladders[depth] = ladder
	parkCage(ladder)
end

function DescentLadderService.init(guard: DescentGuard, completion: DescentCompletion)
	canDescend = guard
	onArrive = completion
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, ride in rides do
			local seat = table.find(ride.riderIds, player.UserId)
			if seat == nil then
				continue
			end
			-- One of two riders leaving is not the ride ending: drop them from the manifest and let the
			-- cage carry whoever is left. Only an EMPTY cage is settled early, which is the case the
			-- original single-rider handler was written for.
			table.remove(ride.riderIds, seat)
			ride.boardedAt[player.UserId] = nil
		end
	end)
end

function DescentLadderService.tick()
	local now = Workspace:GetServerTimeNow()
	for depth, ride in rides do
		local ladder = ladders[depth]
		if ladder == nil then
			-- The floor retired underneath a ride. The rider is either gone or has already been moved
			-- on by the orchestrator; there is no machine left to reset.
			rides[depth] = nil
			continue
		end
		-- The mouth is covered the moment the cage is out of it, and uncovered again just before the
		-- cage comes back through. Both are read off the ride curve rather than off the leg's end, so
		-- the hatch is never drawn across the cage or the riders standing in it.
		if not ride.hatchShut and ride.phase == "Descending" and now >= ride.hatchClosesAt then
			setHatch(ladder, true)
			ride.hatchShut = true
		elseif ride.hatchShut and ride.phase == "Returning" and now >= ride.hatchOpensAt then
			setHatch(ladder, false)
			ride.hatchShut = false
		end
		if ride.phase == "Descending" and now >= ride.endsAt then
			resolveRide(ladder, ride)
		end
		if ride.phase == "Arrived" then
			pushArrivalOccupants(ladder, ride, false)
			if now >= ride.timeline.pushesAt then
				ride.phase = "Pushing"
			end
		elseif ride.phase == "Pushing" then
			local stillAboard = pushArrivalOccupants(ladder, ride, true)
			-- THE GATE WAITS FOR THE DECK, NOT FOR THE CLOCK. `returnsAt` used to close it outright, which
			-- gave an arrival a flat 3.5 seconds from landing to be clear — long enough on paper and not
			-- long enough in the cage, because a rider who is a step from the threshold when it expires
			-- has the leaves slide shut straight through them on their way out. Holding while anyone is
			-- still aboard means the gate is never the thing a player walks through.
			if now >= ride.timeline.returnsAt and (stillAboard == 0 or now >= ride.timeline.holdsUntil) then
				forceExitAndReturn(ladder, ride, now)
			end
		end
		if ride.phase == "Returning" and now >= ride.timeline.parksAt then
			rides[depth] = nil
			parkCage(ladder)
		end
	end
end

-- A FLOOR CANNOT RETIRE OUT FROM UNDER A RIDE, and nothing here has to arrange that: a rider keeps
-- `state.depth` on the floor they set off from until the cage lands, and the orchestrator's
-- retirement protection is measured from exactly that. The window closes itself.
function DescentLadderService.clearDepth(depth: number)
	-- Prompts and cages die with the floor model; only this service's own bookkeeping is cleared.
	ladders[depth] = nil
	rides[depth] = nil
end

function DescentLadderService.reset()
	-- Release anyone the cage still had hold of BEFORE the bookkeeping goes. A restart replaces every
	-- body anyway, but a run that ended while somebody was mid-ride must not be able to leave an
	-- server-owned ride body behind for whatever spawns next.
	for _, ride in rides do
		if not ride.resolved then
			for _, riderId in ride.riderIds do
				CharacterService.setRunBodyRideControlled(riderId, false)
			end
		end
	end
	table.clear(ladders)
	table.clear(rides)
end

return DescentLadderService

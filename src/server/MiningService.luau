--!strict
-- Server authority for the Raw Wax mining slice. Owns every deposit's progress and depletion, the
-- working stance, the movement lock, and the reward.
--
-- THE INTERACTION, as this file enforces it: a click near a seam ENGAGES it — the player plants, the
-- pickaxe comes up, and a marker starts sweeping a ring on a loop. Every further click is a STRIKE
-- scored against wherever the marker is at that instant. Strike, recover, the band moves, strike
-- again. The stance ends when the player asks it to, when they try to move, when the seam breaks, or
-- when the world stops allowing it.
--
-- WHY THE CLIENT CANNOT CLAIM AN OUTCOME: it sends no accuracy or phase. A strike may include the
-- shared-clock instant of the click, but Logic/MiningRules accepts it only near server arrival.
-- The server owns the sweep, band, validation, cooldown and progress; invalid or implausible
-- timestamps score at arrival.
--
-- WHY THE BAND MOVES: with a ring that never stops sweeping, a fixed target would make mining a
-- metronome. The band's centre is re-derived per strike from the deposit's id and the strike index
-- (`MiningRules.bandCenter`) and sent along for display, so every strike is a fresh read.
--
-- WHY THE PICKAXE CANNOT BECOME A WEAPON: nothing in this file references a threat, and a strike's
-- only outputs are deposit progress and a NoiseService emit. There is no code path from swinging to
-- anything with health, because nothing in the game has health.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local MiningRules = require(ReplicatedStorage.Shared.Logic.MiningRules)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local MiningVisualProtocol = require(ReplicatedStorage.Shared.MiningVisualProtocol)
local WaxDeposit = require(ReplicatedStorage.Shared.NewModelsAndObjects.WaxDeposit)
local PlayerState = require(script.Parent.PlayerState)
local MovementService = require(script.Parent.MovementService)
local NoiseService = require(script.Parent.NoiseService)
local ExtractionService = require(script.Parent.ExtractionService)
local RequestGuard = require(script.Parent.RequestGuard)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local Telemetry = require(script.Parent.Telemetry)

local MiningService = {}

type RoomGroundSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
}

type Deposit = {
	built: WaxDeposit.BuiltDeposit,
	state: Types.DepositState,
}

-- One player's locked working stance. At most one at a time, per player.
type Session = {
	deposit: Deposit,
	-- os.clock() the CURRENT sweep began, as measured by the SERVER. Advances past each strike's
	-- recovery so the ring restarts on the beat rather than mid-pass.
	sweepStartedAt: number,
	-- How many strikes have landed in this stance. Drives the band's wander.
	strikeIndex: number,
	bandCenter: number,
	-- os.clock() of the last thing this player actually did, for the idle release.
	lastActivityAt: number,
}

local deposits: { [BasePart]: Deposit } = {}
local depositList: { Deposit } = {}
-- Stable per-run deposit identity. The cargo grant is deduplicated against this rather than against
-- a Instance reference, so the latch survives anything that could hand out the same part twice.
local nextDepositId = 1
-- At most one stance per player. A repeated `engage` replays this session without restarting it,
-- while an attempt to engage another seam cannot replace or queue behind the active one.
local sessions: { [Types.PlayerId]: Session } = {}
local nextStrikeAt: { [Types.PlayerId]: number } = {}

local function publish(deposit: Deposit)
	WaxDeposit.applyProgress(deposit.built, deposit.state.progress)
	local root = deposit.built.root
	root:SetAttribute(MiningVisualProtocol.attributes.progress, deposit.state.progress)
	root:SetAttribute(MiningVisualProtocol.attributes.depleted, deposit.state.depleted)
end

local function sendState(player: Player, kind: MiningVisualProtocol.MineStateKind, payload: { [string]: unknown })
	Remotes.get("MineState"):FireClient(player, kind, payload)
end

-- Server-derived sight from the player's real run body to the real seam. Player characters are
-- excluded so a teammate crossing the line cannot cancel somebody else's stance; cave geometry is
-- the obstruction this rule is meant to enforce.
local function hasLineOfSight(state: Types.PlayerRunState, deposit: Deposit): boolean
	if not Config.Mining.deposit.requiresLineOfSight then
		return true
	end

	local player = Players:GetPlayerByUserId(state.playerId)
	local character = if player ~= nil then player.Character else nil
	local originPart = if character ~= nil then character.PrimaryPart else nil
	if originPart == nil or deposit.built.model.Parent == nil then
		return false
	end

	local direction = deposit.built.root.Position - originPart.Position
	if direction.Magnitude <= 0 then
		return true
	end

	local exclude: { Instance } = {}
	for _, otherPlayer in Players:GetPlayers() do
		local otherCharacter = otherPlayer.Character
		if otherCharacter ~= nil then
			table.insert(exclude, otherCharacter)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	params.RespectCanCollide = false
	local result = Workspace:Raycast(originPart.Position, direction, params)
	return result == nil or result.Instance:IsDescendantOf(deposit.built.model)
end

-- Assemble the request the pure rules judge. One place reads live state, so the begin check and the
-- resolve check can never fall out of step with each other.
local function requestFor(
	state: Types.PlayerRunState,
	deposit: Deposit,
	now: number,
	hasOpenSwing: boolean
): MiningRules.StrikeRequest
	return {
		alive = state.alive,
		finished = state.finished,
		snuffed = state.snuffedAt ~= nil,
		isLit = state.isLit,
		isCupping = state.isCupping,
		playerDepth = state.depth,
		depositDepth = deposit.state.depth,
		depositDepleted = deposit.state.depleted,
		distance = (state.position - deposit.state.position).Magnitude,
		hasLineOfSight = hasLineOfSight(state, deposit),
		now = now,
		nextStrikeAt = nextStrikeAt[state.playerId] or 0,
		hasOpenSwing = hasOpenSwing,
		-- The row decides the strike count, the yield and whether this seam demands a bright flame.
		row = MiningRules.resolveRow(deposit.state.rowId),
		burnRate = state.burnRate,
		isFlaring = now < state.flareEndsAt,
	}
end

-- End a stance and hand the player their legs back. Every exit — asking to stop, stepping away,
-- cupping, dying, descending, the seam breaking under someone else — ends here, so the movement
-- lock can never outlive the stance that applied it.
local function endSession(playerId: Types.PlayerId, reason: string)
	if sessions[playerId] == nil then
		return
	end
	sessions[playerId] = nil
	local state = PlayerState.get(playerId)
	if state ~= nil then
		state.isSwinging = false
	end
	MovementService.refresh(playerId)
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		sendState(player, "disengaged", { reason = reason })
	end
end

-- Tell the client where the next sweep starts and where its band sits. Sent on engage and after
-- every strike, in shared `GetServerTimeNow()` space — the same handoff the dripstone warning and
-- the elevator ride use. No ring position is ever replicated; only the two numbers it derives from.
local function sweepPayload(session: Session, now: number): { [string]: unknown }
	return {
		-- Convert the server's own os.clock() stamp into the clock both sides share.
		startedAt = Workspace:GetServerTimeNow() + (session.sweepStartedAt - now),
		bandCenter = session.bandCenter,
		strikeIndex = session.strikeIndex,
		progress = session.deposit.state.progress,
	}
end

local function engage(player: Player, state: Types.PlayerRunState, deposit: Deposit, now: number)
	-- Remote retries and two inputs landing in one frame are the same request. Replay the live
	-- session instead of answering "AlreadySwinging", which would make the client discard a stance
	-- the server still owns and leave the player planted until timeout.
	local existing = sessions[state.playerId]
	if existing ~= nil then
		local payload = sweepPayload(existing, now)
		payload.deposit = existing.deposit.built.root
		sendState(player, "engaged", payload)
		return
	end

	local allowed, denial = MiningRules.canBeginStrike(requestFor(state, deposit, now, sessions[state.playerId] ~= nil))
	if not allowed then
		sendState(player, "disengaged", { reason = denial or "Refused" })
		return
	end

	local session: Session = {
		deposit = deposit,
		-- The first sweep begins the moment the stance is taken; the wind-up inside `sweepPhase` is
		-- what stops the very first strike from being a coin flip.
		sweepStartedAt = now,
		strikeIndex = 0,
		bandCenter = MiningRules.bandCenter(deposit.state.id, 0),
		lastActivityAt = now,
	}
	sessions[state.playerId] = session
	-- The commitment: planted for as long as the stance is held. The flag lives on the run state, so
	-- MovementService still decides speed from state alone rather than gaining a second input.
	state.isSwinging = true
	MovementService.refresh(state.playerId)

	local payload = sweepPayload(session, now)
	payload.deposit = deposit.built.root
	sendState(player, "engaged", payload)
end

local function strike(
	player: Player,
	state: Types.PlayerRunState,
	now: number,
	sharedNow: number,
	reportedSharedTime: number?
)
	local session = sessions[state.playerId]
	if session == nil then
		return
	end
	local deposit = session.deposit

	-- Re-validated at the moment of impact, not only at engagement. A stance taken legally can still
	-- be worth nothing if the world moved underneath it.
	local allowed, denial = MiningRules.canResolveStrike(requestFor(state, deposit, now, true))
	if not allowed then
		endSession(state.playerId, denial or "Refused")
		return
	end
	-- Too soon after the last strike: the pick is still coming back up. Swallowed rather than
	-- punished, so mashing costs a player nothing but their rhythm.
	if now < (nextStrikeAt[state.playerId] or 0) then
		return
	end

	session.lastActivityAt = now
	nextStrikeAt[state.playerId] = now + Config.Mining.deposit.strikeCooldownSeconds

	local row = MiningRules.resolveRow(deposit.state.rowId)
	-- Only scoring uses the bounded client click sample. Cooldowns, state checks, session activity,
	-- progression ownership and the next sweep all remain stamped by authoritative arrival time.
	local scoreClock = MiningRules.resolveInputClock(now, sharedNow, reportedSharedTime)
	local outcome =
		MiningRules.resolveStrike(deposit.state.progress, scoreClock - session.sweepStartedAt, session.bandCenter, row)
	deposit.state.progress = outcome.progress
	deposit.state.strikes += 1
	-- Every landed swing marks this seam as one this player worked. A seam somebody started and
	-- nobody finished is an abandonment, which is worth measuring on its own.
	ExtractionService.noteDepositTouched(state.playerId, deposit.state.id)

	-- THE SHARDS. A perfect strike shatters wax out of the seam and a little of it lands on the player
	-- and stays there. Perfect only: a fumble sprays nothing, so this rewards reading the ring rather
	-- than grinding the rock, and no amount of mashing can farm it.
	--
	-- Routed through WaxAccounting like every other wax mutation, with its own ledger source, so the
	-- run summary can answer "how much of this candle came out of the walls" rather than having a
	-- quiet unattributed gain floating in it. The grant clamps at capacity, so a full candle takes
	-- nothing and the ledger records the clamp rather than inventing wax.
	local shardWax = 0
	if outcome.accuracy == "Perfect" then
		local newWax, applied = WaxAccounting.grant(
			state.wax,
			state.waxLedger,
			Config.Mining.deposit.waxPerPerfectStrike,
			"MiningShardGain"
		)
		state.wax = newWax
		shardWax = applied
	end

	-- The noise lands whatever the swing was worth — a fumble is the loud one. Emitted at the SEAM,
	-- not at the player: what the dark heard is a place, and the player is standing at it.
	NoiseService.emit(outcome.noiseKind, deposit.state.position, state.playerId)
	-- Teammates receive presentation only after this server has accepted and scored the strike. The
	-- striking client already gets its richer MineState response and ignores its own echo.
	Remotes.get("RunEvent"):FireAllClients("mineImpact", {
		deposit = deposit.built.root,
		accuracy = outcome.accuracy,
		depleted = outcome.depleted,
		shardWax = shardWax > 0,
		strikerId = state.playerId,
	})

	-- Advance the rhythm: the next sweep starts when the recovery ends, with a freshly derived band.
	session.strikeIndex += 1
	session.sweepStartedAt = nextStrikeAt[state.playerId]
	session.bandCenter = MiningRules.bandCenter(deposit.state.id, session.strikeIndex)

	local payload = sweepPayload(session, now)
	payload.accuracy = outcome.accuracy
	payload.depleted = outcome.depleted
	-- So the client can pop the shard burst and tick the wax bar on the same frame the strike lands,
	-- rather than waiting for the next authoritative wax replication.
	payload.shardWax = shardWax
	sendState(player, "strikeResolved", payload)

	if not outcome.depleted then
		publish(deposit)
		return
	end

	-- Depletion. Guarded by the flag rather than by progress, so two players who release on the same
	-- frame cannot both be the one who broke it: the second finds `depositDepleted` true above and
	-- is cancelled before reaching here.
	deposit.state.depleted = true
	publish(deposit)
	WaxDeposit.markDepleted(deposit.built)

	-- THE PHASE 6 READOUT. A counter and a depth, on the run state, wiped with the run. Deliberately
	-- not wax, not currency, not persisted, and not part of the brazier formula.
	local globalDepth = PlayerState.globalDepth(state)
	state.depositsMinedThisRun += 1
	table.insert(state.depositsMinedAtDepths, globalDepth)

	-- WHO GETS PAID. The breaker always does. A row with `maxPaidMiners` above one — Twin Seam — also
	-- pays everyone else still IN A STANCE at this seam on the frame it broke.
	--
	-- "Still standing there when it broke" is the whole rule, and it is deliberately not "landed a
	-- strike at some point". Paying past contributors would let one player tag a seam, walk away, and
	-- collect while somebody else did the remaining work — the row's strike count is the same however
	-- many people swing at it, so a drive-by would be paid in full for a fraction of the effort.
	-- Requiring presence at the break makes the co-operation real and the read obvious: be there at
	-- the end.
	--
	-- Ordered breaker-first and then by player id, so which of two simultaneous helpers takes the last
	-- slot is deterministic rather than dependent on hash order.
	local paidIds: { Types.PlayerId } = { state.playerId }
	if row.maxPaidMiners > 1 then
		local helpers: { Types.PlayerId } = {}
		for otherId, other in sessions do
			if otherId ~= state.playerId and other.deposit == deposit then
				table.insert(helpers, otherId)
			end
		end
		table.sort(helpers)
		for _, otherId in helpers do
			if #paidIds >= row.maxPaidMiners then
				break
			end
			table.insert(paidIds, otherId)
		end
	end

	-- Each paid miner gets the row's FULL yield — it is not split. Two miners each doing half the
	-- strikes are each paid in full, which is exactly what makes the row worth buying, and the strike
	-- count staying constant is what stops that from being free money.
	--
	-- ExtractionService latches per (deposit, player), so no second call can pay the same person for
	-- the same seam however this is reached. It is still not wax and still not currency here: it
	-- becomes money only by being carried out through a brazier, priced by THIS depth, stamped now.
	local rawWaxGranted = 0
	for _, paidId in paidIds do
		local granted = ExtractionService.grantForDeposit(paidId, deposit.state.id, globalDepth, row.units)
		if paidId == state.playerId then
			rawWaxGranted = granted
		elseif granted > 0 then
			local helper = Players:GetPlayerByUserId(paidId)
			local helperState = PlayerState.get(paidId)
			if helper ~= nil and helperState ~= nil then
				-- A paid helper mined this seam as much as the breaker did, so their own readout has to
				-- agree. Counted here rather than at the top with the breaker's, because only a miner who
				-- was actually paid worked it to the end.
				helperState.depositsMinedThisRun += 1
				table.insert(helperState.depositsMinedAtDepths, globalDepth)
				-- The helper needs the same confirmation the breaker gets, on the same frame. Without it
				-- their cargo readout would tick up with no visible cause.
				sendState(helper, "depleted", {
					minedThisRun = helperState.depositsMinedThisRun,
					globalDepth = globalDepth,
					rawWaxGranted = granted,
					rawWaxCarried = helperState.rawWax.cargo.total,
					sharedWith = state.playerId,
				})
			end
		end
	end

	sendState(player, "depleted", {
		minedThisRun = state.depositsMinedThisRun,
		globalDepth = globalDepth,
		rawWaxGranted = rawWaxGranted,
		rawWaxCarried = state.rawWax.cargo.total,
		paidMiners = #paidIds,
	})
	Telemetry.event("deposit_mined", state.playerId, {
		globalDepth = globalDepth,
		depth = state.depth,
		strikes = deposit.state.strikes,
		minedThisRun = state.depositsMinedThisRun,
		rawWaxGranted = rawWaxGranted,
		rawWaxCarried = state.rawWax.cargo.total,
	})

	-- Everyone still standing at this seam — the breaker included — is released rather than left
	-- planted at a spent rock.
	for playerId, other in sessions do
		if other.deposit == deposit then
			endSession(playerId, "Depleted")
		end
	end
end

function MiningService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomGroundSurface },
	parent: Instance
)
	for _, placement in plan.deposits do
		local roomCenter = roomCenters[placement.roomIndex]
		local roomSurface = roomSurfaces[placement.roomIndex]
		if roomCenter == nil or roomSurface == nil then
			continue
		end

		local spot = roomCenter + placement.localOffset
		local surfaceY = roomSurface.center.Y
			+ GroundGeometry.offset(
				roomSurface.groundField,
				spot.X - roomSurface.center.X,
				spot.Z - roomSurface.center.Z
			)
		-- The pure field planned the intended surface, but Terrain is voxelized and cave dressing can
		-- occupy that shelf. Resolve the final rest height against the built world, exactly as loot
		-- does, so a deposit never starts buried or floating.
		surfaceY = SurfaceProbe.groundY(surfaceY, spot.X, spot.Z)

		local built = WaxDeposit.build(placement.visualSeed)
		-- Seated by its VISIBLE bottom, not by its root. The root is the rock's centre (every reach
		-- and line-of-sight query wants it there), which is half the boulder's height above its base
		-- — pivoting straight to the ground buried the whole seam and left only a few flecks of wax
		-- showing through the floor. `surfaceEmbed` then sinks it a little on purpose, so the boulder
		-- reads as shouldered into the cave rather than set down on it.
		-- Faces the room, so the seams are on the side a player approaches from.
		SurfaceProbe.seat(
			built.model,
			Vector3.new(spot.X, surfaceY, spot.Z),
			roomCenter,
			-Config.Mining.visual.surfaceEmbed
		)
		built.model.Parent = parent

		local depositId = nextDepositId
		nextDepositId += 1
		local deposit: Deposit = {
			built = built,
			state = {
				id = depositId,
				depth = plan.depth,
				position = built.root.Position,
				progress = 0,
				strikes = 0,
				depleted = false,
				-- Chosen by the planner from the party's unlock union. Resolved through MiningRules on every
				-- read, so a row whose layer is later rolled back degrades to Standard instead of breaking.
				rowId = placement.rowId,
			},
		}
		built.root:SetAttribute(MiningVisualProtocol.attributes.depth, plan.depth)
		built.root:SetAttribute(MiningVisualProtocol.attributes.rowId, placement.rowId)
		publish(deposit)

		deposits[built.root] = deposit
		table.insert(depositList, deposit)
		-- So "deposits reachable on the floors this player got to" is answerable from server state
		-- alone, without ever asking a client what it saw.
		ExtractionService.noteDepositSpawned(plan.depth)
	end
end

function MiningService.init()
	Remotes.get("MineStrike").OnServerEvent:Connect(function(player: Player, action: unknown, target: unknown)
		if not RequestGuard.allow(player, "MineStrike") or typeof(action) ~= "string" then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil then
			return
		end
		local now = os.clock()
		local sharedNow = Workspace:GetServerTimeNow()

		if action == "disengage" then
			endSession(player.UserId, "Cancelled")
			return
		end
		if action == "strike" then
			local reportedSharedTime: number? = nil
			if typeof(target) == "number" then
				reportedSharedTime = target
			end
			strike(player, state, now, sharedNow, reportedSharedTime)
			return
		end
		if action ~= "engage" then
			return
		end

		-- The only place a client-supplied Instance is trusted, and only as a lookup key: an unknown
		-- part is not a deposit, so there is nothing to strike.
		if typeof(target) ~= "Instance" then
			return
		end
		local deposit = deposits[target :: BasePart]
		if deposit == nil then
			return
		end
		engage(player, state, deposit, now)
	end)
end

-- Release stances the world has invalidated: a client that went quiet, and anyone who has been
-- pushed out of range, cupped their flame, changed floor, or died since engaging. Runs every tick so
-- a stuck stance can never hold the movement lock open.
function MiningService.tick()
	if next(sessions) == nil then
		return
	end
	local now = os.clock()
	for playerId, session in sessions do
		local state = PlayerState.get(playerId)
		if state == nil then
			endSession(playerId, "Dead")
			continue
		end
		if MiningRules.swingHasTimedOut(now - session.lastActivityAt) then
			endSession(playerId, "TimedOut")
			continue
		end
		local allowed, denial = MiningRules.canResolveStrike(requestFor(state, session.deposit, now, true))
		if not allowed then
			endSession(playerId, denial or "Refused")
		end
	end
end

function MiningService.clear(playerId: Types.PlayerId)
	-- Straight table clear rather than `endSession`: the player is gone, so there is nobody to tell
	-- and no character left to unlock.
	sessions[playerId] = nil
	nextStrikeAt[playerId] = nil
end

function MiningService.reset()
	for _, deposit in depositList do
		deposit.built.model:Destroy()
	end
	table.clear(depositList)
	table.clear(deposits)
	table.clear(sessions)
	table.clear(nextStrikeAt)
	-- Ids restart with the run, which is exactly the lifetime of the cargo latch that keys off them.
	nextDepositId = 1
end

return MiningService

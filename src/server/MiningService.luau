--!strict
-- Server authority for the Raw Wax mining slice. Owns every deposit's progress and depletion, the
-- working stance, the movement lock, and the reward.
--
-- THE INTERACTION, as this file enforces it: a click near a seam ENGAGES it — the player plants, the
-- pickaxe comes up, and a marker starts sweeping a fracture rail on a loop. Every further click is a STRIKE
-- scored against wherever the marker is at that instant. Strike, recover, the band moves, strike
-- again. The stance ends when the player asks it to, when they try to move, when the seam breaks, or
-- when the world stops allowing it.
--
-- EVERY LANDED STRIKE PAYS. Raw Wax is granted per swing, in whole grams, at the moment the swing is
-- scored (Config/Mining, Logic/MiningRules.gramsForAccuracy) — a fumble pays nothing, and breaking the
-- seam pays nothing extra because there is nothing left to pay. That single change is what makes
-- abandoning a half-worked seam a real option instead of a total loss, and it is what makes a seam
-- with no end (the Explosive row) expressible at all.
--
-- WHY THE CLIENT CANNOT CLAIM AN OUTCOME: it sends no accuracy or phase. A strike may include the
-- shared-clock instant of the click, but Logic/MiningRules accepts it only near server arrival.
-- The server owns the sweep, band, validation, cooldown and progress; invalid or implausible
-- timestamps score at arrival.
--
-- WHY THE BAND MOVES: with a rail sweep that never stops, a fixed target would make mining a
-- metronome. The band's centre is re-derived per strike from the deposit's id and the strike index
-- (`MiningRules.bandCenter`) and sent along for display, so every strike is a fresh read.
--
-- WHY THE PICKAXE STILL CANNOT BECOME A WEAPON, even though this file now knows what a threat is.
-- There is exactly ONE reference to ThreatService below and it is the explosive seam's blast, which
-- SUMMONS — it moves bodies to a place and does nothing else to them. A strike's own outputs remain
-- deposit progress, a gram count and a NoiseService emit. There is still no code path from swinging to
-- anything with health, because nothing in the game has health, and the one thing a player can do here
-- that reaches a threat at all is the thing that brings threats TOWARD them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
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
-- ONE-DIRECTIONAL, and only for the explosive seam's summons. ThreatService knows nothing about
-- mining; this file knows one verb of ThreatService's (`alertAll`) and no more. See the header.
local ThreatService = require(script.Parent.ThreatService)
local WaxService = require(script.Parent.WaxService)

local MiningService = {}

type RoomGroundSurface = SurfaceProbe.RoomGroundSurface

type Deposit = {
	built: WaxDeposit.BuiltDeposit,
	state: Types.DepositState,
	-- The shared-clock stamp of `state.primedAt`, kept beside it rather than in the pure state because
	-- it exists only to be published to clients (MiningVisualProtocol). The server never reasons about
	-- the fuse in this clock — `state.primedAt` is os.clock() and is the only authority on when the
	-- blast lands.
	primedSharedAt: number?,
}

-- One player's locked working stance. At most one at a time, per player.
type Session = {
	deposit: Deposit,
	-- os.clock() the CURRENT sweep began, as measured by the SERVER. Advances past each strike's
	-- recovery so the rail restarts on the beat rather than mid-pass.
	sweepStartedAt: number,
	-- How many strikes have landed in this stance. Drives the band's wander.
	strikeIndex: number,
	bandCenter: number,
	-- Where this stance sits on the tier ladder, and therefore how fast and how tight the sweep the
	-- player is about to read will be (Logic/MiningRules.nextTier).
	--
	-- IT LIVES HERE RATHER THAN ON THE DEPOSIT because it is the player's momentum, not the rock's
	-- condition: two miners in a stance at one Twin Seam climb their own ladders, and a seam somebody
	-- abandoned at tier 3 hands the next person to touch it a tier 1 sweep.
	tier: number,
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
-- The prime roll for explosive seams. Server-side and never seeded from anything the client can see or
-- derive: the floor's layout is deterministic from its seed on purpose, but WHEN a gas pocket lets go
-- must not be, or the row becomes a lookup table and its whole decision evaporates.
local primeRng = Random.new()

local function publish(deposit: Deposit)
	WaxDeposit.applyProgress(deposit.built, deposit.state.progress)
	local root = deposit.built.root
	root:SetAttribute(MiningVisualProtocol.attributes.progress, deposit.state.progress)
	root:SetAttribute(MiningVisualProtocol.attributes.depleted, deposit.state.depleted)
	root:SetAttribute(MiningVisualProtocol.attributes.primedAt, deposit.primedSharedAt or 0)
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
		depositPrimed = deposit.state.primedAt ~= nil,
		distance = (state.position - deposit.state.position).Magnitude,
		hasLineOfSight = hasLineOfSight(state, deposit),
		now = now,
		nextStrikeAt = nextStrikeAt[state.playerId] or 0,
		hasOpenSwing = hasOpenSwing,
		-- The row decides the strike count, the yield and whether this seam demands a bright flame.
		row = MiningRules.resolveRow(deposit.state.rowId),
		burnRate = state.burnRate,
		isFlaring = now < state.flareEndsAt,
		minimumBurnRate = state.modifiers.minBurnRate,
		maximumBurnRate = state.modifiers.maxBurnRate,
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
-- the elevator ride use. No rail position is ever replicated; only the two numbers it derives from.
local function sweepPayload(session: Session, now: number): { [string]: unknown }
	return {
		-- Convert the server's own os.clock() stamp into the clock both sides share.
		startedAt = Workspace:GetServerTimeNow() + (session.sweepStartedAt - now),
		bandCenter = session.bandCenter,
		-- The tier the sweep this payload describes will be read at. Sent for the same reason the band
		-- centre is: the client must be able to draw the rail it is about to be scored against without
		-- inventing either number, and the tier decides the marker's speed and both band widths.
		tier = session.tier,
		strikeIndex = session.strikeIndex,
		progress = session.deposit.state.progress,
	}
end

--------------------------------------------------------------------------------
-- The explosive seam
--------------------------------------------------------------------------------

-- LIGHT THE FUSE. The seam stops being minable on this frame and detonates `fuseSeconds` later, in
-- `tick`. Everyone at the rock is released immediately rather than being left planted in front of a
-- thing that is about to go off — the stance is a movement lock, and holding somebody in place here
-- would be the game killing them with its own UI.
--
-- THE THREE SECONDS ARE NOT A WARNING, THEY ARE THE WHOLE INTERACTION. The player has already been
-- told, by a hiss that has been climbing since their first swing, that this could happen; what the
-- fuse buys is the chance to act on having been told. Shortening it would turn an authored gamble into
-- a coin flip, and lengthening it would make leaving free.
local function prime(deposit: Deposit, now: number, sharedNow: number)
	if deposit.state.primedAt ~= nil or deposit.state.depleted then
		return
	end
	deposit.state.primedAt = now
	deposit.primedSharedAt = sharedNow
	publish(deposit)
	WaxDeposit.applyPrimed(deposit.built)
	for playerId, other in sessions do
		if other.deposit == deposit then
			endSession(playerId, "Primed")
		end
	end
	-- Presentation for everyone who can see or hear it, not only for whoever was swinging: a seam
	-- crackling is the loudest thing that has ever happened to their friends' evening.
	Remotes.get("RunEvent"):FireAllClients("seamPrimed", {
		deposit = deposit.built.root,
		position = deposit.state.position,
		depth = deposit.state.depth,
		primedAt = sharedNow,
	})
end

-- THE BLAST. Everything the explosive seam is for happens in this function, in this order:
--
--   1. the seam is spent — it is the one thing that ends a row which cannot be mined out;
--   2. every candle inside `blastRadius` loses Living Wax, falling off with distance;
--   3. a very loud, slow-decaying noise is left ON the site, so the area stays hostile afterwards;
--   4. EVERY THREAT ON THE FLOOR is summoned to it (see ThreatService.alertAll).
--
-- Step 4 is the row's actual payload and steps 2 and 3 are its punctuation. The wax cost is a bill,
-- not a death: it is what makes standing next to your own explosion a mistake rather than a strategy,
-- and it is deliberately survivable from full so that what kills a greedy player is what arrives
-- afterwards rather than the blast itself.
local function detonate(deposit: Deposit)
	if deposit.state.depleted then
		return
	end
	local explosive = Config.Mining.explosive
	local position = deposit.state.position
	local depth = deposit.state.depth

	deposit.state.depleted = true
	deposit.state.primedAt = nil
	deposit.primedSharedAt = nil
	publish(deposit)
	WaxDeposit.markDepleted(deposit.built)

	local caught = 0
	for playerId, state in PlayerState.all() do
		if state.depth ~= depth or not state.alive or state.finished then
			continue
		end
		local cost = MiningRules.blastWaxCost((state.position - position).Magnitude)
		if cost <= 0 then
			continue
		end
		caught += 1
		-- Through WaxService like every other hit in the game, so the Candle Sleeve protects against it
		-- for free and the ledger records what actually left the candle. A single discrete impact: the
		-- blast happens once, however long the fuse was.
		WaxService.drainExternal(
			playerId,
			cost,
			"SeamBlast" :: Types.WaxSource,
			"The seam went up in your face.",
			{ kind = "Hit", seconds = 0 },
			"SeamBlast"
		)
	end

	NoiseService.emit("SeamExplosion", position, nil)
	local roused = ThreatService.alertAll(depth, position, explosive.alertRadius, explosive.alertSeconds)

	Remotes.get("RunEvent"):FireAllClients("seamExploded", {
		deposit = deposit.built.root,
		position = position,
		depth = depth,
	})
	Telemetry.event("seam_exploded", nil, {
		depth = depth,
		strikes = deposit.state.strikes,
		caught = caught,
		roused = roused,
	})

	-- Belt and braces: `prime` already released everybody, but a stance opened between priming and the
	-- blast would be a stance at a rock that no longer exists.
	for playerId, other in sessions do
		if other.deposit == deposit then
			endSession(playerId, "Depleted")
		end
	end
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
		-- Every stance opens at the bottom of the ladder, whatever this player just did at the last rock.
		-- The streak is a thing you build on one seam, not a rating you carry around the floor.
		tier = 1,
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
	-- Scored at the tier the sweep the player was actually watching was drawn at, which is why the
	-- promotion below happens after this line and not before it.
	local outcome = MiningRules.resolveStrike(
		deposit.state.progress,
		scoreClock - session.sweepStartedAt,
		session.bandCenter,
		row,
		session.tier
	)
	deposit.state.progress = outcome.progress
	deposit.state.strikes += 1
	-- Every landed swing marks this seam as one this player worked. A seam somebody started and
	-- nobody finished is an abandonment, which is worth measuring on its own.
	ExtractionService.noteDepositTouched(state.playerId, deposit.state.id)

	-- THE SHARDS. A perfect strike shatters wax out of the seam and a little of it lands on the player
	-- and stays there. Perfect only: a fumble sprays nothing, so this rewards reading the rail rather
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

	-- THE PAYMENT. Whole Raw Wax grams, decided by the row and this swing's accuracy, stamped with the
	-- depth the seam is on and banked immediately. A fumble reaches here with nothing to give.
	--
	-- WHO GETS PAID. The striker always does. A row with `maxPaidMiners` above one — Twin Seam — pays
	-- everyone else currently IN A STANCE at this seam the same amount for the same swing, which is
	-- what makes two miners at one rock genuinely worth double rather than a way to split one payout.
	-- Eligibility is re-derived per strike from the ordinary resolve rule, so a helper who has moved,
	-- died, cupped, dimmed or lost line of sight since the last swing is simply not paid for this one.
	--
	-- Ordered striker-first and then by player id, so which of two simultaneous helpers takes the last
	-- slot is deterministic rather than dependent on hash order.
	local globalDepth = PlayerState.globalDepth(state)
	local rawWaxGranted = 0
	if outcome.grams > 0 then
		local paidIds: { Types.PlayerId } = { state.playerId }
		if row.maxPaidMiners > 1 then
			local helpers: { Types.PlayerId } = {}
			for otherId, other in sessions do
				if otherId == state.playerId or other.deposit ~= deposit then
					continue
				end
				local otherState = PlayerState.get(otherId)
				if otherState ~= nil and MiningRules.canResolveStrike(requestFor(otherState, deposit, now, true)) then
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

		-- ExtractionService latches per (deposit, player, strike), so no second call can pay the same
		-- person for the same swing however this is reached. It is still not wax and still not currency
		-- here: it becomes money only by being carried out through a brazier, priced by THIS depth.
		for _, paidId in paidIds do
			local granted = ExtractionService.grantForStrike(
				paidId,
				deposit.state.id,
				deposit.state.strikes,
				globalDepth,
				outcome.grams
			)
			if paidId == state.playerId then
				rawWaxGranted = granted
			elseif granted > 0 then
				local helper = Players:GetPlayerByUserId(paidId)
				local helperState = PlayerState.get(paidId)
				if helper ~= nil and helperState ~= nil then
					-- The helper's own cargo readout must tick with a visible cause on the same frame. They
					-- did not swing, so this is deliberately not a `strikeResolved` — their own stance owns
					-- their rail — but it carries the same two cargo numbers.
					sendState(helper, "sharedStrike", {
						deposit = deposit.built.root,
						rawWaxGranted = granted,
						rawWaxCarried = helperState.rawWax.cargo.total,
						sharedWith = state.playerId,
					})
				end
			end
		end
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
	-- ...and at a new place on the ladder. This governs the sweep the player is about to read, never
	-- the one they were just scored on, so a promotion is always a warning of what is coming rather
	-- than a retroactive change to what already happened.
	session.tier = MiningRules.nextTier(session.tier, outcome.accuracy)

	local payload = sweepPayload(session, now)
	payload.accuracy = outcome.accuracy
	payload.depleted = outcome.depleted
	-- So the client can pop the shard burst and tick the wax bar on the same frame the strike lands,
	-- rather than waiting for the next authoritative wax replication.
	payload.shardWax = shardWax
	payload.rawWaxGranted = rawWaxGranted
	payload.rawWaxCarried = state.rawWax.cargo.total
	-- Keep confirmed contact spatial even if the player locally released the stance before this
	-- response arrived and already cleared their mirrored engaged root.
	payload.deposit = deposit.built.root
	sendState(player, "strikeResolved", payload)

	-- THE GAS POCKET'S ROLL. After the payment, so the strike that lights the fuse is still paid for —
	-- the player took that wax out of the wall and it is theirs. Before the depletion branch, because a
	-- never-depleting row can never reach one.
	if MiningRules.neverDepletes(row) and deposit.state.primedAt == nil then
		if MiningRules.rollPrimes(row, deposit.state.strikes, primeRng:NextNumber()) then
			prime(deposit, now, sharedNow)
			return
		end
	end

	if not outcome.depleted then
		publish(deposit)
		return
	end

	-- Depletion. Guarded by the flag rather than by progress, so two players who release on the same
	-- frame cannot both be the one who broke it: the second finds `depositDepleted` true above and
	-- is cancelled before reaching here.
	--
	-- NOTHING IS PAID HERE. Every gram this seam was worth has already been handed out, swing by swing,
	-- so breaking it is the end of an income stream rather than a payout — which is also why there is
	-- no helper branch left: a Twin Seam's second miner was paid on each strike they were present for.
	deposit.state.depleted = true
	publish(deposit)
	WaxDeposit.markDepleted(deposit.built)

	-- THE PHASE 6 READOUT. A counter and a depth, on the run state, wiped with the run. Deliberately
	-- not wax, not currency, not persisted, and not part of the brazier formula. Credited to everyone
	-- still working the rock, because finishing a seam is a thing the group did.
	local finishers: { Types.PlayerId } = {}
	for otherId, other in sessions do
		if other.deposit == deposit then
			table.insert(finishers, otherId)
		end
	end
	table.sort(finishers)
	for _, finisherId in finishers do
		local finisherState = PlayerState.get(finisherId)
		if finisherState == nil then
			continue
		end
		finisherState.depositsMinedThisRun += 1
		table.insert(finisherState.depositsMinedAtDepths, globalDepth)
		local finisher = Players:GetPlayerByUserId(finisherId)
		if finisher ~= nil then
			sendState(finisher, "depleted", {
				minedThisRun = finisherState.depositsMinedThisRun,
				globalDepth = globalDepth,
				rawWaxCarried = finisherState.rawWax.cargo.total,
				sharedWith = if finisherId ~= state.playerId then state.playerId else nil,
				-- MineState and RunEvent are separate ordered streams. Carry the physical break result on
				-- both so whichever reaches a client first presents the same event.
				accuracy = outcome.accuracy,
				shardWax = shardWax > 0,
				deposit = deposit.built.root,
			})
		end
	end

	Telemetry.event("deposit_mined", state.playerId, {
		globalDepth = globalDepth,
		depth = state.depth,
		strikes = deposit.state.strikes,
		minedThisRun = state.depositsMinedThisRun,
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
): (number, number, number, number)
	local builtCount = 0
	local relocatedCount = 0
	local refusedCount = 0
	local supportWarningCount = 0
	for _, placement in plan.deposits do
		local roomCenter = roomCenters[placement.roomIndex]
		local roomSurface = roomSurfaces[placement.roomIndex]
		if roomCenter == nil or roomSurface == nil then
			refusedCount += 1
			warn(
				string.format(
					"[WICK] refused wax deposit on floor %d room %d: missing room surface",
					plan.depth,
					placement.roomIndex
				)
			)
			continue
		end

		-- Preserve the planner's reserved X/Z. A relocation here can collide with loot, another seam,
		-- or the room wall because none of those systems reserved the replacement position.
		local resolved = SurfaceProbe.resolvePlannedPosition(
			roomSurface,
			placement.localOffset,
			Config.Mining.visual.surfaceProbeRadius
		)
		if resolved.failed then
			refusedCount += 1
			warn(
				string.format(
					"[WICK] refused wax deposit on floor %d room %d: planned footprint has no complete Terrain support",
					plan.depth,
					placement.roomIndex
				)
			)
			continue
		end

		local built = WaxDeposit.build(placement.visualSeed)
		-- Seated by its VISIBLE bottom, not by its root. The root is the rock's centre (every reach
		-- and line-of-sight query wants it there), which is half the boulder's height above its base
		-- — pivoting straight to the ground buried the whole seam and left only a few flecks of wax
		-- showing through the floor. What gets buried now is the builder's skirt: the seam-bearing
		-- mass rides above it, so lumpy terrain around the probe point eats stone instead of wax.
		-- Faces the room, so the seams are on the side a player approaches from.
		SurfaceProbe.seat(built.model, resolved.position, roomCenter, built.bottomOffset, resolved.normal)
		local gap = SurfaceProbe.groundGapStuds(built.model)
		if
			gap == nil
			or math.abs(gap - built.bottomOffset) > Config.Floors.geometry.placementProbe.maxSeatedGapStuds
		then
			supportWarningCount += 1
			warn(
				string.format(
					"[WICK] wax deposit support audit on floor %d room %d: gap %s (wanted %.2f)",
					plan.depth,
					placement.roomIndex,
					if gap == nil then "no terrain below" else string.format("%.2f studs", gap),
					built.bottomOffset
				)
			)
		end
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
				primedAt = nil,
			},
			primedSharedAt = nil,
		}
		built.root:SetAttribute(MiningVisualProtocol.attributes.depth, plan.depth)
		built.root:SetAttribute(MiningVisualProtocol.attributes.rowId, placement.rowId)
		-- Dressed for its row before it is ever seen. An explosive seam has to read as wrong from across
		-- the room, or the tell arrives only after the player has already committed to swinging at it.
		WaxDeposit.applyRow(built, MiningRules.resolveRow(placement.rowId))
		publish(deposit)

		deposits[built.root] = deposit
		table.insert(depositList, deposit)
		-- So "deposits reachable on the floors this player got to" is answerable from server state
		-- alone, without ever asking a client what it saw.
		ExtractionService.noteDepositSpawned(plan.depth)
		builtCount += 1
	end
	return builtCount, relocatedCount, refusedCount, supportWarningCount
end

function MiningService.init()
	Remotes.get("MineStrike").OnServerEvent:Connect(function(player: Player, action: unknown, target: unknown)
		if typeof(action) ~= "string" then
			return
		end
		-- Release is idempotent and only removes server state. It must remain available even when a
		-- burst of scored requests has exhausted the shared mining bucket, or movement can stay
		-- locked until the session watchdog expires.
		if action == "disengage" then
			endSession(player.UserId, "Cancelled")
			return
		end
		if not RequestGuard.allow(player, "MineStrike") then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil then
			return
		end
		local now = os.clock()
		local sharedNow = Workspace:GetServerTimeNow()

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
--
-- IT ALSO BURNS THE FUSES. Detonation is checked here rather than scheduled with `task.delay` for one
-- reason that matters: a floor can be retired, or a run torn down, inside those three seconds, and a
-- pending delayed call would then fire against a deposit that no longer exists. A tick scan over the
-- live list cannot outlive the list.
function MiningService.tick()
	local now = os.clock()
	for index = #depositList, 1, -1 do
		local deposit = depositList[index]
		local primedAt = deposit.state.primedAt
		if primedAt ~= nil and MiningRules.fuseProgress(now - primedAt) >= 1 then
			detonate(deposit)
		end
	end

	if next(sessions) == nil then
		return
	end
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

function MiningService.clearDepth(depth: number)
	-- A retirement is only eligible after every connected participant has moved beyond this floor,
	-- but end any stale stance defensively before its deposit disappears so movement can never remain
	-- locked because of lifecycle ordering.
	for playerId, session in sessions do
		if session.deposit.state.depth == depth then
			endSession(playerId, "FloorRetired")
			nextStrikeAt[playerId] = nil
		end
	end
	for index = #depositList, 1, -1 do
		local deposit = depositList[index]
		if deposit.state.depth == depth then
			deposits[deposit.built.root] = nil
			deposit.built.model:Destroy()
			table.remove(depositList, index)
		end
	end
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

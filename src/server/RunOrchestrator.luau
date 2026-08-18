--!strict
-- Expedition state machine: lobby handoff -> countdown -> build -> descend -> all resolved ->
-- reset. Public lobby/teleport ownership lives in PartyLobbyService, not here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local FloorPlanner = require(ReplicatedStorage.Shared.Logic.FloorPlanner)
local BossFloorPlan = require(ReplicatedStorage.Shared.Logic.BossFloorPlan)
local FloorRetentionRules = require(ReplicatedStorage.Shared.Logic.FloorRetentionRules)
local FloorStacking = require(ReplicatedStorage.Shared.Logic.FloorStacking)
local DepthRules = require(ReplicatedStorage.Shared.Logic.DepthRules)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local EntrySpawnRules = require(ReplicatedStorage.Shared.Logic.EntrySpawnRules)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local EnvironmentSetup = require(script.Parent.EnvironmentSetup)
local FloorBuilder = require(script.Parent.FloorBuilder)
local HazardService = require(script.Parent.HazardService)
local DripstoneService = require(script.Parent.DripstoneService)
local ThreatService = require(script.Parent.ThreatService)
local BasinService = require(script.Parent.BasinService)
local BrazierService = require(script.Parent.BrazierService)
local WallLampService = require(script.Parent.WallLampService)
-- One-directional, exactly like PartyLobbyService's start callback: the ladder service never requires
-- this module. It is handed the two descent callbacks at init and knows nothing else about floors.
local DescentLadderService = require(script.Parent.DescentLadderService)
local DripTrailService = require(script.Parent.DripTrailService)
local ToolService = require(script.Parent.ToolService)
local DeathService = require(script.Parent.DeathService)
local SpectatorService = require(script.Parent.SpectatorService)
local WaxService = require(script.Parent.WaxService)
local MovementService = require(script.Parent.MovementService)
local MovementSanityService = require(script.Parent.MovementSanityService)
local LootService = require(script.Parent.LootService)
local DeadCandleService = require(script.Parent.DeadCandleService)
local MiningService = require(script.Parent.MiningService)
local NoiseService = require(script.Parent.NoiseService)
local ContractWatchService = require(script.Parent.ContractWatchService)
local ExtractionService = require(script.Parent.ExtractionService)
local ShopService = require(script.Parent.ShopService)
-- One-directional: PartyLobbyService reaches this module through the start callback wired in
-- init.server, never by requiring it, so this import introduces no cycle.
local PartyLobbyService = require(script.Parent.PartyLobbyService)
local RemainsService = require(script.Parent.RemainsService)
local VineService = require(script.Parent.VineService)
local TripwireService = require(script.Parent.TripwireService)
local DynamiteService = require(script.Parent.DynamiteService)
local MossFireService = require(script.Parent.MossFireService)
local AshamedLurkerService = require(script.Parent.AshamedLurkerService)
local WardenRegistry = require(script.Parent.WardenRegistry)
local EnemyRegistry = require(script.Parent.EnemyRegistry)
local QueenRegistry = require(script.Parent.QueenRegistry)
local EnemyService = require(script.Parent.EnemyService)
local BossEncounterService = require(script.Parent.BossEncounterService)
local StoneWardenService = require(script.Parent.StoneWardenService)
local RequestGuard = require(script.Parent.RequestGuard)
local RunSummaryService = require(script.Parent.RunSummaryService)
local Telemetry = require(script.Parent.Telemetry)

local RunOrchestrator = {}

type Phase = "Waiting" | "Countdown" | "Running" | "Restarting"
type LobbyReturnHandler = () -> ()

local phase: Phase = "Waiting"
local phaseDeadline = 0
local currentTierId = 1
-- Absolute depth the current expedition starts at. Server-authoritative and the only place a run's
-- global depth is anchored: every player's globalDepth is this plus their floor ordinal minus one.
local currentStartDepth = 1
local currentRunSeed = 0
-- Monotonic within this server's lifetime. Only job is to keep two expeditions that start in the same
-- second from deriving the same run id, and therefore the same currency transaction ids.
local runCounter = 0
-- WHICH CAVE THIS EXPEDITION IS, as a stable family id (Config/CaveFamilies). This replaced a pair of
-- loose per-run multipliers: a threat budget and a dripstone budget that could be set independently
-- of each other and of everything else the cave is. A family id resolves all of it consistently, and
-- makes "which cave am I in" one answer rather than several that could drift apart.
local currentFamilyId = Config.CaveFamilies.defaultId
-- THE UNION of every member's owned Lamp Network nodes, resolved once at descent and held for the
-- whole expedition. Read only by the floor planner, and only to decide which deposit rows may appear.
--
-- A UNION RATHER THAN THE LEADER'S OWN SET, because a floor is one shared thing: if it were the
-- leader's, a player who bought Twin Seam would stop finding them the moment somebody else pulled the
-- lever, which is indistinguishable from the purchase not working.
--
-- CAPTURED ONCE, not re-read per floor. Later floors are built on demand, and a player buying a node
-- mid-expedition must not retroactively change what the cave contains — the run has to be the cave
-- everybody descended into.
local currentUnlockedNodes: { [string]: boolean } = {}
local floors: { [number]: FloorBuilder.FloorRuntime } = {}
local floorPlans: { [number]: Types.FloorPlan } = {}
-- FLOORS THAT ARE OWED BUT NOT YET CARVED, nearest first. Everything past the floor a runner is
-- actually standing on goes through here rather than being built inline, because a floor build is
-- long enough to be felt: two of them back to back is the whole reason the descent used to sit on a
-- loading screen. Drained one serialized floor at a time (see `tick`), which spreads the cost across the
-- seconds a party spends walking their first room instead of stacking it before they have a body.
local pendingFloors: { number } = {}
-- `FloorBuilder.build` crosses one Heartbeat after its Terrain writes so collision queries can see the
-- committed voxels. Heartbeat callbacks are re-entrant across a yield, so this guard keeps a second
-- orchestrator tick, descent callback, or lookahead build from observing a half-built floor.
local floorBuildInProgress = false
-- How many floors this frame has already carved. Reset at the top of every tick; read only to stop
-- the queue drain from landing on the same frame as an on-demand build.
local floorsCarvedThisTick = 0
-- Next time the retirement sweep is allowed to look at the floor table. Retirement is throttled
-- rather than run every frame because a Terrain clear is the expensive half of it.
local nextFloorRetirementAt = 0
local floorsFolder: Folder? = nil
local queuedRunners: { [Types.PlayerId]: boolean } = {}
local runners: { [Types.PlayerId]: boolean } = {}
local runnerSlots: { [Types.PlayerId]: number } = {}
local lobbyReturnHandler: LobbyReturnHandler? = nil
local startingRunnerCount = 0

local function broadcast(kind: string, payload: { [string]: unknown })
	Remotes.get("RunEvent"):FireAllClients(kind, payload)
end

-- `seconds` is how long the descent still owes the player before the cave is carved. It is zero for
-- a party arriving by teleport: their elevator car already rode out the full countdown in the lobby
-- server before Roblox moved them, and running a second one here charged the same wait twice — ten
-- seconds of a loading screen where the design asks for five.
local function beginCountdown(seconds: number)
	phase = "Countdown"
	phaseDeadline = os.clock() + seconds
	if seconds > 0 then
		broadcast("countdown", { seconds = seconds, tierId = currentTierId })
	end
end

local function reserveRunnerSlot(playerId: Types.PlayerId): number?
	local existing = runnerSlots[playerId]
	if existing ~= nil then
		return existing
	end
	local occupied: { [number]: boolean } = {}
	for _, slot in runnerSlots do
		occupied[slot] = true
	end
	for slot = 1, Config.Run.partyCap do
		if not occupied[slot] then
			runnerSlots[playerId] = slot
			return slot
		end
	end
	return nil
end

local function entryForRunner(playerId: Types.PlayerId, entryCenter: Vector3): Vector3?
	local slot = reserveRunnerSlot(playerId)
	return if slot ~= nil then EntrySpawnRules.positionForSlot(entryCenter, slot) else nil
end

local function spawnRunner(player: Player, entryCenter: Vector3)
	local entry = entryForRunner(player.UserId, entryCenter)
	if entry == nil then
		return
	end
	runners[player.UserId] = true
	-- The contract comes from the run's own snapshot (taken in ExtractionService.beginRun, which has
	-- already run by the time anyone spawns), never from the live profile.
	PlayerState.reset(
		player.UserId,
		startingRunnerCount == 1,
		currentStartDepth,
		ExtractionService.contractFor(player.UserId)
	)
	-- Elevator doors open directly into the cave: CharacterService.spawn always clears any lobby
	-- candle first (see its own despawnLobby call), so the run rig replaces it cleanly.
	CharacterService.spawn(player, entry)
	MovementService.refresh(player.UserId)
	MovementSanityService.markAuthorized(player.UserId, entry)
	-- `familyId` is the canonical persisted cave id and `tierId` its legacy numeric projection. Both
	-- travel because they answer different questions: the elevator and the shop speak tier ids, while
	-- anything asking "what is this cave LIKE" (client/AmbientCaveDirector) wants the family and should
	-- not have to translate. Every "floor" message carries both, including the rejoin paths below.
	Remotes.get("RunEvent"):FireClient(player, "floor", {
		depth = 1,
		globalDepth = DepthRules.getGlobalDepth(currentStartDepth, 1),
		tierId = currentTierId,
		familyId = currentFamilyId,
	})
end

local function buildFloorNow(localFloor: number): FloorBuilder.FloorRuntime?
	local existing = floors[localFloor]
	if existing ~= nil then
		return existing
	end
	local folder = floorsFolder
	if folder == nil then
		return nil
	end
	local globalDepth = DepthRules.getGlobalDepth(currentStartDepth, localFloor)
	local worldOrigin = Vector3.zero
	if localFloor > 1 then
		local previousPlan = floorPlans[localFloor - 1]
		if previousPlan == nil then
			return nil
		end
		worldOrigin = FloorStacking.nextFloorOrigin(previousPlan, Config.Floors.geometry.cellSize)
	end
	-- Before a single voxel is carved: this floor sits `FloorBuilder.baseY` studs down, and the engine
	-- destroys unanchored parts below its own fallen-parts plane. Reserving the depth first means no
	-- body can ever be standing on a floor the engine has already decided is out of the world.
	EnvironmentSetup.reserveDepth(FloorBuilder.baseY(localFloor))
	floorsCarvedThisTick += 1
	local planStartedAt = os.clock()
	Telemetry.loadingStage("planning_floor")
	-- THE GRUB QUEEN'S FLOOR IS AUTHORED, NOT ROLLED (Logic/BossFloorPlan). Every ten to fifteen
	-- floors the generator steps aside entirely and a hand-built plus of five rooms is substituted —
	-- same builder, same carving, same everything downstream, but a shape the encounter can rely on.
	--
	-- Decided from the EXPEDITION seed rather than the floor seed, for the same reason the dynamite
	-- schedule is: the interval is a promise across floors, and floors are planned independently and
	-- out of order, so it cannot come from a per-floor stream.
	local isBossFloor = BossFloorPlan.isBossDepth(globalDepth, currentRunSeed)
	local plan = if isBossFloor
		then BossFloorPlan.plan(globalDepth, localFloor, currentFamilyId, worldOrigin)
		else FloorPlanner.plan({
			globalDepth = globalDepth,
			localFloor = localFloor,
			rng = Random.new(DepthRules.getFloorSeed(currentRunSeed, currentTierId, globalDepth)),
			familyId = currentFamilyId,
			unlockedNodes = currentUnlockedNodes,
			-- The EXPEDITION's seed, not this floor's. Dynamite supply is a promise across floors ("a
			-- stick every one to three"), and floors are planned independently and out of order, so
			-- that schedule cannot be derived from a per-floor stream. See
			-- Logic/DynamiteRules.supplyForDepth.
			runSeed = currentRunSeed,
			worldOrigin = worldOrigin,
		})
	local carveStartedAt = os.clock()
	Telemetry.loadingStage("carving_floor")
	local runtime = FloorBuilder.build(plan)
	local populateStartedAt = os.clock()
	Telemetry.loadingStage("populating_floor")
	runtime.model.Parent = folder
	floors[plan.depth] = runtime
	floorPlans[plan.depth] = plan
	HazardService.registerFloor(plan.depth, runtime.waterRegions)
	DripstoneService.registerFloor(plan.depth, runtime.dripstones)
	VineService.registerFloor(plan.depth, runtime.vines)
	DynamiteService.registerFloor(plan.depth, runtime.blastDoors)
	MossFireService.registerFloor(plan.depth, runtime.mossFire)
	AshamedLurkerService.registerFloor(plan.depth, runtime.lurkers)
	-- POPULATION IS ISOLATED PER STEP. Each of these seats a different, independent kind of content onto
	-- a floor that is already carved, parented and live. Before this they ran as one straight-line
	-- sequence, so the FIRST error took every later step with it — and silently, because the audit
	-- below is itself one of the things that got skipped. That is exactly how a single nil config field
	-- inside a deposit's builder came to read as "wax does not exist in this game": threats and loot had
	-- already been seated, so the floor looked populated, while seams, remains, the Basin and the
	-- Brazier were all quietly gone and no line was ever logged saying so.
	--
	-- A step that fails now loses only its own content, and says so loudly in the server log.
	local function populate(label: string, step: () -> ())
		Telemetry.loadingStage("populating_" .. label)
		local ok, err = pcall(step)
		if ok then
			return
		end
		warn(string.format("[WICK] floor %d: population step %q failed: %s", plan.depth, label, tostring(err)))
		Telemetry.event("floor_populate_failed", nil, {
			depth = plan.depth,
			globalDepth = plan.globalDepth,
			step = label,
			err = tostring(err),
		})
	end

	local builtThreats = 0
	populate("threats", function()
		builtThreats = ThreatService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces)
	end)
	-- THE WICK-PACK BODIES, planned alongside the ordinary roster and built immediately after it.
	--
	-- Inside `populate` like every other content pass, which is what guarantees a creature that fails
	-- to seat cannot take the floor down with it: the wrapper catches, records the step and lets the
	-- rest of the floor finish. A cave missing one Longarm is a worse cave; a cave that failed to
	-- build is a lost run.
	local builtEnemies = 0
	populate("enemies", function()
		builtEnemies = EnemyService.spawnFloor(plan, runtime.roomCenters)
	end)
	-- THE BOSS ENCOUNTER, after the ordinary content passes so its Queen and guards are placed onto a
	-- floor that is otherwise finished. A no-op on every floor that is not hers.
	if isBossFloor then
		populate("boss", function()
			BossEncounterService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces)
		end)
	end
	local builtLoot, relocatedLoot, refusedLoot, supportWarningsLoot = 0, 0, 0, 0
	populate("loot", function()
		builtLoot, relocatedLoot, refusedLoot, supportWarningsLoot =
			LootService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	end)
	local builtWarden, relocatedWarden, refusedWarden = false, false, false
	populate("warden", function()
		builtWarden, relocatedWarden, refusedWarden =
			StoneWardenService.spawnFloor(plan, runtime.roomSurfaces, runtime.model)
	end)
	local builtDeposits, relocatedDeposits, refusedDeposits, supportWarningsDeposits = 0, 0, 0, 0
	populate("deposits", function()
		builtDeposits, relocatedDeposits, refusedDeposits, supportWarningsDeposits =
			MiningService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	end)
	-- Scenery, and deliberately its own step: the dead candle's loot and flies were seated by the two
	-- steps above from the same plan, so losing the prop costs a story beat and never the encounter.
	local builtDeadCandle = false
	populate("dead_candle", function()
		builtDeadCandle = DeadCandleService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	end)
	populate("remains", function()
		RemainsService.spawnFloor(plan, runtime.roomCenters, runtime.roomSurfaces, runtime.model)
	end)
	populate("basin", function()
		BasinService.registerFloor(plan.depth, runtime.basinPosition, runtime.model)
	end)
	populate("brazier", function()
		BrazierService.registerFloor(plan.depth, runtime.brazier)
	end)
	populate("wall_lamps", function()
		WallLampService.registerFloor(plan.depth, runtime.lamps)
	end)
	populate("ladder", function()
		DescentLadderService.registerFloor(plan.depth, runtime.ladder)
	end)
	local finishedAt = os.clock()
	Telemetry.event("floor_spawn_audit", nil, {
		depth = plan.depth,
		globalDepth = plan.globalDepth,
		family = plan.familyId,
		-- WHERE A FLOOR'S TIME ACTUALLY GOES, in milliseconds, split at the three boundaries that have
		-- different fixes: planning is pure Luau, carving is Terrain plus every dressing part, and
		-- populating is the gameplay services seating threats, loot, seams and remains on the built
		-- surface. A descent that feels slow is one of these three and the audit line says which.
		planMs = math.round((carveStartedAt - planStartedAt) * 1000),
		carveMs = math.round((populateStartedAt - carveStartedAt) * 1000),
		populateMs = math.round((finishedAt - populateStartedAt) * 1000),
		totalMs = math.round((finishedAt - planStartedAt) * 1000),
		-- Shape diagnostics: how many ordinary rooms took a non-rectangular footprint, and how often
		-- the shape roll had to be refused or abandoned. A rising fallback count is the signal that a
		-- family's shape parameters have drifted out of what the cell can actually contain.
		shapedRooms = plan.diagnostics.shapedRooms,
		shapeFallbacks = plan.diagnostics.shapeFallbacks,
		shapeRejections = plan.diagnostics.shapeRejections,
		plannedThreats = #plan.threatSpawns,
		builtThreats = builtThreats,
		-- `plannedEnemies` counts PLACEMENTS and `builtEnemies` counts BODIES, so the two legitimately
		-- disagree: one planned WaxGrub placement is a brood anchor that becomes two to five grubs.
		-- A built count that is LOWER than planned is the signal worth watching — it means bodies were
		-- refused for want of measured Terrain under their planned offsets.
		plannedEnemies = #plan.enemySpawns,
		builtEnemies = builtEnemies,
		plannedLoot = #plan.lootSpawns,
		builtLoot = builtLoot,
		relocatedLoot = relocatedLoot,
		-- `planned = built + refused` for both reward categories. The independent visible-bounds check is
		-- approximate on asymmetric art, so it remains a warning rather than silently deleting content.
		refusedLoot = refusedLoot,
		supportWarningsLoot = supportWarningsLoot,
		unaccountedLoot = #plan.lootSpawns - builtLoot - refusedLoot,
		plannedDeposits = #plan.deposits,
		builtDeposits = builtDeposits,
		relocatedDeposits = relocatedDeposits,
		refusedDeposits = refusedDeposits,
		supportWarningsDeposits = supportWarningsDeposits,
		unaccountedDeposits = #plan.deposits - builtDeposits - refusedDeposits,
		plannedLurkers = #plan.lurkers,
		builtLurkers = #runtime.lurkers,
		plannedDeadCandle = plan.deadCandle ~= nil,
		builtDeadCandle = builtDeadCandle,
		plannedWarden = plan.warden ~= nil,
		builtWarden = builtWarden,
		relocatedWarden = relocatedWarden,
		refusedWarden = refusedWarden,
	})
	Telemetry.loadingStage("floor_ready")
	return runtime
end

local function buildFloor(localFloor: number): FloorBuilder.FloorRuntime?
	if floorBuildInProgress then
		return nil
	end
	floorBuildInProgress = true
	local result: FloorBuilder.FloorRuntime? = nil
	-- The protected boundary exists to release the re-entrancy guard even if planning, carving, or one
	-- population step raises. Preserve the prior failure contract by rethrowing after the guard clears.
	local ok, buildError = pcall(function()
		result = buildFloorNow(localFloor)
	end)
	floorBuildInProgress = false
	if not ok then
		error(buildError, 0)
	end
	return result
end

-- Owe a floor without paying for it now. Silent about floors that already exist or are already
-- queued, so callers can ask for their lookahead every descent without checking anything first.
local function queueFloor(localFloor: number)
	if floors[localFloor] ~= nil or table.find(pendingFloors, localFloor) ~= nil then
		return
	end
	table.insert(pendingFloors, localFloor)
end

-- Keep `Config.Run.floorLookahead` floors ready counting from the one passed in. The floor itself is
-- never queued — a caller only ever asks for lookahead from ground it already has.
local function ensureLookahead(fromFloor: number)
	for offset = 1, Config.Run.floorLookahead - 1 do
		queueFloor(fromFloor + offset)
	end
end

-- ONE floor at a time, and only one. Building the whole queue together would put the stall back exactly
-- where it was removed from; each build crosses its Terrain-query Heartbeat under the guard above, then
-- returns before the next pending floor may begin.
local function buildOnePendingFloor()
	while #pendingFloors > 0 do
		local nextFloor = table.remove(pendingFloors, 1) :: number
		if floors[nextFloor] == nil then
			buildFloor(nextFloor)
			return
		end
	end
end

-- ADMISSION. Every party member pays their own fee for a paid cave, once, at the moment the cave is
-- built. Owning the cave outright makes the fee zero (Interfaces/CaveTiers), so this is also the only
-- place a permanent unlock has to be honoured.
--
-- Affordability was already validated when the party readied up, so a refusal here means something
-- changed underneath us (a purchase elsewhere, a session that ended). The run still proceeds for the
-- players who did pay: kicking a party out of a cave that is already being carved would be a worse
-- outcome than one player getting a free ride, and the refusal is logged loudly enough to notice.
local function chargeAdmission(tierId: number, memberIds: { Types.PlayerId }, runId: string)
	for _, playerId in memberIds do
		local fee = Interfaces.CaveTiers.entryFeeFor(playerId, tierId)
		if fee <= 0 then
			continue
		end
		local result = Interfaces.CaveTiers.chargeEntry(playerId, tierId, string.format("%s:entry:%d", runId, playerId))
		if not result.ok then
			warn(
				string.format(
					"[WICK] Admission to tier %d could not be charged to user %d (%s); they descend unbilled.",
					tierId,
					playerId,
					tostring(result.failure)
				)
			)
		end
		Telemetry.event("cave_admission", playerId, {
			runId = runId,
			tier = tierId,
			fee = fee,
			ok = result.ok,
			balance = result.balance,
		})
	end
end

-- Record on each profile that this player is mid-run, and where. Read on join by RejoinService to
-- decide whether to send them back into the expedition they dropped from rather than leaving them in
-- a fresh public lobby with their bag lying on a floor they can no longer reach.
local function markPlayersInRun(memberIds: { Types.PlayerId }, runId: string)
	local accessCode = PartyLobbyService.reservedAccessCode()
	if accessCode == nil then
		-- A run started outside a reserved server (Studio, or a local start). There is nowhere to send
		-- a dropped player back TO, so no pointer is written — a marker without a valid access code
		-- would only ever produce failed teleports.
		return
	end
	for _, playerId in memberIds do
		local profile = Interfaces.Persistence.get(playerId)
		profile.activeRunServer = game.PrivateServerId
		profile.activeRunAccessCode = accessCode
		profile.activeRunId = runId
		profile.activeRunStartedAt = os.time()
		Interfaces.Persistence.save(playerId, profile)
	end
end

-- Clear that marker. Called for every player as the expedition resolves, so a finished run never
-- pulls a returning player back into a cave that no longer exists.
local function clearRunMarker(playerId: Types.PlayerId)
	local profile = Interfaces.Persistence.get(playerId)
	if profile.activeRunId == nil then
		return
	end
	profile.activeRunServer = nil
	profile.activeRunId = nil
	profile.activeRunStartedAt = nil
	Interfaces.Persistence.save(playerId, profile)
end

local function startRun()
	local tier = Interfaces.CaveTiers.get(currentTierId) or Interfaces.CaveTiers.list()[1]
	currentStartDepth = tier.startDepth
	if not DepthRules.isSupportedDepth(currentStartDepth) then
		Telemetry.event("run_start_rejected", nil, { tier = tier.id, startDepth = currentStartDepth })
		phase = "Waiting"
		return
	end
	-- THE ONE PLACE A RUN LEARNS WHICH CAVE IT IS. Every floor this expedition builds is planned from
	-- this family id and nothing else; the difficulty, topology, ecology and ore curves are all
	-- resolved from it inside the planner (Logic/CaveFamilyRules), never recomputed out here.
	currentFamilyId = tier.familyId
	phase = "Running"
	BrazierService.setCaveTier(tier.id)
	WaxService.setCaveTier(tier.id)
	-- Anything a family needs chosen ONCE per expedition rather than once per floor — a skybox, a
	-- global particle emitter, an ambience bed — belongs at this call site, because the family is in
	-- scope here and nowhere downstream. Per-FLOOR flavour belongs in FloorBuilder's resolved palette.
	EnvironmentSetup.applyCaveFamily(currentFamilyId)

	-- Floors are drawn as smooth Terrain (which lives outside the floor model), so clear any left
	-- over the cave before carving the new one.
	workspace.Terrain:Clear()

	local folder = Instance.new("Folder")
	folder.Name = "WickFloors"
	folder.Parent = workspace
	floorsFolder = folder
	ThreatService.setFloorsFolder(folder)

	currentRunSeed = os.time()

	-- THE RUN'S IDENTITY, and the namespace every currency transaction this expedition performs is
	-- keyed under. It must be unique per expedition on this server, because two runs sharing an id
	-- would let the second one's payout be rejected as a replay of the first's. JobId pins the server,
	-- the seed pins the expedition within it, and the counter covers the case of two runs starting in
	-- the same second.
	runCounter += 1
	local runId = string.format("%s:%d:%d", game.JobId, currentRunSeed, runCounter)
	local memberIds: { Types.PlayerId } = {}
	for playerId in queuedRunners do
		table.insert(memberIds, playerId)
	end
	table.sort(memberIds)
	-- Before the first floor is planned: which seam kinds this cave may contain.
	table.clear(currentUnlockedNodes)
	for _, playerId in memberIds do
		for _, nodeId in Interfaces.LampNetwork.ownedNodes(playerId) do
			currentUnlockedNodes[nodeId] = true
		end
	end

	ExtractionService.beginRun(runId, tier.id, memberIds)
	-- Admission is taken here, at the last possible moment before the cave exists, and never
	-- speculatively: everything that could still cancel this expedition has already happened.
	chargeAdmission(tier.id, memberIds, runId)
	markPlayersInRun(memberIds, runId)

	-- THE ONLY FLOOR THE DESCENT WAITS ON. Nothing below floor one can be reached before a body
	-- exists, and a body cannot exist before floor one does — so floor one is built here and the rest
	-- of the lookahead is owed rather than paid. Every floor built ahead of the spawn used to be time
	-- the whole party spent staring at a loading screen for a room none of them were in yet.
	local floorOneStartedAt = os.clock()
	buildFloor(1)
	local floorOneMs = math.round((os.clock() - floorOneStartedAt) * 1000)
	ensureLookahead(1)
	Telemetry.loadingStage("spawning_body")
	startingRunnerCount = 0
	for _ in queuedRunners do
		startingRunnerCount += 1
	end
	table.clear(runners)
	local firstFloor = floors[1]
	if firstFloor ~= nil then
		for _, player in Players:GetPlayers() do
			if queuedRunners[player.UserId] then
				spawnRunner(player, firstFloor.entryPosition)
			end
		end
	end
	Telemetry.loadingStage("run_ready")
	Telemetry.event("run_started", nil, {
		players = #Players:GetPlayers(),
		tier = currentTierId,
		startDepth = currentStartDepth,
		-- What the descent actually blocked on, and what it deferred. `blockingFloorMs` is the number
		-- the loading screen is measured in: everything else on this line happens after bodies exist.
		blockingFloorMs = floorOneMs,
		lookaheadFloors = Config.Run.floorLookahead,
		queuedFloors = #pendingFloors,
		seed = currentRunSeed,
	})
end

local function teardown()
	ThreatService.reset()
	EnemyService.reset()
	BossEncounterService.reset()
	DripstoneService.reset()
	VineService.reset()
	TripwireService.reset()
	DynamiteService.reset()
	MossFireService.reset()
	AshamedLurkerService.reset()
	StoneWardenService.reset()
	-- The service destroys owned encounters above; the registry reset remains a final guard for any
	-- handle that had already detached itself from production floor ownership.
	WardenRegistry.reset()
	EnemyRegistry.reset()
	QueenRegistry.reset()
	HazardService.reset()
	DripTrailService.reset()
	ToolService.reset()
	LootService.reset()
	DeadCandleService.reset()
	MiningService.reset()
	-- Cargo, its dedup latches, the party-bonus ledger and the run id every transaction was keyed by
	-- die with the deposits that produced them. Nothing about Raw Wax survives a run boundary in any
	-- direction — and because transaction ids embed the run id, a replayed credit from a finished run
	-- cannot collide with a live one either.
	ExtractionService.reset()
	-- Candle remains deliberately outlive an expedition, but the CARGO on them must not: a haul that
	-- survived teardown would be free money deposited into the next run's floors.
	Interfaces.Remains.clearAllCargo()
	-- Deposits and their models are gone, so the noise they made must go with them: a stale event
	-- would otherwise let the next floor's threats investigate a sound from the previous one.
	NoiseService.reset()
	RemainsService.reset()
	BasinService.reset()
	ShopService.reset()
	ContractWatchService.reset()
	BrazierService.reset()
	WallLampService.reset()
	DescentLadderService.reset()
	DeathService.reset()
	-- Ghosts and the footfalls they were reading die with the floors those footfalls were left on.
	SpectatorService.reset()
	RunSummaryService.reset()
	WaxService.reset()
	MovementSanityService.reset()
	table.clear(floors)
	table.clear(floorPlans)
	-- Floors this expedition still owed itself. They die with it: the next run reseeds, and a leftover
	-- entry would have the following expedition carve a floor from the finished one's depth.
	table.clear(pendingFloors)
	table.clear(runners)
	table.clear(runnerSlots)
	table.clear(queuedRunners)
	nextFloorRetirementAt = 0
	startingRunnerCount = 0
	currentRunSeed = 0
	currentFamilyId = Config.CaveFamilies.defaultId
	if floorsFolder ~= nil then
		floorsFolder:Destroy()
		floorsFolder = nil
	end
	-- The floor Terrain is not parented to the folder; clear it explicitly on teardown.
	workspace.Terrain:Clear()
	-- Nobody is mid-run any more. Clearing every marker here — rather than only on the paths that
	-- resolve a player cleanly — is what stops a crashed or abandoned expedition from pulling a
	-- returning player back into a cave that has already been demolished.
	for _, player in Players:GetPlayers() do
		clearRunMarker(player.UserId)
	end
end

local function queuePresentParty()
	table.clear(queuedRunners)
	local party = Interfaces.Party.snapshot()
	if party == nil then
		return
	end
	for _, playerId in party.members do
		if Players:GetPlayerByUserId(playerId) ~= nil then
			queuedRunners[playerId] = true
		end
	end
end

local function restartExpedition()
	-- A remote can arrive while FloorBuilder is suspended at its Terrain-query barrier. Teardown would
	-- clear those voxels out from under the pending build, so let the normal resolved-run tick retry once
	-- the serialized build has finished.
	if floorBuildInProgress then
		return
	end
	teardown()
	queuePresentParty()
	if next(queuedRunners) ~= nil then
		-- A replay starts from inside the finished cave with no elevator ride in front of it, so this
		-- is the one path that still owes the player the whole countdown.
		beginCountdown(Config.Run.startCountdownSeconds)
	else
		phase = "Waiting"
	end
end

local function returnToLobby()
	if floorBuildInProgress then
		return
	end
	for playerId in runners do
		local player = Players:GetPlayerByUserId(playerId)
		if player ~= nil then
			CharacterService.despawn(player)
		end
		-- A player who died mid-run stays `alive = false` in PlayerState until spawnRunner resets it for
		-- their NEXT run — otherwise nothing ever touches that flag again. StateSync keeps broadcasting it
		-- as-is, so without this the client's ghost HUD (client/SpectatorController) reads them as still
		-- a ghost for the entire time they are back in the lobby.
		PlayerState.reset(playerId)
	end
	teardown()
	phase = "Waiting"
	phaseDeadline = 0
	local callback = lobbyReturnHandler
	if callback ~= nil then
		callback()
	end
end

-- NOBODY IS EVER STUCK ON A FLOOR.
--
-- Two things can take a runner out of play without taking them out of the run: the engine can destroy
-- the body outright (server/EnvironmentSetup.reserveDepth explains how that used to happen every time
-- anyone reached floor 7), and a body can leave its floor through a seam in the terrain and keep
-- falling. Neither is a death, and nothing else notices — PlayerState reads "alive" from the wax, so
-- the run carries on happily while the player sits there unable to walk.
--
-- It is a REPAIR, never a kill: the wax, the haul and the floor they had reached are all preserved,
-- and they are put back at their own entry slot on the floor they are already on. The wax they are
-- burning while stranded is the only cost, which is the same cost as being lost.
local function recoverStrandedRunners()
	for playerId in runners do
		local state = PlayerState.get(playerId)
		if state == nil or not state.alive or state.finished then
			continue
		end
		local player = Players:GetPlayerByUserId(playerId)
		local runtime = floors[state.depth]
		if player == nil or runtime == nil then
			continue
		end
		-- Order matters: a destroyed root keeps reporting the position it died at, so "did they fall"
		-- is only a meaningful question once we know there is still a body to ask it about.
		local bodyLost = not CharacterService.hasIntactBody(playerId)
		local position = if bodyLost then nil else CharacterService.basePosition(playerId)
		local leftFloor = position ~= nil and position.Y < runtime.entryPosition.Y - Config.Run.floorRecoveryDrop
		if not bodyLost and not leftFloor then
			continue
		end

		local entry = entryForRunner(playerId, runtime.entryPosition)
		if entry == nil then
			continue
		end
		state.position = entry
		if bodyLost then
			-- A replacement rig, not a new candle: `spawn` builds it at the height this player's
			-- remaining wax says it is, and PlayerState is never touched.
			CharacterService.spawn(player, entry)
			MovementService.refresh(playerId)
			DeathService.rebindRelightPrompt(playerId)
			-- The client binds its camera to the humanoid it is told about, so a replaced body needs
			-- the same signal a descent sends.
			Remotes.get("RunEvent"):FireClient(player, "floor", {
				depth = state.depth,
				globalDepth = PlayerState.globalDepth(state),
				tierId = currentTierId,
				familyId = currentFamilyId,
			})
		else
			CharacterService.teleport(playerId, entry)
		end
		MovementSanityService.markAuthorized(playerId, entry)
		Telemetry.event("runner_recovered", playerId, {
			depth = state.depth,
			globalDepth = PlayerState.globalDepth(state),
			reason = if bodyLost then "BodyLost" else "LeftFloor",
		})
	end
end

-- FLOORS THE PARTY HAS LEFT BEHIND FOR GOOD.
--
-- Depth is uncapped, so without this every floor an expedition ever carved stays resident AND stays
-- simulated for the rest of the run: each per-floor service ticks its entire history every frame, and
-- with StreamingEnabled off every client keeps rendering all of it. A long run therefore got steadily
-- slower the deeper it went and never recovered until teardown.
--
-- WHAT PROTECTS A FLOOR: any connected participant still inside the cave who is standing on it, plus
-- a trailing margin (`Config.Run.floorRetentionBehind`) measured from the SHALLOWEST of them — so a
-- split party and a ghost who deliberately stays behind both keep their ground. A player who has
-- extracted is out of the cave and protects nothing; a disconnected one has no body left to strand.
--
-- ONLY THIS EXPEDITION'S PARTICIPANTS COUNT. `runners` rather than `PlayerState.all()` is load-bearing:
-- in Studio the lobby shares this server, and a player standing in the hub carries a default depth of
-- 1, which would pin the shallowest protected depth at the top of the cave and silently disable
-- retirement for the whole run.
local function protectedDepths(): { number }
	local depths: { number } = {}
	for playerId in runners do
		local state = PlayerState.get(playerId)
		-- `finished` is an extraction, not a location: they are out, and their last floor is free.
		if state == nil or state.finished then
			continue
		end
		if Players:GetPlayerByUserId(playerId) == nil then
			continue
		end
		table.insert(depths, state.depth)
	end
	return depths
end

-- Everything one retired floor owns, in the one order that is safe: service state first, while the
-- Instances those services own are still parented and destroyable, then the floor model, then the
-- rock it was carved from.
local function retireFloor(depth: number)
	local runtime = floors[depth]
	if runtime == nil then
		return
	end
	floors[depth] = nil
	floorPlans[depth] = nil

	ThreatService.clearDepth(depth)
	EnemyService.clearDepth(depth)
	BossEncounterService.clearDepth(depth)
	LootService.clearDepth(depth)
	DeadCandleService.clearDepth(depth)
	MiningService.clearDepth(depth)
	RemainsService.clearDepth(depth)
	DripstoneService.clearDepth(depth)
	VineService.clearDepth(depth)
	TripwireService.clearDepth(depth)
	DynamiteService.clearDepth(depth)
	MossFireService.clearDepth(depth)
	AshamedLurkerService.clearDepth(depth)
	StoneWardenService.clearDepth(depth)
	HazardService.clearDepth(depth)
	BasinService.clearDepth(depth)
	BrazierService.clearDepth(depth)
	WallLampService.clearDepth(depth)
	DescentLadderService.clearDepth(depth)
	ToolService.clearDepth(depth)
	-- A Warden's own animation connection and pathing loop both retire themselves when the model
	-- below disappears, but the registry is read by hazard lookups every tick and must never answer
	-- with a body that is already gone.
	WardenRegistry.clearDepth(depth)
	-- Same contract for the wick-pack bodies and the Queen: both registries are read by the blast
	-- path, and an entry whose model went down with this floor would answer a detonation on the NEXT
	-- floor with a stale position. The owning services destroy their own bodies above; these two calls
	-- are what guarantee the lookup tables cannot outlive them.
	EnemyRegistry.clearDepth(depth)
	QueenRegistry.clearDepth(depth)

	runtime.model:Destroy()
	-- Exactly the regions this floor wrote, recorded by FloorBuilder at carve time rather than
	-- re-derived here. Floors sit `geometry.floorGap` apart and no room reaches that height, so
	-- clearing one can never eat into a floor still in play.
	local terrain = workspace.Terrain
	for _, region in runtime.terrainRegions do
		terrain:FillRegion(region, 4, Enum.Material.Air)
	end

	Telemetry.event("floor_retired", nil, {
		depth = depth,
		globalDepth = DepthRules.getGlobalDepth(currentStartDepth, depth),
	})
end

-- Amortized deliberately: a Terrain clear is not free, and landing several of them on the same frame
-- as a descent or a queued carve is exactly the hitch the lookahead split exists to avoid.
local function retireFloors(now: number)
	if now < nextFloorRetirementAt then
		return
	end
	nextFloorRetirementAt = now + math.max(Config.Run.floorRetirementCheckSeconds, 0)

	local built: { number } = {}
	for depth in floors do
		table.insert(built, depth)
	end
	local retained: { [number]: boolean }? = nil
	if Config.Run.retainEntryFloor then
		-- `onPlayerAdded` admits a late or rejoining party member at floor one's entry position, so
		-- retiring it would leave them with nowhere to arrive.
		retained = { [1] = true }
	end

	local retireable =
		FloorRetentionRules.retireableDepths(built, protectedDepths(), Config.Run.floorRetentionBehind, retained)
	local budget = math.max(1, math.floor(Config.Run.maxFloorRetirementsPerCheck))
	-- `retireableDepths` returns ascending, so the oldest floor always goes first.
	for index = 1, math.min(#retireable, budget) do
		retireFloor(retireable[index])
	end
end

-- THE TWO HALVES OF A DESCENT, split at the Descent Ladder's ride (FLOOR-FIXTURES-OVERHAUL).
--
-- This used to be one function polled every tick against every runner's position: stand in an
-- invisible box around a floating beacon and you were on the next floor that frame. The rules it
-- enforced are unchanged and still live here — the orchestrator is the only thing that knows what a
-- floor is — but the two ends now sit either side of a four-second ride that `DescentLadderService`
-- owns the clock for.
--
-- MAY THIS PLAYER SET OFF? Asked when the winch is pulled, and deliberately the place the floor
-- below gets built if the lookahead has not reached it yet. The guard finishes that synchronous work
-- before `DescentLadderService` commits riders or broadcasts motion, so a successful ride always has
-- a complete physical landing beneath it.
local function canDescendFrom(playerId: Types.PlayerId, fromDepth: number): boolean
	if phase ~= "Running" or not runners[playerId] then
		return false
	end
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished or state.snuffedAt ~= nil or state.depth ~= fromDepth then
		return false
	end
	if floors[fromDepth] == nil then
		return false
	end
	-- THE GRUB QUEEN GUARDS THE LADDER (Config/GrubQueen.requiresKillToDescend).
	--
	-- This is a deliberate, narrow exception to the rule that every creature in this cave is a hazard
	-- to route around rather than an obstacle to defeat — an owner decision, and the only place in the
	-- game where a body blocks progression. It is bounded the same way the dynamite exception is: by a
	-- config flag on one encounter that appears every ten to fifteen floors, not by a convention other
	-- creatures could quietly acquire.
	--
	-- Checked HERE rather than on the ladder fixture because this function is already the single
	-- authority on whether a descent may begin, and a second gate on the cage would be a second place
	-- for the answer to disagree with itself.
	if Config.GrubQueen.requiresKillToDescend and EnemyService.queenAliveAtDepth(fromDepth) then
		return false
	end
	local nextRuntime = floors[fromDepth + 1]
	if nextRuntime == nil then
		nextRuntime = buildFloor(fromDepth + 1)
	end
	if nextRuntime == nil then
		return false
	end
	return true
end

-- THE CAGE HAS LANDED. Every check `canDescendFrom` made is made again rather than trusted, because
-- the seconds in between are seconds a player can die, be snuffed, extract or leave in — and the one
-- thing this must never do is hand somebody a depth their body did not go to.
--
-- Returns whether the move actually happened, so the ladder can put a refused rider back on the pad
-- instead of stranding them on a cage it is about to haul up.
local function arriveBelow(playerId: Types.PlayerId, fromDepth: number, landingPosition: Vector3): boolean
	if phase ~= "Running" or not runners[playerId] then
		return false
	end
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished or state.snuffedAt ~= nil or state.depth ~= fromDepth then
		return false
	end
	local nextRuntime = floors[fromDepth + 1]
	if nextRuntime == nil then
		nextRuntime = buildFloor(fromDepth + 1)
	end
	if nextRuntime == nil then
		return false
	end
	state.depth = fromDepth + 1
	state.position = landingPosition
	local globalDepth = PlayerState.globalDepth(state)
	WaxAccounting.noteDepth(state.waxLedger, globalDepth)
	CharacterService.teleport(playerId, landingPosition)
	MovementSanityService.markAuthorized(playerId, landingPosition)
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		Remotes.get("RunEvent"):FireClient(player, "floor", {
			depth = state.depth,
			globalDepth = globalDepth,
			tierId = currentTierId,
			familyId = currentFamilyId,
		})
	end
	Telemetry.event("floor_reached", playerId, {
		depth = state.depth,
		globalDepth = globalDepth,
		tier = currentTierId,
	})
	-- THE SUCCESSOR IS OWED LAST, and deliberately so: it is the longest and the most fallible step in
	-- a descent, and nothing above it needs the result. Running it before the move meant a floor that
	-- failed to build left a player holding a depth their body had not gone to. It is queued rather
	-- than built because the floor this runner just arrived on already exists and the one below it was
	-- proven above; the rest of the lookahead can take a frame.
	ensureLookahead(state.depth)
	return true
end

local function runIsOver(): boolean
	for playerId in runners do
		local state = PlayerState.get(playerId)
		if state ~= nil and Players:GetPlayerByUserId(playerId) ~= nil and state.alive and not state.finished then
			return false
		end
	end
	return true
end

local function announceEarlyExtraction(extractor: Player)
	local text = string.format("%s has extracted early.", extractor.Name)
	for playerId in runners do
		if playerId == extractor.UserId then
			continue
		end
		local teammate = Players:GetPlayerByUserId(playerId)
		if teammate ~= nil then
			Remotes.get("RunEvent"):FireClient(teammate, "message", { text = text })
		end
	end
end

function RunOrchestrator.init(onLobbyReturn: LobbyReturnHandler?)
	lobbyReturnHandler = onLobbyReturn
	-- The ladder owns its prompt, its ride and its machinery; these two functions are the whole of
	-- what it is allowed to know about floors. Handed over here rather than required in the other
	-- direction so the module that owns the cave keeps owning it.
	DescentLadderService.init(canDescendFrom, arriveBelow)
	Remotes.get("RestartRun").OnServerEvent:Connect(function(player: Player)
		if not RequestGuard.allow(player, "RestartRun") then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil or (state.alive and not state.finished) then
			return
		end
		if (phase ~= "Running" and phase ~= "Restarting") or not runIsOver() then
			Remotes.get("RunEvent"):FireClient(player, "message", {
				text = "Restart is available when every runner has finished or died.",
			})
			return
		end
		Telemetry.event("run_restart_requested", player.UserId)
		restartExpedition()
	end)
	Remotes.get("ReturnToLobby").OnServerEvent:Connect(function(player: Player)
		if not RequestGuard.allow(player, "ReturnToLobby") then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil or (state.alive and not state.finished) then
			return
		end
		if phase ~= "Running" and phase ~= "Restarting" then
			return
		end
		if runIsOver() then
			Telemetry.event("run_lobby_return_requested", player.UserId)
			returnToLobby()
			return
		end
		-- A living, resolved player has already banked their non-group payout at a Brazier. They may
		-- leave now without ending the shared expedition; the choice permanently gives up only their
		-- still-pending party credit.
		if state.alive and state.finished then
			if ExtractionService.forfeitPartyBonus(player.UserId) then
				announceEarlyExtraction(player)
				Telemetry.event("early_extraction_requested", player.UserId, {
					depth = state.depth,
					globalDepth = PlayerState.globalDepth(state),
				})
			end
			clearRunMarker(player.UserId)
			PartyLobbyService.returnPlayerToMainLobby(player)
			return
		end
		if not runIsOver() then
			Remotes.get("RunEvent"):FireClient(player, "message", {
				text = "Lobby return is available when every runner has finished or died.",
			})
			return
		end
	end)
end

-- `countdownAlreadyServed` is the lobby telling this run that the wait the player owes has already
-- been spent somewhere the player could see it. A live expedition arrives that way — the elevator car
-- rides the full countdown down its shaft before the teleport — and running the countdown again in
-- the destination server only adds silent seconds to a loading screen. Studio, which has no teleport
-- and therefore no ride, passes nothing and gets the countdown here.
function RunOrchestrator.startFromLobby(tierId: number, memberIds: { Types.PlayerId }, countdownAlreadyServed: boolean?)
	if phase ~= "Waiting" then
		return
	end
	local tier = Interfaces.CaveTiers.get(tierId)
	currentTierId = if tier ~= nil then tier.id else 1
	table.clear(queuedRunners)
	for _, playerId in memberIds do
		if Players:GetPlayerByUserId(playerId) ~= nil then
			queuedRunners[playerId] = true
			PlayerState.ensure(playerId)
		end
	end
	if next(queuedRunners) ~= nil then
		beginCountdown(if countdownAlreadyServed then 0 else Config.Run.startCountdownSeconds)
	end
end

function RunOrchestrator.onPlayerAdded(player: Player)
	PlayerState.ensure(player.UserId)
	if phase == "Countdown" then
		local party = Interfaces.Party.snapshot()
		if party ~= nil and table.find(party.members, player.UserId) ~= nil then
			queuedRunners[player.UserId] = true
		end
	elseif phase == "Running" then
		local party = Interfaces.Party.snapshot()
		local firstFloor = floors[1]
		if
			party ~= nil
			and table.find(party.members, player.UserId) ~= nil
			and firstFloor ~= nil
			and not runners[player.UserId]
		then
			spawnRunner(player, firstFloor.entryPosition)
		end
	end
end

-- Living Wax still on the candle at the moment a run resolves, for the experiment's summary line.
-- Zero for a player with no run state left to read.
local function waxRemainingFor(playerId: Types.PlayerId): number
	local state = PlayerState.get(playerId)
	return if state ~= nil then state.wax.current else 0
end

function RunOrchestrator.onPlayerRemoving(player: Player)
	if runners[player.UserId] then
		local leaving = PlayerState.get(player.UserId)
		-- WHETHER THIS PLAYER SHOULD BE PULLED BACK IN. A player who is still alive and still in the
		-- cave dropped out of a run they were playing, and their marker stays so RejoinService can
		-- return them to it. A player who already cashed out or already died has nothing to come back
		-- to, so their marker is cleared and rejoining puts them in a normal lobby.
		if leaving == nil or leaving.finished or not leaving.alive then
			clearRunMarker(player.UserId)
		end
		-- Leaving mid-run still resolves the run for accounting purposes.
		RunSummaryService.emit(player.UserId, "Disconnect")

		-- PHASE 8: THE BAG DROPS WHERE THEY STOOD, LOCKED TO THEM.
		--
		-- This is the shape that makes "it drops, and if you come back you get it back" safe. The pile
		-- IS the hold: the cargo is removed from the run state and placed in the world in one step, so
		-- at no instant does it exist in two places. During the grace window only its owner may claim
		-- it (Interfaces/Remains enforces the lock); after the window it unlocks for whoever is still
		-- down there. Nothing is ever taken back from a teammate who already picked it up, because
		-- "return it to the owner" and "credit it to the finder" cannot both be true.
		local state = PlayerState.get(player.UserId)
		local dropped, droppedUnits = ExtractionService.dropOnDisconnect(player.UserId)
		if droppedUnits > 0 and state ~= nil then
			local record = Interfaces.Remains.deposit({
				playerId = player.UserId,
				depth = state.depth,
				position = state.position,
				-- A disconnect leaves no candle behind — the body simply is not there any more. Only
				-- the haul drops, so this record carries cargo and no wax.
				wax = 0,
				cargo = dropped,
				ownerLockUntil = os.clock() + Config.Extraction.disconnectGraceSeconds,
			})
			-- Visible immediately, so the party sees where their teammate went down and can decide
			-- whether to wait out the lock or move on.
			RemainsService.spawnLive(record)
		end
		ExtractionService.emitRunSummary(player.UserId, "Disconnect", waxRemainingFor(player.UserId))
		-- A disconnect resolves this player WITHOUT cancelling the party bonus (Config/Extraction:
		-- connections drop for reasons that are not decisions). The survivors may still settle.
		ExtractionService.noteDisconnect(player.UserId)
		local bonuses = ExtractionService.settlePartyBonus()
		BrazierService.announceBonuses(bonuses)
	end
	RunSummaryService.clear(player.UserId)
	ExtractionService.clear(player.UserId)
	DripTrailService.clear(player.UserId)
	SpectatorService.clear(player.UserId)
	MiningService.clear(player.UserId)
	NoiseService.clear(player.UserId)
	CharacterService.despawn(player)
	MovementSanityService.clear(player.UserId)
	PlayerState.remove(player.UserId)
	queuedRunners[player.UserId] = nil
	runners[player.UserId] = nil
	runnerSlots[player.UserId] = nil
end

function RunOrchestrator.tick()
	if floorBuildInProgress then
		return
	end
	local now = os.clock()
	floorsCarvedThisTick = 0
	if phase == "Countdown" and now >= phaseDeadline then
		if next(queuedRunners) ~= nil then
			startRun()
		else
			phase = "Waiting"
		end
	elseif phase == "Running" then
		-- Before the ladders, so a runner whose body was just replaced is standing somewhere real when
		-- this frame's rides land.
		recoverStrandedRunners()
		-- Rides that have reached the bottom move their rider through `arriveBelow`, which is where a
		-- floor may be carved on demand — so this sits exactly where the old descent check did.
		DescentLadderService.tick()
		-- After the descent step, never before it. If this frame already had to carve a floor to let
		-- somebody down, that is the whole frame's budget spent — draining the queue on top of it would
		-- double the one stall this split exists to avoid.
		if floorsCarvedThisTick == 0 then
			buildOnePendingFloor()
		end
		-- Last, and never on a frame that already carved: a build and a Terrain clear are the two
		-- most expensive things this tick can do, and there is no reason to pay for both at once.
		if floorsCarvedThisTick == 0 then
			retireFloors(now)
		end
		if runIsOver() then
			phase = "Restarting"
			phaseDeadline = now + Config.Run.restartDelaySeconds
			broadcast("runResolved", {})
			broadcast("message", { text = "The caves grow quiet. Replay, or return to the lobby." })
			Telemetry.event("run_resolved", nil, { tier = currentTierId })
		end
	elseif phase == "Restarting" and now >= phaseDeadline then
		restartExpedition()
	end
end

return RunOrchestrator

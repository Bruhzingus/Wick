--!strict
-- Server authority for the PIN-gated enemy laboratory. The room uses real candle, threat, Lurker,
-- Warden, Dripstone, noise and tool systems; this service only owns isolation, lifecycle and the
-- physical console's fixed action routing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local RoomFootprint = require(ReplicatedStorage.Shared.Logic.RoomFootprint)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local DevTestRoomRules = require(ReplicatedStorage.Shared.Logic.DevTestRoomRules)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local AshamedLurkerVisualProtocol = require(ReplicatedStorage.Shared.AshamedLurkerVisualProtocol)
local DripstoneVisualProtocol = require(ReplicatedStorage.Shared.DripstoneVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CaveKit = require(ReplicatedStorage.Shared.NewModelsAndObjects.CaveKit)
local UnstableDripstone = require(ReplicatedStorage.Shared.NewModelsAndObjects.UnstableDripstone)

local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local MovementService = require(script.Parent.MovementService)
local MovementSanityService = require(script.Parent.MovementSanityService)
local ToolService = require(script.Parent.ToolService)
local DynamiteService = require(script.Parent.DynamiteService)
local ThreatService = require(script.Parent.ThreatService)
local EnemyService = require(script.Parent.EnemyService)
local AshamedLurkerService = require(script.Parent.AshamedLurkerService)
local DripstoneService = require(script.Parent.DripstoneService)
local StoneWardenService = require(script.Parent.StoneWardenService)
local NoiseService = require(script.Parent.NoiseService)
local DripTrailService = require(script.Parent.DripTrailService)
local DevDiagnosticsService = require(script.Parent.DevDiagnosticsService)
local DevTestSessionRegistry = require(script.Parent.DevTestSessionRegistry)
local DevTestRoomBuilder = require(script.Parent.DevTestRoomBuilder)
local RequestGuard = require(script.Parent.RequestGuard)

local DevTestRoomService = {}

type Runtime = DevTestRoomBuilder.Runtime
type WardenHandle = StoneWardenService.EncounterHandle
type LobbyClosedProvider = () -> boolean

-- THE SHARED ROSTER ONLY. The three signature rows deliberately have no entry here any more: they
-- are reached through `spawn:Signature`, which resolves whichever one belongs to the armed cave, so a
-- direct `spawn:Listener` action would be a second route to the same creature that ignored the cave
-- selector — and the button that used to send it no longer exists.
local THREAT_BY_ACTION: { [string]: Types.ThreatId } = {
	["spawn:DarkCrawler"] = "DarkCrawler",
	["spawn:Moth"] = "Moth",
	["spawn:VoidFly"] = "VoidFly",
}

-- THE ARMED CAVE. One button per family sets this; every spawn button reads it.
--
-- Before this existed the laboratory could only ever produce Stone-dressed shared creatures — a
-- signature row got its own family hardcoded and everything else got `session.familyId` — so two
-- thirds of the variant system had no way to be looked at. The cave is a MODE now, which also
-- collapsed three per-family columns into one three-button selector.
local CAVE_BY_ACTION: { [string]: string } = {
	["cave:STONE"] = "STONE",
	["cave:MOSS"] = "MOSS",
	["cave:ICE"] = "ICE",
}

-- The one creature each cave has to itself, resolved from whatever is armed.
local SIGNATURE_BY_FAMILY: { [string]: Types.ThreatId } = {
	STONE = "Listener",
	MOSS = "Knotwalker",
	ICE = "Calver",
}

local armedFamilyId: string = Config.DevTestRoom.session.familyId

-- THE WICK PACK (shared/Enemies). Kept out of `THREAT_BY_ACTION` because these are not
-- `Config/Threats` rows and nothing about them routes through `ThreatService`: they are bespoke
-- bodies owned by `EnemyService`, so they spawn, tick and tear down through a different service
-- entirely. Sharing the table would only have meant every consumer of it re-checking which kind it
-- had actually been handed.
local PACK_BY_ACTION: { [string]: string } = {
	["spawn:WaxGrub"] = "WaxGrub",
	["spawn:StoneGnawer"] = "StoneGnawer",
	["spawn:Longarm"] = "Longarm",
	["spawn:GrubQueen"] = "GrubQueen",
}

-- Display names for the status line, so a press reports the creature rather than the action id.
local PACK_DISPLAY_NAME: { [string]: string } = {
	WaxGrub = "Wax Grub brood",
	StoneGnawer = "Stone Gnawer",
	Longarm = "Longarm",
	GrubQueen = "Grub Queen",
}

local REBUILD_ACTIONS: { [string]: boolean } = {
	["spawn:AshamedLurker"] = true,
	["spawn:Warden"] = true,
	-- The Queen replaces whichever one is live rather than stacking (see `spawnPackEnemy`), so she
	-- destroys and rebuilds a set piece exactly as the Warden and the Lurker do and earns the same
	-- longer cooldown and shared rebuild lock. The other three pack buttons are ordinary additive
	-- spawns and deliberately are NOT here.
	["spawn:GrubQueen"] = true,
	-- The arena's own start button rebuilds a whole encounter — her, both guards, and whatever the last
	-- attempt left standing — so it takes the same shared rebuild lock the other set pieces do.
	["boss:start"] = true,
	["remove:all"] = true,
	["remove:hotkey"] = true,
	["reset:hazards"] = true,
}

local DEFAULT_THREAT_ROOM_INDEX = 3
local KNOTWALKER_ROOM_INDEX = 4

local runtime: Runtime? = nil
local lobbyClosedProvider: LobbyClosedProvider? = nil
local activePlayers: { [Types.PlayerId]: boolean } = {}
local ordinaryModels: { Model } = {}
local spawnSequence = 0
local lurkerProxy: BasePart? = nil
local hazardModel: Model? = nil
local warden: WardenHandle? = nil
local actionBusy: { [Types.PlayerId]: boolean } = {}
local nextControlAt: { [Types.PlayerId]: number } = {}
local nextSharedRebuildAt = 0
local nextContainmentCheckAt = 0
local testPlan: Types.FloorPlan? = nil
local testCenters: { Vector3 } = {}
local testSurfaces: { [number]: ThreatService.RoomSurface } = {}

local function remote(): RemoteEvent
	return Remotes.get("DevTestRoom")
end

local function sendState(player: Player, message: string?)
	remote():FireClient(player, "state", {
		active = activePlayers[player.UserId] == true,
		message = message or "",
	})
end

local function sendStatus(player: Player, message: string)
	remote():FireClient(player, "status", { message = message })
end

local function hasActivePlayers(): boolean
	return next(activePlayers) ~= nil
end

local function runCleanup(label: string, callback: () -> ())
	local ok, cleanupError = pcall(callback)
	if not ok then
		warn(string.format("[WICK] developer test cleanup failed (%s): %s", label, tostring(cleanupError)))
	end
end

local function allowControl(playerId: Types.PlayerId, actionId: string): boolean
	local now = os.clock()
	if now < (nextControlAt[playerId] or 0) then
		return false
	end
	local session = Config.DevTestRoom.session
	local rebuild = REBUILD_ACTIONS[actionId] == true
	if rebuild and now < nextSharedRebuildAt then
		return false
	end
	nextControlAt[playerId] = now
		+ (if rebuild then session.rebuildControlCooldownSeconds else session.controlCooldownSeconds)
	if rebuild then
		nextSharedRebuildAt = now + session.sharedRebuildCooldownSeconds
	end
	return true
end

local function rebuildOrdinaryModelList()
	for index = #ordinaryModels, 1, -1 do
		if ordinaryModels[index].Parent == nil then
			table.remove(ordinaryModels, index)
		end
	end
end

local function buildThreatContext()
	local built = runtime
	if built == nil then
		return
	end
	local roomConfig = Config.DevTestRoom.room
	local session = Config.DevTestRoom.session
	local rooms: { Types.RoomPlacement } = {
		{
			moduleId = "DeveloperTestSouthwestBay",
			gridX = 0,
			gridZ = 0,
			doorways = { "S", "E" },
			ceilingHeight = roomConfig.interiorSize.Y,
			footprint = RoomFootprint.rectangle(),
		},
		{
			moduleId = "DeveloperTestNorthwestBay",
			gridX = 0,
			gridZ = 1,
			doorways = { "N", "E" },
			ceilingHeight = roomConfig.interiorSize.Y,
			footprint = RoomFootprint.rectangle(),
		},
		{
			moduleId = "DeveloperTestSoutheastBay",
			gridX = 1,
			gridZ = 0,
			doorways = { "W", "S" },
			ceilingHeight = roomConfig.interiorSize.Y,
			footprint = RoomFootprint.rectangle(),
		},
		{
			moduleId = "DeveloperTestNortheastBay",
			gridX = 1,
			gridZ = 1,
			doorways = { "W", "N" },
			ceilingHeight = roomConfig.interiorSize.Y,
			footprint = RoomFootprint.rectangle(),
		},
	}
	testPlan = {
		depth = session.depth,
		globalDepth = session.globalDepth,
		familyId = session.familyId,
		diagnostics = { shapedRooms = 0, shapeFallbacks = 0, shapeRejections = 0 },
		rooms = rooms,
		entryRoomIndex = 1,
		-- A deliberately absent index: none of the four test bays may become a protected Basin.
		basinRoomIndex = 5,
		brazierRoomIndex = 5,
		threatSpawns = {},
		lootSpawns = {},
		hazards = {},
		dripstones = {},
		vines = {},
		lurkers = {},
		warden = nil,
		deadCandle = nil,
		deposits = {},
		blastVaults = {},
		mossFire = {},
		groundPatches = {},
		lockedStoreRoomIndex = nil,
	}
	local halfCell = Config.Floors.geometry.cellSize / 2
	testCenters = {
		built.roomCenter + Vector3.new(-halfCell, 0, -halfCell),
		built.roomCenter + Vector3.new(-halfCell, 0, halfCell),
		built.roomCenter + Vector3.new(halfCell, 0, -halfCell),
		built.roomCenter + Vector3.new(halfCell, 0, halfCell),
	}
	testSurfaces = {}
	for index, room in rooms do
		testSurfaces[index] = {
			center = testCenters[index],
			ceilingHeight = room.ceilingHeight,
			allowAnalyticGroundFallback = true,
			groundField = GroundGeometry.fieldFor(
				room,
				session.globalDepth,
				true,
				-- Cover the full square cell, including its corners, so analytic AI height agrees with
				-- the laboratory's flat physical Part floor in all four bays.
				{ { x = 0, z = 0, r = halfCell * math.sqrt(2) } },
				{},
				{},
				session.familyId
			),
			roofField = {
				maxRelief = 0,
				frequencies = { 0, 0, 0, 0 },
				phases = { 0, 0, 0, 0 },
			},
		}
	end

	-- THE SAME CONCESSION `allowAnalyticGroundFallback` MAKES ABOVE, for the wick-pack bodies.
	--
	-- This laboratory stands on a collidable Part floor and has no Terrain at all, while every seat in
	-- `EnemyService` probes for Terrain and refuses on a miss — correct in a real cave, and here it
	-- would mean every pack button reported a failure the tester could do nothing about. Registering
	-- the room's flat floor height is what lets them spawn and, for the CFrame-driven grub, what lets
	-- it crawl instead of standing still.
	--
	-- Production floors never register one, so they keep failing closed.
	EnemyService.setGroundFallback(session.depth, built.roomCenter.Y)
end

local function clearLurker()
	AshamedLurkerService.clearDepth(Config.DevTestRoom.session.depth)
	local proxy = lurkerProxy
	lurkerProxy = nil
	if proxy ~= nil and proxy.Parent ~= nil then
		proxy:Destroy()
	end
end

local function clearWarden()
	local current = warden
	warden = nil
	if current ~= nil then
		current.destroy()
	end
end

local function clearEnemies(): number
	local removed = ThreatService.clearTest(Config.DevTestRoom.session.scopeId)
	table.clear(ordinaryModels)
	-- The wick-pack bodies are owned by EnemyService and keyed by this room's virtual depth, so one
	-- call takes every grub, gnawer, longarm and queen — including grubs the Queen birthed, which are
	-- ordinary tracked bodies at the same depth.
	removed += EnemyService.countAtDepth(Config.DevTestRoom.session.depth)
	EnemyService.clearDepth(Config.DevTestRoom.session.depth)
	if lurkerProxy ~= nil then
		removed += 1
	end
	clearLurker()
	if warden ~= nil then
		removed += 1
	end
	clearWarden()
	spawnSequence = 0
	return removed
end

local function clearHazard()
	DripstoneService.clearDepth(Config.DevTestRoom.session.depth)
	local model = hazardModel
	hazardModel = nil
	if model ~= nil and model.Parent ~= nil then
		model:Destroy()
	end
end

local function resetHazard(): boolean
	local built = runtime
	if built == nil then
		return false
	end
	clearHazard()
	local hazard = Config.DevTestRoom.hazard
	local variant = DripstoneRules.variantById(hazard.variantId)
	if variant == nil then
		return false
	end

	local family = CaveFamilyRules.resolve(Config.DevTestRoom.session.familyId)
	local dressing = Config.Floors.caveDressing
	CaveKit.configure({
		palette = family.presentation.formationPalette,
		dampTint = dressing.formationDampTint,
		materials = family.presentation.formationMaterials,
		wetMaterial = family.presentation.formationWetMaterial,
		wetReflectance = dressing.formationWetReflectance,
	})
	local model = UnstableDripstone.build(built.dynamicFolder, built.hazardAnchorCFrame, variant, hazard.visualSeed)
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local visibleBottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
	local fallDistance =
		math.max(0, visibleBottomY - built.hazardImpactPosition.Y + Config.Hazards.unstableDripstone.impactEmbedDepth)
	local protocol = DripstoneVisualProtocol
	model:SetAttribute(protocol.attributes.state, protocol.states.dormant)
	model:SetAttribute(protocol.attributes.stateStartedAt, Workspace:GetServerTimeNow())
	model:SetAttribute(protocol.attributes.restCFrame, built.hazardAnchorCFrame)
	model:SetAttribute(protocol.attributes.impactPosition, built.hazardImpactPosition)
	model:SetAttribute(protocol.attributes.fallDistance, fallDistance)
	model:SetAttribute(protocol.attributes.variantId, hazard.variantId)
	model:SetAttribute(protocol.attributes.visualSeed, hazard.visualSeed)
	model:SetAttribute(protocol.attributes.depth, Config.DevTestRoom.session.depth)
	CollectionService:AddTag(model, protocol.tag)
	DripstoneService.registerFloor(Config.DevTestRoom.session.depth, {
		{
			model = model,
			depth = Config.DevTestRoom.session.depth,
			impactPosition = built.hazardImpactPosition,
			fallDistance = fallDistance,
			variantId = hazard.variantId,
		},
	})
	hazardModel = model
	return true
end

local function spawnOrdinary(threatId: Types.ThreatId): boolean
	local built = runtime
	local plan = testPlan
	local spawnRoomIndex = if threatId == "Knotwalker" then KNOTWALKER_ROOM_INDEX else DEFAULT_THREAT_ROOM_INDEX
	local spawnCenter = testCenters[spawnRoomIndex]
	if built == nil or plan == nil or spawnCenter == nil then
		return false
	end
	rebuildOrdinaryModelList()
	if #ordinaryModels >= Config.DevTestRoom.session.maxOrdinaryThreats then
		return false
	end

	-- A small deterministic ring prevents several spawned rows from occupying the same root while
	-- keeping Calver within reach of the registered crown.
	local slot = spawnSequence % 8
	spawnSequence += 1
	local angle = slot * math.pi / 4
	local authoredPosition = if threatId == "Knotwalker"
		then built.knotwalkerSpawnPosition
		else built.threatSpawnPosition
	local spawnPosition = authoredPosition + Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5)
	local spawnPlan = table.clone(plan)
	-- EVERY ROW WEARS THE ARMED CAVE. This used to pin signature rows to the family they ship in and
	-- hand everything else the laboratory's own Stone baseline, which meant a Moss or Ice crawler could
	-- not be produced here at all — two thirds of the presentation system had no way to be inspected.
	-- Arming a cave is now the one input that decides it, for signature and shared rows alike.
	spawnPlan.familyId = armedFamilyId
	local model = ThreatService.spawnTest(threatId, {
		scopeId = Config.DevTestRoom.session.scopeId,
		plan = spawnPlan,
		roomCenters = testCenters,
		roomSurfaces = testSurfaces,
		roomIndex = spawnRoomIndex,
		offset = spawnPosition - spawnCenter,
		targetPlayerIds = activePlayers,
		parent = built.dynamicFolder,
		geometryRoot = built.roomModel,
	})
	if model == nil then
		return false
	end
	table.insert(ordinaryModels, model)
	return true
end

-- One wick-pack body, spawned into the laboratory through the same `EnemyService` a real floor uses.
--
-- IT DOES NOT GO THROUGH `ThreatService.spawnTest`. That path exists to build a `Config/Threats` row
-- with a test scope and a target allowlist; these creatures are not rows and have no such concept, so
-- they are spawned exactly the way a real cave spawns them and torn down by depth instead.
--
-- THE LAB HAS A PART FLOOR, WHICH IS THE ONE THING THAT MAKES THIS DIFFERENT. Every spawn in
-- `EnemyService` seats itself by probing for Terrain, and this room has none — so without the flat
-- fallback registered in `buildThreatContext` every press here would silently refuse and report a
-- failure the tester could not act on.
local function spawnPackEnemy(packId: string): boolean
	local built = runtime
	if built == nil then
		return false
	end
	local session = Config.DevTestRoom.session

	-- RE-ASSERTED HERE, not merely registered once at init.
	--
	-- Every wick-pack body seats itself by probing for Terrain, and this laboratory has none — without
	-- a flat floor height on record every spawn refuses. Registering it once during setup is correct
	-- and was also fragile: a teardown between setup and the first press wiped it, and the symptom was
	-- every pack button reporting "no clear ground at the marker" while the ordinary roster kept
	-- working, because ThreatService carries its own per-surface `allowAnalyticGroundFallback` instead.
	--
	-- The value is a constant of a room that is built once and never moves, so writing it again on each
	-- press costs one table assignment and makes the ordering impossible to get wrong.
	EnemyService.setGroundFallback(session.depth, built.roomCenter.Y)

	-- NOTHING HERE IS CAPPED. The laboratory used to refuse a spawn past `maxOrdinaryThreats`, which
	-- was wrong for this room twice over: one GRUB BROOD press is two to five bodies, so three presses
	-- exhausted a cap of twelve and every button after that reported a failure the tester could do
	-- nothing about — and the Queen, whose own brood is capped by her, was refused for space her own
	-- creatures had taken. A room whose entire purpose is "what does this do to that" has no business
	-- rationing bodies; the tester decides when there are too many, and the REMOVE ALL hotkey is the
	-- answer when there are.

	-- The Queen is a set piece and an encounter, not a body you stack: she is immobile, births grubs
	-- on a timer and caps them herself, so a second one would just double an already-running clock in
	-- the same room. Pressing her button replaces whichever one is live.
	if packId == "GrubQueen" then
		EnemyService.clearKindAtDepth(session.depth, "GrubQueen")
		local queen =
			EnemyService.spawnQueen(session.depth, built.threatSpawnPosition, armedFamilyId, session.globalDepth * 7919)
		return queen ~= nil
	end

	-- The same deterministic ring `spawnOrdinary` uses, so repeated presses land beside each other
	-- rather than inside each other.
	local slot = spawnSequence % 8
	spawnSequence += 1
	local angle = slot * math.pi / 4
	local position = built.threatSpawnPosition + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
	local seed = session.globalDepth * 104_729 + spawnSequence

	if packId == "WaxGrub" then
		-- A BROOD, not a single grub, because a lone one is not the creature: the whole design is 2-5
		-- of them making a room annoying to stand still in. Seeded from the press so two brood presses
		-- are two different broods.
		return EnemyService.spawnBrood(session.depth, position, armedFamilyId, Random.new(seed)) > 0
	elseif packId == "StoneGnawer" then
		return EnemyService.spawnGnawer(session.depth, position, armedFamilyId, seed)
	elseif packId == "Longarm" then
		return EnemyService.spawnLongarm(session.depth, position, armedFamilyId, seed) ~= nil
	end
	return false
end

-- THE WHOLE ENCOUNTER, IN THE ARENA, AS THE REAL FLOOR COMPOSES IT: the Queen at her authored post and
-- two Longarms leashed to the chamber, from the same `BossFloorPlan.fixtures()` offsets the live fight
-- is built from (the builder maps them into the room; see `DevTestRoomBuilder.buildArena`).
--
-- WHY THIS DOES NOT CALL `BossEncounterService.spawnFloor`. That function takes a carved FloorPlan and
-- seats every fixture with `SurfaceProbe.resolvePlannedPosition`, which reads TERRAIN — and the
-- laboratory has none. Handing it a fabricated plan would mean lying to it about a floor that does not
-- exist; what is worth sharing is the COMPOSITION, and that lives in `BossFloorPlan` where both callers
-- read it from.
--
-- What is deliberately missing is the rest of the floor: no wax wing, no dynamite wing, no sealed
-- caches. The lab already hands out infinite wax and 999 sticks, so a resource race would be a race
-- against nothing — this tests the FIGHT, and the supply pressure is the part a real run has to
-- provide. An animated intro, when it exists, belongs on the threshold this room already has.
local function startBossEncounter(): (boolean, string)
	local built = runtime
	if built == nil then
		return false, "The arena is unavailable."
	end
	local session = Config.DevTestRoom.session
	local arena = built.arena
	EnemyService.setGroundFallback(session.depth, built.roomCenter.Y)

	-- A restart rebuilds the set piece rather than stacking a second one on it. Longarms go too: a
	-- guard from the previous attempt is chained to this chamber and would join the new fight, which is
	-- an encounter nobody authored. Bodies elsewhere in the laboratory are untouched by everything else
	-- here, but these two kinds are the encounter, so both are cleared.
	EnemyService.clearKindAtDepth(session.depth, "GrubQueen")
	EnemyService.clearKindAtDepth(session.depth, "Longarm")

	local queen = EnemyService.spawnQueen(session.depth, arena.queenPosition, armedFamilyId, session.globalDepth * 7919)
	if queen == nil then
		return false, "The Queen refused to seat in the arena."
	end

	-- HER DEATH IS THE ENCOUNTER'S STATE CHANGE, announced exactly as `BossEncounterService` announces
	-- it on a real floor. Nothing in the laboratory gates on it — there is no ladder to unlock here —
	-- but the client-side answer to "she died" is one of the things worth testing in this room.
	local defeated = false
	queen.onDeath = function()
		if defeated then
			return
		end
		defeated = true
		Remotes.get("RunEvent"):FireAllClients("bossDefeated", {
			depth = session.depth,
			position = arena.queenPosition,
		})
	end

	local guards = 0
	for index, guardPosition in arena.guardPositions do
		local guard = EnemyService.spawnLongarm(
			session.depth,
			guardPosition,
			armedFamilyId,
			session.globalDepth * 104_729 + index,
			arena.center,
			arena.guardLeashRadius
		)
		if guard ~= nil then
			guards += 1
		end
	end
	return true, string.format("Grub Queen encounter started with %d chained guards.", guards)
end

local function spawnLurker(): boolean
	local built = runtime
	if built == nil or #built.lurkerSites == 0 then
		return false
	end
	clearLurker()
	local first = built.lurkerSites[1]
	local protocol = AshamedLurkerVisualProtocol
	local proxy = Instance.new("Part")
	proxy.Name = "AshamedLurker_Test"
	proxy.Size = Vector3.one * 0.5
	proxy.CFrame = first.cframe
	proxy.Transparency = 1
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.CastShadow = false
	proxy:SetAttribute(protocol.attributes.trapSide, first.trapSide)
	proxy:SetAttribute(protocol.attributes.doorWidth, first.doorWidth)
	proxy:SetAttribute(protocol.attributes.doorHeight, first.doorHeight)
	proxy:SetAttribute(protocol.attributes.visualSeed, Config.DevTestRoom.lurker.visualSeed)
	proxy:SetAttribute(protocol.attributes.site, 1)
	proxy:SetAttribute(protocol.attributes.depth, Config.DevTestRoom.session.depth)
	proxy:SetAttribute(protocol.attributes.familyId, Config.DevTestRoom.session.familyId)
	proxy:SetAttribute(protocol.attributes.stateStartedAt, Workspace:GetServerTimeNow())
	proxy:SetAttribute(protocol.attributes.state, protocol.states.dormant)
	proxy.Parent = built.dynamicFolder
	CollectionService:AddTag(proxy, protocol.tag)
	AshamedLurkerService.registerFloor(Config.DevTestRoom.session.depth, {
		{
			proxy = proxy,
			sites = built.lurkerSites,
			depth = Config.DevTestRoom.session.depth,
		},
	})
	lurkerProxy = proxy
	return true
end

local function spawnWarden(familyId: string): boolean
	local built = runtime
	if built == nil then
		return false
	end
	clearWarden()
	warden = StoneWardenService.spawnEncounter({
		spawnCFrame = built.wardenSpawnCFrame,
		waxGround = built.wardenWaxPosition,
		-- The lab owns one Heavy Crown and it is the guaranteed Warden counter. The production
		-- encounter's opening collapse must not spend that counter before the Warden can walk under it.
		collapsePositions = {},
		parent = built.dynamicFolder,
		depth = Config.DevTestRoom.session.depth,
		familyId = familyId,
	})
	return true
end

local function resetCandle(player: Player)
	local built = runtime
	local state = PlayerState.get(player.UserId)
	if built == nil or state == nil then
		return
	end
	state.wax.current = state.wax.max
	state.isLit = true
	state.snuffedAt = nil
	state.lightSuppressedUntil = 0
	state.lightSuppressionMultiplier = 1
	state.flareEndsAt = 0
	state.isCupping = false
	state.alive = true
	state.finished = false
	state.freeToolCharges.Flare = Config.DevTestRoom.session.freeToolCharges
	state.freeToolCharges.Decoy = Config.DevTestRoom.session.freeToolCharges
	state.dynamiteCharges = Config.DevTestRoom.session.dynamiteCharges
	CharacterService.teleport(player.UserId, built.candleSpawnPosition)
	MovementService.refresh(player.UserId)
	MovementSanityService.markAuthorized(player.UserId, built.candleSpawnPosition)
end

local function teardownWorld()
	clearEnemies()
	clearHazard()
	-- THE GROUND FALLBACK IS NOT CLEARED HERE, AND MUST NOT BE.
	--
	-- This function clears the room's CONTENTS. The room itself is built once in `init` and lives for
	-- the whole server, so the flat floor height every wick-pack body seats against outlives every
	-- session in it. Clearing it here looked tidy and broke every pack spawn immediately: `enterPlayer`
	-- calls this on the FIRST player entering an empty lab, to sweep leftovers from the last session —
	-- so the fallback was registered at init and then wiped before anybody could press a button, and
	-- every grub, gnawer and Longarm reported "no clear ground at the marker" forever after.
	--
	-- Leaving it registered is safe because the laboratory's depth is a virtual one chosen to sit
	-- outside every generated run (Config/DevTestRoom.session.depth), so no real floor can ever ask for
	-- it and be handed a laboratory's floor height.
end

local function detachPlayer(playerId: Types.PlayerId, player: Player?): boolean
	if not activePlayers[playerId] then
		-- This is intentionally idempotent. PlayerRemoving calls it again as a final fail-closed guard
		-- in case a preceding cleanup path was interrupted.
		DevTestSessionRegistry.release(playerId)
		actionBusy[playerId] = nil
		nextControlAt[playerId] = nil
		return false
	end

	-- Authority is removed before any Instance/service cleanup. Nothing below this line, including a
	-- failed callback, can leave infinite-health protection attached to a non-lab player.
	DevTestSessionRegistry.release(playerId)
	activePlayers[playerId] = nil
	actionBusy[playerId] = nil
	nextControlAt[playerId] = nil
	PlayerState.remove(playerId)

	if player ~= nil then
		runCleanup("body", function()
			CharacterService.despawn(player)
		end)
	end
	runCleanup("movement", function()
		-- Dropped before the sanity sample, and unconditionally: the sprint is a laboratory-only speed,
		-- so a player who leaves mid-hold must not carry it back to the Landing whatever else fails here.
		MovementService.setDevSuperSprint(playerId, false)
		MovementSanityService.clear(playerId)
	end)
	runCleanup("decoys", function()
		ToolService.clearPlayerDecoys(playerId)
	end)
	runCleanup("drip trail", function()
		DripTrailService.clear(playerId)
	end)
	runCleanup("noise", function()
		NoiseService.clear(playerId)
	end)
	runCleanup("Lurker gaze", function()
		AshamedLurkerService.clearPlayer(playerId)
	end)
	runCleanup("threat targets", function()
		ThreatService.updateTestTargets(Config.DevTestRoom.session.scopeId, activePlayers)
	end)
	if not hasActivePlayers() then
		nextSharedRebuildAt = 0
		runCleanup("enemies", function()
			clearEnemies()
		end)
		runCleanup("hazard", function()
			clearHazard()
		end)
	end
	return true
end

local function restoreLobbyAsync(player: Player, position: Vector3)
	-- LoadCharacter yields. Keeping it off the fixed Heartbeat driver prevents one avatar fetch from
	-- stalling all expedition, wax, threat, and movement ticks when the lab is force-closed.
	task.spawn(function()
		if player.Parent ~= Players then
			return
		end
		local spawned, spawnError = pcall(CharacterService.spawnLobby, player, position)
		if player.Parent ~= Players then
			return
		end
		if not spawned or CharacterService.lobbyBodyPosition(player.UserId) == nil then
			local detail = if not spawned then spawnError else "spawn completed without a lobby body"
			warn(string.format("[WICK] failed to restore lobby body after developer test: %s", tostring(detail)))
			sendState(player, "The lab closed, but your lobby body could not be restored. Rejoin the server.")
		end
	end)
end

local function leavePlayer(player: Player, respawnInLobby: boolean, message: string?)
	local playerId = player.UserId
	if not detachPlayer(playerId, player) then
		return
	end
	if player.Parent ~= Players then
		return
	end
	runCleanup("client state", function()
		sendState(player, message or "Returned to the Landing.")
	end)
	if respawnInLobby then
		local built = runtime
		local position = if built ~= nil then built.lobbyReturnPosition else Config.LobbyRoom.origin
		restoreLobbyAsync(player, position)
	end
end

local function enterPlayer(player: Player)
	local built = runtime
	if built == nil or activePlayers[player.UserId] then
		return
	end
	local wasEmpty = not hasActivePlayers()
	activePlayers[player.UserId] = true
	ThreatService.updateTestTargets(Config.DevTestRoom.session.scopeId, activePlayers)
	DevTestSessionRegistry.protect(player.UserId)
	local state = PlayerState.reset(player.UserId, false, 1)
	state.depth = Config.DevTestRoom.session.depth
	state.position = built.candleSpawnPosition
	state.freeToolCharges.Flare = Config.DevTestRoom.session.freeToolCharges
	state.freeToolCharges.Decoy = Config.DevTestRoom.session.freeToolCharges
	state.dynamiteCharges = Config.DevTestRoom.session.dynamiteCharges
	CharacterService.spawn(player, built.candleSpawnPosition)
	MovementService.refresh(player.UserId)
	MovementSanityService.markAuthorized(player.UserId, built.candleSpawnPosition)
	if wasEmpty then
		nextContainmentCheckAt = 0
		teardownWorld()
		resetHazard()
	end
	sendState(player, "Test lab active: infinite wax, Flare and Decoy charges enabled.")
end

local function doorwayAvailable(player: Player): (boolean, string?)
	local built = runtime
	if built == nil then
		return false, "The test room is unavailable."
	end
	if activePlayers[player.UserId] then
		return false, "You are already in the test room."
	end
	local lobbyClosed = lobbyClosedProvider
	if lobbyClosed ~= nil and lobbyClosed() then
		return false, "Wait for the current expedition to finish."
	end
	if Interfaces.Party.forPlayer(player.UserId) ~= nil then
		return false, "Leave the elevator party before entering the test room."
	end
	local terminal = built.accessPrompt.Parent
	if terminal == nil or not terminal:IsA("BasePart") then
		return false, "The test terminal is unavailable."
	end
	if
		not DevTestRoomRules.isWithinRange(
			CharacterService.lobbyBodyPosition(player.UserId),
			terminal.Position,
			Config.DevTestRoom.access.promptDistance + 2
		)
	then
		return false, "Stand at the test terminal to enter the code."
	end
	return true, nil
end

local function handleControl(player: Player, actionId: string)
	local built = runtime
	if built == nil or not activePlayers[player.UserId] then
		return
	end
	local prompt = built.actionPrompts[actionId]
	local promptPart = if prompt ~= nil then prompt.Parent else nil
	if promptPart == nil or not promptPart:IsA("BasePart") then
		return
	end
	if
		not DevTestRoomRules.isWithinRange(
			CharacterService.basePosition(player.UserId),
			promptPart.Position,
			Config.DevTestRoom.session.controlValidationDistance
		)
	then
		return
	end
	if actionId ~= "return:lobby" and not DevDiagnosticsService.isEnabled(player.UserId) then
		sendStatus(player, "Developer access was disabled. Return and enter 0610 again.")
		return
	end
	if actionId ~= "return:lobby" and not allowControl(player.UserId, actionId) then
		return
	end

	-- ARMING A CAVE SPAWNS NOTHING. It is the mode every button below reads for its dressing, so it
	-- reports what is now armed rather than what appeared.
	local caveId = CAVE_BY_ACTION[actionId]
	if caveId ~= nil then
		armedFamilyId = caveId
		sendStatus(
			player,
			string.format("%s armed. Spawns now wear its presentation.", CaveFamilyRules.resolve(caveId).displayName)
		)
		return
	end
	-- THE ARMED CAVE'S OWN CREATURE. One button instead of the three this replaced; which row it
	-- produces follows whatever is armed, and the status line names it so the generic label costs
	-- nothing.
	if actionId == "spawn:Signature" then
		local signature = SIGNATURE_BY_FAMILY[armedFamilyId]
		if signature == nil then
			sendStatus(player, "No signature creature for the armed cave.")
		elseif spawnOrdinary(signature) then
			sendStatus(player, "Spawned " .. Config.Threats.definitions[signature].displayName .. ".")
		else
			sendStatus(player, "Signature spawn failed — no clear ground at the marker.")
		end
		return
	end
	if actionId == "spawn:Warden" then
		spawnWarden(armedFamilyId)
		sendStatus(player, CaveFamilyRules.wardenDisplayName(armedFamilyId) .. " encounter reset.")
		return
	end
	local threatId = THREAT_BY_ACTION[actionId]
	if threatId ~= nil then
		if spawnOrdinary(threatId) then
			sendStatus(player, "Spawned " .. Config.Threats.definitions[threatId].displayName .. ".")
		else
			-- No cap any more, so a failure here is a real placement failure and says so.
			sendStatus(player, "Spawn failed — no clear ground at the marker.")
		end
		return
	end
	local packId = PACK_BY_ACTION[actionId]
	if packId ~= nil then
		if spawnPackEnemy(packId) then
			sendStatus(player, "Spawned " .. (PACK_DISPLAY_NAME[packId] or packId) .. ".")
		else
			sendStatus(player, "Spawn failed — no clear ground at the marker.")
		end
		return
	end
	if actionId == "boss:start" then
		local started, message = startBossEncounter()
		sendStatus(player, if started then message else "Encounter failed to start — " .. message)
	elseif actionId == "spawn:AshamedLurker" then
		spawnLurker()
		sendStatus(player, "Ashamed Lurker reset across both test arches.")
	elseif actionId == "remove:all" then
		local removed = clearEnemies()
		sendStatus(player, string.format("Removed %d test enemies.", removed))
	elseif actionId == "reset:hazards" then
		sendStatus(player, if resetHazard() then "Heavy Crown reset." else "Crown reset failed.")
	elseif actionId == "trigger:hazard" then
		local triggered = DripstoneService.triggerNearest(
			Config.DevTestRoom.session.depth,
			built.hazardImpactPosition,
			Config.DevTestRoom.session.crownTriggerRadius
		)
		sendStatus(player, if triggered then "Heavy Crown warning triggered." else "Reset the Crown first.")
	elseif actionId == "warden:wake" then
		local current = warden
		if current == nil then
			sendStatus(player, "Spawn a Warden first.")
		else
			sendStatus(player, "Warden emergence started.")
			-- Emergence deliberately yields across its animation. Run it independently so the physical
			-- console confirms the press immediately and does not hold this player's action guard.
			task.spawn(function()
				local activated, activationError = pcall(current.activate)
				if not activated then
					warn(string.format("[WICK] developer Warden emergence failed: %s", tostring(activationError)))
				end
			end)
		end
	elseif actionId == "warden:stun" then
		local current = warden
		if current == nil or current.state() ~= "ACTIVE" then
			sendStatus(player, "Wake the Warden before applying a direct stun.")
		else
			current.stun(Config.DevTestRoom.session.wardenStunSeconds)
			sendStatus(player, "Warden stunned.")
		end
	elseif actionId == "reset:candle" then
		resetCandle(player)
		sendStatus(player, "Candle restored and returned to the start marker.")
	elseif actionId == "grant:dynamite" then
		-- The same restock RESET CANDLE performs, without the teleport. A tester mid-way through a
		-- Warden or Crown setup should not have to give up their position to refill a stack.
		local state = PlayerState.get(player.UserId)
		if state == nil then
			sendStatus(player, "Your lab candle state is unavailable. Use RESET CANDLE.")
		else
			local charges = Config.DevTestRoom.session.dynamiteCharges
			state.dynamiteCharges = charges
			sendStatus(player, string.format("Dynamite restocked to %d sticks.", charges))
		end
	elseif actionId == "emit:noise" then
		-- Keep the lure away from the Listener's spawn/home point so its full investigate walk is
		-- visible across the room instead of immediately completing at distance zero.
		NoiseService.emit("MineBreak", built.noisePosition, player.UserId)
		sendStatus(player, "Loud seam-break noise emitted at the noise marker.")
	elseif actionId == "return:lobby" then
		leavePlayer(player, true, "Returned to the Landing.")
	end
end

-- Every volume a lab session is allowed to stand in: the main chamber, the corridor east out of it,
-- and the boss arena at the far end. Rebuilt per check rather than cached because the room is built
-- once and this runs twice a second — a stale box would be the kind of bug that closes the lab on
-- somebody mid-fight.
local function containmentBoxes(built: Runtime): { DevTestRoomRules.RoomBox }
	local arena = built.arena
	return {
		{ center = built.roomCenter, size = Config.DevTestRoom.room.interiorSize },
		{ center = arena.corridorCenter, size = arena.corridorSize },
		{ center = arena.center, size = arena.interiorSize },
	}
end

local function invalidSessionReason(player: Player, lobbyClosed: boolean): string?
	local playerId = player.UserId
	local built = runtime
	if lobbyClosed then
		return "The lab closed because an expedition started."
	end
	if built == nil then
		return "The lab closed because its room state became unavailable."
	end
	if not DevTestSessionRegistry.isProtected(playerId) then
		return "The lab closed because its protection state became invalid."
	end
	if not DevDiagnosticsService.isEnabled(playerId) then
		return "The lab closed because developer access was disabled."
	end
	if Interfaces.Party.forPlayer(playerId) ~= nil then
		return "The lab closed because you joined an elevator party."
	end
	local state = PlayerState.get(playerId)
	if
		state == nil
		or state.depth ~= Config.DevTestRoom.session.depth
		or not state.alive
		or state.finished
		or not CharacterService.hasIntactBody(playerId)
	then
		return "The lab reset after its isolated candle state became invalid."
	end
	if
		not DevTestRoomRules.isInsideAnyRoom(
			CharacterService.basePosition(playerId),
			containmentBoxes(built),
			Config.DevTestRoom.session.containmentMargin
		)
	then
		return "The lab closed because your candle left the test chamber."
	end
	return nil
end

function DevTestRoomService.init(isLobbyClosed: LobbyClosedProvider)
	if not Config.DevTestRoom.enabled then
		return
	end
	lobbyClosedProvider = isLobbyClosed
	runtime = DevTestRoomBuilder.build()
	buildThreatContext()
	local built = runtime :: Runtime
	ToolService.setDevTestGeometry(built.roomModel, built.groundPart)
	-- Dynamite solves its own throw and needs the same opt-in: without it the lab has no Terrain and no
	-- WickFloors folder for the arc to cast against, and every throw is refused as InvalidTarget.
	DynamiteService.setDevTestGeometry(built.roomModel, built.groundPart)

	-- THE ARENA'S START BUTTON JOINS THE CONSOLE'S OWN ACTION TABLE. It is not on a board — it hangs on
	-- the arena's entry wall a corridor away — but routing it through `handleControl` means it inherits
	-- every guard the wall buttons have: a live session, developer access, the rebuild cooldown, and the
	-- server's own distance check against the prompt's part.
	if built.actionPrompts["boss:start"] ~= nil then
		error("Duplicate DevTestRoom action id: boss:start")
	end
	built.actionPrompts["boss:start"] = built.arena.startPrompt

	built.accessPrompt.Triggered:Connect(function(player: Player)
		local available, reason = doorwayAvailable(player)
		if not available then
			sendStatus(player, reason or "The test room is unavailable.")
			return
		end
		remote():FireClient(player, "keypad", {})
	end)
	for actionId, controlPrompt in built.actionPrompts do
		controlPrompt.Triggered:Connect(function(player: Player)
			if actionBusy[player.UserId] then
				return
			end
			actionBusy[player.UserId] = true
			local ok, message = pcall(handleControl, player, actionId)
			actionBusy[player.UserId] = nil
			if not ok then
				warn(string.format("[WICK] developer test action %q failed: %s", actionId, tostring(message)))
				sendStatus(player, "That test action failed; check the server log.")
			end
		end)
	end

	remote().OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
		if not DevTestRoomRules.isRemoteAction(action) or not RequestGuard.allow(player, "DevTestRoom") then
			return
		end
		if action == "sync" then
			sendState(player)
			return
		end
		-- THE REMOVE-ALL HOTKEY. Requires a live laboratory session for this player and nothing else —
		-- no proximity, because the entire reason it is a key rather than a wall button is being able to
		-- empty the room from wherever you are standing when it fills up. It shares the board's own rate
		-- limiter so a held key cannot spam a rebuild.
		if action == "clear" then
			if not activePlayers[player.UserId] then
				return
			end
			if not allowControl(player.UserId, "remove:hotkey") then
				return
			end
			local removed = clearEnemies()
			sendStatus(player, string.format("Removed %d test enemies.", removed))
			return
		end
		-- THE HELD SUPER-SPRINT KEY. Same trust boundary as the hotkey above and nothing more: a live
		-- laboratory session, and a speed that only exists while this player has one. Deliberately NOT
		-- rate-limited beyond the shared remote guard — it is one message per key press and one per
		-- release, and dropping a release because a bucket was empty is exactly the failure that would
		-- leave somebody sprinting.
		if action == "sprint" then
			MovementService.setDevSuperSprint(player.UserId, activePlayers[player.UserId] == true and value == true)
			return
		end
		local available, reason = doorwayAvailable(player)
		if not available then
			sendStatus(player, reason or "The test room is unavailable.")
			return
		end
		if not DevTestRoomRules.isValidCode(value, Config.Diagnostics.unlockCode) then
			DevDiagnosticsService.tryUnlock(player, value)
			sendStatus(player, "Invalid developer code.")
			return
		end
		local accepted, unlockMessage = DevDiagnosticsService.tryUnlock(player, value)
		if not accepted then
			sendStatus(player, unlockMessage)
			return
		end
		local entered, message = pcall(enterPlayer, player)
		if not entered then
			warn(string.format("[WICK] developer test entry failed: %s", tostring(message)))
			if activePlayers[player.UserId] then
				leavePlayer(player, true, "The test room could not start. You were returned to the Landing.")
			else
				DevTestSessionRegistry.release(player.UserId)
				sendStatus(player, "The test room could not start. Check the server log.")
			end
		end
	end)
end

function DevTestRoomService.onPlayerRemoving(player: Player)
	local playerId = player.UserId
	local wasActive = activePlayers[playerId] == true
	local ok, leaveError = pcall(leavePlayer, player, false)
	-- Final authority cleanup is deliberately repeated outside the protected call.
	DevTestSessionRegistry.release(playerId)
	activePlayers[playerId] = nil
	actionBusy[player.UserId] = nil
	nextControlAt[playerId] = nil
	if not ok and wasActive then
		PlayerState.remove(playerId)
		runCleanup("departing threat targets", function()
			ThreatService.updateTestTargets(Config.DevTestRoom.session.scopeId, activePlayers)
		end)
		if not hasActivePlayers() then
			runCleanup("departing enemies", function()
				clearEnemies()
			end)
			runCleanup("departing hazard", function()
				clearHazard()
			end)
		end
	end
	if not ok then
		warn(string.format("[WICK] developer test departure cleanup failed: %s", tostring(leaveError)))
	end
end

function DevTestRoomService.tick()
	if not hasActivePlayers() then
		return
	end
	local now = os.clock()
	if now < nextContainmentCheckAt then
		return
	end
	nextContainmentCheckAt = now + Config.DevTestRoom.session.containmentCheckSeconds
	local lobbyClosed = lobbyClosedProvider
	local isLobbyClosed = lobbyClosed ~= nil and lobbyClosed()
	local rejected: { { player: Player, message: string } } = {}
	local missing: { Types.PlayerId } = {}
	for playerId in activePlayers do
		local player = Players:GetPlayerByUserId(playerId)
		if player == nil then
			table.insert(missing, playerId)
			continue
		end
		local reason = invalidSessionReason(player, isLobbyClosed)
		if reason ~= nil then
			table.insert(rejected, { player = player, message = reason })
		end
	end
	for _, playerId in missing do
		detachPlayer(playerId, nil)
	end
	for _, record in rejected do
		leavePlayer(record.player, true, record.message)
	end
end

return DevTestRoomService

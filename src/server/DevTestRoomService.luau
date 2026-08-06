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
local ThreatService = require(script.Parent.ThreatService)
local AshamedLurkerService = require(script.Parent.AshamedLurkerService)
local DripstoneService = require(script.Parent.DripstoneService)
local StoneWardenService = require(script.Parent.StoneWardenService)
local NoiseService = require(script.Parent.NoiseService)
local DripTrailService = require(script.Parent.DripTrailService)
local SignalBellService = require(script.Parent.SignalBellService)
local DevDiagnosticsService = require(script.Parent.DevDiagnosticsService)
local DevTestSessionRegistry = require(script.Parent.DevTestSessionRegistry)
local DevTestRoomBuilder = require(script.Parent.DevTestRoomBuilder)
local RequestGuard = require(script.Parent.RequestGuard)

local DevTestRoomService = {}

type Runtime = DevTestRoomBuilder.Runtime
type WardenHandle = StoneWardenService.EncounterHandle
type LobbyClosedProvider = () -> boolean

local THREAT_BY_ACTION: { [string]: Types.ThreatId } = {
	["spawn:DarkCrawler"] = "DarkCrawler",
	["spawn:Moth"] = "Moth",
	["spawn:VoidFly"] = "VoidFly",
	["spawn:Listener"] = "Listener",
	["spawn:Knotwalker"] = "Knotwalker",
	["spawn:Calver"] = "Calver",
}

local WARDEN_FAMILY_BY_ACTION: { [string]: string } = {
	["spawn:StoneWarden"] = "STONE",
	["spawn:MossWarden"] = "MOSS",
	["spawn:IceWarden"] = "ICE",
}

local REBUILD_ACTIONS: { [string]: boolean } = {
	["spawn:AshamedLurker"] = true,
	["spawn:StoneWarden"] = true,
	["spawn:MossWarden"] = true,
	["spawn:IceWarden"] = true,
	["remove:all"] = true,
	["reset:hazards"] = true,
}

local SIGNATURE_FAMILY_BY_THREAT: { [Types.ThreatId]: string } = {
	Listener = "STONE",
	Knotwalker = "MOSS",
	Calver = "ICE",
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
		echoGate = nil,
		lurkers = {},
		warden = nil,
		deposits = {},
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
	-- Signature rows wear the cave presentation in which they actually ship. Shared threats use the
	-- lab's Stone baseline; family-specific Warden controls cover the three set-piece variants.
	spawnPlan.familyId = SIGNATURE_FAMILY_BY_THREAT[threatId] or Config.DevTestRoom.session.familyId
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
	CharacterService.teleport(player.UserId, built.candleSpawnPosition)
	MovementService.refresh(player.UserId)
	MovementSanityService.markAuthorized(player.UserId, built.candleSpawnPosition)
end

local function teardownWorld()
	clearEnemies()
	clearHazard()
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
	runCleanup("signal bell", function()
		SignalBellService.clear(playerId)
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

	local threatId = THREAT_BY_ACTION[actionId]
	if threatId ~= nil then
		if spawnOrdinary(threatId) then
			sendStatus(player, "Spawned " .. Config.Threats.definitions[threatId].displayName .. ".")
		else
			sendStatus(player, "Threat cap reached or spawn failed. Use REMOVE ALL.")
		end
		return
	end
	local familyId = WARDEN_FAMILY_BY_ACTION[actionId]
	if familyId ~= nil then
		spawnWarden(familyId)
		sendStatus(player, CaveFamilyRules.wardenDisplayName(familyId) .. " encounter reset.")
		return
	end
	if actionId == "spawn:AshamedLurker" then
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
	elseif actionId == "emit:noise" then
		-- Keep the lure away from the Listener's spawn/home point so its full investigate walk is
		-- visible across the room instead of immediately completing at distance zero.
		NoiseService.emit("MineBreak", built.noisePosition, player.UserId)
		sendStatus(player, "Loud seam-break noise emitted at the noise marker.")
	elseif actionId == "return:lobby" then
		leavePlayer(player, true, "Returned to the Landing.")
	end
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
		not DevTestRoomRules.isInsideRoom(
			CharacterService.basePosition(playerId),
			built.roomCenter,
			Config.DevTestRoom.room.interiorSize,
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

--!strict
-- Server authority for the three tools. Generic over ToolDef rows: behaviour is selected by the
-- row's data flags (held / burst / throw params), never by tool name. Owns decoys
-- and flare-burst lifetimes; exposes their light sources for threat perception.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local ToolRules = require(ReplicatedStorage.Shared.Logic.ToolRules)
local CandleModifiers = require(ReplicatedStorage.Shared.Logic.CandleModifiers)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local HazardService = require(script.Parent.HazardService)
local MovementService = require(script.Parent.MovementService)
local RequestGuard = require(script.Parent.RequestGuard)
local ActionFeedbackService = require(script.Parent.ActionFeedbackService)
local DevTestSessionRegistry = require(script.Parent.DevTestSessionRegistry)

local ToolService = {}

type Decoy = {
	ownerId: Types.PlayerId,
	position: Vector3,
	endsAt: number,
	attractsDrawn: boolean,
	intensity: number,
	range: number,
	model: Model,
}

type DecoyLanding = {
	surface: CFrame,
	position: Vector3,
}

local decoys: { Decoy } = {}
local decoyFolder: Folder? = nil
local decoySequence = 0
local devTestGeometry: Instance? = nil
local devTestGround: BasePart? = nil

local function obstructionRaycastParams(): RaycastParams?
	local floors = Workspace:FindFirstChild("WickFloors")
	local devGeometry = devTestGeometry
	if floors == nil and (devGeometry == nil or devGeometry.Parent == nil) then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local roots: { Instance } = { Workspace.Terrain }
	if floors ~= nil then
		table.insert(roots, floors)
	end
	if devGeometry ~= nil and devGeometry.Parent ~= nil then
		table.insert(roots, devGeometry)
	end
	params.FilterDescendantsInstances = roots
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

local function groundRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	-- Gameplay floor is Terrain. Keeping props out prevents casts from balancing on a brazier,
	-- boulder, or descent fixture merely because its top face points upward.
	local roots: { Instance } = { Workspace.Terrain }
	local devGround = devTestGround
	if devGround ~= nil and devGround.Parent ~= nil then
		table.insert(roots, devGround)
	end
	params.FilterDescendantsInstances = roots
	params.RespectCanCollide = true
	params.IgnoreWater = true
	return params
end

local function surfaceFrame(position: Vector3, normal: Vector3, offset: number): CFrame
	local up = normal.Unit
	local tangentSeed = if math.abs(up:Dot(Vector3.xAxis)) < 0.95 then Vector3.xAxis else Vector3.zAxis
	local right = (tangentSeed - up * tangentSeed:Dot(up)).Unit
	local back = right:Cross(up)
	return CFrame.fromMatrix(position + up * math.max(offset, 0), right, up, back)
end

local function legalTerrainLanding(
	state: Types.PlayerRunState,
	origin: Vector3,
	def: Types.ToolDef,
	result: RaycastResult
): DecoyLanding?
	local placement = def.throwPlacement
	local visual = def.decoyVisual
	local devGround = devTestGround
	local allowedDevSurface = DevTestSessionRegistry.isProtected(state.playerId)
		and devGround ~= nil
		and result.Instance == devGround
	if
		placement == nil
		or visual == nil
		or (result.Instance ~= Workspace.Terrain and not allowedDevSurface)
		or not ToolRules.decoySurfaceAllowed(result.Normal, placement.maxGroundSlopeDegrees)
		or result.Position.Y - origin.Y > placement.maximumGroundRise
	then
		return nil
	end
	local surface = surfaceFrame(result.Position, result.Normal, placement.surfaceOffset)
	local position = surface.Position
	-- A burning distraction candle cannot sit beneath a Sump surface. Rejecting both wading and
	-- lethal exposure keeps its flame presentation and authoritative light source consistent.
	if HazardService.exposureFor(state.depth, position, visual.bodyHeight).water ~= "None" then
		return nil
	end
	return {
		surface = surface,
		position = position,
	}
end

-- Opt one isolated physical floor into the ordinary Decoy solver. A production candle cannot use
-- the part because the landing check above additionally requires a protected test session.
function ToolService.setDevTestGeometry(geometry: Instance?, ground: BasePart?)
	devTestGeometry = geometry
	devTestGround = ground
end

local function resolveDecoyLanding(
	state: Types.PlayerRunState,
	origin: Vector3,
	def: Types.ToolDef,
	aim: Vector3
): DecoyLanding?
	local throwRange = def.throwRange
	local placement = def.throwPlacement
	if throwRange == nil or placement == nil or def.decoyVisual == nil then
		return nil
	end
	local obstructionParams = obstructionRaycastParams()
	if obstructionParams == nil then
		return nil
	end
	local groundParams = groundRaycastParams()

	local horizontal = ToolRules.throwHorizontalPoint(
		origin,
		aim,
		throwRange,
		nil,
		placement.obstructionInset,
		placement.minimumDistance
	)
	if horizontal == nil then
		return nil
	end

	-- Trace a real throw rather than a low straight ray. The latter collided with normal rolling
	-- cave ground and made the decoy appear unreliable as the player crossed a room.
	local arcStart = origin + Vector3.yAxis * placement.throwStartHeight
	local arcEnd = horizontal + Vector3.yAxis * placement.throwStartHeight
	local previous = arcStart
	for step = 1, math.max(1, math.floor(placement.throwProbeSegments)) do
		local point = ToolRules.throwArcPoint(
			arcStart,
			arcEnd,
			placement.throwArcHeight,
			step / math.max(1, math.floor(placement.throwProbeSegments))
		)
		local obstruction = Workspace:Raycast(previous, point - previous, obstructionParams)
		if obstruction ~= nil then
			local directLanding = legalTerrainLanding(state, origin, def, obstruction)
			if directLanding ~= nil then
				local directDistance =
					Vector3.new(obstruction.Position.X - origin.X, 0, obstruction.Position.Z - origin.Z).Magnitude
				if directDistance >= placement.minimumDistance then
					return directLanding
				end
			end
			local obstructionDistance =
				Vector3.new(obstruction.Position.X - origin.X, 0, obstruction.Position.Z - origin.Z).Magnitude
			horizontal = ToolRules.throwHorizontalPoint(
				origin,
				aim,
				throwRange,
				obstructionDistance,
				placement.obstructionInset,
				placement.minimumDistance
			)
			if horizontal == nil then
				return nil
			end
			break
		end
		previous = point
	end

	-- A deep floor trough can put this probe inside the sealed roof. Skip only downward-facing
	-- roof undersides; a steep upward/vertical formation remains an invalid landing instead of
	-- silently probing through it.
	local probeOrigin = horizontal + Vector3.new(0, placement.groundProbeHeight, 0)
	local probeRemaining = placement.groundProbeHeight + placement.groundProbeDepth
	local ground: RaycastResult? = nil
	for _ = 1, math.max(1, math.floor(placement.groundProbeMaxHits)) do
		local result = Workspace:Raycast(probeOrigin, Vector3.new(0, -probeRemaining, 0), groundParams)
		if result == nil then
			break
		end
		if ToolRules.decoySurfaceAllowed(result.Normal, placement.maxGroundSlopeDegrees) then
			ground = result
			break
		end
		if result.Normal.Y >= 0 then
			return nil
		end
		local advance = math.max(placement.groundProbeAdvance, 0)
		local traveled = math.max(probeOrigin.Y - result.Position.Y, 0) + advance
		probeRemaining -= traveled
		if probeRemaining <= 0 then
			break
		end
		probeOrigin = result.Position - Vector3.new(0, advance, 0)
	end
	if ground == nil then
		return nil
	end
	return legalTerrainLanding(state, origin, def, ground)
end

local function ensureDecoyFolder(): Folder
	local current = decoyFolder
	if current ~= nil and current.Parent ~= nil then
		return current
	end
	local folder = Instance.new("Folder")
	folder.Name = "WickDecoys"
	folder.Parent = Workspace
	decoyFolder = folder
	return folder
end

local function visualPart(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function buildDecoyModel(playerId: Types.PlayerId, def: Types.ToolDef, landing: DecoyLanding): (Model, Vector3)
	local visual = def.decoyVisual
	if visual == nil then
		error("Decoy tool definition is missing decoyVisual")
	end
	decoySequence += 1

	local model = Instance.new("Model")
	model.Name = ("Decoy_%d_%d"):format(playerId, decoySequence)

	local bodyDiameter = visual.bodyRadius * 2
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local bodyFrame = landing.surface * CFrame.new(0, visual.bodyHeight / 2, 0)
	local body = visualPart(
		model,
		"Body",
		Vector3.new(visual.bodyHeight, bodyDiameter, bodyDiameter),
		bodyFrame * upright,
		visual.bodyColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)

	local rimRadius = visual.bodyRadius * visual.rimRadiusMultiplier
	local rimDiameter = rimRadius * 2
	local rimFrame = landing.surface * CFrame.new(0, visual.bodyHeight - visual.rimHeight / 2, 0)
	visualPart(
		model,
		"Rim",
		Vector3.new(visual.rimHeight, rimDiameter, rimDiameter),
		rimFrame * upright,
		visual.rimColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)

	local wickDiameter = visual.wickRadius * 2
	local wickFrame = landing.surface * CFrame.new(0, visual.bodyHeight + visual.wickHeight / 2, 0)
	visualPart(
		model,
		"Wick",
		Vector3.new(visual.wickHeight, wickDiameter, wickDiameter),
		wickFrame * upright,
		visual.wickColor,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)

	local flameFrame = landing.surface * CFrame.new(0, visual.bodyHeight + visual.wickHeight + visual.flameSize / 2, 0)
	local flameCenter = flameFrame.Position
	local flame = visualPart(
		model,
		"Flame",
		Vector3.one * visual.flameSize,
		flameFrame,
		visual.flameColor,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	local light = Instance.new("PointLight")
	light.Name = "DecoyLight"
	light.Color = visual.lightColor
	light.Brightness = visual.lightBrightness
	light.Range = visual.lightRange
	light.Shadows = false
	light.Parent = flame

	model.PrimaryPart = body
	model.Parent = ensureDecoyFolder()
	return model, flameCenter
end

local function spawnDecoy(state: Types.PlayerRunState, def: Types.ToolDef, landing: DecoyLanding, now: number)
	local candle = CandleModifiers.profile(state.candle, state.isCupping)
	local model, lightPosition = buildDecoyModel(state.playerId, def, landing)

	table.insert(decoys, {
		ownerId = state.playerId,
		position = lightPosition,
		endsAt = now + def.duration * state.modifiers.decoyDurationMultiplier,
		attractsDrawn = candle.attractsDrawn, -- a decoy is made of your wax and behaves like your flame
		intensity = def.decoyIntensity :: number,
		range = def.decoyRange :: number,
		model = model,
	})
end

local function activate(
	player: Player,
	state: Types.PlayerRunState,
	def: Types.ToolDef,
	decoyLanding: DecoyLanding?,
	now: number
)
	state.nextToolUse[def.id] = now + def.cooldown * state.modifiers.toolCooldownMultiplier

	if def.held then
		state.isCupping = not state.isCupping
		if state.isCupping then
			state.flareEndsAt = 0
		end
		MovementService.refresh(player.UserId)
		return
	end

	-- Instant effects: charge, then apply whatever physical params the row declares.
	if ToolRules.hasFreeActivation(state, def) then
		local remaining = (state.freeToolCharges[def.id] :: number) - 1
		state.freeToolCharges[def.id] = if remaining > 0 then remaining else nil
	else
		-- Validated strictly above; can never hit zero here. Attributed per tool so the run summary
		-- can separate tool spending from passive burn.
		local source: Types.WaxSource = if def.id == "Flare"
			then "ToolFlare"
			elseif def.id == "Decoy" then "ToolDecoy"
			elseif def.id == "Cup" then "ToolCup"
			else "ToolOther"
		state.wax = WaxAccounting.spend(state.wax, state.waxLedger, def.waxCost, source)
	end
	if def.burstIntensity ~= nil then
		-- FLARE exposes the flame fully. CUP and FLARE are opposing light states, never stacked.
		state.isCupping = false
		state.flareEndsAt = now + def.duration * state.modifiers.flareDurationMultiplier
		MovementService.refresh(player.UserId)
	end
	if def.throwRange ~= nil then
		spawnDecoy(state, def, decoyLanding :: DecoyLanding, now)
	end
end

function ToolService.init()
	Remotes.get("ToolUse").OnServerEvent:Connect(function(player: Player, toolId: unknown, aimPoint: unknown)
		if not RequestGuard.allow(player, "ToolUse") or typeof(toolId) ~= "string" then
			return
		end
		local def = Config.Tools[toolId :: Types.ToolId]
		if def == nil then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil then
			return
		end
		local now = os.clock()
		local ok, denial = ToolRules.validate(state, def, now)
		if not ok then
			ActionFeedbackService.send(player, state, def.id, false, now, denial)
			return
		end
		local decoyLanding: DecoyLanding? = nil
		if def.throwRange ~= nil then
			if
				not RequestGuard.finiteVector3(aimPoint)
				or def.decoyIntensity == nil
				or def.decoyRange == nil
				or def.decoyVisual == nil
			then
				ActionFeedbackService.send(player, state, def.id, false, now, "InvalidTarget")
				return
			end
			local origin = CharacterService.basePosition(player.UserId) or state.position
			decoyLanding = resolveDecoyLanding(state, origin, def, aimPoint :: Vector3)
			-- A blocked, too-close, missing-floor, or too-steep landing does not spend wax and does
			-- not begin cooldown. Validation of player state happened first; world placement is the
			-- final precondition before activation mutates anything.
			if decoyLanding == nil then
				ActionFeedbackService.send(player, state, def.id, false, now, "InvalidTarget")
				return
			end
		end
		activate(player, state, def, decoyLanding, now)
		ActionFeedbackService.send(player, state, def.id, true, now, nil)
	end)
end

-- Expire decoys and lapsed flare bursts.
function ToolService.tick()
	local now = os.clock()
	for index = #decoys, 1, -1 do
		if now >= decoys[index].endsAt or decoys[index].model.Parent == nil then
			decoys[index].model:Destroy()
			table.remove(decoys, index)
		end
	end
	for _, state in PlayerState.all() do
		if state.flareEndsAt ~= 0 and now >= state.flareEndsAt then
			state.flareEndsAt = 0
		end
	end
end

-- Decoy contributions to the light field.
function ToolService.decoySources(): { Types.LightSource }
	local sources: { Types.LightSource } = {}
	for _, decoy in decoys do
		table.insert(sources, {
			kind = "Decoy" :: Types.LightSourceKind,
			position = decoy.position,
			intensity = decoy.intensity,
			range = decoy.range,
			attractsDrawn = decoy.attractsDrawn,
			repelsDarkHunters = false,
			forcesDarkHunterRetreat = false,
			ownerId = nil,
		})
	end
	return sources
end

-- Remove only one player's placed distractions. Test-room exit uses this narrow lifecycle route so
-- a session cannot leave a live lure in the next session, while ordinary decoys keep their normal
-- duration and global reset behavior.
function ToolService.clearPlayerDecoys(playerId: Types.PlayerId): number
	local removed = 0
	for index = #decoys, 1, -1 do
		local decoy = decoys[index]
		if decoy.ownerId == playerId then
			decoy.model:Destroy()
			table.remove(decoys, index)
			removed += 1
		end
	end
	return removed
end

function ToolService.reset()
	for _, decoy in decoys do
		decoy.model:Destroy()
	end
	table.clear(decoys)
	if decoyFolder ~= nil then
		decoyFolder:Destroy()
		decoyFolder = nil
	end
	decoySequence = 0
end

return ToolService

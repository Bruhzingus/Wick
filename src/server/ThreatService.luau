--!strict
-- Thin adapter around ThreatBrain: spawns silhouettes from the floor plan, feeds the brain its
-- snapshots, moves parts to the positions the brain returns, and applies contact effects.
-- Zero per-threat-ID logic lives here — additional threats are Config/Threats rows that reuse
-- generic behavior profiles.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local ThreatBrain = require(ReplicatedStorage.Shared.Logic.ThreatBrain)
local LightField = require(ReplicatedStorage.Shared.Logic.LightField)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local RoofGeometry = require(ReplicatedStorage.Shared.Logic.RoofGeometry)
local RoomNavigation = require(ReplicatedStorage.Shared.Logic.RoomNavigation)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local LightSources = require(script.Parent.LightSources)
local DripTrailService = require(script.Parent.DripTrailService)
local NoiseService = require(script.Parent.NoiseService)
local WaxService = require(script.Parent.WaxService)
local DeathService = require(script.Parent.DeathService)
local ThreatVisualProxy = require(script.Parent.ThreatVisualProxy)

local ThreatService = {}

type RoomSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
	roofField: RoofGeometry.Field,
}

type Perch = {
	cframe: CFrame, -- resting frame against the wall face
	height: number, -- world Y of the resting point, so releasing can ease back down
	endsAt: number,
}

type Instance_ = {
	def: Types.ThreatDef,
	state: Types.ThreatState,
	model: Model,
	visualProxy: ThreatVisualProxy.Proxy?,
	upOffset: number, -- pivot height above the floor plane
	roomSurface: RoomSurface?, -- the SPAWN room's fields; only a fallback once the threat has moved
	-- Every room on this threat's floor. A threat walks between rooms and each room carves its own
	-- ground and roof, so the fields it stands on have to be looked up from where it IS (see
	-- `surfaceAt`) rather than frozen at spawn.
	roomSurfaces: { [number]: RoomSurface },
	visualY: number, -- smoothed world-space root height, separate from ground-plane AI state
	perch: Perch?, -- set only while resting on a wall in Wander mode
	navigation: RoomNavigation.Navigation,
	contactHits: { [Types.PlayerId]: number },
	nextContactAt: { [Types.PlayerId]: number },
}

local instances: { Instance_ } = {}
local rng = Random.new()
local wallFilter: RaycastParams? = nil
-- Terrain and nothing else. The roof probe is correcting ONE specific disagreement — the analytic
-- roof field against the voxels actually written from it — so it must not be able to mistake a
-- boulder, a wall or a rock column for a ceiling and drag a ceiling ambusher down onto it. Hanging
-- clear of dressing is a different job, already done by `ambush.roofDecorationClearance` when the
-- builder reserves the territory.
local terrainFilter: RaycastParams? = nil
local nextHintAt: { [Types.PlayerId]: number } = {}

local LABEL_COLORS: { [Types.ThreatCategory]: Color3 } = {
	DarkHunter = Color3.fromRGB(150, 165, 200),
	Drawn = Color3.fromRGB(230, 195, 130),
}

local function threatPart(
	model: Model,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = model
	return part
end

local function weldTo(root: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = root
end

local function addHunterEyes(root: BasePart, model: Model, scale: number, centerY: number, forward: number)
	local visual = Config.Threats.visuals.darkHunter
	local eyeSize = math.clamp(scale * visual.eyeSizeScale, visual.eyeMinSize, visual.eyeMaxSize)
	for _, side in { -1, 1 } do
		local eye = threatPart(
			model,
			Vector3.new(eyeSize * visual.eyeWidthScale, eyeSize * visual.eyeHeightScale, eyeSize * visual.eyeDepthScale),
			visual.eyeColor,
			Enum.Material.Neon
		)
		eye.Name = "Eye"
		weldTo(
			root,
			eye,
			CFrame.new(side * eyeSize * 1.15, centerY, -forward)
				* CFrame.Angles(0, 0, side * math.rad(visual.eyeAngleDegrees))
		)

		local glow = Instance.new("PointLight")
		glow.Color = visual.eyeColor
		glow.Brightness = visual.eyeGlowBrightness
		glow.Range = visual.eyeGlowRange
		glow.Shadows = false
		glow.Parent = eye
	end
end

-- Category-shaped silhouettes, scaled by the row's bodySize. Shapes at the edge of light,
-- never rendered detail (DESIGN §16). New threats reuse their category's shape automatically.
local function buildThreatModel(def: Types.ThreatDef): (Model, number)
	local s = def.bodySize
	local model = Instance.new("Model")
	model.Name = "Threat_" .. def.id

	local root: BasePart
	local upOffset: number
	if def.visualStyle == "Bug" then
		-- Compact black ceiling bug with grey translucent wings and two visible red pinpricks.
		local hunter = Config.Threats.visuals.darkHunter
		local bug = Config.Threats.visuals.bug
		root = threatPart(model, Vector3.new(s * 0.48, s * 0.34, s), hunter.bodyColor)
		root.Shape = Enum.PartType.Ball
		root.Anchored = true
		for _, side in { -1, 1 } do
			local wing =
				threatPart(model, Vector3.new(s * 0.78, s * 0.06, s * 0.38), bug.wingColor, nil, bug.wingTransparency)
			wing.Shape = Enum.PartType.Ball
			weldTo(
				root,
				wing,
				CFrame.new(side * s * 0.46, s * 0.05, s * 0.08) * CFrame.Angles(0, 0, side * math.rad(14))
			)
		end
		addHunterEyes(root, model, s, 0, s * 0.47)
		upOffset = s * 0.3
	elseif def.category == "DarkHunter" then
		-- A connected, gaunt humanoid silhouette. Every limb overlaps the torso or pelvis so the
		-- figure still reads as a body when only fragments cross the candle's edge light.
		local visual = Config.Threats.visuals.darkHunter
		local torsoHeight = s * 0.92
		local legLength = s * 0.8
		local pelvisHeight = s * 0.3
		local legCenterY = -torsoHeight / 2 - pelvisHeight / 2 - legLength / 2 + s * 0.12
		root = threatPart(model, Vector3.new(s * 0.62, torsoHeight, s * 0.38), visual.bodyColor)
		root.Anchored = true

		local chest = threatPart(model, Vector3.new(s * 0.86, s * 0.3, s * 0.44), visual.bodyColor)
		weldTo(root, chest, CFrame.new(0, torsoHeight * 0.3, -s * 0.04))

		local pelvis = threatPart(model, Vector3.new(s * 0.58, pelvisHeight, s * 0.4), visual.bodyColor)
		weldTo(root, pelvis, CFrame.new(0, -torsoHeight / 2 - pelvisHeight / 2 + s * 0.08, 0))

		local neck = threatPart(model, Vector3.new(s * 0.22, s * 0.28, s * 0.22), visual.bodyColor)
		weldTo(root, neck, CFrame.new(0, torsoHeight / 2 + s * 0.09, -s * 0.06))

		local headCenter = torsoHeight / 2 + s * 0.38
		local head = threatPart(model, Vector3.new(s * 0.52, s * 0.52, s * 0.44), visual.bodyColor)
		weldTo(root, head, CFrame.new(0, headCenter, -s * 0.12) * CFrame.Angles(math.rad(-10), 0, 0))

		for _, side in { -1, 1 } do
			local upperArm = threatPart(model, Vector3.new(s * 0.22, s * 0.68, s * 0.24), visual.bodyColor)
			weldTo(
				root,
				upperArm,
				CFrame.new(side * s * 0.49, torsoHeight * 0.08, -s * 0.09)
					* CFrame.Angles(math.rad(-12), 0, side * math.rad(-8))
			)

			local forearm = threatPart(model, Vector3.new(s * 0.19, s * 0.72, s * 0.21), visual.bodyColor)
			weldTo(
				root,
				forearm,
				CFrame.new(side * s * 0.55, -s * 0.55, -s * 0.24) * CFrame.Angles(math.rad(-18), 0, side * math.rad(5))
			)

			local hand = threatPart(model, Vector3.new(s * 0.23, s * 0.28, s * 0.2), visual.bodyColor)
			weldTo(root, hand, CFrame.new(side * s * 0.57, -s * 0.91, -s * 0.34))

			local leg = threatPart(model, Vector3.new(s * 0.25, legLength, s * 0.29), visual.bodyColor)
			weldTo(root, leg, CFrame.new(side * s * 0.18, legCenterY, 0) * CFrame.Angles(0, 0, side * math.rad(4)))

			local foot = threatPart(model, Vector3.new(s * 0.28, s * 0.2, s * 0.48), visual.bodyColor)
			weldTo(root, foot, CFrame.new(side * s * 0.2, legCenterY - legLength / 2 + s * 0.03, -s * 0.14))
		end

		addHunterEyes(root, model, s, headCenter, s * 0.36)
		upOffset = -legCenterY + legLength / 2 - s * 0.03
	else
		-- Neutral ash moth viewed upright. Wings occupy the X/Y plane so they remain broad and
		-- unmistakable when the moth faces a player; the old horizontal wings vanished edge-on.
		local visual = Config.Threats.visuals.drawn
		root = threatPart(model, Vector3.new(s * 0.27, s * 0.68, s * 0.3), visual.bodyColor)
		root.Shape = Enum.PartType.Ball
		root.Anchored = true

		local thorax = threatPart(model, Vector3.new(s * 0.36, s * 0.4, s * 0.34), visual.thoraxColor)
		thorax.Shape = Enum.PartType.Ball
		weldTo(root, thorax, CFrame.new(0, s * 0.13, -s * 0.08))

		local head = threatPart(model, Vector3.one * (s * 0.27), visual.thoraxColor)
		head.Shape = Enum.PartType.Ball
		weldTo(root, head, CFrame.new(0, s * 0.4, -s * 0.1))

		for _, side in { -1, 1 } do
			local foreWing = threatPart(
				model,
				Vector3.new(s * 0.82, s * 0.94, s * 0.08),
				visual.wingColor,
				nil,
				visual.wingTransparency
			)
			foreWing.Shape = Enum.PartType.Ball
			weldTo(
				root,
				foreWing,
				CFrame.new(side * s * 0.48, s * 0.16, s * 0.09)
					* CFrame.Angles(0, side * math.rad(5), side * math.rad(-17))
			)

			local hindWing = threatPart(
				model,
				Vector3.new(s * 0.62, s * 0.62, s * 0.07),
				visual.wingColor,
				nil,
				visual.wingTransparency + 0.06
			)
			hindWing.Shape = Enum.PartType.Ball
			weldTo(
				root,
				hindWing,
				CFrame.new(side * s * 0.4, -s * 0.28, s * 0.12)
					* CFrame.Angles(0, side * math.rad(-7), side * math.rad(22))
			)

			local antenna = threatPart(model, Vector3.new(s * 0.035, s * 0.42, s * 0.035), visual.bodyColor)
			weldTo(
				root,
				antenna,
				CFrame.new(side * s * 0.13, s * 0.61, -s * 0.11) * CFrame.Angles(0, 0, side * math.rad(-18))
			)
		end
		upOffset = s * 0.58
	end

	-- Grey-box tuning aid, disabled for horror/readability playtests by default.
	if Config.Feel.debug.showThreatLabels then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(140, 26)
		billboard.StudsOffset = Vector3.new(0, upOffset + 1.2, 0)
		billboard.MaxDistance = 90
		billboard.LightInfluence = 0
		billboard.AlwaysOnTop = false
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.TextScaled = true
		text.TextTransparency = 0.25
		text.TextColor3 = LABEL_COLORS[def.category]
		text.Text = def.displayName
		text.Parent = billboard
		billboard.Parent = root
	end

	model.PrimaryPart = root
	CollectionService:AddTag(model, Config.Feel.threatWarning.collectionTag)
	return model, upOffset
end

function ThreatService.setFloorsFolder(folder: Instance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	-- Terrain is the cave floor now, so the ground probe and obstacle ray must see it alongside the
	-- part geometry (walls, boulders, columns) that still lives in the floor model.
	params.FilterDescendantsInstances = { folder, workspace.Terrain }
	params.RespectCanCollide = true
	wallFilter = params

	local roofOnly = RaycastParams.new()
	roofOnly.FilterType = Enum.RaycastFilterType.Include
	roofOnly.FilterDescendantsInstances = { workspace.Terrain }
	roofOnly.RespectCanCollide = true
	terrainFilter = roofOnly
end

local function projectToGround(position: Vector3): Vector3
	if wallFilter == nil then
		return position
	end
	local terrain = Config.Floors.terrain
	local origin = position + Vector3.new(0, terrain.aiGroundProbeHeight, 0)
	local direction = Vector3.new(0, -(terrain.aiGroundProbeHeight + terrain.aiGroundProbeDepth), 0)
	local result = workspace:Raycast(origin, direction, wallFilter)
	if result == nil then
		return position
	end
	return Vector3.new(position.X, result.Position.Y, position.Z)
end

-- THE FIELDS UNDER THE THREAT RIGHT NOW, not the ones it was born on. Each room carves its own
-- ground and roof from its own seeded field, and `GroundGeometry.offset` happily extrapolates a
-- neighbouring room's undulation and wall berm out past the cell it was authored for — which is how
-- a crawler that walked one doorway east ended up standing on air at its old room's berm height, and
-- a ceiling ambusher ended up hunting a roof that does not exist above it.
local function surfaceAt(instance: Instance_, position: Vector3): RoomSurface?
	local roomIndex = RoomNavigation.roomAt(instance.navigation, position)
	if roomIndex ~= nil then
		local surface = instance.roomSurfaces[roomIndex]
		if surface ~= nil then
			return surface
		end
	end
	-- Mid-doorway, or briefly outside every cell. The spawn room is a bounded, deterministic answer
	-- and the terrain probe below corrects whatever it gets wrong.
	return instance.roomSurface
end

local function surfaceGroundPosition(surface: RoomSurface, position: Vector3): Vector3
	local localX = position.X - surface.center.X
	local localZ = position.Z - surface.center.Z
	local groundY = surface.center.Y + GroundGeometry.offset(surface.groundField, localX, localZ)
	return Vector3.new(position.X, groundY, position.Z)
end

-- Reconcile the analytic field with the Terrain that actually got written, the same way every object
-- that stands on the floor already does (see server/SurfaceProbe). The two disagree by up to a voxel,
-- which is the difference between a threat standing on the ground and a threat sunk to its eyes in
-- it. The probe is deliberately a narrow window around the planned height: a long ray finds shelves,
-- overhangs and roofs, and none of those is this spot's floor.
local function resolveGroundY(plannedY: number, x: number, z: number): number
	local filter = wallFilter
	if filter == nil then
		return plannedY
	end
	local terrain = Config.Floors.terrain
	local origin = Vector3.new(x, plannedY + terrain.aiGroundProbeHeight, z)
	local span = terrain.aiGroundProbeHeight + terrain.aiGroundProbeDepth
	local hit = workspace:Raycast(origin, Vector3.new(0, -span, 0), filter)
	if hit == nil then
		return plannedY
	end
	return hit.Position.Y
end

local function surfaceRoofY(instance: Instance_, position: Vector3): number
	local surface = surfaceAt(instance, position)
	if surface == nil then
		return position.Y + Config.Floors.roof.minimumClearance
	end
	local localX = position.X - surface.center.X
	local localZ = position.Z - surface.center.Z
	local groundHeight = GroundGeometry.offset(surface.groundField, localX, localZ)
	local plannedY = surface.center.Y
		+ RoofGeometry.undersideHeight(surface.ceilingHeight, surface.roofField, groundHeight, localX, localZ)

	-- And then the same reconciliation the floor gets. A ceiling ambusher hangs a couple of studs under
	-- the roof, which is well inside the error between the analytic underside and the voxelized one, so
	-- trusting the field alone parks its whole body inside the rock. Only a LOWER real ceiling can
	-- matter here — a higher one just leaves the threat hanging where it was planned to.
	local filter = terrainFilter
	if filter == nil then
		return plannedY
	end
	local floorY = position.Y
	local originY = math.max(plannedY - Config.Floors.terrain.aiRoofProbeWindow, floorY + 1)
	if originY >= plannedY then
		return plannedY
	end
	local hit =
		workspace:Raycast(Vector3.new(position.X, originY, position.Z), Vector3.new(0, plannedY - originY, 0), filter)
	if hit == nil then
		return plannedY
	end
	return math.max(hit.Position.Y, originY)
end

local function groundPositionFor(instance: Instance_, position: Vector3): Vector3
	local surface = surfaceAt(instance, position)
	if surface == nil then
		return projectToGround(position)
	end
	local planned = surfaceGroundPosition(surface, position)
	return Vector3.new(position.X, resolveGroundY(planned.Y, position.X, position.Z), position.Z)
end

local function targetVisualY(instance: Instance_, groundPosition: Vector3): number
	local ambush = instance.def.ambush
	if ambush == nil then
		return groundPosition.Y + instance.upOffset
	end
	if instance.state.mode == "Seek" then
		return groundPosition.Y + instance.upOffset + ambush.attackHeight
	end
	if surfaceAt(instance, groundPosition) ~= nil then
		-- Never below the height it dives to: a roof probe that came back low must not park the
		-- ambusher under its own attack line.
		local hang = surfaceRoofY(instance, groundPosition) - ambush.ceilingClearance
		return math.max(hang, groundPosition.Y + instance.upOffset + ambush.attackHeight)
	end
	return groundPosition.Y + instance.upOffset + ambush.hoverHeight
end

-- Look outward from a wander point for a cave wall to rest on. Returns nil when the point sits in
-- open floor, which simply leaves the threat drifting the way it always has.
local function findPerch(instance: Instance_, now: number): Perch?
	local profile = instance.def.perch
	local filter = wallFilter
	if profile == nil or filter == nil then
		return nil
	end
	local height = rng:NextNumber(profile.minimumHeight, profile.maximumHeight)
	local origin = groundPositionFor(instance, instance.state.position) + Vector3.new(0, height, 0)
	local directions = math.max(math.floor(profile.searchDirections), 1)
	local firstAngle = rng:NextNumber() * 2 * math.pi
	-- A wall's normal is near-horizontal, so its face slope is acos(|normal.Y|). Requiring that to
	-- exceed the configured minimum rejects floors and roof undersides without a second probe.
	local maximumNormalY = math.cos(math.rad(math.clamp(profile.minimumWallSlopeDegrees, 0, 90)))
	for step = 0, directions - 1 do
		local angle = firstAngle + step * (2 * math.pi / directions)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)) * profile.searchRadius
		local hit = workspace:Raycast(origin, direction, filter)
		if hit ~= nil and math.abs(hit.Normal.Y) <= maximumNormalY then
			local point = hit.Position + hit.Normal * profile.surfaceOffset
			if RoomNavigation.isProtected(instance.navigation, point) then
				continue
			end
			return {
				-- Head up, belly to the stone: the body faces into the wall it is clinging to.
				cframe = CFrame.lookAt(point, point - hit.Normal, Vector3.yAxis),
				height = point.Y,
				endsAt = now + rng:NextNumber(profile.minimumDwellSeconds, profile.maximumDwellSeconds),
			}
		end
	end
	return nil
end

local function approach(current: number, target: number, maximumDelta: number): number
	if current < target then
		return math.min(current + maximumDelta, target)
	end
	return math.max(current - maximumDelta, target)
end

function ThreatService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomSurface }
): number
	local navigation = RoomNavigation.build(plan, roomCenters)
	local builtCount = 0
	for _, spawn in plan.threatSpawns do
		local def = Config.Threats.definitions[spawn.threatId]
		if def == nil then
			continue
		end
		local center = roomCenters[spawn.roomIndex]
		local roomSurface = roomSurfaces[spawn.roomIndex]
		if center == nil or roomSurface == nil then
			continue
		end
		local position = center + spawn.offset
		-- Seated on the Terrain that was actually written, not on the field it was planned from, so a
		-- threat never starts its life sunk into the floor it is standing on.
		local plannedY = surfaceGroundPosition(roomSurface, position).Y
		position = Vector3.new(position.X, resolveGroundY(plannedY, position.X, position.Z), position.Z)

		local visualProxy: ThreatVisualProxy.Proxy? = nil
		local model: Model
		local upOffset: number
		if Config.Threats.visuals.procedural.enabled then
			-- The family comes from the plan, so a threat is dressed for the cave it stands in without
			-- ThreatService itself knowing anything about cave families.
			visualProxy = ThreatVisualProxy.build(def, plan.familyId)
			model = visualProxy.model
			upOffset = visualProxy.upOffset
		else
			-- Emergency grey-box fallback for isolating a client-visual regression in Studio.
			model, upOffset = buildThreatModel(def)
		end

		local instance: Instance_ = {
			def = def,
			state = {
				id = def.id,
				category = def.category,
				position = position,
				homePosition = position,
				mode = "Wander" :: Types.ThreatMode,
				targetPosition = nil,
				targetPlayerId = nil,
				nextThinkAt = 0,
				retreatUntil = 0,
				investigateUntil = 0,
				investigateLoudness = 0,
			},
			model = model,
			visualProxy = visualProxy,
			upOffset = upOffset,
			roomSurface = roomSurface,
			roomSurfaces = roomSurfaces,
			visualY = position.Y + upOffset,
			perch = nil,
			navigation = navigation,
			contactHits = {},
			nextContactAt = {},
		}
		instance.visualY = targetVisualY(instance, position)
		model:PivotTo(CFrame.new(position.X, instance.visualY, position.Z))
		model.Parent = workspace
		table.insert(instances, instance)
		builtCount += 1
	end
	return builtCount
end

local function sourcesOutsideProtectedRoom(
	navigation: RoomNavigation.Navigation,
	sources: { Types.LightSource }
): { Types.LightSource }
	local visible: { Types.LightSource } = {}
	for _, source in sources do
		if not RoomNavigation.isProtected(navigation, source.position) then
			table.insert(visible, source)
		end
	end
	return visible
end

local function trailOutsideProtectedRoom(
	navigation: RoomNavigation.Navigation,
	trail: { Types.TrailPoint }
): { Types.TrailPoint }
	local exposed: { Types.TrailPoint } = {}
	for _, point in trail do
		if not RoomNavigation.isProtected(navigation, point.position) then
			table.insert(exposed, point)
		end
	end
	return exposed
end

-- The Basin excludes itself from every perception input, sound included: a noise made inside the
-- safe room does not exist to anything outside it, exactly as its light and its drips do not.
local function noisesOutsideProtectedRoom(
	navigation: RoomNavigation.Navigation,
	noises: { Types.NoiseEvent }
): { Types.NoiseEvent }
	local audible: { Types.NoiseEvent } = {}
	for _, noise in noises do
		if not RoomNavigation.isProtected(navigation, noise.position) then
			table.insert(audible, noise)
		end
	end
	return audible
end

local function playerSnapshots(
	navigation: RoomNavigation.Navigation,
	sources: { Types.LightSource },
	now: number
): { ThreatBrain.PlayerSnapshot }
	local snapshots: { ThreatBrain.PlayerSnapshot } = {}
	for playerId, state in PlayerState.all() do
		local robloxPlayer = Players:GetPlayerByUserId(playerId)
		local character = if robloxPlayer ~= nil then robloxPlayer.Character else nil
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		local lookDirection: Vector3? = nil
		if root ~= nil and root:IsA("BasePart") then
			local look = root.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0 then
				lookDirection = flatLook.Unit
			end
		end
		local flamePosition = Vector3.new(
			state.position.X,
			CandleGeometry.flameCenterY(state.position.Y, state.currentHeight),
			state.position.Z
		)
		table.insert(snapshots, {
			playerId = playerId,
			position = state.position,
			lookDirection = lookDirection,
			lightLevel = LightField.intensityAt(flamePosition, sources),
			targetable = state.alive
				and not state.finished
				and state.snuffedAt == nil
				and state.depth == navigation.plan.depth
				and not RoomNavigation.isProtected(navigation, state.position),
			-- FLARE is the solo panic counter. The normal dial still changes visibility and light
			-- reads, but reaching its ceiling never hard-counters a ceiling ambusher.
			repelsAmbusher = state.isLit and state.flareEndsAt > now,
		})
	end
	return snapshots
end

local function ambushNeedsImmediateReaction(instance: Instance_, players: { ThreatBrain.PlayerSnapshot }): boolean
	local profile = instance.def.ambush
	if profile == nil then
		return false
	end
	for _, player in players do
		if player.targetable and player.repelsAmbusher then
			local delta = player.position - instance.state.homePosition
			if Vector3.new(delta.X, 0, delta.Z).Magnitude <= profile.territoryRadius then
				return true
			end
		end
	end
	return false
end

local function hunterNeedsImmediatePanicReaction(
	instance: Instance_,
	players: { ThreatBrain.PlayerSnapshot },
	sources: { Types.LightSource }
): boolean
	if instance.def.ambush ~= nil then
		return ambushNeedsImmediateReaction(instance, players)
	end
	if instance.def.category ~= "DarkHunter" then
		return false
	end
	local source = LightField.strongestRetreatSourceAt(instance.state.position, sources)
	return source ~= nil
		and LightField.contributionOf(source, instance.state.position) * math.abs(instance.def.lightResponse)
			> Config.Threats.behavior.repelLightThreshold
end

local function movementState(state: Types.ThreatState, targetPosition: Vector3?): Types.ThreatState
	local horizontalTarget = if targetPosition == nil
		then nil
		else Vector3.new(targetPosition.X, state.position.Y, targetPosition.Z)
	return {
		id = state.id,
		category = state.category,
		position = state.position,
		homePosition = state.homePosition,
		mode = state.mode,
		targetPosition = horizontalTarget,
		targetPlayerId = state.targetPlayerId,
		nextThinkAt = state.nextThinkAt,
		retreatUntil = state.retreatUntil,
		investigateUntil = state.investigateUntil,
		investigateLoudness = state.investigateLoudness,
	}
end

local function sendTutorialHint(instance: Instance_, player: ThreatBrain.PlayerSnapshot, now: number)
	local hints = Config.Feel.tutorialHints
	if not hints.enabled then
		return
	end
	local state = PlayerState.get(player.playerId)
	if state == nil or state.depth > hints.maxDepth or now < (nextHintAt[player.playerId] or 0) then
		return
	end
	nextHintAt[player.playerId] = now + hints.serverCooldownSeconds
	local robloxPlayer = Players:GetPlayerByUserId(player.playerId)
	if robloxPlayer ~= nil then
		Remotes.get("TutorialHint"):FireClient(robloxPlayer, instance.def.id)
	end
end

-- Cosmetic swing, raised only where contact has actually resolved into an effect, so a staged row
-- sitting on its cooldown does not mime a hit it never landed. The proxy paces the beats.
local function signalAttackVisual(instance: Instance_, victimPlayerId: Types.PlayerId, now: number)
	local visualProxy = instance.visualProxy
	if visualProxy ~= nil then
		ThreatVisualProxy.signalAttack(visualProxy, victimPlayerId, now)
	end
end

local function applyContact(instance: Instance_, player: ThreatBrain.PlayerSnapshot, now: number, dt: number)
	local attack = instance.def.contactAttack
	if attack ~= nil then
		if instance.state.mode ~= "Seek" or instance.state.targetPlayerId ~= player.playerId then
			return
		end
		if now < (instance.nextContactAt[player.playerId] or 0) then
			return
		end
		instance.nextContactAt[player.playerId] = now + attack.cooldownSeconds
		signalAttackVisual(instance, player.playerId, now)
		sendTutorialHint(instance, player, now)
		if attack.waxDamagePerHit > 0 then
			WaxService.drainExternal(
				player.playerId,
				attack.waxDamagePerHit,
				"DamageThreat",
				instance.def.displayName .. " struck your flame."
			)
		end
		local hits, shouldSnuff =
			ThreatBrain.advanceContactHits(instance.contactHits[player.playerId] or 0, attack.hitsToSnuff)
		instance.contactHits[player.playerId] = hits
		if shouldSnuff then
			instance.contactHits[player.playerId] = nil
			instance.nextContactAt[player.playerId] = nil
			DeathService.snuff(player.playerId, instance.def.displayName .. " battered your flame out.")
		end
		return
	end

	signalAttackVisual(instance, player.playerId, now)
	if instance.def.contactEffect == "Snuff" then
		sendTutorialHint(instance, player, now)
		DeathService.snuff(player.playerId, instance.def.displayName .. " snuffed your flame.")
	else
		sendTutorialHint(instance, player, now)
		WaxService.drainExternal(
			player.playerId,
			instance.def.waxDamagePerSecond * dt,
			"DamageThreat",
			instance.def.displayName .. " drained your remaining wax."
		)
	end
end

function ThreatService.tick(dt: number)
	if #instances == 0 then
		return
	end
	local now = os.clock()
	local sources = LightSources.collect(now)
	local trail = DripTrailService.getTrail()
	local noises = NoiseService.events()

	for _, instance in instances do
		local visibleSources = sourcesOutsideProtectedRoom(instance.navigation, sources)
		local perceivedSources = if instance.def.category == "DarkHunter"
			then LightField.sourcesForDarkHunters(visibleSources)
			else visibleSources
		local exposedTrail = trailOutsideProtectedRoom(instance.navigation, trail)
		-- Deaf rows are handed an empty list rather than a filtered one: every Drawn threat and the
		-- territorial VoidFly pay nothing for a perception field they do not have.
		local audibleNoises: { Types.NoiseEvent } = if instance.def.hearing ~= nil
			then noisesOutsideProtectedRoom(instance.navigation, noises)
			else {}
		local players = playerSnapshots(instance.navigation, perceivedSources, now)
		-- Panic light interrupts a live dive on the next server tick instead of waiting for the
		-- ordinary repath cadence. Entering Flee clears staged hits below: the fly is "burned off,"
		-- never damaged.
		if
			now >= instance.state.nextThinkAt
			or hunterNeedsImmediatePanicReaction(instance, players, perceivedSources)
		then
			instance.state = ThreatBrain.think({
				def = instance.def,
				state = instance.state,
				players = players,
				sources = perceivedSources,
				trail = exposedTrail,
				noises = audibleNoises,
				now = now,
				rng = rng,
			})
			if instance.state.mode == "Flee" and instance.def.contactAttack ~= nil then
				table.clear(instance.contactHits)
				table.clear(instance.nextContactAt)
			end
		end

		if instance.def.perch ~= nil then
			local perch = instance.perch
			-- Any light the row can sense has already pulled it out of Wander, so a player bright
			-- enough to be noticed walking underneath takes the moth off the wall on that same think.
			if perch ~= nil and (instance.state.mode ~= "Wander" or now >= perch.endsAt) then
				-- Release from the resting height so the drop back to the floor is eased, not snapped.
				instance.visualY = perch.height
				instance.perch = nil
				perch = nil
				if instance.state.mode == "Wander" then
					-- Rethink before the block below runs again, so it roams to a new wander target
					-- instead of immediately re-clinging to the wall it just left.
					instance.state.nextThinkAt = now
				end
			elseif perch == nil and instance.state.mode == "Wander" then
				local target = instance.state.targetPosition
				local arrived = target == nil
					or (target - instance.state.position).Magnitude
						< Config.Threats.behavior.wanderArrivalToleranceStuds
				if arrived then
					perch = findPerch(instance, now)
					if perch ~= nil then
						-- Anchor the ground-plane AI beneath the wall so releasing stays horizontally
						-- continuous and the next roam starts from where the moth actually rested.
						-- The probe needs a Y near the real floor, so it starts from the resting point.
						instance.state.position = groundPositionFor(instance, perch.cframe.Position)
						instance.perch = perch
					end
				end
			end
			if perch ~= nil then
				instance.model:PivotTo(perch.cframe)
				local visualProxy = instance.visualProxy
				if visualProxy ~= nil then
					ThreatVisualProxy.sync(
						visualProxy,
						instance.state.mode,
						nil,
						LightField.intensityAt(perch.cframe.Position, perceivedSources),
						false
					)
				end
				-- A resting moth is ambience: it neither moves nor drains until a light wakes it.
				continue
			end
		end

		local clearance = instance.def.bodySize / 2 + Config.Floors.geometry.wallThickness
		local targetPosition = instance.state.targetPosition
		local waypoint = if targetPosition == nil
			then nil
			elseif instance.def.ambush ~= nil then targetPosition
			else RoomNavigation.nextWaypoint(
				instance.navigation,
				instance.state.position,
				targetPosition,
				clearance
			)
		local routedState = movementState(instance.state, waypoint)
		local nextPosition = ThreatBrain.step(routedState, instance.def, dt)
		nextPosition =
			RoomNavigation.constrainStep(instance.navigation, instance.state.position, nextPosition, clearance)
		nextPosition = groundPositionFor(instance, nextPosition)
		-- Silhouettes don't ghost through walls: a blocked move stops and forces a rethink.
		-- Ceiling ambushers stay in their small room-local territory and fly above floor obstacles;
		-- probing at their roof root would only collide with the irregular ceiling itself.
		local delta = nextPosition - instance.state.position
		local horizontalDelta = Vector3.new(delta.X, 0, delta.Z)
		if horizontalDelta.Magnitude > 0.01 and wallFilter ~= nil and instance.def.ambush == nil then
			local origin = instance.state.position + Vector3.new(0, instance.upOffset, 0)
			local ray = horizontalDelta + horizontalDelta.Unit * instance.def.bodySize / 2
			if workspace:Raycast(origin, ray, wallFilter) ~= nil then
				-- Temporarily sidestep a boulder/column instead of repeatedly selecting the same
				-- blocked line. The room graph remains authoritative for the next full rethink.
				if horizontalDelta.Magnitude > 0 then
					local side = Vector3.new(-horizontalDelta.Z, 0, horizontalDelta.X).Unit
					if rng:NextInteger(0, 1) == 0 then
						side = -side
					end
					instance.state.targetPosition =
						projectToGround(instance.state.position + side * Config.Floors.terrain.aiObstacleSidestep)
					instance.state.nextThinkAt = now + Config.Threats.behavior.repathIntervalSeconds
				else
					instance.state.nextThinkAt = now
				end
				continue
			end
		end
		instance.state.position = nextPosition
		local ambush = instance.def.ambush
		local wantedVisualY = targetVisualY(instance, nextPosition)
		if ambush ~= nil then
			local verticalSpeed = if instance.state.mode == "Seek" then ambush.diveSpeed else ambush.returnSpeed
			instance.visualY = approach(instance.visualY, wantedVisualY, verticalSpeed * dt)
			if surfaceAt(instance, nextPosition) ~= nil then
				-- A descending roof is a hard upper bound in every mode. Even during a diagonal
				-- dive, horizontal movement may reach lower relief faster than the vertical tween.
				local roofSafeY = surfaceRoofY(instance, nextPosition) - ambush.ceilingClearance
				instance.visualY = math.min(instance.visualY, roofSafeY)
			end
		elseif instance.def.perch ~= nil then
			-- Only ever off-target just after leaving a wall; this flies the moth back down.
			instance.visualY = approach(instance.visualY, wantedVisualY, instance.def.speed * dt)
		else
			instance.visualY = wantedVisualY
		end
		local visualPosition = Vector3.new(nextPosition.X, instance.visualY, nextPosition.Z)
		local target = routedState.targetPosition
		local targetDelta = if target == nil
			then Vector3.zero
			else Vector3.new(target.X - nextPosition.X, 0, target.Z - nextPosition.Z)
		if target ~= nil and targetDelta.Magnitude > 0.5 then
			instance.model:PivotTo(CFrame.lookAt(visualPosition, visualPosition + targetDelta))
		else
			instance.model:PivotTo(CFrame.new(visualPosition))
		end
		local visualProxy = instance.visualProxy
		if visualProxy ~= nil then
			ThreatVisualProxy.sync(
				visualProxy,
				instance.state.mode,
				instance.state.targetPosition,
				LightField.intensityAt(visualPosition, perceivedSources),
				horizontalDelta.Magnitude > 0.01
			)
		end

		-- Contact: continuous rows use their declared effect; staged rows count discrete attacks.
		local contactAttack = instance.def.contactAttack
		local uninterrupted: { [Types.PlayerId]: boolean } = {}
		local heightReady = if ambush == nil
			then true
			else math.abs(instance.visualY - wantedVisualY) <= ambush.contactHeightTolerance
		for _, player in players do
			if not player.targetable then
				continue
			end
			local playerDelta = player.position - instance.state.position
			local contactDistance = if ambush == nil
				then playerDelta.Magnitude
				else Vector3.new(playerDelta.X, 0, playerDelta.Z).Magnitude
			local isActiveAttack = contactAttack == nil
				or (
					instance.state.mode == "Seek"
					and instance.state.targetPlayerId == player.playerId
					and heightReady
					and not player.repelsAmbusher
				)
			if contactDistance <= instance.def.contactRadius and isActiveAttack then
				if contactAttack ~= nil then
					uninterrupted[player.playerId] = true
				end
				applyContact(instance, player, now, dt)
			end
		end
		if contactAttack ~= nil then
			-- The configured hit count means uninterrupted attacks. Breaking contact, escaping the
			-- territory, being snuffed, or driving the fly away starts the sequence over.
			for playerId in instance.contactHits do
				if not uninterrupted[playerId] then
					instance.contactHits[playerId] = nil
				end
			end
			for playerId in instance.nextContactAt do
				if not uninterrupted[playerId] then
					instance.nextContactAt[playerId] = nil
				end
			end
		end
	end
end

function ThreatService.reset()
	for _, instance in instances do
		instance.model:Destroy()
	end
	table.clear(instances)
	table.clear(nextHintAt)
end

return ThreatService

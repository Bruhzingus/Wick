--!strict
-- Thin adapter around ThreatBrain: spawns silhouettes from the floor plan, feeds the brain its
-- snapshots, moves parts to the positions the brain returns, and applies contact effects.
-- Zero per-threat-ID logic lives here — additional threats are Config/Threats rows that reuse
-- generic behavior profiles.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local ThreatBrain = require(ReplicatedStorage.Shared.Logic.ThreatBrain)
local LightField = require(ReplicatedStorage.Shared.Logic.LightField)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local RoomNavigation = require(ReplicatedStorage.Shared.Logic.RoomNavigation)
local PlayerState = require(script.Parent.PlayerState)
local LightSources = require(script.Parent.LightSources)
local DripTrailService = require(script.Parent.DripTrailService)
local WaxService = require(script.Parent.WaxService)
local DeathService = require(script.Parent.DeathService)

local ThreatService = {}

type Instance_ = {
	def: Types.ThreatDef,
	state: Types.ThreatState,
	model: Model,
	upOffset: number, -- pivot height above the floor plane
	navigation: RoomNavigation.Navigation,
	contactHits: { [Types.PlayerId]: number },
	nextContactAt: { [Types.PlayerId]: number },
}

local instances: { Instance_ } = {}
local rng = Random.new()
local wallFilter: RaycastParams? = nil

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
	params.FilterDescendantsInstances = { folder }
	params.RespectCanCollide = true
	wallFilter = params
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

function ThreatService.spawnFloor(plan: Types.FloorPlan, roomCenters: { Vector3 })
	local cell = Config.Floors.geometry.cellSize
	local navigation = RoomNavigation.build(plan, roomCenters)
	for _, spawn in plan.threatSpawns do
		local def = Config.Threats.definitions[spawn.threatId]
		if def == nil then
			continue
		end
		local center = roomCenters[spawn.roomIndex]
		local position = center
			+ Vector3.new(rng:NextNumber(-cell / 4, cell / 4), 0, rng:NextNumber(-cell / 4, cell / 4))
		position = projectToGround(position)

		local model, upOffset = buildThreatModel(def)
		local hoverHeight = if def.ambush ~= nil then def.ambush.hoverHeight else 0
		model:PivotTo(CFrame.new(position + Vector3.new(0, upOffset + hoverHeight, 0)))
		model.Parent = workspace

		table.insert(instances, {
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
			},
			model = model,
			upOffset = upOffset,
			navigation = navigation,
			contactHits = {},
			nextContactAt = {},
		})
	end
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

local function playerSnapshots(
	navigation: RoomNavigation.Navigation,
	sources: { Types.LightSource }
): { ThreatBrain.PlayerSnapshot }
	local snapshots: { ThreatBrain.PlayerSnapshot } = {}
	for playerId, state in PlayerState.all() do
		local flamePosition = Vector3.new(
			state.position.X,
			CandleGeometry.flameCenterY(state.position.Y, state.currentHeight),
			state.position.Z
		)
		table.insert(snapshots, {
			playerId = playerId,
			position = state.position,
			lightLevel = LightField.intensityAt(flamePosition, sources),
			targetable = state.alive
				and not state.finished
				and not RoomNavigation.isProtected(navigation, state.position),
			burningAtMax = state.isLit and state.burnRate >= state.modifiers.maxBurnRate - 0.01,
		})
	end
	return snapshots
end

local function movementState(state: Types.ThreatState, targetPosition: Vector3?): Types.ThreatState
	return {
		id = state.id,
		category = state.category,
		position = state.position,
		homePosition = state.homePosition,
		mode = state.mode,
		targetPosition = targetPosition,
		targetPlayerId = state.targetPlayerId,
		nextThinkAt = state.nextThinkAt,
		retreatUntil = state.retreatUntil,
	}
end

local function visualHeightFor(instance: Instance_): number
	local height = instance.upOffset
	if instance.def.ambush ~= nil then
		height += if instance.state.mode == "Seek"
			then instance.def.ambush.attackHeight
			else instance.def.ambush.hoverHeight
	end
	return height
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
		if attack.waxDamagePerHit > 0 then
			WaxService.drainExternal(
				player.playerId,
				attack.waxDamagePerHit,
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

	if instance.def.contactEffect == "Snuff" then
		DeathService.snuff(player.playerId, instance.def.displayName .. " snuffed your flame.")
	else
		WaxService.drainExternal(
			player.playerId,
			instance.def.waxDamagePerSecond * dt,
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

	for _, instance in instances do
		local visibleSources = sourcesOutsideProtectedRoom(instance.navigation, sources)
		local exposedTrail = trailOutsideProtectedRoom(instance.navigation, trail)
		local players = playerSnapshots(instance.navigation, visibleSources)
		if now >= instance.state.nextThinkAt then
			instance.state = ThreatBrain.think({
				def = instance.def,
				state = instance.state,
				players = players,
				sources = visibleSources,
				trail = exposedTrail,
				now = now,
				rng = rng,
			})
			if instance.state.mode == "Flee" and instance.def.contactAttack ~= nil then
				table.clear(instance.contactHits)
				table.clear(instance.nextContactAt)
			end
		end

		local clearance = instance.def.bodySize / 2 + Config.Floors.geometry.wallThickness
		local targetPosition = instance.state.targetPosition
		local waypoint = if targetPosition == nil
			then nil
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
		nextPosition = projectToGround(nextPosition)
		-- Silhouettes don't ghost through walls: a blocked move stops and forces a rethink.
		local offset = nextPosition - instance.state.position
		if offset.Magnitude > 0.01 and wallFilter ~= nil then
			local origin = instance.state.position + Vector3.new(0, visualHeightFor(instance), 0)
			if workspace:Raycast(origin, offset + offset.Unit * instance.def.bodySize / 2, wallFilter) ~= nil then
				-- Temporarily sidestep a boulder/column instead of repeatedly selecting the same
				-- blocked line. The room graph remains authoritative for the next full rethink.
				local flat = Vector3.new(offset.X, 0, offset.Z)
				if flat.Magnitude > 0 then
					local side = Vector3.new(-flat.Z, 0, flat.X).Unit
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
		local visualHeight = visualHeightFor(instance)
		local up = Vector3.new(0, visualHeight, 0)
		local target = routedState.targetPosition
		if target ~= nil and (target - nextPosition).Magnitude > 0.5 then
			instance.model:PivotTo(CFrame.lookAt(nextPosition + up, target + up))
		else
			instance.model:PivotTo(CFrame.new(nextPosition + up))
		end

		-- Contact: continuous rows use their declared effect; staged rows count discrete attacks.
		for _, player in players do
			if not player.targetable then
				continue
			end
			if (player.position - instance.state.position).Magnitude <= instance.def.contactRadius then
				applyContact(instance, player, now, dt)
			end
		end
	end
end

function ThreatService.reset()
	for _, instance in instances do
		instance.model:Destroy()
	end
	table.clear(instances)
end

return ThreatService

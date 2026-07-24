--!strict
-- Thin adapter around ThreatBrain: spawns silhouettes from the floor plan, feeds the brain its
-- snapshots, moves parts to the positions the brain returns, and applies contact effects.
-- Zero per-threat logic lives here — a fifth threat is a Config/Threats row.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local ThreatBrain = require(ReplicatedStorage.Shared.Logic.ThreatBrain)
local LightField = require(ReplicatedStorage.Shared.Logic.LightField)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
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
}

local instances: { Instance_ } = {}
local rng = Random.new()
local wallFilter: RaycastParams? = nil

local SILHOUETTE = Color3.fromRGB(12, 12, 16)

local LABEL_COLORS: { [Types.ThreatCategory]: Color3 } = {
	DarkHunter = Color3.fromRGB(150, 165, 200),
	Drawn = Color3.fromRGB(230, 195, 130),
}

local function silhouettePart(model: Model, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.Color = SILHOUETTE
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
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

-- Category-shaped silhouettes, scaled by the row's bodySize. Shapes at the edge of light,
-- never rendered detail (DESIGN §16). New threats reuse their category's shape automatically.
local function buildThreatModel(def: Types.ThreatDef): (Model, number)
	local s = def.bodySize
	local model = Instance.new("Model")
	model.Name = "Threat_" .. def.id

	local root: BasePart
	local upOffset: number
	if def.category == "DarkHunter" then
		-- Tall, gaunt: narrow torso with a small head. Reads as a standing figure in the dark.
		local torsoHeight = s * 1.6
		root = silhouettePart(model, Vector3.new(s * 0.55, torsoHeight, s * 0.4))
		root.Anchored = true
		local head = silhouettePart(model, Vector3.one * (s * 0.38))
		weldTo(root, head, CFrame.new(0, torsoHeight / 2 + s * 0.19, 0))
		upOffset = torsoHeight / 2
	else
		-- Drawn: a hovering moth-like body with two flat wing panels.
		root = silhouettePart(model, Vector3.new(s * 0.45, s * 0.45, s))
		root.Anchored = true
		for _, side in { -1, 1 } do
			local wing = silhouettePart(model, Vector3.new(s * 0.85, 0.15, s * 0.6))
			weldTo(root, wing, CFrame.new(side * s * 0.6, s * 0.1, 0) * CFrame.Angles(0, 0, side * math.rad(20)))
		end
		upOffset = s * 0.6
	end

	-- Grey-box tuning aid: a name label so playtests can tell rows apart. Remove (or gate behind
	-- a debug flag) when real silhouette readability is being evaluated.
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

	model.PrimaryPart = root
	return model, upOffset
end

function ThreatService.setFloorsFolder(folder: Instance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	wallFilter = params
end

function ThreatService.spawnFloor(plan: Types.FloorPlan, roomCenters: { Vector3 })
	local cell = Config.Floors.geometry.cellSize
	for _, spawn in plan.threatSpawns do
		local def = Config.Threats.definitions[spawn.threatId]
		if def == nil then
			continue
		end
		local center = roomCenters[spawn.roomIndex]
		local position = center
			+ Vector3.new(rng:NextNumber(-cell / 4, cell / 4), 0, rng:NextNumber(-cell / 4, cell / 4))

		local model, upOffset = buildThreatModel(def)
		model:PivotTo(CFrame.new(position + Vector3.new(0, upOffset, 0)))
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
			},
			model = model,
			upOffset = upOffset,
		})
	end
end

local function playerSnapshots(sources: { Types.LightSource }): { ThreatBrain.PlayerSnapshot }
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
			targetable = state.alive and not state.finished,
		})
	end
	return snapshots
end

function ThreatService.tick(dt: number)
	if #instances == 0 then
		return
	end
	local now = os.clock()
	local sources = LightSources.collect(now)
	local trail = DripTrailService.getTrail()
	local players = playerSnapshots(sources)

	for _, instance in instances do
		if now >= instance.state.nextThinkAt then
			instance.state = ThreatBrain.think({
				def = instance.def,
				state = instance.state,
				players = players,
				sources = sources,
				trail = trail,
				now = now,
				rng = rng,
			})
		end

		local nextPosition = ThreatBrain.step(instance.state, instance.def, dt)
		-- Silhouettes don't ghost through walls: a blocked move stops and forces a rethink.
		local offset = nextPosition - instance.state.position
		if offset.Magnitude > 0.01 and wallFilter ~= nil then
			local origin = instance.state.position + Vector3.new(0, instance.upOffset, 0)
			if workspace:Raycast(origin, offset + offset.Unit * instance.def.bodySize / 2, wallFilter) ~= nil then
				instance.state.nextThinkAt = now
				continue
			end
		end
		instance.state.position = nextPosition
		local up = Vector3.new(0, instance.upOffset, 0)
		local target = instance.state.targetPosition
		if target ~= nil and (target - nextPosition).Magnitude > 0.5 then
			instance.model:PivotTo(CFrame.lookAt(nextPosition + up, target + up))
		else
			instance.model:PivotTo(CFrame.new(nextPosition + up))
		end

		-- Contact: apply the row's declared effect. Snuffed players remain valid prey (they're dark).
		for _, player in players do
			if not player.targetable then
				continue
			end
			if (player.position - instance.state.position).Magnitude <= instance.def.contactRadius then
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

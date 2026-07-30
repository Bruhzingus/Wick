--!strict
-- Local loose-rock presentation used by AmbientCaveDirector. This deliberately has no server route,
-- collision, or gameplay state: the director decides WHEN one harmless event may happen, while this
-- module only finds real wall/ground surfaces and renders the fall.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local CaveKit = require(ReplicatedStorage.Shared.NewModelsAndObjects.CaveKit)
local AudioCues = require(script.Parent.AudioCues)

local AmbientRockfallController = {}

type ActiveRockfall = {
	model: Model,
	startedAt: number,
	dropStart: Vector3,
	landPosition: Vector3,
	rollDirection: Vector3,
	rollDistance: number,
	yaw: number,
	size: number,
	soundPlayed: boolean,
}

local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local player = Players.LocalPlayer
local rng = Random.new()
local folder: Folder? = nil
local active: ActiveRockfall? = nil

local function rockfallConfig()
	return Config.Feel.ambientRockfall
end

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function ensureFolder(): Folder
	local current = folder
	if current ~= nil and current.Parent ~= nil then
		return current
	end

	local created = Instance.new("Folder")
	created.Name = "WickAmbientRockfalls"
	created.Parent = workspace
	folder = created
	return created
end

local function raycastParams(ignore: Instance?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = {}
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		if character ~= nil then
			table.insert(ignored, character)
		end
	end
	if ignore ~= nil then
		table.insert(ignored, ignore)
	end
	params.FilterDescendantsInstances = ignored
	-- Loose stone needs a solid wall/floor. Terrain water is not a landing surface.
	params.IgnoreWater = true
	return params
end

local function flat(vector: Vector3): Vector3?
	local result = Vector3.new(vector.X, 0, vector.Z)
	return if result.Magnitude > 0.001 then result.Unit else nil
end

local function raycastGround(near: Vector3, ignore: Instance?): RaycastResult?
	local config = rockfallConfig()
	local origin = near + Vector3.yAxis * config.groundProbeHeight
	local hit = workspace:Raycast(origin, Vector3.yAxis * -config.groundProbeDistance, raycastParams(ignore))
	if hit == nil or hit.Normal.Y < config.groundNormalMinY then
		return nil
	end
	return hit
end

local function wallCandidate(root: BasePart): (Vector3?, Vector3?)
	local config = rockfallConfig()
	local origin = root.Position + Vector3.yAxis * 1.5
	for _attempt = 1, config.wallSearchAttempts do
		-- Every attempt samples a fresh azimuth. A deterministic camera-forward first choice made the
		-- event feel staged around the listener instead of like unrelated cave movement.
		local yaw = rng:NextNumber(-math.pi, math.pi)
		local direction = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local wall = workspace:Raycast(origin, direction * config.wallSearchMaxDistance, raycastParams())
		if
			wall == nil
			or wall.Distance < config.wallSearchMinDistance
			or math.abs(wall.Normal.Y) > config.wallNormalMaxY
		then
			continue
		end
		local inward = flat(wall.Normal)
		if inward == nil then
			continue
		end
		local ground = raycastGround(wall.Position + inward * config.wallInset, nil)
		if ground ~= nil then
			return ground.Position + inward * config.wallInset, inward
		end
	end
	return nil, nil
end

local function spawnRockfall(now: number): boolean
	local root = localRoot()
	if root == nil then
		return false
	end
	local landPosition, inward = wallCandidate(root)
	if landPosition == nil or inward == nil then
		return false
	end

	local config = rockfallConfig()
	local size = rng:NextNumber(config.rockMinSize, config.rockMaxSize)
	local fallHeight = rng:NextNumber(config.fallMinHeight, config.fallMaxHeight)
	local tangent = Vector3.new(-inward.Z, 0, inward.X)
	local rollDirection = (inward + tangent * rng:NextNumber(-0.38, 0.38)).Unit
	local model = CaveKit.looseRock(ensureFolder(), CFrame.new(landPosition), size, {
		seed = rng:NextInteger(1, 1_000_000),
	})
	model:PivotTo(
		CFrame.new(landPosition + Vector3.yAxis * fallHeight) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	)
	active = {
		model = model,
		startedAt = now,
		dropStart = landPosition + Vector3.yAxis * fallHeight,
		landPosition = landPosition,
		rollDirection = rollDirection,
		rollDistance = rng:NextNumber(config.rollMinDistance, config.rollMaxDistance),
		yaw = rng:NextNumber(0, math.pi * 2),
		size = size,
		soundPlayed = false,
	}
	return true
end

local function renderRockfall(now: number, event: ActiveRockfall)
	local config = rockfallConfig()
	local elapsed = now - event.startedAt
	local dropProgress = math.clamp(elapsed / math.max(config.fallSeconds, 0.001), 0, 1)
	local position: Vector3
	if dropProgress < 1 then
		local gravityCurve = dropProgress * dropProgress
		position = event.dropStart:Lerp(event.landPosition, gravityCurve)
	else
		if not event.soundPlayed then
			local emitter = event.model.PrimaryPart
			if emitter ~= nil then
				AudioCues.playAt("AmbientRockfall", emitter)
			end
			event.soundPlayed = true
		end
		local rollProgress = math.clamp((elapsed - config.fallSeconds) / math.max(config.rollSeconds, 0.001), 0, 1)
		local eased = 1 - (1 - rollProgress) * (1 - rollProgress)
		local rollingPosition = event.landPosition + event.rollDirection * event.rollDistance * eased
		local ground = raycastGround(rollingPosition, event.model)
		position = if ground ~= nil then ground.Position else rollingPosition
	end

	local spin = elapsed * (10 + event.size * 7)
	event.model:PivotTo(
		CFrame.new(position + Vector3.yAxis * event.size * 0.12)
			* CFrame.Angles(spin, event.yaw + spin * 0.35, spin * 0.42)
	)
	if elapsed >= config.fallSeconds + config.rollSeconds + config.lingerSeconds then
		event.model:Destroy()
		active = nil
	end
end

local function expeditionChanged()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		return
	end
	local event = active
	if event ~= nil then
		event.model:Destroy()
		active = nil
	end
end

-- The director calls this only after it has won the shared ambience slot. Failure is cheap and
-- means "the sampled cave geometry could not support this event"; the director will reschedule
-- rather than falling back to a fake emitter.
function AmbientRockfallController.tryPlay(): boolean
	if
		not rockfallConfig().enabled
		or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true
		or active ~= nil
		or not AudioCues.isCueAvailable("AmbientRockfall")
	then
		return false
	end
	return spawnRockfall(os.clock())
end

function AmbientRockfallController.isActive(): boolean
	return active ~= nil
end

function AmbientRockfallController.start()
	local dressing = Config.Floors.caveDressing
	CaveKit.configure({
		palette = dressing.formationPalette,
		dampTint = dressing.formationDampTint,
		materials = dressing.formationMaterials,
		wetMaterial = dressing.formationWetMaterial,
		wetReflectance = dressing.formationWetReflectance,
	})
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(expeditionChanged)
	expeditionChanged()

	RunService:BindToRenderStep("WickAmbientRockfall", Enum.RenderPriority.Camera.Value + 3, function()
		local now = os.clock()
		local event = active
		if event ~= nil then
			if event.model.Parent == nil then
				active = nil
			else
				renderRockfall(now, event)
			end
		end
	end)
end

return AmbientRockfallController

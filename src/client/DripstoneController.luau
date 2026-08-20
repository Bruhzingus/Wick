--!strict
-- Local presentation for server-owned unstable dripstones. Replicated states and server timestamps
-- drive synchronized wobble/fall motion; dust, debris, spatial audio, camera shake, and grading are
-- cosmetic only. No client report can trigger or damage anything.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local DripstoneRules = require(ReplicatedStorage.Shared.Logic.DripstoneRules)
local DripstoneVisualProtocol = require(ReplicatedStorage.Shared.DripstoneVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CameraMotionController = require(script.Parent.CameraMotionController)

local DripstoneController = {}

type Entry = {
	model: Model,
	dust: ParticleEmitter?,
	stateConnection: RBXScriptConnection,
	dustRng: Random,
	nextDormantDustAt: number,
}

local player = Players.LocalPlayer
local entries: { [Model]: Entry } = {}
local impactGrade: ColorCorrectionEffect? = nil
local hitDimEndsAt = 0

local function visualConfig()
	return Config.Hazards.unstableDripstone
end

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function modelPosition(model: Model): Vector3
	local rest = model:GetAttribute(DripstoneVisualProtocol.attributes.restCFrame)
	return if typeof(rest) == "CFrame" then rest.Position else model:GetPivot().Position
end

local function isNear(model: Model, radius: number): boolean
	local root = localRoot()
	return root ~= nil and (modelPosition(model) - root.Position).Magnitude <= radius
end

local function readState(model: Model): string
	local value = model:GetAttribute(DripstoneVisualProtocol.attributes.state)
	return if typeof(value) == "string" then value else DripstoneVisualProtocol.states.dormant
end

local function stateChanged(entry: Entry)
	local model = entry.model
	local state = readState(model)
	local dust = entry.dust
	if dust ~= nil then
		dust.Enabled = false
		dust.Rate = 0
	end
	if state == DripstoneVisualProtocol.states.warning then
		if dust ~= nil then
			local config = visualConfig()
			dust.Enabled = true
			dust.Rate = config.warningDustRate
			dust:Emit(config.warningDustBurst)
		end
		local startedAt = model:GetAttribute(DripstoneVisualProtocol.attributes.stateStartedAt)
		local justStarted = typeof(startedAt) ~= "number"
			or workspace:GetServerTimeNow() - startedAt < visualConfig().warningAudioFreshSeconds
		if justStarted and isNear(model, Config.Hazards.unstableDripstone.presentationCullDistance) then
			local emitter = model.PrimaryPart
			if emitter ~= nil then
				AudioCues.playAt("DripstoneFracture", emitter)
			end
		end
	elseif state == DripstoneVisualProtocol.states.falling and dust ~= nil then
		local config = visualConfig()
		dust.Enabled = true
		dust.Rate = config.fallingDustRate
		dust:Emit(config.fallingDustBurst)
	end
end

local function add(instance: Instance)
	if not instance:IsA("Model") or entries[instance] ~= nil then
		return
	end
	local dustInstance = instance:FindFirstChild("DryFractureDust", true)
	local dust = if dustInstance ~= nil and dustInstance:IsA("ParticleEmitter") then dustInstance else nil
	local seedValue = instance:GetAttribute(DripstoneVisualProtocol.attributes.visualSeed)
	local seed = if typeof(seedValue) == "number" then math.floor(seedValue) else 1
	local rng = Random.new(seed)
	local entry: Entry
	entry = {
		model = instance,
		dust = dust,
		stateConnection = instance
			:GetAttributeChangedSignal(DripstoneVisualProtocol.attributes.state)
			:Connect(function()
				stateChanged(entry)
			end),
		dustRng = rng,
		nextDormantDustAt = workspace:GetServerTimeNow()
			+ rng:NextNumber(visualConfig().dormantDustMinSeconds, visualConfig().dormantDustMaxSeconds),
	}
	entries[instance] = entry
	stateChanged(entry)
end

local function remove(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local entry = entries[instance]
	if entry == nil then
		return
	end
	entry.stateConnection:Disconnect()
	entries[instance] = nil
end

local function renderFormation(entry: Entry)
	local model = entry.model
	if model.Parent == nil then
		return
	end
	local restValue = model:GetAttribute(DripstoneVisualProtocol.attributes.restCFrame)
	if typeof(restValue) ~= "CFrame" then
		return
	end
	local rest = restValue
	local config = Config.Hazards.unstableDripstone
	if not isNear(model, config.presentationCullDistance) then
		if entry.dust ~= nil then
			entry.dust.Enabled = false
		end
		return
	end

	local now = workspace:GetServerTimeNow()
	local state = readState(model)
	local startedValue = model:GetAttribute(DripstoneVisualProtocol.attributes.stateStartedAt)
	local startedAt = if typeof(startedValue) == "number" then startedValue else now
	local seedValue = model:GetAttribute(DripstoneVisualProtocol.attributes.visualSeed)
	local seed = if typeof(seedValue) == "number" then seedValue else 1
	local variantValue = model:GetAttribute(DripstoneVisualProtocol.attributes.variantId)
	local variantId = if typeof(variantValue) == "string" then variantValue else ""
	local variant = DripstoneRules.variantById(variantId)
	local fallDistanceValue = model:GetAttribute(DripstoneVisualProtocol.attributes.fallDistance)
	local fallDistance = if typeof(fallDistanceValue) == "number" then math.max(0, fallDistanceValue) else 0

	if state == DripstoneVisualProtocol.states.dormant then
		local tremorWave = math.max(0, math.sin(now * 0.82 + seed * 0.013)) ^ 18
		local angle = math.rad(config.dormantTremorDegrees) * tremorWave
		model:PivotTo(
			rest * CFrame.Angles(math.sin(now * 11 + seed) * angle, 0, math.cos(now * 9.7 + seed * 0.4) * angle)
		)
		if now >= entry.nextDormantDustAt then
			local dust = entry.dust
			if dust ~= nil then
				dust:Emit(entry.dustRng:NextInteger(config.dormantDustBurstMin, config.dormantDustBurstMax))
			end
			entry.nextDormantDustAt = now
				+ entry.dustRng:NextNumber(config.dormantDustMinSeconds, config.dormantDustMaxSeconds)
		end
	elseif state == DripstoneVisualProtocol.states.warning then
		local warningSeconds = if variant ~= nil then variant.warningSeconds else 1.7
		local progress = math.clamp((now - startedAt) / math.max(warningSeconds, 0.001), 0, 1)
		local stillnessStart = 1 - config.warningFinalStillFraction
		local stillness = if progress > stillnessStart
			then (1 - progress) / math.max(config.warningFinalStillFraction, 0.001)
			else 1
		local angle = math.rad(
			config.warningWobbleStartDegrees
				+ (config.warningWobbleEndDegrees - config.warningWobbleStartDegrees) * progress
		) * stillness
		local frequency = config.warningFrequencyStart + progress * config.warningFrequencyIncrease
		local vibration = config.warningVibrationStuds * progress * stillness
		model:PivotTo(
			rest
				* CFrame.new(
					math.sin(now * frequency * 1.3 + seed) * vibration,
					0,
					math.cos(now * frequency + seed * 0.3) * vibration
				)
				* CFrame.Angles(
					math.sin(now * frequency + seed) * angle,
					0,
					math.cos(now * frequency * 0.91 + seed * 0.7) * angle
				)
		)
	elseif state == DripstoneVisualProtocol.states.falling then
		local offset = DripstoneRules.fallOffset(now - startedAt, fallDistance)
		model:PivotTo(CFrame.new(0, -offset, 0) * rest)
	elseif state == DripstoneVisualProtocol.states.spent then
		model:PivotTo(CFrame.new(0, -fallDistance, 0) * rest)
	end
end

local function impactEmitter(position: Vector3): BasePart
	local emitter = Instance.new("Part")
	emitter.Name = "WickDripstoneImpact"
	emitter.Size = Vector3.one * 0.1
	emitter.Position = position + Vector3.new(0, 0.12, 0)
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.CastShadow = false
	emitter.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = emitter
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Enabled = false
	dust.Lifetime = NumberRange.new(0.65, 1.4)
	dust.Speed = NumberRange.new(2.5, 7)
	dust.Acceleration = Vector3.new(0, -5, 0)
	dust.SpreadAngle = Vector2.new(55, 55)
	dust.Rotation = NumberRange.new(-180, 180)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.Color = ColorSequence.new(Color3.fromRGB(88, 82, 73), Color3.fromRGB(42, 42, 45))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.4, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42),
		NumberSequenceKeypoint.new(0.72, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = attachment
	dust:Emit(visualConfig().impactDustBurst)
	Debris:AddItem(emitter, 4)
	return emitter
end

local function scatterDebris(position: Vector3)
	local rng = Random.new(math.floor(math.abs(position.X * 37 + position.Y * 101 + position.Z * 59)) + 17)
	local config = visualConfig()
	for _ = 1, config.impactDebrisCount do
		local shard = Instance.new("Part")
		shard.Name = "WickDripstoneDebris"
		shard.Size = Vector3.new(rng:NextNumber(0.12, 0.42), rng:NextNumber(0.1, 0.32), rng:NextNumber(0.12, 0.42))
		shard.Position = position + Vector3.new(0, rng:NextNumber(0.15, 0.55), 0)
		shard.Orientation = Vector3.new(rng:NextNumber(-180, 180), rng:NextNumber(-180, 180), rng:NextNumber(-180, 180))
		shard.Color = Color3.fromRGB(rng:NextInteger(48, 68), rng:NextInteger(49, 69), rng:NextInteger(55, 76))
		shard.Material = if rng:NextInteger(0, 1) == 0 then Enum.Material.Slate else Enum.Material.Basalt
		shard.Anchored = false
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		shard.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-7, 7), rng:NextNumber(4, 10), rng:NextNumber(-7, 7))
		shard.AssemblyAngularVelocity =
			Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
		shard.Parent = workspace
		Debris:AddItem(shard, config.impactDebrisLifetime)
	end
end

local function localPlayerWasHit(hitPlayerIds: any): boolean
	if typeof(hitPlayerIds) ~= "table" then
		return false
	end
	for _, playerId in hitPlayerIds do
		if typeof(playerId) == "number" and playerId == player.UserId then
			return true
		end
	end
	return false
end

local function handleImpact(payload: { [string]: any })
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local directHit = localPlayerWasHit(payload.hitPlayerIds)
	if directHit then
		AudioCues.play("DripstoneImpale")
	end
	local root = localRoot()
	if root == nil then
		return
	end
	local config = Config.Hazards.unstableDripstone
	local distance = (root.Position - position).Magnitude
	if distance > config.impactPresentationRadius then
		return
	end

	local emitter = impactEmitter(position)
	AudioCues.playAt("DripstoneImpact", emitter)
	scatterDebris(position)

	local proximity = 1 - math.clamp(distance / config.impactPresentationRadius, 0, 1)
	local strength = math.max(proximity, if directHit then 1 else 0)
	local now = os.clock()
	CameraMotionController.impulse({
		studs = config.impactShakeStuds,
		degrees = config.impactShakeDegrees,
		frequencyRadians = config.impactShakeFrequency,
		durationSeconds = config.impactShakeSeconds,
		strength = strength,
	})
	if directHit then
		hitDimEndsAt = now + config.impactDimSeconds
	end
end

function DripstoneController.start()
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WickDripstoneImpactGrade"
	grade.Enabled = false
	grade.Parent = Lighting
	impactGrade = grade

	for _, instance in CollectionService:GetTagged(DripstoneVisualProtocol.tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(DripstoneVisualProtocol.tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(DripstoneVisualProtocol.tag):Connect(remove)
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind == "dripstoneImpact" and typeof(payload) == "table" then
			handleImpact(payload)
		end
	end)

	RunService:BindToRenderStep("WickDripstonePresentation", Enum.RenderPriority.Camera.Value + 4, function()
		for _, entry in entries do
			renderFormation(entry)
		end

		local config = Config.Hazards.unstableDripstone
		local now = os.clock()
		local currentGrade = impactGrade
		if currentGrade ~= nil and now < hitDimEndsAt then
			local duration = math.max(config.impactDimSeconds, 0.001)
			local remaining = math.clamp((hitDimEndsAt - now) / duration, 0, 1)
			currentGrade.Enabled = true
			currentGrade.Brightness = config.impactDimBrightness * remaining * remaining
			currentGrade.Contrast = config.impactGradeContrast * remaining
			currentGrade.Saturation = config.impactGradeSaturation * remaining
		else
			if currentGrade ~= nil then
				currentGrade.Enabled = false
			end
		end
	end)
end

return DripstoneController

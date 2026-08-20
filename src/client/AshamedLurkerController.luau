--!strict
-- Local presentation for server-owned Ashamed Lurkers, plus the one thing only a client knows: where
-- its camera is looking. Bodies are built locally around the server's invisible proxy and animated
-- from the replicated state and timestamp, so every client sees the same lunge at the same moment.
-- Nothing here triggers, clears, relocates, or damages anything — the server owns all of that, and a
-- reported camera is only ever evidence it validates.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Logic.AshamedLurkerRules)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local Protocol = require(ReplicatedStorage.Shared.AshamedLurkerVisualProtocol)
local AshamedLurker = require(ReplicatedStorage.Shared.NewModelsAndObjects.AshamedLurker)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CameraMotionController = require(script.Parent.CameraMotionController)

local AshamedLurkerController = {}

type Entry = {
	proxy: BasePart,
	body: AshamedLurker.Lurker?,
	builtSite: number,
	nextBreathAt: number,
	stateConnection: RBXScriptConnection,
}

local player = Players.LocalPlayer
local entries: { [BasePart]: Entry } = {}
local bodiesFolder: Folder? = nil
local rng = Random.new()
local gazeAccumulator = 0
local grabGrade: ColorCorrectionEffect? = nil
local dimEndsAt = 0

local function config()
	return Config.AshamedLurker
end

local function attributeNumber(proxy: BasePart, name: string, fallback: number): number
	local value = proxy:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

local function proxyState(proxy: BasePart): string
	local value = proxy:GetAttribute(Protocol.attributes.state)
	return if type(value) == "string" then value else Protocol.states.dormant
end

local function trapSideOf(proxy: BasePart): Rules.TrapSide
	return Rules.normalizeTrapSide(proxy:GetAttribute(Protocol.attributes.trapSide))
end

local function destroyBody(entry: Entry)
	local body = entry.body
	if body ~= nil then
		body:destroy()
		entry.body = nil
	end
end

local function addProxy(instance: Instance)
	if not instance:IsA("BasePart") or entries[instance] ~= nil then
		return
	end
	local proxy = instance
	entries[proxy] = {
		proxy = proxy,
		body = nil,
		builtSite = -1,
		nextBreathAt = os.clock() + rng:NextNumber(
			config().presentation.breathMinIntervalSeconds,
			config().presentation.breathMaxIntervalSeconds
		),
		-- A lunge is a state change, not a separate message: everyone who can see the arch hears the
		-- joint crack whether or not the grab connects.
		stateConnection = proxy:GetAttributeChangedSignal(Protocol.attributes.state):Connect(function()
			if proxyState(proxy) == Protocol.states.triggered then
				AudioCues.playAt("LurkerLunge", proxy)
			end
		end),
	}
end

local function removeProxy(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local entry = entries[instance]
	if entry == nil then
		return
	end
	entries[instance] = nil
	entry.stateConnection:Disconnect()
	destroyBody(entry)
end

-- Dry, restrained breathing from the arch itself. It is the only warning a player gets in the dark,
-- and it is deliberately quiet: the tell is that something is breathing, not where exactly.
local function updateBreath(entry: Entry, state: string, distance: number, now: number)
	local presentation = config().presentation
	if now < entry.nextBreathAt then
		return
	end
	if state ~= Protocol.states.dormant or distance > presentation.breathAudibleDistance then
		entry.nextBreathAt = now + presentation.breathMinIntervalSeconds
		return
	end
	AudioCues.playAt("LurkerBreath", entry.proxy)
	entry.nextBreathAt = now
		+ rng:NextNumber(presentation.breathMinIntervalSeconds, presentation.breathMaxIntervalSeconds)
end

local function renderBodies(dt: number)
	local camera = Workspace.CurrentCamera
	local parent = bodiesFolder
	if camera == nil or parent == nil then
		return
	end

	local presentation = config().presentation
	local boundedDt = math.min(dt, presentation.maxAnimationDeltaSeconds)
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	local cameraPosition = camera.CFrame.Position

	for proxy, entry in entries do
		if proxy.Parent == nil then
			continue
		end
		local state = proxyState(proxy)
		local distance = (cameraPosition - proxy.Position).Magnitude
		updateBreath(entry, state, distance, now)

		local cullLimit = presentation.cullDistance + if entry.body ~= nil then presentation.cullHysteresis else 0
		-- A hidden creature has no body anywhere: it is not in this arch, it is between arches.
		if distance > cullLimit or state == Protocol.states.hidden then
			destroyBody(entry)
			continue
		end

		local site = math.floor(attributeNumber(proxy, Protocol.attributes.site, 1))
		local body = entry.body
		if body ~= nil and entry.builtSite ~= site then
			destroyBody(entry)
			body = nil
		end
		if body == nil then
			-- The rock this arch is actually made of, so the socket and the back plates disappear into
			-- the springer in every cave rather than only in Stone. Flesh is untouched: one creature,
			-- three walls.
			local familyId = proxy:GetAttribute(Protocol.attributes.familyId)
			local dressing = CaveFamilyRules.creatureDressing(if type(familyId) == "string" then familyId else nil)
			body = AshamedLurker.build(parent, {
				doorWidth = attributeNumber(proxy, Protocol.attributes.doorWidth, 12),
				doorHeight = attributeNumber(proxy, Protocol.attributes.doorHeight, 10.5),
				trapSide = trapSideOf(proxy),
				seed = math.floor(attributeNumber(proxy, Protocol.attributes.visualSeed, 1)),
				rockColor = dressing.rockColor,
				rockLightColor = dressing.rockLightColor,
				rockMaterial = dressing.rockMaterial,
			})
			body.model.Name = "Lurker_" .. proxy.Name
			CollectionService:AddTag(body.model, Config.Diagnostics.enemyVisualTag)
			entry.body = body
			entry.builtSite = site
		end

		body.root.CFrame = proxy.CFrame
		-- Server time, so a client that just built the body (or just joined) enters the animation at
		-- the same point everyone else is already at.
		local age = serverNow - attributeNumber(proxy, Protocol.attributes.stateStartedAt, serverNow)
		body:setState(state, math.max(0, age))
		body:step(boundedDt)
	end
end

-- Prefilter only. It is intentionally looser than the server's validation, and the server ignores a
-- sample it does not agree with rather than trusting this choice.
local function chooseGazeTarget(cameraPosition: Vector3, lookVector: Vector3): BasePart?
	local gaze = config().gaze
	local best: BasePart? = nil
	local bestScore = -math.huge
	for proxy, _entry in entries do
		if proxy.Parent == nil or proxyState(proxy) ~= Protocol.states.dormant then
			continue
		end
		local facePosition = Rules.facePosition(
			proxy.CFrame,
			attributeNumber(proxy, Protocol.attributes.doorWidth, 12),
			attributeNumber(proxy, Protocol.attributes.doorHeight, 10.5),
			trapSideOf(proxy)
		)
		local offset = facePosition - cameraPosition
		local distance = offset.Magnitude
		if distance <= 0.001 or distance > gaze.maxDistance then
			continue
		end
		local dot = lookVector:Dot(offset.Unit)
		if dot < gaze.dotThreshold - 0.1 then
			continue
		end
		local score = dot * 4 - distance * 0.02
		if score > bestScore then
			bestScore = score
			best = proxy
		end
	end
	return best
end

local function sampleGaze(dt: number)
	gazeAccumulator += dt
	local step = 1 / math.max(config().gaze.sampleHz, 1)
	if gazeAccumulator < step then
		return
	end
	gazeAccumulator = 0

	local camera = Workspace.CurrentCamera
	local character = player.Character
	if camera == nil or character == nil or character.Parent == nil then
		return
	end
	local target = chooseGazeTarget(camera.CFrame.Position, camera.CFrame.LookVector)
	if target ~= nil then
		Remotes.get("LurkerGaze"):FireServer(target, camera.CFrame.Position, camera.CFrame.LookVector)
	end
end

-- The scare. A connecting grab is meant to land hard on the player it hit and still be felt by
-- anyone nearby, so the shake is proximity-scaled and only the victim gets the grade.
local function onGrab(payload: { [string]: unknown })
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local presentation = config().presentation
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local distance = if root ~= nil and root:IsA("BasePart") then (root.Position - position).Magnitude else math.huge
	local hitLocally = payload.playerId == player.UserId
	if not hitLocally and distance > presentation.grabPresentationRadius then
		return
	end

	local emitter = Instance.new("Part")
	emitter.Name = "WickLurkerGrabEmitter"
	emitter.Size = Vector3.one
	emitter.Position = position
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.Parent = Workspace
	AudioCues.playAt("LurkerGrab", emitter)
	-- Layered on the same frame, not sequenced: see the LurkerImpact row in Config/Audio.
	AudioCues.playAt("LurkerImpact", emitter)
	task.delay(Config.Audio.cleanupSeconds, function()
		emitter:Destroy()
	end)

	local proximity = 1 - math.clamp(distance / presentation.grabPresentationRadius, 0, 1)
	local now = os.clock()
	CameraMotionController.impulse({
		studs = presentation.grabShakeStuds,
		degrees = presentation.grabShakeDegrees,
		frequencyRadians = presentation.grabShakeFrequency,
		durationSeconds = presentation.grabShakeSeconds,
		strength = if hitLocally then 1 else proximity,
	})
	if hitLocally then
		dimEndsAt = now + presentation.grabDimSeconds
	end
end

local function renderScare()
	local presentation = config().presentation
	local now = os.clock()
	local grade = grabGrade
	if grade == nil then
		return
	end
	if now < dimEndsAt then
		local duration = math.max(presentation.grabDimSeconds, 0.001)
		local remaining = math.clamp((dimEndsAt - now) / duration, 0, 1)
		grade.Enabled = true
		grade.Brightness = presentation.grabDimBrightness * remaining
		grade.Contrast = presentation.grabDimContrast * remaining
		grade.TintColor = Color3.new(1, 1, 1):Lerp(presentation.grabDimTint, remaining)
	elseif grade.Enabled then
		grade.Enabled = false
	end
end

function AshamedLurkerController.start()
	local folder = Instance.new("Folder")
	folder.Name = "WickLurkerBodies"
	folder.Parent = Workspace
	bodiesFolder = folder

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WickLurkerGrabGrade"
	grade.Enabled = false
	grade.Parent = Lighting
	grabGrade = grade

	for _, instance in CollectionService:GetTagged(Protocol.tag) do
		addProxy(instance)
	end
	CollectionService:GetInstanceAddedSignal(Protocol.tag):Connect(addProxy)
	CollectionService:GetInstanceRemovedSignal(Protocol.tag):Connect(removeProxy)

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: unknown)
		if kind == "lurkerGrab" and type(payload) == "table" then
			onGrab(payload :: { [string]: unknown })
		end
	end)

	RunService:BindToRenderStep("WickAshamedLurker", Enum.RenderPriority.Camera.Value + 5, function(dt: number)
		renderBodies(dt)
		sampleGaze(dt)
		renderScare()
	end)
end

return AshamedLurkerController

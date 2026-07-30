--!strict
-- One scheduler for every harmless cave one-shot. The director deliberately selects silence,
-- prevents immediate family repeats, waits for high-priority audio to clear, and refuses to invent
-- an emitter when real cave geometry cannot support one. It owns presentation only: no remotes,
-- hitboxes, threat noise, or server state.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FeelConfig = require(ReplicatedStorage.Shared.Config.Feel)
local AmbientRockfallController = require(script.Parent.AmbientRockfallController)
local AmbientWaterDripController = require(script.Parent.AmbientWaterDripController)
local AudioCues = require(script.Parent.AudioCues)

local AmbientCaveDirector = {}

type SoundEvent = FeelConfig.AmbientSoundEvent
type CandidateKind = "Rockfall" | "WaterDrip" | "Sound"
type Candidate = {
	id: string,
	kind: CandidateKind,
	weight: number,
	soundEvent: SoundEvent?,
}

local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local FOCUS_BUS = "Focus"
local ROCKFALL_ID = "Rockfall"
local WATER_DRIP_ID = "WaterDrip"

local player = Players.LocalPlayer
local rng = Random.new()
local nextEventAt = math.huge
local activeUntil = -math.huge
local generation = 0
local recentFamilies: { string } = {}
local emitterFolder: Folder? = nil

local function directorConfig()
	return Config.Feel.ambientCave
end

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function ensureEmitterFolder(): Folder
	local current = emitterFolder
	if current ~= nil and current.Parent ~= nil then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = "WickAmbientCaveSounds"
	created.Parent = workspace
	emitterFolder = created
	return created
end

local function raycastParams(allowWater: boolean?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local characters: { Instance } = {}
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		if character ~= nil then
			table.insert(characters, character)
		end
	end
	params.FilterDescendantsInstances = characters
	params.IgnoreWater = allowWater ~= true
	return params
end

local function flat(vector: Vector3): Vector3?
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	return if flattened.Magnitude > 0 then flattened.Unit else nil
end

local function directionIsUseful(direction: Vector3): boolean
	local camera = workspace.CurrentCamera
	if camera == nil then
		return true
	end
	local forward = flat(camera.CFrame.LookVector)
	return forward == nil or direction:Dot(forward) <= directorConfig().maxForwardDot
end

-- Find a source on the requested real surface. Sampling a direction per attempt avoids the
-- predictable "always behind you" horror-game tell while `maxForwardDot` keeps a sound-only event
-- out of the player's central, visibly empty aim cone.
local function sourcePosition(root: BasePart, event: SoundEvent): Vector3?
	local config = directorConfig()
	local params = raycastParams(event.allowWater)
	for _attempt = 1, config.emitterSearchAttempts do
		local yaw = rng:NextNumber(-math.pi, math.pi)
		local direction = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		if not directionIsUseful(direction) then
			continue
		end

		if event.surface == "Wall" then
			local hit = workspace:Raycast(root.Position, direction * event.maxDistance, params)
			if hit ~= nil and hit.Distance >= event.minDistance and math.abs(hit.Normal.Y) <= config.wallNormalMaxY then
				return hit.Position - hit.Normal * config.sourceInset
			end
		else
			local distance = rng:NextNumber(event.minDistance, event.maxDistance)
			local offset = direction * distance
			if event.surface == "Ceiling" then
				local hit =
					workspace:Raycast(root.Position + offset, Vector3.yAxis * config.ceilingProbeDistance, params)
				if hit ~= nil and hit.Normal.Y <= config.ceilingNormalMaxY then
					return hit.Position - hit.Normal * config.sourceInset
				end
			else
				local origin = root.Position + offset + Vector3.yAxis * config.groundProbeHeight
				local hit = workspace:Raycast(origin, -Vector3.yAxis * config.groundProbeDistance, params)
				if hit ~= nil and hit.Normal.Y >= config.groundNormalMinY then
					return hit.Position - hit.Normal * config.sourceInset
				end
			end
		end
	end
	return nil
end

local function createEmitter(position: Vector3): BasePart
	local emitter = Instance.new("Part")
	emitter.Name = "WickAmbientCaveEmitter"
	emitter.Size = Vector3.one * directorConfig().emitterSize
	emitter.Position = position
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.CastShadow = false
	emitter.Parent = ensureEmitterFolder()
	Debris:AddItem(emitter, directorConfig().emitterLifetimeSeconds)
	return emitter
end

local function playSoundEvent(event: SoundEvent, now: number): boolean
	local root = localRoot()
	if root == nil then
		return false
	end
	local position = sourcePosition(root, event)
	if position == nil then
		return false
	end

	local emitter = createEmitter(position)
	local expectedGeneration = generation
	local burstMinimum = math.max(1, math.floor(event.burstsMin))
	local burstMaximum = math.max(burstMinimum, math.floor(event.burstsMax))
	local burstCount = rng:NextInteger(burstMinimum, burstMaximum)
	if not AudioCues.playAt(event.cueName, emitter, rng:NextNumber(event.pitchMin, event.pitchMax)) then
		emitter:Destroy()
		return false
	end
	activeUntil = now + event.durationSeconds

	if burstCount > 1 then
		task.spawn(function()
			for _burst = 2, burstCount do
				task.wait(rng:NextNumber(event.burstGapMinSeconds, event.burstGapMaxSeconds))
				if
					generation ~= expectedGeneration
					or emitter.Parent == nil
					or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true
				then
					return
				end
				AudioCues.playAt(event.cueName, emitter, rng:NextNumber(event.pitchMin, event.pitchMax))
			end
		end)
	end
	return true
end

local function isRecent(id: string): boolean
	for _, recent in recentFamilies do
		if recent == id then
			return true
		end
	end
	return false
end

local function candidates(): { Candidate }
	local config = directorConfig()
	local result: { Candidate } = {}
	if Config.Feel.ambientRockfall.enabled and not isRecent(ROCKFALL_ID) then
		table.insert(result, {
			id = ROCKFALL_ID,
			kind = "Rockfall",
			weight = config.rockfallWeight,
			soundEvent = nil,
		})
	end
	if Config.Feel.ambientWaterDrip.enabled and not isRecent(WATER_DRIP_ID) then
		table.insert(result, {
			id = WATER_DRIP_ID,
			kind = "WaterDrip",
			weight = config.waterDripWeight,
			soundEvent = nil,
		})
	end
	for _, event in config.soundEvents do
		if not isRecent(event.id) then
			table.insert(result, {
				id = event.id,
				kind = "Sound",
				weight = event.weight,
				soundEvent = event,
			})
		end
	end
	return result
end

local function chooseCandidate(): Candidate?
	local config = directorConfig()
	local available = candidates()
	local totalWeight = math.max(config.silentWeight, 0)
	for _, candidate in available do
		totalWeight += math.max(candidate.weight, 0)
	end
	if totalWeight <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, totalWeight)
	if roll < config.silentWeight then
		return nil
	end
	roll -= config.silentWeight
	for _, candidate in available do
		roll -= math.max(candidate.weight, 0)
		if roll <= 0 then
			return candidate
		end
	end
	return available[#available]
end

local function remember(id: string)
	table.insert(recentFamilies, id)
	local limit = math.max(0, math.floor(directorConfig().recentFamilyCount))
	while #recentFamilies > limit do
		table.remove(recentFamilies, 1)
	end
end

local function schedule(now: number, initial: boolean, retry: boolean)
	local config = directorConfig()
	if initial then
		nextEventAt = now + rng:NextNumber(config.initialDelayMinSeconds, config.initialDelayMaxSeconds)
		return
	end
	if retry then
		nextEventAt = now + config.retryDelaySeconds
		return
	end
	local refractory = rng:NextNumber(config.refractoryMinSeconds, config.refractoryMaxSeconds)
	local unit = rng:NextNumber()
	local exponential = -math.log(1 - unit) * config.meanSilenceSeconds
	nextEventAt = now + refractory + math.min(exponential, config.maxSilenceSeconds)
end

local function attempt(now: number)
	local selected = chooseCandidate()
	if selected == nil then
		schedule(now, false, false)
		return
	end

	local played = false
	if selected.kind == "Rockfall" then
		played = AmbientRockfallController.tryPlay()
		if played then
			local rockfall = Config.Feel.ambientRockfall
			activeUntil = now + rockfall.fallSeconds + rockfall.rollSeconds + rockfall.lingerSeconds
		end
	elseif selected.kind == "WaterDrip" then
		played = AmbientWaterDripController.tryPlay()
		if played then
			activeUntil = now + Config.Feel.ambientWaterDrip.emitterLifetimeSeconds
		end
	else
		local event = selected.soundEvent
		played = if event ~= nil then playSoundEvent(event, now) else false
	end

	if played then
		remember(selected.id)
	end
	schedule(now, false, not played)
end

local function expeditionChanged()
	generation += 1
	activeUntil = -math.huge
	table.clear(recentFamilies)
	local currentFolder = emitterFolder
	if currentFolder ~= nil then
		currentFolder:Destroy()
		emitterFolder = nil
	end
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		schedule(os.clock(), true, false)
	else
		nextEventAt = math.huge
	end
end

function AmbientCaveDirector.start()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(expeditionChanged)
	expeditionChanged()

	RunService.Heartbeat:Connect(function()
		local config = directorConfig()
		if not config.enabled or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
			return
		end
		local now = os.clock()
		if now < nextEventAt or now < activeUntil then
			return
		end
		if not AudioCues.isBusQuiet(FOCUS_BUS, config.focusQuietSeconds) then
			-- Spend this opportunity and draw a fresh long interval. Firing on a fixed retry after
			-- mining or danger would make harmless ambience feel causally scripted to gameplay.
			schedule(now, false, false)
			return
		end
		attempt(now)
	end)
end

return AmbientCaveDirector

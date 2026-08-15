--!strict
-- One scheduler for every harmless cave one-shot. The director deliberately selects silence,
-- prevents immediate family repeats, waits for high-priority audio to clear, and refuses to invent
-- an emitter when real cave geometry cannot support one. It owns presentation only: no remotes,
-- hitboxes, threat noise, or server state.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local FeelConfig = require(ReplicatedStorage.Shared.Config.Feel)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local MineRelicVisualProtocol = require(ReplicatedStorage.Shared.MineRelicVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AmbientRockfallController = require(script.Parent.AmbientRockfallController)
local AmbientWaterDripController = require(script.Parent.AmbientWaterDripController)
local AudioCues = require(script.Parent.AudioCues)

local AmbientCaveDirector = {}

type SoundEvent = FeelConfig.AmbientSoundEvent
type CandidateKind = "Rockfall" | "WaterDrip" | "Relic" | "Sound"
type Candidate = {
	id: string,
	kind: CandidateKind,
	weight: number,
	soundEvent: SoundEvent?,
}

local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local FOCUS_BUS = "Focus"
-- Shared with Logic/CaveFamilyRules so the id a family weights and the id this file rolls are one
-- spelling. Two copies would fail open: the weighting would silently do nothing and validation would
-- still report the family complete.
local ROCKFALL_ID = CaveFamilyRules.ambientRockfallId
local WATER_DRIP_ID = CaveFamilyRules.ambientWaterDripId
local RELIC_ID = CaveFamilyRules.ambientRelicId

local player = Players.LocalPlayer
local rng = Random.new()
local nextEventAt = math.huge
local activeUntil = -math.huge
local generation = 0
-- ANTI-REPEAT HISTORY for ambient SOUND-EVENT families — the grouping that stops the same flavour of
-- one-shot landing twice in a row. Nothing to do with CAVE families; see `caveFamilyId` below, which
-- is the unrelated thing that happens to share the word.
local recentFamilies: { string } = {}
-- WHICH CAVE this run is in, so the director can weight what the cave says (Stone, Moss and Ice roll
-- the same candidates at very different rates). Resolved through CaveFamilyRules like every other
-- consumer, so an absent or unknown id plays the free family's soundscape rather than nothing.
local caveFamilyId: string? = nil
local emitterFolder: Folder? = nil

local function directorConfig()
	return Config.Feel.ambientCave
end

local function caveFamily()
	return CaveFamilyRules.resolve(caveFamilyId)
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

-- THE ONE AMBIENT EVENT THAT COMES FROM A REAL OBJECT. Every other candidate here raycasts the cave
-- for a surface to speak from; this one looks for an abandoned working the server actually built
-- (`Config/MineRelics`) and hangs the cue on that model's own acoustic centre.
--
-- IT REFUSES FAR MORE OFTEN THAN IT FIRES, and that is the design. Most floors have no equipment on
-- them at all, and the ones that do have one or two pieces in a cave sixty studs across — so the
-- honest answer to "is there something here that could creak" is usually no, and returning false
-- sends the director back round to pick something else. A fallback emitter would make every cave
-- sound like it had machinery in it.
local function playRelicEvent(now: number): boolean
	local config = Config.Feel.ambientRelic
	if not config.enabled or not AudioCues.isCueAvailable(config.cueName) then
		return false
	end
	local root = localRoot()
	if root == nil then
		return false
	end

	-- Distance alone does the floor filtering: floors are stacked far enough apart
	-- (`Config/Floors.geometry.floorGap`) that a relic on another one can never fall inside this band.
	local inRange: { Vector3 } = {}
	for _, relic in CollectionService:GetTagged(MineRelicVisualProtocol.tag) do
		if not relic:IsA("Model") then
			continue
		end
		local anchor = relic.PrimaryPart
		local emitter = if anchor ~= nil then anchor:FindFirstChild(MineRelicVisualProtocol.emitterName) else nil
		if emitter == nil or not emitter:IsA("Attachment") then
			continue
		end
		local position = emitter.WorldPosition
		local distance = (position - root.Position).Magnitude
		if distance >= config.minDistance and distance <= config.maxDistance then
			table.insert(inRange, position)
		end
	end
	if #inRange == 0 then
		return false
	end

	-- Any piece in range rather than the nearest one: always choosing the closest would make a party
	-- standing between two carts hear the same one every time.
	local emitter = createEmitter(inRange[rng:NextInteger(1, #inRange)])
	local expectedGeneration = generation
	local burstMinimum = math.max(1, math.floor(config.burstsMin))
	local burstCount = rng:NextInteger(burstMinimum, math.max(burstMinimum, math.floor(config.burstsMax)))
	if not AudioCues.playAt(config.cueName, emitter, rng:NextNumber(config.pitchMin, config.pitchMax)) then
		emitter:Destroy()
		return false
	end
	activeUntil = now + config.durationSeconds

	if burstCount > 1 then
		task.spawn(function()
			for _burst = 2, burstCount do
				task.wait(rng:NextNumber(config.burstGapMinSeconds, config.burstGapMaxSeconds))
				if
					generation ~= expectedGeneration
					or emitter.Parent == nil
					or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true
				then
					return
				end
				AudioCues.playAt(config.cueName, emitter, rng:NextNumber(config.pitchMin, config.pitchMax))
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

-- WHAT THIS CAVE IS LIKELY TO SAY. Every candidate's authored weight is scaled by the cave family's
-- own (Logic/CaveFamilyRules.ambientWeightMultiplier), which is the whole of the per-family
-- soundscape: Moss ticks and seeps, Ice groans and strains, Stone is the baseline both were authored
-- against. A family may zero a candidate outright, which is how an event belongs to one cave only —
-- so a zero-weight candidate is dropped from the pool here rather than left in it. `rng:NextNumber`
-- can return exactly 0, and a leading zero-weight row would then satisfy the roll and be picked.
local function candidates(): { Candidate }
	local config = directorConfig()
	local family = caveFamily()
	local result: { Candidate } = {}
	local function offer(id: string, kind: CandidateKind, authoredWeight: number, soundEvent: SoundEvent?)
		if isRecent(id) then
			return
		end
		local weight = math.max(0, authoredWeight) * CaveFamilyRules.ambientWeightMultiplier(family, id)
		if weight <= 0 then
			return
		end
		table.insert(result, { id = id, kind = kind, weight = weight, soundEvent = soundEvent })
	end

	if Config.Feel.ambientRockfall.enabled then
		offer(ROCKFALL_ID, "Rockfall", config.rockfallWeight, nil)
	end
	if Config.Feel.ambientWaterDrip.enabled then
		offer(WATER_DRIP_ID, "WaterDrip", config.waterDripWeight, nil)
	end
	if Config.Feel.ambientRelic.enabled then
		offer(RELIC_ID, "Relic", config.relicWeight, nil)
	end
	for _, event in config.soundEvents do
		offer(event.id, "Sound", event.weight, event)
	end
	return result
end

local function chooseCandidate(): Candidate?
	local config = directorConfig()
	local available = candidates()
	-- The authored non-event, scaled by how talkative this cave is. Only the RATE moves: no family
	-- touches a cue's gain, its bus, or the mixer, which is what keeps a quieter cave from becoming a
	-- cave that hides an approach.
	local silentWeight = math.max(config.silentWeight, 0) * CaveFamilyRules.ambientSilenceMultiplier(caveFamily())
	local totalWeight = silentWeight
	for _, candidate in available do
		totalWeight += math.max(candidate.weight, 0)
	end
	if totalWeight <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, totalWeight)
	if roll < silentWeight then
		return nil
	end
	roll -= silentWeight
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
	elseif selected.kind == "Relic" then
		-- Sets its own `activeUntil` on success, exactly as `playSoundEvent` does, because both own a
		-- cue duration the director has no other way to know.
		played = playRelicEvent(now)
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

-- The run's cave family, taken from the same "floor" message the camera and the settings controller
-- already bind to. `familyId` is the canonical persisted string; `tierId` is its legacy numeric
-- projection and is read only as a fallback, so a payload from an older server still resolves. Anything
-- unrecognised falls through CaveFamilyRules.resolve to the free family, which is a real soundscape
-- rather than silence.
local function floorAnnounced(payload: { [string]: any })
	local declared = payload.familyId
	if type(declared) == "string" and CaveFamilyRules.isValidId(declared) then
		caveFamilyId = declared
		return
	end
	local tierId = tonumber(payload.tierId)
	local fromTier = if tierId ~= nil then CaveFamilyRules.fromLegacyTierId(tierId) else nil
	caveFamilyId = if fromTier ~= nil then fromTier.id else nil
end

function AmbientCaveDirector.start()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(expeditionChanged)
	expeditionChanged()

	-- `any` is confined to this untyped RemoteEvent boundary; both fields are validated before use.
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind == "floor" and typeof(payload) == "table" then
			floorAnnounced(payload)
		end
	end)

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

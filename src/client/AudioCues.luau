--!strict
-- Config-driven client audio adapter. Callers name gameplay events; this module owns the local
-- mix graph, lifecycle, throttling, variation, bounded polyphony, preload, and empty-ID no-op path.
-- It never decides gameplay state.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local AudioCues = {}

type CueDef = {
	assetId: string,
	volume: number,
	playbackSpeed: number,
	looped: boolean,
	cooldownSeconds: number,
	bus: string,
	volumeMinMultiplier: number,
	volumeMaxMultiplier: number,
	pitchMinMultiplier: number,
	pitchMaxMultiplier: number,
	maxVoices: number,
	maxDurationSeconds: number?,
	fadeOutSeconds: number,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?,
	emitterSize: number?,
}

type EqualizerDef = {
	lowGain: number,
	midGain: number,
	highGain: number,
}

type ReverbDef = {
	decayTime: number,
	density: number,
	diffusion: number,
	dryLevel: number,
	wetLevel: number,
}

type DuckingDef = {
	sidechainBus: string,
	threshold: number,
	attack: number,
	release: number,
	ratio: number,
}

type BusDef = {
	volume: number,
	voiceLimit: number,
	equalizer: EqualizerDef?,
	reverb: ReverbDef?,
	ducking: DuckingDef?,
}

type OcclusionDef = {
	enabled: boolean,
	volumeMultiplier: number,
	lowGain: number,
	midGain: number,
	highGain: number,
}

type AudioConfig = {
	enabled: boolean,
	cleanupSeconds: number,
	maxActiveVoices: number,
	defaultBus: string,
	occlusion: OcclusionDef,
	buses: { [string]: BusDef },
	cues: { [string]: CueDef },
}

type ActiveVoice = {
	sound: Sound,
	cueName: string,
	busName: string,
	startedAt: number,
	ending: boolean,
}

type VoicePredicate = (voice: ActiveVoice) -> boolean

local MASTER_GROUP_NAME = "WickMaster"
local BUS_GROUP_PREFIX = "Wick"
local EQUALIZER_NAME = "WickEqualizer"
local REVERB_NAME = "WickReverb"
local DUCKING_NAME = "WickFocusDucking"
local OCCLUSION_EQUALIZER_NAME = "WickOcclusion"

local container: Folder? = nil
local masterGroup: SoundGroup? = nil
local busGroups: { [string]: SoundGroup } = {}
local graphReady = false
local activeLoops: { [string]: Sound } = {}
local activeVoices: { ActiveVoice } = {}
-- Non-spatial/UI throttles are global. Spatial throttles are emitter-scoped so two miners or two
-- threats acting in the same instant remain two truthful world events instead of muting each other.
local lastPlayedAt: { [string]: number } = {}
local lastPlayedAtByEmitter =
	setmetatable({}, { __mode = "k" }) :: { [Instance]: { [string]: number } }
local lastPlayedAtByBus: { [string]: number } = {}
local volumeMultiplier = 1
local preloadStarted = false
local rng = Random.new()

local function audioConfig(): AudioConfig
	return Config.Audio :: AudioConfig
end

local function finiteOr(value: number, fallback: number): number
	return if value == value and value > -math.huge and value < math.huge then value else fallback
end

local function ensureMasterGroup(): SoundGroup
	local current = masterGroup
	if current ~= nil and current.Parent ~= nil then
		current.Volume = volumeMultiplier
		return current
	end

	local existing = SoundService:FindFirstChild(MASTER_GROUP_NAME)
	local group: SoundGroup
	if existing ~= nil and existing:IsA("SoundGroup") then
		group = existing
	else
		group = Instance.new("SoundGroup")
		group.Name = MASTER_GROUP_NAME
		group.Parent = SoundService
	end
	group.Volume = volumeMultiplier

	masterGroup = group
	table.clear(busGroups)
	graphReady = false
	return group
end

local function ensureContainer(): Folder
	local current = container
	if current ~= nil and current.Parent ~= nil then
		return current
	end

	local existing = SoundService:FindFirstChild("WickAudio")
	local folder: Folder
	if existing ~= nil and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "WickAudio"
		folder.Parent = SoundService
	end
	container = folder
	return folder
end

local function effectOfClass(parent: SoundGroup, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing ~= nil and existing.ClassName == className then
		return existing
	end
	if existing ~= nil then
		existing:Destroy()
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local function removeEffect(parent: SoundGroup, name: string)
	local existing = parent:FindFirstChild(name)
	if existing ~= nil then
		existing:Destroy()
	end
end

local function configureEqualizer(group: SoundGroup, definition: EqualizerDef?)
	if definition == nil then
		removeEffect(group, EQUALIZER_NAME)
		return
	end
	local effect = effectOfClass(group, EQUALIZER_NAME, "EqualizerSoundEffect") :: EqualizerSoundEffect
	effect.Priority = 30
	effect.LowGain = math.clamp(finiteOr(definition.lowGain, 0), -80, 10)
	effect.MidGain = math.clamp(finiteOr(definition.midGain, 0), -80, 10)
	effect.HighGain = math.clamp(finiteOr(definition.highGain, 0), -80, 10)
end

local function configureReverb(group: SoundGroup, definition: ReverbDef?)
	if definition == nil then
		removeEffect(group, REVERB_NAME)
		return
	end
	local effect = effectOfClass(group, REVERB_NAME, "ReverbSoundEffect") :: ReverbSoundEffect
	effect.Priority = 20
	effect.DecayTime = math.clamp(finiteOr(definition.decayTime, 1.5), 0.1, 20)
	effect.Density = math.clamp(finiteOr(definition.density, 1), 0, 1)
	effect.Diffusion = math.clamp(finiteOr(definition.diffusion, 1), 0, 1)
	effect.DryLevel = math.clamp(finiteOr(definition.dryLevel, 0), -80, 10)
	effect.WetLevel = math.clamp(finiteOr(definition.wetLevel, -80), -80, 10)
end

local function configureDucking(group: SoundGroup, definition: DuckingDef?)
	if definition == nil then
		removeEffect(group, DUCKING_NAME)
		return
	end
	local sidechain = busGroups[definition.sidechainBus]
	if sidechain == nil or sidechain.Parent == nil then
		removeEffect(group, DUCKING_NAME)
		warn(
			string.format(
				"[WICK AUDIO] Bus %s cannot sidechain from unknown bus %s",
				group.Name,
				definition.sidechainBus
			)
		)
		return
	end
	local effect = effectOfClass(group, DUCKING_NAME, "CompressorSoundEffect") :: CompressorSoundEffect
	effect.Priority = 10
	effect.Threshold = math.clamp(finiteOr(definition.threshold, -20), -80, 0)
	effect.Attack = math.clamp(finiteOr(definition.attack, 0.1), 0.1, 1)
	effect.Release = math.clamp(finiteOr(definition.release, 0.1), 0, 5)
	effect.Ratio = math.clamp(finiteOr(definition.ratio, 2), 1, 50)
	effect.GainMakeup = 0
	effect.SideChain = sidechain
end

local function busGraphIsValid(master: SoundGroup): boolean
	if not graphReady then
		return false
	end
	for busName in audioConfig().buses do
		local group = busGroups[busName]
		if group == nil or group.Parent ~= master then
			return false
		end
	end
	return true
end

local function ensureBusGraph()
	local master = ensureMasterGroup()
	if busGraphIsValid(master) then
		return
	end

	table.clear(busGroups)
	local buses = audioConfig().buses
	-- All groups must exist before effects are configured because compressors refer to their
	-- sidechain group.
	for busName, definition in buses do
		local expectedName = BUS_GROUP_PREFIX .. busName
		local existing = master:FindFirstChild(expectedName)
		local group: SoundGroup
		if existing ~= nil and existing:IsA("SoundGroup") then
			group = existing
		else
			group = Instance.new("SoundGroup")
			group.Name = expectedName
			group.Parent = master
		end
		group.Volume = math.clamp(finiteOr(definition.volume, 1), 0, 10)
		busGroups[busName] = group
	end
	for busName, definition in buses do
		local group = busGroups[busName]
		if group ~= nil then
			configureEqualizer(group, definition.equalizer)
			configureReverb(group, definition.reverb)
			configureDucking(group, definition.ducking)
		end
	end
	graphReady = true
end

local function resolvedBusName(busName: string): string
	local config = audioConfig()
	if config.buses[busName] ~= nil then
		return busName
	end
	if config.buses[config.defaultBus] ~= nil then
		return config.defaultBus
	end
	if config.buses.World ~= nil then
		return "World"
	end
	for candidate in config.buses do
		return candidate
	end
	return ""
end

local function getBusGroup(busName: string): SoundGroup
	ensureBusGraph()
	local resolved = resolvedBusName(busName)
	local group = busGroups[resolved]
	if group ~= nil and group.Parent ~= nil then
		return group
	end

	graphReady = false
	ensureBusGraph()
	return busGroups[resolved] or ensureMasterGroup()
end

local function soundIdFor(assetId: string): string?
	if assetId == "" then
		return nil
	end
	if string.match(assetId, "^rbxassetid://%d+$") ~= nil then
		return assetId
	end
	if string.match(assetId, "^rbxasset://sounds/[%w%._%-]+$") ~= nil then
		return assetId
	end
	if string.match(assetId, "^%d+$") ~= nil then
		return "rbxassetid://" .. assetId
	end
	return nil
end

local function randomBetween(first: number, second: number): number
	local low = finiteOr(math.min(first, second), 1)
	local high = finiteOr(math.max(first, second), low)
	if high <= low then
		return low
	end
	return rng:NextNumber(low, high)
end

local function emitterPosition(parent: Instance): Vector3?
	if parent:IsA("BasePart") then
		return parent.Position
	end
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

-- Short spatial cues sample obstruction once at playback. The direct path is filtered while the bus
-- reverb remains intact, preserving a believable tail through rock without a per-frame raycast cost.
local function applyOcclusion(sound: Sound, parent: Instance)
	local definition = audioConfig().occlusion
	if not definition.enabled then
		return
	end
	local source = emitterPosition(parent)
	local camera = Workspace.CurrentCamera
	if source == nil or camera == nil then
		return
	end
	local direction = source - camera.CFrame.Position
	local distance = direction.Magnitude
	if distance <= 0.5 then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}
	params.IgnoreWater = true
	local result = Workspace:Raycast(camera.CFrame.Position, direction, params)
	local sourceModel = parent:FindFirstAncestorOfClass("Model")
	if
		result == nil
		or result.Distance >= distance - 0.5
		or result.Instance == parent
		or (parent:IsA("Attachment") and result.Instance == parent.Parent)
		or (sourceModel ~= nil and result.Instance:IsDescendantOf(sourceModel))
	then
		return
	end

	sound.Volume *= math.clamp(finiteOr(definition.volumeMultiplier, 0.7), 0, 1)
	local equalizer = Instance.new("EqualizerSoundEffect")
	equalizer.Name = OCCLUSION_EQUALIZER_NAME
	equalizer.Priority = 40
	equalizer.LowGain = math.clamp(finiteOr(definition.lowGain, 0), -80, 10)
	equalizer.MidGain = math.clamp(finiteOr(definition.midGain, -5), -80, 10)
	equalizer.HighGain = math.clamp(finiteOr(definition.highGain, -18), -80, 10)
	equalizer.Parent = sound
end

local function removeVoice(sound: Sound)
	for index = #activeVoices, 1, -1 do
		local voice = activeVoices[index]
		if voice.sound == sound then
			table.remove(activeVoices, index)
			if activeLoops[voice.cueName] == sound then
				activeLoops[voice.cueName] = nil
			end
			return
		end
	end
end

local function destroyVoice(sound: Sound)
	removeVoice(sound)
	if sound.Parent ~= nil then
		sound:Stop()
		sound:Destroy()
	end
end

local function purgeVoices()
	for index = #activeVoices, 1, -1 do
		local voice = activeVoices[index]
		if voice.sound.Parent == nil then
			table.remove(activeVoices, index)
			if activeLoops[voice.cueName] == voice.sound then
				activeLoops[voice.cueName] = nil
			end
		end
	end
end

local function countVoices(predicate: VoicePredicate): number
	local count = 0
	for _, voice in activeVoices do
		if predicate(voice) then
			count += 1
		end
	end
	return count
end

local function stealOldest(predicate: VoicePredicate): boolean
	local oldest: ActiveVoice? = nil
	for _, voice in activeVoices do
		if predicate(voice) and (oldest == nil or voice.startedAt < oldest.startedAt) then
			oldest = voice
		end
	end
	if oldest == nil then
		return false
	end
	destroyVoice(oldest.sound)
	return true
end

local function stealUntilBelow(limit: number, predicate: VoicePredicate)
	local boundedLimit = math.max(1, math.floor(finiteOr(limit, 1)))
	while countVoices(predicate) >= boundedLimit do
		if not stealOldest(predicate) then
			return
		end
	end
end

local function enforceVoiceLimits(cueName: string, busName: string, cue: CueDef)
	purgeVoices()
	stealUntilBelow(cue.maxVoices, function(voice: ActiveVoice): boolean
		return voice.cueName == cueName
	end)
	local busDefinition = audioConfig().buses[busName]
	if busDefinition ~= nil then
		stealUntilBelow(busDefinition.voiceLimit, function(voice: ActiveVoice): boolean
			return voice.busName == busName
		end)
	end
	stealUntilBelow(audioConfig().maxActiveVoices, function(_voice: ActiveVoice): boolean
		return true
	end)
end

local function scheduleMaximumDuration(voice: ActiveVoice, cue: CueDef)
	local configuredMaximum = cue.maxDurationSeconds
	if cue.looped or configuredMaximum == nil then
		return
	end
	local maximum = finiteOr(configuredMaximum, 0)
	if maximum <= 0 then
		return
	end
	local fadeSeconds = math.clamp(finiteOr(cue.fadeOutSeconds, 0), 0, maximum)
	task.delay(maximum - fadeSeconds, function()
		local sound = voice.sound
		if sound.Parent == nil then
			return
		end
		voice.ending = true
		if fadeSeconds <= 0 then
			destroyVoice(sound)
			return
		end
		local tween = TweenService:Create(
			sound,
			TweenInfo.new(fadeSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Volume = 0 }
		)
		tween:Play()
		task.delay(fadeSeconds, function()
			if sound.Parent ~= nil then
				destroyVoice(sound)
			end
		end)
	end)
end

local function beginPreload()
	if preloadStarted then
		return
	end
	preloadStarted = true
	task.spawn(function()
		local preloadSounds: { Sound } = {}
		local seenIds: { [string]: boolean } = {}
		for cueName, cue in audioConfig().cues do
			local soundId = soundIdFor(cue.assetId)
			if soundId ~= nil and seenIds[soundId] ~= true then
				seenIds[soundId] = true
				local sound = Instance.new("Sound")
				sound.Name = "Preload_" .. cueName
				sound.SoundId = soundId
				sound.Volume = 0
				sound.Parent = ensureContainer()
				table.insert(preloadSounds, sound)
			end
		end

		if #preloadSounds > 0 then
			local ok, message = pcall(function()
				ContentProvider:PreloadAsync(preloadSounds)
			end)
			if not ok then
				warn(string.format("[WICK AUDIO] Startup preload did not complete: %s", tostring(message)))
			end
		end
		for _, sound in preloadSounds do
			sound:Destroy()
		end
	end)
end

-- `pitchMultiplier` scales the cue's configured playback speed for this one play. It exists for
-- authored response curves such as mining accuracy. Both caller and cue variation are bounded so
-- the source retains its identity.
local function playFrom(cueName: string, parent: Instance, pitchMultiplier: number?): boolean
	local config = audioConfig()
	if not config.enabled or parent.Parent == nil then
		return false
	end

	local cue = config.cues[cueName]
	if cue == nil then
		return false
	end

	local soundId = soundIdFor(cue.assetId)
	if soundId == nil then
		return false
	end

	local now = os.clock()
	local cooldownTimes = lastPlayedAt
	if parent:IsA("BasePart") or parent:IsA("Attachment") then
		local emitterTimes = lastPlayedAtByEmitter[parent]
		if emitterTimes == nil then
			emitterTimes = {}
			lastPlayedAtByEmitter[parent] = emitterTimes
		end
		cooldownTimes = emitterTimes
	end
	local lastPlayed = cooldownTimes[cueName]
	local cooldown = math.max(0, finiteOr(cue.cooldownSeconds, 0))
	if lastPlayed ~= nil and now - lastPlayed < cooldown then
		return false
	end

	local busName = resolvedBusName(cue.bus)
	if cue.looped then
		local active = activeLoops[cueName]
		if active ~= nil and active.Parent ~= nil then
			lastPlayedAtByBus[busName] = now
			return true
		end
	end

	enforceVoiceLimits(cueName, busName, cue)
	cooldownTimes[cueName] = now

	local callerPitch = if pitchMultiplier ~= nil
			and pitchMultiplier == pitchMultiplier
			and pitchMultiplier > -math.huge
			and pitchMultiplier < math.huge
		then math.clamp(pitchMultiplier, 0.5, 2)
		else 1
	local volumeVariation = randomBetween(cue.volumeMinMultiplier, cue.volumeMaxMultiplier)
	local pitchVariation = randomBetween(cue.pitchMinMultiplier, cue.pitchMaxMultiplier)

	local sound = Instance.new("Sound")
	sound.Name = "Cue_" .. cueName
	sound.SoundId = soundId
	sound.Volume = math.clamp(finiteOr(cue.volume, 0.5) * volumeVariation, 0, 10)
	sound.PlaybackSpeed = math.clamp(finiteOr(cue.playbackSpeed, 1) * callerPitch * pitchVariation, 0.05, 4)
	sound.Looped = cue.looped
	sound.SoundGroup = getBusGroup(busName)
	if cue.rollOffMaxDistance ~= nil then
		local maximum = math.max(0, finiteOr(cue.rollOffMaxDistance, 0))
		local minimum = math.clamp(finiteOr(cue.rollOffMinDistance or 1, 1), 0, maximum)
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = minimum
		sound.RollOffMaxDistance = maximum
		sound.EmitterSize = math.max(0, finiteOr(cue.emitterSize or 0, 0))
	end
	sound.Parent = parent
	if cue.rollOffMaxDistance ~= nil then
		applyOcclusion(sound, parent)
	end

	local voice: ActiveVoice = {
		sound = sound,
		cueName = cueName,
		busName = busName,
		startedAt = now,
		ending = false,
	}
	table.insert(activeVoices, voice)
	sound.Destroying:Connect(function()
		removeVoice(sound)
	end)
	if cue.looped then
		activeLoops[cueName] = sound
	else
		sound.Ended:Connect(function()
			destroyVoice(sound)
		end)
		local fallbackLifetime = math.max(0.1, finiteOr(config.cleanupSeconds, 20))
		if cue.maxDurationSeconds ~= nil then
			fallbackLifetime = math.max(fallbackLifetime, math.max(0, cue.maxDurationSeconds) + 1)
		end
		Debris:AddItem(sound, fallbackLifetime)
		scheduleMaximumDuration(voice, cue)
	end

	sound:Play()
	lastPlayedAtByBus[busName] = now
	return true
end

function AudioCues.play(cueName: string, pitchMultiplier: number?): boolean
	return playFrom(cueName, ensureContainer(), pitchMultiplier)
end

function AudioCues.playAt(cueName: string, parent: Instance, pitchMultiplier: number?): boolean
	return playFrom(cueName, parent, pitchMultiplier)
end

function AudioCues.setVolumeMultiplier(multiplier: number)
	volumeMultiplier = math.clamp(finiteOr(multiplier, 1), 0, 1)
	ensureMasterGroup().Volume = volumeMultiplier
end

function AudioCues.getMasterGroup(): SoundGroup
	return ensureMasterGroup()
end

function AudioCues.getBusGroup(busName: string): SoundGroup
	return getBusGroup(busName)
end

function AudioCues.noteBusActivity(busName: string)
	lastPlayedAtByBus[resolvedBusName(busName)] = os.clock()
end

function AudioCues.isBusQuiet(busName: string, quietSeconds: number): boolean
	local lastPlayed = lastPlayedAtByBus[resolvedBusName(busName)]
	if lastPlayed == nil then
		return true
	end
	local threshold = math.max(0, finiteOr(quietSeconds, 0))
	return os.clock() - lastPlayed >= threshold
end

function AudioCues.stop(cueName: string)
	local sound = activeLoops[cueName]
	if sound ~= nil then
		destroyVoice(sound)
	end
end

function AudioCues.stopAll()
	local cueNames: { string } = {}
	for cueName in activeLoops do
		table.insert(cueNames, cueName)
	end
	for _, cueName in cueNames do
		AudioCues.stop(cueName)
	end
end

function AudioCues.start()
	ensureMasterGroup()
	ensureBusGraph()
	ensureContainer()
	beginPreload()
end

return AudioCues

--!strict
-- Config-driven client audio adapter. Callers name gameplay events; this module owns Sound
-- lifecycle, throttling, load diagnostics, and the empty-ID no-op path. It never decides game state.

local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local AudioCues = {}

type CueDef = {
	assetId: string,
	volume: number,
	playbackSpeed: number,
	looped: boolean,
	cooldownSeconds: number,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?,
	emitterSize: number?,
}

local container: Folder? = nil
local masterGroup: SoundGroup? = nil
local activeLoops: { [string]: Sound } = {}
local lastPlayedAt: { [string]: number } = {}
local volumeMultiplier = 1

local function ensureMasterGroup(): SoundGroup
	local current = masterGroup
	if current ~= nil and current.Parent ~= nil then
		return current
	end

	local group = Instance.new("SoundGroup")
	group.Name = "WickMaster"
	group.Volume = volumeMultiplier
	group.Parent = SoundService
	masterGroup = group
	return group
end

local function ensureContainer(): Folder
	local current = container
	if current ~= nil and current.Parent ~= nil then
		return current
	end

	local folder = Instance.new("Folder")
	folder.Name = "WickAudio"
	folder.Parent = SoundService
	container = folder
	return folder
end

local function soundIdFor(assetId: string): string?
	if assetId == "" then
		return nil
	end
	if string.match(assetId, "^rbxassetid://%d+$") ~= nil then
		return assetId
	end
	if string.match(assetId, "^%d+$") ~= nil then
		return "rbxassetid://" .. assetId
	end
	return nil
end

local function playFrom(cueName: string, parent: Instance): boolean
	if not Config.Audio.enabled then
		return false
	end

	local cues = Config.Audio.cues :: { [string]: CueDef }
	local cue = cues[cueName]
	if cue == nil then
		return false
	end

	local soundId = soundIdFor(cue.assetId)
	if soundId == nil then
		return false
	end

	local now = os.clock()
	local lastPlayed = lastPlayedAt[cueName]
	if lastPlayed ~= nil and now - lastPlayed < cue.cooldownSeconds then
		return false
	end

	if cue.looped then
		local active = activeLoops[cueName]
		if active ~= nil and active.Parent ~= nil then
			return true
		end
	end

	lastPlayedAt[cueName] = now
	local sound = Instance.new("Sound")
	sound.Name = "Cue_" .. cueName
	sound.SoundId = soundId
	sound.Volume = cue.volume
	sound.PlaybackSpeed = cue.playbackSpeed
	sound.Looped = cue.looped
	sound.SoundGroup = ensureMasterGroup()
	if cue.rollOffMaxDistance ~= nil then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = cue.rollOffMinDistance or 1
		sound.RollOffMaxDistance = cue.rollOffMaxDistance
		sound.EmitterSize = cue.emitterSize or 0
	end
	sound.Parent = parent
	task.spawn(function()
		local ok, message = pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
		if not ok and sound.Parent ~= nil then
			warn(string.format("[WICK AUDIO] Failed to load %s (%s): %s", cueName, soundId, tostring(message)))
		end
	end)

	if cue.looped then
		activeLoops[cueName] = sound
	else
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		Debris:AddItem(sound, Config.Audio.cleanupSeconds)
	end

	sound:Play()
	return true
end

function AudioCues.play(cueName: string): boolean
	return playFrom(cueName, ensureContainer())
end

function AudioCues.playAt(cueName: string, parent: Instance): boolean
	if parent.Parent == nil then
		return false
	end
	return playFrom(cueName, parent)
end

function AudioCues.setVolumeMultiplier(multiplier: number)
	volumeMultiplier = math.clamp(multiplier, 0, 1)
	ensureMasterGroup().Volume = volumeMultiplier
end

function AudioCues.getMasterGroup(): SoundGroup
	return ensureMasterGroup()
end

function AudioCues.stop(cueName: string)
	local sound = activeLoops[cueName]
	if sound ~= nil then
		activeLoops[cueName] = nil
		sound:Stop()
		sound:Destroy()
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
	ensureContainer()
end

return AudioCues

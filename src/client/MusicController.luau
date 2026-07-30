--!strict
-- Owns menu music and the cave playlist. Cave tracks play from a shuffled non-repeating bag,
-- begin only after a randomized delay, leave silence between tracks, and fade at both ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioCues = require(script.Parent.AudioCues)
local Config = require(ReplicatedStorage.Shared.Config)

local MusicController = {}

type CueDef = {
	assetId: string,
	volume: number,
	playbackSpeed: number,
	looped: boolean,
	cooldownSeconds: number,
	bus: string,
}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local rng = Random.new()

local generation = 0
local currentSound: Sound? = nil
local soundTweens: { [Sound]: Tween } = {}
local lastTrackCue: string? = nil
local trackBag: { string } = {}

local function soundIdFor(assetId: string): string?
	if string.match(assetId, "^rbxassetid://%d+$") ~= nil then
		return assetId
	end
	if string.match(assetId, "^%d+$") ~= nil then
		return "rbxassetid://" .. assetId
	end
	return nil
end

local function randomDelay(minSeconds: number, maxSeconds: number): number
	return rng:NextNumber(math.min(minSeconds, maxSeconds), math.max(minSeconds, maxSeconds))
end

local function refillTrackBag()
	table.clear(trackBag)
	for _, cueName in Config.Audio.music.caveTrackCues do
		table.insert(trackBag, cueName)
	end
	for index = #trackBag, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		trackBag[index], trackBag[swapIndex] = trackBag[swapIndex], trackBag[index]
	end
	if #trackBag > 1 and trackBag[#trackBag] == lastTrackCue then
		trackBag[#trackBag], trackBag[1] = trackBag[1], trackBag[#trackBag]
	end
end

local function nextTrackCue(): string?
	if #trackBag == 0 then
		refillTrackBag()
	end
	local cueName = table.remove(trackBag)
	lastTrackCue = cueName
	return cueName
end

local function destroySound(sound: Sound)
	local tween = soundTweens[sound]
	if tween ~= nil then
		soundTweens[sound] = nil
		tween:Cancel()
	end
	if sound.Parent ~= nil then
		sound:Stop()
		sound:Destroy()
	end
end

local function fadeOutCurrent(seconds: number)
	local sound = currentSound
	if sound == nil or sound.Parent == nil then
		return
	end
	local existingTween = soundTweens[sound]
	if existingTween ~= nil then
		soundTweens[sound] = nil
		existingTween:Cancel()
	end
	if seconds <= 0 or sound.Volume <= 0 then
		if currentSound == sound then
			currentSound = nil
		end
		destroySound(sound)
		return
	end
	local tween = TweenService:Create(
		sound,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = 0 }
	)
	soundTweens[sound] = tween
	tween:Play()
	task.delay(seconds, function()
		if soundTweens[sound] ~= tween then
			return
		end
		soundTweens[sound] = nil
		if currentSound == sound then
			currentSound = nil
		end
		destroySound(sound)
	end)
end

local function createSound(cueName: string): Sound?
	local cues = Config.Audio.cues :: { [string]: CueDef }
	local cue = cues[cueName]
	if cue == nil then
		warn(string.format("[WICK AUDIO] Unknown music cue %s", cueName))
		return nil
	end
	local soundId = soundIdFor(cue.assetId)
	if soundId == nil then
		warn(string.format("[WICK AUDIO] Invalid music asset ID for %s", cueName))
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. cueName
	sound.SoundId = soundId
	sound.Volume = 0
	sound.PlaybackSpeed = cue.playbackSpeed
	sound.Looped = cue.looped
	sound.SoundGroup = AudioCues.getBusGroup(cue.bus)
	sound.Parent = SoundService

	if not AudioCues.preloadSound(sound, cueName) then
		destroySound(sound)
		return nil
	end
	return sound
end

local function playCue(cueName: string, expectedGeneration: number): Sound?
	if generation ~= expectedGeneration or not Config.Audio.enabled then
		return nil
	end
	local sound = createSound(cueName)
	if sound == nil or generation ~= expectedGeneration then
		if sound ~= nil then
			destroySound(sound)
		end
		return nil
	end

	local cue = (Config.Audio.cues :: { [string]: CueDef })[cueName] :: CueDef
	currentSound = sound
	sound:Play()
	AudioCues.noteBusActivity(cue.bus)
	local tween = TweenService:Create(
		sound,
		TweenInfo.new(Config.Audio.music.fadeInSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Volume = cue.volume }
	)
	soundTweens[sound] = tween
	tween:Play()
	return sound
end

local function waitForTrackEnding(sound: Sound, expectedGeneration: number)
	local music = Config.Audio.music
	while generation == expectedGeneration and sound.Parent ~= nil and sound.IsPlaying do
		if sound.TimeLength > 0 then
			local remaining = sound.TimeLength - sound.TimePosition
			if remaining <= music.fadeOutSeconds then
				if currentSound == sound then
					fadeOutCurrent(math.max(remaining, 0))
				end
				task.wait(math.max(remaining, 0))
				return
			end
		end
		task.wait(music.endCheckIntervalSeconds)
	end
	if generation ~= expectedGeneration then
		-- A mode switch owns the in-flight fade and cleanup.
		return
	end
	if currentSound == sound then
		currentSound = nil
	end
	destroySound(sound)
end

local function runCavePlaylist(expectedGeneration: number)
	local music = Config.Audio.music
	task.wait(randomDelay(music.initialDelayMinSeconds, music.initialDelayMaxSeconds))
	while generation == expectedGeneration and player:GetAttribute(EXPEDITION_ATTRIBUTE) == true do
		local cueName = nextTrackCue()
		if cueName ~= nil then
			local sound = playCue(cueName, expectedGeneration)
			if sound ~= nil then
				waitForTrackEnding(sound, expectedGeneration)
			end
		end
		if generation ~= expectedGeneration then
			return
		end
		task.wait(randomDelay(music.betweenTrackDelayMinSeconds, music.betweenTrackDelayMaxSeconds))
	end
end

local function updateMode()
	generation += 1
	local expectedGeneration = generation
	fadeOutCurrent(Config.Audio.music.fadeOutSeconds)

	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		task.spawn(runCavePlaylist, expectedGeneration)
	else
		task.spawn(function()
			playCue(Config.Audio.music.menuCue, expectedGeneration)
		end)
	end
end

function MusicController.start()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(updateMode)
	updateMode()
end

return MusicController

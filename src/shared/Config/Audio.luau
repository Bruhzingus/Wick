--!strict
-- Client audio registry. Client callers address cues by event name. Repository MP3 files cannot
-- be streamed by Roblox; active rows must reference uploaded or Creator Store audio asset IDs.

export type CueDef = {
	assetId: string,
	volume: number,
	playbackSpeed: number,
	looped: boolean,
	cooldownSeconds: number,
}

export type AudioConfig = {
	enabled: boolean,
	cleanupSeconds: number,
	cues: { [string]: CueDef },
}

type CueOverrides = {
	assetId: string?,
	volume: number?,
	playbackSpeed: number?,
	looped: boolean?,
	cooldownSeconds: number?,
}

local function cue(overrides: CueOverrides?): CueDef
	return {
		assetId = if overrides ~= nil and overrides.assetId ~= nil then overrides.assetId else "",
		volume = if overrides ~= nil and overrides.volume ~= nil then overrides.volume else 0.5,
		playbackSpeed = if overrides ~= nil and overrides.playbackSpeed ~= nil then overrides.playbackSpeed else 1,
		looped = if overrides ~= nil and overrides.looped ~= nil then overrides.looped else false,
		cooldownSeconds = if overrides ~= nil and overrides.cooldownSeconds ~= nil
			then overrides.cooldownSeconds
			else 0,
	}
end

local Audio: AudioConfig = {
	enabled = true,
	-- Fallback cleanup for one-shots whose asset fails to load and never reaches Ended.
	cleanupSeconds = 20,
	cues = {
		-- Uploaded project tracks. Keep their experience permissions enabled when ownership or
		-- publishing-group settings change.
		MenuMusic = cue({ assetId = "122061612190896", volume = 0.36, looped = true }),
		CaveAmbience = cue({ assetId = "71682768476112", volume = 0.44, looped = true }),
		DialSnap = cue({ volume = 0.2, cooldownSeconds = 0.08 }),
		LowWax = cue({ volume = 0.45, cooldownSeconds = 5 }),
		Draft = cue({ volume = 0.45, looped = true }),
		Water = cue({ volume = 0.4, looped = true }),
		ThreatNear = cue({ volume = 0.5, cooldownSeconds = 4 }),
		ToolSnuff = cue({ volume = 0.45, cooldownSeconds = 0.2 }),
		ToolFlare = cue({ volume = 0.65, cooldownSeconds = 0.2 }),
		ToolCast = cue({ volume = 0.5, cooldownSeconds = 0.2 }),
		ToolCup = cue({ volume = 0.35, cooldownSeconds = 0.2 }),
		Dodge = cue({ volume = 0.35, cooldownSeconds = 0.15 }),
		Slide = cue({ volume = 0.35, cooldownSeconds = 0.15 }),
		Sprint = cue({ volume = 0.25, cooldownSeconds = 0.2 }),
		BasinOpen = cue({ volume = 0.55, cooldownSeconds = 0.5 }),
		BasinChoose = cue({ volume = 0.65, cooldownSeconds = 0.5 }),
		BrazierNear = cue({ volume = 0.55, cooldownSeconds = 1 }),
		BrazierCommit = cue({ volume = 0.8, cooldownSeconds = 1 }),
		DeathSnuffed = cue({ volume = 0.7, cooldownSeconds = 1 }),
		DeathBurnOut = cue({ volume = 0.7, cooldownSeconds = 1 }),
		Relight = cue({ volume = 0.55, cooldownSeconds = 0.5 }),
		FloorEnter = cue({ volume = 0.35, cooldownSeconds = 0.5 }),
	},
}

return Audio

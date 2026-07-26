--!strict
-- Client audio registry. Client callers address cues by event name. Repository MP3 files cannot
-- be streamed by Roblox; active rows use uploaded/Creator Store IDs or Roblox's built-in sounds.

export type CueDef = {
	assetId: string,
	volume: number,
	playbackSpeed: number,
	looped: boolean,
	cooldownSeconds: number,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?,
	emitterSize: number?,
}

export type AudioConfig = {
	enabled: boolean,
	cleanupSeconds: number,
	music: {
		menuCue: string,
		caveTrackCues: { string },
		initialDelayMinSeconds: number,
		initialDelayMaxSeconds: number,
		betweenTrackDelayMinSeconds: number,
		betweenTrackDelayMaxSeconds: number,
		fadeInSeconds: number,
		fadeOutSeconds: number,
		endCheckIntervalSeconds: number,
	},
	cues: { [string]: CueDef },
}

type CueOverrides = {
	assetId: string?,
	volume: number?,
	playbackSpeed: number?,
	looped: boolean?,
	cooldownSeconds: number?,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?,
	emitterSize: number?,
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
		rollOffMinDistance = if overrides ~= nil then overrides.rollOffMinDistance else nil,
		rollOffMaxDistance = if overrides ~= nil then overrides.rollOffMaxDistance else nil,
		emitterSize = if overrides ~= nil then overrides.emitterSize else nil,
	}
end

local Audio: AudioConfig = {
	enabled = true,
	-- Fallback cleanup for one-shots whose asset fails to load and never reaches Ended.
	cleanupSeconds = 20,
	music = {
		menuCue = "MenuMusic",
		caveTrackCues = {
			"CaveAmbience",
			"CaveTrack2",
			"CaveTrack3",
			"CaveTrack4",
		},
		-- Cave music should emerge after the expedition has settled, never at the instant it starts.
		initialDelayMinSeconds = 18,
		initialDelayMaxSeconds = 42,
		-- Silence between tracks keeps the cave from feeling like a continuous album.
		betweenTrackDelayMinSeconds = 10,
		betweenTrackDelayMaxSeconds = 24,
		fadeInSeconds = 4,
		fadeOutSeconds = 5,
		endCheckIntervalSeconds = 0.2,
	},
	cues = {
		-- Uploaded project tracks. Keep their experience permissions enabled when ownership or
		-- publishing-group settings change.
		MenuMusic = cue({ assetId = "122061612190896", volume = 0.36, looped = true }),
		-- Underground tracks are kept 20% below their original 0.44 mix level.
		CaveAmbience = cue({ assetId = "71682768476112", volume = 0.352 }),
		CaveTrack2 = cue({ assetId = "136582960170775", volume = 0.352 }),
		CaveTrack3 = cue({ assetId = "104375150403939", volume = 0.352 }),
		CaveTrack4 = cue({ assetId = "113564986043204", volume = 0.352 }),
		DialSnap = cue({ volume = 0.2, cooldownSeconds = 0.08 }),
		LowWax = cue({ volume = 0.45, cooldownSeconds = 5 }),
		Water = cue({ volume = 0.4, looped = true }),
		ThreatNear = cue({ volume = 0.5, cooldownSeconds = 4 }),
		-- Free Creator Store SFX by Pro Sound Effects: a short, restrained insect vocal.
		FlyBuzz = cue({
			assetId = "9114506042",
			volume = 0.12,
			cooldownSeconds = 3,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 32,
			emitterSize = 1.5,
		}),
		-- Free Creator Store stone cues by Pro Sound Effects. Both are spatial and restrained:
		-- the fracture teaches the collar warning; the impact carries only through nearby rooms.
		DripstoneFracture = cue({
			assetId = "9125929705",
			volume = 0.32,
			cooldownSeconds = 0.18,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 48,
			emitterSize = 2,
		}),
		DripstoneImpact = cue({
			assetId = "9118609396",
			volume = 0.68,
			cooldownSeconds = 0.12,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 68,
			emitterSize = 3,
		}),
		-- The same licensed stone source as the dripstone impact, mixed much lower for a harmless
		-- loose chip rolling out of a side wall rather than a dangerous ceiling collapse.
		AmbientRockfall = cue({
			assetId = "9118609396",
			volume = 0.24,
			playbackSpeed = 1.28,
			cooldownSeconds = 0.5,
			rollOffMinDistance = 3,
			rollOffMaxDistance = 52,
			emitterSize = 1,
		}),
		-- Roblox's built-in water impact, pitched up and kept quiet so it reads as one natural drip,
		-- not as a player splash or a persistent water loop.
		AmbientWaterDrip = cue({
			assetId = "rbxasset://sounds/impact_water.mp3",
			volume = 0.08,
			playbackSpeed = 1.55,
			cooldownSeconds = 0.25,
			rollOffMinDistance = 2,
			rollOffMaxDistance = 26,
			emitterSize = 0.5,
		}),
		ToolSnuff = cue({ volume = 0.45, cooldownSeconds = 0.2 }),
		ToolFlare = cue({ volume = 0.65, cooldownSeconds = 0.2 }),
		ToolDecoy = cue({ volume = 0.5, cooldownSeconds = 0.2 }),
		ToolCup = cue({ volume = 0.35, cooldownSeconds = 0.2 }),
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

--!strict
-- Client audio registry. Client callers address cues by event name. Repository MP3 files cannot
-- be streamed by Roblox; active rows use uploaded/Creator Store IDs or Roblox's built-in sounds.

export type CueDef = {
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

export type EqualizerDef = {
	lowGain: number,
	midGain: number,
	highGain: number,
}

export type ReverbDef = {
	decayTime: number,
	density: number,
	diffusion: number,
	dryLevel: number,
	wetLevel: number,
}

export type DuckingDef = {
	sidechainBus: string,
	threshold: number,
	attack: number,
	release: number,
	ratio: number,
}

export type OcclusionDef = {
	enabled: boolean,
	volumeMultiplier: number,
	lowGain: number,
	midGain: number,
	highGain: number,
}

export type BusDef = {
	volume: number,
	voiceLimit: number,
	equalizer: EqualizerDef?,
	reverb: ReverbDef?,
	ducking: DuckingDef?,
}

export type AudioConfig = {
	enabled: boolean,
	cleanupSeconds: number,
	maxActiveVoices: number,
	defaultBus: string,
	occlusion: OcclusionDef,
	buses: { [string]: BusDef },
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
	bus: string?,
	volumeMinMultiplier: number?,
	volumeMaxMultiplier: number?,
	pitchMinMultiplier: number?,
	pitchMaxMultiplier: number?,
	maxVoices: number?,
	maxDurationSeconds: number?,
	fadeOutSeconds: number?,
	rollOffMinDistance: number?,
	rollOffMaxDistance: number?,
	emitterSize: number?,
}

local function cue(overrides: CueOverrides?): CueDef
	local looped = overrides ~= nil and overrides.looped == true
	return {
		assetId = if overrides ~= nil and overrides.assetId ~= nil then overrides.assetId else "",
		volume = if overrides ~= nil and overrides.volume ~= nil then overrides.volume else 0.5,
		playbackSpeed = if overrides ~= nil and overrides.playbackSpeed ~= nil then overrides.playbackSpeed else 1,
		looped = looped,
		cooldownSeconds = if overrides ~= nil and overrides.cooldownSeconds ~= nil
			then overrides.cooldownSeconds
			else 0,
		bus = if overrides ~= nil and overrides.bus ~= nil then overrides.bus else "World",
		volumeMinMultiplier = if overrides ~= nil and overrides.volumeMinMultiplier ~= nil
			then overrides.volumeMinMultiplier
			else 1,
		volumeMaxMultiplier = if overrides ~= nil and overrides.volumeMaxMultiplier ~= nil
			then overrides.volumeMaxMultiplier
			else 1,
		pitchMinMultiplier = if overrides ~= nil and overrides.pitchMinMultiplier ~= nil
			then overrides.pitchMinMultiplier
			else 1,
		pitchMaxMultiplier = if overrides ~= nil and overrides.pitchMaxMultiplier ~= nil
			then overrides.pitchMaxMultiplier
			else 1,
		maxVoices = if overrides ~= nil and overrides.maxVoices ~= nil
			then overrides.maxVoices
			elseif looped then 1
			else 4,
		maxDurationSeconds = if overrides ~= nil then overrides.maxDurationSeconds else nil,
		fadeOutSeconds = if overrides ~= nil and overrides.fadeOutSeconds ~= nil then overrides.fadeOutSeconds else 0,
		rollOffMinDistance = if overrides ~= nil then overrides.rollOffMinDistance else nil,
		rollOffMaxDistance = if overrides ~= nil then overrides.rollOffMaxDistance else nil,
		emitterSize = if overrides ~= nil then overrides.emitterSize else nil,
	}
end

local Audio: AudioConfig = {
	enabled = true,
	-- Fallback cleanup for one-shots whose asset fails to load and never reaches Ended.
	cleanupSeconds = 20,
	-- AudioCues enforces both this global ceiling and the per-bus ceilings below. Oldest voices are
	-- stolen first, so a burst degrades in density instead of growing without bound on a slow client.
	maxActiveVoices = 48,
	defaultBus = "World",
	-- A single ray at spawn is sufficient for these short spatial one-shots. Rock between listener
	-- and emitter lowers the direct signal and rolls away its edge while the cave-bus reverb remains,
	-- so a sound inside a wall reads as geology rather than as a speaker beside the player.
	occlusion = {
		enabled = true,
		volumeMultiplier = 0.68,
		lowGain = -1,
		midGain = -5,
		highGain = -17,
	},
	-- A small production mix tree. Every child is parented beneath WickMaster at runtime, so the
	-- existing LOCAL AUDIO setting remains one true master while each category keeps its own
	-- headroom and processing. Focus is the sidechain key: mining impacts, hazards, attacks, and
	-- other immediate reads briefly make room for themselves without flattening the whole mix.
	buses = {
		Music = {
			volume = 1,
			voiceLimit = 4,
			equalizer = nil,
			reverb = nil,
			ducking = {
				sidechainBus = "Focus",
				threshold = -28,
				attack = 0.1,
				release = 0.8,
				ratio = 4,
			},
		},
		Ambience = {
			volume = 1,
			voiceLimit = 10,
			equalizer = {
				lowGain = -0.5,
				midGain = -1.5,
				highGain = -3,
			},
			reverb = {
				decayTime = 2.8,
				density = 0.76,
				diffusion = 0.86,
				dryLevel = -1,
				wetLevel = -15,
			},
			ducking = {
				sidechainBus = "Focus",
				threshold = -25,
				attack = 0.1,
				release = 0.65,
				ratio = 2.8,
			},
		},
		World = {
			volume = 1,
			voiceLimit = 16,
			equalizer = {
				lowGain = 0,
				midGain = -0.5,
				highGain = -1.5,
			},
			reverb = {
				decayTime = 2.15,
				density = 0.7,
				diffusion = 0.8,
				dryLevel = 0,
				wetLevel = -18,
			},
			ducking = nil,
		},
		Focus = {
			volume = 1,
			voiceLimit = 18,
			equalizer = {
				lowGain = 0.5,
				midGain = 0,
				highGain = -0.5,
			},
			-- A restrained room return keeps close gameplay transients physical without smearing
			-- their warning edge.
			reverb = {
				decayTime = 1.75,
				density = 0.64,
				diffusion = 0.74,
				dryLevel = 0,
				wetLevel = -22,
			},
			ducking = nil,
		},
		UI = {
			volume = 1,
			voiceLimit = 8,
			equalizer = nil,
			reverb = nil,
			ducking = nil,
		},
	},
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
		MenuMusic = cue({
			assetId = "122061612190896",
			volume = 0.36,
			looped = true,
			bus = "Music",
			maxVoices = 1,
		}),
		-- Underground tracks are kept 20% below their original 0.44 mix level.
		CaveAmbience = cue({
			assetId = "71682768476112",
			volume = 0.352,
			bus = "Music",
			maxVoices = 1,
		}),
		CaveTrack2 = cue({
			assetId = "136582960170775",
			volume = 0.352,
			bus = "Music",
			maxVoices = 1,
		}),
		CaveTrack3 = cue({
			assetId = "104375150403939",
			volume = 0.352,
			bus = "Music",
			maxVoices = 1,
		}),
		CaveTrack4 = cue({
			assetId = "113564986043204",
			volume = 0.352,
			bus = "Music",
			maxVoices = 1,
		}),
		DialSnap = cue({ volume = 0.2, cooldownSeconds = 0.08, bus = "UI", maxVoices = 2 }),
		LowWax = cue({ volume = 0.45, cooldownSeconds = 5, bus = "Focus", maxVoices = 1 }),
		Water = cue({ volume = 0.4, looped = true, bus = "World", maxVoices = 1 }),
		ThreatNear = cue({ volume = 0.5, cooldownSeconds = 4, bus = "Focus", maxVoices = 1 }),
		-- Free Creator Store SFX by Pro Sound Effects: a short, restrained insect vocal.
		FlyBuzz = cue({
			assetId = "9114506042",
			volume = 0.12,
			cooldownSeconds = 3,
			bus = "Focus",
			volumeMinMultiplier = 0.86,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 32,
			emitterSize = 1.5,
		}),
		-- Confirmed threat-contact layers. Crawler joints use a low, dry fracture; moths and the
		-- VoidFly bend the insect source into distinct hostile bursts. ThreatHit is deliberately
		-- non-spatial and victim-only so taking wax always has an immediate, frightening body cue.
		DarkCrawlerAttack = cue({
			assetId = "9125929705",
			volume = 0.88,
			playbackSpeed = 0.58,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 64,
			emitterSize = 3,
		}),
		DrawnAttack = cue({
			assetId = "9114506042",
			volume = 0.78,
			playbackSpeed = 0.68,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 52,
			emitterSize = 2.5,
		}),
		VoidFlyAttack = cue({
			assetId = "9114506042",
			volume = 0.86,
			playbackSpeed = 1.38,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 40,
			emitterSize = 2,
		}),
		ThreatHit = cue({
			assetId = "9118609396",
			volume = 0.94,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.12,
			bus = "Focus",
			maxVoices = 2,
		}),
		-- Free Creator Store stone cues by Pro Sound Effects. Both are spatial and restrained:
		-- the fracture teaches the collar warning; the impact carries only through nearby rooms.
		DripstoneFracture = cue({
			assetId = "9125929705",
			volume = 0.32,
			cooldownSeconds = 0.18,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.05,
			maxVoices = 4,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 48,
			emitterSize = 2,
		}),
		DripstoneImpact = cue({
			assetId = "9118609396",
			volume = 0.68,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 4,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 68,
			emitterSize = 3,
		}),
		-- Victim-only sting layered over the spatial rock impact. The brighter, close-mixed fracture
		-- makes a confirmed hit feel like the crown punched through the local candle.
		DripstoneImpale = cue({
			assetId = "9125929705",
			volume = 0.95,
			playbackSpeed = 1.25,
			cooldownSeconds = 0.12,
			bus = "Focus",
			maxVoices = 2,
		}),
		-- The same licensed stone source as the dripstone impact, mixed much lower for a harmless
		-- loose chip rolling out of a side wall rather than a dangerous ceiling collapse.
		AmbientRockfall = cue({
			assetId = "9118609396",
			volume = 0.24,
			playbackSpeed = 1.28,
			cooldownSeconds = 0.5,
			bus = "Ambience",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 4,
			fadeOutSeconds = 0.35,
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
			bus = "Ambience",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 2,
			fadeOutSeconds = 0.15,
			rollOffMinDistance = 2,
			rollOffMaxDistance = 26,
			emitterSize = 0.5,
		}),
		-- Natural cave movement. These are deliberately restrained, spatially broad, and varied at
		-- playback so the ambience director can imply a living geology without producing a parade
		-- of authored scares. The director owns rarity and placement; these rows own only the mix.
		CaveStrataStrain = cue({
			assetId = "9125880974",
			volume = 0.1,
			playbackSpeed = 0.9,
			cooldownSeconds = 0.5,
			bus = "Ambience",
			volumeMinMultiplier = 0.76,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			maxDurationSeconds = 4.4,
			fadeOutSeconds = 0.45,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 90,
			emitterSize = 4,
		}),
		CaveFissureBreath = cue({
			assetId = "9120698168",
			volume = 0.075,
			playbackSpeed = 0.9,
			cooldownSeconds = 0.75,
			bus = "Ambience",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 1,
			maxDurationSeconds = 6.5,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 96,
			emitterSize = 10,
		}),
		CaveCalciteTick = cue({
			assetId = "9118628948",
			volume = 0.07,
			playbackSpeed = 0.95,
			cooldownSeconds = 0.35,
			bus = "Ambience",
			volumeMinMultiplier = 0.76,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 1.8,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 3,
			rollOffMaxDistance = 55,
			emitterSize = 1,
		}),
		CaveHiddenWater = cue({
			assetId = "9125499039",
			volume = 0.075,
			playbackSpeed = 0.9,
			cooldownSeconds = 0.5,
			bus = "Ambience",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 1,
			maxDurationSeconds = 5.5,
			fadeOutSeconds = 0.65,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 76,
			emitterSize = 3,
		}),
		CaveGravelCreep = cue({
			assetId = "9113218672",
			volume = 0.09,
			cooldownSeconds = 0.45,
			bus = "Ambience",
			volumeMinMultiplier = 0.76,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 3,
			fadeOutSeconds = 0.35,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 68,
			emitterSize = 2,
		}),
		-- Ashamed Lurker. Placeholder sources drawn from the licensed cues already in this file:
		-- breathing and the joint crack are a stone fracture pitched around, and the grab reuses the
		-- impact at full weight. Replace the asset IDs when dedicated creature audio is uploaded;
		-- the volumes and rolloffs below are already tuned for the arch.
		--
		-- The dry breath is the only warning in the dark. It is deliberately quiet and short-ranged:
		-- it says something is breathing, not exactly where.
		LurkerBreath = cue({
			assetId = "9125929705",
			volume = 0.1,
			playbackSpeed = 0.62,
			cooldownSeconds = 1.5,
			bus = "Focus",
			volumeMinMultiplier = 0.84,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			rollOffMinDistance = 3,
			rollOffMaxDistance = 30,
			emitterSize = 1.5,
		}),
		-- The lunge: an abrupt joint crack the moment the arm commits, whether or not it connects.
		LurkerLunge = cue({
			assetId = "9125929705",
			volume = 0.5,
			playbackSpeed = 1.42,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 55,
			emitterSize = 2,
		}),
		-- A connecting grab. This one is meant to be a scare, so it is the loudest cue the creature
		-- has and it carries into the neighbouring rooms.
		LurkerGrab = cue({
			assetId = "9118609396",
			volume = 0.9,
			playbackSpeed = 0.86,
			cooldownSeconds = 0.2,
			bus = "Focus",
			maxVoices = 3,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 70,
			emitterSize = 3,
		}),
		-- Mining. Contact is constructed from separate movement, stone body, material transient,
		-- scrape, and debris sources. These licensed library cuts are production stand-ins for a
		-- future multi-take recording set, but none relies on the recognizable stock sword sources.
		--
		-- Consecutive Perfects receive only a subtle four-percent ceiling. The physical source must
		-- retain its identity; the old wide pitch ladder turned stone into an arcade score flourish.
		--
		-- NOTE: these are the LOCAL cues the mining player hears. What the cave hears is a separate,
		-- server-owned thing entirely (Config/Sound) — never assume the two match.
		--
		-- The stance opening: a short, dry handle/metal draw as the pick comes up. Deliberately quiet
		-- — this is punctuation before the loop, not an event.
		MineEngage = cue({
			assetId = "9126284289",
			volume = 0.08,
			playbackSpeed = 0.6,
			cooldownSeconds = 0.08,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.98,
			pitchMaxMultiplier = 1.02,
			maxVoices = 2,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.08,
		}),
		-- Close-mixed wind off the head, fired on input rather than waiting for the server. The actual
		-- contact layers remain authoritative and spatial at the seam.
		MineSwing = cue({
			assetId = "9126284289",
			volume = 0.2,
			playbackSpeed = 0.82,
			cooldownSeconds = 0.08,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
		}),
		-- Quiet handle/metal scrape as the bounced head is hauled back over the shoulder.
		MineRecover = cue({
			assetId = "9126284289",
			volume = 0.065,
			playbackSpeed = 0.68,
			cooldownSeconds = 0.08,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 2,
			maxDurationSeconds = 0.65,
			fadeOutSeconds = 0.08,
		}),
		-- THE CRUNCH. Every single strike — whatever it was worth — plays this underneath its accuracy
		-- layer: a heavy, low, physical bite of steel into rock. This is the layer that was missing
		-- before: the accuracy cues alone were a thin metallic "tink" with no weight behind it, so a
		-- strike never read as the pickaxe actually landing. `MiningController` randomizes its pitch a
		-- little per hit (cosmetic only) so a fast run of strikes doesn't phase into a machine-gun.
		MineStrikeImpact = cue({
			assetId = "9118609396",
			volume = 0.72,
			playbackSpeed = 0.78,
			cooldownSeconds = 0.04,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 5,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 60,
			emitterSize = 2.5,
		}),
		-- Dead centre. Bright, tight, and pitched clearly above a merely good hit, so Perfect is
		-- audible as a different EVENT rather than a louder version of the same one. Layers on top of
		-- MineStrikeImpact — the crunch is the impact, this is the ring of a clean bite.
		MineStrikePerfect = cue({
			assetId = "9118628948",
			volume = 0.38,
			playbackSpeed = 1.02,
			cooldownSeconds = 0.06,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.99,
			pitchMaxMultiplier = 1.01,
			maxVoices = 4,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 46,
			emitterSize = 2,
		}),
		MineStrikeClean = cue({
			assetId = "9125929705",
			volume = 0.42,
			playbackSpeed = 1.14,
			cooldownSeconds = 0.1,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.99,
			pitchMaxMultiplier = 1.01,
			maxVoices = 4,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 46,
			emitterSize = 2,
		}),
		MineStrikeFumble = cue({
			assetId = "9125880974",
			volume = 0.24,
			playbackSpeed = 1.08,
			cooldownSeconds = 0.1,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.98,
			pitchMaxMultiplier = 1.02,
			maxVoices = 4,
			maxDurationSeconds = 1.2,
			fadeOutSeconds = 0.16,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 62,
			emitterSize = 2.5,
		}),
		-- THE SIGNAL BELL (Config/LampNetwork.bell). A bright, carrying strike with a long tail, and the
		-- ONE cue in the game whose roll-off is deliberately huge: the whole point of the node is that the
		-- sound reaches a friend across a floor when nothing else does.
		--
		-- Placeholder asset. It must read as a struck bell rather than a chime or an alarm — the player is
		-- signalling a position, not warning of danger, and the two must never be confusable.
		SignalBell = cue({
			assetId = "9125929705",
			volume = 0.62,
			playbackSpeed = 0.82,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.96,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.99,
			pitchMaxMultiplier = 1.01,
			maxVoices = 2,
			rollOffMinDistance = 14,
			-- Far past every other cue: audible across a whole floor, which is what a bearing needs.
			rollOffMaxDistance = 320,
			emitterSize = 6,
		}),
		MineBreak = cue({
			assetId = "9113218672",
			volume = 0.7,
			playbackSpeed = 0.92,
			cooldownSeconds = 0.2,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.98,
			pitchMaxMultiplier = 1.02,
			maxVoices = 3,
			maxDurationSeconds = 1.8,
			fadeOutSeconds = 0.22,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 74,
			emitterSize = 3,
		}),
		ToolFlare = cue({ volume = 0.65, cooldownSeconds = 0.2, bus = "Focus", maxVoices = 2 }),
		ToolDecoy = cue({ volume = 0.5, cooldownSeconds = 0.2, bus = "Focus", maxVoices = 2 }),
		ToolCup = cue({ volume = 0.35, cooldownSeconds = 0.2, bus = "Focus", maxVoices = 2 }),
		Sprint = cue({ volume = 0.25, cooldownSeconds = 0.2, bus = "World", maxVoices = 2 }),
		BasinOpen = cue({ volume = 0.55, cooldownSeconds = 0.5, bus = "UI", maxVoices = 1 }),
		BasinChoose = cue({ volume = 0.65, cooldownSeconds = 0.5, bus = "UI", maxVoices = 1 }),
		BrazierNear = cue({ volume = 0.55, cooldownSeconds = 1, bus = "Focus", maxVoices = 1 }),
		BrazierCommit = cue({ volume = 0.8, cooldownSeconds = 1, bus = "Focus", maxVoices = 1 }),
		DeathSnuffed = cue({ volume = 0.7, cooldownSeconds = 1, bus = "Focus", maxVoices = 1 }),
		DeathBurnOut = cue({ volume = 0.7, cooldownSeconds = 1, bus = "Focus", maxVoices = 1 }),
		Relight = cue({ volume = 0.55, cooldownSeconds = 0.5, bus = "Focus", maxVoices = 2 }),
		FloorEnter = cue({ volume = 0.35, cooldownSeconds = 0.5, bus = "UI", maxVoices = 1 }),
	},
}

return Audio

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
		-- Confirmed threat-contact layers. Crawler joints use a low, dry fracture; moths and the
		-- VoidFly bend the insect source into distinct hostile bursts. ThreatHit is deliberately
		-- non-spatial and victim-only so taking wax always has an immediate, frightening body cue.
		DarkCrawlerAttack = cue({
			assetId = "9125929705",
			volume = 0.88,
			playbackSpeed = 0.58,
			cooldownSeconds = 0.12,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 64,
			emitterSize = 3,
		}),
		DrawnAttack = cue({
			assetId = "9114506042",
			volume = 0.78,
			playbackSpeed = 0.68,
			cooldownSeconds = 0.12,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 52,
			emitterSize = 2.5,
		}),
		VoidFlyAttack = cue({
			assetId = "9114506042",
			volume = 0.86,
			playbackSpeed = 1.38,
			cooldownSeconds = 0.12,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 40,
			emitterSize = 2,
		}),
		ThreatHit = cue({
			assetId = "9118609396",
			volume = 0.94,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.12,
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
		-- Victim-only sting layered over the spatial rock impact. The brighter, close-mixed fracture
		-- makes a confirmed hit feel like the crown punched through the local candle.
		DripstoneImpale = cue({
			assetId = "9125929705",
			volume = 0.95,
			playbackSpeed = 1.25,
			cooldownSeconds = 0.12,
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
			rollOffMinDistance = 8,
			rollOffMaxDistance = 70,
			emitterSize = 3,
		}),
		-- Mining. Contact reuses the licensed stone cues already in this file; close tool movement
		-- uses Roblox's built-in slash/unsheathe sources. Replace them when dedicated pick audio is
		-- uploaded; the mix below is already tuned so the
		-- three outcomes are distinguishable with your eyes shut, which is the point.
		--
		-- THE LADDER IS THE HOOK: `AudioCues.play` takes a pitch multiplier, and MiningController
		-- raises it a step for every consecutive Perfect. A clean run of strikes climbs; the moment
		-- you fumble it drops back to the floor. That rising line is what makes the loop worth
		-- repeating — it is the only place in this game where the audio is a scoreboard.
		--
		-- NOTE: these are the LOCAL cues the mining player hears. What the cave hears is a separate,
		-- server-owned thing entirely (Config/Sound) — never assume the two match.
		--
		-- The stance opening: a short, dry handle/metal draw as the pick comes up. Deliberately quiet
		-- — this is punctuation before the loop, not an event.
		MineEngage = cue({
			assetId = "rbxasset://sounds/unsheath.wav",
			volume = 0.18,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.08,
		}),
		-- Close-mixed wind off the head, fired on input rather than waiting for the server. The actual
		-- contact layers remain authoritative and spatial at the seam.
		MineSwing = cue({
			assetId = "rbxasset://sounds/swordslash.wav",
			volume = 0.19,
			playbackSpeed = 0.64,
			cooldownSeconds = 0.08,
		}),
		-- Quiet handle/metal scrape as the bounced head is hauled back over the shoulder.
		MineRecover = cue({
			assetId = "rbxasset://sounds/unsheath.wav",
			volume = 0.09,
			playbackSpeed = 0.58,
			cooldownSeconds = 0.08,
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
			rollOffMinDistance = 6,
			rollOffMaxDistance = 60,
			emitterSize = 2.5,
		}),
		-- Dead centre. Bright, tight, and pitched clearly above a merely good hit, so Perfect is
		-- audible as a different EVENT rather than a louder version of the same one. Layers on top of
		-- MineStrikeImpact — the crunch is the impact, this is the ring of a clean bite.
		MineStrikePerfect = cue({
			assetId = "9125929705",
			volume = 0.54,
			playbackSpeed = 1.48,
			cooldownSeconds = 0.06,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 46,
			emitterSize = 2,
		}),
		MineStrikeClean = cue({
			assetId = "9125929705",
			volume = 0.42,
			playbackSpeed = 1.14,
			cooldownSeconds = 0.1,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 46,
			emitterSize = 2,
		}),
		MineStrikeFumble = cue({
			assetId = "9125929705",
			volume = 0.5,
			playbackSpeed = 0.72,
			cooldownSeconds = 0.1,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 62,
			emitterSize = 2.5,
		}),
		MineBreak = cue({
			assetId = "9118609396",
			volume = 0.84,
			playbackSpeed = 0.94,
			cooldownSeconds = 0.2,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 74,
			emitterSize = 3,
		}),
		-- Layered on top of the break: the wax itself coming free, a half-beat after the rock gives.
		-- The payoff chime the whole ladder has been climbing toward.
		MineBreakChime = cue({
			assetId = "9125929705",
			volume = 0.44,
			playbackSpeed = 1.62,
			cooldownSeconds = 0.2,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 52,
			emitterSize = 2,
		}),
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

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
	-- Higher-priority incoming buses may steal lower-priority voices at the global ceiling. A
	-- low-priority ambient event can never evict a Focus gameplay read.
	priority: number,
	equalizer: EqualizerDef?,
	reverb: ReverbDef?,
	ducking: DuckingDef?,
}

export type AudioConfig = {
	enabled: boolean,
	cleanupSeconds: number,
	maxActiveVoices: number,
	defaultBus: string,
	settings: {
		musicMinMultiplier: number,
		ambienceMinMultiplier: number,
	},
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
	-- AudioCues enforces both this global ceiling and the per-bus ceilings below. Cue/bus caps steal
	-- their oldest match; the global cap steals the oldest voice from the lowest eligible priority,
	-- so ambience density degrades without erasing a critical Focus read.
	maxActiveVoices = 48,
	defaultBus = "World",
	settings = {
		musicMinMultiplier = 0,
		ambienceMinMultiplier = 0.1,
	},
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
			priority = 30,
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
			-- Every cue on this bus is emitted by the cave-only ambience director. This is another 20%
			-- below the prior 0.5625 mix (55% below authored gain), without touching gameplay-critical reads.
			volume = 0.45,
			voiceLimit = 10,
			priority = 10,
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
			priority = 20,
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
			priority = 100,
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
			priority = 40,
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
			volume = 0.1755,
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
		-- Confirmed threat-contact layers. The crawler gets a flesh slice, the moth a compact bite,
		-- and every other rendered kind has an explicit voice. ThreatHit is deliberately non-spatial
		-- and victim-only so taking wax always has an immediate, frightening body cue.
		DarkCrawlerAttack = cue({
			assetId = "9125619840",
			volume = 0.82,
			playbackSpeed = 0.9,
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
			maxDurationSeconds = 0.62,
			fadeOutSeconds = 0.06,
		}),
		MothBite = cue({
			assetId = "9119055965",
			volume = 0.78,
			playbackSpeed = 1.15,
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
		-- THE VOIDFLY LANDING ON YOUR CANDLE. Its contact effect is Snuff — it is not biting a player,
		-- it is a hand-sized armoured body slamming into the flame, four times, to put it out. This is
		-- a big flying insect batting against a window pane, which is the closest real-world recording
		-- of exactly that event. Previously this was `FlyBuzz`'s own file sped up 38%, so the fly's
		-- idle patrol, its dive and its strike were one sample at three speeds and none of the three
		-- read as an attack.
		VoidFlyAttack = cue({
			assetId = "9113978334",
			volume = 0.86,
			playbackSpeed = 1.12,
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
		-- A heavy wet body blow. The Listener carries its skull low and hits with the whole mass behind
		-- it, so this is a ribcage impact rather than the small-teeth snap it used to share with the
		-- moth — two creatures of very different size must not close on you with the same jaw.
		ListenerAttack = cue({
			assetId = "9118167124",
			volume = 0.82,
			playbackSpeed = 0.78,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 62,
			emitterSize = 3,
		}),
		-- Wet ligament and cartilage. The Knotwalker is a narrow thing built of long forelimbs, and what
		-- it does on contact is fold one around you — a squishing joint rather than the crawler's clean
		-- slice, which is the sound this row used to borrow.
		KnotwalkerAttack = cue({
			assetId = "9119560180",
			volume = 0.76,
			playbackSpeed = 1.05,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			maxDurationSeconds = 0.56,
			fadeOutSeconds = 0.06,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 58,
			emitterSize = 2.5,
		}),
		-- ROCK ON ROCK, and the only creature in the game whose "attack" cue is correctly geological:
		-- the Calver never touches a player. It strikes the vault above you to bring the ice down, so
		-- what a player hears is the blow LANDING ON THE CEILING, not on them. A dedicated rock-hitting-
		-- rock impact rather than the shale burst it used to share with dripstone, mining and the bell.
		CalverAttack = cue({
			assetId = "9125869159",
			volume = 0.8,
			playbackSpeed = 0.92,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			rollOffMinDistance = 7,
			rollOffMaxDistance = 64,
			emitterSize = 3,
		}),
		-- THE VICTIM STING, and the row that had the worst source in this file: it was `Rock Impact 1`
		-- (9118609396) at 0.7x, and `MineStrikeImpact` is THE SAME RECORDING at 0.78x. Being bitten and
		-- swinging a pickaxe were one sound a tenth of a tone apart — on the layer that is supposed to
		-- be the most alarming read in the game, during a run the player spends mostly inside the
		-- mining loop. It is now a dull wet gut impact with no stone in it, so contact can never again
		-- be mistaken for the pick landing.
		ThreatHit = cue({
			assetId = "9113513536",
			volume = 0.94,
			playbackSpeed = 0.8,
			cooldownSeconds = 0.12,
			bus = "Focus",
			maxVoices = 2,
		}),
		-- THE WIND-UP, not the hit. An attack is two sounds because it is two moments: the body
		-- commits, and then the body arrives. The `*Attack` rows above are the arrival and fire on the
		-- animation's own strike frame; these fire the instant the swing starts, which is the half
		-- second a player still has to move. Each is deliberately quieter than its arrival.
		--
		-- A throaty snarl as the body gathers. This and the Knotwalker's wind-up were the project's only
		-- two cues sourced from an unverified uploader's generic "Slash Sound Effect"; both are now
		-- licensed creature audio, which also means every sound in this file comes from one of two
		-- accountable sources (Pro Sound Effects, or the project's own uploads).
		DarkCrawlerLunge = cue({
			assetId = "9116311525",
			volume = 0.36,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.05,
			maxVoices = 3,
			maxDurationSeconds = 0.55,
			fadeOutSeconds = 0.08,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 58,
			emitterSize = 2.5,
		}),
		-- A heavy vocalised wing-flap: the moth stops circling the flame and commits to it. The source
		-- is tagged for exactly this beat ("flutter, vocal, attack, grab") rather than being the
		-- VoidFly's buzz slowed to less than half speed, which is what it used to be.
		MothLunge = cue({
			assetId = "9113979818",
			volume = 0.4,
			playbackSpeed = 0.82,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.86,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 3,
			maxDurationSeconds = 1.2,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 44,
			emitterSize = 2,
		}),
		-- THE DIVE. A wet whipping swish: the moment the fly lets go of the roof and drops, which is the
		-- only warning a player gets that the dark patch overhead was occupied. Distinct from both the
		-- idle buzz and the strike, so the three beats of an ambush are three different sounds.
		VoidFlyLunge = cue({
			assetId = "9120627691",
			volume = 0.42,
			playbackSpeed = 1.45,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.05,
			maxVoices = 3,
			maxDurationSeconds = 0.8,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 38,
			emitterSize = 1.5,
		}),
		-- A deep breathy growl. The Listener is blind and hunts by ear, so the instant it commits is the
		-- one moment it stops being quiet — and it must be a VOICE, not the rock scrape this row used
		-- to play, which a player could not tell from the cave settling around them.
		ListenerLunge = cue({
			assetId = "9113971433",
			volume = 0.34,
			playbackSpeed = 0.66,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
			maxDurationSeconds = 0.68,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 56,
			emitterSize = 3,
		}),
		-- One long dry crack as a folded limb straightens. Deliberately the same family of sound as the
		-- Knotwalker's idle joint-ticking below and its wet arrival above: this creature is audibly
		-- made of levers, and all three of its layers say so at different moisture and length.
		KnotwalkerLunge = cue({
			assetId = "9113546532",
			volume = 0.32,
			playbackSpeed = 0.88,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
			maxDurationSeconds = 0.5,
			fadeOutSeconds = 0.07,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 48,
			emitterSize = 2,
		}),
		-- Stone dragging on stone as it hauls back for the strike. Its own scrape family rather than the
		-- shared strata-strain source, so a Calver winding up is distinguishable from the cave settling
		-- — which matters more here than anywhere, because this creature's whole output is convincing
		-- you the ceiling is about to move.
		CalverLunge = cue({
			assetId = "9125881620",
			volume = 0.32,
			playbackSpeed = 1.1,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 56,
			emitterSize = 2.5,
		}),
		-- LOCOMOTION. The most frightening sound in a cave is the one that tells you something is
		-- moving and how fast. Both rows are mixed far below the attack layers on purpose: they are
		-- meant to be the thing you strain to hear, and the client scales each playback by the body's
		-- own animation weight, so a creeping stalk is nearly silent and a charge is not.
		--
		-- ONE STEP CUE PER WALKING BODY, where there used to be one shared `ThreatStep` for all three.
		-- That row was `Avalanche Debris 7` — a twenty-two-second avalanche recording, clipped to its
		-- first fraction of a second — and it was ALSO the player's own `FootstepStone` and
		-- `FootstepMoss` source. So in a game whose stated design risk is "if you cannot see, hearing
		-- does all the work", the single question a player most needs answered in the dark — is that me,
		-- or is that it? — was being asked of one identical sample. Each body now plants its own foot,
		-- and none of them plants the player's.
		--
		-- Only the crawler, the Listener and the Knotwalker have a gait to source these from; the moth
		-- flies, and the VoidFly and Calver never leave the ceiling.
		--
		-- Chitin on stone: a single clacky claw tap, sub-second, so one plant is one event.
		CrawlerStep = cue({
			assetId = "9125467664",
			volume = 0.19,
			playbackSpeed = 0.86,
			cooldownSeconds = 0.1,
			bus = "Focus",
			volumeMinMultiplier = 0.7,
			volumeMaxMultiplier = 1,
			-- Wide pitch variance because a footstep is the one cue that repeats often enough to become
			-- a metronome if every plant sounds identical, and a metronome is the opposite of dread.
			pitchMinMultiplier = 0.88,
			pitchMaxMultiplier = 1.14,
			maxVoices = 5,
			maxDurationSeconds = 0.5,
			fadeOutSeconds = 0.08,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 46,
			emitterSize = 1.5,
		}),
		-- The heaviest walker on the roster, and the only one that lands with real body weight behind
		-- it: a crunching mass onto dirt rather than a claw tick. It carries furthest of the three,
		-- which is the point — the Listener is the creature you are meant to hear coming and stop
		-- mining for.
		ListenerStep = cue({
			assetId = "9113469691",
			volume = 0.21,
			playbackSpeed = 0.72,
			cooldownSeconds = 0.1,
			bus = "Focus",
			volumeMinMultiplier = 0.7,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.1,
			maxVoices = 5,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 46,
			emitterSize = 2,
		}),
		-- A different claw from the crawler's, pitched down and stretched: the same chitin, but on a
		-- limb long enough to be reaching rather than scuttling. Quietest and shortest-ranged of the
		-- three, because a Knotwalker is supposed to arrive from a direction you were not listening in.
		KnotwalkerStep = cue({
			assetId = "9125467704",
			volume = 0.16,
			playbackSpeed = 0.68,
			cooldownSeconds = 0.1,
			bus = "Focus",
			volumeMinMultiplier = 0.7,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.86,
			pitchMaxMultiplier = 1.12,
			maxVoices = 5,
			maxDurationSeconds = 0.55,
			fadeOutSeconds = 0.08,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 40,
			emitterSize = 1.5,
		}),
		-- Dry paper wings. A moth does not walk, so this is its footstep: the sound that says one is
		-- already in the room with you. It was `Whoosh By Howling Wind` — a six-second wind gust — which
		-- is weather, not an animal, and it is now an actual recording of insect wings.
		MothWing = cue({
			assetId = "9114876115",
			volume = 0.085,
			playbackSpeed = 1.15,
			cooldownSeconds = 0.6,
			bus = "Focus",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.12,
			maxVoices = 3,
			maxDurationSeconds = 1.4,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 3,
			rollOffMaxDistance = 28,
			emitterSize = 1.5,
		}),
		-- IDLE VOICES — the layer that did not exist. Four of the six bodies made no sound whatsoever
		-- unless they were walking at you or already hitting you: a crawler holding a dark corner, a
		-- Knotwalker waiting in the room you were about to enter, and a Calver on the vault were all
		-- completely silent, and so was the CAVE LISTENER — the creature whose entire design is that it
		-- lives by sound. A threat that is only audible once it commits gives a player nothing to
		-- avoid, which turns every encounter into an ambush and flattens the tension the roster was
		-- built for.
		--
		-- These are the quietest rows in the file and the shortest-ranged, deliberately. They are not
		-- a warning system — the attack layer is that. They are the sound of the room not being empty,
		-- and they stop working the moment they are loud enough to pinpoint. All five sit well under
		-- every step cue, which in turn sits well under every attack cue.
		--
		-- The VoidFly is absent from this set on purpose: `FlyBuzz` is already its idle voice and it
		-- owns a bespoke ceiling-occlusion path (`ceilingFlyBuzz`) that this generic layer does not
		-- model. It is not a missing row.
		--
		-- A low spider hiss from the dark it is holding.
		CrawlerIdle = cue({
			assetId = "9113982931",
			volume = 0.115,
			playbackSpeed = 0.8,
			cooldownSeconds = 1.2,
			bus = "Focus",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 1.6,
			fadeOutSeconds = 0.25,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 34,
			emitterSize = 2,
		}),
		-- Ratchety insect clicking from a moth resting on the stone. Thin and high against the
		-- crawler's hiss, so two idle bodies in one room stay tellable apart.
		MothIdle = cue({
			assetId = "9119531802",
			volume = 0.075,
			playbackSpeed = 0.72,
			cooldownSeconds = 1.2,
			bus = "Focus",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.12,
			maxVoices = 2,
			maxDurationSeconds = 1.1,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 3,
			rollOffMaxDistance = 26,
			emitterSize = 1.5,
		}),
		-- THE MOST IMPORTANT ROW IN THIS BLOCK. A deep, quiet, breathy gurgle — the blind thing
		-- listening. It is the loudest and furthest-carrying idle voice by a clear margin, because the
		-- Listener is the one creature a player is supposed to be able to hear BEFORE deciding whether
		-- to keep swinging a pick, and until now the creature built entirely around sound was the only
		-- one that made none.
		ListenerIdle = cue({
			assetId = "9113973119",
			volume = 0.155,
			playbackSpeed = 0.55,
			cooldownSeconds = 1.5,
			bus = "Focus",
			volumeMinMultiplier = 0.78,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 2.2,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 44,
			emitterSize = 2.5,
		}),
		-- Dry joint ticking. The Knotwalker's whole gimmick is standing somewhere you have not looked
		-- yet, so its idle is the one that most often plays from an unseen room — short, sparse clicks
		-- that place it roughly without drawing it for you.
		KnotwalkerIdle = cue({
			assetId = "9113542386",
			volume = 0.1,
			playbackSpeed = 0.7,
			cooldownSeconds = 1.2,
			bus = "Focus",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.1,
			maxVoices = 2,
			maxDurationSeconds = 1.3,
			fadeOutSeconds = 0.22,
			rollOffMinDistance = 4,
			rollOffMaxDistance = 32,
			emitterSize = 2,
		}),
		-- "With nothing in range it only scrapes" is what Config/Threats has always said the Calver
		-- does between strikes. This is that scrape, which previously had no cue behind it at all: a
		-- slow stone drag from the vault overhead, so a player who hears it can look up and find the
		-- thing before it decides to bring the ceiling down on them.
		CalverIdle = cue({
			assetId = "9125876215",
			volume = 0.095,
			playbackSpeed = 0.8,
			cooldownSeconds = 1.5,
			bus = "Focus",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 2,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 5,
			rollOffMaxDistance = 38,
			emitterSize = 2.5,
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
		-- Additional low-gain cave punctuation. The director owns their rarity and surface placement.
		CaveDistantSettle = cue({
			assetId = "9118609396",
			volume = 0.055,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.75,
			bus = "Ambience",
			volumeMinMultiplier = 0.7,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 1,
			maxDurationSeconds = 3.2,
			fadeOutSeconds = 0.4,
			rollOffMinDistance = 14,
			rollOffMaxDistance = 88,
			emitterSize = 8,
		}),
		CaveColdDraft = cue({
			assetId = "9120698168",
			volume = 0.05,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.75,
			bus = "Ambience",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 1,
			maxDurationSeconds = 5.8,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 82,
			emitterSize = 6,
		}),
		CaveDripCluster = cue({
			assetId = "rbxasset://sounds/impact_water.mp3",
			volume = 0.052,
			playbackSpeed = 1.12,
			cooldownSeconds = 0.2,
			bus = "Ambience",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 1.2,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 2,
			rollOffMaxDistance = 40,
			emitterSize = 0.75,
		}),
		-- YOUR OWN FOOTSTEPS, one row per cave plus one for standing water.
		--
		-- THE PLAYER MADE NO SOUND AT ALL BEFORE THESE EXISTED, which in a game whose stated design risk
		-- is "horror lives on audio, and if you cannot see, hearing does all the work" was the largest
		-- hole in the mix: the most frequent event available — a footfall, several times a second, for
		-- the entire run — was silence, and a first-person body that makes no noise reads as a floating
		-- camera rather than a person in a cave.
		--
		-- SELF-AUDIBLE ONLY, AND DELIBERATELY SO. These are World-bus presentation played on the local
		-- player's own ears. They emit nothing through server/NoiseService, because Config/Sound's
		-- emitter list is what the CAVE hears and walking is not on it. Making footsteps audible to
		-- threats would hand every hearing row a permanent track on every moving player and turn the
		-- Cave Listener from a mining threat into an unavoidable one.
		--
		-- Placeholder sources on the same footing as the ambience above: each re-voices a licensed asset
		-- already in this file at a materially different speed and gain, which is enough to read as a
		-- different surface underfoot. The pitch spread is wide on purpose — identical repeated footfalls
		-- become a metronome faster than any other sound in a game.
		FootstepStone = cue({
			assetId = "9113218672",
			volume = 0.11,
			playbackSpeed = 1.15,
			cooldownSeconds = 0,
			bus = "World",
			volumeMinMultiplier = 0.7,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.88,
			pitchMaxMultiplier = 1.12,
			maxVoices = 3,
			maxDurationSeconds = 0.5,
			fadeOutSeconds = 0.08,
		}),
		-- Softer and duller: wet growth absorbs a footfall where bare slate rings it.
		FootstepMoss = cue({
			assetId = "9113218672",
			volume = 0.085,
			playbackSpeed = 0.82,
			cooldownSeconds = 0,
			bus = "World",
			volumeMinMultiplier = 0.68,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.82,
			pitchMaxMultiplier = 1.05,
			maxVoices = 3,
			maxDurationSeconds = 0.55,
			fadeOutSeconds = 0.1,
		}),
		-- Brighter and shorter: a brittle crunch with no tail, which is what packed glacier does.
		FootstepIce = cue({
			assetId = "9118628948",
			volume = 0.1,
			playbackSpeed = 1.28,
			cooldownSeconds = 0,
			bus = "World",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.18,
			maxVoices = 3,
			maxDurationSeconds = 0.4,
			fadeOutSeconds = 0.06,
		}),
		-- WADING. Overrides the family cue wherever there is standing water, in every cave — the water
		-- is the same water everywhere and it is also the sound of a hazard actively costing you wax, so
		-- it is the one footstep that should cut through rather than blend in.
		FootstepWater = cue({
			assetId = "9125499039",
			volume = 0.13,
			playbackSpeed = 1.35,
			cooldownSeconds = 0,
			bus = "World",
			volumeMinMultiplier = 0.75,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.15,
			maxVoices = 3,
			maxDurationSeconds = 0.5,
			fadeOutSeconds = 0.08,
		}),
		-- THE TWO FAMILY-EXCLUSIVE AMBIENT VOICES. Weighted to zero everywhere but one cave
		-- (Config/CaveFamilies.ambience), so these are the sounds only Moss makes and only Ice makes.
		--
		-- Placeholder sources, on the same footing as the Lurker rows below: each re-voices a licensed
		-- asset already in this file at a materially different speed, gain and rolloff, which is enough
		-- to read as a different sound because the mix is what this file owns. Replace the asset IDs
		-- when dedicated ambience is uploaded; nothing outside these two rows has to change.
		--
		-- ICE'S. The cave itself under load, and the only ambient event in the game authored for the
		-- CEILING surface — in the family that drops things on you, the cave speaks from overhead. Slow
		-- and deep against the strata strain it is cut from, and it carries much further than anything
		-- else here: Ice's identity is long open halls, and a sound that travels the length of one is
		-- that identity in the audio layer.
		CaveGlacierGroan = cue({
			assetId = "9125880974",
			volume = 0.095,
			playbackSpeed = 0.72,
			cooldownSeconds = 0.8,
			bus = "Ambience",
			volumeMinMultiplier = 0.78,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.02,
			maxVoices = 1,
			maxDurationSeconds = 7.5,
			fadeOutSeconds = 0.9,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 110,
			emitterSize = 12,
		}),
		-- MOSS'S. Water running down a wall a few studs away rather than the deep hidden pulse it is cut
		-- from: faster, thinner, quieter, and with a rolloff tight enough (46 against CaveHiddenWater's
		-- 76) that it reads as CLOSE AND ON THE ROCK instead of far and underfoot. That contrast is the
		-- whole point — Moss already has the hidden pulse, and a second distant water sound would have
		-- added density without adding information.
		CaveSeepRun = cue({
			assetId = "9125499039",
			volume = 0.065,
			playbackSpeed = 1.05,
			cooldownSeconds = 0.4,
			bus = "Ambience",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 6,
			fadeOutSeconds = 0.5,
			rollOffMinDistance = 3,
			rollOffMaxDistance = 46,
			emitterSize = 1.5,
		}),
		-- Warden set-piece layers. The wake is a room-wide geological strain; contact is a heavy body
		-- impact, distinct from the ordinary creature voices above.
		WardenWake = cue({
			assetId = "9125880974",
			volume = 0.62,
			playbackSpeed = 0.78,
			cooldownSeconds = 0.5,
			bus = "Focus",
			maxVoices = 2,
			maxDurationSeconds = 2.2,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 72,
			emitterSize = 6,
		}),
		WardenAttack = cue({
			assetId = "9118609396",
			volume = 0.92,
			playbackSpeed = 0.74,
			cooldownSeconds = 0.15,
			bus = "Focus",
			maxVoices = 3,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 68,
			emitterSize = 4,
		}),
		-- Ashamed Lurker. Placeholder sources drawn from the licensed cues already in this file:
		-- breathing and the joint crack are a stone fracture pitched around, and the grab reuses the
		-- impact at full weight. Replace the asset IDs when dedicated creature audio is uploaded;
		-- the volumes and rolloffs below are already tuned for the arch.
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
			-- Accepted co-op strikes can legitimately land on the same seam in the same frame. Voice
			-- limits bound density; an emitter cooldown would incorrectly erase the second miner.
			cooldownSeconds = 0,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 5,
			rollOffMinDistance = 6,
			-- Match the server's clean-strike hearing radius. Fumble and break carry farther only
			-- through their truthful authored accent layers.
			rollOffMaxDistance = 46,
			emitterSize = 2.5,
		}),
		-- Dead centre. Bright, tight, and pitched clearly above a merely good hit, so Perfect is
		-- audible as a different EVENT rather than a louder version of the same one. Layers on top of
		-- MineStrikeImpact — the crunch is the impact, this is the ring of a clean bite.
		MineStrikePerfect = cue({
			assetId = "9118628948",
			volume = 0.38,
			playbackSpeed = 1.02,
			cooldownSeconds = 0,
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
			cooldownSeconds = 0,
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
			cooldownSeconds = 0,
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

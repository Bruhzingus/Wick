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
		ambiencePreviewCue: string,
		ambiencePreviewIntervalSeconds: number,
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
		-- NOTE that this floor now applies to the underground playlist too, since that rides the
		-- ambience bus: a player can take the cave down to a tenth but never mute it. That is the
		-- intent — the cave is never allowed to go fully silent on a player who is listening for what
		-- is coming — but it is a stricter rule than the music slider's 0, so it is stated rather
		-- than left to be discovered.
		ambienceMinMultiplier = 0.1,
		-- IN THE LOBBY the ambience bus carries nothing at all: the cave director only runs inside an
		-- expedition and the playlist only plays underground. So the ambience slider moves against
		-- silence up there and reads as a dead control, however correctly it is wired. This row is the
		-- sample that answers it, played through the ambience bus itself so what the player hears while
		-- dragging IS the setting rather than an imitation of it. SettingsController plays it only
		-- outside an expedition; underground the playlist already answers the slider.
		ambiencePreviewCue = "SettingsAmbiencePreview",
		ambiencePreviewIntervalSeconds = 0.32,
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
			-- EVERYTHING THE CAVE SOUNDS LIKE WHEN NOTHING IS HAPPENING: the director's one-shots and the
			-- underground playlist both ride here, so the settings menu's AMBIENCE slider governs the
			-- whole background layer a player hears for a whole descent. That is what a player means by
			-- the word, and routing the tracks anywhere else left the control inaudible.
			--
			-- 0.45 is a bus TRIM, not a statement about how loud ambience should be: it is another 20%
			-- below the prior 0.5625 mix (55% below authored gain) for the director's rows, which are
			-- authored against it. The playlist rows are authored against 1.0 and divide it back out (see
			-- their `volume`), so moving them here changed their routing and not their level.
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
		-- UNDERGROUND TRACKS RIDE THE AMBIENCE BUS, NOT THE MUSIC BUS. To a player these ARE the cave's
		-- ambience — the only thing audible for minutes at a time — so they must answer the control
		-- labelled AMBIENCE. On the music bus they answered a slider nobody reached for during a run,
		-- and the ambience slider governed one-shots too rare to hear a change in.
		--
		-- 0.782 IS STILL THE SAME 0.352 IN THE MIX. The ambience bus trims to 0.45, so each row divides
		-- that back out (0.352 / 0.45 = 0.782) and lands at the level it has always played at, which is
		-- 20% below its original 0.44. Change the bus trim and these must be re-derived, or the descent
		-- gets louder without anyone having asked for it.
		--
		-- MenuMusic stays on the music bus above: the lobby is not a cave and has no ambience to be part
		-- of, which also leaves the MUSIC slider a real job.
		CaveAmbience = cue({
			assetId = "71682768476112",
			volume = 0.782,
			bus = "Ambience",
			maxVoices = 1,
		}),
		CaveTrack2 = cue({
			assetId = "136582960170775",
			volume = 0.782,
			bus = "Ambience",
			maxVoices = 1,
		}),
		CaveTrack3 = cue({
			assetId = "104375150403939",
			volume = 0.782,
			bus = "Ambience",
			maxVoices = 1,
		}),
		CaveTrack4 = cue({
			assetId = "113564986043204",
			volume = 0.782,
			bus = "Ambience",
			maxVoices = 1,
		}),
		DialSnap = cue({ volume = 0.2, cooldownSeconds = 0.08, bus = "UI", maxVoices = 2 }),
		LowWax = cue({ volume = 0.45, cooldownSeconds = 5, bus = "Focus", maxVoices = 1 }),
		Water = cue({ volume = 0.4, looped = true, bus = "World", maxVoices = 1 }),
		ThreatNear = cue({ volume = 0.5, cooldownSeconds = 4, bus = "Focus", maxVoices = 1 }),
		-- Free Creator Store SFX by Pro Sound Effects: a short, restrained insect vocal.
		-- THE PATROL BUZZ. A bug on a ceiling, minding its own business — and at 0.14 it was so far
		-- under the cave bed that it was doing none of the work the comment on `ceilingFlyBuzz` claims
		-- for it ("this is now the ENTIRE tell"). Raised to a level where a fly overhead is a thing you
		-- notice rather than a thing you can only find afterwards.
		FlyBuzz = cue({
			assetId = "9114506042",
			volume = 0.42,
			cooldownSeconds = 3,
			bus = "Focus",
			volumeMinMultiplier = 0.86,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 48,
			emitterSize = 1.5,
		}),
		-- THE SAME BUG COMING AT YOU. Played instead of the patrol buzz while the fly is hunting, on a
		-- much tighter interval (Config/Threats.ceilingFlyBuzz.pursuit*), and the three changes here are
		-- what turn one into the other: half again the level, a third faster so the wingbeat rises, and
		-- a wide pitch spread so a fly that is chasing you never settles into a drone the way a patrolling
		-- one does. It is the same recording on purpose — the player has to hear that it is the thing
		-- that was on the ceiling a moment ago.
		FlyBuzzHunt = cue({
			assetId = "9114506042",
			volume = 0.62,
			playbackSpeed = 1.34,
			cooldownSeconds = 0.5,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.12,
			maxVoices = 3,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 66,
			emitterSize = 2,
		}),
		-- Confirmed threat-contact layers. The crawler gets a flesh slice, the moth a compact bite,
		-- and every other rendered kind has an explicit voice. ThreatHit is deliberately non-spatial
		-- and victim-only so taking wax always has an immediate, frightening body cue.
		-- THE BLOW LANDING, AND IT IS NO LONGER A SCREAM. This row was a vocal, which meant every crawler
		-- contact was a throat and a player had no way to tell the wind-up from the hit — the whole
		-- creature sounded like one long shriek at two lengths. It is now the Warden`s footfall recording
		-- slowed and cut to 0.45s: a heavy body part arriving on you, which is what the animation is
		-- actually doing. The lunge below keeps the voice, so the pair reads as "it committed" and then
		-- "it connected".
		--
		-- NOT A MINING SOURCE, and that is a rule rather than a preference — AudioConfigTests pins every
		-- creature voice against the four pick recordings, because a crawler that hits you with the same
		-- sample as a pickaxe teaches the player the wrong thing about what just happened.
		DarkCrawlerAttack = cue({
			assetId = "9118588165",
			volume = 0.92,
			playbackSpeed = 0.85,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			rollOffMinDistance = 10.5,
			rollOffMaxDistance = 96,
			emitterSize = 3,
			maxDurationSeconds = 0.45,
			fadeOutSeconds = 0.06,
		}),
		-- WAS A SHARK BITE. `9119055965` is Pro Sound Effects' "Shark Bite Smaller Teeth Snaps" — a
		-- large aquatic predator's jaw closing, catalogued under sea animals. The body wearing it is an
		-- insect with a pair of glass fangs that gape and chew (NewModelsAndObjects/CaveMoth:
		-- `ATTACK.feedingReachDegrees`), so what a player heard on contact belonged to a different
		-- animal in a different medium entirely.
		--
		-- Now the moth's OWN idle voice (`MothIdle`, below — Pro Sound Effects' "Sprite Chitter": small
		-- insects, ratchety clicks, cicada-like), driven far faster and cut short so the same ratchet
		-- reads as one mandible snapping shut instead of an insect resting on the stone. The two rows
		-- sharing a source is deliberate, not a shortcut — it is the same move already made for the
		-- Ashamed Lurker's breath/lunge pair and the Warden's wake/roar pair below — and it means this
		-- creature's rest sound and its bite are recognizably the same mouth.
		MothBite = cue({
			assetId = "9119531802",
			volume = 0.8,
			playbackSpeed = 1.45,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.06,
			maxVoices = 3,
			maxDurationSeconds = 0.3,
			fadeOutSeconds = 0.05,
			rollOffMinDistance = 9,
			rollOffMaxDistance = 78,
			emitterSize = 2.5,
		}),
		-- THE VOIDFLY LANDING ON YOUR CANDLE. Its contact effect is Snuff — it is not biting a player,
		-- it is a hand-sized armoured body slamming into the flame, four times, to put it out. This is
		-- a big flying insect batting against a window pane, which is the closest real-world recording
		-- of exactly that event. Previously this was `FlyBuzz`'s own file sped up 38%, so the fly's
		-- idle patrol, its dive and its strike were one sample at three speeds and none of the three
		-- read as an attack.
		-- THE BITE, AND IT IS A BITE NOW. This was a percussive hit — a thing striking you with an
		-- object — which is wrong for a creature the size of a fist that lands on you and feeds. The
		-- insect source the grubs use, run fast and cut very short: mandibles closing on skin, twice a
		-- second, not a hammer. Quieter than the old row as well, because the horror of this creature is
		-- that it is small and ON you rather than that it is loud.
		VoidFlyAttack = cue({
			assetId = "9119531802",
			volume = 0.72,
			playbackSpeed = 2.2,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.86,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.12,
			maxVoices = 3,
			maxDurationSeconds = 0.2,
			fadeOutSeconds = 0.04,
			rollOffMinDistance = 7.5,
			rollOffMaxDistance = 60,
			emitterSize = 2,
		}),
		-- A heavy wet body blow. The Listener carries its skull low and hits with the whole mass behind
		-- it, so this is a ribcage impact rather than the small-teeth snap it used to share with the
		-- moth — two creatures of very different size must not close on you with the same jaw.
		ListenerAttack = cue({
			assetId = "9118167124",
			volume = 0.98,
			playbackSpeed = 0.78,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			rollOffMinDistance = 10.5,
			rollOffMaxDistance = 93,
			emitterSize = 3,
		}),
		-- Wet ligament and cartilage. The Knotwalker is a narrow thing built of long forelimbs, and what
		-- it does on contact is fold one around you — a squishing joint rather than the crawler's clean
		-- slice, which is the sound this row used to borrow.
		KnotwalkerAttack = cue({
			assetId = "9119560180",
			volume = 0.91,
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
			rollOffMinDistance = 9,
			rollOffMaxDistance = 87,
			emitterSize = 2.5,
		}),
		-- ROCK ON ROCK, and the only creature in the game whose "attack" cue is correctly geological:
		-- the Calver never touches a player. It strikes the vault above you to bring the ice down, so
		-- what a player hears is the blow LANDING ON THE CEILING, not on them. A dedicated rock-hitting-
		-- rock impact rather than the shale burst it used to share with dripstone, mining and the bell.
		CalverAttack = cue({
			assetId = "9125869159",
			volume = 0.96,
			playbackSpeed = 0.92,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			rollOffMinDistance = 10.5,
			rollOffMaxDistance = 96,
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
			volume = 1.18,
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
			volume = 0.66,
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
			rollOffMinDistance = 9,
			rollOffMaxDistance = 87,
			emitterSize = 2.5,
		}),
		-- A heavy vocalised wing-flap: the moth stops circling the flame and commits to it. The source
		-- is tagged for exactly this beat ("flutter, vocal, attack, grab") rather than being the
		-- VoidFly's buzz slowed to less than half speed, which is what it used to be.
		MothLunge = cue({
			assetId = "9113979818",
			volume = 0.62,
			playbackSpeed = 1.05,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.86,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 3,
			maxDurationSeconds = 1.2,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 7.5,
			rollOffMaxDistance = 66,
			emitterSize = 2,
		}),
		-- THE DIVE. A wet whipping swish: the moment the fly lets go of the roof and drops, which is the
		-- only warning a player gets that the dark patch overhead was occupied. Distinct from both the
		-- idle buzz and the strike, so the three beats of an ambush are three different sounds.
		-- The commit: the dive itself, an insect winding up rather than an object being swung. Kept as the
		-- wing source rather than the mandible one so the pair reads as "it came at you, then it bit".
		VoidFlyLunge = cue({
			assetId = "9120627691",
			volume = 0.62,
			playbackSpeed = 1.6,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.05,
			maxVoices = 3,
			maxDurationSeconds = 0.8,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 57,
			emitterSize = 1.5,
		}),
		-- A deep breathy growl. The Listener is blind and hunts by ear, so the instant it commits is the
		-- one moment it stops being quiet — and it must be a VOICE, not the rock scrape this row used
		-- to play, which a player could not tell from the cave settling around them.
		ListenerLunge = cue({
			assetId = "9113971433",
			volume = 0.44,
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
			rollOffMinDistance = 9,
			rollOffMaxDistance = 84,
			emitterSize = 3,
		}),
		-- One long dry crack as a folded limb straightens. Deliberately the same family of sound as the
		-- Knotwalker's idle joint-ticking below and its wet arrival above: this creature is audibly
		-- made of levers, and all three of its layers say so at different moisture and length.
		KnotwalkerLunge = cue({
			assetId = "9113546532",
			volume = 0.42,
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
			rollOffMinDistance = 7.5,
			rollOffMaxDistance = 72,
			emitterSize = 2,
		}),
		-- Stone dragging on stone as it hauls back for the strike. Its own scrape family rather than the
		-- shared strata-strain source, so a Calver winding up is distinguishable from the cave settling
		-- — which matters more here than anywhere, because this creature's whole output is convincing
		-- you the ceiling is about to move.
		CalverLunge = cue({
			assetId = "9125881620",
			volume = 0.42,
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
			rollOffMinDistance = 9,
			rollOffMaxDistance = 84,
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
			volume = 0.22,
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
			rollOffMinDistance = 6,
			rollOffMaxDistance = 69,
			emitterSize = 1.5,
		}),
		-- The heaviest walker on the roster, and the only one that lands with real body weight behind
		-- it: a crunching mass onto dirt rather than a claw tick. It carries furthest of the three,
		-- which is the point — the Listener is the creature you are meant to hear coming and stop
		-- mining for.
		ListenerStep = cue({
			assetId = "9113469691",
			volume = 0.24,
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
			rollOffMinDistance = 7.5,
			rollOffMaxDistance = 69,
			emitterSize = 2,
		}),
		-- A different claw from the crawler's, pitched down and stretched: the same chitin, but on a
		-- limb long enough to be reaching rather than scuttling. Quietest and shortest-ranged of the
		-- three, because a Knotwalker is supposed to arrive from a direction you were not listening in.
		KnotwalkerStep = cue({
			assetId = "9125467704",
			volume = 0.18,
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
			rollOffMinDistance = 6,
			rollOffMaxDistance = 60,
			emitterSize = 1.5,
		}),
		-- Dry paper wings. A moth does not walk, so this is its footstep: the sound that says one is
		-- already in the room with you. It was `Whoosh By Howling Wind` — a six-second wind gust — which
		-- is weather, not an animal, and it is now an actual recording of wingbeats.
		--
		-- Also no longer the Crawler's idle recording, which it had been sharing: a moth in flight and a
		-- crawler at rest are the two things most likely to be in one room together, and they were the
		-- same file.
		-- THE WINGS, AND THEY WERE ALL BUT INAUDIBLE. At 0.098 this was thirty times quieter than the
		-- creature it belongs to and the moth genuinely had no flying sound at all — the one body on the
		-- roster with no footfalls, so this row IS its locomotion. Raised to sit where a step cue sits, and
		-- the interval that drives it was tightened in Config/Threats so a moth in the room beats its wings
		-- every second or two rather than every four.
		MothWing = cue({
			assetId = "9113443896",
			volume = 0.46,
			playbackSpeed = 1.25,
			cooldownSeconds = 0.6,
			bus = "Focus",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.12,
			maxVoices = 3,
			maxDurationSeconds = 1.4,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 4.5,
			rollOffMaxDistance = 42,
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
			volume = 0.13,
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
			rollOffMinDistance = 6,
			rollOffMaxDistance = 51,
			emitterSize = 2,
		}),
		-- Ratchety insect clicking from a moth resting on the stone. Thin and high against the
		-- crawler's hiss, so two idle bodies in one room stay tellable apart.
		--
		-- ITS OWN RECORDING NOW. This used to be the same asset as `MothBite` at a different speed, so
		-- the sound of a moth sitting still and the sound of one biting you were one recording — the
		-- single worst kind of collision, because it is the pair a player most needs to tell apart and
		-- they belong to the same body. Wings rather than mandibles: resting is not a slower bite.
		MothIdle = cue({
			assetId = "9113992528",
			volume = 0.3,
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
			rollOffMinDistance = 4.5,
			rollOffMaxDistance = 39,
			emitterSize = 1.5,
		}),
		-- THE MOST IMPORTANT ROW IN THIS BLOCK. A deep, quiet, breathy gurgle — the blind thing
		-- listening. It is the loudest and furthest-carrying idle voice by a clear margin, because the
		-- Listener is the one creature a player is supposed to be able to hear BEFORE deciding whether
		-- to keep swinging a pick, and until now the creature built entirely around sound was the only
		-- one that made none.
		ListenerIdle = cue({
			assetId = "9113973119",
			volume = 0.18,
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
			rollOffMinDistance = 7.5,
			rollOffMaxDistance = 66,
			emitterSize = 2.5,
		}),
		-- Dry joint ticking. The Knotwalker's whole gimmick is standing somewhere you have not looked
		-- yet, so its idle is the one that most often plays from an unseen room — short, sparse clicks
		-- that place it roughly without drawing it for you.
		KnotwalkerIdle = cue({
			assetId = "9113542386",
			volume = 0.115,
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
			rollOffMinDistance = 6,
			rollOffMaxDistance = 48,
			emitterSize = 2,
		}),
		-- "With nothing in range it only scrapes" is what Config/Threats has always said the Calver
		-- does between strikes. This is that scrape, which previously had no cue behind it at all: a
		-- slow stone drag from the vault overhead, so a player who hears it can look up and find the
		-- thing before it decides to bring the ceiling down on them.
		CalverIdle = cue({
			assetId = "9125876215",
			volume = 0.11,
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
			rollOffMinDistance = 7.5,
			rollOffMaxDistance = 57,
			emitterSize = 2.5,
		}),
		--------------------------------------------------------------------------------
		-- THE WICK ENEMY PACK (shared/Enemies, docs/wick-enemies/SOUND.md)
		--------------------------------------------------------------------------------
		--
		-- WHY THESE ARE CUES AND NOT THE PACK'S OWN `SOUNDS` TABLES. Each pack module ships a SOUNDS
		-- table of raw asset ids and an `EnemyKit.emitter()` that builds bare Sound instances. That
		-- bypasses everything this file exists to provide: buses, voice limits, ducking, the cave's own
		-- reverb (`AudioCues.setCaveAcoustics`) and — most importantly for these five — OCCLUSION.
		--
		-- Occlusion is not a nicety here, it is the mechanic. A Gnawer's eat loop heard through forty
		-- studs of solid rock has to sound like it is through rock, because "there is something in the
		-- next room" is the entire warning the player gets. So the pack's SOUNDS tables are left empty
		-- (the modules run silent by design and need no edit), and the integration layer plays these
		-- rows at the creature's own part through `AudioCues.playAt`.
		--
		-- SIXTEEN ROWS, NOT THE PACK'S FULL SOUNDS TABLE. The first six are exactly what SOUND.md calls
		-- "mechanics" or prioritises — eat, warn, idle, snap, scream, churn. The rest (GnawerImpact,
		-- QueenCall, QueenBirth, QueenBite, GrubAttack, GrubEat, the Longarm's reveal/slash/grab/flee/death)
		-- are NOT in that priority list; they exist because the integration layer (server/EnemySystem)
		-- already fires real state transitions for a wall-smash, a room-wide summon, a birth beat, a
		-- grub latching on, an unfold, each of the two attacks, a panic and a collapse — and a state
		-- transition with no cue behind it is a silent bug wearing a comment that says it should be
		-- audible.
		-- Everything else in each module's SOUNDS table (listen, drink, hurt, the other creatures'
		-- deaths) is still deliberately unauthored: nothing in this game's own code calls those yet, so
		-- there is nothing for a missing cue to break.
		--
		-- SOURCES ARE PLACEHOLDERS, AND ARE MEANT TO BE REPLACED. Every row below points at a verified
		-- public-domain Roblox library recording (AssetTypeId 3, ProSoundEffects) chosen to be close
		-- enough to SOUND.md's brief to ship on, not at bespoke audio. SOUND.md asks for recordings the
		-- owner has made and personally verified; when those exist, swapping them in is a one-line
		-- change per row and every range, bus, cooldown and duration here stays as tuned.
		--
		-- LEVELS ARE TIERED BY WHAT THE CUE IS FOR, not by how big the creature is. Three bands, and a new
		-- row should be placed in one of them deliberately:
		--   * MECHANICS AND JUMPSCARES sit loudest — the Gnawer's warn and charge, the Longarm's reveal,
		--     snap and scream, the Queen's call and bite. These are cues a player must not be able to
		--     miss, and several deliberately exceed 1.0 (the mixer clamps at 10, not 1).
		--   * REACTIONS AND PAYOFFS sit in the middle — deaths, grabs, staggers, flee confirmations.
		--     Audible without competing with the cue that warned you.
		--   * AMBIENT TEXTURE sits quietest — the grub idle and eat, the Queen's churn, the birth beat.
		--     These are things a player should PICK UP ON rather than be told, and a brood at threat
		--     volume stops being a nuisance and starts sounding like a boss.
		-- The eat loop is the one deliberate exception: it is ambient in character but a mechanic in
		-- function (SOUND.md is explicit that a Gnawer nobody can hear through a wall is unfair), so it
		-- is voiced up with the mechanics despite being a background loop.
		--
		-- ONE RECORDING PER EVENT IS THE RULE. These twenty-one rows previously ran on FIVE recordings,
		-- which meant the Queen's landmark churn and the Longarm's jumpscare scream were the same rock
		-- scrape at two speeds. They now run on nineteen, and the only pair still sharing one is
		-- GnawerImpact/QueenBite, which cannot occur on the same floor. If a future edit points two cues
		-- at one asset again, that is the regression to catch.

		-- HOW FAR ANY OF THIS CARRIES WAS RAISED WHOLESALE, AND THAT IS WHY THE NUMBERS BELOW LOOK ODD
		-- NEXT TO THE PROSE. Every creature row in this file — this block, the ordinary threat roster
		-- above, the Warden and the Lurker — had both its rolloff distances multiplied by 1.5, and every
		-- Gnawer row by 2. Owner decision: creatures were being seen before they were heard, which
		-- inverts what this whole layer is for, and the Gnawer got double because it is the one creature
		-- whose entire encounter is "hear it before you walk into the room".
		--
		-- THE RATIOS BETWEEN ROWS ARE UNCHANGED, which is what makes the pass safe: every argument in the
		-- comments below about one cue carrying further than another still holds, because they all moved
		-- together. Where a comment cites a specific stud figure it is quoting the AUTHORED number and
		-- the row now reads 1.5x (or 2x) that — the reasoning is what was worth keeping, not the digits.

		-- 1. THE GNAWER EATING. The single most important cue in the pack: it is how a player learns a
		-- room is dangerous BEFORE walking into it, and SOUND.md is explicit that without it the
		-- creature is unfair. Looped, and reaching a little past the 45 studs the doc asks for so it is
		-- comfortably audible rather than marginally so at that range.
		--
		-- The gravel source run slow and low: rock being ground down, which is what it is doing.
		GnawerEat = cue({
			assetId = "9113218672",
			volume = 0.39,
			playbackSpeed = 0.46,
			looped = true,
			bus = "Focus",
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.1,
			maxVoices = 2,
			rollOffMinDistance = 20,
			rollOffMaxDistance = 104,
			emitterSize = 4,
		}),
		-- 2. THE CHARGE WARNING. The other mechanic, and the only thing standing between the player and
		-- an unavoidable hit. It must carry FURTHER than the eat loop — sight reaches about 20 studs, so
		-- a telegraph that only travels 45 arrives with the creature already on top of you.
		--
		-- "Goliath Vocal Deep Growling Voice 20", slowed slightly into something with more mass behind it.
		-- An actual animal voice rather than the rock recording this used to borrow: the whole read is
		-- "the grinding stopped and something ALIVE started", and a second voicing of the eat loop's own
		-- gravel could never say that.
		--
		-- NOTE FOR WHOEVER TIMES THIS: Config.StoneGnawer.warnSeconds is 1.1 and must not shrink. This
		-- row's `maxDurationSeconds` is the AUDIO length and is allowed to be shorter than the state —
		-- what may never happen is the cue starting late.
		GnawerWarn = cue({
			assetId = "9114628598",
			volume = 0.81,
			playbackSpeed = 0.85,
			cooldownSeconds = 0.4,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.05,
			maxVoices = 2,
			maxDurationSeconds = 1.1,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 28,
			rollOffMaxDistance = 156,
			emitterSize = 5,
		}),
		-- 3. THE GRUB'S IDLE. SOUND.md warns that a brood of eight must not sound like one recording
		-- played eight times, and asks for a per-instance PlaybackSpeed fixed at spawn.
		--
		-- THE PITCH SPREAD BELOW ALREADY DOES THAT, and is why this needs no special handling: the
		-- multiplier is rolled once when the voice is created, and a LOOPED voice is created once per
		-- grub and then simply runs. So eight grubs are eight rolls that never change — which is exactly
		-- the "set it at spawn and never touch it" the doc asks for. The spread is wide on purpose.
		--
		-- "Creature Mix Big Flying Insects 4" — chitinous and many-legged. SOUND.md wants fingernail-on-comb
		-- clicks; an insect recording is the closest thing in the library and reads as the same creature.
		GrubIdle = cue({
			assetId = "9113977316",
			volume = 0.14,
			playbackSpeed = 1.15,
			looped = true,
			bus = "World",
			pitchMinMultiplier = 0.82,
			pitchMaxMultiplier = 1.24,
			maxVoices = 8,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 51,
			emitterSize = 1.5,
		}),
		-- 4. THE LONGARM. NOTHING BEFORE IT COMMITS, EVERYTHING AFTER. There is deliberately no idle, no
		-- creep and no footstep row for this creature — SOUND.md's `creep` is the one line of its spec
		-- this file refuses on purpose, because the whole design is that the player gets nothing to hear
		-- until it has already moved. If an idle or a footstep ever appears here, the design has been
		-- lost.
		--
		-- Every row below hangs off a state the server brain actually enters (LongarmBehavior), in the
		-- order it enters them: reveal → strike → hold, or flee, or death.
		--
		-- THE SLASH is the outer attack: the arm whipping across the far edge of its reach at a player
		-- who thought they were clear. It is the cue most likely to arrive from BEHIND somebody, so it
		-- carries as far as the snap does — and it is thinner and faster than the snap on purpose,
		-- because the two attacks have to be tellable apart by ear alone. Air being cut, not a
		-- mechanism locking: "Buggy Whip Light Crack Swish", which is mostly air, against the snap's
		-- heavier "Whip Cracks 2".
		LongarmSlash = cue({
			assetId = "9113611449",
			volume = 0.62,
			playbackSpeed = 1.3,
			cooldownSeconds = 0.25,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.1,
			maxVoices = 2,
			maxDurationSeconds = 0.45,
			fadeOutSeconds = 0.08,
			rollOffMinDistance = 18,
			rollOffMaxDistance = 105,
			emitterSize = 3,
		}),
		-- THE SNAP is the inner one — the thrust that grabs, going from folded to nine studs out in a
		-- frame. Short, hard and bright so it reads as a mechanism rather than a voice, because what
		-- just happened is structural.
		-- THE REVEAL is the unfold, and it is the ONLY warning this creature ever gives: the brain holds
		-- its ground for `revealSeconds` (0.55) with the arms coming apart and nothing else happening,
		-- and that half-second is the player's entire opportunity to break range. It was silent until
		-- now, which meant the tell was purely visual — worthless to anyone facing the wrong way in a
		-- cave lit by one candle.
		--
		-- "Bow Stretches Wood Creaking Ripping Tearing", slightly slowed — literally rope and wood under
		-- tension, which is what SOUND.md asks for, rather than the whip crack the snap uses. The two
		-- must not be the same sample — "something is unfolding"
		-- and "it just reached you" are different events and the player has to be able to tell them
		-- apart in the dark. `maxDurationSeconds` is kept under `revealSeconds` so the creak has
		-- finished before the snap lands on top of it.
		LongarmReveal = cue({
			assetId = "9125407239",
			volume = 0.65,
			playbackSpeed = 0.9,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 0.5,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 15,
			rollOffMaxDistance = 90,
			emitterSize = 3,
		}),
		LongarmSnap = cue({
			assetId = "9120660382",
			volume = 0.75,
			playbackSpeed = 1.1,
			cooldownSeconds = 0.25,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 18,
			rollOffMaxDistance = 105,
			emitterSize = 3,
		}),
		-- THE SCREAM is the grab, and it is the loudest thing this creature ever does. It fires at the
		-- moment the player has already lost the exchange, so it is not a warning — it is the punctuation
		-- on one, and it wants to be heard by the rest of the party across the floor.
		--
		-- "Female Scream Woman Screams Hysterically 1", SLOWED to 0.8 rather than sped up. SOUND.md asks
		-- for a scream pitched DOWN about five semitones so it stops being a person and starts being a
		-- thing; this row used to run the rock-scrape recording fast, which was the exact opposite move.
		-- Being a pre-moderated library asset also sidesteps the upload-rejection risk the doc flags for
		-- this cue specifically.
		-- THE BODY UNDER BOTH ATTACKS, and the reason neither of them twangs any more. A single sharp
		-- transient on its own — however it is voiced — reads as a plucked string, because that is what
		-- a plucked string IS: one bright attack with nothing behind it. This is the nothing-behind-it,
		-- played underneath the slash and the snap alike: the impact source slowed until it has no
		-- attack of its own left, so it contributes mass and not a second click.
		--
		-- Quieter and much shorter-ranged than either cue it sits under, because it is not meant to be
		-- heard as an event. If a player can point at this layer and name it, it is too loud.
		LongarmBody = cue({
			assetId = "9118609396",
			volume = 0.5,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.2,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 0.5,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 75,
			emitterSize = 3,
		}),
		-- THE CRUNCH, and it lands AFTER the scream rather than with it. The jumpscare used to be one
		-- noise — a voice — and a voice alone is a thing that happened NEAR you; the crunch is what
		-- makes it a thing that happened TO you. LongarmBehavior fires it a third of a second into the
		-- hold, on its own timer, because the two arriving together mix into a single louder scream and
		-- lose the one-two that sells it.
		--
		-- Wet and low: the impact source at a quarter speed, which turns a rock strike into something
		-- closing on a body. Ranged with the scream rather than with the grip, because the whole point
		-- is that the rest of the party hears what just happened to somebody.
		LongarmCrunch = cue({
			assetId = "9118609396",
			volume = 0.95,
			playbackSpeed = 0.26,
			cooldownSeconds = 0.5,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 1.1,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 20,
			rollOffMaxDistance = 150,
			emitterSize = 6,
		}),
		LongarmScream = cue({
			assetId = "9114397739",
			volume = 1.28,
			playbackSpeed = 0.8,
			cooldownSeconds = 0.5,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 1.6,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 24,
			rollOffMaxDistance = 165,
			emitterSize = 6,
		}),
		-- THE GRIP is the other half of the grab, and it plays UNDER the scream on the same transition:
		-- SOUND.md asks for a wet grip plus the air knocked out, and the scream alone is a voice with no
		-- body behind it. Heavy, slow and short-range — this is a contact sound at the player, not a
		-- floor-carrying event like the scream layered over it. Range mirrors the pack's own `grab`
		-- emitter exactly (`EnemyKit.emitter(rig.root, SOUNDS.grab, "Grab", false, 0.9, 6, 40)`).
		LongarmGrab = cue({
			assetId = "9113536416",
			volume = 0.9,
			playbackSpeed = 0.9,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 0.9,
			fadeOutSeconds = 0.15,
			rollOffMinDistance = 9,
			rollOffMaxDistance = 60,
			emitterSize = 2.5,
		}),
		-- THE PANIC. A flare is the only thing that repels this creature, and the flare is a rare,
		-- deliberately-spent consumable — the player has to be able to hear that it WORKED, from behind
		-- their own light, at the moment the thing turns. A scramble rather than a voice: the gravel
		-- source run fast, which is the sound of something large leaving badly.
		LongarmFlee = cue({
			assetId = "9113218672",
			volume = 0.66,
			playbackSpeed = 1.55,
			cooldownSeconds = 0.6,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.1,
			maxVoices = 2,
			maxDurationSeconds = 1.4,
			fadeOutSeconds = 0.25,
			rollOffMinDistance = 15,
			rollOffMaxDistance = 90,
			emitterSize = 4,
		}),
		-- THE COLLAPSE. One point-blank stick kills a Longarm (Config/Longarm: `blast.hitPoints = 1`),
		-- and a party that spends its rarest consumable on the tallest thing in the cave has earned a
		-- confirmation that it is down — the death animation runs for 2.2 seconds before the body is
		-- removed and nobody more than a room away can see it.
		--
		-- "Bone Cracks 16", slowed and given room to ring out: SOUND.md's "arms folding in on
		-- themselves", a structure coming apart rather than an animal crying. The one place this
		-- creature is allowed to sound like it has a skeleton.
		LongarmDeath = cue({
			assetId = "9113542694",
			volume = 0.84,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.4,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 2.2,
			fadeOutSeconds = 0.35,
			rollOffMinDistance = 15,
			rollOffMaxDistance = 105,
			emitterSize = 4,
		}),
		-- 5. THE QUEEN. Looped and at landmark range, because SOUND.md gives this cue a second job:
		-- it is how a player navigates a multi-room boss chamber. She is the loudest fixed point in the
		-- space and you should always be able to tell roughly where she is from anywhere in it.
		--
		-- "Bubbles Big Deep Bloop Swells Slow Pass Bys", halved: thick liquid turning over slowly, which
		-- is SOUND.md's stirred-oatmeal brief far more closely than the rock recording this used to
		-- share with the Longarm's scream.
		QueenChurn = cue({
			assetId = "9125315899",
			volume = 0.58,
			playbackSpeed = 0.5,
			looped = true,
			bus = "Focus",
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			rollOffMinDistance = 36,
			rollOffMaxDistance = 285,
			emitterSize = 12,
		}),
		-- 6. THE GNAWER'S WALL-SMASH. Fires on `onChargeCollide` — a charge that ends in rock rather
		-- than in a player. CLAUDE.md §4 calls having it wreck CaveKit stalagmites "worth the small
		-- effort — it makes the environment feel real"; without a cue behind it that effort is invisible.
		--
		-- The rockfall/impact source, slowed into something heavier than any existing use of it — this
		-- is forty studs of charging mass hitting a wall, not a footstep or a settling stone.
		-- `rollOffMinDistance`/`rollOffMaxDistance` mirror the pack's own `impact` emitter call exactly
		-- (StoneGnawer.new: `EnemyKit.emitter(rig.root, SOUNDS.impact, "Impact", false, 1, 14, 110)`).
		GnawerImpact = cue({
			assetId = "9118609396",
			volume = 1.06,
			playbackSpeed = 0.5,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 0.9,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 28,
			rollOffMaxDistance = 220,
			emitterSize = 4,
		}),
		-- 7. THE REST OF THE GNAWER'S STATE MACHINE. `listen`, `charge`, `hurt` and `death` are every
		-- remaining state Enemies/StoneGnawer can enter, and all four were silent — which left this
		-- creature with exactly two audible moments (the warn and a wall-smash) despite running a
		-- six-state brain. The eat loop above is the only thing it reliably made, so a Gnawer that had
		-- already been disturbed once was effectively mute for the rest of the floor.
		--
		-- THE INTAKE. Fires the instant the grinding stops (StoneGnawer.setState, `listen` from `eat`)
		-- and is the single most important beat this creature has after the eat loop itself: the loop
		-- cutting out is information, but silence is easy to miss under a cave ambience bed, and one
		-- sharp breath in the gap is not. SOUND.md wants the player to stop moving when they hear it.
		--
		-- "Goliath Vocal Deep Growling Voice 21" run fast and cut short — a body drawing breath. Same
		-- creature-voice family as the warn and deliberately so: they are the same animal, one breathing
		-- in and one about to commit. The COOLDOWN is doing real work here: `listen` is where the brain lands after a charge,
		-- a stagger and a hurt (StoneGnawer.step), so without it a repelled Gnawer would gasp three
		-- times in four seconds. Range matches the eat loop it replaces, so it arrives from the same
		-- place in the mix as the sound it just interrupted.
		-- IT FELT SOMETHING BREAK, AND IT IS COMING. Fires once, on the transition into `hunt`, when a
		-- collapse or a detonation somewhere else on the floor has put this creature on its feet and
		-- pointed it at a room it cannot see (StoneGnawerBehavior.stepHunt).
		--
		-- IT HAS TO CARRY FURTHER THAN THE EAT LOOP DOES, because the thing it is announcing happens
		-- outside the eat loop's range by definition — the player who set the dripstone off is 60-plus
		-- studs away, and the whole point of the cue is that they get told the room they are standing
		-- in has stopped being empty. 90 studs against the eat loop's 52.
		--
		-- Voiced as the animal, not the rock: the same breath family as the listen chirp, run slower
		-- and longer so it reads as a decision rather than a flinch. It must never be mistaken for the
		-- warn — that one is a dodge cue with 1.1 seconds of life in it, this one means you have
		-- something like ten seconds before it arrives.
		GnawerHunt = cue({
			assetId = "9114628620",
			volume = 0.5,
			playbackSpeed = 0.82,
			cooldownSeconds = 3,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 28,
			rollOffMaxDistance = 180,
			emitterSize = 4,
		}),
		-- SNUFFLING. What a hunting Gnawer sounds like between decisions: a boar working a scent, or a
		-- bear at a rotten log — short wet bursts through the nose, an ear flicking, nothing that reads
		-- as a voice. It fires on a jittered timer for as long as the creature is walking toward
		-- something it felt (StoneGnawerBehavior), NOT as a loop, and that is the whole design:
		--
		-- A LOOP CANNOT SNUFFLE. Snuffling is irregular by nature — two quick, a pause, one more — and a
		-- continuous voice at a fixed length turns that into a machine breathing. Repeated one-shots on a
		-- randomised interval give the rhythm for free, and the pitch spread below means no two are the
		-- same snuffle. It is also why this does not go through the loop channel, which is one-per-body
		-- and already spoken for by the eat loop.
		--
		-- QUIETER AND SHORTER-RANGED THAN THE HUNT CUE IT FOLLOWS. `GnawerHunt` is the announcement and
		-- carries 90 studs; this is texture for whoever it is getting close to, and at 55 it arrives
		-- about when the creature does. A player hearing snuffling has roughly one room of warning.
		--
		-- Same breath source as the listen chirp and the hunt cue — one animal, three things it does
		-- with its nose — run short and given the widest pitch spread of the three.
		GnawerSnuffle = cue({
			assetId = "9114628620",
			volume = 0.42,
			playbackSpeed = 1.6,
			cooldownSeconds = 0.25,
			bus = "Focus",
			volumeMinMultiplier = 0.72,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.86,
			pitchMaxMultiplier = 1.18,
			maxVoices = 3,
			maxDurationSeconds = 0.28,
			fadeOutSeconds = 0.05,
			rollOffMinDistance = 16,
			rollOffMaxDistance = 110,
			emitterSize = 3,
		}),
		GnawerListen = cue({
			assetId = "9114628620",
			volume = 0.55,
			playbackSpeed = 1.35,
			cooldownSeconds = 1.5,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 0.34,
			fadeOutSeconds = 0.06,
			rollOffMinDistance = 16,
			rollOffMaxDistance = 104,
			emitterSize = 3,
		}),
		-- THE CHARGE ITSELF. SOUND.md asks for this looped while running. It is authored as a ONE-SHOT
		-- bounded to `chargeLockSeconds` instead, because the loop channel in server/EnemySystem/
		-- EnemyAudio is one-per-body (a single `WickLoopCue` attribute) and that channel is already
		-- spoken for by the eat loop. A charge is hard-capped at 1.6s by the brain, so a one-shot of
		-- exactly that length is indistinguishable from a loop that gets stopped on exit — and it
		-- cannot leak a running voice if the body is destroyed mid-charge.
		--
		-- "Rock Scrape Deep Clunky Slides Rumbling Thunder" at natural speed: mass moving over rock, and
		-- pointedly NOT the eat loop's gravel — a charge must not sound like grinding. It must carry as
		-- far as the warn that
		-- precedes it (78) or the telegraph would be louder than the thing it warns about.
		GnawerCharge = cue({
			assetId = "9125880974",
			volume = 0.96,
			playbackSpeed = 1,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 1.6,
			fadeOutSeconds = 0.15,
			rollOffMinDistance = 20,
			rollOffMaxDistance = 156,
			emitterSize = 5,
		}),
		-- THE NON-LETHAL HIT. One stick of the two it takes (Config/StoneGnawer: `blast.hitPoints = 2`)
		-- puts it here, and the player needs to know the difference between "that hurt it" and "that
		-- killed it" immediately — otherwise the correct read on a half-damaged Gnawer is unavailable
		-- until it charges again. Short, because the state is: 0.40s (StoneGnawer.step).
		--
		-- "Goliath Vocal Deep Growling Voice 46" — the creature's own voice, not the impact recording at
		-- a different speed. A stagger is something it did to itself and reads as rock; a hurt is
		-- something the player did to it and has to read as the animal.
		GnawerHurt = cue({
			assetId = "9114630281",
			volume = 0.69,
			playbackSpeed = 1,
			cooldownSeconds = 0.25,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 0.4,
			fadeOutSeconds = 0.08,
			rollOffMinDistance = 20,
			rollOffMaxDistance = 140,
			emitterSize = 3,
		}),
		-- THE COLLAPSE. SOUND.md wants forelegs buckling, a head slam, then a long settling rumble, and
		-- the confirmation matters more on this creature than on any other: two sticks of a scarce
		-- consumable is a real price, and a party that pays it from across a dark room has no visual
		-- read on whether it worked.
		--
		-- LONGER THAN THE BODY IT COMES FROM, ON PURPOSE. StoneGnawerBehavior removes the model at
		-- `stateT > 2.2`, but one-shots are broadcast to a throwaway anchor that outlives the creature
		-- (client/EnemyAudioController.playAtPoint, 4s of Debris), so the settle is free to ring out
		-- past the corpse — which is exactly the 4s tail the doc asks for and the body cannot provide.
		-- Range sits between the hurt and the wall-smash and mirrors the pack's own `death` emitter
		-- (StoneGnawer.new: `EnemyKit.emitter(rig.root, SOUNDS.death, "Death", false, 0.9, 12, 80)`).
		GnawerDeath = cue({
			assetId = "9126239755",
			volume = 0.98,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.4,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			maxDurationSeconds = 2.8,
			fadeOutSeconds = 0.5,
			rollOffMinDistance = 24,
			rollOffMaxDistance = 172,
			emitterSize = 5,
		}),
		-- 8. THE QUEEN'S CALL. Fires every `callInterval` seconds (Config.GrubQueen) and alerts the
		-- room — ENCOUNTERS.md names it the fight's pressure valve. It has to read as a DIFFERENT event
		-- from her churn, not a louder version of it, because the churn is ambient wayfinding a player
		-- is meant to tune out and the call is the one moment on this floor that must cut through
		-- whatever else is happening.
		--
		-- "Creature Vocal Giant Crab Monster Roars 1", slightly slowed. A different recording from the
		-- churn rather than a fast voicing of it, which is the point: the churn is the room and the call
		-- is the animal in it, and they must not be the same thing at two speeds. Range mirrors the
		-- pack's own `call` emitter
		-- (GrubQueen.new: `EnemyKit.emitter(rig.root, SOUNDS.call, "Call", false, 1, 25, 170)`).
		QueenCall = cue({
			assetId = "9113987603",
			volume = 1.17,
			playbackSpeed = 0.9,
			cooldownSeconds = 1,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.05,
			maxVoices = 1,
			maxDurationSeconds = 2,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 37.5,
			rollOffMaxDistance = 255,
			emitterSize = 10,
		}),
		-- 9. THE QUEEN'S BIRTH. Fires on every brood (`Config.GrubQueen.broodInterval`, 2 grubs at a
		-- time). Local rather than floor-carrying — this is a beat at the ovipositor, not a summon —
		-- and deliberately wet rather than fleshy or stony, since every other cue in this block is one
		-- of those two textures and a birth is neither. "Body Wiggle 2" — soft and organic, and no longer
		-- the engine's built-in `impact_water.mp3`, which was the one asset in this block that always
		-- loaded and so was the only creature sound anyone could hear while the preload bug was live.
		--
		-- Range mirrors the pack's own `birth` emitter, which is parented to the ovipositor rather than
		-- the root (GrubQueen.new: `EnemyKit.emitter(rig.ovi, SOUNDS.birth, "Birth", false, 0.8, 6, 55)`)
		-- — this integration broadcasts a position rather than parenting to a live attachment, so the
		-- short range is what keeps it reading as local without needing that distinction.
		QueenBirth = cue({
			assetId = "9113536503",
			volume = 0.58,
			playbackSpeed = 0.85,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 0.8,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 9,
			rollOffMaxDistance = 82.5,
			emitterSize = 2,
		}),
		-- THE QUEEN'S BITE. Her mandibles shutting on somebody who stood in front of her, and the
		-- loudest single event of the encounter after her call. It is not a warning — the warning was
		-- half a second of her head rearing up — so it is voiced as mass arriving rather than as a
		-- voice: the impact recording at half speed, the same move GnawerImpact makes for the same
		-- reason, pitched lower and given longer to land because she is four times the Gnawer. This and
		-- the wall-smash are the only two cues left sharing a recording, and they never fire on the same
		-- floor as each other.
		--
		-- Range sits between her birth (local) and her call (the whole floor): a party across the
		-- chamber should hear that somebody just lost most of a candle; the next room need not.
		QueenBite = cue({
			assetId = "9118609396",
			volume = 1.1,
			playbackSpeed = 0.44,
			cooldownSeconds = 0.5,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.05,
			maxVoices = 2,
			maxDurationSeconds = 1.5,
			fadeOutSeconds = 0.25,
			rollOffMinDistance = 21,
			rollOffMaxDistance = 142.5,
			emitterSize = 7,
		}),
		-- 10. THE GRUB'S BITE. Fires when a grub latches onto a still player (WaxGrubBehavior:
		-- `self.body:setState("attack")`) — a real transition the state machine already makes, which
		-- previously had no cue behind it at all: a brood could feed on a player in total silence.
		--
		-- "Creature Mix Big Flying Insects 5", the sibling recording to the idle's number 4, voiced fast
		-- and cut short. Sibling rather than identical so a grub's rest chitter and its bite are
		-- recognizably the same mandibles without being the same file. Quieter, shorter and closer-range than
		-- every other creature's attack cue in this file: the grub is a nuisance, not a threat, and its
		-- bite should sound like one.
		GrubAttack = cue({
			assetId = "9113977335",
			volume = 0.6,
			playbackSpeed = 1.6,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 0.22,
			fadeOutSeconds = 0.04,
			rollOffMinDistance = 4.5,
			rollOffMaxDistance = 39,
			emitterSize = 1.2,
		}),
		-- 11. THE GRUB EATING A WAX DROP. Fires when a grub parks over a drip-trail point it has
		-- caught up to and starts chewing (WaxGrubBehavior: `self.body:setState("eat")`) — the
		-- payoff for trail-following, which previously ended in the grub just idling beside the
		-- drop until it expired on its own.
		--
		-- "Cactus Crunches 5" at natural speed: actual chewing, which the insect-chitter recordings the
		-- idle and the bite use cannot do. Eating is the one grub state that should sound like the wax
		-- rather than like the animal. Quiet and short-range on purpose — this is ambient scavenging, not a threat cue, so
		-- it rides the World bus like GrubIdle rather than Focus like GrubAttack.
		GrubEat = cue({
			assetId = "9113660936",
			volume = 0.16,
			playbackSpeed = 1,
			cooldownSeconds = 0.3,
			bus = "World",
			volumeMinMultiplier = 0.82,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.1,
			maxVoices = 4,
			maxDurationSeconds = 0.9,
			fadeOutSeconds = 0.15,
			rollOffMinDistance = 4.5,
			rollOffMaxDistance = 36,
			emitterSize = 1.2,
		}),
		-- 12. THE LAST SIX STATES, which close the roster: every remaining transition any pack brain can
		-- make now has a cue behind it. All six were live states with nothing authored against them —
		-- including a boss that died in total silence.
		--
		-- THE LONGARM TAKING A HIT. A blast that does not kill it (Config/Longarm: `blast.hitPoints = 1`
		-- means one point-blank stick does, so this is splash) drops it into `hurt` for 0.42s.
		-- "Female Scream Woman Screams Hysterically 2" — the sibling recording to its scream, slowed the
		-- same way for the same reason, then cut short and held well under the scream's level. Same
		-- throat, half a second, nothing like the same event.
		LongarmHurt = cue({
			assetId = "9114397912",
			volume = 0.6,
			playbackSpeed = 0.8,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 0.42,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 18,
			rollOffMaxDistance = 105,
			emitterSize = 3,
		}),
		-- THE BROOD SCATTERING. `flee` is the stomp-and-flare response and it is the one grub state a
		-- player deliberately causes, so it has to be audible as a RESULT: you did a thing and the floor
		-- emptied. Wider-ranged and louder than any other grub cue because it is many bodies at once.
		GrubFlee = cue({
			assetId = "9113977177",
			volume = 0.41,
			playbackSpeed = 1.45,
			cooldownSeconds = 0.4,
			bus = "Focus",
			volumeMinMultiplier = 0.85,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.86,
			pitchMaxMultiplier = 1.18,
			maxVoices = 4,
			maxDurationSeconds = 1.1,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 69,
			emitterSize = 3,
		}),
		-- A GRUB TAKING A HIT, and a grub dying. Kept quiet and close: a brood is a nuisance rather than
		-- a threat, and eight simultaneous death cues at threat volume would read as a boss fight. The
		-- wide pitch spread is the same rule as GrubIdle — eight of these must not be one sound eight
		-- times. `maxVoices` is generous for exactly that reason.
		GrubHurt = cue({
			assetId = "9113979325",
			volume = 0.25,
			playbackSpeed = 1.55,
			cooldownSeconds = 0.12,
			bus = "World",
			volumeMinMultiplier = 0.82,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.84,
			pitchMaxMultiplier = 1.2,
			maxVoices = 6,
			maxDurationSeconds = 0.35,
			fadeOutSeconds = 0.08,
			rollOffMinDistance = 7.5,
			rollOffMaxDistance = 45,
			emitterSize = 2,
		}),
		-- The body is removed at `stateT > 1.6` (WaxGrubBehavior), and this runs just under that so the
		-- sound belongs to a grub that is still visibly there.
		GrubDeath = cue({
			assetId = "9113977085",
			volume = 0.35,
			playbackSpeed = 1.1,
			cooldownSeconds = 0.12,
			bus = "World",
			volumeMinMultiplier = 0.82,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.84,
			pitchMaxMultiplier = 1.2,
			maxVoices = 6,
			maxDurationSeconds = 1.4,
			fadeOutSeconds = 0.25,
			rollOffMinDistance = 9,
			rollOffMaxDistance = 51,
			emitterSize = 2,
		}),
		-- THE QUEEN TAKING A STICK, IN THREE VOICES. Her `hurt` runs 0.70s (GrubQueen.step) and her
		-- churn deliberately keeps running underneath it — she is hit, not interrupted. Louder than her
		-- call is not wanted: the call is a summon and this is a reaction, and a party needs to tell
		-- those apart instantly.
		--
		-- THREE ROWS BECAUSE SIX STICKS KILL HER. One sample played six times over a fight turns the
		-- boss's only pain response into a sound effect the player stops hearing by the third hit —
		-- which is the hit where it matters most, because it is the one telling them the plan is
		-- working. `EnemyAudio` picks one at random per hit (STATE_CUE_VARIANTS), so a full kill is six
		-- groans and no two adjacent ones are reliably the same.
		--
		-- They are three DIFFERENT recordings rather than three speeds of one, because a pitch-shifted
		-- repeat is still recognisably the same event and the ear catches that faster than it catches a
		-- new source. Same animal in all three: a very large thing that has just been damaged and is
		-- letting the room know, voiced low enough that none of them can be mistaken for her call.
		QueenHurt = cue({
			assetId = "9113987614",
			volume = 0.86,
			playbackSpeed = 0.95,
			cooldownSeconds = 0.35,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.05,
			maxVoices = 2,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.15,
			rollOffMinDistance = 30,
			rollOffMaxDistance = 225,
			emitterSize = 8,
		}),
		-- The second voice: the strain source at less than half speed, which turns a rock groan into
		-- something with lungs behind it. The wettest and lowest of the three.
		QueenHurt2 = cue({
			assetId = "9125880974",
			volume = 0.88,
			playbackSpeed = 0.42,
			cooldownSeconds = 0.35,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.18,
			rollOffMinDistance = 30,
			rollOffMaxDistance = 225,
			emitterSize = 8,
		}),
		-- The third: the breath source the Gnawer uses, dropped far below where that creature ever
		-- takes it. Shorter and harder than the other two — the one that reads as a flinch rather than
		-- as a bellow, so the trio covers both halves of what being hit sounds like.
		QueenHurt3 = cue({
			assetId = "9114628620",
			volume = 0.9,
			playbackSpeed = 0.55,
			cooldownSeconds = 0.35,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.93,
			pitchMaxMultiplier = 1.07,
			maxVoices = 2,
			maxDurationSeconds = 0.6,
			fadeOutSeconds = 0.14,
			rollOffMinDistance = 30,
			rollOffMaxDistance = 225,
			emitterSize = 8,
		}),
		-- THE BOSS DYING, which until now happened in complete silence — the single worst gap on the
		-- roster. SOUND.md asks for every vent venting at once and then a long collapse, and "Medium
		-- Pressure Air Release 2" is literally that first half; slowed, it becomes something very large
		-- letting go.
		--
		-- THE LONGEST AND WIDEST CUE IN THE FILE, deliberately. It is the end of a floor-length
		-- encounter, her churn has been the room's ambience for the whole fight, and it stops dead when
		-- this fires (`death` is absent from the churn loop's state list). The silence left behind is
		-- part of the cue, which is why this reaches nearly as far as the churn it replaces: everyone who
		-- could hear her should hear her stop.
		QueenDeath = cue({
			assetId = "9116495722",
			volume = 1.13,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.5,
			bus = "Focus",
			volumeMinMultiplier = 0.95,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 4,
			fadeOutSeconds = 0.8,
			rollOffMinDistance = 36,
			rollOffMaxDistance = 270,
			emitterSize = 10,
		}),

		----------------------------------------------------------------------------------------
		-- UNLITTIUS (Config/Unlittius, DESIGN §9b). Sixteen rows for the second boss.
		--
		-- HE SOUNDS LIKE THE CAVE UNDER TENSION, NOT LIKE AN ANIMAL. SOUND_DESIGN.md's brief for him is
		-- explicit about what he must NOT be — no roaring, no chanting, no orchestral spellcasting —
		-- and everything below is drawn from the two textures that are left: dry rock plates moving
		-- against one another, and a low resonance that sounds like weight the room is carrying. The
		-- Grub Queen is the only creature in this game with a voice; he deliberately has none.
		--
		-- EVERY ROW IS HIS ALONE. Owner decision, and the reason the ids below are all new to this file:
		-- a boss who borrows the cave's own voices does not get an identity, he gets an echo. A player who
		-- has spent forty floors learning that one recording means "a rock landed near me" should not hear
		-- that same recording when a god throws something at them. The one deliberate exception is the
		-- shared DRIPSTONE landing: the stones he pulls out of the ceiling are the cave's own rock and are
		-- supposed to sound exactly like every other formation that has ever fallen on you.
		--
		-- ONE ASSET IS USED TWICE WITHIN HIS OWN SET (`9113807250`, a long gritty stone scrape: the boulder
		-- conjure and the ceiling embed). They are seconds of fight apart, never overlap, and are voiced at
		-- different speeds and ranges.
		--
		-- ALL 24 ARE VERIFIED: every id was resolved against Roblox's asset API for name, duration, artist
		-- and free/public status before it was written here. Every one is Pro Sound Effects, the same
		-- verified creator the rest of this file draws on.
		----------------------------------------------------------------------------------------

		-- HIS PRESENCE. The looped bed that runs the whole encounter: stone holding a weight it should
		-- not be able to. Quiet enough that a player mostly notices it near the dais, and the one thing
		-- in the chamber that stops dead when he is banished.
		UnlittiusTension = cue({
			assetId = "9112795463",
			volume = 0.3,
			playbackSpeed = 0.55,
			looped = true,
			bus = "Ambience",
			maxVoices = 1,
			fadeOutSeconds = 1.6,
			rollOffMinDistance = 14,
			rollOffMaxDistance = 90,
			emitterSize = 12,
		}),

		-- THE CEILING BEING TAKEN HOLD OF. Fires as his arms rise, a second before anything lands, and
		-- it is half the telegraph — the floor markers are the other half. Long and slow: the sound of
		-- a room being leaned on rather than of a rock breaking.
		UnlittiusDripstoneCharge = cue({
			assetId = "9118693443",
			volume = 0.66,
			playbackSpeed = 0.6,
			cooldownSeconds = 0.8,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			maxDurationSeconds = 2.2,
			fadeOutSeconds = 0.4,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 90,
			emitterSize = 8,
		}),

		-- THE SNAP, at 1.62s. Dry, sharp and short — the release, not the impact. The stones' own
		-- landings are the existing `DripstoneImpact`, because they are the cave's own rock and should
		-- sound exactly like it.
		UnlittiusDripstoneSnap = cue({
			assetId = "9118617328",
			volume = 0.86,
			playbackSpeed = 0.78,
			cooldownSeconds = 0.4,
			bus = "Focus",
			volumeMinMultiplier = 0.95,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.05,
			maxVoices = 2,
			maxDurationSeconds = 1.4,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 95,
			emitterSize = 8,
		}),

		-- TWO STONES ASSEMBLING OUT OF NOTHING. Gravel pulled inward, run slowly so it reads as
		-- material ARRIVING — which is the one thing that tells a player the boulders were conjured
		-- rather than picked up.
		UnlittiusBoulderConjure = cue({
			assetId = "9113807250",
			volume = 0.62,
			playbackSpeed = 0.78,
			cooldownSeconds = 0.5,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 1.6,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 70,
			emitterSize = 6,
		}),

		-- THE RELEASE. Not a gunshot: a heavy mass being pushed. Two fire 0.24s apart, and the wide
		-- pitch jitter is what stops the pair reading as one stuttered sound.
		UnlittiusBoulderFire = cue({
			assetId = "9125883521",
			volume = 0.82,
			playbackSpeed = 0.9,
			cooldownSeconds = 0.1,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.1,
			maxVoices = 3,
			maxDurationSeconds = 1.4,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 85,
			emitterSize = 7,
		}),

		-- WHERE IT LANDED, on rock or on somebody. Blunt and low, with the cave's own tail.
		UnlittiusBoulderImpact = cue({
			assetId = "9118584349",
			volume = 0.9,
			playbackSpeed = 0.66,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 1.8,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 85,
			emitterSize = 8,
		}),

		-- THE RITUAL, as his arms go up. A rising resonance under the room rather than a spell: the
		-- point of this cue is that a player hears the summon COMING and has the whole hold to run in.
		UnlittiusSummonRise = cue({
			assetId = "9112795571",
			volume = 0.62,
			playbackSpeed = 0.52,
			cooldownSeconds = 1,
			bus = "Focus",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.05,
			maxVoices = 1,
			maxDurationSeconds = 2.6,
			fadeOutSeconds = 0.5,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 80,
			emitterSize = 9,
		}),

		-- THE FLOOR OPENING. Gravel and debris at each arrival point; the Gnawer's own voice takes over
		-- immediately after, which is why this one is short and stays out of its way.
		UnlittiusGnawerSpawn = cue({
			assetId = "9118586430",
			volume = 0.7,
			playbackSpeed = 0.74,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 1.2,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 60,
			emitterSize = 5,
		}),

		-- CLAWS DRAWN BACK. Short and close-ranged, and besides the pose it is the only warning a
		-- player standing under him gets — so it is dry and sharp rather than atmospheric.
		UnlittiusMeleeWindup = cue({
			assetId = "9114222038",
			volume = 0.4,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 0.7,
			fadeOutSeconds = 0.1,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 40,
			emitterSize = 3,
		}),

		-- ONE RAKE. Air shear with stone in it. Two fire a quarter-second apart, so the pitch spread is
		-- deliberately wide.
		UnlittiusMeleeSwipe = cue({
			assetId = "9114221908",
			volume = 0.64,
			playbackSpeed = 0.8,
			cooldownSeconds = 0.08,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.88,
			pitchMaxMultiplier = 1.12,
			maxVoices = 3,
			maxDurationSeconds = 0.9,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 48,
			emitterSize = 4,
		}),

		-- A CANDLE CAUGHT, AND IT HURT HIM. THE MOST IMPORTANT CUE IN THE ENCOUNTER: he has no health
		-- bar, so this is how a party knows the eight-candle plan is working. Loud, brittle, capped at
		-- one voice with a long cooldown, so two candles lit together are one wound rather than two
		-- overlapping ones — which would read as a bug rather than as progress.
		UnlittiusRecoil = cue({
			assetId = "9118586053",
			volume = 1.15,
			playbackSpeed = 0.58,
			cooldownSeconds = 0.9,
			bus = "Focus",
			volumeMinMultiplier = 0.97,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 1,
			maxDurationSeconds = 2.4,
			fadeOutSeconds = 0.4,
			rollOffMinDistance = 16,
			rollOffMaxDistance = 130,
			emitterSize = 10,
		}),

		-- BANISH, IN FOUR BEATS. The only sequence in the game that runs three and a half seconds with
		-- nothing else allowed to happen, so each beat gets its own row rather than one long asset: the
		-- timings are gameplay state (`Config.Unlittius.banish`) and must be able to move without
		-- anybody re-cutting audio.
		UnlittiusBanishUnbind = cue({
			assetId = "9114222042",
			volume = 0.88,
			playbackSpeed = 0.5,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 1,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 1,
			pitchMaxMultiplier = 1,
			maxVoices = 1,
			maxDurationSeconds = 2.4,
			fadeOutSeconds = 0.4,
			rollOffMinDistance = 16,
			rollOffMaxDistance = 140,
			emitterSize = 12,
		}),
		UnlittiusBanishRise = cue({
			assetId = "9125883255",
			volume = 0.88,
			playbackSpeed = 0.62,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 1,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 1,
			pitchMaxMultiplier = 1,
			maxVoices = 1,
			maxDurationSeconds = 3,
			fadeOutSeconds = 0.6,
			rollOffMinDistance = 16,
			rollOffMaxDistance = 140,
			emitterSize = 12,
		}),
		UnlittiusBanishEmbed = cue({
			assetId = "9113807250",
			volume = 1.05,
			playbackSpeed = 0.5,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 1,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 1,
			pitchMaxMultiplier = 1,
			maxVoices = 1,
			maxDurationSeconds = 3.2,
			fadeOutSeconds = 0.6,
			rollOffMinDistance = 18,
			rollOffMaxDistance = 160,
			emitterSize = 14,
		}),
		-- THE LAST SOUND OF THE ENCOUNTER, and then deliberate silence before the chamber's own
		-- ambience comes back up. Nothing else in this game is allowed to be the last thing you hear.
		UnlittiusBanishSeal = cue({
			assetId = "9118584737",
			volume = 0.95,
			playbackSpeed = 0.55,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 1,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 1,
			pitchMaxMultiplier = 1,
			maxVoices = 1,
			maxDurationSeconds = 3.6,
			fadeOutSeconds = 0.9,
			rollOffMinDistance = 18,
			rollOffMaxDistance = 160,
			emitterSize = 14,
		}),

		-- THE VIOLET UNDER EVERYTHING. A client-owned loop (client/UnlittiusController) whose gain is
		-- driven by how many candles are lit — full at zero, almost gone at seven, silent at eight. It
		-- is the only cue in this file whose volume is not fixed here, and that is the point: it is the
		-- progress bar this encounter refuses to draw.
		UnlittiusRuneHum = cue({
			assetId = "9112795400",
			volume = 0.36,
			playbackSpeed = 0.72,
			looped = true,
			bus = "Ambience",
			maxVoices = 1,
			fadeOutSeconds = 1.2,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 55,
			emitterSize = 8,
		}),

		-- HIM MOVING. A one-shot rather than a loop, emitted every few seconds while he is actually
		-- drifting and at HIS OWN position, so a player hears the stone shift somewhere off in the dark
		-- and can place him without seeing him. A loop was the obvious implementation and the wrong one:
		-- his speed varies constantly, and a fixed-rate bed would either drone under a stationary boss
		-- or cut in and out every time he stopped to attack.
		UnlittiusDrift = cue({
			assetId = "9118586481",
			volume = 0.3,
			playbackSpeed = 0.46,
			cooldownSeconds = 1.4,
			bus = "World",
			volumeMinMultiplier = 0.82,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 2.6,
			fadeOutSeconds = 0.8,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 70,
			emitterSize = 8,
		}),

		-- THE STONE IN THE AIR, between his snap and its landing. Emitted at the falling stone rather
		-- than at him, which is the whole point of having it: the snap tells you it is coming and this
		-- tells you where from.
		UnlittiusDripstoneFall = cue({
			assetId = "9118694131",
			volume = 0.6,
			playbackSpeed = 0.92,
			cooldownSeconds = 0.1,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 4,
			maxDurationSeconds = 1.6,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 55,
			emitterSize = 5,
		}),

		-- THE POWER GOING OUT OF HIM, one eighth at a time. Rides under `UnlittiusRecoil` on every
		-- candle: the recoil is the wound and this is what it costs him. Pitched down further on each
		-- successive candle by the caller, so the eight of them descend rather than repeat.
		UnlittiusRuneDim = cue({
			assetId = "9112777364",
			volume = 0.52,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.6,
			bus = "Focus",
			volumeMinMultiplier = 0.95,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 1,
			pitchMaxMultiplier = 1,
			maxVoices = 1,
			maxDurationSeconds = 2,
			fadeOutSeconds = 0.6,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 48,
			emitterSize = 6,
		}),

		-- VARIATIONS. Three of the encounter's cues fire often enough that one recording becomes a tell
		-- in its own right: a player stops hearing "a boulder landed" and starts hearing "that clip
		-- again". Each set below is DIFFERENT RECORDINGS rather than the same one re-pitched, because
		-- pitch-shifting a two-second rock impact eight times reads as a broken sampler.
		--
		-- The caller walks the set (`EnemyAudio.playVariant`), so consecutive hits are always different
		-- rather than randomly sometimes identical.
		UnlittiusBoulderImpactB = cue({
			assetId = "9118585250",
			volume = 0.88,
			playbackSpeed = 0.7,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 1.8,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 85,
			emitterSize = 8,
		}),
		UnlittiusBoulderImpactC = cue({
			assetId = "9118586224",
			volume = 0.9,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.12,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 3,
			maxDurationSeconds = 1.8,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 85,
			emitterSize = 8,
		}),

		-- EIGHT RECOILS IN ONE FIGHT is the worst repetition problem in the encounter, and the most
		-- important cue not to let go stale — it is the only feedback that the candles are working.
		UnlittiusRecoilB = cue({
			assetId = "9118585044",
			volume = 1.12,
			playbackSpeed = 0.6,
			cooldownSeconds = 0.9,
			bus = "Focus",
			volumeMinMultiplier = 0.97,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 1,
			maxDurationSeconds = 2.4,
			fadeOutSeconds = 0.4,
			rollOffMinDistance = 16,
			rollOffMaxDistance = 130,
			emitterSize = 10,
		}),
		UnlittiusRecoilC = cue({
			assetId = "9118585294",
			volume = 1.14,
			playbackSpeed = 0.54,
			cooldownSeconds = 0.9,
			bus = "Focus",
			volumeMinMultiplier = 0.97,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 1,
			maxDurationSeconds = 2.4,
			fadeOutSeconds = 0.4,
			rollOffMinDistance = 16,
			rollOffMaxDistance = 130,
			emitterSize = 10,
		}),

		-- The second rake of a pair, so the two never sound like one stuttered swipe. A dry granite
		-- strike against the first's air shear: two different halves of the same claw passing.
		UnlittiusMeleeSwipeB = cue({
			assetId = "9114221862",
			volume = 0.6,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.08,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.88,
			pitchMaxMultiplier = 1.12,
			maxVoices = 3,
			maxDurationSeconds = 0.9,
			fadeOutSeconds = 0.12,
			rollOffMinDistance = 6,
			rollOffMaxDistance = 48,
			emitterSize = 4,
		}),

		----------------------------------------------------------------------------------------
		-- HIS VOICE. Twelve utterances in a language nobody speaks (owner decision).
		--
		-- WHAT THIS OVERRIDES. SOUND_DESIGN.md asks for "no obvious human voice lines" and says "no
		-- chanting human voice is required", and the first implementation of this boss took that
		-- literally: he was the one creature in the game with no voice at all. The owner asked for the
		-- opposite — a wizard muttering in some dead tongue between attacks — and that is a better boss
		-- than a silent one, so the brief loses. What survives from it is the RESTRAINT: these are
		-- mutters, not lines; they are quiet, they are short, and there is no screaming anywhere in the
		-- set.
		--
		-- WHY THEY ARE UNINTELLIGIBLE AND STAY THAT WAY. Two of the twelve are literally catalogued as
		-- "Whisper Bursts, Eerie Unintelligible Phrases"; the other ten are reverberant whispering with
		-- no words in it. Pitched down to roughly two thirds speed they stop sounding like a person and
		-- start sounding like something very large and very old saying something in a language that was
		-- dead before the cave was. Nothing here should ever resolve into English — the moment a player
		-- can make out a word, he becomes a man in a costume.
		--
		-- TWELVE, AND EVERY ONE PLAYS BEFORE ANY REPEATS. `UnlittiusBehavior` walks a shuffled bag
		-- rather than rolling each time, so a fight cannot serve the same mutter twice in a row or three
		-- times in a minute — the specific failure the owner asked to avoid.
		--
		-- EACH ROW HAS ITS OWN BASE PITCH. Ten identical rows re-pitched at playback would read as one
		-- sample on a wheel; giving each utterance its own speed makes them read as different things
		-- being said. The BEHAVIOUR then drops all of them further as candles are lit, so his voice
		-- sinks as he weakens.
		----------------------------------------------------------------------------------------

		UnlittiusVoice1 = cue({
			assetId = "9114228469",
			volume = 0.46,
			playbackSpeed = 0.7,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.6,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice2 = cue({
			assetId = "9114228524",
			volume = 0.48,
			playbackSpeed = 0.66,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.2,
			fadeOutSeconds = 0.6,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice3 = cue({
			assetId = "9114228525",
			volume = 0.45,
			playbackSpeed = 0.74,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.8,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice4 = cue({
			assetId = "9114228578",
			volume = 0.5,
			playbackSpeed = 0.62,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.4,
			fadeOutSeconds = 0.6,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice5 = cue({
			assetId = "9114228632",
			volume = 0.44,
			playbackSpeed = 0.78,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.6,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice6 = cue({
			assetId = "9114228638",
			volume = 0.47,
			playbackSpeed = 0.68,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 3,
			fadeOutSeconds = 0.8,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice7 = cue({
			assetId = "9114228691",
			volume = 0.46,
			playbackSpeed = 0.72,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.7,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice8 = cue({
			assetId = "9114228786",
			volume = 0.45,
			playbackSpeed = 0.64,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.9,
			fadeOutSeconds = 0.8,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		-- THE TWO REAL PHRASES. Catalogued as "Eerie Unintelligible Phrases, Very Breathy, Deep and
		-- Monstrous" — the closest thing in the library to an actual incantation, and the pair that make
		-- the rest of the set read as speech rather than as atmosphere.
		UnlittiusVoice9 = cue({
			assetId = "9126213743",
			volume = 0.54,
			playbackSpeed = 0.76,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 3,
			fadeOutSeconds = 0.6,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 55,
			emitterSize = 5,
		}),
		UnlittiusVoice10 = cue({
			assetId = "9126213744",
			volume = 0.54,
			playbackSpeed = 0.7,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 3,
			fadeOutSeconds = 0.6,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 55,
			emitterSize = 5,
		}),
		-- THE HISSED ONES. Throatier and angrier than the whispers; the bag holds them alongside the
		-- rest so a mutter occasionally comes out as something closer to a threat.
		UnlittiusVoice11 = cue({
			assetId = "9114229167",
			volume = 0.44,
			playbackSpeed = 0.8,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.5,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),
		UnlittiusVoice12 = cue({
			assetId = "9114229293",
			volume = 0.44,
			playbackSpeed = 0.74,
			cooldownSeconds = 2,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 2.8,
			fadeOutSeconds = 0.7,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 52,
			emitterSize = 5,
		}),

		-- THE INCANTATION. Longer, louder and reserved for the summon: the one action of his that IS a
		-- spell being cast, so it is the one moment the muttering becomes a working. Played over the
		-- ritual's held pose rather than at its start, so the words and the arms-up silhouette land
		-- together.
		UnlittiusIncant1 = cue({
			assetId = "9114228469",
			volume = 0.72,
			playbackSpeed = 0.58,
			cooldownSeconds = 3,
			bus = "Focus",
			volumeMinMultiplier = 0.95,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.98,
			pitchMaxMultiplier = 1.02,
			maxVoices = 1,
			maxDurationSeconds = 4.2,
			fadeOutSeconds = 1,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 75,
			emitterSize = 8,
		}),
		UnlittiusIncant2 = cue({
			assetId = "9114228786",
			volume = 0.72,
			playbackSpeed = 0.54,
			cooldownSeconds = 3,
			bus = "Focus",
			volumeMinMultiplier = 0.95,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.98,
			pitchMaxMultiplier = 1.02,
			maxVoices = 1,
			maxDurationSeconds = 4.5,
			fadeOutSeconds = 1,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 75,
			emitterSize = 8,
		}),

		-- THE BANISHMENT, IN HIS OWN VOICE. Two utterances and then nothing — the only place in the
		-- encounter he raises it, and the last thing he ever says.
		--
		-- WHY IT IS TWO AND NOT ONE. A single death cry is a sound effect; a cry and then a fragment that
		-- does not finish is a death. The first lands as the rune comes apart and he understands what is
		-- happening to him — the biggest, longest vocal in the fight, carrying across the whole floor so
		-- a teammate two rooms away knows the party has won. The second is four fifths of a second before
		-- the stone closes: quiet, pitched lower than anything else he has said, and CUT OFF by the seal
		-- rather than allowed to resolve. Then the deliberate silence the sound brief asks for.
		--
		-- A DIFFERENT REGISTER FROM HIS MUTTERING, on purpose. Everything else he says is a reverberant
		-- whisper; these two are from the "Goliath Vocal, Deep Growling Voice, Mumbling Nonsense" family,
		-- which is the same wordless language spoken by something that is no longer trying to be quiet.
		-- Hearing him go from muttering to THIS is the whole point of giving him a voice at all.
		--
		-- IT IS THE SAME LINE EVERY TIME, and that is deliberate where the twelve mutters are deliberately
		-- varied. A party meets him once every twenty floors; the cry is supposed to be the thing they
		-- remember and recognise the second time, which is exactly what varying it would prevent.
		UnlittiusBanishCry = cue({
			assetId = "9114630122",
			volume = 1.2,
			playbackSpeed = 0.55,
			cooldownSeconds = 4,
			bus = "Focus",
			volumeMinMultiplier = 1,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 1,
			pitchMaxMultiplier = 1,
			maxVoices = 1,
			maxDurationSeconds = 5,
			fadeOutSeconds = 0.9,
			rollOffMinDistance = 20,
			rollOffMaxDistance = 190,
			emitterSize = 12,
		}),
		-- The fragment the ceiling takes. Deliberately short, deliberately unresolved.
		UnlittiusLastWord = cue({
			assetId = "9114629203",
			volume = 0.78,
			playbackSpeed = 0.44,
			cooldownSeconds = 4,
			bus = "Focus",
			volumeMinMultiplier = 1,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 1,
			pitchMaxMultiplier = 1,
			maxVoices = 1,
			-- Capped SHORTER than the asset so it is audibly interrupted: the seal arrives on top of it.
			maxDurationSeconds = 1.2,
			fadeOutSeconds = 0.25,
			rollOffMinDistance = 14,
			rollOffMaxDistance = 110,
			emitterSize = 9,
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
		-- THE AMBIENCE SLIDER'S OWN VOICE. Not a cave event: the director never rolls it and no
		-- gameplay path plays it. It exists so the settings menu can demonstrate the ambience bus on
		-- demand, in the lobby as readily as underground.
		--
		-- Deliberately 2D — no rolloff rows — because a preview must not depend on where the player is
		-- standing or on there being cave geometry nearby to hang an emitter from.
		--
		-- Louder than the director's rows (~0.08) on purpose: those are authored to sit under a run and
		-- be heard once, from a distance, while this is heard alone in a paused menu and has to make a
		-- 10%-versus-100% difference obvious in a single drip.
		SettingsAmbiencePreview = cue({
			assetId = "rbxasset://sounds/impact_water.mp3",
			volume = 0.3,
			playbackSpeed = 1.3,
			bus = "Ambience",
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			maxDurationSeconds = 1.2,
			fadeOutSeconds = 0.12,
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
		-- THE OLD WORKINGS' OWN VOICE. Unlike every other ambient row this one is not placed on a
		-- surface the director raycast for — it is hung on a real abandoned relic model somewhere near
		-- the player (`Config/MineRelics`, `client/AmbientCaveDirector`), so it only ever exists in a
		-- cave that actually has equipment rotting in it.
		--
		-- Cut from the gravel creep rather than from anything metallic, pitched down and stretched: what
		-- it has to say is "a heavy dead thing settling half a stud", not "a machine". A clean metal
		-- clang would read as something USING the cart, which is a threat cue, and harmless ambience is
		-- never allowed to imitate one. It is also the tightest rolloff in the ambient set (38 against
		-- CaveDistantSettle's 88) — the object is right there, and a sound from a specific thing has to
		-- be locatable or it becomes another vague noise from the dark.
		CaveOldWorkings = cue({
			assetId = "9113218672",
			volume = 0.075,
			playbackSpeed = 0.68,
			cooldownSeconds = 0.6,
			bus = "Ambience",
			volumeMinMultiplier = 0.74,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.05,
			maxVoices = 2,
			maxDurationSeconds = 3.4,
			fadeOutSeconds = 0.4,
			rollOffMinDistance = 3,
			rollOffMaxDistance = 38,
			emitterSize = 1.5,
		}),
		-- Warden set-piece layers. The wake is a room-wide geological strain; contact is a heavy body
		-- impact, distinct from the ordinary creature voices above.
		--
		-- SIX CUES, SIX RECORDINGS — it used to be six cues on THREE. The wake, the roar and the presence
		-- bed were all one rock-scrape sample, which meant the biggest set-piece on the roster announced
		-- itself, threatened you and idled at you in the same voice, and the two that must never be
		-- confused (a Warden waking and a Warden roaring at you) were separated only by playback speed.
		-- Each layer is now its own source: subterranean booms for the wake, a deep vocal for the roar,
		-- rock dropped on rock for the footfall, a body impact for contact, an avalanche for the squeeze,
		-- and a low drone for the bed it carries.
		WardenWake = cue({
			assetId = "9114223352",
			volume = 0.81,
			playbackSpeed = 0.78,
			cooldownSeconds = 0.5,
			bus = "Focus",
			maxVoices = 2,
			maxDurationSeconds = 2.2,
			fadeOutSeconds = 0.2,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 108,
			emitterSize = 6,
		}),
		WardenAttack = cue({
			assetId = "9113525391",
			volume = 1.1,
			playbackSpeed = 0.74,
			cooldownSeconds = 0.15,
			bus = "Focus",
			maxVoices = 3,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 102,
			emitterSize = 4,
		}),
		-- THE WARDEN'S FOOT. Placeholder source on the same footing as the Lurker rows: the heavy
		-- contact body already in this file, taken down to less than half speed so what lands is a
		-- weight rather than a hit. It is the loudest footstep in the game by a wide margin and it is
		-- meant to be — the player's own feet sit at 0.11 and a threat's at a fraction of that, because
		-- those say "I am walking" and this one says "it is in this room and it is coming".
		--
		-- Cooldown is per-emitter (client/AudioCues keys spatial cues by parent), so a footfall can
		-- never be swallowed by the other foot, and the wide pitch spread stops a pursuit at constant
		-- speed from turning into a metronome.
		WardenStep = cue({
			assetId = "9118588165",
			volume = 0.53,
			playbackSpeed = 0.42,
			cooldownSeconds = 0.1,
			bus = "World",
			volumeMinMultiplier = 0.82,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.9,
			pitchMaxMultiplier = 1.12,
			maxVoices = 4,
			maxDurationSeconds = 1.1,
			fadeOutSeconds = 0.15,
			rollOffMinDistance = 15,
			rollOffMaxDistance = 105,
			emitterSize = 5,
		}),
		-- STONE DRAGGING THROUGH STONE, while it folds itself through an opening it does not fit. The
		-- gravel creep stretched most of the way down, which is the one source in this file that is
		-- already a continuous grind rather than an impact.
		WardenSqueeze = cue({
			assetId = "9113222895",
			volume = 0.5,
			playbackSpeed = 0.36,
			cooldownSeconds = 0.5,
			bus = "World",
			volumeMinMultiplier = 0.8,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.92,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 2.4,
			fadeOutSeconds = 0.35,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 96,
			emitterSize = 5,
		}),
		-- THE BELLOW AT FULL HEIGHT. The same geological strain WardenWake is cut from, dropped
		-- another third and given room to run: the wake is the wall failing, this is the thing that
		-- was inside it announcing that it is now standing up.
		WardenRoar = cue({
			assetId = "9114628818",
			volume = 1.06,
			playbackSpeed = 0.5,
			cooldownSeconds = 1,
			bus = "Focus",
			maxVoices = 2,
			maxDurationSeconds = 3.4,
			fadeOutSeconds = 0.5,
			rollOffMinDistance = 18,
			rollOffMaxDistance = 165,
			emitterSize = 10,
		}),
		-- THE BED IT CARRIES WITH IT. Looped on the body itself while a player is close enough for it
		-- to matter, so the room a Warden is in never sounds like an empty one. Very quiet and very
		-- low: this is the audio half of the floor shaking, and it must stay under every other cue in
		-- the mix — including its own footsteps landing on top of it.
		WardenPresence = cue({
			assetId = "9112777512",
			volume = 0.16,
			playbackSpeed = 0.3,
			looped = true,
			bus = "World",
			maxVoices = 1,
			rollOffMinDistance = 9,
			rollOffMaxDistance = 87,
			emitterSize = 12,
		}),
		-- Ashamed Lurker. These were three PLACEHOLDERS borrowed from other cues in this file — the breath
		-- and the joint crack were one stone-fracture recording pitched two ways, and the grab was the
		-- rock impact at full weight. So the creature that is supposed to be heard before it is seen
		-- shared a voice with falling masonry, and its two most important moments were the same sample.
		--
		-- All three now have their own: a deep vocal for the breath, an actual snapping stalk for the
		-- joints, and a body impact for the grab. Rolloffs and the arch's tuning are unchanged.
		-- The dry breath is the only warning in the dark. It is deliberately quiet and short-ranged:
		-- it says something is breathing, not exactly where.
		LurkerBreath = cue({
			assetId = "9114628321",
			volume = 0.13,
			playbackSpeed = 0.62,
			cooldownSeconds = 1.5,
			bus = "Focus",
			volumeMinMultiplier = 0.84,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			rollOffMinDistance = 4.5,
			rollOffMaxDistance = 45,
			emitterSize = 1.5,
		}),
		-- The lunge: an abrupt joint crack the moment the arm commits, whether or not it connects.
		LurkerLunge = cue({
			assetId = "9113734496",
			volume = 0.65,
			playbackSpeed = 1.42,
			cooldownSeconds = 0.15,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.04,
			maxVoices = 3,
			rollOffMinDistance = 9,
			rollOffMaxDistance = 82.5,
			emitterSize = 2,
		}),
		-- A connecting grab. This one is meant to be a scare, so it is the loudest cue the creature
		-- has and it carries into the neighbouring rooms.
		-- THE ARCH GRAB, AND IT IS THE LOUDEST CONTACT IN THE GAME NOW. This creature's whole problem
		-- was that being caught by it did not register: a player ran through an archway, lost a fifth of
		-- their wax, and kept going. Three things fix that together and this is one of them — the other
		-- two are the stun (Config/AshamedLurker.trigger.grabStunSeconds) and the arm sweep that is now
		-- big enough to see. Voiced up hard and slowed further, so it is a grip closing rather than a
		-- rustle, and it carries far enough that the rest of the party knows exactly which arch did it.
		LurkerGrab = cue({
			assetId = "9113525643",
			volume = 1.55,
			playbackSpeed = 0.72,
			cooldownSeconds = 0.2,
			bus = "Focus",
			maxVoices = 3,
			rollOffMinDistance = 12,
			rollOffMaxDistance = 105,
			emitterSize = 3,
		}),
		-- THE SECOND HALF OF IT, layered under the grip on the same frame rather than delayed like the
		-- Longarm's crunch: this is not a jumpscare with a beat to it, it is one violent moment in an
		-- archway, and the two sounds arriving together are what make it hit like a door slamming.
		-- The Warden's roar dropped to a quarter speed — a very large thing very close, and the deepest
		-- single sound any creature in the game makes.
		LurkerImpact = cue({
			assetId = "9114628818",
			volume = 1.3,
			playbackSpeed = 0.26,
			cooldownSeconds = 0.3,
			bus = "Focus",
			volumeMinMultiplier = 0.95,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.06,
			maxVoices = 2,
			maxDurationSeconds = 1.5,
			fadeOutSeconds = 0.3,
			rollOffMinDistance = 14,
			rollOffMaxDistance = 120,
			emitterSize = 5,
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
			-- Match the server's clean-strike hearing radius. A fumble remains louder to the cave through
			-- Config/Sound, while its player-facing read comes from the glance animation and HUD rather than
			-- an unrelated second recording layered over this impact.
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
		-- THE EXPLOSIVE SEAM (Config/Mining.explosive). The first-strike gas hiss was removed completely;
		-- only the primed fuse and the actual blast have dedicated voices.
		-- THE CRACKLE. Three seconds of it, and it must not sound like any part of mining — a fumbled
		-- scrape pitched high and dry, so the moment the fuse lights the audio stops being about rock.
		SeamCrackle = cue({
			assetId = "9125880974",
			volume = 0.7,
			playbackSpeed = 1.35,
			cooldownSeconds = 0,
			bus = "Focus",
			maxVoices = 2,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 110,
			emitterSize = 4,
		}),
		-- THE BLAST. The lowest, loudest, furthest-carrying cue in the file, and
		-- for the opposite reason: the bell is heard by friends, and this is heard by everything.
		SeamExplosion = cue({
			assetId = "9113218672",
			volume = 1,
			playbackSpeed = 0.52,
			cooldownSeconds = 0.1,
			bus = "Focus",
			maxVoices = 2,
			maxDurationSeconds = 3.5,
			fadeOutSeconds = 0.5,
			rollOffMinDistance = 20,
			rollOffMaxDistance = 260,
			emitterSize = 10,
		}),
		-- DYNAMITE (Config/Dynamite). These use dedicated, public Creator Store sources instead of the
		-- geology placeholders used by explosive seams. The old borrowed ids could fail asset loading for
		-- the experience and made the entire interaction silent; a rare consumable cannot depend on a
		-- best-effort placeholder for its only warning and payoff.
		--
		-- The burning fuse. This public fire source is long enough to loop cleanly for either fuse length;
		-- its tight rolloff and raised pitch turn the broad burn into a close sputter.
		DynamiteFuse = cue({
			assetId = "158853971",
			volume = 0.68,
			playbackSpeed = 1.35,
			looped = true,
			bus = "Focus",
			maxVoices = 3,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 90,
			emitterSize = 3,
		}),
		-- THE BLAST. One short public boom, played once and non-spatial for each client on the matching
		-- floor. Non-spatial here means guaranteed floor-wide audibility, not a second mix layer.
		DynamiteBlast = cue({
			assetId = "7093763783",
			volume = 0.62,
			playbackSpeed = 1,
			cooldownSeconds = 0.1,
			bus = "Focus",
			maxVoices = 2,
			maxDurationSeconds = 1.25,
			fadeOutSeconds = 0.08,
		}),
		-- HANDLING THE STICK (client/DynamiteViewmodelController). Four local, non-spatial one-shots:
		-- these happen in the player's own hands, so unlike the fuse and the blast they carry no
		-- rolloff and are never heard by anybody else.
		--
		-- EACH RE-VOICES A SOURCE ALREADY LICENSED IN THIS FILE at a materially different speed and
		-- gain, which is the same approach the footstep rows above document and take. Nothing here is a
		-- new upload: a handling cue is a texture rather than a performance, and these four sources
		-- already carry every texture the gesture needs — granular rock for dry paper and wood, moving
		-- air for cloth, and a brittle tick for a dead click.
		--
		-- THE SPEEDS ARE THE WHOLE TRICK, and they are chosen to sit clear of every other use of the
		-- same recording so no two of them can be mistaken for each other:
		--
		--   Equip/Stow  9113218672, the gravel/rock source (footsteps 0.82-1.15, MineBreak 0.92). Run
		--               fast at 1.66 and 1.34 it stops being gravel and becomes a short dry rustle —
		--               waxed paper and a wooden crimp coming out of a satchel. Stow is the same
		--               gesture with less energy rather than a mirror copy of it: lower and quieter,
		--               because stowing is the beat nobody is listening to.
		--   Windup      9120698168, the moving-air source (drafts 0.62-0.9, LadderWinch 0.68). Run the
		--               other way at 1.25 and hard-capped, a six-second cave draft becomes one short
		--               close cloth shift. Almost subliminal on purpose: its job is to confirm the
		--               button registered, not to announce the throw to the room.
		--   Denied      9118628948, the brittle tick (CalciteTick 0.95, FootstepIce 1.28). Dropped to
		--               0.52 the tick loses its ring and lands as a dull dead thunk, which is exactly
		--               the sound of nothing happening.
		--
		-- EVERY ONE IS HARD-CAPPED SHORT. Three of these sources are authored elsewhere as multi-second
		-- ambience, and an uncapped handling cue would leave a cave tail hanging off the player's hands.
		--
		-- Pitch variation is authored on every row so a player throwing four sticks over one floor does
		-- not hear the same recording four times.
		DynamiteEquip = cue({
			assetId = "9113218672",
			volume = 0.3,
			playbackSpeed = 1.66,
			cooldownSeconds = 0.05,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.96,
			pitchMaxMultiplier = 1.05,
			maxVoices = 2,
			maxDurationSeconds = 0.42,
			fadeOutSeconds = 0.07,
		}),
		DynamiteStow = cue({
			assetId = "9113218672",
			volume = 0.19,
			playbackSpeed = 1.34,
			cooldownSeconds = 0.05,
			bus = "Focus",
			volumeMinMultiplier = 0.9,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.95,
			pitchMaxMultiplier = 1.04,
			maxVoices = 2,
			maxDurationSeconds = 0.34,
			fadeOutSeconds = 0.08,
		}),
		DynamiteWindup = cue({
			assetId = "9120698168",
			volume = 0.16,
			playbackSpeed = 1.25,
			cooldownSeconds = 0.08,
			bus = "Focus",
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.08,
			maxVoices = 2,
			maxDurationSeconds = 0.3,
			fadeOutSeconds = 0.06,
		}),
		-- THE THROW. The one handling cue with a real recording behind it, and the only one of these five
		-- the player consciously hears.
		--
		-- THIS IS THE RECORDING MINING USED TO USE, and it is here deliberately. It was pulled from the
		-- game because it misfired on the first swing of a mining stance — a fault of how the mining
		-- stance triggered it, not of the sound, which is an ordinary whoosh and exactly right for the
		-- one gesture in this game that is actually a throw. Mining is still forbidden from playing it
		-- (Tests/AudioConfigTests), so the old fault cannot come back with it.
		--
		-- Pitched down and slowed a little: this is a heavy stick leaving the hand, not a blade.
		DynamiteThrow = cue({
			assetId = "9126284289",
			volume = 0.42,
			playbackSpeed = 0.86,
			cooldownSeconds = 0.08,
			bus = "Focus",
			volumeMinMultiplier = 0.92,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.93,
			pitchMaxMultiplier = 1.07,
			maxVoices = 3,
			maxDurationSeconds = 0.8,
			fadeOutSeconds = 0.06,
		}),
		-- On the UI bus rather than Focus, unlike the other four: a refusal is the interface answering
		-- the player, not something happening in the cave. It is also the only one of these that must
		-- cut through whatever else is playing, because it is the reply to a button that did nothing.
		DynamiteDenied = cue({
			assetId = "9118628948",
			volume = 0.3,
			playbackSpeed = 0.52,
			cooldownSeconds = 0.18,
			bus = "UI",
			volumeMinMultiplier = 0.94,
			volumeMaxMultiplier = 1,
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 1,
			maxDurationSeconds = 0.28,
			fadeOutSeconds = 0.05,
		}),
		-- THE BRAZIER CATCHING (Config/Brazier), and the crowned lamp that answers a floor
		-- (Config/WallLamp). Pitched below the seam crackle it borrows its source from and cut short: a
		-- bowl of fuel catches with one soft whump and then simply burns, where a fuse sputters.
		-- Reaches further than most Focus cues because the answering echoes are played from anchors
		-- well out in the dark and have to arrive as the SAME sound, quieter.
		--
		-- ONE ROW, THREE PLAYS. The brazier's chain reaction is this cue and nothing else: the ignition
		-- at the bowl, then one or two delayed copies at reduced level and pitch. A second asset would
		-- have made "something is catching somewhere unseen" read as a different event entirely.
		LanternIgnite = cue({
			assetId = "9125880974",
			volume = 0.72,
			playbackSpeed = 0.74,
			cooldownSeconds = 0.05,
			bus = "Focus",
			maxVoices = 4,
			maxDurationSeconds = 1.6,
			fadeOutSeconds = 0.35,
			rollOffMinDistance = 10,
			rollOffMaxDistance = 140,
			emitterSize = 5,
		}),
		-- ONE WALL CANDLE CATCHING (Config/WallLamp). The same source as the row above, taken up in
		-- pitch and down in level until it is the small sound it should be: a wick taking, not a bowl
		-- of fuel going up. Every lamp on a floor plays this — by hand as a player lights their way,
		-- and once per room during the crowned lamp's cascade — so it is deliberately the quietest
		-- ignition in the game and the shortest.
		--
		-- IT REACHES FURTHER THAN IT IS LOUD, and that is the point of the row. A lamp catching two
		-- rooms away is how a player who fell behind learns that somebody ahead of them is lighting the
		-- way, without a single line of UI. Cheap to hear, expensive to ignore.
		--
		-- MORE VOICES THAN ANY OTHER IGNITION, because the cascade can put several rooms' worth of
		-- these in the air inside a second and a starved voice pool would silently drop the far ones —
		-- which are exactly the ones carrying the information.
		LampIgnite = cue({
			assetId = "9125880974",
			volume = 0.34,
			playbackSpeed = 1.18,
			cooldownSeconds = 0.02,
			bus = "Focus",
			-- A little variance so a cascade reads as a row of separate wicks rather than one sound
			-- repeating on a timer.
			volumeMinMultiplier = 0.88,
			volumeMaxMultiplier = 1.06,
			pitchMinMultiplier = 0.94,
			pitchMaxMultiplier = 1.09,
			maxVoices = 8,
			maxDurationSeconds = 0.75,
			fadeOutSeconds = 0.22,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 120,
			emitterSize = 3,
		}),
		-- THE WINCH, running for as long as the cage is moving (Config/DescentLadder). Looped, low and
		-- close: a chain under load a few feet over the rider's head. Deliberately short-ranged — a
		-- teammate two rooms away learns nothing useful from hearing somebody else's ride.
		LadderWinch = cue({
			assetId = "9120698168",
			volume = 0.5,
			playbackSpeed = 0.68,
			looped = true,
			bus = "Focus",
			maxVoices = 2,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 70,
			emitterSize = 4,
		}),
		-- THE LATCH. One hard clank at each end of the ride: the pawl releasing as the cage sets off,
		-- and the cage setting down at the bottom. Same asset the rock fracture uses, pitched down into
		-- metal.
		LadderLatch = cue({
			assetId = "9125929705",
			volume = 0.6,
			playbackSpeed = 0.62,
			cooldownSeconds = 0.1,
			bus = "Focus",
			pitchMinMultiplier = 0.97,
			pitchMaxMultiplier = 1.03,
			maxVoices = 3,
			rollOffMinDistance = 8,
			rollOffMaxDistance = 80,
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

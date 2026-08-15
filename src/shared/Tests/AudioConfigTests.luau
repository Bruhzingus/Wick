--!strict

local Harness = require(script.Parent.Harness)
local Audio = require(script.Parent.Parent.Config.Audio)
local Dynamite = require(script.Parent.Parent.Config.Dynamite)
local Feel = require(script.Parent.Parent.Config.Feel)
local Mining = require(script.Parent.Parent.Config.Mining)
local Sound = require(script.Parent.Parent.Config.Sound)
local Threats = require(script.Parent.Parent.Config.Threats)
local CaveFamilyRules = require(script.Parent.Parent.Logic.CaveFamilyRules)
local ThreatVisualProtocol = require(script.Parent.Parent.NewModelsAndObjects.ThreatVisualProtocol)

local REQUIRED_PRODUCTION_CUES = {
	"MineStrikeImpact",
	"MineStrikePerfect",
	"MineStrikeClean",
	"MineBreak",
	"CaveStrataStrain",
	"CaveFissureBreath",
	"CaveCalciteTick",
	"CaveHiddenWater",
	"CaveGravelCreep",
	"CaveDistantSettle",
	"CaveColdDraft",
	"CaveDripCluster",
	-- The two family-exclusive voices. They are placeholder re-voicings of assets already in this
	-- file rather than new uploads, which is exactly why they are pinned here: a re-voicing that lost
	-- its asset id would be silent rather than loud, and a cave would quietly stop making the one
	-- sound that is only its.
	"CaveSeepRun",
	"CaveGlacierGroan",
	-- The player's own feet. Pinned because a silent player is the failure this whole layer exists to
	-- fix, and a cue that lost its asset id would fail silently rather than loudly.
	"FootstepStone",
	"FootstepMoss",
	"FootstepIce",
	"FootstepWater",
	"DarkCrawlerAttack",
	"MothBite",
	"VoidFlyAttack",
	"ListenerAttack",
	"KnotwalkerAttack",
	"CalverAttack",
	-- The per-body movement and idle voices. Pinned for the same reason as the player's own feet: a
	-- creature layer that lost its asset id would go SILENT rather than error, and silence is exactly
	-- what this pass was written to remove.
	"CrawlerStep",
	"ListenerStep",
	"KnotwalkerStep",
	"CrawlerIdle",
	"MothIdle",
	"ListenerIdle",
	"KnotwalkerIdle",
	"CalverIdle",
	"WardenWake",
	"WardenAttack",
	-- The set-piece's own body: the footfall that tells a player it is in the room, the grind of it
	-- folding through an opening, the bellow at full height, and the bed it carries. Pinned for the
	-- same reason as the footsteps above — every one of them exists to stop the encounter being
	-- silent, and a lost asset id would fail by going quiet.
	"WardenStep",
	"WardenSqueeze",
	"WardenRoar",
	"WardenPresence",
	"LurkerLunge",
	"LurkerGrab",
}

-- Ambient SOUND-EVENT ids (Config/Feel.ambientCave.soundEvents). Nothing to do with CAVE families —
-- these are the anti-repeat groupings the director rolls between.
local EXPECTED_SOUND_EVENTS: { [string]: boolean } = {
	StrataStrain = true,
	FissureBreath = true,
	CalciteTicks = true,
	HiddenWaterPulse = true,
	GravelCreep = true,
	DistantSettle = true,
	ColdDraft = true,
	DripCluster = true,
	SeepRun = true,
	GlacierGroan = true,
}

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local suite: Harness.Suite = {
	name = "AudioConfig",
	tests = {
		Harness.test("every cue routes to a real bounded mixer bus", function()
			Harness.expect(Audio.buses[Audio.defaultBus] ~= nil, "default audio bus must exist")
			Harness.expect(Audio.maxActiveVoices >= 1, "global voice ceiling must be positive")
			for busName, bus in Audio.buses do
				Harness.expect(bus.voiceLimit >= 1, busName .. " needs a positive voice limit")
				Harness.expect(isFinite(bus.volume) and bus.volume >= 0, busName .. " volume must be finite")
				Harness.expect(isFinite(bus.priority) and bus.priority >= 0, busName .. " priority must be finite")
				local ducking = bus.ducking
				if ducking ~= nil then
					Harness.expect(
						Audio.buses[ducking.sidechainBus] ~= nil,
						busName .. " sidechains from an unknown bus " .. ducking.sidechainBus
					)
				end
			end
			Harness.expect(
				Audio.buses.Focus.priority > Audio.buses.Ambience.priority
					and Audio.buses.Focus.priority > Audio.buses.World.priority
					and Audio.buses.Focus.priority > Audio.buses.UI.priority,
				"Focus must survive lower-priority global voice stealing"
			)
			for cueName, cue in Audio.cues do
				Harness.expect(Audio.buses[cue.bus] ~= nil, cueName .. " routes to an unknown bus " .. cue.bus)
				Harness.expect(cue.maxVoices >= 1, cueName .. " needs a positive voice limit")
				Harness.expect(
					cue.volumeMinMultiplier <= cue.volumeMaxMultiplier,
					cueName .. " volume range is inverted"
				)
				Harness.expect(cue.pitchMinMultiplier <= cue.pitchMaxMultiplier, cueName .. " pitch range is inverted")
				if cue.rollOffMaxDistance ~= nil then
					Harness.expect(
						cue.rollOffMinDistance ~= nil and cue.rollOffMinDistance <= cue.rollOffMaxDistance,
						cueName .. " has an invalid spatial rolloff"
					)
				end
			end
		end),

		Harness.test("cave ambience remains isolated and 20 percent below the prior mix", function()
			Harness.near(Audio.buses.Ambience.volume, 0.45, 1e-6)
			Harness.near(Audio.cues.MenuMusic.volume, 0.1755, 1e-6)
			Harness.equal(Audio.settings.musicMinMultiplier, 0)
			Harness.near(Audio.settings.ambienceMinMultiplier, 0.1, 1e-6)
			for _, cueName in { "AmbientRockfall", "AmbientWaterDrip" } do
				Harness.equal(Audio.cues[cueName].bus, "Ambience", cueName .. " must use the cave ambience bus")
			end
			for _, event in Feel.ambientCave.soundEvents do
				local cue = assert(Audio.cues[event.cueName], event.id .. " has no configured cue")
				Harness.equal(cue.bus, "Ambience", event.id .. " must use the cave ambience bus")
			end
		end),

		Harness.test("mining and five cave families retain assigned source assets and co-op voices", function()
			for _, cueName in REQUIRED_PRODUCTION_CUES do
				local cue = Audio.cues[cueName]
				Harness.expect(cue ~= nil, "missing required cue " .. cueName)
				Harness.expect(cue.assetId ~= "", cueName .. " must not be an empty no-op")
			end
			for _, cueName in
				{
					"MineStrikeImpact",
					"MineStrikePerfect",
					"MineStrikeClean",
				}
			do
				Harness.equal(
					Audio.cues[cueName].cooldownSeconds,
					0,
					cueName .. " must not suppress a teammate striking the same emitter"
				)
			end
			local hearing = Sound.emitters
			Harness.equal(
				Audio.cues.MineStrikeImpact.rollOffMaxDistance,
				hearing.MineStrikeClean.radius,
				"the common contact body must not out-reach a clean strike's server hearing"
			)
			Harness.equal(Audio.cues.MineStrikePerfect.rollOffMaxDistance, hearing.MineStrikeClean.radius)
			Harness.equal(Audio.cues.MineStrikeClean.rollOffMaxDistance, hearing.MineStrikeClean.radius)
			Harness.isNil(
				Audio.cues.MineStrikeFumble,
				"a miss must not layer the old non-impact fumble recording over the common strike"
			)
			Harness.equal(Audio.cues.MineBreak.rollOffMaxDistance, hearing.MineBreak.radius)
			Harness.expect(
				Mining.feedback.impactPresentationRange >= hearing.MineBreak.radius,
				"teammate presentation must cover the loudest server-authorized mining event"
			)
		end),

		Harness.test("the explosive seam warns before it hurts and calls the floor", function()
			local explosive = Mining.explosive
			Harness.isNil(Audio.cues.SeamHiss, "the removed first-strike gas hiss must not return")
			-- ...and the blast must be audible exactly as far as it SUMMONS. A player who cannot hear it
			-- has no way to know that everything on the floor is now walking toward one place.
			Harness.equal(
				Audio.cues.SeamExplosion.rollOffMaxDistance,
				explosive.alertRadius,
				"the blast must be heard exactly as far as it calls threats in from"
			)
			Harness.expect(
				Audio.cues.SeamExplosion.rollOffMaxDistance >= Sound.emitters.SeamExplosion.radius,
				"the blast must never lure further than it can be heard"
			)
			-- The crackle only has to cover the people it can hurt, and comfortably does.
			Harness.expect(
				(Audio.cues.SeamCrackle.rollOffMaxDistance or 0) > explosive.blastRadius,
				"everyone inside the blast must be able to hear the fuse"
			)
		end),

		Harness.test("dynamite has dedicated fuse and blast sources", function()
			local fuse = assert(Audio.cues.DynamiteFuse, "dynamite fuse cue is missing")
			local blast = assert(Audio.cues.DynamiteBlast, "dynamite blast cue is missing")
			Harness.expect(fuse.assetId ~= "" and fuse.looped, "a lit fuse must have a looping warning")
			Harness.expect(blast.assetId ~= "", "a detonation must have an audible payoff")
			Harness.isNil(blast.rollOffMaxDistance, "the one blast must reach the whole matching floor")
			Harness.expect((blast.maxDurationSeconds or math.huge) <= 1.25, "the blast must remain one short boom")
			Harness.isNil(Audio.cues.DynamiteFloorBlast, "a second blast layer would sound like multiple explosions")
			Harness.expect(fuse.assetId ~= Audio.cues.SeamCrackle.assetId, "the fuse must not borrow the seam crackle")
			Harness.expect(
				blast.assetId ~= Audio.cues.SeamExplosion.assetId,
				"the blast must not borrow the seam blast"
			)
			Harness.expect(Dynamite.blast.floorShakeStrength > 0, "the whole floor must feel a small shake")
		end),

		Harness.test("the removed whoosh recording cannot return through another cue", function()
			for cueName, configuredCue in Audio.cues do
				Harness.expect(
					configuredCue.assetId ~= "9126284289",
					cueName .. " reintroduced the banned whoosh recording"
				)
			end
			Harness.isNil(Audio.cues.MineSwing, "mining input must not play a whoosh")
			Harness.isNil(Audio.cues.MineRecover, "mining recovery must not play a whoosh")
			Harness.isNil(Audio.cues.DynamiteThrow, "dynamite throw acknowledgement must remain visual-only")
		end),

		Harness.test("every creature cue a threat names is real, audible, and correctly placed", function()
			-- A threat's voice is addressed by NAME from Config/Threats, so a typo here is silent
			-- rather than loud: the enemy simply stops making the sound, and nothing errors. These are
			-- the rows a player uses to know something is coming and that it has committed, so they
			-- are worth pinning.
			local procedural = Threats.visuals.procedural
			local attackAudio = procedural.attackAudio
			local locomotion = procedural.locomotionAudio
			local idle = procedural.idleAudio
			local spatial = {
				procedural.ceilingFlyBuzz.cueName,
				locomotion.mothWingCueName,
			}
			-- Per-kind locomotion and idle voices. Both maps are deliberately partial — only three
			-- bodies walk, and the VoidFly's idle is `ceilingFlyBuzz` rather than a row in `idleAudio` —
			-- so these iterate what is authored instead of demanding an entry for every kind. What they
			-- do enforce is that anything named is real, audible, and comes from the creature.
			for _, cueName in locomotion.stepCueNames do
				table.insert(spatial, cueName)
			end
			for _, cueName in idle.cueNames do
				table.insert(spatial, cueName)
			end
			for _, kind in ThreatVisualProtocol.kinds do
				local impactCue = assert(attackAudio.impactCueNames[kind], kind .. " has no explicit attack impact cue")
				local lungeCue = assert(attackAudio.lungeCueNames[kind], kind .. " has no explicit attack lunge cue")
				table.insert(spatial, impactCue)
				table.insert(spatial, lungeCue)
			end
			for _, cueName in spatial do
				local cue = Audio.cues[cueName]
				Harness.expect(cue ~= nil, "threats name a cue that does not exist: " .. cueName)
				Harness.expect(cue.assetId ~= "", cueName .. " is a silent no-op")
				Harness.expect(cue.rollOffMaxDistance ~= nil, cueName .. " must come from the creature, not the head")
			end
			-- The victim sting is the one that deliberately is NOT spatial: a confirmed hit has to land
			-- on the player's own ears whatever direction it came from.
			local victim = Audio.cues[attackAudio.victimCueName]
			Harness.expect(victim ~= nil and victim.assetId ~= "", "the victim sting must exist and be audible")
			Harness.isNil(victim.rollOffMaxDistance, "the victim sting must stay non-spatial")

			-- A wind-up that is louder than the blow would invert the read.
			for _, kind in ThreatVisualProtocol.kinds do
				local impactName = assert(attackAudio.impactCueNames[kind], kind .. " impact cue disappeared")
				local lungeName = assert(attackAudio.lungeCueNames[kind], kind .. " lunge cue disappeared")
				local impact = assert(Audio.cues[impactName], impactName .. " is not configured")
				local lunge = assert(Audio.cues[lungeName], lungeName .. " is not configured")
				Harness.expect(lunge.volume < impact.volume, kind .. " wind-up must sit under its arrival")
			end
			-- Locomotion is the layer a player strains to hear. If it ever rises to the attack layer it
			-- stops being information and starts being noise.
			local movementCues = { locomotion.mothWingCueName }
			for _, cueName in locomotion.stepCueNames do
				table.insert(movementCues, cueName)
			end
			for _, cueName in movementCues do
				Harness.expect(
					Audio.cues[cueName].volume
						< Audio.cues[assert(attackAudio.impactCueNames.Moth, "Moth impact cue disappeared")].volume,
					cueName .. " must stay well under the attack layer"
				)
				Harness.expect(
					locomotion.audibleDistance >= (Audio.cues[cueName].rollOffMaxDistance :: number),
					cueName .. " is still audible past the distance the client stops spending voices at"
				)
			end
			-- THE THREE-LAYER ORDERING, which is the whole grammar of the creature mix: a body is
			-- quietest when it is only present, louder when it is moving, and loudest when it commits.
			-- An idle voice that reached its own movement layer would make a stationary creature sound
			-- like an approaching one, which is the confusion the per-kind step split exists to remove.
			--
			-- COMPARED PER CREATURE, not against the roster's quietest cue. Bodies are legitimately
			-- different sizes: the Listener's idle breath is louder in absolute terms than the moth's
			-- WING BEAT, and should be — a moth is the quietest thing in the cave and a Listener is the
			-- heaviest. What must hold is that each body is quieter standing still than moving.
			local movementByKind: { [string]: string } = table.clone(locomotion.stepCueNames)
			-- A moth does not walk; its flutter is its movement layer.
			movementByKind[ThreatVisualProtocol.kinds.moth] = locomotion.mothWingCueName
			for kind, cueName in idle.cueNames do
				local cue = Audio.cues[cueName]
				local movementName = movementByKind[kind]
				if movementName ~= nil then
					Harness.expect(
						cue.volume < Audio.cues[movementName].volume,
						cueName .. " is louder than " .. movementName .. ", so standing still reads as moving"
					)
				end
				Harness.expect(
					idle.audibleDistance >= (cue.rollOffMaxDistance :: number),
					cueName .. " is still audible past the distance the client stops spending voices at"
				)
				local impactName = assert(attackAudio.impactCueNames[kind], kind .. " has an idle voice but no attack")
				Harness.expect(
					cue.volume < Audio.cues[impactName].volume,
					cueName .. " must stay well under its own attack layer"
				)
			end
			-- The VoidFly's passive voice is `ceilingFlyBuzz`, not a row in `idleAudio`. Pinned so that
			-- adding one later is a deliberate act rather than an accident that doubles the density of
			-- the only creature that hangs directly over a player's head.
			Harness.isNil(
				idle.cueNames[ThreatVisualProtocol.kinds.ceilingFly],
				"the VoidFly's idle voice must remain its occlusion-aware buzz"
			)
			Harness.expect(
				idle.alertIntervalSeconds > 0 and idle.calmIntervalSeconds >= idle.alertIntervalSeconds,
				"an alert creature must not speak less often than a calm one"
			)
			Harness.expect(
				idle.quietVolume > 0 and idle.quietVolume <= idle.loudVolume and idle.loudVolume <= 1,
				"the idle volume band must be an ascending 0..1 range"
			)
			-- The step band is handed to AudioCues as a level multiplier, which clamps to 0..1; a value
			-- outside that would quietly do nothing rather than fail.
			Harness.expect(
				locomotion.quietStepVolume > 0
					and locomotion.quietStepVolume <= locomotion.loudStepVolume
					and locomotion.loudStepVolume <= 1,
				"the footstep volume band must be an ascending 0..1 range"
			)
			Harness.expect(
				locomotion.minimumStepWeight > 0 and locomotion.minimumStepWeight < 1,
				"a silent-step floor of 0 makes a standing creature sound like a walking one"
			)
			Harness.expect(
				locomotion.mothWingMinIntervalSeconds > 0
					and locomotion.mothWingMaxIntervalSeconds >= locomotion.mothWingMinIntervalSeconds,
				"the moth flutter interval is inverted"
			)
		end),

		Harness.test("no creature voice is the mining loop wearing a different name", function()
			-- THE REGRESSION THIS EXISTS FOR. The victim sting was `Rock Impact 1` at 0.7x while
			-- `MineStrikeImpact` was THE SAME RECORDING at 0.78x, so being bitten and swinging a pick
			-- were one sound a tenth of a tone apart. A player spends most of a run inside the mining
			-- loop; a creature that borrows from it has no read left at all.
			--
			-- Asset SOURCES are what is compared, because playback speed is not a disguise. The rule is
			-- narrow on purpose: creature voices must not overlap MINING. Stone-on-stone is still
			-- correct for the Calver striking a ceiling, and creature rows may legitimately share the
			-- geology library with dripstone and ambience.
			local miningSources: { [string]: string } = {}
			for _, cueName in
				{
					"MineStrikeImpact",
					"MineStrikePerfect",
					"MineStrikeClean",
					"MineBreak",
				}
			do
				miningSources[assert(Audio.cues[cueName], cueName .. " is not configured").assetId] = cueName
			end

			local procedural = Threats.visuals.procedural
			local creatureCues = {
				procedural.attackAudio.victimCueName,
				procedural.ceilingFlyBuzz.cueName,
				procedural.locomotionAudio.mothWingCueName,
			}
			for _, kind in ThreatVisualProtocol.kinds do
				-- Bound to locals first: `assert` returns every argument it was given, so inlining it
				-- into table.insert would pass the failure message along as a third argument.
				local impactName = assert(procedural.attackAudio.impactCueNames[kind], kind .. " has no impact cue")
				local lungeName = assert(procedural.attackAudio.lungeCueNames[kind], kind .. " has no lunge cue")
				table.insert(creatureCues, impactName)
				table.insert(creatureCues, lungeName)
			end
			for _, cueName in procedural.locomotionAudio.stepCueNames do
				table.insert(creatureCues, cueName)
			end
			for _, cueName in procedural.idleAudio.cueNames do
				table.insert(creatureCues, cueName)
			end

			for _, cueName in creatureCues do
				local assetId = assert(Audio.cues[cueName], cueName .. " is not configured").assetId
				local collision = miningSources[assetId]
				Harness.isNil(
					collision,
					cueName .. " plays the same recording as " .. tostring(collision) .. " (" .. assetId .. ")"
				)
			end

			-- The player's own boots are the other thing a creature must never sound like. Same
			-- reasoning, different confusion: one is "is that my pick?", this is "is that me walking?".
			local ownFootsteps: { [string]: string } = {}
			for _, cueName in { "FootstepStone", "FootstepMoss", "FootstepIce", "FootstepWater" } do
				ownFootsteps[assert(Audio.cues[cueName], cueName .. " is not configured").assetId] = cueName
			end
			for _, cueName in procedural.locomotionAudio.stepCueNames do
				local assetId = Audio.cues[cueName].assetId
				local collision = ownFootsteps[assetId]
				Harness.isNil(
					collision,
					cueName .. " is the player's own " .. tostring(collision) .. " recording (" .. assetId .. ")"
				)
			end
		end),

		Harness.test("ambient sound events are unique, spatial, and backed by configured cues", function()
			local events = Feel.ambientCave.soundEvents
			Harness.equal(#events, 10, "the cave director must own exactly the authored natural events")
			local seenIds: { [string]: boolean } = {}
			for _, event in events do
				Harness.expect(EXPECTED_SOUND_EVENTS[event.id] == true, "unexpected sound event " .. event.id)
				Harness.expect(not seenIds[event.id], "duplicate sound event " .. event.id)
				seenIds[event.id] = true
				Harness.expect(
					event.surface == "Wall" or event.surface == "Ceiling" or event.surface == "Ground",
					event.id .. " has no real surface class"
				)
				if event.allowWater == true then
					Harness.equal(
						event.id,
						"HiddenWaterPulse",
						"only the hidden-water family may anchor to Terrain water"
					)
				end
				if event.id == "HiddenWaterPulse" then
					Harness.equal(event.allowWater, true, "hidden water must retain water-surface eligibility")
				end
				Harness.expect(
					event.minDistance > 0 and event.maxDistance > event.minDistance,
					event.id .. " range is invalid"
				)
				Harness.expect(event.weight > 0, event.id .. " must be selectable")
				Harness.expect(
					event.burstsMin >= 1 and event.burstsMax >= event.burstsMin,
					event.id .. " bursts are invalid"
				)
				Harness.expect(
					(event.burstsMax - 1) * event.burstGapMaxSeconds <= event.durationSeconds,
					event.id .. " burst sequence outlives its occupied ambience slot"
				)
				Harness.expect(
					event.durationSeconds <= Feel.ambientCave.emitterLifetimeSeconds,
					event.id .. " outlives its positional emitter"
				)
				local cue = Audio.cues[event.cueName]
				Harness.expect(cue ~= nil and cue.assetId ~= "", event.id .. " points at a silent cue")
				Harness.expect(cue.rollOffMaxDistance ~= nil, event.id .. " must remain positional")
			end
		end),

		Harness.test("every family answers for every ambient candidate", function()
			-- THE COMPLETENESS RULE, checked from the audio side as well as inside CaveFamilyRules.
			-- `ambientWeightMultiplier` returns a neutral 1 for anything a family did not mention, so an
			-- event authored without being weighted would silently appear in all three caves at full
			-- rate — including in the two it was written to be exclusive of. A newly authored event has
			-- to fail here rather than leak.
			local ids: { string } = { CaveFamilyRules.ambientRockfallId, CaveFamilyRules.ambientWaterDripId }
			for _, event in Feel.ambientCave.soundEvents do
				table.insert(ids, event.id)
			end
			for _, profile in CaveFamilyRules.list() do
				for _, candidateId in ids do
					Harness.expect(
						profile.ambience.candidateWeights[candidateId] ~= nil,
						profile.id .. " never weighted the ambient candidate " .. candidateId
					)
				end
			end
		end),

		Harness.test("the two family-exclusive voices are genuinely different cues", function()
			-- They re-voice existing assets, which is fine and is recorded in Config/Audio — but a
			-- re-voicing that did not actually change the mix would be the same sound under a second
			-- name, and the family would have gained nothing. Each must differ from its source in
			-- playback speed and in how far it carries.
			for _, pair in
				{
					{ voice = "CaveGlacierGroan", source = "CaveStrataStrain" },
					{ voice = "CaveSeepRun", source = "CaveHiddenWater" },
				}
			do
				local voice, source = Audio.cues[pair.voice], Audio.cues[pair.source]
				Harness.expect(voice ~= nil and source ~= nil, pair.voice .. " or its source is missing")
				Harness.expect(
					voice.playbackSpeed ~= source.playbackSpeed,
					pair.voice .. " plays at its source's speed and is the same sound twice"
				)
				Harness.expect(
					voice.rollOffMaxDistance ~= source.rollOffMaxDistance,
					pair.voice .. " carries exactly as far as its source"
				)
				Harness.equal(voice.bus, "Ambience", pair.voice .. " must use the cave ambience bus")
			end
			-- Ice's voice is the long-range one and Moss's the close one. That contrast IS the identity:
			-- a groan down an open hall against water running down a wall a few studs away.
			Harness.expect(
				(Audio.cues.CaveGlacierGroan.rollOffMaxDistance :: number)
					> Audio.cues.CaveSeepRun.rollOffMaxDistance :: number,
				"the glacier groan must carry further than the wall seep"
			)
		end),

		Harness.test("every family's footstep cue is real, quiet, and its own", function()
			-- THE MOST FREQUENT SOUND IN THE GAME. It has to exist (it did not, for a long time), it has
			-- to differ per cave, and above all it has to stay UNDER the layer a player strains to hear:
			-- your own feet masking an approaching crawler would be the audio working against the game.
			local locomotion = Threats.visuals.procedural.locomotionAudio
			-- Measured against the QUIETEST creature on the roster, not an average: the masking risk is
			-- worst for whichever body is hardest to hear, and that is the one a player most needs their
			-- own boots to stay out of the way of.
			local quietestCreatureStep = math.huge
			for _, cueName in locomotion.stepCueNames do
				quietestCreatureStep = math.min(quietestCreatureStep, Audio.cues[cueName].volume)
			end
			local creatureStep = { volume = quietestCreatureStep }
			Harness.near(Feel.footsteps.quietVolume, 0.238, 1e-6)
			Harness.near(Feel.footsteps.loudVolume, 0.595, 1e-6)
			local seen: { [string]: boolean } = {}
			for _, profile in CaveFamilyRules.list() do
				local cueName = CaveFamilyRules.footstepCue(profile.id, false)
				local cue = Audio.cues[cueName]
				Harness.expect(cue ~= nil, profile.id .. " names a footstep cue that does not exist: " .. cueName)
				Harness.expect(cue.assetId ~= "", cueName .. " is a silent no-op")
				Harness.expect(not seen[cueName], "two families share the footstep cue " .. cueName)
				seen[cueName] = true
				Harness.equal(cue.bus, "World", cueName .. " must sit on the world bus, not Focus")
				Harness.expect(
					cue.volume <= creatureStep.volume,
					cueName .. " is louder than a creature's step and would mask one"
				)
				-- A repeated identical footfall becomes a metronome faster than any other sound in a
				-- game, and a metronome is the opposite of dread.
				Harness.expect(
					cue.pitchMinMultiplier < cue.pitchMaxMultiplier,
					cueName .. " has no pitch variation and will read as a loop"
				)
			end

			local water = Audio.cues[CaveFamilyRules.waterFootstepCue]
			Harness.expect(water ~= nil and water.assetId ~= "", "wading must be audible in every cave")
			Harness.equal(water.bus, "World")
		end),

		Harness.test("footsteps are heard by the player and never by the cave", function()
			-- A DESIGN INVARIANT, not an oversight. Config/Sound.emitters is what threats hear; walking
			-- is deliberately absent from it. If footsteps were a noise source, every hearing row would
			-- hold a permanent track on every moving player, standing still would become the dominant
			-- strategy, and the Cave Listener would stop being the price of working a seam.
			for _, profile in CaveFamilyRules.list() do
				local cueName = CaveFamilyRules.footstepCue(profile.id, false)
				Harness.isNil(
					(Sound.emitters :: { [string]: any })[cueName],
					cueName .. " became something the cave can hear"
				)
			end
			Harness.isNil((Sound.emitters :: { [string]: any })[CaveFamilyRules.waterFootstepCue])
		end),

		Harness.test("cave music stays one shared pool across every family", function()
			-- A DELIBERATE DECISION, recorded as a test so it is not quietly reversed. There are only a
			-- handful of cave tracks; split three ways a family would loop one track for a whole descent,
			-- which is worse identity rather than better. Cave character is carried by the layer that
			-- plays constantly (ambience), never by the one that plays for a few minutes every fifteen.
			-- Revisit when there are enough tracks to give each family a real playlist.
			Harness.expect(#Audio.music.caveTrackCues >= 2, "the shared cave playlist must have real variety")
			for _, cueName in Audio.music.caveTrackCues do
				local cue = Audio.cues[cueName]
				Harness.expect(cue ~= nil and cue.assetId ~= "", "cave track " .. cueName .. " is silent")
				-- The underground playlist is the ambience layer as far as a player is concerned, and the
				-- settings menu's AMBIENCE slider is the control they reach for to quiet it. Routing these
				-- to the music bus put them behind the wrong slider.
				Harness.equal(cue.bus, "Ambience", cueName .. " must route to the ambience bus")
				-- The ambience bus trims to 0.45 for the director's rows; these divide it back out so the
				-- move changed their routing and not their level. If either number drifts the descent
				-- silently changes volume, so both are pinned together here.
				Harness.near(cue.volume * Audio.buses.Ambience.volume, 0.352, 1e-3)
			end
			Harness.equal(
				Audio.cues[Audio.music.menuCue].bus,
				"Music",
				"the lobby track is not cave ambience and must leave the MUSIC slider a real job"
			)
		end),
	},
}

return suite

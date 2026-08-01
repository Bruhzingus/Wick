--!strict

local Harness = require(script.Parent.Harness)
local Audio = require(script.Parent.Parent.Config.Audio)
local Feel = require(script.Parent.Parent.Config.Feel)
local Mining = require(script.Parent.Parent.Config.Mining)
local Sound = require(script.Parent.Parent.Config.Sound)
local Threats = require(script.Parent.Parent.Config.Threats)

local REQUIRED_PRODUCTION_CUES = {
	"MineEngage",
	"MineSwing",
	"MineRecover",
	"MineStrikeImpact",
	"MineStrikePerfect",
	"MineStrikeClean",
	"MineStrikeFumble",
	"MineBreak",
	"CaveStrataStrain",
	"CaveFissureBreath",
	"CaveCalciteTick",
	"CaveHiddenWater",
	"CaveGravelCreep",
}

local EXPECTED_CAVE_FAMILIES: { [string]: boolean } = {
	StrataStrain = true,
	FissureBreath = true,
	CalciteTicks = true,
	HiddenWaterPulse = true,
	GravelCreep = true,
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

		Harness.test("cave ambience remains isolated and 25 percent below its authored gain", function()
			Harness.near(Audio.buses.Ambience.volume, 0.75, 1e-6)
			for _, cueName in
				{
					"AmbientRockfall",
					"AmbientWaterDrip",
					"CaveStrataStrain",
					"CaveFissureBreath",
					"CaveCalciteTick",
					"CaveHiddenWater",
					"CaveGravelCreep",
				}
			do
				Harness.equal(Audio.cues[cueName].bus, "Ambience", cueName .. " must use the cave ambience bus")
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
					"MineStrikeFumble",
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
			Harness.equal(Audio.cues.MineStrikeFumble.rollOffMaxDistance, hearing.MineStrikeFumble.radius)
			Harness.equal(Audio.cues.MineBreak.rollOffMaxDistance, hearing.MineBreak.radius)
			Harness.expect(
				Mining.feedback.impactPresentationRange >= hearing.MineBreak.radius,
				"teammate presentation must cover the loudest server-authorized mining event"
			)
		end),

		Harness.test("every creature cue a threat names is real, audible, and correctly placed", function()
			-- A threat's voice is addressed by NAME from Config/Threats, so a typo here is silent
			-- rather than loud: the enemy simply stops making the sound, and nothing errors. These are
			-- the rows a player uses to know something is coming and that it has committed, so they
			-- are worth pinning.
			local procedural = Threats.visuals.procedural
			local attackAudio = procedural.attackAudio
			local locomotion = procedural.locomotionAudio
			local spatial = {
				attackAudio.crawlerCueName,
				attackAudio.drawnCueName,
				attackAudio.ceilingFlyCueName,
				attackAudio.crawlerLungeCueName,
				attackAudio.drawnLungeCueName,
				attackAudio.ceilingFlyLungeCueName,
				procedural.ceilingFlyBuzz.cueName,
				locomotion.stepCueName,
				locomotion.mothWingCueName,
			}
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
			Harness.expect(
				Audio.cues[attackAudio.crawlerLungeCueName].volume < Audio.cues[attackAudio.crawlerCueName].volume,
				"a crawler's wind-up must sit under its arrival"
			)
			-- Locomotion is the layer a player strains to hear. If it ever rises to the attack layer it
			-- stops being information and starts being noise.
			for _, cueName in { locomotion.stepCueName, locomotion.mothWingCueName } do
				Harness.expect(
					Audio.cues[cueName].volume < Audio.cues[attackAudio.drawnCueName].volume,
					cueName .. " must stay well under the attack layer"
				)
				Harness.expect(
					locomotion.audibleDistance >= (Audio.cues[cueName].rollOffMaxDistance :: number),
					cueName .. " is still audible past the distance the client stops spending voices at"
				)
			end
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

		Harness.test("ambient cave families are unique, spatial, and backed by configured cues", function()
			local events = Feel.ambientCave.soundEvents
			Harness.equal(#events, 5, "the cave director must own exactly five requested natural families")
			local seenIds: { [string]: boolean } = {}
			for _, event in events do
				Harness.expect(EXPECTED_CAVE_FAMILIES[event.id] == true, "unexpected cave family " .. event.id)
				Harness.expect(not seenIds[event.id], "duplicate cave family " .. event.id)
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
	},
}

return suite

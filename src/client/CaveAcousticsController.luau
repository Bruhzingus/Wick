--!strict
-- HOW BIG THIS CAVE SOUNDS. Re-voices the mixer's reverb for whichever family the run is in, and puts
-- it back to neutral in the lobby.
--
-- WHY THIS IS WORTH ITS OWN CONTROLLER. Reverb is the strongest "this is a different place" signal
-- available in audio, and it is the only one that colours EVERY sound at once — a creature's step, a
-- pick strike, a falling formation, your own footfall, the ambience director's one-shots. All three
-- families previously shared one acoustic, so a knotted wet Moss warren and an open Ice glacier hall
-- rang identically and the ear had nothing to tell them apart with, however different they looked.
--
-- IT IS A MODIFIER, NOT A REPLACEMENT. Config/Audio authors genuinely different tails per bus
-- (ambience wetter than focus, because a gameplay read must stay legible), and this scales the decay
-- and offsets the wet level so those relationships survive. See CaveFamilyRules.acoustics.
--
-- Presentation only, and local only: nothing here is authoritative, nothing is replicated, and a
-- client that never receives a floor message simply plays the authored mix.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local CaveAcousticsController = {}

local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local player = Players.LocalPlayer

local function applyFamily(familyId: string?)
	local acoustics = CaveFamilyRules.acoustics(familyId)
	AudioCues.setCaveAcoustics(acoustics.decayScale, acoustics.wetOffset)
end

-- The lobby is not a cave and must not inherit one's tail — an Ice reverb surviving the ride back up
-- would make the hub sound like the place the player just escaped.
local function resetToNeutral()
	AudioCues.setCaveAcoustics(1, 0)
end

function CaveAcousticsController.start()
	-- `any` is confined to this untyped RemoteEvent boundary; both fields are validated before use.
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind ~= "floor" or typeof(payload) ~= "table" then
			return
		end
		local declared = payload.familyId
		if type(declared) == "string" and CaveFamilyRules.isValidId(declared) then
			applyFamily(declared)
			return
		end
		-- Older payloads carry only the legacy numeric tier. Translating it here keeps the acoustic
		-- correct rather than silently falling back to Stone's.
		local tierId = tonumber(payload.tierId)
		local fromTier = if tierId ~= nil then CaveFamilyRules.fromLegacyTierId(tierId) else nil
		applyFamily(if fromTier ~= nil then fromTier.id else nil)
	end)

	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
			resetToNeutral()
		end
	end)
end

return CaveAcousticsController

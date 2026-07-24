--!strict
-- ProfileStore-backed player profiles. Studio always uses ProfileStore.Mock so local tests cannot
-- overwrite production data. This remains the single persistence boundary for gameplay systems.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(script.Parent.Parent.Types)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

export type Profile = {
	schemaVersion: number,
	unlockedCaveTier: number,
	currency: number,
	cosmetics: { string },
	runsCompleted: number,
	deepestFloor: number,
	totalWaxDelivered: number,
}

export type PersistenceInterface = {
	initPlayer: (player: Player) -> boolean,
	closePlayer: (playerId: Types.PlayerId) -> (),
	get: (playerId: Types.PlayerId) -> Profile,
	save: (playerId: Types.PlayerId, profile: Profile) -> (),
	isLoaded: (playerId: Types.PlayerId) -> boolean,
}

local DEFAULT_PROFILE: Profile = {
	schemaVersion = 1,
	unlockedCaveTier = 1,
	currency = 0,
	cosmetics = {},
	runsCompleted = 0,
	deepestFloor = 0,
	totalWaxDelivered = 0,
}

local function copyDefault(): Profile
	return {
		schemaVersion = DEFAULT_PROFILE.schemaVersion,
		unlockedCaveTier = DEFAULT_PROFILE.unlockedCaveTier,
		currency = DEFAULT_PROFILE.currency,
		cosmetics = {},
		runsCompleted = DEFAULT_PROFILE.runsCompleted,
		deepestFloor = DEFAULT_PROFILE.deepestFloor,
		totalWaxDelivered = DEFAULT_PROFILE.totalWaxDelivered,
	}
end

local profileStore = ProfileStore.New("WickProfiles_v1", DEFAULT_PROFILE)
if RunService:IsStudio() then
	-- ProfileStore.Mock is deliberately ephemeral and isolated from live DataStore keys.
	profileStore = profileStore.Mock
end

type LoadedProfile = typeof(profileStore:StartSessionAsync(""))

local sessions: { [Types.PlayerId]: LoadedProfile } = {}
local fallbacks: { [Types.PlayerId]: Profile } = {}
local ending: { [Types.PlayerId]: boolean } = {}

local Persistence: PersistenceInterface

Persistence = {
	initPlayer = function(player: Player): boolean
		if sessions[player.UserId] ~= nil then
			return true
		end

		local profile = profileStore:StartSessionAsync(tostring(player.UserId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
		if profile == nil then
			return false
		end

		profile:AddUserId(player.UserId)
		profile:Reconcile()
		profile.Data.schemaVersion = DEFAULT_PROFILE.schemaVersion
		sessions[player.UserId] = profile
		fallbacks[player.UserId] = nil

		profile.OnSessionEnd:Connect(function()
			sessions[player.UserId] = nil
			if not ending[player.UserId] and player.Parent == Players then
				player:Kick("Your profile opened on another server. Please rejoin.")
			end
		end)

		if player.Parent ~= Players then
			ending[player.UserId] = true
			profile:EndSession()
			ending[player.UserId] = nil
			return false
		end
		return true
	end,

	closePlayer = function(playerId: Types.PlayerId)
		local profile = sessions[playerId]
		if profile ~= nil then
			ending[playerId] = true
			profile:EndSession()
			sessions[playerId] = nil
			ending[playerId] = nil
		end
		fallbacks[playerId] = nil
	end,

	get = function(playerId: Types.PlayerId): Profile
		local profile = sessions[playerId]
		if profile ~= nil and profile:IsActive() then
			return profile.Data
		end
		local fallback = fallbacks[playerId]
		if fallback == nil then
			fallback = copyDefault()
			fallbacks[playerId] = fallback
		end
		return fallback
	end,

	save = function(playerId: Types.PlayerId, data: Profile)
		local profile = sessions[playerId]
		if profile ~= nil and profile:IsActive() and profile.Data ~= data then
			profile.Data.schemaVersion = DEFAULT_PROFILE.schemaVersion
			profile.Data.unlockedCaveTier = data.unlockedCaveTier
			profile.Data.currency = data.currency
			profile.Data.cosmetics = table.clone(data.cosmetics)
			profile.Data.runsCompleted = data.runsCompleted
			profile.Data.deepestFloor = data.deepestFloor
			profile.Data.totalWaxDelivered = data.totalWaxDelivered
		end
	end,

	isLoaded = function(playerId: Types.PlayerId): boolean
		local profile = sessions[playerId]
		return profile ~= nil and profile:IsActive()
	end,
}

return Persistence

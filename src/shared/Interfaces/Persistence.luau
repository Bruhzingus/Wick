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

local function copyProfile(source: Profile): Profile
	return {
		schemaVersion = source.schemaVersion,
		unlockedCaveTier = source.unlockedCaveTier,
		currency = source.currency,
		cosmetics = table.clone(source.cosmetics),
		runsCompleted = source.runsCompleted,
		deepestFloor = source.deepestFloor,
		totalWaxDelivered = source.totalWaxDelivered,
	}
end

local function copyDefault(): Profile
	return copyProfile(DEFAULT_PROFILE)
end

-- True if `fallback` still equals a just-created default (i.e. no gameplay mutation ever landed
-- on it). Used only to decide whether a discarded fallback is worth a loud warning.
local function fallbackIsUnmutated(fallback: Profile): boolean
	return fallback.currency == DEFAULT_PROFILE.currency
		and fallback.unlockedCaveTier == DEFAULT_PROFILE.unlockedCaveTier
		and fallback.runsCompleted == DEFAULT_PROFILE.runsCompleted
		and fallback.deepestFloor == DEFAULT_PROFILE.deepestFloor
		and fallback.totalWaxDelivered == DEFAULT_PROFILE.totalWaxDelivered
		and #fallback.cosmetics == 0
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

		-- A caller can only have mutated a fallback if gameplay ran before this session activated,
		-- which the current boot order (initPlayer must succeed before a player joins any party or
		-- run) should make unreachable. Warn instead of silently discarding or blindly overwriting
		-- real loaded progress with a guessed merge.
		local fallback = fallbacks[player.UserId]
		if fallback ~= nil and not fallbackIsUnmutated(fallback) then
			warn(
				string.format(
					"[WICK] Persistence: discarding a mutated fallback profile for user %d;"
						.. " gameplay mutated state before the ProfileStore session activated.",
					player.UserId
				)
			)
		end
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

	-- Returns a defensive copy: callers may freely mutate the result, but nothing is persisted
	-- until it is passed back to `save`. This keeps `save` a real commit point rather than a
	-- no-op that only ever ran against a table it had already been handed by reference.
	get = function(playerId: Types.PlayerId): Profile
		local profile = sessions[playerId]
		if profile ~= nil and profile:IsActive() then
			return copyProfile(profile.Data)
		end
		local fallback = fallbacks[playerId]
		if fallback == nil then
			fallback = copyDefault()
			fallbacks[playerId] = fallback
		end
		return copyProfile(fallback)
	end,

	save = function(playerId: Types.PlayerId, data: Profile)
		local profile = sessions[playerId]
		if profile ~= nil and profile:IsActive() then
			profile.Data.schemaVersion = DEFAULT_PROFILE.schemaVersion
			profile.Data.unlockedCaveTier = data.unlockedCaveTier
			profile.Data.currency = data.currency
			profile.Data.cosmetics = table.clone(data.cosmetics)
			profile.Data.runsCompleted = data.runsCompleted
			profile.Data.deepestFloor = data.deepestFloor
			profile.Data.totalWaxDelivered = data.totalWaxDelivered
		else
			-- No active session yet: persist the mutation into the fallback cache so it is not
			-- lost while ProfileStore is still loading (see the fallback-discard warning above).
			fallbacks[playerId] = copyProfile(data)
		end
	end,

	isLoaded = function(playerId: Types.PlayerId): boolean
		local profile = sessions[playerId]
		return profile ~= nil and profile:IsActive()
	end,
}

return Persistence

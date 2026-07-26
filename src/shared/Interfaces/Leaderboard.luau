--!strict
-- Cross-server standings for the deepest floor ever reached. This is the ONLY cross-server
-- persistence boundary in the prototype: profiles (Interfaces/Persistence) are per-player and
-- session-scoped, so a global ranking cannot be derived from them and needs its own store.
--
-- Deliberately narrow: submit a score, read the top N. No pagination, no time windows, no other
-- metrics. Every call is wrapped — a DataStore outage must degrade the hub's board to a message,
-- never break the lobby or throw into a caller.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

export type LeaderboardEntry = {
	playerId: Types.PlayerId,
	displayName: string,
	depth: number,
}

export type LeaderboardInterface = {
	available: () -> boolean,
	submit: (playerId: Types.PlayerId, depth: number) -> (),
	top: (count: number) -> { LeaderboardEntry }?,
}

-- Studio has no access to live OrderedDataStores unless API access is explicitly enabled, and even
-- then writing there would pollute production standings from local tests — the same reasoning that
-- puts Interfaces/Persistence on ProfileStore.Mock in Studio.
local ENABLED = not RunService:IsStudio()
local STORE_NAME = "WickDeepestFloor_v1"

local store: OrderedDataStore? = nil
if ENABLED then
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	store = if ok then result else nil
end

-- Names are not stored alongside scores (an OrderedDataStore value must be an integer). Resolving
-- a userId to a name is a web call, so results are cached for the server's lifetime.
local nameCache: { [Types.PlayerId]: string } = {}
-- Updated synchronously before the live write begins. This both removes the same-server read race
-- after an extract and gives Studio a session-local board without touching production data.
local localScores: { [Types.PlayerId]: number } = {}

local function displayNameFor(playerId: Types.PlayerId): string
	local cached = nameCache[playerId]
	if cached ~= nil then
		return cached
	end
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		nameCache[playerId] = player.DisplayName
		return player.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(playerId)
	end)
	local name = if ok then result else "Candle " .. tostring(playerId)
	nameCache[playerId] = name
	return name
end

local function mergedEntries(storedEntries: { LeaderboardEntry }, count: number): { LeaderboardEntry }
	local byPlayer: { [Types.PlayerId]: LeaderboardEntry } = {}
	for _, entry in storedEntries do
		byPlayer[entry.playerId] = entry
	end
	for playerId, depth in localScores do
		local existing = byPlayer[playerId]
		if existing == nil or depth > existing.depth then
			byPlayer[playerId] = {
				playerId = playerId,
				displayName = displayNameFor(playerId),
				depth = depth,
			}
		end
	end

	local entries: { LeaderboardEntry } = {}
	for _, entry in byPlayer do
		table.insert(entries, entry)
	end
	table.sort(entries, function(a, b)
		if a.depth == b.depth then
			return a.playerId < b.playerId
		end
		return a.depth > b.depth
	end)
	while #entries > count do
		table.remove(entries)
	end
	return entries
end

local Leaderboard: LeaderboardInterface = {
	available = function()
		return store ~= nil
	end,

	submit = function(playerId, depth)
		if depth <= 0 or depth % 1 ~= 0 then
			return
		end
		local previousLocal = localScores[playerId]
		localScores[playerId] = if previousLocal ~= nil then math.max(previousLocal, depth) else depth

		local activeStore = store
		if activeStore == nil then
			return
		end
		task.spawn(function()
			local ok, message = pcall(function()
				-- UpdateAsync, not SetAsync: two servers can resolve the same player's runs at once,
				-- and a shallower late write must never overwrite a deeper earlier one.
				activeStore:UpdateAsync(tostring(playerId), function(previous: number?)
					if previous ~= nil and previous >= depth then
						return nil -- nil aborts the write; the stored score already wins.
					end
					return depth
				end)
			end)
			if not ok then
				warn(string.format("[WICK] Leaderboard submit failed for %d: %s", playerId, tostring(message)))
			end
		end)
	end,

	top = function(count)
		if count <= 0 then
			return nil
		end
		local activeStore = store
		if activeStore == nil then
			local localEntries = mergedEntries({}, count)
			return if #localEntries > 0 then localEntries else nil
		end
		local ok, result = pcall(function()
			return activeStore:GetSortedAsync(false, count):GetCurrentPage()
		end)
		if not ok then
			warn(string.format("[WICK] Leaderboard read failed: %s", tostring(result)))
			local localEntries = mergedEntries({}, count)
			return if #localEntries > 0 then localEntries else nil
		end

		local storedEntries: { LeaderboardEntry } = {}
		for _, row in result do
			local playerId = tonumber(row.key)
			local depth = tonumber(row.value)
			if playerId ~= nil and depth ~= nil then
				table.insert(storedEntries, {
					playerId = playerId,
					displayName = displayNameFor(playerId),
					depth = depth,
				})
			end
		end
		return mergedEntries(storedEntries, count)
	end,
}

return Leaderboard

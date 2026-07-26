--!strict
-- Paints the hub's deepest-descent board from the cross-server standings. Owns only the refresh
-- cadence and the text layout; the store itself lives behind Interfaces.Leaderboard, and scores are
-- submitted where they are earned (BrazierService on a cash-out, DeathService on a death).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local LeaderboardInterface = require(ReplicatedStorage.Shared.Interfaces.Leaderboard)
local LobbyRoomBuilder = require(script.Parent.LobbyRoomBuilder)

local LeaderboardService = {}

type LeaderboardEntry = LeaderboardInterface.LeaderboardEntry

local nextRefreshAt = 0
local refreshing = false
local refreshQueued = false

local function render(entries: { LeaderboardEntry }?): string
	local room = Config.LobbyRoom
	if entries == nil then
		return if Interfaces.Leaderboard.available()
			then "Standings could not be read. Try again shortly."
			else room.leaderboardUnavailableText
	end
	if #entries == 0 then
		return room.leaderboardEmptyText
	end

	local lines: { string } = {}
	for rank, entry in entries do
		table.insert(lines, string.format("%2d.  %-22s  floor %d", rank, entry.displayName, entry.depth))
	end
	return table.concat(lines, "\n")
end

local function refresh()
	if refreshing then
		refreshQueued = true
		return
	end
	refreshing = true
	task.spawn(function()
		-- GetSortedAsync yields; the label is only touched once the call resolves.
		local entries = Interfaces.Leaderboard.top(Config.LobbyRoom.leaderboardRows)
		local label = LobbyRoomBuilder.leaderboardLabel()
		if label ~= nil then
			label.Text = render(entries)
		end
		refreshing = false
		if refreshQueued then
			refreshQueued = false
			refresh()
		end
	end)
end

function LeaderboardService.init()
	nextRefreshAt = os.clock() + Config.LobbyRoom.leaderboardRefreshSeconds
	refresh()
end

function LeaderboardService.tick()
	local now = os.clock()
	if now < nextRefreshAt then
		return
	end
	nextRefreshAt = now + Config.LobbyRoom.leaderboardRefreshSeconds
	refresh()
end

-- A score earned in this server should be visible when the player returns to its Landing, without
-- waiting for the periodic cross-server poll. Interfaces.Leaderboard overlays the local score
-- immediately, so this refresh cannot race its asynchronous OrderedDataStore write.
function LeaderboardService.requestRefresh()
	nextRefreshAt = os.clock() + Config.LobbyRoom.leaderboardRefreshSeconds
	refresh()
end

return LeaderboardService

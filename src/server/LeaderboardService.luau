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

local function render(entries: { LeaderboardEntry }?)
	local room = Config.LobbyRoom
	local display = LobbyRoomBuilder.leaderboardDisplay()
	if display == nil then
		return
	end
	for _, row in display.rows do
		row.rank.Visible = false
		row.candle.Visible = false
		row.depth.Visible = false
	end
	if entries == nil then
		display.status.Text = if Interfaces.Leaderboard.available()
			then "Standings could not be read. Try again shortly."
			else room.leaderboardUnavailableText
		return
	end
	if #entries == 0 then
		display.status.Text = room.leaderboardEmptyText
		return
	end

	for rank, entry in entries do
		local row = display.rows[rank]
		if row == nil then
			break
		end
		row.rank.Text = string.format("%02d", rank)
		row.candle.Text = entry.displayName
		row.depth.Text = "FLOOR " .. tostring(entry.depth)
		row.rank.TextColor3 = if rank == 1 then Color3.fromRGB(255, 220, 126) else Color3.fromRGB(210, 185, 132)
		row.candle.TextColor3 = Color3.fromRGB(232, 224, 210)
		row.depth.TextColor3 = Color3.fromRGB(232, 224, 210)
		row.rank.Visible = true
		row.candle.Visible = true
		row.depth.Visible = true
	end
	display.status.Text = "INTERACT TO REFRESH  /  AUTO-UPDATES EACH MINUTE"
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
		render(entries)
		refreshing = false
		if refreshQueued then
			refreshQueued = false
			refresh()
		end
	end)
end

function LeaderboardService.init()
	nextRefreshAt = os.clock() + Config.LobbyRoom.leaderboardRefreshSeconds
	local display = LobbyRoomBuilder.leaderboardDisplay()
	if display ~= nil then
		local nextManualRefreshAt = 0
		display.refreshPrompt.Triggered:Connect(function()
			local now = os.clock()
			if now < nextManualRefreshAt then
				return
			end
			nextManualRefreshAt = now + Config.LobbyRoom.leaderboardManualRefreshSeconds
			display.status.Text = "CHECKING THE ARCHIVES..."
			refresh()
		end)
	end
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

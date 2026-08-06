--!strict
-- PHASE 8 — getting a dropped player back into the expedition they dropped from.
--
-- THE PROBLEM THIS SOLVES, stated plainly: a Wick run happens on a RESERVED server. When a player's
-- connection dies and they press Play again, Roblox routes them to a PUBLIC server — a fresh lobby
-- that has never heard of their run, their party, or the bag lying on the floor where they vanished.
-- Without this service, "your cargo is held for you if you come back" is a promise the platform
-- physically cannot keep.
--
-- HOW IT IS MADE POSSIBLE: the only thing that can send a player into one specific reserved server is
-- that server's reservation ACCESS CODE, and Roblox only gives you one if you reserve the server
-- yourself with `TeleportService:ReserveServer`. The old launch path used
-- `TeleportOptions.ShouldReserveServer`, which reserves a server and keeps the code to itself — so
-- PartyLobbyService now reserves explicitly and carries the code along in the teleport data. This
-- service is the other half of that change.
--
-- THE FLOW:
--   1. The party launches. The lobby reserves a server and passes (accessCode, privateServerId) in
--      the teleport data.
--   2. The expedition starts. RunOrchestrator stamps both onto every member's profile, along with a
--      run id and a timestamp.
--   3. A player drops. Their bag lands in the world, locked to them (Interfaces/Remains).
--   4. They rejoin, landing in a public lobby. This service reads their profile, sees a fresh marker
--      pointing at a server that is not this one, and teleports them back.
--   5. They arrive, and the run is still theirs. Their pile is still where they left it and still
--      locked, provided the grace window has not lapsed.
--
-- WHAT IT DELIBERATELY DOES NOT DO: it never restores cargo, currency, or any state from the profile.
-- The profile carries only a POINTER to a running server; all the actual run state stayed in that
-- server's memory the whole time and was never at risk of being duplicated. A rejoin that failed
-- halfway leaves a player in the lobby with an empty bag, which is a disappointment rather than an
-- exploit — and that asymmetry is the entire reason it is built this way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Telemetry = require(script.Parent.Telemetry)
local DevDiagnosticsService = require(script.Parent.DevDiagnosticsService)

local RejoinService = {}

-- How stale a run marker may be before it is treated as wreckage rather than a destination. A run
-- whose server crashed leaves a marker nobody will ever clear, and bouncing a player at a dead
-- reservation forever is worse than dropping them in a lobby. Comfortably longer than the cargo grace
-- window, so the marker never expires while the pile it points at is still claimable.
local MARKER_MAX_AGE_SECONDS = 1800

-- Players this server has already tried to send back, so a failed teleport (or a Roblox retry) cannot
-- put someone in a bounce loop.
local attempted: { [Types.PlayerId]: boolean } = {}

local function clearMarker(playerId: Types.PlayerId)
	local profile = Interfaces.Persistence.get(playerId)
	if profile.activeRunId == nil then
		return
	end
	profile.activeRunServer = nil
	profile.activeRunAccessCode = nil
	profile.activeRunId = nil
	profile.activeRunStartedAt = nil
	Interfaces.Persistence.save(playerId, profile)
end

RejoinService.clearMarker = clearMarker

-- Should this player be sent back into a run, and if so, where? Returns the access code, or nil with
-- a reason. Split out from the teleport itself so the decision is testable and so every rejection
-- path is visible in one place.
local function destinationFor(playerId: Types.PlayerId): (string?, string)
	local profile = Interfaces.Persistence.get(playerId)
	local accessCode = profile.activeRunAccessCode
	local runId = profile.activeRunId
	if accessCode == nil or runId == nil then
		return nil, "NoActiveRun"
	end
	-- Already there. This is the normal case on the reserved server itself: the marker exists because
	-- the run is live, and the player is standing in it.
	if profile.activeRunServer ~= nil and profile.activeRunServer == game.PrivateServerId then
		return nil, "AlreadyInRun"
	end
	local startedAt = profile.activeRunStartedAt
	if startedAt == nil or os.time() - startedAt > MARKER_MAX_AGE_SECONDS then
		-- Wreckage from a server that never got to clean up after itself.
		clearMarker(playerId)
		return nil, "MarkerExpired"
	end
	return accessCode, "Rejoin"
end

RejoinService.destinationFor = destinationFor

-- Called for every arriving player, after their profile has loaded. Returns true if a teleport was
-- dispatched, so the caller can skip putting them through the normal lobby flow.
function RejoinService.tryReturnToRun(player: Player): boolean
	-- Studio has no reserved servers to return to, and bouncing during a local test would just break
	-- the test. The marker is still written and read, so everything except the teleport is exercised.
	if RunService:IsStudio() or game.PlaceId == 0 then
		return false
	end

	-- Rejoin routing starts in a PUBLIC lobby and nowhere else. A reserved expedition server is
	-- already a destination; letting it evaluate an old profile marker can only bounce the player
	-- toward a different reservation. This server-identity check is the authority even if Roblox
	-- omits or delays TeleportData on arrival. PrivateServerOwnerId distinguishes a reserved server
	-- from a player-owned VIP server.
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return false
	end

	-- An arrival that already carries WICK expedition teleport data is at its destination. In
	-- particular, a fresh cave launch must not follow a stale active-run marker back toward an older
	-- reservation: TeleportToPrivateServerAsync yields while Roblox tries that dead destination and
	-- leaves the player bodyless behind the loading screen. Real reconnect arrivals carry the same
	-- flag and are admitted into the live run by PartyLobbyService/RunOrchestrator below this check.
	local teleportData = player:GetJoinData().TeleportData
	if typeof(teleportData) == "table" and teleportData.wickExpedition == true then
		return false
	end
	if attempted[player.UserId] then
		return false
	end

	local accessCode, reason = destinationFor(player.UserId)
	if accessCode == nil then
		return false
	end
	attempted[player.UserId] = true

	local ok, message = pcall(function()
		TeleportService:TeleportToPrivateServerAsync(game.PlaceId, accessCode, { player }, nil, {
			wickExpedition = true,
			wickRejoin = true,
			reservedAccessCode = accessCode,
			devDiagnostics = DevDiagnosticsService.isEnabled(player.UserId),
		})
	end)
	Telemetry.event("run_rejoin", player.UserId, {
		reason = reason,
		ok = ok,
		error = if ok then nil else tostring(message),
	})
	if not ok then
		-- The reservation is gone or unreachable. Clear the marker rather than leaving the player
		-- pointed at a server that will refuse them every time they log in.
		warn(string.format("[WICK] Rejoin teleport failed for user %d: %s", player.UserId, tostring(message)))
		clearMarker(player.UserId)
		return false
	end
	return true
end

-- How long a dropped player has before their pile unlocks for the rest of the party. Exposed so the
-- lobby can tell a returning player whether they were fast enough, rather than letting them walk all
-- the way back down to find out.
function RejoinService.graceSeconds(): number
	return Config.Extraction.disconnectGraceSeconds
end

function RejoinService.clear(playerId: Types.PlayerId)
	attempted[playerId] = nil
end

function RejoinService.init()
	Players.PlayerRemoving:Connect(function(player)
		attempted[player.UserId] = nil
	end)
end

return RejoinService

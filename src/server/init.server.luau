--!strict
-- Server boot: pure wiring. Creates remotes, darkens the world, connects player lifecycle,
-- and drives every service's tick from one Heartbeat in a fixed order. No logic lives here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local EnvironmentSetup = require(script.EnvironmentSetup)
local CharacterService = require(script.CharacterService)
local DialService = require(script.DialService)
local ToolService = require(script.ToolService)
local LootService = require(script.LootService)
local DripTrailService = require(script.DripTrailService)
local NoiseService = require(script.NoiseService)
local MiningService = require(script.MiningService)
local WaxService = require(script.WaxService)
local DripstoneService = require(script.DripstoneService)
local VineService = require(script.VineService)
local TripwireService = require(script.TripwireService)
local DynamiteService = require(script.DynamiteService)
local MossFireService = require(script.MossFireService)
local AshamedLurkerService = require(script.AshamedLurkerService)
local ThreatService = require(script.ThreatService)
local EnemyService = require(script.EnemyService)
local DeathService = require(script.DeathService)
local SpectatorService = require(script.SpectatorService)
local BasinService = require(script.BasinService)
local BrazierService = require(script.BrazierService)
local WallLampService = require(script.WallLampService)
-- DescentLadderService is deliberately absent from this file. It is initialised and ticked by
-- RunOrchestrator, because WHERE in the tick a ride lands is load-bearing: a landing cage may carve
-- a floor, and that has to happen in the same slot the old descent check occupied — before the
-- pending-floor queue drains and before any Terrain clear.
local RunOrchestrator = require(script.RunOrchestrator)
local PartyLobbyService = require(script.PartyLobbyService)
local RejoinService = require(script.RejoinService)
local ShopService = require(script.ShopService)
local ContractWatchService = require(script.ContractWatchService)
local MovementSanityService = require(script.MovementSanityService)
local LobbyRoomBuilder = require(script.LobbyRoomBuilder)
local ElevatorService = require(script.ElevatorService)
local LeaderboardService = require(script.LeaderboardService)
local Telemetry = require(script.Telemetry)
local DevDiagnosticsService = require(script.DevDiagnosticsService)
local DevTestRoomService = require(script.DevTestRoomService)

EnvironmentSetup.apply()
Remotes.get("StateSync") -- forces remote folder creation before any client looks for it
Telemetry.loadingStage("building_landing")
-- IS THIS SERVER THE HUB, OR AN EXPEDITION?
--
-- Both run this same PlaceId, and until now both built the full hub. The distinction matters for
-- exactly one instance: the hub's SpawnLocation, which on an expedition server is the only spawn in
-- the world and therefore where Roblox parks the default camera for an arriving player who has no
-- character yet — which is every arriving expedition member, by design, until floor one is carved.
-- That was the "brief flash back in the lobby" between the loading screen and the cave. See
-- `LobbyRoomBuilder.build`.
--
-- THE SAME SIGNAL `RejoinService` ALREADY USES, deliberately copied rather than invented:
-- `PrivateServerId` is set on reserved AND player-owned VIP servers, and `PrivateServerOwnerId`
-- distinguishes them (zero means Roblox reserved it, which is what an expedition is).
local isReservedExpedition = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
-- Static hub geometry; must exist before any player can join and spawn into it. Still built on an
-- expedition server, which puts bodies back in it when a run resolves — only the spawn pad is skipped.
LobbyRoomBuilder.build(not isReservedExpedition)
Telemetry.loadingStage("starting_services")

CharacterService.init()
DialService.init()
ToolService.init()
MiningService.init()
DynamiteService.init()
SpectatorService.init()
BasinService.init()
AshamedLurkerService.init()
WallLampService.init()
RunOrchestrator.init(function()
	-- Order matters: put the cars back at the top of their shafts and reopen their gates BEFORE
	-- PartyLobbyService puts bodies back in the hub, so nobody is placed next to a sunk car.
	ElevatorService.resetCars()
	PartyLobbyService.returnToLobby()
end)
PartyLobbyService.init(function(tierId: number, memberIds: { number }, countdownAlreadyServed: boolean)
	RunOrchestrator.startFromLobby(tierId, memberIds, countdownAlreadyServed)
end)
-- The shop talks to players through the lobby's own status line, so it is handed a notifier rather
-- than learning how the lobby renders messages.
ShopService.init(function(player: Player, message: string)
	PartyLobbyService.notifyPlayer(player, message)
end, function(status: string?)
	PartyLobbyService.notifyLobbyChanged(status)
end, function(): boolean
	return PartyLobbyService.isLobbyClosed()
end, function(playerId: number): number
	-- The party this player is queuing in, not a server-wide roster: contract minimums are about the
	-- group you are actually going to descend with. Loose in the hub counts as a party of one.
	local party = Interfaces.Party.forPlayer(playerId)
	return if party ~= nil then #party.members else 1
end)
RejoinService.init()
ElevatorService.init(PartyLobbyService)
LeaderboardService.init()
DevDiagnosticsService.init()
DevTestRoomService.init(function(): boolean
	return PartyLobbyService.isLobbyClosed()
end)

-- Everything a joining player goes through, in the one order that is correct.
--
-- THE REJOIN CHECK COMES FIRST, immediately after the profile loads and before any lobby or run
-- state is touched. A player who dropped out of a live expedition is not a lobby arrival — putting
-- them through the lobby flow first would seat them in a party, broadcast them to everyone, and then
-- teleport them away again a frame later.
--
-- THIS FUNCTION IS THE DESCENT'S CRITICAL PATH, which is not obvious from reading it. An expedition
-- server cannot start its run until `beginExpeditionFromTeleport` on the last line runs, and that
-- line is behind `initPlayer` — a ProfileStore session start, which is a DataStore round trip that
-- BLOCKS FOR 5 SECONDS MINIMUM whenever it finds the profile still session-locked by the server the
-- player just teleported out of, then 10 more per retry, stealing the lock at 40 (ProfileStore's own
-- FIRST_LOAD_REPEAT / LOAD_REPEAT_PERIOD / SESSION_STEAL). Every one of those seconds is spent on a
-- loading screen with no body behind it, and none of it is the cave. Hence the timings below: when a
-- descent feels long, `profileMs` is the first number to read.
local function admitPlayer(player: Player)
	local admittedAt = os.clock()
	Telemetry.loadingStage("loading_profile")
	local profileOk = Interfaces.Persistence.initPlayer(player)
	local profileMs = math.round((os.clock() - admittedAt) * 1000)
	if not profileOk then
		Telemetry.event("player_admit", player.UserId, { profileMs = profileMs, outcome = "ProfileFailed" })
		if player.Parent == Players then
			player:Kick("Your profile could not be loaded. Please rejoin.")
		end
		return
	end
	Telemetry.loadingStage("profile_loaded")
	DevDiagnosticsService.onPlayerAdded(player)
	Telemetry.loadingStage("checking_rejoin")
	-- A reserved server is already the expedition destination. Keep rejoin teleporting completely
	-- out of its admission path, even if a future RejoinService change accidentally relaxes its own
	-- identical guard.
	local mayRouteRejoin = game.PrivateServerId == "" or game.PrivateServerOwnerId ~= 0
	if mayRouteRejoin and RejoinService.tryReturnToRun(player) then
		Telemetry.event("player_admit", player.UserId, {
			profileMs = profileMs,
			totalMs = math.round((os.clock() - admittedAt) * 1000),
			outcome = "Rejoined",
		})
		return
	end
	Telemetry.loadingStage("admitting_party")
	PartyLobbyService.onPlayerAdded(player)
	Telemetry.loadingStage("registering_runner")
	RunOrchestrator.onPlayerAdded(player)
	Telemetry.event("player_admit", player.UserId, {
		profileMs = profileMs,
		totalMs = math.round((os.clock() - admittedAt) * 1000),
		outcome = "Admitted",
	})
	Telemetry.loadingStage("beginning_expedition")
	PartyLobbyService.beginExpeditionFromTeleport()
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(admitPlayer, player)
end)
Telemetry.loadingStage("waiting_for_player")
Players.PlayerRemoving:Connect(function(player)
	-- A test candle is a real run rig. Return its isolated state before the ordinary lobby/run
	-- departure paths clear bodies and profiles.
	DevTestRoomService.onPlayerRemoving(player)
	PartyLobbyService.onPlayerRemoving(player)
	RunOrchestrator.onPlayerRemoving(player)
	RejoinService.clear(player.UserId)
	-- Drop any purchase this player had open. `inFlight` keys are set and cleared inside one yield-free
	-- call, so a leak needs an error mid-purchase — but a leaked key would silently refuse their next
	-- attempt at that same node, which is a bug nobody could diagnose from inside the game.
	ShopService.clear(player.UserId)
	DevDiagnosticsService.clear(player.UserId)
	-- Last, and deliberately so: the two calls above still write to this profile (the rejoin pointer,
	-- the run summary), and closing the session first would send those writes into a fallback cache
	-- that is about to be discarded.
	Interfaces.Persistence.closePlayer(player.UserId)
end)
for _, player in Players:GetPlayers() do
	task.spawn(admitPlayer, player)
end

-- Order matters: elevators (lobby tier/ready/start, before any run exists) -> orchestrate
-- (descent/phase) -> movement sanity (correct impossible displacement) -> trails -> tools (expiry)
-- -> mining (abandon swings the world invalidated, BEFORE wax can change the state they read)
-- -> wax (the authoritative tick, incl. hazards and death checks) -> dripstone (shared
-- trigger/impact and partial snuff) -> vines (burn progress reads the same post-suppression light)
-- -> lurkers (read the same post-wax positions and measured speeds) -> noise (expire spent events,
-- so perception below reads a field containing exactly this frame's live sounds and no older ones)
-- -> threats (perceive the post-impact world) -> death timers -> spectators (records the footfalls of
-- the players who are still alive after all of the above, and gives a body to anyone who just stopped
-- being one) -> contract watch (judges the post-death, post-movement positions, so a player killed
-- this frame is never counted as a teammate who wandered off) -> brazier previews.
RunService.Heartbeat:Connect(function(dt: number)
	ElevatorService.tick()
	DevTestRoomService.tick()
	LeaderboardService.tick()
	RunOrchestrator.tick()
	MovementSanityService.tick(dt)
	DripTrailService.tick()
	ToolService.tick()
	-- Brings the boss chamber's spent supply caches back. A no-op on every ordinary floor.
	LootService.tick()
	MiningService.tick()
	-- Fuses burn down BEFORE the wax tick, so a candle caught in its own blast pays for it on the same
	-- tick the blast happened rather than one tick later. Same ordering reason the seam's fuse has.
	DynamiteService.tick()
	WaxService.tick(dt)
	DripstoneService.tick()
	VineService.tick(dt)
	-- BEFORE ThreatService, deliberately. A wire firing on this tick has to have put its victim on the
	-- floor and posted the catch before the Knotwalker's own step reads it, or the creature answers a
	-- fall one tick late — which at its walking speed is the difference between arriving while you are
	-- still down and arriving after you have stood up.
	TripwireService.tick(dt)
	MossFireService.tick(dt)
	AshamedLurkerService.tick(dt)
	NoiseService.tick()
	ThreatService.tick(dt)
	-- Immediately after the existing roster and for the same reasons: the wick-pack bodies read the
	-- same noise field and the same player positions, so stepping them in the same beat keeps every
	-- creature on the floor reacting to one consistent snapshot of the world.
	EnemyService.tick(dt)
	DeathService.tick()
	SpectatorService.tick(dt)
	ContractWatchService.tick(dt)
	BrazierService.tick(dt)
	WallLampService.tick(dt)
	DevDiagnosticsService.tick(dt)
end)

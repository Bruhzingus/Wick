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
local DripTrailService = require(script.DripTrailService)
local NoiseService = require(script.NoiseService)
local MiningService = require(script.MiningService)
local WaxService = require(script.WaxService)
local DripstoneService = require(script.DripstoneService)
local VineService = require(script.VineService)
local EchoGateService = require(script.EchoGateService)
local MossFireService = require(script.MossFireService)
local AshamedLurkerService = require(script.AshamedLurkerService)
local ThreatService = require(script.ThreatService)
local DeathService = require(script.DeathService)
local SpectatorService = require(script.SpectatorService)
local BasinService = require(script.BasinService)
local BrazierService = require(script.BrazierService)
local RunOrchestrator = require(script.RunOrchestrator)
local PartyLobbyService = require(script.PartyLobbyService)
local RejoinService = require(script.RejoinService)
local ShopService = require(script.ShopService)
local SignalBellService = require(script.SignalBellService)
local ContractWatchService = require(script.ContractWatchService)
local MovementSanityService = require(script.MovementSanityService)
local LobbyRoomBuilder = require(script.LobbyRoomBuilder)
local ElevatorService = require(script.ElevatorService)
local LeaderboardService = require(script.LeaderboardService)
local Telemetry = require(script.Telemetry)

EnvironmentSetup.apply()
Remotes.get("StateSync") -- forces remote folder creation before any client looks for it
LobbyRoomBuilder.build() -- static hub geometry; must exist before any player can join and spawn into it

CharacterService.init()
DialService.init()
ToolService.init()
MiningService.init()
SpectatorService.init()
BasinService.init()
AshamedLurkerService.init()
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
end, function(): number
	local party = Interfaces.Party.snapshot()
	return if party ~= nil then #party.members else 1
end)
SignalBellService.init()
RejoinService.init()
ElevatorService.init(PartyLobbyService)
LeaderboardService.init()

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
	local profileOk = Interfaces.Persistence.initPlayer(player)
	local profileMs = math.round((os.clock() - admittedAt) * 1000)
	if not profileOk then
		Telemetry.event("player_admit", player.UserId, { profileMs = profileMs, outcome = "ProfileFailed" })
		if player.Parent == Players then
			player:Kick("Your profile could not be loaded. Please rejoin.")
		end
		return
	end
	if RejoinService.tryReturnToRun(player) then
		Telemetry.event("player_admit", player.UserId, {
			profileMs = profileMs,
			totalMs = math.round((os.clock() - admittedAt) * 1000),
			outcome = "Rejoined",
		})
		return
	end
	PartyLobbyService.onPlayerAdded(player)
	RunOrchestrator.onPlayerAdded(player)
	Telemetry.event("player_admit", player.UserId, {
		profileMs = profileMs,
		totalMs = math.round((os.clock() - admittedAt) * 1000),
		outcome = "Admitted",
	})
	PartyLobbyService.beginExpeditionFromTeleport()
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(admitPlayer, player)
end)
Players.PlayerRemoving:Connect(function(player)
	PartyLobbyService.onPlayerRemoving(player)
	RunOrchestrator.onPlayerRemoving(player)
	RejoinService.clear(player.UserId)
	-- Drop any purchase this player had open. `inFlight` keys are set and cleared inside one yield-free
	-- call, so a leak needs an error mid-purchase — but a leaked key would silently refuse their next
	-- attempt at that same node, which is a bug nobody could diagnose from inside the game.
	ShopService.clear(player.UserId)
	SignalBellService.clear(player.UserId)
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
	LeaderboardService.tick()
	RunOrchestrator.tick()
	MovementSanityService.tick(dt)
	DripTrailService.tick()
	ToolService.tick()
	MiningService.tick()
	WaxService.tick(dt)
	DripstoneService.tick()
	VineService.tick(dt)
	EchoGateService.tick(dt)
	MossFireService.tick(dt)
	AshamedLurkerService.tick(dt)
	NoiseService.tick()
	ThreatService.tick(dt)
	DeathService.tick()
	SpectatorService.tick(dt)
	ContractWatchService.tick(dt)
	BrazierService.tick(dt)
end)

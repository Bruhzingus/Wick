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
local MovementService = require(script.MovementService)
local DialService = require(script.DialService)
local ToolService = require(script.ToolService)
local DripTrailService = require(script.DripTrailService)
local WaxService = require(script.WaxService)
local DripstoneService = require(script.DripstoneService)
local VineService = require(script.VineService)
local ThreatService = require(script.ThreatService)
local DeathService = require(script.DeathService)
local BasinService = require(script.BasinService)
local BrazierService = require(script.BrazierService)
local RunOrchestrator = require(script.RunOrchestrator)
local PartyLobbyService = require(script.PartyLobbyService)
local MovementSanityService = require(script.MovementSanityService)
local LobbyRoomBuilder = require(script.LobbyRoomBuilder)
local ElevatorService = require(script.ElevatorService)
local LeaderboardService = require(script.LeaderboardService)

EnvironmentSetup.apply()
Remotes.get("StateSync") -- forces remote folder creation before any client looks for it
LobbyRoomBuilder.build() -- static hub geometry; must exist before any player can join and spawn into it

CharacterService.init()
MovementService.init()
DialService.init()
ToolService.init()
BasinService.init()
RunOrchestrator.init(function()
	-- Order matters: put the cars back at the top of their shafts and reopen their gates BEFORE
	-- PartyLobbyService puts bodies back in the hub, so nobody is placed next to a sunk car.
	ElevatorService.resetCars()
	PartyLobbyService.returnToLobby()
end)
PartyLobbyService.init(function(tierId: number, memberIds: { number })
	RunOrchestrator.startFromLobby(tierId, memberIds)
end)
ElevatorService.init(PartyLobbyService)
LeaderboardService.init()

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		if not Interfaces.Persistence.initPlayer(player) then
			if player.Parent == Players then
				player:Kick("Your profile could not be loaded. Please rejoin.")
			end
			return
		end
		Interfaces.CaveTiers.refreshUnlocks(player.UserId)
		PartyLobbyService.onPlayerAdded(player)
		RunOrchestrator.onPlayerAdded(player)
		PartyLobbyService.beginExpeditionFromTeleport()
	end)
end)
Players.PlayerRemoving:Connect(function(player)
	PartyLobbyService.onPlayerRemoving(player)
	RunOrchestrator.onPlayerRemoving(player)
	Interfaces.Persistence.closePlayer(player.UserId)
end)
for _, player in Players:GetPlayers() do
	task.spawn(function()
		if Interfaces.Persistence.initPlayer(player) then
			Interfaces.CaveTiers.refreshUnlocks(player.UserId)
			PartyLobbyService.onPlayerAdded(player)
			RunOrchestrator.onPlayerAdded(player)
			PartyLobbyService.beginExpeditionFromTeleport()
		end
	end)
end

-- Order matters: elevators (lobby tier/ready/start, before any run exists) -> orchestrate
-- (descent/phase) -> movement sanity (correct impossible displacement) -> trails -> tools (expiry)
-- -> wax (the authoritative tick, incl. hazards and death checks) -> dripstone (shared
-- trigger/impact and partial snuff) -> vines (burn progress reads the same post-suppression light)
-- -> threats (perceive the post-impact world) -> death timers -> movement ->
-- brazier previews.
RunService.Heartbeat:Connect(function(dt: number)
	ElevatorService.tick()
	LeaderboardService.tick()
	RunOrchestrator.tick()
	MovementSanityService.tick(dt)
	DripTrailService.tick()
	ToolService.tick()
	WaxService.tick(dt)
	DripstoneService.tick()
	VineService.tick(dt)
	ThreatService.tick(dt)
	DeathService.tick()
	BrazierService.tick(dt)
end)

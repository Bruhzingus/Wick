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
local ThreatService = require(script.ThreatService)
local DeathService = require(script.DeathService)
local BasinService = require(script.BasinService)
local BrazierService = require(script.BrazierService)
local RunOrchestrator = require(script.RunOrchestrator)
local PartyLobbyService = require(script.PartyLobbyService)
local MovementSanityService = require(script.MovementSanityService)

EnvironmentSetup.apply()
Remotes.get("StateSync") -- forces remote folder creation before any client looks for it

CharacterService.init()
MovementService.init()
DialService.init()
ToolService.init()
BasinService.init()
RunOrchestrator.init()
PartyLobbyService.init(function(tierId: number, memberIds: { number })
	RunOrchestrator.startFromLobby(tierId, memberIds)
end)

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

-- Order matters: orchestrate (descent/phase) -> trails -> tools (expiry) -> wax (the authoritative
-- tick, incl. hazards and death checks) -> threats (perceive the post-tick world) -> death timers
-- -> movement (slide expiry) -> brazier previews.
RunService.Heartbeat:Connect(function(dt: number)
	RunOrchestrator.tick()
	MovementSanityService.tick(dt)
	DripTrailService.tick()
	ToolService.tick()
	WaxService.tick(dt)
	ThreatService.tick(dt)
	DeathService.tick()
	MovementService.tick()
	BrazierService.tick(dt)
end)

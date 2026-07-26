--!strict
-- Server authority for the brightness dial: accepts a target burn rate, clamps it against config
-- and the player's sacrifice cap, and stores it. The drain/light consequences happen in the tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local RequestGuard = require(script.Parent.RequestGuard)

local DialService = {}

function DialService.init()
	Remotes.get("SetBurnRate").OnServerEvent:Connect(function(player: Player, value: unknown)
		if not RequestGuard.allow(player, "SetBurnRate") or not RequestGuard.finiteNumber(value) then
			return
		end
		local burnRate = value :: number
		local state = PlayerState.get(player.UserId)
		if state == nil or not state.alive or state.finished then
			return
		end
		-- Both ends of the dial are sacrifice-owned: MaxBrightness lowers the ceiling, DialFloor
		-- raises the floor. Config supplies only the defaults those started from.
		state.burnRate = math.clamp(
			burnRate,
			state.modifiers.minBurnRate,
			math.max(state.modifiers.maxBurnRate, state.modifiers.minBurnRate)
		)
	end)
end

return DialService

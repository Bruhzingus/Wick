--!strict
-- Server authority for the brightness dial: accepts a target burn rate, clamps it against config
-- and the player's sacrifice cap, and stores it. The drain/light consequences happen in the tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)

local DialService = {}

function DialService.init()
	Remotes.get("SetBurnRate").OnServerEvent:Connect(function(player: Player, value: unknown)
		if typeof(value) ~= "number" or value ~= value then -- reject non-numbers and NaN
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil or not state.alive or state.finished then
			return
		end
		state.burnRate = math.clamp(value, Config.Light.minBurnRate, state.modifiers.maxBurnRate)
	end)
end

return DialService

--!strict
-- Server authority for the resulting always-run walk-speed decision.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)

local MovementService = {}

-- The one place a player's current speed is decided, from state alone.
local function speedFor(state: Types.PlayerRunState): number
	if not state.alive or state.finished or state.snuffedAt ~= nil then
		return 0
	end
	local speed = Config.Movement.runSpeed
	-- The MoveSpeed sacrifice slows the default run and every slower movement state alike.
	speed *= state.modifiers.moveSpeedMultiplier
	if state.isCupping then
		local multiplier = Config.Tools.Cup.speedMultiplier
		if multiplier ~= nil then
			speed *= multiplier * state.modifiers.cupSpeedMultiplier
		end
	end
	-- A mining swing is a movement commitment, not a freeze: you can always walk out of one (which
	-- cancels it), you simply cannot work a seam and reposition at the same time.
	if state.isSwinging then
		speed *= Config.Mining.deposit.movementSpeedMultiplier
	end
	return speed
end

function MovementService.refresh(playerId: Types.PlayerId)
	local state = PlayerState.get(playerId)
	if state ~= nil then
		CharacterService.setWalkSpeed(playerId, speedFor(state))
	end
end

return MovementService

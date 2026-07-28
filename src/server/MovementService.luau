--!strict
-- Server authority for sprint intent and the resulting walk-speed decision.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local RequestGuard = require(script.Parent.RequestGuard)

local MovementService = {}

-- The one place a player's current speed is decided, from state alone.
local function speedFor(state: Types.PlayerRunState): number
	if not state.alive or state.finished or state.snuffedAt ~= nil then
		return 0
	end
	local sprinting = state.sprinting
	local speed = if sprinting then Config.Movement.runSpeed else Config.Movement.walkSpeed
	-- The MoveSpeed sacrifice slows walking and running alike.
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

local function canAct(state: Types.PlayerRunState): boolean
	return state.alive and not state.finished and state.snuffedAt == nil
end

function MovementService.init()
	Remotes.get("MovementAction").OnServerEvent:Connect(function(player: Player, action: unknown)
		if not RequestGuard.allow(player, "MovementAction") or typeof(action) ~= "string" then
			return
		end
		local state = PlayerState.get(player.UserId)
		if state == nil then
			return
		end
		if not canAct(state) then
			return
		end
		if action == "SprintStart" or action == "SprintEnd" then
			-- The intent is still recorded after the Sprint sacrifice so releasing the key behaves
			-- normally; speedFor is what refuses to honour it.
			state.sprinting = action == "SprintStart"
			MovementService.refresh(player.UserId)
		end
	end)
end

return MovementService

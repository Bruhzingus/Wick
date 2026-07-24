--!strict
-- Server authority for movement actions: validates dodge/slide/sprint requests, charges wax,
-- and owns the walk-speed decision. The client executes only what was approved.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)

local MovementService = {}

-- The one place a player's current speed is decided, from state alone.
local function speedFor(state: Types.PlayerRunState): number
	if not state.alive or state.finished or state.snuffedAt ~= nil then
		return 0
	end
	if state.slidingUntil > os.clock() then
		return Config.Movement.slideSpeed
	end
	local speed = if state.sprinting then Config.Movement.runSpeed else Config.Movement.walkSpeed
	if state.isCupping then
		local multiplier = Config.Tools.Cup.speedMultiplier
		if multiplier ~= nil then
			speed *= multiplier
		end
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

local function chargeAction(state: Types.PlayerRunState, cost: number): boolean
	local scaled = cost * Config.Wax.movementCostMultiplier
	-- Strict `>`: a movement action can never be the thing that burns you out.
	if state.wax.current <= scaled then
		return false
	end
	state.wax.current -= scaled
	return true
end

local function handleDodge(player: Player, state: Types.PlayerRunState, direction: Vector3)
	local now = os.clock()
	if now - state.lastDodgeAt < Config.Movement.dodgeCooldown then
		return
	end
	if not chargeAction(state, Config.Movement.dodgeWaxCost) then
		return
	end
	state.lastDodgeAt = now
	local distance = Config.Movement.dodgeDistance * state.modifiers.dodgeDistanceMultiplier
	Remotes.get("MovementApproved")
		:FireClient(player, "Dodge", direction, Config.Movement.dodgeSpeed, distance / Config.Movement.dodgeSpeed)
end

local function handleSlide(state: Types.PlayerRunState)
	local now = os.clock()
	if not state.modifiers.canSlide then
		return
	end
	if now - state.lastSlideAt < Config.Movement.slideCooldown then
		return
	end
	if not chargeAction(state, Config.Movement.slideWaxCost) then
		return
	end
	state.lastSlideAt = now
	state.slidingUntil = now + Config.Movement.slideDuration
	MovementService.refresh(state.playerId)
end

function MovementService.init()
	Remotes.get("MovementAction").OnServerEvent:Connect(function(player: Player, action: unknown, direction: unknown)
		local state = PlayerState.get(player.UserId)
		if state == nil or not canAct(state) then
			return
		end
		if action == "SprintStart" or action == "SprintEnd" then
			state.sprinting = action == "SprintStart"
			MovementService.refresh(player.UserId)
		elseif action == "Slide" then
			handleSlide(state)
		elseif action == "Dodge" then
			-- Validate the client-supplied direction; a bad vector becomes "dodge forward-less" (rejected).
			if typeof(direction) ~= "Vector3" then
				return
			end
			local flat = Vector3.new(direction.X, 0, direction.Z)
			if flat.Magnitude < 0.01 or flat.X ~= flat.X then -- zero or NaN
				return
			end
			handleDodge(player, state, flat.Unit)
		end
	end)
end

-- Ends slides whose duration has lapsed (restores normal speed).
function MovementService.tick()
	local now = os.clock()
	for playerId, state in PlayerState.all() do
		if state.slidingUntil ~= 0 and now >= state.slidingUntil then
			state.slidingUntil = 0
			MovementService.refresh(playerId)
		end
	end
end

return MovementService

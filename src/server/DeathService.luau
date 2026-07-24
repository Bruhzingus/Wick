--!strict
-- The two death states (DESIGN §7) and relighting. Snuffed: incapacitated, wax remaining,
-- revivable by a lit teammate who personally pays the cost. BurnOut / expired snuff: terminal —
-- the player becomes a wisp. Water's "instant and absolute" kill routes here as a terminal snuff.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local MovementService = require(script.Parent.MovementService)

local DeathService = {}

local relightPrompts: { [Types.PlayerId]: ProximityPrompt } = {}
local wispExpiry: { [Types.PlayerId]: number } = {}

local function removeRelightPrompt(playerId: Types.PlayerId)
	local prompt = relightPrompts[playerId]
	if prompt ~= nil then
		prompt:Destroy()
		relightPrompts[playerId] = nil
	end
end

local function tryRelight(reviver: Player, targetId: Types.PlayerId)
	local reviverState = PlayerState.get(reviver.UserId)
	local targetState = PlayerState.get(targetId)
	if reviverState == nil or targetState == nil then
		return
	end
	if targetState.snuffedAt == nil or not targetState.alive then
		return
	end
	if not reviverState.alive or reviverState.finished or not reviverState.isLit then
		return
	end
	if not reviverState.modifiers.canRelight then
		return
	end
	-- The reviver personally gives a piece of their life — and it can never burn them out.
	if reviverState.wax.current <= Config.Death.relightWaxCost then
		return
	end
	reviverState.wax.current -= Config.Death.relightWaxCost

	targetState.snuffedAt = nil
	targetState.isLit = true
	targetState.unlitByChoice = false
	targetState.litChangedAt = os.clock()
	removeRelightPrompt(targetId)
	MovementService.refresh(targetId)
end

-- Involuntary snuff (draft, snuffer-type threats, …). Revivable — unless this player sacrificed
-- being relit, in which case going out is going out for good.
function DeathService.snuff(playerId: Types.PlayerId)
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished or state.snuffedAt ~= nil then
		return
	end
	if not state.modifiers.canBeRelit then
		DeathService.kill(playerId, "Snuffed")
		return
	end
	local now = os.clock()
	state.isLit = false
	state.unlitByChoice = false
	state.litChangedAt = now
	state.snuffedAt = now
	state.isCupping = false
	MovementService.refresh(playerId)
	CharacterService.applyLight(playerId, 0, 0, false)

	local root = CharacterService.rootPart(playerId)
	if root ~= nil then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Relight"
		prompt.ObjectText = "Snuffed candle"
		prompt.HoldDuration = Config.Death.relightHoldSeconds
		prompt.MaxActivationDistance = Config.Death.relightRange
		prompt.RequiresLineOfSight = false
		prompt.Triggered:Connect(function(reviver: Player)
			if reviver.UserId ~= playerId then -- you cannot relight yourself out of a world-snuff
				tryRelight(reviver, playerId)
			end
		end)
		prompt.Parent = root
		relightPrompts[playerId] = prompt
	end
end

function DeathService.burnOut(playerId: Types.PlayerId)
	DeathService.kill(playerId, "BurnOut")
end

-- Terminal. Deposits remains (stub), reports the result, and swaps the body for a wisp.
function DeathService.kill(playerId: Types.PlayerId, cause: Types.DeathCause)
	local state = PlayerState.get(playerId)
	if state == nil or not state.alive or state.finished then
		return
	end
	local now = os.clock()
	state.alive = false
	state.isLit = false
	state.snuffedAt = nil
	removeRelightPrompt(playerId)

	Interfaces.Remains.deposit({
		playerId = playerId,
		position = state.position,
		wax = state.wax.current * Config.Death.remainsWaxFraction,
	})
	state.wax.current = 0

	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		Remotes.get("RunEvent"):FireClient(player, "results", {
			survived = false,
			deathCause = cause,
			depthReached = state.depth,
			waxDelivered = 0,
			reward = 0,
		})
		CharacterService.spawnWisp(player, state.position)
		wispExpiry[playerId] = now + Config.Run.wisp.lifetimeSeconds
	end
end

-- Expire snuffed states into terminal deaths, and lapsed wisps into stillness.
function DeathService.tick()
	local now = os.clock()
	for playerId, state in PlayerState.all() do
		local snuffedAt = state.snuffedAt
		if snuffedAt ~= nil and state.alive and now - snuffedAt >= Config.Death.snuffStateDuration then
			DeathService.kill(playerId, "Snuffed")
		end
	end
	for playerId, expiresAt in wispExpiry do
		if now >= expiresAt then
			local player = Players:GetPlayerByUserId(playerId)
			if player ~= nil then
				CharacterService.freezeWisp(player)
			end
			wispExpiry[playerId] = nil
		end
	end
end

function DeathService.reset()
	for playerId in relightPrompts do
		removeRelightPrompt(playerId)
	end
	table.clear(wispExpiry)
end

return DeathService

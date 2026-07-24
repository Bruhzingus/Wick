--!strict
-- The Basin (DESIGN §10): one safe room per floor. Offers are PRIVATE per player (public offers
-- are deferred), rolled from the weighted pool, depth-scaled, applied via pure SacrificeRules.
-- One exchange per player per floor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local SacrificeRules = require(ReplicatedStorage.Shared.Logic.SacrificeRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local DripTrailService = require(script.Parent.DripTrailService)

local BasinService = {}

local rng = Random.new()
local prompts: { [number]: ProximityPrompt } = {} -- keyed by depth
local pending: { [Types.PlayerId]: { Types.ResolvedOffer } } = {}

local function takenSet(state: Types.PlayerRunState): { [string]: boolean }
	local taken: { [string]: boolean } = {}
	for _, id in state.sacrifices do
		taken[id] = true
	end
	return taken
end

local function presentOffers(player: Player, state: Types.PlayerRunState)
	if state.basinUsedAtDepth[state.depth] then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = "The Basin has taken from you already." })
		return
	end
	local offers = SacrificeRules.rollOffers(state.modifiers, takenSet(state), state.depth, state.nextBasinPenalty, rng)
	if #offers == 0 then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = "You have nothing left the Basin wants." })
		return
	end
	pending[state.playerId] = offers
	local serialized = {}
	for index, offer in offers do
		serialized[index] = {
			id = offer.def.id,
			displayName = offer.def.displayName,
			toolId = offer.toolId,
			waxGranted = offer.waxGranted,
		}
	end
	Remotes.get("BasinOffers"):FireClient(player, serialized)
end

local function applyChoice(player: Player, index: number)
	local state = PlayerState.get(player.UserId)
	local offers = pending[player.UserId]
	if state == nil or offers == nil then
		return
	end
	local offer = offers[index]
	if offer == nil or not state.alive or state.finished or state.snuffedAt ~= nil then
		return
	end
	if state.basinUsedAtDepth[state.depth] then
		return
	end

	local result = SacrificeRules.apply(state.modifiers, offer)
	state.modifiers = result.modifiers
	-- "Double the next price" halves the NEXT grant; any other choice consumes the penalty.
	state.nextBasinPenalty = if result.doublesNextPrice then 2 else 1
	table.insert(state.sacrifices, offer.def.id)
	state.basinUsedAtDepth[state.depth] = true
	pending[player.UserId] = nil

	state.wax.current = math.min(state.wax.current + offer.waxGranted, state.wax.max)
	-- Live side effects of what was just given up.
	state.burnRate = math.min(state.burnRate, state.modifiers.maxBurnRate)
	if not state.modifiers.hasDripTrail then
		DripTrailService.clear(player.UserId)
	end

	local label = offer.def.displayName .. (if offer.toolId ~= nil then " (" .. offer.toolId .. ")" else "")
	Remotes.get("RunEvent"):FireClient(player, "message", { text = "The Basin accepts: " .. label })
end

function BasinService.registerFloor(depth: number, basinPosition: Vector3, parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "BasinPrompt"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Position = basinPosition + Vector3.new(0, 2, 0)
	anchor.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Offer yourself"
	prompt.ObjectText = "The Basin"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = Config.Floors.geometry.cellSize / 4
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		local state = PlayerState.get(player.UserId)
		if state ~= nil and state.alive and not state.finished and state.snuffedAt == nil and state.depth == depth then
			presentOffers(player, state)
		end
	end)
	prompt.Parent = anchor
	prompts[depth] = prompt
end

function BasinService.init()
	Remotes.get("BasinChoose").OnServerEvent:Connect(function(player: Player, index: unknown)
		if typeof(index) ~= "number" or index ~= index or index % 1 ~= 0 then
			return
		end
		applyChoice(player, index)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player.UserId] = nil
	end)
end

function BasinService.reset()
	table.clear(prompts) -- prompt instances die with the floor models
	table.clear(pending)
end

return BasinService

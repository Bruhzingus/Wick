--!strict
-- The Basin (DESIGN §10): one safe room per floor. Offers are PRIVATE per player (public offers
-- are deferred), rolled from the weighted pool, grant-band-clamped, applied via pure SacrificeRules.
-- One exchange per player per floor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local SacrificeRules = require(ReplicatedStorage.Shared.Logic.SacrificeRules)
local ContractRules = require(ReplicatedStorage.Shared.Logic.ContractRules)
local WaxAccounting = require(ReplicatedStorage.Shared.Logic.WaxAccounting)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
-- Safe direction: ExtractionService requires PlayerState and Telemetry but never this file, so
-- asking it which contract a player signed cannot close a require cycle.
local ExtractionService = require(script.Parent.ExtractionService)
local DripTrailService = require(script.Parent.DripTrailService)
local MovementService = require(script.Parent.MovementService)
local RequestGuard = require(script.Parent.RequestGuard)
local Telemetry = require(script.Parent.Telemetry)

local BasinService = {}

local rng = Random.new()
local prompts: { [number]: ProximityPrompt } = {} -- keyed by depth
local basinPositions: { [number]: Vector3 } = {}
local pending: {
	[Types.PlayerId]: {
		offers: { Types.ResolvedOffer },
		depth: number,
	},
} = {}

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
	-- SEALED BASIN (Config/LampNetwork). The pool is cold for the whole run: it grants nothing and
	-- takes nothing. The room keeps every other job it has — it is still the one safe chamber and it
	-- still holds the descent pad — so this removes the exchange, never the sanctuary or the way down.
	local effect = ContractRules.effectFor(ExtractionService.contractFor(state.playerId))
	if effect.sealsBasin then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = "The wax here is cold. You agreed to that." })
		return
	end
	-- Depth remains an explicit input for deterministic offer resolution, but no longer reduces the
	-- grant: the growing list of permanent sacrifices is the long-run cost.
	local offers = SacrificeRules.rollOffers(
		state.modifiers,
		takenSet(state),
		PlayerState.globalDepth(state),
		state.nextBasinPenalty,
		rng
	)
	if #offers == 0 then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = "You have nothing left the Basin wants." })
		return
	end
	pending[state.playerId] = {
		offers = offers,
		depth = state.depth,
	}
	local serialized = {}
	for index, offer in offers do
		serialized[index] = {
			id = offer.def.id,
			displayName = offer.def.displayName,
			description = offer.def.description,
			toolId = offer.toolId,
			waxGranted = offer.waxGranted,
		}
	end
	Remotes.get("BasinOffers"):FireClient(player, serialized)
end

local function applyChoice(player: Player, index: number)
	local state = PlayerState.get(player.UserId)
	local pendingChoice = pending[player.UserId]
	if state == nil or pendingChoice == nil then
		Remotes.get("RunEvent"):FireClient(player, "basinChoice", {
			accepted = false,
			retryable = false,
			reason = "The offer is no longer waiting. Approach the Basin again.",
		})
		return
	end
	local basinPosition = basinPositions[pendingChoice.depth]
	if state.depth ~= pendingChoice.depth or basinPosition == nil then
		pending[player.UserId] = nil
		Remotes.get("RunEvent"):FireClient(player, "basinChoice", {
			accepted = false,
			retryable = false,
			reason = "That Basin is no longer within reach.",
		})
		return
	end

	-- Validate against the body that exists NOW, not PlayerState.position's last periodic wax sample.
	-- The prompt itself opens from the live character, so using a different, older position for the
	-- follow-up click made an honest choice intermittently disappear when the candle was still moving.
	local livePosition = CharacterService.basePosition(player.UserId)
	if
		livePosition == nil
		or (livePosition - basinPosition).Magnitude
			> Config.Floors.geometry.cellSize / 4 + Config.Basin.positionToleranceStuds
	then
		Remotes.get("RunEvent"):FireClient(player, "basinChoice", {
			accepted = false,
			retryable = true,
			reason = "Move closer to the Basin, then choose again.",
		})
		return
	end
	local offers = pendingChoice.offers
	local offer = offers[index]
	if offer == nil or not state.alive or state.finished or state.snuffedAt ~= nil then
		pending[player.UserId] = nil
		Remotes.get("RunEvent"):FireClient(player, "basinChoice", {
			accepted = false,
			retryable = false,
			reason = "The Basin will not accept that choice now.",
		})
		return
	end
	if state.basinUsedAtDepth[state.depth] then
		pending[player.UserId] = nil
		Remotes.get("RunEvent"):FireClient(player, "basinChoice", {
			accepted = false,
			retryable = false,
			reason = "The Basin has taken from you already.",
		})
		return
	end

	local result = SacrificeRules.apply(state.modifiers, offer)
	state.modifiers = result.modifiers
	-- "Double the next price" halves the NEXT grant; any other choice consumes the penalty.
	state.nextBasinPenalty = if result.doublesNextPrice then 2 else 1
	table.insert(state.sacrifices, offer.def.id)
	state.basinUsedAtDepth[state.depth] = true
	pending[player.UserId] = nil

	-- Live side effects of what was just given up. A shrunken reserve applies before the grant is
	-- credited, so "shrink your reserve" can never hand back wax the candle can no longer hold.
	state.wax.max = Config.Wax.maxWax * state.modifiers.maxWaxMultiplier
	state.wax = WaxAccounting.grant(state.wax, state.waxLedger, offer.waxGranted, "BasinGain")
	state.burnRate = math.clamp(
		state.burnRate,
		state.modifiers.minBurnRate,
		math.max(state.modifiers.maxBurnRate, state.modifiers.minBurnRate)
	)
	if not state.modifiers.hasDripTrail then
		DripTrailService.clear(player.UserId)
	end
	-- Movement changes are read from state every refresh, but the character's WalkSpeed only follows
	-- when something asks for it.
	MovementService.refresh(player.UserId)

	local label = offer.def.displayName .. (if offer.toolId ~= nil then " (" .. offer.toolId .. ")" else "")
	-- The client keeps the private offer screen open until this acknowledgement arrives. A UI close
	-- now means the server committed the sacrifice; a rejected request remains visible and retryable.
	Remotes.get("RunEvent"):FireClient(player, "basinChoice", { accepted = true, retryable = false })
	Remotes.get("RunEvent"):FireClient(player, "message", { text = "The Basin accepts: " .. label })
	Telemetry.event("basin_choice", player.UserId, {
		depth = state.depth,
		sacrifice = offer.def.id,
	})
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
	prompt.HoldDuration = Config.Basin.promptHoldSeconds
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
	basinPositions[depth] = basinPosition
end

function BasinService.init()
	Remotes.get("BasinChoose").OnServerEvent:Connect(function(player: Player, index: unknown)
		if not RequestGuard.allow(player, "BasinChoose") or not RequestGuard.finiteNumber(index) then
			return
		end
		local choiceIndex = index :: number
		if choiceIndex % 1 ~= 0 then
			return
		end
		applyChoice(player, choiceIndex)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player.UserId] = nil
	end)
end

function BasinService.reset()
	table.clear(prompts) -- prompt instances die with the floor models
	table.clear(basinPositions)
	table.clear(pending)
end

return BasinService

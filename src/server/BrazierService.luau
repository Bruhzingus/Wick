--!strict
-- The Brazier (DESIGN §12): individual cash-out with a group multiplier. Shows the player the
-- real arithmetic while they stand at it (deliberate design choice), commits on a held prompt,
-- and pays through the ProfileStore-backed Persistence boundary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local RewardMath = require(ReplicatedStorage.Shared.Logic.RewardMath)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local Telemetry = require(script.Parent.Telemetry)

local BrazierService = {}

type Brazier = { position: Vector3, ignited: BasePart? }

local braziers: { [number]: Brazier } = {} -- keyed by depth
local previewShown: { [Types.PlayerId]: boolean } = {}
local previewAccumulator = 0
local tierRewardMultiplier = 1

-- Other alive, unfinished players standing close enough to share the moment.
local function additionalPlayersAt(depth: number, position: Vector3, excludeId: Types.PlayerId): number
	local count = 0
	for playerId, state in PlayerState.all() do
		if playerId ~= excludeId and state.alive and not state.finished and state.depth == depth then
			if (state.position - position).Magnitude <= Config.Brazier.groupRadius then
				count += 1
			end
		end
	end
	return count
end

local function commit(player: Player, depth: number)
	local state = PlayerState.get(player.UserId)
	local brazier = braziers[depth]
	if state == nil or brazier == nil then
		return
	end
	if not state.alive or state.finished or state.snuffedAt ~= nil or not state.isLit then
		return
	end
	if state.depth ~= depth then
		return
	end
	if
		(state.position - brazier.position).Magnitude
		> Config.Brazier.promptRange + Config.Brazier.positionToleranceStuds
	then
		return
	end

	local additional = additionalPlayersAt(depth, brazier.position, player.UserId)
	local breakdown = RewardMath.compute(state.wax.current, depth, additional, tierRewardMultiplier)

	state.finished = true
	local delivered = state.wax.current
	state.wax.current = 0

	local profile = Interfaces.Persistence.get(player.UserId)
	profile.currency += breakdown.total
	profile.runsCompleted += 1
	profile.deepestFloor = math.max(profile.deepestFloor, depth)
	profile.totalWaxDelivered += delivered
	Interfaces.Persistence.save(player.UserId, profile)
	local unlockedTier = Interfaces.CaveTiers.refreshUnlocks(player.UserId)
	Telemetry.event("brazier_commit", player.UserId, {
		depth = depth,
		reward = breakdown.total,
		tierMultiplier = breakdown.tierMultiplier,
		wax = math.floor(delivered * 1000) / 1000,
	})

	CharacterService.freeze(player.UserId)
	local ignited = brazier.ignited
	if ignited ~= nil then
		ignited.Material = Enum.Material.Neon
		ignited.Color = Color3.fromRGB(255, 170, 60)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 190, 100)
		light.Range = Config.Light.maxRange
		light.Brightness = Config.Light.maxBrightness
		light.Parent = ignited
	end

	Remotes.get("RunEvent"):FireClient(player, "results", {
		survived = true,
		depthReached = depth,
		waxDelivered = delivered,
		depthMultiplier = breakdown.depthMultiplier,
		groupMultiplier = breakdown.groupMultiplier,
		tierMultiplier = breakdown.tierMultiplier,
		reward = breakdown.total,
		unlockedTier = unlockedTier,
	})
end

function BrazierService.setCaveTier(tierId: number)
	local tier = Interfaces.CaveTiers.get(tierId)
	tierRewardMultiplier = if tier ~= nil then tier.rewardMultiplier else 1
end

function BrazierService.registerFloor(depth: number, position: Vector3, parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name = "BrazierBowl"
	anchor.Size = Vector3.new(2, 1, 2)
	anchor.Color = Color3.fromRGB(50, 40, 35)
	anchor.Material = Enum.Material.SmoothPlastic
	anchor.Anchored = true
	anchor.Position = position
	anchor.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Light the Brazier"
	prompt.ObjectText = "End your run"
	prompt.HoldDuration = Config.Brazier.commitHoldSeconds
	prompt.MaxActivationDistance = Config.Brazier.promptRange
	prompt.RequiresLineOfSight = false
	prompt.Triggered:Connect(function(player: Player)
		commit(player, depth)
	end)
	prompt.Parent = anchor

	braziers[depth] = { position = position, ignited = anchor }
end

-- Live arithmetic for anyone standing at their floor's brazier (and a clear when they leave).
function BrazierService.tick(dt: number)
	previewAccumulator += dt
	if previewAccumulator < Config.Brazier.previewUpdateSeconds then
		return
	end
	previewAccumulator = 0

	for playerId, state in PlayerState.all() do
		local player = Players:GetPlayerByUserId(playerId)
		if player == nil then
			continue
		end
		local brazier = braziers[state.depth]
		local near = brazier ~= nil
			and state.alive
			and not state.finished
			and (state.position - brazier.position).Magnitude <= Config.Brazier.promptRange
		if near and brazier ~= nil then
			local additional = additionalPlayersAt(state.depth, brazier.position, playerId)
			local breakdown = RewardMath.compute(state.wax.current, state.depth, additional, tierRewardMultiplier)
			previewShown[playerId] = true
			Remotes.get("RunEvent"):FireClient(player, "brazierPreview", {
				waxDelivered = breakdown.waxDelivered,
				depthMultiplier = breakdown.depthMultiplier,
				groupMultiplier = breakdown.groupMultiplier,
				tierMultiplier = breakdown.tierMultiplier,
				additionalPlayers = additional,
				total = breakdown.total,
			})
		elseif previewShown[playerId] then
			previewShown[playerId] = nil
			Remotes.get("RunEvent"):FireClient(player, "brazierPreviewClear", {})
		end
	end
end

function BrazierService.reset()
	table.clear(braziers) -- anchors die with the floor models
	table.clear(previewShown)
	tierRewardMultiplier = 1
end

return BrazierService

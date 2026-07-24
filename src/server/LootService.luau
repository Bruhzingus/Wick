--!strict
-- Server-authoritative adapter for config-planned in-run loot. Pickups either replace the active
-- wax profile or add free activations consumed by ToolService; there is no parallel inventory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local LootRules = require(ReplicatedStorage.Shared.Logic.LootRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)

local LootService = {}

local activeParts: { BasePart } = {}

local function removePart(part: BasePart)
	for index = #activeParts, 1, -1 do
		if activeParts[index] == part then
			table.remove(activeParts, index)
			break
		end
	end
	part:Destroy()
end

local function collect(player: Player, depth: number, def: Types.LootDef, part: BasePart)
	if part.Parent == nil then
		return
	end
	local state = PlayerState.get(player.UserId)
	if
		state == nil
		or not state.alive
		or state.finished
		or state.snuffedAt ~= nil
		or state.depth ~= depth
		or (state.position - part.Position).Magnitude > Config.Loot.pickupRange
	then
		return
	end

	local applied = LootRules.apply(state.waxTypeId, state.freeToolCharges, def)
	if applied == nil then
		return
	end
	state.waxTypeId = applied.waxTypeId
	state.freeToolCharges = applied.freeToolCharges

	local message: string
	if def.kind == "WaxType" then
		message = "Burn profile changed: " .. def.displayName .. "."
	else
		local freeCharges = math.floor(def.freeCharges or 0)
		message = ("%s: %d free activation%s ready."):format(
			def.displayName,
			freeCharges,
			if freeCharges == 1 then "" else "s"
		)
	end
	Remotes.get("RunEvent"):FireClient(player, "message", { text = message })
	removePart(part)
end

function LootService.spawnFloor(plan: Types.FloorPlan, roomCenters: { Vector3 }, parent: Instance)
	for _, spawn in plan.lootSpawns do
		local def = Config.Loot.definitions[spawn.lootId]
		local roomCenter = roomCenters[spawn.roomIndex]
		if def == nil or roomCenter == nil then
			continue
		end

		local part = Instance.new("Part")
		part.Name = "Loot_" .. def.id
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * Config.Loot.visualSize
		part.Position = roomCenter + spawn.offset + Vector3.new(0, Config.Loot.visualSize / 2, 0)
		part.Color = def.color
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.Parent = parent

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take"
		prompt.ObjectText = def.displayName
		prompt.HoldDuration = Config.Loot.pickupHoldSeconds
		prompt.MaxActivationDistance = Config.Loot.pickupRange
		prompt.RequiresLineOfSight = true
		prompt.Triggered:Connect(function(player: Player)
			collect(player, plan.depth, def, part)
		end)
		prompt.Parent = part

		table.insert(activeParts, part)
	end
end

function LootService.reset()
	for _, part in activeParts do
		part:Destroy()
	end
	table.clear(activeParts)
end

return LootService

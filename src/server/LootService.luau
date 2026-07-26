--!strict
-- Server-authoritative adapter for config-planned in-run loot. Pickups either replace the active
-- wax profile or add free activations consumed by ToolService; there is no parallel inventory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local LootRules = require(ReplicatedStorage.Shared.Logic.LootRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local LootPickup = require(ReplicatedStorage.Shared.NewModelsAndObjects.LootPickup)
local PlayerState = require(script.Parent.PlayerState)

local LootService = {}

type RoomGroundSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
}

type ActivePickup = {
	model: Model,
	root: BasePart,
}

local activePickups: { ActivePickup } = {}

local function removePickup(pickup: ActivePickup)
	for index = #activePickups, 1, -1 do
		if activePickups[index] == pickup then
			table.remove(activePickups, index)
			break
		end
	end
	pickup.model:Destroy()
end

local function collect(player: Player, depth: number, def: Types.LootDef, pickup: ActivePickup)
	if pickup.model.Parent == nil then
		return
	end
	local state = PlayerState.get(player.UserId)
	if
		state == nil
		or not state.alive
		or state.finished
		or state.snuffedAt ~= nil
		or state.depth ~= depth
		or (state.position - pickup.root.Position).Magnitude > Config.Loot.pickupRange
	then
		return
	end

	local applied = LootRules.apply(state.waxTypeId, state.freeToolCharges, state.matchCharges, def)
	if applied == nil then
		return
	end
	state.waxTypeId = applied.waxTypeId
	state.freeToolCharges = applied.freeToolCharges
	state.matchCharges = applied.matchCharges

	local message: string
	if def.kind == "WaxType" then
		message = "Burn profile changed: " .. def.displayName .. "."
	elseif def.kind == "ToolCharge" then
		local freeCharges = math.floor(def.freeCharges or 0)
		message = ("%s: %d free activation%s ready."):format(
			def.displayName,
			freeCharges,
			if freeCharges == 1 then "" else "s"
		)
	else
		message = "Match found: relight yourself after one solo snuff."
	end
	Remotes.get("RunEvent"):FireClient(player, "message", { text = message })
	removePickup(pickup)
end

function LootService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomGroundSurface },
	parent: Instance
)
	for _, spawn in plan.lootSpawns do
		local def = Config.Loot.definitions[spawn.lootId]
		local roomCenter = roomCenters[spawn.roomIndex]
		local roomSurface = roomSurfaces[spawn.roomIndex]
		if def == nil or roomCenter == nil or roomSurface == nil then
			continue
		end

		local spot = roomCenter + spawn.offset
		local surfaceY = roomSurface.center.Y
			+ GroundGeometry.offset(
				roomSurface.groundField,
				spot.X - roomSurface.center.X,
				spot.Z - roomSurface.center.Z
			)
		-- The pure field plans the intended surface, but Terrain is voxelized and cave dressing can
		-- occupy that exact shelf. Resolve the final stand height against the built world so a pickup
		-- never starts inside Terrain or beneath a collidable rock.
		local rayOrigin = Vector3.new(spot.X, roomSurface.center.Y + roomSurface.ceilingHeight - 1, spot.Z)
		local hit = workspace:Raycast(rayOrigin, Vector3.new(0, -roomSurface.ceilingHeight * 2, 0))
		if hit ~= nil then
			surfaceY = hit.Position.Y
		end
		local position = Vector3.new(spot.X, surfaceY, spot.Z)
		local built = LootPickup.build(def, Config.Loot.visualSize, Config.Loot.promptHeight)
		built.model:PivotTo(CFrame.lookAt(position, Vector3.new(roomCenter.X, position.Y, roomCenter.Z)))
		-- The invisible root is intentionally not the base of every pickup silhouette. Lift from the
		-- model's real bounding-box bottom, so each visible object rests just above the sampled ground
		-- regardless of its own local construction (wax cache, charge, or Match).
		local boundsCFrame, boundsSize = built.model:GetBoundingBox()
		local visibleBottomY = boundsCFrame.Position.Y - boundsSize.Y / 2
		local lift = surfaceY + Config.Loot.surfaceClearance - visibleBottomY
		if lift ~= 0 then
			position += Vector3.new(0, lift, 0)
			built.model:PivotTo(CFrame.lookAt(position, Vector3.new(roomCenter.X, position.Y, roomCenter.Z)))
		end
		built.model.Parent = parent
		local pickup: ActivePickup = {
			model = built.model,
			root = built.root,
		}

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Take"
		prompt.ObjectText = def.displayName
		prompt.HoldDuration = Config.Loot.pickupHoldSeconds
		prompt.MaxActivationDistance = Config.Loot.pickupRange
		prompt.RequiresLineOfSight = true
		prompt.Triggered:Connect(function(player: Player)
			collect(player, plan.depth, def, pickup)
		end)
		prompt.Parent = built.promptAttachment

		table.insert(activePickups, pickup)
	end
end

function LootService.reset()
	for _, pickup in activePickups do
		pickup.model:Destroy()
	end
	table.clear(activePickups)
end

return LootService

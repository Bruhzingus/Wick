--!strict
-- Renders session-local remains records into newly built floors, exposes their light to threat
-- perception, and performs atomic server-authoritative recovery through Interfaces/Remains.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Interfaces = require(ReplicatedStorage.Shared.Interfaces)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)

local RemainsService = {}

type ActiveRemains = {
	id: number,
	ownerId: Types.PlayerId,
	depth: number,
	position: Vector3,
	intensity: number,
	range: number,
	part: BasePart,
}

local active: { [number]: ActiveRemains } = {}

local function destroyActive(id: number)
	local remains = active[id]
	if remains ~= nil then
		remains.part:Destroy()
		active[id] = nil
	end
end

local function eligibleRoomIndices(plan: Types.FloorPlan): { number }
	local flooded: { [number]: boolean } = {}
	for _, hazard in plan.hazards do
		if hazard.hazardId == "Water" then
			flooded[hazard.roomIndex] = true
		end
	end

	local indices: { number } = {}
	for index in plan.rooms do
		if index ~= plan.entryRoomIndex and index ~= plan.basinRoomIndex and not flooded[index] then
			table.insert(indices, index)
		end
	end
	if #indices == 0 then
		table.insert(indices, plan.entryRoomIndex)
	end
	return indices
end

-- Old and new plans share a floor plane but not necessarily topology. Choose the nearest safe room
-- in the new layout, then clamp the old local offset away from walls.
local function remapPosition(oldPosition: Vector3, roomCenters: { Vector3 }, roomIndices: { number }): Vector3
	local nearestCenter = roomCenters[roomIndices[1]]
	local nearestDistance = math.huge
	for _, roomIndex in roomIndices do
		local center = roomCenters[roomIndex]
		local delta = Vector3.new(oldPosition.X - center.X, 0, oldPosition.Z - center.Z)
		if delta.Magnitude < nearestDistance then
			nearestDistance = delta.Magnitude
			nearestCenter = center
		end
	end

	local halfExtent = Config.Floors.geometry.cellSize * Config.Remains.placementInset / 2
	local localX = math.clamp(oldPosition.X - nearestCenter.X, -halfExtent, halfExtent)
	local localZ = math.clamp(oldPosition.Z - nearestCenter.Z, -halfExtent, halfExtent)
	return nearestCenter + Vector3.new(localX, Config.Remains.visualThickness / 2, localZ)
end

-- Rest remains on the real cave floor (smooth Terrain or a part) at their remapped spot, rather
-- than the flat room level, so they never float above or sink into the undulating ground.
local function groundedPosition(parent: Instance, position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { parent, workspace.Terrain }
	params.RespectCanCollide = true
	local floorFallback = position.Y - Config.Remains.visualThickness / 2
	local hit = workspace:Raycast(
		Vector3.new(position.X, floorFallback + Config.Remains.groundProbeHeightAbove, position.Z),
		Vector3.new(0, -Config.Remains.groundProbeDepth, 0),
		params
	)
	local surfaceY = if hit ~= nil then hit.Position.Y else floorFallback
	return Vector3.new(position.X, surfaceY + Config.Remains.visualThickness / 2, position.Z)
end

local function collect(player: Player, remains: ActiveRemains)
	if remains.part.Parent == nil then
		return
	end
	local state = PlayerState.get(player.UserId)
	if
		state == nil
		or not state.alive
		or state.finished
		or state.snuffedAt ~= nil
		or state.depth ~= remains.depth
		or (state.position - remains.position).Magnitude > Config.Remains.pickupRange
	then
		return
	end
	if player.UserId == remains.ownerId and not Config.Remains.ownerMayCollect then
		Remotes.get("RunEvent"):FireClient(player, "message", {
			text = "Your own remains cannot relight this candle.",
		})
		return
	end
	if state.wax.current >= state.wax.max then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = "Your candle cannot hold more wax." })
		return
	end

	-- Claim before granting. Only one prompt callback can remove this record, so duplicate recovery
	-- is impossible even if two clients trigger on the same frame.
	local capacity = state.wax.max - state.wax.current
	local record, remainingWax = Interfaces.Remains.claim(remains.id, capacity)
	if record == nil then
		destroyActive(remains.id)
		return
	end
	local recovered = record.wax
	state.wax.current += recovered
	local recoveredPercent = recovered / Config.Wax.maxWax * 100
	Remotes.get("RunEvent"):FireClient(player, "message", {
		text = if remainingWax > 0
			then ("Recovered %.0f%% wax; some remains."):format(recoveredPercent)
			else ("Recovered %.0f%% wax from another candle."):format(recoveredPercent),
	})
	if remainingWax <= 0 then
		destroyActive(remains.id)
	end
end

function RemainsService.spawnFloor(plan: Types.FloorPlan, roomCenters: { Vector3 }, parent: Instance)
	local roomIndices = eligibleRoomIndices(plan)
	for _, record in Interfaces.Remains.listForFloor(plan.depth) do
		if active[record.id] ~= nil then
			continue
		end
		local position = groundedPosition(parent, remapPosition(record.position, roomCenters, roomIndices))

		local part = Instance.new("Part")
		part.Name = "Remains_" .. record.id
		part.Shape = Enum.PartType.Cylinder
		part.Size =
			Vector3.new(Config.Remains.visualThickness, Config.Remains.visualDiameter, Config.Remains.visualDiameter)
		part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		part.Color = Config.Remains.color
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.Parent = parent

		local light = Instance.new("PointLight")
		light.Color = Config.Remains.color
		light.Brightness = Config.Remains.lightIntensity
		light.Range = Config.Remains.lightRange
		light.Parent = part

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Recover"
		prompt.ObjectText = "Candle Remains"
		prompt.HoldDuration = Config.Remains.pickupHoldSeconds
		prompt.MaxActivationDistance = Config.Remains.pickupRange
		prompt.RequiresLineOfSight = true
		prompt.Parent = part

		local runtime: ActiveRemains = {
			id = record.id,
			ownerId = record.playerId,
			depth = plan.depth,
			position = position,
			intensity = Config.Remains.lightIntensity,
			range = Config.Remains.lightRange,
			part = part,
		}
		active[record.id] = runtime
		prompt.Triggered:Connect(function(player: Player)
			collect(player, runtime)
		end)
	end
end

function RemainsService.sources(): { Types.LightSource }
	local sources: { Types.LightSource } = {}
	for _, remains in active do
		table.insert(sources, {
			kind = "Remains" :: Types.LightSourceKind,
			position = remains.position,
			intensity = remains.intensity,
			range = remains.range,
			attractsDrawn = true,
			repelsDarkHunters = true,
			ownerId = nil,
		})
	end
	return sources
end

-- Removes this run's Instances only. Interface storage intentionally survives for the next run.
function RemainsService.reset()
	for _, remains in active do
		remains.part:Destroy()
	end
	table.clear(active)
end

return RemainsService

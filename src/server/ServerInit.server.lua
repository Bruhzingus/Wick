-- ServerInit.server.lua
-- Watches for floors deep enough to host the Stone Warden and spawns one per eligible floor,
-- parented inside that floor's model so the encounter (bowl, relic, dormant pile, active warden)
-- is destroyed automatically when RunOrchestrator tears the floor down or restarts the run.
-- Floor models are procedurally rebuilt every run (see RunOrchestrator.startRun / FloorBuilder),
-- so there is no fixed world position that is safe across floors -- ground is found by
-- raycasting against that floor's own Terrain band instead of trusting a hardcoded CFrame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StoneWardenBehavior = require(script.Parent.StoneWardenSystem.StoneWardenBehavior)

-- "Only spawns after floor 3": floors 1-3 stay Warden-free, he can first appear on floor 4.
local MIN_ELIGIBLE_DEPTH = 4

-- Tracks which floor models already got a Warden so we never double-spawn one. Weak keys let
-- entries fall away on their own once a floor model (and the Warden parented inside it) is
-- destroyed at run teardown/restart -- no manual cleanup bookkeeping needed.
local spawnedFloors = setmetatable({}, { __mode = "k" })

local function floorDepthFromName(name: string): number?
	local depthText = name:match("^Floor_(%d+)$")
	return depthText and tonumber(depthText) or nil
end

-- Finds real ground for this floor by raycasting straight down through its Terrain band, sampling
-- outward in rings from the floor's geometric center so we land inside one of its rooms rather
-- than in open space between them. Returns nil (caller skips the spawn) if nothing solid is found
-- in this floor's Y band -- better to skip a floor than drop the Warden through the map.
local function findGroundPosition(floorModel: Model, depth: number): Vector3?
	local geometry = Config.Floors.geometry
	local floorY = -(depth - 1) * geometry.floorGap
	local topY = floorY + geometry.ceilingMaxHeight + Config.Floors.roof.rockThickness + 5
	local bottomY = floorY - geometry.wallHeight - 10

	local bounds = floorModel:GetBoundingBox()
	local center = bounds.Position

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { workspace.Terrain }

	local samples = { Vector3.new(center.X, 0, center.Z) }
	for _, radius in { geometry.cellSize * 0.5, geometry.cellSize, geometry.cellSize * 1.5, geometry.cellSize * 2 } do
		for i = 1, 8 do
			local angle = (i / 8) * math.pi * 2
			table.insert(samples, Vector3.new(center.X + math.cos(angle) * radius, 0, center.Z + math.sin(angle) * radius))
		end
	end

	for _, xz in samples do
		local origin = Vector3.new(xz.X, topY, xz.Z)
		local result = workspace:Raycast(origin, Vector3.new(0, bottomY - topY, 0), raycastParams)
		if result then
			return result.Position
		end
	end

	return nil
end

local function spawnWardenOnFloor(floorModel: Model, depth: number)
	if spawnedFloors[floorModel] then
		return
	end

	local groundPosition = findGroundPosition(floorModel, depth)
	if groundPosition == nil then
		warn(("StoneWardenSystem: no valid ground found on %s, skipping spawn"):format(floorModel.Name))
		return
	end
	spawnedFloors[floorModel] = true

	local spawnCFrame = CFrame.new(groundPosition)

	-- 1. Create the Relic and Bowl
	local bowl = Instance.new("Part")
	bowl.Size = Vector3.new(4, 1, 4)
	bowl.Position = spawnCFrame.Position - Vector3.new(0, 0, 8)
	bowl.Anchored = true
	bowl.CanCollide = true
	bowl.Color = Color3.fromRGB(30, 30, 30)
	bowl.Material = Enum.Material.Slate
	bowl.Parent = floorModel
	bowl.Name = "StoneWardenBowl"

	local relic = Instance.new("Part")
	relic.Size = Vector3.new(1, 1, 1)
	relic.Position = bowl.Position + Vector3.new(0, 1, 0)
	relic.Anchored = true
	relic.CanCollide = false
	relic.Color = Color3.fromRGB(200, 200, 200)
	relic.Material = Enum.Material.Ice
	relic.Parent = floorModel
	relic.Name = "StoneWardenRelic"

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 220, 255)
	light.Range = 15
	light.Brightness = 2
	light.Parent = relic

	-- 2. Spawn the Stone Warden, parented under this floor so it is cleaned up with it
	StoneWardenBehavior.new(spawnCFrame, relic, floorModel, depth)
end

local function onFloorAdded(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local depth = floorDepthFromName(instance.Name)
	if depth == nil or depth < MIN_ELIGIBLE_DEPTH then
		return
	end
	spawnWardenOnFloor(instance, depth)
end

local function watchFloorsFolder(folder: Instance)
	if not folder:IsA("Folder") then
		return
	end
	folder.ChildAdded:Connect(onFloorAdded)
	for _, child in folder:GetChildren() do
		onFloorAdded(child)
	end
end

-- RunOrchestrator recreates the "WickFloors" folder fresh at the start of every run and destroys
-- it on teardown/restart, so we watch workspace for it rather than assuming it already exists.
workspace.ChildAdded:Connect(function(child)
	if child.Name == "WickFloors" then
		watchFloorsFolder(child)
	end
end)

local existingFloorsFolder = workspace:FindFirstChild("WickFloors")
if existingFloorsFolder ~= nil then
	watchFloorsFolder(existingFloorsFolder)
end

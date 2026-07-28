--!strict
-- Realizes planner-owned Stone Warden encounters on their exact analytic room surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local FloorBuilder = require(script.Parent.FloorBuilder)
local StoneWardenBehavior = require(script.Parent.StoneWardenSystem.StoneWardenBehavior)
local Telemetry = require(script.Parent.Telemetry)

local StoneWardenService = {}

local function surfacePosition(surface: FloorBuilder.RoomSurface, offset: Vector3): Vector3
	return surface.center
		+ Vector3.new(offset.X, GroundGeometry.offset(surface.groundField, offset.X, offset.Z), offset.Z)
end

function StoneWardenService.spawnFloor(
	plan: Types.FloorPlan,
	roomSurfaces: { [number]: FloorBuilder.RoomSurface },
	parent: Instance
): boolean
	local placement = plan.warden
	if placement == nil then
		return false
	end
	local surface = roomSurfaces[placement.roomIndex]
	if surface == nil then
		Telemetry.event("warden_spawn_failed", nil, {
			depth = plan.depth,
			globalDepth = plan.globalDepth,
			reason = "missing_room_surface",
		})
		return false
	end

	local pilePosition = surfacePosition(surface, placement.pileOffset)
	local relicPosition = surfacePosition(surface, placement.relicOffset)

	local bowl = Instance.new("Part")
	bowl.Name = "StoneWardenBowl"
	bowl.Size = Vector3.new(4, 1, 4)
	bowl.Position = relicPosition + Vector3.new(0, 0.5, 0)
	bowl.Anchored = true
	bowl.CanCollide = true
	bowl.Color = Color3.fromRGB(30, 30, 30)
	bowl.Material = Enum.Material.Slate
	bowl.Parent = parent

	local relic = Instance.new("Part")
	relic.Name = "StoneWardenRelic"
	relic.Size = Vector3.one
	relic.Position = relicPosition + Vector3.new(0, 1.5, 0)
	relic.Anchored = true
	relic.CanCollide = false
	relic.Color = Color3.fromRGB(200, 220, 255)
	relic.Material = Enum.Material.Ice
	relic.Parent = parent

	local light = Instance.new("PointLight")
	light.Color = relic.Color
	light.Range = 15
	light.Brightness = 2
	light.Parent = relic

	StoneWardenBehavior.new(CFrame.new(pilePosition), relic, parent, plan.depth)
	Telemetry.event("warden_spawned", nil, {
		depth = plan.depth,
		globalDepth = plan.globalDepth,
		room = placement.roomIndex,
	})
	return true
end

return StoneWardenService

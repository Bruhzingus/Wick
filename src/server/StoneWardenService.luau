--!strict
-- Realizes planner-owned Stone Warden encounters on their exact analytic room surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local FloorBuilder = require(script.Parent.FloorBuilder)
local StoneWardenBehavior = require(script.Parent.StoneWardenSystem.StoneWardenBehavior)
local StoneWardenModel = require(script.Parent.StoneWardenSystem.StoneWardenModel)
local CaveFamilyRules = require(ReplicatedStorage.Shared.Logic.CaveFamilyRules)
local SurfaceProbe = require(script.Parent.SurfaceProbe)
local Telemetry = require(script.Parent.Telemetry)

local StoneWardenService = {}

-- The side of the room cell a wall is on, to the direction pointing from that wall back into the
-- room. This is the Warden's whole orientation: the body faces this way while it sleeps in the rock,
-- steps this way as it emerges, and the relic it is guarding sits this way in front of it.
local WALL_INWARD: { [Types.Direction]: Vector3 } = {
	N = Vector3.new(0, 0, 1),
	S = Vector3.new(0, 0, -1),
	E = Vector3.new(-1, 0, 0),
	W = Vector3.new(1, 0, 0),
}

-- Resolve every encounter fixture before creating the collidable bowl. Terrain remains the only
-- valid floor, so population order cannot make the bowl or another object become the pile's ground.
local function surfacePosition(
	surface: FloorBuilder.RoomSurface,
	offset: Vector3,
	fallbackSlot: number
): SurfaceProbe.ResolveResult
	return SurfaceProbe.resolveRoomPosition(surface, offset, Config.StoneWarden.fixtureFootprint / 2, fallbackSlot)
end

function StoneWardenService.spawnFloor(
	plan: Types.FloorPlan,
	roomSurfaces: { [number]: FloorBuilder.RoomSurface },
	parent: Instance
): (boolean, boolean, boolean)
	local placement = plan.warden
	if placement == nil then
		return false, false, false
	end
	local surface = roomSurfaces[placement.roomIndex]
	if surface == nil then
		Telemetry.event("warden_spawn_failed", nil, {
			depth = plan.depth,
			globalDepth = plan.globalDepth,
			reason = "missing_room_surface",
		})
		return false, false, false
	end

	local pileResolution = surfacePosition(surface, placement.pileOffset, 1)
	local relicResolution = surfacePosition(surface, placement.relicOffset, 2)
	local pilePosition = pileResolution.position
	local relicGround = relicResolution.position

	local bowl = Instance.new("Part")
	bowl.Name = "StoneWardenBowl"
	bowl.Size = Config.StoneWarden.bowlSize
	bowl.Position = relicGround + Vector3.new(0, bowl.Size.Y / 2, 0)
	bowl.Anchored = true
	bowl.CanCollide = true
	bowl.Color = Color3.fromRGB(30, 30, 30)
	bowl.Material = Enum.Material.Slate
	bowl.Parent = parent

	local relic = Instance.new("Part")
	relic.Name = "StoneWardenRelic"
	relic.Size = Config.StoneWarden.relicSize
	relic.Position = relicGround
		+ Vector3.new(0, bowl.Size.Y + Config.StoneWarden.relicSurfaceClearance + relic.Size.Y / 2, 0)
	relic.Anchored = true
	relic.CanCollide = false
	relic.CanQuery = true
	relic.CanTouch = true
	relic.Shape = Enum.PartType.Ball
	relic.Color = Config.StoneWarden.relicColor
	relic.Material = Enum.Material.Ice
	relic.Parent = parent

	local light = Instance.new("PointLight")
	light.Color = relic.Color
	light.Range = Config.StoneWarden.relicLightRange
	light.Brightness = Config.StoneWarden.relicLightBrightness
	light.Parent = relic

	-- Facing out of its wall and into the room. Everything the encounter does directionally is built
	-- from this frame: the dormant outcrop is laid between the wall face and the room, and the body
	-- steps forward along the look vector as it comes out of the stone.
	local facing = WALL_INWARD[placement.wallDirection] or Vector3.new(0, 0, 1)
	-- THE WARDEN IS MADE OF THE CAVE IT GUARDS. Its courses take this family's formation palette and
	-- materials, so a Moss Warden is wet green-grey rock and an Ice Warden is packed glacier — which is
	-- what lets the dormant mass read as part of the wall until the moment it stands up. Stone's own
	-- values are the slate this encounter was authored in, so Stone is unchanged.
	local presentation = CaveFamilyRules.resolve(plan.familyId).presentation
	StoneWardenModel.setPalette(presentation.formationPalette, presentation.formationMaterials)
	StoneWardenBehavior.new(
		CFrame.lookAt(pilePosition, pilePosition + facing),
		relic,
		parent,
		plan.depth,
		CaveFamilyRules.wardenDisplayName(plan.familyId)
	)
	Telemetry.event("warden_spawned", nil, {
		depth = plan.depth,
		globalDepth = plan.globalDepth,
		room = placement.roomIndex,
		pileRelocated = pileResolution.relocated,
		relicRelocated = relicResolution.relocated,
		emergencyPlacement = pileResolution.emergency or relicResolution.emergency,
	})
	return true,
		pileResolution.relocated or relicResolution.relocated,
		pileResolution.emergency or relicResolution.emergency
end

return StoneWardenService

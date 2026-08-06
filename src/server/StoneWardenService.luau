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

local WALL_INWARD: { [Types.Direction]: Vector3 } = {
	N = Vector3.new(0, 0, 1),
	S = Vector3.new(0, 0, -1),
	E = Vector3.new(-1, 0, 0),
	W = Vector3.new(1, 0, 0),
}

local function surfacePosition(
	surface: FloorBuilder.RoomSurface,
	offset: Vector3,
	fallbackSlot: number
): SurfaceProbe.ResolveResult
	return SurfaceProbe.resolveRoomPosition(surface, offset, Config.StoneWarden.fixtureFootprint / 2, fallbackSlot)
end

local function buildWaxFixture(
	ground: Vector3,
	facing: Vector3,
	presentation: CaveFamilyRules.CaveFamilyProfile,
	parent: Instance
): { BasePart }
	local tray = Instance.new("Part")
	tray.Name = "WardenWaxTray"
	tray.Size = Config.StoneWarden.traySize
	tray.Position = ground + Vector3.new(0, tray.Size.Y / 2, 0)
	tray.Anchored = true
	tray.CanCollide = true
	tray.Color = presentation.presentation.formationPalette[1]
	tray.Material = presentation.presentation.formationMaterials[1]
	tray.Parent = parent

	local right = Vector3.new(-facing.Z, 0, facing.X)
	local pieces: { BasePart } = {}
	for index, localOffset in Config.StoneWarden.waxPieceOffsets do
		local piece = Instance.new("Part")
		piece.Name = "WardenWaxPiece" .. tostring(index)
		piece.Size = Config.StoneWarden.waxPieceSize
		piece.Position = ground
			+ right * localOffset.X
			+ facing * localOffset.Z
			+ Vector3.new(0, tray.Size.Y + Config.StoneWarden.waxSurfaceClearance + piece.Size.Y / 2 + localOffset.Y, 0)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = true
		piece.CanTouch = false
		piece.Color = Config.StoneWarden.waxColor
		piece.Material = Enum.Material.SmoothPlastic
		piece.Parent = parent
		table.insert(pieces, piece)
	end
	return pieces
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
	local waxResolution = surfacePosition(surface, placement.waxOffset, 2)
	local pilePosition = pileResolution.position
	local facing = WALL_INWARD[placement.wallDirection] or Vector3.new(0, 0, 1)
	local family = CaveFamilyRules.resolve(plan.familyId)
	local waxPieces = buildWaxFixture(waxResolution.position, facing, family, parent)
	local collapsePositions: { Vector3 } = {}
	for _, offset in placement.collapseDripstoneOffsets do
		table.insert(collapsePositions, surface.center + Vector3.new(offset.X, 0, offset.Z))
	end

	StoneWardenModel.setPalette(family.presentation.formationPalette, family.presentation.formationMaterials)
	StoneWardenBehavior.new(
		CFrame.lookAt(pilePosition, pilePosition + facing),
		waxPieces,
		collapsePositions,
		parent,
		plan.depth,
		CaveFamilyRules.wardenDisplayName(plan.familyId)
	)
	Telemetry.event("warden_spawned", nil, {
		depth = plan.depth,
		globalDepth = plan.globalDepth,
		room = placement.roomIndex,
		pileRelocated = pileResolution.relocated,
		waxRelocated = waxResolution.relocated,
		emergencyPlacement = pileResolution.emergency or waxResolution.emergency,
	})
	return true,
		pileResolution.relocated or waxResolution.relocated,
		pileResolution.emergency or waxResolution.emergency
end

return StoneWardenService

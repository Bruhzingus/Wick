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

export type SpawnEncounterInput = {
	spawnCFrame: CFrame,
	waxGround: Vector3,
	waxNormal: Vector3?,
	collapsePositions: { Vector3 },
	parent: Instance,
	depth: number,
	familyId: string?,
}

export type EncounterHandle = {
	model: Model,
	waxFixture: Model,
	activate: () -> (),
	stun: (seconds: number) -> (),
	isStunned: () -> boolean,
	state: () -> string,
	destroy: () -> (),
}

local floorEncounters: { [number]: { EncounterHandle } } = {}

local WALL_INWARD: { [Types.Direction]: Vector3 } = {
	N = Vector3.new(0, 0, 1),
	S = Vector3.new(0, 0, -1),
	E = Vector3.new(-1, 0, 0),
	W = Vector3.new(1, 0, 0),
}

local function surfacePosition(surface: FloorBuilder.RoomSurface, offset: Vector3): SurfaceProbe.ResolveResult
	return SurfaceProbe.resolvePlannedPosition(surface, offset, Config.StoneWarden.fixtureFootprint / 2)
end

local function buildWaxFixture(
	ground: Vector3,
	facing: Vector3,
	normal: Vector3?,
	presentation: CaveFamilyRules.CaveFamilyProfile,
	parent: Instance
): ({ BasePart }, Model)
	local fixture = Instance.new("Model")
	fixture.Name = "WardenWaxFixture"

	local tray = Instance.new("Part")
	tray.Name = "WardenWaxTray"
	tray.Size = Config.StoneWarden.traySize
	tray.Position = ground + Vector3.new(0, tray.Size.Y / 2, 0)
	tray.Anchored = true
	tray.CanCollide = true
	tray.Color = presentation.presentation.formationPalette[1]
	tray.Material = presentation.presentation.formationMaterials[1]
	tray.Parent = fixture

	local pieces: { BasePart } = {}
	for index, localOffset in Config.StoneWarden.waxPieceOffsets do
		local piece = Instance.new("Part")
		piece.Name = "WardenWaxPiece" .. tostring(index)
		piece.Size = Config.StoneWarden.waxPieceSize
		piece.Position = ground
			+ Vector3.new(
				localOffset.X,
				tray.Size.Y + Config.StoneWarden.waxSurfaceClearance + piece.Size.Y / 2 + localOffset.Y,
				-localOffset.Z
			)
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = true
		piece.CanTouch = false
		piece.Color = Config.StoneWarden.waxColor
		piece.Material = Enum.Material.SmoothPlastic
		piece.Parent = fixture
		table.insert(pieces, piece)
	end
	fixture.PrimaryPart = tray
	SurfaceProbe.seat(fixture, ground, ground + facing, 0, normal)
	fixture.Parent = parent
	return pieces, fixture
end

-- Build one complete encounter from already-resolved server positions. Floor spawning remains the
-- planner-owned path below; this seam lets a bounded developer room own and remove one encounter
-- without fabricating a FloorPlan or reaching into StoneWardenBehavior internals.
function StoneWardenService.spawnEncounter(input: SpawnEncounterInput): EncounterHandle
	local family = CaveFamilyRules.resolve(input.familyId)
	local look = input.spawnCFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local facing = if flatLook.Magnitude > 0.001 then flatLook.Unit else Vector3.new(0, 0, 1)
	local waxPieces, waxFixture = buildWaxFixture(input.waxGround, facing, input.waxNormal, family, input.parent)

	StoneWardenModel.setPalette(family.presentation.formationPalette, family.presentation.formationMaterials)
	-- The rock it is made of was already this cave's; these are the two things about it that were not.
	-- `accents` is what burns inside it (Config/StoneWarden.accents — a creature's own small light,
	-- which is why it lives there rather than under the family's cave-darkness bound), and the dressing
	-- is the growth this cave puts on every body in it — the same seam the crawler, the moth and the
	-- Lurker already grow out of. Stone's dressing is "None" and costs nothing at all.
	StoneWardenModel.setStyle(
		Config.StoneWarden.accents[family.id] or Config.StoneWarden.defaultAccent,
		CaveFamilyRules.creatureDressing(family.id)
	)
	local behavior = StoneWardenBehavior.new(
		input.spawnCFrame,
		waxPieces,
		input.collapsePositions,
		input.parent,
		input.depth,
		CaveFamilyRules.wardenDisplayName(input.familyId)
	)
	local destroyed = false
	return {
		model = behavior.ActiveModel,
		waxFixture = waxFixture,
		activate = function()
			if not destroyed then
				behavior:Activate()
			end
		end,
		stun = function(seconds: number)
			if not destroyed then
				behavior:Stun(seconds)
			end
		end,
		isStunned = function(): boolean
			return not destroyed and behavior:IsStunned()
		end,
		state = function(): string
			return if destroyed then "DESTROYED" else behavior.State
		end,
		destroy = function()
			if destroyed then
				return
			end
			destroyed = true
			behavior:Destroy()
			if waxFixture.Parent ~= nil then
				waxFixture:Destroy()
			end
		end,
	}
end

function StoneWardenService.spawnFloor(
	plan: Types.FloorPlan,
	roomSurfaces: { [number]: FloorBuilder.RoomSurface },
	parent: Instance
): (boolean, boolean, boolean)
	StoneWardenService.clearDepth(plan.depth)
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
		return false, false, true
	end

	local pileResolution = surfacePosition(surface, placement.pileOffset)
	local waxResolution = surfacePosition(surface, placement.waxOffset)
	if pileResolution.failed or waxResolution.failed then
		Telemetry.event("warden_spawn_failed", nil, {
			depth = plan.depth,
			globalDepth = plan.globalDepth,
			reason = if pileResolution.failed then "unsupported_pile" else "unsupported_wax_fixture",
			room = placement.roomIndex,
		})
		return false, false, true
	end
	local pilePosition = pileResolution.position
	local facing = WALL_INWARD[placement.wallDirection] or Vector3.new(0, 0, 1)
	local collapsePositions: { Vector3 } = {}
	for _, offset in placement.collapseDripstoneOffsets do
		table.insert(collapsePositions, surface.center + Vector3.new(offset.X, 0, offset.Z))
	end

	local encounter = StoneWardenService.spawnEncounter({
		spawnCFrame = CFrame.lookAt(pilePosition, pilePosition + facing),
		waxGround = waxResolution.position,
		waxNormal = waxResolution.normal,
		collapsePositions = collapsePositions,
		parent = parent,
		depth = plan.depth,
		familyId = plan.familyId,
	})
	local waxGap = SurfaceProbe.groundGapStuds(encounter.waxFixture)
	if waxGap == nil or math.abs(waxGap) > Config.Floors.geometry.placementProbe.maxSeatedGapStuds then
		-- This visible-bounds audit is intentionally diagnostic: on an asymmetric model it raycasts at
		-- an averaged X/Z, not necessarily the true contact point. The complete nine-point surface proof
		-- above is the hard gate; an approximate audit may not erase a guaranteed encounter.
		Telemetry.event("warden_surface_warning", nil, {
			depth = plan.depth,
			globalDepth = plan.globalDepth,
			room = placement.roomIndex,
			gap = waxGap,
		})
	end
	floorEncounters[plan.depth] = { encounter }
	Telemetry.event("warden_spawned", nil, {
		depth = plan.depth,
		globalDepth = plan.globalDepth,
		room = placement.roomIndex,
		pileRelocated = false,
		waxRelocated = false,
		emergencyPlacement = false,
	})
	return true, false, false
end

-- Production encounters are retained by floor so ignition can remove the creature without
-- destroying the cave geometry around it. Developer-room encounters use `spawnEncounter` directly
-- and remain owned by that session.
function StoneWardenService.clearDepth(depth: number): number
	local encounters = floorEncounters[depth]
	if encounters == nil then
		return 0
	end
	floorEncounters[depth] = nil
	for _, encounter in encounters do
		encounter.destroy()
	end
	return #encounters
end

function StoneWardenService.reset()
	local depths: { number } = {}
	for depth in floorEncounters do
		table.insert(depths, depth)
	end
	for _, depth in depths do
		StoneWardenService.clearDepth(depth)
	end
end

return StoneWardenService

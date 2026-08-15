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
	collapsePositions: { Vector3 },
	parent: Instance,
	depth: number,
	familyId: string?,
}

export type EncounterHandle = {
	model: Model,
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
): ({ BasePart }, BasePart)
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
	return pieces, tray
end

-- Build one complete encounter from already-resolved server positions. Floor spawning remains the
-- planner-owned path below; this seam lets a bounded developer room own and remove one encounter
-- without fabricating a FloorPlan or reaching into StoneWardenBehavior internals.
function StoneWardenService.spawnEncounter(input: SpawnEncounterInput): EncounterHandle
	local family = CaveFamilyRules.resolve(input.familyId)
	local look = input.spawnCFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local facing = if flatLook.Magnitude > 0.001 then flatLook.Unit else Vector3.new(0, 0, 1)
	local waxPieces, tray = buildWaxFixture(input.waxGround, facing, family, input.parent)

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
			if tray.Parent ~= nil then
				tray:Destroy()
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
		return false, false, false
	end

	local pileResolution = surfacePosition(surface, placement.pileOffset, 1)
	local waxResolution = surfacePosition(surface, placement.waxOffset, 2)
	local pilePosition = pileResolution.position
	local facing = WALL_INWARD[placement.wallDirection] or Vector3.new(0, 0, 1)
	local collapsePositions: { Vector3 } = {}
	for _, offset in placement.collapseDripstoneOffsets do
		table.insert(collapsePositions, surface.center + Vector3.new(offset.X, 0, offset.Z))
	end

	local encounter = StoneWardenService.spawnEncounter({
		spawnCFrame = CFrame.lookAt(pilePosition, pilePosition + facing),
		waxGround = waxResolution.position,
		collapsePositions = collapsePositions,
		parent = parent,
		depth = plan.depth,
		familyId = plan.familyId,
	})
	floorEncounters[plan.depth] = { encounter }
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

--!strict
-- Thin Instance adapter for the planned dead candle (Config/DeadCandle, Logic/DeadCandleRules).
--
-- IT SEATS ONE PROP AND NOTHING ELSE. The encounter's reward is ordinary loot and its danger is
-- ordinary threats, both already seated by LootService and ThreatService from the same plan, so this
-- service owns no rule, no prompt, no perception and no per-player state. If it fails, the population
-- step that calls it loses a piece of scenery and the encounter still plays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local GroundGeometry = require(ReplicatedStorage.Shared.Logic.GroundGeometry)
local DeadCandleModel = require(ReplicatedStorage.Shared.NewModelsAndObjects.DeadCandle)
local SurfaceProbe = require(script.Parent.SurfaceProbe)

local DeadCandleService = {}

type RoomGroundSurface = {
	center: Vector3,
	ceilingHeight: number,
	groundField: GroundGeometry.Field,
}

type ActiveBody = {
	model: Model,
	depth: number,
}

local bodies: { ActiveBody } = {}

-- Returns whether a body was built. A floor with no planned dead candle is the common case and is not
-- a failure; the audit line reads the same `false` for both.
function DeadCandleService.spawnFloor(
	plan: Types.FloorPlan,
	roomCenters: { Vector3 },
	roomSurfaces: { [number]: RoomGroundSurface },
	parent: Instance
): boolean
	local placement = plan.deadCandle
	if placement == nil then
		return false
	end
	local roomCenter = roomCenters[placement.roomIndex]
	local roomSurface = roomSurfaces[placement.roomIndex]
	if roomCenter == nil or roomSurface == nil then
		return false
	end

	-- The corpse is the tableau's ANCHOR: the planner validated the loot and the flies against this
	-- exact offset, so it is resolved onto the built Terrain rather than relocated on its own account.
	-- `resolveRoomPosition` only ever moves it toward the room centre when the planned point turns out
	-- to be voxel rock, which keeps it inside the disc the whole encounter was checked against.
	local resolved = SurfaceProbe.resolveRoomPosition(
		roomSurface,
		placement.localOffset,
		Config.DeadCandle.layout.corpseClearance / 2,
		1
	)
	local built = DeadCandleModel.build(placement.visualSeed)
	SurfaceProbe.seat(
		built.model,
		resolved.position,
		roomCenter,
		Config.DeadCandle.body.surfaceClearance,
		resolved.normal
	)
	built.model.Parent = parent
	table.insert(bodies, { model = built.model, depth = plan.depth })
	return true
end

function DeadCandleService.clearDepth(depth: number)
	for index = #bodies, 1, -1 do
		if bodies[index].depth == depth then
			bodies[index].model:Destroy()
			table.remove(bodies, index)
		end
	end
end

function DeadCandleService.reset()
	for _, body in bodies do
		body.model:Destroy()
	end
	table.clear(bodies)
end

return DeadCandleService

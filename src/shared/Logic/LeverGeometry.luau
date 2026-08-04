--!strict
-- Pure geometry for THE DESCENT LEVER (see server/LobbyRoomBuilder.descentLever), split out so the
-- lever's rest pose and its pull-down animation (client/ElevatorController) are computed from the
-- exact same numbers and can never quietly drift apart. Every position here is in the elevator
-- car's own local space — the same "each stage steps back toward the rider, `+X` is into the east
-- wall" scheme LobbyRoomBuilder used before this module existed — so a car built anywhere in the
-- hub gets an identical lever for free, and the client can reconstruct the handle's pose without
-- ever asking the server where it is.

local LeverGeometry = {}

-- The handle's two named poses. `0` stands it straight up; increasing the angle swings it down
-- through horizontal. Exported so the builder (rest pose) and the ride renderer (the pull) share
-- one definition of "up" and "down" and can never disagree about either.
LeverGeometry.REST_ANGLE = math.rad(-35)
LeverGeometry.PULLED_ANGLE = math.rad(110)
-- How long the pull takes once a descent actually starts. Short enough to read as one decisive
-- yank rather than a slow mechanical swing — the gate is already sliding shut by the time it settles.
LeverGeometry.PULL_DURATION = 0.35
-- The one dimension the builder needs to size the shaft part; `handleCFrames` below is built from it.
LeverGeometry.SHAFT_LENGTH = 3

export type Layout = {
	plateOffset: Vector3,
	plateSize: Vector3,
	housingOffset: Vector3,
	housingSize: Vector3,
	bossOffset: Vector3,
	bossSize: Vector3,
	lampOffset: Vector3,
	lampSize: Vector3,
	-- The hinge the handle swings around, in car-local space. `handleCFrames` takes this directly.
	pivotOffset: Vector3,
}

-- EVERY PIECE IS DERIVED FROM THE FACE OF THE ONE BEHIND IT rather than from its own hand-picked
-- offset, so nothing ends up hovering a fraction of a stud off its neighbour. `halfCarWidth` is the
-- only input because every car in the hub is built to the same width
-- (Config.LobbyRoom.elevatorCarWidth), so one layout serves all of them.
function LeverGeometry.layout(halfCarWidth: number): Layout
	local floorY = 0.4 -- top face of the platform: the plane a rider stands on
	local wallX = halfCarWidth - 0.25 -- inner face of the east wall
	local laneZ = 2 -- forward of the gate and clear of the back-wall readout

	local plateDepth, plateHeight = 0.5, 7
	local plateFrontX = wallX - plateDepth

	local housingDepth, housingHeight = 2.4, 2
	local housingFrontX = plateFrontX - housingDepth

	local bossLength = 1.6
	local bossX = housingFrontX - bossLength / 2 + 0.5
	local pivotY = floorY + 2.2 -- waist height: the handle sweeps to shoulder height, not overhead

	return {
		plateOffset = Vector3.new(wallX - plateDepth / 2, floorY + plateHeight / 2, laneZ),
		plateSize = Vector3.new(plateDepth, plateHeight, 5.6),
		housingOffset = Vector3.new(plateFrontX - housingDepth / 2, floorY + housingHeight / 2, laneZ),
		housingSize = Vector3.new(housingDepth, housingHeight, 3.4),
		bossOffset = Vector3.new(bossX, pivotY, laneZ),
		bossSize = Vector3.new(bossLength, 1.8, 1.8),
		lampOffset = Vector3.new(housingFrontX, floorY + housingHeight / 2, laneZ + 1),
		lampSize = Vector3.new(0.5, 1.2, 1.2),
		pivotOffset = Vector3.new(bossX, pivotY, laneZ),
	}
end

-- The shaft and knob's car-local CFrames with the handle raked to `angle` radians around
-- `pivotOffset`. From the pivot: rake to `angle`, run out the shaft along that raked axis, then
-- turn the cylinder onto its length — composing it this way means the angle is the only number
-- either pose (or a frame mid-animation) ever has to touch.
function LeverGeometry.handleCFrames(pivotOffset: Vector3, angle: number): (CFrame, CFrame)
	local pivotFrame = CFrame.new(pivotOffset) * CFrame.Angles(angle, 0, 0)
	local shaft = pivotFrame * CFrame.new(0, LeverGeometry.SHAFT_LENGTH / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	local knob = pivotFrame * CFrame.new(0, LeverGeometry.SHAFT_LENGTH, 0)
	return shaft, knob
end

return LeverGeometry

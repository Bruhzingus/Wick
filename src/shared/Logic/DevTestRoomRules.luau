--!strict
-- Pure trust-boundary checks for the developer test-room doorway. The PIN is only a convenience
-- gate; proximity and the server-owned session are the actual authority.

local DevTestRoomRules = {}

function DevTestRoomRules.isRemoteAction(action: unknown): boolean
	return action == "sync" or action == "enter"
end

function DevTestRoomRules.isValidCode(value: unknown, expected: string): boolean
	return typeof(value) == "string" and #value <= 16 and value == expected
end

function DevTestRoomRules.isWithinRange(position: Vector3?, target: Vector3, maximumDistance: number): boolean
	if position == nil or maximumDistance < 0 then
		return false
	end
	return (position - target).Magnitude <= maximumDistance
end

function DevTestRoomRules.isInsideRoom(
	position: Vector3?,
	floorCenter: Vector3,
	interiorSize: Vector3,
	margin: number
): boolean
	if position == nil or margin < 0 or interiorSize.X < 0 or interiorSize.Y < 0 or interiorSize.Z < 0 then
		return false
	end
	local offset = position - floorCenter
	return math.abs(offset.X) <= interiorSize.X / 2 + margin
		and offset.Y >= -margin
		and offset.Y <= interiorSize.Y + margin
		and math.abs(offset.Z) <= interiorSize.Z / 2 + margin
end

return DevTestRoomRules

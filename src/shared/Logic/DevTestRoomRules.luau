--!strict
-- Pure trust-boundary checks for the developer test-room doorway. The PIN is only a convenience
-- gate; proximity and the server-owned session are the actual authority.

local DevTestRoomRules = {}

-- `clear` is the REMOVE ALL hotkey. It is a remote action rather than a board prompt because the whole
-- point of it is not having to walk back to the wall to use it — a tester buried in grubs needs the
-- room emptied from where they are standing. The trust boundary is unchanged: the service still
-- requires a live laboratory session for the caller, and clearing only ever touches the lab's own
-- virtual depth, so this can do nothing to a real run whoever sends it.
-- `sprint` is the held super-sprint key, and it is a remote action for the same reason `clear` is:
-- there is no button to walk to, and the whole value of it is not having to. It carries a boolean
-- payload rather than toggling, so a dropped key-up cannot leave a player fast forever — the service
-- also drops it on every session close.
function DevTestRoomRules.isRemoteAction(action: unknown): boolean
	return action == "sync" or action == "enter" or action == "clear" or action == "sprint"
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

export type RoomBox = {
	center: Vector3,
	size: Vector3,
}

-- THE LABORATORY IS MORE THAN ONE ROOM NOW. A tester walks a corridor to the boss arena and stands in
-- it for the length of a fight, and a containment check that only knew the main chamber read every one
-- of those as "your candle left the test chamber" and closed the lab under them.
--
-- An OR of boxes rather than one bounding box around the lot: the union of the two rooms and the
-- corridor is an L, and the rectangle around an L contains a large volume that is outside every wall.
function DevTestRoomRules.isInsideAnyRoom(position: Vector3?, boxes: { RoomBox }, margin: number): boolean
	for _, box in boxes do
		if DevTestRoomRules.isInsideRoom(position, box.center, box.size, margin) then
			return true
		end
	end
	return false
end

return DevTestRoomRules

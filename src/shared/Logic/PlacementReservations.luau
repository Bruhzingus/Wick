--!strict
-- Pure circular footprint reservations shared by the planner and cave decorator. These are
-- deliberately simple XZ discs: gameplay objects need conservative empty space, not exact meshes.

export type Reservation = {
	roomIndex: number,
	offset: Vector3,
	radius: number,
	kind: string,
}

local PlacementReservations = {}

function PlacementReservations.overlaps(
	reservations: { Reservation },
	roomIndex: number,
	offset: Vector3,
	radius: number,
	padding: number?
): boolean
	for _, reservation in reservations do
		if reservation.roomIndex ~= roomIndex then
			continue
		end
		local dx = reservation.offset.X - offset.X
		local dz = reservation.offset.Z - offset.Z
		local clearance = reservation.radius + radius + (padding or 0)
		if dx * dx + dz * dz < clearance * clearance then
			return true
		end
	end
	return false
end

function PlacementReservations.add(
	reservations: { Reservation },
	roomIndex: number,
	offset: Vector3,
	radius: number,
	kind: string
)
	table.insert(reservations, {
		roomIndex = roomIndex,
		offset = offset,
		radius = radius,
		kind = kind,
	})
end

return PlacementReservations

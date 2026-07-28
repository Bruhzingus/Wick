--!strict

local Harness = require(script.Parent.Harness)
local PlacementReservations = require(script.Parent.Parent.Logic.PlacementReservations)

local suite: Harness.Suite = {
	name = "PlacementReservations",
	tests = {
		Harness.test("overlap uses room-scoped XZ radii and optional padding", function()
			local reservations: { PlacementReservations.Reservation } = {}
			PlacementReservations.add(reservations, 2, Vector3.new(4, 99, -3), 3, "Loot")

			Harness.expect(PlacementReservations.overlaps(reservations, 2, Vector3.new(8.9, 0, -3), 2))
			Harness.expect(not PlacementReservations.overlaps(reservations, 1, Vector3.new(4, 0, -3), 50))
			Harness.expect(not PlacementReservations.overlaps(reservations, 2, Vector3.new(10, 0, -3), 2))
			Harness.expect(PlacementReservations.overlaps(reservations, 2, Vector3.new(10, 0, -3), 2, 1.1))
		end),
	},
}

return suite

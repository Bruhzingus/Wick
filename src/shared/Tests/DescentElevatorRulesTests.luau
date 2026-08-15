--!strict

local Rules = require(script.Parent.Parent.Logic.DescentElevatorRules)
local Harness = require(script.Parent.Harness)

return {
	name = "DescentElevatorRules",
	tests = {
		Harness.test("timeline orders landing, ejection, and return", function()
			local timeline = Rules.timeline(10, 4, 2.5, 1, 3, 8)
			Harness.equal(timeline.landsAt, 14)
			Harness.equal(timeline.pushesAt, 16.5)
			Harness.equal(timeline.returnsAt, 17.5)
			Harness.equal(timeline.parksAt, 20.5)
		end),
		-- The gate may shut at `returnsAt` only once the deck is clear; `holdsUntil` is how long past
		-- that it will wait for a rider who is still aboard before ejecting them. A gate that closed on
		-- `returnsAt` regardless is a gate that closes through somebody walking out of it.
		Harness.test("hold deadline sits past the earliest return", function()
			local timeline = Rules.timeline(10, 4, 2.5, 1, 3, 8)
			Harness.equal(timeline.holdsUntil, 25.5)
			Harness.expect(timeline.holdsUntil > timeline.returnsAt)
		end),
		Harness.test("no hold allowance collapses onto the earliest return", function()
			local timeline = Rules.timeline(0, 0, 0, 0, 3, 0)
			Harness.equal(timeline.holdsUntil, timeline.returnsAt)
		end),
		Harness.test("negative hold allowance cannot pull the deadline before the return", function()
			local timeline = Rules.timeline(10, 4, 2.5, 1, 3, -5)
			Harness.equal(timeline.holdsUntil, timeline.returnsAt)
		end),
		Harness.test("ride ease inverts exactly across the curve", function()
			for _, progress in { 0, 0.13, 0.25, 0.5, 0.75, 0.9, 1 } do
				Harness.near(Rules.rideEaseInverse(Rules.rideEase(progress)), progress, 1e-9)
			end
		end),
		-- THE POINT OF THE WHOLE MECHANISM: the hatch may not be thrown until the cage has actually
		-- fallen its own clearance. Assert the distance, not the time — a hatch timed off anything but
		-- the ride curve is a slab drawn through the cage and its riders.
		Harness.test("hatch waits until the cage has fallen clear of the mouth", function()
			local distance, duration, clearance = 96, 4, 8.3
			local closesAt = Rules.hatchClosesAt(100, duration, clearance, distance)
			local fallen = Rules.rideEase((closesAt - 100) / duration) * distance
			Harness.near(fallen, clearance, 1e-6)
			Harness.expect(closesAt > 100 and closesAt < 100 + duration)
		end),
		Harness.test("hatch reopens before the returning cage reaches the mouth", function()
			local distance, duration, clearance = 96, 3, 8.3
			local opensAt = Rules.hatchOpensAt(50, duration, clearance, distance)
			-- The return leg runs the curve backwards, so this is how far BELOW the mouth the cage is.
			local remaining = (1 - Rules.rideEase((opensAt - 50) / duration)) * distance
			Harness.near(remaining, clearance, 1e-6)
			Harness.expect(opensAt > 50 and opensAt < 50 + duration)
		end),
		Harness.test("a cage taller than its own ride covers the mouth only once landed", function()
			Harness.equal(Rules.hatchClosesAt(0, 4, 200, 96), 4)
		end),
		Harness.test("a shaft with no depth never strands the hatch open", function()
			Harness.equal(Rules.hatchClosesAt(7, 4, 8.3, 0), 11)
		end),
		Harness.test("deck test follows the cage frame", function()
			local pivot = CFrame.new(8, -96, 12) * CFrame.Angles(0, math.rad(90), 0)
			Harness.expect(Rules.isOnDeck(pivot, pivot.Position + pivot.RightVector, 5.2, 5.2, 2))
			Harness.expect(not Rules.isOnDeck(pivot, pivot.Position + pivot.RightVector * 4, 5.2, 5.2, 2))
		end),
		Harness.test("forced exit is outward and keeps rider spacing", function()
			local pivot = CFrame.new(3, -20, 7)
			local exit = Rules.exitPosition(pivot, 1.2, 5)
			Harness.vectorNear(exit, Vector3.new(4.2, -20, 2))
		end),
	},
}

--!strict
-- The Knotwalker's trap, tested as the three promises it makes to a player:
--   1. A hop clears it.
--   2. Running into it is worse than walking into it, everywhere in the band — never just at the ends.
--   3. A fast runner cannot pass through it between two server ticks.
--
-- The third is the one that needed a test written for it rather than a comment: it is invisible in
-- play (nothing happens, which is also what a working dodge looks like) and it is the single reason
-- the trip test is a swept segment instead of a radius.

local Harness = require(script.Parent.Harness)
local TripwireRules = require(script.Parent.Parent.Logic.TripwireRules)
local TripwireConfig = require(script.Parent.Parent.Config.Tripwire)
local MovementConfig = require(script.Parent.Parent.Config.Movement)

-- A wire strung along the X axis at the origin, ankle high. Players below cross it walking in Z.
local WIRE_Y = TripwireConfig.geometry.heightStuds
local ANCHOR_A = Vector3.new(-5, WIRE_Y, 0)
local ANCHOR_B = Vector3.new(5, WIRE_Y, 0)

local function query(previous: Vector3, current: Vector3, speed: number, airborne: boolean)
	return {
		previousFoot = previous,
		currentFoot = current,
		anchorA = ANCHOR_A,
		anchorB = ANCHOR_B,
		speed = speed,
		airborne = airborne,
	}
end

return {
	name = "TripwireRules",
	tests = {
		Harness.test("running through the wire trips it", function()
			local tripped = TripwireRules.trips(query(Vector3.new(0, 0, -2), Vector3.new(0, 0, 2), 16, false))
			Harness.equal(tripped, true, "a step across the strand is a trip")
		end),

		Harness.test("a step that never reaches the wire does not trip it", function()
			local tripped = TripwireRules.trips(query(Vector3.new(0, 0, -6), Vector3.new(0, 0, -2), 16, false))
			Harness.equal(tripped, false, "stopping short of the strand is not running into it")
		end),

		Harness.test("a step past the end of the wire misses it", function()
			-- The wire spans a doorway, not the whole wall. Walking around the end of it is a real miss.
			local tripped = TripwireRules.trips(query(Vector3.new(9, 0, -2), Vector3.new(9, 0, 2), 16, false))
			Harness.equal(tripped, false, "the strand only occupies the span it was strung across")
		end),

		Harness.test("A FULL-SPEED RUNNER CANNOT TUNNEL THROUGH IT", function()
			-- THE REASON THE TEST IS A SEGMENT. At run speed (16 studs/s) a player covers over half a
			-- stud per server tick and several studs per lag spike, so both samples of the step can sit
			-- clear of the wire on opposite sides. A radius check misses precisely the player this
			-- creature exists to catch. Sampled at a deliberately brutal quarter-second interval.
			local perTick = MovementConfig.runSpeed * 0.25
			Harness.expect(perTick > 2, "this test is meaningless unless the step overshoots the wire")
			local tripped =
				TripwireRules.trips(query(Vector3.new(0, 0, -perTick / 2), Vector3.new(0, 0, perTick / 2), 16, false))
			Harness.equal(tripped, true, "a step that steps OVER the wire in XZ must still catch")
		end),

		Harness.test("a hop clears it", function()
			-- THE COUNTERPLAY, asserted directly: airborne, feet above the strand, same crossing that
			-- would otherwise trip. Cleared by a margin the hop actually produces.
			local height = WIRE_Y + TripwireConfig.trip.hopClearanceStuds + 0.5
			local tripped = TripwireRules.trips(
				query(Vector3.new(0, height, -2), Vector3.new(0, height, 2), MovementConfig.runSpeed, true)
			)
			Harness.equal(tripped, false, "jumping over a rope has to work")
		end),

		Harness.test("being airborne is not enough on its own", function()
			-- Falling past the wire, or clipping it on the way down, still catches. Otherwise every
			-- player who happened to be off the ground would walk the trapline for free.
			local tripped = TripwireRules.trips(
				query(Vector3.new(0, WIRE_Y + 0.1, -2), Vector3.new(0, WIRE_Y + 0.1, 2), MovementConfig.runSpeed, true)
			)
			Harness.equal(tripped, true, "clearing it means being ABOVE it, not merely off the ground")
		end),

		Harness.test("edging into it does not spring it", function()
			local slow = TripwireConfig.trip.minimumTripSpeed * 0.5
			local tripped = TripwireRules.trips(query(Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), slow, false))
			Harness.equal(tripped, false, "somebody creeping through a doorway has not run into anything")
		end),

		Harness.test("walking ALONG the wire is not running into it", function()
			-- Collinear travel: a player moving down the length of the strand inside the opening. The
			-- degenerate case a naive segment test reports as an infinite number of crossings.
			local tripped =
				TripwireRules.trips(query(Vector3.new(-3, 0, 0), Vector3.new(3, 0, 0), MovementConfig.runSpeed, false))
			Harness.equal(tripped, false, "travel parallel to the strand is not a crossing")
		end),

		Harness.test("the faster you hit it, the longer you are down — across the whole band", function()
			-- Not just the endpoints: the relationship a player feels is monotonic, so every step up in
			-- speed must cost at least as much time as the one before it.
			local previous = -1
			for speed = 0, 30, 1 do
				local seconds = TripwireRules.stunSeconds(speed)
				Harness.expect(seconds >= previous, "stun must never decrease as speed rises, at " .. speed)
				previous = seconds
			end
		end),

		Harness.test("the stun stays inside the authored one-to-three-second band", function()
			-- Including well past the top of the band: a player launched by something else must not be
			-- pinned for ten seconds because their speed was off the scale.
			for _, speed in { 0, 4, 8, 16, 60, 500 } do
				local seconds = TripwireRules.stunSeconds(speed)
				Harness.expect(
					seconds >= TripwireConfig.trip.minStunSeconds and seconds <= TripwireConfig.trip.maxStunSeconds,
					"stun out of band at speed " .. speed
				)
			end
		end),

		Harness.test("a run-speed impact is the full stun and a crawl is the least", function()
			Harness.equal(
				TripwireRules.stunSeconds(MovementConfig.runSpeed),
				TripwireConfig.trip.maxStunSeconds,
				"running into it is the worst case"
			)
			Harness.equal(
				TripwireRules.stunSeconds(TripwireConfig.trip.minimumTripSpeed),
				TripwireConfig.trip.minStunSeconds,
				"the slowest trip that fires at all costs the least"
			)
		end),

		Harness.test("maximum brightness burns it and a cupped flame never does", function()
			-- The dial means ONE thing everywhere in the game: this delegates to Logic/VineRules rather
			-- than deciding for itself, and the test asserts that the delegation actually holds.
			Harness.equal(TripwireRules.burns(true, false, 1, false, nil), true, "a full dial burns the strand")
			Harness.equal(TripwireRules.burns(true, true, 1, false, nil), false, "a cupped ember is not brightness")
			Harness.equal(TripwireRules.burns(false, false, 1, false, nil), false, "an unlit candle burns nothing")
			Harness.equal(TripwireRules.burns(true, false, 0.1, false, nil), false, "a low dial burns nothing")
		end),

		Harness.test("a capped candle can still burn one", function()
			-- A player who sacrificed brightness at the Basin has a lower ceiling, and "maximum" means
			-- maximum FOR THEM. The alternative is a permanent upgrade that silently removes an answer.
			Harness.equal(
				TripwireRules.burns(true, false, 0.5, false, 0.5),
				true,
				"the top of a reduced dial is still the top of the dial"
			)
		end),

		Harness.test("the strand sags in the middle and not at its ends", function()
			Harness.near(TripwireRules.sagAt(0, 10), 0, 1e-9, "an anchored end does not hang")
			Harness.near(TripwireRules.sagAt(1, 10), 0, 1e-9, "the far anchor does not hang either")
			Harness.expect(TripwireRules.sagAt(0.5, 10) > 0, "the middle of a strung vine hangs")
		end),
	},
}

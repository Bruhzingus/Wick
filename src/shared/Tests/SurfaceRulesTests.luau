--!strict

local Harness = require(script.Parent.Harness)
local SurfaceRules = require(script.Parent.Parent.Logic.SurfaceRules)

local suite: Harness.Suite = {
	name = "SurfaceRules",
	tests = {
		Harness.test("accepts a vertical normal at any configured slope", function()
			Harness.equal(SurfaceRules.isUpwardFacing(Vector3.yAxis, 0), true)
			Harness.equal(SurfaceRules.isUpwardFacing(Vector3.yAxis, 60), true)
		end),

		Harness.test("accepts a normal just inside the configured slope and rejects one just past it", function()
			local maximum = 60
			local within = math.rad(maximum - 1)
			local beyond = math.rad(maximum + 1)
			Harness.equal(
				SurfaceRules.isUpwardFacing(Vector3.new(math.sin(within), math.cos(within), 0), maximum),
				true
			)
			Harness.equal(
				SurfaceRules.isUpwardFacing(Vector3.new(math.sin(beyond), math.cos(beyond), 0), maximum),
				false
			)
		end),

		Harness.test("rejects a downward-facing normal, such as the underside of an overhang", function()
			Harness.equal(SurfaceRules.isUpwardFacing(-Vector3.yAxis, 60), false)
			Harness.equal(SurfaceRules.isUpwardFacing(Vector3.new(0, -0.2, 1), 60), false)
		end),

		Harness.test("rejects a zero-length normal instead of dividing by zero", function()
			Harness.equal(SurfaceRules.isUpwardFacing(Vector3.zero, 60), false)
		end),

		Harness.test("clamps an out-of-range slope instead of inverting the check", function()
			-- A negative or >90 maxSlopeDegrees is a config mistake, not a licence to accept walls.
			Harness.equal(SurfaceRules.isUpwardFacing(Vector3.new(1, 0, 0), -10), false)
			Harness.equal(SurfaceRules.isUpwardFacing(Vector3.yAxis, 500), true)
		end),

		Harness.test("keeps the centre surface as the seat instead of lifting to a nearby hump", function()
			Harness.near(SurfaceRules.footprintSeatY(12, { 12.5, 14.75, 10.5 }, 3.5) or 0, 12, 1e-6)
		end),

		Harness.test("rejects a footprint that crosses a different-height surface", function()
			Harness.equal(SurfaceRules.footprintSeatY(12, { 12.5, 16 }, 3.5), nil)
		end),
	},
}

return suite

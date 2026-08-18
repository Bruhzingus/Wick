--!strict

local Harness = require(script.Parent.Harness)
local SurfaceRules = require(script.Parent.Parent.Logic.SurfaceRules)
local RoofGeometry = require(script.Parent.Parent.Logic.RoofGeometry)
local FloorsConfig = require(script.Parent.Parent.Config.Floors)

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

		Harness.test("keeps a floor-probe origin inside the guaranteed open band", function()
			Harness.near(SurfaceRules.openBandProbeLift(10, 8.5), 4.25)
			Harness.near(SurfaceRules.openBandProbeLift(2, 8.5), 2)
			Harness.near(SurfaceRules.openBandProbeLift(-2, 8.5), 0)
		end),

		Harness.test("refuses a peripheral shelf whose local roof join has no guaranteed headroom", function()
			local roofField: RoofGeometry.Field = {
				maxRelief = 0,
				frequencies = { 0, 0, 0, 0 },
				phases = { 0, 0, 0, 0 },
			}
			local groundHeight = 12
			local edgeRoof = RoofGeometry.undersideHeight(15, roofField, groundHeight, 24, 0)
			Harness.isNil(
				SurfaceRules.plannedProbeLift(10, edgeRoof - groundHeight, FloorsConfig.roof.minimumClearance),
				"the wall-transition band must not borrow the room interior's clearance"
			)

			local interiorRoof = RoofGeometry.undersideHeight(15, roofField, groundHeight, 0, 0)
			Harness.near(
				SurfaceRules.plannedProbeLift(10, interiorRoof - groundHeight, FloorsConfig.roof.minimumClearance) or 0,
				FloorsConfig.roof.minimumClearance / 2
			)
		end),

		Harness.test("keeps the centre surface as the seat instead of lifting to a nearby hump", function()
			local samples = {
				{ offset = Vector2.new(1, 0), y = 12.5 },
				{ offset = Vector2.new(0, 1), y = 14.75 },
				{ offset = Vector2.new(-1, 0), y = 10.5 },
			}
			Harness.near(SurfaceRules.footprintSeatY(12, Vector3.yAxis, samples, 3, 3.5) or 0, 12, 1e-6)
		end),

		Harness.test("rejects a footprint that crosses a different-height surface", function()
			local samples = {
				{ offset = Vector2.new(1, 0), y = 12.5 },
				{ offset = Vector2.new(-1, 0), y = 16 },
			}
			Harness.equal(SurfaceRules.footprintSeatY(12, Vector3.yAxis, samples, 2, 3.5), nil)
		end),

		Harness.test("accepts a complete footprint on a legal tangent slope", function()
			local rise = math.tan(math.rad(45))
			local normal = Vector3.new(-rise, 1, 0).Unit
			local samples = {
				{ offset = Vector2.new(-5.5, 0), y = 20 - rise * 5.5 },
				{ offset = Vector2.new(5.5, 0), y = 20 + rise * 5.5 },
				{ offset = Vector2.new(0, -5.5), y = 20 },
				{ offset = Vector2.new(0, 5.5), y = 20 },
			}
			Harness.near(SurfaceRules.footprintSeatY(20, normal, samples, 4, 0.01) or 0, 20, 1e-6)
		end),

		Harness.test("rejects a footprint when any required support ray is missing", function()
			local samples = {
				{ offset = Vector2.new(-1, 0), y = 12 },
				{ offset = Vector2.new(1, 0), y = 12 },
			}
			Harness.equal(SurfaceRules.footprintSeatY(12, Vector3.yAxis, samples, 3, 3.5), nil)
		end),
	},
}

return suite

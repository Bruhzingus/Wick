--!strict

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local VineRules = require(script.Parent.Parent.Logic.VineRules)
local IcicleRules = require(script.Parent.Parent.Logic.IcicleRules)
local BasinConfig = require(script.Parent.Parent.Config.Basin)
local IciclesConfig = require(script.Parent.Parent.Config.Icicles)
local LightConfig = require(script.Parent.Parent.Config.Light)
local VinesConfig = require(script.Parent.Parent.Config.Vines)

local function room(gridX: number, gridZ: number, doorways: { Types.Direction }): Types.RoomPlacement
	return {
		moduleId = "Corridor",
		gridX = gridX,
		gridZ = gridZ,
		doorways = doorways,
		ceilingHeight = 20,
	}
end

-- A---B
-- |   |
-- C---D   (a loop: every doorway is redundant on its own)
local function loopRooms(): { Types.RoomPlacement }
	return {
		room(0, 0, { "E", "S" }),
		room(1, 0, { "W", "S" }),
		room(0, 1, { "N", "E" }),
		room(1, 1, { "N", "W" }),
	}
end

-- A---B---C   (a chain: the middle doorway is load-bearing)
local function chainRooms(): { Types.RoomPlacement }
	return {
		room(0, 0, { "E" }),
		room(1, 0, { "W", "E" }),
		room(2, 0, { "W" }),
	}
end

local suite: Harness.Suite = {
	name = "VineRules",
	tests = {
		Harness.test("a doorway on a loop is redundant, one on a chain is not", function()
			Harness.equal(VineRules.doorwayIsRedundant(loopRooms(), 1, 1, "E"), true)
			Harness.equal(VineRules.doorwayIsRedundant(loopRooms(), 1, 1, "S"), true)
			Harness.equal(VineRules.doorwayIsRedundant(chainRooms(), 1, 2, "E"), false)
			Harness.equal(VineRules.doorwayIsRedundant(chainRooms(), 1, 1, "E"), false)
		end),

		Harness.test("a sealed doorway is refused from both of its sides", function()
			-- The same opening named from the far room must block the identical edge.
			Harness.equal(VineRules.doorwayIsRedundant(chainRooms(), 1, 3, "W"), false)
			Harness.equal(VineRules.allRoomsReachable(chainRooms(), 1, { { roomIndex = 3, direction = "W" } }), false)
		end),

		Harness.test("individually redundant doorways are still checked as a set", function()
			local rooms = loopRooms()
			-- Cutting either side of the loop alone is fine; cutting both isolates the corner room.
			Harness.equal(VineRules.allRoomsReachable(rooms, 1, { { roomIndex = 2, direction = "S" } }), true)
			Harness.equal(VineRules.allRoomsReachable(rooms, 1, { { roomIndex = 3, direction = "E" } }), true)
			Harness.equal(
				VineRules.allRoomsReachable(rooms, 1, {
					{ roomIndex = 2, direction = "S" },
					{ roomIndex = 3, direction = "E" },
				}),
				false
			)
		end),

		Harness.test("vines burn at the top of the dial without needing FLARE", function()
			local top = LightConfig.maxBurnRate
			Harness.equal(VineRules.burnsVines(true, false, top, false), true, "a full dial must clear vines")
			Harness.equal(VineRules.burnsVines(true, false, LightConfig.minBurnRate, false), false)
			Harness.equal(VineRules.burnsVines(false, false, top, false), false, "an unlit candle burns nothing")
			Harness.equal(VineRules.burnsVines(true, true, top, false), false, "a cupped ember burns nothing")
		end),

		Harness.test("a Basin brightness cap still clears barriers at that candle's maximum", function()
			local capped = LightConfig.maxBurnRate * BasinConfig.effects.maxBurnRateCapMultiplier
			Harness.equal(
				VineRules.burnsVines(true, false, capped, false, capped),
				true,
				"maximum means the candle's reachable maximum, not the unmodified global ceiling"
			)
			Harness.equal(
				VineRules.burnsVines(true, false, capped, true, capped),
				VinesConfig.flareBurns,
				"FLARE remains a faster alternative, never a requirement"
			)
			Harness.equal(
				IcicleRules.meltSeconds(true, false, capped, false, capped),
				IciclesConfig.maxBrightnessMeltSeconds
			)
		end),

		Harness.test("Ice bars melt slowly at maximum brightness and quickly under a Flare", function()
			Harness.equal(
				IcicleRules.meltSeconds(true, false, LightConfig.maxBurnRate, false),
				IciclesConfig.maxBrightnessMeltSeconds
			)
			Harness.equal(
				IcicleRules.meltSeconds(true, false, LightConfig.minBurnRate, true),
				IciclesConfig.flareMeltSeconds
			)
			Harness.expect(IciclesConfig.flareMeltSeconds < IciclesConfig.maxBrightnessMeltSeconds)
			Harness.isNil(IcicleRules.meltSeconds(true, true, LightConfig.maxBurnRate, true))
		end),

		Harness.test("fire spreads between curtains within range and stops beyond it", function()
			local origin = Vector3.new(0, 0, 0)
			local radius = VinesConfig.spreadRadius
			Harness.expect(radius > 0, "curtains are meant to catch from one another")
			Harness.equal(
				VineRules.spreadsTo(origin, Vector3.new(radius - 1, 0, 0)),
				true,
				"a curtain inside the spread radius must catch"
			)
			Harness.equal(
				VineRules.spreadsTo(origin, Vector3.new(radius + 1, 0, 0)),
				false,
				"spread must not be floor-wide regardless of distance"
			)
			-- Height counts too: curtains sit at different lane heights on a rolling floor.
			Harness.equal(VineRules.spreadsTo(origin, Vector3.new(0, radius + 1, 0)), false)
		end),

		Harness.test("a curtain catches well before it is consumed", function()
			Harness.expect(
				VinesConfig.igniteSeconds < VinesConfig.burnSeconds,
				"igniting must be the short part — the burn itself runs unattended"
			)
			Harness.expect(VinesConfig.igniteSeconds > 0, "curtains must not ignite on the first frame of light")
		end),

		Harness.test("vine budget respects the configured minimum depth", function()
			for depth = 1, VinesConfig.minDepth - 1 do
				Harness.equal(VineRules.targetCount(depth), 0, "vines must not be budgeted at depth " .. depth)
			end
			local deepest = #VinesConfig.perFloorByDepth
			Harness.expect(VineRules.targetCount(deepest) > 0, "the deepest floor must be able to host vines")
			Harness.equal(
				VineRules.targetCount(deepest + 5),
				VineRules.targetCount(deepest),
				"depth beyond the table must clamp, not fall off it"
			)
		end),
	},
}

return suite

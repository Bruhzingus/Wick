--!strict
-- What a phone-shaped viewport is owed. These are the numbers that used to be checkable only by
-- opening Studio, shaping the window like a handset and looking at it, which is why they drifted.

local Harness = require(script.Parent.Harness)
local TouchLayoutRules = require(script.Parent.Parent.Logic.TouchLayoutRules)

-- Two real shapes rather than round numbers: a small handset in landscape and a large one. Both are
-- landscape because this game is played that way and the reserves are horizontal.
local SMALL_WIDTH, SMALL_HEIGHT = 800, 400
local LARGE_WIDTH, LARGE_HEIGHT = 1280, 600
local TOPBAR_INSET = 36

-- What the two rows actually hold today, with a spare slot each. The tool row is Flare, Decoy, Cup
-- and Dynamite; the primary row is Stop, Throw and Light. Either row wrapping to a second line eats
-- the screen height this layout was shortened to give back, so both counts are load-bearing.
local TOUCH_TOOL_COUNT = 5
local TOUCH_PRIMARY_COUNT = 3

local function bothScreens(check: (number, number) -> ())
	check(SMALL_WIDTH, SMALL_HEIGHT)
	check(LARGE_WIDTH, LARGE_HEIGHT)
end

return {
	name = "TouchLayoutRules",
	tests = {
		Harness.test("jump reserve follows Roblox's own small-screen threshold", function()
			Harness.equal(TouchLayoutRules.jumpPixels(500), 70)
			Harness.equal(TouchLayoutRules.jumpPixels(501), 120)
		end),

		Harness.test("reserves leave the middle of the screen unclaimed", function()
			bothScreens(function(width: number, height: number)
				local right, left = TouchLayoutRules.reservations(width, height)
				Harness.expect(right > 0 and left > 0, "both corners must be reserved")
				Harness.expect(
					right + left < width * 0.7,
					"reserves swallowed the screen: nothing is left for the tap field"
				)
			end)
		end),

		Harness.test("action buttons are wider than they are tall", function()
			bothScreens(function(width: number, height: number)
				local metrics = TouchLayoutRules.cluster(width, height)
				Harness.expect(
					metrics.toolWidthPixels > metrics.toolHeightPixels * 1.5,
					"a tool button that is nearly square is the tall slab this layout replaced"
				)
				Harness.expect(
					metrics.primaryWidthPixels > metrics.primaryHeightPixels * 1.5,
					"the primary row went back to being square"
				)
			end)
		end),

		Harness.test("rows are shorter than the jump button they sit beside", function()
			bothScreens(function(width: number, height: number)
				local metrics = TouchLayoutRules.cluster(width, height)
				Harness.expect(
					metrics.toolHeightPixels < metrics.jumpPixels * 0.75,
					"the tool row is as tall as Roblox's jump button again"
				)
				Harness.expect(metrics.primaryHeightPixels <= metrics.toolHeightPixels, "primary row outgrew a tool")
			end)
		end),

		Harness.test("row height never drops below a thumb", function()
			-- A viewport nothing sane reports, to prove the floor is a floor rather than an accident of
			-- the sizes that happen to be tested above.
			for _, height in { 200, 320, 400, 600, 1080, 2160 } do
				local metrics = TouchLayoutRules.cluster(640, height)
				Harness.expect(
					metrics.toolHeightPixels >= 44 and metrics.primaryHeightPixels >= 44,
					string.format("row height fell under 44 at height %d", height)
				)
			end
		end),

		Harness.test("every button of a row fits on one line", function()
			bothScreens(function(width: number, height: number)
				local metrics = TouchLayoutRules.cluster(width, height)
				Harness.expect(
					metrics.toolsPerRow >= TOUCH_TOOL_COUNT,
					string.format("only %d tools fit on a line", metrics.toolsPerRow)
				)
				Harness.expect(
					metrics.primaryPerRow >= TOUCH_PRIMARY_COUNT,
					string.format("only %d primary actions fit on a line", metrics.primaryPerRow)
				)
			end)
		end),

		Harness.test("the cluster reserve accounts for both of its rows", function()
			bothScreens(function(width: number, height: number)
				local metrics = TouchLayoutRules.cluster(width, height)
				Harness.expect(
					metrics.bottomReservePixels >= metrics.toolHeightPixels + metrics.primaryHeightPixels,
					"the reserve is shorter than the rows standing in it"
				)
				Harness.expect(
					metrics.bottomReservePixels < height * 0.4,
					"the cluster claims most of the screen's height"
				)
			end)
		end),

		Harness.test("the tap field clears every reserved edge", function()
			bothScreens(function(width: number, height: number)
				local metrics = TouchLayoutRules.cluster(width, height)
				local field = TouchLayoutRules.tapField(width, height, TOPBAR_INSET)
				Harness.expect(field.leftPixels >= metrics.leftReservePixels, "field overlaps the thumbstick")
				Harness.expect(
					field.leftPixels + field.widthPixels <= width - metrics.rightReservePixels,
					"field overlaps the jump button and the brightness dial"
				)
				Harness.expect(field.topPixels > TOPBAR_INSET, "field reaches under Roblox's topbar")
				Harness.expect(
					field.topPixels + field.heightPixels <= height - metrics.bottomReservePixels,
					"field reaches under the action cluster"
				)
			end)
		end),

		Harness.test("the tap field is still most of what is left", function()
			bothScreens(function(width: number, height: number)
				local field = TouchLayoutRules.tapField(width, height, TOPBAR_INSET)
				Harness.expect(field.widthPixels > width * 0.5, "the field stopped being an area and became a strip")
				Harness.expect(field.heightPixels > height * 0.4, "the field is too short to aim at")
			end)
		end),

		Harness.test("a screen with no room left yields an empty field rather than a negative one", function()
			local field = TouchLayoutRules.tapField(120, 120, TOPBAR_INSET)
			Harness.expect(field.widthPixels >= 0 and field.heightPixels >= 0, "field inverted")
			Harness.expect(not TouchLayoutRules.contains(field, 60, 60), "an empty field accepted a tap")
		end),

		Harness.test("the field accepts the middle and refuses every control's corner", function()
			local field = TouchLayoutRules.tapField(LARGE_WIDTH, LARGE_HEIGHT, TOPBAR_INSET)
			Harness.expect(TouchLayoutRules.contains(field, LARGE_WIDTH / 2, LARGE_HEIGHT / 2), "centre refused")
			-- Thumbstick, jump button, topbar, and the cluster, in that order.
			Harness.expect(not TouchLayoutRules.contains(field, 40, LARGE_HEIGHT - 60), "thumbstick corner accepted")
			Harness.expect(
				not TouchLayoutRules.contains(field, LARGE_WIDTH - 40, LARGE_HEIGHT - 60),
				"jump corner accepted"
			)
			Harness.expect(not TouchLayoutRules.contains(field, LARGE_WIDTH / 2, 8), "topbar accepted")
			Harness.expect(
				not TouchLayoutRules.contains(field, LARGE_WIDTH / 2, LARGE_HEIGHT - 10),
				"the cluster's own row accepted"
			)
		end),

		Harness.test("the dial column is outside the field", function()
			-- The brightness dial hugs the right edge for a little over half the screen's height. A tap
			-- that misses it must not become a pickaxe swing, which is only true while the field's right
			-- boundary stays inside the reserve the dial lives in.
			bothScreens(function(width: number, height: number)
				local field = TouchLayoutRules.tapField(width, height, TOPBAR_INSET)
				Harness.expect(
					not TouchLayoutRules.contains(field, width - 30, height / 2),
					"a tap beside the dial reached the mining field"
				)
			end)
		end),

		Harness.test("the menu square is smaller than the bar it replaced", function()
			bothScreens(function(width: number, height: number)
				local size = TouchLayoutRules.menuPixels(width, height)
				Harness.expect(size >= 42, "the menu button stopped being hittable")
				Harness.expect(size <= 54, "the menu button is drifting back toward a headline")
				Harness.expect(size * size < 112 * 48, "the menu button claims more area than the old bar")
			end)
		end),

		Harness.test("the candle caption tightens on touch without becoming unreadable", function()
			local touchText, touchGap = TouchLayoutRules.candleCaption(true)
			local deskText, deskGap = TouchLayoutRules.candleCaption(false)
			Harness.expect(touchText < deskText, "the touch caption is no tighter than the desktop one")
			Harness.expect(touchGap < deskGap, "the touch caption sits no closer under the dish")
			-- The floor the whole caption is worth its row against. Below this it costs height and
			-- returns nothing, which is worse than not naming the candle at all.
			Harness.expect(touchText >= 12, "the touch caption dropped under a readable size")
			-- One row, and it has to stay one row: the caption plus its gap must not approach the height
			-- of the candle it labels, or the thing being explained is smaller than the explanation.
			Harness.expect(touchText + touchGap < 24, "the caption block grew past a single tight row")
		end),

		Harness.test("the caption does not shrink with the candle it names", function()
			-- The caption hangs inside the candle's scaled envelope and cancels that scale, so its size
			-- is stated in final pixels. This is the invariant that makes that legal: touch text is
			-- chosen outright, never derived from the candle's own scale.
			local candleTouch = TouchLayoutRules.candle(true)
			local touchText = TouchLayoutRules.candleCaption(true)
			local deskText = TouchLayoutRules.candleCaption(false)
			Harness.expect(
				touchText > deskText * candleTouch,
				"the caption is no larger than a caption that had simply been scaled down with the candle"
			)
		end),

		Harness.test("the candle is smaller on touch than on desktop", function()
			local touchScale, touchHeight = TouchLayoutRules.candle(true)
			local deskScale, deskHeight = TouchLayoutRules.candle(false)
			Harness.equal(deskScale, 1, "desktop candle must be left at its authored size")
			Harness.expect(touchScale < deskScale, "touch candle is no smaller")
			Harness.expect(touchHeight < deskHeight, "touch candle is no shorter")
			-- Both together, or the flame ends up floating off a wick that shrank without it.
			Harness.expect(touchScale * touchHeight < deskScale * deskHeight * 0.75, "barely shrunk at all")
		end),
	},
}

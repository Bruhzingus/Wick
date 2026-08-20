--!strict
-- How a phone screen is divided between the controls that compete for it, as arithmetic over a
-- viewport size.
--
-- WHY THIS IS A SHARED MODULE. Every number here used to live inside client/TouchControls, where the
-- only way to check one was to open Studio, shape the viewport like a phone, and look. The division
-- is pure arithmetic — a width, a height and the two corners Roblox already owns — so it belongs
-- where the rest of this game's arithmetic lives: in shared/Logic, beside a suite that can state what
-- a 400-pixel-tall screen is supposed to get and fail when somebody changes it by accident.
--
-- Nothing here touches an instance, a service, or a Roblox datatype; callers turn these numbers into
-- UDim2s. Sizes are in the ScreenGui's own pixels (`AbsoluteSize`), which is what every consumer
-- already measures in.

local TouchLayoutRules = {}

-- Roblox's TouchJump drops to a smaller jump button at or below this viewport height. Matching the
-- threshold keeps this game's cluster in proportion with the one control it has to sit beside.
local SMALL_SCREEN_HEIGHT = 500
local SMALL_JUMP_PIXELS = 70
local JUMP_PIXELS = 120

-- A square touch target below roughly this many pixels is a target players miss. The sizing unit is
-- allowed to shrink with the screen right up to this floor and no further.
local MIN_TARGET_PIXELS = 46
local MAX_TARGET_PIXELS = 96

-- ACTION BUTTONS ARE WIDE AND SHORT, NOT SQUARE. They were sized off the jump button in both axes,
-- which on a phone made FLARE / DECOY / CUP / DYNAMITE a row of ~132x94 slabs eating a fifth of a
-- landscape viewport — in a game whose whole subject is what you can see. Width is what makes a
-- word-labelled button easy to hit, so width keeps tracking the jump button; height drops to roughly
-- half of it. The 44-pixel floor is the short side of a target that is already three times as wide,
-- which is a far larger area than the 46-pixel square the unit floor describes.
local MIN_ROW_HEIGHT_PIXELS = 44
local MAX_ROW_HEIGHT_PIXELS = 58
local TOOL_HEIGHT_UNIT_SCALE = 0.56
local PRIMARY_HEIGHT_UNIT_SCALE = 0.5

local TOOL_WIDTH_UNIT_SCALE = 1.5
local MIN_TOOL_WIDTH_PIXELS = 64
local MAX_TOOL_WIDTH_PIXELS = 132
-- The primary row (STOP, LIGHT) is fewer and wider than a tool chip.
local PRIMARY_WIDTH_TOOL_SCALE = 1.6

-- The candle IS the health bar (DESIGN §3), and at the authored size it owned the left sixth of a
-- phone screen. Touch shrinks it rather than moving it: where it sits is the one thing about it a
-- player has already learned, and a cave is read through the middle of the frame, not the edge.
local TOUCH_CANDLE_SCALE = 0.62
local TOUCH_CANDLE_HEIGHT_SCALE = 0.38
local DESKTOP_CANDLE_HEIGHT_SCALE = 0.46

-- The caption under the candle, which names it and reads out what is left. It does NOT shrink with
-- the candle — a label too small to read is the same as no label, and this one exists for the player
-- who has not learned the HUD yet — so touch buys its compactness by tightening instead: one point
-- smaller and sat closer under the dish. Below about twelve pixels the two letters stop being worth
-- the row they cost, which is the floor these numbers are chosen against.
local TOUCH_CAPTION_TEXT_PIXELS = 13
local TOUCH_CAPTION_GAP_PIXELS = 7
local DESKTOP_CAPTION_TEXT_PIXELS = 15
local DESKTOP_CAPTION_GAP_PIXELS = 11

-- The menu opener. On desktop it is a labelled bar; on touch it is a square in the corner, sized
-- like a control rather than like a headline.
local MIN_MENU_PIXELS = 42
local MAX_MENU_PIXELS = 54

export type Cluster = {
	jumpPixels: number,
	-- Free space either side of the cluster, measured in from that edge of the viewport.
	rightReservePixels: number,
	leftReservePixels: number,
	unitPixels: number,
	gapPixels: number,
	toolWidthPixels: number,
	toolHeightPixels: number,
	primaryWidthPixels: number,
	primaryHeightPixels: number,
	toolsPerRow: number,
	primaryPerRow: number,
	bottomMarginPixels: number,
	-- How much of the bottom of the screen the cluster is expected to occupy, gaps included.
	bottomReservePixels: number,
}

export type Field = {
	leftPixels: number,
	topPixels: number,
	widthPixels: number,
	heightPixels: number,
}

function TouchLayoutRules.jumpPixels(viewportHeight: number): number
	return if viewportHeight <= SMALL_SCREEN_HEIGHT then SMALL_JUMP_PIXELS else JUMP_PIXELS
end

-- The reserved corners, in the viewport's own pixels.
--
-- TouchJump sizes its button 70 on a short screen and 120 otherwise, and anchors it at
-- `(1, -(size * 1.5 - 10), 1, -size - 20)`. Reserving `size * 1.5` plus a margin from the right edge
-- therefore clears it on any device without anything having to find the instance. The movement
-- thumbstick owns the opposite corner and is bounded the same way rather than measured.
function TouchLayoutRules.reservations(viewportWidth: number, viewportHeight: number): (number, number)
	local jump = TouchLayoutRules.jumpPixels(viewportHeight)
	local right = jump * 1.5 + 16
	local left = math.min(viewportWidth * 0.34, jump * 2.6)
	return right, left
end

function TouchLayoutRules.cluster(viewportWidth: number, viewportHeight: number): Cluster
	local jump = TouchLayoutRules.jumpPixels(viewportHeight)
	local right, left = TouchLayoutRules.reservations(viewportWidth, viewportHeight)

	-- Targets track the jump button, which is the one control on screen Roblox has already sized for
	-- a thumb on this exact device.
	local unit = math.clamp(jump * 0.78, MIN_TARGET_PIXELS, MAX_TARGET_PIXELS)
	local gap = math.max(6, math.floor(unit * 0.14))
	local toolWidth = math.clamp(unit * TOOL_WIDTH_UNIT_SCALE, MIN_TOOL_WIDTH_PIXELS, MAX_TOOL_WIDTH_PIXELS)
	local toolHeight =
		math.clamp(math.floor(unit * TOOL_HEIGHT_UNIT_SCALE), MIN_ROW_HEIGHT_PIXELS, MAX_ROW_HEIGHT_PIXELS)
	local primaryHeight =
		math.clamp(math.floor(unit * PRIMARY_HEIGHT_UNIT_SCALE), MIN_ROW_HEIGHT_PIXELS, MAX_ROW_HEIGHT_PIXELS)

	-- How many tool buttons fit on one line between the thumbstick and the jump button. Below two the
	-- cluster would be a column tall enough to reach the top of the screen, so two is the floor and a
	-- genuinely tiny screen accepts overlapping a reserve instead.
	local available = math.max(viewportWidth - right - left, toolWidth)
	local primaryWidth = math.min(toolWidth * PRIMARY_WIDTH_TOOL_SCALE, available)
	local bottomMargin = math.max(12, math.floor(unit * 0.2))

	return {
		jumpPixels = jump,
		rightReservePixels = right,
		leftReservePixels = left,
		unitPixels = unit,
		gapPixels = gap,
		toolWidthPixels = toolWidth,
		toolHeightPixels = toolHeight,
		primaryWidthPixels = primaryWidth,
		primaryHeightPixels = primaryHeight,
		toolsPerRow = math.max(2, math.floor((available + gap) / (toolWidth + gap))),
		primaryPerRow = math.max(1, math.floor((available + gap) / (primaryWidth + gap))),
		bottomMarginPixels = bottomMargin,
		-- One tool line is assumed. Under-reserving is the safe direction: the cluster's buttons are
		-- real GUI, so a field that reaches under a wrapped second line still loses every tap that
		-- lands on a button to the button.
		bottomReservePixels = bottomMargin + toolHeight + gap + primaryHeight + gap,
	}
end

-- THE MINING TAP AREA. Everything in the middle of the screen that no control claims: clear of the
-- movement thumbstick on the left, of the jump button and the brightness dial on the right, of the
-- Roblox topbar and this game's menu button above, and of the action cluster below.
--
-- The margins it leaves are not waste. They are where a touch player drags to look around, and a
-- strike fires the instant a finger lands (client/MiningController explains why a quick-time event
-- cannot wait for the release), so a region that covered the whole screen would turn every camera
-- drag into a swing.
function TouchLayoutRules.tapField(viewportWidth: number, viewportHeight: number, topInsetPixels: number): Field
	local metrics = TouchLayoutRules.cluster(viewportWidth, viewportHeight)
	local top = topInsetPixels + TouchLayoutRules.menuPixels(viewportWidth, viewportHeight) + 20
	local bottom = viewportHeight - metrics.bottomReservePixels
	return {
		leftPixels = metrics.leftReservePixels,
		topPixels = top,
		widthPixels = math.max(0, viewportWidth - metrics.rightReservePixels - metrics.leftReservePixels),
		heightPixels = math.max(0, bottom - top),
	}
end

function TouchLayoutRules.contains(field: Field, x: number, y: number): boolean
	if field.widthPixels <= 0 or field.heightPixels <= 0 then
		return false
	end
	return x >= field.leftPixels
		and x <= field.leftPixels + field.widthPixels
		and y >= field.topPixels
		and y <= field.topPixels + field.heightPixels
end

-- Uniform scale for the candle HUD, and the fraction of the viewport height its full-wax envelope
-- spans. Returned together because changing one without the other moves the flame off the wick.
function TouchLayoutRules.candle(touch: boolean): (number, number)
	if touch then
		return TOUCH_CANDLE_SCALE, TOUCH_CANDLE_HEIGHT_SCALE
	end
	return 1, DESKTOP_CANDLE_HEIGHT_SCALE
end

-- Text size for the candle's caption, and the gap between the bottom of its dish and the top of that
-- caption. Both in FINAL rendered pixels, deliberately: the caption hangs inside the candle's scaled
-- envelope, so the caller converts the gap into that envelope's units and cancels the scale on the
-- text. Returning what the player actually sees is what keeps this checkable.
function TouchLayoutRules.candleCaption(touch: boolean): (number, number)
	if touch then
		return TOUCH_CAPTION_TEXT_PIXELS, TOUCH_CAPTION_GAP_PIXELS
	end
	return DESKTOP_CAPTION_TEXT_PIXELS, DESKTOP_CAPTION_GAP_PIXELS
end

function TouchLayoutRules.menuPixels(viewportWidth: number, viewportHeight: number): number
	local jump = TouchLayoutRules.jumpPixels(viewportHeight)
	local _, left = TouchLayoutRules.reservations(viewportWidth, viewportHeight)
	-- Bounded by the thumbstick reserve as well as by the jump button, so a very narrow viewport whose
	-- reserves already meet in the middle cannot be handed a corner button wider than its own margin.
	return math.clamp(math.min(jump * 0.42, left * 0.22), MIN_MENU_PIXELS, MAX_MENU_PIXELS)
end

return TouchLayoutRules

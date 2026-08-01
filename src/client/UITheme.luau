--!strict
-- Shared cave/candle look-and-feel for every menu surface. This is presentation only: colours,
-- fonts, and small builder/animation helpers so the lobby, results, Basin, and settings screens
-- read as one hand-lit game instead of grey-box primitives. No game rule lives here.
--
-- The whole palette is warm firelight against cold cave stone: near-black rock, bronze edges,
-- and amber/ember highlights that stand in for candlelight. Animations are deliberately small
-- (hover lifts, press dips, soft glows) — a professional menu breathes without shouting.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = {}

export type Palette = {
	void: Color3,
	panel: Color3,
	panelRaised: Color3,
	chip: Color3,
	chipHover: Color3,
	chipActive: Color3,
	stroke: Color3,
	strokeSoft: Color3,
	gold: Color3,
	ember: Color3,
	emberDeep: Color3,
	danger: Color3,
	text: Color3,
	textMuted: Color3,
	textDim: Color3,
	flameCore: Color3,
	flameMid: Color3,
	flameOuter: Color3,
	waxLight: Color3,
	waxDeep: Color3,
	smoke: Color3,
}

UITheme.palette = {
	-- Cold cave rock.
	void = Color3.fromRGB(9, 8, 10),
	panel = Color3.fromRGB(18, 15, 18),
	panelRaised = Color3.fromRGB(27, 22, 25),
	chip = Color3.fromRGB(33, 28, 32),
	chipHover = Color3.fromRGB(56, 44, 40),
	chipActive = Color3.fromRGB(104, 63, 34),
	-- Bronze / lit-stone edges.
	stroke = Color3.fromRGB(120, 96, 66),
	strokeSoft = Color3.fromRGB(64, 53, 46),
	-- Candlelight.
	gold = Color3.fromRGB(255, 201, 120),
	ember = Color3.fromRGB(255, 150, 66),
	emberDeep = Color3.fromRGB(190, 84, 38),
	danger = Color3.fromRGB(255, 92, 60),
	-- Type. All three are measured against `panel`/`void`, not against white: `textDim` used to be
	-- RGB(112,103,96), which lands around 2.5:1 on this game's panels and is below any usable
	-- contrast floor — and it was the colour chosen for the states players most need to read (a
	-- LOCKED node, a control hint). Dimness still means "recessive", it just no longer means
	-- "invisible"; the hierarchy between the three is preserved, lifted bodily into legible range.
	text = Color3.fromRGB(240, 232, 216),
	textMuted = Color3.fromRGB(190, 178, 162),
	textDim = Color3.fromRGB(152, 142, 131),
	-- Flame gradient (base -> tip).
	flameCore = Color3.fromRGB(255, 247, 222),
	flameMid = Color3.fromRGB(255, 186, 92),
	flameOuter = Color3.fromRGB(255, 116, 44),
	-- Wax body.
	waxLight = Color3.fromRGB(243, 234, 212),
	waxDeep = Color3.fromRGB(203, 187, 155),
	smoke = Color3.fromRGB(120, 116, 120),
} :: Palette

UITheme.font = {
	display = Enum.Font.GothamBlack,
	heading = Enum.Font.GothamBold,
	body = Enum.Font.GothamMedium,
	fine = Enum.Font.Gotham,
}

-- ONE TYPE SCALE for every surface in the game. `TextSize` in Roblox is absolute pixels and does not
-- respond to resolution, so a hand-picked 10 or 11 that looked fine in a small Studio viewport is
-- genuinely unreadable on a real monitor. Every label should name a step here instead of inventing a
-- number, which is what let the old sizes drift down to 10px in the places players read most often.
--
-- THE FLOOR IS `micro` AT 14. Nothing in this game is allowed to be smaller than that: if a label
-- does not fit at 14, the container is too small or the copy is too long, and both of those are real
-- problems that shrinking the type only hides.
UITheme.textSize = {
	micro = 14, -- captions, unit labels, status chips
	fine = 16, -- secondary copy, hints, subtitles
	body = 18, -- default reading size
	strong = 21, -- emphasised copy, node names, buttons
	value = 26, -- numeric readouts
	title = 32, -- panel headings
}

-- Make a label survive whatever it is drawn over. This game is a dark cave under a candle, so HUD
-- text sits on top of near-black rock, open flame, and everything in between — a colour alone is
-- never enough contrast. A tight dark outline costs nothing and makes the same label readable
-- against both the void and a lit wall, which is why prompts use it rather than a backing plate.
function UITheme.legible(label: TextLabel | TextButton, strength: number?)
	label.TextStrokeColor3 = UITheme.palette.void
	label.TextStrokeTransparency = 1 - math.clamp(strength or 0.75, 0, 1)
	return label
end

-- One shared cadence for interface motion. Snappy but soft-landing.
UITheme.motion = {
	hover = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	settle = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	rise = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	fade = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

function UITheme.tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

function UITheme.corner(parent: GuiObject, radiusPixels: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radiusPixels)
	corner.Parent = parent
	return corner
end

function UITheme.stroke(parent: GuiObject, color: Color3, thickness: number, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UITheme.padding(parent: GuiObject, top: number, right: number, bottom: number, left: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right)
	padding.PaddingBottom = UDim.new(0, bottom)
	padding.PaddingLeft = UDim.new(0, left)
	padding.Parent = parent
	return padding
end

function UITheme.uniformPadding(parent: GuiObject, pixels: number): UIPadding
	return UITheme.padding(parent, pixels, pixels, pixels, pixels)
end

function UITheme.listLayout(parent: GuiObject, paddingPixels: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, paddingPixels)
	layout.Parent = parent
	return layout
end

function UITheme.scale(parent: GuiObject, initial: number): UIScale
	local scale = Instance.new("UIScale")
	scale.Scale = initial
	scale.Parent = parent
	return scale
end

-- A vertical warm-to-dark wash: candlelight pooled in the middle of a dark cave. Faked with a
-- single linear gradient (no radial in Roblox UI) but reads as a lit room, not a flat fill.
function UITheme.backdrop(parent: GuiObject, transparency: number): Frame
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = UITheme.palette.void
	backdrop.BackgroundTransparency = transparency
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 0
	backdrop.Parent = parent

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UITheme.palette.void),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(34, 24, 20)),
		ColorSequenceKeypoint.new(1, UITheme.palette.void),
	})
	gradient.Parent = backdrop
	return backdrop
end

-- Standard cave panel: raised stone with a bronze rim and a faint top-lit sheen.
function UITheme.panel(parent: GuiObject): Frame
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = UITheme.palette.panel
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Parent = parent

	UITheme.corner(panel, 14)
	UITheme.stroke(panel, UITheme.palette.stroke, 1.5, 0.35)

	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 38, 40)),
		ColorSequenceKeypoint.new(0.14, UITheme.palette.panel),
		ColorSequenceKeypoint.new(1, UITheme.palette.void),
	})
	sheen.Parent = panel
	return panel
end

function UITheme.heading(parent: GuiObject, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Heading"
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.display
	label.Text = text
	label.TextColor3 = UITheme.palette.gold
	label.TextScaled = true
	label.Size = UDim2.new(1, 0, 0, 40)
	label.Parent = parent
	return label
end

function UITheme.label(parent: GuiObject, text: string, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.body
	label.Text = text
	label.TextColor3 = UITheme.palette.text
	label.TextWrapped = true
	label.TextScaled = true
	label.Size = UDim2.new(1, 0, 0, height)
	label.Parent = parent
	return label
end

export type Button = {
	instance: TextButton,
	scale: UIScale,
	stroke: UIStroke,
	setEnabled: (enabled: boolean) -> (),
	setActive: (active: boolean) -> (),
}

-- A button that lifts on hover, dips on press, and warms its rim on both. Works for mouse and
-- touch (Activated covers both; the press look is driven by pointer state). `setActive` marks a
-- persistent selected state (used by the cave-tier picker).
function UITheme.button(parent: GuiObject, text: string): Button
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BackgroundColor3 = UITheme.palette.chip
	button.BorderSizePixel = 0
	button.Font = UITheme.font.heading
	button.Text = text
	button.TextColor3 = UITheme.palette.gold
	button.TextScaled = true
	button.Size = UDim2.new(1, 0, 0, 46)
	button.Parent = parent

	UITheme.corner(button, 10)
	local stroke = UITheme.stroke(button, UITheme.palette.strokeSoft, 1.5, 0.3)
	local scale = UITheme.scale(button, 1)
	UITheme.uniformPadding(button, 6)

	UITheme.legible(button, 0.5)

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = UITheme.textSize.fine
	textConstraint.MaxTextSize = UITheme.textSize.strong
	textConstraint.Parent = button

	local enabled = true
	local active = false
	local hovered = false

	local function restColor(): Color3
		return if active then UITheme.palette.chipActive else UITheme.palette.chip
	end

	local function paint(instant: boolean)
		local targetColor = restColor()
		local targetStroke = if active then UITheme.palette.ember else UITheme.palette.strokeSoft
		local strokeTransparency = 0.3
		if not enabled then
			targetColor = UITheme.palette.chip
			targetStroke = UITheme.palette.strokeSoft
			strokeTransparency = 0.7
		elseif hovered then
			targetColor = if active then UITheme.palette.chipActive else UITheme.palette.chipHover
			targetStroke = UITheme.palette.ember
			strokeTransparency = 0.05
		end
		local info = if instant then TweenInfo.new(0) else UITheme.motion.hover
		UITheme.tween(button, info, { BackgroundColor3 = targetColor })
		UITheme.tween(stroke, info, { Color = targetStroke, Transparency = strokeTransparency })
		button.TextTransparency = if enabled then 0 else 0.45
	end

	button.MouseEnter:Connect(function()
		if not enabled then
			return
		end
		hovered = true
		paint(false)
		UITheme.tween(scale, UITheme.motion.hover, { Scale = 1.03 })
	end)
	button.MouseLeave:Connect(function()
		hovered = false
		paint(false)
		UITheme.tween(scale, UITheme.motion.hover, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		if not enabled then
			return
		end
		UITheme.tween(scale, UITheme.motion.press, { Scale = 0.97 })
	end)
	button.MouseButton1Up:Connect(function()
		if not enabled then
			return
		end
		UITheme.tween(scale, UITheme.motion.press, { Scale = if hovered then 1.03 else 1 })
	end)

	local api: Button
	api = {
		instance = button,
		scale = scale,
		stroke = stroke,
		setEnabled = function(value: boolean)
			enabled = value
			button.Active = value
			button.AutoButtonColor = false
			paint(true)
		end,
		setActive = function(value: boolean)
			active = value
			paint(false)
		end,
	}
	paint(true)
	return api
end

-- The shared heartbeat behind every candle in the game: organic noise leans and stretches the flame
-- from its wick, and the glow pulses in step. math.noise gives smooth wander — a flame nudged by cave
-- air, never a strobe. The loop retires itself when `group` leaves the tree, so callers only Destroy.
local function attachFlicker(
	group: GuiObject,
	pivot: Frame,
	pivotScale: UIScale,
	glowInner: Frame,
	glowOuter: Frame,
	flameCore: Frame,
	restX: number,
	restY: number
)
	local seed = Random.new():NextNumber(0, 1000)
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		if group.Parent == nil then
			if connection ~= nil then
				connection:Disconnect()
				connection = nil
			end
			return
		end
		local t = os.clock()
		local sway = math.noise(t * 1.5, seed)
		local flick = math.noise(seed, t * 2.3)
		local fast = math.noise(t * 5.5, seed * 0.5)
		pivot.Rotation = sway * 5
		pivot.Position = UDim2.fromScale(restX + sway * 0.02, restY)
		pivotScale.Scale = 1 + flick * 0.08 + fast * 0.03
		local pulse = (flick + 1) * 0.5
		glowInner.BackgroundTransparency = 0.72 - pulse * 0.12
		glowOuter.BackgroundTransparency = 0.9 - pulse * 0.07
		flameCore.BackgroundTransparency = math.clamp(0.05 - fast * 0.05, 0, 1)
	end)
end

-- A candle drawn to stand in for a capital "I": a lit wax column on a small foot, a bright flame
-- rising off the wick, and a pooled glow. `height` is the cap height it should match beside letters.
-- Everything is proportioned off `height` so it scales cleanly. Returns the glyph frame; the flame
-- animates itself and retires with the frame.
function UITheme.candleGlyph(parent: GuiObject, height: number): Frame
	local width = height * 0.36
	local box = Instance.new("Frame")
	box.Name = "CandleI"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(width, height)
	box.Parent = parent

	local glowOuter = Instance.new("Frame")
	glowOuter.Name = "GlowOuter"
	glowOuter.AnchorPoint = Vector2.new(0.5, 0.5)
	glowOuter.Position = UDim2.fromScale(0.5, 0.28)
	glowOuter.Size = UDim2.fromOffset(height * 0.62, height * 0.62)
	glowOuter.BackgroundColor3 = UITheme.palette.emberDeep
	glowOuter.BackgroundTransparency = 0.9
	glowOuter.BorderSizePixel = 0
	glowOuter.ZIndex = 1
	glowOuter.Parent = box
	UITheme.corner(glowOuter, math.floor(height * 0.31))

	local glowInner = Instance.new("Frame")
	glowInner.Name = "GlowInner"
	glowInner.AnchorPoint = Vector2.new(0.5, 0.5)
	glowInner.Position = UDim2.fromScale(0.5, 0.28)
	glowInner.Size = UDim2.fromOffset(height * 0.36, height * 0.36)
	glowInner.BackgroundColor3 = UITheme.palette.ember
	glowInner.BackgroundTransparency = 0.76
	glowInner.BorderSizePixel = 0
	glowInner.ZIndex = 2
	glowInner.Parent = box
	UITheme.corner(glowInner, math.floor(height * 0.18))

	-- Wax column: the vertical stroke of the "I", lit brightest at the molten top.
	local wax = Instance.new("Frame")
	wax.Name = "Wax"
	wax.AnchorPoint = Vector2.new(0.5, 1)
	wax.Position = UDim2.fromScale(0.5, 0.92)
	wax.Size = UDim2.new(0, height * 0.22, 0.5, 0)
	wax.BackgroundColor3 = UITheme.palette.waxLight
	wax.BorderSizePixel = 0
	wax.ZIndex = 4
	wax.Parent = box
	UITheme.corner(wax, math.floor(height * 0.05))

	local waxGradient = Instance.new("UIGradient")
	waxGradient.Rotation = 90
	waxGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UITheme.palette.waxLight),
		ColorSequenceKeypoint.new(1, UITheme.palette.waxDeep),
	})
	waxGradient.Parent = wax

	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.AnchorPoint = Vector2.new(0.5, 0)
	rim.Position = UDim2.fromScale(0.5, 0)
	rim.Size = UDim2.fromScale(1, 0.16)
	rim.BackgroundColor3 = UITheme.palette.gold
	rim.BackgroundTransparency = 0.3
	rim.BorderSizePixel = 0
	rim.ZIndex = 5
	rim.Parent = wax
	UITheme.corner(rim, math.floor(height * 0.04))

	local wick = Instance.new("Frame")
	wick.Name = "Wick"
	wick.AnchorPoint = Vector2.new(0.5, 1)
	wick.Position = UDim2.fromScale(0.5, 0.04)
	wick.Size = UDim2.fromOffset(math.max(2, height * 0.02), height * 0.06)
	wick.BackgroundColor3 = Color3.fromRGB(28, 20, 16)
	wick.BorderSizePixel = 0
	wick.ZIndex = 5
	wick.Parent = wax

	-- Flame, built as a teardrop so it reads as fire, not a pill: a rounded body carries a rotated
	-- square whose top corner is the point. Warm orange throughout — a deep-orange body with a bright
	-- amber core — rather than the old near-white centre.
	local pivot = Instance.new("Frame")
	pivot.Name = "FlamePivot"
	pivot.AnchorPoint = Vector2.new(0.5, 1)
	pivot.Position = UDim2.fromScale(0.5, 0.46)
	pivot.Size = UDim2.new(0, height * 0.22, 0.48, 0)
	pivot.BackgroundTransparency = 1
	pivot.ZIndex = 6
	pivot.Parent = box

	local pivotScale = UITheme.scale(pivot, 1)

	-- Outer body: the deep-orange bulk, rounded into a blob at the base.
	local outerBody = Instance.new("Frame")
	outerBody.Name = "FlameOuterBody"
	outerBody.AnchorPoint = Vector2.new(0.5, 1)
	outerBody.Position = UDim2.fromScale(0.5, 1)
	outerBody.Size = UDim2.fromScale(1, 0.66)
	outerBody.BackgroundColor3 = UITheme.palette.flameOuter
	outerBody.BorderSizePixel = 0
	outerBody.ZIndex = 6
	outerBody.Parent = pivot
	UITheme.corner(outerBody, math.floor(height * 0.11))

	local outerBodyGradient = Instance.new("UIGradient")
	outerBodyGradient.Rotation = 90
	outerBodyGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UITheme.palette.flameOuter),
		ColorSequenceKeypoint.new(1, UITheme.palette.ember),
	})
	outerBodyGradient.Parent = outerBody

	-- Outer tip: a rounded square rotated 45° — its top corner tapers the flame to a point.
	local outerTip = Instance.new("Frame")
	outerTip.Name = "FlameOuterTip"
	outerTip.AnchorPoint = Vector2.new(0.5, 0.5)
	outerTip.Position = UDim2.fromScale(0.5, 0.3)
	outerTip.Size = UDim2.fromOffset(height * 0.18, height * 0.18)
	outerTip.Rotation = 45
	outerTip.BackgroundColor3 = UITheme.palette.flameOuter
	outerTip.BorderSizePixel = 0
	outerTip.ZIndex = 6
	outerTip.Parent = pivot
	UITheme.corner(outerTip, math.floor(height * 0.05))

	-- Core body: the bright amber heart, lower and narrower.
	local coreBody = Instance.new("Frame")
	coreBody.Name = "FlameCoreBody"
	coreBody.AnchorPoint = Vector2.new(0.5, 1)
	coreBody.Position = UDim2.fromScale(0.5, 0.96)
	coreBody.Size = UDim2.fromScale(0.52, 0.5)
	coreBody.BackgroundColor3 = UITheme.palette.flameMid
	coreBody.BorderSizePixel = 0
	coreBody.ZIndex = 7
	coreBody.Parent = pivot
	UITheme.corner(coreBody, math.floor(height * 0.07))

	local coreTip = Instance.new("Frame")
	coreTip.Name = "FlameCoreTip"
	coreTip.AnchorPoint = Vector2.new(0.5, 0.5)
	coreTip.Position = UDim2.fromScale(0.5, 0.42)
	coreTip.Size = UDim2.fromOffset(height * 0.1, height * 0.1)
	coreTip.Rotation = 45
	coreTip.BackgroundColor3 = UITheme.palette.flameMid
	coreTip.BorderSizePixel = 0
	coreTip.ZIndex = 7
	coreTip.Parent = pivot
	UITheme.corner(coreTip, math.floor(height * 0.03))

	attachFlicker(box, pivot, pivotScale, glowInner, glowOuter, coreBody, 0.5, 0.46)

	return box
end

-- The WICK wordmark: the game's logo, composited in UI so it scales crisply and needs no uploaded
-- asset. W, C and K are set in the display face with a gilded gold→ember wash and a warm rim; the
-- "I" is a live candle (see `candleGlyph`) whose flame is the mark's focal light. `height` is the
-- cap height. Returns a content-sized frame the caller positions; center it and it reads as a logo.
-- `src/replicatedfirst/WickLoadingScreen.client.luau` duplicates this and `candleGlyph` inline
-- (ReplicatedFirst can't require ReplicatedStorage.Shared this early) — keep both in sync.
function UITheme.wordmark(parent: GuiObject, height: number): Frame
	local container = Instance.new("Frame")
	container.Name = "Wordmark"
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.X
	container.Size = UDim2.fromOffset(0, height)
	container.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, math.floor(height * 0.05))
	layout.Parent = container

	local function letter(char: string, order: number)
		local label = Instance.new("TextLabel")
		label.Name = "Letter_" .. char
		label.BackgroundTransparency = 1
		label.Font = UITheme.font.display
		label.Text = char
		label.TextColor3 = UITheme.palette.gold
		label.TextSize = height
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, height)
		label.LayoutOrder = order
		label.Parent = container

		local gild = Instance.new("UIGradient")
		gild.Rotation = 90
		gild.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UITheme.palette.flameCore),
			ColorSequenceKeypoint.new(0.45, UITheme.palette.gold),
			ColorSequenceKeypoint.new(1, UITheme.palette.ember),
		})
		gild.Parent = label

		-- Contextual (not Border) so the outline hugs the glyph shapes, never a rectangle around them.
		local outline = Instance.new("UIStroke")
		outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		outline.Color = UITheme.palette.emberDeep
		outline.Thickness = math.max(1, height * 0.03)
		outline.Transparency = 0.25
		outline.Parent = label
	end

	letter("W", 1)
	local candle = UITheme.candleGlyph(container, height)
	candle.LayoutOrder = 2
	letter("C", 3)
	letter("K", 4)
	return container
end

-- Panel entrance: a soft rise + settle from a hair below, scaled up from 0.94. Use on a panel that
-- has a UIScale (see `scale`). Mirrors the results/settings card reveal so every surface arrives the
-- same way. Pass the resting position/scale the panel should land on.
function UITheme.rise(target: GuiObject, targetScale: UIScale, restPosition: UDim2)
	target.Position = restPosition + UDim2.fromOffset(0, 22)
	targetScale.Scale = 0.94
	UITheme.tween(target, UITheme.motion.rise, { Position = restPosition })
	UITheme.tween(targetScale, UITheme.motion.rise, { Scale = 1 })
end

-- A one-shot warm flash used to acknowledge a click/commit (also reused by the hotbar on tool use):
-- snap to ember, then settle back to the resting colour. Sequenced so both stages are visible.
function UITheme.flash(target: GuiObject, restColor: Color3, stroke: UIStroke?)
	local up = TweenService:Create(target, UITheme.motion.press, { BackgroundColor3 = UITheme.palette.chipActive })
	up.Completed:Connect(function()
		TweenService:Create(target, UITheme.motion.settle, { BackgroundColor3 = restColor }):Play()
	end)
	up:Play()
	if stroke ~= nil then
		local restStroke = stroke.Color
		stroke.Transparency = 0
		stroke.Color = UITheme.palette.ember
		UITheme.tween(stroke, UITheme.motion.settle, { Transparency = 0.3, Color = restStroke })
	end
end

return UITheme

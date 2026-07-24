--!strict
-- Shared cave/candle look-and-feel for every menu surface. This is presentation only: colours,
-- fonts, and small builder/animation helpers so the lobby, results, Basin, and settings screens
-- read as one hand-lit game instead of grey-box primitives. No game rule lives here.
--
-- The whole palette is warm firelight against cold cave stone: near-black rock, bronze edges,
-- and amber/ember highlights that stand in for candlelight. Animations are deliberately small
-- (hover lifts, press dips, soft glows) — a professional menu breathes without shouting.

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
	-- Type.
	text = Color3.fromRGB(237, 227, 209),
	textMuted = Color3.fromRGB(163, 150, 135),
	textDim = Color3.fromRGB(112, 103, 96),
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

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 22
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

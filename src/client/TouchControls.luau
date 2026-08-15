--!strict
-- Every on-screen action button a touch player has, in one cluster this game owns.
--
-- WHY THIS FILE EXISTS. ContextActionService's native touch buttons are laid out inside an
-- engine-owned frame whose origin and size this game does not control, and every caller was
-- guessing at that geometry in its own convention: the tools asked for `UDim2.new(0, 62, 1, -142)`,
-- mining asked for `UDim2.new(1, -150, 1, -230)`. On a phone those guesses landed on top of one
-- another and on top of Roblox's own jump button, so the right-hand side of the screen was a pile
-- of overlapping circles reading "FLAR", "STO" and "DECO" with no reliable way to press any of them.
--
-- Owning the buttons is what makes the layout knowable: one cluster, one grid, sized from the
-- viewport and placed clear of the two corners Roblox already owns — the movement thumbstick
-- bottom-left and the jump button bottom-right. Callers name an action and a label; a caller never
-- names a position, because a position is only correct relative to every other button on screen and
-- no single caller can see those.
--
-- This module owns presentation and hit-testing only. The bindings, the rules, and every refusal
-- stay with the controller that registered the action.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(script.Parent.UITheme)

local TouchControls = {}

local player = Players.LocalPlayer
local palette = UITheme.palette

-- Roblox's TouchJump drops to a smaller jump button at or below this viewport height. Matching the
-- threshold keeps this cluster in proportion with the one control it has to sit beside.
local SMALL_SCREEN_HEIGHT = 500
local SMALL_JUMP_SIZE = 70
local JUMP_SIZE = 120

-- A touch target below roughly this many pixels is a target players miss. Everything here is
-- allowed to shrink with the screen right up to this floor and no further; past it the grid wraps
-- to a second line instead, because an unpressable button is worse than a taller cluster.
local MIN_TARGET_PIXELS = 46
local MAX_TARGET_PIXELS = 96

export type Row = "primary" | "tool"

export type Registration = {
	id: string,
	label: string,
	row: Row,
	order: number,
	activated: () -> (),
}

type Entry = {
	id: string,
	row: Row,
	order: number,
	baseLabel: string,
	button: TextButton,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	cooldownTrack: Frame,
	cooldownFill: Frame,
	cooldownLabel: TextLabel,
	active: boolean,
	wanted: boolean,
	flashToken: number,
}

local gui: ScreenGui? = nil
local root: Frame? = nil
local rowFrames: { [Row]: Frame } = {}
local rowGrids: { [Row]: UIGridLayout } = {}
local entries: { [string]: Entry } = {}
local started = false
-- Whether the touch cluster should currently be on screen at all. A tablet or a touchscreen laptop
-- has both a keyboard and a digitiser, and showing thumb buttons to somebody using the keys is the
-- same mistake in the other direction; the last input type decides, exactly as the hotbar legend does.
local layoutActive = false

local function isTouchLayout(inputType: Enum.UserInputType): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	if not UserInputService.KeyboardEnabled then
		return true
	end
	return inputType == Enum.UserInputType.Touch
end

function TouchControls.available(): boolean
	return UserInputService.TouchEnabled
end

-- The reserved corners, in the viewport's own pixels.
--
-- TouchJump sizes its button 70 on a short screen and 120 otherwise, and anchors it at
-- `(1, -(size * 1.5 - 10), 1, -size - 20)`. Reserving `size * 1.5` plus a margin from the right edge
-- therefore clears it on any device without this file having to find the instance. The thumbstick
-- owns the opposite corner and is bounded the same way rather than measured.
local function reservations(viewport: Vector2): (number, number, number)
	local jump = if viewport.Y <= SMALL_SCREEN_HEIGHT then SMALL_JUMP_SIZE else JUMP_SIZE
	local right = jump * 1.5 + 16
	local left = math.min(viewport.X * 0.34, jump * 2.6)
	return jump, right, left
end

local function applyLayout()
	local screen = gui
	local container = root
	local tools = rowGrids.tool
	local primary = rowGrids.primary
	if screen == nil or container == nil or tools == nil or primary == nil then
		return
	end
	local viewport = screen.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local jump, rightReserve, leftReserve = reservations(viewport)
	-- Targets track the jump button, which is the one control on screen Roblox has already sized for
	-- a thumb on this exact device.
	local unit = math.clamp(jump * 0.78, MIN_TARGET_PIXELS, MAX_TARGET_PIXELS)
	local gap = math.max(6, math.floor(unit * 0.14))
	local toolWidth = math.clamp(unit * 1.5, 64, 132)

	container.Position = UDim2.new(1, -rightReserve, 1, -math.max(12, math.floor(unit * 0.2)))

	-- How many tool buttons fit on one line between the thumbstick and the jump button. Below two the
	-- cluster would be a column tall enough to reach the top of the screen, so two is the floor and a
	-- genuinely tiny screen accepts a slightly narrower gap instead.
	local available = math.max(viewport.X - rightReserve - leftReserve, toolWidth)
	local perRow = math.max(2, math.floor((available + gap) / (toolWidth + gap)))

	tools.CellSize = UDim2.fromOffset(toolWidth, unit)
	tools.CellPadding = UDim2.fromOffset(gap, gap)
	tools.FillDirectionMaxCells = perRow

	-- The primary row is MINE / STOP: fewer, wider, and closer to the resting thumb than a tool.
	primary.CellSize = UDim2.fromOffset(math.min(toolWidth * 1.6, available), math.floor(unit * 0.82))
	primary.CellPadding = UDim2.fromOffset(gap, gap)
	primary.FillDirectionMaxCells = math.max(1, math.floor((available + gap) / (toolWidth * 1.6 + gap)))
end

local function refreshVisibility()
	local container = root
	if container == nil then
		return
	end
	container.Visible = layoutActive
end

local function buildRow(parent: Frame, row: Row, order: number)
	local frame = Instance.new("Frame")
	frame.Name = if row == "primary" then "PrimaryRow" else "ToolRow"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	frame.Parent = parent

	local grid = Instance.new("UIGridLayout")
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellSize = UDim2.fromOffset(72, 56)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.Parent = frame

	rowFrames[row] = frame
	rowGrids[row] = grid
end

function TouchControls.start()
	if started or not UserInputService.TouchEnabled then
		started = true
		return
	end
	started = true

	local screen = Instance.new("ScreenGui")
	screen.Name = "WickTouchControls"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above the hotbar legend and the mining HUD, below any full-screen modal: these are controls, and
	-- a control that a results card or the shop can bury is a control that traps the player.
	screen.DisplayOrder = 12

	local container = Instance.new("Frame")
	container.Name = "Cluster"
	container.AnchorPoint = Vector2.new(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.AutomaticSize = Enum.AutomaticSize.XY
	container.Size = UDim2.fromOffset(0, 0)
	container.Visible = false
	container.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container

	root = container
	buildRow(container, "primary", 1)
	buildRow(container, "tool", 2)

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	layoutActive = isTouchLayout(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		layoutActive = isTouchLayout(inputType)
		refreshVisibility()
	end)
	refreshVisibility()
	applyLayout()
end

function TouchControls.register(registration: Registration)
	if not UserInputService.TouchEnabled then
		return
	end
	local existing = entries[registration.id]
	if existing ~= nil then
		-- A re-register is a rebind after a floor or a run, not a second button. Keep the instance and
		-- reset it to its resting state so no cooldown or denial survives into the new expedition.
		existing.baseLabel = registration.label
		existing.label.Text = registration.label
		existing.order = registration.order
		existing.button.LayoutOrder = registration.order
		TouchControls.setActive(registration.id, false)
		TouchControls.setCooldown(registration.id, 0, nil)
		return
	end
	local parent = rowFrames[registration.row]
	if parent == nil then
		return
	end

	local button = Instance.new("TextButton")
	button.Name = registration.id
	button.AutoButtonColor = false
	button.BackgroundColor3 = palette.chip
	button.BackgroundTransparency = 0.06
	button.BorderSizePixel = 0
	button.LayoutOrder = registration.order
	button.Text = ""
	button.Visible = false
	button.Parent = parent
	UITheme.corner(button, 12)
	local stroke = UITheme.stroke(button, palette.strokeSoft, 1.5, 0.2)
	local scale = UITheme.scale(button, 1)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.44)
	label.Size = UDim2.new(1, -12, 1, -18)
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.heading
	label.Text = registration.label
	label.TextColor3 = palette.gold
	label.TextScaled = true
	label.TextWrapped = true
	label.ZIndex = 2
	label.Parent = button
	UITheme.legible(label, 0.6)
	-- A tool name has to survive a phone in the dark. It may shrink to fit a narrow button, but the
	-- floor is a size a player can still read at arm's length rather than whatever fills the box.
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 12
	constraint.MaxTextSize = UITheme.textSize.strong
	constraint.Parent = label

	local cooldownTrack = Instance.new("Frame")
	cooldownTrack.Name = "Cooldown"
	cooldownTrack.AnchorPoint = Vector2.new(0.5, 1)
	cooldownTrack.Position = UDim2.new(0.5, 0, 1, -6)
	cooldownTrack.Size = UDim2.new(1, -16, 0, 4)
	cooldownTrack.BackgroundColor3 = palette.void
	cooldownTrack.BackgroundTransparency = 0.15
	cooldownTrack.BorderSizePixel = 0
	cooldownTrack.ClipsDescendants = true
	cooldownTrack.Visible = false
	cooldownTrack.ZIndex = 3
	cooldownTrack.Parent = button
	UITheme.corner(cooldownTrack, 2)

	local cooldownFill = Instance.new("Frame")
	cooldownFill.Name = "Remaining"
	cooldownFill.BackgroundColor3 = palette.ember
	cooldownFill.BorderSizePixel = 0
	cooldownFill.Size = UDim2.fromScale(1, 1)
	cooldownFill.ZIndex = 4
	cooldownFill.Parent = cooldownTrack

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "Seconds"
	cooldownLabel.AnchorPoint = Vector2.new(0.5, 1)
	cooldownLabel.Position = UDim2.new(0.5, 0, 1, -12)
	cooldownLabel.Size = UDim2.new(1, -12, 0, 14)
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Font = UITheme.font.heading
	cooldownLabel.Text = ""
	cooldownLabel.TextColor3 = palette.text
	cooldownLabel.TextSize = UITheme.textSize.micro
	cooldownLabel.Visible = false
	cooldownLabel.ZIndex = 4
	cooldownLabel.Parent = button
	UITheme.legible(cooldownLabel, 0.7)

	local entry: Entry = {
		id = registration.id,
		row = registration.row,
		order = registration.order,
		baseLabel = registration.label,
		button = button,
		label = label,
		stroke = stroke,
		scale = scale,
		cooldownTrack = cooldownTrack,
		cooldownFill = cooldownFill,
		cooldownLabel = cooldownLabel,
		active = false,
		wanted = false,
		flashToken = 0,
	}
	entries[registration.id] = entry

	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, UITheme.motion.press, { Scale = 0.94 }):Play()
	end)
	local function release()
		TweenService:Create(scale, UITheme.motion.settle, { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(registration.activated)

	applyLayout()
end

function TouchControls.unregister(id: string)
	local entry = entries[id]
	if entry == nil then
		return
	end
	entries[id] = nil
	entry.button:Destroy()
end

function TouchControls.setVisible(id: string, visible: boolean)
	local entry = entries[id]
	if entry == nil or entry.wanted == visible then
		return
	end
	entry.wanted = visible
	entry.button.Visible = visible
end

function TouchControls.setLabel(id: string, text: string)
	local entry = entries[id]
	if entry == nil then
		return
	end
	entry.label.Text = text
end

local function restColor(entry: Entry): Color3
	return if entry.active then palette.chipActive else palette.chip
end

function TouchControls.setActive(id: string, active: boolean)
	local entry = entries[id]
	if entry == nil or entry.active == active then
		return
	end
	entry.active = active
	entry.button.BackgroundColor3 = restColor(entry)
	entry.stroke.Color = if active then palette.ember else palette.strokeSoft
end

-- `fraction` is how much of the cooldown remains (1 -> just fired, 0 -> ready). A nil `text` hides
-- the numeric readout, which is what a cooldown of zero means.
function TouchControls.setCooldown(id: string, fraction: number, text: string?)
	local entry = entries[id]
	if entry == nil then
		return
	end
	local showing = text ~= nil and fraction > 0
	entry.cooldownTrack.Visible = showing
	entry.cooldownLabel.Visible = showing
	if showing then
		entry.cooldownFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		entry.cooldownLabel.Text = text :: string
	end
end

-- One warm (or red) acknowledgement that the tap was heard, matching the hotbar chip's flash so a
-- touch player and a desktop player are told the same thing in the same colour.
function TouchControls.flash(id: string, color: Color3, seconds: number)
	local entry = entries[id]
	if entry == nil then
		return
	end
	entry.flashToken += 1
	local token = entry.flashToken
	entry.button.BackgroundColor3 = color
	entry.stroke.Transparency = 0
	local tween = TweenService:Create(entry.button, TweenInfo.new(seconds), { BackgroundColor3 = restColor(entry) })
	tween:Play()
	TweenService:Create(entry.stroke, TweenInfo.new(seconds), { Transparency = 0.2 }):Play()
	tween.Completed:Connect(function()
		if entry.flashToken == token then
			entry.button.BackgroundColor3 = restColor(entry)
		end
	end)
end

return TouchControls

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
-- It also owns the one control that is not a button: the MINING TAP FIELD, the open region of screen
-- a touch player taps to swing. That belongs here for the same reason the buttons do — where it may
-- sit is decided by every other control on the screen, and only this module can see them all.
--
-- This module owns presentation and hit-testing only. The bindings, the rules, and every refusal
-- stay with the controller that registered the action.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TouchLayoutRules = require(ReplicatedStorage.Shared.Logic.TouchLayoutRules)
local UITheme = require(script.Parent.UITheme)

local TouchControls = {}

local player = Players.LocalPlayer
local palette = UITheme.palette

-- The tap field's outline is an affordance, not a frame: it says "here" and then gets out of the way
-- of a cave the player is straining to see into. It brightens for one beat when a tap lands so a
-- swallowed tap and a heard one never look the same.
local FIELD_RESTING_TRANSPARENCY = 0.88
local FIELD_TAP_TRANSPARENCY = 0.6
local FIELD_TAP_SECONDS = 0.18

export type Row = "primary" | "tool"

export type Registration = {
	id: string,
	label: string,
	row: Row,
	order: number,
	activated: () -> (),
}

-- A REGION RATHER THAN A BUTTON, and deliberately not a transparent TextButton covering the screen.
-- A full-screen button consumes every touch that lands on it, which on a phone is how a player looks
-- around; installing one would trade a small mining button for a camera that no longer turns. So the
-- field is an inert Frame drawn where taps count, and the taps themselves are read from
-- UserInputService, where a camera drag stays a camera drag.
export type FieldRegistration = {
	id: string,
	activated: () -> (),
}

type Field = {
	id: string,
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
local fieldFrame: Frame? = nil
local fieldStroke: UIStroke? = nil
local fields: { [string]: Field } = {}
-- At most one field is armed at a time. Two overlapping "tap here" regions would be two answers to
-- the same tap, and nothing in this game has ever needed a second one.
local activeFieldId: string? = nil
-- Whatever is currently moving the outline's transparency, so a tap landing mid-fade — or the field
-- disarming mid-flash — cancels the older motion instead of racing it to a different resting value.
local fieldTween: Tween? = nil
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

-- Where the cluster and the tap field go, from shared/Logic/TouchLayoutRules. The arithmetic used to
-- be inline here; it moved so the suite could state what a given viewport is owed, and so the tap
-- field and the buttons could not drift apart into overlapping answers.
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

	local metrics = TouchLayoutRules.cluster(viewport.X, viewport.Y)
	container.Position = UDim2.new(1, -metrics.rightReservePixels, 1, -metrics.bottomMarginPixels)

	tools.CellSize = UDim2.fromOffset(metrics.toolWidthPixels, metrics.toolHeightPixels)
	tools.CellPadding = UDim2.fromOffset(metrics.gapPixels, metrics.gapPixels)
	tools.FillDirectionMaxCells = metrics.toolsPerRow

	-- The primary row is STOP and LIGHT: fewer, wider, and closer to the resting thumb than a tool.
	primary.CellSize = UDim2.fromOffset(metrics.primaryWidthPixels, metrics.primaryHeightPixels)
	primary.CellPadding = UDim2.fromOffset(metrics.gapPixels, metrics.gapPixels)
	primary.FillDirectionMaxCells = metrics.primaryPerRow

	local region = fieldFrame
	if region ~= nil then
		local area = TouchLayoutRules.tapField(viewport.X, viewport.Y, GuiService:GetGuiInset().Y)
		region.Position = UDim2.fromOffset(area.leftPixels, area.topPixels)
		region.Size = UDim2.fromOffset(area.widthPixels, area.heightPixels)
	end
end

local function moveOutline(outline: UIStroke, info: TweenInfo, transparency: number)
	local previous = fieldTween
	if previous ~= nil then
		previous:Cancel()
	end
	local tween = TweenService:Create(outline, info, { Transparency = transparency })
	fieldTween = tween
	tween:Play()
end

local function refreshFieldVisibility()
	local region = fieldFrame
	local outline = fieldStroke
	if region == nil or outline == nil then
		return
	end
	local showing = layoutActive and activeFieldId ~= nil
	region.Visible = showing
	if showing then
		outline.Transparency = 1
		moveOutline(outline, UITheme.motion.fade, FIELD_RESTING_TRANSPARENCY)
	else
		local previous = fieldTween
		if previous ~= nil then
			previous:Cancel()
			fieldTween = nil
		end
		outline.Transparency = 1
	end
end

local function refreshVisibility()
	local container = root
	if container == nil then
		return
	end
	container.Visible = layoutActive
	refreshFieldVisibility()
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

local function buildField(parent: ScreenGui)
	local region = Instance.new("Frame")
	region.Name = "TapField"
	region.BackgroundTransparency = 1
	region.BorderSizePixel = 0
	-- INERT ON PURPOSE. `Active` false and a transparent background together mean this frame is not a
	-- GUI hit target at all, so a finger that lands on it still reaches the camera and still reports
	-- `gameProcessed == false` to the handler below. It is a drawing, and nothing else.
	region.Active = false
	region.Selectable = false
	region.Visible = false
	region.Parent = parent
	UITheme.corner(region, 18)

	local outline = UITheme.stroke(region, palette.ember, 1.5, 1)
	fieldFrame = region
	fieldStroke = outline
end

-- One tap heard, acknowledged where the finger landed. The controller decides whether the tap did
-- anything; this only says the field caught it, which is the difference between a game that ignored
-- you and a game that refused you.
local function flashField()
	local outline = fieldStroke
	if outline == nil then
		return
	end
	outline.Transparency = FIELD_TAP_TRANSPARENCY
	moveOutline(outline, TweenInfo.new(FIELD_TAP_SECONDS), FIELD_RESTING_TRANSPARENCY)
end

-- FIRES ON TOUCH-DOWN, NOT ON RELEASE. Mining is a quick-time event scored against a sweeping marker
-- (Config/Mining timing), and the gap between a finger landing and a finger lifting is longer than
-- the perfect aperture is wide; waiting for the lift would score the player on their release reflex
-- instead of their read. The cost is that a camera drag begun inside the field also swings, which is
-- why the field stops short of the screen edges: the margins are where looking around lives.
local function onTouchBegan(input: InputObject, processed: boolean)
	if processed or not layoutActive then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local id = activeFieldId
	local region = fieldFrame
	if id == nil or region == nil or not region.Visible then
		return
	end
	local field = fields[id]
	if field == nil then
		return
	end
	-- Hit-tested against the frame the player can see rather than against recomputed arithmetic, so
	-- the region that answers is by construction the region that was drawn.
	local origin = region.AbsolutePosition
	local size = region.AbsoluteSize
	local position = input.Position
	if
		position.X < origin.X
		or position.X > origin.X + size.X
		or position.Y < origin.Y
		or position.Y > origin.Y + size.Y
	then
		return
	end
	flashField()
	field.activated()
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
	buildField(screen)

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	layoutActive = isTouchLayout(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		layoutActive = isTouchLayout(inputType)
		refreshVisibility()
	end)
	UserInputService.InputBegan:Connect(onTouchBegan)
	-- The topbar's height decides where the field's ceiling is, and it changes when Roblox reflows its
	-- own controls rather than when the viewport resizes.
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(applyLayout)
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

function TouchControls.registerField(registration: FieldRegistration)
	if not UserInputService.TouchEnabled then
		return
	end
	fields[registration.id] = {
		id = registration.id,
		activated = registration.activated,
	}
end

-- Arming a field disarms whichever one was armed before it, because a tap has one meaning at a time.
-- Disarming is only honoured from the field that currently holds the screen, so a controller tidying
-- up after itself cannot take the region away from the one that has since claimed it.
function TouchControls.setFieldVisible(id: string, visible: boolean)
	if fields[id] == nil then
		return
	end
	if visible then
		-- Called every frame by the mining update loop, so a no-op has to stay a no-op: re-arming an
		-- already-armed field would restart its fade on every frame and leave the outline stuck mid-tween.
		if activeFieldId == id then
			return
		end
		activeFieldId = id
	elseif activeFieldId == id then
		activeFieldId = nil
	else
		return
	end
	refreshFieldVisibility()
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

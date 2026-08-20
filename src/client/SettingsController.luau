--!strict
-- Local settings menu for the Landing and an active run. It deliberately affects only client
-- presentation/input; game rules stay server-authoritative. M toggles it; Roblox's native Escape
-- menu stays available. Music and ambience sliders are client-local mix controls, and the camera
-- motion row is a client-local accessibility control read by client/CameraMotionController.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AudioCues = require(script.Parent.AudioCues)
local CameraMotionController = require(script.Parent.CameraMotionController)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local TouchLayoutRules = require(ReplicatedStorage.Shared.Logic.TouchLayoutRules)

local SettingsController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local SHOP_OPEN_ATTRIBUTE = "WickShopOpen"
local MIN_SENSITIVITY = 0.2
local MAX_SENSITIVITY = 3
local SENSITIVITY_STEP = 0.2
local VOLUME_STEP = 0.25

local panel: CanvasGroup? = nil
local panelScale: UIScale? = nil
local screenGui: ScreenGui? = nil
local openButton: TextButton? = nil
local openGlyph: Frame? = nil
local sensitivityLabel: TextLabel? = nil
local volumeLabel: TextLabel? = nil
local musicLabel: TextLabel? = nil
local musicFill: Frame? = nil
local musicTrack: TextButton? = nil
local ambienceLabel: TextLabel? = nil
local ambienceFill: Frame? = nil
local ambienceTrack: TextButton? = nil
local motionLabel: TextLabel? = nil
local audioVolume = 1
local runActive = false
-- WHICH FINGER IS ON WHICH SLIDER, or nil for neither. These were two booleans, and every
-- `InputChanged` that arrived while one was set moved that slider — so a second finger anywhere on a
-- phone, including the one walking the character, dragged the music volume with it. Holding the
-- InputObject means a slider only follows the finger that started on it.
local musicDragInput: InputObject? = nil
local ambienceDragInput: InputObject? = nil

local function expeditionActive(): boolean
	return player:GetAttribute(EXPEDITION_ATTRIBUTE) == true
end

local function menuAvailable(): boolean
	if not expeditionActive() then
		return player:GetAttribute(SHOP_OPEN_ATTRIBUTE) ~= true
	end
	return runActive
end

local function refreshLabels()
	if sensitivityLabel ~= nil then
		sensitivityLabel.Text = string.format("SENSITIVITY   %.1f", UserInputService.MouseDeltaSensitivity)
	end
	if volumeLabel ~= nil then
		volumeLabel.Text = string.format("LOCAL AUDIO   %d%%", math.floor(audioVolume * 100 + 0.5))
	end
	local musicVolume = AudioCues.getBusVolumeMultiplier("Music")
	if musicLabel ~= nil then
		musicLabel.Text = string.format("MUSIC   %d%%", math.floor(musicVolume * 100 + 0.5))
	end
	if musicFill ~= nil then
		musicFill.Size = UDim2.fromScale(musicVolume, 1)
	end
	local ambienceVolume = AudioCues.getBusVolumeMultiplier("Ambience")
	if ambienceLabel ~= nil then
		ambienceLabel.Text = string.format("AMBIENCE   %d%%", math.floor(ambienceVolume * 100 + 0.5))
	end
	if ambienceFill ~= nil then
		ambienceFill.Size = UDim2.fromScale(ambienceVolume, 1)
	end
	if motionLabel ~= nil then
		motionLabel.Text = string.format("CAMERA MOTION   %s", CameraMotionController.levelLabel())
	end
end

local function setMusicVolume(value: number)
	AudioCues.setBusVolumeMultiplier("Music", math.clamp(value, Config.Audio.settings.musicMinMultiplier, 1))
	refreshLabels()
end

local function setMusicVolumeFromScreenX(screenX: number)
	local track = musicTrack
	if track == nil or track.AbsoluteSize.X <= 0 then
		return
	end
	setMusicVolume(math.clamp((screenX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1))
end

-- A SLIDER MUST BE AUDIBLE WHILE YOU MOVE IT, and neither music slider nor ambience slider needs help
-- underground: menu music plays throughout the lobby menu, and the cave playlist rides the ambience
-- bus, so during a run both controls demonstrate themselves on the sound already in the player's ears.
--
-- The lobby is the gap. Nothing routes to the ambience bus up there — the cave director only runs
-- inside an expedition — so the ambience slider moves against silence and reads as a dead control.
-- This plays one sample through the ambience bus itself, so what the player hears IS the setting, and
-- only in the case that needs it: firing it over a playing track would be noise, not feedback.
local lastAmbiencePreviewAt = -math.huge

local function previewAmbience(force: boolean)
	if expeditionActive() then
		return
	end
	local settings = Config.Audio.settings
	local now = os.clock()
	if not force and now - lastAmbiencePreviewAt < settings.ambiencePreviewIntervalSeconds then
		return
	end
	lastAmbiencePreviewAt = now
	AudioCues.play(settings.ambiencePreviewCue)
end

local function setAmbienceVolume(value: number)
	AudioCues.setBusVolumeMultiplier("Ambience", math.clamp(value, Config.Audio.settings.ambienceMinMultiplier, 1))
	refreshLabels()
	previewAmbience(false)
end

local function setAmbienceVolumeFromScreenX(screenX: number)
	local track = ambienceTrack
	if track == nil or track.AbsoluteSize.X <= 0 then
		return
	end
	setAmbienceVolume(math.clamp((screenX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1))
end

-- A [-]  label value  [+] stepper row.
local function controlRow(parent: Instance, order: number, onDown: () -> (), onUp: () -> ()): TextLabel
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 44)
	row.LayoutOrder = order
	row.Parent = parent

	local minus = UITheme.button(row, "-")
	minus.instance.AnchorPoint = Vector2.new(0, 0.5)
	minus.instance.Position = UDim2.fromScale(0, 0.5)
	minus.instance.Size = UDim2.fromOffset(48, 44)
	minus.instance.Activated:Connect(function()
		onDown()
		refreshLabels()
	end)

	local plus = UITheme.button(row, "+")
	plus.instance.AnchorPoint = Vector2.new(1, 0.5)
	plus.instance.Position = UDim2.fromScale(1, 0.5)
	plus.instance.Size = UDim2.fromOffset(48, 44)
	plus.instance.Activated:Connect(function()
		onUp()
		refreshLabels()
	end)

	local value = Instance.new("TextLabel")
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.fromScale(0.5, 0.5)
	value.Size = UDim2.new(1, -112, 1, 0)
	value.BackgroundColor3 = palette.panelRaised
	value.BackgroundTransparency = 0.2
	value.Font = UITheme.font.body
	value.TextColor3 = palette.text
	value.TextScaled = true
	value.Text = ""
	value.Parent = row
	UITheme.corner(value, 8)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = UITheme.textSize.fine
	constraint.MaxTextSize = UITheme.textSize.strong
	constraint.Parent = value
	return value
end

local function audioSliderRow(
	parent: Instance,
	name: string,
	order: number,
	onBeginDrag: (InputObject) -> ()
): (TextLabel, Frame, TextButton)
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 54)
	row.LayoutOrder = order
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Font = UITheme.font.body
	label.TextColor3 = palette.text
	label.TextSize = UITheme.textSize.body
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = row

	local track = Instance.new("TextButton")
	track.Name = "Slider"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 0, 1, 0)
	track.Size = UDim2.new(1, 0, 0, 20)
	track.BackgroundColor3 = palette.panelRaised
	track.BackgroundTransparency = 0.1
	track.BorderSizePixel = 0
	track.AutoButtonColor = false
	track.Text = ""
	track.ClipsDescendants = true
	track.Parent = row
	UITheme.corner(track, 7)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = palette.gold
	fill.BackgroundTransparency = 0.1
	fill.BorderSizePixel = 0
	fill.Parent = track
	UITheme.corner(fill, 7)

	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		-- The whole InputObject, not just its X: the caller has to remember which finger this was, or
		-- every other finger on the screen will keep moving this slider.
		onBeginDrag(input)
	end)

	return label, fill, track
end

-- Whether `input` is the movement belonging to a drag started by `owner`. A touch is matched by
-- identity, since the engine reuses one InputObject for a finger's whole life; a held mouse button
-- reports its movement as a separate MouseMovement object, so that pairing is matched by type.
local function ownsMovement(owner: InputObject?, input: InputObject): boolean
	if owner == nil then
		return false
	end
	if owner.UserInputType == Enum.UserInputType.Touch then
		return input == owner
	end
	return input.UserInputType == Enum.UserInputType.MouseMovement
end

local function ownsRelease(owner: InputObject?, input: InputObject): boolean
	if owner == nil then
		return false
	end
	if owner.UserInputType == Enum.UserInputType.Touch then
		return input == owner
	end
	return input.UserInputType == owner.UserInputType
end

local function touchLayout(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	if not UserInputService.KeyboardEnabled then
		return true
	end
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- The card holds eight rows and a heading — around 480 units of content. A phone viewport is roughly
-- 410 units TALL in total, so the authored `0.7` scale left RESUME below the bottom edge of the
-- screen with no way to reach it, which is the same class of bug as the update log's missing close
-- button. The panel is clamped to the viewport and its body scrolls, so the rows that do not fit are
-- reachable rather than absent.
local function applyLayout()
	local screen = screenGui
	local group = panel
	local scale = panelScale
	if screen == nil or group == nil or scale == nil then
		return
	end
	local viewport = screen.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	local density = UITheme.density()
	scale.Scale = density
	local availableX = viewport.X / density
	local availableY = viewport.Y / density
	local margin = if availableX < 480 then 12 else 28
	-- Wider floor on touch: every row here is a slider or a pair of steppers, and they need width to
	-- stay hittable once the panel stops being able to have height.
	local minWidth = if touchLayout() then 320 else 300
	local width = math.min(math.max(availableX * 0.34, minWidth), math.max(availableX - margin * 2, 240))
	local height = math.min(math.max(availableY * 0.7, 260), math.max(availableY - margin * 2, 220))
	group.Size = UDim2.fromOffset(width, height)
end

-- The MENU button used to sit at `(0.02, 0.96)` — the bottom-left corner, which on a phone is exactly
-- where Roblox puts the movement thumbstick. It was drawn straight on top of it, so opening the menu
-- and walking left were the same tap. On touch it moves to the top-right, the one corner neither the
-- topbar, the thumbstick, the jump button nor the touch cluster claims.
--
-- IT IS NOW A GLYPH, NOT A WORD. At 112x48 with "MENU" set across it, the loudest thing in the top
-- half of a phone screen was a settings button — in a game whose subject is a dark cave you are
-- straining to see into. A square with three bars is the one control convention every phone player
-- already reads without being told, and it costs a fifth of the area. The word stays on desktop,
-- where it also has to name the key that does the same thing.
local function applyOpenButtonLayout()
	local button = openButton
	local glyph = openGlyph
	if button == nil or glyph == nil then
		return
	end
	if not touchLayout() then
		button.AnchorPoint = Vector2.new(0, 1)
		button.Position = UDim2.fromScale(0.02, 0.96)
		button.Size = UDim2.fromOffset(132, 40)
		button.Text = "MENU  ·  M"
		glyph.Visible = false
		return
	end
	-- This ScreenGui ignores the GUI inset, so the topbar's height has to be added back by hand or the
	-- button lands underneath Roblox's own chat and menu controls.
	local screen = screenGui
	local viewport = if screen ~= nil then screen.AbsoluteSize else Vector2.new(1280, 720)
	local inset = GuiService:GetGuiInset()
	local size = TouchLayoutRules.menuPixels(math.max(viewport.X, 1), math.max(viewport.Y, 1))
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -12, 0, inset.Y + 8)
	button.Size = UDim2.fromOffset(size, size)
	button.Text = ""
	glyph.Visible = true
end

local function setOpen(open: boolean)
	local group = panel
	local scale = panelScale
	if group == nil or scale == nil then
		return
	end
	local allowed = open and menuAvailable()
	CursorController.setReleased("Settings", allowed)
	if allowed then
		applyLayout()
		group.Visible = true
		group.GroupTransparency = 1
		scale.Scale = 0.94
		refreshLabels()
		TweenService:Create(group, UITheme.motion.fade, { GroupTransparency = 0 }):Play()
		TweenService:Create(scale, UITheme.motion.rise, { Scale = 1 }):Play()
	else
		group.Visible = false
		-- A slider whose panel closed under it keeps no claim on the finger. Without this, closing the
		-- menu mid-drag leaves the volume following a thumb that has gone back to walking.
		musicDragInput = nil
		ambienceDragInput = nil
	end
end

local function refreshOpenButton()
	if openButton ~= nil then
		openButton.Visible = menuAvailable()
	end
end

local function toggle()
	local group = panel
	if group ~= nil then
		setOpen(not group.Visible)
	end
end

function SettingsController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickSettings"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.IgnoreGuiInset = true

	local open = UITheme.button(gui, "MENU  ·  M")
	open.instance.Name = "OpenMenu"
	open.instance.AnchorPoint = Vector2.new(0, 1)
	open.instance.Position = UDim2.fromScale(0.02, 0.96)
	open.instance.Size = UDim2.fromOffset(132, 40)
	open.instance.Visible = false
	open.instance.Activated:Connect(toggle)
	openButton = open.instance

	-- Three bars, drawn rather than typed. A "≡" would depend on the glyph existing in whichever font
	-- fallback the device picks, and a missing glyph is a blank button in the corner with no way for a
	-- player to guess what it was. Sized in scale so it follows the square whatever the viewport is.
	local glyph = Instance.new("Frame")
	glyph.Name = "Bars"
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.46, 0.36)
	glyph.BackgroundTransparency = 1
	glyph.BorderSizePixel = 0
	glyph.Visible = false
	glyph.Parent = open.instance
	for index = 0, 2 do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. index
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, index * 0.5)
		bar.Size = UDim2.new(1, 0, 0, 2)
		bar.BackgroundColor3 = palette.gold
		bar.BorderSizePixel = 0
		bar.Parent = glyph
		UITheme.corner(bar, 1)
	end
	openGlyph = glyph

	local group = Instance.new("CanvasGroup")
	group.Name = "Panel"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromScale(0.32, 0.7)
	group.BackgroundColor3 = palette.panel
	group.BackgroundTransparency = 0.02
	group.BorderSizePixel = 0
	group.Visible = false
	group.Parent = gui
	UITheme.corner(group, 16)
	UITheme.stroke(group, palette.stroke, 1.5, 0.3)
	panel = group
	panelScale = UITheme.scale(group, 1)

	-- The rows live in a scroller inside the card rather than directly in it. The CanvasGroup stays the
	-- thing that fades as one surface; the scroller is what lets a short screen still reach RESUME.
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 5
	body.ScrollBarImageColor3 = palette.stroke
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.CanvasSize = UDim2.new()
	body.Parent = group
	UITheme.uniformPadding(body, 24)
	UITheme.listLayout(body, 12)

	local heading = UITheme.heading(body, "SETTINGS")
	heading.Size = UDim2.new(1, 0, 0, 42)
	heading.LayoutOrder = 1

	local note = UITheme.label(body, "Your mouse is freed while this menu is open.", 26)
	note.Font = UITheme.font.fine
	note.TextColor3 = palette.textMuted
	note.LayoutOrder = 2

	sensitivityLabel = controlRow(body, 3, function()
		UserInputService.MouseDeltaSensitivity =
			math.max(MIN_SENSITIVITY, UserInputService.MouseDeltaSensitivity - SENSITIVITY_STEP)
	end, function()
		UserInputService.MouseDeltaSensitivity =
			math.min(MAX_SENSITIVITY, UserInputService.MouseDeltaSensitivity + SENSITIVITY_STEP)
	end)

	volumeLabel = controlRow(body, 4, function()
		audioVolume = math.max(0, audioVolume - VOLUME_STEP)
		AudioCues.setVolumeMultiplier(audioVolume)
	end, function()
		audioVolume = math.min(1, audioVolume + VOLUME_STEP)
		AudioCues.setVolumeMultiplier(audioVolume)
	end)

	musicLabel, musicFill, musicTrack = audioSliderRow(body, "Music", 5, function(input: InputObject)
		musicDragInput = input
		setMusicVolumeFromScreenX(input.Position.X)
	end)
	ambienceLabel, ambienceFill, ambienceTrack = audioSliderRow(body, "Ambience", 6, function(input: InputObject)
		ambienceDragInput = input
		setAmbienceVolumeFromScreenX(input.Position.X)
	end)

	-- CAMERA MOTION. A stepper rather than a checkbox, because "off" is the wrong shape for this
	-- complaint: most players who notice the head bob or a blast shake want less of it, not none, and a
	-- two-state control makes them choose between a camera they find busy and a game with no impacts in
	-- it. FULL / REDUCED / OFF, and OFF still keeps the things that are information rather than
	-- decoration (see `Config/CameraMotion.scales`).
	--
	-- Session-local, like the sensitivity and volume rows above it and for the same reason: nothing in
	-- this menu is persisted yet, and quietly making one row the exception would put a player setting
	-- in the profile schema without the rest of the surface that has to come with it.
	motionLabel = controlRow(body, 7, function()
		CameraMotionController.cycleLevel(-1)
	end, function()
		CameraMotionController.cycleLevel(1)
	end)

	local resume = UITheme.button(body, "RESUME  ·  M")
	resume.instance.Size = UDim2.new(1, 0, 0, 46)
	resume.instance.LayoutOrder = 8
	resume.instance.Activated:Connect(function()
		setOpen(false)
	end)

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyLayout()
		applyOpenButtonLayout()
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	screenGui = gui
	refreshLabels()
	applyLayout()
	applyOpenButtonLayout()
	-- A tablet or touchscreen laptop can switch hands mid-session; the MENU button follows whichever
	-- one is in use rather than being decided once at boot.
	UserInputService.LastInputTypeChanged:Connect(function()
		applyLayout()
		applyOpenButtonLayout()
	end)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(applyOpenButtonLayout)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			toggle()
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if ownsMovement(musicDragInput, input) then
			setMusicVolumeFromScreenX(input.Position.X)
		end
		if ownsMovement(ambienceDragInput, input) then
			setAmbienceVolumeFromScreenX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if ownsRelease(musicDragInput, input) then
			musicDragInput = nil
		end
		if ownsRelease(ambienceDragInput, input) then
			-- The throttle can swallow the last few frames of a drag, which are exactly the ones
			-- carrying the value the player settled on. Release always gets its own sample.
			ambienceDragInput = nil
			previewAmbience(true)
		end
	end)
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string)
		if kind == "floor" then
			runActive = true
		elseif kind == "countdown" or kind == "results" then
			runActive = false
			setOpen(false)
		end
		refreshOpenButton()
	end)
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if not menuAvailable() then
			setOpen(false)
		end
		refreshOpenButton()
	end)
	player:GetAttributeChangedSignal(SHOP_OPEN_ATTRIBUTE):Connect(function()
		if not menuAvailable() then
			setOpen(false)
		end
		refreshOpenButton()
	end)
	refreshOpenButton()
end

return SettingsController

--!strict
-- Local, in-run settings menu. It deliberately affects only client presentation/input; game rules
-- stay server-authoritative. M toggles it; Roblox's native Escape menu stays available. Owns the
-- "Settings" cursor release and only offers itself while a run is actually live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AudioCues = require(script.Parent.AudioCues)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local SettingsController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local MIN_SENSITIVITY = 0.2
local MAX_SENSITIVITY = 3
local SENSITIVITY_STEP = 0.2
local VOLUME_STEP = 0.25

local panel: CanvasGroup? = nil
local panelScale: UIScale? = nil
local openButton: TextButton? = nil
local sensitivityLabel: TextLabel? = nil
local volumeLabel: TextLabel? = nil
local audioVolume = 1
local runActive = false

local function expeditionActive(): boolean
	return player:GetAttribute(EXPEDITION_ATTRIBUTE) == true
end

local function menuAvailable(): boolean
	return expeditionActive() and runActive
end

local function refreshLabels()
	if sensitivityLabel ~= nil then
		sensitivityLabel.Text = string.format("SENSITIVITY   %.1f", UserInputService.MouseDeltaSensitivity)
	end
	if volumeLabel ~= nil then
		volumeLabel.Text = string.format("LOCAL AUDIO   %d%%", math.floor(audioVolume * 100 + 0.5))
	end
end

-- A [-]  label value  [+] stepper row.
local function controlRow(parent: Instance, order: number, onDown: () -> (), onUp: () -> ()): TextLabel
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 44)
	row.LayoutOrder = order
	row.Parent = parent

	local minus = UITheme.button(row, "–")
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
	constraint.MaxTextSize = 17
	constraint.Parent = value
	return value
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
		group.Visible = true
		group.GroupTransparency = 1
		scale.Scale = 0.94
		refreshLabels()
		TweenService:Create(group, UITheme.motion.fade, { GroupTransparency = 0 }):Play()
		TweenService:Create(scale, UITheme.motion.rise, { Scale = 1 }):Play()
	else
		group.Visible = false
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

	local group = Instance.new("CanvasGroup")
	group.Name = "Panel"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.5)
	group.Size = UDim2.fromScale(0.32, 0.5)
	group.BackgroundColor3 = palette.panel
	group.BackgroundTransparency = 0.02
	group.BorderSizePixel = 0
	group.Visible = false
	group.Parent = gui
	UITheme.corner(group, 16)
	UITheme.stroke(group, palette.stroke, 1.5, 0.3)
	UITheme.uniformPadding(group, 24)
	panel = group
	panelScale = UITheme.scale(group, 1)
	UITheme.listLayout(group, 12)

	local heading = UITheme.heading(group, "SETTINGS")
	heading.Size = UDim2.new(1, 0, 0, 42)
	heading.LayoutOrder = 1

	local note = UITheme.label(group, "Your mouse is freed while this menu is open.", 26)
	note.Font = UITheme.font.fine
	note.TextColor3 = palette.textMuted
	note.LayoutOrder = 2

	sensitivityLabel = controlRow(group, 3, function()
		UserInputService.MouseDeltaSensitivity =
			math.max(MIN_SENSITIVITY, UserInputService.MouseDeltaSensitivity - SENSITIVITY_STEP)
	end, function()
		UserInputService.MouseDeltaSensitivity =
			math.min(MAX_SENSITIVITY, UserInputService.MouseDeltaSensitivity + SENSITIVITY_STEP)
	end)

	volumeLabel = controlRow(group, 4, function()
		audioVolume = math.max(0, audioVolume - VOLUME_STEP)
		AudioCues.setVolumeMultiplier(audioVolume)
	end, function()
		audioVolume = math.min(1, audioVolume + VOLUME_STEP)
		AudioCues.setVolumeMultiplier(audioVolume)
	end)

	local resume = UITheme.button(group, "RESUME  ·  M")
	resume.instance.Size = UDim2.new(1, 0, 0, 46)
	resume.instance.LayoutOrder = 5
	resume.instance.Activated:Connect(function()
		setOpen(false)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	refreshLabels()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			toggle()
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
	refreshOpenButton()
end

return SettingsController

--!strict
-- Local, in-run settings menu. It deliberately affects only client presentation/input; game
-- rules remain server-authoritative. M opens it, and Escape/M closes it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AudioCues = require(script.Parent.AudioCues)
local CursorController = require(script.Parent.CursorController)

local SettingsController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local MENU_ACTION = "WickSettingsMenu"
local MIN_SENSITIVITY = 0.2
local MAX_SENSITIVITY = 3
local SENSITIVITY_STEP = 0.2
local VOLUME_STEP = 0.25

local screen: ScreenGui? = nil
local panel: Frame? = nil
local sensitivityLabel: TextLabel? = nil
local volumeLabel: TextLabel? = nil
local audioVolume = 1

local function expeditionActive(): boolean
	return player:GetAttribute(EXPEDITION_ATTRIBUTE) == true
end

local function makeLabel(parent: Instance, text: string, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -28, 0, height)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 222, 205)
	label.Font = Enum.Font.Gotham
	label.TextScaled = true
	label.Text = text
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -28, 0, 38)
	button.BackgroundColor3 = Color3.fromRGB(60, 48, 42)
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 220, 175)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.Parent = parent
	return button
end

local function refreshLabels()
	if sensitivityLabel ~= nil then
		sensitivityLabel.Text = string.format("MOUSE SENSITIVITY  %.1f", UserInputService.MouseDeltaSensitivity)
	end
	if volumeLabel ~= nil then
		volumeLabel.Text = string.format("LOCAL AUDIO  %d%%", math.floor(audioVolume * 100 + 0.5))
	end
end

local function setOpen(open: boolean)
	local currentPanel = panel
	if currentPanel == nil then
		return
	end
	local allowed = open and expeditionActive()
	currentPanel.Visible = allowed
	CursorController.setReleased("Settings", allowed)
	if allowed then
		refreshLabels()
	end
end

local function toggle()
	local currentPanel = panel
	if currentPanel ~= nil then
		setOpen(not currentPanel.Visible)
	end
end

function SettingsController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickSettings"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.IgnoreGuiInset = true

	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenMenu"
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.fromScale(0.02, 0.96)
	openButton.Size = UDim2.fromScale(0.12, 0.045)
	openButton.BackgroundColor3 = Color3.fromRGB(20, 18, 22)
	openButton.BackgroundTransparency = 0.15
	openButton.BorderSizePixel = 0
	openButton.TextColor3 = Color3.fromRGB(255, 220, 175)
	openButton.Font = Enum.Font.GothamBold
	openButton.TextScaled = true
	openButton.Text = "MENU  [M]"
	openButton.Visible = false
	openButton.Parent = gui
	openButton.Activated:Connect(toggle)

	local menuPanel = Instance.new("Frame")
	menuPanel.Name = "Panel"
	menuPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	menuPanel.Position = UDim2.fromScale(0.5, 0.5)
	menuPanel.Size = UDim2.fromScale(0.34, 0.46)
	menuPanel.BackgroundColor3 = Color3.fromRGB(12, 11, 14)
	menuPanel.BackgroundTransparency = 0.05
	menuPanel.BorderSizePixel = 0
	menuPanel.Visible = false
	menuPanel.Parent = gui
	panel = menuPanel

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = menuPanel

	makeLabel(menuPanel, "SETTINGS", 52).Font = Enum.Font.GothamBlack
	makeLabel(menuPanel, "Mouse is released while this menu is open.", 32)
	sensitivityLabel = makeLabel(menuPanel, "", 34)
	local lowerSensitivity = makeButton(menuPanel, "SENSITIVITY -")
	lowerSensitivity.Activated:Connect(function()
		UserInputService.MouseDeltaSensitivity = math.max(
			MIN_SENSITIVITY,
			UserInputService.MouseDeltaSensitivity - SENSITIVITY_STEP
		)
		refreshLabels()
	end)
	local raiseSensitivity = makeButton(menuPanel, "SENSITIVITY +")
	raiseSensitivity.Activated:Connect(function()
		UserInputService.MouseDeltaSensitivity = math.min(
			MAX_SENSITIVITY,
			UserInputService.MouseDeltaSensitivity + SENSITIVITY_STEP
		)
		refreshLabels()
	end)
	volumeLabel = makeLabel(menuPanel, "", 34)
	local lowerVolume = makeButton(menuPanel, "AUDIO -")
	lowerVolume.Activated:Connect(function()
		audioVolume = math.max(0, audioVolume - VOLUME_STEP)
		AudioCues.setVolumeMultiplier(audioVolume)
		refreshLabels()
	end)
	local raiseVolume = makeButton(menuPanel, "AUDIO +")
	raiseVolume.Activated:Connect(function()
		audioVolume = math.min(1, audioVolume + VOLUME_STEP)
		AudioCues.setVolumeMultiplier(audioVolume)
		refreshLabels()
	end)
	local closeButton = makeButton(menuPanel, "RESUME  [M / ESC]")
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui
	refreshLabels()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and menuPanel.Visible then
			setOpen(false)
		end
	end)
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		openButton.Visible = expeditionActive()
		if not expeditionActive() then
			setOpen(false)
		end
	end)
	openButton.Visible = expeditionActive()
end

return SettingsController

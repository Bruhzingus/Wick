--!strict
-- Responsive control legend. Desktop shows the exact keyboard bindings; touch shows the same
-- actions without pretending that mobile players have keys. Actual input remains in its controllers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local HotbarController = {}

local player = Players.LocalPlayer

type Chip = {
	key: TextLabel,
	name: TextLabel,
	baseName: string,
}

local chips: { Chip } = {}
local toolChips: { [Types.ToolId]: Chip } = {}
local panel: Frame? = nil
local header: TextLabel? = nil

local function isTouchLayout(inputType: Enum.UserInputType): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	if not UserInputService.KeyboardEnabled then
		return true
	end
	return inputType == Enum.UserInputType.Touch
end

local function addCorner(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Config.Feel.hotbar.cornerRadiusPixels)
	corner.Parent = parent
end

local function addTextConstraint(parent: TextLabel)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = Config.Feel.hotbar.minTextSize
	constraint.MaxTextSize = Config.Feel.hotbar.maxTextSize
	constraint.Parent = parent
end

local function buildChip(parent: Frame, keyText: string, nameText: string): Chip
	local chip = Instance.new("Frame")
	chip.BackgroundColor3 = Config.Feel.hotbar.chipColor
	chip.BackgroundTransparency = Config.Feel.hotbar.chipTransparency
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = parent
	addCorner(chip)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Config.Feel.hotbar.strokeColor
	stroke.Transparency = Config.Feel.hotbar.strokeTransparency
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = chip

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.BackgroundTransparency = 1
	key.Position = UDim2.fromScale(0.03, 0)
	key.Size = UDim2.fromScale(0.27, 1)
	key.Font = Enum.Font.GothamBold
	key.Text = keyText
	key.TextColor3 = Config.Feel.hotbar.keyColor
	key.TextScaled = true
	key.Parent = chip
	addTextConstraint(key)

	local name = Instance.new("TextLabel")
	name.Name = "Action"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0.3, 0)
	name.Size = UDim2.fromScale(0.67, 1)
	name.Font = Enum.Font.GothamMedium
	name.Text = nameText
	name.TextColor3 = Config.Feel.hotbar.textColor
	name.TextScaled = true
	name.Parent = chip
	addTextConstraint(name)

	local result = { key = key, name = name, baseName = nameText }
	table.insert(chips, result)
	return result
end

local function buildRow(parent: Frame, count: number): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = parent

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.new(0, Config.Feel.hotbar.chipGapPixels, 0, 0)
	layout.CellSize = UDim2.new(1 / count, -Config.Feel.hotbar.chipGapPixels, 1, 0)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = count
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	return row
end

local function applyLayout(touch: boolean)
	local currentPanel = panel
	local currentHeader = header
	if currentPanel == nil or currentHeader == nil then
		return
	end

	currentPanel.Position = if touch then Config.Feel.hotbar.touchPosition else Config.Feel.hotbar.desktopPosition
	currentPanel.Size = if touch then Config.Feel.hotbar.touchSize else Config.Feel.hotbar.desktopSize
	currentHeader.Text = if touch then Config.Feel.hotbar.touchHeader else Config.Feel.hotbar.desktopHeader

	for _, chip in chips do
		chip.key.Visible = not touch
		chip.name.Position = if touch then UDim2.fromScale(0.03, 0) else UDim2.fromScale(0.3, 0)
		chip.name.Size = if touch then UDim2.fromScale(0.94, 1) else UDim2.fromScale(0.67, 1)
	end
end

function HotbarController.start()
	if not Config.Feel.hotbar.enabled then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WickHotbar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Config.Feel.hotbar.displayOrder

	local root = Instance.new("Frame")
	root.Name = "ControlLegend"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundColor3 = Config.Feel.hotbar.backgroundColor
	root.BackgroundTransparency = Config.Feel.hotbar.backgroundTransparency
	root.BorderSizePixel = 0
	root.Parent = gui
	addCorner(root)
	panel = root

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, Config.Feel.hotbar.rowGapPixels)
	padding.PaddingBottom = UDim.new(0, Config.Feel.hotbar.rowGapPixels)
	padding.PaddingLeft = UDim.new(0, Config.Feel.hotbar.rowGapPixels)
	padding.PaddingRight = UDim.new(0, Config.Feel.hotbar.rowGapPixels)
	padding.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Header"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Size = UDim2.new(1, 0, 0.18, 0)
	title.TextColor3 = Config.Feel.hotbar.keyColor
	title.TextScaled = true
	title.Parent = root
	addTextConstraint(title)
	header = title

	local toolsRow = buildRow(root, #Config.Feel.controls.tools)
	toolsRow.Name = "Tools"
	toolsRow.Position = UDim2.fromScale(0, 0.2)
	toolsRow.Size = UDim2.fromScale(1, 0.37)
	for _, control in Config.Feel.controls.tools do
		toolChips[control.toolId] = buildChip(toolsRow, control.keyLabel, Config.Tools[control.toolId].displayName)
	end

	local movementOrder = {
		Config.Feel.controls.movement.Dodge,
		Config.Feel.controls.movement.Slide,
		Config.Feel.controls.movement.Sprint,
	}
	local movementRow = buildRow(root, #movementOrder)
	movementRow.Name = "Movement"
	movementRow.Position = UDim2.fromScale(0, 0.61)
	movementRow.Size = UDim2.fromScale(1, 0.37)
	for _, control in movementOrder do
		buildChip(movementRow, control.keyLabel, control.displayName)
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	applyLayout(isTouchLayout(UserInputService:GetLastInputType()))
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		applyLayout(isTouchLayout(inputType))
	end)

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			for toolId, chip in toolChips do
				local charges = entry.freeToolCharges[toolId] or 0
				chip.name.Text = if charges > 0
					then string.format(Config.Feel.hotbar.freeChargeFormat, chip.baseName, charges)
					else chip.baseName
			end
			break
		end
	end)
end

return HotbarController

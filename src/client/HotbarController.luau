--!strict
-- Responsive control legend. Desktop shows the exact keyboard bindings; touch shows the same
-- actions without pretending that mobile players have keys. Actual input remains in its controllers.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local HotbarController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

type TouchMirror = {
	button: ImageButton,
	track: Frame,
	fill: Frame,
	label: TextLabel,
}

type Chip = {
	frame: Frame,
	key: TextLabel,
	name: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	cooldownTrack: Frame,
	cooldownFill: Frame,
	cooldownLabel: TextLabel,
	cooldownEndsAt: number,
	cooldownDuration: number,
	cooldownVisible: boolean,
	active: boolean,
	baseName: string,
	displayName: string,
	denialText: string?,
	touchActionName: string?,
	touchMirror: TouchMirror?,
	feedbackToken: number,
	frameTween: Tween?,
	strokeTween: Tween?,
	scaleTween: Tween?,
}

-- Chips a tool/ability use can light up. Keyed by tool id ("Snuff", …) and movement id ("Dodge", …).
local BOUNCE = TweenInfo.new(Config.Feel.hotbar.pulseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)

local chips: { Chip } = {}
local toolChips: { [Types.ToolId]: Chip } = {}
local chipsByAction: { [string]: Chip } = {}
local panel: Frame? = nil
local header: TextLabel? = nil
local touchLayout = false

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

local function buildChip(
	parent: Frame,
	actionId: string,
	keyText: string,
	nameText: string,
	touchActionName: string?
): Chip
	local chip = Instance.new("Frame")
	chip.BackgroundColor3 = Config.Feel.hotbar.chipColor
	chip.BackgroundTransparency = Config.Feel.hotbar.chipTransparency
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromScale(1, 1)
	chip.Parent = parent
	addCorner(chip)

	-- Own UIScale so a use can bounce the chip without disturbing the grid layout.
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = chip

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
	key.ZIndex = 3
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
	name.ZIndex = 3
	name.Parent = chip
	addTextConstraint(name)

	local cooldownTrack = Instance.new("Frame")
	cooldownTrack.Name = "Cooldown"
	cooldownTrack.AnchorPoint = Vector2.new(0, 1)
	cooldownTrack.BackgroundColor3 = Config.Feel.hotbar.cooldownTrackColor
	cooldownTrack.BackgroundTransparency = Config.Feel.hotbar.cooldownTrackTransparency
	cooldownTrack.BorderSizePixel = 0
	cooldownTrack.ClipsDescendants = true
	cooldownTrack.Position = UDim2.fromScale(0, 1)
	cooldownTrack.Size = UDim2.fromScale(1, Config.Feel.hotbar.cooldownBarHeightScale)
	cooldownTrack.Visible = false
	cooldownTrack.ZIndex = 4
	cooldownTrack.Parent = chip
	addCorner(cooldownTrack)

	local cooldownFill = Instance.new("Frame")
	cooldownFill.Name = "Remaining"
	cooldownFill.BackgroundColor3 = Config.Feel.hotbar.cooldownFillColor
	cooldownFill.BackgroundTransparency = Config.Feel.hotbar.cooldownFillTransparency
	cooldownFill.BorderSizePixel = 0
	cooldownFill.Size = UDim2.fromScale(1, 1)
	cooldownFill.ZIndex = 5
	cooldownFill.Parent = cooldownTrack

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "Seconds"
	cooldownLabel.BackgroundColor3 = Config.Feel.hotbar.cooldownTrackColor
	cooldownLabel.BackgroundTransparency = Config.Feel.hotbar.cooldownTrackTransparency
	cooldownLabel.BorderSizePixel = 0
	cooldownLabel.Font = Enum.Font.GothamBold
	cooldownLabel.Position = Config.Feel.hotbar.cooldownLabelPosition
	cooldownLabel.Size = Config.Feel.hotbar.cooldownLabelSize
	cooldownLabel.Text = ""
	cooldownLabel.TextColor3 = Config.Feel.hotbar.cooldownTextColor
	cooldownLabel.TextScaled = true
	cooldownLabel.TextStrokeTransparency = Config.Feel.hotbar.cooldownTextStrokeTransparency
	cooldownLabel.Visible = false
	cooldownLabel.ZIndex = 6
	cooldownLabel.Parent = chip
	addCorner(cooldownLabel)
	addTextConstraint(cooldownLabel)

	local result: Chip = {
		frame = chip,
		key = key,
		name = name,
		stroke = stroke,
		scale = scale,
		cooldownTrack = cooldownTrack,
		cooldownFill = cooldownFill,
		cooldownLabel = cooldownLabel,
		cooldownEndsAt = 0,
		cooldownDuration = 0,
		cooldownVisible = false,
		active = false,
		baseName = nameText,
		displayName = nameText,
		denialText = nil,
		touchActionName = touchActionName,
		touchMirror = nil,
		feedbackToken = 0,
		frameTween = nil,
		strokeTween = nil,
		scaleTween = nil,
	}
	table.insert(chips, result)
	chipsByAction[actionId] = result
	return result
end

local function buildRow(parent: Frame, count: number): Frame
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = parent

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(Config.Feel.hotbar.chipGapPixels, 0)
	layout.CellSize = UDim2.new(1 / count, -Config.Feel.hotbar.chipGapPixels, 1, 0)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = count
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	return row
end

local function applyChipLayout(chip: Chip)
	chip.key.Visible = not touchLayout
	if touchLayout and not chip.cooldownVisible then
		chip.name.Position = UDim2.fromScale(0.03, 0)
		chip.name.Size = UDim2.fromScale(0.94, 1)
	else
		-- On touch, the numeric timer temporarily occupies the key column that desktop already
		-- reserves. The action title shifts beside it instead of being painted underneath it.
		chip.name.Position = UDim2.fromScale(0.3, 0)
		chip.name.Size = UDim2.fromScale(0.67, 1)
	end
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
	touchLayout = touch

	for _, chip in chips do
		applyChipLayout(chip)
	end
end

local function restColor(chip: Chip): Color3
	return if chip.active then Config.Feel.hotbar.activeChipColor else Config.Feel.hotbar.chipColor
end

local function restStrokeColor(chip: Chip): Color3
	return if chip.active then Config.Feel.hotbar.activeStrokeColor else Config.Feel.hotbar.strokeColor
end

local function destroyTouchMirror(chip: Chip)
	local mirror = chip.touchMirror
	if mirror == nil then
		return
	end
	if mirror.label.Parent ~= nil then
		mirror.label:Destroy()
	end
	if mirror.track.Parent ~= nil then
		mirror.track:Destroy()
	end
	chip.touchMirror = nil
end

local function ensureTouchMirror(chip: Chip): TouchMirror?
	local actionName = chip.touchActionName
	if not UserInputService.TouchEnabled or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true or actionName == nil then
		return nil
	end

	local current = chip.touchMirror
	if current ~= nil and current.button.Parent ~= nil then
		return current
	end
	chip.touchMirror = nil

	-- ToolController and MovementController own the bindings and native button layout. This
	-- controller only adds presentation children to the button Roblox already created.
	local button = ContextActionService:GetButton(actionName)
	if button == nil then
		return nil
	end

	local track = Instance.new("Frame")
	track.Name = "WickCooldown"
	track.BackgroundColor3 = Config.Feel.hotbar.cooldownTrackColor
	track.BackgroundTransparency = Config.Feel.hotbar.cooldownTrackTransparency
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = Config.Feel.hotbar.touchCooldownTrackPosition
	track.Size = Config.Feel.hotbar.touchCooldownTrackSize
	track.Visible = false
	track.ZIndex = button.ZIndex + 3
	track.Parent = button
	addCorner(track)

	local fill = Instance.new("Frame")
	fill.Name = "Remaining"
	fill.BackgroundColor3 = Config.Feel.hotbar.cooldownFillColor
	fill.BackgroundTransparency = Config.Feel.hotbar.cooldownFillTransparency
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = track.ZIndex + 1
	fill.Parent = track

	local label = Instance.new("TextLabel")
	label.Name = "WickCooldownSeconds"
	label.BackgroundColor3 = Config.Feel.hotbar.cooldownTrackColor
	label.BackgroundTransparency = Config.Feel.hotbar.cooldownTrackTransparency
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Position = Config.Feel.hotbar.touchCooldownLabelPosition
	label.Size = Config.Feel.hotbar.touchCooldownLabelSize
	label.Text = ""
	label.TextColor3 = Config.Feel.hotbar.cooldownTextColor
	label.TextScaled = true
	label.TextStrokeTransparency = Config.Feel.hotbar.cooldownTextStrokeTransparency
	label.Visible = false
	label.ZIndex = track.ZIndex + 2
	label.Parent = button
	addCorner(label)
	addTextConstraint(label)

	local mirror: TouchMirror = {
		button = button,
		track = track,
		fill = fill,
		label = label,
	}
	chip.touchMirror = mirror
	ContextActionService:SetTitle(actionName, chip.denialText or chip.displayName)
	return mirror
end

local function refreshChipText(chip: Chip)
	local text = chip.denialText or chip.displayName
	chip.name.Text = text
	local mirror = ensureTouchMirror(chip)
	local actionName = chip.touchActionName
	if mirror ~= nil and actionName ~= nil then
		ContextActionService:SetTitle(actionName, text)
	end
end

local function cancelFeedback(chip: Chip, clearDenial: boolean)
	chip.feedbackToken += 1
	if chip.frameTween ~= nil then
		chip.frameTween:Cancel()
		chip.frameTween = nil
	end
	if chip.strokeTween ~= nil then
		chip.strokeTween:Cancel()
		chip.strokeTween = nil
	end
	if chip.scaleTween ~= nil then
		chip.scaleTween:Cancel()
		chip.scaleTween = nil
	end
	chip.scale.Scale = 1
	if clearDenial then
		chip.denialText = nil
	end
end

local function paintRest(chip: Chip)
	chip.frame.BackgroundColor3 = restColor(chip)
	chip.stroke.Color = restStrokeColor(chip)
	chip.stroke.Transparency = Config.Feel.hotbar.strokeTransparency
end

local function setActive(chip: Chip, active: boolean)
	if chip.active == active then
		return
	end
	cancelFeedback(chip, true)
	chip.active = active
	paintRest(chip)
	refreshChipText(chip)
end

local function setCooldown(actionId: string, endsAt: number, duration: number)
	local chip = chipsByAction[actionId]
	if chip == nil then
		return
	end
	chip.cooldownEndsAt = math.max(0, endsAt)
	chip.cooldownDuration = math.max(0, duration)
end

local function setCooldownVisible(chip: Chip, visible: boolean)
	if chip.cooldownVisible == visible then
		return
	end
	chip.cooldownVisible = visible
	chip.cooldownTrack.Visible = visible
	chip.cooldownLabel.Visible = visible
	applyChipLayout(chip)
end

local function formattedRemaining(remaining: number): string
	local step = Config.Feel.hotbar.cooldownDisplayStepSeconds
	local roundedUp = math.ceil(remaining / step) * step
	return string.format(Config.Feel.hotbar.cooldownSecondsFormat, roundedUp)
end

local function renderCooldown(chip: Chip, now: number)
	local remaining = math.max(0, chip.cooldownEndsAt - now)
	if remaining <= Config.Feel.hotbar.cooldownMinimumDisplaySeconds or chip.cooldownDuration <= 0 then
		setCooldownVisible(chip, false)
		chip.cooldownEndsAt = 0
		local mirror = chip.touchMirror
		if mirror ~= nil then
			mirror.track.Visible = false
			mirror.label.Visible = false
		end
		return
	end
	local fraction = math.clamp(remaining / chip.cooldownDuration, 0, 1)
	local text = formattedRemaining(remaining)
	setCooldownVisible(chip, true)
	chip.cooldownFill.Size = UDim2.fromScale(fraction, 1)
	chip.cooldownLabel.Text = text

	local mirror = ensureTouchMirror(chip)
	if mirror ~= nil then
		mirror.track.Visible = true
		mirror.label.Visible = true
		mirror.fill.Size = UDim2.fromScale(fraction, 1)
		mirror.label.Text = text
	end
end

local function playFeedback(chip: Chip, color: Color3, duration: number, bounce: boolean): number
	cancelFeedback(chip, true)
	refreshChipText(chip)
	local token = chip.feedbackToken

	chip.frame.BackgroundColor3 = color
	chip.stroke.Color = Config.Feel.hotbar.activeStrokeColor
	chip.stroke.Transparency = 0

	local frameTween = TweenService:Create(chip.frame, TweenInfo.new(duration), {
		BackgroundColor3 = restColor(chip),
	})
	local strokeTween = TweenService:Create(chip.stroke, TweenInfo.new(duration), {
		Color = restStrokeColor(chip),
		Transparency = Config.Feel.hotbar.strokeTransparency,
	})
	chip.frameTween = frameTween
	chip.strokeTween = strokeTween
	frameTween.Completed:Connect(function()
		if chip.feedbackToken == token then
			chip.frameTween = nil
		end
	end)
	strokeTween.Completed:Connect(function()
		if chip.feedbackToken == token then
			chip.strokeTween = nil
		end
	end)
	frameTween:Play()
	strokeTween:Play()

	if bounce then
		local scaleTween = TweenService:Create(chip.scale, BOUNCE, { Scale = Config.Feel.hotbar.pulseScale })
		chip.scaleTween = scaleTween
		scaleTween.Completed:Connect(function()
			if chip.feedbackToken == token then
				chip.scaleTween = nil
			end
		end)
		scaleTween:Play()
	end
	return token
end

local function friendlyDenial(reason: string?): string
	if reason ~= nil then
		local configured = Config.Feel.hotbar.denialMessages[reason]
		if configured ~= nil then
			return configured
		end
	end
	return Config.Feel.hotbar.denialFallbackText
end

local function resetChip(chip: Chip)
	cancelFeedback(chip, true)
	chip.active = false
	chip.displayName = chip.baseName
	chip.cooldownEndsAt = 0
	chip.cooldownDuration = 0
	setCooldownVisible(chip, false)
	paintRest(chip)
	local mirror = chip.touchMirror
	local actionName = chip.touchActionName
	if mirror ~= nil and mirror.button.Parent ~= nil and actionName ~= nil then
		ContextActionService:SetTitle(actionName, chip.baseName)
	end
	destroyTouchMirror(chip)
	refreshChipText(chip)
end

local function resetAllChips()
	for _, chip in chips do
		resetChip(chip)
	end
end

-- Light a chip up when its tool/ability fires: a warm flash plus a small scale bounce. Purely
-- cosmetic acknowledgement; safe to call for an unknown or not-yet-built action (it no-ops).
function HotbarController.pulse(actionId: string)
	local chip = chipsByAction[actionId]
	if chip == nil then
		return
	end
	playFeedback(chip, Config.Feel.hotbar.acceptedColor, Config.Feel.hotbar.pulseSeconds, true)
end

function HotbarController.reject(actionId: string, reason: string?)
	local chip = chipsByAction[actionId]
	if chip == nil then
		return
	end
	local token = playFeedback(chip, Config.Feel.hotbar.deniedColor, Config.Feel.hotbar.deniedFlashSeconds, false)
	local denialText = friendlyDenial(reason)
	chip.denialText = denialText
	refreshChipText(chip)
	task.delay(Config.Feel.hotbar.denialTextSeconds, function()
		if chip.feedbackToken ~= token or chip.denialText ~= denialText then
			return
		end
		chip.denialText = nil
		refreshChipText(chip)
	end)
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
	title.Size = UDim2.fromScale(1, 0.18)
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
		toolChips[control.toolId] = buildChip(
			toolsRow,
			control.toolId,
			control.keyLabel,
			Config.Tools[control.toolId].displayName,
			"WickTool" .. control.toolId
		)
	end

	local movementOrder = {
		{ id = "Dodge", control = Config.Feel.controls.movement.Dodge },
		{ id = "Slide", control = Config.Feel.controls.movement.Slide },
		{ id = "Sprint", control = Config.Feel.controls.movement.Sprint },
	}
	local movementRow = buildRow(root, #movementOrder)
	movementRow.Name = "Movement"
	movementRow.Position = UDim2.fromScale(0, 0.61)
	movementRow.Size = UDim2.fromScale(1, 0.37)
	for _, entry in movementOrder do
		buildChip(movementRow, entry.id, entry.control.keyLabel, entry.control.displayName, "Wick" .. entry.id)
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	applyLayout(isTouchLayout(UserInputService:GetLastInputType()))
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		applyLayout(isTouchLayout(inputType))
	end)
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
			resetAllChips()
		end
	end)

	Remotes.get("ActionFeedback").OnClientEvent
		:Connect(function(actionId: unknown, accepted: unknown, endsAt: unknown, duration: unknown, reason: unknown)
			if
				player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true
				or typeof(actionId) ~= "string"
				or typeof(accepted) ~= "boolean"
				or typeof(endsAt) ~= "number"
				or typeof(duration) ~= "number"
			then
				return
			end
			setCooldown(actionId, endsAt, duration)
			if accepted then
				HotbarController.pulse(actionId)
			else
				HotbarController.reject(actionId, if typeof(reason) == "string" then reason else nil)
			end
		end)

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		if player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
			return
		end
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			for toolId, chip in toolChips do
				local active = false
				local displayName = chip.baseName
				if
					toolId == "Snuff"
					and not entry.isLit
					and not entry.snuffed
					and entry.alive
					and not entry.finished
				then
					active = true
					displayName = Config.Feel.hotbar.relightDisplayName
				elseif toolId == "Cup" and entry.isCupping then
					active = true
					displayName = Config.Feel.hotbar.uncupDisplayName
				end
				setActive(chip, active)
				local charges = entry.freeToolCharges[toolId] or 0
				chip.displayName = if charges > 0
					then string.format(Config.Feel.hotbar.freeChargeFormat, displayName, charges)
					else displayName
				refreshChipText(chip)
			end
			for actionId, chip in chipsByAction do
				local cooldown = entry.actionCooldowns[actionId]
				if cooldown ~= nil then
					setCooldown(actionId, cooldown.endsAt, cooldown.duration)
				elseif chip.cooldownEndsAt ~= 0 then
					setCooldown(actionId, 0, 0)
				end
			end
			break
		end
	end)

	if player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
		resetAllChips()
	end

	RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for _, chip in chips do
			renderCooldown(chip, now)
		end
	end)
end

return HotbarController

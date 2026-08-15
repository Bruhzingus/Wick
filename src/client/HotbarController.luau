--!strict
-- Responsive control legend. Desktop shows the exact keyboard bindings; touch shows the same
-- actions without pretending that mobile players have keys. Actual input remains in its controllers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpectatorRules = require(ReplicatedStorage.Shared.Logic.SpectatorRules)
local TouchControls = require(script.Parent.TouchControls)

local HotbarController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

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
	feedbackToken: number,
	frameTween: Tween?,
	strokeTween: Tween?,
	scaleTween: Tween?,
}

-- Chips a tool use can light up, keyed by tool id ("Flare", …).
local BOUNCE = TweenInfo.new(Config.Feel.hotbar.pulseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)

local chips: { Chip } = {}
local toolChips: { [Types.ToolId]: Chip } = {}
local chipsByAction: { [string]: Chip } = {}
-- Dynamite's chip, kept out of `toolChips` because dynamite is not a `ToolId` (Types/Dynamite). The
-- action id has to match the one `server/DynamiteService` sends feedback under.
local DYNAMITE_ACTION_ID = "Dynamite"
local dynamiteChip: Chip? = nil
local panel: Frame? = nil
local header: TextLabel? = nil
local touchLayout = false
-- A ghost has no tools and no strain, so the legend hides for them (see the StateSync handler). It is
-- tracked rather than read off `panel.Visible` because the touch layout hides the same panel for an
-- unrelated reason, and two claims on one flag is how a panel comes back when only one of them lifts.
local spectating = false

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

-- THE LEGEND IS A DESKTOP SURFACE and, since the touch cluster shipped, only a desktop surface.
-- Every chip here says "this key does this thing"; a phone has no keys, so the touch variant was the
-- same four tool names printed a second time — once across the top of the screen and once on the
-- buttons themselves — and the copy at the top was the one competing with Roblox's own topbar for
-- room. `panel.Visible` is also driven by the spectator branch in `start`, so this sets the layout
-- flag and lets `refreshPanelVisible` reconcile the two claims.
local function refreshPanelVisible()
	local currentPanel = panel
	if currentPanel ~= nil then
		currentPanel.Visible = not touchLayout and not spectating
	end
	-- The same rule has to reach the touch buttons or a ghost keeps a full tool cluster it cannot use.
	-- Only the tool row is claimed here; MINE/STOP are `client/MiningController`'s to show and hide.
	if UserInputService.TouchEnabled then
		for _, chip in chips do
			local id = chip.touchActionName
			if id ~= nil then
				TouchControls.setVisible(id, not spectating and player:GetAttribute(EXPEDITION_ATTRIBUTE) == true)
			end
		end
	end
end

local function applyLayout(touch: boolean)
	local currentPanel = panel
	local currentHeader = header
	if currentPanel == nil or currentHeader == nil then
		return
	end

	currentPanel.Position = Config.Feel.hotbar.desktopPosition
	currentPanel.Size = Config.Feel.hotbar.desktopSize
	currentHeader.Text = Config.Feel.hotbar.desktopHeader
	touchLayout = touch
	refreshPanelVisible()
end

local function restColor(chip: Chip): Color3
	return if chip.active then Config.Feel.hotbar.activeChipColor else Config.Feel.hotbar.chipColor
end

local function restStrokeColor(chip: Chip): Color3
	return if chip.active then Config.Feel.hotbar.activeStrokeColor else Config.Feel.hotbar.strokeColor
end

-- The touch button for this chip's action, if this chip has one. `client/TouchControls` owns the
-- instance, its size and its place in the cluster; this controller owns only what it says.
local function touchId(chip: Chip): string?
	if not UserInputService.TouchEnabled then
		return nil
	end
	return chip.touchActionName
end

local function refreshChipText(chip: Chip)
	local text = chip.denialText or chip.displayName
	chip.name.Text = text
	local id = touchId(chip)
	if id ~= nil then
		TouchControls.setLabel(id, text)
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
	local id = touchId(chip)
	if id ~= nil then
		TouchControls.setActive(id, active)
	end
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
end

local function formattedRemaining(remaining: number): string
	local step = Config.Feel.hotbar.cooldownDisplayStepSeconds
	local roundedUp = math.ceil(remaining / step) * step
	return string.format(Config.Feel.hotbar.cooldownSecondsFormat, roundedUp)
end

local function renderCooldown(chip: Chip, now: number)
	local id = touchId(chip)
	local remaining = math.max(0, chip.cooldownEndsAt - now)
	if remaining <= Config.Feel.hotbar.cooldownMinimumDisplaySeconds or chip.cooldownDuration <= 0 then
		setCooldownVisible(chip, false)
		chip.cooldownEndsAt = 0
		if id ~= nil then
			TouchControls.setCooldown(id, 0, nil)
		end
		return
	end
	local fraction = math.clamp(remaining / chip.cooldownDuration, 0, 1)
	local text = formattedRemaining(remaining)
	setCooldownVisible(chip, true)
	chip.cooldownFill.Size = UDim2.fromScale(fraction, 1)
	chip.cooldownLabel.Text = text
	if id ~= nil then
		TouchControls.setCooldown(id, fraction, text)
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
	local id = touchId(chip)
	if id ~= nil then
		TouchControls.setCooldown(id, 0, nil)
		TouchControls.setActive(id, false)
	end
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
	local id = touchId(chip)
	if id ~= nil then
		TouchControls.flash(id, Config.Feel.hotbar.acceptedColor, Config.Feel.hotbar.pulseSeconds)
	end
end

function HotbarController.reject(actionId: string, reason: string?)
	local chip = chipsByAction[actionId]
	if chip == nil then
		return
	end
	local token = playFeedback(chip, Config.Feel.hotbar.deniedColor, Config.Feel.hotbar.deniedFlashSeconds, false)
	local id = touchId(chip)
	if id ~= nil then
		TouchControls.flash(id, Config.Feel.hotbar.deniedColor, Config.Feel.hotbar.deniedFlashSeconds)
	end
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

	-- Dynamite takes a chip in the same row but is NOT a tool: it has no cooldown bar, no wax price and
	-- no active state, and its label is a count rather than a name. It is built after the tools so it
	-- always sits at the end of the row, wherever the tool list grows to.
	local showDynamite = Config.Dynamite.enabled
	local toolsRow = buildRow(root, #Config.Feel.controls.tools + (if showDynamite then 1 else 0))
	toolsRow.Name = "Tools"
	toolsRow.Position = UDim2.fromScale(0, 0.2)
	toolsRow.Size = UDim2.fromScale(1, 0.78)
	for _, control in Config.Feel.controls.tools do
		toolChips[control.toolId] = buildChip(
			toolsRow,
			control.toolId,
			control.keyLabel,
			Config.Tools[control.toolId].displayName,
			"WickTool" .. control.toolId
		)
	end
	if showDynamite then
		local control = Config.Feel.controls.dynamite
		dynamiteChip = buildChip(toolsRow, DYNAMITE_ACTION_ID, control.keyLabel, control.displayName, "WickDynamite")
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
			-- A ghost (server/SpectatorService) has no tools and no default-run strain. Hiding the legend is what makes
			-- spectating read as its own mode instead of a candle whose every key silently stopped working;
			-- client/SpectatorController shows the one control a ghost does have.
			spectating = SpectatorRules.isGhost(entry.alive, entry.finished)
			refreshPanelVisible()
			for toolId, chip in toolChips do
				local active = false
				local displayName = chip.baseName
				if toolId == "Cup" and entry.isCupping then
					active = true
					displayName = Config.Feel.hotbar.uncupDisplayName
				elseif toolId == "Flare" and entry.isFlaring then
					active = true
					displayName = Config.Feel.hotbar.flareDisplayName
				end
				setActive(chip, active)
				local charges = entry.freeToolCharges[toolId] or 0
				local resolvedName = if charges > 0
					then string.format(Config.Feel.hotbar.freeChargeFormat, displayName, charges)
					else displayName
				chip.displayName = if active and (toolId == "Flare" or toolId == "Cup")
					then string.format(Config.Feel.hotbar.activeDisplayFormat, resolvedName)
					else resolvedName
				refreshChipText(chip)
			end
			-- The count IS the label. Dynamite has no active state and no cooldown, so the only thing
			-- its chip has to say is how many sticks are left — and, at zero, that this is why the key
			-- is doing nothing.
			local dynamite = dynamiteChip
			if dynamite ~= nil then
				local control = Config.Feel.controls.dynamite
				local held = math.max(0, math.floor(entry.dynamiteCharges or 0))
				dynamite.displayName = if held > 0
					then string.format(control.countFormat, control.displayName, held)
					else control.emptyDisplayName
				setActive(dynamite, held > 0)
				refreshChipText(dynamite)
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

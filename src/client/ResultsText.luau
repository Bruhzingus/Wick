--!strict
-- Run text + the end-of-run screen. Transient beats (countdown, floor, messages) and the live
-- brazier preview are styled overlays; the results card is a lit cave panel that reveals with a
-- soft rise. It also owns the "Results" cursor release, and clears it defensively on every path
-- back to play or lobby so a finished run can never strand the player with a free cursor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Config = require(ReplicatedStorage.Shared.Config)
local AudioCues = require(script.Parent.AudioCues)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local ResultsText = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local transientLabel: TextLabel? = nil
local previewLabel: TextLabel? = nil
local resultsBackdrop: Frame? = nil
local card: CanvasGroup? = nil
local cardScale: UIScale? = nil
local outcomeLabel: TextLabel? = nil
local flavorLabel: TextLabel? = nil
local statsLabel: TextLabel? = nil
local debugLabel: TextLabel? = nil
local clearAt = 0

local TRANSIENT_SECONDS = 4

local function hideResults()
	CursorController.setReleased("Results", false)
	if card ~= nil then
		card.Visible = false
	end
	if resultsBackdrop ~= nil then
		resultsBackdrop.Visible = false
	end
end

local function hidePreview()
	if previewLabel ~= nil then
		previewLabel.Visible = false
	end
end

local function overlayLabel(gui: ScreenGui, name: string, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.heading
	label.TextColor3 = palette.text
	label.TextScaled = true
	label.Text = ""
	label.Visible = false
	label.Parent = gui
	UITheme.stroke(label, Color3.fromRGB(0, 0, 0), 2, 0.35)
	return label
end

local function showTransient(text: string)
	local label = transientLabel
	if label ~= nil then
		label.Text = text
		label.Visible = true
		label.TextTransparency = 0
		clearAt = os.clock() + TRANSIENT_SECONDS
		task.delay(TRANSIENT_SECONDS, function()
			if os.clock() >= clearAt and label ~= nil then
				label.Visible = false
			end
		end)
	end
end

local function cardLabel(parent: Instance, font: Enum.Font, color: Color3, height: number, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = ""
	label.Size = UDim2.new(1, 0, 0, height)
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function buildCard(gui: ScreenGui)
	-- Unlike the lobby, this overlay sits on top of live (often near-black) gameplay, not a
	-- backdrop of its own. Without a dimming wash behind it, the panel had nothing to contrast
	-- against and read as barely-there. Toggled alongside the card in hideResults/revealCard.
	local backdrop = UITheme.backdrop(gui, 0.2)
	backdrop.Visible = false
	resultsBackdrop = backdrop

	local group = Instance.new("CanvasGroup")
	group.Name = "Results"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.46)
	group.Size = UDim2.fromScale(0.42, 0.6)
	group.BackgroundColor3 = palette.panelRaised
	group.BackgroundTransparency = 0.02
	group.BorderSizePixel = 0
	group.Visible = false
	group.Parent = gui
	UITheme.corner(group, 16)
	UITheme.stroke(group, palette.stroke, 2, 0.15)
	UITheme.uniformPadding(group, 28)
	cardScale = UITheme.scale(group, 1)

	local sheen = Instance.new("UIGradient")
	sheen.Rotation = 90
	sheen.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 46, 48)),
		ColorSequenceKeypoint.new(0.16, palette.panelRaised),
		ColorSequenceKeypoint.new(1, palette.panel),
	})
	sheen.Parent = group

	local layout = UITheme.listLayout(group, 10)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	outcomeLabel = cardLabel(group, UITheme.font.display, palette.gold, 50, 1)

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(0.5, 0, 0, 2)
	divider.BackgroundColor3 = palette.ember
	divider.BackgroundTransparency = 0.3
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 2
	divider.Parent = group
	UITheme.corner(divider, 1)

	flavorLabel = cardLabel(group, UITheme.font.fine, palette.textMuted, 30, 3)
	statsLabel = cardLabel(group, UITheme.font.body, palette.text, 116, 4)
	debugLabel = cardLabel(group, UITheme.font.fine, palette.textDim, 34, 5)
	if debugLabel ~= nil then
		debugLabel.Visible = false
	end

	local restart = UITheme.button(group, "RESTART RUN")
	restart.instance.Size = UDim2.new(1, 0, 0, 46)
	restart.instance.LayoutOrder = 6
	restart.instance.Activated:Connect(function()
		-- The next server event is a countdown, so release the menu claim before asking the server
		-- to restart. First-person input must not wait for a round trip.
		UITheme.flash(restart.instance, palette.chip)
		hideResults()
		Remotes.get("RestartRun"):FireServer()
	end)

	local lobby = UITheme.button(group, "BACK TO LOBBY")
	lobby.instance.Size = UDim2.new(1, 0, 0, 46)
	lobby.instance.LayoutOrder = 7
	lobby.instance.Activated:Connect(function()
		-- Keep the result card open until LobbyState confirms the transition. If another runner is
		-- unresolved, the server can reject the request without leaving this player in limbo.
		UITheme.flash(lobby.instance, palette.chip)
		Remotes.get("ReturnToLobby"):FireServer()
	end)
end

local function revealCard()
	local group = card
	local scale = cardScale
	if group == nil or scale == nil then
		return
	end
	CursorController.setReleased("Results", true)
	if resultsBackdrop ~= nil then
		resultsBackdrop.Visible = true
	end
	group.Visible = true
	group.GroupTransparency = 1
	group.Position = UDim2.fromScale(0.5, 0.5)
	scale.Scale = 0.92
	TweenService:Create(group, UITheme.motion.fade, { GroupTransparency = 0 }):Play()
	TweenService:Create(group, UITheme.motion.rise, { Position = UDim2.fromScale(0.5, 0.46) }):Play()
	TweenService:Create(scale, UITheme.motion.rise, { Scale = 1 }):Play()
end

local function showResults(payload: { [string]: any })
	AudioCues.stop("Draft")
	AudioCues.stop("Water")
	if payload.survived then
		AudioCues.play("BrazierCommit")
	elseif payload.deathCause == "BurnOut" then
		AudioCues.play("DeathBurnOut")
	else
		AudioCues.play("DeathSnuffed")
	end
	hidePreview()

	local outcome = outcomeLabel
	local flavor = flavorLabel
	local stats = statsLabel
	local debug = debugLabel
	if outcome == nil or flavor == nil or stats == nil or debug == nil then
		return
	end

	if payload.survived then
		outcome.Text = "LIGHT DELIVERED"
		outcome.TextColor3 = palette.gold
		flavor.Text = "You carried the light home."
		stats.Text = string.format(
			"Floor %d reached\n%.2f wax delivered\nReward   +%d\nCave tier %d unlocked",
			payload.depthReached or 0,
			payload.waxDelivered or 0,
			payload.reward or 0,
			payload.unlockedTier or 1
		)
		debug.Visible = false
	else
		local burnedOut = payload.deathCause == "BurnOut"
		outcome.Text = if burnedOut then "BURNED OUT" else "SNUFFED"
		outcome.TextColor3 = palette.danger
		flavor.Text = if burnedOut then "Your wax ran dry in the deep." else "The dark reached in and took your flame."
		stats.Text = string.format("Floor %d reached\nNothing delivered.", payload.depthReached or 0)

		local info = payload.deathDebug
		if Config.Feel.debug.showDeathDebug and typeof(info) == "table" then
			debug.Text = string.format(
				"debug · %s · wax %.3f/%.3f · burn %.2f · %s",
				tostring(info.trigger or "Unknown"),
				tonumber(info.waxRemaining) or 0,
				tonumber(info.maxWax) or 0,
				tonumber(info.burnRate) or 0,
				tostring(info.movementMode or "Unknown")
			)
			debug.Visible = true
		else
			debug.Visible = false
		end
	end

	revealCard()
end

function ResultsText.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickText"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	transientLabel = overlayLabel(gui, "Transient", UDim2.fromScale(0.5, 0.14), UDim2.fromScale(0.6, 0.08))
	transientLabel.Font = UITheme.font.display
	transientLabel.TextColor3 = palette.gold
	previewLabel = overlayLabel(gui, "BrazierPreview", UDim2.fromScale(0.5, 0.86), UDim2.fromScale(0.72, 0.05))
	previewLabel.Font = UITheme.font.body
	buildCard(gui)
	card = gui:FindFirstChild("Results") :: CanvasGroup
	gui.Parent = player:WaitForChild("PlayerGui")

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		-- any: remote payloads are untyped at the boundary; fields are read defensively below.
		if kind == "countdown" then
			hideResults()
			showTransient(string.format("Descending in %d…", payload.seconds or 0))
		elseif kind == "floor" then
			hideResults()
			AudioCues.play("FloorEnter")
			showTransient(string.format("Floor %d", payload.depth or 0))
		elseif kind == "message" then
			showTransient(tostring(payload.text or ""))
		elseif kind == "brazierPreview" then
			local preview = previewLabel
			if preview ~= nil then
				if not preview.Visible then
					AudioCues.play("BrazierNear")
				end
				preview.Text = string.format(
					"THE BRAZIER · deliver %.2f wax for +%d light",
					payload.waxDelivered or 0,
					payload.total or 0
				)
				preview.Visible = true
			end
		elseif kind == "brazierPreviewClear" then
			hidePreview()
		elseif kind == "results" then
			showResults(payload)
		end
	end)

	-- Softlock guards: any return to lobby or drop out of the expedition tears down the results
	-- overlay and its cursor claim, even if the normal countdown/floor event never arrives.
	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: any })
		if state.inExpedition ~= true then
			hideResults()
			hidePreview()
		end
	end)
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
			hideResults()
			hidePreview()
		end
	end)
end

return ResultsText

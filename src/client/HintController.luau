--!strict
-- First-three-floor teaching hints. Threat hints come from authoritative server contact;
-- hazard hints come from the local player's replicated exposure transitions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local UITheme = require(script.Parent.UITheme)

local HintController = {}

local player = Players.LocalPlayer
local label: TextLabel? = nil
local backdrop: Frame? = nil
local currentDepth = 1
local active = false
local previousWater = false
local revision = 0
local lastAnyAt = -math.huge
local lastShownAt: { [string]: number } = {}

-- Two kinds of hint share this one panel, and they are throttled differently on purpose.
--
--   A TUTORIAL hint teaches a recurring pressure (water, a moth, falling stone). It can fire again
--   and again, so it is capped by depth and rate-limited: past floor 3 the player has met it.
--
--   An ITEM hint fires the FIRST TIME a pickup is ever collected, and the server has already spent
--   that one chance to send it (Interfaces/Persistence.claimFirstSighting). There is no second
--   showing to fall back on, so it is exempt from the depth cap and from the gap throttle — a hint
--   swallowed because a moth happened to be biting is a hint the player never gets.
local function resolve(hintId: string): (string?, boolean)
	local itemHints = Config.Feel.itemHints
	if itemHints.enabled then
		local itemMessage = itemHints.messages[hintId]
		if itemMessage ~= nil then
			return itemMessage, true
		end
	end
	local hints = Config.Feel.tutorialHints
	if not hints.enabled then
		return nil, false
	end
	return hints.messages[hintId], false
end

local function show(hintId: string)
	local hints = Config.Feel.tutorialHints
	local message, oneShot = resolve(hintId)
	local text = label
	local panel = backdrop
	if not active or message == nil or text == nil or panel == nil then
		return
	end
	if not oneShot and currentDepth > hints.maxDepth then
		return
	end

	local now = os.clock()
	if not oneShot then
		if now - (lastShownAt[hintId] or -math.huge) < hints.repeatCooldownSeconds then
			return
		end
		if now - lastAnyAt < hints.minimumGapSeconds then
			return
		end
	end
	lastShownAt[hintId] = now
	lastAnyAt = now
	revision += 1
	local thisRevision = revision

	text.Text = message
	text.TextTransparency = 1
	panel.BackgroundTransparency = 1
	text.Visible = true
	panel.Visible = true
	TweenService:Create(text, TweenInfo.new(hints.fadeSeconds), { TextTransparency = 0 }):Play()
	TweenService:Create(panel, TweenInfo.new(hints.fadeSeconds), { BackgroundTransparency = 0.28 }):Play()

	task.delay(hints.displaySeconds, function()
		if revision ~= thisRevision or text.Parent == nil or panel.Parent == nil then
			return
		end
		local textFade = TweenService:Create(text, TweenInfo.new(hints.fadeSeconds), { TextTransparency = 1 })
		local panelFade = TweenService:Create(panel, TweenInfo.new(hints.fadeSeconds), { BackgroundTransparency = 1 })
		textFade.Completed:Connect(function()
			if revision == thisRevision then
				text.Visible = false
				panel.Visible = false
			end
		end)
		textFade:Play()
		panelFade:Play()
	end)
end

function HintController.start()
	local hints = Config.Feel.tutorialHints
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickTutorialHints"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = hints.displayOrder

	local panel = Instance.new("Frame")
	panel.Name = "HintBackdrop"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = hints.position
	panel.Size = hints.size
	panel.BackgroundColor3 = UITheme.palette.void
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	UITheme.corner(panel, 7)
	UITheme.stroke(panel, UITheme.palette.strokeSoft, 1, 0.55)
	backdrop = panel

	local text = Instance.new("TextLabel")
	text.Name = "HintText"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = UITheme.font.body
	text.TextColor3 = UITheme.palette.text
	text.TextWrapped = true
	text.TextScaled = true
	text.TextTransparency = 1
	text.Visible = false
	text.Parent = panel
	UITheme.uniformPadding(text, 8)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = hints.maxTextSize
	constraint.Parent = text
	label = text

	gui.Parent = player:WaitForChild("PlayerGui")

	Remotes.get("TutorialHint").OnClientEvent:Connect(function(hintId: unknown)
		if type(hintId) == "string" then
			show(hintId)
		end
	end)

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			local depthChanged = entry.depth ~= currentDepth
			currentDepth = entry.depth
			active = entry.alive and not entry.finished
			local inWater = entry.water == "Wading"
			if active and currentDepth <= hints.maxDepth then
				if inWater and (not previousWater or depthChanged) then
					show("Water")
				end
			end
			previousWater = inWater
			break
		end
	end)
end

return HintController

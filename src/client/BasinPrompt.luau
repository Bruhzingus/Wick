--!strict
-- The Basin offer screen — the run's hard choice. A lit stone bowl asks for a sacrifice; you pick
-- what it takes (tap a card or press its number). Presentation only: the server rolls the offers,
-- validates the pick, and applies it. Owns its "Basin" cursor release and clears it on every close.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local BasinPrompt = {}

local player = Players.LocalPlayer
local palette = UITheme.palette

type OfferPayload = { id: string, displayName: string, description: string, toolId: string?, waxGranted: number }

local NUMBER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local gui: ScreenGui? = nil
local submitting = false
local statusLabel: TextLabel? = nil

local function close()
	local current = gui
	if current ~= nil then
		current:Destroy()
		gui = nil
	end
	submitting = false
	statusLabel = nil
	CursorController.setReleased("Basin", false)
	for index = 1, #NUMBER_KEYS do
		ContextActionService:UnbindAction("WickBasinChoice" .. index)
	end
end

local function choose(index: number)
	if gui == nil or submitting then
		return
	end
	submitting = true
	if statusLabel ~= nil then
		statusLabel.Text = "The Basin considers your offering..."
	end
	Remotes.get("BasinChoose"):FireServer(index)
end

local function buildOfferCard(parent: Instance, index: number, offer: OfferPayload)
	local card = UITheme.button(parent, "")
	card.instance.Size = UDim2.new(1, 0, 0, 84)
	card.instance.LayoutOrder = index
	card.instance.Activated:Connect(function()
		choose(index)
	end)

	local badge = Instance.new("TextLabel")
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.fromScale(0, 0.5)
	badge.Size = UDim2.fromOffset(34, 34)
	badge.BackgroundColor3 = palette.chipActive
	badge.Font = UITheme.font.display
	badge.Text = tostring(index)
	badge.TextColor3 = palette.gold
	badge.TextScaled = true
	badge.Parent = card.instance
	UITheme.corner(badge, 8)
	UITheme.uniformPadding(badge, 6)

	local name = Instance.new("TextLabel")
	name.Position = UDim2.fromOffset(46, 8)
	name.Size = UDim2.new(1, -160, 0, 26)
	name.BackgroundTransparency = 1
	name.Font = UITheme.font.heading
	name.Text = if offer.toolId ~= nil
		then string.format("%s  (%s)", offer.displayName, offer.toolId)
		else offer.displayName
	name.TextColor3 = palette.text
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true
	name.Parent = card.instance
	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MinTextSize = UITheme.textSize.fine
	nameConstraint.MaxTextSize = UITheme.textSize.strong
	nameConstraint.Parent = name

	local description = Instance.new("TextLabel")
	description.Position = UDim2.fromOffset(46, 36)
	description.Size = UDim2.new(1, -58, 0, 40)
	description.BackgroundTransparency = 1
	description.Font = UITheme.font.fine
	description.Text = offer.description
	description.TextColor3 = palette.textMuted
	description.TextSize = UITheme.textSize.fine
	description.TextWrapped = true
	description.TextXAlignment = Enum.TextXAlignment.Left
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.Parent = card.instance

	local reward = Instance.new("TextLabel")
	reward.AnchorPoint = Vector2.new(1, 0.5)
	reward.Position = UDim2.new(1, -12, 0, 21)
	reward.Size = UDim2.new(0.32, 0, 0, 24)
	reward.BackgroundTransparency = 1
	reward.Font = UITheme.font.body
	reward.Text = string.format("+%.2f wax", offer.waxGranted)
	reward.TextColor3 = palette.gold
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.TextScaled = true
	reward.Parent = card.instance
	local rewardConstraint = Instance.new("UITextSizeConstraint")
	rewardConstraint.MinTextSize = UITheme.textSize.micro
	rewardConstraint.MaxTextSize = UITheme.textSize.body
	rewardConstraint.Parent = reward
end

local function show(offers: { OfferPayload })
	close()
	AudioCues.play("BasinOpen")
	local screen = Instance.new("ScreenGui")
	screen.Name = "WickBasin"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 15
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	UITheme.backdrop(screen, 0.4)

	local panel = Instance.new("CanvasGroup")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.56, 0.72)
	panel.BackgroundColor3 = palette.panel
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.ZIndex = 1
	panel.Parent = screen
	UITheme.corner(panel, 16)
	UITheme.stroke(panel, palette.stroke, 1.5, 0.3)
	UITheme.uniformPadding(panel, 26)
	local panelScale = UITheme.scale(panel, 0.92)
	UITheme.listLayout(panel, 10)

	local header = UITheme.heading(panel, "THE BASIN")
	header.Size = UDim2.new(1, 0, 0, 44)
	header.LayoutOrder = 1

	local subtitle = UITheme.label(panel, "It always takes something. Choose what it takes.", 26)
	subtitle.Font = UITheme.font.fine
	subtitle.TextColor3 = palette.textMuted
	subtitle.LayoutOrder = 2
	statusLabel = subtitle

	local list = Instance.new("Frame")
	list.Name = "Offers"
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, 0, 1, -84)
	list.LayoutOrder = 3
	list.Parent = panel
	UITheme.listLayout(list, 8)

	for index, offer in offers do
		buildOfferCard(list, index, offer)
		if NUMBER_KEYS[index] ~= nil then
			ContextActionService:BindAction("WickBasinChoice" .. index, function(_name, inputState)
				if inputState == Enum.UserInputState.Begin then
					choose(index)
				end
				return Enum.ContextActionResult.Sink
			end, false, NUMBER_KEYS[index])
		end
	end

	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	CursorController.setReleased("Basin", true)

	-- Soft reveal.
	panel.GroupTransparency = 1
	TweenService:Create(panel, UITheme.motion.fade, { GroupTransparency = 0 }):Play()
	TweenService:Create(panelScale, UITheme.motion.rise, { Scale = 1 }):Play()
end

function BasinPrompt.start()
	Remotes.get("BasinOffers").OnClientEvent:Connect(function(offers: { OfferPayload })
		if typeof(offers) == "table" and #offers > 0 then
			show(offers)
		end
	end)
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: unknown }?)
		if kind == "basinChoice" and gui ~= nil then
			local accepted = payload ~= nil and payload.accepted == true
			if accepted then
				AudioCues.play("BasinChoose")
				close()
			elseif payload ~= nil and payload.retryable == true then
				submitting = false
				if statusLabel ~= nil then
					local reason = payload.reason
					statusLabel.Text = if typeof(reason) == "string" then reason else "Move closer and try again."
				end
			else
				close()
			end
			return
		end
		if kind == "results" or kind == "countdown" or kind == "floor" then
			close()
		end
	end)
	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId == player.UserId then
				if not entry.alive or entry.finished then
					close()
				end
				break
			end
		end
	end)
	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: unknown })
		if state.inExpedition ~= true then
			close()
		end
	end)
end

return BasinPrompt

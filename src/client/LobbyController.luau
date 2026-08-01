--!strict
-- The physical lobby ("The Landing") now owns tier-select/ready/start entirely through its
-- elevators (see server/ElevatorService, client/ElevatorController). This controller's job shrank
-- to what still has no in-world home: toggling gameplay input/GUIs across the lobby<->expedition
-- boundary, and surfacing the server's informational lobby status as small, non-modal text (leader
-- validation messages, teleport/arrival status) rather than a full-screen panel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local UITheme = require(script.Parent.UITheme)

local LobbyController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local STATUS_SECONDS = 4

local GAMEPLAY_GUIS = {
	WickDial = true,
	WickHotbar = true,
	WickWaxBar = true,
	WickText = true,
}

local statusLabel: TextLabel? = nil
local clearStatusAt = 0

local function setGameplayGuiEnabled(enabled: boolean)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, child in playerGui:GetChildren() do
		if child:IsA("ScreenGui") and GAMEPLAY_GUIS[child.Name] then
			child.Enabled = enabled
		end
	end
end

local function setExpeditionMode(enabled: boolean)
	player:SetAttribute(EXPEDITION_ATTRIBUTE, enabled)
	setGameplayGuiEnabled(enabled)
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickLobby"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -28)
	label.Size = UDim2.new(0.7, 0, 0, 26)
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.fine
	label.Text = ""
	label.TextColor3 = palette.gold
	label.TextScaled = true
	label.TextTransparency = 0
	label.Visible = false
	label.Parent = gui
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = UITheme.textSize.fine
	constraint.MaxTextSize = UITheme.textSize.strong
	constraint.Parent = label
	UITheme.legible(label, 0.7)
	statusLabel = label

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function showStatus(text: string)
	local label = statusLabel
	if label == nil or text == "" then
		return
	end
	label.Text = text
	label.Visible = true
	clearStatusAt = os.clock() + STATUS_SECONDS
	task.delay(STATUS_SECONDS, function()
		if os.clock() >= clearStatusAt and label ~= nil then
			label.Visible = false
		end
	end)
end

function LobbyController.start()
	setExpeditionMode(false)
	build()
	-- `any` is confined to this untyped RemoteEvent boundary; every field is checked before use.
	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: any })
		setExpeditionMode(state.inExpedition == true)
		showStatus(tostring(state.status or ""))
	end)
	Remotes.get("LobbyAction"):FireServer("sync")
end

return LobbyController

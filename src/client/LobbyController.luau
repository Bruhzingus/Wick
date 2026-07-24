--!strict
-- Minimal party/tier lobby. It is intentionally built from primitives so a published prototype
-- can form a friend party without requiring finished art or a separate hub place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CursorController = require(script.Parent.CursorController)

local LobbyController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local screen: ScreenGui? = nil
local partyText: TextLabel? = nil
local tierText: TextLabel? = nil
local statusText: TextLabel? = nil
local readyButton: TextButton? = nil
local startButton: TextButton? = nil
local tierButtons: Frame? = nil
local localReady = false
local GAMEPLAY_GUIS = {
	WickDial = true,
	WickHotbar = true,
	WickWaxBar = true,
	WickText = true,
}

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
	CursorController.setReleased("Lobby", not enabled)
end

local function label(parent: Instance, text: string, height: number): TextLabel
	local result = Instance.new("TextLabel")
	result.Size = UDim2.new(1, -24, 0, height)
	result.BackgroundTransparency = 1
	result.TextColor3 = Color3.fromRGB(230, 222, 205)
	result.TextWrapped = true
	result.TextScaled = true
	result.Font = Enum.Font.Gotham
	result.Text = text
	result.Parent = parent
	return result
end

local function button(parent: Instance, text: string): TextButton
	local result = Instance.new("TextButton")
	result.Size = UDim2.new(1, -24, 0, 42)
	result.BackgroundColor3 = Color3.fromRGB(60, 48, 42)
	result.BorderSizePixel = 0
	result.TextColor3 = Color3.fromRGB(255, 220, 175)
	result.TextScaled = true
	result.Font = Enum.Font.GothamBold
	result.Text = text
	result.Parent = parent
	return result
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickLobby"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	local background = Instance.new("Frame")
	background.Name = "Panel"
	background.AnchorPoint = Vector2.new(0.5, 0.5)
	background.Position = UDim2.fromScale(0.5, 0.5)
	background.Size = UDim2.fromScale(0.42, 0.7)
	background.BackgroundColor3 = Color3.fromRGB(12, 11, 14)
	background.BackgroundTransparency = 0.08
	background.BorderSizePixel = 0
	background.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = background

	label(background, "WICK", 56).Font = Enum.Font.GothamBlack
	label(background, "Choose a cave. Ready together. The leader starts the descent.", 54)
	partyText = label(background, "Party", 110)
	tierText = label(background, "Cave tier", 34)

	local tiers = Instance.new("Frame")
	tiers.Size = UDim2.new(1, -24, 0, 82)
	tiers.BackgroundTransparency = 1
	tiers.Parent = background
	local tierLayout = Instance.new("UIListLayout")
	tierLayout.FillDirection = Enum.FillDirection.Horizontal
	tierLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tierLayout.Padding = UDim.new(0, 6)
	tierLayout.Parent = tiers
	tierButtons = tiers

	local ready = button(background, "READY")
	ready.Activated:Connect(function()
		localReady = not localReady
		Remotes.get("LobbyAction"):FireServer("ready", localReady)
	end)
	readyButton = ready

	local start = button(background, "START EXPEDITION")
	start.Activated:Connect(function()
		Remotes.get("LobbyAction"):FireServer("start")
	end)
	startButton = start

	statusText = label(background, "", 50)

	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui
end

local function rebuildTiers(tiers: { any }, selectedTier: number, unlockedTier: number, isLeader: boolean)
	local container = tierButtons
	if container == nil then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, tier in tiers do
		local tierId = tonumber(tier.id) or 1
		local required = tonumber(tier.requiredCurrency) or 0
		local unlocked = tierId <= unlockedTier
		local choice = Instance.new("TextButton")
		choice.Size = UDim2.new(0.31, 0, 1, 0)
		choice.BackgroundColor3 = if tierId == selectedTier
			then Color3.fromRGB(105, 64, 35)
			else Color3.fromRGB(38, 35, 40)
		choice.BorderSizePixel = 0
		choice.TextColor3 = if unlocked then Color3.fromRGB(235, 220, 195) else Color3.fromRGB(115, 108, 105)
		choice.TextScaled = true
		choice.TextWrapped = true
		choice.Text = string.format(
			"%s\n%s",
			tostring(tier.displayName or "Cave"),
			if unlocked then "UNLOCKED" else string.format("%d currency", required)
		)
		choice.Active = isLeader and unlocked
		choice.Activated:Connect(function()
			if isLeader and unlocked then
				Remotes.get("LobbyAction"):FireServer("tier", tierId)
			end
		end)
		choice.Parent = container
	end
end

function LobbyController.start()
	setExpeditionMode(false)
	build()
	-- `any` is confined to this untyped RemoteEvent boundary; every field is checked before use.
	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: any })
		local gui = screen
		if gui == nil then
			return
		end
		if state.inExpedition == true then
			gui.Enabled = false
			setExpeditionMode(true)
			return
		end
		setExpeditionMode(false)
		gui.Enabled = true

		local members = if typeof(state.members) == "table" then state.members else {}
		local lines = { "PARTY" }
		localReady = false
		for _, member in members do
			local memberId = tonumber(member.playerId) or 0
			local isReady = member.ready == true
			table.insert(
				lines,
				string.format(
					"%s  %s",
					tostring(member.displayName or memberId),
					if isReady then "READY" else "WAITING"
				)
			)
			if memberId == player.UserId then
				localReady = isReady
			end
		end
		if partyText ~= nil then
			partyText.Text = table.concat(lines, "\n")
		end

		local selectedTier = tonumber(state.tierId) or 1
		local unlockedTier = tonumber(state.unlockedTier) or 1
		if tierText ~= nil then
			tierText.Text =
				string.format("SELECTED TIER %d  |  CURRENCY %d", selectedTier, tonumber(state.currency) or 0)
		end
		local isLeader = tonumber(state.leaderId) == player.UserId
		rebuildTiers(if typeof(state.tiers) == "table" then state.tiers else {}, selectedTier, unlockedTier, isLeader)
		if readyButton ~= nil then
			readyButton.Text = if localReady then "UNREADY" else "READY"
		end
		if startButton ~= nil then
			startButton.Visible = isLeader
		end
		if statusText ~= nil then
			statusText.Text = tostring(state.status or "")
		end
	end)
	Remotes.get("LobbyAction"):FireServer("sync")
end

return LobbyController

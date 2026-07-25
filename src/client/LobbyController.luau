--!strict
-- Party/tier lobby — the game's front door. Cave-mouth panel: your party gathers by candlelight,
-- the leader picks a cave everyone has unlocked, everyone readies, the leader lights the descent.
-- Presentation only; the server owns membership, unlocks, and the start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local LobbyController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local screen: ScreenGui? = nil
local partyList: Frame? = nil
local tierText: TextLabel? = nil
local statusText: TextLabel? = nil
local readyButton: UITheme.Button? = nil
local startButton: UITheme.Button? = nil
local tierRow: Frame? = nil
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

local function sectionHeader(parent: Instance, text: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.heading
	label.Text = text
	label.TextColor3 = palette.textMuted
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	label.Size = UDim2.new(1, 0, 0, 16)
	label.LayoutOrder = order
	label.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 15
	constraint.Parent = label
	return label
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickLobby"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	-- Descendants must always render above their panel background. The themed rewrite gave the
	-- panel ZIndex 2 while its buttons remained at 1, causing the panel to cover its own content.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	UITheme.backdrop(gui, 0.35)

	local root = UITheme.panel(gui)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(0.4, 0.8)
	root.ZIndex = 1
	UITheme.uniformPadding(root, 26)
	local rootScale = UITheme.scale(root, 1)

	UITheme.listLayout(root, 12)

	-- The WICK logo: gilded letters with a live candle for the "I". Same mark as the loading screen.
	local logo = UITheme.wordmark(root, 64)
	logo.LayoutOrder = 1

	-- Arrive with a soft rise-and-settle, the same motion the results and settings cards use.
	UITheme.rise(root, rootScale, UDim2.fromScale(0.5, 0.5))

	local tagline = UITheme.label(root, "Descend by candlelight. Feed the brazier. Carry the light home.", 30)
	tagline.Font = UITheme.font.fine
	tagline.TextColor3 = palette.textMuted
	tagline.LayoutOrder = 2

	-- Below Graphics quality 5, Roblox falls back to voxel-grid lighting instead of per-pixel
	-- shadows, which shows up in-game as shadows lagging behind the player's own candle light.
	-- There is no scriptable way to raise a player's own quality setting, so this is the fix.
	local graphicsNote =
		UITheme.label(root, "For accurate shadows, set Graphics to 5 or higher in the Roblox menu.", 20)
	graphicsNote.Font = UITheme.font.fine
	graphicsNote.TextColor3 = palette.textDim
	graphicsNote.LayoutOrder = 3

	-- A softly breathing ember divider — the panel feels lit rather than printed.
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(0.7, 0, 0, 2)
	divider.BackgroundColor3 = palette.ember
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 4
	divider.Parent = root
	UITheme.corner(divider, 1)
	TweenService:Create(
		divider,
		TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.6 }
	):Play()

	sectionHeader(root, "YOUR PARTY", 5)

	local party = Instance.new("Frame")
	party.Name = "PartyList"
	party.BackgroundTransparency = 1
	party.Size = UDim2.new(1, 0, 0, 140)
	party.LayoutOrder = 6
	party.Parent = root
	local partyLayout = UITheme.listLayout(party, 6)
	partyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	partyList = party

	local tierHeader = sectionHeader(root, "CHOOSE A CAVE", 7)
	tierText = tierHeader

	local tiers = Instance.new("Frame")
	tiers.Name = "TierRow"
	tiers.Size = UDim2.new(1, 0, 0, 92)
	tiers.BackgroundTransparency = 1
	tiers.LayoutOrder = 8
	tiers.Parent = root
	local tierLayout = Instance.new("UIListLayout")
	tierLayout.FillDirection = Enum.FillDirection.Horizontal
	tierLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tierLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tierLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tierLayout.Padding = UDim.new(0, 8)
	tierLayout.Parent = tiers
	tierRow = tiers

	local ready = UITheme.button(root, "READY")
	ready.instance.Size = UDim2.new(1, 0, 0, 46)
	ready.instance.LayoutOrder = 9
	ready.instance.Activated:Connect(function()
		localReady = not localReady
		UITheme.flash(ready.instance, if localReady then palette.chipActive else palette.chip)
		Remotes.get("LobbyAction"):FireServer("ready", localReady)
	end)
	readyButton = ready

	local start = UITheme.button(root, "LIGHT THE DESCENT")
	start.instance.Size = UDim2.new(1, 0, 0, 46)
	start.instance.LayoutOrder = 10
	start.instance.TextColor3 = palette.text
	start.instance.Activated:Connect(function()
		UITheme.flash(start.instance, palette.chip)
		Remotes.get("LobbyAction"):FireServer("start")
	end)
	startButton = start

	local status = UITheme.label(root, "", 30)
	status.Font = UITheme.font.fine
	status.TextColor3 = palette.gold
	status.LayoutOrder = 11
	statusText = status

	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui
end

local function statusPill(parent: Instance, ready: boolean): Frame
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(1, 0.5)
	pill.Position = UDim2.fromScale(1, 0.5)
	pill.Size = UDim2.fromOffset(84, 24)
	pill.BackgroundColor3 = if ready then palette.chipActive else palette.chip
	pill.BorderSizePixel = 0
	pill.Parent = parent
	UITheme.corner(pill, 12)
	UITheme.stroke(pill, if ready then palette.ember else palette.strokeSoft, 1, if ready then 0.1 else 0.5)

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = UITheme.font.heading
	text.Text = if ready then "LIT" else "WAITING"
	text.TextColor3 = if ready then palette.gold else palette.textDim
	text.TextScaled = true
	text.Parent = pill
	UITheme.uniformPadding(text, 5)
	return pill
end

local function rebuildParty(members: { any })
	local container = partyList
	if container == nil then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	localReady = false
	for index, member in members do
		local memberId = tonumber(member.playerId) or 0
		local isReady = member.ready == true
		local isLeader = member.isLeader == true
		if memberId == player.UserId then
			localReady = isReady
		end

		local row = Instance.new("Frame")
		row.Name = "Member"
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3 = palette.panelRaised
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Parent = container
		UITheme.corner(row, 8)
		UITheme.padding(row, 0, 10, 0, 12)

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.Position = UDim2.fromScale(0, 0.5)
		name.Size = UDim2.fromScale(0.7, 0.7)
		name.Font = UITheme.font.body
		name.Text = if isLeader
			then "★ " .. tostring(member.displayName or memberId)
			else tostring(member.displayName or memberId)
		name.TextColor3 = if isLeader then palette.gold else palette.text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextScaled = true
		name.Parent = row
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = 16
		constraint.Parent = name

		statusPill(row, isReady)
	end
end

local function rebuildTiers(tiers: { any }, selectedTier: number, unlockedTier: number, isLeader: boolean)
	local container = tierRow
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
		local selected = tierId == selectedTier

		local card = UITheme.button(container, "")
		card.instance.Size = UDim2.fromScale(0.31, 1)
		card.instance.Text = ""
		card.instance.LayoutOrder = tierId
		card.setActive(selected)
		card.setEnabled(isLeader and unlocked)

		local caveName = Instance.new("TextLabel")
		caveName.BackgroundTransparency = 1
		caveName.Position = UDim2.fromScale(0, 0.12)
		caveName.Size = UDim2.fromScale(1, 0.42)
		caveName.Font = UITheme.font.heading
		caveName.Text = tostring(tier.displayName or "Cave")
		caveName.TextColor3 = if unlocked then palette.text else palette.textDim
		caveName.TextScaled = true
		caveName.Parent = card.instance
		local nameConstraint = Instance.new("UITextSizeConstraint")
		nameConstraint.MaxTextSize = 17
		nameConstraint.Parent = caveName

		local state = Instance.new("TextLabel")
		state.BackgroundTransparency = 1
		state.Position = UDim2.fromScale(0, 0.56)
		state.Size = UDim2.fromScale(1, 0.32)
		state.Font = UITheme.font.fine
		state.Text = if not unlocked
			then string.format("🔒 %d", required)
			elseif selected then "SELECTED"
			else "UNLOCKED"
		state.TextColor3 = if selected then palette.gold elseif unlocked then palette.textMuted else palette.textDim
		state.TextScaled = true
		state.Parent = card.instance
		local stateConstraint = Instance.new("UITextSizeConstraint")
		stateConstraint.MaxTextSize = 13
		stateConstraint.Parent = state

		card.instance.Activated:Connect(function()
			if isLeader and unlocked then
				Remotes.get("LobbyAction"):FireServer("tier", tierId)
			end
		end)
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
		local leaderId = tonumber(state.leaderId)
		for _, member in members do
			member.isLeader = tonumber(member.playerId) == leaderId
		end
		rebuildParty(members)

		local selectedTier = tonumber(state.tierId) or 1
		local unlockedTier = tonumber(state.unlockedTier) or 1
		if tierText ~= nil then
			tierText.Text = string.format("CHOOSE A CAVE   ·   %d CURRENCY", tonumber(state.currency) or 0)
		end
		local isLeader = leaderId == player.UserId
		rebuildTiers(if typeof(state.tiers) == "table" then state.tiers else {}, selectedTier, unlockedTier, isLeader)
		if readyButton ~= nil then
			readyButton.instance.Text = if localReady then "STAND DOWN" else "READY"
			readyButton.setActive(localReady)
		end
		if startButton ~= nil then
			startButton.instance.Visible = isLeader
		end
		if statusText ~= nil then
			statusText.Text = tostring(state.status or "")
		end
	end)
	Remotes.get("LobbyAction"):FireServer("sync")
end

return LobbyController

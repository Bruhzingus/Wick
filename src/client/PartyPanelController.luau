--!strict
-- The interactive party surface that appears while the local player stands in an elevator. The
-- server owns membership, leadership, readiness, voting, admission and removals; this controller
-- releases the shift-locked cursor and renders those decisions as buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local PartyPanelController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local textSize = UITheme.textSize
local CURSOR_OWNER = "PartyPanel"

type MemberView = {
	displayName: string,
	ready: boolean,
	playerId: number,
}

type CaveBenefit = {
	payoutPermille: number,
	nativeOreTier: number,
}

type CaveCard = {
	button: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	cost: TextLabel,
	benefit: TextLabel,
	count: TextLabel,
}

local gui: ScreenGui? = nil
local panel: ScrollingFrame? = nil
local panelScale: UIScale? = nil
local titleLabel: TextLabel? = nil
local phaseLabel: TextLabel? = nil
local caveHeading: TextLabel? = nil
local leaderHint: TextLabel? = nil
local slotFrames: { Frame } = {}
local slotNames: { TextLabel } = {}
local slotStates: { TextLabel } = {}
local slotKickButtons: { TextButton } = {}
local slotTargetIds: { number } = {}
local readyButton: TextButton? = nil
local leaveButton: TextButton? = nil
local caveCards: { [number]: CaveCard } = {}
local localReady = false
local panelVisible = false

-- Static benefits are read from the authoritative family rows. Dynamic price, ownership and
-- affordability still arrive from the server on LobbyState.
local caveBenefits: { [number]: CaveBenefit } = {}
for _, family in Config.CaveFamilies.families do
	caveBenefits[family.legacyTierId] = {
		payoutPermille = family.payoutPermille,
		nativeOreTier = family.ore.nativeTier,
	}
end

local function formatInteger(value: number): string
	local digits = tostring(math.max(0, math.floor(value)))
	local result = ""
	while #digits > 3 do
		result = "," .. string.sub(digits, -3) .. result
		digits = string.sub(digits, 1, #digits - 3)
	end
	return digits .. result
end

local function setPanelVisible(visible: boolean)
	local screen = gui
	if screen == nil then
		return
	end
	if panelVisible == visible then
		return
	end
	panelVisible = visible
	screen.Enabled = visible
	-- CursorController applies after Roblox's first-person camera, so these buttons remain clickable
	-- even though the lobby avatar itself stays shift-locked.
	CursorController.setReleased(CURSOR_OWNER, visible)
end

local function textLabel(parent: GuiObject, name: string, size: UDim2, font: Enum.Font, sizePx: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = sizePx
	label.TextColor3 = palette.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function buildPartySlot(parent: Frame, index: number)
	local slot = Instance.new("Frame")
	slot.Name = "Slot" .. tostring(index)
	slot.LayoutOrder = 2 + index
	slot.Size = UDim2.new(1, 0, 0, 34)
	slot.BackgroundColor3 = palette.chip
	slot.BackgroundTransparency = 0.55
	slot.BorderSizePixel = 0
	slot.Parent = parent
	UITheme.corner(slot, 8)

	local name = textLabel(slot, "Name", UDim2.new(0.53, -10, 1, 0), UITheme.font.body, textSize.fine)
	name.Position = UDim2.fromOffset(10, 0)
	name.TextColor3 = palette.textDim
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = "empty"

	local state = textLabel(slot, "State", UDim2.new(0.26, 0, 1, 0), UITheme.font.heading, textSize.micro)
	state.Position = UDim2.new(0.53, 0, 0, 0)
	state.TextXAlignment = Enum.TextXAlignment.Right
	state.TextColor3 = palette.ember
	state.Text = ""

	local kick = Instance.new("TextButton")
	kick.Name = "Kick"
	kick.AnchorPoint = Vector2.new(1, 0.5)
	kick.Position = UDim2.new(1, -5, 0.5, 0)
	kick.Size = UDim2.fromOffset(58, 26)
	kick.BackgroundColor3 = palette.emberDeep
	kick.BackgroundTransparency = 0.16
	kick.BorderSizePixel = 0
	kick.AutoButtonColor = true
	kick.Font = UITheme.font.heading
	kick.TextSize = textSize.micro
	kick.TextColor3 = palette.text
	kick.Text = "KICK"
	kick.Visible = false
	kick.Parent = slot
	UITheme.corner(kick, 6)
	kick.Activated:Connect(function()
		local targetId = slotTargetIds[index]
		if targetId ~= nil and targetId > 0 then
			Remotes.get("LobbyAction"):FireServer("kick", targetId)
		end
	end)

	table.insert(slotFrames, slot)
	table.insert(slotNames, name)
	table.insert(slotStates, state)
	table.insert(slotKickButtons, kick)
	slotTargetIds[index] = 0
end

local function buildCaveCard(parent: Frame, tierId: number, order: number)
	local button = Instance.new("TextButton")
	button.Name = "Cave" .. tostring(tierId)
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 68)
	button.BackgroundColor3 = palette.chip
	button.BackgroundTransparency = 0.12
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent
	UITheme.corner(button, 9)
	local cardStroke = UITheme.stroke(button, palette.strokeSoft, 1, 0.35)

	local name = textLabel(button, "Name", UDim2.new(0.72, -12, 0, 22), UITheme.font.heading, textSize.fine)
	name.Position = UDim2.fromOffset(10, 5)
	name.TextColor3 = palette.gold
	name.Text = "CAVE"

	local count = textLabel(button, "Count", UDim2.new(0.28, -10, 0, 22), UITheme.font.heading, textSize.micro)
	count.Position = UDim2.new(0.72, 0, 0, 5)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = palette.ember
	count.Text = ""

	local cost = textLabel(button, "Cost", UDim2.new(1, -20, 0, 18), UITheme.font.fine, textSize.micro)
	cost.Position = UDim2.fromOffset(10, 26)
	cost.TextColor3 = palette.textMuted
	cost.Text = "ENTRY FREE"

	local benefit = textLabel(button, "Benefit", UDim2.new(1, -20, 0, 18), UITheme.font.fine, textSize.micro)
	benefit.Position = UDim2.fromOffset(10, 44)
	benefit.TextColor3 = palette.textDim
	benefit.Text = ""

	button.Activated:Connect(function()
		if button.Active then
			Remotes.get("LobbyAction"):FireServer("vote", tierId)
		end
	end)

	caveCards[tierId] = {
		button = button,
		stroke = cardStroke,
		name = name,
		cost = cost,
		benefit = benefit,
		count = count,
	}
end

-- The panel is authored at 356x610 but must never exceed the actual screen: on a short mobile
-- viewport a fixed offset height pushes the lower rows (caves, LEAVE ELEVATOR) past the bottom of
-- the screen with no way to reach them. Clamp to the viewport like `UpdateLogController.applyLayout`
-- and `ShopController.applyLayout`; the panel is a ScrollingFrame so content that still doesn't fit
-- at the clamped size scrolls instead of being cut off.
local function applyLayout()
	local screen = gui
	local panelFrame = panel
	local scale = panelScale
	if screen == nil or panelFrame == nil or scale == nil then
		return
	end
	local viewport = screen.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	local density = UITheme.density()
	scale.Scale = density
	local availableX = viewport.X / density
	local availableY = viewport.Y / density
	local margin = if availableY < 480 then 12 else 24
	local width = math.min(356, math.max(260, availableX - margin * 2))
	local height = math.min(610, math.max(280, availableY - margin * 2))
	panelFrame.Size = UDim2.fromOffset(width, height)
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WickPartyPanel"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 18
	screen.Enabled = false

	local panelFrame = Instance.new("ScrollingFrame")
	panelFrame.Name = "Panel"
	panelFrame.AnchorPoint = Vector2.new(1, 0.5)
	panelFrame.Position = UDim2.new(1, -24, 0.5, 0)
	panelFrame.Size = UDim2.fromOffset(356, 610)
	panelFrame.BackgroundColor3 = palette.panel
	panelFrame.BackgroundTransparency = 0.06
	panelFrame.BorderSizePixel = 0
	panelFrame.ScrollBarThickness = 5
	panelFrame.ScrollBarImageColor3 = palette.stroke
	panelFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panelFrame.CanvasSize = UDim2.new()
	panelFrame.Parent = screen
	UITheme.corner(panelFrame, 14)
	UITheme.stroke(panelFrame, palette.stroke, 1.5, 0.25)
	panel = panelFrame

	panelScale = UITheme.scale(panelFrame, UITheme.density())

	UITheme.padding(panel, 14, 14, 14, 14)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 7)
	layout.Parent = panel

	local title = textLabel(panel, "Title", UDim2.new(1, 0, 0, 28), UITheme.font.display, textSize.title)
	title.LayoutOrder = 1
	title.TextColor3 = palette.gold
	title.Text = "PARTY"
	UITheme.legible(title, 0.7)
	titleLabel = title

	local phase = textLabel(panel, "Phase", UDim2.new(1, 0, 0, 24), UITheme.font.fine, textSize.fine)
	phase.LayoutOrder = 2
	phase.TextColor3 = palette.textDim
	phase.Text = ""
	phaseLabel = phase

	for index = 1, Config.Run.partyCap do
		buildPartySlot(panel, index)
	end

	local ready = Instance.new("TextButton")
	ready.Name = "Ready"
	ready.LayoutOrder = 20
	ready.Size = UDim2.new(1, 0, 0, 38)
	ready.BackgroundColor3 = palette.chip
	ready.BorderSizePixel = 0
	ready.AutoButtonColor = true
	ready.Font = UITheme.font.heading
	ready.TextSize = textSize.strong
	ready.TextColor3 = palette.gold
	ready.Text = "READY UP"
	ready.Parent = panel
	UITheme.corner(ready, 9)
	UITheme.stroke(ready, palette.strokeSoft, 1, 0.3)
	ready.Activated:Connect(function()
		if ready.Active then
			Remotes.get("LobbyAction"):FireServer("ready", not localReady)
		end
	end)
	readyButton = ready

	local cavesTitle = textLabel(panel, "CaveHeading", UDim2.new(1, 0, 0, 18), UITheme.font.heading, textSize.fine)
	cavesTitle.LayoutOrder = 21
	cavesTitle.TextColor3 = palette.textMuted
	cavesTitle.Text = "CAVES · READY THE PARTY TO VOTE"
	caveHeading = cavesTitle

	local caves = Instance.new("Frame")
	caves.Name = "Caves"
	caves.LayoutOrder = 22
	caves.Size = UDim2.new(1, 0, 0, 216)
	caves.BackgroundTransparency = 1
	caves.Parent = panel
	local caveLayout = Instance.new("UIListLayout")
	caveLayout.FillDirection = Enum.FillDirection.Vertical
	caveLayout.SortOrder = Enum.SortOrder.LayoutOrder
	caveLayout.Padding = UDim.new(0, 6)
	caveLayout.Parent = caves

	for order, tier in Config.CaveTiers do
		buildCaveCard(caves, tier.id, order)
	end

	local hint = textLabel(panel, "LeaderHint", UDim2.new(1, 0, 0, 16), UITheme.font.fine, textSize.micro)
	hint.LayoutOrder = 23
	hint.TextColor3 = palette.textDim
	hint.Text = ""
	leaderHint = hint

	local leave = Instance.new("TextButton")
	leave.Name = "Leave"
	leave.LayoutOrder = 24
	leave.Size = UDim2.new(1, 0, 0, 36)
	leave.BackgroundColor3 = palette.panelRaised
	leave.BorderSizePixel = 0
	leave.AutoButtonColor = true
	leave.Font = UITheme.font.heading
	leave.TextSize = textSize.fine
	leave.TextColor3 = palette.textMuted
	leave.Text = "LEAVE ELEVATOR"
	leave.Parent = panel
	UITheme.corner(leave, 9)
	UITheme.stroke(leave, palette.strokeSoft, 1, 0.45)
	leave.Activated:Connect(function()
		if leave.Active then
			Remotes.get("LobbyAction"):FireServer("leave")
		end
	end)
	leaveButton = leave

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	applyLayout()
end

local function renderSlots(members: { MemberView }, leaderId: number, phase: string)
	local localIsLeader = leaderId == player.UserId
	for index = 1, Config.Run.partyCap do
		local member = members[index]
		local name = slotNames[index]
		local state = slotStates[index]
		local slot = slotFrames[index]
		local kick = slotKickButtons[index]
		if name == nil or state == nil or slot == nil or kick == nil then
			continue
		end
		if member == nil then
			slotTargetIds[index] = 0
			name.Text = "empty"
			name.TextColor3 = palette.textDim
			state.Text = ""
			kick.Visible = false
			slot.BackgroundTransparency = 0.55
		else
			slotTargetIds[index] = member.playerId
			name.Text = member.displayName
			name.TextColor3 = if member.playerId == player.UserId then palette.gold else palette.text
			local role = if member.playerId == leaderId then "LEADER" else ""
			local readiness = if member.ready then "READY" else ""
			state.Text = if role ~= "" and readiness ~= "" then (role .. " · " .. readiness) else (role .. readiness)
			state.TextColor3 = if member.ready then palette.ember else palette.textDim
			kick.Visible = localIsLeader and member.playerId ~= player.UserId and phase ~= "Launching"
			slot.BackgroundTransparency = if member.ready then 0.1 else 0.25
		end
	end
end

local function voteTally(state: { [string]: any }, partyId: number): { [number]: number }
	local tally: { [number]: number } = {}
	for _, otherParty in state.parties or {} do
		if tonumber(otherParty.partyId) == partyId then
			for _, entry in otherParty.votes or {} do
				local tierId = tonumber(entry.tierId)
				local count = tonumber(entry.count)
				if tierId ~= nil and count ~= nil then
					tally[tierId] = count
				end
			end
		end
	end
	return tally
end

local function caveName(tierId: number): string
	for _, tier in Config.CaveTiers do
		if tier.id == tierId then
			return tier.displayName
		end
	end
	return "Cave"
end

local function renderCaves(state: { [string]: any }, partyId: number, phase: string)
	local tally = voteTally(state, partyId)
	local myVote = tonumber(state.vote)
	local admissions: { [number]: { [string]: any } } = {}
	for _, entry in state.admission or {} do
		local tierId = tonumber(entry.tierId)
		if tierId ~= nil then
			admissions[tierId] = entry
		end
	end

	for tierId, card in caveCards do
		local entry = admissions[tierId] or {}
		local fee = tonumber(entry.fee) or 0
		local unlockPrice = tonumber(entry.unlockPrice) or 0
		local owned = entry.owned == true
		local personallyAffordable = entry.affordable == true
		local partyAffordable = entry.partyAffordable == true
		local affordable = personallyAffordable and partyAffordable
		local canVote = phase == "Voting" and affordable
		local selected = myVote == tierId

		card.name.Text = string.upper(caveName(tierId))
		local costText = if fee > 0 then ("ENTRY " .. formatInteger(fee)) else "ENTRY FREE"
		if owned then
			costText ..= " · OWNED"
		elseif unlockPrice > 0 then
			costText ..= " · OWN " .. formatInteger(unlockPrice)
		end
		if not personallyAffordable then
			costText ..= " · CANNOT AFFORD"
		elseif not partyAffordable then
			costText ..= " · PARTY CAN'T PAY"
		end
		card.cost.Text = costText
		card.cost.TextColor3 = if affordable then palette.textMuted else palette.danger

		local benefit = caveBenefits[tierId]
		if benefit ~= nil then
			card.benefit.Text = string.format(
				"%.1fx RAW WAX VALUE · TIER %d NATIVE ORE",
				benefit.payoutPermille / 1000,
				benefit.nativeOreTier
			)
		else
			card.benefit.Text = ""
		end

		local votes = tally[tierId] or 0
		card.count.Text = if votes > 0 then string.format("%d VOTE%s", votes, if votes == 1 then "" else "S") else ""
		card.button.Active = canVote
		card.button.AutoButtonColor = canVote
		card.button.BackgroundColor3 = if selected then palette.chipActive else palette.chip
		card.button.BackgroundTransparency = if affordable then 0.12 else 0.48
		card.stroke.Color = if selected then palette.ember else palette.strokeSoft
		card.stroke.Transparency = if selected then 0.05 else 0.35
	end
end

local function render(state: { [string]: any })
	local partyId = tonumber(state.partyId) or 0
	if partyId <= 0 or state.inExpedition == true then
		setPanelVisible(false)
		return
	end
	applyLayout()
	setPanelVisible(true)

	local phase = tostring(state.phase or "Gathering")
	local leaderId = tonumber(state.leaderId) or 0
	localReady = state.ready == true

	local title = titleLabel
	if title ~= nil then
		title.Text = "PARTY " .. tostring(partyId)
	end

	local members: { MemberView } = {}
	for _, entry in state.parties or {} do
		if tonumber(entry.partyId) == partyId then
			for _, raw in entry.members or {} do
				table.insert(members, {
					displayName = tostring(raw.displayName or "?"),
					ready = raw.ready == true,
					playerId = tonumber(raw.playerId) or 0,
				})
			end
		end
	end
	renderSlots(members, leaderId, phase)

	local phaseText = phaseLabel
	if phaseText ~= nil then
		if phase == "Launching" then
			phaseText.Text = "Vote resolved. The gate is closing."
		elseif phase == "Voting" then
			phaseText.Text = "Everyone is ready. Cast your cave vote."
		else
			phaseText.Text = string.format("%d of %d aboard. Ready up when settled.", #members, Config.Run.partyCap)
		end
	end

	local ready = readyButton
	if ready ~= nil then
		local committed = phase == "Launching"
		ready.Active = not committed
		ready.AutoButtonColor = not committed
		ready.Text = if committed then "DESCENDING" elseif localReady then "STAND DOWN" else "READY UP"
		ready.BackgroundColor3 = if localReady or committed then palette.chipActive else palette.chip
		ready.TextColor3 = if committed then palette.textMuted else palette.gold
	end

	local heading = caveHeading
	if heading ~= nil then
		heading.Text = if phase == "Voting" then "CAVE VOTE · CHOOSE ONE" else "CAVES · COSTS AND BENEFITS"
	end

	local hint = leaderHint
	if hint ~= nil then
		hint.Text = if leaderId == player.UserId and phase ~= "Launching"
			then string.format(
				"Leader controls: KICK blocks re-entry for %d seconds.",
				Config.Lobby.kickRejoinBlockSeconds
			)
			else "The first rider aboard is the party leader."
	end

	local leave = leaveButton
	if leave ~= nil then
		local committed = phase == "Launching"
		leave.Active = not committed
		leave.AutoButtonColor = not committed
		leave.Text = if committed then "GATE CLOSED" else "LEAVE ELEVATOR"
		leave.TextColor3 = if committed then palette.textDim else palette.textMuted
	end

	renderCaves(state, partyId, phase)
end

function PartyPanelController.start()
	build()
	-- `any` is confined to this untyped RemoteEvent boundary; every field is checked before use.
	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: any })
		render(state)
	end)
end

return PartyPanelController

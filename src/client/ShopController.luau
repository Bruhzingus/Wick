--!strict
-- The Keeper's Shop: one responsive surface for the Lamp Network and permanent cave access.
--
-- This controller is intentionally display/input only. It renders the server's ShopState projection
-- and sends small intents (an action plus an id/depth) through ShopAction. Prices, prerequisites,
-- profile state, and purchase results are never decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LampTreeView = require(script.Parent.LampTreeView)
local LampNodeIcons = require(script.Parent.LampNodeIcons)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)
local LampConfig = require(ReplicatedStorage.Shared.Config.LampNetwork)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local ShopController = {}

type LampOffer = LampTreeView.LampOffer

type CaveOffer = {
	tierId: number,
	displayName: string,
	price: number,
	entryFee: number,
	owned: boolean,
	affordable: boolean,
	purchasable: boolean,
	failure: string?,
	description: string,
}

type ContractOffer = {
	id: string,
	displayName: string,
	rule: string,
	payoutPermille: number,
	minPartySize: number,
}

type Agreement = {
	kind: string,
	id: string?,
	depth: number?,
}

type PendingIntent = {
	kind: string,
	id: string,
}

type CaveWidget = {
	button: TextButton,
	stroke: UIStroke,
	scale: UIScale,
	offer: CaveOffer,
}

local player = Players.LocalPlayer
local palette = UITheme.palette
local SHOP_OPEN_ATTRIBUTE = "WickShopOpen"
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local FALLBACK_POSITIONS: { [string]: Vector2 } = {
	["lamp.pay_table"] = Vector2.new(0, 2),
	["lamp.contract_board"] = Vector2.new(1, 2),
	["lamp.twin_seam"] = Vector2.new(2, 0),
	["lamp.deep_seam"] = Vector2.new(3, 0),
	["lamp.dim_seam"] = Vector2.new(4, 0),
	["lamp.bright_seam"] = Vector2.new(4, 1),
	["lamp.signal_bell"] = Vector2.new(2, 2),
	["lamp.echo_lock"] = Vector2.new(3, 2),
	["lamp.locked_store"] = Vector2.new(2, 4),
	["lamp.hard_contracts"] = Vector2.new(5, 3),
	["lamp.wager_board"] = Vector2.new(6, 3),
}

local FALLBACK_ICONS: { [string]: string } = {
	["lamp.pay_table"] = "Ledger",
	["lamp.contract_board"] = "Contract",
	["lamp.twin_seam"] = "TwinSeam",
	["lamp.deep_seam"] = "DeepSeam",
	["lamp.dim_seam"] = "DimSeam",
	["lamp.bright_seam"] = "BrightSeam",
	["lamp.signal_bell"] = "Bell",
	["lamp.echo_lock"] = "EchoGate",
	["lamp.locked_store"] = "Store",
	["lamp.hard_contracts"] = "HardContract",
	["lamp.wager_board"] = "Wager",
}

-- What a lit PASSIVE node (no board UI of its own) actually does below, in concrete terms rather
-- than the generic "its effect is active" filler. `offer.description` above this already states the
-- mechanic; this is the second, in-character confirmation a player used to get by walking up to the
-- node's own physical lamp and holding its prompt, back when each node had one (see LampHubService,
-- now unused — its physical lamp line was replaced by this shop's schematic).
local PASSIVE_NODE_CONFIRMATION: { [string]: string } = {
	["lamp.twin_seam"] = "Twin Seams are cut into the rock now. Strike one with a second miner nearby "
		.. "and you both get paid for it — take someone with you.",
	["lamp.signal_bell"] = "Your bell is on your belt. Ring it below and your party hears exactly "
		.. "where you are — so does anything else down there listening.",
	["lamp.echo_lock"] = "Barred loops start showing up in the generation. Ring the Signal Bell beside "
		.. "one and it lifts, opening a shortcut the cave doesn't otherwise offer.",
	["lamp.deep_seam"] = "Deep Seams start appearing from floor 6 down. Nine deliberate strikes each, "
		.. "and you cannot move while you make them.",
	["lamp.dim_seam"] = "Dim Seams answer only while your uncovered flame is below one-third burn. "
		.. "Burn low to reach them, same as staying hidden.",
	["lamp.bright_seam"] = "Bright Seams only give at full burn. Working one makes you the brightest "
		.. "thing in the cave, on purpose.",
	["lamp.locked_store"] = "Locked Stores are sealed behind vines from floor 5 down. Burn one open "
		.. "and take what's inside — it's stocked whether or not you knew it was there.",
}

local gui: ScreenGui? = nil
local root: CanvasGroup? = nil
local mainPanel: Frame? = nil
local mainScale: UIScale? = nil
local header: Frame? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil
local currencyFrame: Frame? = nil
local currencyLabel: TextLabel? = nil
local closeButton: TextButton? = nil
local tabsFrame: Frame? = nil
local lampTab: UITheme.Button? = nil
local caveTab: UITheme.Button? = nil
local contentFrame: Frame? = nil
local browserPane: Frame? = nil
local browserCaption: TextLabel? = nil
local lampHost: Frame? = nil
local caveHost: ScrollingFrame? = nil
local detailPane: Frame? = nil
local detailScroller: ScrollingFrame? = nil
local detailBody: Frame? = nil
local treeView: LampTreeView.View? = nil
local confirmLayer: Frame? = nil
local confirmHeading: TextLabel? = nil
local confirmBody: TextLabel? = nil
local confirmAction: (() -> ())? = nil
local toast: CanvasGroup? = nil
local toastLabel: TextLabel? = nil

local isOpen = false
local activeTab = "lamp"
local selectedLampId: string? = nil
local selectedCaveId: number? = nil
local currency = 0
local lampOffers: { LampOffer } = {}
local caveOffers: { CaveOffer } = {}
local contracts: { ContractOffer } = {}
local activeAgreement: Agreement? = nil
local lastRunBreakdown: { [string]: any }? = nil
local minimumWagerTarget = 6
local wagerTarget = 6
local pendingIntent: PendingIntent? = nil
local toastGeneration = 0
local caveWidgets: { CaveWidget } = {}

local shopAction = Remotes.get("ShopAction")

local function asString(value: any, fallback: string): string
	return if typeof(value) == "string" and value ~= "" then value else fallback
end

local function finiteNumber(value: any, fallback: number): number
	if typeof(value) ~= "number" or value ~= value or value <= -math.huge or value >= math.huge then
		return fallback
	end
	return value
end

local function wholeNumber(value: any, fallback: number): number
	return math.floor(finiteNumber(value, fallback))
end

local function strings(value: any): { string }
	local result: { string } = {}
	if typeof(value) ~= "table" then
		return result
	end
	for _, entry in value do
		if typeof(entry) == "string" and entry ~= "" then
			table.insert(result, entry)
		end
	end
	return result
end

local function positionOf(value: any, fallback: Vector2): Vector2
	if typeof(value) == "Vector2" then
		local vector = value :: Vector2
		return Vector2.new(math.max(0, vector.X), math.max(0, vector.Y))
	elseif typeof(value) == "table" then
		local x = finiteNumber(value.X or value.x or value[1], fallback.X)
		local y = finiteNumber(value.Y or value.y or value[2], fallback.Y)
		return Vector2.new(math.max(0, x), math.max(0, y))
	end
	return fallback
end

local function findLamp(nodeId: string?): LampOffer?
	if nodeId == nil then
		return nil
	end
	for _, offer in lampOffers do
		if offer.nodeId == nodeId then
			return offer
		end
	end
	return nil
end

local function findCave(tierId: number?): CaveOffer?
	if tierId == nil then
		return nil
	end
	for _, offer in caveOffers do
		if offer.tierId == tierId then
			return offer
		end
	end
	return nil
end

local function displayNameFor(nodeId: string): string
	local offer = findLamp(nodeId)
	return if offer ~= nil then offer.displayName else nodeId
end

local function showToast(message: string, danger: boolean?)
	local group = toast
	local label = toastLabel
	if group == nil or label == nil or message == "" then
		return
	end
	toastGeneration += 1
	local generation = toastGeneration
	label.Text = message
	label.TextColor3 = if danger == true then palette.danger else palette.gold
	group.Visible = true
	group.GroupTransparency = 1
	UITheme.tween(group, UITheme.motion.fade, { GroupTransparency = 0 })
	task.delay(4, function()
		if toastGeneration ~= generation or group.Parent == nil then
			return
		end
		local fade = UITheme.tween(group, UITheme.motion.fade, { GroupTransparency = 1 })
		fade.Completed:Connect(function()
			if toastGeneration == generation then
				group.Visible = false
			end
		end)
	end)
end

local function detailLabel(
	parent: Instance,
	text: string,
	font: Enum.Font,
	color: Color3,
	textSize: number,
	order: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, 0)
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function divider(parent: Instance, order: number)
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = palette.strokeSoft
	rule.BackgroundTransparency = 0.35
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.LayoutOrder = order
	rule.Parent = parent
end

local function statePill(parent: Instance, text: string, color: Color3, order: number)
	local pill = Instance.new("TextLabel")
	pill.BackgroundColor3 = palette.chip
	pill.BorderSizePixel = 0
	pill.Font = UITheme.font.heading
	pill.Text = text
	pill.TextColor3 = color
	pill.TextSize = UITheme.textSize.body
	pill.TextXAlignment = Enum.TextXAlignment.Left
	pill.Size = UDim2.new(1, 0, 0, 38)
	pill.LayoutOrder = order
	pill.Parent = parent
	UITheme.corner(pill, 8)
	UITheme.stroke(pill, color, 1, 0.55)
	UITheme.padding(pill, 0, 10, 0, 10)
end

local function detailButton(parent: Instance, text: string, order: number): UITheme.Button
	local button = UITheme.button(parent :: GuiObject, text)
	button.instance.Size = UDim2.new(1, 0, 0, 48)
	button.instance.LayoutOrder = order
	return button
end

local function clearDetail()
	if detailBody ~= nil then
		detailBody:Destroy()
		detailBody = nil
	end
	local scroller = detailScroller
	if scroller == nil then
		return
	end
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Size = UDim2.new(1, -4, 0, 0)
	body.Parent = scroller
	UITheme.padding(body, 16, 14, 18, 14)
	local layout = UITheme.listLayout(body, 11)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	detailBody = body
	scroller.CanvasPosition = Vector2.zero
end

local function confirm(title: string, body: string, action: () -> ())
	local layer = confirmLayer
	if layer == nil or confirmHeading == nil or confirmBody == nil then
		return
	end
	confirmHeading.Text = title
	confirmBody.Text = body
	confirmAction = action
	layer.Visible = true
end

local function dismissConfirmation()
	confirmAction = nil
	if confirmLayer ~= nil then
		confirmLayer.Visible = false
	end
end

local function send(action: string, value: any?)
	shopAction:FireServer(action, value)
end

local function agreementSummary(): string
	local agreement = activeAgreement
	if agreement == nil then
		return "No agreement is set for the next descent."
	elseif agreement.kind == "contract" and agreement.id ~= nil then
		for _, contract in contracts do
			if contract.id == agreement.id then
				return "SIGNED - " .. contract.displayName
			end
		end
		return "A contract is signed for the next descent."
	elseif agreement.kind == "wager" and agreement.depth ~= nil then
		return string.format("WAGERED - Floor %d or deeper", agreement.depth)
	end
	return "An agreement is set for the next descent."
end

local function payoutText(permille: number): string
	return string.format("x%.2f", permille / 1000)
end

local function wagerPermille(depth: number): number
	local config: any = LampConfig
	local wager: any = config.wager or {}
	local base = wholeNumber(wager.basePermille, 1000)
	local perDepth = wholeNumber(wager.permillePerDepth, 150)
	local minimum = wholeNumber(wager.minimumTarget, 6)
	local maximum = wholeNumber(wager.maximumPermille, 2500)
	return math.clamp(base + perDepth * (depth - (minimum - 1)), base, maximum)
end

local renderLampDetails: () -> ()

local function addPayTable(parent: Instance, startOrder: number): number
	divider(parent, startOrder)
	detailLabel(parent, "LAST EXTRACTION", UITheme.font.heading, palette.gold, 13, startOrder + 1)
	local breakdown = lastRunBreakdown
	if breakdown == nil then
		detailLabel(
			parent,
			"The slate is blank. Bring a bag of Raw Wax back from a cave to record a payment.",
			UITheme.font.fine,
			palette.textMuted,
			14,
			startOrder + 2
		)
		return startOrder + 2
	end
	local rows = {
		{ "UNITS DELIVERED", wholeNumber(breakdown.units, 0) },
		{ "BASE VALUE", wholeNumber(breakdown.baseValue, 0) },
		{ "CAVE RATE", payoutText(wholeNumber(breakdown.cavePayoutPermille, 1000)) },
		{ "PARTY RETURN", payoutText(wholeNumber(breakdown.partyBonusPermille, 1000)) },
		{ "AGREEMENT", payoutText(wholeNumber(breakdown.contractPermille, 1000)) },
		{ "PAID", wholeNumber(breakdown.total, 0) },
	}
	local order = startOrder + 2
	for _, row in rows do
		local rowFrame = Instance.new("Frame")
		rowFrame.BackgroundColor3 = palette.chip
		rowFrame.BackgroundTransparency = if row[1] == "PAID" then 0 else 0.38
		rowFrame.BorderSizePixel = 0
		rowFrame.Size = UDim2.new(1, 0, 0, 34)
		rowFrame.LayoutOrder = order
		rowFrame.Parent = parent
		UITheme.corner(rowFrame, 7)
		local left = detailLabel(rowFrame, row[1] :: string, UITheme.font.fine, palette.textMuted, 11, 1)
		left.AutomaticSize = Enum.AutomaticSize.None
		left.Position = UDim2.fromOffset(10, 0)
		left.Size = UDim2.new(0.58, -10, 1, 0)
		left.TextYAlignment = Enum.TextYAlignment.Center
		local right = detailLabel(rowFrame, tostring(row[2]), UITheme.font.heading, palette.gold, 13, 2)
		right.AutomaticSize = Enum.AutomaticSize.None
		right.Position = UDim2.fromScale(0.58, 0)
		right.Size = UDim2.new(0.42, -10, 1, 0)
		right.TextXAlignment = Enum.TextXAlignment.Right
		right.TextYAlignment = Enum.TextYAlignment.Center
		order += 1
	end
	return order
end

local function addContracts(parent: Instance, startOrder: number): number
	divider(parent, startOrder)
	detailLabel(parent, "NEXT DESCENT", UITheme.font.heading, palette.gold, 13, startOrder + 1)
	statePill(
		parent,
		agreementSummary(),
		if activeAgreement ~= nil then palette.ember else palette.textMuted,
		startOrder + 2
	)

	local order = startOrder + 3
	if #contracts == 0 then
		detailLabel(
			parent,
			"No contracts are available for this party size.",
			UITheme.font.fine,
			palette.textMuted,
			14,
			order
		)
		order += 1
	else
		for _, contract in contracts do
			local selected = activeAgreement ~= nil
				and activeAgreement.kind == "contract"
				and activeAgreement.id == contract.id
			local card = Instance.new("TextButton")
			card.AutoButtonColor = false
			card.BackgroundColor3 = if selected then palette.chipActive else palette.chip
			card.BorderSizePixel = 0
			card.Text = ""
			card.Size = UDim2.new(1, 0, 0, 84)
			card.LayoutOrder = order
			card.Parent = parent
			UITheme.corner(card, 9)
			UITheme.stroke(
				card,
				if selected then palette.ember else palette.strokeSoft,
				1.25,
				if selected then 0.1 else 0.45
			)

			local name = detailLabel(card, contract.displayName, UITheme.font.heading, palette.text, 14, 1)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.Position = UDim2.fromOffset(12, 9)
			name.Size = UDim2.new(0.7, -12, 0, 20)
			name.TextYAlignment = Enum.TextYAlignment.Center
			local rate =
				detailLabel(card, payoutText(contract.payoutPermille), UITheme.font.heading, palette.gold, 14, 2)
			rate.AutomaticSize = Enum.AutomaticSize.None
			rate.Position = UDim2.new(0.7, 0, 0, 9)
			rate.Size = UDim2.new(0.3, -12, 0, 20)
			rate.TextXAlignment = Enum.TextXAlignment.Right
			rate.TextYAlignment = Enum.TextYAlignment.Center
			local rule = detailLabel(card, contract.rule, UITheme.font.fine, palette.textMuted, 12, 3)
			rule.AutomaticSize = Enum.AutomaticSize.None
			rule.Position = UDim2.fromOffset(12, 34)
			rule.Size = UDim2.new(1, -24, 0, 41)
			card.Activated:Connect(function()
				pendingIntent = { kind = "contract", id = contract.id }
				send("setContract", contract.id)
				showToast("Signing " .. contract.displayName .. "...")
			end)
			order += 1
		end
	end

	if activeAgreement ~= nil then
		local clear = detailButton(parent, "CLEAR AGREEMENT", order)
		clear.instance.Activated:Connect(function()
			pendingIntent = { kind = "agreement", id = "clear" }
			send("clearAgreement")
			showToast("Clearing the agreement...")
		end)
		order += 1
	end
	return order
end

local function addWager(parent: Instance, startOrder: number): number
	divider(parent, startOrder)
	detailLabel(parent, "NAME THE DEPTH", UITheme.font.heading, palette.gold, 13, startOrder + 1)
	detailLabel(
		parent,
		"Your target must be deeper than your personal record. Reach it and the whole extraction pays the shown rate.",
		UITheme.font.fine,
		palette.textMuted,
		13,
		startOrder + 2
	)

	local stepper = Instance.new("Frame")
	stepper.BackgroundTransparency = 1
	stepper.Size = UDim2.new(1, 0, 0, 52)
	stepper.LayoutOrder = startOrder + 3
	stepper.Parent = parent

	local down = UITheme.button(stepper, "-")
	down.instance.AnchorPoint = Vector2.new(0, 0.5)
	down.instance.Position = UDim2.fromScale(0, 0.5)
	down.instance.Size = UDim2.fromOffset(48, 48)
	local up = UITheme.button(stepper, "+")
	up.instance.AnchorPoint = Vector2.new(1, 0.5)
	up.instance.Position = UDim2.fromScale(1, 0.5)
	up.instance.Size = UDim2.fromOffset(48, 48)

	local value = Instance.new("TextLabel")
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.fromScale(0.5, 0.5)
	value.Size = UDim2.new(1, -112, 0, 48)
	value.BackgroundColor3 = palette.chip
	value.BorderSizePixel = 0
	value.Font = UITheme.font.heading
	value.TextColor3 = palette.gold
	value.TextSize = UITheme.textSize.body
	value.Parent = stepper
	UITheme.corner(value, 8)

	local function refresh()
		value.Text = string.format("FLOOR %d  -  %s", wagerTarget, payoutText(wagerPermille(wagerTarget)))
		down.setEnabled(wagerTarget > minimumWagerTarget)
	end
	down.instance.Activated:Connect(function()
		wagerTarget = math.max(minimumWagerTarget, wagerTarget - 1)
		refresh()
	end)
	up.instance.Activated:Connect(function()
		wagerTarget += 1
		refresh()
	end)
	refresh()

	local set = detailButton(parent, "PLACE WAGER", startOrder + 4)
	set.instance.Activated:Connect(function()
		pendingIntent = { kind = "wager", id = tostring(wagerTarget) }
		send("setWager", wagerTarget)
		showToast(string.format("Placing a wager on Floor %d...", wagerTarget))
	end)
	local order = startOrder + 5
	if activeAgreement ~= nil then
		statePill(parent, agreementSummary(), palette.ember, order)
		order += 1
		local clear = detailButton(parent, "CLEAR AGREEMENT", order)
		clear.instance.Activated:Connect(function()
			pendingIntent = { kind = "agreement", id = "clear" }
			send("clearAgreement")
			showToast("Clearing the agreement...")
		end)
		order += 1
	end
	return order
end

renderLampDetails = function()
	clearDetail()
	local body = detailBody
	if body == nil then
		return
	end
	local offer = findLamp(selectedLampId)
	if offer == nil then
		detailLabel(body, "LAMP NETWORK", UITheme.font.display, palette.gold, 22, 1)
		detailLabel(body, "Select a lamp to inspect what it awakens.", UITheme.font.fine, palette.textMuted, 14, 2)
		return
	end

	local headingRow = Instance.new("Frame")
	headingRow.BackgroundTransparency = 1
	headingRow.Size = UDim2.new(1, 0, 0, 54)
	headingRow.LayoutOrder = 1
	headingRow.Parent = body
	local iconHolder = Instance.new("Frame")
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.Position = UDim2.fromScale(0, 0.5)
	iconHolder.Size = UDim2.fromOffset(42, 42)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = headingRow
	local icon = LampNodeIcons.create(iconHolder, offer.iconId)
	icon.setColor(if offer.owned then palette.gold elseif offer.purchasable then palette.ember else palette.textDim)
	local heading = detailLabel(headingRow, offer.displayName, UITheme.font.display, palette.gold, 20, 1)
	heading.AutomaticSize = Enum.AutomaticSize.None
	heading.Position = UDim2.fromOffset(54, 0)
	heading.Size = UDim2.new(1, -54, 1, 0)
	heading.TextYAlignment = Enum.TextYAlignment.Center

	if offer.owned then
		statePill(body, "LIT - OWNED", palette.gold, 2)
	elseif not offer.live then
		statePill(body, "DORMANT - NOT AVAILABLE", palette.textDim, 2)
	elseif offer.purchasable then
		statePill(body, string.format("READY - %d RAW WAX", offer.price), palette.ember, 2)
	elseif offer.missingNode ~= nil then
		statePill(body, "LOCKED - LIGHT " .. displayNameFor(offer.missingNode) .. " FIRST", palette.textMuted, 2)
	elseif not offer.affordable then
		statePill(body, string.format("NEEDS %d RAW WAX", offer.price), palette.textMuted, 2)
	else
		statePill(body, "LOCKED", palette.textMuted, 2)
	end

	detailLabel(body, offer.description, UITheme.font.body, palette.text, 15, 3)
	local order = 4
	if #offer.requires > 0 or #offer.requiresAny > 0 then
		divider(body, order)
		order += 1
		detailLabel(body, "PATH", UITheme.font.heading, palette.gold, 12, order)
		order += 1
		for _, requirement in offer.requires do
			local required = findLamp(requirement)
			local mark = if required ~= nil and required.owned then "LIT" else "UNLIT"
			detailLabel(
				body,
				string.format("%s  -  %s", displayNameFor(requirement), mark),
				UITheme.font.fine,
				if mark == "LIT" then palette.gold else palette.textMuted,
				13,
				order
			)
			order += 1
		end
		if #offer.requiresAny > 0 then
			local names: { string } = {}
			for _, requirement in offer.requiresAny do
				table.insert(names, displayNameFor(requirement))
			end
			detailLabel(
				body,
				string.format("Light any %d: %s", offer.requiresAnyCount, table.concat(names, ", ")),
				UITheme.font.fine,
				palette.textMuted,
				13,
				order
			)
			order += 1
		end
	end

	if not offer.owned then
		local buy = detailButton(body, string.format("LIGHT FOR %d RAW WAX", offer.price), order)
		buy.setEnabled(offer.purchasable)
		buy.instance.Activated:Connect(function()
			confirm(
				"LIGHT " .. string.upper(offer.displayName) .. "?",
				string.format(
					"This spends %d Raw Wax permanently. The lamp awakens %s.",
					offer.price,
					string.lower(offer.description)
				),
				function()
					pendingIntent = { kind = "lamp", id = offer.nodeId }
					send("buyLamp", offer.nodeId)
					showToast("Lighting " .. offer.displayName .. "...")
				end
			)
		end)
		return
	end

	if offer.nodeId == "lamp.pay_table" then
		addPayTable(body, order)
	elseif offer.nodeId == "lamp.contract_board" or offer.nodeId == "lamp.hard_contracts" then
		addContracts(body, order)
	elseif offer.nodeId == "lamp.wager_board" then
		addWager(body, order)
	else
		divider(body, order)
		detailLabel(body, "THIS MACHINE IS AWAKE", UITheme.font.heading, palette.gold, 12, order + 1)
		detailLabel(
			body,
			PASSIVE_NODE_CONFIRMATION[offer.nodeId]
				or "Its effect is active whenever its layer is enabled. "
					.. "No extra purchase or loadout slot is required.",
			UITheme.font.fine,
			palette.textMuted,
			13,
			order + 2
		)
	end
end

local function renderCaveDetails()
	clearDetail()
	local body = detailBody
	if body == nil then
		return
	end
	local offer = findCave(selectedCaveId)
	if offer == nil then
		detailLabel(body, "CAVE ACCESS", UITheme.font.display, palette.gold, 22, 1)
		detailLabel(body, "No permanent access deeds are being offered.", UITheme.font.fine, palette.textMuted, 14, 2)
		return
	end
	detailLabel(body, offer.displayName, UITheme.font.display, palette.gold, 22, 1)
	if offer.owned then
		statePill(body, "OWNED - NO FUTURE TOLL", palette.gold, 2)
	elseif offer.purchasable then
		statePill(body, string.format("AVAILABLE - %d RAW WAX", offer.price), palette.ember, 2)
	else
		statePill(body, string.format("NEEDS %d RAW WAX", offer.price), palette.textMuted, 2)
	end
	detailLabel(body, offer.description, UITheme.font.body, palette.text, 15, 3)
	divider(body, 4)
	detailLabel(
		body,
		string.format("ORDINARY ENTRY TOLL  %d RAW WAX", offer.entryFee),
		UITheme.font.heading,
		palette.textMuted,
		13,
		5
	)
	detailLabel(
		body,
		"Permanent access changes only what future descents cost. It does not change the cave, its danger, or its payout.",
		UITheme.font.fine,
		palette.textMuted,
		13,
		6
	)
	if not offer.owned then
		local buy = detailButton(body, string.format("BUY ACCESS FOR %d", offer.price), 7)
		buy.setEnabled(offer.purchasable)
		buy.instance.Activated:Connect(function()
			confirm(
				"BUY " .. string.upper(offer.displayName) .. "?",
				string.format(
					"This spends %d Raw Wax permanently. You will never pay its %d Raw Wax entry toll again.",
					offer.price,
					offer.entryFee
				),
				function()
					pendingIntent = { kind = "cave", id = tostring(offer.tierId) }
					send("buyCave", offer.tierId)
					showToast("Recording the cave deed...")
				end
			)
		end)
	end
end

local function renderCaveList()
	local scroller = caveHost
	if scroller == nil then
		return
	end
	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		elseif child:IsA("UIListLayout") or child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(caveWidgets)

	UITheme.padding(scroller, 10, 10, 10, 10)
	local layout = UITheme.listLayout(scroller, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for index, offer in caveOffers do
		local selected = offer.tierId == selectedCaveId
		local card = Instance.new("TextButton")
		card.Name = "Cave_" .. tostring(offer.tierId)
		card.AutoButtonColor = false
		card.BackgroundColor3 = if selected then palette.chipActive else palette.chip
		card.BorderSizePixel = 0
		card.Text = ""
		card.Size = UDim2.new(1, 0, 0, 82)
		card.LayoutOrder = index
		card.Parent = scroller
		UITheme.corner(card, 10)
		local stroke = UITheme.stroke(card, if selected then palette.ember else palette.strokeSoft, 1.5, 0.35)
		local scale = UITheme.scale(card, 1)

		local iconHolder = Instance.new("Frame")
		iconHolder.Position = UDim2.fromOffset(12, 19)
		iconHolder.Size = UDim2.fromOffset(42, 42)
		iconHolder.BackgroundTransparency = 1
		iconHolder.Parent = card
		local icon = LampNodeIcons.create(iconHolder, "Store")
		icon.setColor(if offer.owned then palette.gold elseif offer.purchasable then palette.ember else palette.textDim)
		local name = detailLabel(card, offer.displayName, UITheme.font.heading, palette.text, 15, 1)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.Position = UDim2.fromOffset(66, 13)
		name.Size = UDim2.new(1, -78, 0, 24)
		name.TextYAlignment = Enum.TextYAlignment.Center
		local status = if offer.owned
			then "OWNED"
			elseif offer.purchasable then string.format("%d RAW WAX", offer.price)
			else string.format("NEEDS %d RAW WAX", offer.price)
		local statusLabel = detailLabel(
			card,
			status,
			UITheme.font.fine,
			if offer.owned then palette.gold elseif offer.purchasable then palette.ember else palette.textMuted,
			12,
			2
		)
		statusLabel.AutomaticSize = Enum.AutomaticSize.None
		statusLabel.Position = UDim2.fromOffset(66, 42)
		statusLabel.Size = UDim2.new(1, -78, 0, 22)
		statusLabel.TextYAlignment = Enum.TextYAlignment.Center
		card.MouseButton1Down:Connect(function()
			UITheme.tween(scale, UITheme.motion.press, { Scale = 0.98 })
		end)
		card.MouseButton1Up:Connect(function()
			UITheme.tween(scale, UITheme.motion.press, { Scale = 1 })
		end)
		card.Activated:Connect(function()
			selectedCaveId = offer.tierId
			renderCaveList()
			renderCaveDetails()
		end)
		table.insert(caveWidgets, { button = card, stroke = stroke, scale = scale, offer = offer })
	end
	if #caveOffers == 0 then
		local empty = detailLabel(
			scroller,
			"No permanent access deeds are available.",
			UITheme.font.fine,
			palette.textMuted,
			14,
			1
		)
		empty.Size = UDim2.new(1, 0, 0, 72)
		empty.AutomaticSize = Enum.AutomaticSize.None
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.TextYAlignment = Enum.TextYAlignment.Center
	end
end

local function setTab(tab: string)
	activeTab = if tab == "cave" then "cave" else "lamp"
	if lampTab ~= nil then
		lampTab.setActive(activeTab == "lamp")
	end
	if caveTab ~= nil then
		caveTab.setActive(activeTab == "cave")
	end
	if lampHost ~= nil then
		lampHost.Visible = activeTab == "lamp"
	end
	if caveHost ~= nil then
		caveHost.Visible = activeTab == "cave"
	end
	if browserCaption ~= nil then
		browserCaption.Text = if activeTab == "lamp"
			then "SELECT A NODE  -  DRAG TO PAN  -  SCROLL TO MOVE"
			else "PERMANENT ACCESS DEEDS"
	end
	if activeTab == "lamp" then
		renderLampDetails()
	else
		renderCaveList()
		renderCaveDetails()
	end
end

local function setOpen(open: boolean, tellServer: boolean?)
	local group = root
	if group == nil then
		return
	end
	local allowed = open and player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true
	isOpen = allowed
	CursorController.setReleased("Shop", allowed)
	player:SetAttribute(SHOP_OPEN_ATTRIBUTE, allowed)
	dismissConfirmation()
	if allowed then
		group.Visible = true
		group.GroupTransparency = 1
		if mainScale ~= nil then
			mainScale.Scale = 0.96
		end
		UITheme.tween(group, UITheme.motion.fade, { GroupTransparency = 0 })
		if mainScale ~= nil then
			UITheme.tween(mainScale, UITheme.motion.rise, { Scale = 1 })
		end
		setTab(activeTab)
	else
		group.Visible = false
		pendingIntent = nil
	end
	if tellServer == true then
		send("close")
	end
end

local function normalizeLampOffers(state: { [string]: any }): { LampOffer }
	local serverRows: { [string]: any } = {}
	local rawServerRows = state.lampOffers or state.nodes
	if typeof(rawServerRows) == "table" then
		for _, raw in rawServerRows do
			if typeof(raw) == "table" then
				local nodeId = asString(raw.nodeId or raw.id, "")
				if nodeId ~= "" then
					serverRows[nodeId] = raw
				end
			end
		end
	end

	local result: { LampOffer } = {}
	local seen: { [string]: boolean } = {}
	local config: any = LampConfig
	local rawNodes: any = config.nodes or {}
	for index, configNode in rawNodes do
		local raw: any = configNode
		local nodeId = asString(raw.id or raw.nodeId, "")
		if nodeId == "" then
			continue
		end
		local server: any = serverRows[nodeId] or {}
		local price = wholeNumber(server.price or server.cost, wholeNumber(raw.cost, 0))
		local owned = server.owned == true
		local live = server.live ~= false and server.layerLive ~= false and server.enabled ~= false
		local missingNode = if typeof(server.missingNode or server.missingPrerequisite) == "string"
			then (server.missingNode or server.missingPrerequisite)
			else nil
		local affordable = if typeof(server.affordable) == "boolean" then server.affordable else currency >= price
		local failure = if typeof(server.failure) == "string" then server.failure else nil
		local purchasable = if typeof(server.purchasable) == "boolean"
			then server.purchasable
			else live and not owned and missingNode == nil and affordable and failure ~= "LayerDisabled"
		local fallback = FALLBACK_POSITIONS[nodeId] or Vector2.new(index - 1, 0)
		table.insert(result, {
			nodeId = nodeId,
			displayName = asString(server.displayName, asString(raw.displayName, nodeId)),
			description = asString(
				server.description or server.promptClause,
				asString(raw.description or raw.promptClause, "An old machine waiting for a flame.")
			),
			iconId = asString(server.iconId, asString(raw.iconId, FALLBACK_ICONS[nodeId] or "Flame")),
			price = math.max(0, price),
			owned = owned,
			live = live,
			affordable = affordable,
			purchasable = purchasable,
			failure = failure,
			missingNode = missingNode,
			requires = if #strings(server.requires) > 0 then strings(server.requires) else strings(raw.requires),
			requiresAny = if #strings(server.requiresAny) > 0
				then strings(server.requiresAny)
				else strings(raw.requiresAny),
			requiresAnyCount = math.max(0, wholeNumber(server.requiresAnyCount, wholeNumber(raw.requiresAnyCount, 0))),
			treePosition = positionOf(server.treePosition or server.position, positionOf(raw.treePosition, fallback)),
		})
		seen[nodeId] = true
	end

	for nodeId, server in serverRows do
		if seen[nodeId] then
			continue
		end
		local index = #result
		local price = math.max(0, wholeNumber(server.price or server.cost, 0))
		local affordable = if typeof(server.affordable) == "boolean" then server.affordable else currency >= price
		local missingNode = if typeof(server.missingNode or server.missingPrerequisite) == "string"
			then (server.missingNode or server.missingPrerequisite)
			else nil
		local live = server.live ~= false and server.layerLive ~= false and server.enabled ~= false
		local owned = server.owned == true
		table.insert(result, {
			nodeId = nodeId,
			displayName = asString(server.displayName, nodeId),
			description = asString(server.description or server.promptClause, "An old machine waiting for a flame."),
			iconId = asString(server.iconId, FALLBACK_ICONS[nodeId] or "Flame"),
			price = price,
			owned = owned,
			live = live,
			affordable = affordable,
			purchasable = if typeof(server.purchasable) == "boolean"
				then server.purchasable
				else live and not owned and missingNode == nil and affordable,
			failure = if typeof(server.failure) == "string" then server.failure else nil,
			missingNode = missingNode,
			requires = strings(server.requires),
			requiresAny = strings(server.requiresAny),
			requiresAnyCount = math.max(0, wholeNumber(server.requiresAnyCount, 0)),
			treePosition = positionOf(
				server.treePosition or server.position,
				FALLBACK_POSITIONS[nodeId] or Vector2.new(index, 0)
			),
		})
	end
	return result
end

local function normalizeCaveOffers(state: { [string]: any }): { CaveOffer }
	local result: { CaveOffer } = {}
	local rows = state.caveOffers or state.caves
	if typeof(rows) ~= "table" then
		return result
	end
	for _, raw in rows do
		if typeof(raw) ~= "table" then
			continue
		end
		local tierId = wholeNumber(raw.tierId or raw.id, 0)
		if tierId <= 0 then
			continue
		end
		local price = math.max(0, wholeNumber(raw.price or raw.permanentUnlockPrice, 0))
		local owned = raw.owned == true
		local affordable = if typeof(raw.affordable) == "boolean" then raw.affordable else currency >= price
		local failure = if typeof(raw.failure) == "string" then raw.failure else nil
		table.insert(result, {
			tierId = tierId,
			displayName = asString(raw.displayName, "Cave " .. tostring(tierId)),
			price = price,
			entryFee = math.max(0, wholeNumber(raw.entryFee, 0)),
			owned = owned,
			affordable = affordable,
			purchasable = if typeof(raw.purchasable) == "boolean"
				then raw.purchasable
				else not owned and price > 0 and affordable,
			failure = failure,
			description = asString(
				raw.description,
				"Buy the deed once and this cave's entry toll is waived on every future descent."
			),
		})
	end
	return result
end

local function normalizeContracts(state: { [string]: any }): { ContractOffer }
	local result: { ContractOffer } = {}
	local rows = state.contracts or state.eligibleContracts
	if typeof(rows) ~= "table" then
		return result
	end
	for _, raw in rows do
		if typeof(raw) ~= "table" then
			continue
		end
		local id = asString(raw.id or raw.contractId, "")
		if id == "" then
			continue
		end
		table.insert(result, {
			id = id,
			displayName = asString(raw.displayName, id),
			rule = asString(raw.rule or raw.description, "A harder descent for a richer extraction."),
			payoutPermille = math.max(1000, wholeNumber(raw.payoutPermille, 1000)),
			minPartySize = math.max(1, wholeNumber(raw.minPartySize, 1)),
		})
	end
	return result
end

local function normalizeAgreement(state: { [string]: any }): Agreement?
	local raw = state.activeAgreement
	if typeof(raw) == "table" then
		local kind = string.lower(asString(raw.kind or raw.type, ""))
		if kind == "contract" then
			return { kind = "contract", id = asString(raw.id or raw.contractId, ""), depth = nil }
		elseif kind == "wager" then
			return { kind = "wager", id = nil, depth = math.max(1, wholeNumber(raw.depth or raw.targetDepth, 1)) }
		end
	end
	if typeof(state.activeContractId) == "string" and state.activeContractId ~= "" then
		return { kind = "contract", id = state.activeContractId, depth = nil }
	elseif typeof(state.activeWagerDepth) == "number" then
		return { kind = "wager", id = nil, depth = math.max(1, wholeNumber(state.activeWagerDepth, 1)) }
	end
	return nil
end

local function refreshCurrency()
	if currencyLabel ~= nil then
		currencyLabel.Text = string.format("%d  RAW WAX", currency)
	end
end

local function consumeState(state: { [string]: any })
	local previouslyOwnedLamp: { [string]: boolean } = {}
	for _, offer in lampOffers do
		previouslyOwnedLamp[offer.nodeId] = offer.owned
	end
	local previouslyOwnedCave: { [number]: boolean } = {}
	for _, offer in caveOffers do
		previouslyOwnedCave[offer.tierId] = offer.owned
	end

	currency = math.max(0, wholeNumber(state.currency or state.balance, currency))
	lampOffers = normalizeLampOffers(state)
	caveOffers = normalizeCaveOffers(state)
	contracts = normalizeContracts(state)
	activeAgreement = normalizeAgreement(state)
	if typeof(state.lastRunBreakdown) == "table" then
		lastRunBreakdown = state.lastRunBreakdown
	elseif state.lastRunBreakdown == false then
		lastRunBreakdown = nil
	end
	minimumWagerTarget = math.max(1, wholeNumber(state.minimumWagerTarget or state.wagerMinimum, minimumWagerTarget))
	if activeAgreement ~= nil and activeAgreement.kind == "wager" and activeAgreement.depth ~= nil then
		wagerTarget = math.max(minimumWagerTarget, activeAgreement.depth)
	else
		wagerTarget = math.max(minimumWagerTarget, wagerTarget)
	end

	if selectedLampId == nil or findLamp(selectedLampId) == nil then
		selectedLampId = if #lampOffers > 0 then lampOffers[1].nodeId else nil
	end
	if selectedCaveId == nil or findCave(selectedCaveId) == nil then
		selectedCaveId = if #caveOffers > 0 then caveOffers[1].tierId else nil
	end
	refreshCurrency()
	if treeView ~= nil then
		treeView.setNodes(lampOffers, selectedLampId)
	end
	renderCaveList()
	if activeTab == "lamp" then
		renderLampDetails()
	else
		renderCaveDetails()
	end

	local result = state.result
	local status = asString(state.status or state.message, "")
	local pending = pendingIntent
	if pending ~= nil then
		local succeeded = false
		if pending.kind == "lamp" then
			local offer = findLamp(pending.id)
			succeeded = offer ~= nil and offer.owned and previouslyOwnedLamp[pending.id] ~= true
			if succeeded and treeView ~= nil then
				treeView.flashNode(pending.id)
			end
		elseif pending.kind == "cave" then
			local tierId = tonumber(pending.id)
			local offer = findCave(tierId)
			succeeded = offer ~= nil and offer.owned and previouslyOwnedCave[tierId :: number] ~= true
		elseif pending.kind == "contract" then
			succeeded = activeAgreement ~= nil
				and activeAgreement.kind == "contract"
				and activeAgreement.id == pending.id
		elseif pending.kind == "wager" then
			succeeded = activeAgreement ~= nil
				and activeAgreement.kind == "wager"
				and activeAgreement.depth == tonumber(pending.id)
		elseif pending.kind == "agreement" then
			succeeded = activeAgreement == nil
		end
		if typeof(result) == "table" and result.ok == false then
			succeeded = false
		end
		if status ~= "" then
			showToast(status, not succeeded)
		elseif succeeded then
			showToast("The keeper records the change.")
		else
			showToast("That change could not be completed.", true)
		end
		pendingIntent = nil
	elseif status ~= "" then
		showToast(status, typeof(result) == "table" and result.ok == false)
	end

	if state.open == false then
		setOpen(false, false)
	else
		setOpen(true, false)
	end
end

local function applyLayout()
	local group = root
	local panel = mainPanel
	local content = contentFrame
	local left = browserPane
	local right = detailPane
	if
		group == nil
		or panel == nil
		or content == nil
		or left == nil
		or right == nil
		or header == nil
		or tabsFrame == nil
	then
		return
	end
	local viewport = group.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	local margin = if viewport.X < 720 then 8 else 28
	local panelWidth = math.min(1180, math.max(260, viewport.X - margin * 2))
	local panelHeight = math.min(760, math.max(320, viewport.Y - margin * 2))
	panel.Size = UDim2.fromOffset(panelWidth, panelHeight)

	local short = panelHeight < 520
	local headerHeight = if short then 52 else 66
	local tabsHeight = if short then 44 else 50
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	tabsFrame.Position = UDim2.fromOffset(0, headerHeight)
	tabsFrame.Size = UDim2.new(1, 0, 0, tabsHeight)
	content.Position = UDim2.fromOffset(0, headerHeight + tabsHeight)
	content.Size = UDim2.new(1, 0, 1, -(headerHeight + tabsHeight))

	local stacked = panelWidth < 720 and panelHeight > panelWidth * 0.84
	if stacked then
		left.Position = UDim2.fromScale(0, 0)
		left.Size = UDim2.new(1, 0, 0.55, -5)
		right.Position = UDim2.new(0, 0, 0.55, 5)
		right.Size = UDim2.new(1, 0, 0.45, -5)
	else
		left.Position = UDim2.fromScale(0, 0)
		left.Size = UDim2.new(0.66, -6, 1, 0)
		right.Position = UDim2.new(0.66, 6, 0, 0)
		right.Size = UDim2.new(0.34, -6, 1, 0)
	end

	if titleLabel ~= nil and subtitleLabel ~= nil and currencyFrame ~= nil and closeButton ~= nil then
		local narrow = panelWidth < 560
		titleLabel.Text = if narrow then "KEEPER'S SHOP" else "THE KEEPER'S SHOP"
		titleLabel.Position = UDim2.fromOffset(if short then 14 else 20, if short then 6 else 9)
		titleLabel.Size = UDim2.new(1, if narrow then -174 else -330, 0, if short then 36 else 30)
		titleLabel.TextSize = if narrow then 18 else 22
		subtitleLabel.Visible = not narrow and not short
		subtitleLabel.Position = UDim2.fromOffset(20, 38)
		subtitleLabel.Size = UDim2.new(1, -340, 0, 18)
		currencyFrame.Size = UDim2.fromOffset(if narrow then 112 else 148, if short then 38 else 42)
		currencyFrame.Position = UDim2.new(1, if narrow then -162 else -202, 0.5, 0)
		closeButton.Size = UDim2.fromOffset(if short then 42 else 46, if short then 42 else 46)
		closeButton.Position = UDim2.new(1, -10, 0.5, 0)
		if currencyLabel ~= nil then
			currencyLabel.TextSize = if narrow then 11 else 13
		end
	end
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WickShop"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 45
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- The root is a CanvasGroup purely so the whole shop can fade as one surface (GroupTransparency).
	-- It must stay a bare, untinted container: a CanvasGroup renders its descendants into one buffer,
	-- so a UIGradient parented *here* multiplies every child by the gradient colour and drags the
	-- entire shop down to near-black. The dark vertical wash belongs to a backdrop frame underneath.
	local group = Instance.new("CanvasGroup")
	group.Name = "Shop"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Visible = false
	group.Parent = screen
	root = group
	UITheme.backdrop(group, 0.18)

	local panel = UITheme.panel(group)
	panel.Name = "ShopPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.ClipsDescendants = true
	panel.ZIndex = 2
	mainPanel = panel
	mainScale = UITheme.scale(panel, 1)

	local builtHeader = Instance.new("Frame")
	builtHeader.Name = "Header"
	builtHeader.BackgroundColor3 = palette.panelRaised
	builtHeader.BackgroundTransparency = 0.15
	builtHeader.BorderSizePixel = 0
	builtHeader.ZIndex = 3
	builtHeader.Parent = panel
	header = builtHeader

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = UITheme.font.display
	title.Text = "THE KEEPER'S SHOP"
	title.TextColor3 = palette.gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.ZIndex = 4
	title.Parent = builtHeader
	titleLabel = title

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Font = UITheme.font.fine
	subtitle.Text = "Relight old machinery. Own the road down."
	subtitle.TextColor3 = palette.textMuted
	subtitle.TextSize = UITheme.textSize.fine
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 4
	subtitle.Parent = builtHeader
	subtitleLabel = subtitle

	local balance = Instance.new("Frame")
	balance.Name = "Balance"
	balance.AnchorPoint = Vector2.new(1, 0.5)
	balance.BackgroundColor3 = palette.chip
	balance.BorderSizePixel = 0
	balance.ZIndex = 4
	balance.Parent = builtHeader
	UITheme.corner(balance, 9)
	UITheme.stroke(balance, palette.stroke, 1.25, 0.3)
	currencyFrame = balance
	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.Size = UDim2.fromScale(1, 1)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Font = UITheme.font.heading
	balanceLabel.TextColor3 = palette.gold
	balanceLabel.Text = "0  RAW WAX"
	balanceLabel.ZIndex = 5
	balanceLabel.Parent = balance
	currencyLabel = balanceLabel

	local close = UITheme.button(builtHeader, "X")
	close.instance.Name = "Close"
	close.instance.AnchorPoint = Vector2.new(1, 0.5)
	close.instance.Modal = true
	close.instance.ZIndex = 5
	close.instance.Activated:Connect(function()
		setOpen(false, true)
	end)
	closeButton = close.instance

	local builtTabs = Instance.new("Frame")
	builtTabs.Name = "Tabs"
	builtTabs.BackgroundColor3 = palette.panel
	builtTabs.BorderSizePixel = 0
	builtTabs.ZIndex = 3
	builtTabs.Parent = panel
	UITheme.padding(builtTabs, 4, 14, 4, 14)
	tabsFrame = builtTabs
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 10)
	tabLayout.Parent = builtTabs
	local lamp = UITheme.button(builtTabs, "LAMP NETWORK")
	lamp.instance.Size = UDim2.new(0.5, -5, 1, 0)
	lamp.instance.LayoutOrder = 1
	lamp.instance.Activated:Connect(function()
		setTab("lamp")
	end)
	lampTab = lamp
	local cave = UITheme.button(builtTabs, "CAVE ACCESS")
	cave.instance.Size = UDim2.new(0.5, -5, 1, 0)
	cave.instance.LayoutOrder = 2
	cave.instance.Activated:Connect(function()
		setTab("cave")
	end)
	caveTab = cave

	local builtContent = Instance.new("Frame")
	builtContent.Name = "Content"
	builtContent.BackgroundTransparency = 1
	builtContent.BorderSizePixel = 0
	builtContent.ZIndex = 3
	builtContent.Parent = panel
	UITheme.padding(builtContent, 10, 12, 12, 12)
	contentFrame = builtContent

	local left = Instance.new("Frame")
	left.Name = "Browser"
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ZIndex = 3
	left.Parent = builtContent
	browserPane = left
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, 0, 0, 26)
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.font.fine
	caption.Text = "SELECT A NODE  -  DRAG TO PAN  -  SCROLL TO MOVE"
	caption.TextColor3 = palette.textMuted
	caption.TextSize = UITheme.textSize.fine
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.ZIndex = 4
	caption.Parent = left
	browserCaption = caption

	local builtLampHost = Instance.new("Frame")
	builtLampHost.Name = "TreeHost"
	builtLampHost.Position = UDim2.fromOffset(0, 26)
	builtLampHost.Size = UDim2.new(1, 0, 1, -26)
	builtLampHost.BackgroundTransparency = 1
	builtLampHost.ZIndex = 3
	builtLampHost.Parent = left
	lampHost = builtLampHost
	treeView = LampTreeView.create(builtLampHost, function(nodeId)
		selectedLampId = nodeId
		renderLampDetails()
	end)

	local caveList = Instance.new("ScrollingFrame")
	caveList.Name = "CaveList"
	caveList.Position = UDim2.fromOffset(0, 26)
	caveList.Size = UDim2.new(1, 0, 1, -26)
	caveList.BackgroundColor3 = palette.void
	caveList.BackgroundTransparency = 0.24
	caveList.BorderSizePixel = 0
	caveList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	caveList.CanvasSize = UDim2.fromOffset(0, 0)
	caveList.ScrollBarImageColor3 = palette.stroke
	caveList.ScrollBarThickness = 5
	caveList.Visible = false
	caveList.ZIndex = 3
	caveList.Parent = left
	UITheme.corner(caveList, 12)
	UITheme.stroke(caveList, palette.strokeSoft, 1, 0.5)
	caveHost = caveList

	local right = UITheme.panel(builtContent)
	right.Name = "Details"
	right.ZIndex = 3
	detailPane = right
	local details = Instance.new("ScrollingFrame")
	details.Name = "Scroller"
	details.Size = UDim2.fromScale(1, 1)
	details.BackgroundTransparency = 1
	details.BorderSizePixel = 0
	details.AutomaticCanvasSize = Enum.AutomaticSize.Y
	details.CanvasSize = UDim2.fromOffset(0, 0)
	details.ScrollBarImageColor3 = palette.stroke
	details.ScrollBarImageTransparency = 0.3
	details.ScrollBarThickness = 4
	details.ZIndex = 4
	details.Parent = right
	detailScroller = details

	local confirmation = Instance.new("Frame")
	confirmation.Name = "Confirmation"
	confirmation.Size = UDim2.fromScale(1, 1)
	confirmation.BackgroundColor3 = palette.void
	confirmation.BackgroundTransparency = 0.22
	confirmation.BorderSizePixel = 0
	confirmation.Visible = false
	confirmation.ZIndex = 20
	confirmation.Parent = group
	confirmLayer = confirmation
	local confirmationPanel = UITheme.panel(confirmation)
	confirmationPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmationPanel.Position = UDim2.fromScale(0.5, 0.5)
	confirmationPanel.Size = UDim2.new(0.86, 0, 0, 232)
	confirmationPanel.SizeConstraint = Enum.SizeConstraint.RelativeXX
	confirmationPanel.ZIndex = 21
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(470, 260)
	sizeConstraint.MinSize = Vector2.new(280, 220)
	sizeConstraint.Parent = confirmationPanel
	UITheme.padding(confirmationPanel, 20, 20, 18, 20)
	local confirmationLayout = UITheme.listLayout(confirmationPanel, 12)
	confirmationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local confirmationTitle =
		detailLabel(confirmationPanel, "CONFIRM PURCHASE", UITheme.font.display, palette.gold, 20, 1)
	confirmationTitle.TextXAlignment = Enum.TextXAlignment.Center
	confirmHeading = confirmationTitle
	local confirmationText = detailLabel(confirmationPanel, "", UITheme.font.body, palette.text, 14, 2)
	confirmationText.TextXAlignment = Enum.TextXAlignment.Center
	confirmBody = confirmationText
	local confirmationButtons = Instance.new("Frame")
	confirmationButtons.BackgroundTransparency = 1
	confirmationButtons.Size = UDim2.new(1, 0, 0, 48)
	confirmationButtons.LayoutOrder = 3
	confirmationButtons.Parent = confirmationPanel
	local cancel = UITheme.button(confirmationButtons, "CANCEL")
	cancel.instance.Size = UDim2.new(0.5, -5, 1, 0)
	cancel.instance.Activated:Connect(dismissConfirmation)
	local commit = UITheme.button(confirmationButtons, "CONFIRM")
	commit.instance.Position = UDim2.new(0.5, 5, 0, 0)
	commit.instance.Size = UDim2.new(0.5, -5, 1, 0)
	commit.instance.Activated:Connect(function()
		local action = confirmAction
		dismissConfirmation()
		if action ~= nil then
			action()
		end
	end)

	local toastGroup = Instance.new("CanvasGroup")
	toastGroup.Name = "Toast"
	toastGroup.AnchorPoint = Vector2.new(0.5, 1)
	toastGroup.Position = UDim2.new(0.5, 0, 1, -14)
	toastGroup.Size = UDim2.new(0.84, 0, 0, 48)
	toastGroup.BackgroundColor3 = palette.panelRaised
	toastGroup.BackgroundTransparency = 0.04
	toastGroup.BorderSizePixel = 0
	toastGroup.Visible = false
	toastGroup.ZIndex = 30
	toastGroup.Parent = group
	UITheme.corner(toastGroup, 10)
	UITheme.stroke(toastGroup, palette.stroke, 1.25, 0.25)
	local toastSize = Instance.new("UISizeConstraint")
	toastSize.MaxSize = Vector2.new(650, 48)
	toastSize.Parent = toastGroup
	local message = Instance.new("TextLabel")
	message.Size = UDim2.new(1, -24, 1, 0)
	message.Position = UDim2.fromOffset(12, 0)
	message.BackgroundTransparency = 1
	message.Font = UITheme.font.heading
	message.Text = ""
	message.TextColor3 = palette.gold
	message.TextSize = UITheme.textSize.body
	message.TextWrapped = true
	message.ZIndex = 31
	message.Parent = toastGroup
	toast = toastGroup
	toastLabel = message

	group:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	task.defer(applyLayout)
	setTab("lamp")
end

function ShopController.start()
	build()
	player:SetAttribute(SHOP_OPEN_ATTRIBUTE, false)
	Remotes.get("ShopState").OnClientEvent:Connect(function(state: { [string]: any })
		if typeof(state) ~= "table" then
			return
		end
		consumeState(state)
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not isOpen or processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			if confirmLayer ~= nil and confirmLayer.Visible then
				dismissConfirmation()
			else
				setOpen(false, true)
			end
		end
	end)
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
			setOpen(false, false)
		end
	end)
end

return ShopController

--!strict
-- Per-player developer diagnostics unlocked from the Landing. All highlights and UI are local;
-- the server authorizes the PIN and sends observation-only aggregate stats.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local AshamedLurkerVisualProtocol = require(ReplicatedStorage.Shared.AshamedLurkerVisualProtocol)
local MiningVisualProtocol = require(ReplicatedStorage.Shared.MiningVisualProtocol)
local UnlittiusVisualProtocol = require(ReplicatedStorage.Shared.UnlittiusVisualProtocol)
local ThreatVisualProtocol = require(ReplicatedStorage.Shared.NewModelsAndObjects.ThreatVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local DevDiagnosticsController = {}

type Marker = {
	highlight: Highlight,
	billboard: BillboardGui?,
	-- Kept so the label can be REWRITTEN rather than only created. Most markers say the same thing
	-- for their whole life; a boss does not, and "what is he doing right now" is the single most
	-- useful thing this overlay can put on screen while an encounter is being tuned.
	label: TextLabel?,
	kind: string,
}

local player = Players.LocalPlayer
local palette = UITheme.palette
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local markers: { [Instance]: Marker } = {}
local enabled = false
-- AUTHORIZED AND SHOWN ARE TWO DIFFERENT THINGS, and they used to be one.
--
-- `enabled` is the server's answer to the access code: it is what gates the stats subscription and it
-- is not something a keypress may change. `shown` is whether the overlay is currently drawn. Until
-- this split existed there was no way back: entering the code turned every enemy, ore seam, pickup and
-- exit in the world into a red nameplate for the rest of the session, and a developer who wanted to
-- LOOK at the thing they had just built — which is most of what the code is entered for — had to
-- rejoin the game to get their view back.
--
-- F8 is now the door AND the switch: it asks for the code while locked, and toggles the overlay once
-- it is not.
local shown = true

local serverStats: { [string]: unknown } = {}
local accessButton: TextButton? = nil
local accessPanel: CanvasGroup? = nil
local codeBox: TextBox? = nil
local accessStatus: TextLabel? = nil
local statsPanel: Frame? = nil
local statsLabel: TextLabel? = nil
local localFps = 0
local frameElapsed = 0
local frameCount = 0
local nextUiRefresh = 0
local typedCode = ""

local function expeditionActive(): boolean
	return player:GetAttribute(EXPEDITION_ATTRIBUTE) == true
end

local function setTeleportHandoffDiagnostics(visible: boolean)
	local template = ReplicatedFirst:FindFirstChild("WickTeleportGui")
	if template == nil or not template:IsA("ScreenGui") then
		return
	end
	local previous = template:FindFirstChild("WickDevTeleportDiagnostics")
	if previous ~= nil then
		previous:Destroy()
	end
	if visible then
		local panel = Instance.new("Frame")
		panel.Name = "WickDevTeleportDiagnostics"
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.fromScale(0.985, 0.025)
		panel.Size = UDim2.fromOffset(390, 92)
		panel.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
		panel.BackgroundTransparency = 0.08
		panel.BorderSizePixel = 0
		panel.ZIndex = 50
		panel.Parent = template
		UITheme.corner(panel, 8)
		UITheme.stroke(panel, Config.Diagnostics.highlightColor, 1.5, 0.1)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -24, 1, -20)
		label.Position = UDim2.fromOffset(12, 10)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Code
		label.Text = "DEV DIAGNOSTICS - TRANSFERRING\nDestination loading telemetry attaching..."
		label.TextColor3 = Config.Diagnostics.highlightColor
		label.TextSize = 14
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.ZIndex = 51
		label.Parent = panel
	end
	TeleportService:SetTeleportGui(template)
end

local function rootFor(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function markerText(instance: Instance, kind: string): string
	if kind == "ORE" then
		local rowId = instance:GetAttribute(MiningVisualProtocol.attributes.rowId)
		local depth = instance:GetAttribute(MiningVisualProtocol.attributes.depth)
		return string.format("ORE  %s  F%s", tostring(rowId or "STANDARD"), tostring(depth or "?"))
	end
	if kind == "ENEMY" then
		return "ENEMY  " .. tostring(instance:GetAttribute(ThreatVisualProtocol.attributes.kind) or instance.Name)
	end
	if kind == "PACK" then
		-- The variant system is the thing this label exists to make debuggable. A wick-pack body wears
		-- one of three dressings and rolls an elder about one time in twelve, and both are silent
		-- properties of the model — VARIANTS.md's own acceptance test is "spawn six of the same enemy
		-- and they should look like six individuals", which is impossible to check by eye alone. The
		-- attributes are written by `EnemyKit.begin`/`finish` at construction.
		local id = tostring(instance:GetAttribute("EnemyId") or instance.Name)
		local variant = tostring(instance:GetAttribute("Variant") or "regular")
		local elder = if instance:GetAttribute("Elder") == true then "  ELDER" else ""
		-- A BOSS ALSO SAYS WHAT IT IS DOING. Both authored bosses publish their current action as a
		-- replicated attribute — that attribute IS the server-to-client contract their whole
		-- presentation runs on — so reading it here costs nothing and turns "he just stands there"
		-- from a report into a measurement: a label stuck on `Idle` means the director never picked an
		-- action, and one cycling through `Dripstone` / `BoulderBurst` means it did and the problem is
		-- downstream of the decision.
		local action = instance:GetAttribute(UnlittiusVisualProtocol.boss.attributes.action)
		local state = if action ~= nil then "  " .. tostring(action) else ""
		return string.format("%s  %s%s%s", id, variant, elder, state)
	end
	if kind == "ITEM" then
		return "ITEM  " .. tostring(instance:GetAttribute(Config.Diagnostics.itemNameAttribute) or instance.Name)
	end
	if kind == "DESCENT" then
		return "NEXT FLOOR"
	end
	return kind
end

local function removeMarker(instance: Instance)
	local marker = markers[instance]
	if marker == nil then
		return
	end
	marker.highlight:Destroy()
	if marker.billboard ~= nil then
		marker.billboard:Destroy()
	end
	markers[instance] = nil
end

local function addMarker(instance: Instance, kind: string)
	-- `enabled and shown` written out rather than `visible()`, which is declared further down. This is
	-- also the guard that makes hiding the overlay stick: tags keep arriving while it is off.
	if not (enabled and shown) or markers[instance] ~= nil or instance.Parent == nil then
		return
	end
	local root = rootFor(instance)
	if root == nil then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "WickDevHighlight"
	highlight.Adornee = instance
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Config.Diagnostics.highlightColor
	highlight.OutlineColor = Config.Diagnostics.highlightColor
	highlight.FillTransparency = Config.Diagnostics.highlightFillTransparency
	highlight.OutlineTransparency = Config.Diagnostics.highlightOutlineTransparency
	highlight.Parent = instance

	local billboard: BillboardGui? = nil
	local textLabel: TextLabel? = nil
	-- Client-built bodies get the red silhouette, while their authoritative invisible proxies own
	-- the single text marker. Keeping those roles separate avoids two labels at the same position.
	if kind ~= "ENEMY_VISUAL" then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "WickDevMarker"
		billboard.Adornee = root
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = Config.Diagnostics.markerMaxDistance
		billboard.Size = UDim2.fromOffset(190, 30)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		billboard.Parent = root

		local label = Instance.new("TextLabel")
		textLabel = label
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.BackgroundTransparency = 0.25
		label.BorderSizePixel = 0
		label.Font = UITheme.font.heading
		label.Text = markerText(instance, kind)
		label.TextColor3 = Config.Diagnostics.highlightColor
		label.TextSize = UITheme.textSize.fine
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0
		label.Parent = billboard
		UITheme.corner(label, 5)
	end

	markers[instance] = { highlight = highlight, billboard = billboard, label = textLabel, kind = kind }
end

-- Rewrite every marker's text against the world as it is now. Cheap — one string per tagged instance,
-- twice a second — and it is what makes a live attribute like a boss's current action readable at all;
-- without it a label says whatever was true the moment the marker was built.
local function refreshLabels()
	for instance, marker in markers do
		local label = marker.label
		if label ~= nil and instance.Parent ~= nil then
			label.Text = markerText(instance, marker.kind)
		end
	end
end

local function clearMarkers()
	local instances: { Instance } = {}
	for instance in markers do
		table.insert(instances, instance)
	end
	for _, instance in instances do
		removeMarker(instance)
	end
end

local function addCurrentMarkers()
	for _, instance in CollectionService:GetTagged(MiningVisualProtocol.depositTag) do
		addMarker(instance, "ORE")
	end
	for _, instance in CollectionService:GetTagged(Config.Feel.threatWarning.collectionTag) do
		addMarker(instance, "ENEMY")
	end
	for _, instance in CollectionService:GetTagged(AshamedLurkerVisualProtocol.tag) do
		addMarker(instance, "LURKER")
	end
	for _, instance in CollectionService:GetTagged(Config.Diagnostics.wardenTag) do
		addMarker(instance, "WARDEN")
	end
	for _, instance in CollectionService:GetTagged(Config.Diagnostics.enemyVisualTag) do
		addMarker(instance, "ENEMY_VISUAL")
	end
	for _, instance in CollectionService:GetTagged(Config.Diagnostics.packEnemyTag) do
		addMarker(instance, "PACK")
	end
	for _, instance in CollectionService:GetTagged(Config.Diagnostics.itemTag) do
		addMarker(instance, "ITEM")
	end
	for _, instance in CollectionService:GetTagged(Config.Diagnostics.descentTag) do
		addMarker(instance, "DESCENT")
	end
end

local function refreshAccessButton()
	local button = accessButton
	if button == nil then
		return
	end
	button.Visible = not enabled and not expeditionActive()
	button.Text = "DEV CODE  -  F8"
end

local function setAccessOpen(open: boolean)
	local panel = accessPanel
	if panel == nil then
		return
	end
	local allowed = open and not enabled and not expeditionActive()
	panel.Visible = allowed
	CursorController.setReleased("DevDiagnostics", allowed)
	if allowed and codeBox ~= nil then
		codeBox.Text = ""
		codeBox:CaptureFocus()
	end
end

local function visible(): boolean
	return enabled and shown
end

local function applyPresentation()
	local drawing = visible()
	if statsPanel ~= nil then
		statsPanel.Visible = drawing
	end
	if drawing then
		addCurrentMarkers()
	else
		-- The markers are torn down rather than hidden. They are one BillboardGui per tagged instance
		-- and there can be hundreds; leaving them parented and invisible would keep the whole set
		-- alive, and rebuilding them costs one pass over the tagged instances the next time F8 goes on.
		clearMarkers()
	end
	refreshAccessButton()
end

local function setEnabled(nextEnabled: boolean)
	enabled = nextEnabled
	-- A fresh authorization always shows: entering the code and seeing nothing happen would read as
	-- the code being refused.
	if nextEnabled then
		shown = true
	end
	setTeleportHandoffDiagnostics(nextEnabled)
	setAccessOpen(false)
	applyPresentation()
end

-- F8 while authorized. The teleport-handoff readout follows the overlay, because it is part of the
-- same red furniture and hiding one while leaving the other on screen would be worse than either.
local function setShown(nextShown: boolean)
	if not enabled or shown == nextShown then
		return
	end
	shown = nextShown
	setTeleportHandoffDiagnostics(nextShown)
	applyPresentation()
end

local function submitCode()
	local input = codeBox
	if input == nil then
		return
	end
	if accessStatus ~= nil then
		accessStatus.Text = "CHECKING…"
	end
	Remotes.get("DevDiagnostics"):FireServer("unlock", input.Text)
end

local function numberField(name: string): number
	local value = serverStats[name]
	return if typeof(value) == "number" and value == value then value else 0
end

local function markerCount(): number
	local count = 0
	for _ in markers do
		count += 1
	end
	return count
end

local function refreshStatsText()
	local label = statsLabel
	if label == nil or not visible() then
		return
	end
	local pingMs = 0
	pcall(function()
		pingMs = math.round(player:GetNetworkPing() * 1000)
	end)
	local clientMemory = math.round(Stats:GetTotalMemoryUsageMb())
	local mode = if serverStats.reservedServer == true then "RESERVED" else "PUBLIC"
	label.Text = string.format(
		"DEV DIAGNOSTICS\nCLIENT  %d FPS  %d ms  %d MB\nSERVER  %d FPS  %d MB  %ds  %s\nPLAYERS %d  INSTANCES %d\nENM %d  ORE %d  ITEM %d  EXIT %d\nMARK %d\nSTAGE   %s\nJOB     %s",
		math.round(localFps),
		pingMs,
		clientMemory,
		numberField("serverFps"),
		numberField("serverMemoryMb"),
		numberField("serverUptime"),
		mode,
		numberField("players"),
		numberField("workspaceInstances"),
		numberField("threats"),
		numberField("ore"),
		numberField("items"),
		numberField("descents"),
		markerCount(),
		tostring(serverStats.loadingStage or "waiting"),
		tostring(serverStats.job or "--------")
	)
end

local function buildUi()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickDevDiagnostics"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80

	-- UITheme helpers require a GuiObject parent. A ScreenGui accepts GUI children at runtime, but it
	-- is not itself a GuiObject; keeping one transparent root satisfies that contract consistently.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local button = UITheme.button(root, "DEV CODE")
	button.instance.Name = "DevCode"
	button.instance.AnchorPoint = Vector2.new(1, 1)
	button.instance.Position = UDim2.fromScale(0.98, 0.96)
	button.instance.Size = UDim2.fromOffset(138, 40)
	button.instance.Activated:Connect(function()
		if not enabled then
			setAccessOpen(true)
		end
	end)
	accessButton = button.instance

	local panel = Instance.new("CanvasGroup")
	panel.Name = "Access"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(390, 250)
	panel.BackgroundColor3 = palette.panel
	panel.BackgroundTransparency = 0.02
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = root
	UITheme.corner(panel, 14)
	UITheme.stroke(panel, palette.stroke, 1.5, 0.25)
	UITheme.uniformPadding(panel, 22)
	UITheme.listLayout(panel, 12)
	accessPanel = panel

	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, 0, 0, 38)
	titleRow.LayoutOrder = 1
	titleRow.Parent = panel

	local heading = UITheme.heading(titleRow, "DEVELOPER ACCESS")
	heading.Size = UDim2.new(1, -46, 1, 0)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.fromScale(1, 0)
	closeButton.Size = UDim2.fromOffset(38, 38)
	closeButton.BackgroundColor3 = palette.chip
	closeButton.BorderSizePixel = 0
	closeButton.Font = UITheme.font.heading
	closeButton.Text = "X"
	closeButton.TextColor3 = palette.text
	closeButton.TextSize = UITheme.textSize.strong
	closeButton.Parent = titleRow
	UITheme.corner(closeButton, 10)
	UITheme.stroke(closeButton, palette.strokeSoft, 1, 0.25)
	closeButton.Activated:Connect(function()
		setAccessOpen(false)
	end)

	local note = UITheme.label(panel, "Enter the Landing diagnostic code.", 28)
	note.TextColor3 = palette.textMuted
	note.LayoutOrder = 2

	local input = Instance.new("TextBox")
	input.Name = "Code"
	input.Size = UDim2.new(1, 0, 0, 48)
	input.LayoutOrder = 3
	input.BackgroundColor3 = palette.panelRaised
	input.BorderSizePixel = 0
	input.ClearTextOnFocus = false
	input.Font = UITheme.font.heading
	input.PlaceholderText = "ACCESS CODE"
	input.PlaceholderColor3 = palette.textMuted
	input.Text = ""
	input.TextColor3 = palette.text
	input.TextSize = UITheme.textSize.strong
	input.Parent = panel
	UITheme.corner(input, 8)
	UITheme.stroke(input, palette.stroke, 1, 0.45)
	input.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submitCode()
		end
	end)
	codeBox = input

	local submit = UITheme.button(panel, "ENABLE DIAGNOSTICS")
	submit.instance.Size = UDim2.new(1, 0, 0, 44)
	submit.instance.LayoutOrder = 4
	submit.instance.Activated:Connect(submitCode)

	local status = UITheme.label(panel, "", 22)
	status.TextColor3 = Config.Diagnostics.highlightColor
	status.LayoutOrder = 5
	accessStatus = status

	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.AnchorPoint = Vector2.new(1, 0)
	stats.Position = UDim2.fromScale(0.985, 0.025)
	stats.Size = UDim2.fromOffset(330, 190)
	stats.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	stats.BackgroundTransparency = 0.12
	stats.BorderSizePixel = 0
	stats.Visible = false
	stats.Parent = root
	UITheme.corner(stats, 8)
	UITheme.stroke(stats, Config.Diagnostics.highlightColor, 1, 0.15)
	statsPanel = stats

	local text = Instance.new("TextLabel")
	text.Position = UDim2.fromOffset(12, 10)
	text.Size = UDim2.new(1, -24, 1, -20)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Code
	text.Text = "DEV DIAGNOSTICS\nWAITING FOR SERVER…"
	text.TextColor3 = Config.Diagnostics.highlightColor
	text.TextSize = 14
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Parent = stats
	statsLabel = text

	gui.Parent = player:WaitForChild("PlayerGui")
	refreshAccessButton()
end

local function watchTag(tag: string, kind: string)
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		addMarker(instance, kind)
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeMarker)
end

function DevDiagnosticsController.start()
	buildUi()
	watchTag(MiningVisualProtocol.depositTag, "ORE")
	watchTag(Config.Feel.threatWarning.collectionTag, "ENEMY")
	watchTag(AshamedLurkerVisualProtocol.tag, "LURKER")
	watchTag(Config.Diagnostics.wardenTag, "WARDEN")
	watchTag(Config.Diagnostics.enemyVisualTag, "ENEMY_VISUAL")
	-- The wick-pack bodies are server-built and replicate whole, so unlike the proxy-backed threats
	-- above they own BOTH their silhouette and their label — no separate authoritative proxy exists to
	-- hand the text to, which is why "PACK" is not excluded from the billboard the way ENEMY_VISUAL is.
	watchTag(Config.Diagnostics.packEnemyTag, "PACK")
	watchTag(Config.Diagnostics.itemTag, "ITEM")
	watchTag(Config.Diagnostics.descentTag, "DESCENT")

	Remotes.get("DevDiagnostics").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if typeof(kind) ~= "string" or typeof(payload) ~= "table" then
			return
		end
		if kind == "state" then
			local accepted = payload.accepted == true
			if accessStatus ~= nil then
				accessStatus.Text = tostring(payload.message or "")
			end
			if accepted then
				setEnabled(payload.enabled == true)
			end
		elseif kind == "stats" and enabled then
			serverStats = payload
			refreshStatsText()
		end
	end)

	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if expeditionActive() then
			setAccessOpen(false)
		end
		refreshAccessButton()
	end)
	-- First-person camera/input systems may mark keyboard events as processed, which is why this is a
	-- bound action at high priority rather than an `InputBegan` listener.
	--
	-- ONE KEY, TWO JOBS, decided by whether the session is already authorized: the access door while it
	-- is not, and the overlay switch once it is. It is deliberately NOT a second keybind — a developer
	-- who has just been handed a screen full of red nameplates reaches for the key that produced them.
	ContextActionService:BindActionAtPriority(
		"WickDevDiagnostics",
		function(_actionName: string, inputState: Enum.UserInputState, _input: InputObject)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			if enabled then
				setShown(not shown)
			elseif not expeditionActive() then
				setAccessOpen(true)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 100,
		Enum.KeyCode.F8
	)
	-- Zero-interaction access for the game's locked-mouse presentation: type 0610 while walking in
	-- the Landing. This observes number keys without consuming them, then lets the server validate the
	-- completed code and the player's authoritative lobby position.
	local codeDigits = {
		[Enum.KeyCode.Zero] = "0",
		[Enum.KeyCode.Six] = "6",
		[Enum.KeyCode.One] = "1",
	}
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if enabled or expeditionActive() then
			return
		end
		local digit = codeDigits[input.KeyCode]
		if digit == nil then
			return
		end
		typedCode = string.sub(typedCode .. digit, -4)
		if typedCode == Config.Diagnostics.unlockCode then
			typedCode = ""
			Remotes.get("DevDiagnostics"):FireServer("unlock", Config.Diagnostics.unlockCode)
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		frameElapsed += dt
		frameCount += 1
		if frameElapsed >= 0.5 then
			localFps = frameCount / frameElapsed
			frameElapsed = 0
			frameCount = 0
		end
		if enabled and shown and os.clock() >= nextUiRefresh then
			nextUiRefresh = os.clock() + 0.5
			-- Builders tag models before their owning service seats and parents them. The added-tag signal
			-- therefore sees a temporarily parentless model and correctly refuses it; reconcile the live
			-- tag set here so that model is picked up once it enters Workspace. This also repairs visuals
			-- recreated after a death, floor transition, or client-side cull.
			addCurrentMarkers()
			refreshLabels()
			refreshStatsText()
		end
	end)

	Remotes.get("DevDiagnostics"):FireServer("sync")
end

return DevDiagnosticsController

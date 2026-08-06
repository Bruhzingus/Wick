--!strict
-- Renders only update entries selected by the server from the player's loaded profile. Closing the
-- panel sends no version or entry id; the server derives and persists its own current build.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local UpdateLogController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette
local textSize = UITheme.textSize

type UpdateEntry = {
	version: number,
	date: string,
	lines: { string },
}

local gui: ScreenGui? = nil
local panel: Frame? = nil
local panelScale: UIScale? = nil
local list: ScrollingFrame? = nil
local shownThisSession = false

local function textLabel(parent: Instance, text: string, size: number, color: Color3, bold: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, size + 8)
	label.Font = if bold then UITheme.font.heading else UITheme.font.body
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

local function close()
	local screen = gui
	if screen == nil or not screen.Enabled then
		return
	end
	screen.Enabled = false
	CursorController.setReleased("UpdateLog", false)
	Remotes.get("LobbyAction"):FireServer("dismissUpdates")
end

-- The panel is authored at 560x520 but must never exceed the actual screen: on a narrow phone
-- viewport a fixed offset size pushes the close button (anchored to the panel's own top-right
-- corner) past the edge of the screen, which is why the log could not be dismissed on mobile.
-- Same clamp-to-viewport approach as `ShopController.applyLayout` — shrink to fit, never grow past
-- the authored size.
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
	local margin = if availableX < 420 then 10 else 24
	local width = math.min(560, math.max(280, availableX - margin * 2))
	local height = math.min(520, math.max(320, availableY - margin * 2))
	panelFrame.Size = UDim2.fromOffset(width, height)
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WickUpdateLog"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 40
	screen.Enabled = false

	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = palette.void
	shade.BackgroundTransparency = 0.24
	shade.BorderSizePixel = 0
	shade.Parent = screen

	local panelFrame = UITheme.panel(shade)
	panelFrame.Name = "UpdatePanel"
	panelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	panelFrame.Position = UDim2.fromScale(0.5, 0.5)
	panelFrame.Size = UDim2.fromOffset(560, 520)
	panel = panelFrame

	-- Exactly one density scale at the panel root. Every descendant uses the shared authored scale.
	panelScale = UITheme.scale(panelFrame, UITheme.density())
	UITheme.padding(panelFrame, 22, 22, 20, 22)

	local title = textLabel(panel, "WHAT'S NEW", textSize.title, palette.gold, true)
	title.Name = "Title"
	title.Size = UDim2.new(1, -56, 0, 42)
	UITheme.legible(title, 0.65)

	local subtitle = textLabel(panel, "Updates since your last visit", textSize.fine, palette.textMuted, false)
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(0, 42)
	subtitle.Size = UDim2.new(1, -56, 0, 26)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 0, 0, 0)
	closeButton.Size = UDim2.fromOffset(42, 42)
	closeButton.BackgroundColor3 = palette.chip
	closeButton.BorderSizePixel = 0
	closeButton.Font = UITheme.font.heading
	closeButton.Text = "X"
	closeButton.TextColor3 = palette.text
	closeButton.TextSize = textSize.strong
	closeButton.Parent = panel
	UITheme.corner(closeButton, 10)
	UITheme.stroke(closeButton, palette.strokeSoft, 1, 0.25)
	closeButton.Activated:Connect(close)

	local updates = Instance.new("ScrollingFrame")
	updates.Name = "Entries"
	updates.Position = UDim2.fromOffset(0, 82)
	updates.Size = UDim2.new(1, 0, 1, -142)
	updates.BackgroundTransparency = 1
	updates.BorderSizePixel = 0
	updates.ScrollBarThickness = 5
	updates.ScrollBarImageColor3 = palette.stroke
	updates.AutomaticCanvasSize = Enum.AutomaticSize.Y
	updates.CanvasSize = UDim2.new()
	updates.Parent = panel
	UITheme.listLayout(updates, 10)
	list = updates

	local continueButton = Instance.new("TextButton")
	continueButton.Name = "Continue"
	continueButton.AnchorPoint = Vector2.new(0, 1)
	continueButton.Position = UDim2.new(0, 0, 1, 0)
	continueButton.Size = UDim2.new(1, 0, 0, 44)
	continueButton.BackgroundColor3 = palette.chipActive
	continueButton.BorderSizePixel = 0
	continueButton.Font = UITheme.font.heading
	continueButton.Text = "CONTINUE"
	continueButton.TextColor3 = palette.gold
	continueButton.TextSize = textSize.strong
	continueButton.Parent = panel
	UITheme.corner(continueButton, 10)
	UITheme.stroke(continueButton, palette.stroke, 1.5, 0.2)
	continueButton.Activated:Connect(close)

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	applyLayout()
end

local function readEntries(rawEntries: unknown): { UpdateEntry }
	local entries: { UpdateEntry } = {}
	if typeof(rawEntries) ~= "table" then
		return entries
	end
	for _, raw in rawEntries :: { unknown } do
		if typeof(raw) ~= "table" then
			continue
		end
		local row = raw :: { [string]: unknown }
		local version = row.version
		local date = row.date
		local rawLines = row.lines
		if typeof(version) ~= "number" or typeof(date) ~= "string" or typeof(rawLines) ~= "table" then
			continue
		end
		local lines: { string } = {}
		for _, line in rawLines :: { unknown } do
			if typeof(line) == "string" then
				table.insert(lines, line)
			end
		end
		table.insert(entries, { version = version, date = date, lines = lines })
	end
	return entries
end

local function render(entries: { UpdateEntry })
	if shownThisSession or #entries == 0 then
		return
	end
	local container = list
	local screen = gui
	if container == nil or screen == nil then
		return
	end
	shownThisSession = true
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for index, entry in entries do
		local card = Instance.new("Frame")
		card.Name = "Build" .. tostring(entry.version)
		card.LayoutOrder = index
		-- Height grows to fit wrapped text instead of assuming one line per entry: the panel can now
		-- be much narrower than its authored 560px on a phone, and these lines wrap there.
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.Size = UDim2.new(1, -8, 0, 0)
		card.BackgroundColor3 = palette.chip
		card.BackgroundTransparency = 0.12
		card.BorderSizePixel = 0
		card.Parent = container
		UITheme.corner(card, 10)
		UITheme.stroke(card, palette.strokeSoft, 1, 0.4)
		UITheme.padding(card, 12, 14, 12, 14)
		UITheme.listLayout(card, 4)

		local heading = textLabel(
			card,
			string.format("BUILD %d  /  %s", entry.version, entry.date),
			textSize.strong,
			palette.gold,
			true
		)
		heading.LayoutOrder = 1
		heading.Size = UDim2.new(1, 0, 0, 28)
		for lineIndex, line in entry.lines do
			local body = textLabel(card, "• " .. line, textSize.body, palette.text, false)
			body.LayoutOrder = 1 + lineIndex
			body.AutomaticSize = Enum.AutomaticSize.Y
			body.Size = UDim2.fromScale(1, 0)
		end
	end
	applyLayout()
	screen.Enabled = true
	CursorController.setReleased("UpdateLog", true)
end

function UpdateLogController.start()
	build()
	-- `any` is confined to this untyped RemoteEvent boundary; only `unseenUpdates` is read here.
	Remotes.get("LobbyState").OnClientEvent:Connect(function(state: { [string]: any })
		render(readEntries(state.unseenUpdates))
	end)
end

return UpdateLogController

--!strict
-- Client presentation for the physical developer-lab terminal. The client owns only keypad text and
-- status; the server validates the PIN/proximity and every in-room control is a server-owned prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CursorController = require(script.Parent.CursorController)
local UITheme = require(script.Parent.UITheme)

local DevTestRoomController = {}

local player = Players.LocalPlayer
local remote = Remotes.get("DevTestRoom")
local palette = UITheme.palette
local CURSOR_OWNER = "DevTestRoomKeypad"

local gui: ScreenGui? = nil
local panel: Frame? = nil
local codeBox: TextBox? = nil
local statusLabel: TextLabel? = nil
local active = false
local sprinting = false
local statusGeneration = 0

-- How long ANY lab status line stays up. Nothing here is persistent any more, including the
-- "test lab active" line that used to stand for the whole session: every one of these confirms
-- something the developer just did and can see the result of, and a line that never clears is a
-- permanent strip across the screen for the rest of the visit.
local STATUS_SECONDS = 1

local function setKeypadVisible(visible: boolean)
	if panel ~= nil then
		panel.Visible = visible
	end
	CursorController.setReleased(CURSOR_OWNER, visible)
	if visible and codeBox ~= nil then
		codeBox.Text = ""
		codeBox:CaptureFocus()
	elseif codeBox ~= nil then
		codeBox:ReleaseFocus()
	end
end

local function showStatus(message: string)
	local label = statusLabel
	if label == nil then
		return
	end
	statusGeneration += 1
	local generation = statusGeneration
	label.Text = message
	label.Visible = message ~= ""
	if message == "" then
		return
	end
	task.delay(STATUS_SECONDS, function()
		-- Generation guard only: a newer line has already taken the label and owns its own timer.
		if generation == statusGeneration then
			label.Visible = false
		end
	end)
end

-- Edge-triggered, so a held key sends one message rather than one per repeat and a release that
-- arrives twice (key-up plus focus loss) costs nothing.
local function setSprinting(wanted: boolean)
	if sprinting == wanted then
		return
	end
	sprinting = wanted
	remote:FireServer("sprint", wanted)
end

local function submit()
	local box = codeBox
	if box == nil then
		return
	end
	if #box.Text ~= 4 then
		showStatus("Enter the four-digit lab code.")
		return
	end
	remote:FireServer("enter", box.Text)
	setKeypadVisible(false)
end

local function makeButton(parent: Instance, text: string, position: UDim2, size: UDim2): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = palette.panel
	button.BackgroundTransparency = 0.08
	button.BorderSizePixel = 0
	button.Font = UITheme.font.heading
	button.Text = text
	button.TextColor3 = palette.text
	button.TextScaled = true
	button.Parent = parent
	UITheme.corner(button, 4)
	UITheme.stroke(button, palette.gold, 1, 0.45)
	return button
end

local function build()
	local root = Instance.new("ScreenGui")
	root.Name = "WickDevTestRoom"
	root.ResetOnSpawn = false
	root.IgnoreGuiInset = true
	root.DisplayOrder = 80

	local frame = Instance.new("Frame")
	frame.Name = "Keypad"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(320, 430)
	frame.BackgroundColor3 = palette.void
	frame.BackgroundTransparency = 0.03
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = root
	UITheme.corner(frame, 8)
	UITheme.stroke(frame, palette.gold, 2, 0.18)
	panel = frame

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(20, 16)
	title.Size = UDim2.new(1, -80, 0, 42)
	title.BackgroundTransparency = 1
	title.Font = UITheme.font.display
	title.Text = "ENEMY TEST LAB"
	title.TextColor3 = palette.gold
	title.TextScaled = true
	title.Parent = frame

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -16, 0, 16)
	closeButton.Size = UDim2.fromOffset(30, 30)
	closeButton.BackgroundColor3 = palette.panel
	closeButton.BackgroundTransparency = 0.08
	closeButton.BorderSizePixel = 0
	closeButton.Font = UITheme.font.heading
	closeButton.Text = "X"
	closeButton.TextColor3 = palette.text
	closeButton.TextScaled = true
	closeButton.Parent = frame
	UITheme.corner(closeButton, 4)
	UITheme.stroke(closeButton, palette.gold, 1, 0.45)
	closeButton.Activated:Connect(function()
		setKeypadVisible(false)
	end)

	local subtitle = Instance.new("TextLabel")
	subtitle.Position = UDim2.fromOffset(20, 58)
	subtitle.Size = UDim2.new(1, -40, 0, 26)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = UITheme.font.fine
	subtitle.Text = "ENTER ACCESS CODE"
	subtitle.TextColor3 = palette.textMuted
	subtitle.TextScaled = true
	subtitle.Parent = frame

	local display = Instance.new("TextBox")
	display.Position = UDim2.fromOffset(35, 96)
	display.Size = UDim2.new(1, -70, 0, 56)
	display.BackgroundColor3 = Color3.fromRGB(15, 16, 17)
	display.BorderSizePixel = 0
	display.ClearTextOnFocus = false
	display.Font = UITheme.font.display
	display.PlaceholderText = "----"
	display.Text = ""
	display.TextColor3 = palette.gold
	display.TextScaled = true
	display.Parent = frame
	UITheme.corner(display, 4)
	UITheme.stroke(display, palette.stroke, 1, 0.35)
	codeBox = display
	display:GetPropertyChangedSignal("Text"):Connect(function()
		local filtered = string.sub(string.gsub(display.Text, "%D", ""), 1, 4)
		if filtered ~= display.Text then
			display.Text = filtered
		end
	end)
	display.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit()
		end
	end)

	local labels = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
	for index, digit in labels do
		local column = (index - 1) % 3
		local row = math.floor((index - 1) / 3)
		local button =
			makeButton(frame, digit, UDim2.fromOffset(35 + column * 86, 170 + row * 62), UDim2.fromOffset(76, 52))
		button.Activated:Connect(function()
			if #display.Text < 4 then
				display.Text ..= digit
			end
		end)
	end

	local clear = makeButton(frame, "CLEAR", UDim2.fromOffset(35, 356), UDim2.fromOffset(76, 48))
	clear.Activated:Connect(function()
		display.Text = ""
	end)
	local zero = makeButton(frame, "0", UDim2.fromOffset(121, 356), UDim2.fromOffset(76, 48))
	zero.Activated:Connect(function()
		if #display.Text < 4 then
			display.Text ..= "0"
		end
	end)
	local enter = makeButton(frame, "ENTER", UDim2.fromOffset(207, 356), UDim2.fromOffset(76, 48))
	enter.Activated:Connect(submit)

	-- SEATED ABOVE THE HOTBAR, not at a fixed offset from the bottom of the screen. The old -58px put
	-- the strip straight across the tool row it is reporting on. Derived from the hotbar's own config so
	-- the two cannot drift apart: bottom-anchored to the hotbar's top edge, less a small gap.
	local hotbar = Config.Feel.hotbar
	local hotbarTopScale = hotbar.desktopPosition.Y.Scale - hotbar.desktopSize.Y.Scale / 2

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, hotbarTopScale, -10)
	status.Size = UDim2.new(0.76, 0, 0, 34)
	status.BackgroundColor3 = palette.void
	status.BackgroundTransparency = 0.18
	status.BorderSizePixel = 0
	status.Font = UITheme.font.fine
	status.Text = ""
	status.TextColor3 = palette.gold
	status.TextScaled = true
	status.Visible = false
	status.Parent = root
	UITheme.corner(status, 4)
	UITheme.stroke(status, palette.gold, 1, 0.55)
	statusLabel = status

	root.Parent = player:WaitForChild("PlayerGui")
	gui = root
end

function DevTestRoomController.start()
	if gui ~= nil then
		return
	end
	build()
	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if input.KeyCode == Enum.KeyCode.Escape and panel ~= nil and panel.Visible then
			setKeypadVisible(false)
			return
		end
		-- REMOVE EVERY TEST ENEMY, from wherever you are standing.
		--
		-- F7 because it is the only free key that reads as a developer one: F8 is already this game's
		-- diagnostics overlay, so its neighbour carries the same "this is a tool, not a verb" meaning,
		-- and no player will ever reach for it by accident. F9 was rejected — Roblox gives that to the
		-- developer console, and a key that opens a console on top of the thing you are testing is
		-- worse than no key.
		--
		-- Guarded on the live session flag so it does nothing outside the laboratory; the server
		-- re-checks that anyway and is the actual authority. `_processed` is deliberately ignored for
		-- the same reason the F8 binding ignores it: first-person camera and input systems mark
		-- keyboard events as processed, and a dev key that stops working once you are in a body is
		-- not a dev key.
		if input.KeyCode == Config.DevTestRoom.hotkeys.clearEnemies and active then
			remote:FireServer("clear")
			return
		end
		-- HELD SUPER SPRINT. The key press and release are the whole protocol: the server holds the speed
		-- for exactly as long as it has been told the key is down, so nothing here has to repeat itself.
		if input.KeyCode == Config.DevTestRoom.hotkeys.superSprint and active then
			setSprinting(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
		-- NOT GUARDED ON `active`, unlike the press. A key-up is the only thing that ends the sprint, and
		-- the one moment it matters most is the moment the session ended under a held key — the server
		-- drops the speed on session close as well, and this is the other half of the same belt.
		if input.KeyCode == Config.DevTestRoom.hotkeys.superSprint then
			setSprinting(false)
		end
	end)
	-- A window that loses focus never delivers the key-up, which is the classic way a held key gets
	-- stuck on. Releasing here costs nothing when no key was down, because `setSprinting` is edge-only.
	UserInputService.WindowFocusReleased:Connect(function()
		setSprinting(false)
	end)
	remote.OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if kind == "keypad" then
			setKeypadVisible(true)
			return
		end
		if typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		local message = if typeof(data.message) == "string" then data.message else ""
		if kind == "state" then
			active = data.active == true
			setKeypadVisible(false)
			if not active then
				-- The session ended, possibly under a held key. The server has already dropped the speed;
				-- this is what stops the local edge flag from thinking the key is still down next visit.
				setSprinting(false)
			end
			-- THE CAVE TURNED DOWN, and back up on the way out. A trim rather than a write to the
			-- ambience multiplier, so the tester's own slider survives the visit untouched.
			AudioCues.setBusVolumeTrim("Ambience", if active then Config.DevTestRoom.session.ambienceTrim else 1)
			if active and message == "" then
				message = "TEST LAB  •  INFINITE WAX  •  USE THE PHYSICAL CONSOLE"
			end
			showStatus(message)
		elseif kind == "status" then
			showStatus(message)
		end
	end)
	remote:FireServer("sync")
end

return DevTestRoomController

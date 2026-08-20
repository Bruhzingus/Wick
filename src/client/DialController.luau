--!strict
-- The brightness dial (DESIGN §4) — the game's spine. Scroll wheel on desktop, a draggable
-- edge slider everywhere, gentle snap points from config. Sends the target rate; the server
-- clamps and owns the consequence. Reconciles to the server's value when not being dragged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local UITheme = require(script.Parent.UITheme)

local DialController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"

local targetRate = Config.Wax.initialBurnRate
-- THE FINGER THAT OWNS THE DIAL, or nil. Not a boolean, because a phone has more than one finger on
-- it: the drag used to be a flag, and every `InputChanged` that arrived while it was set moved the
-- dial — including the touch steering the movement thumbstick, whose Y is nowhere near the dial's.
-- Holding the InputObject means only the finger that started on the track can move it, and only its
-- own release can end it.
local dragInput: InputObject? = nil
local fill: Frame? = nil
local trackFrame: Frame? = nil
local currentSnapPoint: number? = nil
local feedbackGeneration = 0
local sendGeneration = 0
local sendScheduled = false
local lastSentAt = -math.huge
local lastLocalInputAt = -math.huge

local function snap(value: number): (number, number?)
	local dial = Config.Light.dial
	for _, point in dial.snapPoints do
		if math.abs(value - point) <= dial.snapRadius then
			return point, point
		end
	end
	return value, nil
end

local function snapFeedback()
	if not Config.Feel.dialSnap.enabled then
		return
	end
	AudioCues.play("DialSnap")
	local track = trackFrame
	if track == nil then
		return
	end
	feedbackGeneration += 1
	local generation = feedbackGeneration
	track.BackgroundColor3 = Config.Feel.dialSnap.flashColor
	task.delay(Config.Feel.dialSnap.flashSeconds, function()
		if generation == feedbackGeneration and track.Parent ~= nil then
			track.BackgroundColor3 = Config.Feel.dialSnap.trackColor
		end
	end)
end

local function inputEnabled(): boolean
	return player:GetAttribute(EXPEDITION_ATTRIBUTE) == true
end

local function updateFill()
	local currentFill = fill
	if currentFill ~= nil then
		local span = Config.Light.maxBurnRate - Config.Light.minBurnRate
		local t = if span > 0 then (targetRate - Config.Light.minBurnRate) / span else 0
		currentFill.Size = UDim2.fromScale(1, t)
	end
end

local function sendNow()
	if not inputEnabled() then
		return
	end
	lastSentAt = os.clock()
	Remotes.get("SetBurnRate"):FireServer(targetRate)
end

local function requestSend(force: boolean)
	if not inputEnabled() then
		return
	end

	local now = os.clock()
	local interval = Config.Feel.dialInput.sendIntervalSeconds
	if force or now - lastSentAt >= interval then
		sendGeneration += 1
		sendScheduled = false
		sendNow()
		return
	end
	if sendScheduled then
		return
	end

	sendScheduled = true
	sendGeneration += 1
	local generation = sendGeneration
	task.delay(math.max(interval - (now - lastSentAt), 0), function()
		if generation ~= sendGeneration or not sendScheduled then
			return
		end
		sendScheduled = false
		sendNow()
	end)
end

local function setRate(value: number, provideFeedback: boolean, fromLocalInput: boolean)
	local snappedRate, snapPoint = snap(math.clamp(value, Config.Light.minBurnRate, Config.Light.maxBurnRate))
	targetRate = snappedRate
	if provideFeedback and snapPoint ~= nil and snapPoint ~= currentSnapPoint then
		snapFeedback()
	end
	currentSnapPoint = snapPoint
	updateFill()
	if fromLocalInput then
		lastLocalInputAt = os.clock()
		requestSend(false)
	end
end

local function buildSlider(): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickDial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	-- A FAT INVISIBLE TARGET AROUND A THIN VISIBLE ONE. The dial is the game's spine, and on a phone it
	-- was a ribbon a thumb had to hit within a few pixels. Since mining became a tap on the open screen
	-- (client/TouchControls), a thumb that misses the ribbon no longer just fails — it swings a pickaxe.
	-- The pad is what catches the finger; the track is what the player reads. Sizing them separately is
	-- what lets the dial stay a thin warm line at the edge of a dark cave and still be easy to grab.
	local hitPad = Instance.new("Frame")
	hitPad.Name = "DialInput"
	hitPad.AnchorPoint = Vector2.new(1, 0.5)
	hitPad.Position = UDim2.fromScale(1, 0.5)
	hitPad.Size = UDim2.new(0, 52, 0.45, 0)
	hitPad.BackgroundTransparency = 1
	hitPad.BorderSizePixel = 0
	hitPad.Active = true
	hitPad.Parent = gui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -12, 0.5, 0)
	-- Full height of the pad, so the value a Y coordinate maps to is the same whichever of the two the
	-- finger landed on.
	track.Size = UDim2.new(0, 28, 1, 0)
	track.BackgroundColor3 = Config.Feel.dialSnap.trackColor
	track.BorderSizePixel = 0
	track.Parent = hitPad

	-- THE GAME'S SPINE, and on a phone it was a 28-pixel ribbon with nothing naming it. A desktop
	-- player has the scroll wheel and a legend line reading "WHEEL / RIGHT SLIDER = BRIGHTNESS"; a
	-- touch player has only this, and that legend no longer exists on touch (Config/Feel hotbar). So on
	-- touch the track widens to something a thumb can actually land on and says what it is.
	-- Set on its side, running up the left of the track, rather than as a line above it. The right edge
	-- of a phone screen is the most contested strip in the game — the MENU button sits at the top of it,
	-- Roblox's jump button at the bottom — and a horizontal caption would have to fit between them. A
	-- rotated label is 18 pixels wide and spends no vertical room at all, so it cannot be squeezed out.
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.new(0, -14, 0.5, 0)
	caption.Size = UDim2.fromOffset(140, 18)
	caption.Rotation = -90
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.font.heading
	caption.Text = "BRIGHTNESS"
	caption.TextColor3 = UITheme.palette.textMuted
	caption.TextSize = UITheme.textSize.micro
	caption.Visible = false
	caption.Parent = track
	UITheme.legible(caption, 0.75)

	local function applyPlatformLayout()
		local touch = UserInputService.TouchEnabled
			and (
				not UserInputService.KeyboardEnabled
				or UserInputService:GetLastInputType() == Enum.UserInputType.Touch
			)
		-- The pad reaches roughly twice as far in from the edge as the track it wraps, which is the
		-- difference between "aim for the ribbon" and "put your thumb near the right edge".
		hitPad.Size = if touch then UDim2.new(0, 96, 0.56, 0) else UDim2.new(0, 52, 0.45, 0)
		track.Size = if touch then UDim2.new(0, 46, 1, 0) else UDim2.new(0, 28, 1, 0)
		caption.Visible = touch
	end
	applyPlatformLayout()
	UserInputService.LastInputTypeChanged:Connect(applyPlatformLayout)

	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "Fill"
	fillFrame.AnchorPoint = Vector2.new(0, 1)
	fillFrame.Position = UDim2.fromScale(0, 1)
	fillFrame.Size = UDim2.fromScale(1, 0.4)
	fillFrame.BackgroundColor3 = Color3.fromRGB(255, 180, 80)
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = track

	-- Snap-point ticks so the dial's landmarks are visible.
	for _, point in Config.Light.dial.snapPoints do
		local span = Config.Light.maxBurnRate - Config.Light.minBurnRate
		local t = if span > 0 then (point - Config.Light.minBurnRate) / span else 0
		local tickMark = Instance.new("Frame")
		tickMark.AnchorPoint = Vector2.new(0.5, 0.5)
		tickMark.Position = UDim2.fromScale(0.5, 1 - t)
		tickMark.Size = UDim2.new(1, 6, 0, 2)
		tickMark.BackgroundColor3 = Color3.fromRGB(90, 85, 95)
		tickMark.BorderSizePixel = 0
		tickMark.Parent = track
	end

	local function rateFromY(y: number)
		local top = track.AbsolutePosition.Y
		local heightPixels = track.AbsoluteSize.Y
		local t = 1 - math.clamp((y - top) / math.max(heightPixels, 1), 0, 1)
		local span = Config.Light.maxBurnRate - Config.Light.minBurnRate
		setRate(Config.Light.minBurnRate + t * span, true, true)
	end

	hitPad.InputBegan:Connect(function(input: InputObject)
		if not inputEnabled() or dragInput ~= nil then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragInput = input
			rateFromY(input.Position.Y)
		end
	end)

	-- WHICH MOVEMENTS BELONG TO THIS DRAG. A touch is matched by identity: the engine hands the same
	-- InputObject to every event of one finger's life, so a second finger walking the character has a
	-- different object and cannot move the dial. A mouse drag is the one case that cannot be matched
	-- that way — the button is held as one object while the pointer moves as another — so it is matched
	-- by type, which is unambiguous because a mouse has exactly one pointer.
	local function ownsMovement(input: InputObject): boolean
		local owner = dragInput
		if owner == nil then
			return false
		end
		if owner.UserInputType == Enum.UserInputType.Touch then
			return input == owner
		end
		return input.UserInputType == Enum.UserInputType.MouseMovement
	end

	local function endDrag(input: InputObject)
		local owner = dragInput
		if owner == nil then
			return
		end
		local ownsRelease = if owner.UserInputType == Enum.UserInputType.Touch
			then input == owner
			else input.UserInputType == owner.UserInputType
		if not ownsRelease then
			return
		end
		dragInput = nil
		requestSend(true)
	end
	-- Only the global signal, never the pad's own. `GuiObject.InputEnded` also fires when a finger
	-- SLIDES OFF the object it started on, and a dial is dragged along its length by a thumb that does
	-- not travel in a straight line — so listening there let a wobble end the drag halfway. A release
	-- is a release wherever the finger happens to be by then.
	UserInputService.InputEnded:Connect(endDrag)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if ownsMovement(input) then
			rateFromY(input.Position.Y)
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	trackFrame = track
	return fillFrame
end

function DialController.start()
	fill = buildSlider()
	setRate(targetRate, false, false)

	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if processed or not inputEnabled() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			setRate(targetRate + input.Position.Z * Config.Light.dial.scrollStep, true, true)
		end
	end)

	-- Server is authoritative: while not dragging, mirror whatever it settled on (sacrifice caps).
	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		if
			dragInput ~= nil
			or sendScheduled
			or os.clock() - lastLocalInputAt < Config.Feel.dialInput.serverReconcileDelaySeconds
		then
			return
		end
		for _, entry in entries do
			if entry.playerId == player.UserId and math.abs(entry.burnRate - targetRate) > 0.005 then
				targetRate = entry.burnRate
				currentSnapPoint = nil
				updateFill()
			end
		end
	end)

	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if inputEnabled() then
			requestSend(true)
		else
			dragInput = nil
			sendGeneration += 1
			sendScheduled = false
		end
	end)
end

return DialController

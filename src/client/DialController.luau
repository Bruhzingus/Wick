--!strict
-- The brightness dial (DESIGN §4) — the game's spine. Scroll wheel on desktop, a draggable
-- edge slider everywhere, gentle snap points from config. Sends the target rate; the server
-- clamps and owns the consequence. Reconciles to the server's value when not being dragged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local DialController = {}

local player = Players.LocalPlayer

local targetRate = Config.Wax.initialBurnRate
local dragging = false
local fill: Frame? = nil

local function snap(value: number): number
	local dial = Config.Light.dial
	for _, point in dial.snapPoints do
		if math.abs(value - point) <= dial.snapRadius then
			return point
		end
	end
	return value
end

local function send()
	Remotes.get("SetBurnRate"):FireServer(targetRate)
end

local function setRate(value: number)
	targetRate = snap(math.clamp(value, Config.Light.minBurnRate, Config.Light.maxBurnRate))
	local currentFill = fill
	if currentFill ~= nil then
		local span = Config.Light.maxBurnRate - Config.Light.minBurnRate
		local t = if span > 0 then (targetRate - Config.Light.minBurnRate) / span else 0
		currentFill.Size = UDim2.fromScale(1, t)
	end
	send()
end

local function buildSlider(): Frame
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickDial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -12, 0.5, 0)
	track.Size = UDim2.new(0, 28, 0.45, 0)
	track.BackgroundColor3 = Color3.fromRGB(30, 28, 32)
	track.BorderSizePixel = 0
	track.Active = true
	track.Parent = gui

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
		setRate(Config.Light.minBurnRate + t * span)
	end

	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			rateFromY(input.Position.Y)
		end
	end)
	track.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			rateFromY(input.Position.Y)
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	return fillFrame
end

function DialController.start()
	fill = buildSlider()
	setRate(targetRate)

	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			setRate(targetRate + input.Position.Z * Config.Light.dial.scrollStep)
		end
	end)

	-- Server is authoritative: while not dragging, mirror whatever it settled on (sacrifice caps).
	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		if dragging then
			return
		end
		for _, entry in entries do
			if entry.playerId == player.UserId and math.abs(entry.burnRate - targetRate) > 0.005 then
				targetRate = entry.burnRate
				local currentFill = fill
				if currentFill ~= nil then
					local span = Config.Light.maxBurnRate - Config.Light.minBurnRate
					local t = if span > 0 then (targetRate - Config.Light.minBurnRate) / span else 0
					currentFill.Size = UDim2.fromScale(1, t)
				end
			end
		end
	end)
end

return DialController

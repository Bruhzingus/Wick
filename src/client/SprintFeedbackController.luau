--!strict
-- Local-only run strain: restrained FOV, peripheral urgency, heat shimmer, and unstable
-- first-person motion. It renders authoritative movement and never changes speed, wax, or game state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local SprintFeedbackController = {}

local player = Players.LocalPlayer
local cfg = Config.Feel.sprintFeedback
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local RENDER_STEP_NAME = "WickSprintFeedback"

type Streak = {
	frame: Frame,
	baseY: number,
	phase: number,
	side: number,
}

local intensity = 0
local activeAttributeValue = false
local edgeFrames: { Frame } = {}
local streaks: { Streak } = {}

local function gradient(parent: GuiObject, rotation: number, middleTransparency: number?)
	local value = middleTransparency
	local uiGradient = Instance.new("UIGradient")
	uiGradient.Rotation = rotation
	if value == nil then
		uiGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
	else
		uiGradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, value),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	uiGradient.Parent = parent
end

local function createEdge(gui: ScreenGui, name: string, position: UDim2, size: UDim2, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = cfg.vignetteColor
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	gradient(frame, rotation)
	table.insert(edgeFrames, frame)
	return frame
end

local function buildGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickSprintStrain"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6

	local width = cfg.vignetteWidthScale
	createEdge(gui, "LeftVignette", UDim2.fromScale(0, 0), UDim2.fromScale(width, 1), 0)
	local right = createEdge(gui, "RightVignette", UDim2.fromScale(1, 0), UDim2.fromScale(width, 1), 180)
	right.AnchorPoint = Vector2.new(1, 0)
	createEdge(gui, "TopVignette", UDim2.fromScale(0, 0), UDim2.fromScale(1, width), 90)
	local bottom = createEdge(gui, "BottomVignette", UDim2.fromScale(0, 1), UDim2.fromScale(1, width), 270)
	bottom.AnchorPoint = Vector2.new(0, 1)

	for sideIndex = 1, 2 do
		local side = if sideIndex == 1 then -1 else 1
		for index = 1, cfg.streakCountPerSide do
			local frame = Instance.new("Frame")
			frame.Name = if side < 0 then "LeftStreak" else "RightStreak"
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Size = UDim2.new(0, cfg.streakWidthPixels, cfg.streakLengthScale, 0)
			frame.BackgroundColor3 = cfg.streakColor
			frame.BackgroundTransparency = 1
			frame.BorderSizePixel = 0
			frame.Rotation = cfg.streakAngleDegrees * side
			frame.Parent = gui
			gradient(frame, 90, 0.2)

			local baseY = index / (cfg.streakCountPerSide + 1)
			table.insert(streaks, {
				frame = frame,
				baseY = baseY,
				phase = index / cfg.streakCountPerSide * math.pi * 2 + sideIndex,
				side = side,
			})
		end
	end

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function shouldRender(): boolean
	if not cfg.enabled or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
		return false
	end
	local character = player.Character
	if character == nil or character:FindFirstChild("Body") == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.MoveDirection.Magnitude <= cfg.movementThreshold then
		return false
	end
	-- WalkSpeed is assigned by the authoritative MovementService and replicated with the Humanoid.
	return humanoid.WalkSpeed >= Config.Movement.walkSpeed + cfg.acceptedSpeedMargin
end

local function setActiveAttribute(active: boolean)
	if active == activeAttributeValue then
		return
	end
	activeAttributeValue = active
	player:SetAttribute(cfg.activeAttribute, active)
end

function SprintFeedbackController.start()
	local gui = buildGui()
	player:SetAttribute(cfg.activeAttribute, false)

	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 3, function(dt: number)
		local target = if shouldRender() then 1 else 0
		local step = if cfg.transitionSeconds > 0 then dt / cfg.transitionSeconds else 1
		if intensity < target then
			intensity = math.min(intensity + step, target)
		else
			intensity = math.max(intensity - step, target)
		end
		setActiveAttribute(target > 0)

		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			camera.FieldOfView = cfg.normalFov + (cfg.sprintFov - cfg.normalFov) * intensity
		end

		gui.Enabled = intensity > 0
		if intensity <= 0 then
			return
		end

		local now = os.clock()
		local pulse = math.sin(now * cfg.vignettePulseFrequencyHz * math.pi * 2)
		local opacity = math.clamp(cfg.vignetteMaxOpacity + pulse * cfg.vignettePulseOpacity, 0, 1) * intensity
		local shimmer = math.sin(now * cfg.heatFrequencyHz * math.pi * 2) * cfg.heatShimmerPixels * intensity
		for index, frame in edgeFrames do
			frame.BackgroundTransparency = 1 - opacity
			if index <= 2 then
				frame.Position = UDim2.new(frame.Position.X.Scale, shimmer * (if index == 1 then 1 else -1), 0, 0)
			end
		end

		for _, streak in streaks do
			local wave = (math.sin(now * cfg.heatFrequencyHz + streak.phase) + 1) / 2
			local x = if streak.side < 0 then cfg.streakInsetScale else 1 - cfg.streakInsetScale
			local y = streak.baseY + wave * cfg.streakTravelScale
			streak.frame.Position = UDim2.fromScale(x, y)
			streak.frame.BackgroundTransparency = 1 - cfg.streakMaxOpacity * wave * intensity
		end

		if camera ~= nil then
			local phase = now * cfg.cameraFrequencyHz * math.pi * 2
			local sway = math.sin(phase) * cfg.cameraSwayStuds * intensity
			local bob = math.sin(phase * 1.7) * cfg.cameraBobStuds * intensity
			local roll = math.rad(math.sin(phase * 0.7) * cfg.cameraRollDegrees * intensity)
			camera.CFrame = camera.CFrame * CFrame.new(sway, bob, 0) * CFrame.Angles(0, 0, roll)
		end
	end)
end

return SprintFeedbackController

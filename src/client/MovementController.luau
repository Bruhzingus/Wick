--!strict
-- Movement input: sprint (hold), dodge, slide — keyboard and touch buttons via
-- ContextActionService. Requests go to the server; only approved dodges apply velocity here.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local MovementController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local ACTION_SPRINT = "WickSprint"
local ACTION_DODGE = "WickDodge"
local ACTION_SLIDE = "WickSlide"

local controlsBound = false
local sprintHeld = false

local function moveDirection(): Vector3
	local character = player.Character
	if character == nil then
		return Vector3.zero
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return Vector3.zero
	end
	if humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root.CFrame.LookVector
	end
	return Vector3.zero
end

local function onSprint(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		sprintHeld = true
		Remotes.get("MovementAction"):FireServer("SprintStart")
		AudioCues.play(Config.Feel.controls.movement.Sprint.audioCue)
	elseif inputState == Enum.UserInputState.End then
		sprintHeld = false
		Remotes.get("MovementAction"):FireServer("SprintEnd")
	end
	return Enum.ContextActionResult.Pass
end

local function onDodge(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		Remotes.get("MovementAction"):FireServer("Dodge", moveDirection())
	end
	return Enum.ContextActionResult.Sink
end

local function onSlide(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		Remotes.get("MovementAction"):FireServer("Slide")
		AudioCues.play(Config.Feel.controls.movement.Slide.audioCue)
	end
	return Enum.ContextActionResult.Sink
end

local function bindControls()
	if controlsBound then
		return
	end
	controlsBound = true
	local controls = Config.Feel.controls.movement
	ContextActionService:BindAction(ACTION_SPRINT, onSprint, true, controls.Sprint.keyCode)
	ContextActionService:BindAction(ACTION_DODGE, onDodge, true, controls.Dodge.keyCode)
	ContextActionService:BindAction(ACTION_SLIDE, onSlide, true, controls.Slide.keyCode)
	if UserInputService.TouchEnabled then
		ContextActionService:SetTitle(ACTION_SPRINT, controls.Sprint.displayName)
		ContextActionService:SetTitle(ACTION_DODGE, controls.Dodge.displayName)
		ContextActionService:SetTitle(ACTION_SLIDE, controls.Slide.displayName)
		ContextActionService:SetPosition(ACTION_SPRINT, controls.Sprint.touchPosition)
		ContextActionService:SetPosition(ACTION_DODGE, controls.Dodge.touchPosition)
		ContextActionService:SetPosition(ACTION_SLIDE, controls.Slide.touchPosition)
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	if sprintHeld then
		sprintHeld = false
		Remotes.get("MovementAction"):FireServer("SprintEnd")
	end
	controlsBound = false
	ContextActionService:UnbindAction(ACTION_SPRINT)
	ContextActionService:UnbindAction(ACTION_DODGE)
	ContextActionService:UnbindAction(ACTION_SLIDE)
end

local function refreshControls()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		bindControls()
	else
		unbindControls()
	end
end

function MovementController.start()
	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)

	-- Server-approved dodge: a brief velocity burst in the approved direction, then release.
	Remotes.get("MovementApproved").OnClientEvent
		:Connect(function(action: string, direction: Vector3, speed: number, duration: number)
			if action ~= "Dodge" or not controlsBound then
				return
			end
			AudioCues.play(Config.Feel.controls.movement.Dodge.audioCue)
			local character = player.Character
			if character == nil then
				return
			end
			local root = character:FindFirstChild("HumanoidRootPart")
			if root == nil or not root:IsA("BasePart") then
				return
			end
			root.AssemblyLinearVelocity = direction * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			task.delay(duration, function()
				local velocity = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
			end)
		end)
end

return MovementController

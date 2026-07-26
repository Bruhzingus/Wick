--!strict
-- Movement input: sprint (hold), with keyboard and touch bindings.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local HotbarController = require(script.Parent.HotbarController)

local MovementController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local ACTION_SPRINT = "WickSprint"

local controlsBound = false
local sprintHeld = false

local function setSprintHeld(held: boolean)
	sprintHeld = held
	player:SetAttribute(Config.Feel.sprintFeedback.heldAttribute, held)
end

local function onSprint(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		setSprintHeld(true)
		Remotes.get("MovementAction"):FireServer("SprintStart")
		AudioCues.play(Config.Feel.controls.movement.Sprint.audioCue)
		HotbarController.pulse("Sprint")
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		setSprintHeld(false)
		Remotes.get("MovementAction"):FireServer("SprintEnd")
	end
	return Enum.ContextActionResult.Pass
end

local function bindControls()
	if controlsBound then
		return
	end
	controlsBound = true
	local controls = Config.Feel.controls.movement
	ContextActionService:BindAction(ACTION_SPRINT, onSprint, true, controls.Sprint.keyCode)
	if UserInputService.TouchEnabled then
		ContextActionService:SetTitle(ACTION_SPRINT, controls.Sprint.displayName)
		ContextActionService:SetPosition(ACTION_SPRINT, controls.Sprint.touchPosition)
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	if sprintHeld then
		setSprintHeld(false)
		Remotes.get("MovementAction"):FireServer("SprintEnd")
	end
	controlsBound = false
	ContextActionService:UnbindAction(ACTION_SPRINT)
end

local function refreshControls()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		bindControls()
	else
		unbindControls()
	end
end

function MovementController.start()
	setSprintHeld(false)
	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)
end

return MovementController

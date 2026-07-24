--!strict
-- Tool input: keys 1-4 and touch buttons, one binding per ToolDef row. Cast sends an aim point
-- from the camera ray; everything else is just the tool id. The server validates all of it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local ToolController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local controlsBound = false

local function aimPoint(castRange: number): Vector3
	local camera = Workspace.CurrentCamera
	local origin = Vector3.zero
	local character = player.Character
	if character ~= nil then
		local root = character.PrimaryPart
		if root ~= nil then
			origin = root.Position
		end
	end
	if camera == nil then
		return origin
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local direction = if flat.Magnitude > 0.05 then flat.Unit else Vector3.xAxis
	return origin + direction * castRange
end

local function use(toolId: Types.ToolId)
	local def = Config.Tools[toolId]
	if def.castRange ~= nil then
		Remotes.get("ToolUse"):FireServer(toolId, aimPoint(def.castRange))
	else
		Remotes.get("ToolUse"):FireServer(toolId)
	end
end

local function bindControls()
	if controlsBound then
		return
	end
	controlsBound = true
	for _, control in Config.Feel.controls.tools do
		local toolId = control.toolId
		local actionName = "WickTool" .. toolId
		ContextActionService:BindAction(actionName, function(_name: string, inputState: Enum.UserInputState)
			if controlsBound and inputState == Enum.UserInputState.Begin then
				use(toolId)
				AudioCues.play(control.audioCue)
			end
			return Enum.ContextActionResult.Sink
		end, true, control.keyCode)
		if UserInputService.TouchEnabled then
			ContextActionService:SetTitle(actionName, Config.Tools[toolId].displayName)
			ContextActionService:SetPosition(actionName, control.touchPosition)
		end
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	controlsBound = false
	for _, control in Config.Feel.controls.tools do
		ContextActionService:UnbindAction("WickTool" .. control.toolId)
	end
end

local function refreshControls()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		bindControls()
	else
		unbindControls()
	end
end

function ToolController.start()
	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)
end

return ToolController

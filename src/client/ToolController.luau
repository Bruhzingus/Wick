--!strict
-- Tool input: keys 1-4 and touch buttons, one binding per ToolDef row. Decoy proposes only the
-- camera's horizontal direction; the server traces the throw and owns the landing.

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
local audioByTool: { [string]: string } = {}

local function aimPoint(throwRange: number): Vector3
	local camera = Workspace.CurrentCamera
	local fallback = Vector3.zero
	local fallbackDirection = Vector3.xAxis
	local character = player.Character
	if character ~= nil then
		local root = character.PrimaryPart
		if root ~= nil then
			fallback = root.Position
			local rootHorizontal = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if rootHorizontal.Magnitude > 1e-3 then
				fallbackDirection = rootHorizontal.Unit
			end
		end
	end
	if camera == nil then
		return fallback + fallbackDirection * throwRange
	end
	local look = camera.CFrame.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	local direction = if horizontal.Magnitude > 1e-3 then horizontal.Unit else fallbackDirection
	return fallback + direction * throwRange
end

local function use(toolId: Types.ToolId)
	local def = Config.Tools[toolId]
	if def.throwRange ~= nil then
		Remotes.get("ToolUse"):FireServer(toolId, aimPoint(def.throwRange))
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
	for _, control in Config.Feel.controls.tools do
		audioByTool[control.toolId] = control.audioCue
	end
	Remotes.get("ActionFeedback").OnClientEvent:Connect(function(actionId: unknown, accepted: unknown)
		if typeof(actionId) ~= "string" or accepted ~= true or not controlsBound then
			return
		end
		local cue = audioByTool[actionId]
		if cue ~= nil then
			AudioCues.play(cue)
		end
	end)
	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)
end

return ToolController

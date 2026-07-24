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

local ToolController = {}

local player = Players.LocalPlayer

local TOOL_KEYS: { [Types.ToolId]: Enum.KeyCode } = {
	Snuff = Enum.KeyCode.One,
	Flare = Enum.KeyCode.Two,
	Cast = Enum.KeyCode.Three,
	Cup = Enum.KeyCode.Four,
}

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

function ToolController.start()
	local slot = 0
	for _, toolId in { "Snuff" :: Types.ToolId, "Flare" :: Types.ToolId, "Cast" :: Types.ToolId, "Cup" :: Types.ToolId } do
		slot += 1
		local actionName = "WickTool" .. toolId
		ContextActionService:BindAction(actionName, function(_name: string, inputState: Enum.UserInputState)
			if inputState == Enum.UserInputState.Begin then
				use(toolId)
			end
			return Enum.ContextActionResult.Sink
		end, true, TOOL_KEYS[toolId])
		if UserInputService.TouchEnabled then
			ContextActionService:SetTitle(actionName, Config.Tools[toolId].displayName)
			ContextActionService:SetPosition(actionName, UDim2.new(0, 10 + (slot - 1) * 64, 1, -140))
		end
	end
end

return ToolController

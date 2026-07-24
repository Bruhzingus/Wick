--!strict
-- First-person from the flame, with your own body visible when you look down (DESIGN §21 Q1:
-- watching yourself shrink is the emotional hook — never hide the body).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CameraController = {}

local player = Players.LocalPlayer

function CameraController.start()
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

	RunService.RenderStepped:Connect(function()
		local character = player.Character
		if character == nil then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local body = character:FindFirstChild("Body")
		if humanoid ~= nil and body ~= nil and body:IsA("BasePart") then
			-- Eye rides ABOVE the body top (cameraLift) so your own cap and flame never fill the
			-- view; body height is Size.X (cylinder long axis).
			local height = body.Size.X
			humanoid.CameraOffset =
				Vector3.new(0, height + Config.Character.cameraLift - Config.Character.hipHeight - 1, 0)
		end
		-- Default camera scripts fade character parts at close zoom; override every frame:
		-- body and rim stay visible (the shrink is the point), flame and wick are hidden
		-- locally — they sit at the eye and would fill the screen. Everyone else still sees them.
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if part.Name == "Flame" or part.Name == "Wick" then 1 else 0
			end
		end
	end)
end

return CameraController

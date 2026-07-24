--!strict
-- First-person from the flame, with your own body visible when you look down (DESIGN §21 Q1:
-- watching yourself shrink is the emotional hook — never hide the body).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local CameraController = {}

local player = Players.LocalPlayer

local function bindToCurrentCharacter()
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

	local character = player.Character
	local camera = Workspace.CurrentCamera
	if character == nil or camera == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	-- CharacterService replaces the entire candle/wisp model between death and restart. Roblox
	-- can leave CameraSubject pointing at the destroyed humanoid even though CameraMode remains
	-- locked. Explicitly hand the new humanoid to the default camera before the next frame.
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
end

function CameraController.start()
	bindToCurrentCharacter()
	player.CharacterAdded:Connect(function()
		bindToCurrentCharacter()
		-- PlayerModule also reacts to CharacterAdded. Reapply after its event callbacks finish so
		-- callback ordering cannot restore the dead character as the subject.
		task.defer(bindToCurrentCharacter)
	end)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		task.defer(bindToCurrentCharacter)
	end)
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string)
		if kind == "floor" then
			-- The server sends floor only after the replacement candle is assigned to Character.
			bindToCurrentCharacter()
		end
	end)

	RunService:BindToRenderStep("WickCamera", Enum.RenderPriority.Camera.Value + 2, function()
		local character = player.Character
		if character == nil then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local camera = Workspace.CurrentCamera
		if
			humanoid ~= nil
			and camera ~= nil
			and (camera.CameraSubject ~= humanoid or camera.CameraType ~= Enum.CameraType.Custom)
		then
			-- Final guard for restart races: the active character always owns the camera.
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
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

--!strict
-- First-person from the flame, with your own body visible when you look down (DESIGN §21 Q1:
-- watching yourself shrink is the emotional hook — never hide the body).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local CameraController = {}

local player = Players.LocalPlayer
local elevatorOffset = Vector3.zero

-- Keyed off the body itself, NOT off WickInExpedition. CharacterService swaps the committed rider
-- to a cosmetic candle as the elevator begins, so the same signal enters first person for both the
-- descent and the authoritative cave body.
local function hasRunBody(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute(LobbyVisualProtocol.attributes.runBody) == true
end

-- Locked first-person from elevator commitment onward (DESIGN §21 Q1: the view from the flame),
-- but free third-person while choosing a cave in the hub.
local function applyCameraMode()
	if hasRunBody() then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 4
		player.CameraMaxZoomDistance = 24
	end
end

local function bindToCurrentCharacter()
	applyCameraMode()

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

local function cameraOffsetFor(character: Model): Vector3
	local body = character:FindFirstChild("Body")
	if body == nil or not body:IsA("BasePart") then
		return elevatorOffset
	end
	-- Eye rides ABOVE the body top (cameraLift) so your own cap and flame never fill the view;
	-- body height is Size.X (cylinder long axis).
	local height = body.Size.X
	return Vector3.new(0, height + Config.Character.cameraLift - Config.Character.hipHeight - 1, 0) + elevatorOffset
end

-- ElevatorController updates this before Roblox's camera step. Keeping the base first-person
-- candle offset and ride vibration in one writer prevents competing Humanoid.CameraOffset writes.
function CameraController.setElevatorOffset(offset: Vector3)
	elevatorOffset = offset
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if character ~= nil and humanoid ~= nil then
		humanoid.CameraOffset = cameraOffsetFor(character)
	end
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
		if humanoid ~= nil then
			humanoid.CameraOffset = cameraOffsetFor(character)
		end
		-- Default camera scripts fade character parts at close zoom; override every frame:
		-- body and rim stay visible (the shrink is the point), flame and wick are hidden
		-- locally — they sit at the eye and would fill the screen. Everyone else still sees them.
		-- Run bodies only: the lobby's Roblox avatar is viewed in third person and should fade exactly
		-- the way Roblox's own camera intends.
		if character:GetAttribute(LobbyVisualProtocol.attributes.runBody) ~= true then
			return
		end
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = if part.Name == "Flame" or part.Name == "Wick" then 1 else 0
			end
		end
	end)
end

return CameraController

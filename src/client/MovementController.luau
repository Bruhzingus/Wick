--!strict
-- Movement input: sprint (hold), dodge, slide — keyboard and touch buttons via
-- ContextActionService. Requests go to the server; only approved dodges apply velocity here.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local MovementController = {}

local player = Players.LocalPlayer

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
		Remotes.get("MovementAction"):FireServer("SprintStart")
	elseif inputState == Enum.UserInputState.End then
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
	end
	return Enum.ContextActionResult.Sink
end

function MovementController.start()
	ContextActionService:BindAction("WickSprint", onSprint, true, Enum.KeyCode.LeftShift)
	ContextActionService:BindAction("WickDodge", onDodge, true, Enum.KeyCode.Q)
	ContextActionService:BindAction("WickSlide", onSlide, true, Enum.KeyCode.C)
	if UserInputService.TouchEnabled then
		ContextActionService:SetTitle("WickSprint", "RUN")
		ContextActionService:SetTitle("WickDodge", "DODGE")
		ContextActionService:SetTitle("WickSlide", "SLIDE")
		ContextActionService:SetPosition("WickSprint", UDim2.new(1, -70, 0, 10))
		ContextActionService:SetPosition("WickDodge", UDim2.new(1, -140, 0, 60))
		ContextActionService:SetPosition("WickSlide", UDim2.new(1, -70, 0, 110))
	end

	-- Server-approved dodge: a brief velocity burst in the approved direction, then release.
	Remotes.get("MovementApproved").OnClientEvent
		:Connect(function(action: string, direction: Vector3, speed: number, duration: number)
			if action ~= "Dodge" then
				return
			end
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

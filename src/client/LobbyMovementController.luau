--!strict
-- Sprint for the open hub, and only the open hub. Its avatar (and the anchored cosmetic candle
-- that replaces it after elevator commitment) has no run rig behind it, so this costs no wax, is
-- never checked by MovementSanityService, and
-- deliberately does not go through the MovementAction remote — there is nothing authoritative to
-- decide. It exists because The Landing is a big room and crossing it at walking pace is tedious.
--
-- The run's own sprint (MovementController) binds on WickInExpedition being true; this binds on it
-- being false, so exactly one of them owns the sprint key at any moment.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local LobbyMovementController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local ACTION_NAME = "WickLobbySprint"

local bound = false
local sprinting = false

local function humanoid(): Humanoid?
	local character = player.Character
	return if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
end

local function applySpeed()
	local target = humanoid()
	if target ~= nil then
		target.WalkSpeed = if sprinting then Config.LobbyRoom.sprintSpeed else Config.LobbyRoom.walkSpeed
	end
end

local function onSprint(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		sprinting = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		sprinting = false
	end
	applySpeed()
	return Enum.ContextActionResult.Pass
end

local function bind()
	if bound then
		return
	end
	bound = true
	local sprint = Config.Feel.controls.movement.Sprint
	ContextActionService:BindAction(ACTION_NAME, onSprint, true, sprint.keyCode)
	ContextActionService:SetTitle(ACTION_NAME, sprint.displayName)
	ContextActionService:SetPosition(ACTION_NAME, sprint.touchPosition)
	applySpeed()
end

local function unbind()
	if not bound then
		return
	end
	bound = false
	sprinting = false
	ContextActionService:UnbindAction(ACTION_NAME)
end

local function refresh()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		unbind()
	else
		bind()
	end
end

function LobbyMovementController.start()
	refresh()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refresh)
	-- Each new lobby body arrives at the Humanoid's default WalkSpeed; reapply on every respawn.
	player.CharacterAdded:Connect(function()
		task.defer(function()
			if not bound then
				return
			end
			sprinting = false
			applySpeed()
		end)
	end)
end

return LobbyMovementController

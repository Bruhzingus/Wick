--!strict
-- Central cursor ownership for first-person play. Any interactive UI claims a named release;
-- when the last claim closes, first-person mouse capture resumes for the expedition.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CursorController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local releases: { [string]: boolean } = {}
local coreMenuOpen = false

local function cursorShouldBeFree(): boolean
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
		return true
	end
	if coreMenuOpen then
		return true
	end
	return next(releases) ~= nil
end

local function apply()
	-- The default first-person camera writes MouseBehavior during camera updates. Applying after
	-- that step makes menu buttons reliably clickable without changing the game's camera mode.
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = if cursorShouldBeFree()
		then Enum.MouseBehavior.Default
		else Enum.MouseBehavior.LockCenter
end

function CursorController.setReleased(owner: string, released: boolean)
	if released then
		releases[owner] = true
	else
		releases[owner] = nil
	end
	apply()
end

function CursorController.isReleased(): boolean
	return cursorShouldBeFree()
end

function CursorController.start()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(apply)
	GuiService.MenuOpened:Connect(function()
		coreMenuOpen = true
		apply()
	end)
	GuiService.MenuClosed:Connect(function()
		coreMenuOpen = false
		apply()
	end)
	RunService:BindToRenderStep("WickCursor", Enum.RenderPriority.Camera.Value + 1, apply)
	apply()
end

return CursorController

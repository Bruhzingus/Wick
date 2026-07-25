--!strict
-- Central cursor ownership for first-person play. Any interactive UI claims a named release;
-- when the last claim closes, first-person mouse capture resumes for the expedition and the OS
-- arrow is swapped for a small, subtle dot reticle.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UITheme = require(script.Parent.UITheme)

local CursorController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local releases: { [string]: boolean } = {}
local coreMenuOpen = false
local crosshair: Frame? = nil

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
	local free = cursorShouldBeFree()
	-- The default first-person camera writes MouseBehavior during camera updates. Applying after
	-- that step makes menu buttons reliably clickable without changing the game's camera mode.
	-- The OS arrow is only meaningful while the cursor is free to click UI; locked first-person
	-- play shows the dedicated dot reticle below instead.
	UserInputService.MouseIconEnabled = free
	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	if crosshair ~= nil then
		crosshair.Visible = not free
	end
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

-- A small, subtle dot reticle in place of the OS arrow during locked first-person play. Deliberately
-- tiny and low-contrast — DESIGN §16 wants the flame's light circle to be the only strong visual
-- anchor on screen, not a HUD crosshair.
local function buildCrosshair()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickCrosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.BackgroundColor3 = UITheme.palette.text
	dot.BackgroundTransparency = 0.35
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.Parent = gui
	UITheme.corner(dot, 2)
	UITheme.stroke(dot, Color3.new(0, 0, 0), 1, 0.5)

	crosshair = dot
end

function CursorController.start()
	buildCrosshair()
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

--!strict
-- THE GHOST'S EYES (server/SpectatorService, Config/Spectator). Draws the footfall trail a dead player
-- is allowed to see, shows who they are following, and owns the one key they still have.
--
-- IT DECIDES NOTHING. Which teammate is next in the cycle, where a ghost is put when it follows, which
-- floor's footfalls it may see, and whether it is a ghost at all are all server answers. This file
-- turns the last packet into marks on the floor and a line of text.
--
-- WHY THE MARKS ARE PARTS IN THE WORLD rather than a billboard, an arrow or a screen-space overlay:
-- geometry has to be able to hide them. A ghost following a path around a corner should lose sight of
-- it exactly as it would lose sight of a candle, so the trail can never become an x-ray of the cave the
-- living are still trying to survive. Nothing here emits light for the same reason — a mark that lit
-- the floor would hand the party a lantern every time somebody died.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local SpectatorRules = require(ReplicatedStorage.Shared.Logic.SpectatorRules)
local Types = require(ReplicatedStorage.Shared.Types)
local UITheme = require(script.Parent.UITheme)

local SpectatorController = {}

local player = Players.LocalPlayer
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's height runs along X; this lays it flat

type Mark = {
	part: BasePart,
	sample: Types.SpectatorSample,
	baseWidth: number,
}

local marks: { [number]: Mark } = {}
local markFolder: Folder? = nil
local statusLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local panel: Frame? = nil
local followButton: TextButton? = nil
local spectating = false
local fadeAccumulator = 0

local function ensureFolder(): Folder
	local existing = markFolder
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "WickGhostTrail"
	created.Parent = Workspace
	markFolder = created
	return created
end

local function clearMarks()
	for seq, mark in marks do
		mark.part:Destroy()
		marks[seq] = nil
	end
	local folder = markFolder
	if folder ~= nil then
		folder:Destroy()
		markFolder = nil
	end
end

local function colorFor(ownerId: number): Color3
	local colors = Config.Spectator.trail.ownerColors
	local index = SpectatorRules.colorIndexFor(ownerId, #colors)
	return colors[index] or Color3.fromRGB(200, 200, 200)
end

local function addMark(sample: Types.SpectatorSample)
	if marks[sample.seq] ~= nil then
		return
	end
	local trail = Config.Spectator.trail
	local part = Instance.new("Part")
	part.Name = "WickFootfall"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(trail.markerThickness, trail.markerWidth, trail.markerWidth)
	part.CFrame = CFrame.new(sample.position + Vector3.new(0, trail.markerLift, 0)) * UPRIGHT
	part.Color = colorFor(sample.ownerId)
	-- Neon so it reads at all in near-total darkness, but a Neon PART is not a light: it brightens
	-- nothing around it, which is the whole point.
	part.Material = Enum.Material.Neon
	part.Transparency = trail.markerTransparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = ensureFolder()
	marks[sample.seq] = { part = part, sample = sample, baseWidth = trail.markerWidth }
end

-- Ages every mark: fresher marks are wider and clearer, and one that outlives the configured lifetime
-- is removed on the same curve the server prunes its buffer by (Logic/SpectatorRules).
local function fadeMarks()
	local trail = Config.Spectator.trail
	local now = Workspace:GetServerTimeNow()
	for seq, mark in marks do
		local age = now - mark.sample.at
		local alpha = SpectatorRules.trailAlpha(age, trail.lifetimeSeconds, trail.markerFadeFloor)
		if alpha <= 0 then
			mark.part:Destroy()
			marks[seq] = nil
			continue
		end
		mark.part.Transparency = 1 - (1 - trail.markerTransparency) * alpha
		-- The newest mark of each runner lands large and settles: it is the one live thing a ghost sees.
		local freshness = if trail.freshMarkerSeconds > 0
			then math.clamp(1 - age / trail.freshMarkerSeconds, 0, 1)
			else 0
		local width = mark.baseWidth * (1 + (trail.freshMarkerWidthMultiplier - 1) * freshness)
		mark.part.Size = Vector3.new(trail.markerThickness, width, width)
	end
end

local function setPanelVisible(visible: boolean)
	local hud = Config.Spectator.hud
	-- Desktop ghosts use the key. The on-screen button exists for touch, where there is no key to press
	-- and first-person capture means there is no cursor either — so the panel grows to hold it.
	local touch = UserInputService.TouchEnabled
	local frame = panel
	if frame ~= nil then
		frame.Visible = visible and hud.enabled
		frame.Size = if touch then hud.touchSize else hud.size
	end
	local button = followButton
	if button ~= nil then
		button.Visible = visible and hud.enabled and touch
	end
end

local function updateReadout(payload: Remotes.SpectatorPayload)
	local hud = Config.Spectator.hud
	local status = statusLabel
	if status == nil then
		return
	end
	local name = payload.targetName
	if payload.targetId ~= nil and name ~= nil then
		status.Text = string.format(hud.followingFormat, string.upper(name))
	else
		status.Text = hud.freeRoamText
	end
	local hint = hintLabel
	if hint ~= nil then
		hint.Text = string.format(hud.hintFormat, Config.Feel.controls.spectatorFollowKeyLabel)
		-- With nobody left to follow the key does nothing, so stop advertising it.
		hint.Visible = payload.followable > 0
	end
end

local function stopSpectating()
	if not spectating then
		return
	end
	spectating = false
	clearMarks()
	setPanelVisible(false)
end

local function buildHud()
	local hud = Config.Spectator.hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickSpectator"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = hud.displayOrder

	local frame = Instance.new("Frame")
	frame.Name = "GhostReadout"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = hud.position
	frame.Size = hud.size
	frame.BackgroundColor3 = UITheme.palette.void
	frame.BackgroundTransparency = hud.backgroundTransparency
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	UITheme.corner(frame, 7)
	UITheme.stroke(frame, UITheme.palette.strokeSoft, 1, 0.5)
	UITheme.uniformPadding(frame, 6)
	local layout = UITheme.listLayout(frame, 2)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	panel = frame

	local function line(color: Color3, order: number, font: Enum.Font): TextLabel
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 0.4)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextColor3 = color
		label.TextScaled = true
		label.Text = ""
		label.LayoutOrder = order
		label.Parent = frame
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = hud.maxTextSize
		constraint.Parent = label
		return label
	end

	statusLabel = line(UITheme.palette.text, 1, UITheme.font.heading)
	hintLabel = line(UITheme.palette.textDim, 2, UITheme.font.fine)

	local button = UITheme.button(frame, "FOLLOW")
	button.instance.Size = UDim2.new(0.5, 0, 0, 34)
	button.instance.LayoutOrder = 3
	button.instance.Visible = false
	button.instance.Activated:Connect(function()
		if spectating then
			Remotes.get("SpectatorAction"):FireServer("follow")
		end
	end)
	followButton = button.instance

	gui.Parent = player:WaitForChild("PlayerGui")
end

function SpectatorController.start()
	buildHud()

	Remotes.get("SpectatorState").OnClientEvent:Connect(function(payload: Remotes.SpectatorPayload)
		if typeof(payload) ~= "table" then
			return
		end
		-- Receiving this at all means the server considers this player dead: it is only ever sent to
		-- ghosts. Nothing about being a spectator is inferred locally.
		spectating = true
		if payload.reset then
			clearMarks()
		end
		if typeof(payload.samples) == "table" then
			for _, sample in payload.samples do
				if typeof(sample) == "table" and typeof(sample.position) == "Vector3" then
					addMark(sample)
				end
			end
		end
		updateReadout(payload)
		-- With no target and nobody left to follow, there is nothing this readout can say. Hiding it
		-- rather than printing "no one is left down here" keeps a solo/last-out death screen clean.
		setPanelVisible(payload.targetId ~= nil or payload.followable > 0)
	end)

	-- The authoritative exit from spectating: a restart or a lobby return makes this player alive
	-- again, and the ghost's trail and readout must not survive it.
	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			if not SpectatorRules.isGhost(entry.alive, entry.finished) then
				stopSpectating()
			end
			break
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or not spectating or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.KeyCode ~= Config.Feel.controls.spectatorFollowKey then
			return
		end
		-- One action, one meaning: take me to the next candle. Cycling past the last teammate is how a
		-- ghost asks to be left alone, and the server owns that order.
		Remotes.get("SpectatorAction"):FireServer("follow")
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		if next(marks) == nil then
			return
		end
		fadeAccumulator += dt
		-- Marks age over tens of seconds; a per-frame pass would be pure waste.
		if fadeAccumulator < 0.1 then
			return
		end
		fadeAccumulator = 0
		fadeMarks()
	end)
end

return SpectatorController

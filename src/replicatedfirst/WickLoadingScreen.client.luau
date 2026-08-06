--!strict
-- First-load screen. Lives in ReplicatedFirst so it can paint before the rest of the game finishes
-- replicating — that is the whole point of this slot. It is deliberately self-contained: it must not
-- require anything from ReplicatedStorage.Shared, because those modules may not have replicated yet.
-- The palette and the WICK wordmark below are hand-copied from Shared UITheme so the very first thing
-- a player sees is already the finished logo — gilded letters with a live candle for the "I".
--
-- The candle's flame flickers on organic noise (never a strobe) and is the mark's focal light. A thin
-- bronze progress line fills toward the descent; when the game and the server-owned lobby/run body
-- are ready and a minimum beat has passed, the whole thing fades and hands off.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local palette = {
	void = Color3.fromRGB(9, 8, 10),
	gold = Color3.fromRGB(255, 201, 120),
	ember = Color3.fromRGB(255, 150, 66),
	emberDeep = Color3.fromRGB(190, 84, 38),
	flameCore = Color3.fromRGB(255, 247, 222),
	flameMid = Color3.fromRGB(255, 186, 92),
	flameOuter = Color3.fromRGB(255, 116, 44),
	waxLight = Color3.fromRGB(243, 234, 212),
	waxDeep = Color3.fromRGB(198, 182, 150),
	textMuted = Color3.fromRGB(163, 150, 135),
}

local FONT_DISPLAY = Enum.Font.GothamBlack
local FONT_BODY = Enum.Font.GothamMedium
local FONT_FINE = Enum.Font.Gotham

-- Feels unhurried without stalling: we never fade out before this, and never while assets remain.
local MIN_SECONDS = 2.6
local MAX_SECONDS = 14

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local teleportData: { [string]: any }? = nil
pcall(function()
	local arrivingData = TeleportService:GetLocalPlayerTeleportData()
	if typeof(arrivingData) == "table" then
		teleportData = arrivingData
	end
end)

local loadingDiagnosticsEnabled = teleportData ~= nil and teleportData.devDiagnostics == true
if not loadingDiagnosticsEnabled and teleportData ~= nil and typeof(teleportData.devDiagnosticsMembers) == "table" then
	for _, memberId in teleportData.devDiagnosticsMembers do
		if memberId == player.UserId then
			loadingDiagnosticsEnabled = true
			break
		end
	end
end
local arrivingTeleportGui = TeleportService:GetArrivingTeleportGui()
if arrivingTeleportGui ~= nil then
	-- Roblox unparents an arriving custom teleport GUI once loading completes. Claim it immediately
	-- so it covers the few frames while this fresh animated screen is being constructed.
	arrivingTeleportGui.Parent = playerGui
end

local function corner(instance: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = instance
end

local screen = Instance.new("ScreenGui")
screen.Name = "WickLoadingScreen"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 1000
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Cold rock, with candlelight pooled toward the middle. One linear wash reads as a lit cavern.
local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = palette.void
backdrop.BorderSizePixel = 0
backdrop.Parent = screen

local backdropGradient = Instance.new("UIGradient")
backdropGradient.Rotation = 90
backdropGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, palette.void),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 21, 18)),
	ColorSequenceKeypoint.new(1, palette.void),
})
backdropGradient.Parent = backdrop

-- Everything that animates in/out together lives on this group so one fade retires the whole screen.
local stage = Instance.new("CanvasGroup")
stage.Name = "Stage"
stage.AnchorPoint = Vector2.new(0.5, 0.5)
stage.Position = UDim2.fromScale(0.5, 0.5)
stage.Size = UDim2.fromScale(1, 1)
stage.BackgroundTransparency = 1
stage.Parent = screen

-- StarterPlayerScripts do not exist yet. Authorization is carried in TeleportData, so an enabled
-- player gets this panel on the first ReplicatedFirst frame in the destination server.
local diagnosticsLabel: TextLabel? = nil
if loadingDiagnosticsEnabled then
	local diagnostics = Instance.new("Frame")
	diagnostics.Name = "WickLoadingDiagnostics"
	diagnostics.AnchorPoint = Vector2.new(1, 0)
	diagnostics.Position = UDim2.fromScale(0.985, 0.025)
	diagnostics.Size = UDim2.fromOffset(390, 220)
	diagnostics.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	diagnostics.BackgroundTransparency = 0.08
	diagnostics.BorderSizePixel = 0
	diagnostics.ZIndex = 50
	diagnostics.Parent = screen
	corner(diagnostics, 8)

	local diagnosticsStroke = Instance.new("UIStroke")
	diagnosticsStroke.Color = Color3.fromRGB(255, 38, 38)
	diagnosticsStroke.Thickness = 1.5
	diagnosticsStroke.Transparency = 0.1
	diagnosticsStroke.Parent = diagnostics

	local label = Instance.new("TextLabel")
	label.Name = "Readout"
	label.Position = UDim2.fromOffset(12, 10)
	label.Size = UDim2.new(1, -24, 1, -20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.Text = "DEV DIAGNOSTICS - LOADING\nATTACHING..."
	label.TextColor3 = Color3.fromRGB(255, 38, 38)
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 51
	label.Parent = diagnostics
	diagnosticsLabel = label
end

-- --- The WICK wordmark (hero) ---------------------------------------------------------------------
-- Built inline here rather than shared, because ReplicatedFirst can't depend on Shared UITheme yet.
-- Kept structurally identical to UITheme.wordmark / candleGlyph so both surfaces show the same mark.
local LOGO_HEIGHT = 104

local logo = Instance.new("Frame")
logo.Name = "Wordmark"
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.4)
logo.AutomaticSize = Enum.AutomaticSize.X
logo.Size = UDim2.fromOffset(0, LOGO_HEIGHT)
logo.BackgroundTransparency = 1
logo.Parent = stage

local logoLayout = Instance.new("UIListLayout")
logoLayout.FillDirection = Enum.FillDirection.Horizontal
logoLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
logoLayout.VerticalAlignment = Enum.VerticalAlignment.Center
logoLayout.SortOrder = Enum.SortOrder.LayoutOrder
logoLayout.Padding = UDim.new(0, math.floor(LOGO_HEIGHT * 0.05))
logoLayout.Parent = logo

local function letter(char: string, order: number)
	local label = Instance.new("TextLabel")
	label.Name = "Letter_" .. char
	label.BackgroundTransparency = 1
	label.Font = FONT_DISPLAY
	label.Text = char
	label.TextColor3 = palette.gold
	label.TextSize = LOGO_HEIGHT
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, LOGO_HEIGHT)
	label.LayoutOrder = order
	label.Parent = logo

	local gild = Instance.new("UIGradient")
	gild.Rotation = 90
	gild.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.flameCore),
		ColorSequenceKeypoint.new(0.45, palette.gold),
		ColorSequenceKeypoint.new(1, palette.ember),
	})
	gild.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = palette.emberDeep
	stroke.Thickness = math.max(1, LOGO_HEIGHT * 0.03)
	stroke.Transparency = 0.25
	stroke.Parent = label
end

-- The candle-"I". Returns the parts the flicker loop drives.
local function candleGlyph(order: number): (Frame, UIScale, Frame, Frame, Frame)
	local width = LOGO_HEIGHT * 0.36
	local box = Instance.new("Frame")
	box.Name = "CandleI"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(width, LOGO_HEIGHT)
	box.LayoutOrder = order
	box.Parent = logo

	local glowOuter = Instance.new("Frame")
	glowOuter.Name = "GlowOuter"
	glowOuter.AnchorPoint = Vector2.new(0.5, 0.5)
	glowOuter.Position = UDim2.fromScale(0.5, 0.28)
	glowOuter.Size = UDim2.fromOffset(LOGO_HEIGHT * 0.62, LOGO_HEIGHT * 0.62)
	glowOuter.BackgroundColor3 = palette.emberDeep
	glowOuter.BackgroundTransparency = 0.9
	glowOuter.BorderSizePixel = 0
	glowOuter.ZIndex = 1
	glowOuter.Parent = box
	corner(glowOuter, math.floor(LOGO_HEIGHT * 0.31))

	local glowInner = Instance.new("Frame")
	glowInner.Name = "GlowInner"
	glowInner.AnchorPoint = Vector2.new(0.5, 0.5)
	glowInner.Position = UDim2.fromScale(0.5, 0.28)
	glowInner.Size = UDim2.fromOffset(LOGO_HEIGHT * 0.36, LOGO_HEIGHT * 0.36)
	glowInner.BackgroundColor3 = palette.ember
	glowInner.BackgroundTransparency = 0.76
	glowInner.BorderSizePixel = 0
	glowInner.ZIndex = 2
	glowInner.Parent = box
	corner(glowInner, math.floor(LOGO_HEIGHT * 0.18))

	local wax = Instance.new("Frame")
	wax.Name = "Wax"
	wax.AnchorPoint = Vector2.new(0.5, 1)
	wax.Position = UDim2.fromScale(0.5, 0.92)
	wax.Size = UDim2.new(0, LOGO_HEIGHT * 0.22, 0.5, 0)
	wax.BackgroundColor3 = palette.waxLight
	wax.BorderSizePixel = 0
	wax.ZIndex = 4
	wax.Parent = box
	corner(wax, math.floor(LOGO_HEIGHT * 0.05))

	local waxGradient = Instance.new("UIGradient")
	waxGradient.Rotation = 90
	waxGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.waxLight),
		ColorSequenceKeypoint.new(1, palette.waxDeep),
	})
	waxGradient.Parent = wax

	local rim = Instance.new("Frame")
	rim.Name = "Rim"
	rim.AnchorPoint = Vector2.new(0.5, 0)
	rim.Position = UDim2.fromScale(0.5, 0)
	rim.Size = UDim2.fromScale(1, 0.16)
	rim.BackgroundColor3 = palette.gold
	rim.BackgroundTransparency = 0.3
	rim.BorderSizePixel = 0
	rim.ZIndex = 5
	rim.Parent = wax
	corner(rim, math.floor(LOGO_HEIGHT * 0.04))

	local wick = Instance.new("Frame")
	wick.Name = "Wick"
	wick.AnchorPoint = Vector2.new(0.5, 1)
	wick.Position = UDim2.fromScale(0.5, 0.04)
	wick.Size = UDim2.fromOffset(math.max(2, LOGO_HEIGHT * 0.02), LOGO_HEIGHT * 0.06)
	wick.BackgroundColor3 = Color3.fromRGB(28, 20, 16)
	wick.BorderSizePixel = 0
	wick.ZIndex = 5
	wick.Parent = wax

	-- Flame, built as a teardrop so it reads as fire, not a pill: a rounded body carries a rotated
	-- square whose top corner is the point. Warm orange throughout — a deep-orange body with a bright
	-- amber core — rather than the old near-white centre.
	local pivot = Instance.new("Frame")
	pivot.Name = "FlamePivot"
	pivot.AnchorPoint = Vector2.new(0.5, 1)
	pivot.Position = UDim2.fromScale(0.5, 0.46)
	pivot.Size = UDim2.new(0, LOGO_HEIGHT * 0.22, 0.48, 0)
	pivot.BackgroundTransparency = 1
	pivot.ZIndex = 6
	pivot.Parent = box

	local pivotScale = Instance.new("UIScale")
	pivotScale.Scale = 1
	pivotScale.Parent = pivot

	local outerBody = Instance.new("Frame")
	outerBody.Name = "FlameOuterBody"
	outerBody.AnchorPoint = Vector2.new(0.5, 1)
	outerBody.Position = UDim2.fromScale(0.5, 1)
	outerBody.Size = UDim2.fromScale(1, 0.66)
	outerBody.BackgroundColor3 = palette.flameOuter
	outerBody.BorderSizePixel = 0
	outerBody.ZIndex = 6
	outerBody.Parent = pivot
	corner(outerBody, math.floor(LOGO_HEIGHT * 0.11))

	local outerBodyGradient = Instance.new("UIGradient")
	outerBodyGradient.Rotation = 90
	outerBodyGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.flameOuter),
		ColorSequenceKeypoint.new(1, palette.ember),
	})
	outerBodyGradient.Parent = outerBody

	local outerTip = Instance.new("Frame")
	outerTip.Name = "FlameOuterTip"
	outerTip.AnchorPoint = Vector2.new(0.5, 0.5)
	outerTip.Position = UDim2.fromScale(0.5, 0.3)
	outerTip.Size = UDim2.fromOffset(LOGO_HEIGHT * 0.18, LOGO_HEIGHT * 0.18)
	outerTip.Rotation = 45
	outerTip.BackgroundColor3 = palette.flameOuter
	outerTip.BorderSizePixel = 0
	outerTip.ZIndex = 6
	outerTip.Parent = pivot
	corner(outerTip, math.floor(LOGO_HEIGHT * 0.05))

	local coreBody = Instance.new("Frame")
	coreBody.Name = "FlameCoreBody"
	coreBody.AnchorPoint = Vector2.new(0.5, 1)
	coreBody.Position = UDim2.fromScale(0.5, 0.96)
	coreBody.Size = UDim2.fromScale(0.52, 0.5)
	coreBody.BackgroundColor3 = palette.flameMid
	coreBody.BorderSizePixel = 0
	coreBody.ZIndex = 7
	coreBody.Parent = pivot
	corner(coreBody, math.floor(LOGO_HEIGHT * 0.07))

	local coreTip = Instance.new("Frame")
	coreTip.Name = "FlameCoreTip"
	coreTip.AnchorPoint = Vector2.new(0.5, 0.5)
	coreTip.Position = UDim2.fromScale(0.5, 0.42)
	coreTip.Size = UDim2.fromOffset(LOGO_HEIGHT * 0.1, LOGO_HEIGHT * 0.1)
	coreTip.Rotation = 45
	coreTip.BackgroundColor3 = palette.flameMid
	coreTip.BorderSizePixel = 0
	coreTip.ZIndex = 7
	coreTip.Parent = pivot
	corner(coreTip, math.floor(LOGO_HEIGHT * 0.03))

	return pivot, pivotScale, glowInner, glowOuter, coreBody
end

letter("W", 1)
local flPivot, flScale, flGlowInner, flGlowOuter, flCore = candleGlyph(2)
letter("C", 3)
letter("K", 4)

-- --- Tagline / progress / status ------------------------------------------------------------------
local tagline = Instance.new("TextLabel")
tagline.Name = "Tagline"
tagline.AnchorPoint = Vector2.new(0.5, 0.5)
tagline.Position = UDim2.fromScale(0.5, 0.57)
tagline.Size = UDim2.fromOffset(520, 28)
tagline.BackgroundTransparency = 1
tagline.Font = FONT_FINE
tagline.Text = "Descend by candlelight · carry the light home"
tagline.TextColor3 = palette.textMuted
tagline.TextScaled = true
tagline.Parent = stage

local taglineConstraint = Instance.new("UITextSizeConstraint")
taglineConstraint.MaxTextSize = 20
taglineConstraint.Parent = tagline

local track = Instance.new("Frame")
track.Name = "ProgressTrack"
track.AnchorPoint = Vector2.new(0.5, 0.5)
track.Position = UDim2.fromScale(0.5, 0.74)
track.Size = UDim2.fromOffset(320, 4)
track.BackgroundColor3 = Color3.fromRGB(40, 33, 30)
track.BorderSizePixel = 0
track.Parent = stage
corner(track, 2)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.AnchorPoint = Vector2.new(0, 0.5)
fill.Position = UDim2.fromScale(0, 0.5)
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = palette.ember
fill.BorderSizePixel = 0
fill.Parent = track
corner(fill, 2)

local fillGradient = Instance.new("UIGradient")
fillGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, palette.emberDeep),
	ColorSequenceKeypoint.new(1, palette.gold),
})
fillGradient.Parent = fill

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.8)
status.Size = UDim2.fromOffset(320, 20)
status.BackgroundTransparency = 1
status.Font = FONT_BODY
status.Text = "Lighting the candle…"
status.TextColor3 = palette.textMuted
status.TextTransparency = 0.15
status.TextScaled = true
status.Parent = stage

local statusConstraint = Instance.new("UITextSizeConstraint")
-- Matches client/UITheme.textSize.fine. ReplicatedFirst cannot require the shared theme this early,
-- so the number is duplicated here on purpose — keep it in step with that table.
statusConstraint.MinTextSize = 13
statusConstraint.MaxTextSize = 16
statusConstraint.Parent = status

-- Entrance: the whole stage fades up while the logo lifts a hair into place.
stage.GroupTransparency = 1
logo.Position = UDim2.fromScale(0.5, 0.43)
TweenService:Create(stage, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	GroupTransparency = 0,
}):Play()
TweenService:Create(logo, TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
	Position = UDim2.fromScale(0.5, 0.4),
}):Play()
if arrivingTeleportGui ~= nil then
	arrivingTeleportGui:Destroy()
	arrivingTeleportGui = nil
end

-- Flame flicker. math.noise gives smooth, organic wander — a candle nudged by cave air, not a strobe.
local seed = Random.new():NextNumber(0, 1000)
local flameConn: RBXScriptConnection? = nil
flameConn = RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local sway = math.noise(t * 1.5, seed)
	local flick = math.noise(seed, t * 2.3)
	local fast = math.noise(t * 5.5, seed * 0.5)
	flPivot.Rotation = sway * 5
	flPivot.Position = UDim2.fromScale(0.5 + sway * 0.02, 0.46)
	flScale.Scale = 1 + flick * 0.08 + fast * 0.03
	local pulse = (flick + 1) * 0.5
	flGlowInner.BackgroundTransparency = 0.74 - pulse * 0.12
	flGlowOuter.BackgroundTransparency = 0.9 - pulse * 0.07
	flCore.BackgroundTransparency = math.clamp(0.05 - fast * 0.05, 0, 1)
end)

-- --- Progress model -------------------------------------------------------------------------------
-- A real target (game loaded + queue drained) that the bar eases toward every frame, so the line is
-- always alive and never parks at a hard 100% before the handoff.
local statusStages = {
	{ at = 0.0, text = "Lighting the candle…" },
	{ at = 0.35, text = "Shaping the caves…" },
	{ at = 0.65, text = "Pooling the wax…" },
	{ at = 0.9, text = "Opening the descent…" },
}
local lastStage = ""

local startClock = os.clock()
local shown = 0

-- WHAT THIS SCREEN IS STILL WAITING ON, in the order it is checked. Recorded rather than inferred,
-- because the three gates fail for completely unrelated reasons and only one of them is ours: a body
-- is the server finishing the cave, replication is the platform handing over the data model, and the
-- asset queue is the client fetching sounds and textures. A descent that feels long is one of these
-- and the retire line below says which one held it and for how long.
local blockedOn = "starting"

local diagnosticsFrames = 0
local diagnosticsFrameSeconds = 0
local diagnosticsFps = 0
local nextDiagnosticsRefresh = 0

local function updateLoadingDiagnostics(dt: number, elapsed: number)
	local label = diagnosticsLabel
	if label == nil then
		return
	end
	diagnosticsFrames += 1
	diagnosticsFrameSeconds += dt
	if diagnosticsFrameSeconds >= 0.5 then
		diagnosticsFps = diagnosticsFrames / diagnosticsFrameSeconds
		diagnosticsFrames = 0
		diagnosticsFrameSeconds = 0
	end
	if elapsed < nextDiagnosticsRefresh then
		return
	end
	nextDiagnosticsRefresh = elapsed + 0.25

	local serverStage = workspace:GetAttribute("WickLoadingStage")
	local serverStageSince = workspace:GetAttribute("WickLoadingStageSince")
	local stageElapsed = if typeof(serverStageSince) == "number"
		then math.max(0, workspace:GetServerTimeNow() - serverStageSince)
		else -1
	local pingMs = 0
	pcall(function()
		pingMs = math.round(player:GetNetworkPing() * 1000)
	end)
	local tier = if teleportData ~= nil then tostring(teleportData.tierId or "-") else "-"
	label.Text = string.format(
		"DEV DIAGNOSTICS - LOADING\nELAPSED  %.1fs   GATE  %s\nSTAGE    %s\nSTAGE AGE %.1fs\nBODY     %s   REPLICATION %s\nASSETS   %d\nCLIENT   %d FPS   %d ms   %d MB\nSERVER   %s   TIER %s\nJOB      %s",
		elapsed,
		blockedOn,
		tostring(serverStage or "unavailable"),
		stageElapsed,
		if player.Character ~= nil then "READY" else "WAITING",
		if game:IsLoaded() then "READY" else "WAITING",
		ContentProvider.RequestQueueSize,
		math.round(diagnosticsFps),
		pingMs,
		math.round(Stats:GetTotalMemoryUsageMb()),
		if game.PrivateServerId ~= "" then "RESERVED" else "PUBLIC",
		tier,
		string.sub(game.JobId, 1, 8)
	)
end

local function ready(): boolean
	local elapsed = os.clock() - startClock
	if player.Character == nil then
		blockedOn = "body"
		return false
	end
	if not game:IsLoaded() then
		blockedOn = "replication"
		return false
	end
	if elapsed < MIN_SECONDS then
		blockedOn = "minimumBeat"
		return false
	end
	if ContentProvider.RequestQueueSize > 8 and elapsed < MAX_SECONDS then
		blockedOn = "assets"
		return false
	end
	-- Deliberately not cleared on success: the useful value is the LAST thing that held the screen,
	-- and by the time anything reads this the screen is retiring anyway.
	return true
end

local function installTeleportGui()
	local previous = ReplicatedFirst:FindFirstChild("WickTeleportGui")
	if previous ~= nil then
		previous:Destroy()
	end
	-- LocalScripts inside a custom teleport GUI do not run, so preserve this finished frame as a
	-- static handoff. The destination's fresh ReplicatedFirst screen takes over as soon as it boots.
	local template = screen:Clone()
	template.Name = "WickTeleportGui"
	template.Parent = ReplicatedFirst
	TeleportService:SetTeleportGui(template)
end

local function retire()
	print(string.format(
		"[WICK] loading_screen elapsed=%.1fs lastGate=%s",
		os.clock() - startClock,
		-- Whatever `ready` was refusing on immediately before it passed. "body" means the wait was
		-- the server carving floor one; anything else means it was not.
		blockedOn
	))
	installTeleportGui()
	if flameConn ~= nil then
		flameConn:Disconnect()
		flameConn = nil
	end
	local fade = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(stage, fade, { GroupTransparency = 1 }):Play()
	TweenService:Create(backdrop, fade, { BackgroundTransparency = 1 }):Play()
	task.delay(0.65, function()
		screen:Destroy()
	end)
end

-- A screen that is still up several seconds in is the one thing a player can see and a developer
-- cannot, so it reports itself rather than being guessed at from the outside. Every gate it can stall
-- on belongs to a different system — a body is the server's cave, replication is the platform handing
-- over the data model, assets are the client fetching sound and texture — and the whole point of
-- naming the gate is that three completely different fixes hang off it. Readable live from the
-- in-game developer console (F9), which is why it warns rather than prints.
local STALL_REPORT_AFTER = 6
local STALL_REPORT_EVERY = 3
local nextStallReport = STALL_REPORT_AFTER

task.spawn(function()
	local previousFrame = os.clock()
	while true do
		local now = os.clock()
		local elapsed = now - startClock
		local frameDt = math.max(0, now - previousFrame)
		previousFrame = now
		local isReady = ready()
		if diagnosticsLabel ~= nil then
			local currentLabel = diagnosticsLabel
			local ok, message = pcall(updateLoadingDiagnostics, frameDt, elapsed)
			if not ok then
				warn("[WICK] Loading diagnostics update failed: " .. tostring(message))
				currentLabel.Text = "DEV DIAGNOSTICS - LOADING\nREADOUT ERROR - SEE OUTPUT"
				diagnosticsLabel = nil
			end
		end

		if not isReady and elapsed >= nextStallReport then
			nextStallReport = elapsed + STALL_REPORT_EVERY
			local serverStage = workspace:GetAttribute("WickLoadingStage")
			local serverStageSince = workspace:GetAttribute("WickLoadingStageSince")
			local serverStageElapsed = if typeof(serverStageSince) == "number"
				then math.max(0, workspace:GetServerTimeNow() - serverStageSince)
				else -1
			warn(
				string.format(
					"[WICK] loading_screen_waiting elapsed=%.1fs gate=%s assetQueue=%d serverStage=%s stageElapsed=%.1fs",
					elapsed,
					blockedOn,
					ContentProvider.RequestQueueSize,
					tostring(serverStage or "unavailable"),
					serverStageElapsed
				)
			)
		end

		-- Target creeps up on time but is capped short of full until we are truly ready; then it completes.
		local timeTarget = math.clamp(elapsed / MIN_SECONDS, 0, 0.92)
		local target = if isReady then 1 else timeTarget

		shown += (target - shown) * 0.08
		if target >= 1 and shown > 0.995 then
			shown = 1
		end
		fill.Size = UDim2.fromScale(shown, 1)

		for _, entry in statusStages do
			if shown >= entry.at and entry.text ~= lastStage then
				lastStage = entry.text
				status.Text = entry.text
			end
		end

		if shown >= 0.999 and isReady then
			break
		end
		RunService.RenderStepped:Wait()
	end
	task.wait(0.25)
	retire()
end)

--!strict
-- Mining input and presentation. Finds the deposit in reach, puts a pickaxe in the player's hands,
-- takes the clicks, draws the timing rail, and shows what has been carried out of the rock. It
-- decides NOTHING: the server owns whether a stance may open, when each sweep began, where its band
-- sits, what a strike was worth, and when the seam breaks.
--
-- THE LOOP, from this side: click a seam to ENGAGE — you plant, the pick comes up over your
-- shoulder, and a marker starts sweeping a fracture rail. Every click after that is a STRIKE scored where the
-- marker is. Strike, the pick recovers, the band has moved, read it again. Any movement key, a right
-- click, or the seam breaking ends the stance.
--
-- The rail is reconstructed, never replicated. The server sends a `startedAt` stamp in
-- Workspace:GetServerTimeNow() space plus the band's centre, and this file evaluates
-- Logic/MiningRules against them — the same pure function the server scores the strike with. The
-- click carries that shared timestamp back through a tightly bounded server rewind, removing normal
-- transport latency without accepting a client-authored outcome or an arbitrary old strike.
--
-- Two things here are deliberately LOCAL PREDICTIONS, and both are cosmetic only: the down-stroke
-- starts on the click rather than on the server's reply (a swing that waited for a round trip felt
-- broken), and the seam glow is drawn entirely client-side. Neither touches progress, accuracy, or
-- cargo — every number this file displays came from the server.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MiningRules = require(ReplicatedStorage.Shared.Logic.MiningRules)
local MiningVisualProtocol = require(ReplicatedStorage.Shared.MiningVisualProtocol)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local UITheme = require(script.Parent.UITheme)

local MiningController = {}

local player = Players.LocalPlayer
local palette = UITheme.palette

local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local ACTION_NAME = "WickMineStrike"
local EXIT_ACTION_NAME = "WickMineExit"
local qteConfig = Config.Mining.qte
-- Keys that mean "I am leaving". Polled rather than bound, so mining never sinks a movement key
-- away from MovementController.
local EXIT_KEYS: { Enum.KeyCode } = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Space,
}

local controlsBound = false
local currentDepth = 0
-- The deposit currently in reach, if any. Purely a display/input target: being "active" grants
-- nothing, and the server re-derives reach itself on engage and on every strike.
local activeRoot: BasePart? = nil
-- The live stance, mirrored from the server. Non-nil means the rail is up and the pick is ready.
local sweepStartedAt: number? = nil
local bandCenter = Config.Mining.timing.perfectCenter
local engagedRoot: BasePart? = nil
-- The Config/Mining row of the seam currently engaged, or nil. Read once on engage rather than per
-- frame: a seam cannot change row mid-stance, and re-reading an attribute every strike would be
-- three lookups for a value that never moves.
local engagedRow: MiningRules.DepositRow? = nil
-- Consecutive Perfects. Drives the audio ladder and nothing else — it is not a score, it is not
-- replicated, and it buys the player no progress.
local perfectStreak = 0
-- Input latches keep a reliable RemoteEvent round trip from becoming duplicate gameplay input. A
-- second click while engage/strike is in flight is swallowed locally; server validation remains the
-- authority and independently treats a duplicate engage as an idempotent state resend.
local engagePending = false
local strikePending = false
local requestGeneration = 0
-- Only a floor/run transition invalidates authoritative reward presentation. A normal
-- `disengaged("Depleted")` follows the private depletion result in the same server frame and must
-- not cancel its delayed contact-aligned break/cargo beat.
local presentationLifetimeGeneration = 0
-- Local-only animation clock. Set on the CLICK so anticipation and the down-stroke start instantly,
-- then left alone. The server reply times impact feedback against this predicted visual contact.
local swingStartedAt = -math.huge
local engagedAt = 0
local swingAccuracy: string? = nil
local swingDepleted = false
local swingReleasedWax = false
local swingTarget: BasePart? = nil

-- Where the strike rail sits when it is not being shaken. Read by the per-frame miss offset.
local RING_BASE_POSITION = qteConfig.position
-- A fumble jolts the rail instead of just changing a colour, so a miss is felt as well as seen. Local
-- animation clock only — cosmetic, so it runs on os.clock() rather than the shared server clock.
local shakeUntil = -math.huge

local ringFrame: CanvasGroup? = nil
local ringScale: UIScale? = nil
local ringMarker: Frame? = nil
local ringMarkerScale: UIScale? = nil
local ringImpactLine: Frame? = nil
local ringResult: TextLabel? = nil
local ringControl: TextLabel? = nil
local resultUntil = -math.huge
local goodBands: { Frame } = {}
local perfectBands: { Frame } = {}
local ringBandCenter = -1
local ringVisibilityGeneration = 0
-- The break flash. Deliberately NOT a child of the rail: `depleted` tears the rail down on the same
-- frame it fires, and a burst parented to a frame that just went invisible never gets to be seen.
local breakFlash: Frame? = nil
local promptLabel: TextLabel? = nil
local promptAlpha = 0
local hintLabel: TextLabel? = nil
local hintGeneration = 0
local cargoPanel: CanvasGroup? = nil
local cargoValue: TextLabel? = nil
local cargoScale: UIScale? = nil
local cargoVisibilityGeneration = 0
local carriedRawWax = 0
-- A paid helper receives both the shared world break and their private cargo result. Whichever
-- arrives first owns the spatial break presentation; the other still delivers its HUD/reward read
-- without doubling the same rubble transient and debris burst.
local presentedBreaks: { [BasePart]: boolean } = {}

local pickaxeModel: Model? = nil
local pickaxeWanted = false
local pickaxeFadeAlpha = 0

-- Local amber ember shells, one per wax seam of every nearby deposit. Client-only presentation:
-- built on approach, faded by distance, destroyed when you walk away.
type SeamGlow = { shells: { BasePart }, alpha: number }
local seamGlows: { [Model]: SeamGlow } = {}

-- Put the authored target midpoint at the centre of the rail. This moves the circular seam to an
-- always-empty phase, so the full wander range stays one aperture instead of splitting across the
-- rail's disconnected endpoints.
local function displayPhase(phase: number): number
	return (phase + 0.5 - Config.Mining.timing.perfectCenter) % 1
end

-- Paint a circular scoring window on a linear rail. A window that crosses 0/1 is split into two
-- contiguous pieces, so the display remains mathematically identical to MiningRules without the
-- old 48-segment timing quantization.
local function setBandGeometry(frames: { Frame }, center: number, halfWidth: number, height: number)
	local intervals: { { number } } = {}
	local first = center - halfWidth
	local last = center + halfWidth
	if first < 0 then
		table.insert(intervals, { first + 1, 1 })
		table.insert(intervals, { 0, last })
	elseif last > 1 then
		table.insert(intervals, { first, 1 })
		table.insert(intervals, { 0, last - 1 })
	else
		table.insert(intervals, { first, last })
	end
	for index, frame in frames do
		local interval = intervals[index]
		if interval == nil then
			frame.Visible = false
		else
			local startPhase = interval[1]
			local endPhase = interval[2]
			frame.Visible = true
			frame.Position = UDim2.new(startPhase, 0, 0.5, 0)
			frame.Size = UDim2.new(math.max(0, endPhase - startPhase), 0, 0, height)
		end
	end
end

-- Repaint only when the server moves the aperture. Good is the warm shoulder and Perfect the
-- narrow bright core, preserving one clear visual hierarchy.
local function paintRing(center: number)
	if math.abs(center - ringBandCenter) < 1e-4 then
		return
	end
	ringBandCenter = center
	local displayedCenter = displayPhase(center)
	setBandGeometry(goodBands, displayedCenter, Config.Mining.timing.goodHalfWidth, qteConfig.goodBandHeightPixels)
	setBandGeometry(
		perfectBands,
		displayedCenter,
		Config.Mining.timing.perfectHalfWidth,
		qteConfig.perfectBandHeightPixels
	)
end

local function buildRing(parent: ScreenGui)
	local frame = Instance.new("CanvasGroup")
	frame.Name = "MiningStrikeRail"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = RING_BASE_POSITION
	frame.Size = UDim2.fromOffset(qteConfig.widthPixels + 40, qteConfig.heightPixels)
	frame.BackgroundTransparency = 1
	frame.GroupTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	ringScale = UITheme.scale(frame, 1)

	local track = Instance.new("Frame")
	track.Name = "FractureTrack"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.5)
	track.Size = UDim2.fromOffset(qteConfig.widthPixels, qteConfig.trackThicknessPixels)
	track.BackgroundColor3 = palette.strokeSoft
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.ClipsDescendants = false
	track.ZIndex = 1
	track.Parent = frame
	UITheme.corner(track, qteConfig.trackThicknessPixels)

	local trackGradient = Instance.new("UIGradient")
	trackGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.strokeSoft),
		ColorSequenceKeypoint.new(0.5, palette.textDim),
		ColorSequenceKeypoint.new(1, palette.strokeSoft),
	})
	trackGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.12, 0),
		NumberSequenceKeypoint.new(0.88, 0),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	trackGradient.Parent = track

	local function buildBand(name: string, color: Color3, transparency: number): Frame
		local band = Instance.new("Frame")
		band.Name = name
		band.AnchorPoint = Vector2.new(0, 0.5)
		band.BackgroundColor3 = color
		band.BackgroundTransparency = transparency
		band.BorderSizePixel = 0
		band.ZIndex = 2
		band.Parent = track
		UITheme.corner(band, 3)
		return band
	end

	for _ = 1, 2 do
		table.insert(goodBands, buildBand("GoodAperture", palette.emberDeep, 0.18))
		table.insert(perfectBands, buildBand("PerfectCore", palette.gold, 0.02))
	end
	paintRing(Config.Mining.timing.perfectCenter % 1)

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0, 0.5)
	marker.Size = UDim2.fromOffset(qteConfig.markerSize.X, qteConfig.markerSize.Y)
	marker.BackgroundColor3 = palette.flameCore
	marker.BorderSizePixel = 0
	marker.ZIndex = 3
	marker.Parent = track
	UITheme.corner(marker, 3)
	local markerGlow = UITheme.stroke(marker, palette.ember, 2, 0.42)
	markerGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ringMarker = marker
	ringMarkerScale = UITheme.scale(marker, 1)

	local impactLine = Instance.new("Frame")
	impactLine.Name = "ContactTrace"
	impactLine.AnchorPoint = Vector2.new(0.5, 0.5)
	impactLine.Position = UDim2.fromScale(0, 0.5)
	impactLine.Size = UDim2.fromOffset(8, 2)
	impactLine.BackgroundColor3 = palette.gold
	impactLine.BackgroundTransparency = 1
	impactLine.BorderSizePixel = 0
	impactLine.ZIndex = 4
	impactLine.Parent = track
	UITheme.corner(impactLine, 2)
	ringImpactLine = impactLine

	local result = Instance.new("TextLabel")
	result.Name = "StrikeRead"
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.new(0.5, 0, 0, 10)
	result.Size = UDim2.fromOffset(150, 20)
	result.BackgroundTransparency = 1
	result.Font = UITheme.font.fine
	result.Text = "READ THE FRACTURE"
	result.TextColor3 = palette.textMuted
	result.TextSize = 12
	result.TextTransparency = 0.28
	result.ZIndex = 4
	result.Parent = frame
	ringResult = result

	local control = Instance.new("TextLabel")
	control.Name = "ReleaseControl"
	control.AnchorPoint = Vector2.new(0.5, 0.5)
	control.Position = UDim2.new(0.5, 0, 1, -8)
	control.Size = UDim2.fromOffset(130, 18)
	control.BackgroundTransparency = 1
	control.Font = UITheme.font.fine
	control.Text = "[Q] RELEASE"
	control.TextColor3 = palette.textDim
	control.TextSize = 11
	control.TextTransparency = 0.24
	control.ZIndex = 4
	control.Parent = frame
	ringControl = control

	ringFrame = frame

	local flash = Instance.new("Frame")
	flash.Name = "MiningBreakFlash"
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = RING_BASE_POSITION
	flash.Size = UDim2.fromOffset(qteConfig.widthPixels * 0.24, 2)
	flash.BackgroundColor3 = palette.gold
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Visible = false
	flash.Parent = parent
	UITheme.corner(flash, 2)
	breakFlash = flash
end

-- A seam break gets one restrained line of light; fracture, debris, and the low-end audio body carry
-- the payoff in the world instead of a full-screen arcade burst.
local function playBreakFlash()
	local flash = breakFlash
	if flash == nil then
		return
	end
	flash.Size = UDim2.fromOffset(qteConfig.widthPixels * 0.24, 2)
	flash.BackgroundTransparency = 0.08
	flash.Visible = true
	local info = TweenInfo.new(qteConfig.exitSeconds + 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fade = UITheme.tween(flash, info, {
		Size = UDim2.fromOffset(qteConfig.widthPixels, 2),
		BackgroundTransparency = 1,
	})
	fade.Completed:Connect(function()
		flash.Visible = false
	end)
end

-- Contact compresses the marker and sends one short trace through the rail. The result replaces the
-- instruction briefly; no combo typography, expanding circles, or simultaneous whole-HUD bounce.
local function playRingHit(accuracy: string)
	local marker = ringMarker
	local markerScale = ringMarkerScale
	local impactLine = ringImpactLine
	local result = ringResult
	if marker == nil or markerScale == nil or impactLine == nil or result == nil then
		return
	end

	local color: Color3
	local resultText: string
	if accuracy == "Perfect" then
		color = palette.gold
		resultText = "PERFECT BITE"
	elseif accuracy == "Miss" then
		color = palette.danger
		resultText = "GLANCE"
	else
		color = palette.ember
		resultText = "SOLID BITE"
	end

	impactLine.Position = marker.Position
	impactLine.Size = UDim2.fromOffset(8, 2)
	impactLine.BackgroundColor3 = color
	impactLine.BackgroundTransparency = 0.08
	UITheme.tween(
		impactLine,
		TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(if accuracy == "Perfect" then 44 else 30, 2), BackgroundTransparency = 1 }
	)

	marker.BackgroundColor3 = color
	markerScale.Scale = if accuracy == "Miss" then 0.9 else 0.76
	UITheme.tween(markerScale, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
	UITheme.tween(
		marker,
		TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundColor3 = palette.flameCore }
	)

	result.Text = resultText
	result.TextColor3 = color
	result.TextTransparency = 0
	resultUntil = os.clock() + Config.Mining.feedback.hintSeconds

	local scale = ringScale
	if scale ~= nil then
		scale.Scale = if accuracy == "Miss" then 0.99 else 0.985
		UITheme.tween(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
	end

	if accuracy == "Miss" then
		shakeUntil = os.clock() + qteConfig.shakeDuration
	end
end

local function buildPrompt(parent: ScreenGui)
	local label = Instance.new("TextLabel")
	label.Name = "MiningPrompt"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.705)
	label.Size = UDim2.fromOffset(300, 28)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = UITheme.font.heading
	label.TextSize = 13
	label.TextColor3 = palette.gold
	label.TextTransparency = 1
	label.TextStrokeColor3 = palette.void
	label.TextStrokeTransparency = 0.62
	label.Visible = false
	label.Parent = parent
	promptLabel = label

	local hint = Instance.new("TextLabel")
	hint.Name = "MiningHint"
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, 0.725)
	hint.Size = UDim2.fromOffset(420, 24)
	hint.BackgroundTransparency = 1
	hint.Font = UITheme.font.fine
	hint.TextSize = 13
	hint.TextColor3 = palette.textDim
	hint.TextStrokeColor3 = palette.void
	hint.TextStrokeTransparency = 0.68
	hint.TextTransparency = 1
	hint.Visible = false
	hint.Parent = parent
	hintLabel = hint
end

-- The carried-cargo readout (PHASE 7A). A COUNT, never a meter: no bar, no maximum, no drain — it
-- must not read as a second thing keeping you alive, because it does nothing of the sort. Hidden
-- entirely at zero, so a run that never mines never sees it.
local function buildCargo(parent: ScreenGui)
	local panel = Instance.new("CanvasGroup")
	panel.Name = "RawWaxCargo"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromOffset(24, 92)
	panel.Size = UDim2.fromOffset(132, 38)
	panel.BackgroundTransparency = 1
	panel.GroupTransparency = 1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent
	cargoScale = UITheme.scale(panel, 1)

	local rule = Instance.new("Frame")
	rule.Name = "WaxRule"
	rule.AnchorPoint = Vector2.new(0, 0.5)
	rule.Position = UDim2.new(0, 0, 0.5, 0)
	rule.Size = UDim2.fromOffset(2, 28)
	rule.BackgroundColor3 = Config.Mining.visual.waxColor
	rule.BackgroundTransparency = 0.08
	rule.BorderSizePixel = 0
	rule.Parent = panel
	UITheme.corner(rule, 2)

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0, 0.5)
	caption.Position = UDim2.new(0, 11, 0.5, -7)
	caption.Size = UDim2.fromOffset(112, 12)
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.font.fine
	caption.Text = "RAW WAX"
	caption.TextSize = 10
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = palette.textDim
	caption.Parent = panel

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.Position = UDim2.new(0, 11, 0.5, 8)
	value.Size = UDim2.fromOffset(112, 18)
	value.BackgroundTransparency = 1
	value.Font = UITheme.font.body
	value.Text = "0"
	value.TextSize = 17
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = palette.gold
	value.Parent = panel
	cargoValue = value

	cargoPanel = panel
end

local function setCargo(total: number, pulse: boolean)
	local panel = cargoPanel
	local value = cargoValue
	if panel == nil or value == nil then
		return
	end
	local previous = carriedRawWax
	carriedRawWax = total
	value.Text = tostring(total)
	cargoVisibilityGeneration += 1
	local generation = cargoVisibilityGeneration
	if total > 0 then
		panel.Visible = true
		UITheme.tween(
			panel,
			TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 0 }
		)
	else
		local fade = UITheme.tween(
			panel,
			TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ GroupTransparency = 1 }
		)
		fade.Completed:Connect(function()
			if cargoVisibilityGeneration == generation and carriedRawWax <= 0 then
				panel.Visible = false
			end
		end)
	end
	local scale = cargoScale
	if pulse and scale ~= nil and total > previous then
		scale.Scale = Config.Mining.feedback.cargoPulseScale
		UITheme.tween(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
	end
end

-- A short, blunt, obviously non-combat tool, parented to the camera. It has no collision, answers no
-- query, and exists only while a seam is in reach — there is no pickaxe to swing at anything else.
local function toolPart(
	model: Model,
	className: "Part" | "WedgePart",
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material
): BasePart
	local created = Instance.new(className) :: BasePart
	created.Name = name
	created.Size = size
	created.CFrame = at
	created.Color = color
	created.Material = material
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.CastShadow = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = model
	return created
end

local function buildPickaxe(): Model
	local cfg = Config.Mining.pickaxe
	local model = Instance.new("Model")
	model.Name = "WickPickaxe"

	local handle =
		toolPart(model, "Part", "Handle", cfg.handleSize, CFrame.identity, cfg.handleColor, Enum.Material.Wood)
	local headY = cfg.handleSize.Y / 2 + cfg.headSize.Y * 0.15
	local headAt = CFrame.new(0, headY, 0)
	toolPart(model, "Part", "HeadEye", cfg.headSize, headAt, cfg.headColor, Enum.Material.Metal)

	local prongOffset = (cfg.headSize.X + cfg.prongSize.X) * 0.5 - 0.08
	local leftProng = toolPart(
		model,
		"WedgePart",
		"LeftProng",
		cfg.prongSize,
		headAt * CFrame.new(-prongOffset, 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
		cfg.headEdgeColor,
		Enum.Material.Metal
	)
	local rightProng = toolPart(
		model,
		"WedgePart",
		"RightProng",
		cfg.prongSize,
		headAt * CFrame.new(prongOffset, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
		cfg.headEdgeColor,
		Enum.Material.Metal
	)
	toolPart(
		model,
		"Part",
		"Collar",
		cfg.collarSize,
		CFrame.new(0, cfg.handleSize.Y / 2 - cfg.collarSize.Y * 0.35, 0),
		cfg.headColor,
		Enum.Material.Metal
	)

	for index = 1, math.max(0, math.floor(cfg.gripCount)) do
		local y = -cfg.handleSize.Y / 2 + 0.18 + (index - 1) * cfg.gripSpacing
		local wrap = toolPart(
			model,
			"Part",
			"GripWrap",
			cfg.gripSize,
			CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(index * 18), 0),
			cfg.gripColor,
			Enum.Material.Fabric
		)
		wrap.Transparency = 0.05
	end

	local leftTrail = Instance.new("Attachment")
	leftTrail.Name = "TrailLeft"
	leftTrail.Position = Vector3.new(-cfg.prongSize.X * 0.35, 0, 0)
	leftTrail.Parent = leftProng
	local rightTrail = Instance.new("Attachment")
	rightTrail.Name = "TrailRight"
	rightTrail.Position = Vector3.new(cfg.prongSize.X * 0.35, 0, 0)
	rightTrail.Parent = rightProng
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = leftTrail
	trail.Attachment1 = rightTrail
	trail.Color = ColorSequence.new(cfg.trailColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.48),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, cfg.trailWidthScale),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.FaceCamera = true
	trail.Lifetime = cfg.trailLifetime
	trail.LightEmission = 0.4
	trail.Enabled = false
	trail.Parent = handle

	model.PrimaryPart = handle
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("WickBaseTransparency", descendant.Transparency)
			descendant.Transparency = 1
		end
	end
	return model
end

local function setPickaxeVisible(visible: boolean)
	pickaxeWanted = visible
	if visible then
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		if pickaxeModel == nil then
			local built = buildPickaxe()
			built.Parent = camera
			pickaxeModel = built
		elseif pickaxeModel.Parent ~= camera then
			pickaxeModel.Parent = camera
		end
	end
end

local function destroyPickaxe()
	pickaxeWanted = false
	pickaxeFadeAlpha = 0
	if pickaxeModel ~= nil then
		pickaxeModel:Destroy()
		pickaxeModel = nil
	end
end

local function updatePickaxeVisibility(dt: number)
	local built = pickaxeModel
	if built == nil then
		pickaxeFadeAlpha = 0
		return
	end
	local target = if pickaxeWanted then 1 else 0
	local seconds = if pickaxeWanted then Config.Mining.pickaxe.raiseSeconds else qteConfig.exitSeconds
	local step = math.clamp(dt / math.max(seconds, 0.01), 0, 1)
	pickaxeFadeAlpha += (target - pickaxeFadeAlpha) * step
	for _, descendant in built:GetDescendants() do
		if descendant:IsA("BasePart") then
			local baseTransparency = tonumber(descendant:GetAttribute("WickBaseTransparency")) or 0
			descendant.Transparency = 1 - pickaxeFadeAlpha * (1 - baseTransparency)
		end
	end
	if not pickaxeWanted and pickaxeFadeAlpha <= 0.015 then
		destroyPickaxe()
	end
end

-- The pickaxe's whole animation, as one function of the clock.
--
-- Out of a stance it rests at the hip. Entering one draws it up over the shoulder, and it LIVES
-- there — every strike is a fall from ready to the rock and a recovery back to ready, timed so the
-- pick is up and still again before the next sweep starts. The down-stroke accelerates and the
-- recovery decelerates, because a pickaxe is a weight on a stick, not a cursor.
local function pickaxeOffset(now: number): CFrame
	local cfg = Config.Mining.pickaxe
	local engaged = sweepStartedAt ~= nil
	local sinceSwing = now - swingStartedAt
	local contactOffset = if swingDepleted
		then cfg.breakOffset
		elseif swingAccuracy == "Miss" then cfg.glanceOffset
		else cfg.strikeOffset
	local reboundOffset = if swingDepleted
		then contactOffset:Lerp(cfg.reboundOffset, 0.45)
		elseif swingAccuracy == "Perfect" then contactOffset:Lerp(cfg.reboundOffset, 0.68)
		elseif swingAccuracy == "Miss" then contactOffset:Lerp(cfg.reboundOffset, 0.82)
		else cfg.reboundOffset

	if sinceSwing >= 0 then
		if sinceSwing < cfg.anticipationSeconds then
			local alpha = sinceSwing / math.max(cfg.anticipationSeconds, 0.01)
			return cfg.raisedOffset:Lerp(cfg.anticipationOffset, 1 - (1 - alpha) * (1 - alpha))
		end
		if sinceSwing < cfg.anticipationSeconds + cfg.swingSeconds then
			-- Falling. Cubed alpha: a visible hitch, then real acceleration into the rock.
			local alpha = (sinceSwing - cfg.anticipationSeconds) / math.max(cfg.swingSeconds, 0.01)
			return cfg.anticipationOffset:Lerp(contactOffset, alpha * alpha * alpha)
		end
		if sinceSwing < cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds then
			-- Buried. The pause that makes the hit feel like it landed on something.
			return contactOffset
		end
		if sinceSwing < cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds then
			local alpha = (sinceSwing - cfg.anticipationSeconds - cfg.swingSeconds - cfg.impactSeconds)
				/ math.max(cfg.reboundSeconds, 0.01)
			return contactOffset:Lerp(reboundOffset, 1 - (1 - alpha) * (1 - alpha))
		end
		local recoverStart = cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds
		if sinceSwing < recoverStart + cfg.recoverSeconds then
			local alpha = (sinceSwing - recoverStart) / math.max(cfg.recoverSeconds, 0.01)
			local target = if engaged then cfg.raisedOffset else cfg.restOffset
			return reboundOffset:Lerp(target, 1 - (1 - alpha) * (1 - alpha))
		end
	end

	if not engaged then
		return cfg.restOffset
	end

	-- Held ready, breathing. The draw at the top of the stance is the same lerp run once.
	local drawn = math.clamp((now - engagedAt) / math.max(cfg.raiseSeconds, 0.01), 0, 1)
	local bob = math.sin((now / math.max(cfg.bobSeconds, 0.01)) * math.pi * 2) * cfg.bobStuds
	local sway = math.sin((now / math.max(cfg.bobSeconds * 1.7, 0.01)) * math.pi * 2) * math.rad(cfg.swayDegrees)
	return cfg.restOffset:Lerp(cfg.raisedOffset, drawn) * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, sway)
end

-- Build the local ember shells for one deposit's seams. Client-only: these parts exist nowhere on
-- the server, cast no light, and are removed the moment the player walks away.
local function ensureGlow(model: Model): SeamGlow?
	local existing = seamGlows[model]
	if existing ~= nil then
		return existing
	end
	local glowCfg = Config.Mining.visual.glow
	local shells: { BasePart } = {}
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") or child.Name ~= "WaxSeam" then
			continue
		end
		local shell = Instance.new("Part")
		shell.Name = "WickSeamEmber"
		-- `thickness` insets (it is configured negative): clamp per-axis so an unusually thin seam
		-- can never collapse the shell to a zero or negative size.
		local grown = child.Size + Vector3.one * glowCfg.thickness
		shell.Size = Vector3.new(math.max(grown.X, 0.05), math.max(grown.Y, 0.05), math.max(grown.Z, 0.05))
		shell.CFrame = child.CFrame
		shell.Color = glowCfg.color
		shell.Material = Enum.Material.Neon
		shell.Transparency = 1
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.Parent = child
		table.insert(shells, shell)
	end
	if #shells == 0 then
		return nil
	end
	local glow: SeamGlow = { shells = shells, alpha = 0 }
	seamGlows[model] = glow
	return glow
end

local function destroyGlow(model: Model)
	local glow = seamGlows[model]
	if glow == nil then
		return
	end
	seamGlows[model] = nil
	for _, shell in glow.shells do
		shell:Destroy()
	end
end

-- The proximity ember. Deliberately a slight warmth that rises as you close on a seam, not a marker
-- that shows through the dark: at range it is nothing, and even at the rock it stays mostly
-- transparent. It exists so a deposit reads as "that is wax" once you are near it — never so it can
-- be spotted across a room, which would undo the whole point of a cave you have to search.
local function updateGlow(origin: Vector3?, dt: number)
	local glowCfg = Config.Mining.visual.glow
	local attributes = MiningVisualProtocol.attributes
	local seen: { [Model]: boolean } = {}

	if origin ~= nil then
		for _, tagged in CollectionService:GetTagged(MiningVisualProtocol.depositTag) do
			local model = tagged :: Model
			local root = model.PrimaryPart
			-- A spent seam has no wax left to catch the light, and a deposit on another floor is
			-- behind solid rock.
			if
				root == nil
				or root:GetAttribute(attributes.depleted) == true
				or root:GetAttribute(attributes.depth) ~= currentDepth
			then
				continue
			end
			local distance = (root.Position - origin).Magnitude
			if distance > glowCfg.range then
				continue
			end
			local glow = ensureGlow(model)
			if glow == nil then
				continue
			end
			seen[model] = true
			-- 0 at the edge of range, 1 from `nearDistance` in.
			local closeness =
				math.clamp((glowCfg.range - distance) / math.max(glowCfg.range - glowCfg.nearDistance, 0.01), 0, 1)
			local step = math.clamp(dt * glowCfg.fadePerSecond, 0, 1)
			glow.alpha += (closeness - glow.alpha) * step
			local transparency = 1 - glow.alpha * (1 - glowCfg.minTransparency)
			for _, shell in glow.shells do
				local seam = shell.Parent
				local remaining = if seam ~= nil and seam:IsA("BasePart") then 1 - seam.Transparency else 0
				shell.Transparency = 1 - (1 - transparency) * remaining
			end
		end
	end

	for model in seamGlows do
		if not seen[model] then
			destroyGlow(model)
		end
	end
end

-- A handful of local stone/wax chips sells contact at the seam. They are collision-neutral,
-- short-lived, and never cross the server boundary, so they cannot become a hazard or resource.
local function emitImpactDebris(root: BasePart, accuracy: string, shardWax: boolean?)
	local feedback = Config.Mining.feedback
	local rng = Random.new(math.floor(Workspace:GetServerTimeNow() * 1000) % 2147483647)
	local surface = root.CFrame:PointToWorldSpace(Vector3.new(0, root.Size.Y * 0.08, -root.Size.Z * 0.52))
	-- The exposed seam is built on local -Z, which is the root's LookVector in world space.
	local outward = root.CFrame.LookVector
	local count = math.max(0, math.floor(feedback.impactDebrisCount))
	if accuracy == "Miss" then
		count = math.max(2, math.floor(count * 0.55))
	end

	for index = 1, count do
		local size = rng:NextNumber(feedback.impactDebrisSizeMin, feedback.impactDebrisSizeMax)
		local chip = Instance.new("Part")
		chip.Name = "WickMineChip"
		chip.Size = Vector3.new(size * rng:NextNumber(0.7, 1.4), size, size * rng:NextNumber(0.7, 1.4))
		chip.CFrame = CFrame.new(surface + Vector3.new(rng:NextNumber(-0.45, 0.45), rng:NextNumber(-0.2, 0.45), 0))
			* CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi))
		local isWax = shardWax == true and index % 3 == 0
		chip.Color = if isWax then Config.Mining.visual.waxDeepColor else Config.Mining.visual.rockAccent
		chip.Material = if isWax then Enum.Material.SmoothPlastic else Enum.Material.Slate
		chip.Anchored = false
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CastShadow = false
		chip.Parent = Workspace
		chip.AssemblyLinearVelocity = outward
				* rng:NextNumber(feedback.impactDebrisSpeed * 0.55, feedback.impactDebrisSpeed)
			+ root.CFrame.RightVector * rng:NextNumber(
				-feedback.impactDebrisSpeed * 0.45,
				feedback.impactDebrisSpeed * 0.45
			)
			+ Vector3.yAxis * rng:NextNumber(feedback.impactDebrisUpSpeed * 0.45, feedback.impactDebrisUpSpeed)
		chip.AssemblyAngularVelocity =
			Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		Debris:AddItem(chip, feedback.impactDebrisLifetime)
	end
end

local function claimBreakPresentation(target: BasePart?): boolean
	if target == nil then
		return true
	end
	if presentedBreaks[target] == true then
		return false
	end
	presentedBreaks[target] = true
	return true
end

local function characterPosition(): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character.PrimaryPart
	return if root ~= nil then root.Position else nil
end

local function canSeeDeposit(model: Model, root: BasePart): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end
	local offset = root.Position - camera.CFrame.Position
	local distance = offset.Magnitude
	if distance <= 1e-3 then
		return true
	end
	if camera.CFrame.LookVector:Dot(offset / distance) < Config.Mining.deposit.promptViewDot then
		return false
	end
	if not Config.Mining.deposit.requiresLineOfSight then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	params.FilterDescendantsInstances = if character ~= nil then { character } else {}
	params.IgnoreWater = false
	local hit = Workspace:Raycast(camera.CFrame.Position, offset, params)
	return hit == nil or hit.Instance:IsDescendantOf(model)
end

-- Nearest eligible deposit that is both in reach and being examined. The server repeats reach and
-- obstruction checks authoritatively; this view cone only keeps prompts attached to what the player
-- is actually looking at.
local function findNearestDeposit(): BasePart?
	local origin = characterPosition()
	if origin == nil then
		return nil
	end
	local attributes = MiningVisualProtocol.attributes
	local range = Config.Mining.deposit.interactionRange
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, tagged in CollectionService:GetTagged(MiningVisualProtocol.depositTag) do
		if not tagged:IsA("Model") then
			continue
		end
		local model = tagged :: Model
		local root = model.PrimaryPart
		if root == nil or root:GetAttribute(attributes.depleted) == true then
			continue
		end
		if root:GetAttribute(attributes.depth) ~= currentDepth then
			continue
		end
		local distance = (root.Position - origin).Magnitude
		if distance <= range and distance < bestDistance and canSeeDeposit(model, root) then
			best = root
			bestDistance = distance
		end
	end
	return best
end

local function setHint(text: string?, color: Color3?)
	local hint = hintLabel
	if hint == nil then
		return
	end
	hintGeneration += 1
	local generation = hintGeneration
	if text == nil then
		local fade = UITheme.tween(
			hint,
			TweenInfo.new(qteConfig.exitSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1 }
		)
		fade.Completed:Connect(function()
			if hintGeneration == generation then
				hint.Visible = false
			end
		end)
		return
	end
	hint.Text = text
	hint.TextColor3 = color or palette.textDim
	if not hint.Visible then
		hint.TextTransparency = 1
	end
	hint.Visible = true
	UITheme.tween(
		hint,
		TweenInfo.new(qteConfig.enterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0.04 }
	)
end

local function showStanceDisplay()
	local ring = ringFrame
	if ring == nil then
		return
	end
	ringVisibilityGeneration += 1
	ring.Visible = true
	ring.GroupTransparency = 1
	local scale = ringScale
	if scale ~= nil then
		scale.Scale = qteConfig.enterScale
		UITheme.tween(
			scale,
			TweenInfo.new(qteConfig.enterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
	end
	UITheme.tween(
		ring,
		TweenInfo.new(qteConfig.enterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	)
end

-- Local teardown of the stance display. The server has already decided the stance is over (or is
-- about to be told it should be); a short accelerating fade prevents the interface snapping away.
local function endStanceDisplay()
	sweepStartedAt = nil
	engagedRoot = nil
	engagedRow = nil
	perfectStreak = 0
	local ring = ringFrame
	if ring ~= nil then
		ringVisibilityGeneration += 1
		local generation = ringVisibilityGeneration
		local fade = UITheme.tween(
			ring,
			TweenInfo.new(qteConfig.exitSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1 }
		)
		fade.Completed:Connect(function()
			if ringVisibilityGeneration == generation and sweepStartedAt == nil then
				ring.Visible = false
			end
		end)
	end
end

local function requestDisengage()
	if sweepStartedAt == nil and not engagePending then
		return
	end
	-- Stop drawing immediately rather than waiting for the round trip: the player asked to leave, and
	-- a stance that lingers for 60 ms after they pressed W feels like the game arguing with them.
	requestGeneration += 1
	engagePending = false
	strikePending = false
	endStanceDisplay()
	Remotes.get("MineStrike"):FireServer("disengage")
end

local function actionLabel(): string
	if sweepStartedAt ~= nil then
		if UserInputService.TouchEnabled then
			return "STOP TO RELEASE"
		elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
			return "[B] RELEASE"
		end
		return "[Q] RELEASE"
	end
	local row = if activeRoot ~= nil
		then MiningRules.rowById(activeRoot:GetAttribute(MiningVisualProtocol.attributes.rowId))
		else nil
	local seamName = string.upper(if row ~= nil then row.displayName else "WAX SEAM")
	if UserInputService.TouchEnabled then
		return "MINE " .. seamName
	elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		return "[RT]  MINE " .. seamName
	end
	return "[LMB]  MINE " .. seamName
end

local function visualImpactTime(): number
	local cfg = Config.Mining.pickaxe
	return swingStartedAt + cfg.anticipationSeconds + cfg.swingSeconds
end

local function visualSwingEndsAt(): number
	local cfg = Config.Mining.pickaxe
	return swingStartedAt
		+ cfg.anticipationSeconds
		+ cfg.swingSeconds
		+ cfg.impactSeconds
		+ cfg.reboundSeconds
		+ cfg.recoverSeconds
end

local function pickaxeAimAdjustment(camera: Camera, now: number): CFrame
	local cfg = Config.Mining.pickaxe
	local target = if now < visualSwingEndsAt() then swingTarget else engagedRoot or activeRoot
	if target == nil or target.Parent == nil then
		return CFrame.identity
	end
	local viewportPoint, visible = camera:WorldToViewportPoint(target.Position)
	local viewport = camera.ViewportSize
	if not visible or viewportPoint.Z <= 0 or viewport.X <= 0 or viewport.Y <= 0 then
		return CFrame.identity
	end

	local screenX = math.clamp((viewportPoint.X / viewport.X - 0.5) * 2, -1, 1)
	local screenY = math.clamp((viewportPoint.Y / viewport.Y - 0.5) * 2, -1, 1)
	local adjustment = CFrame.new(screenX * cfg.aimScreenOffsetStuds.X, -screenY * cfg.aimScreenOffsetStuds.Y, 0)
		* CFrame.Angles(math.rad(-screenY * cfg.aimPitchDegrees), math.rad(-screenX * cfg.aimYawDegrees), 0)

	local idle = if sweepStartedAt ~= nil then cfg.idleAimFraction else 0
	local elapsed = now - swingStartedAt
	local weight = idle
	if elapsed >= 0 then
		if elapsed < cfg.anticipationSeconds then
			local alpha = elapsed / math.max(cfg.anticipationSeconds, 0.01)
			weight = idle + (1 - idle) * alpha * alpha
		elseif elapsed < cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds then
			weight = 1
		elseif elapsed < cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds then
			local alpha = (elapsed - cfg.anticipationSeconds - cfg.swingSeconds - cfg.impactSeconds)
				/ math.max(cfg.reboundSeconds, 0.01)
			weight = 1 + (0.45 - 1) * alpha
		elseif elapsed < visualSwingEndsAt() - swingStartedAt then
			local recoverStart = cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds
			local alpha = (elapsed - recoverStart) / math.max(cfg.recoverSeconds, 0.01)
			weight = 0.45 + (idle - 0.45) * alpha
		end
	end
	return CFrame.new():Lerp(adjustment, math.clamp(weight, 0, 1))
end

local function onStrikeInput(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not controlsBound or inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if engagePending or strikePending then
		return Enum.ContextActionResult.Sink
	end

	-- Already working a seam: this click is a strike. The down-stroke starts NOW — locally, on the
	-- input — while the server decides what it was worth.
	local startedAt = sweepStartedAt
	if startedAt ~= nil then
		local now = Workspace:GetServerTimeNow()
		-- Clicks during the recovery are swallowed here rather than sent. The gate is the server's own
		-- next-sweep stamp, so the client and the server agree about when a strike is possible without
		-- the client keeping a second cooldown of its own — and a masher cannot burn through the
		-- remote's rate limit and lose a legitimate strike to a throttle.
		if now < startedAt then
			return Enum.ContextActionResult.Sink
		end
		strikePending = true
		requestGeneration += 1
		local generation = requestGeneration
		swingStartedAt = now
		swingAccuracy = nil
		swingDepleted = false
		swingReleasedWax = false
		swingTarget = engagedRoot
		AudioCues.play("MineSwing", 0.94 + math.random() * 0.1)
		-- Shared-clock click time is accepted only through MiningRules' server-side rewind clamp.
		Remotes.get("MineStrike"):FireServer("strike", now)
		task.delay(qteConfig.requestTimeoutSeconds, function()
			if requestGeneration == generation then
				strikePending = false
			end
		end)
		return Enum.ContextActionResult.Sink
	end

	local root = activeRoot
	if root == nil then
		-- Nothing in reach: let the input through so a bound left click is never swallowed away from
		-- a deposit. Mining must not make the rest of the game feel unresponsive.
		return Enum.ContextActionResult.Pass
	end
	engagePending = true
	requestGeneration += 1
	local generation = requestGeneration
	Remotes.get("MineStrike"):FireServer("engage", root)
	task.delay(qteConfig.requestTimeoutSeconds, function()
		if requestGeneration == generation then
			engagePending = false
		end
	end)
	return Enum.ContextActionResult.Sink
end

local function onExitInput(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or (sweepStartedAt == nil and not engagePending) then
		return Enum.ContextActionResult.Pass
	end
	requestDisengage()
	return Enum.ContextActionResult.Sink
end

local function styleTouchButton(actionName: string)
	local button = ContextActionService:GetButton(actionName)
	if button == nil or button:GetAttribute("WickMiningStyled") == true then
		return
	end
	button:SetAttribute("WickMiningStyled", true)
	button.AutoButtonColor = false
	button.ImageTransparency = 1
	button.BackgroundColor3 = palette.panel
	button.BackgroundTransparency = 0.16
	button.Size = UDim2.fromOffset(108, 48)
	UITheme.corner(button, 8)
	UITheme.stroke(button, palette.strokeSoft, 1, 0.28)
	for _, descendant in button:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.Font = UITheme.font.heading
			descendant.TextColor3 = palette.gold
			descendant.TextSize = 12
			descendant.TextScaled = false
			descendant.TextStrokeColor3 = palette.void
			descendant.TextStrokeTransparency = 0.55
		end
	end
	local scale = UITheme.scale(button, 1)
	button.MouseButton1Down:Connect(function()
		UITheme.tween(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		UITheme.tween(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
	end)
end

local function bindControls()
	if controlsBound then
		return
	end
	controlsBound = true
	-- One action, three surfaces: left click, a touch button, and the right trigger. All three are a
	-- single press, so the interaction is identical on every platform rather than a keyboard mechanic
	-- with a mobile approximation bolted beside it.
	ContextActionService:BindAction(
		ACTION_NAME,
		onStrikeInput,
		true,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	-- An explicit way out that is not a movement key: Q on keyboard, right click as a second desktop
	-- option, and B on a controller. Movement keys are handled by polling instead (see `update`), so
	-- mining never steals one — this is for a player who wants to stop mining without walking away.
	ContextActionService:BindAction(
		EXIT_ACTION_NAME,
		onExitInput,
		true,
		Enum.KeyCode.Q,
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.ButtonB
	)
	if UserInputService.TouchEnabled then
		ContextActionService:SetTitle(ACTION_NAME, "MINE")
		ContextActionService:SetPosition(ACTION_NAME, UDim2.new(1, -150, 1, -230))
		ContextActionService:SetTitle(EXIT_ACTION_NAME, "STOP")
		ContextActionService:SetPosition(EXIT_ACTION_NAME, UDim2.new(1, -150, 1, -150))
		task.defer(function()
			styleTouchButton(ACTION_NAME)
			styleTouchButton(EXIT_ACTION_NAME)
		end)
		task.delay(0.15, function()
			styleTouchButton(ACTION_NAME)
			styleTouchButton(EXIT_ACTION_NAME)
		end)
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	controlsBound = false
	ContextActionService:UnbindAction(ACTION_NAME)
	ContextActionService:UnbindAction(EXIT_ACTION_NAME)
	requestGeneration += 1
	presentationLifetimeGeneration += 1
	table.clear(presentedBreaks)
	engagePending = false
	strikePending = false
	endStanceDisplay()
	destroyPickaxe()
	updateGlow(nil, 1)
end

-- Has the player asked to move? While engaged their walk speed is zero, so this is the only thing
-- that makes "walking away" work — and it is why the lock can never trap anyone: the same key that
-- would have moved them releases them, on the frame they press it.
local function wantsToLeave(): boolean
	for _, key in EXIT_KEYS do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		local move = UserInputService:GetGamepadState(gamepad)
		for _, input in move do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.25 then
				return true
			end
		end
	end
	return false
end

local function refreshControls()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		bindControls()
	else
		unbindControls()
	end
end

local function update(dt: number)
	local prompt = promptLabel
	if prompt == nil then
		return
	end
	if not controlsBound then
		prompt.Visible = false
		promptAlpha = 0
		return
	end

	local origin = characterPosition()
	updateGlow(origin, dt)

	-- Any movement input ends the stance before anything else this frame is decided.
	if (sweepStartedAt ~= nil or engagePending) and wantsToLeave() then
		requestDisengage()
	end

	local engaged = sweepStartedAt ~= nil
	activeRoot = findNearestDeposit()
	local inReach = activeRoot ~= nil
	-- Once engaged, the strike rail owns the tiny release reminder. Keeping the approach prompt
	-- up over the QTE was most of what made mining read as a detached task screen.
	local showPrompt = inReach and not engaged and not engagePending
	local promptTarget = if showPrompt then 1 else 0
	local promptStep = math.clamp(dt / math.max(qteConfig.enterSeconds, 0.01), 0, 1)
	promptAlpha += (promptTarget - promptAlpha) * promptStep
	prompt.Visible = showPrompt or promptAlpha > 0.01
	prompt.TextTransparency = 1 - promptAlpha * 0.96
	if inReach then
		prompt.Text = actionLabel()
	end
	local now = Workspace:GetServerTimeNow()
	setPickaxeVisible(inReach or engaged or engagePending or now < visualSwingEndsAt())
	updatePickaxeVisibility(dt)

	local camera = Workspace.CurrentCamera
	local built = pickaxeModel
	if built ~= nil and camera ~= nil then
		local cfg = Config.Mining.pickaxe
		local base = camera.CFrame * pickaxeAimAdjustment(camera, now) * pickaxeOffset(now)
		built:PivotTo(base)
		local trail = built:FindFirstChild("SwingTrail", true)
		if trail ~= nil and trail:IsA("Trail") then
			local sinceSwing = now - swingStartedAt
			trail.Enabled = sinceSwing >= cfg.anticipationSeconds * 0.45
				and sinceSwing <= cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds
		end
	end

	local ring = ringFrame
	local marker = ringMarker
	local startedAt = sweepStartedAt
	if ring == nil or marker == nil then
		return
	end
	if startedAt == nil then
		return
	end

	-- The fumble jolt. Decays back to the configured base position; harmless to compute
	-- every frame since it is a no-op the instant `shakeUntil` is in the past.
	local nowLocal = os.clock()
	if nowLocal < shakeUntil then
		local remaining = shakeUntil - nowLocal
		local decay = remaining / qteConfig.shakeDuration
		local wobble = math.sin(nowLocal * 55) * qteConfig.shakeMagnitudePixels * decay
		ring.Position = RING_BASE_POSITION + UDim2.fromOffset(wobble, 0)
	else
		ring.Position = RING_BASE_POSITION
	end

	-- The sweep is evaluated continuously from the server's stamp. `nil` means the recovery/wind-up
	-- is still running, so the marker rests at the start rather than teleporting.
	local phase = MiningRules.sweepPhase(now - startedAt)
	marker.Position = UDim2.new(displayPhase(phase or 0), 0, 0.5, 0)
	marker.Rotation = 0
	marker.BackgroundTransparency = if phase == nil then 0.55 else 0

	local control = ringControl
	if control ~= nil then
		control.Text = actionLabel()
	end
	local result = ringResult
	if result ~= nil and nowLocal >= resultUntil then
		result.Text = if phase == nil then "SETTLE" else "STRIKE"
		result.TextColor3 = if phase == nil then palette.textDim else palette.textMuted
		result.TextTransparency = if phase == nil then 0.48 else 0.28
	end
end

function MiningController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickMining"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	buildRing(gui)
	buildPrompt(gui)
	buildCargo(gui)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Adopt a sweep the server has just published: when it starts and where its band sits. Both
	-- numbers are the server's; this file only draws them.
	local function adoptSweep(payload: { [string]: any })
		local startedAt = tonumber(payload.startedAt)
		if startedAt == nil then
			return
		end
		sweepStartedAt = startedAt
		bandCenter = tonumber(payload.bandCenter) or bandCenter
		paintRing(bandCenter)
	end

	-- Mining audio plays AT the seam, not at the player's head. The rock is what is making the noise,
	-- and hearing it come from a point in the world is most of why a strike lands as a physical event.
	local function playAtSeam(cueName: string, pitchMultiplier: number?, target: BasePart?)
		local root = target or engagedRoot
		if root ~= nil and root.Parent ~= nil then
			AudioCues.playAt(cueName, root, pitchMultiplier)
			return
		end
		AudioCues.play(cueName, pitchMultiplier)
	end

	local function clearHintLater(seconds: number)
		local generation = hintGeneration
		task.delay(seconds, function()
			if hintGeneration == generation then
				setHint(nil)
			end
		end)
	end

	Remotes.get("MineState").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		-- any: remote payloads are untyped at the boundary; every field is read defensively.
		if kind == "engaged" then
			requestGeneration += 1
			engagePending = false
			strikePending = false
			engagedAt = Workspace:GetServerTimeNow()
			-- Clear any lingering strike animation so the pick draws from rest, not from the rock.
			swingStartedAt = -math.huge
			swingAccuracy = nil
			swingDepleted = false
			swingReleasedWax = false
			perfectStreak = 0
			resultUntil = -math.huge
			local depositInstance = payload.deposit
			engagedRoot = if typeof(depositInstance) == "Instance" and depositInstance:IsA("BasePart")
				then depositInstance
				else nil
			swingTarget = engagedRoot
			-- The row decides how many clean strikes this seam takes, so every "N clean left" readout has to
			-- be measured against THIS seam rather than against the Standard three. A rail that promised
			-- three swings on a nine-swing Deep Seam would simply be lying to the player.
			engagedRow = if engagedRoot ~= nil
				then MiningRules.rowById(engagedRoot:GetAttribute(MiningVisualProtocol.attributes.rowId))
				else nil
			adoptSweep(payload)
			showStanceDisplay()
			AudioCues.play("MineEngage")
			local seamName = if engagedRow ~= nil then string.upper(engagedRow.displayName) else "WAX SEAM"
			setHint(seamName .. "  ·  STRIKE THE BRIGHT CORE", palette.textMuted)
			clearHintLater(2.2)
		elseif kind == "strikeResolved" then
			requestGeneration += 1
			local presentationGeneration = requestGeneration
			strikePending = false
			local accuracy = tostring(payload.accuracy or "Miss")
			local releasedWax = (tonumber(payload.shardWax) or 0) > 0
			swingAccuracy = accuracy
			swingDepleted = false
			swingReleasedWax = releasedWax
			local target = engagedRoot
			local progress = tonumber(payload.progress) or 0
			local feedback = Config.Mining.feedback
			if accuracy == "Perfect" then
				perfectStreak += 1
			else
				perfectStreak = 0
			end
			local streakAtImpact = perfectStreak
			-- Adopt the authoritative next sweep immediately, but hold all contact presentation until
			-- the local pick head actually reaches the rock. Latency changes neither score nor sync.
			adoptSweep(payload)
			local delaySeconds = math.max(0, visualImpactTime() - Workspace:GetServerTimeNow())
			task.delay(delaySeconds, function()
				if requestGeneration ~= presentationGeneration then
					return
				end
				perfectStreak = streakAtImpact
				playRingHit(accuracy)
				playAtSeam("MineStrikeImpact", 0.93 + math.random() * 0.14, target)
				if target ~= nil and target.Parent ~= nil then
					emitImpactDebris(target, accuracy, releasedWax)
				end
				if accuracy == "Perfect" then
					local pitch = math.min(1 + (streakAtImpact - 1) * feedback.comboPitchStep, feedback.comboPitchMax)
					playAtSeam("MineStrikePerfect", pitch, target)
					setHint(
						string.format(
							"PERFECT BITE  ·  %d CLEAN STRIKES REMAIN",
							MiningRules.cleanStrikesRemaining(progress, engagedRow)
						),
						palette.gold
					)
				elseif accuracy == "Miss" then
					playAtSeam("MineStrikeFumble", nil, target)
					setHint("GLANCE  ·  LOUDER, LESS PROGRESS", palette.danger)
				else
					playAtSeam("MineStrikeClean", nil, target)
					setHint(
						string.format(
							"SOLID BITE  ·  %d CLEAN STRIKES REMAIN",
							MiningRules.cleanStrikesRemaining(progress, engagedRow)
						),
						palette.ember
					)
				end
				clearHintLater(feedback.hintSeconds)
				task.delay(Config.Mining.pickaxe.impactSeconds + Config.Mining.pickaxe.reboundSeconds * 0.35, function()
					if requestGeneration == presentationGeneration then
						AudioCues.play("MineRecover", 0.96 + math.random() * 0.08)
					end
				end)
			end)
		elseif kind == "disengaged" then
			requestGeneration += 1
			engagePending = false
			strikePending = false
			endStanceDisplay()
			-- A refusal is silent unless it is one the player can act on. "Out of range" and
			-- "cooldown" are self-evident from the world; being unlit or cupped is not.
			local reason = tostring(payload.reason or "")
			if reason == "NotLit" then
				setHint("You cannot work a seam in the dark.", palette.danger)
				clearHintLater(2.2)
			elseif reason == "Covered" then
				setHint("Uncover the flame to mine.", palette.danger)
				clearHintLater(2.2)
			elseif reason == "TooDim" then
				setHint("This seam needs maximum flame or a FLARE.", palette.danger)
				clearHintLater(2.4)
			elseif reason == "Obstructed" then
				setHint("Get a clear face on the seam.", palette.danger)
				clearHintLater(2.2)
			end
		elseif kind == "depleted" then
			requestGeneration += 1
			local expectedLifetime = presentationLifetimeGeneration
			engagePending = false
			strikePending = false
			swingDepleted = true
			local target = engagedRoot
			local delaySeconds = math.max(0, visualImpactTime() - Workspace:GetServerTimeNow())
			endStanceDisplay()
			local granted = tonumber(payload.rawWaxGranted) or 0
			local carried = tonumber(payload.rawWaxCarried) or carriedRawWax
			local minedThisRun = tonumber(payload.minedThisRun) or 0
			task.delay(delaySeconds, function()
				if presentationLifetimeGeneration ~= expectedLifetime then
					return
				end
				if claimBreakPresentation(target) then
					playAtSeam("MineBreak", nil, target)
					if target ~= nil and target.Parent ~= nil then
						emitImpactDebris(target, swingAccuracy or "Good", swingReleasedWax)
					end
				end
				playBreakFlash()
				if granted > 0 then
					setCargo(carried, carried ~= carriedRawWax)
					setHint(string.format("+%d RAW WAX  ·  %d CARRIED", granted, carried), palette.gold)
				else
					setHint(string.format("SEAM OPEN  ·  %d THIS RUN", minedThisRun), palette.gold)
				end
				clearHintLater(2.6)
			end)
		end
	end)

	-- The authoritative cargo total. `depleted` pulses the readout the instant a seam breaks; this is
	-- what keeps it honest afterwards — including the drop to zero on extraction or death.
	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId == player.UserId then
				local total = tonumber(entry.rawWax) or 0
				if total ~= carriedRawWax then
					setCargo(total, total > carriedRawWax)
				end
				break
			end
		end
	end)

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind == "mineImpact" then
			if tonumber(payload.strikerId) == player.UserId then
				return
			end
			local target = if typeof(payload.deposit) == "Instance" and payload.deposit:IsA("BasePart")
				then payload.deposit :: BasePart
				else nil
			local origin = characterPosition()
			if
				target == nil
				or origin == nil
				or (target.Position - origin).Magnitude > Config.Mining.feedback.impactPresentationRange
			then
				return
			end
			local accuracy = tostring(payload.accuracy or "Miss")
			if payload.depleted == true then
				if claimBreakPresentation(target) then
					playAtSeam("MineBreak", nil, target)
					emitImpactDebris(target, accuracy, payload.shardWax == true)
				end
			else
				playAtSeam("MineStrikeImpact", nil, target)
				if accuracy == "Perfect" then
					playAtSeam("MineStrikePerfect", nil, target)
				elseif accuracy == "Good" then
					playAtSeam("MineStrikeClean", nil, target)
				else
					playAtSeam("MineStrikeFumble", nil, target)
				end
				emitImpactDebris(target, accuracy, payload.shardWax == true)
			end
		elseif kind == "floor" then
			currentDepth = tonumber(payload.depth) or 0
			table.clear(presentedBreaks)
			requestGeneration += 1
			presentationLifetimeGeneration += 1
			engagePending = false
			strikePending = false
			endStanceDisplay()
			setHint(nil)
		elseif kind == "countdown" then
			currentDepth = 0
			table.clear(presentedBreaks)
			requestGeneration += 1
			presentationLifetimeGeneration += 1
			engagePending = false
			strikePending = false
			endStanceDisplay()
			setCargo(0, false)
		end
	end)

	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)
	RunService.RenderStepped:Connect(update)
end

return MiningController

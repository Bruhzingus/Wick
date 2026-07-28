--!strict
-- Mining input and presentation. Finds the deposit in reach, puts a pickaxe in the player's hands,
-- takes the clicks, draws the timing ring, and shows what has been carried out of the rock. It
-- decides NOTHING: the server owns whether a stance may open, when each sweep began, where its band
-- sits, what a strike was worth, and when the seam breaks.
--
-- THE LOOP, from this side: click a seam to ENGAGE — you plant, the pick comes up over your
-- shoulder, and a marker starts sweeping a ring. Every click after that is a STRIKE scored where the
-- marker is. Strike, the pick recovers, the band has moved, read it again. Any movement key, a right
-- click, or the seam breaking ends the stance.
--
-- The ring is reconstructed, never replicated. The server sends a `startedAt` stamp in
-- Workspace:GetServerTimeNow() space plus the band's centre, and this file evaluates
-- Logic/MiningRules against them — the same pure function the server scores the strike with. That is
-- why the band a player aims at and the band they are judged against cannot drift apart, and why no
-- ring position ever crosses the wire.
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
-- The live stance, mirrored from the server. Non-nil means the ring is up and the pick is ready.
local sweepStartedAt: number? = nil
local bandCenter = Config.Mining.timing.perfectCenter
local engagedRoot: BasePart? = nil
-- Consecutive Perfects. Drives the audio ladder and nothing else — it is not a score, it is not
-- replicated, and it buys the player no progress.
local perfectStreak = 0
-- Local-only animation clock. Set on the CLICK so anticipation and the down-stroke start instantly,
-- then left alone. The server reply times impact feedback against this predicted visual contact.
local swingStartedAt = -math.huge
local engagedAt = 0

-- Where the ring sits when it is not being shaken. Read by the per-frame shake offset in `update`.
local RING_BASE_POSITION = qteConfig.position
-- A fumble jolts the ring instead of just changing a colour, so a miss is felt as well as seen. Local
-- animation clock only — cosmetic, so it runs on os.clock() rather than the shared server clock.
local shakeUntil = -math.huge

local ringFrame: Frame? = nil
local ringScale: UIScale? = nil
local ringMarker: Frame? = nil
local ringMarkerScale: UIScale? = nil
local ringBurst: Frame? = nil
local ringBurstScale: UIScale? = nil
local ringResult: TextLabel? = nil
local ringResultScale: UIScale? = nil
local ringControl: TextLabel? = nil
local resultUntil = -math.huge
local ringSegments: { Frame } = {}
local ringBandCenter = -1
-- The break flash. Deliberately NOT a child of the ring: `depleted` tears the ring down on the same
-- frame it fires, and a burst parented to a frame that just went invisible never gets to be seen.
local breakFlash: Frame? = nil
local breakFlashScale: UIScale? = nil
local promptLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local cargoPanel: Frame? = nil
local cargoValue: TextLabel? = nil
local cargoScale: UIScale? = nil
local carriedRawWax = 0

local pickaxeModel: Model? = nil

-- Local amber ember shells, one per wax seam of every nearby deposit. Client-only presentation:
-- built on approach, faded by distance, destroyed when you walk away.
type SeamGlow = { shells: { BasePart }, alpha: number }
local seamGlows: { [Model]: SeamGlow } = {}

-- Which of the pure bands this ring segment sits in, for a given band centre. Drawn from
-- MiningRules, so recolouring the ring never means restating the windows.
local function segmentColor(phase: number, center: number): (Color3, number)
	local accuracy = MiningRules.accuracyForPhase(phase, center)
	if accuracy == "Perfect" then
		return palette.gold, 0
	elseif accuracy == "Good" then
		return palette.emberDeep, 0.25
	end
	return palette.strokeSoft, 0.72
end

-- Maps the server's circular 0..1 phase onto a broken-open overhand arc. The endpoints still wrap
-- exactly like the rule does; opening the bottom changes only the silhouette, not the score.
local function phaseAngle(phase: number): number
	return qteConfig.arcStartDegrees + phase * qteConfig.arcSpanDegrees
end

-- Repaint the target arc wherever the band has moved to. Cheap enough to do once per strike, and it
-- is the only way the player can see the band wander.
local function paintRing(center: number)
	if math.abs(center - ringBandCenter) < 1e-4 then
		return
	end
	ringBandCenter = center
	for index, dot in ringSegments do
		local phase = (index - 1) / qteConfig.segmentCount
		local color, transparency = segmentColor(phase, center)
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = transparency
		local accuracy = MiningRules.accuracyForPhase(phase, center)
		local size = if accuracy == "Perfect"
			then qteConfig.perfectSegmentSize
			elseif accuracy == "Good" then qteConfig.goodSegmentSize
			else qteConfig.restSegmentSize
		dot.Size = UDim2.fromOffset(size.X, size.Y)
	end
end

local function buildRing(parent: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "MiningRing"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = RING_BASE_POSITION
	frame.Size = UDim2.fromOffset(qteConfig.radiusPixels * 2 + 54, qteConfig.radiusPixels * 2 + 54)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	ringScale = UITheme.scale(frame, 1)

	-- A faint stone disc gives the lit arc contrast without becoming an opaque task panel.
	local backing = Instance.new("Frame")
	backing.Name = "Backing"
	backing.AnchorPoint = Vector2.new(0.5, 0.5)
	backing.Position = UDim2.fromScale(0.5, 0.5)
	backing.Size = UDim2.fromOffset(94, 94)
	backing.BackgroundColor3 = palette.void
	backing.BackgroundTransparency = 0.58
	backing.BorderSizePixel = 0
	backing.ZIndex = 0
	backing.Parent = frame
	UITheme.corner(backing, 47)
	UITheme.stroke(backing, palette.strokeSoft, 1, 0.68)

	for index = 1, qteConfig.segmentCount do
		local phase = (index - 1) / qteConfig.segmentCount
		local angleDegrees = phaseAngle(phase)
		local angle = math.rad(angleDegrees)
		local dot = Instance.new("Frame")
		dot.Name = "Segment"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position =
			UDim2.new(0.5, math.cos(angle) * qteConfig.radiusPixels, 0.5, math.sin(angle) * qteConfig.radiusPixels)
		dot.Size = UDim2.fromOffset(qteConfig.restSegmentSize.X, qteConfig.restSegmentSize.Y)
		dot.BackgroundColor3 = palette.strokeSoft
		dot.BackgroundTransparency = 0.72
		dot.BorderSizePixel = 0
		dot.Rotation = angleDegrees + 90
		dot.ZIndex = 1
		dot.Parent = frame
		UITheme.corner(dot, 3)
		table.insert(ringSegments, dot)
	end
	paintRing(Config.Mining.timing.perfectCenter % 1)

	-- The hit ripple. One reusable frame parked at the marker's position and re-triggered every
	-- strike: it snaps to a small scale at full colour and expands away to nothing, so a hit reads as
	-- a burst of light at the exact point on the ring where it landed. Sits BEHIND the marker so the
	-- marker's own punch stays the sharpest thing on screen.
	local burst = Instance.new("Frame")
	burst.Name = "HitBurst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Size = UDim2.fromOffset(20, 20)
	burst.BackgroundColor3 = palette.gold
	burst.BackgroundTransparency = 1
	burst.BorderSizePixel = 0
	burst.ZIndex = 2
	burst.Parent = frame
	UITheme.corner(burst, 10)
	ringBurst = burst
	ringBurstScale = UITheme.scale(burst, 1)

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(qteConfig.markerSize.X, qteConfig.markerSize.Y)
	marker.BackgroundColor3 = palette.flameCore
	marker.BorderSizePixel = 0
	marker.ZIndex = 3
	marker.Parent = frame
	UITheme.corner(marker, 3)
	local markerGlow = UITheme.stroke(marker, palette.ember, 3, 0.35)
	markerGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ringMarker = marker
	ringMarkerScale = UITheme.scale(marker, 1)

	local result = Instance.new("TextLabel")
	result.Name = "StrikeRead"
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.fromScale(0.5, 0.46)
	result.Size = UDim2.fromOffset(116, 26)
	result.BackgroundTransparency = 1
	result.Font = UITheme.font.heading
	result.Text = "STRIKE"
	result.TextColor3 = palette.textMuted
	result.TextSize = 15
	result.TextTransparency = 0.15
	result.ZIndex = 4
	result.Parent = frame
	ringResult = result
	ringResultScale = UITheme.scale(result, 1)

	local control = Instance.new("TextLabel")
	control.Name = "ReleaseControl"
	control.AnchorPoint = Vector2.new(0.5, 0.5)
	control.Position = UDim2.fromScale(0.5, 0.61)
	control.Size = UDim2.fromOffset(130, 18)
	control.BackgroundTransparency = 1
	control.Font = UITheme.font.fine
	control.Text = "[Q] RELEASE"
	control.TextColor3 = palette.textDim
	control.TextSize = 11
	control.TextTransparency = 0.08
	control.ZIndex = 4
	control.Parent = frame
	ringControl = control

	ringFrame = frame

	-- Sits at the ring's own on-screen spot, parented to the GUI directly rather than to the ring
	-- frame, so it survives `endStanceDisplay` hiding the ring on the same frame the seam breaks.
	local flash = Instance.new("Frame")
	flash.Name = "MiningBreakFlash"
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = RING_BASE_POSITION
	flash.Size = UDim2.fromOffset(46, 46)
	flash.BackgroundColor3 = palette.gold
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Visible = false
	flash.Parent = parent
	UITheme.corner(flash, 23)
	breakFlash = flash
	breakFlashScale = UITheme.scale(flash, 1)
end

-- The bigger flash for the strike that actually breaks the seam. `strikeResolved` already gave the
-- final hit its ordinary accuracy pop (`playRingHit`); this is the extra, larger beat on top of it —
-- the moment reads as a small event rather than just another strike.
local function playBreakFlash()
	local flash = breakFlash
	local scale = breakFlashScale
	if flash == nil or scale == nil then
		return
	end
	flash.BackgroundTransparency = 0.05
	flash.Visible = true
	scale.Scale = 0.4
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local scaleTween = UITheme.tween(scale, info, { Scale = 3.6 })
	UITheme.tween(flash, info, { BackgroundTransparency = 1 })
	scaleTween.Completed:Connect(function()
		flash.Visible = false
	end)
end

-- Visual half of the hit feedback: a colour-and-size punch scaled to how well the strike landed, at
-- the exact point on the ring the marker was struck at. A Miss also jolts the whole ring — a fumble
-- should feel like it, not just look duller.
local function playRingHit(accuracy: string)
	local marker = ringMarker
	local burst = ringBurst
	local markerScale = ringMarkerScale
	local burstScale = ringBurstScale
	local result = ringResult
	local resultScale = ringResultScale
	if
		marker == nil
		or burst == nil
		or markerScale == nil
		or burstScale == nil
		or result == nil
		or resultScale == nil
	then
		return
	end

	local color: Color3
	local burstPeak: number
	local markerPeak: number
	local burstStartTransparency: number
	local resultText: string
	if accuracy == "Perfect" then
		color = palette.gold
		burstPeak = 2.7
		markerPeak = 1.75
		burstStartTransparency = 0.05
		resultText = if perfectStreak > 1 then string.format("PERFECT  x%d", perfectStreak) else "PERFECT"
	elseif accuracy == "Miss" then
		color = palette.danger
		burstPeak = 1.3
		markerPeak = 1.15
		burstStartTransparency = 0.4
		resultText = "GLANCED"
	else
		color = palette.ember
		burstPeak = 1.9
		markerPeak = 1.4
		burstStartTransparency = 0.15
		resultText = "GOOD BITE"
	end

	burst.Position = marker.Position
	burst.BackgroundColor3 = color
	burst.BackgroundTransparency = burstStartTransparency
	burstScale.Scale = 0.5
	local burstInfo = TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	UITheme.tween(burstScale, burstInfo, { Scale = burstPeak }):Play()
	UITheme.tween(burst, burstInfo, { BackgroundTransparency = 1 }):Play()

	markerScale.Scale = markerPeak
	UITheme.tween(markerScale, UITheme.motion.rise, { Scale = 1 }):Play()

	result.Text = resultText
	result.TextColor3 = color
	result.TextTransparency = 0
	resultScale.Scale = if accuracy == "Perfect" then 1.28 else 1.12
	UITheme.tween(resultScale, UITheme.motion.rise, { Scale = 1 }):Play()
	resultUntil = os.clock() + Config.Mining.feedback.hintSeconds

	local scale = ringScale
	if scale ~= nil then
		scale.Scale = if accuracy == "Perfect" then 1.08 else 1.035
		UITheme.tween(scale, UITheme.motion.rise, { Scale = 1 }):Play()
	end

	if accuracy == "Miss" then
		shakeUntil = os.clock() + qteConfig.shakeDuration
	end
end

local function buildPrompt(parent: ScreenGui)
	local label = Instance.new("TextLabel")
	label.Name = "MiningPrompt"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0.735)
	label.Size = UDim2.fromOffset(230, 36)
	label.BackgroundColor3 = palette.panel
	label.BackgroundTransparency = 0.34
	label.BorderSizePixel = 0
	label.Font = UITheme.font.heading
	label.TextSize = 14
	label.TextColor3 = palette.gold
	label.TextTransparency = 0.05
	label.Visible = false
	label.Parent = parent
	UITheme.corner(label, 8)
	UITheme.stroke(label, palette.strokeSoft, 1, 0.48)
	promptLabel = label

	local hint = Instance.new("TextLabel")
	hint.Name = "MiningHint"
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, 0.79)
	hint.Size = UDim2.fromOffset(360, 26)
	hint.BackgroundTransparency = 1
	hint.Font = UITheme.font.fine
	hint.TextSize = 14
	hint.TextColor3 = palette.textDim
	hint.Visible = false
	hint.Parent = parent
	hintLabel = hint
end

-- The carried-cargo readout (PHASE 7A). A COUNT, never a meter: no bar, no maximum, no drain — it
-- must not read as a second thing keeping you alive, because it does nothing of the sort. Hidden
-- entirely at zero, so a run that never mines never sees it.
local function buildCargo(parent: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Name = "RawWaxCargo"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -26, 0, 96)
	panel.Size = UDim2.fromOffset(150, 42)
	panel.BackgroundColor3 = palette.panel
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = parent
	UITheme.corner(panel, 8)
	UITheme.stroke(panel, palette.strokeSoft, 1, 0.4)
	cargoScale = UITheme.scale(panel, 1)

	-- A single amber lozenge, the same colour the seams glow. The icon and the rock share a palette
	-- so the readout needs no words to say what it is counting.
	local pip = Instance.new("Frame")
	pip.Name = "Pip"
	pip.AnchorPoint = Vector2.new(0, 0.5)
	pip.Position = UDim2.new(0, 12, 0.5, 0)
	pip.Size = UDim2.fromOffset(12, 18)
	pip.BackgroundColor3 = Config.Mining.visual.waxColor
	pip.BorderSizePixel = 0
	pip.Rotation = 12
	pip.Parent = panel
	UITheme.corner(pip, 4)

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0, 0.5)
	caption.Position = UDim2.new(0, 32, 0.5, -7)
	caption.Size = UDim2.fromOffset(96, 12)
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.font.fine
	caption.Text = "RAW WAX"
	caption.TextSize = 11
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = palette.textDim
	caption.Parent = panel

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.Position = UDim2.new(0, 32, 0.5, 8)
	value.Size = UDim2.fromOffset(96, 18)
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
	carriedRawWax = total
	value.Text = tostring(total)
	panel.Visible = total > 0
	local scale = cargoScale
	if pulse and scale ~= nil and total > 0 then
		scale.Scale = Config.Mining.feedback.cargoPulseScale
		UITheme.tween(scale, UITheme.motion.rise, { Scale = 1 }):Play()
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
	return model
end

local function setPickaxeVisible(visible: boolean)
	if visible then
		if pickaxeModel == nil then
			local built = buildPickaxe()
			built.Parent = Workspace.CurrentCamera
			pickaxeModel = built
		end
		return
	end
	if pickaxeModel ~= nil then
		pickaxeModel:Destroy()
		pickaxeModel = nil
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

	if sinceSwing >= 0 then
		if sinceSwing < cfg.anticipationSeconds then
			local alpha = sinceSwing / math.max(cfg.anticipationSeconds, 0.01)
			return cfg.raisedOffset:Lerp(cfg.anticipationOffset, 1 - (1 - alpha) * (1 - alpha))
		end
		if sinceSwing < cfg.anticipationSeconds + cfg.swingSeconds then
			-- Falling. Cubed alpha: a visible hitch, then real acceleration into the rock.
			local alpha = (sinceSwing - cfg.anticipationSeconds) / math.max(cfg.swingSeconds, 0.01)
			return cfg.anticipationOffset:Lerp(cfg.strikeOffset, alpha * alpha * alpha)
		end
		if sinceSwing < cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds then
			-- Buried. The pause that makes the hit feel like it landed on something.
			return cfg.strikeOffset
		end
		if sinceSwing < cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds then
			local alpha = (sinceSwing - cfg.anticipationSeconds - cfg.swingSeconds - cfg.impactSeconds)
				/ math.max(cfg.reboundSeconds, 0.01)
			return cfg.strikeOffset:Lerp(cfg.reboundOffset, 1 - (1 - alpha) * (1 - alpha))
		end
		local recoverStart = cfg.anticipationSeconds + cfg.swingSeconds + cfg.impactSeconds + cfg.reboundSeconds
		if sinceSwing < recoverStart + cfg.recoverSeconds then
			local alpha = (sinceSwing - recoverStart) / math.max(cfg.recoverSeconds, 0.01)
			local target = if engaged then cfg.raisedOffset else cfg.restOffset
			return cfg.reboundOffset:Lerp(target, 1 - (1 - alpha) * (1 - alpha))
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
				shell.Transparency = transparency
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
local function emitImpactDebris(root: BasePart, accuracy: string)
	local feedback = Config.Mining.feedback
	local rng = Random.new(math.floor(Workspace:GetServerTimeNow() * 1000) % 2147483647)
	local surface = root.CFrame:PointToWorldSpace(Vector3.new(0, root.Size.Y * 0.08, -root.Size.Z * 0.52))
	local outward = -root.CFrame.LookVector
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
		chip.Color = if index % 3 == 0 then Config.Mining.visual.waxDeepColor else Config.Mining.visual.rockAccent
		chip.Material = if index % 3 == 0 then Enum.Material.SmoothPlastic else Enum.Material.Slate
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

local function characterPosition(): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character.PrimaryPart
	return if root ~= nil then root.Position else nil
end

-- Nearest eligible deposit in reach. Depth-filtered so a deposit one floor below (floors are stacked
-- in one world) can never light up through the rock.
local function findNearestDeposit(): BasePart?
	local origin = characterPosition()
	if origin == nil then
		return nil
	end
	local attributes = MiningVisualProtocol.attributes
	local range = Config.Mining.deposit.interactionRange
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, model in CollectionService:GetTagged(MiningVisualProtocol.depositTag) do
		local root = (model :: Model).PrimaryPart
		if root == nil or root:GetAttribute(attributes.depleted) == true then
			continue
		end
		if root:GetAttribute(attributes.depth) ~= currentDepth then
			continue
		end
		local distance = (root.Position - origin).Magnitude
		if distance <= range and distance < bestDistance then
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
	if text == nil then
		hint.Visible = false
		return
	end
	hint.Text = text
	hint.TextColor3 = color or palette.textDim
	hint.Visible = true
end

-- Local teardown of the stance display. The server has already decided the stance is over (or is
-- about to be told it should be); this only stops drawing it.
local function endStanceDisplay()
	sweepStartedAt = nil
	engagedRoot = nil
	perfectStreak = 0
	local ring = ringFrame
	if ring ~= nil then
		ring.Visible = false
	end
end

local function requestDisengage()
	if sweepStartedAt == nil then
		return
	end
	-- Stop drawing immediately rather than waiting for the round trip: the player asked to leave, and
	-- a stance that lingers for 60 ms after they pressed W feels like the game arguing with them.
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
	if UserInputService.TouchEnabled then
		return "MINE RAW WAX"
	elseif UserInputService.GamepadEnabled and not UserInputService.MouseEnabled then
		return "[RT]  MINE RAW WAX"
	end
	return "[LMB]  MINE RAW WAX"
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

local function onStrikeInput(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not controlsBound or inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
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
		swingStartedAt = now
		AudioCues.play("MineSwing", 0.94 + math.random() * 0.1)
		Remotes.get("MineStrike"):FireServer("strike")
		return Enum.ContextActionResult.Sink
	end

	local root = activeRoot
	if root == nil then
		-- Nothing in reach: let the input through so a bound left click is never swallowed away from
		-- a deposit. Mining must not make the rest of the game feel unresponsive.
		return Enum.ContextActionResult.Pass
	end
	Remotes.get("MineStrike"):FireServer("engage", root)
	return Enum.ContextActionResult.Sink
end

local function onExitInput(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or sweepStartedAt == nil then
		return Enum.ContextActionResult.Pass
	end
	requestDisengage()
	return Enum.ContextActionResult.Sink
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
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	controlsBound = false
	ContextActionService:UnbindAction(ACTION_NAME)
	ContextActionService:UnbindAction(EXIT_ACTION_NAME)
	endStanceDisplay()
	setPickaxeVisible(false)
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
		return
	end

	local origin = characterPosition()
	updateGlow(origin, dt)

	-- Any movement input ends the stance before anything else this frame is decided.
	if sweepStartedAt ~= nil and wantsToLeave() then
		requestDisengage()
	end

	local engaged = sweepStartedAt ~= nil
	activeRoot = findNearestDeposit()
	local inReach = activeRoot ~= nil
	-- Once engaged, the swing arc owns the tiny release reminder. Keeping the large approach prompt
	-- up over the QTE was most of what made mining read as a detached task screen.
	prompt.Visible = inReach and not engaged
	if prompt.Visible then
		prompt.Text = actionLabel()
	end
	local now = Workspace:GetServerTimeNow()
	setPickaxeVisible(inReach or engaged or now < visualSwingEndsAt())

	local camera = Workspace.CurrentCamera
	local built = pickaxeModel
	if built ~= nil and camera ~= nil then
		local cfg = Config.Mining.pickaxe
		local base = camera.CFrame * pickaxeOffset(now)
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
		ring.Visible = false
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

	-- The sweep, evaluated locally from the server's stamp. `nil` means the wind-up is still
	-- running: the marker is parked at the start rather than teleporting in mid-ring.
	local phase = MiningRules.sweepPhase(now - startedAt)
	ring.Visible = true
	local angleDegrees = phaseAngle(phase or 0)
	local angle = math.rad(angleDegrees)
	marker.Position =
		UDim2.new(0.5, math.cos(angle) * qteConfig.radiusPixels, 0.5, math.sin(angle) * qteConfig.radiusPixels)
	marker.Rotation = angleDegrees + 90
	marker.BackgroundTransparency = if phase == nil then 0.55 else 0

	local control = ringControl
	if control ~= nil then
		control.Text = actionLabel()
	end
	local result = ringResult
	if result ~= nil and nowLocal >= resultUntil then
		result.Text = if phase == nil then "READY" else "STRIKE"
		result.TextColor3 = if phase == nil then palette.textDim else palette.textMuted
		result.TextTransparency = if phase == nil then 0.35 else 0.15
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
		local hint = hintLabel
		local expected = if hint ~= nil then hint.Text else ""
		task.delay(seconds, function()
			local current = hintLabel
			if current ~= nil and current.Text == expected then
				setHint(nil)
			end
		end)
	end

	Remotes.get("MineState").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		-- any: remote payloads are untyped at the boundary; every field is read defensively.
		if kind == "engaged" then
			engagedAt = Workspace:GetServerTimeNow()
			-- Clear any lingering strike animation so the pick draws from rest, not from the rock.
			swingStartedAt = -math.huge
			perfectStreak = 0
			resultUntil = -math.huge
			engagedRoot = if typeof(payload.deposit) == "Instance" then payload.deposit :: BasePart else nil
			adoptSweep(payload)
			AudioCues.play("MineEngage")
			local scale = ringScale
			if scale ~= nil then
				scale.Scale = 0.88
				UITheme.tween(scale, UITheme.motion.rise, { Scale = 1 }):Play()
			end
			setHint("Hit the lit notch as the sweep passes.", palette.textMuted)
			clearHintLater(2.2)
		elseif kind == "strikeResolved" then
			local accuracy = tostring(payload.accuracy or "Miss")
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
				perfectStreak = streakAtImpact
				playRingHit(accuracy)
				playAtSeam("MineStrikeImpact", 0.93 + math.random() * 0.14, target)
				if target ~= nil and target.Parent ~= nil then
					emitImpactDebris(target, accuracy)
				end
				if accuracy == "Perfect" then
					local pitch = math.min(1 + (streakAtImpact - 1) * feedback.comboPitchStep, feedback.comboPitchMax)
					playAtSeam("MineStrikePerfect", pitch, target)
					setHint(
						string.format(
							"PERFECT%s  ·  %d clean left",
							if streakAtImpact > 1 then string.format(" x%d", streakAtImpact) else "",
							MiningRules.cleanStrikesRemaining(progress)
						),
						palette.gold
					)
				elseif accuracy == "Miss" then
					playAtSeam("MineStrikeFumble", nil, target)
					setHint("Glanced — louder, and slower.", palette.danger)
				else
					playAtSeam("MineStrikeClean", nil, target)
					setHint(
						string.format("Good bite  ·  %d clean left", MiningRules.cleanStrikesRemaining(progress)),
						palette.ember
					)
				end
				clearHintLater(feedback.hintSeconds)
				task.delay(Config.Mining.pickaxe.impactSeconds + Config.Mining.pickaxe.reboundSeconds * 0.35, function()
					AudioCues.play("MineRecover", 0.96 + math.random() * 0.08)
				end)
			end)
		elseif kind == "disengaged" then
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
			end
		elseif kind == "depleted" then
			local target = engagedRoot
			local delaySeconds = math.max(0, visualImpactTime() - Workspace:GetServerTimeNow())
			endStanceDisplay()
			local granted = tonumber(payload.rawWaxGranted) or 0
			local carried = tonumber(payload.rawWaxCarried) or carriedRawWax
			local minedThisRun = tonumber(payload.minedThisRun) or 0
			task.delay(delaySeconds, function()
				playAtSeam("MineBreak", nil, target)
				task.delay(0.09, function()
					playAtSeam("MineBreakChime", nil, target)
				end)
				playBreakFlash()
				if granted > 0 then
					setCargo(carried, carried ~= carriedRawWax)
					setHint(string.format("+%d RAW WAX  ·  %d carried", granted, carried), palette.gold)
				else
					setHint(string.format("SEAM OPEN  ·  %d this run", minedThisRun), palette.gold)
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
		if kind == "floor" then
			currentDepth = tonumber(payload.depth) or 0
			endStanceDisplay()
			setHint(nil)
		elseif kind == "countdown" then
			currentDepth = 0
			endStanceDisplay()
			setCargo(0, false)
		end
	end)

	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)
	RunService.RenderStepped:Connect(update)
end

return MiningController

--!strict
-- Presentation-only mining HUD. Builds and animates the continuous fracture rail, approach prompt,
-- transient result copy, and Raw Wax count. The coordinator owns input, target selection, networking,
-- and every authoritative result; this module receives already-selected display values and renders
-- them without creating a remote or binding an action.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MiningRules = require(ReplicatedStorage.Shared.Logic.MiningRules)
local UITheme = require(script.Parent.UITheme)

local MiningHUD = {}

local palette = UITheme.palette
local qteConfig = Config.Mining.qte
local RAIL_BASE_POSITION = qteConfig.position

local railFrame: CanvasGroup? = nil
local railScale: UIScale? = nil
local railMarker: Frame? = nil
local railMarkerScale: UIScale? = nil
local railImpactLine: Frame? = nil
local railResult: TextLabel? = nil
local railControl: TextLabel? = nil
local goodBands: { Frame } = {}
local perfectBands: { Frame } = {}
local railBandCenter = -1
local railVisibilityGeneration = 0
local stanceShown = false

-- Local HUD clocks. They never participate in strike scoring or server validation.
local shakeUntil = -math.huge
local resultUntil = -math.huge

-- The break flash is deliberately not a child of the rail: depletion hides the rail on the same
-- frame, and its final restrained line of light still needs to finish.
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

-- Put the authored target midpoint at the centre of the rail. This moves the circular seam to an
-- always-empty phase, so the full wander range stays one aperture instead of splitting across the
-- rail's disconnected endpoints.
function MiningHUD.displayPhase(phase: number): number
	return (phase + 0.5 - Config.Mining.timing.perfectCenter) % 1
end

-- Paint a circular scoring window on a linear rail. A window that crosses 0/1 is split into two
-- contiguous pieces, so the display remains mathematically identical to MiningRules without the
-- old segmented timing quantization.
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

function MiningHUD.setBandCenter(center: number)
	if math.abs(center - railBandCenter) < 1e-4 then
		return
	end
	railBandCenter = center
	local displayedCenter = MiningHUD.displayPhase(center)
	setBandGeometry(goodBands, displayedCenter, Config.Mining.timing.goodHalfWidth, qteConfig.goodBandHeightPixels)
	setBandGeometry(
		perfectBands,
		displayedCenter,
		Config.Mining.timing.perfectHalfWidth,
		qteConfig.perfectBandHeightPixels
	)
end

local function buildRail(parent: ScreenGui)
	local frame = Instance.new("CanvasGroup")
	frame.Name = "MiningStrikeRail"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = RAIL_BASE_POSITION
	frame.Size = UDim2.fromOffset(qteConfig.widthPixels + 40, qteConfig.heightPixels)
	frame.BackgroundTransparency = 1
	frame.GroupTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	railScale = UITheme.scale(frame, 1)

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
	MiningHUD.setBandCenter(Config.Mining.timing.perfectCenter % 1)

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
	railMarker = marker
	railMarkerScale = UITheme.scale(marker, 1)

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
	railImpactLine = impactLine

	local result = Instance.new("TextLabel")
	result.Name = "StrikeRead"
	result.AnchorPoint = Vector2.new(0.5, 0.5)
	result.Position = UDim2.new(0.5, 0, 0, 10)
	result.Size = UDim2.fromOffset(240, 24)
	result.BackgroundTransparency = 1
	result.Font = UITheme.font.fine
	result.Text = "READ THE FRACTURE"
	result.TextColor3 = palette.textMuted
	result.TextSize = UITheme.textSize.fine
	-- Was 0.28. Fading type that is already recessive in colour is how a readable label becomes an
	-- unreadable one; the rail's hierarchy comes from size and colour, and it does not need this too.
	result.TextTransparency = 0
	result.ZIndex = 4
	result.Parent = frame
	UITheme.legible(result)
	railResult = result

	local control = Instance.new("TextLabel")
	control.Name = "ReleaseControl"
	control.AnchorPoint = Vector2.new(0.5, 0.5)
	control.Position = UDim2.new(0.5, 0, 1, -8)
	control.Size = UDim2.fromOffset(220, 22)
	control.BackgroundTransparency = 1
	control.Font = UITheme.font.fine
	control.Text = "[Q] RELEASE"
	control.TextColor3 = palette.textMuted
	control.TextSize = UITheme.textSize.fine
	control.TextTransparency = 0
	control.ZIndex = 4
	control.Parent = frame
	UITheme.legible(control)
	railControl = control

	railFrame = frame

	local flash = Instance.new("Frame")
	flash.Name = "MiningBreakFlash"
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = RAIL_BASE_POSITION
	flash.Size = UDim2.fromOffset(qteConfig.widthPixels * 0.24, 2)
	flash.BackgroundColor3 = palette.gold
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Visible = false
	flash.Parent = parent
	UITheme.corner(flash, 2)
	breakFlash = flash
end

local function buildPrompt(parent: ScreenGui)
	local label = Instance.new("TextLabel")
	label.Name = "MiningPrompt"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.705)
	-- THE MOST-READ STRING IN THE GAME ("[LMB] MINE ..."), and it was set at 13px in gold over an
	-- unlit cave wall with a barely-there stroke. Sized up to `strong` and given a full outline: this
	-- is a call to action at the centre of the screen, not a footnote.
	label.Size = UDim2.fromOffset(460, 34)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = UITheme.font.heading
	label.TextSize = UITheme.textSize.strong
	label.TextColor3 = palette.gold
	label.TextStrokeColor3 = palette.void
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.Visible = false
	label.Parent = parent
	promptLabel = label

	local hint = Instance.new("TextLabel")
	hint.Name = "MiningHint"
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, 0.725)
	hint.Size = UDim2.fromOffset(560, 28)
	hint.BackgroundTransparency = 1
	hint.Font = UITheme.font.body
	hint.TextSize = UITheme.textSize.fine
	-- Hints carry refusals ("Uncover the flame to mine.") — the one line that tells a player why the
	-- game just said no. It was the dimmest colour in the palette at 13px; it is now muted, not dim.
	hint.TextColor3 = palette.textMuted
	hint.TextStrokeColor3 = palette.void
	hint.TextTransparency = 1
	hint.TextStrokeTransparency = 1
	hint.Visible = false
	hint.Parent = parent
	hintLabel = hint
end

-- A count, never a meter: Raw Wax does not keep the candle alive and must not read as a second core
-- resource. It is hidden entirely at zero so a run that never mines never sees it.
local function buildCargo(parent: ScreenGui)
	local panel = Instance.new("CanvasGroup")
	panel.Name = "RawWaxCargo"
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromOffset(24, 92)
	panel.Size = UDim2.fromOffset(172, 50)
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
	rule.Size = UDim2.fromOffset(2, 38)
	rule.BackgroundColor3 = Config.Mining.visual.waxColor
	rule.BackgroundTransparency = 0.08
	rule.BorderSizePixel = 0
	rule.Parent = panel
	UITheme.corner(rule, 2)

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0, 0.5)
	caption.Position = UDim2.new(0, 11, 0.5, -12)
	caption.Size = UDim2.fromOffset(126, 16)
	caption.BackgroundTransparency = 1
	caption.Font = UITheme.font.fine
	caption.Text = "RAW WAX"
	caption.TextSize = UITheme.textSize.micro
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = palette.textMuted
	caption.Parent = panel
	UITheme.legible(caption, 0.6)

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(0, 0.5)
	value.Position = UDim2.new(0, 11, 0.5, 11)
	value.Size = UDim2.fromOffset(126, 26)
	value.BackgroundTransparency = 1
	value.Font = UITheme.font.body
	value.Text = "0"
	value.TextSize = UITheme.textSize.value
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = palette.gold
	value.Parent = panel
	UITheme.legible(value, 0.6)
	cargoValue = value

	cargoPanel = panel
end

function MiningHUD.start(parentGui: ScreenGui)
	if railFrame ~= nil then
		return
	end
	buildRail(parentGui)
	buildPrompt(parentGui)
	buildCargo(parentGui)
end

function MiningHUD.showStance()
	local rail = railFrame
	if rail == nil then
		return
	end
	railVisibilityGeneration += 1
	stanceShown = true
	resultUntil = -math.huge
	rail.Visible = true
	rail.GroupTransparency = 1
	local scale = railScale
	if scale ~= nil then
		scale.Scale = qteConfig.enterScale
		UITheme.tween(
			scale,
			TweenInfo.new(qteConfig.enterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
	end
	UITheme.tween(
		rail,
		TweenInfo.new(qteConfig.enterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ GroupTransparency = 0 }
	)
end

-- The coordinator has already decided (or requested) that the stance is over. This only gives the
-- rail a short accelerating exit instead of letting it snap away.
function MiningHUD.hideStance()
	stanceShown = false
	local rail = railFrame
	if rail == nil then
		return
	end
	railVisibilityGeneration += 1
	local generation = railVisibilityGeneration
	local fade = UITheme.tween(
		rail,
		TweenInfo.new(qteConfig.exitSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ GroupTransparency = 1 }
	)
	fade.Completed:Connect(function()
		if railVisibilityGeneration == generation and not stanceShown then
			rail.Visible = false
		end
	end)
end

function MiningHUD.updatePrompt(dt: number, visible: boolean, text: string)
	local prompt = promptLabel
	if prompt == nil then
		return
	end
	local promptTarget = if visible then 1 else 0
	local promptStep = math.clamp(dt / math.max(qteConfig.enterSeconds, 0.01), 0, 1)
	promptAlpha += (promptTarget - promptAlpha) * promptStep
	prompt.Visible = visible or promptAlpha > 0.01
	prompt.TextTransparency = 1 - promptAlpha * 0.96
	-- The outline fades WITH the glyphs. A stroke pinned to a fixed transparency while the text fades
	-- out leaves a ghost outline hanging in the middle of the screen, so both are driven from the one
	-- alpha rather than the stroke being set once at build time.
	prompt.TextStrokeTransparency = 1 - promptAlpha * 0.85
	prompt.Text = text
end

function MiningHUD.setHint(text: string?, color: Color3?)
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
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fade.Completed:Connect(function()
			if hintGeneration == generation then
				hint.Visible = false
			end
		end)
		return
	end
	hint.Text = text
	hint.TextColor3 = color or palette.textMuted
	if not hint.Visible then
		hint.TextTransparency = 1
		hint.TextStrokeTransparency = 1
	end
	hint.Visible = true
	UITheme.tween(
		hint,
		TweenInfo.new(qteConfig.enterSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0.2 }
	)
end

function MiningHUD.clearHintAfter(seconds: number)
	local generation = hintGeneration
	task.delay(seconds, function()
		if hintGeneration == generation then
			MiningHUD.setHint(nil)
		end
	end)
end

function MiningHUD.setCargo(total: number, pulse: boolean)
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

function MiningHUD.getCargo(): number
	return carriedRawWax
end

-- Updates only the reconstructed display. `startedAt` is the authoritative server stamp; the
-- optional held phase is the coordinator's click-captured marker location during physical contact.
function MiningHUD.updateRail(
	serverNow: number,
	localNow: number,
	startedAt: number,
	heldDisplayPhase: number?,
	holdThroughContact: boolean,
	controlText: string
)
	local rail = railFrame
	local marker = railMarker
	if rail == nil or marker == nil then
		return
	end

	if localNow < shakeUntil then
		local remaining = shakeUntil - localNow
		local decay = remaining / qteConfig.shakeDuration
		local wobble = math.sin(localNow * 55) * qteConfig.shakeMagnitudePixels * decay
		rail.Position = RAIL_BASE_POSITION + UDim2.fromOffset(wobble, 0)
	else
		rail.Position = RAIL_BASE_POSITION
	end

	local phase = MiningRules.sweepPhase(serverNow - startedAt)
	local markerPhase = if holdThroughContact
		then heldDisplayPhase or MiningHUD.displayPhase(phase or 0)
		else MiningHUD.displayPhase(phase or 0)
	marker.Position = UDim2.new(markerPhase, 0, 0.5, 0)
	marker.Rotation = 0
	marker.BackgroundTransparency = if holdThroughContact or phase ~= nil then 0 else 0.55

	local control = railControl
	if control ~= nil then
		control.Text = controlText
	end
	local result = railResult
	if result ~= nil and localNow >= resultUntil then
		result.Text = if phase == nil then "SETTLE" else "STRIKE"
		-- The idle/armed distinction is carried by COLOUR alone now. It used to be carried by fading
		-- the label to 0.48, which made the rail's own instruction the least readable text on screen
		-- at exactly the moment a player is looking for it.
		result.TextColor3 = if phase == nil then palette.textMuted else palette.text
		result.TextTransparency = 0
	end
end

-- Contact compresses the marker and sends one short trace through the rail. The result replaces the
-- instruction briefly; no combo typography, expanding circles, or simultaneous whole-HUD bounce.
function MiningHUD.playHit(accuracy: string, contactDisplayPhase: number)
	local marker = railMarker
	local markerScale = railMarkerScale
	local impactLine = railImpactLine
	local result = railResult
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

	local contactPosition = UDim2.new(contactDisplayPhase, 0, 0.5, 0)
	marker.Position = contactPosition
	impactLine.Position = contactPosition
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

	local scale = railScale
	if scale ~= nil then
		scale.Scale = if accuracy == "Miss" then 0.99 else 0.985
		UITheme.tween(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
	end

	if accuracy == "Miss" then
		shakeUntil = os.clock() + qteConfig.shakeDuration
	end
end

-- A seam break gets one restrained line of light; fracture, debris, and the low-end audio body carry
-- the payoff in the world instead of a full-screen arcade burst.
function MiningHUD.playBreak()
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

-- Presentation only: the coordinator still creates/binds the ContextActionService action.
function MiningHUD.styleTouchButton(actionName: string)
	local button = ContextActionService:GetButton(actionName)
	if button == nil or not button:IsA("ImageButton") or button:GetAttribute("WickMiningStyled") == true then
		return
	end
	button:SetAttribute("WickMiningStyled", true)
	button.AutoButtonColor = false
	button.ImageTransparency = 1
	button.BackgroundColor3 = palette.panel
	button.BackgroundTransparency = 0.16
	button.Size = UDim2.fromOffset(128, 54)
	UITheme.corner(button, 8)
	UITheme.stroke(button, palette.strokeSoft, 1, 0.28)
	for _, descendant in button:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.Font = UITheme.font.heading
			descendant.TextColor3 = palette.gold
			descendant.TextSize = UITheme.textSize.body
			descendant.TextScaled = false
			UITheme.legible(descendant, 0.6)
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

return MiningHUD

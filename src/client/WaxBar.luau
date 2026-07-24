--!strict
-- The wax HUD, rendered as the thing it represents: a candle. The wax body lowers as you burn;
-- a wick rides its surface; a live flame sits on top and reacts to how fast you are spending wax
-- (the brightness dial). Burn bright and the flame swells and whitens; ease off and it settles.
-- Snuffed candles go dark with a thread of smoke; a low candle reddens and pulses. This replaces
-- the old grey melt-line bar without touching any authoritative number — it only renders state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local UITheme = require(script.Parent.UITheme)

local WaxBar = {}

local player = Players.LocalPlayer
local palette = UITheme.palette

-- Soft glow discs: Roblox UI has no radial gradient, so a couple of concentric rounded frames
-- fake a halo whose transparency we drive from the burn rate each frame.
local function makeCircle(parent: GuiObject, scale: number, color: Color3, zIndex: number): Frame
	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromScale(scale, scale)
	circle.BackgroundColor3 = color
	circle.BorderSizePixel = 0
	circle.ZIndex = zIndex
	circle.Parent = parent
	UITheme.corner(circle, 1000)
	return circle
end

function WaxBar.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickWaxBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true

	-- Envelope for a full (max-wax) candle; the visible body only fills part of it.
	local holder = Instance.new("Frame")
	holder.Name = "Candle"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 30, 0.5, 0)
	holder.Size = UDim2.new(0, 40, 0.46, 0)
	holder.BackgroundTransparency = 1
	holder.Parent = gui

	-- A little bronze dish the candle stands in — grounds it instead of floating.
	local dish = Instance.new("Frame")
	dish.Name = "Dish"
	dish.AnchorPoint = Vector2.new(0.5, 1)
	dish.Position = UDim2.new(0.5, 0, 1, 14)
	dish.Size = UDim2.new(1, 26, 0, 12)
	dish.BackgroundColor3 = Color3.fromRGB(38, 30, 26)
	dish.BorderSizePixel = 0
	dish.ZIndex = 4
	dish.Parent = holder
	UITheme.corner(dish, 6)
	UITheme.stroke(dish, palette.strokeSoft, 1.5, 0.3)

	-- The spent headroom at the top: wax a Basin sacrifice has permanently taken from your ceiling.
	local ceiling = Instance.new("Frame")
	ceiling.Name = "Ceiling"
	ceiling.AnchorPoint = Vector2.new(0.5, 0)
	ceiling.Position = UDim2.fromScale(0.5, 0)
	ceiling.Size = UDim2.new(1, -8, 0, 0)
	ceiling.BackgroundColor3 = Color3.fromRGB(16, 14, 17)
	ceiling.BackgroundTransparency = 0.25
	ceiling.BorderSizePixel = 0
	ceiling.ZIndex = 1
	ceiling.Parent = holder

	-- The wax body. Its height is the remaining wax fraction; it visibly shrinks as you burn.
	local body = Instance.new("Frame")
	body.Name = "Wax"
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 1)
	body.Size = UDim2.new(1, -8, 1, 0)
	body.BackgroundColor3 = palette.waxLight
	body.BorderSizePixel = 0
	body.ZIndex = 2
	body.Parent = holder
	UITheme.corner(body, 5)
	UITheme.stroke(body, Color3.fromRGB(120, 108, 84), 1, 0.55)

	-- Multiplicative sheen: keeps the wax's own colour (so the low-wax red still shows) but darkens
	-- the base and brightens the top edge, giving the column a waxy roundness.
	local waxSheen = Instance.new("UIGradient")
	waxSheen.Rotation = 90
	waxSheen.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.65, Color3.fromRGB(232, 232, 232)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(198, 198, 198)),
	})
	waxSheen.Parent = body

	-- Molten rim at the wax surface — a bright lip of melting wax.
	local meltLine = Instance.new("Frame")
	meltLine.Name = "MeltLine"
	meltLine.AnchorPoint = Vector2.new(0.5, 0)
	meltLine.Position = UDim2.fromScale(0.5, 0)
	meltLine.Size = UDim2.new(1, 0, 0, 3)
	meltLine.BackgroundColor3 = palette.ember
	meltLine.BorderSizePixel = 0
	meltLine.ZIndex = 3
	meltLine.Parent = body
	UITheme.corner(meltLine, 2)

	-- The wick sits on the wax surface and rides down with it.
	local wick = Instance.new("Frame")
	wick.Name = "Wick"
	wick.AnchorPoint = Vector2.new(0.5, 1)
	wick.Position = UDim2.new(0.5, 0, 0, 1)
	wick.Size = UDim2.fromOffset(2, 9)
	wick.BackgroundColor3 = Color3.fromRGB(30, 24, 22)
	wick.BorderSizePixel = 0
	wick.ZIndex = 4
	wick.Parent = body

	-- Flame rig, parented to the wax so it descends with the surface. Offset-sized so it stays a
	-- constant size no matter how short the candle gets.
	local flameRig = Instance.new("Frame")
	flameRig.Name = "Flame"
	flameRig.AnchorPoint = Vector2.new(0.5, 1)
	flameRig.Position = UDim2.new(0.5, 0, 0, -8)
	flameRig.Size = UDim2.fromOffset(34, 52)
	flameRig.BackgroundTransparency = 1
	flameRig.ZIndex = 5
	flameRig.Parent = body
	local flameScale = UITheme.scale(flameRig, 1)

	local glowOuter = makeCircle(flameRig, 1, palette.ember, 5)
	glowOuter.Position = UDim2.fromScale(0.5, 0.62)
	glowOuter.Size = UDim2.fromScale(1.5, 1.5)
	local glowInner = makeCircle(flameRig, 0.8, palette.flameMid, 6)
	glowInner.Position = UDim2.fromScale(0.5, 0.62)
	glowInner.Size = UDim2.fromScale(0.95, 0.95)

	-- Teardrop-ish flame: a tall rounded body with a gradient that fades the tip toward transparent
	-- so the silhouette tapers, plus a bright inner tongue and a near-white base.
	local flameOuter = Instance.new("Frame")
	flameOuter.Name = "Body"
	flameOuter.AnchorPoint = Vector2.new(0.5, 1)
	flameOuter.Position = UDim2.fromScale(0.5, 1)
	flameOuter.Size = UDim2.fromOffset(18, 40)
	flameOuter.BackgroundColor3 = palette.flameOuter
	flameOuter.BorderSizePixel = 0
	flameOuter.ZIndex = 7
	flameOuter.Parent = flameRig
	UITheme.corner(flameOuter, 9)
	local outerFade = Instance.new("UIGradient")
	outerFade.Rotation = 90
	outerFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.35, 0.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	outerFade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.flameMid),
		ColorSequenceKeypoint.new(1, palette.flameOuter),
	})
	outerFade.Parent = flameOuter

	local flameInner = Instance.new("Frame")
	flameInner.Name = "Tongue"
	flameInner.AnchorPoint = Vector2.new(0.5, 1)
	flameInner.Position = UDim2.fromScale(0.5, 1)
	flameInner.Size = UDim2.fromOffset(9, 24)
	flameInner.BackgroundColor3 = palette.flameMid
	flameInner.BorderSizePixel = 0
	flameInner.ZIndex = 8
	flameInner.Parent = flameRig
	UITheme.corner(flameInner, 5)

	local flameCore = Instance.new("Frame")
	flameCore.Name = "Core"
	flameCore.AnchorPoint = Vector2.new(0.5, 1)
	flameCore.Position = UDim2.fromScale(0.5, 0.92)
	flameCore.Size = UDim2.fromOffset(5, 11)
	flameCore.BackgroundColor3 = palette.flameCore
	flameCore.BorderSizePixel = 0
	flameCore.ZIndex = 9
	flameCore.Parent = flameRig
	UITheme.corner(flameCore, 3)

	-- A thread of smoke that shows briefly when the flame goes out.
	local smoke = Instance.new("Frame")
	smoke.Name = "Smoke"
	smoke.AnchorPoint = Vector2.new(0.5, 1)
	smoke.Position = UDim2.fromScale(0.5, 0.9)
	smoke.Size = UDim2.fromOffset(3, 26)
	smoke.BackgroundColor3 = palette.smoke
	smoke.BackgroundTransparency = 1
	smoke.BorderSizePixel = 0
	smoke.ZIndex = 6
	smoke.Parent = flameRig
	UITheme.corner(smoke, 2)

	gui.Parent = player:WaitForChild("PlayerGui")

	local currentWax = Config.Wax.startingWax
	local currentBurnRate = Config.Wax.initialBurnRate
	local localAlive = false
	local localLit = false
	local inDraft = false
	local wasLit = false
	local snuffedAt = -math.huge
	local seed = player.UserId % 4096

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			currentWax = entry.wax
			currentBurnRate = entry.burnRate
			localAlive = entry.alive and not entry.finished
			localLit = entry.isLit
			inDraft = entry.inDraft
			body.Size = UDim2.new(1, -8, math.clamp(entry.wax, 0, 1), 0)
			ceiling.Size = UDim2.new(1, -8, math.clamp(1 - entry.maxWax, 0, 1), 0)

			local lit = entry.isLit and localAlive
			meltLine.Visible = lit
			if wasLit and not lit then
				snuffedAt = os.clock()
			end
			wasLit = lit

			if
				Config.Feel.lowWax.enabled
				and localAlive
				and localLit
				and currentWax <= Config.Feel.lowWax.threshold
			then
				AudioCues.play("LowWax")
			end
			break
		end
	end)

	RunService.RenderStepped:Connect(function()
		local lowWax = Config.Feel.lowWax
		local lit = localAlive and localLit
		local now = os.clock()

		-- Wax body colour: base cream, or pulsing warning red when the candle is running low.
		local baseColor = if lit then lowWax.normalColor else lowWax.snuffedColor
		local lowActive = lowWax.enabled and lit and currentWax <= lowWax.threshold
		if lowActive then
			local warningColor = if currentWax <= lowWax.urgentThreshold
				then lowWax.urgentColor
				else lowWax.warningColor
			local wave = (math.sin(now * lowWax.pulseFrequencyHz * math.pi * 2) + 1) / 2
			local blend = lowWax.minColorBlend + (lowWax.maxColorBlend - lowWax.minColorBlend) * wave
			body.BackgroundColor3 = baseColor:Lerp(warningColor, blend)
		else
			body.BackgroundColor3 = baseColor
		end

		-- The flame reacts to the burn rate (how fast you spend wax).
		local span = Config.Light.maxBurnRate - Config.Light.minBurnRate
		local heat = if span > 0 then math.clamp((currentBurnRate - Config.Light.minBurnRate) / span, 0, 1) else 0

		flameRig.Visible = lit
		if lit then
			-- Organic flicker from value noise; drafts make it faster and wilder.
			local flickerHz = if inDraft then 15 else 8.5
			local swayHz = if inDraft then 4.2 else 2.1
			local flicker = (math.noise(now * flickerHz, seed) + 1) / 2
			local sway = math.noise(now * swayHz + 40, seed)

			local size = 0.7 + 0.55 * heat
			flameScale.Scale = size * (0.93 + 0.14 * flicker)

			local leanDegrees = sway * (if inDraft then 16 else 6)
			flameOuter.Rotation = leanDegrees
			flameInner.Rotation = leanDegrees * 1.15
			flameInner.Position = UDim2.fromScale(0.5 + sway * 0.05, 1)
			flameCore.Position = UDim2.fromScale(0.5 + sway * 0.06, 0.9 + flicker * 0.03)

			-- Hotter burn -> whiter, brighter flame and a stronger halo; low wax reddens it.
			local hotShift = heat * 0.5
			flameOuter.BackgroundColor3 = palette.flameOuter:Lerp(palette.flameMid, hotShift)
			flameInner.BackgroundColor3 = palette.flameMid:Lerp(palette.flameCore, hotShift)
			if lowActive then
				flameOuter.BackgroundColor3 = flameOuter.BackgroundColor3:Lerp(palette.danger, 0.4)
			end

			local halo = 0.62 - 0.24 * heat - 0.08 * flicker
			glowOuter.BackgroundTransparency = math.clamp(halo + 0.18, 0.2, 0.95)
			glowInner.BackgroundTransparency = math.clamp(halo, 0.1, 0.9)
			glowOuter.BackgroundColor3 = if lowActive then palette.emberDeep else palette.ember

			meltLine.BackgroundColor3 = if lowActive then palette.danger else palette.ember
		end

		-- Smoke: a brief rising thread right after the flame is snuffed.
		local sinceSnuff = now - snuffedAt
		if not lit and sinceSnuff < 1.4 then
			smoke.Visible = true
			flameRig.Visible = true
			local fade = sinceSnuff / 1.4
			smoke.BackgroundTransparency = math.clamp(0.55 + fade * 0.45, 0, 1)
			smoke.Position = UDim2.fromScale(0.5 + math.noise(now * 1.5, seed) * 0.08, 0.9 - fade * 0.5)
		else
			smoke.Visible = false
		end
	end)
end

return WaxBar

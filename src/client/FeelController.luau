--!strict
-- Local-only sensory feedback: an additive flame flicker, stronger draft motion, subtle
-- environmental grading, and proximity cue requests. It renders server state; it changes no rules.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local FeelController = {}

local player = Players.LocalPlayer

local alive = false
local finished = false
local lit = false
local snuffed = false
local inDraft = false
local wading = false
local threatNear = false
local threatScanAccumulator = 0
local flickerLight: PointLight? = nil
local draftLabel: TextLabel? = nil

local function updateHazardState(nextInDraft: boolean, nextWading: boolean)
	if nextInDraft ~= inDraft then
		inDraft = nextInDraft
		if inDraft then
			AudioCues.play("Draft")
		else
			AudioCues.stop("Draft")
		end
	end

	if nextWading ~= wading then
		wading = nextWading
		if wading then
			AudioCues.play("Water")
		else
			AudioCues.stop("Water")
		end
	end
end

local function findFlameAttachment(): Attachment?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return nil
	end
	local attachment = root:FindFirstChild("FlameLight")
	return if attachment ~= nil and attachment:IsA("Attachment") then attachment else nil
end

local function ensureFlickerLight(): PointLight?
	local attachment = findFlameAttachment()
	if attachment == nil then
		return nil
	end

	local current = flickerLight
	if current ~= nil and current.Parent == attachment then
		return current
	end
	if current ~= nil then
		current:Destroy()
	end

	local created = Instance.new("PointLight")
	created.Name = "WickClientFlicker"
	created.Color = Config.Feel.flameFlicker.color
	created.Range = Config.Feel.flameFlicker.range
	created.Shadows = false
	created.Parent = attachment
	flickerLight = created
	return created
end

local function scanForThreats()
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") or not alive or finished then
		threatNear = false
		return
	end

	local foundNear = false
	for _, tagged in CollectionService:GetTagged(Config.Feel.threatWarning.collectionTag) do
		if not tagged:IsA("Model") or not tagged:IsDescendantOf(workspace) then
			continue
		end
		local threatRoot = tagged.PrimaryPart
		if
			threatRoot ~= nil
			and (threatRoot.Position - root.Position).Magnitude <= Config.Feel.threatWarning.radius
		then
			foundNear = true
			break
		end
	end
	threatNear = foundNear
	if threatNear then
		AudioCues.play("ThreatNear")
	end
end

function FeelController.start()
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WickEnvironmentWarning"
	grade.Enabled = false
	grade.Parent = Lighting

	local gui = Instance.new("ScreenGui")
	gui.Name = "WickHazardWarning"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.IgnoreGuiInset = true
	local warningLabel = Instance.new("TextLabel")
	warningLabel.Name = "DraftWarning"
	warningLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	warningLabel.Position = UDim2.fromScale(0.5, 0.2)
	warningLabel.Size = UDim2.fromScale(0.62, 0.055)
	warningLabel.BackgroundTransparency = 1
	warningLabel.Font = Enum.Font.GothamBold
	warningLabel.TextScaled = true
	warningLabel.Visible = false
	warningLabel.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	draftLabel = warningLabel

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			alive = entry.alive
			finished = entry.finished
			lit = entry.isLit
			if entry.snuffed and not snuffed then
				AudioCues.play("DeathSnuffed")
			elseif snuffed and not entry.snuffed and alive and lit then
				AudioCues.play("Relight")
			end
			snuffed = entry.snuffed
			updateHazardState(
				entry.inDraft and alive and not finished and lit,
				entry.water == "Wading" and alive and not finished
			)
			break
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local flicker = Config.Feel.flameFlicker
		local localLight = ensureFlickerLight()
		if localLight ~= nil then
			localLight.Enabled = flicker.enabled and alive and not finished and lit
			if localLight.Enabled then
				local speedMultiplier = if inDraft then flicker.draftFrequencyMultiplier else 1
				local amplitudeMultiplier = if inDraft then flicker.draftAmplitudeMultiplier else 1
				if threatNear then
					amplitudeMultiplier *= flicker.threatAmplitudeMultiplier
				end
				local sample = (math.noise(os.clock() * flicker.frequencyHz * speedMultiplier, player.UserId) + 1) / 2
				localLight.Brightness = flicker.baseBrightness
					+ flicker.brightnessAmplitude * amplitudeMultiplier * sample
			end
		end

		if inDraft and Config.Feel.draftWarning.enabled and alive and not finished then
			local warning = Config.Feel.draftWarning
			grade.Enabled = true
			grade.TintColor = warning.tintColor
			grade.Contrast = warning.contrast
			grade.Brightness = warning.baseBrightness
				+ math.sin(os.clock() * warning.pulseFrequencyHz * math.pi * 2) * warning.brightnessAmplitude
			local label = draftLabel
			if label ~= nil then
				label.Text = warning.message
				label.TextColor3 = warning.messageColor
				label.TextTransparency = warning.messageTransparency
				label.Visible = true
			end
		elseif wading and Config.Feel.waterWarning.enabled and alive and not finished then
			local warning = Config.Feel.waterWarning
			grade.Enabled = true
			grade.TintColor = warning.tintColor
			grade.Contrast = warning.contrast
			grade.Brightness = warning.brightness
		else
			grade.Enabled = false
		end
		if not inDraft or not Config.Feel.draftWarning.enabled or not alive or finished then
			local label = draftLabel
			if label ~= nil then
				label.Visible = false
			end
		end

		if Config.Feel.threatWarning.enabled then
			threatScanAccumulator += dt
			if threatScanAccumulator >= Config.Feel.threatWarning.scanIntervalSeconds then
				threatScanAccumulator = 0
				scanForThreats()
			end
		else
			threatNear = false
		end
	end)
end

return FeelController

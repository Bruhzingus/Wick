--!strict
-- Local-only sensory feedback: environmental grading, proximity cue requests, and context for
-- CandleLightController's unified cosmetic flame signal. It renders server state; it changes no rules.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CandleLightController = require(script.Parent.CandleLightController)

local FeelController = {}

local player = Players.LocalPlayer

local alive = false
local finished = false
local lit = false
local snuffed = false
local inDraft = false
local isCupping = false
local wading = false
local threatNear = false
local threatScanAccumulator = 0
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
			isCupping = entry.isCupping
			updateHazardState(
				entry.inDraft and alive and not finished and lit,
				entry.water == "Wading" and alive and not finished
			)
			break
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
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

		-- CUP shields the flame from draft turbulence even though the player remains inside the
		-- wind volume and should still hear/see its environmental warning.
		CandleLightController.setLocalConditions(
			inDraft and not isCupping and alive and not finished and lit,
			threatNear and alive and not finished and lit
		)
	end)
end

return FeelController

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
local wading = false
local threatNear = false
local canHearThreats = true
local peripheralDarkness = 0
local sightBrightness = 0
local sightSaturation = 0
local threatScanAccumulator = 0
local visionEdges: { Frame } = {}

local function addVisionEdge(
	gui: ScreenGui,
	name: string,
	position: UDim2,
	size: UDim2,
	anchorPoint: Vector2,
	rotation: number
)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = position
	frame.Size = size
	frame.AnchorPoint = anchorPoint
	frame.BackgroundColor3 = Config.Feel.basinVision.edgeColor
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
	table.insert(visionEdges, frame)
end

local function buildVisionGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickBasinVision"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5

	local width = Config.Feel.basinVision.edgeWidthScale
	addVisionEdge(gui, "Left", UDim2.fromScale(0, 0), UDim2.fromScale(width, 1), Vector2.zero, 0)
	addVisionEdge(gui, "Right", UDim2.fromScale(1, 0), UDim2.fromScale(width, 1), Vector2.new(1, 0), 180)
	addVisionEdge(gui, "Top", UDim2.fromScale(0, 0), UDim2.fromScale(1, width), Vector2.zero, 90)
	addVisionEdge(gui, "Bottom", UDim2.fromScale(0, 1), UDim2.fromScale(1, width), Vector2.new(0, 1), 270)
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function updateHazardState(nextWading: boolean)
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
	-- The Basin's Hearing sacrifice takes this sense away outright: no cue, and no flame reaction
	-- to something you can no longer sense.
	if root == nil or not root:IsA("BasePart") or not alive or finished or not canHearThreats then
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
	local visionGui = buildVisionGui()
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "WickEnvironmentWarning"
	grade.Enabled = false
	grade.Parent = Lighting
	local visionGrade = Instance.new("ColorCorrectionEffect")
	visionGrade.Name = "WickBasinVision"
	visionGrade.Enabled = false
	visionGrade.Parent = Lighting

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
			canHearThreats = entry.canHearThreats ~= false
			peripheralDarkness = math.clamp(entry.peripheralDarkness, 0, 1)
			sightBrightness = math.clamp(entry.sightBrightness, -1, 1)
			sightSaturation = math.clamp(entry.sightSaturation, -1, 1)
			updateHazardState(entry.water == "Wading" and alive and not finished)
			break
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local renderVision = player:GetAttribute("WickInExpedition") == true and alive and not finished
		visionGui.Enabled = renderVision
		for _, edge in visionEdges do
			edge.BackgroundTransparency = if renderVision then 1 - peripheralDarkness else 1
		end
		visionGrade.Enabled = renderVision and (sightBrightness ~= 0 or sightSaturation ~= 0)
		visionGrade.Brightness = sightBrightness
		visionGrade.Saturation = sightSaturation
		if wading and Config.Feel.waterWarning.enabled and alive and not finished then
			local warning = Config.Feel.waterWarning
			grade.Enabled = true
			grade.TintColor = warning.tintColor
			grade.Contrast = warning.contrast
			grade.Brightness = warning.brightness
		else
			grade.Enabled = false
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

		CandleLightController.setLocalConditions(threatNear and alive and not finished and lit)
	end)
end

return FeelController

--!strict
-- The one text sink: run events (countdown, floor, messages), the live brazier arithmetic,
-- and the end-of-run results. Text only, unstyled, by design.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local ResultsText = {}

local player = Players.LocalPlayer

local transientLabel: TextLabel? = nil
local previewLabel: TextLabel? = nil
local resultsLabel: TextLabel? = nil
local clearAt = 0

local TRANSIENT_SECONDS = 4

local function buildLabel(gui: ScreenGui, name: string, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 225, 215)
	label.TextScaled = true
	label.Text = ""
	label.Visible = false
	label.Parent = gui
	return label
end

local function showTransient(text: string)
	local label = transientLabel
	if label ~= nil then
		label.Text = text
		label.Visible = true
		clearAt = os.clock() + TRANSIENT_SECONDS
		task.delay(TRANSIENT_SECONDS, function()
			if os.clock() >= clearAt and label ~= nil then
				label.Visible = false
			end
		end)
	end
end

function ResultsText.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickText"
	gui.ResetOnSpawn = false
	transientLabel = buildLabel(gui, "Transient", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.6, 0.06))
	previewLabel = buildLabel(gui, "BrazierPreview", UDim2.fromScale(0.5, 0.85), UDim2.fromScale(0.7, 0.05))
	resultsLabel = buildLabel(gui, "Results", UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.7, 0.3))
	gui.Parent = player:WaitForChild("PlayerGui")

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		-- any: remote payloads are untyped at the boundary; fields are read defensively below.
		if kind == "countdown" then
			showTransient(string.format("Descending in %d...", payload.seconds or 0))
		elseif kind == "floor" then
			local results = resultsLabel
			if results ~= nil then
				results.Visible = false
			end
			showTransient(string.format("Floor %d", payload.depth or 0))
		elseif kind == "message" then
			showTransient(tostring(payload.text or ""))
		elseif kind == "brazierPreview" then
			local preview = previewLabel
			if preview ~= nil then
				preview.Text = string.format(
					"Deliver %.2f wax x %.1f depth x %.2f group (%d with you) = %d",
					payload.waxDelivered or 0,
					payload.depthMultiplier or 0,
					payload.groupMultiplier or 1,
					payload.additionalPlayers or 0,
					payload.total or 0
				)
				preview.Visible = true
			end
		elseif kind == "brazierPreviewClear" then
			local preview = previewLabel
			if preview ~= nil then
				preview.Visible = false
			end
		elseif kind == "results" then
			local results = resultsLabel
			if results ~= nil then
				if payload.survived then
					results.Text = string.format(
						"DELIVERED\nFloor %d\n%.2f wax x %.1f x %.2f\nReward: %d",
						payload.depthReached or 0,
						payload.waxDelivered or 0,
						payload.depthMultiplier or 0,
						payload.groupMultiplier or 1,
						payload.reward or 0
					)
				else
					local cause = if payload.deathCause == "BurnOut" then "You burned out." else "You were snuffed."
					results.Text = string.format("%s\nFloor %d\nNothing delivered.", cause, payload.depthReached or 0)
				end
				results.Visible = true
			end
		end
	end)
end

return ResultsText

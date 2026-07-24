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
local restartButton: TextButton? = nil
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

local function buildRestartButton(gui: ScreenGui): TextButton
	local button = Instance.new("TextButton")
	button.Name = "RestartRun"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.62)
	button.Size = UDim2.fromScale(0.26, 0.06)
	button.BackgroundColor3 = Color3.fromRGB(70, 45, 35)
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(255, 220, 185)
	button.TextScaled = true
	button.Text = "RESTART RUN"
	button.Visible = false
	button.Activated:Connect(function()
		Remotes.get("RestartRun"):FireServer()
	end)
	button.Parent = gui
	return button
end

function ResultsText.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickText"
	gui.ResetOnSpawn = false
	transientLabel = buildLabel(gui, "Transient", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.6, 0.06))
	previewLabel = buildLabel(gui, "BrazierPreview", UDim2.fromScale(0.5, 0.85), UDim2.fromScale(0.7, 0.05))
	resultsLabel = buildLabel(gui, "Results", UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.7, 0.3))
	restartButton = buildRestartButton(gui)
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
			local button = restartButton
			if button ~= nil then
				button.Visible = false
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
					local debug = payload.deathDebug
					local trigger = if typeof(debug) == "table" then tostring(debug.trigger or "Unknown") else "Unknown"
					local wax = if typeof(debug) == "table" then tonumber(debug.waxRemaining) or 0 else 0
					local maxWax = if typeof(debug) == "table" then tonumber(debug.maxWax) or 0 else 0
					local burnRate = if typeof(debug) == "table" then tonumber(debug.burnRate) or 0 else 0
					local movement = if typeof(debug) == "table"
						then tostring(debug.movementMode or "Unknown")
						else "Unknown"
					results.Text = string.format(
						"%s\nFloor %d\nWhy: %s\nDebug — wax %.3f/%.3f | burn %.2f | %s\nNothing delivered.",
						cause,
						payload.depthReached or 0,
						trigger,
						wax,
						maxWax,
						burnRate,
						movement
					)
				end
				results.Visible = true
			end
			local button = restartButton
			if button ~= nil then
				button.Visible = true
			end
		end
	end)
end

return ResultsText

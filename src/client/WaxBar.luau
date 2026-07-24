--!strict
-- The entire HUD: one vertical wax bar. Reads as a melt line — a candle column that lowers,
-- with a bright molten strip at the top edge. Dims while snuffed. Nothing else, by design.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local WaxBar = {}

local player = Players.LocalPlayer

function WaxBar.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WickWaxBar"
	gui.ResetOnSpawn = false

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 16, 0.5, 0)
	track.Size = UDim2.new(0, 22, 0.5, 0)
	track.BackgroundColor3 = Color3.fromRGB(22, 20, 24)
	track.BorderSizePixel = 0
	track.Parent = gui

	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "Wax"
	fillFrame.AnchorPoint = Vector2.new(0, 1)
	fillFrame.Position = UDim2.fromScale(0, 1)
	fillFrame.Size = UDim2.fromScale(1, 1)
	fillFrame.BackgroundColor3 = Color3.fromRGB(235, 225, 200)
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = track

	local meltLine = Instance.new("Frame")
	meltLine.Name = "MeltLine"
	meltLine.AnchorPoint = Vector2.new(0, 0)
	meltLine.Position = UDim2.fromScale(0, 0)
	meltLine.Size = UDim2.new(1, 0, 0, 3)
	meltLine.BackgroundColor3 = Color3.fromRGB(255, 180, 80)
	meltLine.BorderSizePixel = 0
	meltLine.Parent = fillFrame

	-- Max-wax ceiling marker: a Basin sacrifice can lower the ceiling; show the lost headroom.
	local ceiling = Instance.new("Frame")
	ceiling.Name = "Ceiling"
	ceiling.AnchorPoint = Vector2.new(0, 0)
	ceiling.Position = UDim2.fromScale(0, 0)
	ceiling.Size = UDim2.fromScale(1, 0)
	ceiling.BackgroundColor3 = Color3.fromRGB(10, 9, 11)
	ceiling.BorderSizePixel = 0
	ceiling.Parent = track

	gui.Parent = player:WaitForChild("PlayerGui")

	local currentWax = Config.Wax.startingWax
	local localAlive = false
	local localLit = false

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			currentWax = entry.wax
			localAlive = entry.alive and not entry.finished
			localLit = entry.isLit
			fillFrame.Size = UDim2.fromScale(1, math.clamp(entry.wax, 0, 1))
			ceiling.Size = UDim2.fromScale(1, math.clamp(1 - entry.maxWax, 0, 1))
			local lit = entry.isLit and entry.alive
			meltLine.Visible = lit
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
		local baseColor = if localAlive and localLit then lowWax.normalColor else lowWax.snuffedColor
		if not lowWax.enabled or not localAlive or not localLit or currentWax > lowWax.threshold then
			fillFrame.BackgroundColor3 = baseColor
			return
		end

		local warningColor = if currentWax <= lowWax.urgentThreshold then lowWax.urgentColor else lowWax.warningColor
		local wave = (math.sin(os.clock() * lowWax.pulseFrequencyHz * math.pi * 2) + 1) / 2
		local blend = lowWax.minColorBlend + (lowWax.maxColorBlend - lowWax.minColorBlend) * wave
		fillFrame.BackgroundColor3 = baseColor:Lerp(warningColor, blend)
	end)
end

return WaxBar

--!strict
-- The entire HUD: one vertical wax bar. Reads as a melt line — a candle column that lowers,
-- with a bright molten strip at the top edge. Dims while snuffed. Nothing else, by design.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

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

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			fillFrame.Size = UDim2.fromScale(1, math.clamp(entry.wax, 0, 1))
			ceiling.Size = UDim2.fromScale(1, math.clamp(1 - entry.maxWax, 0, 1))
			local lit = entry.isLit and entry.alive
			fillFrame.BackgroundColor3 = if lit then Color3.fromRGB(235, 225, 200) else Color3.fromRGB(120, 115, 105)
			meltLine.Visible = lit
		end
	end)
end

return WaxBar

--!strict
-- Bare-text Basin offer list. Appears when the server sends offers; choose by tapping a line
-- or pressing its number key. Unstyled by design — grey-box UI.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local BasinPrompt = {}

local player = Players.LocalPlayer

type OfferPayload = { id: string, displayName: string, toolId: string?, waxGranted: number }

local NUMBER_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local gui: ScreenGui? = nil

local function close()
	local current = gui
	if current ~= nil then
		current:Destroy()
		gui = nil
	end
	for index = 1, #NUMBER_KEYS do
		ContextActionService:UnbindAction("WickBasinChoice" .. index)
	end
end

local function choose(index: number)
	Remotes.get("BasinChoose"):FireServer(index)
	close()
end

local function show(offers: { OfferPayload })
	close()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WickBasin"
	screen.ResetOnSpawn = false

	local list = Instance.new("Frame")
	list.AnchorPoint = Vector2.new(0.5, 0.5)
	list.Position = UDim2.fromScale(0.5, 0.5)
	list.Size = UDim2.fromScale(0.5, 0.4)
	list.BackgroundColor3 = Color3.fromRGB(15, 14, 17)
	list.BackgroundTransparency = 0.2
	list.BorderSizePixel = 0
	list.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 30)
	header.BackgroundTransparency = 1
	header.TextColor3 = Color3.fromRGB(255, 180, 80)
	header.TextScaled = true
	header.Text = "THE BASIN — choose what it takes"
	header.Parent = list

	for index, offer in offers do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 34)
		button.BackgroundColor3 = Color3.fromRGB(35, 32, 38)
		button.BorderSizePixel = 0
		button.TextColor3 = Color3.fromRGB(230, 225, 215)
		button.TextScaled = true
		local toolNote = if offer.toolId ~= nil then " (" .. offer.toolId .. ")" else ""
		button.Text = string.format("[%d] %s%s  —  +%.2f wax", index, offer.displayName, toolNote, offer.waxGranted)
		button.Activated:Connect(function()
			choose(index)
		end)
		button.Parent = list

		if NUMBER_KEYS[index] ~= nil then
			ContextActionService:BindAction("WickBasinChoice" .. index, function(_name, inputState)
				if inputState == Enum.UserInputState.Begin then
					choose(index)
				end
				return Enum.ContextActionResult.Sink
			end, false, NUMBER_KEYS[index])
		end
	end

	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
end

function BasinPrompt.start()
	Remotes.get("BasinOffers").OnClientEvent:Connect(function(offers: { OfferPayload })
		if typeof(offers) == "table" and #offers > 0 then
			show(offers)
		end
	end)
end

return BasinPrompt

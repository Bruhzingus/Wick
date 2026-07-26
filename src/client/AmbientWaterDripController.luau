--!strict
-- Rare sound-only cave ambience. The local client places an invisible spatial emitter just below a
-- real roof hit when possible; it has no visual, collision, server state, or gameplay consequence.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local AudioCues = require(script.Parent.AudioCues)

local AmbientWaterDripController = {}

local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local player = Players.LocalPlayer
local rng = Random.new()
local nextDripAt = math.huge

local function dripConfig()
	return Config.Feel.ambientWaterDrip
end

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function reschedule(now: number)
	local config = dripConfig()
	nextDripAt = now + rng:NextNumber(config.minIntervalSeconds, config.maxIntervalSeconds)
end

local function sourcePosition(root: BasePart): Vector3
	local config = dripConfig()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = root.Parent
	if character ~= nil then
		params.FilterDescendantsInstances = { character }
	end
	local hit =
		workspace:Raycast(root.Position + Vector3.yAxis * 1.5, Vector3.yAxis * config.ceilingSearchHeight, params)
	if hit ~= nil and hit.Normal.Y <= config.ceilingNormalMaxY then
		return hit.Position + hit.Normal * config.sourceInset
	end
	return root.Position + Vector3.yAxis * config.fallbackHeight
end

local function playDrip(root: BasePart)
	local config = dripConfig()
	local emitter = Instance.new("Part")
	emitter.Name = "WickAmbientWaterDrip"
	emitter.Size = Vector3.one * 0.05
	emitter.Position = sourcePosition(root)
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.CastShadow = false
	emitter.Parent = workspace
	AudioCues.playAt("AmbientWaterDrip", emitter)
	Debris:AddItem(emitter, config.emitterLifetimeSeconds)
end

local function expeditionChanged()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		reschedule(os.clock())
	else
		nextDripAt = math.huge
	end
end

function AmbientWaterDripController.start()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(expeditionChanged)
	expeditionChanged()

	RunService.Heartbeat:Connect(function()
		if not dripConfig().enabled or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
			return
		end
		local now = os.clock()
		if now < nextDripAt then
			return
		end
		local root = localRoot()
		if root ~= nil then
			playDrip(root)
		end
		reschedule(now)
	end)
end

return AmbientWaterDripController

--!strict
-- Sound-only roof drip presentation used by AmbientCaveDirector. It accepts no fallback position:
-- if the local cave has no believable ceiling source, the director spends this attempt on silence.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local AudioCues = require(script.Parent.AudioCues)

local AmbientWaterDripController = {}

local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local player = Players.LocalPlayer
local started = false
local activeEmitter: BasePart? = nil
local rng = Random.new()

local function dripConfig()
	return Config.Feel.ambientWaterDrip
end

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function sourcePosition(root: BasePart): Vector3?
	local config = dripConfig()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local characters: { Instance } = {}
	for _, candidate in Players:GetPlayers() do
		local character = candidate.Character
		if character ~= nil then
			table.insert(characters, character)
		end
	end
	params.FilterDescendantsInstances = characters
	params.IgnoreWater = true
	for _attempt = 1, config.sourceSearchAttempts do
		local yaw = rng:NextNumber(-math.pi, math.pi)
		local distance = rng:NextNumber(config.sourceMinDistance, config.sourceMaxDistance)
		local offset = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * distance
		local hit = workspace:Raycast(
			root.Position + offset + Vector3.yAxis * 1.5,
			Vector3.yAxis * config.ceilingSearchHeight,
			params
		)
		if hit ~= nil and hit.Normal.Y <= config.ceilingNormalMaxY then
			return hit.Position + hit.Normal * config.sourceInset
		end
	end
	return nil
end

local function playDrip(root: BasePart): boolean
	local config = dripConfig()
	local position = sourcePosition(root)
	if position == nil then
		return false
	end
	local emitter = Instance.new("Part")
	emitter.Name = "WickAmbientWaterDrip"
	emitter.Size = Vector3.one * 0.05
	emitter.Position = position
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.CastShadow = false
	emitter.Parent = workspace
	if not AudioCues.playAt("AmbientWaterDrip", emitter) then
		emitter:Destroy()
		return false
	end
	activeEmitter = emitter
	emitter.Destroying:Connect(function()
		if activeEmitter == emitter then
			activeEmitter = nil
		end
	end)
	Debris:AddItem(emitter, config.emitterLifetimeSeconds)
	return true
end

function AmbientWaterDripController.tryPlay(): boolean
	if not dripConfig().enabled or player:GetAttribute(EXPEDITION_ATTRIBUTE) ~= true then
		return false
	end
	local root = localRoot()
	return if root ~= nil then playDrip(root) else false
end

function AmbientWaterDripController.start()
	if started then
		return
	end
	started = true
	-- Scheduling belongs entirely to AmbientCaveDirector. This hook only guarantees a drip that
	-- began at the end of an expedition cannot leak into the lobby.
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(function()
		if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
			return
		end
		local emitter = activeEmitter
		if emitter ~= nil then
			emitter:Destroy()
			activeEmitter = nil
		end
	end)
end

return AmbientWaterDripController

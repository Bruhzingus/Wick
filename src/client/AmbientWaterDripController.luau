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
	local character = root.Parent
	if character ~= nil then
		params.FilterDescendantsInstances = { character }
	end
	local hit =
		workspace:Raycast(root.Position + Vector3.yAxis * 1.5, Vector3.yAxis * config.ceilingSearchHeight, params)
	if hit ~= nil and hit.Normal.Y <= config.ceilingNormalMaxY then
		return hit.Position + hit.Normal * config.sourceInset
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
	AudioCues.playAt("AmbientWaterDrip", emitter)
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
	-- Kept as an explicit lifecycle hook beside the other controllers. Scheduling belongs entirely
	-- to AmbientCaveDirector; this module has no connection or timer of its own.
end

return AmbientWaterDripController

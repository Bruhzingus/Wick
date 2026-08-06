--!strict
-- Local presentation for server-confirmed Stone Warden events. Pickup authority, ceiling triggers,
-- pursuit, and contact remain server-owned; this controller only renders the wake tremor and audio.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local StoneWardenController = {}

local player = Players.LocalPlayer
local shakeStartedAt = 0
local shakeEndsAt = 0
local shakeSeed = 0

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function emitterAt(position: Vector3): BasePart
	local emitter = Instance.new("Part")
	emitter.Name = "WickWardenAudio"
	emitter.Size = Vector3.one * 0.1
	emitter.Position = position
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.CastShadow = false
	emitter.Parent = Workspace
	Debris:AddItem(emitter, Config.StoneWarden.presentationEmitterLifetime)
	return emitter
end

local function handleCollapse(payload: { [string]: any })
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local root = localRoot()
	if root == nil or (root.Position - position).Magnitude > Config.StoneWarden.collapsePresentationRadius then
		return
	end
	AudioCues.playAt("WardenWake", emitterAt(position))
	local now = os.clock()
	shakeStartedAt = now
	shakeEndsAt = math.max(shakeEndsAt, now + Config.StoneWarden.collapseShakeSeconds)
	shakeSeed += 1
end

local function handleAttack(payload: { [string]: any })
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	AudioCues.playAt("WardenAttack", emitterAt(position))
	if payload.victimId == player.UserId then
		AudioCues.play(Config.Threats.visuals.procedural.attackAudio.victimCueName)
	end
end

function StoneWardenController.start()
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if typeof(payload) ~= "table" then
			return
		end
		if kind == "wardenCollapse" then
			handleCollapse(payload)
		elseif kind == "wardenAttack" then
			handleAttack(payload)
		end
	end)

	RunService:BindToRenderStep("WickWardenPresentation", Enum.RenderPriority.Camera.Value + 5, function()
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		if camera == nil or now >= shakeEndsAt then
			return
		end
		local config = Config.StoneWarden
		local duration = math.max(config.collapseShakeSeconds, 0.001)
		local remaining = math.clamp((shakeEndsAt - now) / duration, 0, 1)
		local phase = (now - shakeStartedAt) * config.collapseShakeFrequency + shakeSeed * 1.37
		local envelope = remaining * remaining
		local x = math.sin(phase * 1.17) * config.collapseShakeStuds * envelope
		local y = math.cos(phase * 1.53) * config.collapseShakeStuds * envelope
		local angle = math.rad(config.collapseShakeDegrees) * envelope
		camera.CFrame = camera.CFrame
			* CFrame.new(x, y, 0)
			* CFrame.Angles(math.cos(phase * 0.83) * angle * 0.55, 0, math.sin(phase) * angle)
	end)
end

return StoneWardenController

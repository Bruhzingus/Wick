--!strict
-- Local presentation for server-confirmed Stone Warden events. Pickup authority, ceiling triggers,
-- pursuit, contact and the fold through an opening remain server-owned; this controller only renders
-- the floor moving, the footfalls landing, and the audio around all of it.
--
-- WHY THE FLOOR MOVES AT ALL. Everything else in this cave that can kill you announces itself with a
-- sound, and a sound in a reverberant space is the one thing a player cannot reliably locate — which
-- is correct for an ambush predator and wrong for a set-piece the design says you are meant to RUN
-- from. A Warden is twelve studs of rock walking; you should feel it through the floor before you have
-- worked out which corridor it is in, and you should feel it get worse as it closes. That is the
-- difference between a threat you flee and a threat you get surprised by.
--
-- The tremor is read from the body's own replicated position through Config/StoneWarden.presence.tag
-- rather than from a stream of server messages: the position is already replicating, and a shake
-- driven by it cannot drift, stutter on a dropped remote, or keep shaking after the Warden is gone.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CameraMotionController = require(script.Parent.CameraMotionController)

local StoneWardenController = {}

local player = Players.LocalPlayer

local RUMBLE_KEY = "WardenRumble"

local trackedWardens: { [Model]: true } = {}
local presenceEmitter: BasePart? = nil
local nextPresenceCheckAt = 0

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

-- One decaying camera event. Impulses stack rather than replacing each other, so a footfall landing
-- during the wake adds to it instead of cutting it off. The stacking, the cap on it and the ceiling on
-- the sum are `CameraMotionController`'s job now; the numbers stay here, in the Warden's own config,
-- because how heavy this creature reads is part of the creature.
local function addShake(duration: number, studs: number, degrees: number, frequency: number)
	CameraMotionController.impulse({
		studs = studs,
		degrees = degrees,
		frequencyRadians = frequency,
		durationSeconds = duration,
	})
end

-- Distance from the player to the nearest live Warden, and how hard that one is currently working.
-- Returns nil when there is none in the world, which is the ordinary case on almost every floor.
local function nearestWarden(): (number?, number)
	local root = localRoot()
	if root == nil then
		return nil, 0
	end
	local closest: number? = nil
	local moving = 0
	for model in trackedWardens do
		local body = model.PrimaryPart
		if model.Parent == nil or body == nil then
			continue
		end
		local distance = (body.Position - root.Position).Magnitude
		if closest == nil or distance < closest then
			closest = distance
			local velocity = body.AssemblyLinearVelocity
			moving = math.clamp(
				Vector3.new(velocity.X, 0, velocity.Z).Magnitude / math.max(Config.StoneWarden.walkSpeed, 0.001),
				0,
				1
			)
		end
	end
	return closest, moving
end

-- The low bed the body carries with it, played off the body itself so it pans and occludes like the
-- real object it is. Re-checked on a slow timer rather than every frame: the cue is looped and keyed
-- by its emitter, so re-issuing it on the same part is free, and the only work here is the swap.
local function updatePresenceAudio(distance: number?)
	local presence = Config.StoneWarden.presence
	local target: BasePart? = nil
	if distance ~= nil and distance <= presence.loopRadius then
		for model in trackedWardens do
			local body = model.PrimaryPart
			if model.Parent ~= nil and body ~= nil then
				target = body
				break
			end
		end
	end
	if target == presenceEmitter then
		if target ~= nil then
			AudioCues.playAt(presence.loopCueName, target)
		end
		return
	end
	AudioCues.stop(presence.loopCueName)
	presenceEmitter = target
	if target ~= nil then
		AudioCues.playAt(presence.loopCueName, target)
	end
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
	local config = Config.StoneWarden
	addShake(
		config.collapseShakeSeconds,
		config.collapseShakeStuds,
		config.collapseShakeDegrees,
		config.collapseShakeFrequency
	)
end

-- One beat of the wake. Each carries its own floor movement and, for the two that are a sound as well
-- as a motion, its own cue. Scaled by distance like everything else here, so a Warden waking two rooms
-- away is felt rather than staged.
local function handleBeat(payload: { [string]: any })
	local position = payload.position
	local beat = payload.beat
	if typeof(position) ~= "Vector3" or type(beat) ~= "string" then
		return
	end
	local root = localRoot()
	if root == nil then
		return
	end
	local distance = (root.Position - position).Magnitude
	if distance > Config.StoneWarden.collapsePresentationRadius then
		return
	end
	local falloff = 1 - math.clamp(distance / Config.StoneWarden.collapsePresentationRadius, 0, 1)
	falloff *= falloff

	local spec = Config.StoneWarden.emergenceStages.beatShake[beat]
	if spec ~= nil then
		addShake(spec.seconds, spec.studs * falloff, spec.degrees * falloff, spec.frequency)
	end
	if beat == "breach" then
		AudioCues.playAt("WardenSqueeze", emitterAt(position))
	elseif beat == "roar" then
		AudioCues.playAt("WardenRoar", emitterAt(position))
	end
end

-- A SOLE LANDING. The single most important sound this creature makes: it is the only cue in the
-- encounter that tells a player how fast it is closing, because it arrives on the Warden's cadence
-- rather than on a timer.
local function handleStep(payload: { [string]: any })
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local root = localRoot()
	if root == nil then
		return
	end
	local presence = Config.StoneWarden.presence
	local distance = (root.Position - position).Magnitude
	if distance > presence.stepPresentationRadius then
		return
	end
	local strength = if type(payload.strength) == "number" then math.clamp(payload.strength, 0, 1) else 1

	if distance <= presence.stepAudioRadius then
		AudioCues.playAt("WardenStep", emitterAt(position), nil, 0.55 + strength * 0.45)
	end
	-- Quadratic, so the last few studs carry most of it. A footfall you feel at sixty studs and at six
	-- studs equally would tell a player nothing about where it is.
	local falloff = 1 - math.clamp(distance / presence.stepPresentationRadius, 0, 1)
	falloff = falloff * falloff * strength
	addShake(
		presence.stepShakeSeconds,
		presence.stepShakeStuds * falloff,
		presence.stepShakeDegrees * falloff,
		presence.stepShakeFrequency
	)
end

local function handleSqueeze(payload: { [string]: any })
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local root = localRoot()
	if root == nil or (root.Position - position).Magnitude > Config.StoneWarden.collapsePresentationRadius then
		return
	end
	AudioCues.playAt("WardenSqueeze", emitterAt(position))
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
	local presence = Config.StoneWarden.presence
	for _, instance in CollectionService:GetTagged(presence.tag) do
		if instance:IsA("Model") then
			trackedWardens[instance] = true
		end
	end
	CollectionService:GetInstanceAddedSignal(presence.tag):Connect(function(instance)
		if instance:IsA("Model") then
			trackedWardens[instance] = true
		end
	end)
	CollectionService:GetInstanceRemovedSignal(presence.tag):Connect(function(instance)
		if instance:IsA("Model") then
			trackedWardens[instance] = nil
		end
	end)

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if typeof(payload) ~= "table" then
			return
		end
		if kind == "wardenCollapse" then
			handleCollapse(payload)
		elseif kind == "wardenBeat" then
			handleBeat(payload)
		elseif kind == "wardenStep" then
			handleStep(payload)
		elseif kind == "wardenSqueeze" then
			handleSqueeze(payload)
		elseif kind == "wardenAttack" then
			handleAttack(payload)
		end
	end)

	RunService:BindToRenderStep("WickWardenPresentation", Enum.RenderPriority.Camera.Value + 5, function()
		local now = os.clock()
		local distance, moving = nearestWarden()
		if now >= nextPresenceCheckAt then
			nextPresenceCheckAt = now + 0.5
			updatePresenceAudio(distance)
		end

		-- THE SUSTAINED BED. Not an event — this is the floor under a walking twelve-stud body, and it
		-- exists whenever one is close enough for that to be true. It never stops on its own; it stops
		-- because the Warden is further away or dead, which is exactly what a sustained contribution is
		-- for: it is recomputed every frame from the body's own replicated position, and released the
		-- frame there is nothing near enough to make it.
		if distance == nil or distance >= presence.rumbleRadius then
			CameraMotionController.setSustained(RUMBLE_KEY, nil)
			return
		end
		local closeness = 1 - distance / presence.rumbleRadius
		local weight = closeness * closeness * (1 - presence.rumbleMovingBonus + presence.rumbleMovingBonus * moving)
		local phase = now * presence.rumbleFrequency
		CameraMotionController.setSustained(RUMBLE_KEY, {
			x = math.sin(phase * 1.11) * presence.rumbleStuds * weight,
			y = math.cos(phase * 1.43) * presence.rumbleStuds * weight,
			z = 0,
			pitch = math.cos(phase * 0.67) * math.rad(presence.rumbleDegrees) * weight * 0.5,
			yaw = 0,
			roll = math.sin(phase * 0.91) * math.rad(presence.rumbleDegrees) * weight,
		})
	end)
end

return StoneWardenController

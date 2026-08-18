--!strict
-- Plays the wick-pack creatures through this game's mixer.
--
-- TWO CHANNELS, because the two kinds of creature sound have opposite lifetimes:
--
--   ONE-SHOTS arrive as a `RunEvent` carrying a cue name and a world position — a Gnawer's charge
--   warning, a Longarm's snap. They are moments, they are over before anything about the creature
--   changes, and they are played on a throwaway anchor exactly the way the dynamite blast already is.
--
--   LOOPS are a STATE, and are driven by CollectionService tags on the creature's own model rather
--   than by an event. That matters: a Gnawer has been eating since the floor was built, and a player
--   who walks into earshot ten minutes later has to start hearing it. A one-shot "begin the loop"
--   broadcast would only ever reach whoever was already listening when it fired.
--
-- WHY THE LOOP EMITTER IS THE CREATURE ITSELF. Parenting the voice to the model's own root is what
-- lets `AudioCues` apply rolloff and occlusion from where the body actually is, so a Gnawer heard
-- through a wall is filtered like something through a wall — which is the entire mechanic, since
-- hearing one eating is how a player learns a room is dangerous before entering it.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local EnemyAudioController = {}

-- Mirrors server/EnemySystem/EnemyAudio's tag scheme. Kept as a literal rather than required across
-- the boundary because a client must not depend on a server module.
local LOOP_TAG_PREFIX = "WickEnemyLoop_"
local LOOP_CUES = { "GnawerEat", "GrubIdle", "QueenChurn" }

-- Every model currently running each loop, so a tag removal can stop precisely that body's voice.
local running: { [string]: { [Model]: BasePart } } = {}

local function emitterFor(model: Model): BasePart?
	local root = model.PrimaryPart
	if root ~= nil and root.Parent ~= nil then
		return root
	end
	-- A pack body renames its root to HumanoidRootPart when a mover is attached; fall back to it so a
	-- creature whose PrimaryPart was cleared still sounds from the right place.
	local named = model:FindFirstChild("HumanoidRootPart")
	if named ~= nil and named:IsA("BasePart") then
		return named
	end
	return nil
end

-- Loops whose body was not ready when the tag arrived, retried until it is. See `startLoop`.
local pending: { [Model]: { [string]: boolean } } = {}

local function startLoop(cueName: string, model: Model)
	local byModel = running[cueName]
	if byModel == nil then
		byModel = {}
		running[cueName] = byModel
	end
	if byModel[model] ~= nil then
		return
	end
	local emitter = emitterFor(model)
	if emitter == nil then
		-- NOT A FAILURE, A RACE — AND IT USED TO BE PERMANENT SILENCE.
		--
		-- The server tags the body inside the behaviour constructor, BEFORE EnemyService.track parents it
		-- (EnemySystem/*Behavior.new -> EnemyAudio.attachLoop, then EnemyService.track sets model.Parent).
		-- So the model reaches us already tagged and `GetInstanceAddedSignal` fires the instant the Model
		-- itself replicates — which is routinely before its children and its PrimaryPart reference do.
		--
		-- `emitterFor` then finds nothing and this function used to simply return. The tag stayed on the
		-- model forever, so no further signal could ever fire, and that creature's loop was silent for the
		-- rest of the run. It cost the Gnawer's eat loop, every grub's idle and the Queen's churn — three
		-- of the five cues SOUND.md calls mechanics.
		--
		-- Queue it instead and let the sweep below pick it up once the body has arrived.
		local wanted = pending[model]
		if wanted == nil then
			wanted = {}
			pending[model] = wanted
		end
		wanted[cueName] = true
		return
	end
	byModel[model] = emitter
	AudioCues.playAt(cueName, emitter)
end

-- Retry queued loops. Cheap because `pending` is empty in the steady state: an entry only exists
-- between a tag arriving and that body's root replicating, and is dropped on success or on the model
-- leaving the world.
local function sweepPending()
	for model, wanted in pending do
		if model.Parent == nil then
			pending[model] = nil
			continue
		end
		local remaining = false
		for cueName in wanted do
			if CollectionService:HasTag(model, LOOP_TAG_PREFIX .. cueName) then
				startLoop(cueName, model)
				local byModel = running[cueName]
				if byModel == nil or byModel[model] == nil then
					remaining = true
				end
			end
		end
		if not remaining then
			pending[model] = nil
		end
	end
end

local function stopLoop(cueName: string, model: Model)
	-- Drop any queued retry first: a body untagged while still replicating must not start its loop a
	-- moment later, which is exactly what the sweep would otherwise do.
	local wanted = pending[model]
	if wanted ~= nil then
		wanted[cueName] = nil
		if next(wanted) == nil then
			pending[model] = nil
		end
	end

	local byModel = running[cueName]
	if byModel == nil then
		return
	end
	local emitter = byModel[model]
	if emitter == nil then
		return
	end
	byModel[model] = nil
	AudioCues.stopAt(cueName, emitter)
end

-- A cue at a world point, on an anchored part that outlives the sound. Identical in shape to
-- DynamiteController's own `playAtPoint`, and for the same reason: handing `playAt` something
-- transient starts a sound and immediately deletes its emitter, which is what "no sound" sounds like.
local function playAtPoint(cueName: string, position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "WickEnemyAudioAnchor"
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	AudioCues.playAt(cueName, anchor)
	Debris:AddItem(anchor, 4)
end

function EnemyAudioController.start()
	for _, cueName in LOOP_CUES do
		local tag = LOOP_TAG_PREFIX .. cueName
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("Model") then
				startLoop(cueName, instance)
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			if instance:IsA("Model") then
				startLoop(cueName, instance)
			end
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
			if instance:IsA("Model") then
				stopLoop(cueName, instance)
			end
		end)
	end

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if kind ~= "enemyCue" or typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		local cueName = data.cue
		local position = data.position
		if typeof(cueName) == "string" and typeof(position) == "Vector3" then
			playAtPoint(cueName, position)
		end
	end)

	-- Four sweeps a second is far finer than the replication gap it covers and costs nothing while
	-- `pending` is empty, which is almost always.
	local sinceSweep = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if next(pending) == nil then
			return
		end
		sinceSweep += dt
		if sinceSweep < 0.25 then
			return
		end
		sinceSweep = 0
		sweepPending()
	end)
end

return EnemyAudioController

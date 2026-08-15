--!strict
-- Dynamite's whole client surface: the throw key, the blast-door socket marker and prompt,
-- and the blast's own shake. Decides nothing — `server/DynamiteService` owns the bag, the fuse, the
-- landing point and every consequence; this proposes a direction, names a door, and draws.
--
-- WHY THE SOCKET MARKER LIVES HERE AND NOT IN THE BUILDER. It is PER PLAYER: the yellow outline showing
-- where your charge goes appears only for somebody who is actually carrying one. A server-built marker
-- would be built for everybody, including the three teammates who have nothing to put in it — which
-- turns a piece of information ("you can open this") into decoration ("this hole is lit"). The door
-- publishes what it IS through `DynamiteVisualProtocol` attributes; the local `dynamiteCharges` from
-- `StateSync` decides whether the marker exists.
--
-- IT IS NOT A LIGHT. The marker is a fill-free Highlight with no PointLight, so it
-- outlines the interaction without illuminating the rock. The prompt is UI and was never light.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local DynamiteModel = require(ReplicatedStorage.Shared.NewModelsAndObjects.Dynamite)
local DynamiteVisualProtocol = require(ReplicatedStorage.Shared.DynamiteVisualProtocol)
local AudioCues = require(script.Parent.AudioCues)
local TouchControls = require(script.Parent.TouchControls)

local DynamiteController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local ACTION_NAME = "WickDynamite"

type DoorView = {
	model: Model,
	barrier: BasePart,
	socket: Attachment,
	-- The outlined marker model, or nil while it is not being shown. Created and destroyed rather than made
	-- transparent, so a player with no dynamite is paying for nothing at all.
	marker: Model?,
	placePrompt: ProximityPrompt,
	connections: { RBXScriptConnection },
}

local doors: { [Model]: DoorView } = {}
local carried = 0
local localDepth = 0
local controlsBound = false

-- Camera shake, driven exactly like the dripstone impact's: one envelope, decaying, seeded so two
-- blasts in quick succession do not fall into step.
local shakeStartedAt = 0
local shakeEndsAt = 0
local shakeStrength = 0
local shakeSeed = 0

--------------------------------------------------------------------------------
-- Throwing
--------------------------------------------------------------------------------

-- The client proposes only a horizontal direction at the configured range. Vertical aim never buys
-- distance and the server re-derives the landing from its own raycasts — the same contract the Decoy
-- has, so a player who has learned one throw has learned both.
local function aimPoint(): Vector3
	local origin = Vector3.zero
	local direction = Vector3.xAxis
	local character = player.Character
	if character ~= nil then
		local root = character.PrimaryPart
		if root ~= nil then
			origin = root.Position
			local horizontal = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if horizontal.Magnitude > 1e-3 then
				direction = horizontal.Unit
			end
		end
	end
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local look = camera.CFrame.LookVector
		local horizontal = Vector3.new(look.X, 0, look.Z)
		if horizontal.Magnitude > 1e-3 then
			direction = horizontal.Unit
		end
	end
	return origin + direction * Config.Dynamite.throw.range
end

local function throw()
	Remotes.get("DynamiteAction"):FireServer("throw", aimPoint())
end

--------------------------------------------------------------------------------
-- Doors
--------------------------------------------------------------------------------

local function destroyMarker(view: DoorView)
	local marker = view.marker
	if marker == nil then
		return
	end
	marker:Destroy()
	view.marker = nil
end

-- Should this door be showing a marker to THIS player right now?
--
-- Three conditions, and all three are information rather than permission: the door is still sealed,
-- nobody has already charged it, and this player is holding something to put in it. A player on
-- another floor is excluded too — without the depth check, markers two floors down would glow through
-- solid rock.
local function shouldShowMarker(view: DoorView): boolean
	if carried <= 0 then
		return false
	end
	if view.model:GetAttribute(DynamiteVisualProtocol.attributes.open) ~= true then
		return false
	end
	if view.model:GetAttribute(DynamiteVisualProtocol.attributes.charged) == true then
		return false
	end
	return view.model:GetAttribute(DynamiteVisualProtocol.attributes.depth) == localDepth
end

local function refreshDoor(view: DoorView)
	if view.model.Parent == nil then
		return
	end
	local charged = view.model:GetAttribute(DynamiteVisualProtocol.attributes.charged) == true
	local sealed = view.model:GetAttribute(DynamiteVisualProtocol.attributes.open) == true

	-- PROMPT VISIBILITY IS LOCAL, exactly as `RelightPromptController` hides a snuffed candle's
	-- impossible self-relight prompt: the server created these and they stay available to every
	-- teammate, and setting `Enabled` on a replicated instance from a client changes only this client's
	-- copy. A player with no dynamite is not shown an action they cannot take.
	view.placePrompt.Enabled = sealed and not charged and carried > 0

	if shouldShowMarker(view) then
		if view.marker == nil then
			view.marker = DynamiteModel.buildSocketMarker(view.model, view.socket.WorldCFrame)
		end
	else
		destroyMarker(view)
	end
end

local function refreshAllDoors()
	for _, view in doors do
		refreshDoor(view)
	end
end

local function releaseDoor(model: Model)
	local view = doors[model]
	if view == nil then
		return
	end
	doors[model] = nil
	for _, connection in view.connections do
		connection:Disconnect()
	end
	destroyMarker(view)
	-- The prompts are parented into the door model, so the model's own destruction takes them. Nothing
	-- to clean up here beyond our own listeners.
end

local function adoptDoor(model: Model)
	if doors[model] ~= nil or not model:IsA("Model") then
		return
	end
	local barrier = model:FindFirstChild("BlastDoorBarrier")
	if barrier == nil or not barrier:IsA("BasePart") then
		return
	end
	local socket = barrier:FindFirstChild(DynamiteVisualProtocol.socketAttachmentName)
	if socket == nil or not socket:IsA("Attachment") then
		return
	end

	local placePrompt = Instance.new("ProximityPrompt")
	placePrompt.Name = "PlaceDynamite"
	placePrompt.ActionText = Config.Dynamite.door.placeActionText
	placePrompt.ObjectText = Config.Dynamite.door.objectText
	placePrompt.HoldDuration = Config.Dynamite.door.socketHoldSeconds
	placePrompt.MaxActivationDistance = Config.Dynamite.door.socketRange
	placePrompt.RequiresLineOfSight = false
	placePrompt.Enabled = false
	placePrompt.Parent = socket

	local view: DoorView = {
		model = model,
		barrier = barrier,
		socket = socket,
		marker = nil,
		placePrompt = placePrompt,
		connections = {},
	}

	-- The barrier part is the KEY the server looks the door up by. Sending the model would work too;
	-- sending the part means the server never has to trust a name.
	table.insert(
		view.connections,
		placePrompt.Triggered:Connect(function()
			Remotes.get("DynamiteAction"):FireServer("place", barrier)
		end)
	)
	for _, attribute in
		{
			DynamiteVisualProtocol.attributes.open,
			DynamiteVisualProtocol.attributes.charged,
			DynamiteVisualProtocol.attributes.depth,
		}
	do
		table.insert(
			view.connections,
			model:GetAttributeChangedSignal(attribute):Connect(function()
				refreshDoor(view)
			end)
		)
	end

	doors[model] = view
	refreshDoor(view)
end

--------------------------------------------------------------------------------
-- Presentation
--------------------------------------------------------------------------------

-- A cue played AT a world point, on an anchored part that outlives the sound.
--
-- `AudioCues.playAt` attaches to whatever instance it is handed, so handing it something transient —
-- or the charge model itself, which `detonate` destroys on the same frame — starts a sound and then
-- immediately deletes its emitter. That is exactly what "no explosion sound" sounds like.
local function playAtPoint(cueName: string, position: Vector3, lifetimeSeconds: number)
	local anchor = Instance.new("Part")
	anchor.Name = "WickDynamiteAudioAnchor"
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
	game:GetService("Debris"):AddItem(anchor, math.max(lifetimeSeconds, 0.1))
end

local function beginShake(distance: number)
	local radius = math.max(Config.Dynamite.blast.shakeRadius, 0.001)
	-- Every player on this floor gets a restrained concussion. Distance only decides how much stronger
	-- it becomes near the charge; the event handler has already excluded every other floor.
	local strength =
		math.max(math.clamp(Config.Dynamite.blast.floorShakeStrength, 0, 1), math.clamp(1 - distance / radius, 0, 1))
	local now = os.clock()
	local dripstone = Config.Hazards.unstableDripstone
	if now >= shakeEndsAt then
		shakeStrength = strength
	else
		shakeStrength = math.max(shakeStrength, strength)
	end
	shakeStartedAt = now
	shakeEndsAt = math.max(shakeEndsAt, now + dripstone.impactShakeSeconds)
	shakeSeed += 1
end

local function localPosition(): Vector3?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character.PrimaryPart
	if root == nil then
		return nil
	end
	return root.Position
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

local function bindControls()
	if controlsBound then
		return
	end
	controlsBound = true
	local control = Config.Feel.controls.dynamite
	-- No engine touch button (`false`); client/TouchControls places this one beside the tools.
	ContextActionService:BindAction(ACTION_NAME, function(_name: string, inputState: Enum.UserInputState)
		if controlsBound and inputState == Enum.UserInputState.Begin then
			throw()
		end
		return Enum.ContextActionResult.Sink
	end, false, control.keyCode)
	if UserInputService.TouchEnabled then
		TouchControls.register({
			id = ACTION_NAME,
			label = control.displayName,
			row = "tool",
			order = control.touchOrder,
			activated = function()
				if controlsBound then
					throw()
				end
			end,
		})
		TouchControls.setVisible(ACTION_NAME, true)
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	controlsBound = false
	ContextActionService:UnbindAction(ACTION_NAME)
	TouchControls.setVisible(ACTION_NAME, false)
end

local function refreshControls()
	if player:GetAttribute(EXPEDITION_ATTRIBUTE) == true then
		bindControls()
	else
		unbindControls()
	end
end

function DynamiteController.start()
	if not Config.Dynamite.enabled then
		return
	end

	for _, model in CollectionService:GetTagged(DynamiteVisualProtocol.doorTag) do
		if model:IsA("Model") then
			adoptDoor(model)
		end
	end
	CollectionService:GetInstanceAddedSignal(DynamiteVisualProtocol.doorTag):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			adoptDoor(instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(DynamiteVisualProtocol.doorTag):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			releaseDoor(instance)
		end
	end)

	Remotes.get("StateSync").OnClientEvent:Connect(function(entries: { Remotes.StateEntry })
		for _, entry in entries do
			if entry.playerId ~= player.UserId then
				continue
			end
			local nextCarried = math.max(0, math.floor(entry.dynamiteCharges or 0))
			if nextCarried ~= carried or entry.depth ~= localDepth then
				carried = nextCarried
				localDepth = entry.depth
				-- Only when something actually changed: this fires at the wax tick rate, and rebuilding
				-- every marker on every tick would be the most expensive thing in the file.
				refreshAllDoors()
			end
			break
		end
	end)

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if typeof(kind) ~= "string" or typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: unknown }
		if kind == "dynamiteExploded" then
			local position = data.position
			local depth = data.depth
			if typeof(position) == "Vector3" and typeof(depth) == "number" and depth == localDepth then
				-- One short non-spatial boom. Everyone on this floor hears the same single explosion;
				-- there is no nearby second layer to turn it into a cluster of blasts.
				AudioCues.play(Config.Dynamite.audio.blastCue)
				local origin = localPosition()
				beginShake(if origin ~= nil then (position - origin).Magnitude else Config.Dynamite.blast.shakeRadius)
			end
		elseif kind == "dynamiteLit" then
			-- The fuse. Heard by EVERYONE in range, not only whoever struck it: a charge burning down is
			-- the single most useful thing a teammate can be told about, and it is the only warning a
			-- player standing on the wrong side of a door is going to get.
			local position = data.position
			local fuseSeconds = data.fuseSeconds
			local depth = data.depth
			if typeof(position) == "Vector3" and typeof(depth) == "number" and depth == localDepth then
				playAtPoint(
					Config.Dynamite.audio.fuseCue,
					position,
					if typeof(fuseSeconds) == "number" then fuseSeconds else 3
				)
			end
		elseif kind == "floor" or kind == "countdown" then
			-- A floor transition invalidates every door view we are holding; the tag signals rebuild
			-- them as the new floor replicates.
			refreshAllDoors()
		end
	end)

	refreshControls()
	player:GetAttributeChangedSignal(EXPEDITION_ATTRIBUTE):Connect(refreshControls)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local marker = Config.Dynamite.visual
		-- The marker breathes rather than sitting flat. A static glow reads as a texture; a slow pulse
		-- reads as something waiting for you.
		local pulse = (math.sin(now * math.pi * 2 / math.max(marker.socketPulseSeconds, 0.001)) + 1) / 2
		local transparency = math.clamp(marker.socketGlowTransparency + pulse * marker.socketPulseDepth, 0, 1)
		for _, view in doors do
			local markerModel = view.marker
			if markerModel == nil then
				continue
			end
			local outline = markerModel:FindFirstChild("SocketOutline")
			if outline ~= nil and outline:IsA("Highlight") then
				outline.OutlineTransparency = transparency
			end
		end

		local camera = Workspace.CurrentCamera
		if camera == nil or now >= shakeEndsAt then
			return
		end
		local dripstone = Config.Hazards.unstableDripstone
		local duration = math.max(dripstone.impactShakeSeconds, 0.001)
		local remaining = math.clamp((shakeEndsAt - now) / duration, 0, 1)
		local phase = (now - shakeStartedAt) * dripstone.impactShakeFrequency + shakeSeed * 1.37
		local envelope = remaining * remaining * shakeStrength
		local x = math.sin(phase * 1.17) * dripstone.impactShakeStuds * envelope
		local y = math.sin(phase * 1.63) * dripstone.impactShakeStuds * envelope
		camera.CFrame = camera.CFrame * CFrame.new(x, y, 0)
	end)
end

return DynamiteController

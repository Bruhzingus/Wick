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
local DynamiteViewmodelController = require(script.Parent.DynamiteViewmodelController)
local TouchControls = require(script.Parent.TouchControls)

local DynamiteController = {}

local player = Players.LocalPlayer
local EXPEDITION_ATTRIBUTE = "WickInExpedition"
local ACTION_NAME = "WickDynamite"
local THROW_ACTION_NAME = "WickDynamiteThrow"

-- ABOVE MINING, DELIBERATELY, AND ONLY WHILE A STICK IS OUT.
--
-- `client/MiningController` binds MouseButton1 for the WHOLE expedition, not merely while a seam is
-- in reach, so the two actions genuinely share one button. ContextActionService resolves that by
-- bind ORDER, which would make the winner depend on which controller happened to rebind last — and
-- both rebind on the expedition attribute changing. An explicit priority makes the answer a property
-- of the design instead of a property of startup order: while dynamite is in your hands, the mouse
-- throws it, and the pickaxe cannot be swung by something you are not holding.
--
-- The binding is released the instant the stick is stowed, so mining is untouched the rest of the time.
local THROW_PRIORITY = Enum.ContextActionPriority.Medium.Value + 1000

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

-- THE STICK IS EITHER OUT OR IT IS NOT. Equipping is a toggle on the dynamite key; the mouse only
-- means anything while it is out. Kept here rather than in the viewmodel because it is the thing that
-- decides whether the mouse is BOUND at all, which is input authority rather than presentation.
local equipped = false
-- `os.clock()` the mouse went down, or nil when it is not held. The wind-up is derived from it every
-- frame rather than accumulated, so a dropped frame cannot desynchronise the pose from the clock the
-- throw is measured against.
local windupStartedAt: number? = nil
local throwBound = false

-- Camera shake, driven exactly like the dripstone impact's: one envelope, decaying, seeded so two
-- blasts in quick succession do not fall into step.
local shakeStartedAt = 0
local shakeEndsAt = 0
local shakeStrength = 0
local shakeSeed = 0

--------------------------------------------------------------------------------
-- Throwing
--------------------------------------------------------------------------------

-- THE FULL 3D LOOK, pitch included. The client proposes a DIRECTION and nothing else; the server
-- throws along it and simulates the arc itself.
--
-- This used to flatten the aim to horizontal and hand over a point at exactly `range` studs, which is
-- why every throw travelled the same distance however the camera was angled — the one input a player
-- naturally reaches for was being discarded before it was sent. Now looking up lobs it further (to a
-- maximum at 45 degrees), looking flat throws it shorter, and looking down drops it near your feet.
--
-- Length is irrelevant: `DynamiteRules.throwVelocity` normalises, so a modified client cannot buy
-- range by sending a longer vector. Reach comes from config alone.
local function aimDirection(): Vector3
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local look = camera.CFrame.LookVector
		if look.Magnitude > 1e-3 then
			return look.Unit
		end
	end
	-- No camera to read: fall back to the body's own facing, flat. A throw that goes somewhere sensible
	-- beats a throw the server refuses.
	local character = player.Character
	if character ~= nil then
		local root = character.PrimaryPart
		if root ~= nil then
			local horizontal = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if horizontal.Magnitude > 1e-3 then
				return horizontal.Unit
			end
		end
	end
	return Vector3.xAxis
end

-- How far the wind-up has travelled right now, 0..1. Smoothstepped for the same reason the pickaxe's
-- prime is: an arm that cocks at a constant rate reads as a machine.
local function windupAlpha(now: number): number
	local startedAt = windupStartedAt
	if startedAt == nil then
		return 0
	end
	local seconds = math.max(Config.Dynamite.viewmodel.windupSeconds, 0.01)
	local alpha = math.clamp((now - startedAt) / seconds, 0, 1)
	return alpha * alpha * (3 - 2 * alpha)
end

local function playDenied()
	AudioCues.play(Config.Dynamite.audio.deniedCue)
end

--------------------------------------------------------------------------------
-- Equipping
--------------------------------------------------------------------------------

-- The mouse is bound ONLY while a stick is out (see THROW_PRIORITY). Split from `setEquipped` so the
-- unbind can also be reached from teardown, where the equipped flag is being cleared for other reasons.
local function bindThrow()
	if throwBound then
		return
	end
	throwBound = true
	ContextActionService:BindActionAtPriority(
		THROW_ACTION_NAME,
		function(_name: string, inputState: Enum.UserInputState)
			if not equipped then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Begin then
				DynamiteController.beginWindup()
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				DynamiteController.releaseThrow()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		THROW_PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
end

local function unbindThrow()
	if not throwBound then
		return
	end
	throwBound = false
	ContextActionService:UnbindAction(THROW_ACTION_NAME)
end

local function setEquipped(wanted: boolean)
	if equipped == wanted then
		return
	end
	equipped = wanted
	windupStartedAt = nil
	DynamiteViewmodelController.setHeld(wanted)
	if wanted then
		bindThrow()
		AudioCues.play(Config.Dynamite.audio.equipCue)
	else
		unbindThrow()
		AudioCues.play(Config.Dynamite.audio.stowCue)
	end
	TouchControls.setActive(ACTION_NAME, wanted)
	TouchControls.setVisible(THROW_ACTION_NAME, wanted)
end

-- The dynamite key. A toggle rather than a press-to-throw, so the stick can be brought out and looked
-- at — which is the whole point of holding a thing in a game where the light is this dim.
local function toggleEquip()
	if equipped then
		setEquipped(false)
		return
	end
	if carried <= 0 then
		-- The chip already says NO DYNAMITE; this is so the key is not silent as well.
		playDenied()
		return
	end
	setEquipped(true)
end

--------------------------------------------------------------------------------
-- Throwing
--------------------------------------------------------------------------------

function DynamiteController.beginWindup()
	if not equipped or windupStartedAt ~= nil then
		return
	end
	-- A throw already in flight owns the stick until its recover finishes. Without this, holding the
	-- mouse down through the animation would start a second wind-up against a hand that is still empty.
	if DynamiteViewmodelController.isThrowing() then
		return
	end
	if carried <= 0 then
		playDenied()
		setEquipped(false)
		return
	end
	windupStartedAt = os.clock()
	AudioCues.play(Config.Dynamite.audio.windupCue)
end

function DynamiteController.releaseThrow()
	local startedAt = windupStartedAt
	windupStartedAt = nil
	if startedAt == nil or not equipped then
		return
	end
	if carried <= 0 then
		playDenied()
		setEquipped(false)
		return
	end

	local now = os.clock()
	-- Sampled BEFORE the wind-up is cleared, so the release stroke starts from the pose that is
	-- actually on screen. A quick click throws from a barely-cocked arm and still throws — the wind-up
	-- buys presentation, never range, because `throw.range` is fixed and the server owns the arc.
	DynamiteViewmodelController.beginThrow(now, windupAlpha(now))
	AudioCues.play(Config.Dynamite.audio.throwCue)
	Remotes.get("DynamiteAction"):FireServer("throw", aimDirection())
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

-- Doors currently being waited on, so a second tag/child event cannot start a second wait for the same
-- model and end up building two markers on one pocket.
local adopting: { [Model]: boolean } = {}

-- Build this client's view of a door whose parts have all arrived.
local function adoptResolvedDoor(model: Model, barrier: BasePart, socket: Attachment)
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

-- THE MARKER BUG THIS EXISTS TO FIX, and it was a replication race rather than anything geometric.
--
-- The tag lives on the door MODEL, and Roblox does not promise that a model and its descendants arrive
-- on a client together. `GetInstanceAddedSignal` therefore fires as soon as the tagged model lands,
-- which is routinely BEFORE its `BlastDoorBarrier` child and that child's socket Attachment. The old
-- code called `FindFirstChild`, found nothing, and returned — permanently, because nothing ever tried
-- that door again. The door then had no marker and no prompt for the rest of the run, which is exactly
-- the "there still is not the yellow stick of dynamite" symptom.
--
-- `WaitForChild` on its own thread fixes it: the wait costs nothing while the parts are in flight and
-- resolves the instant they land. The timeout is a real bound rather than an infinite yield, so a
-- genuinely malformed door warns once instead of leaking a thread that waits forever.
local function adoptDoor(model: Model)
	if doors[model] ~= nil or adopting[model] or not model:IsA("Model") then
		return
	end
	adopting[model] = true
	task.spawn(function()
		local barrier = model:WaitForChild("BlastDoorBarrier", 10)
		local socket = if barrier ~= nil
			then barrier:WaitForChild(DynamiteVisualProtocol.socketAttachmentName, 10)
			else nil
		adopting[model] = nil

		-- Re-check everything the wait could have invalidated: the floor may have been retired, the door
		-- blown by somebody else, or this controller may have adopted it on another path meanwhile.
		if model.Parent == nil or doors[model] ~= nil then
			return
		end
		if barrier == nil or not barrier:IsA("BasePart") or socket == nil or not socket:IsA("Attachment") then
			warn("[WICK] blast door replicated without its barrier or charge pocket; no marker will show")
			return
		end
		adoptResolvedDoor(model, barrier :: BasePart, socket :: Attachment)
	end)
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
			toggleEquip()
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
					toggleEquip()
				end
			end,
		})
		TouchControls.setVisible(ACTION_NAME, true)
		-- THE THROW BUTTON, in the primary row beside MINE/STOP and visible only while a stick is out.
		-- A touch player has no button to HOLD, so the tap is the whole gesture: it winds up and
		-- releases in one call, which lands on the unprimed end of the same animation a fast click
		-- produces on desktop.
		TouchControls.register({
			id = THROW_ACTION_NAME,
			label = "THROW",
			row = "primary",
			order = 3,
			activated = function()
				if not controlsBound or not equipped then
					return
				end
				DynamiteController.beginWindup()
				DynamiteController.releaseThrow()
			end,
		})
		TouchControls.setVisible(THROW_ACTION_NAME, false)
	end
end

local function unbindControls()
	if not controlsBound then
		return
	end
	controlsBound = false
	-- Leaving the expedition takes the stick with it. Done through `setEquipped` rather than by
	-- clearing the flag, so the mouse binding is released too — a throw action left bound over the
	-- lobby would sink the first click a returning player makes on anything.
	setEquipped(false)
	DynamiteViewmodelController.destroy()
	ContextActionService:UnbindAction(ACTION_NAME)
	unbindThrow()
	TouchControls.setVisible(ACTION_NAME, false)
	TouchControls.setVisible(THROW_ACTION_NAME, false)
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

	-- THE SERVER'S ANSWER TO A THROW. The stick was spent optimistically — the animation and the sound
	-- both ran on the release — so a refusal has to put it back rather than merely report itself.
	-- `StateSync` restores the true count either way; this is what stops the intervening second from
	-- showing an empty hand the player still owns a stick for.
	Remotes.get("ActionFeedback").OnClientEvent:Connect(function(actionId: unknown, accepted: unknown)
		if actionId ~= "Dynamite" or accepted ~= false or not controlsBound then
			return
		end
		playDenied()
		if equipped then
			DynamiteViewmodelController.setHeld(true)
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

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()

		-- THE LAST STICK PUTS THE HAND AWAY BY ITSELF. Checked here rather than at the throw because the
		-- count is the server's: the throw only asked, and this is the frame the answer arrived on.
		-- Deferred until the throw's own recover has finished so the animation is never cut in half.
		if equipped and carried <= 0 and not DynamiteViewmodelController.isThrowing() then
			setEquipped(false)
		end
		DynamiteViewmodelController.setWindup(windupAlpha(now))
		DynamiteViewmodelController.update(dt, now)

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

--!strict
-- LIGHTING A WALL LAMP, from the player's side: finding the one in front of you, drawing the
-- completion circle, bowing the camera toward the wick, and telling the server when you are done.
--
-- THE SERVER DECIDES EVERYTHING THAT MATTERS. This file proposes ("begin", "commit", "cancel") and
-- draws; `server/WallLampService` owns the clock, the gate, the root and whether the lamp catches.
-- A modified client can spam commits and light nothing.
--
-- WHY THIS IS NOT A ProximityPrompt, when the Brazier and the Basin both are. Roblox's prompt gives
-- us its own hold ring, and this interaction needs three things that ring cannot do: a labelled
-- completion circle rather than an unmarked arc, a cancel the moment the player asks to move, and a
-- camera that leans toward what you are lighting. The mining swing already crosses the remote
-- boundary by hand for the same class of reason.
--
-- THE CIRCLE IS BUILT FROM SEGMENTS, not from an image or a gradient. Roblox UI has no arc
-- primitive and no radial gradient (see client/WaxBar, which solves its glow the same way), so the
-- ring is a fixed ring of small marks that light up in order — which also happens to read as a dial
-- being turned, and this is a game about a dial.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local WallLampRules = require(ReplicatedStorage.Shared.Logic.WallLampRules)
local TouchControls = require(script.Parent.TouchControls)
local UITheme = require(script.Parent.UITheme)

local WallLampController = {}

local player = Players.LocalPlayer

local SEGMENTS = 40
local TOUCH_ACTION = "WickLampLight"
local LOOK_BINDING = "WickLampLook"
-- After the Camera step (and after client/CameraController's own guard at +2), so the lean is
-- composed on top of whatever the default camera decided this frame rather than being overwritten
-- by it.
local LOOK_PRIORITY = Enum.RenderPriority.Camera.Value + 3

type Ring = {
	gui: BillboardGui,
	segments: { Frame },
	label: TextLabel,
	hint: TextLabel,
}

local ring: Ring? = nil
local currentLamp: BasePart? = nil
local holding = false
local holdStartedAt = 0
local holdSeconds = 0
-- How many Roblox ProximityPrompts are currently on screen.
--
-- WHILE ANY PROMPT IS SHOWN, THIS CONTROLLER STANDS DOWN. Prompts default to E, and so does this;
-- the completion room holds the Brazier, the Cauldron, the Descent Ladder AND the crowned lamp, so
-- without this a single press could begin lighting the lamp and end the player's run in the same
-- frame. Yielding to the prompt is the correct precedence in every case: a prompt is a specific
-- machine the player has walked up to, and the lamp is always still there afterwards.
local promptsShown = 0
-- 0..1. Eased up while lighting and back down on release, so a cancel returns the camera instead of
-- dropping it — the mouse kept moving during the hold and a hard release would snap the view.
local lookWeight = 0
local lookBound = false

local function config()
	return Config.WallLamp
end

-- THE RING. Built once and re-adorned as the player moves between lamps: a BillboardGui per lamp
-- would be one GUI per room per floor, all but one of them invisible.
local function buildRing(): Ring
	local gui = Instance.new("BillboardGui")
	gui.Name = "WickLampPrompt"
	gui.Size = UDim2.fromOffset(150, 150)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.1, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = config().interaction.promptRange + 6
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local segments: { Frame } = {}
	for index = 1, SEGMENTS do
		local angle = (index - 1) / SEGMENTS * math.pi * 2
		local mark = Instance.new("Frame")
		mark.Name = "Mark"
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		-- Placed on the circle by fraction of the billboard rather than by pixels, so the ring scales
		-- with the GUI and never has to be re-measured.
		mark.Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.38, 0.5 - math.cos(angle) * 0.38)
		mark.Size = UDim2.fromOffset(4, 10)
		mark.Rotation = math.deg(angle)
		mark.BorderSizePixel = 0
		mark.BackgroundColor3 = UITheme.palette.strokeSoft
		mark.BackgroundTransparency = 0.55
		mark.Parent = gui
		UITheme.corner(mark, 2)
		table.insert(segments, mark)
	end

	-- "LIGHTING", in the ring, while the circle fills. The one word is the whole readout: it names the
	-- verb rather than the object, because what the player needs to know is that something is
	-- happening and that letting go stops it.
	local label = Instance.new("TextLabel")
	label.Name = "Action"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.7, 0.2)
	label.BackgroundTransparency = 1
	label.Font = UITheme.font.heading
	label.TextScaled = true
	label.TextColor3 = UITheme.palette.gold
	label.Text = "Lighting"
	label.Visible = false
	label.Parent = gui
	UITheme.legible(label)

	-- The affordance before the hold begins. Deliberately the smaller of the two: an unlit lamp in a
	-- dark room should read as an object first and a button second.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, 0.5)
	hint.Size = UDim2.fromScale(0.8, 0.16)
	hint.BackgroundTransparency = 1
	hint.Font = UITheme.font.body
	hint.TextScaled = true
	hint.TextColor3 = UITheme.palette.textMuted
	hint.Text = "Hold E"
	hint.Parent = gui
	UITheme.legible(hint)

	return { gui = gui, segments = segments, label = label, hint = hint }
end

-- The ring is built once at boot, never on first use: `buildRing` waits on PlayerGui, and yielding
-- inside a render step is not something this file is allowed to do.
local function activeRing(): Ring?
	return ring
end

local function humanoid(): Humanoid?
	local character = player.Character
	return if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
end

local function characterPosition(): Vector3?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
end

-- THE LEAN, applied on top of the default camera. It is a blend rather than a takeover: at weight 1
-- the view is on the wick, and the weight itself is eased in and out so the transition in either
-- direction is something the player watches rather than something that happens to them.
local function stepLook(dt: number)
	local camera = Workspace.CurrentCamera
	local lamp = currentLamp
	if camera == nil then
		return
	end
	local rise = math.max(config().interaction.leanRiseSeconds, 0.001)
	local target = if holding and lamp ~= nil then 1 else 0
	lookWeight = if target > lookWeight
		then math.min(lookWeight + dt / rise, 1)
		else math.max(lookWeight - dt / rise, 0)

	if lookWeight <= 0.001 or lamp == nil then
		if lookWeight <= 0.001 and not holding then
			-- Fully unwound and nothing to watch: stop paying for a render step every frame.
			RunService:UnbindFromRenderStep(LOOK_BINDING)
			lookBound = false
		end
		return
	end

	local origin = camera.CFrame.Position
	local toLamp = lamp.Position - origin
	if toLamp.Magnitude < 0.05 then
		return
	end
	-- Rotation only. Moving the camera's position would break the first-person offset
	-- client/CameraController maintains from the candle's own height.
	local desired = CFrame.lookAt(origin, lamp.Position)
	camera.CFrame = camera.CFrame:Lerp(desired, lookWeight)
end

local function bindLook()
	if lookBound then
		return
	end
	lookBound = true
	RunService:BindToRenderStep(LOOK_BINDING, LOOK_PRIORITY, stepLook)
end

local function stopHold(notifyServer: boolean)
	if not holding then
		return
	end
	holding = false
	if notifyServer then
		Remotes.get("LampAction"):FireServer("cancel")
	end
	local current = ring
	if current ~= nil then
		current.label.Visible = false
		current.hint.Visible = true
	end
	-- The look binding is deliberately NOT unbound here: `stepLook` keeps running until the weight has
	-- eased back to zero, which is the whole reason a cancel does not snap the camera.
end

local function beginHold(lamp: BasePart)
	if holding then
		return
	end
	holding = true
	holdStartedAt = os.clock()
	local variant = lamp:GetAttribute(config().variantAttribute)
	holdSeconds = WallLampRules.holdSecondsFor(if variant == "Main" then "Main" else "Room")
	local current = activeRing()
	if current ~= nil then
		current.label.Visible = true
		current.hint.Visible = false
	end
	bindLook()
	Remotes.get("LampAction"):FireServer("begin", lamp)
end

-- May this player start a hold at all right now? Shared by the key, the gamepad button and the touch
-- button so all three refuse for the same reasons.
local function canBegin(): boolean
	local lamp = currentLamp
	return not holding
		and promptsShown == 0
		and lamp ~= nil
		and lamp.Parent ~= nil
		and lamp:GetAttribute(config().litAttribute) ~= true
end

-- Is the player asking to move? A held movement key with a walk speed of zero still reports a
-- direction, which is exactly what makes this readable: the server has rooted them, and this is the
-- input they are producing anyway.
local function wantsToMove(): boolean
	local body = humanoid()
	if body == nil then
		return false
	end
	if body.MoveDirection.Magnitude > 0.05 then
		return true
	end
	return body.Jump
end

-- THE NEAREST LAMP THIS PLAYER COULD ACTUALLY LIGHT. Found by tag rather than from a replicated
-- list, the same way the water surfaces and the descent cage are found: the world already knows
-- where its lamps are, and a second copy of that on the wire could only ever disagree with it.
local function nearestLamp(): BasePart?
	local origin = characterPosition()
	if origin == nil then
		return nil
	end
	local range = config().interaction.promptRange
	local best: BasePart? = nil
	local bestDistance = range
	for _, anchor in CollectionService:GetTagged(config().tag) do
		if not anchor:IsA("BasePart") or anchor:GetAttribute(config().litAttribute) == true then
			continue
		end
		local distance = (anchor.Position - (origin :: Vector3)).Magnitude
		if distance <= bestDistance then
			bestDistance = distance
			best = anchor
		end
	end
	return best
end

local function drawProgress(progress: number)
	local current = ring
	if current == nil then
		return
	end
	local filled = math.floor(math.clamp(progress, 0, 1) * SEGMENTS + 0.0001)
	for index, mark in current.segments do
		local isLit = index <= filled
		mark.BackgroundColor3 = if isLit then UITheme.palette.ember else UITheme.palette.strokeSoft
		mark.BackgroundTransparency = if isLit then 0 else 0.55
		-- The lit marks grow slightly. At this size a colour change alone is easy to miss in a room
		-- whose only other light is the flame the player is holding.
		mark.Size = if isLit then UDim2.fromOffset(5, 13) else UDim2.fromOffset(4, 10)
	end
end

local function step()
	local current = activeRing()
	if current == nil then
		return
	end
	local lamp = if holding then currentLamp else nearestLamp()

	-- Yield the whole affordance while a ProximityPrompt is up: it owns E, and showing a second
	-- unrelated hold circle beside it would be two competing answers to the same key.
	if lamp == nil or lamp.Parent == nil or (promptsShown > 0 and not holding) then
		stopHold(holding)
		currentLamp = if lamp ~= nil and lamp.Parent ~= nil then lamp else nil
		current.gui.Enabled = false
		TouchControls.setVisible(TOUCH_ACTION, false)
		return
	end

	-- Walking away from a lamp mid-hold ends it, exactly as walking away from a mining swing does.
	if holding then
		local origin = characterPosition()
		local outOfRange = origin == nil
			or (lamp.Position - (origin :: Vector3)).Magnitude > config().interaction.promptRange
		if outOfRange or wantsToMove() or lamp:GetAttribute(config().litAttribute) == true then
			stopHold(true)
		end
	end

	currentLamp = lamp
	current.gui.Adornee = lamp
	current.gui.Enabled = true
	TouchControls.setVisible(TOUCH_ACTION, true)
	TouchControls.setActive(TOUCH_ACTION, holding)

	if holding then
		local progress = if holdSeconds > 0 then (os.clock() - holdStartedAt) / holdSeconds else 1
		drawProgress(progress)
		if progress >= 1 then
			-- The server re-checks the clock, the gate and the distance before anything catches; this is
			-- a claim, not a command.
			Remotes.get("LampAction"):FireServer("commit", lamp)
			holding = false
			current.label.Visible = false
			current.hint.Visible = true
		end
	else
		drawProgress(0)
	end
end

function WallLampController.start()
	if not WallLampRules.isEnabled() then
		return
	end
	ring = buildRing()

	ProximityPromptService.PromptShown:Connect(function()
		promptsShown += 1
	end)
	ProximityPromptService.PromptHidden:Connect(function()
		promptsShown = math.max(promptsShown - 1, 0)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.E and input.KeyCode ~= Enum.KeyCode.ButtonX then
			return
		end
		if canBegin() then
			beginHold(currentLamp :: BasePart)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
			stopHold(true)
		end
	end)

	-- TOUCH IS A TOGGLE, not a hold. A finger pinned to a button for three seconds is the one hand a
	-- mobile player also steers with, so tapping starts the circle and tapping again abandons it —
	-- and walking cancels it exactly as it does on a keyboard, which is the same rule stated in the
	-- input each platform actually has.
	if UserInputService.TouchEnabled then
		TouchControls.register({
			id = TOUCH_ACTION,
			label = "LIGHT",
			row = "primary",
			order = 4,
			activated = function()
				if holding then
					stopHold(true)
				elseif canBegin() then
					beginHold(currentLamp :: BasePart)
				end
			end,
		})
		TouchControls.setVisible(TOUCH_ACTION, false)
	end

	-- A REFUSAL FROM THE SERVER STOPS THE CIRCLE. The ring starts filling on the key press so the
	-- interaction feels immediate, which means an attempt the server was never going to allow has to
	-- be taken off the screen when the answer arrives rather than being left to fill up and do nothing.
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if kind ~= "lampHold" or typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: any }
		-- An answer about a lamp this client has already moved on from is stale. Without this check a
		-- refusal for the lamp behind you would cancel the hold you just started on the one in front.
		if data.lamp ~= currentLamp then
			return
		end
		if data.accepted == true then
			-- Trust the server's own hold length over the one read from the lamp's attribute, so a
			-- retuned config can never leave a client's circle finishing early or late.
			if typeof(data.holdSeconds) == "number" and data.holdSeconds > 0 then
				holdSeconds = data.holdSeconds
			end
			return
		end
		stopHold(false)
	end)

	RunService.RenderStepped:Connect(step)
end

return WallLampController

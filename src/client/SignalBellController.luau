--!strict
-- The Signal Bell's input and presentation (Config/LampNetwork.bell, server/SignalBellService).
--
-- THE ONE THING THIS FILE HAS TO GET RIGHT: the SOUND carries through rock and the LIGHT never does.
--
-- That split is the whole design of the node. A through-rock light would have solved the darkness the
-- game is built on; a through-rock sound solves only "where is my friend". So the cue is played
-- spatially at the ringer's real position with a very long roll-off — audible across a floor — while
-- the warm ripple is an ordinary part in the world, occluded by geometry exactly like every other
-- object. With line of sight you get a confirmation; without it you get a bearing and nothing else.
--
-- The ripple emits NO light: no PointLight, no Neon glow that could brighten a room. It is a shape
-- catching the flame you already carry, so it can never reveal geometry the darkness was hiding.
--
-- This controller decides nothing. It asks the server to ring and renders what the server reports;
-- ownership, wax, cooldown and who hears it are all server-owned and re-derived per ring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local SignalBellController = {}

local started = false

type Ripple = {
	part: BasePart,
	bornAt: number,
	lifetime: number,
}

local ripples: { Ripple } = {}

-- A thin expanding ring at the ringer's feet. Deliberately a plain matte part with no emission: the
-- brief here is "sound made visible", and anything self-lit would be a light source the design
-- explicitly refuses.
local function spawnRipple(position: Vector3, lifetime: number)
	local part = Instance.new("Part")
	part.Name = "WickBellRipple"
	part.Shape = Enum.PartType.Cylinder
	-- Laid flat on the ground: a Cylinder's height runs along its X axis, so it is turned on its side.
	part.Size = Vector3.new(0.12, 2, 2)
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Config.LobbyRoom.lampHousingLitColor
	part.Transparency = 0.35
	part.Parent = Workspace
	table.insert(ripples, { part = part, bornAt = os.clock(), lifetime = math.max(lifetime, 0.05) })
end

local function stepRipples()
	local now = os.clock()
	for index = #ripples, 1, -1 do
		local ripple = ripples[index]
		local age = (now - ripple.bornAt) / ripple.lifetime
		if age >= 1 or ripple.part.Parent == nil then
			ripple.part:Destroy()
			table.remove(ripples, index)
			continue
		end
		-- Widens and fades together, so it reads as one pulse leaving rather than a disc growing.
		local width = 2 + age * 16
		ripple.part.Size = Vector3.new(0.12, width, width)
		ripple.part.Transparency = 0.35 + age * 0.65
	end
end

function SignalBellController.start()
	if started then
		return
	end
	started = true

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: string, payload: { [string]: any })
		if kind ~= "bellRing" or typeof(payload) ~= "table" then
			return
		end
		-- `any` is confined to this untyped RemoteEvent boundary; the position is checked before use.
		local position = payload.position
		if typeof(position) ~= "Vector3" then
			return
		end

		-- Parented to a throwaway anchor at the ring's position rather than to the listener, so the cue
		-- is genuinely spatial — a bearing is only a bearing if the sound comes from somewhere.
		local anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = Workspace
		AudioCues.playAt("SignalBell", anchor)
		-- Long enough for the cue's own tail; the sound instance lives on the anchor, so cleaning up
		-- early would cut it off mid-ring.
		task.delay(6, function()
			anchor:Destroy()
		end)

		local lifetime = if typeof(payload.rippleSeconds) == "number"
			then payload.rippleSeconds
			else Config.LampNetwork.bell.rippleSeconds
		spawnRipple(position, lifetime)
	end)

	-- Desktop keybind. Mobile reaches the bell through the same remote from the hotbar, which is
	-- HotbarController's business; this file owns only the key.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if input.KeyCode ~= Config.Feel.controls.signalBellKey then
			return
		end
		-- Fired unconditionally: every reason a ring might be refused (not owned, too little wax, on
		-- cooldown, dead) is server-owned, and a client that guessed at them would eventually guess
		-- wrong. The remote is rate-limited (Config/Security) so asking is cheap and bounded.
		Remotes.get("BellRing"):FireServer()
	end)

	RunService.RenderStepped:Connect(stepRipples)
end

return SignalBellController

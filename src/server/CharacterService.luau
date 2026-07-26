--!strict
-- Thin Instance adapter for the candle body. Builds the rig, scales it to the authoritative
-- height, drives the flame light, and swaps in the wisp on burnout. All NUMBERS come from
-- state/config/logic — this file only moves parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local BrightnessMap = require(ReplicatedStorage.Shared.Logic.BrightnessMap)
local CandleGeometry = require(ReplicatedStorage.Shared.Logic.CandleGeometry)
local LightVisualProtocol = require(ReplicatedStorage.Shared.LightVisualProtocol)
local LobbyVisualProtocol = require(ReplicatedStorage.Shared.LobbyVisualProtocol)
local PlayerState = require(script.Parent.PlayerState)

local CharacterService = {}

-- Structural constant: the fixed physics collider is 2 studs tall; only the visual body scales.
local ROOT_HEIGHT = 2
-- Lobby arrivals face the elevator wall (+Z) so the first thing a new player sees is the choice.
local FACING = Vector3.new(0, 0, 1)

type Rig = {
	model: Model,
	root: BasePart,
	body: BasePart,
	bodyWeld: Weld,
	rim: BasePart,
	rimWeld: Weld,
	wick: BasePart,
	wickWeld: Weld,
	flame: BasePart,
	flameWeld: Weld,
	lightAttachment: Attachment,
	lightEnabled: boolean,
	lightRange: number,
	lightBrightness: number,
	height: number,
}

local rigs: { [Types.PlayerId]: Rig } = {}
-- Lobby bodies are either the player's Roblox avatar or the cosmetic candle used during an
-- elevator ride. They are deliberately never registered in `rigs`: WaxService and
-- MovementSanityService key off `CharacterService.basePosition`, which only reads `rigs`, so the
-- ride candle can look live without spending wax or entering cave gameplay.
local lobbyBodies: { [Types.PlayerId]: Model } = {}
local lobbyDiedConnections: { [Types.PlayerId]: RBXScriptConnection } = {}

function CharacterService.init()
	Players.CharacterAutoLoads = false
end

local function rootCenterOffset(): number
	-- Distance from candle base (ground) up to the root part's centre.
	return Config.Character.hipHeight + ROOT_HEIGHT / 2
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis is X; this stands it upright

local function updateWelds(rig: Rig, height: number)
	local c = Config.Character
	local offset = rootCenterOffset()
	rig.body.Size = Vector3.new(height, c.bodyRadius * 2, c.bodyRadius * 2)
	rig.bodyWeld.C0 = CFrame.new(0, height / 2 - offset, 0) * UPRIGHT
	-- Melted lip embedded at the body's top.
	local rimRadius = c.bodyRadius * c.rimRadiusMultiplier
	rig.rim.Size = Vector3.new(c.rimHeight, rimRadius * 2, rimRadius * 2)
	rig.rimWeld.C0 = CFrame.new(0, height - c.rimHeight / 2 - offset, 0) * UPRIGHT
	rig.wickWeld.C0 = CFrame.new(0, height + c.wickHeight / 2 - offset, 0) * UPRIGHT
	rig.flameWeld.C0 = CFrame.new(0, CandleGeometry.flameCenterY(0, height) - offset, 0)
	rig.lightAttachment.Position = Vector3.new(0, CandleGeometry.flameCenterY(0, height) - offset, 0)
	rig.height = height
end

-- Shared by the authoritative run candle and cosmetic elevator candle. Builds and positions the
-- rig but does not register it in either tracking table; callers choose whether it participates in
-- gameplay by placing it in `rigs` or `lobbyBodies`.
local function buildRig(player: Player, height: number, position: Vector3, isRideBody: boolean?): Rig
	local model = Instance.new("Model")
	model.Name = "Candle_" .. player.Name
	-- Marks this as a run body, not the lobby's Roblox avatar; CameraController switches to locked
	-- first person on exactly this signal.
	model:SetAttribute(LobbyVisualProtocol.attributes.runBody, true)
	if isRideBody == true then
		model:SetAttribute(LobbyVisualProtocol.attributes.rideBody, true)
	end

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(Config.Character.bodyRadius * 2, ROOT_HEIGHT, Config.Character.bodyRadius * 2)
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = Config.Character.hipHeight
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Movement.hopPower
	humanoid.WalkSpeed = Config.Movement.walkSpeed
	humanoid.Parent = model

	-- The candle never shadows its own light: CastShadow off on every rig part kills the huge
	-- radial self-shadow and its tessellation artifacts (legibility over fidelity).
	root.CastShadow = false

	local function rigPart(name: string, shape: Enum.PartType, color: Color3, material: Enum.Material): (BasePart, Weld)
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = shape
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.Massless = true
		part.CastShadow = false
		part.Parent = model
		local weld = Instance.new("Weld")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = root
		return part, weld
	end

	local waxColor = Color3.fromRGB(235, 225, 200)
	local body, bodyWeld = rigPart("Body", Enum.PartType.Cylinder, waxColor, Enum.Material.SmoothPlastic)
	local rim, rimWeld =
		rigPart("Rim", Enum.PartType.Cylinder, Color3.fromRGB(242, 233, 210), Enum.Material.SmoothPlastic)
	local wick, wickWeld =
		rigPart("Wick", Enum.PartType.Cylinder, Color3.fromRGB(35, 28, 22), Enum.Material.SmoothPlastic)
	wick.Size = Vector3.new(Config.Character.wickHeight, 0.2, 0.2)
	local flame, flameWeld = rigPart("Flame", Enum.PartType.Ball, Color3.fromRGB(255, 170, 60), Enum.Material.Neon)
	flame.Size = Vector3.new(
		Config.Character.flameHeight * Config.Character.flameWidthFactor,
		Config.Character.flameHeight * Config.Character.flameVerticalFactor,
		Config.Character.flameHeight * Config.Character.flameWidthFactor
	)

	-- The light lives on a root attachment, NOT the flame part: the flame ball is tiny and hidden
	-- locally (LocalTransparencyModifier), and lights parented to it get culled/quantized per-part.
	-- An attachment on the always-present root gives a stable emitter at the flame's height.
	local lightAttachment = Instance.new("Attachment")
	lightAttachment.Name = "FlameLight"
	lightAttachment.Parent = root
	lightAttachment:SetAttribute(LightVisualProtocol.attributes.ownerUserId, player.UserId)
	lightAttachment:SetAttribute(LightVisualProtocol.attributes.enabled, false)
	lightAttachment:SetAttribute(LightVisualProtocol.attributes.range, 0)
	lightAttachment:SetAttribute(LightVisualProtocol.attributes.brightness, 0)
	lightAttachment:SetAttribute(LightVisualProtocol.attributes.impactFlickerUntil, 0)
	CollectionService:AddTag(lightAttachment, LightVisualProtocol.tag)

	local rig: Rig = {
		model = model,
		root = root,
		body = body,
		bodyWeld = bodyWeld,
		rim = rim,
		rimWeld = rimWeld,
		wick = wick,
		wickWeld = wickWeld,
		flame = flame,
		flameWeld = flameWeld,
		lightAttachment = lightAttachment,
		lightEnabled = false,
		lightRange = 0,
		lightBrightness = 0,
		height = height,
	}
	updateWelds(rig, height)

	model.PrimaryPart = root
	root.CFrame = CFrame.new(position + Vector3.new(0, rootCenterOffset(), 0))
	model.Parent = workspace
	player.Character = model
	return rig
end

function CharacterService.spawn(player: Player, position: Vector3)
	CharacterService.despawn(player)
	local state = PlayerState.ensure(player.UserId)
	rigs[player.UserId] = buildRig(player, state.currentHeight, position)
end

-- Distance from the candle base up to the avatar pivot that puts an arbitrary rig's feet on the
-- ground: half the root part plus its hip height. Roblox avatars vary (R6/R15, scaled bodies), so
-- this is measured from the loaded character rather than assumed.
local function avatarGroundLift(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return 3
	end
	return root.Size.Y / 2 + humanoid.HipHeight
end

-- Replaces the lobby avatar with a full, lit candle at the instant an elevator commits. It is
-- tracked as a lobby body rather than a run rig, so first-person and candle lighting begin during
-- descent without starting wax drain, hazards, movement correction, or threat perception.
function CharacterService.spawnRideCandle(player: Player): boolean
	local current = lobbyBodies[player.UserId]
	local root = if current ~= nil then current.PrimaryPart else nil
	if current == nil or root == nil then
		return false
	end
	local basePosition = root.Position - Vector3.new(0, avatarGroundLift(current), 0)
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)

	CharacterService.despawn(player)
	local height = CandleGeometry.heightForWax(Config.Wax.startingWax)
	local rig = buildRig(player, height, basePosition, true)
	if flatLook.Magnitude > 0.001 then
		rig.root.CFrame = CFrame.lookAt(rig.root.Position, rig.root.Position + flatLook.Unit)
	end
	local light = BrightnessMap.paramsFor(Config.Wax.initialBurnRate, Config.WaxTypes[Config.Wax.startingWaxTypeId], 1)
	rig.lightEnabled = true
	rig.lightRange = light.range
	rig.lightBrightness = light.brightness
	rig.lightAttachment:SetAttribute(LightVisualProtocol.attributes.enabled, true)
	rig.lightAttachment:SetAttribute(LightVisualProtocol.attributes.range, light.range)
	rig.lightAttachment:SetAttribute(LightVisualProtocol.attributes.brightness, light.brightness)
	lobbyBodies[player.UserId] = rig.model
	return true
end

-- The hub shows the player's REAL Roblox avatar, not a candle: you only become a candle when you
-- descend. It is never registered in `rigs` (see the comment on `lobbyBodies` above), so it is
-- invisible to wax drain and movement-sanity correction for free. Facing is +Z, toward the
-- elevators across the room.
function CharacterService.spawnLobby(player: Player, position: Vector3)
	CharacterService.despawn(player)
	-- LoadCharacter yields on the appearance fetch; the player can leave inside that window.
	player:LoadCharacter()
	local character = player.Character
	if character == nil or player.Parent == nil then
		return
	end
	lobbyBodies[player.UserId] = character
	-- Both points of the look must sit at eye height; aiming at a target on the floor would tip the
	-- whole body forward.
	local eye = position + Vector3.new(0, avatarGroundLift(character), 0)
	character:PivotTo(CFrame.lookAt(eye, eye + FACING))

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.WalkSpeed = Config.LobbyRoom.walkSpeed
		-- R15 avatars default to JumpHeight; JumpPower is ignored unless this is set first.
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.LobbyRoom.jumpPower
		-- CharacterAutoLoads is off, so nothing would ever bring them back; a lobby death would
		-- otherwise leave a permanently ragdolled body. Nothing in the hub deals damage, but a fall
		-- out of the room or a Studio command shouldn't be unrecoverable.
		lobbyDiedConnections[player.UserId] = humanoid.Died:Connect(function()
			task.defer(function()
				if player.Parent ~= nil and lobbyBodies[player.UserId] == character then
					CharacterService.spawnLobby(player, position)
				end
			end)
		end)
	end
end

-- Removes whatever body the player currently owns, from either mode, and clears both tracking
-- tables. A player can only ever have one body, so this is deliberately not two half-teardowns:
-- calling either name from any call order can never leave a destroyed model behind in a table.
function CharacterService.despawn(player: Player)
	local connection = lobbyDiedConnections[player.UserId]
	if connection ~= nil then
		connection:Disconnect()
		lobbyDiedConnections[player.UserId] = nil
	end
	local rig = rigs[player.UserId]
	if rig ~= nil then
		rig.model:Destroy()
		rigs[player.UserId] = nil
	end
	local lobbyBody = lobbyBodies[player.UserId]
	if lobbyBody ~= nil then
		lobbyBody:Destroy()
		lobbyBodies[player.UserId] = nil
	end
	if player.Character ~= nil then
		player.Character:Destroy()
		player.Character = nil
	end
end

-- Intent-revealing alias for lobby-side call sites; see `despawn` for why they are the same teardown.
function CharacterService.despawnLobby(player: Player)
	CharacterService.despawn(player)
end

-- The lobby body's world position, or nil if the player has no lobby body. Kept separate from
-- `basePosition` on purpose: that one must only ever see run rigs.
function CharacterService.lobbyBodyPosition(playerId: Types.PlayerId): Vector3?
	local body = lobbyBodies[playerId]
	local root = if body ~= nil then body.PrimaryPart else nil
	return if root ~= nil then root.Position else nil
end

-- Moves a lobby body by a world-space delta. Used by the elevator descent ride to carry riders down
-- with the car; an anchored part moved by CFrame does not carry a Humanoid on its own.
function CharacterService.nudgeLobbyBody(playerId: Types.PlayerId, delta: Vector3)
	local body = lobbyBodies[playerId]
	if body ~= nil and body.PrimaryPart ~= nil then
		body:PivotTo(body:GetPivot() + delta)
	end
end

-- Places a lobby body somewhere without reloading the avatar. Used for fall recovery, where
-- respawning would mean a yielding LoadCharacter inside a Heartbeat tick.
function CharacterService.teleportLobbyBody(playerId: Types.PlayerId, position: Vector3)
	local body = lobbyBodies[playerId]
	if body == nil or body.PrimaryPart == nil then
		return
	end
	body:PivotTo(CFrame.new(position + Vector3.new(0, avatarGroundLift(body), 0)))
	body.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
end

-- Anchoring the root anchors the whole welded rig. The descent ride uses this so gravity and the
-- Humanoid's own controller cannot fight the client's analytic visual transform, and so a rider
-- cannot simply walk out of a car that is already moving.
function CharacterService.setLobbyBodyAnchored(playerId: Types.PlayerId, anchored: boolean)
	local body = lobbyBodies[playerId]
	local root = if body ~= nil then body.PrimaryPart else nil
	if root ~= nil then
		root.Anchored = anchored
	end
end

-- Candle-base world position (the authoritative `state.position`); nil if no body exists.
function CharacterService.basePosition(playerId: Types.PlayerId): Vector3?
	local rig = rigs[playerId]
	if rig == nil then
		return nil
	end
	return rig.root.Position - Vector3.new(0, rootCenterOffset(), 0)
end

function CharacterService.horizontalSpeed(playerId: Types.PlayerId): number
	local rig = rigs[playerId]
	if rig == nil then
		return 0
	end
	local velocity = rig.root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

function CharacterService.applyHeight(playerId: Types.PlayerId, height: number)
	local rig = rigs[playerId]
	if rig ~= nil then
		updateWelds(rig, height)
	end
end

-- Cosmetic strain visible to teammates: the flame is pulled backward and burns less steadily
-- while the authoritative measured movement mode is Run.
function CharacterService.applyMovementVisual(playerId: Types.PlayerId, movementMode: Types.MovementMode)
	local rig = rigs[playerId]
	if rig == nil then
		return
	end
	local c = Config.Character
	local running = movementMode == "Run"
	local narrow = if running then c.sprintFlameNarrowMultiplier else 1
	local stretch = if running then c.sprintFlameStretchMultiplier else 1
	rig.flame.Size = Vector3.new(
		c.flameHeight * c.flameWidthFactor * narrow,
		c.flameHeight * c.flameVerticalFactor * stretch,
		c.flameHeight * c.flameWidthFactor * narrow
	)
	local center = CandleGeometry.flameCenterY(0, rig.height) - rootCenterOffset()
	local lean = if running then math.rad(c.sprintFlameLeanDegrees) else 0
	rig.flameWeld.C0 = CFrame.new(0, center, 0) * CFrame.Angles(lean, 0, 0)
end

function CharacterService.applyLight(playerId: Types.PlayerId, range: number, brightness: number, isLit: boolean)
	local rig = rigs[playerId]
	if rig == nil then
		return
	end
	if rig.lightEnabled ~= isLit then
		rig.lightEnabled = isLit
		rig.lightAttachment:SetAttribute(LightVisualProtocol.attributes.enabled, isLit)
	end
	if rig.lightRange ~= range then
		rig.lightRange = range
		rig.lightAttachment:SetAttribute(LightVisualProtocol.attributes.range, range)
	end
	if rig.lightBrightness ~= brightness then
		rig.lightBrightness = brightness
		rig.lightAttachment:SetAttribute(LightVisualProtocol.attributes.brightness, brightness)
	end
	rig.flame.Transparency = if isLit then 0 else 0.85
end

-- Server timestamp replicated to every client; CandleLightController reconstructs the short,
-- violent cosmetic flicker without high-frequency light replication.
function CharacterService.signalLightImpact(playerId: Types.PlayerId, duration: number)
	local rig = rigs[playerId]
	if rig ~= nil then
		rig.lightAttachment:SetAttribute(
			LightVisualProtocol.attributes.impactFlickerUntil,
			workspace:GetServerTimeNow() + math.max(0, duration)
		)
	end
end

function CharacterService.setWalkSpeed(playerId: Types.PlayerId, speed: number)
	local rig = rigs[playerId]
	if rig == nil then
		return
	end
	local humanoid = rig.model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.WalkSpeed = speed
	end
end

function CharacterService.teleport(playerId: Types.PlayerId, position: Vector3)
	local rig = rigs[playerId]
	if rig ~= nil then
		rig.model:PivotTo(CFrame.new(position + Vector3.new(0, rootCenterOffset(), 0)))
	end
end

-- The root to attach relight prompts to.
function CharacterService.rootPart(playerId: Types.PlayerId): BasePart?
	local rig = rigs[playerId]
	return if rig ~= nil then rig.root else nil
end

-- Brazier commit: the candle stops being an actor but remains as scenery.
function CharacterService.freeze(playerId: Types.PlayerId)
	local rig = rigs[playerId]
	if rig == nil then
		return
	end
	rig.root.Anchored = true
	rig.lightEnabled = false
	rig.lightAttachment:SetAttribute(LightVisualProtocol.attributes.enabled, false)
	rig.flame.Transparency = 0.85
end

function CharacterService.spawnWisp(player: Player, position: Vector3)
	CharacterService.despawn(player)
	local wisp = Config.Run.wisp

	local model = Instance.new("Model")
	model.Name = "Wisp_" .. player.Name
	model:SetAttribute(LobbyVisualProtocol.attributes.runBody, true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.one * wisp.bodySize
	root.Color = Color3.fromRGB(180, 200, 255)
	root.Material = Enum.Material.Neon
	root.Transparency = 0.4
	root.CanCollide = true
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = wisp.bodySize / 2
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.WalkSpeed = wisp.moveSpeed
	humanoid.Parent = model

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(180, 200, 255)
	light.Range = wisp.lightRange
	light.Brightness = wisp.lightBrightness
	light.Parent = root

	model.PrimaryPart = root
	root.CFrame = CFrame.new(position + Vector3.new(0, wisp.bodySize, 0))
	model.Parent = workspace
	player.Character = model
end

-- Wisp lifetime over: it goes still and dark, but stays in the world until the run resets.
function CharacterService.freezeWisp(player: Player)
	local character = player.Character
	if character == nil or character.Name ~= "Wisp_" .. player.Name then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		root.Anchored = true
		local light = root:FindFirstChildOfClass("PointLight")
		if light ~= nil then
			light.Enabled = false
		end
	end
end

return CharacterService

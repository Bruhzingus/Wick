--!strict
-- Local presentation for the Unlittius encounter (shared/UnlittiusVisualProtocol, DESIGN §9b).
--
-- IT DECIDES NOTHING. The server owns the candle count, every attack timeline, every hit, the
-- projectile positions it collides against and the banish. This file reads replicated attributes and
-- server timestamps and draws what they imply — floor telegraphs counting down, boulders travelling,
-- violet fading out of a god one eighth at a time, and dust coming off a ceiling that is about to
-- swallow him. Nothing here is ever asked whether something landed.
--
-- WHY ATTRIBUTES RATHER THAN A REMOTE STREAM. A player who walks into the chamber four candles into
-- the fight has to see a boss dimmed to half, four burning candles and any boulder currently in the
-- air. A remote reaches whoever was listening when it fired; replicated state reaches whoever looks.
-- The dripstone, the mining rail and the descent elevator all made this choice first.
--
-- THE VFX BUDGET IS DELIBERATELY SMALL (VFX_BLUEPRINT.md: "do not turn him into a particle-heavy
-- anime boss"). Everything below is chunky stone fragments, dust, and restrained violet. There is one
-- particle emitter per live boulder, one per telegraph, and a fixed handful on the body — and the
-- whole encounter is culled by distance, because a chamber this size can hold a player who is
-- nowhere near any of it.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Protocol = require(ReplicatedStorage.Shared.UnlittiusVisualProtocol)
local UnlittiusRules = require(ReplicatedStorage.Shared.Logic.UnlittiusRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)
local CameraMotionController = require(script.Parent.CameraMotionController)

local UnlittiusController = {}

local player = Players.LocalPlayer

-- Nothing in this encounter is drawn for a player who is further away than this. The chamber is one
-- 64-stud cell and the galleries hang off it, so a player in a gallery is inside the range and a
-- player two rooms away is not paying for any of it.
local PRESENTATION_RANGE = 130

local bosses: { [Model]: { connections: { RBXScriptConnection }, humAt: Instance? } } = {}
local telegraphs: { [BasePart]: true } = {}
local boulders: { [BasePart]: true } = {}
local renderConnection: RBXScriptConnection? = nil

local function localRoot(): BasePart?
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function isNear(position: Vector3, range: number?): boolean
	local root = localRoot()
	return root ~= nil and (position - root.Position).Magnitude <= (range or PRESENTATION_RANGE)
end

-- One decaying camera event, handed to the client's single camera writer. Impulses stack rather than
-- replacing each other — a boulder landing during a slam adds to it — and the stacking, the cap on it
-- and the ceiling on the sum are all CameraMotionController's problem now.
--
-- His slams are TRANSLATION ONLY: no roll, no pitch. A twelve-foot ceiling ornament dropping something
-- shoves the floor; it does not tilt the world, and the tilt is the part that reads as being hit,
-- which he never does (DESIGN section 9b — Unlittius cannot be fought and never lands a blow you
-- recover from).
local function addShake(duration: number, studs: number, frequency: number)
	CameraMotionController.impulse({
		studs = studs,
		degrees = 0,
		frequencyRadians = frequency,
		durationSeconds = duration,
	})
end

local function emitterAt(position: Vector3, lifetime: number): BasePart
	local emitter = Instance.new("Part")
	emitter.Name = "WickUnlittiusFX"
	emitter.Size = Vector3.one * 0.1
	emitter.Position = position
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.Transparency = 1
	emitter.Parent = Workspace
	Debris:AddItem(emitter, lifetime)
	return emitter
end

-- Chunky angular debris, the cave's own answer to an impact. Deliberately parts rather than a
-- particle sheet: the art direction is low-poly stone, and a puff of billboards in a chamber lit by
-- eight candles reads as fog.
local function scatterDebris(position: Vector3, count: number, spread: number)
	for index = 1, count do
		local chunk = Instance.new("Part")
		chunk.Name = "WickUnlittiusDebris"
		chunk.Size = Vector3.new(0.3 + (index % 3) * 0.22, 0.28 + (index % 2) * 0.2, 0.34)
		chunk.CFrame = CFrame.new(position + Vector3.new(0, 0.4, 0))
			* CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		chunk.Color = Color3.fromRGB(72, 66, 60)
		chunk.Material = Enum.Material.Slate
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CastShadow = false
		chunk.Anchored = false
		chunk.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * spread,
			6 + math.random() * spread * 0.4,
			(math.random() - 0.5) * spread
		)
		chunk.Parent = Workspace
		Debris:AddItem(chunk, 2.5)
	end
end

local function dustBurst(position: Vector3, rate: number, lifetime: number)
	local emitter = emitterAt(position, lifetime + 1)
	local attachment = Instance.new("Attachment")
	attachment.Parent = emitter
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(96, 90, 82))
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Size = NumberSequence.new(2.4, 4.2)
	particles.Lifetime = NumberRange.new(0.8, 1.6)
	particles.Speed = NumberRange.new(1, 3)
	particles.SpreadAngle = Vector2.new(40, 40)
	particles.Rate = 0
	particles.LightEmission = 0
	particles.Parent = attachment
	particles:Emit(rate)
	return particles
end

--------------------------------------------------------------------------------
-- THE BOSS
--------------------------------------------------------------------------------

local function bossPower(model: Model): number
	local value = model:GetAttribute(Protocol.boss.attributes.power)
	return if typeof(value) == "number" then math.clamp(value, 0, 1) else 1
end

local function bossCandles(model: Model): number
	local value = model:GetAttribute(Protocol.boss.attributes.candlesLit)
	return if typeof(value) == "number" then value else 0
end

-- WHEN AN ACTION STARTS. The one-shot flourishes that are pure cosmetics: the camera answering a
-- snap, dust off his shoulders when he conducts, a hard violet flare when a candle lands.
--
-- THE AUTHORITATIVE VERSION OF EVERY ONE OF THESE ALREADY HAPPENED ON THE SERVER. Nothing here can
-- make an attack hit or miss; the worst a dropped frame in this function can do is cost a puff of
-- dust.
local function actionChanged(model: Model)
	local action = model:GetAttribute(Protocol.boss.attributes.action)
	local startedAt = model:GetAttribute(Protocol.boss.attributes.actionStartedAt)
	if typeof(action) ~= "string" then
		return
	end
	local root = model.PrimaryPart
	if root == nil or not isNear(root.Position) then
		return
	end
	local age = if typeof(startedAt) == "number" then Workspace:GetServerTimeNow() - startedAt else 0
	-- A late joiner adopts the CURRENT action without replaying its opening flourish. Two tenths of a
	-- second is the whole window in which "this just started" is true.
	if age > 0.25 then
		return
	end

	if action == Protocol.actions.recoil then
		-- THE ONE MOMENT THE ENCOUNTER SHOUTS. Chest flare, orbit stones kicked outward, and a short
		-- sharp camera hit — the player has to feel a candle land even if they lit it across the room.
		addShake(0.55, 0.5, 26)
		dustBurst(root.Position + Vector3.new(0, 1, 0), 26, 1.2)
		local chest = model:FindFirstChild("ChestRune")
		if chest ~= nil and chest:IsA("BasePart") then
			local flare = Instance.new("PointLight")
			flare.Color = Config.Unlittius.body.runeColor:Lerp(Color3.new(1, 1, 1), 0.5)
			flare.Range = 34
			flare.Brightness = 6
			flare.Shadows = false
			flare.Parent = chest
			Debris:AddItem(flare, 0.35)
		end
	elseif action == Protocol.actions.banish then
		addShake(2.4, 0.35, 12)
	elseif action == Protocol.actions.dripstone then
		dustBurst(root.Position + Vector3.new(0, 6, 0), 14, 2.0)
	elseif action == Protocol.actions.summon then
		dustBurst(root.Position, 18, 2.2)
	end
end

-- THE RUNE HUM. The only cue in the game whose gain is not fixed in `Config/Audio`: it is loudest at
-- zero candles and almost gone at seven, which makes the supernatural layer itself the progress bar
-- this encounter refuses to draw (SOUND_DESIGN.md's candle-based mix progression).
local function syncHum(model: Model, entry: { connections: { RBXScriptConnection }, humAt: Instance? })
	local root = model.PrimaryPart
	if root == nil then
		return
	end
	local gain = UnlittiusRules.supernaturalGain(bossCandles(model))
	local action = model:GetAttribute(Protocol.boss.attributes.action)
	if action == Protocol.actions.banish or gain <= 0.02 or not isNear(root.Position, 70) then
		if entry.humAt ~= nil then
			AudioCues.stopAt("UnlittiusRuneHum", entry.humAt)
			entry.humAt = nil
		end
		return
	end
	if entry.humAt == nil then
		if AudioCues.playAt("UnlittiusRuneHum", root, nil, gain) then
			entry.humAt = root
		end
	end
end

local function addBoss(instance: Instance)
	if not instance:IsA("Model") or bosses[instance] ~= nil then
		return
	end
	local entry = { connections = {} :: { RBXScriptConnection }, humAt = nil :: Instance? }
	bosses[instance] = entry
	table.insert(
		entry.connections,
		instance:GetAttributeChangedSignal(Protocol.boss.attributes.action):Connect(function()
			actionChanged(instance)
		end)
	)
	table.insert(
		entry.connections,
		instance:GetAttributeChangedSignal(Protocol.boss.attributes.candlesLit):Connect(function()
			-- The hum is re-voiced rather than faded: `AudioCues` owns the fade, and re-asking for it at
			-- the new gain is how every other level-scaled cue in this game changes level.
			if entry.humAt ~= nil then
				AudioCues.stopAt("UnlittiusRuneHum", entry.humAt)
				entry.humAt = nil
			end
		end)
	)
end

local function removeBoss(instance: Instance)
	local entry = bosses[instance]
	if entry == nil then
		return
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	if entry.humAt ~= nil then
		AudioCues.stopAt("UnlittiusRuneHum", entry.humAt)
	end
	bosses[instance] = nil
end

--------------------------------------------------------------------------------
-- TELEGRAPHS AND BOULDERS
--------------------------------------------------------------------------------

-- THE FLOOR MARKER, COUNTING DOWN. The server placed the disc and owns the impact time; all this does
-- is make the last half second unmistakable, because a marker that looks the same at 1.5s and at 0.1s
-- is a warning without a clock in it.
local function renderTelegraph(marker: BasePart, now: number)
	local markedAt = marker:GetAttribute(Protocol.telegraph.attributes.markedAt)
	local impactAt = marker:GetAttribute(Protocol.telegraph.attributes.impactAt)
	if typeof(markedAt) ~= "number" or typeof(impactAt) ~= "number" then
		return
	end
	local span = math.max(impactAt - markedAt, 0.001)
	local progress = math.clamp((now - markedAt) / span, 0, 1)
	-- Brightens and tightens as it fills, then pulses hard over the final fifth.
	local pulse = if progress > 0.8 then 0.5 + 0.5 * math.sin(now * 42) else 1
	marker.Transparency = 0.72 - progress * 0.4 * pulse
	local scale = 1 - progress * 0.12
	local radius = marker:GetAttribute(Protocol.telegraph.attributes.radius)
	if typeof(radius) == "number" then
		marker.Size = Vector3.new(marker.Size.X, radius * 2 * scale, radius * 2 * scale)
	end
end

-- A BOULDER IN THE AIR. Drawn from `origin + direction * speed * (now - firedAt)` — the same
-- arithmetic the server is stepping its own logical projectile with, which is why the stone a player
-- sees and the stone that hits them cannot drift apart.
--
-- BEFORE `firedAt` it is still assembling: the server sets `conjuredAt` when the fragments start
-- pulling together and `firedAt` when it leaves, so the growth is drawn from the gap between them.
local function renderBoulder(part: BasePart, now: number)
	local origin = part:GetAttribute(Protocol.boulder.attributes.origin)
	local direction = part:GetAttribute(Protocol.boulder.attributes.direction)
	local speed = part:GetAttribute(Protocol.boulder.attributes.speed)
	local firedAt = part:GetAttribute(Protocol.boulder.attributes.firedAt)
	local conjuredAt = part:GetAttribute(Protocol.boulder.attributes.conjuredAt)
	local radius = part:GetAttribute(Protocol.boulder.attributes.radius)
	local fullSize = if typeof(radius) == "number" then radius * 2 else 4

	if typeof(firedAt) ~= "number" then
		-- Still conjuring. It grows from a fragment to full size where it was called into being.
		local grown = if typeof(conjuredAt) == "number"
			then math.clamp((now - conjuredAt) / math.max(Config.Unlittius.boulder.conjureSeconds, 0.001), 0, 1)
			else 1
		local eased = grown * grown * (3 - 2 * grown)
		part.Size = Vector3.one * fullSize * (0.12 + 0.88 * eased)
		part.CFrame = part.CFrame * CFrame.Angles(0.02, 0.03, 0.01)
		return
	end

	part.Size = Vector3.one * fullSize
	if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" and typeof(speed) == "number" then
		local travelled = math.max(now - firedAt, 0) * speed
		part.CFrame = CFrame.new(origin + direction * travelled) * CFrame.Angles(now * 2.2, now * 1.7, now * 1.1)
	else
		part.CFrame = part.CFrame * CFrame.Angles(0.04, 0.05, 0.02)
	end
end

--------------------------------------------------------------------------------
-- Server events
--------------------------------------------------------------------------------

local function onRunEvent(kind: string, payload: { [string]: any }?)
	if payload == nil then
		return
	end
	local position = payload.position
	if kind == "unlittiusBoulderImpact" then
		if typeof(position) == "Vector3" and isNear(position) then
			scatterDebris(position, 7, 14)
			dustBurst(position, 18, 1.4)
			addShake(0.4, 0.28, 30)
			AudioCues.playAt("UnlittiusBoulderImpact", emitterAt(position, 3))
		end
	elseif kind == "unlittiusSummon" then
		if typeof(position) == "Vector3" and isNear(position) then
			scatterDebris(position, 5, 10)
			dustBurst(position, 22, 1.6)
		end
	elseif kind == "unlittiusRake" then
		if typeof(position) == "Vector3" and isNear(position) then
			addShake(0.25, 0.2, 34)
		end
	elseif kind == "unlittiusProgress" then
		-- A CANDLE CAUGHT. The warm burst is deliberately at the CANDLE rather than at the boss: the
		-- thing the player did is over there, and the wound he takes for it announces itself
		-- separately through his own recoil.
		if typeof(position) == "Vector3" and isNear(position) then
			dustBurst(position + Vector3.new(0, 2, 0), 8, 1.0)
			AudioCues.playAt("LampIgnite", emitterAt(position, 3))
		end
	elseif kind == "unlittiusRelief" then
		-- He has entered the rock. Dust falls out of the ceiling around the seam for a moment, and
		-- then the room is quiet — the sequence is written to END calm.
		if typeof(position) == "Vector3" and isNear(position, 160) then
			dustBurst(position - Vector3.new(0, 2, 0), 40, 3.0)
			addShake(1.1, 0.42, 16)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function UnlittiusController.start()
	local function watch(tag: string, add: (Instance) -> (), remove: ((Instance) -> ())?)
		for _, instance in CollectionService:GetTagged(tag) do
			add(instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(add)
		if remove ~= nil then
			CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
		end
	end

	watch(Protocol.boss.tag, addBoss, removeBoss)
	watch(Protocol.telegraph.tag, function(instance: Instance)
		if instance:IsA("BasePart") then
			telegraphs[instance] = true
		end
	end, function(instance: Instance)
		if instance:IsA("BasePart") then
			telegraphs[instance] = nil
		end
	end)
	watch(Protocol.boulder.tag, function(instance: Instance)
		if instance:IsA("BasePart") then
			boulders[instance] = true
		end
	end, function(instance: Instance)
		if instance:IsA("BasePart") then
			boulders[instance] = nil
		end
	end)

	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if typeof(kind) == "string" and (payload == nil or typeof(payload) == "table") then
			onRunEvent(kind, payload :: any)
		end
	end)

	if renderConnection ~= nil then
		renderConnection:Disconnect()
	end
	renderConnection = RunService.RenderStepped:Connect(function()
		local now = Workspace:GetServerTimeNow()
		for marker in telegraphs do
			if marker.Parent == nil then
				telegraphs[marker] = nil
				continue
			end
			renderTelegraph(marker, now)
		end
		for boulder in boulders do
			if boulder.Parent == nil then
				boulders[boulder] = nil
				continue
			end
			renderBoulder(boulder, now)
		end
		for model, entry in bosses do
			if model.Parent == nil then
				removeBoss(model)
				continue
			end
			syncHum(model, entry)
			-- The eyes and the rune are dimmed server-side (the body owns its own power), so the only
			-- per-frame work left here is the hum. Reading `power` is kept because a future local effect
			-- that scales with it should have one obvious place to hang off.
			local _ = bossPower(model)
		end
	end)
end

return UnlittiusController

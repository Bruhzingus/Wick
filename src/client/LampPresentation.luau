--!strict
-- EVERY IGNITION IN THE CAVE: a wall candle taking, the crowned lamp answering a floor, and the
-- brazier a run ends at. One flare curve, one cue path, three fixtures.
--
-- PRESENTATION AND NOTHING ELSE. By the time an event reaches here the server has already lit the
-- prop, entered it into the light field and (for the brazier) paid the profile. The payload carries
-- a position, a model and a flag; this file may not derive anything else from them. If this
-- controller failed to load, lamps would still light, threats would still see them and a run would
-- still cash out — the world would simply stop making a noise about it.
--
-- WHY ONE FILE FOR THREE OBJECTS. They are all "a fire caught here": the same hard flare decaying to
-- rest, the same cue family, the same disposable world anchor. Splitting them would be three copies
-- of a decay curve that must never drift, and the only real difference between them — which cue, and
-- whether distant echoes answer — is two booleans.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local LampPresentation = {}

type Flare = {
	light: Light,
	baseBrightness: number,
	startedAt: number,
	duration: number,
	-- Carried per flare rather than read from config in the step loop: a wall candle and a brazier
	-- spike by different amounts, and decaying one against the other's number would settle it at the
	-- wrong brightness for the rest of the floor's life.
	multiplier: number,
}

local flares: { Flare } = {}

-- A short-lived world anchor for a positional cue: the same disposable-emitter pattern
-- client/DynamiteController uses for the fuse and the blast.
local function playAt(cueName: string, position: Vector3, level: number?, pitch: number?)
	local anchor = Instance.new("Part")
	anchor.Name = "WickLampAudioAnchor"
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Parent = Workspace

	AudioCues.playAt(cueName, anchor, pitch, level)
	Debris:AddItem(anchor, 4)
end

-- THE FLARE. A hard spike on catch that decays back to the fixture's steady output — never a
-- fade-in. A light that eases up reads as somebody turning a dial; a light that slams and settles
-- reads as something catching.
--
-- ONLY THE POINT LIGHT INSIDE THE FIXTURE FLARES. Wall lamps also own a broad SpotLight aimed into
-- their room, and spiking that layer would flash the whole chamber like a floodlight every time
-- somebody lit a candle.
local function beginFlare(model: Model, multiplier: number, seconds: number)
	local light: Light? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("PointLight") then
			light = descendant
			break
		end
	end
	if light == nil then
		return
	end
	-- The AUTHORED resting value, read from the light rather than assumed. Every builder stamps what
	-- its light is supposed to settle back to, because a room candle burns at a fraction of the
	-- brazier's output and flaring one against the wrong number would leave it permanently too
	-- bright. A second ignition landing while the first flare is still decaying would capture a
	-- mid-spike brightness for the same reason, which is why the instance's current value is never used.
	local stamped = (light :: Light):GetAttribute(Config.WallLamp.restBrightnessAttribute)
	local baseBrightness = if typeof(stamped) == "number" then stamped else (light :: Light).Brightness
	table.insert(flares, {
		light = light :: Light,
		baseBrightness = baseBrightness,
		startedAt = os.clock(),
		duration = math.max(seconds, 0.01),
		multiplier = multiplier,
	});
	(light :: Light).Brightness = baseBrightness * multiplier
end

-- THE ANSWERING IGNITIONS, and they belong to the BRAZIER alone. The same cue, delayed, quieter,
-- lower and played from anchors well out in the dark — so what the ear reports is "that sound again,
-- further away", which is the whole of what the chain reaction has to say.
--
-- The wall lamps never get these. A cascade already plays one real cue per room from the room it
-- actually happened in; giving each of those its own pair of distant fakes would turn a legible
-- sequence into a dozen overlapping delayed copies of itself.
local function scheduleEchoes(position: Vector3, direction: Vector3)
	local fixture = Config.Brazier.fixture
	local count = math.max(0, math.floor(fixture.echoCount))
	for index = 1, count do
		local delay = fixture.echoDelaySeconds + (index - 1) * fixture.echoSpacingSeconds
		local level = fixture.echoLevelFalloff ^ index
		local pitch = fixture.echoPitchFalloff ^ index
		-- Each echo further out than the last, and swung off the approach line so they do not stack
		-- into one point source. A cave answers from more than one direction.
		local swing = CFrame.Angles(0, math.rad(index * 47), 0)
		local at = position + (swing * direction) * (fixture.echoDistanceStuds * index)
		task.delay(delay, function()
			playAt(fixture.igniteCue, at, level, pitch)
		end)
	end
end

-- THE CROWNED LAMP'S AURA, breathing. Tag-driven exactly as the water surfaces and the cauldron's
-- ripple are: the server sets a resting transparency when the lamp catches and never touches it
-- again, and every client animates around that value locally.
--
-- A DEAD AURA IS LEFT ALONE. Transparency 1 means the lamp is still cold, and pulsing an invisible
-- disc between two invisible values would be a per-frame write that nobody can see.
local function stepAura(now: number)
	local main = Config.WallLamp.main
	local amplitude = main.auraPulseAmplitude
	local period = math.max(main.auraPulseSeconds, 0.01)
	for _, disc in CollectionService:GetTagged(Config.WallLamp.auraTag) do
		if not disc:IsA("BasePart") then
			continue
		end
		local rest = disc:GetAttribute(Config.WallLamp.auraRestAttribute)
		if typeof(rest) ~= "number" or disc.Transparency >= 0.999 then
			continue
		end
		-- Phase offset by position so the inner and outer discs — and two lamps in view at once — are
		-- never breathing in lockstep, which would read as a UI element rather than as light.
		local phase = (disc.Position.X + disc.Position.Z) * 0.35
		disc.Transparency = math.clamp(rest + math.sin(now / period * math.pi * 2 + phase) * amplitude, 0, 1)
	end
end

local function step()
	local now = os.clock()

	for index = #flares, 1, -1 do
		local flare = flares[index]
		if flare.light.Parent == nil then
			table.remove(flares, index)
			continue
		end
		local progress = (now - flare.startedAt) / flare.duration
		if progress >= 1 then
			flare.light.Brightness = flare.baseBrightness
			table.remove(flares, index)
			continue
		end
		-- Cubic decay: most of the spike is spent in the first fraction of a second.
		local falloff = (1 - progress) ^ 3
		flare.light.Brightness = flare.baseBrightness * (1 + (flare.multiplier - 1) * falloff)
	end

	stepAura(now)
end

-- ONE WALL LAMP CATCHING. Fired for every lamp a player lights by hand and for every room the
-- crowned lamp's cascade reaches, so this is by far the most common ignition in the game — and the
-- quietest, deliberately.
local function onLampLit(data: { [string]: any })
	local position = data.position
	if typeof(position) ~= "Vector3" then
		return
	end
	local isMain = data.main == true
	if typeof(data.model) == "Instance" and (data.model :: Instance):IsA("Model") then
		beginFlare(data.model :: Model, Config.WallLamp.flareBrightnessMultiplier, Config.WallLamp.flareSeconds)
	end
	playAt(if isMain then Config.WallLamp.mainIgniteCue else Config.WallLamp.roomIgniteCue, position)
end

-- THE BRAZIER CATCHING, which happens at most once per floor and means somebody's run just ended.
local function onBrazierLit(data: { [string]: any })
	local position = data.position
	local direction = data.direction
	if typeof(position) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	-- The direction drives the distant positional echoes. Keep the remote boundary finite.
	if direction.Magnitude < 0.01 or direction ~= direction then
		return
	end
	local fixture = Config.Brazier.fixture
	if typeof(data.model) == "Instance" and (data.model :: Instance):IsA("Model") then
		beginFlare(data.model :: Model, fixture.flareBrightnessMultiplier, fixture.flareSeconds)
	end
	playAt(fixture.igniteCue, position)
	scheduleEchoes(position, direction.Unit)
end

function LampPresentation.start()
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if typeof(kind) ~= "string" or typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: any }
		if kind == "lampLit" then
			onLampLit(data)
		elseif kind == "brazierLit" then
			onBrazierLit(data)
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return LampPresentation

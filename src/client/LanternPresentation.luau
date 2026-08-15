--!strict
-- The Gas Lantern's ignition beat (Config/Lantern, FLOOR-FIXTURES-OVERHAUL): the flare on catch and
-- the answering ignitions heard somewhere unseen.
--
-- PRESENTATION AND NOTHING ELSE. `server/BrazierService` has already computed the reward, paid the
-- profile and latched the lamp lit by the time this runs; the event that reaches here carries a
-- position, a direction and the model, and this file may not derive anything else from them. If this
-- controller failed to load, a run would still cash out correctly and the lamp would still be lit.
--
-- The only visual effect is the fixture itself catching and settling. Nothing flies away from the
-- lamp or adds unrelated glowing geometry to the shot.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local AudioCues = require(script.Parent.AudioCues)

local LanternPresentation = {}

type Flare = {
	light: PointLight,
	baseBrightness: number,
	startedAt: number,
	duration: number,
}

local flares: { Flare } = {}

-- A short-lived world anchor for a positional cue: the same disposable-emitter pattern
-- client/DynamiteController uses for the fuse and the blast.
local function playAt(cueName: string, position: Vector3, level: number?, pitch: number?)
	local anchor = Instance.new("Part")
	anchor.Name = "WickLanternAudioAnchor"
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

-- THE FLARE. A hard spike on catch that decays back to the lamp's steady output — never a fade-in.
-- A light that eases up reads as somebody turning a dial; a light that slams and settles reads as
-- something catching.
local function beginFlare(model: Model)
	local core = model:FindFirstChild("LanternFlameCore", true)
	-- Only the small PointLight inside the glass flares. Wall-mounted lamps also own a broad SpotLight
	-- aimed into their room, but spiking that layer would flash the entire chamber like a floodlight.
	local light = if core ~= nil then core:FindFirstChildOfClass("PointLight") else nil
	if light == nil then
		return
	end
	local reaction = Config.Lantern.chainReaction
	-- The AUTHORED resting value, never the instance's current one: a second commit landing while the
	-- first flare is still decaying would otherwise capture a mid-spike brightness and settle the lamp
	-- permanently too bright.
	--
	-- READ FROM THE LAMP, not assumed. The builder stamps every light it makes with what that light is
	-- supposed to settle back to, because the cave-network lamps burn at a fraction of the Gas Lantern's
	-- output and flaring one against the fixture's number would leave it permanently four times too
	-- bright. The fallback is the Gas Lantern's own value, which is what an older lamp would want.
	local stamped = light:GetAttribute(Config.Lantern.restBrightnessAttribute)
	local baseBrightness = if typeof(stamped) == "number" then stamped else Config.Lantern.lightBrightness
	table.insert(flares, {
		light = light,
		baseBrightness = baseBrightness,
		startedAt = os.clock(),
		duration = math.max(reaction.flareSeconds, 0.01),
	})
	light.Brightness = baseBrightness * reaction.flareBrightnessMultiplier
end

-- THE ANSWERING IGNITIONS. The same cue as the lantern's own, delayed, quieter, lower and played
-- from anchors well out in the dark — so what the ear reports is "that sound again, further away",
-- which is the whole of what the chain reaction has to say.
local function scheduleEchoes(position: Vector3, direction: Vector3)
	local reaction = Config.Lantern.chainReaction
	local count = math.max(0, math.floor(reaction.echoCount))
	for index = 1, count do
		local delay = reaction.echoDelaySeconds + (index - 1) * reaction.echoSpacingSeconds
		local level = reaction.echoLevelFalloff ^ index
		local pitch = reaction.echoPitchFalloff ^ index
		-- Each echo further out than the last, and swung off the approach line so they do not stack into
		-- one point source. A cave answers from more than one direction.
		local swing = CFrame.Angles(0, math.rad(index * 47), 0)
		local at = position + (swing * direction) * (reaction.echoDistanceStuds * index)
		task.delay(delay, function()
			playAt(Config.Lantern.igniteCue, at, level, pitch)
		end)
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
		local reaction = Config.Lantern.chainReaction
		-- Cubic decay: most of the spike is spent in the first fraction of a second.
		local falloff = (1 - progress) ^ 3
		flare.light.Brightness = flare.baseBrightness * (1 + (reaction.flareBrightnessMultiplier - 1) * falloff)
	end
end

function LanternPresentation.start()
	Remotes.get("RunEvent").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if typeof(kind) ~= "string" or typeof(payload) ~= "table" then
			return
		end
		local data = payload :: { [string]: any }
		if kind ~= "lanternLit" then
			return
		end
		local position = data.position
		local direction = data.direction
		local model = data.model
		if typeof(position) ~= "Vector3" or typeof(direction) ~= "Vector3" then
			return
		end
		-- The direction drives distant positional echoes. Keep the remote boundary finite.
		if direction.Magnitude < 0.01 or direction ~= direction then
			return
		end

		if typeof(model) == "Instance" and model:IsA("Model") then
			beginFlare(model)
		end
		playAt(Config.Lantern.igniteCue, position)
		-- THE ECHOES BELONG TO THE GAS LANTERN ALONE. They are the cave answering the one lamp that
		-- ended a run; the network lamps that catch through the cave are the same ignition heard nearby,
		-- and giving each of them its own pair of distant answers would turn a
		-- composed beat into a dozen overlapping delayed cues. `nil` still means "yes", so nothing
		-- that fired this event before the network existed changed behaviour.
		if data.echoes ~= false then
			scheduleEchoes(position, direction.Unit)
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return LanternPresentation

--!strict
-- Server authority for data-stamped doorway barriers: burning vines and melting Ice bars.
-- Vine fire catches and spreads between nearby curtains. Ice instead accumulates melt progress from
-- maximum brightness or a faster Flare, then leaves a timed cosmetic puddle. Progress is entirely
-- server-owned and shared by everyone at the opening.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local VineRules = require(ReplicatedStorage.Shared.Logic.VineRules)
local IcicleRules = require(ReplicatedStorage.Shared.Logic.IcicleRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local FloorBuilder = require(script.Parent.FloorBuilder)
local NoiseService = require(script.Parent.NoiseService)
local Telemetry = require(script.Parent.Telemetry)

local VineService = {}

type Runtime = FloorBuilder.VineRuntime & {
	-- Qualifying light held at the opening so far, in seconds. Never decays: a party can take turns
	-- at a curtain, and a lone runner can retreat, refill the dial and come back to where they left it.
	exposure: number,
	-- Set once the curtain catches. From here the burn needs no one present.
	alight: boolean,
	-- When a neighbour's fire is due to reach this curtain, if one has thrown to it.
	catchesAt: number?,
	progress: number,
	scorch: number,
	embers: ParticleEmitter?,
	fire: Fire?,
	light: PointLight?,
	strandColors: { Color3 },
	strandTransparencies: { number },
}

local runtimesByDepth: { [number]: { Runtime } } = {}
local nextHintAt: { [Types.PlayerId]: number } = {}

local function makeEmbers(runtime: FloorBuilder.VineRuntime): ParticleEmitter
	local visual = Config.Vines.visual
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "VineEmbers"
	emitter.Enabled = false
	emitter.Rate = 34
	emitter.Lifetime = NumberRange.new(0.5, 1.2)
	emitter.Speed = NumberRange.new(1, 5)
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.Size = NumberSequence.new(0.32)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(visual.emberColor, visual.charColor)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Acceleration = Vector3.new(0, 6, 0)
	emitter.Parent = runtime.barrier
	return emitter
end

-- The open flame of a curtain that has caught, plus the light it throws. Both live on the barrier,
-- which outlives every strand, so neither blinks out early as the growth is consumed.
local function makeFire(runtime: FloorBuilder.VineRuntime): (Fire, PointLight)
	local visual = Config.Vines.visual
	local fire = Instance.new("Fire")
	fire.Name = "VineFire"
	fire.Enabled = false
	fire.Heat = 12
	fire.Size = 9
	fire.Color = visual.emberColor
	fire.SecondaryColor = Color3.fromRGB(120, 40, 12)
	fire.Parent = runtime.barrier

	local light = Instance.new("PointLight")
	light.Name = "VineFireLight"
	light.Enabled = false
	light.Color = visual.emberColor
	light.Brightness = 2.4
	light.Range = 26
	light.Shadows = false
	light.Parent = runtime.barrier
	return fire, light
end

-- Everything the curtain currently looks like: scorched by held light before it catches, then
-- charred through and eaten strand by strand once it is alight.
local function applyBurnVisual(runtime: Runtime)
	if runtime.style == "Icicles" then
		local visual = Config.Icicles.visual
		for index, part in runtime.strands do
			if part.Parent ~= nil then
				part.Color = runtime.strandColors[index]:Lerp(visual.meltColor, runtime.progress)
				part.Transparency = math.clamp(runtime.strandTransparencies[index] + runtime.progress * 0.78, 0, 1)
			end
		end
		return
	end
	local visual = Config.Vines.visual
	local total = #runtime.strands
	for index, part in runtime.strands do
		if part.Parent == nil then
			continue
		end
		local consumed = index / total
		if runtime.progress >= consumed then
			part:Destroy()
			continue
		end
		-- Char runs ahead of the flame front, so the whole curtain is visibly dying rather than only
		-- the part currently being eaten.
		local char = math.max(runtime.scorch, math.clamp(runtime.progress / math.max(consumed, 0.001), 0, 1))
		part.Color = runtime.strandColors[index]:Lerp(visual.charColor, char)
	end
end

function VineService.registerFloor(depth: number, inputs: { FloorBuilder.VineRuntime })
	local floorRuntimes: { Runtime } = {}
	for _, input in inputs do
		local strandColors: { Color3 } = {}
		local strandTransparencies: { number } = {}
		for index, part in input.strands do
			strandColors[index] = part.Color
			strandTransparencies[index] = part.Transparency
		end
		local fire: Fire? = nil
		local light: PointLight? = nil
		local embers: ParticleEmitter? = nil
		if input.style == "Vines" then
			fire, light = makeFire(input)
			embers = makeEmbers(input)
		end
		table.insert(floorRuntimes, {
			model = input.model,
			barrier = input.barrier,
			strands = input.strands,
			depth = input.depth,
			position = input.position,
			style = input.style,
			puddleParent = input.puddleParent,
			puddlePosition = input.puddlePosition,
			puddleSize = input.puddleSize,
			exposure = 0,
			alight = false,
			catchesAt = nil,
			progress = 0,
			scorch = 0,
			embers = embers,
			fire = fire,
			light = light,
			strandColors = strandColors,
			strandTransparencies = strandTransparencies,
		})
	end
	runtimesByDepth[depth] = floorRuntimes
end

local function withinReach(position: Vector3, curtain: Vector3, radius: number): boolean
	local delta = position - curtain
	-- The opening is a vertical slot: a generous vertical band keeps a curtain in a room with a
	-- rolling floor reachable, while the horizontal test stays honest.
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= radius and math.abs(delta.Y) <= radius * 2
end

local function sendLowLightHint(playerId: Types.PlayerId, now: number, message: string)
	if now < (nextHintAt[playerId] or 0) then
		return
	end
	nextHintAt[playerId] = now + Config.Vines.hintCooldownSeconds
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = message })
	end
end

local function finishIcicleMelt(runtime: Runtime)
	local parent = runtime.puddleParent
	local puddle = Instance.new("Part")
	puddle.Name = "MeltwaterPuddle"
	puddle.Size = runtime.puddleSize
	puddle.Position = runtime.puddlePosition
	puddle.Color = Config.Icicles.visual.puddleColor
	puddle.Material = Enum.Material.Glass
	puddle.Transparency = 0.42
	puddle.Anchored = true
	puddle.CanCollide = false
	puddle.CanQuery = false
	puddle.CanTouch = false
	puddle.CastShadow = false
	puddle.Parent = parent
	runtime.model:Destroy()
	Telemetry.event("icicle_barricade_melted", nil, { depth = runtime.depth })
	task.delay(Config.Icicles.puddleLifetimeSeconds, function()
		if puddle.Parent ~= nil then
			puddle:Destroy()
		end
	end)
end

-- Set a curtain alight and throw fire at its neighbours. Each catch schedules the next, so one
-- section taken at full brightness runs the length of the growth a floor is carrying.
local function ignite(floorRuntimes: { Runtime }, runtime: Runtime, now: number)
	if runtime.alight then
		return
	end
	runtime.alight = true
	runtime.catchesAt = nil
	-- Burning through a curtain was always meant to be a loud commitment; now it literally is. Each
	-- curtain that catches announces itself, so a spreading fire is progressively noisier.
	NoiseService.emit("VineBurn", runtime.position, nil)
	local fire = runtime.fire
	if fire ~= nil then
		fire.Enabled = true
	end
	local light = runtime.light
	if light ~= nil then
		light.Enabled = true
	end
	local embers = runtime.embers
	if embers ~= nil then
		embers.Enabled = true
	end

	for _, other in floorRuntimes do
		if
			other.alight
			or other.catchesAt ~= nil
			or other.model.Parent == nil
			or not VineRules.spreadsTo(runtime.position, other.position)
		then
			continue
		end
		other.catchesAt = now + Config.Vines.spreadDelaySeconds
	end
end

function VineService.tick(dt: number)
	if not Config.Vines.enabled then
		return
	end
	local now = os.clock()
	for _, floorRuntimes in runtimesByDepth do
		for _, runtime in floorRuntimes do
			if runtime.model.Parent == nil or runtime.progress >= 1 then
				continue
			end

			if runtime.style == "Icicles" then
				local meltDuration: number? = nil
				for playerId, state in PlayerState.all() do
					if
						not state.alive
						or state.finished
						or state.snuffedAt ~= nil
						or state.depth ~= runtime.depth
						or not withinReach(state.position, runtime.position, Config.Icicles.meltRadius)
					then
						continue
					end
					local candidate = IcicleRules.meltSeconds(
						state.isLit,
						state.isCupping,
						state.burnRate,
						state.flareEndsAt > now,
						state.modifiers.maxBurnRate
					)
					if candidate ~= nil then
						meltDuration = if meltDuration == nil then candidate else math.min(meltDuration, candidate)
					else
						sendLowLightHint(playerId, now, Config.Icicles.lowLightMessage)
					end
				end
				if meltDuration ~= nil then
					runtime.progress = math.min(runtime.progress + dt / math.max(meltDuration, 0.01), 1)
					applyBurnVisual(runtime)
					if runtime.progress >= 1 then
						finishIcicleMelt(runtime)
					end
				end
				continue
			end

			-- Already alight: it needs no one standing there. Fire finishes the curtain on its own.
			if runtime.alight then
				runtime.progress = math.min(runtime.progress + dt / math.max(Config.Vines.burnSeconds, 0.01), 1)
				applyBurnVisual(runtime)
				if runtime.progress >= 1 then
					runtime.model:Destroy()
					Telemetry.event("vine_burned", nil, { depth = runtime.depth })
				end
				continue
			end

			local catchesAt = runtime.catchesAt
			if catchesAt ~= nil and now >= catchesAt then
				ignite(floorRuntimes, runtime, now)
				continue
			end

			local held = false
			for playerId, state in PlayerState.all() do
				if
					not state.alive
					or state.finished
					or state.snuffedAt ~= nil
					or state.depth ~= runtime.depth
					or not withinReach(state.position, runtime.position, Config.Vines.burnRadius)
				then
					continue
				end
				if
					VineRules.burnsVines(
						state.isLit,
						state.isCupping,
						state.burnRate,
						state.flareEndsAt > now,
						state.modifiers.maxBurnRate
					)
				then
					held = true
				else
					sendLowLightHint(playerId, now, Config.Vines.lowLightMessage)
				end
			end

			local embers = runtime.embers
			if embers ~= nil and embers.Enabled ~= held then
				embers.Enabled = held
			end
			-- Scorch is permanent: a curtain someone started never recovers, so a party can take turns
			-- at it and a single runner can retreat, refill the dial, and come back to where they left it.
			if not held then
				continue
			end

			runtime.exposure += dt
			-- Held light darkens the growth but never blacks it out on its own — the last of the colour
			-- goes with the flame, so "scorched" and "burning" stay distinguishable at a glance.
			runtime.scorch = math.clamp(runtime.exposure / math.max(Config.Vines.igniteSeconds, 0.01), 0, 1) * 0.85
			applyBurnVisual(runtime)
			if runtime.exposure >= Config.Vines.igniteSeconds then
				ignite(floorRuntimes, runtime, now)
			end
		end
	end
end

function VineService.reset()
	table.clear(runtimesByDepth)
	table.clear(nextHintAt)
end

return VineService

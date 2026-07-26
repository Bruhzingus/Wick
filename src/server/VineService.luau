--!strict
-- Server authority for burning vine curtains. A curtain opens only under sustained qualifying
-- light (Logic/VineRules); progress is server-owned, shared by everyone standing at the opening,
-- and never resumes from the client. Charring is driven straight onto the parts, so there is no
-- separate visual protocol to keep in sync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local VineRules = require(ReplicatedStorage.Shared.Logic.VineRules)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local PlayerState = require(script.Parent.PlayerState)
local FloorBuilder = require(script.Parent.FloorBuilder)
local Telemetry = require(script.Parent.Telemetry)

local VineService = {}

type Runtime = FloorBuilder.VineRuntime & {
	progress: number,
	burning: boolean,
	embers: ParticleEmitter?,
	strandColors: { Color3 },
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

-- Char the curtain from the bottom up and drop strands as the burn eats through them.
local function applyBurnVisual(runtime: Runtime)
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
		local char = math.clamp(runtime.progress / math.max(consumed, 0.001), 0, 1)
		part.Color = runtime.strandColors[index]:Lerp(visual.charColor, char)
	end
end

function VineService.registerFloor(depth: number, inputs: { FloorBuilder.VineRuntime })
	local floorRuntimes: { Runtime } = {}
	for _, input in inputs do
		local strandColors: { Color3 } = {}
		for index, part in input.strands do
			strandColors[index] = part.Color
		end
		table.insert(floorRuntimes, {
			model = input.model,
			barrier = input.barrier,
			strands = input.strands,
			depth = input.depth,
			position = input.position,
			progress = 0,
			burning = false,
			embers = makeEmbers(input),
			strandColors = strandColors,
		})
	end
	runtimesByDepth[depth] = floorRuntimes
end

local function withinReach(position: Vector3, curtain: Vector3): boolean
	local delta = position - curtain
	local radius = Config.Vines.burnRadius
	-- The opening is a vertical slot: a generous vertical band keeps a curtain in a room with a
	-- rolling floor reachable, while the horizontal test stays honest.
	return Vector3.new(delta.X, 0, delta.Z).Magnitude <= radius and math.abs(delta.Y) <= radius * 2
end

local function sendLowLightHint(playerId: Types.PlayerId, now: number)
	if now < (nextHintAt[playerId] or 0) then
		return
	end
	nextHintAt[playerId] = now + Config.Vines.hintCooldownSeconds
	local player = Players:GetPlayerByUserId(playerId)
	if player ~= nil then
		Remotes.get("RunEvent"):FireClient(player, "message", { text = Config.Vines.lowLightMessage })
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

			local burning = false
			for playerId, state in PlayerState.all() do
				if
					not state.alive
					or state.finished
					or state.snuffedAt ~= nil
					or state.depth ~= runtime.depth
					or not withinReach(state.position, runtime.position)
				then
					continue
				end
				if VineRules.burnsVines(state.isLit, state.isCupping, state.burnRate, state.flareEndsAt > now) then
					burning = true
				else
					sendLowLightHint(playerId, now)
				end
			end

			if burning ~= runtime.burning then
				runtime.burning = burning
				local embers = runtime.embers
				if embers ~= nil then
					embers.Enabled = burning
				end
			end
			-- Char is permanent: a curtain someone started never grows back, so a party can take
			-- turns at it and a single runner can retreat, refill the dial, and come back.
			if not burning then
				continue
			end

			runtime.progress = math.min(runtime.progress + dt / math.max(Config.Vines.burnSeconds, 0.01), 1)
			applyBurnVisual(runtime)
			if runtime.progress >= 1 then
				runtime.model:Destroy()
				Telemetry.event("vine_burned", nil, { depth = runtime.depth })
			end
		end
	end
end

function VineService.reset()
	table.clear(runtimesByDepth)
	table.clear(nextHintAt)
end

return VineService

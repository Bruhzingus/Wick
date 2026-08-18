--!strict
-- Corrects character displacement that exceeds every server-configured movement mode by a
-- generous replication margin. Server-authorized spawns/teleports explicitly reset the sample.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local MovementService = require(script.Parent.MovementService)
local Telemetry = require(script.Parent.Telemetry)

local MovementSanityService = {}

type Sample = {
	position: Vector3,
	at: number,
}

local samples: { [Types.PlayerId]: Sample } = {}
local accumulator = 0

local function horizontalDistance(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

function MovementSanityService.markAuthorized(playerId: Types.PlayerId, position: Vector3)
	samples[playerId] = {
		position = position,
		at = os.clock(),
	}
end

function MovementSanityService.clear(playerId: Types.PlayerId)
	samples[playerId] = nil
end

function MovementSanityService.tick(dt: number)
	accumulator += dt
	if accumulator < Config.Security.movement.sampleSeconds then
		return
	end
	accumulator = 0

	local now = os.clock()
	for playerId, state in PlayerState.all() do
		if not state.alive or state.finished then
			samples[playerId] = nil
			continue
		end
		local current = CharacterService.basePosition(playerId)
		if current == nil then
			continue
		end
		local sample = samples[playerId]
		if sample == nil then
			MovementSanityService.markAuthorized(playerId, current)
			continue
		end
		local elapsed = math.max(now - sample.at, Config.Security.movement.sampleSeconds)
		-- THE DEVELOPER SPRINT IS A SPEED THE SERVER GRANTED, so the ceiling has to know about it.
		-- Without this, a tester holding V in the laboratory covers four times what this allows and is
		-- corrected back on every 0.2s sample — which does not look like a rejected exploit, it looks
		-- like the sprint key is broken. The multiplier is 1 for everyone else, so nothing outside the
		-- laboratory is loosened by a stud.
		local allowed = Config.Movement.runSpeed
				* MovementService.devSuperSprintMultiplier(playerId)
				* elapsed
				* Config.Security.movement.slackMultiplier
			+ Config.Security.movement.teleportAllowance
		local distance = horizontalDistance(sample.position, current)
		if distance > allowed then
			CharacterService.teleport(playerId, sample.position)
			state.position = sample.position
			Telemetry.event("movement_corrected", playerId, {
				distance = math.floor(distance * 10) / 10,
				allowed = math.floor(allowed * 10) / 10,
			})
			sample.at = now
		elseif elapsed >= Config.Security.movement.trustWindowSeconds then
			sample.position = current
			sample.at = now
		end
	end
end

function MovementSanityService.reset()
	table.clear(samples)
	accumulator = 0
end

return MovementSanityService

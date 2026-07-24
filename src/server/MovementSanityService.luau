--!strict
-- Corrects character displacement that exceeds every server-configured movement mode by a
-- generous replication margin. Server-authorized spawns/teleports explicitly reset the sample.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)
local CharacterService = require(script.Parent.CharacterService)
local Telemetry = require(script.Parent.Telemetry)

local MovementSanityService = {}

type Sample = {
	position: Vector3,
	at: number,
	burstDistance: number,
	burstExpiresAt: number,
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
		burstDistance = 0,
		burstExpiresAt = 0,
	}
end

-- MovementService calls this only after the server approves and charges a short burst.
function MovementSanityService.authorizeBurst(playerId: Types.PlayerId, distance: number, duration: number)
	local sample = samples[playerId]
	if sample == nil or distance <= 0 then
		return
	end
	sample.burstDistance += distance
	sample.burstExpiresAt =
		math.max(sample.burstExpiresAt, os.clock() + math.max(duration, 0) + Config.Security.movement.sampleSeconds)
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
		local allowed = Config.Movement.runSpeed * elapsed * Config.Security.movement.slackMultiplier
			+ Config.Security.movement.teleportAllowance
		-- Server-approved bursts add one bounded distance credit. The credit survives an anchor
		-- rollover while its motion is in flight, then clears at the next trusted rollover.
		allowed += sample.burstDistance
		local distance = horizontalDistance(sample.position, current)
		if distance > allowed then
			CharacterService.teleport(playerId, sample.position)
			state.position = sample.position
			Telemetry.event("movement_corrected", playerId, {
				distance = math.floor(distance * 10) / 10,
				allowed = math.floor(allowed * 10) / 10,
			})
			sample.at = now
			sample.burstDistance = 0
			sample.burstExpiresAt = 0
		elseif elapsed >= Config.Security.movement.trustWindowSeconds then
			sample.position = current
			sample.at = now
			if now >= sample.burstExpiresAt then
				sample.burstDistance = 0
				sample.burstExpiresAt = 0
			end
		end
	end
end

function MovementSanityService.reset()
	table.clear(samples)
	accumulator = 0
end

return MovementSanityService

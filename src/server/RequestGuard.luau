--!strict
-- Shared server trust boundary: per-player remote throttles and finite-number helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TokenBucket = require(ReplicatedStorage.Shared.Logic.TokenBucket)

local RequestGuard = {}

local buckets: { [number]: { [string]: TokenBucket.Bucket } } = {}

function RequestGuard.allow(player: Player, remoteName: string): boolean
	local limit = Config.Security.remoteRateLimits[remoteName]
	if limit == nil then
		return false
	end
	local playerBuckets = buckets[player.UserId]
	if playerBuckets == nil then
		playerBuckets = {}
		buckets[player.UserId] = playerBuckets
	end
	local nextBucket, allowed = TokenBucket.consume(playerBuckets[remoteName], limit.burst, limit.perSecond, os.clock())
	playerBuckets[remoteName] = nextBucket
	return allowed
end

function RequestGuard.finiteNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function RequestGuard.finiteVector3(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	return value.X == value.X
		and value.Y == value.Y
		and value.Z == value.Z
		and math.abs(value.X) < math.huge
		and math.abs(value.Y) < math.huge
		and math.abs(value.Z) < math.huge
end

function RequestGuard.clear(playerId: number)
	buckets[playerId] = nil
end

return RequestGuard

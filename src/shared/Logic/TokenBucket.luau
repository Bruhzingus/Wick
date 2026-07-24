--!strict
-- Pure token-bucket arithmetic. Server adapters own the per-player bucket tables.

export type Bucket = {
	tokens: number,
	updatedAt: number,
}

local TokenBucket = {}

function TokenBucket.consume(
	current: Bucket?,
	capacity: number,
	refillPerSecond: number,
	now: number,
	cost: number?
): (Bucket, boolean)
	local charge = cost or 1
	local bucket = current or {
		tokens = capacity,
		updatedAt = now,
	}
	local elapsed = math.max(now - bucket.updatedAt, 0)
	local available = math.min(capacity, bucket.tokens + elapsed * refillPerSecond)
	local allowed = available >= charge
	return {
		tokens = if allowed then available - charge else available,
		updatedAt = now,
	}, allowed
end

return TokenBucket

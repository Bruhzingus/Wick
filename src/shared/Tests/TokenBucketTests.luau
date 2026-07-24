--!strict

local Harness = require(script.Parent.Harness)
local TokenBucket = require(script.Parent.Parent.Logic.TokenBucket)

local suite: Harness.Suite = {
	name = "TokenBucket",
	tests = {
		Harness.test("a fresh bucket starts full and consumes the default cost", function()
			local bucket, allowed = TokenBucket.consume(nil, 4, 2, 10)
			Harness.equal(allowed, true)
			Harness.near(bucket.tokens, 3)
			Harness.near(bucket.updatedAt, 10)
		end),

		Harness.test("elapsed time refills tokens without exceeding capacity", function()
			local initial: TokenBucket.Bucket = { tokens = 0, updatedAt = 10 }
			local partial, partialAllowed = TokenBucket.consume(initial, 4, 2, 10.25)
			Harness.equal(partialAllowed, false)
			Harness.near(partial.tokens, 0.5)

			local full, fullAllowed = TokenBucket.consume(partial, 4, 2, 100)
			Harness.equal(fullAllowed, true)
			Harness.near(full.tokens, 3)
		end),

		Harness.test("denials preserve available tokens and advance the refill timestamp", function()
			local initial: TokenBucket.Bucket = { tokens = 0.75, updatedAt = 10 }
			local denied, allowed = TokenBucket.consume(initial, 4, 0, 12)
			Harness.equal(allowed, false)
			Harness.near(denied.tokens, 0.75)
			Harness.near(denied.updatedAt, 12)
		end),

		Harness.test("custom costs and backward clocks are handled deterministically", function()
			local initial: TokenBucket.Bucket = { tokens = 3, updatedAt = 10 }
			local charged, allowed = TokenBucket.consume(initial, 5, 10, 9, 2.5)
			Harness.equal(allowed, true)
			Harness.near(charged.tokens, 0.5)
			Harness.near(charged.updatedAt, 9)
		end),
	},
}

return suite

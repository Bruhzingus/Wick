--!strict

local Harness = require(script.Parent.Harness)
local PartyVote = require(script.Parent.Parent.Logic.PartyVote)

local FALLBACK = 1

local suite: Harness.Suite = {
	name = "PartyVote",
	tests = {
		Harness.test("a majority wins outright", function()
			local winner = PartyVote.resolve({ [1] = 3, [2] = 3, [3] = 2 }, { 1, 2, 3 }, 3, FALLBACK)
			Harness.equal(winner, 3, "two votes for tier 3 must beat one for tier 2")
		end),

		Harness.test("the leader breaks a tie they voted in", function()
			-- The whole reason the leader is kept in this rule. Without it a two-way split has no
			-- honest answer and the party sits in the car arguing.
			local winner = PartyVote.resolve({ [1] = 2, [2] = 3 }, { 1, 2 }, 2, FALLBACK)
			Harness.equal(winner, 3, "the leader's own vote must settle a deadlock")
		end),

		Harness.test("a tie the leader did not vote in falls to the shallowest cave", function()
			-- Deliberately NOT the deepest: a party that cannot agree should not have somebody's
			-- admission fee spent for them by a coin flip.
			local winner = PartyVote.resolve({ [1] = 2, [2] = 3 }, { 1, 2, 9 }, 9, FALLBACK)
			Harness.equal(winner, 2, "an unbroken tie must resolve to the lowest tier id")
		end),

		Harness.test("votes from players who left the party are ignored", function()
			-- A member who walks out of the car mid-vote must stop steering it. If this regressed, a
			-- party of two could be launched into a cave neither of them chose.
			local winner = PartyVote.resolve({ [1] = 2, [2] = 3, [3] = 3 }, { 1 }, 1, FALLBACK)
			Harness.equal(winner, 2, "only current members may be counted")
		end),

		Harness.test("a silent party gets the fallback rather than tier zero", function()
			local winner = PartyVote.resolve({}, { 1, 2 }, 1, FALLBACK)
			Harness.equal(winner, FALLBACK, "no votes at all must still resolve to a legal cave")
		end),

		Harness.test("the tally counts only current members, like the resolver", function()
			-- The display and the decision read the same votes. If these two ever disagreed the UI
			-- would show a winner the launch does not use.
			local counts = PartyVote.tally({ [1] = 2, [2] = 2, [3] = 3 }, { 1, 2 })
			Harness.equal(counts[2], 2, "both remaining members backed tier 2")
			Harness.isNil(counts[3], "the departed member's vote must not appear in the tally")
		end),
	},
}

return suite

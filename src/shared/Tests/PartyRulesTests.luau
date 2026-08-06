--!strict

local Harness = require(script.Parent.Harness)
local PartyRules = require(script.Parent.Parent.Logic.PartyRules)

local MEMBERS = { 10, 20, 30 }

local suite: Harness.Suite = {
	name = "PartyRules",
	tests = {
		Harness.test("the first-member leader may remove another rider before launch", function()
			Harness.expect(
				PartyRules.canKick(10, MEMBERS, "Gathering", 10, 20),
				"the recorded leader should be able to remove a different current member"
			)
			Harness.expect(
				PartyRules.canKick(10, MEMBERS, "Voting", 10, 30),
				"a roster change during voting should still be reversible"
			)
		end),

		Harness.test("kick refuses non-leaders, self-removal, outsiders and committed parties", function()
			Harness.expect(not PartyRules.canKick(10, MEMBERS, "Gathering", 20, 30), "a member is not the leader")
			Harness.expect(not PartyRules.canKick(10, MEMBERS, "Gathering", 10, 10), "the leader cannot kick themself")
			Harness.expect(not PartyRules.canKick(10, MEMBERS, "Gathering", 10, 99), "the target must be in the party")
			Harness.expect(not PartyRules.canKick(10, MEMBERS, "Launching", 10, 20), "launching freezes the roster")
		end),

		Harness.test("a re-entry block expires against the same server clock", function()
			Harness.near(PartyRules.joinBlockRemaining(120, 105), 15, 0.0001, "fifteen seconds should remain")
			Harness.equal(PartyRules.joinBlockRemaining(120, 120), 0, "the exact deadline is open")
			Harness.equal(PartyRules.joinBlockRemaining(120, 140), 0, "an expired block never goes negative")
			Harness.equal(PartyRules.joinBlockRemaining(nil, 105), 0, "an unblocked player may join")
		end),
	},
}

return suite

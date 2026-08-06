--!strict

local Harness = require(script.Parent.Harness)
local Party = require(script.Parent.Parent.Interfaces.Party)

local suite: Harness.Suite = {
	name = "PartyInterface",
	tests = {
		Harness.test("reserved-server party id zero is a real expedition", function()
			Party.clear()
			Harness.expect(Party.joinExpedition(610, 4), "the first reserved-server arrival should join")
			local expedition = Party.expedition()
			Harness.expect(expedition ~= nil, "party id zero must not be mistaken for no expedition")
			if expedition ~= nil then
				Harness.equal(expedition.partyId, 0, "reserved arrivals belong to the dedicated party id")
				Harness.equal(expedition.members[1], 610, "the arriving player must be readable by the run")
			end
			Party.clear()
		end),
	},
}

return suite

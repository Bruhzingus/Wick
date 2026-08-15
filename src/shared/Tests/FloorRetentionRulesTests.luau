--!strict

local Harness = require(script.Parent.Harness)
local FloorRetentionRules = require(script.Parent.Parent.Logic.FloorRetentionRules)

local function expectDepths(actual: { number }, expected: { number })
	Harness.equal(#actual, #expected, "retired depth count")
	for index, depth in expected do
		Harness.equal(actual[index], depth, "retired depth at index " .. index)
	end
end

local suite: Harness.Suite = {
	name = "FloorRetentionRules",
	tests = {
		Harness.test("retires only depths strictly behind the trailing margin", function()
			expectDepths(FloorRetentionRules.retireableDepths({ 1, 2, 3, 4, 5, 6, 7 }, { 6 }, 2, nil), { 1, 2, 3 })
		end),

		Harness.test("the shallowest split-party member protects shared history", function()
			expectDepths(FloorRetentionRules.retireableDepths({ 1, 2, 3, 4, 5, 6, 7 }, { 3, 7 }, 2, nil), {})
		end),

		Harness.test("retained entry floor remains while later history retires", function()
			expectDepths(
				FloorRetentionRules.retireableDepths({ 1, 2, 3, 4, 5, 6, 7 }, { 6 }, 2, { [1] = true }),
				{ 2, 3 }
			)
		end),

		Harness.test("no connected participant means no speculative retirement", function()
			expectDepths(FloorRetentionRules.retireableDepths({ 1, 2, 3 }, {}, 2, nil), {})
		end),

		-- A ghost that stays behind is an ordinary protected participant, and it is the SHALLOWEST
		-- one that decides. RunOrchestrator derives this list from `runners` (which a dead player
		-- stays in) and tests `finished` rather than `alive`, so this case is reachable in a real run
		-- whenever someone dies early and the rest of the party keeps descending.
		Harness.test("a participant left far behind pins the whole history", function()
			expectDepths(FloorRetentionRules.retireableDepths({ 1, 2, 3, 4, 5, 6 }, { 2, 6 }, 2, { [1] = true }), {})
		end),

		Harness.test("nothing built yet retires nothing", function()
			expectDepths(FloorRetentionRules.retireableDepths({}, { 5 }, 2, nil), {})
		end),

		-- The margin is a trailing allowance, not the thing that protects the occupied floor: even at
		-- zero the depth a participant is standing on must survive, because `cutoff` is exclusive.
		Harness.test("a zero margin still keeps the floor being stood on", function()
			expectDepths(FloorRetentionRules.retireableDepths({ 1, 2, 3 }, { 3 }, 0, nil), { 1, 2 })
		end),

		-- Retirement must never depend on the order the floor table happened to enumerate in, and
		-- RunOrchestrator retires `[1]` first when its per-sweep budget is 1 — so ascending order is
		-- load-bearing, not cosmetic: the oldest floor has to be the one that goes.
		Harness.test("unordered input still retires oldest-first", function()
			expectDepths(FloorRetentionRules.retireableDepths({ 5, 1, 4, 3, 2 }, { 5 }, 1, nil), { 1, 2, 3 })
		end),
	},
}

return suite

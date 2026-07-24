--!strict
-- Runs deterministic pure-rule tests only inside Studio. It is a separate Script so failures are
-- prominent without preventing the gameplay boot Script from starting a manual playtest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if RunService:IsStudio() then
	local Tests = require(ReplicatedStorage.Shared.Tests)

	task.defer(function()
		local passed, summary = Tests.run()
		if passed then
			print(string.format("[WICK TESTS] PASS: %d deterministic tests", summary.passed))
			return
		end

		local lines: { string } = {
			string.format("[WICK TESTS] FAIL: %d passed, %d failed", summary.passed, summary.failed),
		}
		for _, failure in summary.failures do
			table.insert(lines, string.format("- %s: %s", failure.name, failure.message))
		end
		error(table.concat(lines, "\n"), 0)
	end)
end

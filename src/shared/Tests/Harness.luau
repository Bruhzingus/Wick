--!strict
-- Compact in-repo test harness for deterministic pure-rule tests. This deliberately has no
-- third-party dependency so a fresh Rojo sync can run the suite in Studio immediately.

export type TestCase = {
	name: string,
	run: () -> (),
}

export type Suite = {
	name: string,
	tests: { TestCase },
}

export type Failure = {
	name: string,
	message: string,
}

export type Summary = {
	passed: number,
	failed: number,
	failures: { Failure },
}

local Harness = {}

function Harness.test(name: string, run: () -> ()): TestCase
	return {
		name = name,
		run = run,
	}
end

function Harness.expect(condition: boolean, message: string?)
	if not condition then
		error(message or "expected condition to be true", 2)
	end
end

function Harness.equal<T>(actual: T, expected: T, message: string?)
	if actual ~= expected then
		error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

function Harness.isNil(value: unknown, message: string?)
	if value ~= nil then
		error(message or string.format("expected nil, got %s", tostring(value)), 2)
	end
end

function Harness.near(actual: number, expected: number, epsilon: number?, message: string?)
	local tolerance = epsilon or 1e-6
	if actual ~= actual or math.abs(actual - expected) > tolerance then
		error(message or string.format("expected %.12g +/- %.3g, got %.12g", expected, tolerance, actual), 2)
	end
end

function Harness.vectorNear(actual: Vector3, expected: Vector3, epsilon: number?, message: string?)
	local tolerance = epsilon or 1e-6
	if (actual - expected).Magnitude > tolerance then
		error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
	end
end

function Harness.run(suites: { Suite }): (boolean, Summary)
	local summary: Summary = {
		passed = 0,
		failed = 0,
		failures = {},
	}

	for _, suite in suites do
		for _, testCase in suite.tests do
			local ok, issue = pcall(testCase.run)
			if ok then
				summary.passed += 1
			else
				summary.failed += 1
				table.insert(summary.failures, {
					name = suite.name .. " > " .. testCase.name,
					message = tostring(issue),
				})
			end
		end
	end

	return summary.failed == 0, summary
end

return Harness

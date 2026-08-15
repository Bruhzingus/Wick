--!strict
-- Pure eligibility for retiring generated floors. This module decides only which exact depths are
-- safely behind every connected expedition participant; RunOrchestrator owns the actual teardown.

local FloorRetentionRules = {}

function FloorRetentionRules.retireableDepths(
	builtDepths: { number },
	protectedDepths: { number },
	retentionBehind: number,
	retainedDepths: { [number]: boolean }?
): { number }
	if #protectedDepths == 0 then
		return {}
	end

	local shallowest = math.huge
	for _, depth in protectedDepths do
		shallowest = math.min(shallowest, depth)
	end
	local cutoff = shallowest - math.max(0, math.floor(retentionBehind))
	local result: { number } = {}
	for _, depth in builtDepths do
		if depth < cutoff and (retainedDepths == nil or retainedDepths[depth] ~= true) then
			table.insert(result, depth)
		end
	end
	table.sort(result)
	return result
end

return FloorRetentionRules

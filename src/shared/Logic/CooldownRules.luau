--!strict
-- Pure read-only projection of server-owned tool and movement cooldown state for UI rendering.
-- The returned remaining time is informational only; authoritative services still validate use.

local Types = require(script.Parent.Parent.Types)
local ToolsConfig = require(script.Parent.Parent.Config.Tools)

export type CooldownStatus = {
	remaining: number,
	duration: number,
}

local CooldownRules = {}

local function statusUntil(deadline: number, duration: number, now: number): CooldownStatus
	return {
		remaining = math.max(deadline - now, 0),
		duration = duration,
	}
end

local function toolStatus(state: Types.PlayerRunState, def: Types.ToolDef, now: number): CooldownStatus
	local deadline = state.nextToolUse[def.id] or 0
	local duration = def.cooldown * state.modifiers.toolCooldownMultiplier
	return statusUntil(deadline, duration, now)
end

function CooldownRules.forAction(state: Types.PlayerRunState, actionId: string, now: number): CooldownStatus?
	local tool = ToolsConfig[actionId :: Types.ToolId]
	if tool ~= nil then
		return toolStatus(state, tool, now)
	end
	return nil
end

function CooldownRules.snapshot(state: Types.PlayerRunState, now: number): { [string]: CooldownStatus }
	local result: { [string]: CooldownStatus } = {}
	for toolId in ToolsConfig do
		local status = CooldownRules.forAction(state, toolId, now)
		if status ~= nil then
			result[toolId] = status
		end
	end

	return result
end

return CooldownRules

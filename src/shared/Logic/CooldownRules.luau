--!strict
-- Pure read-only projection of server-owned tool and movement cooldown state for UI rendering.
-- The returned remaining time is informational only; authoritative services still validate use.

local Types = require(script.Parent.Parent.Types)
local DeathConfig = require(script.Parent.Parent.Config.Death)
local MovementConfig = require(script.Parent.Parent.Config.Movement)
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

local function movementStatus(lastUsedAt: number, duration: number, now: number): CooldownStatus
	-- PlayerState.freshState seeds -math.huge as the "never used" sentinel, so a fresh action
	-- renders ready immediately rather than waiting out a cooldown window from time zero.
	local deadline = if lastUsedAt <= 0 then now else lastUsedAt + duration
	return statusUntil(deadline, duration, now)
end

local function toolStatus(state: Types.PlayerRunState, def: Types.ToolDef, now: number): CooldownStatus
	local deadline = state.nextToolUse[def.id] or 0
	local duration = def.cooldown

	-- A voluntarily extinguished toggle cannot relight until its commitment delay has elapsed.
	-- Project the later gate so the UI never claims the action is ready before validation does.
	if def.togglesLit and not state.isLit and state.unlitByChoice then
		local relightDeadline = state.litChangedAt + DeathConfig.selfRelightDelaySeconds
		if relightDeadline >= deadline then
			deadline = relightDeadline
			duration = DeathConfig.selfRelightDelaySeconds
		end
	end

	return statusUntil(deadline, duration, now)
end

function CooldownRules.forAction(state: Types.PlayerRunState, actionId: string, now: number): CooldownStatus?
	local tool = ToolsConfig[actionId :: Types.ToolId]
	if tool ~= nil then
		return toolStatus(state, tool, now)
	end
	if actionId == "Dodge" then
		return movementStatus(state.lastDodgeAt, MovementConfig.dodgeCooldown, now)
	end
	if actionId == "Slide" then
		return movementStatus(state.lastSlideAt, MovementConfig.slideCooldown, now)
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

	local dodge = CooldownRules.forAction(state, "Dodge", now)
	if dodge ~= nil then
		result.Dodge = dodge
	end
	local slide = CooldownRules.forAction(state, "Slide", now)
	if slide ~= nil then
		result.Slide = slide
	end
	return result
end

return CooldownRules

--!strict
-- Pure: can this player use this tool right now, and what does using it mean?
-- One generic rule set over ToolDef rows — no per-tool branches beyond the data flags.

local Types = require(script.Parent.Parent.Types)
local DeathConfig = require(script.Parent.Parent.Config.Death)

export type Denial = "Sacrificed" | "Cooldown" | "NotLit" | "CannotRelight" | "NotEnoughWax" | "Dead"

local ToolRules = {}

function ToolRules.validate(state: Types.PlayerRunState, def: Types.ToolDef, now: number): (boolean, Denial?)
	if not state.alive or state.finished or state.snuffedAt ~= nil then
		return false, "Dead"
	end
	if state.modifiers.lostTools[def.id] then
		return false, "Sacrificed"
	end
	local nextUse = state.nextToolUse[def.id]
	if nextUse ~= nil and now < nextUse then
		return false, "Cooldown"
	end
	if def.togglesLit and not state.isLit then
		-- Relight after a voluntary snuff. World-snuffed players never get here (snuffedAt caught above).
		if not state.unlitByChoice then
			return false, "CannotRelight"
		end
		if now - state.litChangedAt < DeathConfig.selfRelightDelaySeconds then
			return false, "CannotRelight"
		end
		return true, nil
	end
	if def.requiresLit and not state.isLit then
		return false, "NotLit"
	end
	-- Strict `>`: a tool can never be the thing that burns you out. (Held upkeep can — that's the
	-- drain pipeline's business, not activation's.)
	if not def.held and def.waxCost > 0 and state.wax.current <= def.waxCost then
		return false, "NotEnoughWax"
	end
	return true, nil
end

-- Clamp a client-supplied aim point to the tool's throw range from the caster. Anti-exploit:
-- the client proposes, the server bounds.
function ToolRules.clampAim(origin: Vector3, aim: Vector3, castRange: number): Vector3
	local offset = aim - origin
	if offset.Magnitude <= castRange then
		return aim
	end
	return origin + offset.Unit * castRange
end

return ToolRules

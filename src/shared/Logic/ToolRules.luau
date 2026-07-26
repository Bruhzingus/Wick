--!strict
-- Pure: can this player use this tool right now, and what does using it mean?
-- One generic rule set over ToolDef rows — no per-tool branches beyond the data flags.

local Types = require(script.Parent.Parent.Types)
local DeathConfig = require(script.Parent.Parent.Config.Death)

export type Denial = "Sacrificed" | "Cooldown" | "NotLit" | "CannotRelight" | "NotEnoughWax" | "Dead"

local ToolRules = {}

-- Charge loot changes only payment. It never bypasses cooldown, lighting, sacrifice, or death.
function ToolRules.hasFreeActivation(state: Types.PlayerRunState, def: Types.ToolDef): boolean
	return not def.held and def.waxCost > 0 and (state.freeToolCharges[def.id] or 0) > 0
end

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
	if
		not def.held
		and def.waxCost > 0
		and not ToolRules.hasFreeActivation(state, def)
		and state.wax.current <= def.waxCost
	then
		return false, "NotEnoughWax"
	end
	return true, nil
end

-- Resolve the server-owned horizontal landing point. The client proposes only a direction/point:
-- vertical aim never grants range, and a cave obstruction can shorten the result by a configured
-- inset. Returning nil means there is not enough legal throw distance to place a decoy.
function ToolRules.throwHorizontalPoint(
	origin: Vector3,
	aim: Vector3,
	throwRange: number,
	obstructionDistance: number?,
	obstructionInset: number,
	minimumDistance: number
): Vector3?
	local offset = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	local requestedDistance = offset.Magnitude
	if requestedDistance <= 0 then
		return if minimumDistance <= 0 then origin else nil
	end

	local distance = math.min(requestedDistance, math.max(throwRange, 0))
	if obstructionDistance ~= nil then
		distance = math.min(distance, math.max(obstructionDistance - math.max(obstructionInset, 0), 0))
	end
	if distance < math.max(minimumDistance, 0) then
		return nil
	end
	return origin + offset.Unit * distance
end

-- Point along the server-validated parabolic throw. Segment raycasts between these points make
-- rolling ground traversable without letting the client place through walls or the cave roof.
function ToolRules.throwArcPoint(startPoint: Vector3, endPoint: Vector3, arcHeight: number, alpha: number): Vector3
	local t = math.clamp(alpha, 0, 1)
	local lift = 4 * math.max(arcHeight, 0) * t * (1 - t)
	return startPoint:Lerp(endPoint, t) + Vector3.yAxis * lift
end

-- Ground normals use the same learnable rule on every floor. A vertical normal is flat ground;
-- normals beyond the configured slope are rejected so the miniature candle never hangs sideways.
function ToolRules.decoySurfaceAllowed(normal: Vector3, maxSlopeDegrees: number): boolean
	if normal.Magnitude <= 0 then
		return false
	end
	local maximum = math.clamp(maxSlopeDegrees, 0, 90)
	return normal.Unit.Y >= math.cos(math.rad(maximum))
end

return ToolRules

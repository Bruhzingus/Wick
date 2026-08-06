--!strict
-- Pure Echo Lock rules shared by planning, runtime authority, and tests. The gate is deliberately
-- only an extra loop doorway: it never owns a room, reward, or required route.

local LampConfig = require(script.Parent.Parent.Config.LampNetwork)

local EchoGateRules = {}

local ECHO_NODE = "lamp.echo_lock"

-- A floor may roll an Echo Lock only when the whole track, its generation layer, the permanent node,
-- and the authored depth gate all agree. Unknown/absent ownership fails closed.
function EchoGateRules.canPlan(unlockedNodes: { [string]: boolean }, depth: number): boolean
	local echo = LampConfig.generation.echoLock
	return LampConfig.enabled
		and LampConfig.generation.enabled
		and unlockedNodes[ECHO_NODE] == true
		and depth >= echo.minDepth
end

-- Entry, objectives, and the Warden encounter remain ordinary readable routes. Both endpoints are
-- checked by the planner, so a gate can only join two ordinary cave rooms.
function EchoGateRules.roomIsEligible(
	roomIndex: number,
	entryRoomIndex: number,
	basinRoomIndex: number,
	brazierRoomIndex: number,
	wardenRoomIndex: number?
): boolean
	return roomIndex ~= entryRoomIndex
		and roomIndex ~= basinRoomIndex
		and roomIndex ~= brazierRoomIndex
		and roomIndex ~= wardenRoomIndex
end

-- A paid Signal Bell ring opens only a nearby lock on the same floor (the service owns the
-- same-floor lookup). Full 3D distance keeps vertically stacked floors from ever bleeding together.
function EchoGateRules.withinRingRange(ringPosition: Vector3, gatePosition: Vector3): boolean
	local radius = math.max(0, LampConfig.generation.echoLock.ringRadius)
	return radius > 0 and (ringPosition - gatePosition).Magnitude <= radius
end

return EchoGateRules

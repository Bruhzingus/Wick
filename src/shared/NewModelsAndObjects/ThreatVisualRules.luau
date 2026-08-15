--!strict
-- Pure presentation-state transitions shared by the client creature adapter and its regression tests.

local ThreatVisualRules = {}

-- A VoidFly may begin clinging to the ceiling, but once it launches it stays airborne for the rest
-- of its patrol. The replicated `moving` flag can briefly fall false when the server reaches one
-- moving circuit target before receiving the next; treating that single frame as a landing repeatedly
-- reverses the body's 180-degree cling transition and makes it backflip against the roof.
function ThreatVisualRules.ceilingFlyAirborne(wasAirborne: boolean, mode: string, moving: boolean): boolean
	return wasAirborne or mode ~= "Wander" or moving
end

return table.freeze(ThreatVisualRules)

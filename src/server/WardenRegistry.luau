--!strict
-- Registry of live Stone Wardens, keyed by the floor they patrol. It exists so environmental
-- hazards can act on the golem without depending on StoneWardenSystem (which owns pathing, models,
-- and the relic), and without the golem depending on any hazard service. Entries are plain
-- callbacks: the registry never touches a model itself.

local WardenRegistry = {}

export type Warden = {
	depth: number,
	-- World position of the golem right now, or nil once its model is gone.
	position: () -> Vector3?,
	-- Root it in place (and disarm its kill contact) for at least this many seconds.
	stun: (seconds: number) -> (),
}

local wardens: { Warden } = {}

function WardenRegistry.register(warden: Warden): Warden
	table.insert(wardens, warden)
	return warden
end

function WardenRegistry.unregister(warden: Warden)
	local index = table.find(wardens, warden)
	if index ~= nil then
		table.remove(wardens, index)
	end
end

-- Live wardens on one floor whose model still exists. Positions are resolved here so callers
-- never have to defend against a warden torn down mid-iteration.
function WardenRegistry.positionsAtDepth(depth: number): { { warden: Warden, position: Vector3 } }
	local result: { { warden: Warden, position: Vector3 } } = {}
	for _, warden in wardens do
		if warden.depth ~= depth then
			continue
		end
		local position = warden.position()
		if position ~= nil then
			table.insert(result, { warden = warden, position = position })
		end
	end
	return result
end

function WardenRegistry.reset()
	table.clear(wardens)
end

return WardenRegistry

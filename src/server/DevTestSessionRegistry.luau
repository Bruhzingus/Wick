--!strict
-- Server-only authority for candles currently inside the developer enemy lab. Gameplay systems
-- consult this tiny registry instead of trusting a replicated attribute or carrying a developer
-- flag in durable run state.

local DevTestSessionRegistry = {}

local protected: { [number]: boolean } = {}

function DevTestSessionRegistry.protect(playerId: number)
	protected[playerId] = true
end

function DevTestSessionRegistry.release(playerId: number)
	protected[playerId] = nil
end

function DevTestSessionRegistry.isProtected(playerId: number): boolean
	return protected[playerId] == true
end

function DevTestSessionRegistry.clear()
	table.clear(protected)
end

return DevTestSessionRegistry

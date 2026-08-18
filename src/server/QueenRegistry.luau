--!strict
-- Registry of live Grub Queens, keyed by the floor they occupy. Mirrors WardenRegistry.luau
-- exactly: it exists so DynamiteService can apply a detonation to her without depending on
-- whatever module ends up owning her model, pathing and brood. Entries are plain callbacks; the
-- registry never touches a model itself.
--
-- ONE ENTRY PER FLOOR IN PRACTICE, but keyed the same way WardenRegistry is (a plain list filtered
-- by depth) rather than a `[depth] -> Queen` map, so nothing here has to assume there is ever
-- exactly one.

local QueenRegistry = {}

export type Queen = {
	depth: number,
	-- World position of the Queen right now, or nil once her model is gone.
	position: () -> Vector3?,
	-- One detonation's worth of charge (Config.GrubQueen.dynamiteDamage, always 1 today — see
	-- Config/GrubQueen.luau for why this is a flat count and not distance-scaled damage).
	-- Accumulates; returns true only if this was the charge that finished her.
	applyDynamite: (charges: number) -> boolean,
}

local queens: { Queen } = {}

function QueenRegistry.register(queen: Queen): Queen
	table.insert(queens, queen)
	return queen
end

function QueenRegistry.unregister(queen: Queen)
	local index = table.find(queens, queen)
	if index ~= nil then
		table.remove(queens, index)
	end
end

-- Live queens on one floor whose model still exists. Positions are resolved here so callers never
-- have to defend against a queen torn down mid-iteration.
function QueenRegistry.positionsAtDepth(depth: number): { { queen: Queen, position: Vector3 } }
	local result: { { queen: Queen, position: Vector3 } } = {}
	for _, queen in queens do
		if queen.depth ~= depth then
			continue
		end
		local position = queen.position()
		if position ~= nil then
			table.insert(result, { queen = queen, position = position })
		end
	end
	return result
end

-- Whether a live Queen still occupies this floor. RunOrchestrator's descent guard reads this to
-- refuse the ladder while she is alive (Config.GrubQueen.requiresKillToDescend).
function QueenRegistry.aliveAtDepth(depth: number): boolean
	return #QueenRegistry.positionsAtDepth(depth) > 0
end

function QueenRegistry.clearDepth(depth: number)
	for index = #queens, 1, -1 do
		if queens[index].depth == depth then
			table.remove(queens, index)
		end
	end
end

function QueenRegistry.reset()
	table.clear(queens)
end

return QueenRegistry

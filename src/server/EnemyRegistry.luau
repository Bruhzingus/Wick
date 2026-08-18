--!strict
-- Registry of live wick-pack enemies (shared/Enemies), keyed by the floor they are on. Mirrors
-- WardenRegistry.luau exactly, and exists for the same one reason: so DynamiteService can damage a
-- creature without depending on whatever module owns its model, pathing and state machine.
--
-- WHY THESE NEED A REGISTRY AT ALL, when the original six do not. The existing roster lives inside
-- ThreatService, so `ThreatService.applyBlast` can walk its own instance list and settle the whole
-- thing internally. The pack's four are bespoke bodies (owner decision: StoneWarden-style behaviour
-- modules rather than Config/Threats rows), so nothing in the blast path can see them. Without this
-- they would be silently, permanently immune to the one thing that kills everything else in the cave
-- — which reads as a bug rather than as a rule, especially to a player who has already learned that
-- one stick removes a crawler.
--
-- THE GRUB QUEEN IS NOT IN HERE. She takes a flat count of charges rather than distance-scaled
-- damage (Config/GrubQueen explains why), so she keeps her own registry with its own verb —
-- server/QueenRegistry.luau. Two registries rather than one union type, because the two are answering
-- genuinely different questions and a shared `blast` that meant something different depending on the
-- body would be the more confusing shape.

local EnemyRegistry = {}

-- What a registered body is, for the blast path only. Deliberately NOT "everything about an enemy":
-- nothing here can move one, target one, or ask what it is doing. Callers that need those talk to the
-- owning service.
export type Enemy = {
	depth: number,
	-- World position right now, or nil once the model is gone.
	position: () -> Vector3?,
	-- Blast damage in "sticks at point blank" (Logic/DynamiteRules.blastDamage), the same currency
	-- WardenRegistry uses. Accumulates against this creature's own Config `blast.hitPoints`.
	-- Returns true only if this was the blast that finished it.
	blast: (damage: number) -> boolean,
}

local enemies: { Enemy } = {}

function EnemyRegistry.register(enemy: Enemy): Enemy
	table.insert(enemies, enemy)
	return enemy
end

function EnemyRegistry.unregister(enemy: Enemy)
	local index = table.find(enemies, enemy)
	if index ~= nil then
		table.remove(enemies, index)
	end
end

-- Live enemies on one floor whose body still exists. Positions are resolved here so callers never
-- have to defend against a body torn down mid-iteration.
function EnemyRegistry.positionsAtDepth(depth: number): { { enemy: Enemy, position: Vector3 } }
	local result: { { enemy: Enemy, position: Vector3 } } = {}
	for _, enemy in enemies do
		if enemy.depth ~= depth then
			continue
		end
		local position = enemy.position()
		if position ~= nil then
			table.insert(result, { enemy = enemy, position = position })
		end
	end
	return result
end

function EnemyRegistry.countAtDepth(depth: number): number
	local count = 0
	for _, enemy in enemies do
		if enemy.depth == depth then
			count += 1
		end
	end
	return count
end

function EnemyRegistry.clearDepth(depth: number)
	for index = #enemies, 1, -1 do
		if enemies[index].depth == depth then
			table.remove(enemies, index)
		end
	end
end

function EnemyRegistry.reset()
	table.clear(enemies)
end

return EnemyRegistry

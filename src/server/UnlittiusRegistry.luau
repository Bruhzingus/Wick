--!strict
-- Registry of live Unlittius bodies, keyed by the floor they occupy. Mirrors `QueenRegistry` exactly,
-- and exists for the same reason: two systems need to reach the boss without owning him.
--
--   * `UnlittiusEncounterService` lights a candle and has to tell whoever is floating over the dais.
--   * `RunOrchestrator`'s descent guard has to know whether the way down is still refused
--     (Config/Unlittius.encounter.requiresBanishToDescend), and must not hold a reference to an
--     encounter to find out.
--
-- Entries are plain callbacks; the registry never touches a model. Kept as a filtered list rather
-- than a `[depth] -> boss` map for the same reason the Queen's is: nothing here should assume there
-- is only ever one, and the developer laboratory is exactly the place that assumption breaks.

local UnlittiusRegistry = {}

export type Boss = {
	depth: number,
	-- Where he is right now, or nil once his model is gone.
	position: () -> Vector3?,
	-- A candle just caught. The count is the AUTHORITATIVE total, not an increment, so a recoil that
	-- arrives out of order can never make him brighter than he was.
	candleLit: (candlesLit: number) -> (),
	-- The eighth candle. Starts the banish; safe to call twice.
	banish: () -> (),
	-- Whether the banish has finished. The descent gate reads this.
	banished: () -> boolean,
}

-- One shrine candle, as far as anything outside the encounter needs to know: where it is and whether
-- it is burning.
--
-- THE CANDLES ARE IN HERE FOR A STRUCTURAL REASON, not a tidiness one. `server/LightSources` has to
-- read them every tick so a lit chamber is real light — and it cannot require the encounter service to
-- ask, because that service reaches `EnemyService` and from there the boss's brain and
-- `ThreatService`, which requires `LightSources` right back. This registry depends on nothing, which
-- is what makes it the only safe place for that edge to live.
export type Candle = {
	depth: number,
	position: Vector3,
	lit: () -> boolean,
}

local bosses: { Boss } = {}
local candles: { Candle } = {}

function UnlittiusRegistry.register(boss: Boss): Boss
	table.insert(bosses, boss)
	return boss
end

function UnlittiusRegistry.unregister(boss: Boss)
	local index = table.find(bosses, boss)
	if index ~= nil then
		table.remove(bosses, index)
	end
end

function UnlittiusRegistry.atDepth(depth: number): { Boss }
	local found: { Boss } = {}
	for _, boss in bosses do
		if boss.depth == depth and boss.position() ~= nil then
			table.insert(found, boss)
		end
	end
	return found
end

-- Whether an unbanished Unlittius still holds this floor. The ladder refuses a rider while this is
-- true, which is the same narrow exception the Grub Queen makes (DESIGN §9a/§9b) and is bounded the
-- same way: one config flag on one authored encounter.
function UnlittiusRegistry.activeAtDepth(depth: number): boolean
	for _, boss in UnlittiusRegistry.atDepth(depth) do
		if not boss.banished() then
			return true
		end
	end
	return false
end

function UnlittiusRegistry.registerCandle(candle: Candle): Candle
	table.insert(candles, candle)
	return candle
end

-- Where every BURNING shrine candle in the world is. Read once per tick by `server/LightSources`,
-- which turns each one into a light-field source through `Logic/UnlittiusRules.candleLightSource`.
--
-- Deliberately unfiltered by floor, exactly as the wall lamps are: every consumer of the light field
-- already judges by distance, so a candle two floors up contributes nothing here without anybody
-- having to remember to exclude it.
function UnlittiusRegistry.litCandlePositions(): { Vector3 }
	local found: { Vector3 } = {}
	for _, candle in candles do
		if candle.lit() then
			table.insert(found, candle.position)
		end
	end
	return found
end

function UnlittiusRegistry.clearDepth(depth: number)
	for index = #bosses, 1, -1 do
		if bosses[index].depth == depth then
			table.remove(bosses, index)
		end
	end
	for index = #candles, 1, -1 do
		if candles[index].depth == depth then
			table.remove(candles, index)
		end
	end
end

function UnlittiusRegistry.reset()
	table.clear(bosses)
	table.clear(candles)
end

return UnlittiusRegistry

--!strict
-- Pure: where a dead candle may lie, and how the tableau is laid out around it.
--
-- Logic/FloorPlanner owns the roll and the placement search; this owns the two questions that decide
-- whether the encounter is FAIR, and it owns them alone so both can be tested cold:
--
--   1. WHICH ROOM MAY HOLD IT. Not the entry, Basin, Brazier, or the Warden's den — the encounter
--      must never sit on a room a party is required to use — and only a room whose ceiling is low
--      enough for the creature it comes with. A dead candle under a 40-stud vault would spawn three
--      flies too high to hear, see, or reach, which is a reward with no encounter attached.
--   2. WHERE THE PIECES GO. Two concentric rings around the corpse, rotated against each other so no
--      pickup starts directly beneath a fly's anchor. The rings are what make this a position problem:
--      the loot is inside the flies' territories by construction, and the player chooses which of the
--      three to take and from which side.
--
-- Nothing here knows about Instances, and nothing here rolls anything: every function is a function
-- of the plan data it is given, which is what lets the planner stay deterministic per seed.

local Types = require(script.Parent.Parent.Types)
local DeadCandleConfig = require(script.Parent.Parent.Config.DeadCandle)
local ThreatsConfig = require(script.Parent.Parent.Config.Threats)
local ThreatRules = require(script.Parent.ThreatRules)

local DeadCandleRules = {}

-- Whether this floor is deep enough to hold the encounter at all. The roll itself belongs to the
-- planner's seeded stream; this only answers the depth gate, so a test can ask the question without
-- owning a Random.
function DeadCandleRules.depthAllows(globalDepth: number): boolean
	return DeadCandleConfig.enabled and globalDepth >= DeadCandleConfig.minGlobalDepth
end

-- The tallest ceiling the encounter's own creature can hold. Read from the roster rather than
-- authored a second time in Config/DeadCandle: if the VoidFly's roof profile ever changes, the rooms
-- this encounter is allowed into change with it instead of drifting apart from it.
function DeadCandleRules.maximumCeilingHeight(): number
	local def = ThreatsConfig.definitions[DeadCandleConfig.threatId]
	local roof = if def ~= nil then ThreatRules.roofProfile(def) else nil
	return if roof ~= nil then roof.maximumCeilingHeight else 0
end

-- Whether one room can hold the tableau. `protectedIndices` is the planner's own set of rooms the
-- floor requires (entry, Basin, Brazier, and the Warden's den when there is one).
function DeadCandleRules.roomIsEligible(
	room: Types.RoomPlacement,
	roomIndex: number,
	protectedIndices: { [number]: boolean },
	moduleDef: Types.RoomModuleDef?
): boolean
	if protectedIndices[roomIndex] then
		return false
	end
	if room.ceilingHeight > DeadCandleRules.maximumCeilingHeight() then
		return false
	end
	-- The room module has to be one the creature is allowed in anyway. The encounter adds bodies to a
	-- floor through the ordinary spawn list, so it must never put a row somewhere the allow-list for
	-- that room already refused.
	if moduleDef == nil then
		return false
	end
	for _, threatId in moduleDef.allowedThreats do
		if threatId == DeadCandleConfig.threatId then
			return true
		end
	end
	return false
end

-- One ring of `count` evenly spaced room-local offsets around `center`, starting at `startDegrees`.
-- Shared by both rings so the loot and the flies cannot drift out of agreement.
function DeadCandleRules.ring(center: Vector3, count: number, radius: number, startDegrees: number): { Vector3 }
	local offsets: { Vector3 } = {}
	local total = math.max(0, math.floor(count))
	if total == 0 then
		return offsets
	end
	local start = math.rad(startDegrees)
	for index = 0, total - 1 do
		local angle = start + index * (2 * math.pi / total)
		table.insert(offsets, center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	return offsets
end

-- The whole tableau, laid out around a corpse that the planner has already found room for.
export type Layout = {
	loot: { Vector3 },
	flies: { Vector3 },
}

function DeadCandleRules.layout(corpseOffset: Vector3): Layout
	local layout = DeadCandleConfig.layout
	return {
		loot = DeadCandleRules.ring(corpseOffset, DeadCandleConfig.lootCount, layout.lootRingRadius, 0),
		flies = DeadCandleRules.ring(
			corpseOffset,
			DeadCandleConfig.flyCount,
			layout.flyRingRadius,
			layout.flyRingOffsetDegrees
		),
	}
end

return DeadCandleRules

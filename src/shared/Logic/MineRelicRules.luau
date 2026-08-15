--!strict
-- WHICH ABANDONED WORKINGS A FLOOR GETS, as pure functions. No Instances, no rng ownership: the
-- builder hands in a depth and gets back an ordered draw list, and hands in its own seeded rng for
-- the two rolls that are genuinely random.
--
-- THE ONE IDEA WORTH READING. The catalog is WALKED, not re-rolled. A weighted roll per placement
-- is the obvious implementation and it is the wrong one here, because independent rolls happily
-- hand a player the same rusted cart on three floors in a row — which is the exact complaint that
-- "make them rare" is trying to avoid, and rarity alone does not fix it. So the eligible catalog is
-- shuffled once (deterministically, from `orderSeed`) and consecutive floors take consecutive
-- entries from that order. Each piece then appears at most once per full cycle of the catalog, and
-- never twice running, whatever the floor rolls do.
--
-- WEIGHT STILL MEANS SOMETHING. It biases the shuffle rather than the draw: a heavier piece lands
-- earlier in the order more often, so it comes round sooner within a cycle. It can never appear
-- twice in a cycle, which is the property the walk exists to guarantee.

local MineRelicsConfig = require(script.Parent.Parent.Config.MineRelics)

local MineRelicRules = {}

export type RelicDef = MineRelicsConfig.RelicDef

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function MineRelicRules.definitionById(id: string?): RelicDef?
	if typeof(id) ~= "string" then
		return nil
	end
	for _, def in MineRelicsConfig.catalog do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Every piece that may appear at this depth, in authored catalog order.
function MineRelicRules.eligible(globalDepth: number): { RelicDef }
	local result: { RelicDef } = {}
	if not isFiniteNumber(globalDepth) then
		return result
	end
	for _, def in MineRelicsConfig.catalog do
		if globalDepth >= def.minDepth and def.weight > 0 then
			table.insert(result, def)
		end
	end
	return result
end

-- Whether this depth may carry workings at all. Separate from the floor roll so a caller can skip
-- the whole pass — including the rng draw — without pretending to roll something it would discard.
function MineRelicRules.isAvailable(globalDepth: number): boolean
	if not MineRelicsConfig.enabled or not isFiniteNumber(globalDepth) then
		return false
	end
	if globalDepth < MineRelicsConfig.placement.minDepth then
		return false
	end
	return #MineRelicRules.eligible(globalDepth) > 0
end

-- THE ONE FIXED CYCLE every floor's draw is a slice of. Built once from the WHOLE catalog — not from
-- a depth's eligible subset — and memoized, so it is the same permutation at depth 1 and at depth 40.
--
-- SHUFFLING THE ELIGIBLE SUBSET INSTEAD IS THE BUG THIS AVOIDS, and it is not obvious. The eligible
-- set grows as a run gets deeper (a powder keg only appears from floor 4), so a per-depth shuffle
-- produces a DIFFERENT permutation of a DIFFERENT-length list either side of every unlock — and two
-- unrelated permutations can perfectly well put the same piece on both floors. The anti-repeat
-- guarantee would then quietly hold everywhere except at exactly the depths where new content
-- arrives, which is the worst place to lose it and the least likely place to notice.
--
-- A weighted Fisher-Yates: each remaining entry's draw chance is its weight, so heavy pieces settle
-- toward the front of the cycle and come round sooner. Weight biases the ORDER; it can never make a
-- piece appear twice in one cycle.
local cachedCycle: { RelicDef }? = nil

local function catalogCycle(): { RelicDef }
	local existing = cachedCycle
	if existing ~= nil then
		return existing
	end
	local pool = table.clone(MineRelicsConfig.catalog)
	local order: { RelicDef } = {}
	local rng = Random.new(MineRelicsConfig.placement.orderSeed)
	while #pool > 0 do
		local total = 0
		for _, def in pool do
			total += math.max(def.weight, 0)
		end
		local index = #pool
		if total > 0 then
			local roll = rng:NextNumber(0, total)
			for candidate, def in pool do
				roll -= math.max(def.weight, 0)
				if roll <= 0 then
					index = candidate
					break
				end
			end
		end
		table.insert(order, pool[index])
		table.remove(pool, index)
	end
	cachedCycle = order
	return order
end

-- THE FLOOR'S DRAW LIST: up to `maxPerFloor` pieces, in the order the builder should try to place
-- them, with no repeats inside the floor and none carried over from the floor above.
--
-- Depth d takes cycle positions (d-1)*perFloor .. (d-1)*perFloor + perFloor - 1, so depth d and
-- depth d+1 together occupy 2 x perFloor CONSECUTIVE positions in one fixed cycle — distinct by
-- construction, which is why the validator requires the catalog to be at least twice a floor's cap.
--
-- A DRAWN PIECE THAT IS NOT YET ELIGIBLE IS DROPPED, NOT REPLACED. Substituting the next eligible
-- entry would slide the cycle and break the guarantee above; dropping it simply means a shallow floor
-- places fewer pieces than a deep one, which is the right answer anyway — the workings should get
-- richer as a party goes further than anybody sensible went.
function MineRelicRules.floorDraw(globalDepth: number): { RelicDef }
	if not MineRelicRules.isAvailable(globalDepth) then
		return {}
	end
	local cycle = catalogCycle()
	local count = #cycle
	local perFloor = math.max(0, math.floor(MineRelicsConfig.placement.maxPerFloor))
	local draw: { RelicDef } = {}
	for slot = 0, math.min(perFloor, count) - 1 do
		local step = (math.floor(globalDepth) - 1) * perFloor + slot
		local def = cycle[step % count + 1]
		if globalDepth >= def.minDepth and def.weight > 0 then
			table.insert(draw, def)
		end
	end
	return draw
end

-- Does this floor have any workings on it? One roll, taken before any room is looked at, so most
-- descents pass through rock nobody ever worked.
function MineRelicRules.rollFloorHasWorkings(rng: Random): boolean
	return rng:NextNumber() < MineRelicsConfig.placement.floorChance
end

function MineRelicRules.rollRoomAttempt(rng: Random): boolean
	return rng:NextNumber() < MineRelicsConfig.placement.roomChance
end

-- A relic never squeezes itself into a room it does not fit: it is dressing, and dressing that has
-- to be compromised to exist is worse than dressing that is not there.
function MineRelicRules.fitsRoom(def: RelicDef, ceilingHeight: number): boolean
	return isFiniteNumber(ceilingHeight) and ceilingHeight >= def.minCeilingHeight
end

-- The ring band, in studs, this piece's placement sweep samples. Wall pieces start further out
-- because they are then walked outward to the rock face anyway.
function MineRelicRules.ringBand(def: RelicDef, cellSize: number): (number, number)
	local placement = MineRelicsConfig.placement
	if def.anchoring == "Wall" then
		return cellSize * placement.wallRingMinFactor, cellSize * placement.wallRingMaxFactor
	end
	return cellSize * placement.openRingMinFactor, cellSize * placement.openRingMaxFactor
end

export type ValidationIssue = { relicId: string, field: string, message: string }

-- Properties a catalog row may never violate. Returned rather than raised, on the same reasoning as
-- CaveFamilyRules.validate: a bad row should be a failing test, not a server that will not boot.
function MineRelicRules.validate(): (boolean, { ValidationIssue })
	local issues: { ValidationIssue } = {}
	local function fail(relicId: string, field: string, message: string)
		table.insert(issues, { relicId = relicId, field = field, message = message })
	end

	local placement = MineRelicsConfig.placement
	if placement.maxPerFloor < 1 or placement.maxPerFloor % 1 ~= 0 then
		fail("placement", "maxPerFloor", "must be a whole number at or above 1")
	end
	-- THE WALK'S ONE STRUCTURAL REQUIREMENT. Two consecutive floors occupy 2 x maxPerFloor consecutive
	-- positions in the cycle, so a catalog shorter than that wraps inside a single pair of floors and
	-- the anti-repeat property this module exists for silently stops holding.
	if #MineRelicsConfig.catalog < placement.maxPerFloor * 2 then
		fail("placement", "catalog", "the catalog must hold at least twice what one floor may place")
	end
	if placement.floorChance < 0 or placement.floorChance > 1 then
		fail("placement", "floorChance", "must be within [0, 1]")
	end
	if placement.roomChance < 0 or placement.roomChance > 1 then
		fail("placement", "roomChance", "must be within [0, 1]")
	end
	if placement.placementBearings < 1 or placement.placementBearings % 1 ~= 0 then
		fail("placement", "placementBearings", "must be a whole number at or above 1")
	end
	if placement.placementRadiiPerBearing < 1 or placement.placementRadiiPerBearing % 1 ~= 0 then
		fail("placement", "placementRadiiPerBearing", "must be a whole number at or above 1")
	end
	if placement.openRingMaxFactor < placement.openRingMinFactor then
		fail("placement", "openRingFactor", "max must not be below min")
	end
	if placement.wallRingMaxFactor < placement.wallRingMinFactor then
		fail("placement", "wallRingFactor", "max must not be below min")
	end

	local seen: { [string]: boolean } = {}
	for _, def in MineRelicsConfig.catalog do
		if seen[def.id] then
			fail(def.id, "id", "duplicate relic id")
		end
		seen[def.id] = true
		if def.weight <= 0 or not isFiniteNumber(def.weight) then
			fail(def.id, "weight", "must be finite and above zero")
		end
		if def.minDepth < 1 or def.minDepth % 1 ~= 0 then
			fail(def.id, "minDepth", "must be a whole depth at or above 1")
		end
		if def.footprintRadius <= 0 or not isFiniteNumber(def.footprintRadius) then
			fail(def.id, "footprintRadius", "must be finite and above zero")
		end
		if not isFiniteNumber(def.minCeilingHeight) or def.minCeilingHeight <= 0 then
			fail(def.id, "minCeilingHeight", "must be finite and above zero")
		end
		if def.anchoring ~= "Open" and def.anchoring ~= "Wall" then
			fail(def.id, "anchoring", "must be Open or Wall")
		end
		if not isFiniteNumber(def.wallOffset) or def.wallOffset < 0 then
			fail(def.id, "wallOffset", "must be finite and non-negative")
		elseif def.anchoring == "Wall" and def.wallOffset <= 0 then
			-- A wall piece with no stand-off is a wall piece built inside the rock it leans on.
			fail(def.id, "wallOffset", "a wall piece must declare how far its geometry reaches back")
		end
	end

	-- Every floor must be able to place something at the shallowest depth workings appear at,
	-- otherwise the whole system is authored out of existence by a minDepth nobody meant.
	if MineRelicsConfig.enabled and #MineRelicRules.eligible(placement.minDepth) == 0 then
		fail("placement", "minDepth", "no catalog row is eligible at the shallowest working depth")
	end

	return #issues == 0, issues
end

return MineRelicRules

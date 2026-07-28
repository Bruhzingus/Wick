--!strict
-- PHASE 8, pure: THE authoritative run cargo model. Every mutation of anyone's Raw Wax goes through
-- one of these five verbs, and the fact that there are only five is the design:
--
--   grant  — a depleted seam adds units stamped with the depth they came out of
--   clear  — the whole bag leaves at once (extraction, or a loss that keeps nothing)
--   split  — a bag is divided into a recoverable part and a destroyed part (terminal death)
--   merge  — a dropped pile is absorbed into a living player's bag (recovery)
--   take   — a pile is claimed whole, leaving nothing behind
--
-- WHAT IS DELIBERATELY ABSENT, and must stay absent: there is no `transfer`, no `spend`, and no
-- `toWax`. Cargo cannot move directly from one living player to another — the only path between two
-- players' bags runs through a pile in the world, which is a physical object with a single claim, and
-- that is what makes duplication structurally impossible rather than merely checked for. Cargo also
-- cannot become wax: wax keeps you alive, Raw Wax makes you money, and a conversion between them
-- would collapse the one tension the whole game is built on. `CargoRulesTests` asserts the exact
-- public surface, so adding a sixth verb fails the suite rather than quietly shipping a new economy.
--
-- EVERY AMOUNT IS A NON-NEGATIVE INTEGER, at every step, for every input. Non-finite, negative,
-- fractional and out-of-range values are REFUSED (they do nothing) rather than clamped into
-- something plausible: a bag repaired into a legal-looking state is a bag nobody can audit.
--
-- CONSERVATION IS THE INVARIANT THAT MATTERS. `split` and `merge` both provably preserve the total
-- unit count — what leaves one side arrives on the other, exactly, with no rounding leak in either
-- direction. That is asserted directly in the tests, because a leak in either direction is the same
-- class of bug: currency appearing from nowhere, or a player's run silently evaporating.

local Types = require(script.Parent.Parent.Types)
local ExtractionConfig = require(script.Parent.Parent.Config.Extraction)
local DepthRules = require(script.Parent.DepthRules)

local CargoRules = {}

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isPositiveInteger(value: number): boolean
	return isFiniteNumber(value) and value > 0 and value % 1 == 0
end

function CargoRules.newCargo(): Types.RawWaxCargo
	return { stacks = {}, total = 0 }
end

-- What one broken seam is worth, validated rather than trusted: a mistyped config value yields zero
-- units instead of a fractional or infinite grant.
function CargoRules.unitsPerDeposit(): number
	local units = ExtractionConfig.unitsPerDeposit
	return if isPositiveInteger(units) then units else 0
end

function CargoRules.maxCargoUnits(): number
	local cap = ExtractionConfig.maxCargoUnits
	return if isPositiveInteger(cap) then cap else 0
end

local function copyStacks(stacks: { Types.RawWaxStack }): { Types.RawWaxStack }
	local copy: { Types.RawWaxStack } = table.create(#stacks)
	for index, stack in stacks do
		copy[index] = { originDepth = stack.originDepth, units = stack.units }
	end
	return copy
end

-- Canonical ordering: ascending by origin depth, at most one stack per depth. Every constructor here
-- ends by restoring it, so two bags holding the same units are always the same table shape — which
-- is what lets tests compare them and lets `formatOrigins` be deterministic.
local function sortStacks(stacks: { Types.RawWaxStack })
	table.sort(stacks, function(a, b)
		return a.originDepth < b.originDepth
	end)
end

-- Add units mined at `originDepth`. Returns the NEW cargo and how many units were actually added,
-- which is fewer than requested at the cap and zero for any invalid input. Units from one depth merge
-- into a single stack, so a long expedition cannot grow an unbounded list of one-unit rows.
function CargoRules.grant(cargo: Types.RawWaxCargo, originDepth: number, units: number): (Types.RawWaxCargo, number)
	-- The origin depth is a real supported depth or the grant does not happen. This is the one field
	-- the payout curve prices, so a garbage depth must never enter a bag.
	if not DepthRules.isSupportedDepth(originDepth) then
		return cargo, 0
	end
	if not isPositiveInteger(units) then
		return cargo, 0
	end

	local room = CargoRules.maxCargoUnits() - cargo.total
	local added = math.min(units, math.max(0, room))
	if added <= 0 then
		return cargo, 0
	end

	local stacks = copyStacks(cargo.stacks)
	for _, stack in stacks do
		if stack.originDepth == originDepth then
			stack.units += added
			return { stacks = stacks, total = cargo.total + added }, added
		end
	end
	table.insert(stacks, { originDepth = originDepth, units = added })
	sortStacks(stacks)
	return { stacks = stacks, total = cargo.total + added }, added
end

-- Remove everything. Returns the new empty cargo and how many units left, so the caller can attribute
-- them (extracted, shattered, destroyed) without re-reading what it just emptied.
function CargoRules.clear(cargo: Types.RawWaxCargo): (Types.RawWaxCargo, number)
	return CargoRules.newCargo(), cargo.total
end

-- SPLIT: divide a bag into the part that survives and the part that does not. Used by terminal death,
-- where half of what you were carrying lands on your remains and half shatters.
--
-- Returns (taken, remainder) where `taken` is `permille` of the total, rounded DOWN, and `remainder`
-- is exactly everything else. `taken.total + remainder.total == cargo.total` always — the split
-- cannot create or destroy a unit.
--
-- THE DISTRIBUTION IS PROPORTIONAL ACROSS DEPTHS, by largest-remainder apportionment rather than by
-- taking from the deepest stacks first. This matters more than it looks: taking deepest-first would
-- mean the recoverable half is always the valuable half, so dying with a mixed bag would cost the
-- party almost nothing in currency terms. Proportional means half the units AND roughly half the
-- value, which is what "half" is supposed to mean. Ties break on origin depth, so the result is fully
-- deterministic and two servers splitting the same bag always agree.
function CargoRules.split(cargo: Types.RawWaxCargo, permille: number): (Types.RawWaxCargo, Types.RawWaxCargo)
	local total = cargo.total
	if total <= 0 or #cargo.stacks == 0 then
		return CargoRules.newCargo(), CargoRules.newCargo()
	end
	local safePermille = if isFiniteNumber(permille) then math.clamp(math.floor(permille), 0, 1000) else 0
	local target = math.floor(total * safePermille / 1000)
	if target <= 0 then
		return CargoRules.newCargo(), { stacks = copyStacks(cargo.stacks), total = total }
	end
	if target >= total then
		return { stacks = copyStacks(cargo.stacks), total = total }, CargoRules.newCargo()
	end

	-- Exact integer apportionment: each stack's floor share, then the leftover handed out one unit at
	-- a time to whichever stacks were rounded down hardest.
	type Share = { originDepth: number, units: number, base: number, remainder: number }
	local shares: { Share } = table.create(#cargo.stacks)
	local assigned = 0
	for _, stack in cargo.stacks do
		local numerator = stack.units * target
		local base = math.floor(numerator / total)
		table.insert(shares, {
			originDepth = stack.originDepth,
			units = stack.units,
			base = base,
			remainder = numerator - base * total,
		})
		assigned += base
	end

	local leftover = target - assigned
	if leftover > 0 then
		local order = table.clone(shares)
		table.sort(order, function(a, b)
			if a.remainder ~= b.remainder then
				return a.remainder > b.remainder
			end
			return a.originDepth < b.originDepth
		end)
		for index = 1, math.min(leftover, #order) do
			order[index].base += 1
		end
	end

	local takenStacks: { Types.RawWaxStack } = {}
	local remainderStacks: { Types.RawWaxStack } = {}
	local takenTotal = 0
	local remainderTotal = 0
	for _, share in shares do
		if share.base > 0 then
			table.insert(takenStacks, { originDepth = share.originDepth, units = share.base })
			takenTotal += share.base
		end
		local left = share.units - share.base
		if left > 0 then
			table.insert(remainderStacks, { originDepth = share.originDepth, units = left })
			remainderTotal += left
		end
	end
	sortStacks(takenStacks)
	sortStacks(remainderStacks)
	return { stacks = takenStacks, total = takenTotal }, { stacks = remainderStacks, total = remainderTotal }
end

-- MERGE: absorb `incoming` into `cargo`, respecting the carry cap. Returns the combined bag, whatever
-- would not fit (so a pile is only partly consumed rather than silently evaporating), and how many
-- units actually moved.
--
-- The leftover return is the whole reason this is not a one-liner: a player at their cap who walks
-- over a pile must leave the rest ON THE GROUND for someone else, not delete it. Units moved plus
-- units left over always equals what was offered.
function CargoRules.merge(
	cargo: Types.RawWaxCargo,
	incoming: Types.RawWaxCargo
): (Types.RawWaxCargo, Types.RawWaxCargo, number)
	if incoming.total <= 0 then
		return cargo, CargoRules.newCargo(), 0
	end
	local result = cargo
	local leftover = CargoRules.newCargo()
	local moved = 0
	-- Deepest first: if only part of a pile fits, the part that fits should be the part worth having.
	-- This is a genuine gift to the finder, and unlike the death split it cannot be gamed — you do not
	-- choose your own cap, and taking the valuable units first leaves the cheap ones for the next
	-- person rather than destroying them.
	local ordered = copyStacks(incoming.stacks)
	table.sort(ordered, function(a, b)
		return a.originDepth > b.originDepth
	end)
	for _, stack in ordered do
		local updated, added = CargoRules.grant(result, stack.originDepth, stack.units)
		result = updated
		moved += added
		local unmoved = stack.units - added
		if unmoved > 0 then
			leftover = (CargoRules.grant(leftover, stack.originDepth, unmoved))
		end
	end
	return result, leftover, moved
end

-- TAKE: claim a pile whole. A named verb rather than an inline `clear` at each call site, so that
-- "this pile was claimed" and "this bag was destroyed" are never the same line of code even though
-- they leave the same empty table behind.
function CargoRules.take(pile: Types.RawWaxCargo): (Types.RawWaxCargo, Types.RawWaxCargo)
	return { stacks = copyStacks(pile.stacks), total = pile.total }, CargoRules.newCargo()
end

-- Deterministic "4x6,7x3" origin-depth distribution, for telemetry and the results line. Sorted by
-- depth, so two runs carrying the same units always produce the same string.
function CargoRules.formatOrigins(cargo: Types.RawWaxCargo): string
	if #cargo.stacks == 0 then
		return "none"
	end
	local parts: { string } = table.create(#cargo.stacks)
	for index, stack in cargo.stacks do
		parts[index] = string.format("%dx%d", stack.originDepth, stack.units)
	end
	return table.concat(parts, ",")
end

-- Depth-weighted mean origin of what is being carried, for the "mining deep or mining safe" question
-- the balance pass has to answer. Zero for an empty bag.
function CargoRules.averageOriginDepth(cargo: Types.RawWaxCargo): number
	if cargo.total <= 0 then
		return 0
	end
	local weighted = 0
	for _, stack in cargo.stacks do
		weighted += stack.originDepth * stack.units
	end
	return weighted / cargo.total
end

function CargoRules.newRun(): Types.RawWaxRun
	return {
		cargo = CargoRules.newCargo(),
		unitsAcquired = 0,
		unitsLost = 0,
		unitsExtracted = 0,
		unitsDropped = 0,
		extractionDepth = nil,
		extracted = false,
		extractionId = nil,
		currencyCredited = 0,
		partyBonusCredited = 0,
		acquiredByDepth = CargoRules.newCargo(),
	}
end

return CargoRules

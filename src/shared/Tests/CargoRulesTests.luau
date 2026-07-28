--!strict
-- PHASE 8. The cargo model's guarantees, asserted rather than assumed.
--
-- The two that matter most, and why they are worth this much test surface:
--
--   CONSERVATION — `split` and `merge` must not create or destroy a single unit. Every unit is
--   eventually currency, so a leak in one direction is inflation and a leak in the other is a player
--   losing a run they actually completed. Both are tested exhaustively over many bag shapes and
--   ratios rather than at a couple of convenient values, because apportionment bugs live in the
--   remainders and remainders only show up at awkward numbers.
--
--   THE CLOSED VERB SET — cargo must never gain a way to move directly between two living players,
--   or to become wax. Those are not bugs that would be caught by playing; they are design failures
--   that would look like features. The surface test fails the build if a sixth verb appears.

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local CargoRules = require(script.Parent.Parent.Logic.CargoRules)
local ExtractionConfig = require(script.Parent.Parent.Config.Extraction)

-- The complete, approved public surface. Adding a key here is a deliberate economic decision that
-- should be argued for in review — which is exactly why the list is spelled out rather than derived.
local APPROVED: { [string]: boolean } = {
	newCargo = true,
	grant = true,
	clear = true,
	split = true,
	merge = true,
	take = true,
	unitsPerDeposit = true,
	maxCargoUnits = true,
	formatOrigins = true,
	averageOriginDepth = true,
	newRun = true,
}

local function cargoOf(pairsList: { { number } }): Types.RawWaxCargo
	local cargo = CargoRules.newCargo()
	for _, entry in pairsList do
		cargo = (CargoRules.grant(cargo, entry[1], entry[2]))
	end
	return cargo
end

-- Sum of stack.units, recomputed independently of the maintained `total`. Every conservation check
-- uses this rather than trusting the field it is trying to validate.
local function sumStacks(cargo: Types.RawWaxCargo): number
	local sum = 0
	for _, stack in cargo.stacks do
		sum += stack.units
	end
	return sum
end

local function assertWellFormed(cargo: Types.RawWaxCargo, label: string)
	Harness.equal(sumStacks(cargo), cargo.total, label .. ": total disagrees with its stacks")
	local seen: { [number]: boolean } = {}
	local previousDepth = -math.huge
	for _, stack in cargo.stacks do
		Harness.expect(stack.units > 0, label .. ": a zero/negative stack survived")
		Harness.equal(stack.units % 1, 0, label .. ": a fractional stack survived")
		Harness.expect(not seen[stack.originDepth], label .. ": duplicate depth stack")
		seen[stack.originDepth] = true
		Harness.expect(stack.originDepth >= previousDepth, label .. ": stacks are not depth-ordered")
		previousDepth = stack.originDepth
	end
end

return {
	name = "CargoRules",
	tests = {
		Harness.test("exposes exactly the approved verbs, and nothing that moves cargo between players", function()
			local api: { [string]: unknown } = CargoRules :: any
			for key in api do
				Harness.expect(
					APPROVED[key] == true,
					string.format(
						"CargoRules.%s is not in the approved surface. Raw Wax must never gain a direct"
							.. " player-to-player transfer or a conversion to wax — the only path between"
							.. " two bags is a pile in the world with a single claim.",
						key
					)
				)
			end
			for key in APPROVED do
				Harness.expect(api[key] ~= nil, string.format("CargoRules.%s went missing", key))
			end
		end),

		Harness.test("grant merges by depth, orders ascending, and keeps total in step", function()
			local cargo = cargoOf({ { 9, 2 }, { 4, 3 }, { 9, 1 } })
			assertWellFormed(cargo, "granted")
			Harness.equal(#cargo.stacks, 2)
			Harness.equal(cargo.stacks[1].originDepth, 4)
			Harness.equal(cargo.stacks[2].originDepth, 9)
			Harness.equal(cargo.stacks[2].units, 3)
			Harness.equal(cargo.total, 6)
			Harness.equal(CargoRules.formatOrigins(cargo), "4x3,9x3")
		end),

		Harness.test("grant does not mutate the bag it was given", function()
			local original = cargoOf({ { 5, 2 } })
			local updated = (CargoRules.grant(original, 5, 2))
			Harness.equal(original.total, 2, "the source bag was mutated in place")
			Harness.equal(updated.total, 4)
		end),

		Harness.test("grant refuses every malformed amount and depth rather than repairing it", function()
			local base = CargoRules.newCargo()
			for _, units in { 0, -1, 1.5, 0 / 0, math.huge, -math.huge } do
				local cargo, added = CargoRules.grant(base, 5, units)
				Harness.equal(added, 0, string.format("units %s was accepted", tostring(units)))
				Harness.equal(cargo.total, 0)
			end
			for _, depth in { 0, -3, 2.5, 0 / 0, math.huge } do
				local cargo, added = CargoRules.grant(base, depth, 3)
				Harness.equal(added, 0, string.format("depth %s was accepted", tostring(depth)))
				Harness.equal(cargo.total, 0)
			end
		end),

		Harness.test("grant fills to the cap and then adds nothing", function()
			local cap = CargoRules.maxCargoUnits()
			local cargo = cargoOf({ { 3, cap - 1 } })
			local partial, addedPartial = CargoRules.grant(cargo, 4, 5)
			Harness.equal(addedPartial, 1, "the cap should allow exactly the remaining room")
			Harness.equal(partial.total, cap)
			local full, addedFull = CargoRules.grant(partial, 4, 5)
			Harness.equal(addedFull, 0)
			Harness.equal(full.total, cap)
		end),

		Harness.test("clear empties whatever it is handed and reports the size", function()
			local cargo = cargoOf({ { 7, 4 }, { 2, 1 } })
			local emptied, removed = CargoRules.clear(cargo)
			Harness.equal(removed, 5)
			Harness.equal(emptied.total, 0)
			Harness.equal(#emptied.stacks, 0)
			local again, removedAgain = CargoRules.clear(emptied)
			Harness.equal(removedAgain, 0, "clearing an empty bag must not invent units")
			Harness.equal(again.total, 0)
		end),

		Harness.test("split conserves every unit across many bag shapes and ratios", function()
			local shapes: { { { number } } } = {
				{ { 1, 3 } },
				{ { 1, 1 } },
				{ { 2, 3 }, { 5, 3 } },
				{ { 1, 3 }, { 4, 3 }, { 8, 3 }, { 12, 3 } },
				{ { 3, 7 }, { 9, 11 }, { 14, 1 } },
				{ { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 }, { 6, 1 }, { 7, 1 } },
			}
			for _, shape in shapes do
				local cargo = cargoOf(shape)
				for permille = 0, 1000, 37 do
					local taken, remainder = CargoRules.split(cargo, permille)
					assertWellFormed(taken, "split taken")
					assertWellFormed(remainder, "split remainder")
					Harness.equal(
						taken.total + remainder.total,
						cargo.total,
						string.format("split at %d permille leaked units", permille)
					)
					-- Never more than asked for: rounding is always downward.
					Harness.expect(
						taken.total <= math.floor(cargo.total * permille / 1000) or permille >= 1000,
						"split took more than the requested share"
					)
					-- No stack may exceed the stack it came from.
					for _, stack in taken.stacks do
						for _, source in cargo.stacks do
							if source.originDepth == stack.originDepth then
								Harness.expect(stack.units <= source.units, "split over-drew a stack")
							end
						end
					end
				end
			end
		end),

		Harness.test(
			"split at the configured death ratio takes roughly half the VALUE, not just the cheap half",
			function()
				-- The reason apportionment is proportional rather than deepest-first: taking the deepest
				-- units first would leave the party salvaging nearly all of the value, so dying would cost
				-- almost nothing. A mixed shallow/deep bag must lose real value.
				local cargo = cargoOf({ { 1, 6 }, { 12, 6 } })
				local dropped, shattered = CargoRules.split(cargo, ExtractionConfig.deathDropPermille)
				Harness.equal(dropped.total + shattered.total, 12)
				Harness.equal(dropped.total, 6)
				-- Both halves must contain deep units; a purely shallow drop would mean the split favoured
				-- one side by depth.
				local droppedDeep = 0
				for _, stack in dropped.stacks do
					if stack.originDepth == 12 then
						droppedDeep = stack.units
					end
				end
				Harness.equal(droppedDeep, 3, "the drop should mirror the bag's depth composition")
			end
		),

		Harness.test("split is deterministic and handles both extremes exactly", function()
			local cargo = cargoOf({ { 2, 5 }, { 7, 5 }, { 11, 3 } })
			local firstTaken, firstLeft = CargoRules.split(cargo, 500)
			local secondTaken, secondLeft = CargoRules.split(cargo, 500)
			Harness.equal(CargoRules.formatOrigins(firstTaken), CargoRules.formatOrigins(secondTaken))
			Harness.equal(CargoRules.formatOrigins(firstLeft), CargoRules.formatOrigins(secondLeft))

			local noneTaken, allLeft = CargoRules.split(cargo, 0)
			Harness.equal(noneTaken.total, 0)
			Harness.equal(allLeft.total, cargo.total)

			local allTaken, noneLeft = CargoRules.split(cargo, 1000)
			Harness.equal(allTaken.total, cargo.total)
			Harness.equal(noneLeft.total, 0)
		end),

		Harness.test("split refuses out-of-range ratios instead of extrapolating", function()
			local cargo = cargoOf({ { 4, 6 } })
			local overTaken, overLeft = CargoRules.split(cargo, 5000)
			Harness.equal(overTaken.total + overLeft.total, 6, "an over-range ratio leaked units")
			Harness.equal(overTaken.total, 6)
			local underTaken, underLeft = CargoRules.split(cargo, -500)
			Harness.equal(underTaken.total, 0)
			Harness.equal(underLeft.total, 6)
			local nanTaken, nanLeft = CargoRules.split(cargo, 0 / 0)
			Harness.equal(nanTaken.total, 0)
			Harness.equal(nanLeft.total, 6)
		end),

		Harness.test("split of an empty bag produces two empty bags", function()
			local taken, remainder = CargoRules.split(CargoRules.newCargo(), 500)
			Harness.equal(taken.total, 0)
			Harness.equal(remainder.total, 0)
		end),

		Harness.test("merge conserves units: what moves plus what is left equals what was offered", function()
			local holder = cargoOf({ { 3, 4 } })
			local pile = cargoOf({ { 3, 2 }, { 9, 5 } })
			local combined, leftover, moved = CargoRules.merge(holder, pile)
			assertWellFormed(combined, "merged")
			assertWellFormed(leftover, "leftover")
			Harness.equal(moved + leftover.total, pile.total, "merge leaked units")
			Harness.equal(combined.total, holder.total + moved)
			Harness.equal(leftover.total, 0, "there was room for all of it")
			Harness.equal(combined.total, 11)
		end),

		Harness.test("merge at the cap leaves the surplus on the ground rather than deleting it", function()
			local cap = CargoRules.maxCargoUnits()
			local holder = cargoOf({ { 2, cap - 3 } })
			local pile = cargoOf({ { 5, 4 }, { 14, 4 } })
			local combined, leftover, moved = CargoRules.merge(holder, pile)
			Harness.equal(moved, 3, "only the remaining room should move")
			Harness.equal(moved + leftover.total, pile.total, "the surplus was destroyed instead of left")
			Harness.equal(combined.total, cap)
			-- Deepest-first: a partial pickup should take the units worth having.
			local tookDeep = 0
			for _, stack in combined.stacks do
				if stack.originDepth == 14 then
					tookDeep = stack.units
				end
			end
			Harness.equal(tookDeep, 3, "a partial pickup should take the deepest units first")
		end),

		Harness.test("merging an empty pile changes nothing", function()
			local holder = cargoOf({ { 6, 3 } })
			local combined, leftover, moved = CargoRules.merge(holder, CargoRules.newCargo())
			Harness.equal(moved, 0)
			Harness.equal(leftover.total, 0)
			Harness.equal(combined.total, 3)
		end),

		Harness.test("take claims a pile whole and leaves nothing behind", function()
			local pile = cargoOf({ { 4, 2 }, { 10, 3 } })
			local claimed, remaining = CargoRules.take(pile)
			Harness.equal(claimed.total, 5)
			Harness.equal(remaining.total, 0)
			Harness.equal(#remaining.stacks, 0)
			Harness.equal(CargoRules.formatOrigins(claimed), "4x2,10x3")
		end),

		Harness.test("a split then merged bag round-trips to the original units", function()
			-- The realistic sequence: a player dies, half drops, a teammate picks the pile up. The
			-- units the teammate gains plus the units that shattered must equal what the dead player
			-- was carrying — no more, and no less.
			local carried = cargoOf({ { 2, 3 }, { 6, 3 }, { 11, 3 } })
			local dropped, shattered = CargoRules.split(carried, 500)
			local finder = CargoRules.newCargo()
			local afterPickup, leftover, moved = CargoRules.merge(finder, dropped)
			Harness.equal(leftover.total, 0)
			Harness.equal(moved + shattered.total, carried.total, "the death round-trip leaked units")
			Harness.equal(afterPickup.total, dropped.total)
		end),

		Harness.test("averageOriginDepth weights by units and is zero when empty", function()
			Harness.near(CargoRules.averageOriginDepth(cargoOf({ { 1, 3 } })), 1)
			Harness.near(CargoRules.averageOriginDepth(cargoOf({ { 18, 3 } })), 18)
			Harness.near(CargoRules.averageOriginDepth(cargoOf({ { 2, 1 }, { 10, 3 } })), 8)
			Harness.near(CargoRules.averageOriginDepth(CargoRules.newCargo()), 0)
		end),

		Harness.test("a fresh run reconciles to zero and carries no transaction", function()
			local run = CargoRules.newRun()
			Harness.equal(run.cargo.total, 0)
			Harness.equal(run.unitsAcquired, 0)
			Harness.equal(run.unitsLost, 0)
			Harness.equal(run.unitsDropped, 0)
			Harness.equal(run.unitsExtracted, 0)
			Harness.equal(run.currencyCredited, 0)
			Harness.equal(run.partyBonusCredited, 0)
			Harness.equal(run.extracted, false)
			Harness.isNil(run.extractionId)
			Harness.isNil(run.extractionDepth)
			Harness.equal(run.acquiredByDepth.total, 0)
		end),

		Harness.test("configured deposit yield and cap are sane whole numbers", function()
			Harness.equal(CargoRules.unitsPerDeposit(), ExtractionConfig.unitsPerDeposit)
			Harness.equal(CargoRules.unitsPerDeposit() % 1, 0)
			Harness.expect(CargoRules.unitsPerDeposit() > 0, "a break must be worth something")
			Harness.expect(
				CargoRules.maxCargoUnits() > CargoRules.unitsPerDeposit(),
				"the cap must leave room for more than one seam"
			)
		end),
	},
}

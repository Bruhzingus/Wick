--!strict
-- PHASE 8. What a bag is worth, and the properties the whole economy rests on.
--
-- These tests are deliberately split between MECHANICAL guarantees (everything is a non-negative
-- integer, for every input, including hostile ones) and ECONOMIC ones (deep wax genuinely dominates
-- shallow wax; you cannot raise your own payout by rearranging your bag). The second group is the
-- more valuable half: a rounding bug produces a wrong number, but a broken incentive produces a game
-- where the optimal way to play is the boring one.

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local CargoRules = require(script.Parent.Parent.Logic.CargoRules)
local ExtractionValue = require(script.Parent.Parent.Logic.ExtractionValue)
local ExtractionConfig = require(script.Parent.Parent.Config.Extraction)
local CaveTierConfig = require(script.Parent.Parent.Config.CaveTiers)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)

local function cargoOf(pairsList: { { number } }): Types.RawWaxCargo
	local cargo = CargoRules.newCargo()
	for _, entry in pairsList do
		cargo = (CargoRules.grant(cargo, entry[1], entry[2]))
	end
	return cargo
end

local function tierPermille(tierId: number): number
	for _, tier in CaveTierConfig do
		if tier.id == tierId then
			return tier.payoutPermille
		end
	end
	return 1000
end

return {
	name = "ExtractionValue",
	tests = {
		Harness.test("per-unit value matches the authored curve exactly", function()
			for depth, expected in ExtractionConfig.valuePerUnitByDepth do
				Harness.equal(
					ExtractionValue.valuePerUnit(depth),
					expected,
					string.format("depth %d should be worth %d", depth, expected)
				)
			end
		end),

		Harness.test("per-unit value is a whole number at every depth, authored or extrapolated", function()
			for depth = 1, 120 do
				local value = ExtractionValue.valuePerUnit(depth)
				Harness.equal(
					value % 1,
					0,
					string.format("depth %d produced the fractional value %s", depth, tostring(value))
				)
				Harness.expect(value >= 0, "value went negative")
				Harness.expect(value < math.huge, "value went infinite")
			end
		end),

		Harness.test("per-unit value never decreases with depth, and settles at the cap", function()
			local previous = 0
			for depth = 1, 120 do
				local value = ExtractionValue.valuePerUnit(depth)
				Harness.expect(
					value >= previous,
					string.format("depth %d (%d) is worth less than depth %d (%d)", depth, value, depth - 1, previous)
				)
				Harness.expect(value <= ExtractionConfig.maxValuePerUnit, "value escaped its ceiling")
				previous = value
			end
			Harness.equal(
				ExtractionValue.valuePerUnit(400),
				ExtractionConfig.maxValuePerUnit,
				"a deep enough floor should sit exactly at the cap"
			)
		end),

		Harness.test("an unsupported origin depth is worth nothing rather than something surprising", function()
			for _, depth in { 0, -1, -100, 1.5, 0 / 0, math.huge, -math.huge } do
				Harness.equal(
					ExtractionValue.valuePerUnit(depth),
					0,
					string.format("depth %s should price at zero", tostring(depth))
				)
			end
		end),

		Harness.test("base value is the plain sum of each stack at its own origin depth", function()
			local cargo = cargoOf({ { 1, 3 }, { 5, 3 }, { 8, 3 } })
			local expected = 3 * ExtractionValue.valuePerUnit(1)
				+ 3 * ExtractionValue.valuePerUnit(5)
				+ 3 * ExtractionValue.valuePerUnit(8)
			local value, units = ExtractionValue.baseValue(cargo)
			Harness.equal(value, expected)
			Harness.equal(units, 9)
		end),

		Harness.test("malformed stacks contribute nothing and cannot poison a payout", function()
			local hostile: Types.RawWaxCargo = {
				stacks = {
					{ originDepth = 5, units = 3 },
					{ originDepth = 5, units = -100 },
					{ originDepth = 5, units = 2.5 },
					{ originDepth = 5, units = 0 / 0 },
					{ originDepth = 5, units = math.huge },
					{ originDepth = 0, units = 50 },
					{ originDepth = 0 / 0, units = 50 },
				},
				total = 999999,
			}
			local value, units = ExtractionValue.baseValue(hostile)
			Harness.equal(units, 3, "only the one legitimate stack should count")
			Harness.equal(value, 3 * ExtractionValue.valuePerUnit(5))
		end),

		Harness.test("base value cannot price more units than the carry cap allows", function()
			local overfull: Types.RawWaxCargo = {
				stacks = {
					{ originDepth = 20, units = ExtractionConfig.maxCargoUnits },
					{ originDepth = 20, units = ExtractionConfig.maxCargoUnits },
				},
				total = ExtractionConfig.maxCargoUnits * 2,
			}
			local _, units = ExtractionValue.baseValue(overfull)
			Harness.equal(units, ExtractionConfig.maxCargoUnits, "a corrupted bag priced past the cap")
		end),

		Harness.test("every computed payout is a non-negative whole number, for hostile scalars too", function()
			local cargo = cargoOf({ { 3, 3 }, { 9, 3 } })
			for _, permille in { 0, 1, 999, 1000, 2500, 4500, -1000, 0 / 0, math.huge, 1234.567 } do
				for _, bonus in { true, false } do
					local breakdown = ExtractionValue.compute(cargo, permille, bonus)
					Harness.equal(
						breakdown.total % 1,
						0,
						string.format("permille %s produced a fractional payout", tostring(permille))
					)
					Harness.expect(breakdown.total >= 0, "payout went negative")
					Harness.expect(breakdown.total < math.huge, "payout went infinite")
				end
			end
		end),

		Harness.test("an empty bag pays exactly nothing, bonus or not", function()
			local empty = CargoRules.newCargo()
			Harness.equal(ExtractionValue.compute(empty, 4500, true).total, 0)
			Harness.equal(ExtractionValue.compute(empty, 4500, false).total, 0)
			Harness.equal(ExtractionValue.partyBonusDelta(empty, 4500), 0)
		end),

		Harness.test("fragmenting a bag across more stacks cannot raise its payout", function()
			-- The attack this defends against: if scaling were applied per stack, N stacks would mean
			-- N chances to round in the player's favour. Scaling the summed subtotal once means a bag
			-- is worth what it is worth however it happens to be arranged.
			local whole = cargoOf({ { 7, 12 } })
			local fragmented: Types.RawWaxCargo = {
				stacks = {
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
					{ originDepth = 7, units = 1 },
				},
				total = 12,
			}
			for _, permille in { 1000, 2500, 4500, 1333 } do
				Harness.equal(
					ExtractionValue.compute(fragmented, permille, false).total,
					ExtractionValue.compute(whole, permille, false).total,
					string.format("fragmentation changed the payout at %d permille", permille)
				)
			end
		end),

		Harness.test("a run signed under no contract pays exactly what it always did", function()
			-- THE regression this whole feature had to avoid. The contract scalar composes into the cave
			-- scalar rather than adding a third rounding step, so `cave x 1000 / 1000` must be bit-for-bit
			-- `cave` — on the bonused path too, which is the one with two floors in it.
			local bag = cargoOf({ { 4, 2 }, { 5, 2 }, { 6, 2 }, { 7, 4 }, { 8, 4 } })
			for _, permille in { 1000, 2500, 4500, 1333 } do
				for _, bonus in { false, true } do
					local legacy = ExtractionValue.compute(bag, permille, bonus)
					Harness.equal(
						ExtractionValue.compute(bag, permille, bonus, nil).total,
						legacy.total,
						string.format("nil contract changed the payout at %d permille", permille)
					)
					Harness.equal(
						ExtractionValue.compute(bag, permille, bonus, 1000).total,
						legacy.total,
						string.format("neutral contract changed the payout at %d permille", permille)
					)
					Harness.equal(legacy.contractPermille, 1000, "an unsigned run must report the neutral rate")
				end
			end
		end),

		Harness.test("a contract can only ever pay more, whatever it is handed", function()
			local bag = cargoOf({ { 7, 4 }, { 8, 4 } })
			local neutral = ExtractionValue.compute(bag, 2500, false, 1000).total
			for _, contract in LampConfig.contracts.rows do
				Harness.expect(
					ExtractionValue.compute(bag, 2500, false, contract.payoutPermille).total > neutral,
					contract.id .. " must pay more than signing nothing"
				)
			end
			-- A sub-neutral, negative or non-finite scalar is a bug upstream. It must never dock a
			-- player's earnings on the way through.
			for _, hostile in { 999, 500, 0, -9999, 0 / 0, -math.huge } do
				Harness.equal(
					ExtractionValue.compute(bag, 2500, false, hostile).total,
					neutral,
					"a scalar below neutral must be clamped, never applied: " .. tostring(hostile)
				)
			end
		end),

		Harness.test("contracts keep every payout a whole number, and the ceiling still binds", function()
			local bag = cargoOf({ { 6, 2 }, { 9, 4 }, { 12, 4 } })
			local rates = { 1000, LampConfig.wager.maximumPermille }
			for _, contract in LampConfig.contracts.rows do
				table.insert(rates, contract.payoutPermille)
			end
			for _, cavePermille in { 1000, 2500, 4500 } do
				for _, contractPermille in rates do
					for _, bonus in { false, true } do
						local result = ExtractionValue.compute(bag, cavePermille, bonus, contractPermille)
						Harness.expect(
							result.total >= 0 and result.total % 1 == 0,
							string.format(
								"cave %d x contract %d produced %s",
								cavePermille,
								contractPermille,
								tostring(result.total)
							)
						)
					end
				end
			end

			-- The worst combination the game can legitimately produce: deepest cave, biggest wager,
			-- party bonus, and a bag past the carry cap.
			local absurd: Types.RawWaxCargo = { stacks = { { originDepth = 15, units = 900 } }, total = 900 }
			local worst = ExtractionValue.compute(absurd, tierPermille(3), true, LampConfig.wager.maximumPermille)
			Harness.equal(worst.total, ExtractionConfig.maxSinglePayout, "the payout ceiling must still bind")
			Harness.expect(worst.capped, "a capped payout must say so")
		end),

		Harness.test("a contracted party bonus still splits into two credits that sum exactly", function()
			-- The base payout lands at the brazier and the bonus lands later, so the two must add up to
			-- one bonused extraction at the SAME rate — including the contract's. Paying the bonus at the
			-- plain cave rate would quietly underpay everyone who signed anything.
			local bag = cargoOf({ { 5, 2 }, { 8, 4 }, { 10, 2 } })
			local rates = { 1000 }
			for _, contract in LampConfig.contracts.rows do
				table.insert(rates, contract.payoutPermille)
			end
			for _, contractPermille in rates do
				local base = ExtractionValue.compute(bag, 4500, false, contractPermille).total
				local bonused = ExtractionValue.compute(bag, 4500, true, contractPermille).total
				local delta = ExtractionValue.partyBonusDelta(bag, 4500, contractPermille)
				Harness.equal(base + delta, bonused, "two credits must sum to one bonused extraction")
			end
		end),

		Harness.test("value is additive across bags, so merging or splitting cannot mint currency", function()
			local shallow = cargoOf({ { 2, 4 } })
			local deep = cargoOf({ { 11, 4 } })
			local both = cargoOf({ { 2, 4 }, { 11, 4 } })
			local shallowValue = ExtractionValue.baseValue(shallow)
			local deepValue = ExtractionValue.baseValue(deep)
			local bothValue = ExtractionValue.baseValue(both)
			Harness.equal(shallowValue + deepValue, bothValue)
		end),

		Harness.test(
			"the party bonus is paid as an exact difference, so two credits equal one bonused payout",
			function()
				-- The bonus arrives as a SECOND profile credit, after the base payout has already landed.
				-- If the two pieces did not sum to exactly the single-payment total, players would be able
				-- to prefer one path over the other.
				for _, shape in
					{
						{ { 1, 3 } },
						{ { 4, 3 }, { 9, 3 } },
						{ { 2, 7 }, { 13, 11 }, { 5, 1 } },
						{ { 15, 1 } },
					}
				do
					local cargo = cargoOf(shape)
					for _, permille in { 1000, 2500, 4500 } do
						local base = ExtractionValue.compute(cargo, permille, false).total
						local bonused = ExtractionValue.compute(cargo, permille, true).total
						local delta = ExtractionValue.partyBonusDelta(cargo, permille)
						Harness.equal(base + delta, bonused, "split payment disagrees with a single bonused payment")
						Harness.expect(delta >= 0, "the bonus must never reduce a payout")
					end
				end
			end
		),

		Harness.test("a single payout is bounded no matter how the multipliers stack", function()
			local absurd: Types.RawWaxCargo = {
				stacks = { { originDepth = 500, units = ExtractionConfig.maxCargoUnits } },
				total = ExtractionConfig.maxCargoUnits,
			}
			local breakdown = ExtractionValue.compute(absurd, 1000000, true)
			Harness.equal(breakdown.total, ExtractionConfig.maxSinglePayout)
			Harness.equal(breakdown.capped, true)
		end),

		Harness.test("the party bonus needs a real party and no deaths", function()
			Harness.equal(ExtractionValue.partyBonusApplies(1, false), false, "solo runs must not earn it")
			Harness.equal(ExtractionValue.partyBonusApplies(2, false), true)
			Harness.equal(ExtractionValue.partyBonusApplies(4, false), true)
			Harness.equal(ExtractionValue.partyBonusApplies(4, true), false, "a death cancels it for everyone")
			Harness.equal(ExtractionValue.partyBonusApplies(0, false), false)
			Harness.equal(ExtractionValue.partyBonusApplies(-1, false), false)
			Harness.equal(ExtractionValue.partyBonusApplies(0 / 0, false), false)
		end),

		Harness.test("deep wax genuinely dominates shallow wax", function()
			-- The design claim the whole descent rests on: no realistic amount of safe shallow mining
			-- is worth one good deep seam. Three units from floor 8 must beat nine units farmed across
			-- floors 1-3 — otherwise the optimal play is to never leave the entrance.
			local shallowFarm = cargoOf({ { 1, 3 }, { 2, 3 }, { 3, 3 } })
			local oneDeepSeam = cargoOf({ { 8, 3 } })
			local farmValue = ExtractionValue.baseValue(shallowFarm)
			local deepValue = ExtractionValue.baseValue(oneDeepSeam)
			Harness.expect(
				deepValue > farmValue,
				string.format("one floor-8 seam (%d) should beat three shallow seams (%d)", deepValue, farmValue)
			)
		end),

		Harness.test("shallow-farm-then-deep-rush loses badly to mining at depth", function()
			-- THE dominant-strategy check this pricing model exists to pass. Both players mine exactly
			-- three seams and both extract at floor 10; the only difference is WHERE they spent their
			-- swings. Because a unit is priced by the floor it came out of and never by where it was
			-- cashed in, the shallow farmer's cargo is dead weight they carried past every threat on
			-- the way down for no gain at all.
			local farmedShallowThenRushed = cargoOf({ { 1, 3 }, { 2, 3 }, { 3, 3 } })
			local minedOnTheWayDown = cargoOf({ { 8, 3 }, { 9, 3 }, { 10, 3 } })
			local farmed = ExtractionValue.baseValue(farmedShallowThenRushed)
			local mined = ExtractionValue.baseValue(minedOnTheWayDown)
			Harness.expect(
				mined > farmed * 3,
				string.format(
					"three deep seams (%d) should overwhelmingly beat three shallow ones (%d);"
						.. " if this narrows, shallow farming becomes viable again",
					mined,
					farmed
				)
			)
		end),

		Harness.test("the authored balance targets still hold", function()
			-- These are the numbers every fee and price in Config/CaveTiers was derived from. If a
			-- curve edit moves them, the economy's pacing has silently changed and the fees need
			-- revisiting — so this test is a tripwire on the tuning, not on the code.
			local averageRun = cargoOf({ { 2, 3 }, { 3, 3 }, { 5, 3 } })
			local shallowsPayout = ExtractionValue.compute(averageRun, tierPermille(1), false).total
			Harness.equal(shallowsPayout, 144, "an average Shallows run should pay about 145")

			local descentFee = 350
			Harness.expect(
				shallowsPayout * 2 < descentFee and shallowsPayout * 3 > descentFee,
				"two-to-three average free runs should buy one Descent admission"
			)

			-- An average paid run roughly repays its fee; the profit is meant to live past floor 8.
			local descentAverage = ExtractionValue.compute(averageRun, tierPermille(2), false).total
			Harness.expect(
				descentAverage >= descentFee and descentAverage < descentFee * 1.2,
				string.format(
					"an average Descent run (%d) should roughly break even against %d",
					descentAverage,
					descentFee
				)
			)

			local deepRun = cargoOf({ { 2, 3 }, { 3, 3 }, { 5, 3 }, { 6, 3 }, { 8, 3 } })
			local descentDeep = ExtractionValue.compute(deepRun, tierPermille(2), false).total
			Harness.expect(
				descentDeep > descentFee * 2,
				string.format("a floor-8 Descent run (%d) should clearly profit against %d", descentDeep, descentFee)
			)
		end),
	},
}

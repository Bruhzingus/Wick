--!strict
-- What a signed contract does to a run, and the one property that makes contracts legal inside a
-- track that forbids upgrades: EVERY ROW MUST COST THE PLAYER SOMETHING.
--
-- A contract pays more than an unsigned run by design. If a row's rule ever stops being enforced —
-- or is authored with a neutral effect by mistake — that extra payout becomes free money, and the
-- Lamp Network has quietly shipped the pure-power upgrade it exists to refuse. Most of this file is
-- there to make that specific mistake impossible to commit.

local Harness = require(script.Parent.Harness)
local Types = require(script.Parent.Parent.Types)
local CargoRules = require(script.Parent.Parent.Logic.CargoRules)
local ContractRules = require(script.Parent.Parent.Logic.ContractRules)
local ExtractionValue = require(script.Parent.Parent.Logic.ExtractionValue)
local LampConfig = require(script.Parent.Parent.Config.LampNetwork)
local WaxConfig = require(script.Parent.Parent.Config.Wax)

local function cargoOf(pairsList: { { number } }): Types.RawWaxCargo
	local cargo = CargoRules.newCargo()
	for _, entry in pairsList do
		cargo = (CargoRules.grant(cargo, entry[1], entry[2]))
	end
	return cargo
end

local suite: Harness.Suite = {
	name = "ContractRules",
	tests = {
		Harness.test("every contract actually costs the player something", function()
			-- THE test this file exists for. A row whose effect is neutral pays extra for nothing, which
			-- is the pure-power upgrade the whole track forbids — and it would arrive not as a designed
			-- decision but as a field somebody forgot to fill in.
			if not LampConfig.contracts.enabled then
				return
			end
			for _, contract in LampConfig.contracts.rows do
				local effect = ContractRules.effectFor(contract.id)
				local costs = #effect.lostTools > 0
					or effect.startingWaxMultiplier < 1
					or effect.maxWaxMultiplier < 1
					or effect.sealsBasin
					or effect.minimumPayingDepth > 0
					or effect.tetherStuds > 0
					or effect.voidsOnPartyDeath
				Harness.expect(
					costs,
					contract.id .. " pays above the neutral rate but takes nothing away — that is free money"
				)
			end
		end),

		Harness.test("no contract can make a run easier, whatever the config says", function()
			-- The clamp is in ContractRules rather than trusted to review, because a contract row is the
			-- only place a designer writes a number that scales a candle and 0.6 versus 1.6 is one
			-- keystroke.
			for _, contract in LampConfig.contracts.rows do
				local effect = ContractRules.effectFor(contract.id)
				Harness.expect(effect.startingWaxMultiplier <= 1, contract.id .. " must not raise starting wax")
				Harness.expect(effect.maxWaxMultiplier <= 1, contract.id .. " must not raise maximum wax")
			end
			-- Even a hostile row cannot buff: the sanitiser clamps rather than trusting the table.
			local neutral = ContractRules.neutral()
			Harness.equal(neutral.startingWaxMultiplier, 1)
			Harness.equal(neutral.maxWaxMultiplier, 1)
		end),

		Harness.test("an unknown, absent or rolled-back contract resolves to neutral", function()
			-- A run must always be playable whatever state the config or the profile is in.
			for _, id in { nil, "contract.nope", "" } do
				local effect = ContractRules.effectFor(id)
				Harness.equal(#effect.lostTools, 0)
				Harness.equal(effect.startingWaxMultiplier, 1)
				Harness.equal(effect.maxWaxMultiplier, 1)
				Harness.equal(effect.sealsBasin, false)
				Harness.equal(effect.minimumPayingDepth, 0)
				Harness.equal(effect.tetherStuds, 0)
				Harness.equal(effect.voidsOnPartyDeath, false)
			end
		end),

		Harness.test("a candle never starts above its own tank", function()
			-- Hollow Wick shrinks the maximum; Short Wick lowers the start. Applied together — or to a
			-- future row that does both — the start must still be clamped, or a candle would begin over
			-- its own ceiling and the wax bar would read past full.
			for _, contract in LampConfig.contracts.rows do
				local effect = ContractRules.effectFor(contract.id)
				local starting, maxWax = ContractRules.waxFor(effect, WaxConfig.startingWax, WaxConfig.maxWax)
				Harness.expect(starting <= maxWax, contract.id .. " starts a candle above its own maximum")
				Harness.expect(starting > 0 and maxWax > 0, contract.id .. " must leave a candle lightable")
				Harness.expect(maxWax <= WaxConfig.maxWax, contract.id .. " must not enlarge the tank")
			end
		end),

		Harness.test("tool removal rides the Basin's own lost-tool set", function()
			-- Reusing `SacrificeModifiers.lostTools` is what keeps Logic/ToolRules free of any
			-- contract-specific branch, and what makes a contract and a sacrifice that remove the same
			-- tool agree instead of one overwriting the other.
			local lost: { [string]: boolean } = {}
			ContractRules.applyLostTools(ContractRules.effectFor("contract.unlit"), lost)
			Harness.equal(lost.Flare, true, "Unlit must remove Flare")
			Harness.equal(lost.Cup, nil, "Unlit must leave Cup alone")

			ContractRules.applyLostTools(ContractRules.effectFor("contract.naked_flame"), lost)
			Harness.equal(lost.Cup, true, "Naked Flame must remove Cup")
			-- Merged, not replaced: the earlier removal survives.
			Harness.equal(lost.Flare, true, "applying a second effect must not restore a lost tool")
			Harness.equal(lost.Decoy, nil, "neither row may touch Decoy")
		end),

		Harness.test("a tether breaks only after its grace period, and only if it exists", function()
			local tethered = ContractRules.effectFor("contract.tethered")
			Harness.expect(tethered.tetherStuds > 0, "the tethered row must actually set a tether")
			Harness.equal(
				ContractRules.tetherIsBroken(tethered, tethered.tetherGraceSeconds),
				false,
				"the grace boundary itself must not break the contract"
			)
			Harness.equal(ContractRules.tetherIsBroken(tethered, tethered.tetherGraceSeconds + 0.01), true)
			-- A contract with no tether can never be broken by separation, however far anyone wanders.
			Harness.equal(ContractRules.tetherIsBroken(ContractRules.effectFor("contract.unlit"), 9999), false)
			Harness.equal(ContractRules.tetherIsBroken(tethered, 0 / 0), false, "NaN must not break a contract")
		end),

		Harness.test("The Long Descent zeroes shallow units but still counts them", function()
			-- The tally and the payout answer different questions. A player who mined ten units and was
			-- paid for four really did carry ten out, and a results card that says four is a bug report.
			local effect = ContractRules.effectFor("contract.long_descent")
			local floorDepth = effect.minimumPayingDepth
			Harness.expect(floorDepth > 0, "The Long Descent must set a depth floor")
			Harness.equal(ContractRules.depthPays(effect, floorDepth - 1), false)
			Harness.equal(ContractRules.depthPays(effect, floorDepth), true)

			local bag = cargoOf({ { 2, 6 }, { 8, 4 } })
			local fullValue, fullUnits = ExtractionValue.baseValue(bag)
			local gatedValue, gatedUnits = ExtractionValue.baseValue(bag, floorDepth)
			Harness.equal(gatedUnits, fullUnits, "disqualified units must still be counted")
			Harness.expect(gatedValue < fullValue, "disqualified units must be worth less")
			Harness.equal(gatedValue, 4 * ExtractionValue.valuePerUnit(8), "only the deep stack may pay")
		end),

		Harness.test("a corrupt origin depth is still skipped entirely, contract or not", function()
			-- The pre-existing guard must survive the new one: an unreadable provenance is not a unit
			-- anybody can audit, so it is neither counted nor priced.
			local hostile: Types.RawWaxCargo = {
				stacks = { { originDepth = 0, units = 5 }, { originDepth = 8, units = 2 } },
				total = 7,
			}
			local _, units = ExtractionValue.baseValue(hostile, 6)
			Harness.equal(units, 2, "an unsupported origin depth must not be counted")
		end),

		Harness.test("The Long Descent is a real bet — it loses shallow and wins deep", function()
			-- If this ever passes in only one direction the row has stopped being a gamble and become
			-- either a trap or a freebie.
			local rate: number? = nil
			for _, contract in LampConfig.contracts.rows do
				if contract.id == "contract.long_descent" then
					rate = contract.payoutPermille
				end
			end
			Harness.expect(rate ~= nil, "the long descent row must exist")
			local floorDepth = ContractRules.effectFor("contract.long_descent").minimumPayingDepth

			local bailedEarly = cargoOf({ { 3, 4 }, { 5, 4 } })
			Harness.expect(
				ExtractionValue.compute(bailedEarly, 2500, false, rate, floorDepth).total
					< ExtractionValue.compute(bailedEarly, 2500, false).total,
				"turning back shallow under The Long Descent must lose money"
			)

			local wentDeep = cargoOf({ { 7, 4 }, { 9, 6 } })
			Harness.expect(
				ExtractionValue.compute(wentDeep, 2500, false, rate, floorDepth).total
					> ExtractionValue.compute(wentDeep, 2500, false).total,
				"going deep under The Long Descent must win money"
			)
		end),

		Harness.test("every contract's payout stays a whole number at every cave rate", function()
			local bag = cargoOf({ { 6, 2 }, { 9, 4 }, { 12, 4 } })
			for _, contract in LampConfig.contracts.rows do
				local effect = ContractRules.effectFor(contract.id)
				local depth = if effect.minimumPayingDepth > 0 then effect.minimumPayingDepth else nil
				for _, cavePermille in { 1000, 2500, 4500 } do
					for _, bonus in { false, true } do
						local total =
							ExtractionValue.compute(bag, cavePermille, bonus, contract.payoutPermille, depth).total
						Harness.expect(
							total >= 0 and total % 1 == 0,
							string.format("%s at cave %d produced %s", contract.id, cavePermille, tostring(total))
						)
					end
				end
			end
		end),
	},
}

return suite
